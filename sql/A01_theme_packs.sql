-- ============================================================================
-- The Daily Nine, admin — which word pack a theme belongs to.
--
-- WHY THIS EXISTS AND WHY IT IS SLIGHTLY UNCOMFORTABLE.
-- Build 21 let a player choose a pack: About ABG, Hire to Retire, or a mix of
-- both. That choice is made in the browser and stored in localStorage. It
-- NEVER reaches the database — only the resulting theme name does, in
-- scores.theme. So the pack cannot be read back; it can only be inferred from
-- the theme.
--
-- This file holds that inference. It is a lookup, and a lookup drifts: add a
-- theme to the game and this list is silently wrong. Two things make the drift
-- visible rather than silent:
--
--   1. Anything not in the ABG list is reported as 'Hire to Retire', because
--      HR is the larger pack and the default weighting, so an unknown theme
--      lands in the bigger bucket rather than inventing a third.
--   2. dn_theme_unknown() lists any theme present in scores that is in NEITHER
--      list. The admin console shows that count. If it is not zero, this file
--      is out of date with the game and the pack numbers are not to be
--      trusted.
--
-- THE PROPER FIX, when it is worth it: a pack column on scores, written at
-- submit time. That is exact, needs no list, and cannot drift — but it means
-- changing the game and it only records packs from that day forward. Until
-- then, this is honest as long as check 2 stays at zero.
--
-- Lists taken from index.html at build 26: 15 ABG themes, 24 HR themes.
--
-- READ ONLY. Creates two functions and writes nothing.
-- Safe to re-run. Rollback: A99_rollback_theme_packs.sql
-- ============================================================================

create or replace function public.dn_abg_themes()
returns text[] language sql immutable
as $function$
  select array[
    'Birla Companies', 'Birla Brands',    'Metals & Cement',
    'Money & Insurance','Fibre & Fabric', 'The Birla Group',
    'Inside Hindalco',  'Inside UltraTech','Fashion Labels',
    'New Ventures',     'Around The World','Green & Clean',
    'Life At Birla',    'Giving Back',    'Birla History'
  ];
$function$;

-- The pack a theme belongs to. Anything unrecognised is reported as HR, which
-- is the larger pack and the default weighting — see dn_theme_unknown() for
-- how an unrecognised theme is surfaced rather than hidden.
create or replace function public.dn_theme_pack(p_theme text)
returns text language sql immutable
as $function$
  select case when p_theme = any (public.dn_abg_themes())
              then 'About ABG' else 'Hire to Retire' end;
$function$;

-- Any theme that has actually been played but appears in neither list. This
-- must return zero rows. If it does not, A01 is behind the game and every pack
-- number in the console is understating ABG.
create or replace function public.dn_theme_unknown()
returns table(theme text, plays bigint) language sql stable
as $function$
  select s.theme, count(*)
    from public.scores s
   where s.theme is not null
     and not (s.theme = any (public.dn_abg_themes()))
     and s.theme not in (
       'Hire To Retire','Talent Hiring','Joining & Onboarding','Payroll & Pay',
       'Benefits & Wellbeing','Learning & Growth','Performance',
       'Time & Attendance','Employee Relations','HR Systems & Data',
       'HR Shared Services','Rewards & Recognition','HR Compliance',
       'Exit & Retire','Workforce Planning','Diversity & Inclusion',
       'Employer Brand','Policy & Handbook','Succession & Talent',
       'Employee Experience','Health & Safety','Mobility & Transfers',
       'Contract & Gig Work','Culture & Values')
   group by s.theme
   order by count(*) desc;
$function$;

-- These are helpers for the admin RPCs, which are SECURITY DEFINER and run as
-- the owner. The browser must not be able to call them directly: revoking from
-- PUBLIC alone is not enough on Supabase, which separately grants EXECUTE to
-- anon and authenticated on anything created in this schema.
revoke execute on function public.dn_abg_themes()          from public, anon, authenticated;
revoke execute on function public.dn_theme_pack(text)      from public, anon, authenticated;
revoke execute on function public.dn_theme_unknown()       from public, anon, authenticated;
