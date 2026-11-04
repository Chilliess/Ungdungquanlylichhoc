-- ==========================================
-- 1. TẠO BẢNG PROFILES (Quản lý thông tin người dùng)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==========================================
-- 2. TẠO BẢNG SUBJECTS (Quản lý môn học)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    subject_code TEXT,
    subject_name TEXT NOT NULL,
    credits INT4,
    color_code TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==========================================
-- 3. TẠO BẢNG SCHEDULES (Quản lý thời khóa biểu / lịch học)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    subject_id UUID REFERENCES public.subjects(id) ON DELETE CASCADE NOT NULL,
    room TEXT,
    lecturer TEXT,
    day_of_week _int4, -- Mảng chứa các ngày trong tuần (ví dụ: [1, 3, 5])
    start_time TIME,
    end_time TIME,
    periods_count INT4,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==========================================
-- 4. TẠO BẢNG REMINDERS (Quản lý thiết lập thông báo)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    schedule_id UUID NOT NULL,                        -- Không còn khóa ngoại cứng REFERENCES public.schedules(id) để chứa được cả id của lịch kiểm tra
    schedule_type TEXT DEFAULT 'schedule' NOT NULL,   -- Phân loại: 'schedule' (lịch học) hoặc 'exam' (lịch kiểm tra)
    remind_before_minutes INT4,
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Bật bảo mật RLS
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

-- Tạo lại Policy bảo mật
DROP POLICY IF EXISTS "Enable all for users based on user_id on reminders" ON public.reminders;
CREATE POLICY "Enable all for users based on user_id on reminders"
ON public.reminders FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ==========================================
-- 5. BẬT BẢO MẬT HÀNG (Row Level Security - RLS) CHO TẤT CẢ CÁC BẢNG
-- ==========================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 6. THIẾT LẬP CHÍNH SÁCH QUYỀN (POLICIES) AN TOÀN
-- ==========================================

-- --- POLICIES CHO PROFILES ---
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Enable read for authenticated users" ON public.profiles;

CREATE POLICY "Enable insert for users based on user_id" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Enable update for users based on user_id" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "Enable read for authenticated users" ON public.profiles FOR SELECT USING (auth.role() = 'authenticated');


-- --- POLICIES CHO SUBJECTS ---
DROP POLICY IF EXISTS "Enable all for users based on user_id on subjects" ON public.subjects;

CREATE POLICY "Enable all for users based on user_id on subjects"
ON public.subjects FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);


-- --- POLICIES CHO SCHEDULES ---
DROP POLICY IF EXISTS "Enable all for users based on user_id on schedules" ON public.schedules;

CREATE POLICY "Enable all for users based on user_id on schedules"
ON public.schedules FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);


-- --- POLICIES CHO REMINDERS ---
DROP POLICY IF EXISTS "Enable all for users based on user_id on reminders" ON public.reminders;

CREATE POLICY "Enable all for users based on user_id on reminders"
ON public.reminders FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Tạo bảng schedule_exams chuyên biệt cho lịch kiểm tra / thi cử
CREATE TABLE IF NOT EXISTS public.schedule_exams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    subject_id UUID REFERENCES public.subjects(id) ON DELETE CASCADE NOT NULL,
    room TEXT,
    supervisor TEXT,                  -- Tên giảng viên coi thi / giám thị
    exam_date DATE NOT NULL,          -- Ngày thi cụ thể
    start_time TIME NOT NULL,         -- Giờ bắt đầu
    end_time TIME NOT NULL,           -- Giờ kết thúc
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Bật bảo mật RLS
ALTER TABLE public.schedule_exams ENABLE ROW LEVEL SECURITY;

-- Thiết lập Policy quyền cho phép user tự quản lý lịch thi của chính họ
DROP POLICY IF EXISTS "Enable all for users based on user_id on schedule_exams" ON public.schedule_exams;

CREATE POLICY "Enable all for users based on user_id on schedule_exams"
ON public.schedule_exams FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ==========================================
-- 7. LƯU LỊCH TỪ MÀN HÌNH LỊCH HỌC
-- Calendar editor setup (20261102).
-- ==========================================
-- Run once in the Supabase SQL Editor. Existing rows and RLS policies are retained.
BEGIN;
ALTER TABLE public.schedules ADD COLUMN IF NOT EXISTS notes text NOT NULL DEFAULT '';
ALTER TABLE public.schedules ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT '';
ALTER TABLE public.schedule_exams ADD COLUMN IF NOT EXISTS notes text NOT NULL DEFAULT '';
ALTER TABLE public.schedule_exams ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT '';

