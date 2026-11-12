-- Rollback for 20261113100000_blocks_and_departed_members.
-- WARNING: chats kept for departed members (buyer, seller or listing is empty) are deleted,
-- because the old rules require every chat to have both people and a listing. Block lists are removed.
begin;

drop function if exists public.chat_state(public.conversations);
drop trigger if exists messages_open_check on public.messages;
drop function if exists public.messages_check_open();
drop trigger if exists conversations_unblocked_check on public.conversations;
drop function if exists public.conversations_check_open();
drop function if exists public.members_blocked(uuid, uuid);
drop table if exists public.user_blocks;

drop trigger if exists conversations_drop_empty on public.conversations;
drop function if exists public.conversations_drop_empty();
drop trigger if exists listings_sync_chat_title on public.listings;
drop function if exists public.listings_sync_chat_title();
drop trigger if exists conversations_snapshot_title on public.conversations;
drop function if exists public.conversations_snapshot_title();

delete from public.messages where sender_id is null;
delete from public.conversations where buyer_id is null or seller_id is null or listing_id is null;

alter table public.messages drop constraint messages_sender_id_fkey;
alter table public.messages add constraint messages_sender_id_fkey
  foreign key (sender_id) references public.profiles(id) on delete cascade;
alter table public.conversations drop constraint conversations_listing_id_fkey;
alter table public.conversations add constraint conversations_listing_id_fkey
  foreign key (listing_id) references public.listings(id) on delete cascade;
alter table public.conversations drop constraint conversations_seller_id_fkey;
alter table public.conversations add constraint conversations_seller_id_fkey
  foreign key (seller_id) references public.profiles(id) on delete cascade;
alter table public.conversations drop constraint conversations_buyer_id_fkey;
alter table public.conversations add constraint conversations_buyer_id_fkey
  foreign key (buyer_id) references public.profiles(id) on delete cascade;
alter table public.messages alter column sender_id set not null;
alter table public.conversations alter column listing_id set not null;
alter table public.conversations alter column seller_id set not null;
alter table public.conversations alter column buyer_id set not null;
alter table public.conversations drop column if exists listing_title;

drop policy if exists "recipients mark messages read" on public.messages;
create policy "recipients mark messages read" on public.messages for update to authenticated
  using ((sender_id <> (select auth.uid())) and public.is_participant(conversation_id))
  with check ((sender_id <> (select auth.uid())) and public.is_participant(conversation_id));

delete from supabase_migrations.schema_migrations where version = '20261113100000';
commit;
