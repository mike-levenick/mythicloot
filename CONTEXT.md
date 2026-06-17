# MythicLoot — Ubiquitous Language

A World of Warcraft addon for filtering Mythic+ dungeon loot by multiple equipment slots at once.

## Glossary

### Slot
An equipment slot on a character. The canonical list mirrors the Reference Addon's naming: Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Main Hand, Off Hand, Finger, Trinket, Other.

### Slot Filter
The player's multi-selection of Slots — a dropdown whose entries toggle independently (multi-select), unlike the Reference Addon's single-choice radio list. A dungeon matches the Slot Filter if it drops an item for **any** checked Slot (OR semantics). Nothing checked means no filter (All Slots); the "All Slots" entry clears all checks. The Slot Filter never reorders or removes dungeons, and persists per character across sessions.

### Slot Coverage
How many of the checked Slots a given dungeon can drop for the Spec Selection (e.g. "2 of 3"). Full coverage is highlighted with a badge; partial coverage shows its count; zero coverage dims the dungeon in place. The denominator is always the number of checked Slots; the numerator counts only Slots whose drop **survives the active Loot Filter** — so tightening the Loot Filter lowers the count. Shown only while the Slot Filter has at least one Slot checked.

### Gear Track
The upgrade track of an equipped item, from lowest to highest: Explorer, Adventurer, Veteran, Champion, Hero, Myth. Read from the player's own equipped gear only — never the Spec Selection's. The "Other" Slot has no Gear Track.

### Track Floor
A player-chosen threshold Gear Track (default Hero), persisted per character; the UI presents it as the track you want every slot **to reach**. A Slot is **Needed** when its equipped Gear Track is below the Floor — compared by track alone, never item level within a track. Empty Slots count as Needed. For the two paired Slots (Finger, Trinket) the Slot is Needed if *either* equipped item is below the Floor (rank by the weaker one). An empty Off Hand is *not* Needed while a two-handed weapon is equipped.

### Find Upgrades
The action that seeds the Slot Filter with exactly the player's Needed Slots, given the chosen Track Floor. Triggered by picking a track from the Find Upgrades dropdown — selecting a track both sets the Track Floor and seeds in one move (there is no separate button). It is a seed, not a live mode: it sets the Slot Filter once and the player may then adjust it by hand. All downstream display (Slot Coverage badges, column highlights, dimming) follows from the resulting Slot Filter with no separate visual state.

### Stat Priority
A player's ordered list of preferred secondary stats — Crit, Haste, Mastery, Versatility — set via 1st/2nd dropdowns. Persisted **per spec** (keyed by class+spec) per character. A stat picked in one rank can't be picked in another; unlisted stats have zero priority. The Stat Priority is the engine of a min-max lens that is independent of the Slot Filter and of Find Upgrades, and evaluates every Slot. To explore other secondaries, the player swaps the 1st/2nd picks ("shop around").

### Stat Tier
A graded rating of how well a loot item's *own* secondary stats match the Stat Priority, by stat presence: **Gold** (has the 1st *and* the 2nd), **Silver** (has the 1st only), **Bronze** (has the 2nd but not the 1st), or none. It considers only the item's own secondaries — the player's equipped gear is not part of the comparison — and ignores item level and Gear Track entirely (this lens is for min-maxing secondaries, not for finding higher-item-level gear, which is Find Upgrades). With only the 1st set, the ceiling is Silver.

### Stat Badge
The grid mark for Stat Tier: a Cell stamps its Shown Drop with the matching profession material-quality medallion — bronze, silver, or gold (top-left corner). Dungeons are never reordered; only marked.

### Drop
A single loot item a dungeon can yield for a Slot. One Slot/dungeon Cell can have several Drops (e.g. four trinkets from one dungeon). Drops are keyed by item, and the same Drop can appear in more than one dungeon.

### Cell
The grid square at one dungeon × one Slot. A Cell holds all of that Slot's Drops but displays exactly **one** at a time — the Shown Drop. A `+N` mark notes how many further Drops are hidden behind it.

### Shown Drop
The single Drop a Cell currently displays. Chosen by the active Loot Filter: under **All**, it is the Pin if set, else the highest-tier Favorite, else the best Stat Tier Drop; under a **tier** filter it is the best Stat Tier Drop; under **Favorited** it is the Favorite. The Cell's Stat Tier star and Favorite heart always describe the Shown Drop.

### Drop Picker
The submenu opened from a Cell that lists every Drop in it. From here a player can inspect each Drop, Favorite any of them, link any to chat, and Pin one as the Cell's everyday Shown Drop. The exact click bindings are tuned in-game.

