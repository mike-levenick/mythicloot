# 8. Track Voidforge Claims as addon-maintained state, rebuilt from the container tooltip

Date: 2026-06-16

## Status

Accepted

A deliberate, scoped deviation from [[0002]] (runtime data, nothing maintained).

## Context

Midnight's Voidforge removes an item from a player's future Voidcore rolls once
they win it — per dungeon, per Gear Track, filtered to their loot specialization,
and with the whole pool **resetting** once fully exhausted (see CONTEXT.md:
Voidforge, Claim, Voidforge Pool). Showing "what's left" requires knowing the
player's **Claims**.

Blizzard exposes **no query API** for remaining or claimed Voidforge loot. This is
community-confirmed: existing tracker addons reconstruct the state from local
tracking plus Adventure Guide (EJ) data, and players complain there's no built-in
way to see it. That directly conflicts with 0002's "don't maintain data" — but
0002 assumed the game *had* a runtime source. Here it does not.

## Decision

Maintain Claim state **per character**, built from three sources:

1. **Popup snapshot (the backbone)** — when the roll offer opens after a dungeon,
   read its reward item: a **"Nebulous Voidcache: &lt;Dungeon&gt;"** instance whose
   *contextual* tooltip lists "Contains one of the following items:" — the remaining
   pool — and shows the Gear Track ("Upgrade Level: Myth"). So
   `claimed = (loot-spec-filtered pool) − (items still listed)`, and the **dungeon
   comes from the item name, the Track from the tooltip** — no shipped map needed.
   Poll until the tooltip is stable, with give-up caps.
2. **Live** — the roll-result event (the reused `BONUS_ROLL_RESULT`-family) to mark
   a win the instant it happens; *optional*, since the next popup snapshot reconciles.
3. **Manual** — a per-Drop toggle for the scopes no popup has covered yet (other
   dungeons/Tracks, or before the player has rolled there).

**Reconciliation is proof &gt; assertion.** A Claim means "currently removed from
the Pool" (rollable state), not lifetime history — so the popup snapshot is ground
truth and *replaces* (not merges) the Claim state for its scope: it clears manual
"won" marks the game proves are still rollable, and adds Claims the player never
marked. Manual marks only stand where no snapshot has spoken. When a snapshot clears
a manual mark, surface a one-line notice so the correction isn't mysterious.

Key Claims by **dungeon + Track** (both read off the Voidcache instance). Handle the
**exhaustion reset**: the popup always reflects current truth, so a snapshot that
shows a full pool means the game has reopened it — clear those Claims to match.

This works **only against the live popup instance**. `C_TooltipInfo.GetItemByID`
on the Voidcache returns a *generic* tooltip (different item level, no Track, no
"Contains" list), so there is **no anytime/retroactive scrape** — we snapshot
going-forward as the player rolls, and fall back to manual for the rest.

Manual marking shipped first as the guaranteed core (v1.2.0); the event + popup
snapshot auto-detect followed once the roll events were decoded in-game (see
"Auto-detect implemented" below).

## Consequences

- A bounded deviation from 0002: we maintain data because the game offers no other
  way. It is per-character state **reconstructed from a live game source** (the
  popup's reward tooltip), not shipped game data — so the spirit of 0002 (no rotting
  shipped data) holds.
- The popup snapshot is a read-only use of a tooltip the game never meant as a data
  source. It can change shape between patches and needs defensive parsing; if it
  breaks, manual marking still works.
- No retroactive backfill: a freshly-installed addon knows nothing until the player
  next opens a roll in a dungeon. Accepted — the popup only matters while rolling,
  and it is always accurate then; manual covers the "browse before rolling" gap.
- Tooltip item names are localized — compare against names resolved in the same
  client locale, never hardcoded strings (consistent with the English-only stance
  in [[0004]], but locale-correct by construction).

## Verified in-game (2026-06-17)

- **Per-Track removal confirmed** — the Voidcache tooltip states items are received
  "once per difficulty level until all potential items have been transmuted," and
  carries an "Upgrade Level: Myth" line. Per-Track (not flat) stands; the exhaustion
  reset is real.
- **Tooltip populates asynchronously** — first read is partial (no list), a later
  read has it; poll-until-stable is required.
- **By-ID is generic** — `GetItemByID(voidcacheItemID)` lacks the Track and the
  "Contains" list, so only the live popup instance is usable.
- Claims bind to the player's real **Loot Spec**; the Voidforge lens is unavailable
  while the Spec Selection points at another spec (CONTEXT.md: Loot Filter).

## Auto-detect implemented (`Data/Voidforge.lua`)

The Voidforge roll reuses the classic bonus-roll frame/events, so detection rides
two paths (verified in-game):

- **Event (the win):** `BONUS_ROLL_STARTED` (popup opens) → `BONUS_ROLL_RESULT`
  (the win). Everything a Claim needs comes off the **won item itself** — itemID +
  link from the reward arg, Track from its own `C_Item.GetItemUpgradeInfo()`
  (validated against the English ladder), dungeon from `GetInstanceInfo()` (the
  instance you're rolling in, captured at `STARTED`). No tooltip parsing; this is
  the authoritative path for new wins.
- **Snapshot (retroactive reconcile):** hooking `GameTooltip` while
  `BonusRollFrame` is shown, we read the reward tooltip's
  `Contains one of the following items:` list. **Won items are *removed* from that
  list** (not dimmed), so `claimed = (loot-spec pool) − (still-listed)`: mark the
  absent items, clear the listed ones, in one pass. This back-fills wins the event
  missed and corrects stale marks.

Two corrections the build settled:

- **The popup is read on the player's mouseover, not via a programmatic frame
  read** — the earlier "open question" spike was unnecessary; the player hovers the
  popup anyway, so hooking the tooltip is enough.
- **`"Other"` items are excluded.** Voidforge only transmutes equippable gear, so
  crates/tokens (slot `"Other"`) are in the loot table but never in the rollable
  list — their absence means "not eligible", not "won". They're skipped by the
  snapshot, the lens, and the exhaustion count.

The snapshot trusts the shipped loot-spec pool (ADR 0009) to equal the Voidforge
pool. For equippable items this holds (the journal is spec-filtered to the same
gear); `"Other"` was the one real divergence, now handled.
