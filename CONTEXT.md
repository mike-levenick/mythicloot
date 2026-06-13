# MythicLoot — Ubiquitous Language

A World of Warcraft addon for filtering Mythic+ dungeon loot by multiple equipment slots at once.

## Glossary

### Slot
An equipment slot on a character. The canonical list mirrors the Reference Addon's naming: Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Main Hand, Off Hand, Finger, Trinket, Other.

### Slot Filter
The player's multi-selection of Slots — a dropdown whose entries toggle independently (multi-select), unlike the Reference Addon's single-choice radio list. A dungeon matches the Slot Filter if it drops an item for **any** checked Slot (OR semantics). Nothing checked means no filter (All Slots); the "All Slots" entry clears all checks. The Slot Filter never reorders or removes dungeons, and persists per character across sessions.

### Slot Coverage
How many of the checked Slots a given dungeon can drop for the Spec Selection (e.g. "2 of 3"). Full coverage is highlighted with a badge; partial coverage shows its count; zero coverage dims the dungeon in place.

### Gear Track
The upgrade track of an equipped item, from lowest to highest: Explorer, Adventurer, Veteran, Champion, Hero, Myth. Read from the player's own equipped gear only — never the Spec Selection's. The "Other" Slot has no Gear Track.

### Track Floor
A player-chosen threshold Gear Track (default Hero), persisted per character. A Slot is **Needed** when its equipped Gear Track is below the Floor — compared by track alone, never item level within a track. Empty Slots count as Needed. For the two paired Slots (Finger, Trinket) the Slot is Needed if *either* equipped item is below the Floor (rank by the weaker one). An empty Off Hand is *not* Needed while a two-handed weapon is equipped.

### Find Upgrades
The one-click action that seeds the Slot Filter with exactly the player's Needed Slots, given the current Track Floor. It is a seed, not a live mode: it sets the Slot Filter once and the player may then adjust it by hand. All downstream display (Slot Coverage badges, column highlights, dimming) follows from the resulting Slot Filter with no separate visual state.

### Dungeon List
The fixed, stable list of all Season Rotation dungeons. Every dungeon is always visible in the same order; filtering only changes highlight/dim state and Slot Coverage display, never membership or position.

### Playing Spec
The specialization the player currently has active. The Spec Selection defaults to this when the addon opens.

### Loot Spec
The in-game loot specialization setting, which determines what can actually drop. May differ from the Playing Spec; the addon offers a one-click switch to it.

### Spec Selection
The class/spec whose loot the addon is currently showing and counting Slot Coverage against. Starts at the Playing Spec, can be pointed anywhere via dropdown, and **persists across reloads and sessions** (per character). Two one-click buttons jump back to the Playing Spec (the "home" state) or the Loot Spec. Whenever the Spec Selection differs from the Playing Spec, the window says so prominently.

### Season Rotation
The set of dungeons eligible for Mythic+ in the current season. V1's Dungeon List is exactly the current Season Rotation — no raids, no off-season dungeons.

### Reference Addon
Keystone Loot (by Wolkenschutz), the addon whose *behavior* MythicLoot replicates. Its code is All Rights Reserved — behavior is studied in-game, code is never copied.
