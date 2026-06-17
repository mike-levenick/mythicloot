# Changelog

## Unreleased

### Changed

- **Faster opens** — the dungeon loot table is now cached between sessions and painted instantly, then refreshed from the game in the background, so you no longer watch it load every time. (ADR 0007)

## v1.1.0 — 2026-06-15

### Added

- **Favorites** — right-click any slot cell to favorite the item shown there; a heart marks it in the cell's bottom-left corner. Favorites are saved per spec, per character, and can be isolated with the new "Favorited" filter.
- **Multi-drop cells** — slots that drop several items (e.g. four trinkets from one dungeon) are no longer collapsed to one. Left-click a cell to open the Drop Picker and choose which drop it shows; favorite any of them with a right-click once shown. The choice is saved per spec, per character.
- **Loot Filter** — a new "Show:" lens (All / Bronze & up / Silver & up / Gold only / Favorited) dims the loot that doesn't match and adjusts each dungeon's coverage count to suit. Saved per character.
- **Reset button** — one click returns to your current spec with all slots shown and no track or loot filter. Your favorites and pins are kept.

### Changed

- **Stat Priority** is now two stats (1st + 2nd) instead of three — early feedback found three confusing. Gold means a drop has both your stats; swap your picks to shop around. (ADR 0006)
- **Find Upgrades** dropdown is now labelled "Help me reach", gained a "—" entry, and shows "—" whenever you edit the slot selection by hand — so it never implies you're filtering for a track when you aren't.

## v1.0.0 — Initial release

First public release of MythicLoot.

### Features

- **Multi-slot loot view** — see every Season Rotation dungeon in one fixed list and check off multiple slots at once (Head, Chest, Legs, Trinket, and more). Dungeons that drop for your checked slots are highlighted, with a coverage count for each.
- **Find Upgrades** — pick the gear track you want every slot to reach and MythicLoot checks the slots whose own gear is still below it.
- **Stat Priority** — rank your secondary stats (Crit, Haste, Mastery, Versatility) and each slot's best drop is badged bronze / silver / gold by how well it matches. Saved per spec, per character.
- **One-click teleports** — jump straight to any dungeon you have the teleport for, right from the list.
- **Loot spec switching** — swap your loot specialization in a click.
- **Collapsible toolbar** — hide the Find Upgrades and Stat Priority controls when you don't need them.
- **Adjustable scale** and a movable window, with all settings persisted across sessions.
