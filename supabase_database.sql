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