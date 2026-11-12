-- Copied verbatim from supabase_migrations.schema_migrations (version 20261111110825).
-- Already applied to project piecenoa-market. Do not edit.

-- Profiles
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Member' check (char_length(btrim(display_name)) between 1 and 40),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles are public" on public.profiles for select to anon, authenticated using (true);
create policy "update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(nullif(btrim(new.raw_user_meta_data->>'name'),''), nullif(btrim(new.raw_user_meta_data->>'full_name'),''), split_part(new.email,'@',1), 'Member'), 40));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Listings
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 2 and 60),
  description text not null check (char_length(btrim(description)) between 10 and 2000),
  price integer not null check (price between 0 and 999999999),
  category text not null check (category in ('회화','드로잉','도자·오브제','아트 프린트')),
  region text not null check (region in ('서울 성동구','서울 마포구','서울 종로구','서울 강남구','경기 성남시','기타 지역')),
  status text not null default '판매중' check (status in ('판매중','예약중','판매완료')),
  image_path text not null check (char_length(image_path) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index listings_created_idx on public.listings (created_at desc);
create index listings_seller_idx on public.listings (seller_id);
alter table public.listings enable row level security;
create policy "listings are public" on public.listings for select to anon, authenticated using (true);
create policy "insert own listing" on public.listings for insert to authenticated with check ((select auth.uid()) = seller_id and image_path like (select auth.uid())::text || '/%');
create policy "update own listing" on public.listings for update to authenticated using ((select auth.uid()) = seller_id) with check ((select auth.uid()) = seller_id and image_path like (select auth.uid())::text || '/%');
create policy "delete own listing" on public.listings for delete to authenticated using ((select auth.uid()) = seller_id);

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;
create trigger listings_touch before update on public.listings for each row execute function public.touch_updated_at();

-- Conversations
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  buyer_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (listing_id, buyer_id),
  check (buyer_id <> seller_id)
);
create index conversations_buyer_idx on public.conversations (buyer_id);
create index conversations_seller_idx on public.conversations (seller_id);
alter table public.conversations enable row level security;
create policy "participants read conversations" on public.conversations for select to authenticated using ((select auth.uid()) in (buyer_id, seller_id));
create policy "buyer starts conversation" on public.conversations for insert to authenticated with check (
  (select auth.uid()) = buyer_id
  and seller_id = (select l.seller_id from public.listings l where l.id = listing_id)
);

-- Messages
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);
create index messages_sender_idx on public.messages (sender_id);
alter table public.messages enable row level security;

create or replace function public.is_participant(conv uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.conversations c where c.id = conv and (select auth.uid()) in (c.buyer_id, c.seller_id));
$$;
revoke execute on function public.is_participant(uuid) from public, anon;
grant execute on function public.is_participant(uuid) to authenticated;

create policy "participants read messages" on public.messages for select to authenticated using (public.is_participant(conversation_id));
create policy "participants send messages" on public.messages for insert to authenticated with check ((select auth.uid()) = sender_id and read_at is null and public.is_participant(conversation_id));

create or replace function public.bump_conversation() returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.conversations set last_message_at = new.created_at where id = new.conversation_id; return new; end $$;
create trigger messages_bump after insert on public.messages for each row execute function public.bump_conversation();

create or replace function public.mark_conversation_read(conv uuid) returns void
language sql security definer set search_path = '' as $$
  update public.messages set read_at = now()
  where conversation_id = conv and read_at is null and sender_id <> (select auth.uid()) and public.is_participant(conv);
$$;
revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.bump_conversation() from public, anon, authenticated;

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;

-- Storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-images', 'listing-images', true, 3145728, array['image/jpeg','image/png','image/webp']);
create policy "upload own listing images" on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "delete own listing images" on storage.objects for delete to authenticated
  using (bucket_id = 'listing-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
