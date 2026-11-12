// Deletes the signed-in user's account.
// The caller is identified from their own access token; nobody can delete another account.
// Order: remove the user's files from storage, then delete the auth user. Deleting the
// auth user cascades to profiles -> listings -> conversations/messages/favorites.
//
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided to
// Edge Functions automatically. The service role key never leaves this server function.
// Optional secret ALLOWED_ORIGINS: comma-separated site origins allowed to call this
// function from a browser (for example "https://piecenoa.com,http://localhost:3000").
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const BUCKETS = ['listing-images', 'avatars'];
const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? 'http://localhost:3000')
  .split(',').map((value) => value.trim()).filter(Boolean);

function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
  if (origin && allowedOrigins.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
}

function reply(status: number, body: unknown, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json' },
  });
}

async function removeFolder(admin: ReturnType<typeof createClient>, bucket: string, folder: string) {
  // Files live directly under "<user id>/". Remove them a page at a time.
  for (let round = 0; round < 50; round++) {
    const { data, error } = await admin.storage.from(bucket).list(folder, { limit: 100 });
    if (error) throw error;
    if (!data?.length) return;
    const paths = data.filter((item) => item.id).map((item) => `${folder}/${item.name}`);
    if (!paths.length) return;
    const { error: removeError } = await admin.storage.from(bucket).remove(paths);
    if (removeError) throw removeError;
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(origin) });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' }, origin);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return reply(500, { error: 'NOT_CONFIGURED' }, origin);

  const authorization = req.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return reply(401, { error: 'AUTH_REQUIRED' }, origin);

  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await asUser.auth.getUser();
  if (userError || !user) return reply(401, { error: 'AUTH_REQUIRED' }, origin);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    for (const bucket of BUCKETS) await removeFolder(admin, bucket, user.id);
  } catch (error) {
    console.error('storage cleanup failed', user.id, error);
    return reply(500, { error: 'STORAGE_CLEANUP_FAILED' }, origin);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error('delete user failed', user.id, deleteError);
    return reply(500, { error: 'DELETE_FAILED' }, origin);
  }
  return reply(200, { ok: true }, origin);
});
