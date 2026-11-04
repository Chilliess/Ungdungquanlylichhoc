# Kiểm tra database trên môi trường thử

## Kiểm tra sau APP_DATA_SYNC

Sau khi chạy nguyên khối APP_DATA_SYNC trong file SQL chính, truy vấn sau phải
trả đúng một khóa ngoại lịch → môn cho mỗi bảng (khóa tổng hợp có user_id):

```sql
SELECT c.conrelid::regclass AS table_name, c.conname,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.contype = 'f' AND c.confrelid = 'public.subjects'::regclass
  AND c.conrelid IN ('public.schedules'::regclass, 'public.schedule_exams'::regclass);
```

Kiểm tra hồ sơ chưa được tạo:

```sql
SELECT count(*) AS missing_profiles
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);
```

Các kiểm tra SQL cần chạy trên database thử; chưa được thực thi trên Supabase
trong phiên chỉnh sửa giao diện và đồng bộ này.

Các đoạn dưới được giữ trong hướng dẫn để dự án chỉ có một file `.sql`.
Chạy từng khối riêng trong SQL Editor. Khối kiểm thử tạo dữ liệu phải chạy trên
database thử và kết thúc bằng ROLLBACK; nếu có lỗi, chạy ROLLBACK thủ công.


## hardening_preflight

```sql
-- Read-only audit. Run as postgres before rollout; no rows are changed.
-- Also use after rollout to plan cleanup and VALIDATE CONSTRAINT separately.
SELECT 'schedules_invalid_time_or_dates' AS issue, count(*) AS affected_rows
FROM public.schedules
WHERE end_time <= start_time OR end_date < start_date
UNION ALL
SELECT 'exams_invalid_time', count(*) FROM public.schedule_exams
WHERE end_time <= start_time
UNION ALL
SELECT 'schedules_subject_owner_mismatch', count(*) FROM public.schedules s
WHERE NOT EXISTS (SELECT 1 FROM public.subjects p WHERE p.id = s.subject_id AND p.user_id = s.user_id)
UNION ALL
SELECT 'exams_subject_owner_mismatch', count(*) FROM public.schedule_exams e
WHERE NOT EXISTS (SELECT 1 FROM public.subjects p WHERE p.id = e.subject_id AND p.user_id = e.user_id)
UNION ALL
SELECT 'reminders_invalid_parent_or_type', count(*) FROM public.reminders r
WHERE NOT (
  (r.schedule_type = 'schedule' AND EXISTS
    (SELECT 1 FROM public.schedules s WHERE s.id = r.schedule_id AND s.user_id = r.user_id))
  OR (r.schedule_type = 'exam' AND EXISTS
    (SELECT 1 FROM public.schedule_exams e WHERE e.id = r.schedule_id AND e.user_id = r.user_id))
)
UNION ALL
SELECT 'reminders_negative_minutes', count(*) FROM public.reminders
WHERE remind_before_minutes < 0;
```


## hardening

