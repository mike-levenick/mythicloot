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

1. **Retroactive / reconcile** — scrape the container item's tooltip via
   `C_TooltipInfo.GetItemByID`; the tooltip lists what can *still* be rolled, so
   `claimed = (loot-spec-filtered pool) − (items still listed)`. Run a one-time
   scan per character (gated by a flag), plus a manual **Rescan**. Poll until the
   tooltip is stable, with give-up caps.
2. **Live** — `BONUS_ROLL_RESULT` (the reused roll event) for rolls witnessed
   in-session.
3. **Manual** — a per-Drop toggle for corrections and backfill; manual always wins.

Key Claims by the **container** (the tooltip's source), which encodes dungeon +
Track without hardcoding a "track" concept — robust whether removal turns out to be
per-Track or flat. Handle the **exhaustion reset**: when a pool is fully claimed,
clear it (the game has reopened it). For the container→dungeon association, derive
at runtime if possible; otherwise ship a tiny, season-scoped static map, following
the [[0003]] (static teleport table) precedent.

Manual marking ships as the guaranteed core; the scrape + event auto-detect is
enabled only after live verification.

## Consequences

- A bounded deviation from 0002: we maintain data because the game offers no other
  way. It is per-character state **reconstructed from a live game source** (the
  tooltip), not shipped game data — so the spirit of 0002 (no rotting shipped data)
  holds.
- The tooltip scrape is a read-only use of an API the game never meant as a data
  source. It can change shape between patches and needs defensive parsing and live
  verification; if it breaks, manual marking still works.
- Tooltip item names are localized — compare against names resolved in the same
  client locale, never hardcoded strings (consistent with the English-only stance
  in [[0004]], but locale-correct by construction).
- Facts to verify live before enabling auto-detect: per-Track vs flat removal, what
  the container actually is and that its tooltip lists remainders, and that
  `BONUS_ROLL_RESULT` fires with the won item.
- Claims bind to the player's real **Loot Spec**; the Voidforge lens is unavailable
  while the Spec Selection points at another spec (CONTEXT.md: Loot Filter).
