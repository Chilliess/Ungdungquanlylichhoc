-- Shared grouped editor: calendar and subject management use save_subject_schedule.
-- Safe to rerun after the calendar/label migrations. Existing rows retain their dates and rules.
BEGIN;
ALTER TABLE public.schedules ADD COLUMN IF NOT EXISTS recurrence text
  CHECK (recurrence IN ('none','daily','weekly','monthly','yearly'));

CREATE OR REPLACE FUNCTION public.save_subject_schedule(
  p_subject_id uuid, p_schedule_id uuid, p_title text, p_date date,
  p_start time, p_end time, p_room text, p_notes text DEFAULT '',
  p_category text DEFAULT '', p_recurrence text DEFAULT 'none', p_until date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  owner_id uuid := auth.uid();
  subject_uuid uuid := p_subject_id;
  result_id uuid;
  old_row public.schedules%ROWTYPE;
  days integer[];
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập'; END IF;
  IF nullif(btrim(p_title),'') IS NULL OR nullif(btrim(p_room),'') IS NULL
     OR p_date IS NULL OR p_start IS NULL OR p_end IS NULL OR p_end <= p_start THEN
    RAISE EXCEPTION 'Nhập đủ tên môn, ngày, phòng và giờ kết thúc sau giờ bắt đầu';
  END IF;
  IF p_recurrence IS NULL OR p_recurrence NOT IN ('none','daily','weekly','monthly','yearly') THEN
    RAISE EXCEPTION 'Chu kỳ lặp không hợp lệ';
  END IF;
  IF p_date < DATE '2020-01-01' OR p_date > DATE '2100-12-31'
     OR p_until < p_date OR p_until > DATE '2100-12-31' THEN
    RAISE EXCEPTION 'Khoảng ngày không hợp lệ';
  END IF;
  IF length(coalesce(p_category,'')) > 60 THEN RAISE EXCEPTION 'Nhãn tối đa 60 ký tự'; END IF;
  IF subject_uuid IS NOT NULL THEN
    PERFORM id FROM public.subjects WHERE id = subject_uuid AND user_id = owner_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy môn học'; END IF;
  ELSE
    SELECT id INTO subject_uuid FROM public.subjects WHERE user_id = owner_id
      AND lower(btrim(subject_name)) = lower(btrim(p_title)) ORDER BY created_at,id LIMIT 1;
    IF subject_uuid IS NULL THEN
    subject_uuid := gen_random_uuid();
    INSERT INTO public.subjects(id,user_id,subject_code,subject_name,color_code)
      VALUES(subject_uuid,owner_id,'AUTO-' || replace(subject_uuid::text,'-',''),btrim(p_title),'#6750A4');
    END IF;
  END IF;
  days := ARRAY[extract(isodow FROM p_date)::integer + 1];
  IF p_schedule_id IS NOT NULL THEN
    SELECT * INTO old_row FROM public.schedules
      WHERE id = p_schedule_id AND subject_id = subject_uuid AND user_id = owner_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy lịch học'; END IF;
    -- Keep all weekdays of legacy schedules when shifting the start date.
    IF p_recurrence = 'weekly' AND coalesce(old_row.recurrence,'weekly') = 'weekly'
       AND cardinality(old_row.day_of_week) > 0 THEN
      days := ARRAY(SELECT (((d - 2 + (p_date - coalesce(old_row.start_date,p_date))) % 7 + 7) % 7) + 2
        FROM unnest(old_row.day_of_week) d);
    END IF;
  END IF;
  UPDATE public.subjects SET subject_name = btrim(p_title) WHERE id = subject_uuid AND user_id = owner_id;
  IF p_schedule_id IS NULL THEN
    INSERT INTO public.schedules(user_id,subject_id,room,day_of_week,start_time,end_time,start_date,end_date,notes,category,recurrence)
    VALUES(owner_id,subject_uuid,btrim(p_room),days,p_start,p_end,p_date,
      CASE WHEN p_recurrence = 'none' THEN p_date ELSE p_until END,
      btrim(coalesce(p_notes,'')),btrim(coalesce(p_category,'')),p_recurrence) RETURNING id INTO result_id;
  ELSE
    UPDATE public.schedules SET room = btrim(p_room), day_of_week = days,
      start_time = p_start, end_time = p_end, start_date = p_date,
      end_date = CASE WHEN p_recurrence = 'none' THEN p_date ELSE p_until END,
      notes = btrim(coalesce(p_notes,'')), category = btrim(coalesce(p_category,'')), recurrence = p_recurrence
      WHERE id = p_schedule_id AND user_id = owner_id RETURNING id INTO result_id;
  END IF;
  RETURN result_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_subject_schedule(uuid,uuid,text,date,time,time,text,text,text,text,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_subject_schedule(uuid,uuid,text,date,time,time,text,text,text,text,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_calendar_subject(p_subject_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE owner_id uuid := auth.uid();
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập'; END IF;
  PERFORM id FROM public.subjects WHERE id = p_subject_id AND user_id = owner_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy môn học'; END IF;
  DELETE FROM public.reminders WHERE user_id = owner_id AND (
    (schedule_type = 'schedule' AND schedule_id IN (SELECT id FROM public.schedules WHERE subject_id = p_subject_id AND user_id = owner_id)) OR
    (schedule_type = 'exam' AND schedule_id IN (SELECT id FROM public.schedule_exams WHERE subject_id = p_subject_id AND user_id = owner_id)));
  DELETE FROM public.schedule_exams WHERE subject_id = p_subject_id AND user_id = owner_id;
  DELETE FROM public.schedules WHERE subject_id = p_subject_id AND user_id = owner_id;
  DELETE FROM public.subjects WHERE id = p_subject_id AND user_id = owner_id;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_calendar_subject(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_calendar_subject(uuid) TO authenticated;
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
  IF p_id IS NOT NULL THEN
    IF p_is_exam THEN
      SELECT subject_id INTO subject_uuid FROM public.schedule_exams WHERE id = p_id AND user_id = owner_id;
    ELSE
      subject_uuid := old_schedule.subject_id;
    END IF;
    UPDATE public.subjects SET subject_name = btrim(p_title) WHERE id = subject_uuid AND user_id = owner_id;
  ELSE
    SELECT id INTO subject_uuid FROM public.subjects
      WHERE user_id = owner_id AND lower(btrim(subject_name)) = lower(btrim(p_title))
      ORDER BY created_at, id LIMIT 1;
  END IF;
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
      end_date = old_schedule.end_date + date_shift,
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
