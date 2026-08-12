local ADDON_NAME, MythicLoot = ...

local function InitSavedVariables()
	-- Account-wide: window position, cached EJ loot tables (ADR 0007).
	-- Per-character: slot filter, spec selection (see CONTEXT.md).
	MythicLootGlobalDB = MythicLootGlobalDB or {}
	MythicLootGlobalDB.lootCache = MythicLootGlobalDB.lootCache or {}
	MythicLootCharDB = MythicLootCharDB or {}
	MythicLootCharDB.slotFilter = MythicLootCharDB.slotFilter or {}
end

-- Returns classID, specID of the spec the player is actually playing.
-- specID is 0 for fresh characters with no spec chosen yet (= all specs in EJ filters).
function MythicLoot.GetPlayingSpec()
	local classID = select(3, UnitClass("player"))
	local specIndex = C_SpecializationInfo.GetSpecialization()
	local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
	return classID, specID or 0
end

-- Returns classID, specID of the player's loot specialization
-- (0 from the game means "same as current spec").
function MythicLoot.GetLootSpec()
	local specID = GetLootSpecialization()
	if not specID or specID == 0 then
		return MythicLoot.GetPlayingSpec()
	end
	return (select(3, UnitClass("player"))), specID
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON_NAME then return end
	InitSavedVariables()
	self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_MYTHICLOOT1 = "/mythicloot"
SLASH_MYTHICLOOT2 = "/ml"

-- Diagnostic/data-gathering commands, only active in dev mode (see /ml dev-mode).
local DEV_COMMANDS = { tracks = true, stats = true, export = true, updump = true, teleports = true }

SlashCmdList.MYTHICLOOT = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")

	-- Undocumented dev toggle. The data-gathering/diagnostic commands below are used
	-- to regenerate the shipped data each season; they're hidden from normal users
	-- and only respond once dev mode is on. The flag persists account-wide.
	if cmd == "dev-mode" or cmd == "dev" then
		MythicLootGlobalDB = MythicLootGlobalDB or {}
		MythicLootGlobalDB.devMode = not MythicLootGlobalDB.devMode
		if MythicLootGlobalDB.devMode then
			print("|cff33ff66MythicLoot|r dev mode |cff33ff66ON|r — /ml tracks · stats · export · updump · teleports")
		else
			print("|cff33ff66MythicLoot|r dev mode |cffff4444OFF|r")
		end
		return
	end

	-- Dev/diagnostic commands: always "handled" (they never fall through to opening
	-- the window), but they only act when dev mode is on — otherwise a silent no-op.
	if DEV_COMMANDS[cmd] then
		if MythicLootGlobalDB and MythicLootGlobalDB.devMode then
			if cmd == "tracks" then MythicLoot.PrintGearTracks() end
			if cmd == "stats" then MythicLoot.PrintGearStats() end
			if cmd == "export" then MythicLoot.ExportLoot() end
			if cmd == "updump" then MythicLoot.DumpUpgrades() end
			if cmd == "teleports" then MythicLoot.DumpTeleports() end
		end
		return
	end

	MythicLoot:ToggleWindow()
end

-- Referenced by ## AddonCompartmentFunc in the TOC; must be a global.
function MythicLoot_OnAddonCompartmentClick()
	MythicLoot:ToggleWindow()
end
