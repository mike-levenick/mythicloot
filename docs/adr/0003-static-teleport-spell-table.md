# 3. Hand-maintained static table for teleport spells

Date: 2026-06-13

## Status

Accepted

## Context

V2 adds a click-to-teleport button on each dungeon, casting the dungeon's
Mythic Keystone teleport. ADR 0002 established that we read everything from the
game at runtime and ship no static data, precisely to avoid per-season
maintenance.

Teleports cannot follow that rule: there is **no runtime API** mapping a
challenge-mode dungeon (or its journal instance) to its teleport spell ID. The
spell IDs are game-data facts, and every teleport addon hardcodes them.

## Decision

Keep a small static `challengeMapID -> teleportSpellID` table
(`Data/Teleports.lua`). It is the narrow, unavoidable exception to ADR 0002.

## Consequences

- Per-season maintenance: when the rotation changes, new dungeons need their
  spell IDs added. Missing entries degrade gracefully (no teleport button, no
  error), so the addon never breaks — it just lacks a button until updated.
- Casting requires a `SecureActionButtonTemplate` (`type=spell`) configured out
  of combat; buttons are gated on `IsSpellKnown` so only learned teleports show.
- The table is keyed by the stable challenge-map ID, not by name, so it is
  unaffected by localization.
