-- =====================================================================
--  Announcement banners
--  Run this once in the Supabase SQL editor.
--
--  READ THIS FIRST
--  Every function below checks the admin token by calling
--  public.banner_admin_id(). That function is the ONLY part written
--  blind, because this repo does not contain the rest of your schema.
--  Open it, point it at whatever table admin_login() writes its token
--  into, and check it returns the admin id. Nothing else needs editing.
-- =====================================================================

-- ---------------------------------------------------------------
-- 0. ADAPT ME. Return the admin id for a live token, else null.
-- ---------------------------------------------------------------
create or replace function public.banner_admin_id(p_token text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_id bigint;
begin
  if p_token is null or length(p_token) < 10 then
    return null;
  end if;

  -- >>> CHANGE THIS QUERY TO MATCH YOUR ADMIN SESSION TABLE <<<
  select s.admin_id into v_id
    from public.admin_sessions s
   where s.token = p_token
     and s.expires_at > now();

  return v_id;
end $$;

-- ---------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------
create table if not exists public.app_banners (
  id          uuid primary key default gen_random_uuid(),
  kind        text        not null default 'text'
                          check (kind in ('text','image')),
  title       text,
  body        text,
  image       text,          -- a data: URI, already shrunk by the admin panel
  image_alt   text,
  tone        text        not null default 'info'
                          check (tone in ('info','success','warn','urgent')),
  link_url    text,
  link_label  text,
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  bigint,

  -- a text banner needs words, a picture banner needs a picture and a description
  constraint banner_has_content check (
    (kind = 'text'  and (coalesce(title,'') <> '' or coalesce(body,'') <> ''))
    or
    (kind = 'image' and coalesce(image,'') <> '' and coalesce(image_alt,'') <> '')
  ),
  -- a link and its button text travel together
  constraint banner_link_pair check (
    (link_url is null and link_label is null)
    or (link_url is not null and link_label is not null)
  ),
  constraint banner_link_https check (
    link_url is null or link_url like 'https://%'
  ),
  constraint banner_window check (ends_at is null or ends_at > starts_at),
  -- the admin panel shrinks pictures; this is the backstop, roughly 400 KB
  constraint banner_image_size check (image is null or length(image) < 560000)
);

create index if not exists app_banners_live_idx
  on public.app_banners (active, starts_at desc);

-- Locked down: no direct reads or writes with the anon key.
-- Everything goes through the functions below.
alter table public.app_banners enable row level security;

-- ---------------------------------------------------------------
-- 2. What the GAME calls. No token: this is public by design.
--    Returns the one banner to show, or null.
-- ---------------------------------------------------------------
create or replace function public.game_active_banner()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select case when b.id is null then null else json_build_object(
           'id',          b.id,
           'kind',        b.kind,
           'title',       b.title,
           'body',        b.body,
           'image',       b.image,
           'image_alt',   b.image_alt,
           'tone',        b.tone,
           'link_url',    b.link_url,
           'link_label',  b.link_label,
           'updated_at',  b.updated_at
         ) end
    from (
      select * from public.app_banners
       where active
         and starts_at <= now()
         and (ends_at is null or ends_at > now())
       order by starts_at desc, created_at desc
       limit 1
    ) b;
$$;

-- ---------------------------------------------------------------
-- 3. What the ADMIN PANEL calls
-- ---------------------------------------------------------------

-- List. Deliberately leaves the picture out so the page stays light.
create or replace function public.admin_banners(p_token text, p_limit int default 60)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_admin bigint;
begin
  v_admin := public.banner_admin_id(p_token);
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  return json_build_object('ok', true, 'rows', coalesce((
    select json_agg(r order by r.starts_at desc)
      from (
        select id, kind, title, body, image_alt, tone, link_url, link_label,
               starts_at, ends_at, active, created_at,
               (image is not null) as has_image
          from public.app_banners
         order by starts_at desc
         limit greatest(1, least(coalesce(p_limit, 60), 200))
      ) r
  ), '[]'::json));
end $$;

-- One full row, picture included. Used when the admin taps Edit.
create or replace function public.admin_banner_get(p_token text, p_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_admin bigint; v_row json;
begin
  v_admin := public.banner_admin_id(p_token);
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  select to_json(b) into v_row from public.app_banners b where b.id = p_id;
  if v_row is null then
    return json_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;
  return json_build_object('ok', true, 'row', v_row);
end $$;

-- Create when p_id is null, otherwise update that row.
create or replace function public.admin_banner_save(
  p_token      text,
  p_id         uuid    default null,
  p_kind       text    default 'text',
  p_title      text    default null,
  p_body       text    default null,
  p_image      text    default null,
  p_image_alt  text    default null,
  p_tone       text    default 'info',
  p_link_url   text    default null,
  p_link_label text    default null,
  p_starts_at  timestamptz default null,
  p_ends_at    timestamptz default null,
  p_active     boolean default true
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_admin bigint; v_id uuid;
begin
  v_admin := public.banner_admin_id(p_token);
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  if p_kind not in ('text','image') then
    return json_build_object('ok', false, 'error', 'BAD_KIND');
  end if;
  if p_image is not null and p_image !~ '^data:image/(png|jpeg|webp|gif);base64,' then
    return json_build_object('ok', false, 'error', 'BAD_IMAGE');
  end if;

  if p_id is null then
    insert into public.app_banners
      (kind,title,body,image,image_alt,tone,link_url,link_label,
       starts_at,ends_at,active,created_by)
    values
      (p_kind,p_title,p_body,p_image,p_image_alt,coalesce(p_tone,'info'),p_link_url,p_link_label,
       coalesce(p_starts_at, now()), p_ends_at, coalesce(p_active,true), v_admin)
    returning id into v_id;
  else
    update public.app_banners set
      kind=p_kind, title=p_title, body=p_body,
      -- keep the stored picture when the panel sends null for a picture banner
      image = case when p_kind='image' then coalesce(p_image, image) else null end,
      image_alt = case when p_kind='image' then p_image_alt else null end,
      tone=coalesce(p_tone, tone), link_url=p_link_url, link_label=p_link_label,
      starts_at=coalesce(p_starts_at, starts_at), ends_at=p_ends_at,
      active=coalesce(p_active, active), updated_at=now()
     where id=p_id
     returning id into v_id;
    if v_id is null then
      return json_build_object('ok', false, 'error', 'NOT_FOUND');
    end if;
  end if;

  return json_build_object('ok', true, 'id', v_id);
exception
  when check_violation then
    return json_build_object('ok', false, 'error', 'INVALID: ' || sqlerrm);
end $$;

-- Start or stop one, without touching anything else.
create or replace function public.admin_banner_active(
  p_token text, p_id uuid, p_active boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_admin bigint; v_id uuid;
begin
  v_admin := public.banner_admin_id(p_token);
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  update public.app_banners
     set active = coalesce(p_active, false), updated_at = now()
   where id = p_id
   returning id into v_id;

  if v_id is null then
    return json_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;
  return json_build_object('ok', true, 'id', v_id, 'active', p_active);
end $$;

create or replace function public.admin_banner_delete(p_token text, p_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_admin bigint; v_id uuid;
begin
  v_admin := public.banner_admin_id(p_token);
  if v_admin is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  delete from public.app_banners where id = p_id returning id into v_id;
  if v_id is null then
    return json_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;
  return json_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------
-- 4. Who may call what
-- ---------------------------------------------------------------
-- Postgres grants EXECUTE to PUBLIC by default, so revoking from anon alone
-- leaves the function callable. PUBLIC must be revoked too. The admin_*
-- functions below still reach it: they run as the definer, not the caller.
revoke all on function public.banner_admin_id(text) from public, anon, authenticated;

grant execute on function public.game_active_banner()                to anon, authenticated;
grant execute on function public.admin_banners(text,int)             to anon, authenticated;
grant execute on function public.admin_banner_get(text,uuid)         to anon, authenticated;
grant execute on function public.admin_banner_save(
  text,uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,boolean)
                                                                     to anon, authenticated;
grant execute on function public.admin_banner_active(text,uuid,boolean) to anon, authenticated;
grant execute on function public.admin_banner_delete(text,uuid)      to anon, authenticated;

-- The admin functions are reachable with the public anon key, exactly like
-- your existing admin_* functions. The admin token checked inside each one
-- is what actually protects them.
