-- Rollback for 20261114110000_fix_message_hide_policy (restores the broken recursive rule; only for undoing).
begin;
drop policy if exists "members hide messages in their chats" on public.message_hides;
create policy "members hide messages in their chats" on public.message_hides for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.messages m where m.id = message_id and public.is_participant(m.conversation_id)));
drop function if exists public.can_hide_message(uuid);
delete from supabase_migrations.schema_migrations where version = '20261114110000';
commit;
