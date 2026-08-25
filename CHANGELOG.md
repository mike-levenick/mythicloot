# Changelog

## v1.4.1 — 2026-08-25

### Changed

- **Maintenance release for WoW 12.1** — no functional changes; re-published so the download is listed under game version 12.1.

## v1.4.0 — 2026-08-11

### Changed

- **Updated for Mythic+ season 18** — the built-in loot tables now cover the new rotation: Altar of Fangs, Ruby Life Pools, Kings' Rest, Voidscar Arena, Den of Nalorakk, Murder Row, Temple of Sethraliss and The Blinding Vale. On the previous version these all read "No journal data found for this dungeon", since the shipped loot was still season 17's.

- **Teleport buttons** are wired up for the new rotation. As always, a dungeon's button appears once you've earned its Mythic Keystone teleport.

## v1.3.0 — 2026-06-23

### Added

- **Voidforge auto-detect** — when you spend a Voidcore, the item you win is marked claimed automatically, with a chat confirmation. Mousing over the roll popup also syncs that dungeon's whole pool from what's still rollable, so your "what's left" self-corrects as you roll — no manual marking needed. (ADR 0008)

### Fixed

- **"Help me reach"** — choosing the blank "—" entry now clears the slots it seeded, returning to All Slots, instead of leaving the seeded slots selected.

## v1.2.0 — 2026-06-21

### Added

- **Voidforge tracking** — mark which items you've already won from a Voidcore bonus roll, per dungeon and per Gear Track, and the new "Voidforge (what's left)" filter lights only the dungeons where a Voidcore can still win you something. A green check marks claimed drops in every view. Mark a drop via shift+right-click, or tick "Won at <track>" in the Drop Picker; pick the track your keys roll at from the filter's submenu (defaults to Myth). Saved per character, shown only while viewing your own spec. (ADR 0008)

- **Loot shown at your target track** — drops now display their item level at the Gear Track you're aiming for: Myth 1/6 by default, or whatever you pick in "Help me reach". Hover a drop and the item level reflects what you'd actually get.

### Changed

- **Loot data is now built in** — the dungeon loot tables ship with the addon instead of being read from the game each session. Opens are instant, the data is identical everywhere (including inside a dungeon, where the game journal used to show every dungeon the same), and there's no more loading flicker. (ADR 0009, supersedes the runtime cache from ADR 0007)

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
