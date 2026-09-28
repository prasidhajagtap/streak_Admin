-- ============================================================================
-- Roll back A06_custom_themes.sql.
--
-- DESTRUCTIVE: this drops the custom_themes table and every theme uploaded
-- into it. Scores played on those themes stay in scores, but the console will
-- then report them as 'Unrecognised'. Export the themes first if you might
-- want them back:
--     select name, status, words from public.custom_themes;
--
-- dn_theme_pack and dn_theme_unknown are put back exactly as A04 left them.
-- ============================================================================

drop function if exists public.live_custom_themes();
drop function if exists public.admin_custom_theme_delete(uuid, bigint);
drop function if exists public.admin_custom_theme_set_status(uuid, bigint, text);
drop function if exists public.admin_custom_theme_list(uuid);
drop function if exists public.admin_custom_theme_save(uuid, text, jsonb);
drop function if exists public.dn_clean_theme(text, jsonb);

-- A04's definitions, verbatim.
create or replace function public.dn_theme_pack(p_theme text)
returns text language sql immutable
as $function$
  select case
    when p_theme = any (public.dn_live_packs())    then 'Trending words'
    when p_theme = any (public.dn_retired_themes()) then 'Retired pack'
    else 'Unrecognised'
  end;
$function$;

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

revoke execute on function public.dn_theme_pack(text) from public, anon, authenticated;
revoke execute on function public.dn_theme_unknown()  from public, anon, authenticated;

drop table if exists public.custom_themes;
