-- PIECENOA: "Delete chat" (leave a conversation).
-- Deleting a chat removes it for the person who deletes it only. The other person keeps the
-- history, sees that the chat was left, and can no longer reply. When both people have left,
-- the conversation is removed (conversations_drop_empty).

alter table public.conversations
  add column if not exists buyer_left_chat boolean not null default false,
  add column if not exists seller_left_chat boolean not null default false;

create or replace function public.leave_conversation(p_conversation uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode = 'P0001'; end if;
  update public.conversations c set
    buyer_id = case when c.buyer_id = uid then null else c.buyer_id end,
    buyer_left_chat = c.buyer_left_chat or coalesce(c.buyer_id = uid, false),
    seller_id = case when c.seller_id = uid then null else c.seller_id end,
    seller_left_chat = c.seller_left_chat or coalesce(c.seller_id = uid, false)
  where c.id = p_conversation and uid in (c.buyer_id, c.seller_id);
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0001'; end if;
end $$;
revoke execute on function public.leave_conversation(uuid) from public, anon;
grant execute on function public.leave_conversation(uuid) to authenticated;

-- chat_state gains 'left_chat': the other person deleted this chat (their account still exists).
create or replace function public.chat_state(c public.conversations) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when (select auth.uid()) is null
      or (select auth.uid()) is distinct from c.buyer_id and (select auth.uid()) is distinct from c.seller_id then null
    when c.buyer_id is null then case when c.buyer_left_chat then 'left_chat' else 'left' end
    when c.seller_id is null then case when c.seller_left_chat then 'left_chat' else 'left' end
    when exists (select 1 from public.user_blocks x where x.blocker_id = (select auth.uid())
      and x.blocked_id = case when c.buyer_id = (select auth.uid()) then c.seller_id else c.buyer_id end) then 'blocked'
    when public.members_blocked(c.buyer_id, c.seller_id) then 'closed'
    else 'open'
  end;
$$;
revoke execute on function public.chat_state(public.conversations) from public, anon;
grant execute on function public.chat_state(public.conversations) to authenticated;
