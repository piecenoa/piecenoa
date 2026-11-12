-- PIECENOA stage 2: paste this whole file into Supabase SQL Editor and press Run.
-- Everything runs in one transaction: if any line fails, nothing is changed.
begin;

-- ===== 20261112100000_record_nickname_feature.sql =====
-- Records changes that were made to the live database outside the migration history
-- (captured from the live schema on 2026-11-12). Every statement is idempotent, so
-- applying this to the live project changes nothing; applying it to a fresh database
-- recreates the same state.

alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists nickname_changed_at timestamptz;
create unique index if not exists profiles_nickname_unique
  on public.profiles (lower(nickname)) where nickname is not null;

-- Profile edits went through set_nickname() only.
drop policy if exists "update own profile" on public.profiles;

create or replace function public.nickname_rule_problem(value text)
 returns text
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  nick text := btrim(coalesce(value, ''));
  low text := lower(nick);
  word text;
begin
  if char_length(nick) < 2 or char_length(nick) > 16 then return 'length'; end if;
  if nick !~ '^[0-9A-Za-z가-힣._]+$' then return 'characters'; end if;
  if nick ~ '^[._]' or nick ~ '[._]$' or nick ~ '[._]{2}' then return 'symbols'; end if;
  if nick ~ '^[0-9]+$' then return 'numbers'; end if;
  foreach word in array array['admin','piecenoa','피스노아','관리자','운영자','운영진','운영팀','고객센터','시발','씨발','병신','좆','개새끼','fuck','shit'] loop
    if position(word in low) > 0 then return 'reserved'; end if;
  end loop;
  if low = any(array['root','staff','system','support','official','moderator','manager','member','guest','null','undefined','공식','매니저','회원','탈퇴회원']) then return 'reserved'; end if;
  return null;
end $function$;

create or replace function public.check_nickname(value text)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  nick text := btrim(coalesce(value, ''));
  problem text := public.nickname_rule_problem(nick);
  owner uuid;
begin
  if problem is not null then return problem; end if;
  select id into owner from public.profiles where lower(nickname) = lower(nick);
  if owner is null then return 'ok'; end if;
  if owner = (select auth.uid()) then return 'mine'; end if;
  return 'taken';
end $function$;

create or replace function public.set_nickname(value text)
 returns json
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  uid uuid := (select auth.uid());
  nick text := btrim(coalesce(value, ''));
  problem text := public.nickname_rule_problem(nick);
  current_nick text;
  changed timestamptz;
  next_change timestamptz;
begin
  if uid is null then raise exception 'NICK_AUTH' using errcode = 'P0001'; end if;
  if problem is not null then raise exception 'NICK_%', upper(problem) using errcode = 'P0001'; end if;
  select nickname, nickname_changed_at into current_nick, changed from public.profiles where id = uid for update;
  if not found then raise exception 'NICK_AUTH' using errcode = 'P0001'; end if;
  if current_nick = nick then raise exception 'NICK_SAME' using errcode = 'P0001'; end if;
  -- Changing only upper/lower case keeps the same nickname, so it is allowed any time.
  if current_nick is not null and lower(current_nick) <> lower(nick) then
    next_change := coalesce(changed, '-infinity'::timestamptz) + interval '30 days';
    if next_change > now() then
      raise exception 'NICK_COOLDOWN:%', to_char(next_change at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') using errcode = 'P0001';
    end if;
  end if;
  begin
    update public.profiles
      set nickname = nick,
          nickname_changed_at = case when current_nick is null or lower(current_nick) = lower(nick) then nickname_changed_at else now() end
      where id = uid;
  exception when unique_violation then
    raise exception 'NICK_TAKEN' using errcode = 'P0001';
  end;
  return json_build_object('nickname', nick, 'nickname_changed_at', (select p.nickname_changed_at from public.profiles p where p.id = uid));
end $function$;
revoke execute on function public.set_nickname(text) from public, anon;
grant execute on function public.set_nickname(text) to authenticated;

create or replace function public.sync_display_name()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin new.display_name := coalesce(new.nickname, 'Member'); return new; end $function$;
revoke execute on function public.sync_display_name() from public, anon, authenticated;
drop trigger if exists profiles_sync_display_name on public.profiles;
create trigger profiles_sync_display_name before insert or update on public.profiles
  for each row execute function public.sync_display_name();

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  wanted text := btrim(coalesce(new.raw_user_meta_data->>'nickname', ''));
begin
  insert into public.profiles (id) values (new.id);
  if wanted <> '' and public.nickname_rule_problem(wanted) is null then
    begin
      update public.profiles set nickname = wanted where id = new.id;
    exception when unique_violation then null;
    end;
  end if;
  return new;
end $function$;

-- ===== 20261112100100_marketplace_schema.sql =====
-- PIECENOA stage 2: global marketplace schema.
-- Keeps every existing row (1 profile, 0 listings/conversations/messages at the time of writing).
-- Rollback: supabase/rollback/20261112100100_marketplace_schema.down.sql

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admins and sanctions (written only from the SQL editor or service role)
-- ---------------------------------------------------------------------------
create table public.admin_users (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  granted_by uuid references public.profiles(id) on delete set null,
  note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index admin_users_granted_by_idx on public.admin_users (granted_by);
create trigger admin_users_touch before update on public.admin_users for each row execute function public.touch_updated_at();
alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to authenticated;
create policy "users see own admin row" on public.admin_users for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.is_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()));
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
-- No "admins see all admin rows" policy: it would call is_admin() on this same table
-- and recurse. Manage admins from the Supabase SQL editor.

