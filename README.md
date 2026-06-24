# MythicLoot

A World of Warcraft addon that shows the current Mythic+ season's dungeon loot
for any class/spec — with a **multi-select slot filter**. Check Chest *and*
Legs and instantly see which dungeons cover both ("2/2"), which cover one
("1/2"), and which have nothing for you (dimmed).

Inspired by the behavior of [Keystone Loot](https://www.curseforge.com/wow/addons/keystoneloot),
whose single-slot radio filter was the itch this scratches. Clean-room
implementation — see `docs/adr/0001`.

## Install (dev)

```
ln -s "$(pwd)/MythicLoot" "/Applications/World of Warcraft/_retail_/Interface/AddOns/MythicLoot"
```

Fully restart the game once (new addon folders are only discovered at launch).
After that, `/reload` picks up code changes.

## Use

- `/ml` or `/mythicloot` (also in the minimap Addon Compartment)
- Spec dropdown: any class/spec; **My Spec** / **Loot Spec** buttons to jump back
- Slot dropdown: toggle any number of slots; "All Slots" clears
- **Voidforge (what's left)** filter tracks which items you've won from Voidcore
  bonus rolls — wins mark themselves, and the roll popup syncs the rest
- Shift-click an item to link it in chat

## Docs

- `CONTEXT.md` — glossary / ubiquitous language
- `docs/adr/` — architecture decision records

Loot data ships with the addon (`Data/SeasonLoot.lua`), generated from the
in-game Encounter Journal by a dev-only exporter (`/ml export`, gated behind
`/ml dev-mode`). Opens are instant and the data is identical everywhere — see
`docs/adr/0009`, which supersedes the original runtime-Journal approach
(`docs/adr/0002`). Refreshing for a new season means re-running the exporter.

## License

MIT — see [LICENSE](LICENSE). This is an original, clean-room implementation
(`docs/adr/0001`); it shares no code or assets with Keystone Loot.
