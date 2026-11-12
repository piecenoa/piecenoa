-- Records changes that were made to the live database outside the migration history
-- (captured from the live schema on 2026-11-12). Every statement is idempotent, so
-- applying this to the live project changes nothing; applying it to a fresh database
-- recreates the same state.

alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists nickname_changed_at timestamptz;
create unique index if not exists profiles_nickname_unique
  on public.profiles (lower(nickname)) where nickname is not null;

-- Profile edits went through set_nickname() only.
drop policy if exists "update own profile" on public.profiles;

create or replace function public.nickname_rule_problem(value text)
 returns text
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  nick text := btrim(coalesce(value, ''));
  low text := lower(nick);
  word text;
begin
  if char_length(nick) < 2 or char_length(nick) > 16 then return 'length'; end if;
  if nick !~ '^[0-9A-Za-z가-힣._]+$' then return 'characters'; end if;
  if nick ~ '^[._]' or nick ~ '[._]$' or nick ~ '[._]{2}' then return 'symbols'; end if;
  if nick ~ '^[0-9]+$' then return 'numbers'; end if;
  foreach word in array array['admin','piecenoa','피스노아','관리자','운영자','운영진','운영팀','고객센터','시발','씨발','병신','좆','개새끼','fuck','shit'] loop
    if position(word in low) > 0 then return 'reserved'; end if;
  end loop;
  if low = any(array['root','staff','system','support','official','moderator','manager','member','guest','null','undefined','공식','매니저','회원','탈퇴회원']) then return 'reserved'; end if;
  return null;
end $function$;

create or replace function public.check_nickname(value text)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  nick text := btrim(coalesce(value, ''));
  problem text := public.nickname_rule_problem(nick);
  owner uuid;
begin
  if problem is not null then return problem; end if;
  select id into owner from public.profiles where lower(nickname) = lower(nick);
  if owner is null then return 'ok'; end if;
  if owner = (select auth.uid()) then return 'mine'; end if;
  return 'taken';
end $function$;

create or replace function public.set_nickname(value text)
 returns json
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  uid uuid := (select auth.uid());
  nick text := btrim(coalesce(value, ''));
  problem text := public.nickname_rule_problem(nick);
  current_nick text;
  changed timestamptz;
  next_change timestamptz;
begin
  if uid is null then raise exception 'NICK_AUTH' using errcode = 'P0001'; end if;
  if problem is not null then raise exception 'NICK_%', upper(problem) using errcode = 'P0001'; end if;
  select nickname, nickname_changed_at into current_nick, changed from public.profiles where id = uid for update;
  if not found then raise exception 'NICK_AUTH' using errcode = 'P0001'; end if;
  if current_nick = nick then raise exception 'NICK_SAME' using errcode = 'P0001'; end if;
  -- Changing only upper/lower case keeps the same nickname, so it is allowed any time.
  if current_nick is not null and lower(current_nick) <> lower(nick) then
    next_change := coalesce(changed, '-infinity'::timestamptz) + interval '30 days';
    if next_change > now() then
      raise exception 'NICK_COOLDOWN:%', to_char(next_change at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') using errcode = 'P0001';
    end if;
  end if;
  begin
    update public.profiles
      set nickname = nick,
          nickname_changed_at = case when current_nick is null or lower(current_nick) = lower(nick) then nickname_changed_at else now() end
      where id = uid;
  exception when unique_violation then
    raise exception 'NICK_TAKEN' using errcode = 'P0001';
  end;
  return json_build_object('nickname', nick, 'nickname_changed_at', (select p.nickname_changed_at from public.profiles p where p.id = uid));
end $function$;
revoke execute on function public.set_nickname(text) from public, anon;
grant execute on function public.set_nickname(text) to authenticated;

create or replace function public.sync_display_name()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin new.display_name := coalesce(new.nickname, 'Member'); return new; end $function$;
revoke execute on function public.sync_display_name() from public, anon, authenticated;
drop trigger if exists profiles_sync_display_name on public.profiles;
create trigger profiles_sync_display_name before insert or update on public.profiles
  for each row execute function public.sync_display_name();

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  wanted text := btrim(coalesce(new.raw_user_meta_data->>'nickname', ''));
begin
  insert into public.profiles (id) values (new.id);
  if wanted <> '' and public.nickname_rule_problem(wanted) is null then
    begin
      update public.profiles set nickname = wanted where id = new.id;
    exception when unique_violation then null;
    end;
  end if;
  return new;
end $function$;