create table public.user_sanctions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  banned_by uuid references public.profiles(id) on delete set null,
  banned_at timestamptz not null default now(),
  lifted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index user_sanctions_banned_by_idx on public.user_sanctions (banned_by);
create trigger user_sanctions_touch before update on public.user_sanctions for each row execute function public.touch_updated_at();
alter table public.user_sanctions enable row level security;
revoke all on public.user_sanctions from anon, authenticated;
grant select on public.user_sanctions to authenticated;
create policy "users see own sanction" on public.user_sanctions for select to authenticated
  using (user_id = (select auth.uid()));
create policy "admins see sanctions" on public.user_sanctions for select to authenticated
  using ((select public.is_admin()));

create or replace function public.current_user_is_banned() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.user_sanctions s
    where s.user_id = (select auth.uid()) and s.lifted_at is null
  );
$$;
revoke execute on function public.current_user_is_banned() from public, anon;
grant execute on function public.current_user_is_banned() to authenticated;

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
create table public.categories (
  code text primary key check (code ~ '^[a-z][a-z_]{1,30}$'),
  name_en text not null check (char_length(name_en) between 1 and 60),
  name_ko text not null check (char_length(name_ko) between 1 and 60),
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger categories_touch before update on public.categories for each row execute function public.touch_updated_at();
alter table public.categories enable row level security;
revoke all on public.categories from anon, authenticated;
grant select on public.categories to anon, authenticated;
create policy "categories are public" on public.categories for select to anon, authenticated using (true);
insert into public.categories (code, name_en, name_ko, sort_order) values
  ('painting', 'Painting', '회화', 10),
  ('drawing', 'Drawing', '드로잉', 20),
  ('object', 'Ceramics & objects', '도자·오브제', 30),
  ('print', 'Prints', '아트 프린트', 40);

create table public.currencies (
  code text primary key check (code ~ '^[A-Z]{3}$'),
  minor_unit smallint not null check (minor_unit between 0 and 3),
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger currencies_touch before update on public.currencies for each row execute function public.touch_updated_at();
alter table public.currencies enable row level security;
revoke all on public.currencies from anon, authenticated;
grant select on public.currencies to anon, authenticated;
create policy "currencies are public" on public.currencies for select to anon, authenticated using (true);
insert into public.currencies (code, minor_unit, sort_order) values
  ('USD', 2, 10), ('EUR', 2, 20), ('GBP', 2, 30), ('KRW', 0, 40), ('JPY', 0, 50),
  ('CNY', 2, 60), ('HKD', 2, 70), ('TWD', 2, 80), ('SGD', 2, 90), ('AUD', 2, 100),
  ('CAD', 2, 110), ('CHF', 2, 120);

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column bio text not null default '' check (char_length(bio) <= 240),
  add column avatar_path text,
  add column role text not null default 'artist' check (role in ('artist', 'collector', 'studio')),
  add column country_code text check (country_code ~ '^[A-Z]{2}$'),
  add column location_text text check (char_length(btrim(location_text)) between 1 and 80),
  add column preferred_locale text not null default 'en' check (preferred_locale in ('en', 'ko')),
  add column updated_at timestamptz not null default now();
alter table public.profiles add constraint profiles_avatar_path_check
  check (avatar_path is null or (char_length(avatar_path) <= 300 and avatar_path like id::text || '/%'));
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();

-- display_name is now the editable studio name. It still follows the nickname
-- while the member has not chosen a different name.
create or replace function public.sync_display_name() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.nickname is not null and coalesce(new.display_name, 'Member') = 'Member' then
      new.display_name := new.nickname;
    end if;
  elsif new.nickname is distinct from old.nickname
        and old.display_name = coalesce(old.nickname, 'Member') then
    new.display_name := coalesce(new.nickname, 'Member');
  end if;
  new.display_name := coalesce(nullif(btrim(new.display_name), ''), 'Member');
  return new;
end $$;
revoke execute on function public.sync_display_name() from public, anon, authenticated;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  wanted text := btrim(coalesce(new.raw_user_meta_data->>'nickname', ''));
  given text := btrim(left(regexp_replace(
    coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', ''),
    '[[:cntrl:]]', '', 'g'), 40));
begin
  insert into public.profiles (id, display_name) values (new.id, coalesce(nullif(given, ''), 'Member'));
  if wanted <> '' and public.nickname_rule_problem(wanted) is null then
    begin
      update public.profiles set nickname = wanted where id = new.id;
    exception when unique_violation then null;
    end;
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Nickname availability only reads public data, so it no longer needs elevated rights.
alter function public.check_nickname(text) security invoker;

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant update (display_name, bio, avatar_path, role, country_code, location_text, preferred_locale)
  on public.profiles to authenticated;
create policy "update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Listings (artworks)
-- ---------------------------------------------------------------------------
drop policy "listings are public" on public.listings;
drop policy "insert own listing" on public.listings;
drop policy "update own listing" on public.listings;
drop policy "delete own listing" on public.listings;

alter table public.listings
  drop constraint listings_category_check,
  drop constraint listings_status_check,
  drop constraint listings_region_check,
  drop constraint listings_price_check;

update public.listings set
  category = case category when '회화' then 'painting' when '드로잉' then 'drawing'
    when '도자·오브제' then 'object' when '아트 프린트' then 'print' else category end,
  status = case status when '판매중' then 'available' when '예약중' then 'reserved'
    when '판매완료' then 'sold' else status end;

alter table public.listings rename column price to price_minor;
alter table public.listings rename column region to location_text;
alter table public.listings alter column price_minor type bigint;
alter table public.listings alter column status set default 'available';

alter table public.listings
  add column currency text not null default 'KRW' references public.currencies(code),
  add column country_code text check (country_code ~ '^[A-Z]{2}$'),
  add column artist text not null default '' check (char_length(artist) <= 80),
  add column medium text not null default '' check (char_length(medium) <= 80),
  add column dimensions text not null default '' check (char_length(dimensions) <= 50),
  add column year smallint check (year between 1000 and 2100),
  add column kind text not null default 'original' check (kind in ('original', 'edition', 'reproduction')),
  add column condition text not null default 'good' check (condition in ('new', 'good', 'vintage')),
  add column delivery text not null default 'either' check (delivery in ('meetup', 'shipping', 'either')),
  add column framed text not null default 'unknown' check (framed in ('yes', 'no', 'unknown')),
  add column negotiable boolean not null default false,
  add column visibility text not null default 'public' check (visibility in ('public', 'private')),
  add column moderation_status text not null default 'active' check (moderation_status in ('active', 'hidden')),
  add column moderation_reason text check (char_length(moderation_reason) <= 500),
  add column moderated_at timestamptz,
  add column deleted_at timestamptz;
-- Existing rows (if any) were KRW; new rows must state their currency.
alter table public.listings alter column currency drop default;

alter table public.listings
  add constraint listings_price_minor_check check (price_minor between 0 and 1000000000000),
  add constraint listings_status_check check (status in ('available', 'reserved', 'sold')),
  add constraint listings_location_text_check check (char_length(btrim(location_text)) between 1 and 80),
  add constraint listings_image_owner_check check (image_path like seller_id::text || '/%'),
  add constraint listings_category_fkey foreign key (category) references public.categories(code) on update cascade;

alter table public.listings add column search_text text generated always as (
  lower(title || ' ' || artist || ' ' || medium || ' ' || location_text || ' ' || description)
) stored;

create index listings_public_feed_idx on public.listings (created_at desc)
  where visibility = 'public' and moderation_status = 'active' and deleted_at is null;
create index listings_category_created_idx on public.listings (category, created_at desc);
create index listings_currency_price_idx on public.listings (currency, price_minor);
create index listings_search_trgm_idx on public.listings using gin (search_text extensions.gin_trgm_ops);

create or replace function public.listings_guard() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if old.deleted_at is not null and new.deleted_at is null and not public.is_admin() then
    raise exception 'LISTING_DELETED' using errcode = 'P0001';
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    new.deleted_at := now();
  end if;
  return new;
end $$;
revoke execute on function public.listings_guard() from public, anon, authenticated;
create trigger listings_guard before update on public.listings for each row execute function public.listings_guard();

revoke all on public.listings from anon, authenticated;
grant select on public.listings to anon, authenticated;
grant insert (title, description, price_minor, currency, category, location_text, country_code, status,
  image_path, artist, medium, dimensions, year, kind, condition, delivery, framed, negotiable, visibility)
  on public.listings to authenticated;
grant update (title, description, price_minor, currency, category, location_text, country_code, status,
  image_path, artist, medium, dimensions, year, kind, condition, delivery, framed, negotiable, visibility,
  deleted_at)
  on public.listings to authenticated;

create policy "public listings are visible" on public.listings for select to anon, authenticated
  using (visibility = 'public' and moderation_status = 'active' and deleted_at is null);
-- Owners also see their soft-deleted rows; the app filters them out. Keeping them
-- visible lets the soft-delete UPDATE pass PostgreSQL's new-row visibility check.
create policy "owners see own listings" on public.listings for select to authenticated
  using (seller_id = (select auth.uid()));
create policy "admins see all listings" on public.listings for select to authenticated
  using ((select public.is_admin()));
create policy "members create own listings" on public.listings for insert to authenticated
  with check (seller_id = (select auth.uid()) and not (select public.current_user_is_banned()));
create policy "owners update own listings" on public.listings for update to authenticated
  using (seller_id = (select auth.uid()) and deleted_at is null)
  with check (seller_id = (select auth.uid()));
-- No delete policy: members soft-delete with deleted_at so buyers keep their inquiry history.

alter publication supabase_realtime add table public.listings;

-- ---------------------------------------------------------------------------
-- Favorites
-- ---------------------------------------------------------------------------
create table public.favorites (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);
create index favorites_listing_idx on public.favorites (listing_id);
create index favorites_user_created_idx on public.favorites (user_id, created_at desc);
create trigger favorites_touch before update on public.favorites for each row execute function public.touch_updated_at();
alter table public.favorites enable row level security;
revoke all on public.favorites from anon, authenticated;
grant select, delete on public.favorites to authenticated;
grant insert (listing_id) on public.favorites to authenticated;
create policy "users see own favorites" on public.favorites for select to authenticated
  using (user_id = (select auth.uid()));
create policy "users save visible listings" on public.favorites for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.listings l
      where l.id = listing_id and l.visibility = 'public'
        and l.moderation_status = 'active' and l.deleted_at is null
    )
  );