```sql
-- Run on a disposable/staging database AFTER the DATABASE_HARDENING block in supabase_database.sql.
-- Fixtures and changes are rolled back. Run as postgres (SQL Editor).
BEGIN;
INSERT INTO auth.users(id, aud, role, email, created_at, updated_at) VALUES
  ('fbfbfbfb-0000-4000-8000-000000000001','authenticated','authenticated','hardening-a@example.invalid',now(),now()),
  ('fbfbfbfb-0000-4000-8000-000000000002','authenticated','authenticated','hardening-b@example.invalid',now(),now());
INSERT INTO public.profiles(id, username) VALUES
  ('fbfbfbfb-0000-4000-8000-000000000001','hardening-a'),
  ('fbfbfbfb-0000-4000-8000-000000000002','hardening-b')
ON CONFLICT (id) DO UPDATE SET username = excluded.username;
INSERT INTO public.subjects(id,user_id,subject_code,subject_name) VALUES
  ('fbfbfbfb-1000-4000-8000-000000000001','fbfbfbfb-0000-4000-8000-000000000001','HARDEN-A','Hardening A'),
  ('fbfbfbfb-1000-4000-8000-000000000002','fbfbfbfb-0000-4000-8000-000000000002','HARDEN-B','Hardening B');
INSERT INTO public.schedules(id,user_id,subject_id,start_time,end_time,start_date,end_date,day_of_week) VALUES
  ('fbfbfbfb-2000-4000-8000-000000000001','fbfbfbfb-0000-4000-8000-000000000001','fbfbfbfb-1000-4000-8000-000000000001','07:00','09:00','2026-11-02','2026-11-30',ARRAY[2,4]),
  ('fbfbfbfb-2000-4000-8000-000000000002','fbfbfbfb-0000-4000-8000-000000000002','fbfbfbfb-1000-4000-8000-000000000002','07:00','09:00','2026-11-02','2026-11-30',ARRAY[2]);
INSERT INTO public.schedule_exams(id,user_id,subject_id,exam_date,start_time,end_time) VALUES
  ('fbfbfbfb-3000-4000-8000-000000000001','fbfbfbfb-0000-4000-8000-000000000001','fbfbfbfb-1000-4000-8000-000000000001','2026-11-02','09:00','10:00');
SELECT set_config('request.jwt.claim.sub','fbfbfbfb-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.profiles) <> 1 THEN
    RAISE EXCEPTION 'Profile isolation failed';
  END IF;
  BEGIN
    INSERT INTO public.schedules(user_id,subject_id) VALUES
      (auth.uid(),'fbfbfbfb-1000-4000-8000-000000000002');
    RAISE EXCEPTION 'Cross-owner subject accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.schedule_exams(user_id,subject_id,exam_date,start_time,end_time) VALUES
      (auth.uid(),'fbfbfbfb-1000-4000-8000-000000000002','2026-11-02','09:00','10:00');
    RAISE EXCEPTION 'Cross-owner exam subject accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.reminders(user_id,schedule_id) VALUES
      (auth.uid(),'fbfbfbfb-2000-4000-8000-000000000002');
    RAISE EXCEPTION 'Cross-owner reminder accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.reminders(user_id,schedule_id) VALUES
      (auth.uid(),'fbfbfbfb-2000-4000-8000-000000000099');
    RAISE EXCEPTION 'Missing reminder parent accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.schedules SET end_time = start_time
      WHERE id = 'fbfbfbfb-2000-4000-8000-000000000001';
    RAISE EXCEPTION 'Invalid lesson time accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.schedules SET end_date = start_date - 1
      WHERE id = 'fbfbfbfb-2000-4000-8000-000000000001';
    RAISE EXCEPTION 'Invalid lesson dates accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO public.reminders(user_id,schedule_id,schedule_type) VALUES
    (auth.uid(),'fbfbfbfb-2000-4000-8000-000000000001','schedule'),
    (auth.uid(),'fbfbfbfb-3000-4000-8000-000000000001','exam');
  BEGIN
    UPDATE public.reminders SET schedule_type = 'exam'
      WHERE schedule_id = 'fbfbfbfb-2000-4000-8000-000000000001';
    RAISE EXCEPTION 'Mismatched reminder type accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  DELETE FROM public.schedules WHERE id = 'fbfbfbfb-2000-4000-8000-000000000001';
  DELETE FROM public.schedule_exams WHERE id = 'fbfbfbfb-3000-4000-8000-000000000001';
  IF EXISTS (SELECT 1 FROM public.reminders) THEN
    RAISE EXCEPTION 'Reminder cleanup failed';
  END IF;
END $$;
RESET ROLE;
DO $$
BEGIN
  IF has_function_privilege('anon','public.save_subject_schedule(uuid,uuid,text,date,time,time,text,text,text,text,date)','EXECUTE')
    OR has_function_privilege('authenticated','public.claim_expired_account_deletions()','EXECUTE') THEN
    RAISE EXCEPTION 'RPC privilege isolation failed';
  END IF;
END $$;
ROLLBACK;
```


## account_deletion_grace

```sql
-- Run only on a disposable/staging database AFTER migrations. Always rolls back.
begin;
insert into auth.users(id, aud, role, email, created_at, updated_at)
values ('fafafafa-0000-4000-8000-000000000001','authenticated','authenticated','grace-test@example.invalid',now(),now());
select set_config('request.jwt.claim.sub', 'fafafafa-0000-4000-8000-000000000001', true);
do $$ declare first_deadline text; r jsonb; begin
  if not public.account_is_active() then raise exception 'Expected active'; end if;
  begin
    perform public.request_account_deletion('DELETE');
    raise exception 'Incorrect confirmation was accepted';
  exception when raise_exception then
    if sqlerrm <> 'Confirmation required' then raise; end if;
  end;
  r := public.request_account_deletion('delete');
  first_deadline := r->>'delete_at';
  if r->>'status' <> 'pending' then raise exception 'Expected pending'; end if;
  if public.account_is_active() then raise exception 'Pending user must be blocked'; end if;
  r := public.request_account_deletion('delete');
  if r->>'delete_at' <> first_deadline then raise exception 'Retry extended deadline'; end if;
  perform public.account_deletion_status();
  if public.account_is_active() then raise exception 'Status call restored user'; end if;
  perform public.restore_pending_account(true);
  if not public.account_is_active() then raise exception 'Restore failed'; end if;
  perform public.request_account_deletion('delete');
  update public.account_deletion_requests set delete_at = clock_timestamp() - interval '1 second' where user_id = auth.uid();
  begin
    perform public.restore_pending_account(true);
    raise exception 'Expired user was restored';
  exception when raise_exception then
    if sqlerrm <> 'Restoration deadline expired' then raise; end if;
  end;
  perform public.claim_expired_account_deletions();
  if (select state from public.account_deletion_requests where user_id = auth.uid()) <> 'deleting' then raise exception 'Claim failed'; end if;
  -- Requires DATABASE_HARDENING: an in-flight claim cannot be reclaimed.
  if exists(select 1 from public.claim_expired_account_deletions() c where c.user_id = auth.uid()) then
    raise exception 'Live claim was reclaimed';
  end if;
  update public.account_deletion_requests set claimed_at = clock_timestamp() - interval '16 minutes'
    where user_id = auth.uid();
  if not exists(select 1 from public.claim_expired_account_deletions() c where c.user_id = auth.uid()) then
    raise exception 'Expired claim was not retried';
  end if;
end $$;
rollback;
```
