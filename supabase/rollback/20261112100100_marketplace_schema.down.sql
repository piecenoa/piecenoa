-- Reverts 20261112100100_marketplace_schema.sql.
-- WARNING: drops favorites, reports, sanctions, admin rows and the new profile/listing
-- columns (bio, avatar, artwork details...). Run only in an emergency, after exporting data.
-- Listings priced in a currency other than KRW cannot be converted back and must be removed first.
-- Run in the Supabase SQL editor, then delete the row for version 20261112100100 from
-- supabase_migrations.schema_migrations.

-- Storage (the avatars bucket must be emptied from the dashboard first)
drop policy if exists "delete own avatar" on storage.objects;
drop policy if exists "read own avatar files" on storage.objects;
drop policy if exists "upload own avatar" on storage.objects;
delete from storage.buckets where id = 'avatars';
drop policy if exists "read own listing images" on storage.objects;

-- Reports, favorites
drop table if exists public.reports;
drop function if exists public.reports_fill_snapshot();
drop table if exists public.favorites;

-- Messages
drop policy if exists "recipients mark messages read" on public.messages;
drop policy if exists "participants send messages" on public.messages;
alter function public.is_participant(uuid) security definer;
alter function public.mark_conversation_read(uuid) security definer;
create policy "participants send messages" on public.messages for insert to authenticated
  with check ((select auth.uid()) = sender_id and read_at is null and public.is_participant(conversation_id));
drop trigger if exists messages_touch on public.messages;
drop index if exists public.messages_unread_idx;
drop index if exists public.messages_sender_client_idx;
alter table public.messages drop column if exists client_id, drop column if exists updated_at;
grant all on public.messages to anon, authenticated;

-- Conversations
drop function if exists public.open_conversation(uuid);
drop policy if exists "buyers start conversations" on public.conversations;
create policy "buyer starts conversation" on public.conversations for insert to authenticated with check (
  (select auth.uid()) = buyer_id
  and seller_id = (select l.seller_id from public.listings l where l.id = listing_id)
);
drop trigger if exists conversations_set_seller on public.conversations;
drop function if exists public.conversations_set_seller();
drop trigger if exists conversations_touch on public.conversations;
drop index if exists public.conversations_buyer_recent_idx;
drop index if exists public.conversations_seller_recent_idx;
create index if not exists conversations_buyer_idx on public.conversations (buyer_id);
create index if not exists conversations_seller_idx on public.conversations (seller_id);
alter table public.conversations drop column if exists updated_at;
grant all on public.conversations to anon, authenticated;

-- Listings
alter publication supabase_realtime drop table public.listings;
drop policy if exists "public listings are visible" on public.listings;
drop policy if exists "owners see own listings" on public.listings;
drop policy if exists "admins see all listings" on public.listings;
drop policy if exists "members create own listings" on public.listings;
drop policy if exists "owners update own listings" on public.listings;
drop trigger if exists listings_guard on public.listings;
drop function if exists public.listings_guard();
drop index if exists public.listings_public_feed_idx;
drop index if exists public.listings_category_created_idx;
drop index if exists public.listings_currency_price_idx;
drop index if exists public.listings_search_trgm_idx;
alter table public.listings
  drop column if exists search_text,
  drop constraint if exists listings_category_fkey,
  drop constraint if exists listings_image_owner_check,
  drop constraint if exists listings_location_text_check,
  drop constraint if exists listings_status_check,
  drop constraint if exists listings_price_minor_check;
alter table public.listings
  drop column if exists currency, drop column if exists country_code, drop column if exists artist,
  drop column if exists medium, drop column if exists dimensions, drop column if exists year,
  drop column if exists kind, drop column if exists condition, drop column if exists delivery,
  drop column if exists framed, drop column if exists negotiable, drop column if exists visibility,
  drop column if exists moderation_status, drop column if exists moderation_reason,
  drop column if exists moderated_at, drop column if exists deleted_at;
update public.listings set
  category = case category when 'painting' then '회화' when 'drawing' then '드로잉'
    when 'object' then '도자·오브제' when 'print' then '아트 프린트' else category end,
  status = case status when 'available' then '판매중' when 'reserved' then '예약중'
    when 'sold' then '판매완료' else status end,
  location_text = case when location_text in ('서울 성동구','서울 마포구','서울 종로구','서울 강남구','경기 성남시')
    then location_text else '기타 지역' end;
alter table public.listings alter column price_minor type integer;
alter table public.listings rename column price_minor to price;
alter table public.listings rename column location_text to region;
alter table public.listings alter column status set default '판매중';
alter table public.listings
  add constraint listings_price_check check (price between 0 and 999999999),
  add constraint listings_category_check check (category in ('회화','드로잉','도자·오브제','아트 프린트')),
  add constraint listings_status_check check (status in ('판매중','예약중','판매완료')),
  add constraint listings_region_check check (region in ('서울 성동구','서울 마포구','서울 종로구','서울 강남구','경기 성남시','기타 지역'));
create policy "listings are public" on public.listings for select to anon, authenticated using (true);
create policy "insert own listing" on public.listings for insert to authenticated with check ((select auth.uid()) = seller_id and image_path like (select auth.uid())::text || '/%');
create policy "update own listing" on public.listings for update to authenticated using ((select auth.uid()) = seller_id) with check ((select auth.uid()) = seller_id and image_path like (select auth.uid())::text || '/%');
create policy "delete own listing" on public.listings for delete to authenticated using ((select auth.uid()) = seller_id);
grant all on public.listings to anon, authenticated;

-- Profiles (restores the 20261112100000 definitions)
drop policy if exists "update own profile" on public.profiles;
drop trigger if exists profiles_touch on public.profiles;
alter function public.check_nickname(text) security definer;
create or replace function public.sync_display_name() returns trigger
language plpgsql set search_path to '' as $function$
begin new.display_name := coalesce(new.nickname, 'Member'); return new; end $function$;
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path to '' as $function$
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
alter table public.profiles
  drop constraint if exists profiles_avatar_path_check,
  drop column if exists bio, drop column if exists avatar_path, drop column if exists role,
  drop column if exists country_code, drop column if exists location_text,
  drop column if exists preferred_locale, drop column if exists updated_at;
grant all on public.profiles to anon, authenticated;

-- Reference data, sanctions, admins
drop table if exists public.currencies;
drop table if exists public.categories;
drop function if exists public.current_user_is_banned();
drop table if exists public.user_sanctions;
drop function if exists public.is_admin();
drop table if exists public.admin_users;