create policy "users remove own favorites" on public.favorites for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Conversations and messages
-- ---------------------------------------------------------------------------
alter table public.conversations add column updated_at timestamptz not null default now();
create trigger conversations_touch before update on public.conversations for each row execute function public.touch_updated_at();
drop index public.conversations_buyer_idx;
drop index public.conversations_seller_idx;
create index conversations_buyer_recent_idx on public.conversations (buyer_id, last_message_at desc);
create index conversations_seller_recent_idx on public.conversations (seller_id, last_message_at desc);

create or replace function public.conversations_set_seller() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  select l.seller_id into new.seller_id from public.listings l where l.id = new.listing_id;
  return new;
end $$;
revoke execute on function public.conversations_set_seller() from public, anon, authenticated;
create trigger conversations_set_seller before insert on public.conversations
  for each row execute function public.conversations_set_seller();

drop policy "buyer starts conversation" on public.conversations;
create policy "buyers start conversations" on public.conversations for insert to authenticated
  with check (
    buyer_id = (select auth.uid())
    and not (select public.current_user_is_banned())
    and exists (
      select 1 from public.listings l
      where l.id = listing_id and l.seller_id = conversations.seller_id
        and l.visibility = 'public' and l.moderation_status = 'active' and l.deleted_at is null
    )
  );
