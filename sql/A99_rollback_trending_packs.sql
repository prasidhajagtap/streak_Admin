-- ============================================================================
-- Rollback for A04. Restores A01's three functions exactly as they were.
-- Re-running A01 does the same thing; this exists so the undo is one file.
--
-- Note what rolling back actually buys you: the console goes back to calling
-- every one of the seven live packs 'Hire to Retire', because that was A01's
-- else-branch. That is the bug, not the baseline.
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
create or replace function public.dn_theme_pack(p_theme text)
returns text language sql immutable
as $function$
  select case when p_theme = any (public.dn_abg_themes())
              then 'About ABG' else 'Hire to Retire' end;
$function$;
drop function if exists public.dn_live_packs();
drop function if exists public.dn_retired_themes();
