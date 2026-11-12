-- PIECENOA: align the database with the piecenoa-2 frontend contract.
-- Adds 8 currencies and 4 categories, allows "unknown" artwork details, keeps public
-- favorite/conversation counts on each listing, and creates a conversation together with
-- its first message in one transaction. Keeps every existing row.
-- Rollback: supabase/rollback/20261112140000_piecenoa2_contract.down.sql

-- Currencies used by the frontend (MARKET_CURRENCIES).
insert into public.currencies (code, minor_unit, sort_order) values
  ('INR', 2, 130), ('NZD', 2, 140), ('AED', 2, 150), ('BRL', 2, 160),
  ('MXN', 2, 170), ('THB', 2, 180), ('VND', 0, 190), ('RUB', 2, 200)
on conflict (code) do nothing;

-- Categories used by the frontend (ART_CATEGORIES), in its order.
insert into public.categories (code, name_en, name_ko, sort_order) values
  ('photography', 'Photography', '사진', 40),
  ('sculpture', 'Sculpture', '조각·입체', 50),
  ('jewelry', 'Jewelry', '주얼리', 70),
  ('mixed', 'Mixed Media & Other', '복합·기타', 80)
on conflict (code) do nothing;
update public.categories c set name_en = v.name_en, name_ko = v.name_ko, sort_order = v.sort_order
from (values
  ('painting', 'Painting', '그림·회화', 10),
  ('drawing', 'Drawing & Calligraphy', '드로잉·서예', 20),
  ('print', 'Prints & Posters', '판화·포스터', 30),
  ('object', 'Craft & Ceramics', '공예·도자', 60)
) as v(code, name_en, name_ko, sort_order)
where c.code = v.code;

-- Artwork details the seller may leave as "unknown".
alter table public.listings
  drop constraint listings_kind_check,
  drop constraint listings_condition_check,
  drop constraint listings_delivery_check;
alter table public.listings
  add constraint listings_kind_check check (kind in ('unknown', 'original', 'edition', 'reproduction')),
  add constraint listings_condition_check check (condition in ('unknown', 'new', 'good', 'vintage')),
  add constraint listings_delivery_check check (delivery in ('unknown', 'meetup', 'shipping', 'either'));

-- Public engagement counts. Members cannot write these columns; triggers keep them exact.
alter table public.listings
  add column favorite_count integer not null default 0 check (favorite_count >= 0),
  add column conversation_count integer not null default 0 check (conversation_count >= 0);
create index listings_public_popular_idx on public.listings (favorite_count desc, created_at desc)
  where visibility = 'public' and moderation_status = 'active' and deleted_at is null;

create or replace function public.refresh_listing_counts(p_listing uuid) returns void
language sql security definer set search_path = '' as $$
  update public.listings l set
    favorite_count = (select count(*) from public.favorites f where f.listing_id = l.id),
    conversation_count = (select count(*) from public.conversations c where c.listing_id = l.id
      and exists (select 1 from public.messages m where m.conversation_id = c.id))
  where l.id = p_listing;
$$;
revoke execute on function public.refresh_listing_counts(uuid) from public, anon, authenticated;

create or replace function public.favorites_refresh_counts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_listing_counts(coalesce(new.listing_id, old.listing_id));
  return null;
end $$;
revoke execute on function public.favorites_refresh_counts() from public, anon, authenticated;
create trigger favorites_refresh_counts after insert or delete on public.favorites
  for each row execute function public.favorites_refresh_counts();

create or replace function public.messages_refresh_counts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_listing_counts((select c.listing_id from public.conversations c where c.id = new.conversation_id));
  return null;
end $$;
revoke execute on function public.messages_refresh_counts() from public, anon, authenticated;
create trigger messages_refresh_counts after insert on public.messages
  for each row execute function public.messages_refresh_counts();

-- A count change is not an edit: keep updated_at for real changes only.
create or replace function public.listings_touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
declare
  ignored text[] := array['favorite_count', 'conversation_count', 'updated_at', 'search_text'];
begin
  if (to_jsonb(new) - ignored) is distinct from (to_jsonb(old) - ignored) then
    new.updated_at := now();
  end if;
  return new;
end $$;
revoke execute on function public.listings_touch_updated_at() from public, anon, authenticated;
drop trigger listings_touch on public.listings;
create trigger listings_touch before update on public.listings
  for each row execute function public.listings_touch_updated_at();

update public.listings l set
  favorite_count = (select count(*) from public.favorites f where f.listing_id = l.id),
  conversation_count = (select count(*) from public.conversations c where c.listing_id = l.id
    and exists (select 1 from public.messages m where m.conversation_id = c.id));

-- First inquiry: create (or reuse) the conversation and save the first message together.
-- Runs with the caller's own permissions, so every row level security rule still applies.
create or replace function public.start_conversation(p_listing uuid, p_body text, p_client_id uuid default null)
returns public.conversations
language plpgsql security invoker set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  body text := btrim(coalesce(p_body, ''));
  result public.conversations;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode = 'P0001'; end if;
  if char_length(body) < 1 or char_length(body) > 500 then raise exception 'VALIDATION' using errcode = 'P0001'; end if;
  select * into result from public.conversations c where c.listing_id = p_listing and c.buyer_id = uid;
  if result.id is null then
    insert into public.conversations (listing_id) values (p_listing) on conflict (listing_id, buyer_id) do nothing;
    select * into result from public.conversations c where c.listing_id = p_listing and c.buyer_id = uid;
    if result.id is null then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
  end if;
  insert into public.messages (conversation_id, body, client_id) values (result.id, body, p_client_id)
    on conflict do nothing;
  select * into result from public.conversations c where c.id = result.id;
  return result;
end $$;
revoke execute on function public.start_conversation(uuid, text, uuid) from public, anon;
grant execute on function public.start_conversation(uuid, text, uuid) to authenticated;

-- The frontend must never create an empty conversation; retire the old entry point.
revoke execute on function public.open_conversation(uuid) from authenticated;
