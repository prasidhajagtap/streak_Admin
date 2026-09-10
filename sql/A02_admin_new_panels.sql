-- ============================================================================
-- The Daily Nine, admin — three new panels: Sprint, Streaks, Segments.
--
-- WHY. The console was written on 7 September. Since then the game has gained
-- a sprint mode with its own three leaderboards, millisecond timing, a
-- calendar-day streak, and a word-pack choice — and the console can see none
-- of it. It does not contain the word "sprint" once.
--
-- ADDITIVE ONLY, DELIBERATELY. admin_overview, admin_players, admin_themes,
-- admin_daily, admin_flagged, admin_find_player, admin_reset_pin and
-- admin_set_min_build are NOT touched. Their definitions were not available
-- when this was written, and replacing a function you cannot read is how a
-- field the console renders silently disappears. Everything here is new, so
-- the console cannot break while these are added.
--
-- IT WRITES NOTHING. All three are STABLE, which Postgres enforces — a stable
-- function cannot write. They are SECURITY DEFINER because they read tables
-- the browser must never reach, and every one refuses without a valid admin
-- session first.
--
-- THE SESSION CHECK is copied from the shape of admin_sessions rather than
-- invented: token, username, expires_at. Same pattern the game uses for player
-- sessions. No admin session, no data — checked before anything else runs.
--
-- THE STREAK IS NOT REIMPLEMENTED HERE. The console and the game share one
-- database, so admin_streaks calls public.dn_streak, which is the same
-- function the game itself uses. If the streak rule changes again, the console
-- follows automatically instead of drifting. dn_streak is revoked from anon
-- and authenticated; these functions run as the owner, so they can still call
-- it.
--
-- Requires A01_theme_packs.sql for the pack split.
-- Safe to re-run. Rollback: A99_rollback_admin_panels.sql
-- Verify: A03_verify_admin_panels.sql
-- ============================================================================


-- ---------------------------------------------------------------- sprint ---
-- Everything the console has been blind to since sprint launched.
--
-- THE TWO CLOCKS. Sprint ran for ten minutes until 12_sprint_five_minutes and
-- five after it, and both kinds of run are still in the table. A ten-minute
-- run carries roughly twice the advantage for the same skill, so they are
-- reported separately rather than summed into one misleading number. The split
-- is on duration_sec, not scoring_version, for the same reason 22 uses it: a
-- player who quit a ten-minute sprint after four minutes did something
-- comparable to a five-minute run, and should not be filed under the old clock
-- for a clock they did not use.
create or replace function public.admin_sprint(p_token uuid, p_days int default 30)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
  v_days int := greatest(1, least(365, coalesce(p_days, 30)));
begin
  select username into v_admin
    from admin_sessions
   where token = p_token and expires_at > now();
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  return json_build_object(
    'ok', true,
    'totals', (
      select json_build_object(
        'runs_total',      count(*),
        'players_total',   count(distinct poornata_id),
        'cleared_total',   coalesce(sum(puzzles_cleared),0),
        'words_total',     coalesce(sum(words_found),0),
        'runs_today',      count(*) filter (where play_date = current_date),
        'players_today',   count(distinct poornata_id) filter (where play_date = current_date),
        'best_run',        coalesce(max(puzzles_cleared),0),
        'flagged',         count(*) filter (where flagged))
      from sprint_scores),

    -- How many registered players have never once opened sprint. This is the
    -- number that says whether sprint has a quality problem or a discovery
    -- problem.
    'never_sprinted', (
      select count(*) from players p
       where not exists (select 1 from sprint_scores s
                          where s.poornata_id = p.poornata_id)),

    'eras', (
      select coalesce(json_agg(e order by e.era), '[]'::json) from (
        select case when duration_sec <= 300 then '5-minute clock'
                    else '10-minute clock' end                as era,
               count(*)::int                                  as runs,
               count(distinct poornata_id)::int               as players,
               coalesce(sum(puzzles_cleared),0)::int          as cleared,
               round(avg(puzzles_cleared)::numeric, 1)        as avg_cleared,
               max(puzzles_cleared)::int                      as best_run,
               min(play_date)                                 as first_seen,
               max(play_date)                                 as last_seen
          from sprint_scores
         group by 1) e),

    'by_player', (
      select coalesce(json_agg(r order by r.cleared desc, r.best_run desc), '[]'::json) from (
        select pl.username,
               count(*)::int                                            as runs,
               coalesce(sum(s.puzzles_cleared),0)::int                  as cleared,
               coalesce(sum(s.words_found),0)::int                      as words,
               max(s.puzzles_cleared)::int                              as best_run,
               -- what they have done on the CURRENT clock, which is the only
               -- part that is comparable between players today
               coalesce(sum(s.puzzles_cleared) filter (where s.duration_sec <= 300),0)::int
                                                                        as cleared_5min,
               count(*) filter (where s.duration_sec > 300)::int         as runs_10min,
               min(s.play_date)                                         as first_played,
               max(s.play_date)                                         as last_played,
               bool_or(s.flagged)                                       as flagged
          from sprint_scores s
          join players pl using (poornata_id)
         group by pl.username) r),

    -- NOTE the alias is dd, not d. The column is called d because the
    -- console's chart helper reads r.d for the label, and if the subquery were
    -- also aliased d then json_agg(d) would resolve to the COLUMN and return a
    -- bare list of dates instead of rows. It did exactly that the first time.
    'by_day', (
      select coalesce(json_agg(dd order by dd.d), '[]'::json) from (
        select play_date::text                        as d,
               count(*)::int                          as runs,
               count(distinct poornata_id)::int       as players,
               coalesce(sum(puzzles_cleared),0)::int  as cleared
          from sprint_scores
         where play_date >= current_date - v_days
         group by play_date) dd)
  );
