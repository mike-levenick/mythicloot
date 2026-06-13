local ADDON_NAME, MythicLoot = ...

local function InitSavedVariables()
	-- Account-wide: window position. Per-character: slot filter, spec selection (see CONTEXT.md).
	MythicLootGlobalDB = MythicLootGlobalDB or {}
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
SlashCmdList.MYTHICLOOT = function(msg)
	msg = (msg or ""):lower():gsub("%s+", "")
	if msg == "tracks" and MythicLoot.PrintGearTracks then
		MythicLoot.PrintGearTracks()
		return
	end
	if msg == "stats" and MythicLoot.PrintGearStats then
		MythicLoot.PrintGearStats()
		return
	end
	MythicLoot:ToggleWindow()
end

-- Referenced by ## AddonCompartmentFunc in the TOC; must be a global.
function MythicLoot_OnAddonCompartmentClick()
	MythicLoot:ToggleWindow()
end
