# 9. Ship a generated loot table instead of reading the Encounter Journal at runtime

Date: 2026-06-21

## Status

Accepted. **Supersedes [[0002]]** (runtime EJ reads, ship nothing) and **retires the
runtime half of [[0007]]** (the per-session EJ cache); the persistent-cache plumbing
is repurposed to seed from the shipped table.

## Context

[[0002]] chose to read all loot from the Encounter Journal at runtime so we'd never
ship data that rots. In practice the runtime EJ has been a steady source of
friction:

- **In-instance reads are wrong.** While the player is inside a dungeon the game
  pins the EJ to that instance, so every per-dungeon read returns the same loot
  (all rows identical). We can only work around it by *not* reading in-instance and
  serving a cache — which means the live read wasn't even usable when the player
  most wants the data (deciding where to spend a Voidcore mid-key).
- **Async + cold starts.** First open watches the grid populate; a freshly installed
  addon (or a spec never opened out-of-dungeon) has nothing in-dungeon.
- **Tier/instance selection quirks** ([[ej-select-tier-before-instance]]) and the
  read/retry machinery are a lot of fragile code for data that changes ~once a season.

The data itself is small, bounded, and slow-moving (a season's M+ rotation loot per
spec). Reference addons ship it. The original "don't ship rotting data" worry is
answered by *how* we generate it.

## Decision

Ship the loot table as `MythicLoot/Data/SeasonLoot.lua` and read from it at runtime.
Remove the live EJ reads from the normal path.

**Generation is self-harvest, in-game, clean-room.** `Data/Export.lua` (`/ml export`)
walks our *existing* EJ reader across every class/spec × every rotation dungeon,
**out of a dungeon**, and dumps the result into a SavedVariable. WoW serialises that
to disk as a Lua table literal, which `tools/gen_seasonloot.lua` turns into the
committed `SeasonLoot.lua` (sorted/deterministic). So the data is Blizzard's, read
through our own code — never another addon ([[0001]]). Refreshing each season is "run
`/ml export`, run the generator, commit."

**Shape:** `SeasonLoot[classID][specID][challengeMapID] = { {id, slot, name, icon}, … }`.
That renders a cell fully offline (icon + name + slot column); tooltips use
`SetItemByID`, and the rare chat-link resolves lazily from the id. Nothing
player- or session-specific is stored. English names ship as-is, consistent with the
English-only stance in [[0004]].

The EJ is no longer read on the normal path. The exporter is the one place that still
touches it, and it's a maintenance tool, not a player path.

## Consequences

- **Robust and instant.** No async, no in-instance freeze, no cold-start gap — the
  same data everywhere, including mid-dungeon. A whole class of bugs disappears.
- **Maintenance is manual but cheap.** Loot updates require regenerating + shipping a
  new file (once per season, or after a loot hotfix). The stamp stored alongside the
  export (`toc`, `season`) lets us detect when the shipped table is for an older
  build and warn, rather than silently serve stale data.
- **Repurposes, doesn't delete, [[0007]].** The persistent-cache seed-then-paint flow
  becomes "seed from `SeasonLoot`"; the background EJ reconcile it described is gone.
- **The exporter is the last EJ reader.** It must run out-of-dungeon (it guards on
  `IsInInstance()`), and the season rotation must be loaded first.
- **Risk: a missing spec/dungeon in the bundle** (new dungeon, export gap) shows an
  empty row rather than wrong data; acceptable and visible. Keep `Data/VoidCheck.lua`
  and the exporter shipped so regeneration is always to hand.
