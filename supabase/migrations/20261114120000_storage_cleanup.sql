-- PIECENOA: automatic cleanup, run by the cleanup-storage server function (daily, or from the admin page).
-- 1. Listings deleted more than 30 days ago are removed for good (their chats keep the title snapshot).
-- 2. Photo files that no listing or profile uses any more, and that are older than a day, are found
--    so the server function can delete them through the Storage API.
-- Both functions can only be called with the service role (inside the server function), never from the site.

create or replace function public.purge_deleted_listings(p_days int default 30, p_limit int default 200)
returns integer
language plpgsql security invoker set search_path = '' as $$
declare
  removed integer;
begin
  with doomed as (
    select l.id from public.listings l
    where l.deleted_at is not null and l.deleted_at < now() - make_interval(days => greatest(p_days, 1))
    order by l.deleted_at
    limit least(greatest(p_limit, 1), 1000)
  )
  delete from public.listings l using doomed where l.id = doomed.id;
  get diagnostics removed = row_count;
  return removed;
end $$;
revoke execute on function public.purge_deleted_listings(int, int) from public, anon, authenticated;
grant execute on function public.purge_deleted_listings(int, int) to service_role;

create or replace function public.storage_cleanup_candidates(p_limit int default 500)
returns table (bucket_id text, name text)
language sql stable security invoker set search_path = '' as $$
  select o.bucket_id, o.name
  from storage.objects o
  where o.bucket_id in ('listing-images', 'avatars')
    and o.created_at < now() - interval '1 day'
    and not (o.bucket_id = 'listing-images' and exists (select 1 from public.listings l where l.image_path = o.name))
    and not (o.bucket_id = 'avatars' and exists (select 1 from public.profiles p where p.avatar_path = o.name))
  order by o.created_at
  limit least(greatest(p_limit, 1), 1000);
$$;
revoke execute on function public.storage_cleanup_candidates(int) from public, anon, authenticated;
grant execute on function public.storage_cleanup_candidates(int) to service_role;
