local ADDON_NAME, MythicLoot = ...

-- Gear Track logic for the "Find Upgrades" action (see CONTEXT.md).
-- We read the player's OWN equipped items and decide which Slots hold gear
-- below a chosen Track Floor, so the UI can seed the Slot Filter with them.

-- Gear Track ladder, lowest -> highest. The addon is English-only (a V1 scope
-- decision), so we rank by the localized track name as it appears on an English
-- client (C_Item.GetItemUpgradeInfo().trackString is e.g. "Hero"). The numeric,
-- locale-independent trackStringID is printed by /ml tracks so a future
-- localization pass can switch to an ID-keyed map. See docs/adr/0004.
local TRACK_ORDER = { "Explorer", "Adventurer", "Veteran", "Champion", "Hero", "Myth" }
local TRACK_RANK = {}
for rank, name in ipairs(TRACK_ORDER) do
	TRACK_RANK[name] = rank
end

MythicLoot.TRACK_ORDER = TRACK_ORDER
MythicLoot.DEFAULT_TRACK_FLOOR = "Hero"

-- Slot (grid column) key -> the character-sheet inventory slot name(s) it covers.
-- Finger and Trinket each cover two equipped items; "Other" has no Gear Track
-- and is omitted entirely.
local SLOT_INV = {
	Head     = { "HeadSlot" },
	Neck     = { "NeckSlot" },
	Shoulder = { "ShoulderSlot" },
	Cloak    = { "BackSlot" },
	Chest    = { "ChestSlot" },
	Wrist    = { "WristSlot" },
	Hand     = { "HandsSlot" },
	Waist    = { "WaistSlot" },
	Legs     = { "LegsSlot" },
	Feet     = { "FeetSlot" },
	MainHand = { "MainHandSlot" },
	OffHand  = { "SecondaryHandSlot" },
	Finger   = { "Finger0Slot", "Finger1Slot" },
	Trinket  = { "Trinket0Slot", "Trinket1Slot" },
}

local function InvID(name)
	return (GetInventorySlotInfo(name))
end

-- Returns the Gear Track rank (1-6) of an item link, or nil when the item has no
-- upgrade track (legacy items, etc.) and so can't be ranked.
local function TrackRankForLink(itemLink)
	if not itemLink then return nil end
	local info = C_Item.GetItemUpgradeInfo(itemLink)
	if info and info.trackString then
		return TRACK_RANK[info.trackString]
	end
	return nil
end

-- An equipped item counts as below the floor when it's empty (a gap to fill) or
-- its track ranks below the floor. Unknown-track items are NOT flagged: we can't
-- prove they're below, so we don't seed false positives.
local function ItemBelowFloor(itemLink, floorRank)
	if not itemLink then return true end
	local rank = TrackRankForLink(itemLink)
	if not rank then return false end
	return rank < floorRank
end

local TWO_HAND_LOC = {
	INVTYPE_2HWEAPON = true,
	INVTYPE_RANGED = true,
	INVTYPE_RANGEDRIGHT = true,
}

-- An empty Off Hand is not a gap while a two-hander occupies the main hand.
local function MainHandIsTwoHand()
	local link = GetInventoryItemLink("player", InvID("MainHandSlot"))
	if not link then return false end
	local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
	return TWO_HAND_LOC[equipLoc] == true
end

-- Returns a set { [slotKey] = true } of the player's Slots whose equipped Gear
-- Track is below floorName. Paired Slots flag if EITHER item is below the floor.
function MythicLoot.GetNeededSlots(floorName)
	local floorRank = TRACK_RANK[floorName] or TRACK_RANK[MythicLoot.DEFAULT_TRACK_FLOOR]
	local needed = {}

	for slotKey, invNames in pairs(SLOT_INV) do
		if slotKey == "OffHand" then
			local link = GetInventoryItemLink("player", InvID("SecondaryHandSlot"))
			if link or not MainHandIsTwoHand() then
				if ItemBelowFloor(link, floorRank) then
					needed[slotKey] = true
				end
			end
		else
			for _, name in ipairs(invNames) do
				if ItemBelowFloor(GetInventoryItemLink("player", InvID(name)), floorRank) then
					needed[slotKey] = true
					break
				end
			end
		end
	end

	return needed
end

-- Diagnostic (/ml tracks): dump each equipped item's track so the live,
-- locale-independent trackStringID values can be verified against TRACK_ORDER.
function MythicLoot.PrintGearTracks()
	print("|cff33ff66MythicLoot|r equipped Gear Tracks:")
	for _, slotKey in ipairs({
		"Head", "Neck", "Shoulder", "Cloak", "Chest", "Wrist", "Hand", "Waist",
		"Legs", "Feet", "MainHand", "OffHand", "Finger", "Trinket",
	}) do
		for _, name in ipairs(SLOT_INV[slotKey]) do
			local link = GetInventoryItemLink("player", InvID(name))
			if not link then
				print("  " .. name .. ": (empty)")
			else
				local info = C_Item.GetItemUpgradeInfo(link)
				if info then
					print(string.format("  %s: %s  id=%s  %s/%s", name,
						tostring(info.trackString), tostring(info.trackStringID),
						tostring(info.currentLevel), tostring(info.maxLevel)))
				else
					print("  " .. name .. ": no upgrade info  " .. link)
				end
			end
		end
	end
end
