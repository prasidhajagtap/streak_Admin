-- ============================================================================
-- The console still thinks the game ships ABG and Hire-to-Retire packs
--
-- WHAT IS WRONG. A01 hard-coded the theme list into three functions. The game
-- has since dropped all 39 ABG and HR themes and now ships seven packs of
-- trending words. So:
--
--   * the Themes pane lists packs that no longer exist,
--   * dn_theme_pack() answers 'Hire to Retire' for every one of the new
--     themes, because that is its else-branch,
--   * dn_theme_unknown() reports every new theme as unrecognised, and the
--     console prints a drift warning that is now permanently true.
--
-- WHAT THIS DOES. Replaces the three functions so they describe the game as
-- it is. The ABG/HR SPLIT ITSELF IS RETIRED - there are no longer two packs
-- to split between, there are seven, and a function whose whole job was
-- 'ABG or the other one' has nothing left to answer.
--
-- >>> NO SCORE IS TOUCHED. <<< scores.theme keeps every value it has ever
-- held, including the 39 retired names. A game played last month under
-- 'Hire To Retire' still reads 'Hire To Retire' on the board and in the
-- player's history, because that is what happened. These functions only
-- decide how the CONSOLE groups them.
--
-- Safe to re-run. Rollback: A99_rollback_trending_packs.sql
-- Verify: A05_verify_trending_packs.sql
-- ============================================================================

-- The seven packs the game ships today, verbatim from THEMES in index.html.
create or replace function public.dn_live_packs()
returns text[] language sql immutable
as $function$
  select array[
    'The Virus Years', 'Jabs and Jargon',  'Words That Spiked',
    'Looked Up in 2022','The AI Turn',     'Very Online',
    'Newest Words'
  ];
$function$;

-- Kept as a name so nothing that calls it breaks, but it now returns an empty
-- array: there is no ABG pack. Anything still calling this is reading a
-- concept that no longer exists and should be moved to dn_live_packs().
create or replace function public.dn_abg_themes()
returns text[] language sql immutable
as $function$ select array[]::text[]; $function$;

-- Every retired theme, so the console can label a historic score rather than
-- calling it unknown. Scores from before the switch are real games and their
-- rows must not start looking like data errors.
create or replace function public.dn_retired_themes()
returns text[] language sql immutable
as $function$
  select array[
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

-- Three answers now, not two, and no default that quietly absorbs anything
-- it does not recognise - that default is exactly what let A01 go stale
-- without anybody noticing.
create or replace function public.dn_theme_pack(p_theme text)
returns text language sql immutable
as $function$
  select case
    when p_theme = any (public.dn_live_packs())    then 'Trending words'
    when p_theme = any (public.dn_retired_themes()) then 'Retired pack'
    else 'Unrecognised'
  end;
$function$;

-- Still the drift alarm, and still must return zero rows - but it now means
-- what it says, because neither list has a catch-all branch behind it.
create or replace function public.dn_theme_unknown()
returns table(theme text, plays bigint) language sql stable
as $function$
  select s.theme, count(*)
    from public.scores s
   where s.theme is not null
     and not (s.theme = any (public.dn_live_packs()))
     and not (s.theme = any (public.dn_retired_themes()))
   group by s.theme
   order by 2 desc;
$function$;

-- These are helpers for the console, which runs as an authenticated admin.
-- The browser must never reach them directly. Revoking from PUBLIC alone is
-- not enough on Supabase: it grants EXECUTE to anon and authenticated
-- separately, so all three have to be named.
revoke execute on function public.dn_live_packs()      from public, anon, authenticated;
revoke execute on function public.dn_retired_themes()  from public, anon, authenticated;
revoke execute on function public.dn_abg_themes()      from public, anon, authenticated;
revoke execute on function public.dn_theme_pack(text)  from public, anon, authenticated;
revoke execute on function public.dn_theme_unknown()   from public, anon, authenticated;
