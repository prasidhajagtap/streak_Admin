-- ============================================================================
-- Rollback for A09_hide_players.sql
--
-- Removes the two admin functions. It does NOT unhide anyone: players.hidden
-- belongs to word_vibe sql/35_fair_boards.sql, and its rollback decides what
-- the boards do with it. Run this BEFORE word_vibe 99_rollback_fair_boards.sql.
-- ============================================================================

drop function if exists public.admin_hide_player(uuid, text, boolean);
drop function if exists public.admin_hidden_players(uuid);

select (to_regprocedure('public.admin_hide_player(uuid,text,boolean)') is null
    and to_regprocedure('public.admin_hidden_players(uuid)') is null) as removed;
