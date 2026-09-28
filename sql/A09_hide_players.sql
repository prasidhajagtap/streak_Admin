-- ============================================================================
-- Word Vibe admin - hide a player from the leaderboards
--
-- NEEDS word_vibe sql/35_fair_boards.sql FIRST. That file adds
-- players.hidden, the name check, and the boards that leave hidden players
-- out. This file only adds the two admin functions that switch it on and off.
-- The guard below stops, changing nothing, if 35 has not been run.
--
-- WHAT HIDING DOES. The player drops off all six boards at once. They can
-- still sign in and play, and their scores are kept; nothing is deleted.
-- Unhide puts them straight back. Use it for a rude name, a fake "official"
-- name, or a player whose results are not believable.
--
-- Both functions check the admin session like every other admin_* function,
-- so the public key alone gets NO_SESSION.
--
-- THE LAST QUERY IS A CHECKLIST. Every row should read ok = true.
-- Safe to re-run. Rollback: A99_rollback_hide_players.sql
-- ============================================================================

do $guard$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'players'
                    and column_name = 'hidden')
     or to_regprocedure('public.dn_name_problem(text)') is null then
    raise exception 'STOPPED, nothing changed: run word_vibe sql/35_fair_boards.sql first';
  end if;
end
$guard$;


-- Hide (p_hide = true) or unhide (false) one player, by username.
-- Usernames are matched ignoring upper/lower case.
create or replace function public.admin_hide_player(p_token uuid, p_username text, p_hide boolean)
returns json language plpgsql security definer volatile
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
  v_pid   text;
  v_name  text;
  v_n     int;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;
  if p_hide is null or coalesce(trim(p_username), '') = '' then
    return json_build_object('ok', false, 'error', 'BAD_INPUT');
  end if;

  select count(*) into v_n from public.players where lower(username) = lower(trim(p_username));
  if v_n = 0 then return json_build_object('ok', false, 'error', 'NOT_FOUND'); end if;
  if v_n > 1 then return json_build_object('ok', false, 'error', 'AMBIGUOUS'); end if;

  update public.players
     set hidden    = p_hide,
         hidden_at = case when p_hide then now() else null end,
         hidden_by = case when p_hide then v_admin else null end
   where lower(username) = lower(trim(p_username))
  returning poornata_id, username into v_pid, v_name;

  return json_build_object('ok', true, 'username', v_name, 'hidden', p_hide,
    'hidden_now', (select count(*) from public.players where hidden));
end;
$function$;


-- Everyone hidden, newest first, plus up to 50 visible players whose names
-- the sign-up check would stop today (names chosen before it existed).
create or replace function public.admin_hidden_players(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare v_admin text;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;

  return json_build_object('ok', true,
    'hidden', coalesce((
      select json_agg(json_build_object('username', username, 'hidden_at', hidden_at,
                                        'hidden_by', hidden_by)
                      order by hidden_at desc nulls last, username)
        from public.players where hidden), '[]'::json),
    'suspect', coalesce((
      select json_agg(json_build_object('username', username, 'why', why) order by username)
        from (select username, why
                from (select username, public.dn_name_problem(username) as why
                        from public.players where not hidden) y
               where why is not null
               order by username
               limit 50) x), '[]'::json));
end;
$function$;


revoke execute on function public.admin_hide_player(uuid, text, boolean) from public;
revoke execute on function public.admin_hidden_players(uuid)             from public;
-- Like every admin_* function: callable with the public key, useless without
-- a live admin session token.
grant  execute on function public.admin_hide_player(uuid, text, boolean) to anon, authenticated;
grant  execute on function public.admin_hidden_players(uuid)             to anon, authenticated;


-- ------------------------------------------------------------- checklist ---
select n as "#", check_name, expected, actual, (expected = actual) as ok from (
  select 1 as n, 'admin_hide_player exists' as check_name, 'true' as expected,
         (to_regprocedure('public.admin_hide_player(uuid,text,boolean)') is not null)::text as actual
  union all
  select 2, 'admin_hidden_players exists', 'true',
         (to_regprocedure('public.admin_hidden_players(uuid)') is not null)::text
  union all
  select 3, 'without an admin session, hiding is refused', 'NO_SESSION',
         public.admin_hide_player('00000000-0000-0000-0000-000000000000'::uuid, 'anyone', true)->>'error'
  union all
  select 4, 'without an admin session, the list is refused', 'NO_SESSION',
         public.admin_hidden_players('00000000-0000-0000-0000-000000000000'::uuid)->>'error'
  union all
  select 5, 'both are SECURITY DEFINER with a fixed search_path', 'true',
         (select bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) s
                                                   where s like 'search_path=%'))::text
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('admin_hide_player','admin_hidden_players'))
) c order by n;
