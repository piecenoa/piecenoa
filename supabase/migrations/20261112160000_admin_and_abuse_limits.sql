-- PIECENOA stage 5: admin tools, abuse limits, consolidated read policies.
-- Rollback: supabase/rollback/20261112160000_admin_and_abuse_limits.down.sql

-- ---------------------------------------------------------------------------
-- One read policy per role (the performance advisor flagged overlapping ones).
-- Same rules as before, written as a single expression.
-- ---------------------------------------------------------------------------
drop policy "public listings are visible" on public.listings;
drop policy "owners see own listings" on public.listings;
drop policy "admins see all listings" on public.listings;
create policy "visitors see public listings" on public.listings for select to anon
  using (visibility = 'public' and moderation_status = 'active' and deleted_at is null);
create policy "members see public, own, or all as admin" on public.listings for select to authenticated
  using ((visibility = 'public' and moderation_status = 'active' and deleted_at is null)
         or seller_id = (select auth.uid()) or (select public.is_admin()));

drop policy "reporters see own reports" on public.reports;
drop policy "admins see reports" on public.reports;
create policy "reporters see own reports, admins see all" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select public.is_admin()));

drop policy "users see own sanction" on public.user_sanctions;
drop policy "admins see sanctions" on public.user_sanctions;
create policy "users see own sanction, admins see all" on public.user_sanctions for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Abuse limits: too many writes in a short time are refused with RATE_LIMIT.
-- Counted with elevated rights so the count is exact; SQL editor and admins are exempt.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_rate_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  short_count int;
  day_count int;
begin
  if uid is null or public.is_admin() then return new; end if;
  if tg_table_name = 'listings' then
    select count(*) filter (where created_at > now() - interval '10 minutes'), count(*) into short_count, day_count
      from public.listings where seller_id = uid and created_at > now() - interval '1 day';
    if short_count >= 5 or day_count >= 30 then raise exception 'RATE_LIMIT' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'messages' then
    select count(*) filter (where created_at > now() - interval '5 minutes'), count(*) into short_count, day_count
      from public.messages where sender_id = uid and created_at > now() - interval '1 day';
    if short_count >= 20 or day_count >= 300 then raise exception 'RATE_LIMIT' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'conversations' then
    select count(*) into short_count from public.conversations where buyer_id = uid and created_at > now() - interval '1 hour';
    if short_count >= 10 then raise exception 'RATE_LIMIT' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'reports' then
    select count(*) into day_count from public.reports where reporter_id = uid and created_at > now() - interval '1 day';
    if day_count >= 10 then raise exception 'RATE_LIMIT' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'favorites' then
    select count(*) into short_count from public.favorites where user_id = uid and created_at > now() - interval '1 hour';
    if short_count >= 120 then raise exception 'RATE_LIMIT' using errcode = 'P0001'; end if;
  end if;
  return new;
