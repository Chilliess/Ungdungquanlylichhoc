$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sql = Get-Content -LiteralPath (Join-Path $root 'supabase_database.sql') -Raw
$start = $sql.IndexOf('-- WORKSPACE_CLOUD_SYNC:')
if ($start -lt 0) { throw 'Migration marker missing' }
$end = $sql.IndexOf('-- CALENDAR_EXAM_CREATE_FIX:', $start)
$block = if ($end -ge 0) { $sql.Substring($start, $end - $start) } else { $sql.Substring($start) }
$migration = $block -replace '(?i)COMMIT;\s*$', ''
$checks = @'
DO $$
DECLARE a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); foreign_s uuid:=gen_random_uuid(); rows jsonb;
BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
  VALUES(a,'sync-a-'||a||'@example.invalid','{}',now(),now()),(b,'sync-b-'||b||'@example.invalid','{}',now(),now());
  INSERT INTO public.subjects(id,user_id,subject_name,subject_code)
  VALUES(s,a,'Sync test','SYNC-A'),(foreign_s,b,'Private subject','SYNC-B');
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  SET LOCAL ROLE authenticated;
  rows:=public.sync_workspace_items('tasks',jsonb_build_array(jsonb_build_object('id','one','payload',jsonb_build_object('title','own','subjectId',s),'overwrite',true)));
  IF jsonb_array_length(rows)<>1 OR rows->0->'payload'->>'subjectId'<>s::text THEN RAISE EXCEPTION 'Own subject sync failed'; END IF;
  BEGIN
    PERFORM public.sync_workspace_items('tasks',jsonb_build_array(jsonb_build_object('id','bad','payload',jsonb_build_object('subjectId',foreign_s),'overwrite',true)));
    RAISE EXCEPTION 'Foreign subject was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='Foreign subject was accepted' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.workspace_items(user_id,collection,item_id,payload) VALUES(b,'tasks','attack','{}');
    RAISE EXCEPTION 'Direct write was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM public.sync_workspace_items('tasks','[{"id":"one","deleted":true,"overwrite":true}]');
  rows:=public.sync_workspace_items('tasks','[{"id":"one","payload":{"title":"stale"},"overwrite":false}]');
  IF rows->0->>'deleted'<>'true' THEN RAISE EXCEPTION 'Migration resurrected deletion'; END IF;
  PERFORM public.sync_workspace_items('chat','[{"id":"thread","payload":{"messages":[]},"overwrite":true}]');
  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  IF jsonb_array_length(public.sync_workspace_items('tasks'))<>0 OR (SELECT count(*) FROM public.workspace_items)<>0 THEN
    RAISE EXCEPTION 'Other account data exposed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM public.sync_workspace_items('tasks',jsonb_build_array(jsonb_build_object('id','linked','payload',jsonb_build_object('subjectId',s),'overwrite',true)));
  RESET ROLE;
  DELETE FROM public.subjects WHERE id=s;
  SET LOCAL ROLE authenticated;
  rows:=public.sync_workspace_items('tasks');
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) r WHERE r->>'id'='linked' AND r->'payload'->'subjectId'='null'::jsonb) THEN
    RAISE EXCEPTION 'Deleted subject lost its task'; END IF;
  PERFORM public.request_account_deletion('delete');
  BEGIN
    PERFORM public.sync_workspace_items('chat');
    RAISE EXCEPTION 'Pending account was accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='Pending account was accepted' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM public.workspace_items)<>0 THEN RAISE EXCEPTION 'Inactive RLS failed'; END IF;
  RESET ROLE;
  DELETE FROM auth.users WHERE id=a;
  IF EXISTS(SELECT 1 FROM public.workspace_items WHERE user_id=a) THEN RAISE EXCEPTION 'Cascade failed'; END IF;
END;
$$;
ROLLBACK;
'@
$testSql = $migration + "`n" + $checks
if ($testSql -match '(?i)\bCOMMIT\b' -or $testSql -notmatch 'ROLLBACK;\s*$') { throw 'Test must only roll back' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('workspace-sync-check-' + [guid]::NewGuid() + '.txt')
try {
  Set-Content -LiteralPath $stage -Value $testSql -Encoding utf8
  & npx.cmd supabase db query --linked --project-ref fjwdaccejrodpcicyxrc --file $stage
  if ($LASTEXITCODE -ne 0) { throw 'Workspace database checks failed' }
  Write-Output 'Workspace ownership, migration, deletion, FK and active-account checks passed; rolled back.'
} finally { Remove-Item -LiteralPath $stage -ErrorAction SilentlyContinue }
