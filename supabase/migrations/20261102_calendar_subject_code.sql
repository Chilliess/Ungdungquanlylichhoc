-- Fix creating a new subject when subjects.subject_code is NOT NULL.
-- Existing subjects and schedules are not modified by running this file.
BEGIN;
CREATE OR REPLACE FUNCTION public.save_calendar_lesson(
  p_title text, p_date date, p_start time, p_end time, p_room text,
  p_notes text DEFAULT '', p_category text DEFAULT '',
  p_id uuid DEFAULT NULL, p_is_exam boolean DEFAULT false,
  p_occurrence_date date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  owner_id uuid := auth.uid();
  subject_uuid uuid;
  result_id uuid;
  old_schedule public.schedules%ROWTYPE;
  date_shift integer;
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập để lưu lịch'; END IF;
  IF p_title IS NULL OR btrim(p_title) = '' OR p_room IS NULL OR btrim(p_room) = ''
     OR p_date IS NULL OR p_start IS NULL OR p_end IS NULL THEN
    RAISE EXCEPTION 'Vui lòng nhập đủ tên môn, ngày, giờ và địa điểm';
  END IF;
  IF p_end <= p_start THEN RAISE EXCEPTION 'Giờ kết thúc phải sau giờ bắt đầu'; END IF;
  IF p_date < DATE '2020-01-01' OR p_date > DATE '2100-12-31' THEN
    RAISE EXCEPTION 'Ngày học ngoài phạm vi cho phép';
  END IF;
  IF length(coalesce(p_category, '')) > 60 THEN RAISE EXCEPTION 'Nhãn tối đa 60 ký tự'; END IF;
  IF p_id IS NOT NULL THEN
    IF p_is_exam THEN
      PERFORM id FROM public.schedule_exams WHERE id = p_id AND user_id = owner_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy lịch kiểm tra'; END IF;
    ELSE
      SELECT * INTO old_schedule FROM public.schedules
        WHERE id = p_id AND user_id = owner_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy lịch học'; END IF;
    END IF;
  END IF;
  SELECT id INTO subject_uuid FROM public.subjects
    WHERE user_id = owner_id AND lower(btrim(subject_name)) = lower(btrim(p_title))
    ORDER BY created_at, id LIMIT 1;
  IF subject_uuid IS NULL THEN
    -- Reuse the UUID for a non-empty, globally unique automatic subject code.
    subject_uuid := gen_random_uuid();
    INSERT INTO public.subjects(id, user_id, subject_code, subject_name, color_code)
      VALUES(subject_uuid, owner_id, 'AUTO-' || replace(subject_uuid::text, '-', ''),
        btrim(p_title), '#6750A4');
  END IF;
  IF p_is_exam THEN
    IF p_id IS NULL THEN RAISE EXCEPTION 'Chỉ tạo lịch học tại đây'; END IF;
    UPDATE public.schedule_exams SET subject_id = subject_uuid, exam_date = p_date,
      start_time = p_start, end_time = p_end, room = btrim(p_room),
      notes = btrim(coalesce(p_notes, '')), category = btrim(coalesce(p_category, ''))
      WHERE id = p_id AND user_id = owner_id RETURNING id INTO result_id;
  ELSIF p_id IS NULL THEN
    INSERT INTO public.schedules(user_id, subject_id, room, day_of_week,
      start_time, end_time, start_date, end_date, notes, category)
      VALUES(owner_id, subject_uuid, btrim(p_room), ARRAY[extract(isodow FROM p_date)::integer + 1],
      p_start, p_end, p_date, p_date, btrim(coalesce(p_notes, '')), btrim(coalesce(p_category, '')))
      RETURNING id INTO result_id;
  ELSE
    date_shift := p_date - coalesce(p_occurrence_date, old_schedule.start_date, p_date);
    IF coalesce(old_schedule.start_date, p_date) + date_shift < DATE '2020-01-01'
       OR coalesce(old_schedule.end_date, p_date) + date_shift > DATE '2100-12-31' THEN
      RAISE EXCEPTION 'Chuỗi lịch vượt quá phạm vi ngày cho phép';
    END IF;
    UPDATE public.schedules SET subject_id = subject_uuid, room = btrim(p_room),
      start_time = p_start, end_time = p_end,
      start_date = coalesce(old_schedule.start_date, p_date) + date_shift,
      end_date = coalesce(old_schedule.end_date, p_date) + date_shift,
      day_of_week = ARRAY(SELECT (((day - 2 + date_shift) % 7 + 7) % 7) + 2
        FROM unnest(coalesce(old_schedule.day_of_week,
          ARRAY[extract(isodow FROM coalesce(p_occurrence_date, p_date))::integer + 1])) AS day),
      notes = btrim(coalesce(p_notes, '')), category = btrim(coalesce(p_category, ''))
      WHERE id = p_id AND user_id = owner_id RETURNING id INTO result_id;
  END IF;
  RETURN result_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_calendar_lesson(text,date,time,time,text,text,text,uuid,boolean,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_calendar_lesson(text,date,time,time,text,text,text,uuid,boolean,date) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
