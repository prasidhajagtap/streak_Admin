-- ============================================================================
-- Verify A06_custom_themes.sql. Run it after A06. Read-only.
-- Each block says what a correct answer looks like.
-- ============================================================================

-- V1. The table is locked to the browser.
--     EXPECT: rls_on = true, and every privilege column = false.
select c.relrowsecurity                                                    as rls_on,
       has_table_privilege('anon',          'public.custom_themes', 'SELECT') as anon_select,
       has_table_privilege('anon',          'public.custom_themes', 'INSERT') as anon_insert,
       has_table_privilege('authenticated', 'public.custom_themes', 'SELECT') as auth_select,
       has_sequence_privilege('anon', 'public.custom_themes_id_seq', 'USAGE') as anon_seq
  from pg_class c where c.oid = 'public.custom_themes'::regclass;

-- V2. Who can call what.
--     EXPECT: the four admin_custom_theme_* functions -> anon true,  authenticated false
--             live_custom_themes                      -> anon true,  authenticated true
--             dn_clean_theme, dn_theme_pack, dn_theme_unknown -> false for both
select p.proname,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('admin_custom_theme_save','admin_custom_theme_list',
                     'admin_custom_theme_set_status','admin_custom_theme_delete',
                     'live_custom_themes','dn_clean_theme','dn_theme_pack','dn_theme_unknown')
 order by 1;

-- V3. ONE of each function, never two. CREATE OR REPLACE with a different
--     argument list makes a SECOND function rather than replacing the first -
--     the fault behind two earlier production bugs (submit_score, login_player).
--     EXPECT: no rows.
select p.proname, count(*) as versions
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('admin_custom_theme_save','admin_custom_theme_list',
                     'admin_custom_theme_set_status','admin_custom_theme_delete',
                     'live_custom_themes','dn_clean_theme','dn_theme_pack','dn_theme_unknown')
 group by 1 having count(*) > 1;

-- V4. The server-side rules, without storing anything.
--     EXPECT: ok true, count 5 | TOO_FEW_WORDS | NAME_CHARS | NAME_RESERVED
select 'five good words' as case_, public.dn_clean_theme('Probe',
         '[{"w":"alpha"},{"w":"bravo"},{"w":"delta"},{"w":"echos"},{"w":"golfs"}]') ->> 'ok'    as ok,
       public.dn_clean_theme('Probe',
         '[{"w":"alpha"},{"w":"bravo"},{"w":"delta"},{"w":"echos"},{"w":"golfs"}]') ->> 'count' as detail
union all
select 'four words',  public.dn_clean_theme('Probe','[{"w":"ONE"},{"w":"TWO"},{"w":"SIX"},{"w":"TEN"}]') ->> 'ok',
                      public.dn_clean_theme('Probe','[{"w":"ONE"},{"w":"TWO"},{"w":"SIX"},{"w":"TEN"}]') ->> 'errors'
union all
select 'markup name', public.dn_clean_theme('<b>x</b>','[]') ->> 'ok', public.dn_clean_theme('<b>x</b>','[]') ->> 'errors'
union all
select 'pack name',   public.dn_clean_theme('The AI Turn','[]') ->> 'ok', public.dn_clean_theme('The AI Turn','[]') ->> 'errors';

-- V5. What the game will be sent right now.
--     EXPECT: live = 0 until a theme is switched on in the console.
select json_array_length(public.live_custom_themes()) as live,
       (select string_agg(t->>'name', ', ') from json_array_elements(public.live_custom_themes()) t) as names;

-- V6. The drift alarm still means what it says.
--     EXPECT: no rows (unless a genuinely unknown theme is in scores).
select * from public.dn_theme_unknown();