### Favorite
A player's mark on a particular Drop ("I want this piece"), keyed by item and persisted **per spec** (class+spec) per character — the same key as Stat Priority — because different specs want different items. A Favorited Drop wears a heart in the Cell's bottom-left corner (clear of the top-left star). Favorites surface in the All view (a Cell prefers to show a Favorite) and are isolated by the Favorited Loot Filter.

### Pin
A player's explicit choice of which Drop a Cell shows, persisted per spec per character. In the **All** view a Pin always wins. Under a Loot Filter, the Cell's lit/dim state and its Slot Coverage still follow whether *any* Drop qualifies (so the lens stays truthful), but if the pinned Drop *itself* qualifies it wins which Drop shows — so re-pinning updates the grid live rather than only after the filter is cleared.

### Loot Filter
A single-choice lens over the grid, replacing the old 3rd Stat Priority dropdown: **All** (off, the default), **Bronze & up**, **Silver & up**, **Gold only**, **Favorited**, or **Voidforge (what's left)**. It dims every Cell whose Shown Drop fails the chosen criterion (combining with the Slot Filter — a Cell must pass both to stay lit) and feeds the Slot Coverage numerator. It never reorders or removes dungeons. An active Loot Filter chooses each Cell's Shown Drop (best Stat Tier for the tier modes, the Favorite for Favorited, a not-yet-Claimed Drop for Voidforge) rather than the All-view Favorite preference — but a Pin whose Drop also qualifies the filter still wins which Drop shows (see Pin). In **Voidforge** mode a Cell passes when the dungeon still has an unclaimed Drop for that Slot at the Voidcore Track, so the lit cells and the coverage count read as "where a Voidcore can still win me something."

A Claimed Drop (at the Voidcore Track) always wears a mark in its Cell's top-right corner, in every mode — so claim progress is visible while browsing, not only inside the Voidforge lens.

An option is only offered when the data it reads exists: the tier modes need a Stat Priority set, Favorited needs at least one Favorite, and Voidforge needs the Spec Selection to be the player's own spec (Claims are their Loot Spec history — they can't be shown for a spec the player has never rolled as). Unmet options are greyed out with a tooltip saying what to do; a selected option whose data later disappears (e.g. switching to a spec with no Stat Priority, or pointing the Spec Selection at another spec) falls back to **All** so the grid never blanks.

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

### Voidforge
The Midnight (patch 12.0.5) bonus-loot system MythicLoot helps the player plan around. After completing eligible content — for V1's scope, a Season Rotation Mythic+ dungeon — the player may spend a Voidcore for an extra roll against that dungeon's loot table, awarded at the Gear Track their key level would grant in the Great Vault. The game removes a won item from future rolls (see Claim).

### Voidcore
The consumable currency (in-game "Nebulous Voidcore") the player accrues and spends on a Voidforge roll. MythicLoot plans around what the rolls *yield*, not the currency balance. **Not** to be confused with the **Ascendant Voidcore** / **Ascendant Voidshard** items, which sit under the same Voidforge umbrella but only *upgrade an item's level* — they are out of scope for this feature.

### Claim
An item the player has already won from a Voidforge roll, which the game then removes from that dungeon's future Voidforge rolls. A Claim is keyed by **dungeon + item + Gear Track**: removal is per Track, so winning a Myth-track piece does not remove the same item at a lower Track — the item can be Claimed at one Track and still available at another. Claims are tracked per character. A Drop that is Claimed at the Track being viewed drops out of that dungeon's Voidforge Pool.

### Voidforge Pool
The set of a dungeon's Drops a Voidcore roll can still yield for the player at a given Gear Track, **filtered to the player's loot specialization** (only what can actually drop for them) and minus their Claims. The Pool shrinks as the player Claims items; when *every* item in a Pool has been Claimed the game **resets** it — the whole Pool reopens and all those Claims clear — so "what's left" must treat a fully-Claimed Pool as freshly full, never as permanently empty.

### Voidcore Track
The single Gear Track whose Voidforge pool the grid is currently showing, chosen by the player and persisted per character (default Myth). It is a *viewing* selection — which Claim pool to look at — and is deliberately separate from the Track Floor: the Track Floor is the track you want your gear to **reach** (a Find Upgrades goal), whereas the Voidcore Track is the track your key **rolls at**. Same Gear Track ladder, different meaning.

### Reference Addon
Keystone Loot (by Wolkenschutz), the addon whose *behavior* MythicLoot replicates. Its code is All Rights Reserved — behavior is studied in-game, code is never copied.
