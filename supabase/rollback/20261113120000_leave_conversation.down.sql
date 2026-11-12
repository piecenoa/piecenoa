-- Rollback for 20261113120000_leave_conversation. Chats that were already left stay left
-- (shown as a departed member); only the leave function and the two flags are removed.
begin;
drop function if exists public.leave_conversation(uuid);
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
alter table public.conversations drop column if exists buyer_left_chat, drop column if exists seller_left_chat;
delete from supabase_migrations.schema_migrations where version = '20261113120000';
commit;
