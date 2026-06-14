local ADDON_NAME, MythicLoot = ...

-- Canonical Slot taxonomy (see CONTEXT.md), in dropdown display order.
-- enumName must match a key of Enum.ItemSlotFilterType; entries the client
-- doesn't know are skipped so an enum rename can't hard-error the addon.
-- invSlot is the character-sheet slot used for the silhouette fallback, read
-- from the game (GetInventorySlotInfo) when a curated icon isn't set.
-- headerIcon is a curated full-color generic item icon for the grid column —
-- the paperdoll silhouettes are nearly invisible, so we prefer a colored chit
-- (a helm for Head, a ring for Finger, etc.) that reads at a glance.
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local I = "Interface\\Icons\\"
local SLOT_DEFS = {
	{ enumName = "Head", label = "Head", invSlot = "HeadSlot", headerIcon = I .. "INV_Helmet_03" },
	{ enumName = "Neck", label = "Neck", invSlot = "NeckSlot", headerIcon = I .. "INV_Jewelry_Necklace_07" },
	{ enumName = "Shoulder", label = "Shoulder", invSlot = "ShoulderSlot", headerIcon = I .. "INV_Shoulder_01" },
	{ enumName = "Cloak", label = "Back", invSlot = "BackSlot", headerIcon = I .. "INV_Misc_Cape_01" },
	{ enumName = "Chest", label = "Chest", invSlot = "ChestSlot", headerIcon = I .. "INV_Chest_Chain" },
	{ enumName = "Wrist", label = "Wrist", invSlot = "WristSlot", headerIcon = I .. "INV_Bracer_07" },
	{ enumName = "Hand", label = "Hands", invSlot = "HandsSlot", headerIcon = I .. "INV_Gauntlets_05" },
	{ enumName = "Waist", label = "Waist", invSlot = "WaistSlot", headerIcon = I .. "INV_Belt_08" },
	{ enumName = "Legs", label = "Legs", invSlot = "LegsSlot", headerIcon = I .. "INV_Pants_03" },
	{ enumName = "Feet", label = "Feet", invSlot = "FeetSlot", headerIcon = I .. "INV_Boots_Plate_01" },
	{ enumName = "MainHand", label = "Main Hand", invSlot = "MainHandSlot", headerIcon = I .. "INV_Sword_04" },
	{ enumName = "OffHand", label = "Off Hand", invSlot = "SecondaryHandSlot", headerIcon = I .. "INV_Shield_06" },
	{ enumName = "Finger", label = "Finger", invSlot = "Finger0Slot", headerIcon = I .. "INV_Jewelry_Ring_03" },
	{ enumName = "Trinket", label = "Trinket", invSlot = "Trinket0Slot", headerIcon = I .. "INV_Jewelry_Trinket_01" },
	{ enumName = "Other", label = "Other", invSlot = nil, headerIcon = QUESTION_MARK },
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
			headerIcon = def.headerIcon or SlotHeaderIcon(def.invSlot),
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
