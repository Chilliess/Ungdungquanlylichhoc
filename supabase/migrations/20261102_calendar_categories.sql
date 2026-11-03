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