revoke all on public.conversations from anon, authenticated;
grant select on public.conversations to authenticated;
grant insert (listing_id) on public.conversations to authenticated;

create or replace function public.open_conversation(p_listing uuid) returns public.conversations
language plpgsql security invoker set search_path = '' as $$
declare
  result public.conversations;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode = 'P0001'; end if;
  -- An existing thread stays reachable even if the listing later became private.
  select * into result from public.conversations c
    where c.listing_id = p_listing and c.buyer_id = (select auth.uid());
  if result.id is not null then return result; end if;
  insert into public.conversations (listing_id) values (p_listing)
    on conflict (listing_id, buyer_id) do nothing;
  select * into result from public.conversations c
    where c.listing_id = p_listing and c.buyer_id = (select auth.uid());
  if result.id is null then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
  return result;
end $$;
revoke execute on function public.open_conversation(uuid) from public, anon;
grant execute on function public.open_conversation(uuid) to authenticated;

alter table public.messages
  add column client_id uuid,
  add column updated_at timestamptz not null default now();
create unique index messages_sender_client_idx on public.messages (sender_id, client_id) where client_id is not null;
create index messages_unread_idx on public.messages (conversation_id) where read_at is null;
create trigger messages_touch before update on public.messages for each row execute function public.touch_updated_at();

