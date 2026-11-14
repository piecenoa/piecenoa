-- PIECENOA: delete a message for me / for everyone. Paste all into SQL Editor and press Run.
-- One transaction: if any line fails, nothing is changed.
begin;

-- PIECENOA: delete a message for me, or for everyone.
-- * Delete for me: hides the message only for the person who deletes it (message_hides).
-- * Delete for everyone: the sender can do this within 24 hours of sending. The text is erased
--   and both people see "This message was deleted."

alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (deleted_at is not null and body = '')
  or (deleted_at is null and char_length(btrim(body)) >= 1 and char_length(btrim(body)) <= 500)
);

create table if not exists public.message_hides (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
create index if not exists message_hides_message_idx on public.message_hides (message_id);
alter table public.message_hides enable row level security;
revoke all on public.message_hides from anon, authenticated;
grant select, delete on public.message_hides to authenticated;
grant insert (message_id) on public.message_hides to authenticated;

create policy "members see own hidden messages" on public.message_hides for select to authenticated
  using (user_id = (select auth.uid()));
create policy "members hide messages in their chats" on public.message_hides for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.messages m where m.id = message_id and public.is_participant(m.conversation_id)));
create policy "members unhide messages" on public.message_hides for delete to authenticated
  using (user_id = (select auth.uid()));

-- Participants read messages, except the ones they deleted for themselves.
drop policy if exists "participants read messages" on public.messages;
create policy "participants read messages" on public.messages for select to authenticated
  using (public.is_participant(conversation_id) and not exists (
    select 1 from public.message_hides h where h.message_id = messages.id and h.user_id = (select auth.uid())));

create or replace function public.delete_message_for_everyone(p_message uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  m public.messages;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode = 'P0001'; end if;
  select * into m from public.messages x where x.id = p_message;
  if m.id is null or m.sender_id is distinct from uid or not public.is_participant(m.conversation_id) then
    raise exception 'NOT_FOUND' using errcode = 'P0001';
  end if;
  if m.deleted_at is not null then return; end if;
  if m.created_at < now() - interval '24 hours' then raise exception 'TOO_LATE' using errcode = 'P0001'; end if;
  update public.messages x set body = '', deleted_at = now() where x.id = p_message;
end $$;
revoke execute on function public.delete_message_for_everyone(uuid) from public, anon;
grant execute on function public.delete_message_for_everyone(uuid) to authenticated;

insert into supabase_migrations.schema_migrations (version, name, created_by) values ('20261114100000', 'message_delete', 'sql-editor') on conflict (version) do nothing;

commit;

-- Expected result: Success. No rows returned
