$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source = Get-Content -LiteralPath (Join-Path $projectRoot 'supabase_database.sql') -Raw
$actionStart = $source.IndexOf('-- AI_CALENDAR_ACTIONS:')
$nextBlock = $source.IndexOf('-- ACCOUNT_RESTORE_HINT:', $actionStart)
$block = if ($nextBlock -ge 0) { $source.Substring($actionStart, $nextBlock - $actionStart) } else { $source.Substring($actionStart) }
if ([regex]::Matches($block, '(?im)^COMMIT;').Count -ne 1 -or
    $block -notmatch 'COMMIT;\s*$') {
  throw 'Expected one final migration COMMIT; refusing remote execution.'
}
$block = $block -replace 'COMMIT;\s*$', ''
if ($block -match '(?i)\b(COMMIT|END\s+TRANSACTION)\b') {
  throw 'Unexpected transaction commit in rollback-only test.'
}
$checks = @'
DO $$
DECLARE
  owner_id uuid := gen_random_uuid();
  other_id uuid := gen_random_uuid();
  request_id uuid := gen_random_uuid();
  event_id uuid;
  other_event uuid;
  exam_id uuid;
  action jsonb := '{"operation":"create","kind":"class","title":"Assistant rollback test","date":"2026-12-01","start":"08:00","end":"09:00","room":"TEST"}';
  delete_action jsonb;
BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
    (owner_id,owner_id::text||'@example.invalid','{}'),
    (other_id,other_id::text||'@example.invalid','{}');
  PERFORM set_config('request.jwt.claim.sub',other_id::text,true);
  other_event := public.save_subject_schedule(NULL,NULL,'Assistant rollback test','2026-12-01','08:00','09:00','TEST','','','none',NULL);
  PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
  SET LOCAL ROLE authenticated;
  event_id := public.apply_assistant_calendar_action(request_id,action);
  IF public.apply_assistant_calendar_action(request_id,action) <> event_id THEN RAISE EXCEPTION 'Idempotency failed'; END IF;
  IF (SELECT count(*) FROM public.schedules WHERE id=event_id) <> 1 THEN RAISE EXCEPTION 'Create failed'; END IF;
  BEGIN
    PERFORM public.apply_assistant_calendar_action(request_id,action||'{"room":"OTHER"}');
    RAISE EXCEPTION 'Expected reused ID rejection';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Expected reused ID rejection' THEN RAISE; END IF;
  END;
  delete_action := action || jsonb_build_object('operation','delete','id',other_event);
  BEGIN
    PERFORM public.apply_assistant_calendar_action(gen_random_uuid(),delete_action);
    RAISE EXCEPTION 'Expected other account rejection';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Expected other account rejection' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.schedules WHERE id=other_event) THEN RAISE EXCEPTION 'RLS leak'; END IF;
  delete_action := action || jsonb_build_object('operation','delete','id',event_id);
  request_id := gen_random_uuid();
  PERFORM public.apply_assistant_calendar_action(request_id,delete_action);
  PERFORM public.apply_assistant_calendar_action(request_id,delete_action);
  IF EXISTS(SELECT 1 FROM public.schedules WHERE id=event_id) THEN RAISE EXCEPTION 'Delete failed'; END IF;
  exam_id := public.apply_assistant_calendar_action(gen_random_uuid(), action||'{"kind":"exam"}');
  IF NOT EXISTS(SELECT 1 FROM public.schedule_exams WHERE id=exam_id) THEN RAISE EXCEPTION 'Exam create failed'; END IF;
  PERFORM public.apply_assistant_calendar_action(gen_random_uuid(), action||jsonb_build_object('kind','exam','operation','delete','id',exam_id));
  IF EXISTS(SELECT 1 FROM public.schedule_exams WHERE id=exam_id) THEN RAISE EXCEPTION 'Exam delete failed'; END IF;
END;
$$;
ROLLBACK;
'@
$temporaryFile = Join-Path ([IO.Path]::GetTempPath()) ('assistant-check-' + [guid]::NewGuid() + '.txt')
try {
  $rollbackOnly = $block + "`n" + $checks
  if ($rollbackOnly -match '(?i)\bCOMMIT\b' -or $rollbackOnly -notmatch 'ROLLBACK;\s*$') {
    throw 'Test must contain no COMMIT and end with ROLLBACK.'
  }
  Set-Content -LiteralPath $temporaryFile -Value $rollbackOnly -Encoding utf8
  & npx.cmd supabase db query --linked --project-ref fjwdaccejrodpcicyxrc --file $temporaryFile
  if ($LASTEXITCODE -ne 0) { throw 'Database checks failed' }
  Write-Output 'Calendar create/delete, retry and account isolation checks passed. All changes rolled back.'
} finally {
  Remove-Item -LiteralPath $temporaryFile -ErrorAction SilentlyContinue
}