-- One transaction resolves the subject and writes the event. No orphan subject on failure.
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

-- ==========================================
-- 8. DANH SÁCH THẺ PHÂN LOẠI THEO TÀI KHOẢN
-- Calendar categories setup (20261102).
-- ==========================================
-- Run after 20261102_calendar_editor.sql.
BEGIN;
CREATE TABLE IF NOT EXISTS public.calendar_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 60)
);
CREATE UNIQUE INDEX IF NOT EXISTS calendar_categories_owner_name
  ON public.calendar_categories(user_id, lower(btrim(name)));
ALTER TABLE public.calendar_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Own calendar categories" ON public.calendar_categories;
CREATE POLICY "Own calendar categories" ON public.calendar_categories FOR ALL
  USING(auth.uid() = user_id) WITH CHECK(auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.calendar_categories TO authenticated;
INSERT INTO public.calendar_categories(user_id, name)
  SELECT user_id, btrim(category) FROM public.schedules WHERE btrim(category) <> ''
  UNION SELECT user_id, btrim(category) FROM public.schedule_exams WHERE btrim(category) <> ''
  ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.manage_calendar_category(
  p_action text, p_name text, p_new_name text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  owner_id uuid := auth.uid();
  actual_name text;
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập'; END IF;
  IF length(btrim(coalesce(p_name, ''))) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
  END IF;
  IF p_action = 'create' THEN
    INSERT INTO public.calendar_categories(user_id, name) VALUES(owner_id, btrim(p_name));
    RETURN;
  END IF;
  SELECT name INTO actual_name FROM public.calendar_categories
    WHERE user_id = owner_id AND lower(name) = lower(btrim(p_name)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy nhãn'; END IF;
  IF p_action = 'rename' THEN
    IF length(btrim(coalesce(p_new_name, ''))) NOT BETWEEN 1 AND 60 THEN
      RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
    END IF;
    UPDATE public.calendar_categories SET name = btrim(p_new_name)
      WHERE user_id = owner_id AND name = actual_name;
    UPDATE public.schedules SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
  ELSIF p_action = 'delete' THEN
    UPDATE public.schedules SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    DELETE FROM public.calendar_categories WHERE user_id = owner_id AND name = actual_name;
  ELSE
    RAISE EXCEPTION 'Thao tác không hợp lệ';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.manage_calendar_category(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.manage_calendar_category(text,text,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ==========================================
-- 9. MAU CHO THE PHAN LOAI
-- ==========================================
-- Run after 20261102_calendar_categories.sql. Existing names and schedules are retained.
BEGIN;
ALTER TABLE public.calendar_categories ADD COLUMN IF NOT EXISTS color_code text NOT NULL DEFAULT '#E53935';
CREATE OR REPLACE FUNCTION public.manage_calendar_category_color(
  p_action text, p_name text, p_new_name text DEFAULT NULL, p_color_code text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  owner_id uuid := auth.uid();
  actual_name text;
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập'; END IF;
  IF length(btrim(coalesce(p_name, ''))) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
  END IF;
  IF p_color_code IS NOT NULL AND p_color_code !~ '^#[0-9a-fA-F]{6}$' THEN
    RAISE EXCEPTION 'Mã màu không hợp lệ';
  END IF;
  IF p_action = 'create' THEN
    INSERT INTO public.calendar_categories(user_id, name, color_code)
      VALUES(owner_id, btrim(p_name), coalesce(p_color_code, '#E53935'));
    RETURN;
  END IF;
  SELECT name INTO actual_name FROM public.calendar_categories
    WHERE user_id = owner_id AND lower(name) = lower(btrim(p_name)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy nhãn'; END IF;
  IF p_action = 'rename' THEN
    IF length(btrim(coalesce(p_new_name, ''))) NOT BETWEEN 1 AND 60 THEN
      RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
    END IF;
    UPDATE public.calendar_categories SET name = btrim(p_new_name),
      color_code = coalesce(p_color_code, color_code)
      WHERE user_id = owner_id AND name = actual_name;
    UPDATE public.schedules SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
  ELSIF p_action = 'delete' THEN
    UPDATE public.schedules SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    DELETE FROM public.calendar_categories WHERE user_id = owner_id AND name = actual_name;
  ELSE
    RAISE EXCEPTION 'Thao tác không hợp lệ';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.manage_calendar_category_color(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.manage_calendar_category_color(text,text,text,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- Subject recurrence management
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


-- ASSISTANT_QUOTA: atomic daily usage limit (20261103).
BEGIN;
-- Atomic per-user quota. The assistant cannot be used without this migration.
create table if not exists public.assistant_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  requests integer not null default 0,
  primary key (user_id, usage_date)
);
alter table public.assistant_daily_usage enable row level security;
revoke all on public.assistant_daily_usage from anon, authenticated;

create or replace function public.consume_assistant_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare consumed integer;
begin
  if auth.uid() is null then return false; end if;
  insert into public.assistant_daily_usage(user_id, usage_date, requests)
  values (auth.uid(), current_date, 1)
  on conflict (user_id, usage_date) do update
    set requests = public.assistant_daily_usage.requests + 1
    where public.assistant_daily_usage.requests < 30
  returning requests into consumed;
  return consumed is not null;
end;
$$;
revoke all on function public.consume_assistant_request() from public, anon;
grant execute on function public.consume_assistant_request() to authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ACCOUNT_CASCADE_AUDIT: verify cascade foreign keys (20261103).
BEGIN;
-- Validate existing constraints; do NOT silently change unrelated schema/data.
-- Refuse rollout if deleting auth.users would leave app data orphaned.
do $$
declare item record;
begin
  for item in select * from (values
    ('profiles', 'id'), ('subjects', 'user_id'), ('schedules', 'user_id'),
    ('schedule_exams', 'user_id'), ('reminders', 'user_id'),
    ('calendar_categories', 'user_id')
  ) as t(table_name, column_name)
  loop
    if not exists (
      select 1 from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
      where c.conrelid = to_regclass('public.' || item.table_name)
        and c.confrelid = 'auth.users'::regclass
        and c.contype = 'f' and c.confdeltype = 'c'
        and a.attname = item.column_name
    ) then
      raise exception 'Missing ON DELETE CASCADE for %.%; review before deploying delete-account', item.table_name, item.column_name;
    end if;
  end loop;
end $$;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ACCOUNT DELETION: seven-day grace period and explicit restoration.
-- ACCOUNT_DELETION_GRACE: account lifecycle setup (20261104).
-- Existing databases: review and apply only the missing transaction blocks.
-- Automatic purge additionally requires Edge Functions and Cron; see
-- backend/ACCOUNT_DELETION_SETUP.md. No purge job is activated here.
begin;
create table if not exists public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default clock_timestamp(),
  delete_at timestamptz not null default (clock_timestamp() + interval '7 days'),
  state text not null default 'pending' check (state in ('pending', 'deleting'))
);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from anon, authenticated;
grant select, update on public.account_deletion_requests to service_role;

create or replace function public.account_is_active()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users where id = auth.uid())
    and not exists(select 1 from public.account_deletion_requests where user_id = auth.uid());
$$;
revoke all on function public.account_is_active() from public;
grant execute on function public.account_is_active() to authenticated, service_role;

create or replace function public.account_deletion_status()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.account_deletion_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if not exists(select 1 from auth.users where id = auth.uid()) then return jsonb_build_object('status', 'deleted'); end if;
  select * into r from public.account_deletion_requests where user_id = auth.uid();
  if not found then return jsonb_build_object('status', 'active'); end if;
  return jsonb_build_object('status', case when r.state = 'deleting' or r.delete_at <= clock_timestamp() then 'expired' else 'pending' end, 'delete_at', r.delete_at);
end $$;

create or replace function public.request_account_deletion(p_confirmation text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from auth.users where id = auth.uid()) then raise exception 'Sign in required'; end if;
  if p_confirmation is distinct from 'delete' then raise exception 'Confirmation required'; end if;
  -- Idempotent: a retry must never extend the seven-day deadline.
  insert into public.account_deletion_requests(user_id) values(auth.uid()) on conflict (user_id) do nothing;
  return public.account_deletion_status();
end $$;

create or replace function public.restore_pending_account(p_confirm boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.account_deletion_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_confirm is distinct from true then raise exception 'Explicit restoration required'; end if;
  select * into r from public.account_deletion_requests where user_id = auth.uid() for update;
  if found then
    if r.state <> 'pending' or r.delete_at <= clock_timestamp() then raise exception 'Restoration deadline expired'; end if;
    delete from public.account_deletion_requests where user_id = auth.uid();
  end if;
  return public.account_deletion_status();
end $$;

-- Claim and restore lock the same row. After a claim, restoration is impossible.
create or replace function public.claim_expired_account_deletions()
returns table(user_id uuid) language plpgsql security definer set search_path = '' as $$
begin
  return query with due as (
    select r.user_id from public.account_deletion_requests r
    where r.delete_at <= clock_timestamp()
    order by r.delete_at limit 100 for update skip locked
  ) update public.account_deletion_requests r set state = 'deleting'
    from due where r.user_id = due.user_id returning r.user_id;
end $$;

revoke all on function public.account_deletion_status(), public.request_account_deletion(text), public.restore_pending_account(boolean), public.claim_expired_account_deletions() from public, anon, authenticated;
grant execute on function public.account_deletion_status(), public.request_account_deletion(text), public.restore_pending_account(boolean) to authenticated;
grant execute on function public.claim_expired_account_deletions() to service_role;

-- RESTRICTIVE combines with existing owner policies using AND, not OR.
do $$ declare t text; begin
  foreach t in array array['profiles','subjects','schedules','schedule_exams','calendar_categories','reminders'] loop
    execute format('drop policy if exists "Active account required" on public.%I', t);
    execute format('create policy "Active account required" on public.%I as restrictive for all to authenticated using ((select public.account_is_active())) with check ((select public.account_is_active()))', t);
  end loop;
end $$;
commit;

-- DATABASE_HARDENING: policies, constraints, indexes and triggers (20261105).
-- ==========================================================================
-- Database hardening
-- Siết bảo mật, hiệu năng và độ bền cho schema "Quản lý lịch học".
--
-- Cách dùng:
--   * Database đang chạy: chỉ áp dụng khối transaction hardening còn thiếu.
--     Không tự chuyển đổi hoặc xóa dữ liệu hiện có.
--   * Database mới: chạy file SQL chính từ đầu để tạo các phần phụ thuộc.
--   * An toàn khi chạy lại nhiều lần (idempotent).
--   * Các mục "TÙY CHỌN" ở cuối file đang để dạng comment; đọc kỹ rồi mới bật.
--
-- Nên thử trên một project Supabase thử (hoặc branch) trước khi chạy thật.
-- ==========================================================================
BEGIN;

-- Refuse a partial/old setup before changing any policies.
DO $$
BEGIN
  IF to_regclass('public.account_deletion_requests') IS NULL
    OR to_regclass('public.calendar_categories') IS NULL
    OR to_regprocedure('public.save_subject_schedule(uuid,uuid,text,date,time,time,text,text,text,text,date)') IS NULL
    OR to_regprocedure('public.account_is_active()') IS NULL THEN
    RAISE EXCEPTION 'Apply calendar, recurrence and account-deletion migrations through 20261104 first';
  END IF;
END $$;

-- ==========================================================================
-- 1. PROFILES: chỉ đọc được hồ sơ của chính mình
--    (trước đây mọi user đã đăng nhập đọc được hồ sơ của nhau)
-- ==========================================================================
DROP POLICY IF EXISTS "Enable read for authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.profiles;
DROP POLICY IF EXISTS "Read own profile" ON public.profiles;
DROP POLICY IF EXISTS "Insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Update own profile" ON public.profiles;

CREATE POLICY "Read own profile" ON public.profiles
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = id);
CREATE POLICY "Insert own profile" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = id);
CREATE POLICY "Update own profile" ON public.profiles
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);

-- ==========================================================================
-- 2. POLICY chủ sở hữu: dùng (select auth.uid()) để Postgres chỉ tính 1 lần
--    mỗi câu truy vấn, và giới hạn rõ cho role authenticated.
--    (Policy RESTRICTIVE "Active account required" vẫn giữ nguyên.)
-- ==========================================================================
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['subjects','schedules','schedule_exams','reminders','calendar_categories']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS "Enable all for users based on user_id on %s" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "Own calendar categories" ON public.%I', t);
    EXECUTE format('DROP POLICY IF EXISTS "Owner full access" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "Owner full access" ON public.%I FOR ALL TO authenticated '
      'USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id)', t);
  END LOOP;
END $$;

-- ==========================================================================
-- 3. QUYỀN GỌI HÀM: đóng với role anon
--    (REVOKE ... FROM PUBLIC chưa đủ trên Supabase vì anon được cấp riêng)
-- ==========================================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.save_calendar_lesson(text,date,time,time,text,text,text,uuid,boolean,date)',
    'public.save_subject_schedule(uuid,uuid,text,date,time,time,text,text,text,text,date)',
    'public.delete_calendar_subject(uuid)',
    'public.manage_calendar_category(text,text,text)',
    'public.manage_calendar_category_color(text,text,text,text)',
    'public.account_deletion_status()',
    'public.request_account_deletion(text)',
    'public.restore_pending_account(boolean)'
  ]
  LOOP
    IF to_regprocedure(f) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END IF;
  END LOOP;

  -- Hàm dành riêng cho Edge Function (service_role)
  IF to_regprocedure('public.claim_expired_account_deletions()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.claim_expired_account_deletions() FROM PUBLIC, anon, authenticated;
    GRANT EXECUTE ON FUNCTION public.claim_expired_account_deletions() TO service_role;
  END IF;

  -- Dùng trong policy RESTRICTIVE (chỉ role authenticated và service_role cần)
  IF to_regprocedure('public.account_is_active()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.account_is_active() FROM PUBLIC, anon;
    GRANT EXECUTE ON FUNCTION public.account_is_active() TO authenticated, service_role;
  END IF;
END $$;

-- ==========================================================================
-- 4. XÓA TÀI KHOẢN: chờ 15 phút trước khi nhận lại yêu cầu đang xử lý
--    Hàm cũ đã nhận lại dòng deleting ở mỗi lần chạy. Bổ sung lease 15 phút
--    để tránh nhận lại quá sớm khi worker trước vẫn đang xử lý.
-- ==========================================================================
ALTER TABLE public.account_deletion_requests
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

CREATE OR REPLACE FUNCTION public.claim_expired_account_deletions()
RETURNS TABLE(user_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT r.user_id
    FROM public.account_deletion_requests r
    WHERE r.delete_at <= clock_timestamp()
      AND (
        r.state = 'pending'
        OR (r.state = 'deleting'
            AND (r.claimed_at IS NULL OR r.claimed_at < clock_timestamp() - interval '15 minutes'))
      )
    ORDER BY r.delete_at
    LIMIT 100
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.account_deletion_requests r
     SET state = 'deleting', claimed_at = clock_timestamp()
    FROM due
   WHERE r.user_id = due.user_id
  RETURNING r.user_id;
END $$;

REVOKE ALL ON FUNCTION public.claim_expired_account_deletions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_expired_account_deletions() TO service_role;

-- ==========================================================================
-- 5. REMINDERS: tự dọn nhắc nhở khi lịch học / lịch thi bị xóa
--    (reminders.schedule_id không có khóa ngoại nên trước đây bị mồ côi)
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.cleanup_reminders_on_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  DELETE FROM public.reminders
   WHERE schedule_id = OLD.id AND schedule_type = TG_ARGV[0]
     AND user_id = OLD.user_id;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS trg_schedules_cleanup_reminders ON public.schedules;
CREATE TRIGGER trg_schedules_cleanup_reminders
  AFTER DELETE ON public.schedules
  FOR EACH ROW EXECUTE FUNCTION public.cleanup_reminders_on_delete('schedule');

DROP TRIGGER IF EXISTS trg_exams_cleanup_reminders ON public.schedule_exams;
CREATE TRIGGER trg_exams_cleanup_reminders
  AFTER DELETE ON public.schedule_exams
  FOR EACH ROW EXECUTE FUNCTION public.cleanup_reminders_on_delete('exam');

-- ==========================================================================
-- 6. RÀNG BUỘC Ở MỨC BẢNG (chặn dữ liệu sai dù ghi trực tiếp qua API)
--    NOT VALID: chỉ áp dụng cho dòng mới/được sửa, không làm hỏng dữ liệu cũ.
-- ==========================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schedules_time_chk'
                 AND conrelid = 'public.schedules'::regclass) THEN
    ALTER TABLE public.schedules ADD CONSTRAINT schedules_time_chk
      CHECK (start_time IS NULL OR end_time IS NULL OR end_time > start_time) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schedules_date_chk'
                 AND conrelid = 'public.schedules'::regclass) THEN
    ALTER TABLE public.schedules ADD CONSTRAINT schedules_date_chk
      CHECK (start_date IS NULL OR end_date IS NULL OR end_date >= start_date) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schedule_exams_time_chk'
                 AND conrelid = 'public.schedule_exams'::regclass) THEN
    ALTER TABLE public.schedule_exams ADD CONSTRAINT schedule_exams_time_chk
      CHECK (end_time > start_time) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reminders_type_chk'
                 AND conrelid = 'public.reminders'::regclass) THEN
    ALTER TABLE public.reminders ADD CONSTRAINT reminders_type_chk
      CHECK (schedule_type IN ('schedule', 'exam')) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reminders_minutes_chk'
                 AND conrelid = 'public.reminders'::regclass) THEN
    ALTER TABLE public.reminders ADD CONSTRAINT reminders_minutes_chk
      CHECK (remind_before_minutes IS NULL OR remind_before_minutes >= 0) NOT VALID;
  END IF;
END $$;

-- ==========================================================================
-- 7. INDEX cho các cột hay lọc / join (tránh quét toàn bảng)
-- ==========================================================================
CREATE INDEX IF NOT EXISTS subjects_user_idx         ON public.subjects(user_id);
CREATE INDEX IF NOT EXISTS schedules_user_start_idx  ON public.schedules(user_id, start_date);
CREATE INDEX IF NOT EXISTS schedules_subject_idx     ON public.schedules(subject_id);
CREATE INDEX IF NOT EXISTS exams_user_date_idx       ON public.schedule_exams(user_id, exam_date);
CREATE INDEX IF NOT EXISTS exams_subject_idx         ON public.schedule_exams(subject_id);
CREATE INDEX IF NOT EXISTS reminders_lookup_idx      ON public.reminders(user_id, schedule_type, schedule_id);

-- ==========================================================================
-- 8. DỮ LIỆU: điền chu kỳ cho dòng cũ, đổi default thời gian, sửa chú thích
-- ==========================================================================
-- Không backfill recurrence: ScheduleRecurrence.frequency đã suy luận NULL.
-- Tránh thay đổi ý nghĩa lịch cũ và tránh UPDATE dòng vi phạm CHECK NOT VALID.
-- NOT VALID chỉ bỏ kiểm tra ban đầu; INSERT/UPDATE sau này vẫn phải hợp lệ.

-- timezone('utc', now()) trả về timestamp không múi giờ; now() đơn giản và đúng hơn.
ALTER TABLE public.profiles        ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.subjects        ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.schedules       ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.reminders       ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.schedule_exams  ALTER COLUMN created_at SET DEFAULT now();

COMMENT ON COLUMN public.schedules.day_of_week IS
  'Mảng thứ trong tuần: 2 = Thứ 2, 3 = Thứ 3, ..., 7 = Thứ 7, 8 = Chủ nhật (isodow + 1).';

-- ==========================================================================
-- 9. NHÃN: báo lỗi thân thiện khi tạo / đổi tên trùng nhãn đã có
--    (thay vì lỗi unique 23505 thô). Giữ nguyên chữ ký hàm.
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.manage_calendar_category_color(
  p_action text, p_name text, p_new_name text DEFAULT NULL, p_color_code text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  owner_id uuid := auth.uid();
  actual_name text;
BEGIN
  IF owner_id IS NULL THEN RAISE EXCEPTION 'Vui lòng đăng nhập'; END IF;
  IF length(btrim(coalesce(p_name, ''))) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
  END IF;
  IF p_color_code IS NOT NULL AND p_color_code !~ '^#[0-9a-fA-F]{6}$' THEN
    RAISE EXCEPTION 'Mã màu không hợp lệ';
  END IF;
  IF p_action = 'create' THEN
    BEGIN
      INSERT INTO public.calendar_categories(user_id, name, color_code)
        VALUES(owner_id, btrim(p_name), coalesce(p_color_code, '#E53935'));
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Nhãn này đã tồn tại';
    END;
    RETURN;
  END IF;
  SELECT name INTO actual_name FROM public.calendar_categories
    WHERE user_id = owner_id AND lower(name) = lower(btrim(p_name)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy nhãn'; END IF;
  IF p_action = 'rename' THEN
    IF length(btrim(coalesce(p_new_name, ''))) NOT BETWEEN 1 AND 60 THEN
      RAISE EXCEPTION 'Tên nhãn phải có từ 1 đến 60 ký tự';
    END IF;
    BEGIN
      UPDATE public.calendar_categories SET name = btrim(p_new_name),
        color_code = coalesce(p_color_code, color_code)
        WHERE user_id = owner_id AND name = actual_name;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Đã có nhãn khác trùng tên này';
    END;
    UPDATE public.schedules SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = btrim(p_new_name)
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
  ELSIF p_action = 'delete' THEN
    UPDATE public.schedules SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    UPDATE public.schedule_exams SET category = ''
      WHERE user_id = owner_id AND lower(btrim(category)) = lower(actual_name);
    DELETE FROM public.calendar_categories WHERE user_id = owner_id AND name = actual_name;
  ELSE
    RAISE EXCEPTION 'Thao tác không hợp lệ';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.manage_calendar_category_color(text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.manage_calendar_category_color(text,text,text,text) TO authenticated;

-- 10. Môn học và lịch phải thuộc cùng một tài khoản.
-- Giữ FK subject_id hiện có; composite FK bảo vệ cả đường ghi trực tiếp.
CREATE UNIQUE INDEX IF NOT EXISTS subjects_owner_id_uniq
  ON public.subjects(user_id, id);
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['schedules', 'schedule_exams'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conname = t || '_subject_owner_fk'
        AND conrelid = to_regclass('public.' || t)) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I '
        'FOREIGN KEY (user_id, subject_id) REFERENCES public.subjects(user_id, id) '
        'ON DELETE CASCADE NOT VALID', t, t || '_subject_owner_fk');
    END IF;
  END LOOP;
END $$;

-- 11. Quan hệ đa hình của reminders: kiểm tra chủ sở hữu và khóa lịch cha
-- để INSERT reminder không chạy đua với DELETE lịch. INVOKER giữ nguyên RLS.
CREATE OR REPLACE FUNCTION public.check_reminder_parent()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF NEW.schedule_type = 'schedule' THEN
    PERFORM 1 FROM public.schedules
      WHERE id = NEW.schedule_id AND user_id = NEW.user_id FOR KEY SHARE;
  ELSIF NEW.schedule_type = 'exam' THEN
    PERFORM 1 FROM public.schedule_exams
      WHERE id = NEW.schedule_id AND user_id = NEW.user_id FOR KEY SHARE;
  ELSE
    RAISE EXCEPTION 'Loại lịch nhắc nhở không hợp lệ' USING ERRCODE = '23514';
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lịch nhắc nhở không tồn tại hoặc không thuộc tài khoản này'
      USING ERRCODE = '23503';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_reminders_check_parent ON public.reminders;
CREATE TRIGGER trg_reminders_check_parent
  BEFORE INSERT OR UPDATE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.check_reminder_parent();

-- Trigger cleanup có thể chỉ biết schedule_id/type khi xóa bằng service_role.
CREATE INDEX IF NOT EXISTS reminders_parent_idx
  ON public.reminders(schedule_id, schedule_type);
CREATE INDEX IF NOT EXISTS account_deletion_due_idx
  ON public.account_deletion_requests(delete_at);

NOTIFY pgrst, 'reload schema';
COMMIT;

-- ==========================================================================
-- TÙY CHỌN (đang tắt). Đọc kỹ trước khi bật.
-- ==========================================================================

-- A) Dọn nhắc nhở mồ côi đã có từ trước.
--    Xem trước số dòng sẽ xóa:
--      SELECT count(*) FROM public.reminders r
--       WHERE (r.schedule_type = 'schedule' AND NOT EXISTS (SELECT 1 FROM public.schedules s WHERE s.id = r.schedule_id))
--          OR (r.schedule_type = 'exam'     AND NOT EXISTS (SELECT 1 FROM public.schedule_exams e WHERE e.id = r.schedule_id));
--    Nếu đúng là rác (app lưu schedule_id là id thật của lịch), chạy:
--      DELETE FROM public.reminders r
--       WHERE (r.schedule_type = 'schedule' AND NOT EXISTS (SELECT 1 FROM public.schedules s WHERE s.id = r.schedule_id))
--          OR (r.schedule_type = 'exam'     AND NOT EXISTS (SELECT 1 FROM public.schedule_exams e WHERE e.id = r.schedule_id));

-- B) Chống trùng tên môn trong cùng một tài khoản.
--    Kiểm tra trùng hiện có trước:
--      SELECT user_id, lower(btrim(subject_name)) AS name, count(*)
--        FROM public.subjects GROUP BY 1, 2 HAVING count(*) > 1;
--    Nếu không có dòng nào (và chức năng nhập file của app không tạo môn trùng tên), chạy:
--      CREATE UNIQUE INDEX IF NOT EXISTS subjects_owner_name_uniq
--        ON public.subjects(user_id, lower(btrim(subject_name)));

-- C) Giới hạn day_of_week trong khoảng 2..8.
--    Chỉ bật khi chắc chắn mọi nơi ghi dữ liệu (kể cả nhập file) đều dùng cách mã hóa 2..8:
--      ALTER TABLE public.schedules
--        ADD CONSTRAINT schedules_dow_chk
--        CHECK (day_of_week IS NULL OR day_of_week <@ ARRAY[2,3,4,5,6,7,8]) NOT VALID;

