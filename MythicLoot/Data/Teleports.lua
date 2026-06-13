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
local TELEPORT_SPELL = {
	[161] = 159898,  -- Skyreach
	[239] = 1254551, -- Seat of the Triumvirate
	[402] = 393273,  -- Algeth'ar Academy
	[556] = 1254555, -- Pit of Saron
	[557] = 1254400, -- Windrunner Spire
	[558] = 1254572, -- Magisters' Terrace
	[559] = 1254563, -- Nexus-Point Xenas
	[560] = 1254559, -- Maisara Caverns
}

function MythicLoot.GetTeleportSpell(challengeMapID)
	return TELEPORT_SPELL[challengeMapID]
end
