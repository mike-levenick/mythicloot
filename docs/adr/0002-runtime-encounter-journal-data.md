# 2. Loot data from the Encounter Journal at runtime, not shipped tables

Date: 2026-06-12

## Status

Accepted

## Context

The addon needs loot tables (items, slots, icons) for every dungeon in the
current Mythic+ Season Rotation, filterable by class/spec. Two sources exist:

1. Pre-generated static Lua tables shipped with the addon (the Reference
   Addon's approach). Synchronous and fast, but requires a data-generation
   pipeline and a re-release every patch and every season rotation.
2. The game client's own Encounter Journal, queried at runtime
   (`C_MythicPlus`/`C_ChallengeMode` for the rotation, `EJ_SelectInstance` +
   `EJ_SetLootFilter` + `C_EncounterJournal.GetLootInfoByIndex` for loot).
   Always current with the live game, but loads asynchronously
   (`EJ_LOOT_DATA_RECIEVED`) and needs request sequencing and caching.

## Decision

Query the Encounter Journal at runtime with a session cache. Ship no data.

## Consequences

- All data access is asynchronous: UI code renders from a cache that fills as
  events arrive, never from direct synchronous lookups. This shapes the whole
  rendering layer and is the hard-to-reverse part.
- Zero data maintenance: a new season or patch needs no addon update for data.
- Slot Coverage requires loot for all rotation dungeons for the selected spec;
  the loader must sequence a burst of journal queries and signal completion.
- If latency ever matters, a SavedVariables cache can be added without
  changing the design.
