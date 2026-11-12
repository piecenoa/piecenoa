-- Reverts 20261112160000_admin_and_abuse_limits.sql (keeps admin_users rows and sanctions data).
-- Run in the SQL editor, then delete version 20261112160000 from supabase_migrations.schema_migrations.

drop function if exists public.admin_update_report(uuid, text, text);
drop function if exists public.admin_set_member_ban(uuid, boolean, text);
drop function if exists public.admin_set_listing_hidden(uuid, boolean, text);
drop function if exists public.admin_members(text, int, int);
drop function if exists public.admin_stats();
drop function if exists public.require_admin();

drop trigger if exists listings_rate_limit on public.listings;
drop trigger if exists messages_rate_limit on public.messages;
drop trigger if exists conversations_rate_limit on public.conversations;
drop trigger if exists reports_rate_limit on public.reports;
drop trigger if exists favorites_rate_limit on public.favorites;
drop function if exists public.enforce_rate_limit();
drop index if exists public.listings_seller_created_idx;
drop index if exists public.messages_sender_created_idx;
drop index if exists public.reports_reporter_created_idx;

drop policy if exists "users see own sanction, admins see all" on public.user_sanctions;
create policy "users see own sanction" on public.user_sanctions for select to authenticated using (user_id = (select auth.uid()));
create policy "admins see sanctions" on public.user_sanctions for select to authenticated using ((select public.is_admin()));

drop policy if exists "reporters see own reports, admins see all" on public.reports;
create policy "reporters see own reports" on public.reports for select to authenticated using (reporter_id = (select auth.uid()));
create policy "admins see reports" on public.reports for select to authenticated using ((select public.is_admin()));

drop policy if exists "visitors see public listings" on public.listings;
drop policy if exists "members see public, own, or all as admin" on public.listings;
create policy "public listings are visible" on public.listings for select to anon, authenticated
  using (visibility = 'public' and moderation_status = 'active' and deleted_at is null);
create policy "owners see own listings" on public.listings for select to authenticated using (seller_id = (select auth.uid()));
create policy "admins see all listings" on public.listings for select to authenticated using ((select public.is_admin()));
