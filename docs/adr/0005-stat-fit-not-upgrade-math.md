# 5. Stat Priority lens grades by stat presence, not item level or stat weights

Date: 2026-06-13

## Status

Accepted

## Context

The Stat Priority feature lets a player rank secondary stats (e.g. Mastery >
Haste) and have the grid surface dungeon drops that suit those stats. The
obvious expectation is "tell me which drops are upgrades." A true upgrade
calculation needs **stat weights** (how much a point of Mastery is worth vs
Haste vs item level) to compare a lower-item-level, better-stat piece against a
higher-item-level, worse-stat one.

WoW exposes no stat weights. They come from external simulation (e.g. SimC) per
spec and even per build, change with tuning, and shipping/maintaining them is a
project in itself. The game's own upgrade arrows sidestep this by comparing
**item level only**, which is exactly the axis a min-maxer hunting secondaries
does *not* care about.

We first scoped this as a fit-vs-equipped comparison, but settled on a simpler,
clearer model: grade each drop by which of the player's top stats it carries.

## Decision

The Stat Priority lens grades a drop by **stat presence** against the priority
order, using the item's *own* secondaries (`C_Item.GetItemStats`):

- **Gold** — has both the 1st and 2nd priority stats.
- **Silver** — has the 1st only.
- **Bronze** — has the 2nd only.
- none otherwise.

It does **not** consider the player's equipped gear, item level, or Gear Track.
Each Slot's best-tier drop is surfaced in its grid cell and stamped with the
corresponding star. This makes the lens a focused "which drops carry my stats,
and how completely" tool — explicitly *not* an upgrade calculator, and separate
from Find Upgrades (the item-level/track tool — see [[0004]] and CONTEXT.md).

## Consequences

- No stat-weight data to ship or maintain; consistent with ADR 0002.
- A drop can be starred even if the player already wears an equivalent piece —
  intended: the lens shows where ideal-stat gear *exists*, and the player judges
  item level from the tooltip.
- Grading is by presence only, so it is robust and locale-independent; only the
  four secondary-stat constants matter, and those are verified live via
  `/ml stats` (same discipline as `/ml tracks`, ADR 0004).
- A single-stat priority caps at Silver (no 2nd stat to complete Gold), which is
  correct and needs no special case.
- If stat weights are ever wanted, they would be a separate, opt-in layer; this
  decision does not preclude it.
