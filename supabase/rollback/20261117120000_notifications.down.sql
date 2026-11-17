-- Undo 20261117120000_notifications.sql
do $$ begin
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
    alter publication supabase_realtime drop table public.notifications;
  end if;
end $$;
drop trigger if exists messages_notify on public.messages;
drop trigger if exists favorites_unnotify on public.favorites;
drop trigger if exists favorites_notify on public.favorites;
drop function if exists public.notify_on_message();
drop function if exists public.notify_on_unfavorite();
drop function if exists public.notify_on_favorite();
drop function if exists public.notification_blocked(uuid, uuid);
drop table if exists public.notifications;
