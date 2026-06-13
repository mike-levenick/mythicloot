# 1. Clean-room rebuild, not a fork of Keystone Loot

Date: 2026-06-12

## Status

Accepted

## Context

MythicLoot replicates the behavior of Keystone Loot (Wolkenschutz), adding multi-slot
filtering. The obvious shortcut is to fork it. Its repository's LICENSE.md is
"All rights reserved" — no right to use, modify, or redistribute the code or assets.

## Decision

Rebuild from scratch. Keystone Loot is studied as a running addon (behavior,
layout, feature ideas) but its code and assets are never copied or ported.

## Consequences

- More upfront work: UI and data loading are written fresh.
- No legal exposure, and we can license our own code as we please.
- Divergence from the reference is free — we are not constrained by its
  architecture (see ADR 0002, which diverges from its static-data approach).
