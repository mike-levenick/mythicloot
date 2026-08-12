local ADDON_NAME, MythicLoot = ...

-- challengeMapID -> Mythic Keystone teleport spell ID.
--
-- Unlike loot (ADR 0002), there is NO runtime API mapping a dungeon to its
-- teleport spell, so this is a hand-maintained table of game-data facts
-- (ADR 0003). Entries for dungeons not in the current season are harmless;
-- a map with no entry simply shows no teleport button. Update when the
-- Mythic+ rotation changes.
-- Keys are the live challengeMapIDs (from C_ChallengeMode.GetMapTable), which
-- the season assigns and which differ from a dungeon's historical IDs.
-- Season 18 (Midnight 12.1). Spell IDs sourced from the Keystone Hero achievement
-- pages on warcraft.wiki.gg, not from the player's spellbook -- the buttons are
-- gated on IsSpellKnown, so shipping a teleport nobody has learned yet is inert
-- until they earn it. Every row below was verified in-game with /ml teleports:
-- each challengeMapID resolved to the dungeon named beside it, and each spell ID
-- to the spell named beside it.
local TELEPORT_SPELL = {
	[249] = 1286831, -- Kings' Rest        -- Path of the Slumbering Conqueror
	[250] = 1286828, -- Temple of Sethraliss -- Path of the Sacred Temple
	[399] = 393256,  -- Ruby Life Pools    -- Path of the Clutch Defender
	[584] = 1286801, -- The Blinding Vale  -- Path of the Blooming Verdure
	[585] = 1286804, -- Voidscar Arena     -- Path of the Brutal Combatant
	[586] = 1286807, -- Den of Nalorakk    -- Path of the Worthy Aspirant
	[587] = 1286809, -- Murder Row         -- Path of the Devious Smuggler
	[588] = 1286812, -- Altar of Fangs     -- Path of Venomous Evolution
}

function MythicLoot.GetTeleportSpell(challengeMapID)
	return TELEPORT_SPELL[challengeMapID]
end

-- TEMPORARY diagnostic (/ml teleports): verify TELEPORT_SPELL against the live
-- game. There is no runtime API mapping a dungeon to its teleport (ADR 0003), so
-- the table is keyed by hand and both halves of each row can be wrong: the
-- challengeMapID might belong to a different dungeon than assumed, and the spell ID
-- is sourced externally. This checks both at once, per rotation dungeon:
--
--   mapID + name   from C_ChallengeMode -- authoritative, no guessing
--   spell name     resolved from the keyed spell ID via C_Spell.GetSpellName
--
-- GetSpellName resolves ANY spell ID, learned or not, so this verifies the table
-- without owning a single teleport. A row whose spell name doesn't match its
-- dungeon is a mis-key; a nil name means the ID doesn't exist at all.
--
-- Kept rather than deleted after use: it is the check to re-run every season when
-- the rotation turns over, and it costs nothing behind /ml dev-mode. (Its sibling
-- /ml updump was marked "delete once done" last season and then turned out to be
-- what caught season 18 rotating the upgrade-track bonus IDs -- see Gear.lua.)
function MythicLoot.DumpTeleports()
	MythicLootGlobalDB = MythicLootGlobalDB or {}

	local rot = MythicLoot.Journal:GetRotation()
	if not rot then
		print("|cffff4444MythicLoot|r: season rotation not loaded yet — try again in a few seconds.")
		return
	end

	local out = {}
	print("|cff33ff66MythicLoot|r teleport table check:")
	for _, dungeon in ipairs(rot) do
		local spellID = TELEPORT_SPELL[dungeon.challengeMapID]
		local spellName = spellID and C_Spell.GetSpellName(spellID)
		table.insert(out, {
			challengeMapID = dungeon.challengeMapID,
			name = dungeon.name,
			spellID = spellID,
			spellName = spellName,
		})
		print(string.format("  [%d] %s  ->  %s (%s)",
			dungeon.challengeMapID, dungeon.name,
			spellName or "|cffff4444NO SPELL NAME|r", tostring(spellID)))
	end

	MythicLootGlobalDB.teleportProbe = out
	print("|cff33ff66MythicLoot|r: " .. #out .. " dungeons checked — /reload, then tell Claude.")
end
