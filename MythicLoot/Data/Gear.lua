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

-- Upgrade-track bonus IDs for this season's gear, level 1 of each track. Appending
-- one to an item link makes the game render that track's item level, so bundled
-- loot can be shown at e.g. Myth 1/6 (ADR 0009). Derived from equipped-gear links
-- via /ml updump (Midnight S1, build 120007): Champion (12785), Hero (12793), Myth
-- (12801) observed directly — level N is base+(N-1), tracks +8 apart — with
-- Adventurer/Veteran extrapolated and confirmed in-game. Explorer alone breaks the
-- spacing (its real bonus is elsewhere), so it's dropped rather than shipped wrong.
MythicLoot.SeasonTrackBonus = {
	Adventurer = 12769, Veteran = 12777,
	Champion = 12785, Hero = 12793, Myth = 12801,
}

-- The Gear Tracks offered as upgrade targets in "Help me reach" (and the item level
-- the grid shows loot at): the full ladder minus Explorer, whose season bonus ID
-- isn't confirmed.
MythicLoot.TARGET_TRACKS = { "Adventurer", "Veteran", "Champion", "Hero", "Myth" }

-- Build a colourless item hyperlink for a bundled drop. With a trackBonus, the
-- game shows that upgrade track's item level; without one, the base item level.
-- The colons pad the itemString to the itemContext(35)+single-bonus position.
function MythicLoot.BuildItemLink(id, name, trackBonus)
	local itemString = trackBonus
		and ("item:" .. id .. string.rep(":", 11) .. "35:1:" .. trackBonus)
		or ("item:" .. id)
	return "|cffffffff|H" .. itemString .. "|h[" .. (name or ("item:" .. id)) .. "]|h|r"
end

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

-- ===== Secondary stat fit (Stat Priority lens, see CONTEXT.md) =====

-- Our stat keys -> the C_Item.GetItemStats table keys that carry that stat.
-- Versatility has shipped under more than one constant; accept both. Verify the
-- live keys with /ml stats before trusting these.
local SECONDARY_STATS = {
	{ key = "Crit",    label = "Crit",    mods = { "ITEM_MOD_CRIT_RATING_SHORT" } },
	{ key = "Haste",   label = "Haste",   mods = { "ITEM_MOD_HASTE_RATING_SHORT" } },
	{ key = "Mastery", label = "Mastery", mods = { "ITEM_MOD_MASTERY_RATING_SHORT" } },
	{ key = "Vers",    label = "Vers",    mods = { "ITEM_MOD_VERSATILITY", "ITEM_MOD_VERSATILITY_SHORT" } },
}
MythicLoot.SECONDARY_STATS = SECONDARY_STATS

local MOD_TO_KEY = {}
for _, stat in ipairs(SECONDARY_STATS) do
	for _, mod in ipairs(stat.mods) do
		MOD_TO_KEY[mod] = stat.key
	end
end

-- Set { [statKey] = true } of the secondary stats present on an item link, or nil.
local function ItemSecondaries(itemLink)
	if not itemLink then return nil end
	local stats = C_Item.GetItemStats(itemLink)
	if not stats then return nil end
	local present
	for mod, value in pairs(stats) do
		local key = MOD_TO_KEY[mod]
		if key and value and value ~= 0 then
			present = present or {}
			present[key] = true
		end
	end
	return present
end

-- Stat Tier of a loot item against the priority order, judged by the item's OWN
-- secondaries (equipped gear is not considered). Priority is the 1st and 2nd
-- picks only (ADR 0006):
--   3 = gold   (has the 1st AND the 2nd)
--   2 = silver (has the 1st only)
--   1 = bronze (has the 2nd but not the 1st)
--   0 = none
-- With only the 1st set, silver is the ceiling.
function MythicLoot.ItemStatTier(itemLink, priority)
	local first, second = priority[1], priority[2]
	if not (first or second) then return 0 end
	local sec = ItemSecondaries(itemLink)
	if not sec then return 0 end
	local hasFirst = first and sec[first]
	local hasSecond = second and sec[second]
	if hasFirst and hasSecond then return 3 end
	if hasFirst then return 2 end
	if hasSecond then return 1 end
	return 0
end

-- TEMPORARY diagnostic (/ml updump): record each equipped item's full link +
-- upgrade info + decomposed item string to SavedVariables, so the season's
-- track-upgrade encoding can be reverse-engineered for track-targeted item levels
-- (ADR 0009 follow-up). Delete once the TRACK_BONUS table is built.
function MythicLoot.DumpUpgrades()
	MythicLootGlobalDB = MythicLootGlobalDB or {}
	local dump = {}
	for _, slotKey in ipairs({
		"Head", "Neck", "Shoulder", "Cloak", "Chest", "Wrist", "Hand", "Waist",
		"Legs", "Feet", "MainHand", "OffHand", "Finger", "Trinket",
	}) do
		for _, name in ipairs(SLOT_INV[slotKey]) do
			local link = GetInventoryItemLink("player", InvID(name))
			if link then
				local info = C_Item.GetItemUpgradeInfo(link)
				local eff, _, base = C_Item.GetDetailedItemLevelInfo(link)
				table.insert(dump, {
					slot = name,
					link = link,
					itemString = link:match("|H(item[%-:%d]+)|h"),
					trackString = info and info.trackString,
					trackStringID = info and info.trackStringID,
					currentLevel = info and info.currentLevel,
					maxLevel = info and info.maxLevel,
					effectiveILvl = eff,
					baseILvl = base,
				})
			end
		end
	end
	MythicLootGlobalDB.upgradeDump = dump
	print("|cff33ff66MythicLoot|r: dumped " .. #dump
		.. " equipped items to SavedVariables — /reload, then tell Claude.")
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

-- Diagnostic (/ml stats): dump each equipped item's raw ITEM_MOD_* stat keys, so
-- the exact secondary-stat constants can be verified against SECONDARY_STATS.
function MythicLoot.PrintGearStats()
	print("|cff33ff66MythicLoot|r equipped secondary stats:")
	for _, slotKey in ipairs({
		"Head", "Neck", "Shoulder", "Cloak", "Chest", "Wrist", "Hand", "Waist",
		"Legs", "Feet", "MainHand", "OffHand", "Finger", "Trinket",
	}) do
		for _, name in ipairs(SLOT_INV[slotKey]) do
			local link = GetInventoryItemLink("player", InvID(name))
			if not link then
				print("  " .. name .. ": (empty)")
			else
				local stats = C_Item.GetItemStats(link)
				local parts = {}
				if stats then
					for k, v in pairs(stats) do
						if k:find("ITEM_MOD") then
							table.insert(parts, k .. "=" .. tostring(v))
						end
					end
				end
				print("  " .. name .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "(none)"))
			end
		end
	end
end
