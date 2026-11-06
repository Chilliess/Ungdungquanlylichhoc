$ErrorActionPreference = 'Stop'
$sql = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../supabase_database.sql') -Raw
$start = $sql.IndexOf('-- CALENDAR_EXAM_CREATE_FIX:')
if ($start -lt 0) { throw 'Missing exam migration' }
$migration = $sql.Substring($start) -replace '(?i)COMMIT;\s*$', ''
$checks = @'
DO $$
DECLARE a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); subject_a uuid:=gen_random_uuid();
  subject_b uuid:=gen_random_uuid(); exam_id uuid; new_exam uuid; lesson_id uuid; got_subject uuid;
BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
  VALUES(a,'exam-a-'||a||'@example.invalid','{}',now(),now()),(b,'exam-b-'||b||'@example.invalid','{}',now(),now());
  INSERT INTO public.subjects(id,user_id,subject_name,subject_code)
  VALUES(subject_a,a,'Toán','TEST-A'),(subject_b,b,'Toán','TEST-B');
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  SET LOCAL ROLE authenticated;
  exam_id:=public.save_calendar_lesson(' Toán ','2026-11-08','19:00','20:00',' A1, 101 ',
    ' Ghi chú thi ','Thực hành',NULL,true,'2026-11-08');
  IF NOT EXISTS(SELECT 1 FROM public.schedule_exams WHERE id=exam_id AND user_id=a AND subject_id=subject_a
    AND exam_date='2026-11-08' AND start_time='19:00' AND end_time='20:00'
    AND room='A1, 101' AND notes='Ghi chú thi' AND category='Thực hành') THEN
    RAISE EXCEPTION 'Exam details or subject ownership incorrect'; END IF;
  IF (SELECT count(*) FROM public.subjects WHERE user_id=a)<>1 OR EXISTS(SELECT 1 FROM public.schedules WHERE user_id=a) THEN
    RAISE EXCEPTION 'Creating exam duplicated subject or created lesson'; END IF;
  PERFORM public.save_calendar_lesson('Toán','2026-11-09','08:00','09:00','A2',
    '', '',exam_id,true,'2026-11-08');
  IF NOT EXISTS(SELECT 1 FROM public.schedule_exams WHERE id=exam_id AND exam_date='2026-11-09' AND room='A2')
    OR (SELECT count(*) FROM public.schedule_exams WHERE user_id=a)<>1 THEN RAISE EXCEPTION 'Exam update failed'; END IF;
  new_exam:=public.save_calendar_lesson('Môn thi mới','2026-11-10','07:00','08:00','A3',p_is_exam=>true);
  SELECT subject_id INTO got_subject FROM public.schedule_exams WHERE id=new_exam;
  IF NOT EXISTS(SELECT 1 FROM public.subjects WHERE id=got_subject AND user_id=a AND subject_name='Môn thi mới') THEN
    RAISE EXCEPTION 'New exam subject failed'; END IF;
  BEGIN
    PERFORM public.save_calendar_lesson('Invalid exam','2026-11-08','20:00','19:00','A1',p_is_exam=>true);
    RAISE EXCEPTION 'Invalid time accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='Invalid time accepted' THEN RAISE; END IF; END;
  IF EXISTS(SELECT 1 FROM public.subjects WHERE user_id=a AND subject_name='Invalid exam') THEN
    RAISE EXCEPTION 'Failed save left orphan subject'; END IF;
  lesson_id:=public.save_calendar_lesson('Toán','2026-11-11','10:00','11:00','A4');
  IF NOT EXISTS(SELECT 1 FROM public.schedules WHERE id=lesson_id AND user_id=a) THEN
    RAISE EXCEPTION 'Existing lesson creation regressed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  BEGIN
    PERFORM public.save_calendar_lesson('Toán','2026-11-12','10:00','11:00','Hacked',p_id=>exam_id,p_is_exam=>true);
    RAISE EXCEPTION 'Foreign exam edit accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='Foreign exam edit accepted' THEN RAISE; END IF; END;
  IF EXISTS(SELECT 1 FROM public.schedule_exams WHERE id=exam_id) THEN RAISE EXCEPTION 'Foreign exam exposed'; END IF;
  RESET ROLE;
END;
$$;
ROLLBACK;
'@
$testSql = $migration + "`n" + $checks
if ($testSql -match '(?i)\bCOMMIT\b' -or $testSql -notmatch 'ROLLBACK;\s*$') { throw 'Test must only roll back' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('exam-create-test-' + [guid]::NewGuid() + '.txt')
try {
  Set-Content -LiteralPath $stage -Value $testSql -Encoding utf8
  & npx.cmd supabase db query --linked --project-ref fjwdaccejrodpcicyxrc --file $stage
  if ($LASTEXITCODE -ne 0) { throw 'Exam creation database checks failed' }
  Write-Output 'Exam create/edit, details, subject reuse, invalid time, lesson regression and ownership checks passed; rolled back.'
} finally { Remove-Item -LiteralPath $stage -ErrorAction SilentlyContinue }
