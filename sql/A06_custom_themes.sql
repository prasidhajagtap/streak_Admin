-- ============================================================================
-- Word Vibe — custom themes: upload in the console, switch on for everyone.
--
-- WHAT THIS ADDS
--   * custom_themes     one row per uploaded theme: a name and its words, each
--                       word with a one-line fact. Status is draft, live or off.
--   * admin_custom_theme_save / _list / _set_status / _delete
--                       what the console's Custom themes tab calls.
--   * live_custom_themes()
--                       what the GAME calls. Returns only the live themes. The
--                       moment one exists, the game's locked Themes tab opens.
--   * dn_theme_pack     learns a fourth answer, 'Custom themes', so a score
--                       played on an uploaded theme is not reported as
--                       'Unrecognised' drift in the console's pack split.
--
-- THE BROWSER NEVER TOUCHES THE TABLE. RLS is on with no policies, and every
-- table privilege is revoked from public, anon and authenticated. Supabase
-- grants anon and authenticated separately from PUBLIC through its default
-- privileges, so all three are named - revoking from PUBLIC alone would leave
-- the table readable. Everything goes through SECURITY DEFINER functions.
--
-- THE CONSOLE IS NOT TRUSTED EITHER. It validates a spreadsheet before
-- sending it, but dn_clean_theme() repeats every rule here, on the server, so
-- a request that skips the console cannot store a word the grid cannot hold
-- or a theme the builder cannot build. The limits are the ones measured
-- against the game's own puzzle builder:
--     5 to 50 usable words      (4 builds nothing; 50 measured clean)
--     3 to 9 letters, A-Z only  (the grid is 9x9; longer is silently dropped)
--     facts up to 160 chars     (the fact card overflows beyond that)
--     names up to 40 chars, from a plain character set
--
-- A THEME THAT HAS BEEN PLAYED CANNOT BE DELETED, only switched off. Scores
-- store the theme by name, so deleting it would turn every one of those
-- scores into 'Unrecognised' in the console. Off keeps the row, so history
-- still classifies, and the game stops offering it.
--
-- Requires A04_trending_packs.sql (dn_live_packs, dn_retired_themes).
-- Safe to re-run. Rollback: A99_rollback_custom_themes.sql
-- Verify: A07_verify_custom_themes.sql
-- ============================================================================


-- ------------------------------------------------------------------ table ---
create table if not exists public.custom_themes (
  id           bigint generated always as identity primary key,
  name         text        not null,
  words        jsonb       not null,
  word_count   int         not null check (word_count between 5 and 50),
  status       text        not null default 'draft'
                           check (status in ('draft','live','off')),
  created_by   text        not null,
  created_at   timestamptz not null default now(),
  activated_at timestamptz,
  updated_at   timestamptz not null default now()
);
-- One name, whatever the case, so the game and the console can never show
-- two themes that look identical.
create unique index if not exists custom_themes_name_ci on public.custom_themes (lower(name));
create index        if not exists custom_themes_live    on public.custom_themes (status) where status = 'live';

alter table public.custom_themes enable row level security;
revoke all on table    public.custom_themes        from public, anon, authenticated;
revoke all on sequence public.custom_themes_id_seq from public, anon, authenticated;


-- -------------------------------------------------------------- validator ---
-- The server's copy of the console's rules. Returns the cleaned theme, never
-- raises: errors come back as codes so the console can say what went wrong.
create or replace function public.dn_clean_theme(p_name text, p_words jsonb)
returns jsonb language plpgsql stable
set search_path to 'public','pg_catalog'
as $function$
declare
  v_name   text := btrim(regexp_replace(coalesce(p_name,''), '\s+', ' ', 'g'));
  v_out    jsonb  := '[]'::jsonb;
  v_seen   text[] := '{}';
  v_errors text[] := '{}';
  v_item   jsonb;
  v_w      text;
  v_f      text;
  n        int;
