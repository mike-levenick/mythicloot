local ADDON_NAME, MythicLoot = ...

-- challengeMapID -> Mythic Keystone teleport spell ID.
--
-- There is no runtime API mapping a dungeon to its teleport spell, so this is a
-- hand-maintained table of game-data facts (ADR 0003). Loot was the contrast when
-- that was written -- read live while this was static -- but ADR 0009 superseded
-- ADR 0002 and bundled the loot table too, so both are shipped data now.
-- Entries for dungeons not in the current season are harmless; a map with no entry
-- simply shows no teleport button. Update when the Mythic+ rotation changes.
-- Keys are the live challengeMapIDs (from C_ChallengeMode.GetMapTable), which
-- the season assigns and which differ from a dungeon's historical IDs.
--
-- Season 18 (Midnight 12.1). Spell IDs sourced from the Keystone Hero achievement
-- pages on warcraft.wiki.gg, not from the player's spellbook -- the buttons are
-- gated on IsSpellKnown, so shipping a teleport nobody has learned yet is inert
-- until they earn it. Verified in-game with /ml teleports: each challengeMapID
-- resolves to the dungeon named beside it, and each spell ID to a spell whose own
-- description names that same dungeon as the destination.
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

-- Diagnostic (/ml teleports): verify TELEPORT_SPELL against the live game. Both
-- halves of a row can be wrong -- the challengeMapID might belong to a different
-- dungeon than assumed, and the spell ID is sourced externally -- so check both,
-- per rotation dungeon:
--
--   mapID + name   from C_ChallengeMode -- authoritative, no guessing
--   spell name     resolved from the keyed spell ID
--   description    the teleport's own text, which names its destination
--
-- The description is what actually proves a row. A name only says some spell with
-- that ID exists; "Teleports you to <dungeon>" ties the ID to a destination, which
-- is the claim being made. Both resolve for ANY spell ID, learned or not, so the
-- table can be verified without owning a single teleport.
--
-- Rows are also checked the other way round, since the per-dungeon loop can only
-- see keys that are in the rotation: a typo'd or left-behind key would otherwise be
-- invisible here while still sitting in the table.
--
-- Kept rather than deleted after use: it is the check to re-run every season when
-- the rotation turns over, and it costs nothing behind /ml dev-mode. (Its sibling
-- /ml updump was marked "delete once done" last season and then turned out to be
-- what caught season 18 rotating the upgrade-track bonus IDs -- see Gear.lua.)
function MythicLoot.DumpTeleports()
	MythicLootGlobalDB = MythicLootGlobalDB or {}

	local rot = MythicLoot.Journal and MythicLoot.Journal:GetRotation()
	if not rot then
		print("|cffff4444MythicLoot|r: season rotation not loaded yet — try again in a few seconds.")
		return
	end

	local out, inRotation = {}, {}
	print("|cff33ff66MythicLoot|r teleport table check:")
	for _, dungeon in ipairs(rot) do
		local spellID = TELEPORT_SPELL[dungeon.challengeMapID]
		local spellName = spellID and C_Spell.GetSpellName(spellID)
		local description = spellID and C_Spell.GetSpellDescription(spellID)
		inRotation[dungeon.challengeMapID] = true
		table.insert(out, {
			challengeMapID = dungeon.challengeMapID,
			name = dungeon.name,
			spellID = spellID,
			spellName = spellName,
			description = description,
		})
		-- Distinguish the two failures: no row for this dungeon at all, versus a row
		-- whose spell ID the client doesn't recognise.
		local label = spellName
			or (spellID and "|cffff4444UNKNOWN SPELL ID|r" or "|cffff4444NO TABLE ENTRY|r")
		print(string.format("  [%d] %s  ->  %s (%s)",
			dungeon.challengeMapID, dungeon.name, label, tostring(spellID)))
		if description and description ~= "" then
			print("        " .. description)
		end
	end

	for mapID, spellID in pairs(TELEPORT_SPELL) do
		if not inRotation[mapID] then
			print(string.format("  |cffffcc00not in this rotation|r: [%d] -> %s (%d)",
				mapID, C_Spell.GetSpellName(spellID) or "?", spellID))
		end
	end

	MythicLootGlobalDB.teleportProbe = out
	print("|cff33ff66MythicLoot|r: " .. #out .. " dungeons checked — /reload, then tell Claude.")
end