end;
$function$;


-- --------------------------------------------------------------- streaks ---
-- The streak is the retention number now, and the console only knew a
-- yes/no. This gives the length, and more usefully, who is about to lose one.
create or replace function public.admin_streaks(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
begin
  select username into v_admin
    from admin_sessions
   where token = p_token and expires_at > now();
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  return json_build_object(
    'ok', true,
    'rows', (
      select coalesce(json_agg(r order by r.streak_days desc, r.days_played desc), '[]'::json)
      from (
        select pl.username,
               -- the game's own function, not a copy of its rule
               public.dn_streak(pl.poornata_id, current_date)          as streak_days,
               exists (select 1 from scores s2
                        where s2.poornata_id = pl.poornata_id
                          and s2.play_date = current_date)             as played_today,
               count(distinct s.play_date)::int                        as days_played,
               max(s.play_date)                                        as last_played,
               (current_date - max(s.play_date))::int                  as days_since
          from players pl
          join scores s using (poornata_id)
         group by pl.poornata_id, pl.username) r),

    'totals', (
      select json_build_object(
        'on_a_streak', count(*) filter (where st > 0),
        'at_risk',     count(*) filter (where st > 0 and not pt),
        'safe_today',  count(*) filter (where st > 0 and pt),
        'longest',     coalesce(max(st), 0))
      from (
        select public.dn_streak(pl.poornata_id, current_date) as st,
               exists (select 1 from scores s2
                        where s2.poornata_id = pl.poornata_id
                          and s2.play_date = current_date)    as pt
          from players pl
         where exists (select 1 from scores s3
                        where s3.poornata_id = pl.poornata_id)) x)
  );
end;
$function$;


-- -------------------------------------------------------------- segments ---
-- How the daily data actually breaks down: which pack, which scoring era, and
-- how much of it carries milliseconds. All three are things the console had no
-- way to see, and the era split in particular is why its trend charts have
-- been quietly averaging two different games together.
create or replace function public.admin_segments(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
begin
  select username into v_admin
    from admin_sessions
   where token = p_token and expires_at > now();
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  return json_build_object(
    'ok', true,

    -- The pack is inferred from the theme, because the player's choice never
    -- reaches the database. See A01 for why, and unknown_themes below for how
    -- the inference tells you when it has gone stale.
    'packs', (
      select coalesce(json_agg(p order by p.plays desc), '[]'::json) from (
        select public.dn_theme_pack(s.theme)                as pack,
               count(*)::int                                as plays,
               count(distinct s.poornata_id)::int           as players,
               count(*) filter (where s.solved)::int        as solved,
               round(100.0 * count(*) filter (where s.solved) / nullif(count(*),0), 1) as pct,
               round(avg(s.time_sec)::numeric, 1)           as avg_time,
               round(avg(s.total_points)::numeric, 1)       as avg_points
          from scores s
         where s.theme is not null
         group by 1) p),

    -- The daily clock was 600 seconds until 21 August and 300 after it. Both
    -- eras award 300 points times the fraction of clock remaining, so only the
    -- clock changed - but that doubled what a second costs, and
    -- scoring_version was never bumped, so the two are indistinguishable
    -- except by arithmetic. A solved row satisfies exactly one of these.
    'daily_eras', (
      select coalesce(json_agg(e order by e.era), '[]'::json) from (
        select case when time_points = 300 - time_sec           then '5-minute clock'
                    when time_points = (600 - time_sec) / 2     then '10-minute clock'
                    else 'fits neither' end                     as era,
               count(*)::int                                    as games,
               round(avg(total_points)::numeric, 1)             as avg_points,
               round(avg(time_sec)::numeric, 1)                 as avg_time,
               min(play_date)                                   as first_seen,
               max(play_date)                                   as last_seen
          from scores
         where solved
         group by 1) e),

    -- How much of the table can actually be tie-broken. Rows from before
    -- 14_score_tiebreak hold null and fall back to the middle of their second.
    'ms_coverage', (
      select json_build_object(
        'rows_total',   count(*),
        'with_ms',      count(time_ms),
        'without_ms',   count(*) filter (where time_ms is null),
        'pct',          round(100.0 * count(time_ms) / nullif(count(*),0), 1))
      from scores),

    -- Must be empty. Anything here is a theme the game plays that A01 does not
    -- know about, which means the pack split above is understating ABG.
    'unknown_themes', (
      select coalesce(json_agg(json_build_object('theme', theme, 'plays', plays)), '[]'::json)
        from public.dn_theme_unknown())
  );
end;
$function$;


-- ---------------------------------------------------------------- grants ---
-- The console calls these with the anon key and its own admin session token,
-- exactly as it already calls admin_overview. The token is what proves who the
-- caller is; anon still cannot read scores, players, sessions, sprint_scores,
-- admins or admin_sessions directly.
grant execute on function public.admin_sprint(uuid, int) to anon;
grant execute on function public.admin_streaks(uuid)     to anon;
grant execute on function public.admin_segments(uuid)    to anon;
