# 4. Read Gear Track at runtime via C_Item.GetItemUpgradeInfo

Date: 2026-06-13

## Status

Accepted

## Context

The "Find Upgrades" action seeds the Slot Filter with the Slots where the
player's own equipped gear is below a chosen Track Floor (see CONTEXT.md). That
requires reading each equipped item's **Gear Track** (Explorer → … → Myth) and
ranking it.

There are three ways to get the track of an item:

1. `C_Item.GetItemUpgradeInfo(itemLink)` — returns `trackStringID` (a
   locale-independent number), `trackString` (localized name, e.g. "Hero"),
   `currentLevel`, `maxLevel`. Official since 11.1.5.
2. Parse the item tooltip line for the upgrade text (what older addons did
   before the API existed).
3. Decode the item link's bonus IDs against a hand-maintained map (what some bag
   addons still keep as a fallback).

We also have to turn a track into a comparable rank, and tracks are added/renamed
across expansions.

## Decision

Use `C_Item.GetItemUpgradeInfo` and rank by **`trackString`** against a fixed
English ladder (`Explorer, Adventurer, Veteran, Champion, Hero, Myth`). The
addon is English-only (a V1 scope decision), so matching the localized name is
correct here and avoids hardcoding `trackStringID` integers we cannot verify
without the live client. `/ml tracks` dumps each equipped item's
`trackStringID`/`trackString` so the locale-independent IDs can be confirmed
in-game and switched to later if we ever localize.

No tooltip parsing. No shipped item data — consistent with ADR 0002.

## Consequences

- An item whose `GetItemUpgradeInfo` returns nil or an unknown track name is
  **not** flagged as needed (we can't prove it's below the floor), avoiding
  false positives; truly empty slots still count as needed.
- Localizing the addon later means replacing the name match with a
  `trackStringID`-keyed rank map — a contained change, the IDs are already
  logged by `/ml tracks`.
- A new track tier in a future patch needs one entry added to `TRACK_ORDER`;
  until then an unknown new track degrades to "not flagged", never an error.
- Only the player's own gear is readable, so Find Upgrades reflects the local
  player regardless of the Spec Selection — intended (CONTEXT.md).
