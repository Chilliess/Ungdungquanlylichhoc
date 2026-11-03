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
