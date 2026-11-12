-- Keep listings.conversation_count correct when conversations disappear
-- (for example when a buyer deletes their account and their conversations cascade away).
-- Before this, the count was only refreshed when a message was inserted.

create or replace function public.conversations_refresh_counts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_listing_counts(old.listing_id);
  return null;
end $$;
revoke execute on function public.conversations_refresh_counts() from public, anon, authenticated;

drop trigger if exists conversations_refresh_counts on public.conversations;
create trigger conversations_refresh_counts after delete on public.conversations
  for each row execute function public.conversations_refresh_counts();

-- Fix counts that are already out of date. Only the two counter columns change.
update public.listings l set
  favorite_count = (select count(*) from public.favorites f where f.listing_id = l.id),
  conversation_count = (select count(*) from public.conversations c where c.listing_id = l.id
    and exists (select 1 from public.messages m where m.conversation_id = c.id))
where l.favorite_count is distinct from (select count(*) from public.favorites f where f.listing_id = l.id)
   or l.conversation_count is distinct from (select count(*) from public.conversations c where c.listing_id = l.id
    and exists (select 1 from public.messages m where m.conversation_id = c.id));
