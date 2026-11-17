-- Notifications inbox: new messages, first message of a new conversation, and likes on your listings.
-- Rows are written only by the triggers below (security definer); members can read, mark read and delete their own.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null check (type in ('message', 'conversation', 'favorite')),
  listing_id uuid references public.listings(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  listing_title text check (char_length(listing_title) <= 60),
  preview text check (char_length(preview) <= 120),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc);
create index if not exists notifications_recipient_unread_idx on public.notifications (recipient_id) where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated
  using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));
drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications for delete to authenticated
  using (recipient_id = (select auth.uid()));

-- Clients may only flip read_at; everything else is written by triggers.
revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Is `recipient` blocking `actor`?
create or replace function public.notification_blocked(recipient uuid, actor uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_blocks b where b.blocker_id = recipient and b.blocked_id = actor)
$$;
revoke all on function public.notification_blocked(uuid, uuid) from public, anon, authenticated;

-- Likes: notify the seller (not for your own listing, not when blocked, at most once a day per person and listing).
create or replace function public.notify_on_favorite()
returns trigger language plpgsql security definer set search_path = '' as $$
declare seller uuid; title text;
begin
  select l.seller_id, l.title into seller, title from public.listings l where l.id = new.listing_id;
  if seller is null or seller = new.user_id or public.notification_blocked(seller, new.user_id) then return null; end if;
  if exists (select 1 from public.notifications n where n.recipient_id = seller and n.actor_id = new.user_id
             and n.type = 'favorite' and n.listing_id = new.listing_id and n.created_at > now() - interval '1 day') then
    return null;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, listing_id, listing_title)
  values (seller, new.user_id, 'favorite', new.listing_id, left(title, 60));
  return null;
end $$;

-- Unlike: remove the still-unread like notification, like Instagram.
create or replace function public.notify_on_unfavorite()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.notifications n where n.type = 'favorite' and n.actor_id = old.user_id
    and n.listing_id = old.listing_id and n.read_at is null;
  return null;
end $$;

-- Messages: first message of a conversation becomes 'conversation'; later ones collapse into one unread 'message' row per chat.
create or replace function public.notify_on_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.conversations; recipient uuid; recipient_left boolean; first_message boolean; existing uuid;
begin
  if new.sender_id is null or new.deleted_at is not null then return null; end if;
  select * into c from public.conversations where id = new.conversation_id;
  if not found then return null; end if;
  if new.sender_id = c.buyer_id then recipient := c.seller_id; recipient_left := c.seller_left_chat;
  elsif new.sender_id = c.seller_id then recipient := c.buyer_id; recipient_left := c.buyer_left_chat;
  else return null; end if;
  if recipient is null or recipient_left or public.notification_blocked(recipient, new.sender_id) then return null; end if;

  first_message := not exists (select 1 from public.messages m where m.conversation_id = new.conversation_id and m.id <> new.id);
  if first_message then
    insert into public.notifications (recipient_id, actor_id, type, listing_id, conversation_id, listing_title, preview)
    values (recipient, new.sender_id, 'conversation', c.listing_id, c.id, c.listing_title, left(new.body, 120));
    return null;
  end if;

  select n.id into existing from public.notifications n
   where n.recipient_id = recipient and n.conversation_id = c.id and n.type in ('message', 'conversation') and n.read_at is null
   order by n.created_at desc limit 1;
  if existing is not null then
    update public.notifications set actor_id = new.sender_id, preview = left(new.body, 120), created_at = now() where id = existing;
  else
    insert into public.notifications (recipient_id, actor_id, type, listing_id, conversation_id, listing_title, preview)
    values (recipient, new.sender_id, 'message', c.listing_id, c.id, c.listing_title, left(new.body, 120));
  end if;
  return null;
end $$;

revoke all on function public.notify_on_favorite() from public, anon, authenticated;
revoke all on function public.notify_on_unfavorite() from public, anon, authenticated;
revoke all on function public.notify_on_message() from public, anon, authenticated;

drop trigger if exists favorites_notify on public.favorites;
create trigger favorites_notify after insert on public.favorites for each row execute function public.notify_on_favorite();
drop trigger if exists favorites_unnotify on public.favorites;
create trigger favorites_unnotify after delete on public.favorites for each row execute function public.notify_on_unfavorite();
drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages for each row execute function public.notify_on_message();

-- Live updates for the bell (realtime still applies the select policy above).
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
