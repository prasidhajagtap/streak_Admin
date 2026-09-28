# Word Vibe — Admin console

**The control room for [Word Vibe](https://prasidhajagtap.github.io/puzzle_abg1/),
a daily word-search game.**

- **Open:** https://prasidhajagtap.github.io/streak_Admin/ (the capital **A**
  matters: GitHub Pages is case-sensitive, and the lower-case address shows a 404)
- **The game:** [prasidhajagtap/puzzle_abg1](https://github.com/prasidhajagtap/puzzle_abg1)

Like the game, it is **one HTML file** with **no third-party scripts**, and it
wears the game's look: the same dark palette and the same brush font. It reads
and writes the game's Supabase database through admin-only functions, and can
see nothing else.

---

## What it does

Eight tabs, each answering one question:

| tab | what you see |
|---|---|
| **Overview** | today at a glance: games, solves, new players, average score and time; all-time totals; the top five today; scores flagged as implausible |
| **Trends** | games and sign-ups per day, and a day-by-day table |
| **Players** | every player: when they joined, games, solves, points, best score, last played, which build they're on, and whether they've set a recovery word |
| **Themes** | how hard each theme is (completion rate, average time), and which word packs players are actually playing |
| **Custom themes** | upload a spreadsheet, check it, save it, and switch it on for every player (below) |
| **Sprint** | the 5-minute mode: runs, the best players, and the old 10-minute runs kept apart |
| **Streaks** | who is on a streak today, whose streak is about to break, and everyone's |
| **Settings** | which game builds are in use, forcing everyone up to a minimum build, and resetting a player's PIN |

It refreshes itself every minute if you tick *Auto*, but only while the tab is
open and visible, so a forgotten window doesn't poll the database all day.

---

## Custom themes

The newest tab turns a spreadsheet into a playable theme for everyone.

1. **Download the template.** It is a working 12-word example, and you can
   upload it as it is.
2. **Upload your sheet** (`.xlsx`, `.csv` or `.tsv`) with two columns: the
   **word**, and a one-line **fact** players see when they find it. A header
   row is optional.
3. **Check it.** Before anything is sent, the console shows:
   - how many words are usable (out of 50)
   - how many different puzzles those words can make
   - every word and fact exactly as it will be stored
   - every skipped row, with the reason
4. **Save as draft**, then **Activate**. The game's locked *Themes* card turns
   lime for every player on build 46 or later, the next time they open the
   menu, with no reload.

| rule | why |
|---|---|
| 5 to 50 usable words | with 4, the puzzle builder fails every time; 50 was measured to lay out cleanly |
| 12 or more recommended | 12 words give 792 different puzzles; 5 give exactly one |
| 3–9 letters, A–Z only | the grid is 9×9, and a longer word can never be placed |
| facts up to 160 characters | a longer fact overflows its card |
| up to 20 live at once | the game lists every live theme on one screen |

**A theme that has been played can't be deleted, only switched off.** Scores
store the theme by its name, so deleting it would leave those games unexplained
in the reports. *Switch off* hides it from players and keeps the history.

**The spreadsheet reader is written from scratch.** An `.xlsx` is a ZIP of XML
files, and the browser can already unzip (`DecompressionStream`) and read XML
(`DOMParser`). So the console loads no library, and nothing third-party ever
runs next to the project key.
- It refuses files over 2 MB.
- It stops any workbook that expands past 16 MB, so a 25 KB "zip bomb" is
  turned away instead of freezing the tab.
- It reads both shared and inline text cells.
- It refuses the pre-2007 `.xls` format and says how to fix it.

---

## Security

- **Only the public key, ever.** On the Connect screen you give the project URL
  and the *anon / publishable* key. The key is kept in this browser only, and
  the console **refuses a secret key** (`service_role` or `sb_secret`) instead
  of storing it.
- **Signing in is separate from connecting.** An admin username and password
  give a session token that expires. Wrong passwords are counted, and
  repeated failures lock the account for 15 minutes.
- **Every admin function checks the session first.** Each one is a
  `SECURITY DEFINER` function that looks the token up in `admin_sessions`
  before it does anything. No valid session means no data, and the console
  sends you back to sign in.
- **The browser can't touch a table directly.** The custom-themes table has
  row-level security on and every privilege removed from `public`, `anon`
  *and* `authenticated`. On Supabase, removing it from `public` alone still
  leaves the other two able to read it.
- **The database never trusts the console.** Every rule in the table above is
  checked again on the server, so a request that goes around this page still
  can't store a theme the game can't build.
- **Nothing uploaded can run.** Every word, fact and name is escaped wherever
  it's shown. Script put into a spreadsheet appears as plain text.

---

## Database scripts

Run these in the Supabase SQL editor, **in order, after the game's own
scripts**. The editor shows only the *last* result in a file, so the newer
scripts end with a single checklist table where every row should read
`ok = true`.

```
A01_theme_packs.sql            the first pack split (superseded by A04)
A02_admin_new_panels.sql       the Sprint, Streaks and pack panels
A03_verify_admin_panels.sql
A04_trending_packs.sql         the 7 trending packs; 44 retired pack names kept for old scores
A05_verify_trending_packs.sql
A06_custom_themes.sql          the custom themes table, its admin functions, and the game's read
A07_verify_custom_themes.sql
A08_retired_theme_names.sql    five early pack names A04 missed; ends in a checklist
A99_rollback_*.sql             one for each risky change
```

**How A08 was found.** A07 includes a "drift alarm": a query listing any theme
in the score history that no pack list recognises. On the live database it
found five: the game's very first packs, from before the list in A04 was
written, covering 27 real games. Rather than patching in just those five,
every theme name from all 80 versions of the game was checked against the
lists. There are 51 in all, and nothing else was missing.

---

## Testing

The custom-themes feature was tested end to end in a real browser against its
real SQL, on a local Postgres 16 set up like Supabase (same roles, same default
privileges). That run covered:
- 16 test spreadsheets, including a fake `.xls`, the zip bomb and a 2.5 MB file
- the name rules, saving, and refused duplicates
- script injection in facts
- Activate, Switch off and Delete
- an expired session

It passed **39 of 39** checks, and found and fixed three real bugs on the way:

- **After the first upload, Activate and Delete did nothing** until a reload.
  An empty list *replaces* the table element, which left the click handler on
  a table no longer on the page.
- **The "is live" confirmation was wiped** at once by the list reloading
  after it.
- **Re-uploading an edited file with the same name was ignored.** Browsers
  don't announce picking the same file twice.

---

## Credits

Designed and developed by **Prasidha Jagtap**.

Font: [Caveat Brush](https://fonts.google.com/specimen/Caveat+Brush) by
Impallari Type, SIL Open Font License 1.1, hosted here in `fonts/caveat-brush/`
with its licence. Archivo and Roboto Mono are served by Google Fonts.