alter function public.is_participant(uuid) security invoker;

drop policy "participants send messages" on public.messages;
create policy "participants send messages" on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and not (select public.current_user_is_banned())
    and public.is_participant(conversation_id)
  );
create policy "recipients mark messages read" on public.messages for update to authenticated
  using (sender_id <> (select auth.uid()) and public.is_participant(conversation_id))
  with check (sender_id <> (select auth.uid()) and public.is_participant(conversation_id));
revoke all on public.messages from anon, authenticated;
grant select on public.messages to authenticated;
grant insert (conversation_id, body, client_id) on public.messages to authenticated;
grant update (read_at) on public.messages to authenticated;

alter function public.mark_conversation_read(uuid) security invoker;

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid default auth.uid() references public.profiles(id) on delete set null,
  target_type text not null check (target_type in ('listing', 'profile', 'message')),
  listing_id uuid references public.listings(id) on delete set null,
  profile_id uuid references public.profiles(id) on delete set null,
  message_id uuid references public.messages(id) on delete set null,
  reason text not null check (reason in ('spam', 'scam', 'counterfeit', 'prohibited', 'offensive', 'other')),
  details text not null default '' check (char_length(details) <= 1000),
  snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  resolution_note text check (char_length(resolution_note) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Targets may later be removed (set null), so only "at most one" is enforced here;
  -- the insert policy requires exactly one.
  check (num_nonnulls(listing_id, profile_id, message_id) <= 1),
  check ((listing_id is null or target_type = 'listing')
     and (profile_id is null or target_type = 'profile')
     and (message_id is null or target_type = 'message'))
);
create index reports_status_created_idx on public.reports (status, created_at desc);
create index reports_reporter_idx on public.reports (reporter_id);
create index reports_listing_idx on public.reports (listing_id);
create index reports_profile_idx on public.reports (profile_id);
create index reports_message_idx on public.reports (message_id);
create index reports_resolved_by_idx on public.reports (resolved_by);
create unique index reports_one_open_per_target_idx
  on public.reports (reporter_id, target_type, coalesce(listing_id, profile_id, message_id))
  where status in ('open', 'reviewing');
create trigger reports_touch before update on public.reports for each row execute function public.touch_updated_at();

-- Keeps a copy of what was reported, read with the reporter's own permissions,
-- so moderators can review it without access to private conversations.
create or replace function public.reports_fill_snapshot() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  new.snapshot := case new.target_type
    when 'listing' then (select jsonb_build_object('title', l.title, 'description', l.description,
      'image_path', l.image_path, 'seller_id', l.seller_id) from public.listings l where l.id = new.listing_id)
    when 'profile' then (select jsonb_build_object('display_name', p.display_name, 'bio', p.bio,
      'avatar_path', p.avatar_path) from public.profiles p where p.id = new.profile_id)
    when 'message' then (select jsonb_build_object('body', m.body, 'sender_id', m.sender_id,
      'conversation_id', m.conversation_id, 'created_at', m.created_at) from public.messages m where m.id = new.message_id)
  end;
  if new.snapshot is null then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
  return new;
end $$;
revoke execute on function public.reports_fill_snapshot() from public, anon, authenticated;
create trigger reports_fill_snapshot before insert on public.reports
  for each row execute function public.reports_fill_snapshot();

alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;
grant insert (target_type, listing_id, profile_id, message_id, reason, details) on public.reports to authenticated;
create policy "members file reports" on public.reports for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and not (select public.current_user_is_banned())
    and num_nonnulls(listing_id, profile_id, message_id) = 1
  );
create policy "reporters see own reports" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()));
create policy "admins see reports" on public.reports for select to authenticated
  using ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
-- Removing a file needs SELECT as well as DELETE on storage.objects.
create policy "read own listing images" on storage.objects for select to authenticated
  using (bucket_id = 'listing-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']);
create policy "upload own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "read own avatar files" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "delete own avatar" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Record both migrations in the migration history.
insert into supabase_migrations.schema_migrations (version, name, created_by) values
  ('20261112100000', 'record_nickname_feature', 'sql-editor'),
  ('20261112100100', 'marketplace_schema', 'sql-editor')
on conflict (version) do nothing;

commit;

-- Expected result: Success. No rows returned