begin
  if v_name = ''                                  then v_errors := v_errors || 'NAME_EMPTY'::text;    end if;
  if char_length(v_name) > 40                     then v_errors := v_errors || 'NAME_TOO_LONG'::text; end if;
  -- A plain set, on purpose: the name is shown on a banner, a leaderboard
  -- row and a share message. It is escaped everywhere it is drawn, but there
  -- is no reason to accept markup characters in the first place.
  if v_name !~ '^[A-Za-z0-9 &''.,!?()-]*$'        then v_errors := v_errors || 'NAME_CHARS'::text;    end if;
  -- A custom theme may not share a name with a trending or retired pack, or
  -- the console could not tell whose score is whose.
  if exists (select 1 from unnest(public.dn_live_packs() || public.dn_retired_themes()) x
              where lower(x) = lower(v_name))    then v_errors := v_errors || 'NAME_RESERVED'::text; end if;

  if jsonb_typeof(p_words) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'name', v_name, 'words', '[]'::jsonb, 'count', 0,
                              'errors', to_jsonb(v_errors || 'WORDS_NOT_A_LIST'::text));
  end if;
  -- Bounds the work one request can ask for. A legitimate sheet is 50 rows
  -- of usable words plus whatever it skips; 500 is far past that.
  if jsonb_array_length(p_words) > 500 then
    return jsonb_build_object('ok', false, 'name', v_name, 'words', '[]'::jsonb, 'count', 0,
                              'errors', to_jsonb(v_errors || 'TOO_MANY_ROWS'::text));
  end if;

  for v_item in select value from jsonb_array_elements(p_words) loop
    continue when jsonb_typeof(v_item) <> 'object';
    v_w := upper(btrim(coalesce(v_item->>'w', '')));
    -- control characters become spaces, then runs of space collapse
    v_f := btrim(regexp_replace(regexp_replace(coalesce(v_item->>'f', ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g'));
    continue when v_w !~ '^[A-Z]{3,9}$';
    continue when v_w = any (v_seen);
    v_seen := v_seen || v_w;
    if char_length(v_f) > 160 then v_f := left(v_f, 159) || '…'; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('w', v_w, 'f', v_f));
  end loop;

  n := jsonb_array_length(v_out);
  if n < 5  then v_errors := v_errors || 'TOO_FEW_WORDS'::text;  end if;
  if n > 50 then v_errors := v_errors || 'TOO_MANY_WORDS'::text; end if;

  return jsonb_build_object('ok', cardinality(v_errors) = 0, 'name', v_name,
                            'words', v_out, 'count', n, 'errors', to_jsonb(v_errors));
end;
$function$;


-- ------------------------------------------------------------ admin: save ---
create or replace function public.admin_custom_theme_save(p_token uuid, p_name text, p_words jsonb)
returns json language plpgsql security definer volatile
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
  v_clean jsonb;
  v_id    bigint;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;

  v_clean := public.dn_clean_theme(p_name, p_words);
  if not (v_clean->>'ok')::boolean then
    return json_build_object('ok', false, 'error', 'INVALID',
                             'errors', v_clean->'errors', 'count', (v_clean->>'count')::int);
  end if;
  -- A ceiling on stored themes, so the console list and the table stay sane.
  if (select count(*) from public.custom_themes) >= 100 then
    return json_build_object('ok', false, 'error', 'STORE_FULL');
  end if;

  insert into public.custom_themes (name, words, word_count, status, created_by)
  values (v_clean->>'name', v_clean->'words', (v_clean->>'count')::int, 'draft', v_admin)
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id, 'name', v_clean->>'name',
                           'count', (v_clean->>'count')::int);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'NAME_TAKEN');
end;
$function$;


-- ------------------------------------------------------------ admin: list ---
create or replace function public.admin_custom_theme_list(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare v_admin text;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;

  return json_build_object('ok', true, 'live_limit', 20, 'themes', coalesce((
    select json_agg(x order by
             case x.status when 'live' then 0 when 'draft' then 1 else 2 end,
             x.created_at desc)
      from (select t.id, t.name, t.word_count, t.status, t.created_by,
                   t.created_at, t.activated_at, t.words,
                   (select count(*) from public.scores s where s.theme = t.name) as plays
              from public.custom_themes t) x), '[]'::json));
end;
$function$;


-- ------------------------------------------------- admin: activate / off ---
create or replace function public.admin_custom_theme_set_status(p_token uuid, p_id bigint, p_status text)
returns json language plpgsql security definer volatile
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin text;
  v_name  text;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;
  if p_status not in ('live', 'off') then
    return json_build_object('ok', false, 'error', 'BAD_STATUS');
  end if;
  -- The game lists every live theme on one screen; twenty is plenty and keeps
  -- that screen, and the payload every player downloads, small.
  if p_status = 'live' and (select count(*) from public.custom_themes
                             where status = 'live' and id <> p_id) >= 20 then
    return json_build_object('ok', false, 'error', 'LIVE_LIMIT');
  end if;

  update public.custom_themes
     set status       = p_status,
         activated_at = case when p_status = 'live' then now() else activated_at end,
         updated_at   = now()
   where id = p_id
  returning name into v_name;
  if v_name is null then return json_build_object('ok', false, 'error', 'NOT_FOUND'); end if;

  return json_build_object('ok', true, 'id', p_id, 'name', v_name, 'status', p_status,
    'live_now', (select count(*) from public.custom_themes where status = 'live'));
end;
$function$;


-- ---------------------------------------------------------- admin: delete ---
create or replace function public.admin_custom_theme_delete(p_token uuid, p_id bigint)
returns json language plpgsql security definer volatile
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_admin  text;
  v_status text;
  v_name   text;
begin
  select username into v_admin from admin_sessions where token = p_token and expires_at > now();
  if v_admin is null then return json_build_object('ok', false, 'error', 'NO_SESSION'); end if;

  select status, name into v_status, v_name from public.custom_themes where id = p_id;
  if v_name is null then return json_build_object('ok', false, 'error', 'NOT_FOUND'); end if;
  if v_status = 'live' then return json_build_object('ok', false, 'error', 'IS_LIVE'); end if;
  if exists (select 1 from public.scores s where s.theme = v_name) then
    return json_build_object('ok', false, 'error', 'HAS_PLAYS');
  end if;

  delete from public.custom_themes where id = p_id;
  return json_build_object('ok', true, 'id', p_id);
end;
$function$;


-- ------------------------------------------------------------- the game ---
-- The only thing a player's browser can ask for. Live themes only, oldest
-- switched-on first, words and facts exactly as cleaned on the way in.
create or replace function public.live_custom_themes()
returns json language sql security definer stable
set search_path to 'public','pg_catalog'
as $function$
  select coalesce(json_agg(json_build_object('name', t.name, 'words', t.words)
                           order by t.activated_at, t.id), '[]'::json)
    from (select name, words, activated_at, id
            from public.custom_themes
           where status = 'live'
           order by activated_at, id
           limit 20) t;
$function$;


-- --------------------------------------------------------- pack split ---
-- STABLE now, not IMMUTABLE: it reads custom_themes, and an immutable
-- function that reads a table can be cached past a change to that table. It
-- is used only inside admin_segments and the verify scripts - no index or
-- stored column depends on it being immutable.
create or replace function public.dn_theme_pack(p_theme text)
returns text language sql stable
set search_path to 'public','pg_catalog'
as $function$
  select case
    when p_theme = any (public.dn_live_packs())                                   then 'Trending words'
    when exists (select 1 from public.custom_themes c where c.name = p_theme)     then 'Custom themes'
    when p_theme = any (public.dn_retired_themes())                               then 'Retired pack'
    else 'Unrecognised'
  end;
$function$;

create or replace function public.dn_theme_unknown()
returns table(theme text, plays bigint) language sql stable
set search_path to 'public','pg_catalog'
as $function$
  select s.theme, count(*)
    from public.scores s
   where s.theme is not null
     and not (s.theme = any (public.dn_live_packs()))
     and not (s.theme = any (public.dn_retired_themes()))
     and not exists (select 1 from public.custom_themes c where c.name = s.theme)
   group by s.theme
   order by 2 desc;
$function$;


-- -------------------------------------------------------------- grants ---
-- Strip every default grant first, from all three roles, then hand back
-- exactly what is needed. The console calls the admin functions with the anon
-- key plus its own session token, as it does admin_segments; the token is
-- what proves who is calling. The game calls live_custom_themes() only.
revoke execute on function public.dn_clean_theme(text, jsonb)                    from public, anon, authenticated;
revoke execute on function public.admin_custom_theme_save(uuid, text, jsonb)     from public, anon, authenticated;
revoke execute on function public.admin_custom_theme_list(uuid)                  from public, anon, authenticated;
revoke execute on function public.admin_custom_theme_set_status(uuid, bigint, text) from public, anon, authenticated;
revoke execute on function public.admin_custom_theme_delete(uuid, bigint)        from public, anon, authenticated;
revoke execute on function public.live_custom_themes()                           from public, anon, authenticated;
revoke execute on function public.dn_theme_pack(text)                            from public, anon, authenticated;
revoke execute on function public.dn_theme_unknown()                             from public, anon, authenticated;

grant execute on function public.admin_custom_theme_save(uuid, text, jsonb)       to anon;
grant execute on function public.admin_custom_theme_list(uuid)                    to anon;
grant execute on function public.admin_custom_theme_set_status(uuid, bigint, text) to anon;
grant execute on function public.admin_custom_theme_delete(uuid, bigint)          to anon;
grant execute on function public.live_custom_themes()                             to anon, authenticated;
