-- PIECENOA fix: 'Delete for me' failed (infinite recursion in policy). Paste all into SQL Editor and press Run.
-- One transaction: if any line fails, nothing is changed.
begin;

-- Fix "infinite recursion detected in policy for relation message_hides" (42P17).
-- The insert rule on message_hides read messages, whose read rule reads message_hides.
-- The participant check now runs in a SECURITY DEFINER function, which does not apply
-- row level security, so the two rules no longer call each other.

create or replace function public.can_hide_message(p_message uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.messages m
    where m.id = p_message and public.is_participant(m.conversation_id));
$$;
revoke execute on function public.can_hide_message(uuid) from public, anon;
grant execute on function public.can_hide_message(uuid) to authenticated;

drop policy if exists "members hide messages in their chats" on public.message_hides;
create policy "members hide messages in their chats" on public.message_hides for insert to authenticated
  with check (user_id = (select auth.uid()) and public.can_hide_message(message_id));

insert into supabase_migrations.schema_migrations (version, name, created_by) values ('20261114110000', 'fix_message_hide_policy', 'sql-editor') on conflict (version) do nothing;

commit;

-- Expected result: Success. No rows returned
