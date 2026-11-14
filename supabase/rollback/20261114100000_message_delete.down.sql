-- Rollback for 20261114100000_message_delete.
-- WARNING: messages deleted for everyone have no text left, so they are removed entirely.
-- Messages hidden "for me" become visible again.
begin;
drop function if exists public.delete_message_for_everyone(uuid);
drop policy if exists "participants read messages" on public.messages;
create policy "participants read messages" on public.messages for select to authenticated
  using (public.is_participant(conversation_id));
drop table if exists public.message_hides;
delete from public.messages where deleted_at is not null;
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check
  check (char_length(btrim(body)) >= 1 and char_length(btrim(body)) <= 500);
alter table public.messages drop column if exists deleted_at;
delete from supabase_migrations.schema_migrations where version = '20261114100000';
commit;
