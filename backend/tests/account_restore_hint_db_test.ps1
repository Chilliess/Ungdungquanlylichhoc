$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sql = Get-Content -LiteralPath (Join-Path $root 'supabase_database.sql') -Raw
$marker = $sql.IndexOf('-- ACCOUNT_RESTORE_HINT:')
if ($marker -lt 0) { throw 'Missing restore hint migration' }
$end = $sql.IndexOf('-- WORKSPACE_CLOUD_SYNC:', $marker)
$migration = if ($end -ge 0) { $sql.Substring($marker, $end - $marker) } else { $sql.Substring($marker) }
if ([regex]::Matches($migration, '(?im)^COMMIT;').Count -ne 1 -or $migration -notmatch 'COMMIT;\s*$') {
  throw 'Expected one final COMMIT'
}
$rollbackMigration = $migration -replace 'COMMIT;\s*$', ''
$checks = @'
DO $$
DECLARE
  owner_id uuid := gen_random_uuid();
  metadata jsonb;
  first_deadline timestamptz;
BEGIN
  INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data)
    VALUES(owner_id,owner_id::text||'@example.invalid','{"provider":"email","keep":"intact"}','{}');
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=owner_id AND raw_app_meta_data ? 'account_deletion_pending') THEN
    RAISE EXCEPTION 'Normal account received a deletion hint'; END IF;
  PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
  PERFORM public.request_account_deletion('delete');
  SELECT raw_app_meta_data INTO metadata FROM auth.users WHERE id=owner_id;
  IF metadata->>'account_deletion_pending' IS DISTINCT FROM 'true' OR metadata->>'keep' IS DISTINCT FROM 'intact'
    THEN RAISE EXCEPTION 'Deletion hint or unrelated metadata incorrect'; END IF;
  SELECT delete_at INTO first_deadline FROM public.account_deletion_requests WHERE user_id=owner_id;
  PERFORM public.request_account_deletion('delete');
  IF (SELECT delete_at FROM public.account_deletion_requests WHERE user_id=owner_id) <> first_deadline
    THEN RAISE EXCEPTION 'Retry extended deletion deadline'; END IF;
  PERFORM public.restore_pending_account(true);
  SELECT raw_app_meta_data INTO metadata FROM auth.users WHERE id=owner_id;
  IF metadata ? 'account_deletion_pending' OR metadata ? 'account_deletion_at' OR metadata->>'keep' IS DISTINCT FROM 'intact'
    THEN RAISE EXCEPTION 'Restore did not clear only the hint'; END IF;
  PERFORM public.request_account_deletion('delete');
  UPDATE public.account_deletion_requests SET delete_at=clock_timestamp()-interval '1 second' WHERE user_id=owner_id;
  IF public.account_deletion_status()->>'status' <> 'expired' THEN RAISE EXCEPTION 'Expired status incorrect'; END IF;
  BEGIN
    PERFORM public.restore_pending_account(true);
    RAISE EXCEPTION 'Expected expired restoration rejection';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Expected expired restoration rejection' THEN RAISE; END IF;
  END;
  DELETE FROM auth.users WHERE id=owner_id;
  IF EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE user_id=owner_id)
    THEN RAISE EXCEPTION 'Cascade deletion failed'; END IF;
END;
$$;
ROLLBACK;
'@
$testSql = $rollbackMigration + "`n" + $checks
if ($testSql -match '(?i)\bCOMMIT\b' -or $testSql -notmatch 'ROLLBACK;\s*$') { throw 'Test must only roll back' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('restore-hint-check-' + [guid]::NewGuid() + '.txt')
try {
  Set-Content -LiteralPath $stage -Value $testSql -Encoding utf8
  & npx.cmd supabase db query --linked --project-ref fjwdaccejrodpcicyxrc --file $stage
  if ($LASTEXITCODE -ne 0) { throw 'Restore hint DB checks failed' }
  Write-Output 'Normal, pending, restored, expired and cascade checks passed. All test changes rolled back.'
} finally {
  Remove-Item -LiteralPath $stage -ErrorAction SilentlyContinue
}
