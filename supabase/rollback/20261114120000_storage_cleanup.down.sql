-- Rollback for 20261114120000_storage_cleanup. Listings and files already removed cannot be restored.
begin;
drop function if exists public.storage_cleanup_candidates(int);
drop function if exists public.purge_deleted_listings(int, int);
delete from supabase_migrations.schema_migrations where version = '20261114120000';
commit;
