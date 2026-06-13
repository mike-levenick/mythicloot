# 5. Stat Priority lens compares stat-fit, not item level or stat weights

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
project in itself. The game's own upgrade arrows sidestep this entirely by
comparing **item level only**, which is exactly the axis a min-maxer hunting
secondaries does *not* care about.

## Decision

The Stat Priority lens scores an item purely by **stat fit**: a rank-weighted
sum over the player's chosen secondaries (`C_Item.GetItemStats`), where a higher
priority strictly dominates all lower ones combined. A Slot is flagged (gold
star) when a drop's stat fit beats the **player's own equipped piece** in that
Slot. Item level and Gear Track are deliberately ignored.

This makes the lens a focused tool: "once my item levels are sorted, which drops
have better secondaries than what I'm wearing." It is explicitly *not* an upgrade
calculator, and is separate from Find Upgrades (which is the item-level/track
tool — see [[0004]] and CONTEXT.md).

## Consequences

- No stat-weight data to ship or maintain; consistent with ADR 0002.
- The lens can star a *lower*-item-level drop than what you wear — correct for
  its purpose (secondary min-maxing), but it is not claiming overall superiority.
  The player judges item level from the tooltip.
- "Better fit" is comparative against equipped gear, so a slot with already-ideal
  stats never lights up — no noise.
- If stat weights are ever wanted, they would be a separate, opt-in layer; this
  decision does not preclude it.
- Secondary-stat constants from `C_Item.GetItemStats` are verified live via
  `/ml stats`, the same discipline as `/ml tracks` (ADR 0004).
