local ADDON_NAME, MythicLoot = ...

-- Canonical Slot taxonomy (see CONTEXT.md), in dropdown display order.
-- enumName must match a key of Enum.ItemSlotFilterType; entries the client
-- doesn't know are skipped so an enum rename can't hard-error the addon.
-- invSlot is the character-sheet slot whose icon labels the grid column; we
-- read the texture from the game (GetInventorySlotInfo) rather than hardcode
-- paths, so it's always correct and complete (Back, Wrist, etc.).
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local SLOT_DEFS = {
	{ enumName = "Head", label = "Head", invSlot = "HeadSlot" },
	{ enumName = "Neck", label = "Neck", invSlot = "NeckSlot" },
	{ enumName = "Shoulder", label = "Shoulder", invSlot = "ShoulderSlot" },
	{ enumName = "Cloak", label = "Back", invSlot = "BackSlot" },
	{ enumName = "Chest", label = "Chest", invSlot = "ChestSlot" },
	{ enumName = "Wrist", label = "Wrist", invSlot = "WristSlot" },
	{ enumName = "Hand", label = "Hands", invSlot = "HandsSlot" },
	{ enumName = "Waist", label = "Waist", invSlot = "WaistSlot" },
	{ enumName = "Legs", label = "Legs", invSlot = "LegsSlot" },
	{ enumName = "Feet", label = "Feet", invSlot = "FeetSlot" },
	{ enumName = "MainHand", label = "Main Hand", invSlot = "MainHandSlot" },
	{ enumName = "OffHand", label = "Off Hand", invSlot = "SecondaryHandSlot" },
	{ enumName = "Finger", label = "Finger", invSlot = "Finger0Slot" },
	{ enumName = "Trinket", label = "Trinket", invSlot = "Trinket0Slot" },
	{ enumName = "Other", label = "Other", invSlot = nil },
}

local function SlotHeaderIcon(invSlot)
	if not invSlot then return QUESTION_MARK end
	local _, texture = GetInventorySlotInfo(invSlot)
	return texture or QUESTION_MARK
end

MythicLoot.Slots = {}
local byFilterType = {}

for _, def in ipairs(SLOT_DEFS) do
	local filterType = Enum.ItemSlotFilterType and Enum.ItemSlotFilterType[def.enumName]
	if filterType ~= nil then
		local slot = {
			key = def.enumName,
			label = def.label,
			headerIcon = SlotHeaderIcon(def.invSlot),
			filterType = filterType,
			order = #MythicLoot.Slots + 1,
		}
		table.insert(MythicLoot.Slots, slot)
		byFilterType[filterType] = slot
	end
end

local fallbackSlot = byFilterType[Enum.ItemSlotFilterType and Enum.ItemSlotFilterType.Other]
	or MythicLoot.Slots[#MythicLoot.Slots]

-- Maps an Encounter Journal itemInfo.filterType to our Slot; unknown
-- filter types (mounts, recipes, future enum additions) count as Other.
function MythicLoot.GetSlotForFilterType(filterType)
	return (filterType ~= nil and byFilterType[filterType]) or fallbackSlot
end

function MythicLoot.GetSlotByKey(key)
	for _, slot in ipairs(MythicLoot.Slots) do
		if slot.key == key then return slot end
	end
end
