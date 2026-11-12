-- Rollback: remove the recount-on-delete trigger. Counter values are left as they are.
drop trigger if exists conversations_refresh_counts on public.conversations;
drop function if exists public.conversations_refresh_counts();
delete from supabase_migrations.schema_migrations where version = '20261113090000';
