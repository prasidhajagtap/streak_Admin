-- ============================================================================
-- Verify A01_theme_packs.sql and A02_admin_new_panels.sql. READS ONLY.
-- ============================================================================

-- 1. The three new RPCs exist, are SECURITY DEFINER, and cannot write.
--    STABLE is enforced by Postgres, so this is the guarantee, not a promise.
--    Expect three rows, all true.
select p.proname, pg_get_function_arguments(p.oid) as arguments,
       p.prosecdef                as security_definer,
       p.provolatile in ('s','i') as cannot_write
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public'
   and p.proname in ('admin_sprint','admin_streaks','admin_segments')
 order by p.proname;

-- 2. The console can call them. Expect three trues.
select has_function_privilege('anon','public.admin_sprint(uuid,int)','EXECUTE')  as anon_sprint,
       has_function_privilege('anon','public.admin_streaks(uuid)','EXECUTE')     as anon_streaks,
       has_function_privilege('anon','public.admin_segments(uuid)','EXECUTE')    as anon_segments;

-- 3. THE ONE TO READ. The helpers must NOT be callable by the browser.
--    Revoking from PUBLIC alone is not enough on Supabase — it separately
--    grants EXECUTE to anon and authenticated on anything created in this
--    schema. Expect all six false.
select has_function_privilege('anon','public.dn_theme_pack(text)','EXECUTE')             as anon_pack,
       has_function_privilege('anon','public.dn_abg_themes()','EXECUTE')                 as anon_list,
       has_function_privilege('anon','public.dn_theme_unknown()','EXECUTE')              as anon_unknown,
       has_function_privilege('authenticated','public.dn_theme_pack(text)','EXECUTE')    as auth_pack,
       has_function_privilege('authenticated','public.dn_abg_themes()','EXECUTE')        as auth_list,
       has_function_privilege('authenticated','public.dn_theme_unknown()','EXECUTE')     as auth_unknown;

-- 4. The tables underneath stay shut to the browser. Expect all false.
select has_table_privilege('anon','public.scores','SELECT')         as anon_scores,
       has_table_privilege('anon','public.players','SELECT')        as anon_players,
       has_table_privilege('anon','public.sprint_scores','SELECT')  as anon_sprint_tbl,
       has_table_privilege('anon','public.admins','SELECT')         as anon_admins,
       has_table_privilege('anon','public.admin_sessions','SELECT') as anon_admin_sessions;

-- 5. A bad token gets nothing from any of them.
--    Expect three rows of {"ok": false, "error": "NO_SESSION"}.
select 'admin_sprint'   as fn, public.admin_sprint('00000000-0000-0000-0000-000000000000'::uuid, 30) as result
union all
select 'admin_streaks',      public.admin_streaks('00000000-0000-0000-0000-000000000000'::uuid)
union all
select 'admin_segments',     public.admin_segments('00000000-0000-0000-0000-000000000000'::uuid);

-- 6. An EXPIRED admin session is refused too, not just an unknown one. This is
--    the check that matters more: an unknown token is obviously wrong, an
--    expired one looks right. Expect ok:false for any expired row.
select s.username, s.expires_at,
       public.admin_streaks(s.token) as result
  from public.admin_sessions s
 where s.expires_at <= now()
 limit 3;

-- 7. THE DRIFT CHECK. Must return zero rows. Anything here is a theme the game
--    plays that A01 does not know about, which means the pack split in the
--    console is understating About ABG. If this is not empty, update the list
--    in A01 from index.html and re-run it.
select * from public.dn_theme_unknown();

-- 8. What the new panels will actually show you, as a sanity read.
select 'sprint runs on record'       as fact,
       (public.admin_sprint((select token from public.admin_sessions
                              where expires_at > now() limit 1), 30)
        ->'totals'->>'runs_total')   as value
union all
select 'players who never sprinted',
       (public.admin_sprint((select token from public.admin_sessions
                              where expires_at > now() limit 1), 30)
        ->>'never_sprinted')
union all
select 'players on a streak right now',
       (public.admin_streaks((select token from public.admin_sessions
                               where expires_at > now() limit 1))
        ->'totals'->>'on_a_streak')
union all
select 'about to LOSE a streak today',
       (public.admin_streaks((select token from public.admin_sessions
                               where expires_at > now() limit 1))
        ->'totals'->>'at_risk')
union all
select 'scores carrying milliseconds',
       (public.admin_segments((select token from public.admin_sessions
                                where expires_at > now() limit 1))
        ->'ms_coverage'->>'pct') || '%';
