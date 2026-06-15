# 6. Drop the 3rd Stat Priority; Stat Tier becomes 1st + 2nd

Date: 2026-06-15

## Status

Accepted

Supersedes the "2nd and 3rd weighted equally" portion of [[0005]] (shipped as
commit #5).

## Context

The Stat Priority lens shipped with three ranked dropdowns (1st/2nd/3rd), and
[[0005]] weighted the 2nd and 3rd equally as a "secondary" group so that **Gold**
meant "has the 1st *and* at least one of the 2nd/3rd." This gave the player
flexibility — two acceptable secondaries to complete a Gold.

Early user feedback was that three stat dropdowns are **confusing**. Players read
the three ranks as a strict hierarchy and were unsure what the 3rd actually did,
especially once 2nd and 3rd were weighted equally. The practical workflow people
reach for is simpler: set a 1st and 2nd, and *swap the picks* to shop around for
other secondaries.

Independently, we want a new **Loot Filter** control (All / Bronze & up / Silver
& up / Gold only / Favorited) on the same toolbar row, and that row is tight on
space. The 3rd Stat Priority dropdown is the natural slot to reclaim.

## Decision

Remove the 3rd Stat Priority dropdown. Stat Priority is now 1st + 2nd only, and
**Stat Tier** grades by presence of those two:

- **Gold** — has the 1st *and* the 2nd.
- **Silver** — has the 1st only.
- **Bronze** — has the 2nd but not the 1st.
- none otherwise.

A single-stat priority still caps at Silver. The reclaimed toolbar slot holds the
new Loot Filter dropdown.

## Consequences

- Gold is now stricter: it demands the player's one specific 2nd stat rather than
  "either of two secondaries." Gold becomes rarer and the lens pickier — accepted,
  since swapping the 2nd pick is the intended way to explore alternatives.
- The "2nd and 3rd weighted equally" rule from [[0005]] is now moot — there is no
  3rd to weight. The scoring engine already degraded gracefully to "1st and 2nd"
  when no 3rd was set, so the change is a removal, not a rewrite.
- Simpler mental model and one fewer control on a crowded row; the freed space
  carries the Loot Filter.
- Reversible if needed (re-add the dropdown and the secondary-group rule), but the
  product direction is two stats.
