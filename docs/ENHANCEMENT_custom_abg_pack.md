# Future enhancement — a custom, admin-uploaded "About ABG" pack

Requested 10 September 2026. **Not built.** This is the note so the decisions
are already made when it is.

## The idea

An admin uploads a file of words and their facts. Once pushed, players
choosing **About ABG** get those themes instead of the fifteen built into the
game.

---

## Use a spreadsheet, not a PDF

A PDF is a *layout* format. Extracting text from one gives you a stream of
fragments in reading order with no reliable structure — you cannot tell a word
from its description except by guessing at font size or position, and the guess
breaks the first time someone changes the template. Every hour spent on PDF
parsing is an hour not spent on the feature.

**CSV or XLSX, two columns.** Unambiguous, editable in Excel, and validates in
a few lines.

```
word,fact
GRASIM,An Aditya Birla Group flagship in fibre, chemicals and paints.
HINDALCO,Aluminium and copper, and one of the largest rolled-products makers.
```

The theme name comes from a field in the admin form, not from the file — one
file is one theme.

## The rules a word has to obey, taken from the live game

Measured against the 316 words shipping in build 26:

| Rule | Value | Why |
|---|---|---|
| Characters | **A–Z only** | all 316 existing words are plain uppercase letters, no spaces, digits or punctuation |
| Length | **3 to 9** | the grid is 9×9 and `CONFIG.maxWordLen` is 9; a 10-letter word cannot be placed |
| Words per theme | **6 minimum, 8–12 ideal** | the game draws `wordsPerDay: 5` from the pool, so a pool of exactly 5 gives the same puzzle every time |
| Fact | one sentence, no line breaks | shown on the answers screen after the game |
| Duplicates | rejected | the same word twice in one grid is unplaceable |

The admin panel should validate on upload and show every failing row **before**
the Push button does anything — a half-loaded theme is worse than a rejected
file.

## The part that is not small, and should be said now

**The words currently ship inside `index.html`.** `THEMES` is a hardcoded array
in the game file. Nothing about themes is in the database today.

So this feature is not an admin-panel change with a small game change attached.
It needs:

1. **Two new tables** — `custom_themes` and `custom_words` — plus an admin RPC
   to write them and a public one to read them.
2. **The game fetching its ABG pack at runtime** instead of reading its own
   array. That is a real change to the game's start-up path, and it needs a
   fallback: if the fetch fails, the built-in fifteen themes must still work,
   or an offline player gets no game at all.
3. **A decision about what "instead of" means.** Replace the fifteen entirely,
   or add to them? Replacing means one bad upload takes the whole ABG pack
   down. Adding is safer and probably what is actually wanted.
4. **Versioning.** If a player is mid-game when a new pack is pushed, their
   grid must not change under them. The same rule the build updater already
   follows: never swap something out while a game is running.

## Suggested order, when it is picked up

1. Tables + admin upload + validation, with the game untouched. Nothing changes
   for players; the data just starts existing and can be reviewed.
2. Game reads custom themes **in addition to** the built-in fifteen, behind a
   flag, with the built-ins as the fallback.
3. Only once that is proven: an option to hide the built-ins.

Doing it in that order means every step is reversible and no step can leave
players without a game.
