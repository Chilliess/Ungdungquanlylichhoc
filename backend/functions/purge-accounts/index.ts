import { createClient } from 'npm:@supabase/supabase-js@2';

// Scheduled worker only. A user JWT cannot authorize this endpoint.
Deno.serve(async (req) => {
  const secret = Deno.env.get('ACCOUNT_DELETION_CRON_SECRET');
  if (req.method !== 'POST' || !secret || req.headers.get('x-cron-secret') !== secret) {
    return new Response('Unauthorized', { status: 401 });
  }
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc('claim_expired_account_deletions');
  if (error) return Response.json({ error: 'Unable to claim deletions' }, { status: 500 });
  let deleted = 0, failed = 0;
  for (const row of data ?? []) {
    // Auth deletion cascades app data. Failed deletions stay locked and are retried.
    const { error } = await admin.auth.admin.deleteUser(row.user_id, false);
    if (error) { failed++; } else { deleted++; }
  }
  return Response.json({ deleted, failed }, { status: failed ? 500 : 200 });
});
