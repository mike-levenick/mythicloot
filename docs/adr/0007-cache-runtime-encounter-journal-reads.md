# 7. Cache runtime Encounter Journal reads; never ship them

Date: 2026-06-16

## Status

Accepted

Complements [[0002]] (runtime Encounter Journal data).

## Context

[[0002]] reads all loot from the Encounter Journal (EJ) at runtime so a new
season needs no addon update. The cost is latency: the EJ populates
**asynchronously** (the `EJ_SelectTier` → `EJ_SelectInstance` dance, plus retries
in `Journal.lua`), so the grid shows "Loading…" on every open until data arrives —
a visible delay every session.

Separately, the Voidforge feature ([[0008]]) needs a **stable, persistent** loot
table to compute "what's left" against.

The temptation is to ship a static loot table to remove the latency. That is
exactly what 0002 rejected — it rots and forces an addon update every season.

## Decision

Cache the EJ-derived loot table in SavedVariables instead of shipping one:

- Persist the table after the first successful read, **account-wide**, keyed by
  `classID-specID`, stamped with the **client build** and the **current M+ season**.
- On open, paint the cached table **immediately**; then **always re-read the EJ in
  the background and overwrite the cache if anything differs**. "Loading…" appears
  only on a cold cache.

This is a cache of **runtime-read** data, not shipped data. The EJ stays the single
source of truth; new seasons still work with no update. It complements 0002 rather
than reversing it.

## Consequences

- Opens are instant after the first read; the async EJ dance hides behind the cache.
- The cache can momentarily show stale loot right after a patch or season change,
  until the background reconcile completes within the session. The build+season
  stamp bounds the window and the reconcile self-heals it.
- New persistent state to version and migrate; keep the cached shape minimal (only
  what the grid renders), and treat any unreadable/old-format cache as a cold cache.
- If a clean runtime "current season" value isn't available, fall back to the build
  number plus the reconcile (still self-heals, a beat slower on a season rollover).
- Account-wide keying means an alt of the same spec benefits from the main's warm
  read, since the EJ loot table is character-independent.
