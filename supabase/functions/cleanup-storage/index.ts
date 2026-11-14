// Daily cleanup for PIECENOA.
// 1. Permanently removes listings that were deleted more than 30 days ago.
// 2. Deletes photo files that no listing or profile uses any more (older than one day).
//
// Who may run it:
// - the scheduled job, which sends the header  x-cleanup-secret: <CLEANUP_SECRET>
// - a signed-in admin (the "Run cleanup" button on the admin page)
//
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
// Add CLEANUP_SECRET (a long random text) under Edge Functions -> Secrets.
// Deploy with "Verify JWT" turned off: this function checks the caller itself.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

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

// Compares two texts in constant time so the secret cannot be guessed from response timing.
function sameText(a: string, b: string) {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return diff === 0;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(origin) });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' }, origin);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const cleanupSecret = Deno.env.get('CLEANUP_SECRET') ?? '';
  if (!url || !anonKey || !serviceKey) return reply(500, { error: 'NOT_CONFIGURED' }, origin);

  // Who is calling?
  const givenSecret = req.headers.get('x-cleanup-secret') ?? '';
  let allowed = cleanupSecret.length >= 24 && givenSecret.length > 0 && sameText(givenSecret, cleanupSecret);
  if (!allowed) {
    const authorization = req.headers.get('Authorization') ?? '';
    if (authorization.startsWith('Bearer ')) {
      const asUser = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: isAdmin } = await asUser.rpc('is_admin');
      allowed = isAdmin === true;
    }
  }
  if (!allowed) return reply(401, { error: 'NOT_ALLOWED' }, origin);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1. Listings deleted more than 30 days ago.
  const { data: purged, error: purgeError } = await admin.rpc('purge_deleted_listings', { p_days: 30, p_limit: 200 });
  if (purgeError) {
    console.error('purge failed', purgeError);
    return reply(500, { error: 'PURGE_FAILED' }, origin);
  }

  // 2. Unused photo files (includes the photos of the listings removed above).
  const { data: candidates, error: listError } = await admin.rpc('storage_cleanup_candidates', { p_limit: 500 });
  if (listError) {
    console.error('listing files failed', listError);
    return reply(500, { error: 'LIST_FAILED' }, origin);
  }
  const byBucket = new Map<string, string[]>();
  for (const row of (candidates ?? []) as { bucket_id: string; name: string }[]) {
    if (!['listing-images', 'avatars'].includes(row.bucket_id)) continue;
    byBucket.set(row.bucket_id, [...(byBucket.get(row.bucket_id) ?? []), row.name]);
  }
  let filesRemoved = 0;
  for (const [bucket, paths] of byBucket) {
    for (let i = 0; i < paths.length; i += 100) {
      const batch = paths.slice(i, i + 100);
      const { error } = await admin.storage.from(bucket).remove(batch);
      if (error) {
        console.error('remove failed', bucket, error);
        return reply(500, { error: 'REMOVE_FAILED', listingsRemoved: purged ?? 0, filesRemoved }, origin);
      }
      filesRemoved += batch.length;
    }
  }

  const result = { ok: true, listingsRemoved: purged ?? 0, filesRemoved };
  console.log('cleanup done', result);
  return reply(200, result, origin);
});