-- OPTIONAL_ACCOUNT_PURGE_CRON
-- Run this block separately AFTER deploying the worker and creating Vault secrets.
-- It remains commented so running the main setup does not activate deletion jobs.
-- -- Run AFTER deploying purge-accounts and creating these Vault secrets:
-- -- account_purge_url: https://YOUR_PROJECT.supabase.co/functions/v1/purge-accounts
-- -- account_purge_secret: same value as Edge secret ACCOUNT_DELETION_CRON_SECRET
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net with schema extensions;
--
-- do $$ begin
--   if not exists(select 1 from vault.decrypted_secrets where name = 'account_purge_url')
--     or not exists(select 1 from vault.decrypted_secrets where name = 'account_purge_secret') then
--     raise exception 'Create account_purge_url and account_purge_secret in Vault first';
--   end if;
-- end $$;
--
-- select cron.schedule('purge-expired-accounts', '* * * * *', $$
--   select net.http_post(
--     url := (select decrypted_secret from vault.decrypted_secrets where name = 'account_purge_url' limit 1),
--     headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret',
--       (select decrypted_secret from vault.decrypted_secrets where name = 'account_purge_secret' limit 1)),
--     body := '{}'::jsonb,
--     timeout_milliseconds := 55000
--   );
-- $$);


