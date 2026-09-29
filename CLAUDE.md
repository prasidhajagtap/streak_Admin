# Word Vibe admin console — notes for Claude

The full project memory (owner's working rules, hard security rules, database
state, history) is in the game repo's `CLAUDE.md`:
https://github.com/prasidhajagtap/word_vibe/blob/main/CLAUDE.md — read it too.
Last updated 29 Sep 2026.

## This repo

- `prasidhajagtap/streak_Admin`, one file `index.html`. Live at
  https://prasidhajagtap.github.io/streak_Admin/ (capital A). Merging to
  `main` deploys it. The owner keeps the link private; the real protection is
  the admin sign-in (`admin_login`, with a lockout).
- Talks to the same Supabase project as the game, with the public anon key.
  Every `admin_*` function checks `admin_sessions` (token, `expires_at`) and
  returns `NO_SESSION` without one.
- **Never merge until the owner says "merge".** Same rules as the game repo.

## Tabs

Overview, Trends, Players (with **Hide a player**), Themes, Custom themes,
Sprint, Streaks, Settings.

## Database scripts

`sql/A01`–`A09`, run after the game's own `sql/` scripts. All run on the live
database as of 29 Sep 2026.
- `A04`/`A08`: retired theme names (44), including old ABG/Birla/HR pack
  names. They must stay: old scores carry those names.
- `A06`: custom themes (`CT_MIN_BUILD = 46` in `index.html`).
- `A09`: `admin_hide_player`, `admin_hidden_players`. Needs the game's
  `sql/35_fair_boards.sql` first.
- `A99_rollback_*` for the risky ones.

## Things that are easy to get wrong here

- `table()` replaces the table element (outerHTML) when there are no rows, so
  a click listener on the table is lost. **Listen on the pane** and use
  `closest()` (see `paneCustom` and `panePlayers`).
- All tables have `min-width:520px` (they scroll sideways in `.tblwrap`). For
  a table with action buttons that must stay on screen on a phone, keep it to
  two columns and set `min-width:0` on it (see `#tblHidden,#tblSuspect`).
- A file input needs its value cleared on click, or picking the same file
  again does nothing.
- Messages: clear only the message a loader wrote (`dataset.kind`), so an
  action's result line is not wiped by the reload that follows.
- Buttons in the Players and Custom themes panes are at least 44 px tall.
