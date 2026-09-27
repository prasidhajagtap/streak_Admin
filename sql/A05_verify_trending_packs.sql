-- ============================================================================
-- Verify A04. Read-only.
-- ============================================================================

-- V1. The seven live packs, and what dn_theme_pack calls each one.
--     Every row must say 'Trending words'.
select t as theme, public.dn_theme_pack(t) as pack
  from unnest(public.dn_live_packs()) t order by 1;

-- V2. A historic theme must be labelled, not called unknown.
select 'Hire To Retire' as theme, public.dn_theme_pack('Hire To Retire') as pack
union all
select 'Birla Brands', public.dn_theme_pack('Birla Brands')
union all
select 'something that never existed', public.dn_theme_pack('something that never existed');
-- expect: Retired pack, Retired pack, Unrecognised

-- V3. THE DRIFT ALARM. Must return NO ROWS. A row here is a theme being
--     played that neither list knows about, which means A04 is behind the
--     game again.
select * from public.dn_theme_unknown();

-- V4. No score was touched: the distinct themes on record, and how the
--     console will now group them.
select public.dn_theme_pack(s.theme) as pack, count(distinct s.theme) as themes,
       count(*) as games
  from public.scores s where s.theme is not null
 group by 1 order by 3 desc;

-- V5. The browser must not be able to call any of these.
select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_call
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public'
   and p.proname in ('dn_live_packs','dn_retired_themes','dn_abg_themes',
                     'dn_theme_pack','dn_theme_unknown')
 order by 1;
-- every anon_can_call must be false
