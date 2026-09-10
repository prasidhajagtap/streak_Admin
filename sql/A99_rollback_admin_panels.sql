-- ============================================================================
-- Undo A01_theme_packs.sql and A02_admin_new_panels.sql.
--
-- Everything they added was NEW — no existing function was replaced — so
-- dropping them puts the database back exactly as it was. Dropping a function
-- takes its grants with it, so there is nothing else to clean up.
--
-- Order matters: the three admin RPCs call the pack helpers, so they come off
-- first. "if exists" throughout, so a partial rollback does not stop half way.
--
-- THE CONSOLE KEEPS WORKING WITHOUT THEM. Each new panel calls its RPC inside
-- a try/catch: a 404 leaves that panel empty and the rest of the dashboard
-- untouched. Verified in a browser against a database with these functions
-- absent — Overview, Trends, Players, Themes and Settings all still render.
--
-- This does NOT touch public.dn_streak, which belongs to the game (sql/24 in
-- puzzle_abg1), not to the admin console. admin_streaks only called it.
--
-- Nothing here touches a score.
-- ============================================================================

drop function if exists public.admin_segments(uuid);
drop function if exists public.admin_streaks(uuid);
drop function if exists public.admin_sprint(uuid, int);

drop function if exists public.dn_theme_unknown();
drop function if exists public.dn_theme_pack(text);
drop function if exists public.dn_abg_themes();
