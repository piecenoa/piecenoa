-- PIECENOA: member blocking, and chat history that survives account deletion.
--
-- 1. When a member deletes their account, the other person keeps the chat history.
--    The departed member's id becomes NULL (shown as "Deleted member"), their messages stay,
--    and nobody can send new messages in that chat. A chat where both people have left is removed.
-- 2. Members can block another member. Blocking stops new chats and messages in both directions.
--    Only the blocker can see their own block list.

-- ---------------------------------------------------------------------------
-- 1. Keep chats when a member leaves
-- ---------------------------------------------------------------------------
alter table public.conversations
  add column if not exists listing_title text check (char_length(listing_title) <= 60);

update public.conversations c set listing_title = l.title
from public.listings l where l.id = c.listing_id and c.listing_title is null;

alter table public.conversations alter column buyer_id drop not null;
alter table public.conversations alter column seller_id drop not null;
alter table public.conversations alter column listing_id drop not null;
alter table public.messages alter column sender_id drop not null;

alter table public.conversations drop constraint conversations_buyer_id_fkey;
alter table public.conversations add constraint conversations_buyer_id_fkey
  foreign key (buyer_id) references public.profiles(id) on delete set null;
alter table public.conversations drop constraint conversations_seller_id_fkey;
alter table public.conversations add constraint conversations_seller_id_fkey
  foreign key (seller_id) references public.profiles(id) on delete set null;
alter table public.conversations drop constraint conversations_listing_id_fkey;
alter table public.conversations add constraint conversations_listing_id_fkey
  foreign key (listing_id) references public.listings(id) on delete set null;
alter table public.messages drop constraint messages_sender_id_fkey;
alter table public.messages add constraint messages_sender_id_fkey
  foreign key (sender_id) references public.profiles(id) on delete set null;

-- Remember the artwork title, so the chat still has a name after the listing is gone.
create or replace function public.conversations_snapshot_title() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.listing_title := (select l.title from public.listings l where l.id = new.listing_id);
  return new;
end $$;
revoke execute on function public.conversations_snapshot_title() from public, anon, authenticated;
drop trigger if exists conversations_snapshot_title on public.conversations;
create trigger conversations_snapshot_title before insert on public.conversations
  for each row execute function public.conversations_snapshot_title();

create or replace function public.listings_sync_chat_title() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.conversations c set listing_title = new.title
  where c.listing_id = new.id and c.listing_title is distinct from new.title;
  return null;
end $$;
revoke execute on function public.listings_sync_chat_title() from public, anon, authenticated;
drop trigger if exists listings_sync_chat_title on public.listings;
create trigger listings_sync_chat_title after update of title on public.listings
  for each row execute function public.listings_sync_chat_title();

-- Nobody is left to read a chat once both people have gone: remove it.
create or replace function public.conversations_drop_empty() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.conversations c where c.id = new.id and c.buyer_id is null and c.seller_id is null;
  return null;
end $$;
revoke execute on function public.conversations_drop_empty() from public, anon, authenticated;
drop trigger if exists conversations_drop_empty on public.conversations;
create trigger conversations_drop_empty after update on public.conversations
  for each row when (new.buyer_id is null and new.seller_id is null)
  execute function public.conversations_drop_empty();

-- Messages from a departed member have no sender; the recipient must still be able to mark them read.
drop policy if exists "recipients mark messages read" on public.messages;
create policy "recipients mark messages read" on public.messages for update to authenticated
  using (sender_id is distinct from (select auth.uid()) and public.is_participant(conversation_id))
  with check (sender_id is distinct from (select auth.uid()) and public.is_participant(conversation_id));

-- ---------------------------------------------------------------------------
-- 2. Blocking
-- ---------------------------------------------------------------------------
create table if not exists public.user_blocks (
  blocker_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);
alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon, authenticated;
grant select, delete on public.user_blocks to authenticated;
grant insert (blocked_id) on public.user_blocks to authenticated;

create policy "members see own blocks" on public.user_blocks for select to authenticated
  using (blocker_id = (select auth.uid()));
create policy "members block others" on public.user_blocks for insert to authenticated
  with check (blocker_id = (select auth.uid()) and blocked_id <> (select auth.uid()));
create policy "members unblock" on public.user_blocks for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- Internal check used by triggers (not callable from the API).
create or replace function public.members_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_blocks x
    where (x.blocker_id = a and x.blocked_id = b) or (x.blocker_id = b and x.blocked_id = a));
$$;
revoke execute on function public.members_blocked(uuid, uuid) from public, anon, authenticated;

-- New chats: not between members where either has blocked the other.
create or replace function public.conversations_check_open() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.buyer_id is not null and new.seller_id is not null
     and public.members_blocked(new.buyer_id, new.seller_id) then
    raise exception 'CHAT_CLOSED' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.conversations_check_open() from public, anon, authenticated;
drop trigger if exists conversations_unblocked_check on public.conversations;
-- Named to run after conversations_set_seller (triggers run in name order).
create trigger conversations_unblocked_check before insert on public.conversations
  for each row execute function public.conversations_check_open();

-- New messages: only while both people are still members and neither has blocked the other.
create or replace function public.messages_check_open() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  c public.conversations;
begin
  select * into c from public.conversations x where x.id = new.conversation_id;
  if c.id is null then return new; end if; -- row level security rejects it
  if c.buyer_id is null or c.seller_id is null or public.members_blocked(c.buyer_id, c.seller_id) then
    raise exception 'CHAT_CLOSED' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.messages_check_open() from public, anon, authenticated;
drop trigger if exists messages_open_check on public.messages;
create trigger messages_open_check before insert on public.messages
  for each row execute function public.messages_check_open();

-- What the viewer sees for a chat: open, left (other person deleted their account),
-- blocked (the viewer blocked them) or closed (the other person blocked the viewer).
-- Read as a column: select chat_state from conversations. Returns NULL for non-participants.
create or replace function public.chat_state(c public.conversations) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when (select auth.uid()) is null
      or (select auth.uid()) is distinct from c.buyer_id and (select auth.uid()) is distinct from c.seller_id then null
    when c.buyer_id is null or c.seller_id is null then 'left'
    when exists (select 1 from public.user_blocks x where x.blocker_id = (select auth.uid())
      and x.blocked_id = case when c.buyer_id = (select auth.uid()) then c.seller_id else c.buyer_id end) then 'blocked'
    when public.members_blocked(c.buyer_id, c.seller_id) then 'closed'
    else 'open'
  end;
$$;
revoke execute on function public.chat_state(public.conversations) from public, anon;
grant execute on function public.chat_state(public.conversations) to authenticated;