end $$;
revoke execute on function public.enforce_rate_limit() from public, anon, authenticated;
create trigger listings_rate_limit before insert on public.listings for each row execute function public.enforce_rate_limit();
create trigger messages_rate_limit before insert on public.messages for each row execute function public.enforce_rate_limit();
create trigger conversations_rate_limit before insert on public.conversations for each row execute function public.enforce_rate_limit();
create trigger reports_rate_limit before insert on public.reports for each row execute function public.enforce_rate_limit();
create trigger favorites_rate_limit before insert on public.favorites for each row execute function public.enforce_rate_limit();
create index if not exists listings_seller_created_idx on public.listings (seller_id, created_at desc);
create index if not exists messages_sender_created_idx on public.messages (sender_id, created_at desc);
create index if not exists reports_reporter_created_idx on public.reports (reporter_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Admin tools. Every function checks is_admin() itself; membership in admin_users can
-- only be changed from the SQL editor (service role), never through the API.
-- ---------------------------------------------------------------------------
create or replace function public.require_admin() returns void
language plpgsql stable security invoker set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
end $$;
revoke execute on function public.require_admin() from public, anon;
grant execute on function public.require_admin() to authenticated;

create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_admin();
  return jsonb_build_object(
    'members', (select count(*) from auth.users),
    'members_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'members_banned', (select count(*) from public.user_sanctions where lifted_at is null),
    'listings', (select count(*) from public.listings where deleted_at is null),
    'listings_public', (select count(*) from public.listings where deleted_at is null and visibility = 'public' and moderation_status = 'active'),
    'listings_private', (select count(*) from public.listings where deleted_at is null and visibility = 'private'),
    'listings_hidden', (select count(*) from public.listings where deleted_at is null and moderation_status = 'hidden'),
    'listings_7d', (select count(*) from public.listings where created_at > now() - interval '7 days'),
    'reports_open', (select count(*) from public.reports where status in ('open', 'reviewing')),
    'conversations', (select count(*) from public.conversations),
    'messages_7d', (select count(*) from public.messages where created_at > now() - interval '7 days'),
    'favorites', (select count(*) from public.favorites));
end $$;

create or replace function public.admin_members(p_search text default '', p_limit int default 50, p_offset int default 0)
returns table (id uuid, email text, display_name text, created_at timestamptz, last_sign_in_at timestamptz,
  email_confirmed boolean, listing_count bigint, is_admin boolean, banned boolean, ban_reason text)
language plpgsql stable security definer set search_path = '' as $$
declare
  term text := btrim(coalesce(p_search, ''));
begin
  perform public.require_admin();
  return query
    select u.id, u.email::text, p.display_name, u.created_at, u.last_sign_in_at, u.email_confirmed_at is not null,
      (select count(*) from public.listings l where l.seller_id = u.id and l.deleted_at is null),
      exists (select 1 from public.admin_users a where a.user_id = u.id),
      coalesce(s.lifted_at is null and s.user_id is not null, false), s.reason
    from auth.users u
    left join public.profiles p on p.id = u.id
    left join public.user_sanctions s on s.user_id = u.id
    where term = '' or u.email ilike '%' || term || '%' or p.display_name ilike '%' || term || '%'
    order by u.created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.admin_set_listing_hidden(p_listing uuid, p_hidden boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_admin();
  update public.listings set
    moderation_status = case when p_hidden then 'hidden' else 'active' end,
    moderation_reason = case when p_hidden then left(nullif(btrim(coalesce(p_reason, '')), ''), 500) end,
    moderated_at = now()
  where id = p_listing;
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
end $$;

create or replace function public.admin_set_member_ban(p_user uuid, p_banned boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
begin
  perform public.require_admin();
  if p_user = actor then raise exception 'CANNOT_BAN_SELF' using errcode = 'P0001'; end if;
  if exists (select 1 from public.admin_users a where a.user_id = p_user) then
    raise exception 'CANNOT_BAN_ADMIN' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_user) then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_banned then
    insert into public.user_sanctions (user_id, reason, banned_by, banned_at, lifted_at)
    values (p_user, coalesce(left(nullif(btrim(coalesce(p_reason, '')), ''), 500), 'Policy violation'), actor, now(), null)
    on conflict (user_id) do update set reason = excluded.reason, banned_by = excluded.banned_by, banned_at = now(), lifted_at = null;
    -- Suspended members' pieces leave the market until the sanction is lifted.
    update public.listings set moderation_status = 'hidden', moderation_reason = 'ACCOUNT_SUSPENDED', moderated_at = now()
    where seller_id = p_user and moderation_status = 'active';
  else
    update public.user_sanctions set lifted_at = now() where user_id = p_user and lifted_at is null;
    update public.listings set moderation_status = 'active', moderation_reason = null, moderated_at = now()
    where seller_id = p_user and moderation_reason = 'ACCOUNT_SUSPENDED';
  end if;
end $$;

create or replace function public.admin_update_report(p_report uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  closing boolean := p_status in ('resolved', 'dismissed');
begin
  perform public.require_admin();
  if p_status not in ('open', 'reviewing', 'resolved', 'dismissed') then
    raise exception 'VALIDATION' using errcode = 'P0001';
  end if;
  update public.reports set
    status = p_status,
    resolution_note = left(nullif(btrim(coalesce(p_note, '')), ''), 1000),
    resolved_by = case when closing then (select auth.uid()) end,
    resolved_at = case when closing then now() end
  where id = p_report;
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
end $$;

do $$
declare fn text;
begin
  foreach fn in array array['admin_stats()', 'admin_members(text, int, int)', 'admin_set_listing_hidden(uuid, boolean, text)',
                            'admin_set_member_ban(uuid, boolean, text)', 'admin_update_report(uuid, text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- The site owner is the first admin.
insert into public.admin_users (user_id, note)
select u.id, 'Site owner' from auth.users u where lower(u.email) = 'taemim2700@gmail.com'
on conflict (user_id) do nothing;
