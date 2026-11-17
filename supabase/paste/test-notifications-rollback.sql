-- Notification trigger test. Everything runs inside one block and is undone at the end
-- by a deliberate error, so nothing is saved and no member receives a notification.
-- The result is shown in the error message: "TEST-RESULT (rolled back) ...".
do $$
declare
  s uuid; a uuid; lid uuid; cid uuid; n int; t text; out text := '';
begin
  select l.seller_id, l.id into s, lid from public.listings l where l.deleted_at is null order by l.created_at desc limit 1;
  select p.id into a from public.profiles p where p.id <> s order by p.created_at limit 1;
  if s is null or a is null then raise exception 'TEST-SETUP: need one listing and one other member'; end if;

  -- start clean (inside the test only)
  delete from public.favorites where user_id = a and listing_id = lid;
  delete from public.notifications where recipient_id in (s, a);

  -- A likes S's piece -> S gets one 'favorite'
  insert into public.favorites (user_id, listing_id) values (a, lid);
  select count(*) into n from public.notifications where recipient_id = s and type = 'favorite' and actor_id = a;
  out := out || ' | like: ' || n || ' (expect 1)';

  -- A unlikes while unread -> removed
  delete from public.favorites where user_id = a and listing_id = lid;
  select count(*) into n from public.notifications where recipient_id = s and type = 'favorite';
  out := out || ' | unlike: ' || n || ' (expect 0)';

  -- A likes S's own piece as S -> no notification
  delete from public.favorites where user_id = s and listing_id = lid;
  insert into public.favorites (user_id, listing_id) values (s, lid);
  select count(*) into n from public.notifications where recipient_id = s and actor_id = s;
  out := out || ' | own like: ' || n || ' (expect 0)';

  -- A opens a new chat with a first message -> S gets one 'conversation'
  insert into public.conversations (listing_id, buyer_id, seller_id, listing_title)
  values (lid, a, s, (select left(title, 60) from public.listings where id = lid)) returning id into cid;
  insert into public.messages (conversation_id, sender_id, body) values (cid, a, 'Test: is this available?');
  select string_agg(type, ',') into t from public.notifications where recipient_id = s and conversation_id = cid;
  out := out || ' | first message: ' || coalesce(t, 'none') || ' (expect conversation)';

  -- A sends two more -> still one unread row for this chat, preview = last message
  insert into public.messages (conversation_id, sender_id, body) values (cid, a, 'Test: second');
  insert into public.messages (conversation_id, sender_id, body) values (cid, a, 'Test: third');
  select count(*), max(preview) into n, t from public.notifications where recipient_id = s and conversation_id = cid and read_at is null;
  out := out || ' | more messages: ' || n || ' row, preview=' || coalesce(t, '') || ' (expect 1, Test: third)';

  -- S replies -> A gets one 'message'
  insert into public.messages (conversation_id, sender_id, body) values (cid, s, 'Test: yes it is');
  select string_agg(type, ',') into t from public.notifications where recipient_id = a and conversation_id = cid;
  out := out || ' | reply: ' || coalesce(t, 'none') || ' (expect message)';

  raise exception 'TEST-RESULT (rolled back)%', out;
end $$;
