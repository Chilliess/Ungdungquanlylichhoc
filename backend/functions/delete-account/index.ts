import { createClient } from 'npm:@supabase/supabase-js@2';
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    const authorization = req.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return json({ error: 'Unauthorized' }, 401);
    const caller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error } = await caller.auth.getUser();
    if (error || !user) return json({ error: 'Unauthorized' }, 401);
    const raw = await req.text();
    if (raw.length > 1000) return json({ error: 'Request too large' }, 413);
    const { action, confirmation } = JSON.parse(raw);
    // Former immediate-delete/OTP actions deliberately removed.
    if (action !== 'request' || confirmation !== 'delete') return json({ error: 'Invalid confirmation' }, 400);
    const result = await caller.rpc('request_account_deletion', { p_confirmation: confirmation });
    if (result.error) return json({ error: 'Could not request deletion' }, 409);
    return json(result.data);
  } catch { return json({ error: 'Request failed' }, 500); }
});