-- ======================================================================
-- APP_DATA_SYNC: profile names and unambiguous subject relationships.
-- Existing databases may run this complete BEGIN..COMMIT block separately.
-- Keeps the composite owner FK; removes only redundant single-column FKs.
-- ======================================================================
BEGIN;
CREATE UNIQUE INDEX IF NOT EXISTS subjects_owner_id_uniq ON public.subjects(user_id, id);
DO $$
DECLARE t text; old_fk record;
BEGIN
  FOREACH t IN ARRAY ARRAY['schedules', 'schedule_exams'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conname = t || '_subject_owner_fk' AND conrelid = to_regclass('public.' || t)) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I '
        'FOREIGN KEY (user_id, subject_id) REFERENCES public.subjects(user_id, id) '
        'ON DELETE CASCADE NOT VALID', t, t || '_subject_owner_fk');
    END IF;
    FOR old_fk IN
      SELECT c.conname FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attname = 'subject_id'
      WHERE c.conrelid = to_regclass('public.' || t) AND c.contype = 'f'
        AND c.confrelid = 'public.subjects'::regclass
        AND c.conkey = ARRAY[a.attnum]::smallint[]
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', t, old_fk.conname);
    END LOOP;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.create_account_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.profiles(id, username)
  VALUES (NEW.id, coalesce(
    nullif(btrim(NEW.raw_user_meta_data->>'username'), ''),
    nullif(btrim(NEW.raw_user_meta_data->>'full_name'), ''),
    nullif(btrim(NEW.raw_user_meta_data->>'name'), ''),
    nullif(split_part(NEW.email, '@', 1), '')))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.create_account_profile() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_create_account_profile ON auth.users;
CREATE TRIGGER trg_create_account_profile AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_account_profile();

-- Fill missing profiles/names from registration metadata; retain edited names.
INSERT INTO public.profiles(id, username)
SELECT u.id, coalesce(nullif(btrim(u.raw_user_meta_data->>'username'), ''),
  nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
  nullif(btrim(u.raw_user_meta_data->>'name'), ''), nullif(split_part(u.email, '@', 1), ''))
FROM auth.users u
ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles p SET username = coalesce(
  nullif(btrim(u.raw_user_meta_data->>'username'), ''),
  nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
  nullif(btrim(u.raw_user_meta_data->>'name'), ''), nullif(split_part(u.email, '@', 1), ''))
FROM auth.users u WHERE p.id = u.id AND nullif(btrim(p.username), '') IS NULL;
NOTIFY pgrst, 'reload schema';
COMMIT;
