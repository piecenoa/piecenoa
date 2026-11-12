-- Reverts 20261112140000_piecenoa2_contract.sql.
-- Listings that use a new currency/category or an "unknown" detail must be changed first,
-- or the re-added checks and foreign keys will fail. Run in the SQL editor, then delete the
-- row for version 20261112140000 from supabase_migrations.schema_migrations.

grant execute on function public.open_conversation(uuid) to authenticated;
drop function if exists public.start_conversation(uuid, text, uuid);

drop trigger if exists listings_touch on public.listings;
create trigger listings_touch before update on public.listings for each row execute function public.touch_updated_at();
drop function if exists public.listings_touch_updated_at();

drop trigger if exists messages_refresh_counts on public.messages;
drop function if exists public.messages_refresh_counts();
drop trigger if exists favorites_refresh_counts on public.favorites;
drop function if exists public.favorites_refresh_counts();
drop function if exists public.refresh_listing_counts(uuid);
drop index if exists public.listings_public_popular_idx;
alter table public.listings drop column if exists favorite_count, drop column if exists conversation_count;

alter table public.listings
  drop constraint listings_kind_check, drop constraint listings_condition_check, drop constraint listings_delivery_check;
alter table public.listings
  add constraint listings_kind_check check (kind in ('original', 'edition', 'reproduction')),
  add constraint listings_condition_check check (condition in ('new', 'good', 'vintage')),
  add constraint listings_delivery_check check (delivery in ('meetup', 'shipping', 'either'));

delete from public.categories where code in ('photography', 'sculpture', 'jewelry', 'mixed');
update public.categories c set name_en = v.name_en, name_ko = v.name_ko, sort_order = v.sort_order
from (values ('painting', 'Painting', '회화', 10), ('drawing', 'Drawing', '드로잉', 20),
             ('object', 'Ceramics & objects', '도자·오브제', 30), ('print', 'Prints', '아트 프린트', 40)) as v(code, name_en, name_ko, sort_order)
where c.code = v.code;
delete from public.currencies where code in ('INR', 'NZD', 'AED', 'BRL', 'MXN', 'THB', 'VND', 'RUB');
