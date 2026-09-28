-- ============================================================================
-- Word Vibe - five early theme names the retired list was missing.
--
-- FOUND BY: A07's drift alarm (dn_theme_unknown) on the live database,
-- 28 Sep 2026. It listed five themes with real plays that no list knew:
--     Our Group 7, Our Story 7, Our Companies 6, Our Brands 4, Life At ABG 3
-- They are the game's very first packs, from before the "Birla ..." names.
-- A04's retired list was taken from later versions of the game and missed
-- them, so the console called 27 real games "Unrecognised".
--
-- CHECKED COMPLETE: every theme name in all 80 versions of index.html in the
-- game's history was compared with the lists. There are 51 in all: the 7
-- trending packs, A04's 39, and these 5. Nothing else is missing.
--
-- THE LAST QUERY IS A CHECKLIST. The SQL editor shows only the last result
-- of a file, so instead of a query that should return "no rows", this ends
-- with one table: every check, what it should say, what it says, and ok.
--
-- A04 carries the same list now, so re-running A04 cannot undo this.
-- Safe to re-run. Writes nothing but this one function.
-- ============================================================================

create or replace function public.dn_retired_themes()
returns text[] language sql immutable
as $function$
  select array[
    -- the first packs of all, from before the Birla names; found by A07's
    -- drift alarm on the live data, 28 Sep 2026
    'Our Group','Our Story','Our Companies','Our Brands','Life At ABG',
    'Birla Companies','Birla Brands','Metals & Cement','Money & Insurance',
    'Fibre & Fabric','The Birla Group','Inside Hindalco','Inside UltraTech',
    'Fashion Labels','New Ventures','Around The World','Green & Clean',
    'Life At Birla','Giving Back','Birla History',
    'Hire To Retire','Talent Hiring','Joining & Onboarding','Payroll & Pay',
    'Benefits & Wellbeing','Learning & Growth','Performance',
    'Time & Attendance','Employee Relations','HR Systems & Data',
    'HR Shared Services','Rewards & Recognition','HR Compliance',
    'Exit & Retire','Workforce Planning','Diversity & Inclusion',
    'Employer Brand','Policy & Handbook','Succession & Talent',
    'Employee Experience','Health & Safety','Mobility & Transfers',
    'Contract & Gig Work','Culture & Values'
  ];
$function$;
revoke execute on function public.dn_retired_themes() from public, anon, authenticated;


-- ------------------------------------------------------------- checklist ---
-- Every row should read ok = true.
select check_name, expected, actual, (expected = actual) as ok from (
  select 1 as n, 'themes in scores that no list recognises' as check_name, '0' as expected,
         (select count(*)::text from public.dn_theme_unknown()) as actual
  union all
  select 2, 'retired pack names known', '44',
         (select cardinality(public.dn_retired_themes())::text)
  union all
  select 3, 'the five early packs classify as Retired pack', 'Retired pack x5',
         (select case when bool_and(public.dn_theme_pack(t) = 'Retired pack') then 'Retired pack x5' else 'NOT ALL' end
            from unnest(array['Our Group','Our Story','Our Companies','Our Brands','Life At ABG']) t)
  union all
  select 4, 'public key can call dn_retired_themes', 'false',
         has_function_privilege('anon','public.dn_retired_themes()','EXECUTE')::text
  union all
  select 5, 'custom_themes table exists (A06 has run)', 'true',
         (to_regclass('public.custom_themes') is not null)::text
  union all
  select 6, 'public key can read custom_themes directly', 'false',
         (case when to_regclass('public.custom_themes') is null then 'false'
               else has_table_privilege('anon','public.custom_themes','SELECT')::text end)
  union all
  select 7, 'the game can fetch live themes ('||
            coalesce((select json_array_length(public.live_custom_themes())::text
                       where to_regproc('public.live_custom_themes') is not null), '?')||' live now)',
         'works',
         (case when to_regproc('public.live_custom_themes') is null then 'function missing - run A06'
               else 'works' end)
) c order by n;
