local ADDON_NAME, MythicLoot = ...

-- Width is chosen so all 15 slot columns fit at once — no horizontal scroll,
-- nothing runs off the right edge.
-- Row 1 (specs/slots) is always shown; row 2 (Find Upgrades + Stat Priority) is
-- collapsible. The geometry here is the EXPANDED layout; collapsing hides row 2
-- and shifts the banner/header/list up by ROW2_SPAN, shrinking the window to
-- match (see ApplyToolsCollapse). The list keeps the same height either way.
-- Height is not fixed: the list never scrolls, so the window is sized to hug the
-- dungeon rows exactly (Render refits it once the rotation is known).
-- DEFAULT_WINDOW_HEIGHT fits the usual ~8-dungeon rotation so it opens tight
-- before data even loads.
local WINDOW_WIDTH = 760
local DEFAULT_WINDOW_HEIGHT = 550
local MIN_WINDOW_HEIGHT = 300
local ROW2_SPAN = 40 -- vertical space row 2 occupies; reclaimed when collapsed
local BANNER_SPAN = 18 -- extra height reserved for the wrong-spec banner, only when shown
-- Overall UI scale, locked for now (was a user stepper; may return later).
local UI_SCALE = 1.25
-- SCROLL_BOTTOM keeps a strip clear at the bottom for the footer bar.
local SCROLL_TOP, SCROLL_BOTTOM = -132, 28
local LIST_WIDTH = WINDOW_WIDTH - 42

-- Every row is one fixed-height line: [dungeon icon][name][slot grid][badge].
-- The slot grid starts at the same x on every row (GRID_START_X) and each
-- slot occupies the same column, so a column can be scanned straight down.
-- Slots a dungeon doesn't drop render as a gray placeholder, not a gap.
-- A fixed header row above the list labels each column with its slot icon.
local ROW_HEIGHT = 46
local DUNGEON_ICON = 38
local NAME_WIDTH = 130
local GRID_START_X = 6 + DUNGEON_ICON + 8 + NAME_WIDTH + 8
local CELL_SIZE, CELL_GAP = 26, 4
local CELL = CELL_SIZE + CELL_GAP
local BADGE_RESERVE = 70 -- right-side room kept clear for the coverage badge
local HEADER_CELL = CELL_SIZE
local HEADER_Y = -104
-- Toolbar rows start clear of the frame's top-left portrait; the list/header
-- below the portrait stay at the full-left margin (10).
local TOOLBAR_LEFT = 60
-- Row 2 sits below the portrait, so it doesn't need row 1's indent to clear it.
local ROW2_LEFT = 12

local COLOR_FULL = "|cff33ff66"
local COLOR_PARTIAL = "|cffffd100"
local COLOR_NONE = "|cffff4444"
local COLOR_WARN = "|cffff8000"

-- Stat Tier badge uses the profession material-quality medallion atlas:
-- Tier1 = bronze, Tier2 = silver, Tier3 = gold — matching our 1/2/3 tiers.
local STAR_TOOLTIP = {
	[1] = "Bronze: has your 2nd-priority stat.",
	[2] = "Silver: has your top-priority stat.",
	[3] = "Gold: has both of your priority stats.",
}

-- Heart marking a Favorited drop. Bottom-left of the cell, clear of the
-- top-left Stat Tier star and the bottom-right "+N" count. Texture is the
-- long-standing friendship heart; swap freely if a better atlas turns up.
local HEART_TEXTURE = "Interface\\COMMON\\friendship-heart"

-- The Loot Filter (replaces the old 3rd Stat Priority dropdown, ADR 0006): a
-- single lens dimming Cells whose Shown Drop fails the criterion. Persists per
-- character; defaults to "all".
local LOOT_FILTERS = {
	{ key = "all",       label = "All Loot" },
	{ key = "bronze",    label = "Bronze & up" },
	{ key = "silver",    label = "Silver & up" },
	{ key = "gold",      label = "Gold only" },
	{ key = "favorited", label = "Favorited" },
	{ key = "voidforge", label = "Voidforge (what's left)" },
}
local LOOT_FILTER_MINTIER = { bronze = 1, silver = 2, gold = 3 }

-- Claimed-mark texture: a green check in the cell's top-right corner, marking a
-- Drop the player has already won from a Voidforge roll at the Voidcore Track
-- (clear of the top-left star, bottom-left heart, bottom-right "+N").
local CLAIMED_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
-- Default Gear Track whose Voidforge pool we view (CONTEXT.md: Voidcore Track).
local DEFAULT_VOIDCORE_TRACK = "Myth"

local window, specDropdown, slotDropdown, floorDropdown, banner, status
local windowHeight = DEFAULT_WINDOW_HEIGHT -- mutable; refit to the row count once loaded
local bannerShown = false -- whether the wrong-spec banner is currently reserving a line
local statDropdowns = {} -- the two Stat Priority rank dropdowns (1st/2nd)
local filterDropdown     -- the Loot Filter lens (All / tier / Favorited)
local row2Widgets = {}   -- every widget on the collapsible second row
local collapseButton     -- row-1 toggle that shows/hides row 2
local scrollFrame, scrollChild, headerFrame
local Render, ApplyToolsCollapse, ApplyLayout -- forward declarations

-- ===== Per-character state =====

local function GetSpecSelection()
	local db = MythicLootCharDB
	if not (db.spec and db.spec.classID) then
		local classID, specID = MythicLoot.GetPlayingSpec()
		db.spec = { classID = classID, specID = specID }
	end
	return db.spec.classID, db.spec.specID or 0
end

local function SetSpecSelection(classID, specID)
	MythicLootCharDB.spec = { classID = classID, specID = specID or 0 }
	MythicLoot.Journal:RequestLoot(classID, specID or 0)
	Render()
end

-- Track Floor for Find Upgrades; persists per character (see CONTEXT.md).
local function GetTrackFloor()
	return (MythicLootCharDB and MythicLootCharDB.trackFloor) or MythicLoot.DEFAULT_TRACK_FLOOR
end

local function SetTrackFloor(name)
	MythicLootCharDB.trackFloor = name
end

-- One-click seed: replace the Slot Filter with exactly the player's own Slots
-- whose equipped Gear Track is below the Track Floor. Only seeds keys that are
-- The "Help me reach" dropdown shows the track that last seeded the Slot Filter,
-- or "—" when the current slots aren't tied to a track (the player edited them by
-- hand, or never used it). This is a transient display hint, not persisted.
local activeFloor

local function UpdateFloorDropdown()
	if floorDropdown then floorDropdown:SetText(activeFloor or "—") end
end

-- Called whenever the Slot Filter is touched by hand, so the dropdown stops
-- claiming the slots reflect a track.
local function ClearActiveFloor()
	activeFloor = nil
	UpdateFloorDropdown()
end

-- real grid columns; everything downstream (badges, highlights) follows the
-- resulting Slot Filter with no separate state.
local function SeedNeededSlots()
	local needed = MythicLoot.GetNeededSlots(GetTrackFloor())
	wipe(MythicLootCharDB.slotFilter)
	local count = 0
	for key in pairs(needed) do
		if MythicLoot.GetSlotByKey(key) then
			MythicLootCharDB.slotFilter[key] = true
			count = count + 1
		end
	end
	if count == 0 then
		print("|cff33ff66MythicLoot|r: nothing below "
			.. GetTrackFloor() .. " track — you're caught up.")
	end
	Render()
end

-- Stat Priority is stored per spec (class+spec) per character; the comparison
-- still uses the player's own equipped gear. The stored value is a (possibly
-- sparse) 1..2 table of stat keys for the two rank dropdowns (ADR 0006).
local function StatKey()
	local classID, specID = GetSpecSelection()
	return classID .. "-" .. (specID or 0)
end

-- Favorites and Pins share the Stat Priority key (per spec, per character): a
-- Guardian druid and a Balance druid want different items, so their wishlists
-- and pins are kept separate (see CONTEXT.md).
local function GetFavorites()
	MythicLootCharDB.favorites = MythicLootCharDB.favorites or {}
	local key = StatKey()
	local set = MythicLootCharDB.favorites[key]
	if not set then set = {}; MythicLootCharDB.favorites[key] = set end
	return set
end

local function IsFavorite(itemID)
	return itemID ~= nil and GetFavorites()[itemID] == true
end

local function ToggleFavorite(itemID)
	if not itemID then return end
	local set = GetFavorites()
	set[itemID] = (not set[itemID]) or nil
	Render()
end

-- A Pin records which Drop a Cell shows in the All view, keyed by dungeon
-- (challengeMapID) + Slot. nil means "auto" (favorite, else best Stat Tier).
local function GetPins()
	MythicLootCharDB.pins = MythicLootCharDB.pins or {}
	local key = StatKey()
	local t = MythicLootCharDB.pins[key]
	if not t then t = {}; MythicLootCharDB.pins[key] = t end
	return t
end

local function PinKey(mapID, slotKey) return mapID .. ":" .. slotKey end

local function GetPin(mapID, slotKey)
	return GetPins()[PinKey(mapID, slotKey)]
end

local function SetPin(mapID, slotKey, itemID)
	GetPins()[PinKey(mapID, slotKey)] = itemID -- itemID, or nil to clear
	Render()
end

-- The Loot Filter lens persists per character (a viewing state, like the Slot
-- Filter), defaulting to "all".
local VALID_LOOT_FILTER = {}
for _, f in ipairs(LOOT_FILTERS) do VALID_LOOT_FILTER[f.key] = true end

local function GetLootFilter()
	local f = MythicLootCharDB and MythicLootCharDB.lootFilter
	return (f and VALID_LOOT_FILTER[f]) and f or "all"
end

local function SetLootFilter(key)
	MythicLootCharDB.lootFilter = key
	Render()
end

-- ===== Voidforge claims (CONTEXT.md: Claim, Voidforge Pool, Voidcore Track) =====
--
-- A Claim records an item the player has already won from a Voidforge roll, which
-- the game then removes from that dungeon's future rolls at that Gear Track.
-- Tracked per character (a Claim is a fact about the player's own rolls, not the
-- Spec Selection), keyed dungeon + Track + item. The loot-spec filtering that
-- decides which Drops can appear is handled by the journal data, so a Claim for an
-- item the current spec can't get simply never surfaces — no per-spec key needed.
local function GetClaims()
	MythicLootCharDB.claims = MythicLootCharDB.claims or {}
	return MythicLootCharDB.claims
end

local function ClaimKey(mapID, track, itemID)
	return mapID .. ":" .. track .. ":" .. itemID
end

local function IsClaimed(mapID, track, itemID)
	return itemID ~= nil and GetClaims()[ClaimKey(mapID, track, itemID)] == true
end

local function ToggleClaim(mapID, track, itemID)
	if not (mapID and track and itemID) then return end
	local claims = GetClaims()
	local k = ClaimKey(mapID, track, itemID)
	claims[k] = (not claims[k]) or nil
	Render()
end

-- Claim seams for the auto-detect module (Data/Voidforge.lua), so it can record
-- wins / reconcile without reaching into these UI locals. SavedVariables exist by
-- the time any roll fires, so the lazy GetClaims init is safe here.

-- Set (or clear) a Claim to an explicit value. Returns true if it changed, so a
-- batch reconcile can refresh once and report a real count. Does NOT re-render —
-- the caller decides when (use RefreshWindow), keeping batch updates cheap.
function MythicLoot.SetClaim(mapID, track, itemID, claimed)
	if not (mapID and track and itemID) then return false end
	local claims = GetClaims()
	local k = ClaimKey(mapID, track, itemID)
	local cur = claims[k] == true
	local want = claimed and true or false
	if cur == want then return false end
	claims[k] = want or nil
	return true
end

-- Re-render the grid if it's open. Safe to call when the window was never created.
function MythicLoot.RefreshWindow()
	if window and window:IsShown() then Render() end
end

-- Record a single Voidforge win (the BONUS_ROLL_RESULT path); refreshes if open.
function MythicLoot.MarkClaim(mapID, track, itemID)
	if MythicLoot.SetClaim(mapID, track, itemID, true) then
		MythicLoot.RefreshWindow()
	end
end

-- The Gear Track whose Voidforge pool the grid currently shows (a viewing choice,
-- persisted per character; default Myth). Separate from the Track Floor — see
-- CONTEXT.md: Voidcore Track.
local function GetVoidcoreTrack()
	return (MythicLootCharDB and MythicLootCharDB.voidcoreTrack) or DEFAULT_VOIDCORE_TRACK
end

-- The filter dropdown's label while the Voidforge lens is on, carrying the track.
local function VoidforgeLabel(track)
	return "Voidforge · " .. track
end

-- Voidforge is a per-Loot-Spec history (a Voidcore rolls against the player's
-- Loot Spec table, not their Playing Spec), so the lens and the claim gestures
-- are only meaningful while the Spec Selection matches the real Loot Spec — that's
-- when the grid's loot table and the claims describe the same pool. (ADR 0008.)
local function VoidforgeAvailable()
	local classID, specID = GetSpecSelection()
	local lClass, lSpec = MythicLoot.GetLootSpec()
	return classID == lClass and specID == lSpec
end

local function GetStatPriority()
	MythicLootCharDB.statPriority = MythicLootCharDB.statPriority or {}
	local key = StatKey()
	local sel = MythicLootCharDB.statPriority[key]
	if not sel then
		sel = {}
		MythicLootCharDB.statPriority[key] = sel
	end
	return sel
end

local function StatLabel(statKey)
	for _, s in ipairs(MythicLoot.SECONDARY_STATS) do
		if s.key == statKey then return s.label end
	end
	return statKey
end

-- The scoring engine wants a dense, ordered array; the stored selection may have
-- gaps (a "—" in the 1st), so compact it preserving rank order.
local function CompactStatPriority(sel)
	local p = {}
	for i = 1, 2 do
		if sel[i] then table.insert(p, sel[i]) end
	end
	return p
end

-- Assign rank i to a stat (or nil to clear), removing that stat from any other
-- rank so it can't be double-picked. Render() refreshes the dropdown labels.
local function SetStatRank(i, statKey)
	local sel = GetStatPriority()
	if statKey then
		for j = 1, 2 do
			if j ~= i and sel[j] == statKey then sel[j] = nil end
		end
	end
	sel[i] = statKey
	Render()
end

local function UpdateStatDropdowns()
	if not statDropdowns[1] then return end
	local sel = GetStatPriority()
	for i = 1, 2 do
		statDropdowns[i]:SetText(sel[i] and StatLabel(sel[i]) or "—")
	end
end

-- A Loot Filter option only makes sense with the data it reads: the tier modes
-- need a Stat Priority to rank against; Favorited needs at least one Favorite.
-- Unmet options are greyed in the menu; a selected-then-invalidated option (e.g.
-- after switching to a spec with no priorities) falls back to "all" so the grid
-- never blanks for no visible reason.
local function StatActiveNow()
	return #CompactStatPriority(GetStatPriority()) > 0
end

local function HasFavorites()
	return next(GetFavorites()) ~= nil
end

local function LootFilterReason(key)
	if LOOT_FILTER_MINTIER[key] and not StatActiveNow() then
		return "Set a stat priority first — these rank loot by your stats."
	elseif key == "favorited" and not HasFavorites() then
		return "Favorite an item first — left-click a cell to pick one."
	elseif key == "voidforge" and not VoidforgeAvailable() then
		return "Switch to your loot spec (the Loot Spec button) to see what your Voidcores can still win."
	end
end

local function EffectiveLootFilter()
	local f = GetLootFilter()
	return LootFilterReason(f) and "all" or f
end

-- Returns the checked Slots in canonical order, plus a key-set for matching.
local function GetCheckedSlots()
	local list, set = {}, {}
	for _, slot in ipairs(MythicLoot.Slots) do
		if MythicLootCharDB.slotFilter[slot.key] then
			table.insert(list, slot)
			set[slot.key] = true
		end
	end
	return list, set
end

-- ===== Text helpers =====

local CLASS_ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- Inline texture-escape so icons can sit in any menu/button/label string.
local function ClassIconMarkup(classFile)
	local c = classFile and CLASS_ICON_TCOORDS[classFile]
	if not c then return "" end
	return string.format("|T%s:18:18:0:0:256:256:%d:%d:%d:%d|t ",
		CLASS_ICON_TEX, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function SpecIconMarkup(icon)
	if not icon then return "" end
	return "|T" .. icon .. ":18:18|t "
end

local function SpecText(classID, specID)
	local classInfo = C_CreatureInfo.GetClassInfo(classID)
	local className = classInfo and classInfo.className or ("Class " .. classID)
	local specName, specIcon
	for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
		local id, name, _, icon = GetSpecializationInfoForClassID(classID, i)
		if id == specID then
			specName = name
			specIcon = icon
			break
		end
	end
	local text = (specName or "All Specs") .. " " .. className
	local color = classInfo and C_ClassColor and C_ClassColor.GetClassColor(classInfo.classFile)
	if color then
		text = color:WrapTextInColorCode(text)
	end
	return SpecIconMarkup(specIcon) .. text
end

local function UpdateToolbarText()
	local classID, specID = GetSpecSelection()
	specDropdown:SetText(SpecText(classID, specID))

	local checked = GetCheckedSlots()
	if #checked == 0 then
		slotDropdown:SetText("All Slots")
	elseif #checked == 1 then
		slotDropdown:SetText(checked[1].label)
	else
		slotDropdown:SetText(#checked .. " Slots")
	end
end

local function UpdateBanner()
	local classID, specID = GetSpecSelection()
	local playingClass, playingSpec = MythicLoot.GetPlayingSpec()
	local wrong = not (classID == playingClass and specID == playingSpec)
	if wrong then
		banner:SetText(COLOR_WARN .. "Viewing:|r " .. SpecText(classID, specID)
			.. COLOR_WARN .. " — not your current spec|r")
	else
		banner:SetText("")
	end
	-- Reserve/release the banner's line when its visibility changes.
	if wrong ~= bannerShown then
		bannerShown = wrong
		if ApplyLayout then ApplyLayout() end
	end
end

-- ===== Frame pools =====

local rowPool, rowsInUse = {}, {}
local cellPool, cellsInUse = {}, {}
local headerPool, headersInUse = {}, {}
local colHLPool, colHLInUse = {}, {} -- full-height column-highlight bands

-- Teleport buttons are persistent (one per fixed rotation slot), not pooled:
-- they're SecureActionButtons whose spell attribute can only be set out of
-- combat, so we configure them once and let them scroll with the list.
local teleportButtons = {}
local teleportsNeedSetup = true

local function CreateRow()
	local row = CreateFrame("Frame", nil, scrollChild)
	row:SetSize(LIST_WIDTH, ROW_HEIGHT)

	row.Bg = row:CreateTexture(nil, "BACKGROUND")
	row.Bg:SetAllPoints()

	-- Thin separator along the row's bottom edge so rows read as distinct bands
	-- instead of floating. Subtler than the column-header rule (0.15). Static on
	-- the pooled frame; shown/hidden with the row.
	row.Divider = row:CreateTexture(nil, "BORDER")
	row.Divider:SetHeight(1)
	row.Divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
	row.Divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
	row.Divider:SetColorTexture(1, 1, 1, 0.08)

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(DUNGEON_ICON, DUNGEON_ICON)
	row.Icon:SetPoint("LEFT", 6, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Thin border so the icon reads as a distinct, prominent element.
	row.IconBorder = row:CreateTexture(nil, "BORDER")
	row.IconBorder:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -2, 2)
	row.IconBorder:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 2, -2)
	row.IconBorder:SetColorTexture(0, 0, 0, 0.6)

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
	row.Name:SetWidth(NAME_WIDTH)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false) -- truncate long names rather than wrap/overlap the grid

	row.Badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	row.Badge:SetPoint("RIGHT", row, "RIGHT", -14, 0)

	-- Shown instead of the grid for loading / missing-data states.
	row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Status:SetPoint("LEFT", row, "LEFT", GRID_START_X, 0)
	row.Status:SetJustifyH("LEFT")

	return row
end

local function AcquireRow()
	local row = table.remove(rowPool) or CreateRow()
	row:Show()
	table.insert(rowsInUse, row)
	return row
end

local function CreateCell()
	local cell = CreateFrame("Button", nil, scrollChild)
	cell:SetSize(CELL_SIZE, CELL_SIZE)

	-- Full-cell dark fill; the icon/placeholder inset 1px leaves it showing as
	-- a thin border, giving every cell a distinct outline (grid look).
	cell.Border = cell:CreateTexture(nil, "BACKGROUND")
	cell.Border:SetAllPoints()
	cell.Border:SetColorTexture(0, 0, 0, 0.85)

	-- Gray placeholder shown when this dungeon drops nothing for the column's slot.
	cell.Empty = cell:CreateTexture(nil, "BORDER")
	cell.Empty:SetPoint("TOPLEFT", 1, -1)
	cell.Empty:SetPoint("BOTTOMRIGHT", -1, 1)
	cell.Empty:SetColorTexture(0.16, 0.16, 0.18, 0.9)

	cell.Icon = cell:CreateTexture(nil, "ARTWORK")
	cell.Icon:SetPoint("TOPLEFT", 1, -1)
	cell.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
	cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- "+N" when a dungeon drops more than one item for this slot.
	cell.Count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	cell.Count:SetPoint("BOTTOMRIGHT", 1, 0)

	-- Stat Tier badge (profession material-quality medallion), atlas set per tier.
	-- Sits in the top-left corner, clear of the icon center.
	cell.Star = cell:CreateTexture(nil, "OVERLAY")
	cell.Star:SetSize(16, 16)
	cell.Star:SetPoint("TOPLEFT", -3, 3)
	cell.Star:Hide()

	-- Favorite heart: bottom-left corner, so it never collides with the top-left
	-- star or the bottom-right "+N" count. Shown when the Shown Drop is Favorited.
	cell.Heart = cell:CreateTexture(nil, "OVERLAY")
	cell.Heart:SetSize(13, 13)
	cell.Heart:SetPoint("BOTTOMLEFT", -2, -2)
	cell.Heart:SetTexture(HEART_TEXTURE)
	cell.Heart:SetVertexColor(1, 0.32, 0.42)
	cell.Heart:Hide()

	-- Claimed mark: top-right corner, clear of the other three. Shown when the
	-- Shown Drop is already won at the Voidcore Track (in every Loot Filter mode).
	cell.Claimed = cell:CreateTexture(nil, "OVERLAY")
	cell.Claimed:SetSize(14, 14)
	cell.Claimed:SetPoint("TOPRIGHT", 3, 3)
	cell.Claimed:SetTexture(CLAIMED_TEXTURE)
	cell.Claimed:Hide()

	cell:SetScript("OnEnter", function(self)
		if not (self.link or self.itemID) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.link then
			GameTooltip:SetHyperlink(self.link)
		else
			GameTooltip:SetItemByID(self.itemID)
		end
		if self.statTier and self.statTier > 0 then
			GameTooltip:AddLine(STAR_TOOLTIP[self.statTier], 1, 0.82, 0, true)
		end
		if self.itemID then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(self.isFav and "Right-click to unfavorite."
				or "Right-click to favorite.", 0.6, 0.6, 0.6)
			if self.voidTrack then
				GameTooltip:AddLine(self.isClaimed
					and ("Won at " .. self.voidTrack .. " — shift+right-click to clear.")
					or ("Shift+right-click: mark won at " .. self.voidTrack .. "."),
					0.5, 0.8, 0.5)
			end
			if self.extraDrops and self.extraDrops > 0 then
				GameTooltip:AddLine("Left-click for all " .. (self.extraDrops + 1)
					.. " drops.", 0.6, 0.6, 0.6)
			end
		end
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:SetScript("OnClick", function(self, button)
		-- Right-click is the quick Favorite toggle on the Shown Drop;
		-- shift+right-click toggles its Voidforge claim at the Voidcore Track;
		-- left-click (unmodified) opens the Drop Picker. Shift-left still links to
		-- chat. These bindings are intentionally easy to retune in-game.
		if button == "RightButton" then
			if IsShiftKeyDown() then
				if self.itemID and self.voidTrack then
					ToggleClaim(self.mapID, self.voidTrack, self.itemID)
				end
			elseif self.itemID then
				ToggleFavorite(self.itemID)
			end
		elseif self.link and IsModifiedClick("CHATLINK") then
			ChatEdit_InsertLink(self.link)
		elseif self.OpenPicker then
			self:OpenPicker()
		end
	end)

	return cell
end

local function AcquireCell(row)
	local cell = table.remove(cellPool) or CreateCell()
	cell:SetParent(row)
	cell:Show()
	table.insert(cellsInUse, cell)
	return cell
end

local function SetCellItem(cell, item, extra)
	cell.itemID = item.itemID
	cell.link = item.link
	cell.Empty:Hide()
	cell.Icon:SetTexture(item.icon or 134400) -- question-mark icon while uncached
	cell.Icon:Show()
	cell.Count:SetText(extra > 0 and ("+" .. extra) or "")
	cell.extraDrops = extra
	cell.statTier = 0
	cell.Star:Hide()
	cell.isClaimed = false
	cell.Claimed:Hide()
end

local function SetCellEmpty(cell)
	cell.itemID = nil
	cell.link = nil
	cell.voidTrack = nil
	cell.Icon:Hide()
	cell.Empty:Show()
	cell.Count:SetText("")
	cell.extraDrops = 0
	cell.isFav = false
	cell.statTier = 0
	cell.Star:Hide()
	cell.Heart:Hide()
	cell.isClaimed = false
	cell.Claimed:Hide()
end

-- Show or hide this cell's Favorite heart (the Shown Drop is Favorited).
local function SetCellHeart(cell, isFav)
	cell.isFav = isFav and true or false
	cell.Heart:SetShown(cell.isFav)
end

-- Show or hide this cell's Claimed mark (the Shown Drop is won at the Voidcore Track).
local function SetCellClaimed(cell, isClaimed)
	cell.isClaimed = isClaimed and true or false
	cell.Claimed:SetShown(cell.isClaimed)
end

-- Show this cell's Stat Tier badge (1 bronze / 2 silver / 3 gold), or hide it.
local function SetCellStar(cell, tier)
	cell.statTier = tier
	if tier and tier >= 1 and tier <= 3 then
		cell.Star:SetAtlas("Professions-Icon-Quality-Tier" .. tier, false)
		cell.Star:Show()
	else
		cell.Star:Hide()
	end
end

local function ReleaseAll()
	for _, cell in ipairs(cellsInUse) do
		cell:Hide()
		cell:ClearAllPoints()
		cell:SetParent(scrollChild)
		table.insert(cellPool, cell)
	end
	wipe(cellsInUse)
	for _, row in ipairs(rowsInUse) do
		row:Hide()
		row:ClearAllPoints()
		table.insert(rowPool, row)
	end
	wipe(rowsInUse)
end

local function CreateHeaderCell()
	local h = CreateFrame("Button", nil, headerFrame)
	h:SetSize(HEADER_CELL, HEADER_CELL)

	-- Same bordered-slot styling as the grid cells so a header reads as the
	-- top of its column.
	h.Border = h:CreateTexture(nil, "BACKGROUND")
	h.Border:SetAllPoints()
	h.Border:SetColorTexture(0, 0, 0, 0.85)

	h.Bg = h:CreateTexture(nil, "BORDER")
	h.Bg:SetPoint("TOPLEFT", 1, -1)
	h.Bg:SetPoint("BOTTOMRIGHT", -1, 1)
	h.Bg:SetColorTexture(0.2, 0.2, 0.23, 0.95)

	h.Icon = h:CreateTexture(nil, "ARTWORK")
	h.Icon:SetPoint("TOPLEFT", 2, -2)
	h.Icon:SetPoint("BOTTOMRIGHT", -2, 2)

	h:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.label or "")
		GameTooltip:Show()
	end)
	h:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return h
end

-- Rebuilds the fixed column-header row. When a Slot Filter is active, the
-- selected columns stay bright and the rest dim, matching the rows below.
local function UpdateHeaders(columns, numCols, checkedSet, filtered)
	for _, h in ipairs(headersInUse) do
		h:Hide()
		table.insert(headerPool, h)
	end
	wipe(headersInUse)

	for i = 1, numCols do
		local slot = columns[i]
		local h = table.remove(headerPool) or CreateHeaderCell()
		h:ClearAllPoints()
		h:SetPoint("LEFT", headerFrame, "LEFT", GRID_START_X + (i - 1) * CELL, 0)
		h.Icon:SetTexture(slot.headerIcon)
		h.label = slot.label
		local active = (not filtered) or checkedSet[slot.key]
		h:SetAlpha(active and 1 or 0.3)
		if filtered and active then
			h.Border:SetColorTexture(1, 0.82, 0, 1)       -- bright gold outline marks a selected slot
			h.Bg:SetColorTexture(0.55, 0.42, 0.05, 0.9)   -- warm fill, icon still legible
		else
			h.Border:SetColorTexture(0, 0, 0, 0.85)
			h.Bg:SetColorTexture(0.2, 0.2, 0.23, 0.95)
		end
		h:Show()
		table.insert(headersInUse, h)
	end
end

-- A soft vertical band behind each selected column, spanning the whole list,
-- so a selected slot reads as a highlighted column top to bottom. Parented to
-- the scroll frame (fixed height) and behind the scrolling cells.
local function UpdateColumnHighlights(columns, numCols, checkedSet, filtered)
	for _, t in ipairs(colHLInUse) do
		t:Hide()
		table.insert(colHLPool, t)
	end
	wipe(colHLInUse)
	if not filtered then return end

	for i = 1, numCols do
		if checkedSet[columns[i].key] then
			local t = table.remove(colHLPool) or scrollFrame:CreateTexture(nil, "BACKGROUND")
			local x = GRID_START_X + (i - 1) * CELL - 2
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", x, 0)
			t:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMLEFT", x, 0)
			t:SetWidth(CELL_SIZE + 4)
			t:SetColorTexture(1, 0.82, 0.2, 0.18)
			t:Show()
			table.insert(colHLInUse, t)
		end
	end
end

-- ===== Teleports =====

local function CreateTeleportButton()
	local b = CreateFrame("Button", nil, scrollChild, "SecureActionButtonTemplate")
	b:SetSize(DUNGEON_ICON, DUNGEON_ICON)
	-- Sit above the pooled dungeon rows (same parent) so clicks land here.
	b:SetFrameLevel(scrollChild:GetFrameLevel() + 10)
	-- Register both edges so the cast fires regardless of the client's
	-- cast-on-key-down setting; the secure framework triggers only the right one.
	b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	b:SetAttribute("type", "spell")
	b:SetAttribute("unit", "player")

	-- Blue frame marks "you know this teleport — click to use it".
	b.Glow = b:CreateTexture(nil, "BACKGROUND")
	b.Glow:SetPoint("TOPLEFT", -2, 2)
	b.Glow:SetPoint("BOTTOMRIGHT", 2, -2)
	b.Glow:SetColorTexture(0.2, 0.6, 1.0, 0.9)

	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetAllPoints()
	b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	b.Cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.Cooldown:SetAllPoints()

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.25)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(self.spellID)
		GameTooltip:AddLine("Click to teleport to " .. (self.dungeonName or ""), 0.3, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return b
end

local function SetTeleportCooldown(b)
	local cd = C_Spell.GetSpellCooldown(b.spellID)
	if cd then
		b.Cooldown:SetCooldown(cd.startTime, cd.duration)
	end
end

-- "Known" detection changed across patches; check every variant so learned
-- teleports are reliably detected.
local function HasTeleport(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then return true end
	if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then return true end
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	if IsSpellKnown and IsSpellKnown(spellID) then return true end
	return false
end

-- Position/configure a secure teleport button over each dungeon's icon, for
-- dungeons whose teleport the player has learned. Secure attributes can only be
-- set out of combat, so defer if we're locked down.
local function ConfigureTeleports()
	local rot = MythicLoot.Journal:GetRotation()
	if not rot then return end
	if InCombatLockdown() then
		teleportsNeedSetup = true
		return
	end

	for i, dungeon in ipairs(rot) do
		local b = teleportButtons[i]
		local spellID = MythicLoot.GetTeleportSpell(dungeon.challengeMapID)
		if spellID and HasTeleport(spellID) then
			if not b then
				b = CreateTeleportButton()
				teleportButtons[i] = b
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6,
				-((i - 1) * (ROW_HEIGHT + 2)) - (ROW_HEIGHT - DUNGEON_ICON) / 2)
			b:SetAttribute("spell", spellID)
			b.spellID = spellID
			b.dungeonName = dungeon.name
			b.Icon:SetTexture(dungeon.icon)
			SetTeleportCooldown(b)
			b:Show()
		elseif b then
			b:Hide()
			b.spellID, b.dungeonName = nil, nil
		end
	end
	-- Hide any buttons left over from a previously longer rotation.
	for i, b in pairs(teleportButtons) do
		if i > #rot then
			b:Hide()
			b.spellID, b.dungeonName = nil, nil
		end
	end
	teleportsNeedSetup = false
end

local function UpdateTeleportCooldowns()
	for _, b in pairs(teleportButtons) do
		if b:IsShown() and b.spellID then
			SetTeleportCooldown(b)
		end
	end
end

-- ===== Rendering =====

-- Choose a Cell's Shown Drop and whether it passes the active Loot Filter, per
-- the precedence in CONTEXT.md: a tier/Favorited filter auto-surfaces the Drop
-- it is about (dimming the Cell if none qualifies); the All view honors a Pin,
-- else the best-tier Favorite, else the best Stat Tier Drop. The Cell's star and
-- heart always describe whichever Drop this returns.
local function ResolveCell(items, slot, mapID, statPriority, statActive, filter, claimedNow)
	local canTier = statActive and slot.key ~= "Other"
	local function tierOf(it)
		return canTier and MythicLoot.ItemStatTier(it.link, statPriority) or 0
	end

	local bestDrop, bestTier = items[1], 0
	if canTier then
		for _, it in ipairs(items) do
			local t = tierOf(it)
			if t > bestTier then bestDrop, bestTier = it, t end
		end
	end

	-- Highest-tier Favorited Drop in this Cell, if any.
	local favDrop, favTier = nil, -1
	for _, it in ipairs(items) do
		if IsFavorite(it.itemID) then
			local t = tierOf(it)
			if t > favTier then favDrop, favTier = it, t end
		end
	end

	-- The pinned Drop, if the player pinned one that still drops here.
	local pinID, pinDrop = GetPin(mapID, slot.key), nil
	if pinID then
		for _, it in ipairs(items) do
			if it.itemID == pinID then pinDrop = it break end
		end
	end

	local shown, tier, passes
	if filter == "voidforge" then
		-- The Cell passes while any Drop here is still unclaimed at the Voidcore
		-- Track; show the first such Drop (or a pinned one if it's still rollable),
		-- so the lit cells read as "where a Voidcore can still win me something".
		-- "Other" items (crates/tokens) aren't transmutable, so they never count.
		local avail
		if slot.key ~= "Other" then
			for _, it in ipairs(items) do
				if not claimedNow(it.itemID) then avail = it break end
			end
		end
		passes = avail ~= nil
		if pinDrop and not claimedNow(pinDrop.itemID) then
			shown = pinDrop
		else
			shown = avail or items[1]
		end
		tier = tierOf(shown)
	elseif filter == "favorited" then
		passes = favDrop ~= nil
		-- Whether the Cell passes depends on any Favorite existing, but a pinned
		-- Favorite still wins which one shows — so re-pinning updates live.
		if pinDrop and IsFavorite(pinDrop.itemID) then
			shown, tier = pinDrop, tierOf(pinDrop)
		else
			shown = favDrop or items[1]
			tier = favDrop and favTier or 0
		end
	elseif LOOT_FILTER_MINTIER[filter] then
		local minTier = LOOT_FILTER_MINTIER[filter]
		passes = bestTier >= minTier
		-- Pass/dim follows whether ANY drop qualifies (keeps coverage honest), but
		-- a pinned drop that also qualifies wins which one shows.
		if pinDrop and tierOf(pinDrop) >= minTier then
			shown, tier = pinDrop, tierOf(pinDrop)
		else
			shown, tier = bestDrop, bestTier
		end
	else -- "all": Pin -> Favorite -> best Stat Tier
		if pinDrop then
			shown, tier = pinDrop, tierOf(pinDrop)
		elseif favDrop then
			shown, tier = favDrop, favTier
		else
			shown, tier = bestDrop, bestTier
		end
		passes = true
	end

	return {
		shown = shown,
		tier = tier,
		extra = #items - 1,
		isFav = IsFavorite(shown.itemID),
		isClaimed = claimedNow(shown.itemID),
		passes = passes,
	}
end

-- Menu label for a Drop: item icon, its name, and the Stat Tier medallion when it
-- has one. Prefer a real hyperlink (colored, clickable) when we have one; the
-- shipped loot only carries a bare "item:<id>" itemString, so fall back to the
-- plain name rather than render the itemString text.
local function DropLabel(it, tier)
	local icon = "|T" .. (it.icon or 134400) .. ":16:16:0:0|t "
	local linkIsReal = it.link and it.link:find("|H", 1, true)
	local name = (linkIsReal and it.link) or it.name or ("item:" .. tostring(it.itemID))
	local medal = (tier and tier > 0)
		and (" |A:Professions-Icon-Quality-Tier" .. tier .. ":14:14|a") or ""
	return icon .. name .. medal
end

-- The Drop Picker (left-click a Cell): lists every Drop so the player can Pin
-- which one shows in the All view and Favorite any of them. Click bindings are
-- intentionally easy to retune in-game.
local function OpenDropPicker(cell)
	local items, mapID, slotKey = cell.drops, cell.mapID, cell.slotKey
	if not (items and #items > 0 and mapID and slotKey) then return end
	local slot = MythicLoot.GetSlotByKey(slotKey)
	local statPriority = CompactStatPriority(GetStatPriority())
	local canTier = (#statPriority > 0) and slotKey ~= "Other"
	local function tierOf(it)
		return canTier and MythicLoot.ItemStatTier(it.link, statPriority) or 0
	end

	MenuUtil.CreateContextMenu(cell, function(_, root)
		root:CreateTitle(slot and slot.label or "Drops")

		-- What shows in the All view: Auto, or a specific pinned Drop.
		root:CreateRadio("Auto (favorite, else best)",
			function() return GetPin(mapID, slotKey) == nil end,
			function() SetPin(mapID, slotKey, nil) end)
		for _, it in ipairs(items) do
			local d = it
			local r = root:CreateRadio(DropLabel(d, tierOf(d)),
				function() return GetPin(mapID, slotKey) == d.itemID end,
				function() SetPin(mapID, slotKey, d.itemID) end)
			r:SetTooltip(function(tooltip) tooltip:SetHyperlink(d.link) end)
		end

		-- Voidforge: mark which Drops you've already won at the Voidcore Track.
		-- Only offered while viewing your own spec (claims are your Loot Spec
		-- history); the marks then drive the "Voidforge (what's left)" lens.
		if VoidforgeAvailable() then
			local track = GetVoidcoreTrack()
			root:CreateDivider()
			root:CreateTitle("Won at " .. track)
			for _, it in ipairs(items) do
				local d = it
				root:CreateCheckbox(DropLabel(d, tierOf(d)),
					function() return IsClaimed(mapID, track, d.itemID) end,
					function() ToggleClaim(mapID, track, d.itemID) end)
			end
		end
	end)
end

local function LayoutDungeonRow(row, dungeon, loot, checkedList, checkedSet, columns, numCols, statPriority, statActive, lootFilter)
	row.Icon:SetTexture(dungeon.icon)
	row.Name:SetText(dungeon.name)
	row.Bg:SetColorTexture(1, 1, 1, 0.04)
	row:SetAlpha(1)
	row.Badge:SetText("")
	row.Status:SetText("")

	if not loot then
		row.Status:SetText("Loading…")
		return
	end
	if loot.missing then
		row.Status:SetText("No journal data found for this dungeon")
		return
	end

	local mapID = dungeon.challengeMapID

	-- Group this dungeon's items by slot so each column shows its slot's drops,
	-- then resolve each slot's Shown Drop + filter-pass once (used by both the
	-- coverage badge and the cell render below).
	local bySlot = {}
	for _, item in ipairs(loot.items) do
		local list = bySlot[item.slotKey]
		if not list then
			list = {}
			bySlot[item.slotKey] = list
		end
		table.insert(list, item)
	end

	-- Voidforge claim state for this dungeon at the viewing Track. Claims are the
	-- player's own Loot Spec history, so they only count while viewing their own
	-- spec. The whole pool (all loot-spec Drops) resets once every item is Claimed,
	-- so a fully-claimed dungeon reads as freshly full, never empty (CONTEXT.md:
	-- Voidforge Pool).
	local ownSpec = VoidforgeAvailable()
	local voidTrack = GetVoidcoreTrack()
	local poolExhausted = false
	if ownSpec then
		-- Only transmutable gear is in the Voidforge Pool — "Other" items (crates,
		-- tokens) never are, so they must not count toward exhaustion or they'd keep
		-- a pool from ever reading as fully won.
		local total, claimed = 0, 0
		for _, item in ipairs(loot.items) do
			if item.slotKey ~= "Other" then
				total = total + 1
				if IsClaimed(mapID, voidTrack, item.itemID) then claimed = claimed + 1 end
			end
		end
		if total > 0 and claimed == total then
			-- The game reopens a Pool the instant its last item is won, so a fully
			-- claimed pool is really a fresh one. Clear the now-void Claims from
			-- saved state (not just the display) to match — otherwise the next
			-- toggle drops claimed below total, resurrecting the stale claims and
			-- making the pool look exhausted again (ADR 0008 reset rule).
			local claims = GetClaims()
			for _, item in ipairs(loot.items) do
				if item.slotKey ~= "Other" then
					claims[ClaimKey(mapID, voidTrack, item.itemID)] = nil
				end
			end
			poolExhausted = true
		end
	end
	local function claimedNow(itemID)
		if not ownSpec or poolExhausted then return false end
		return IsClaimed(mapID, voidTrack, itemID)
	end

	local resolved = {}
	for key, items in pairs(bySlot) do
		local slot = MythicLoot.GetSlotByKey(key)
		if slot then
			resolved[key] = ResolveCell(items, slot, mapID, statPriority, statActive, lootFilter, claimedNow)
		end
	end

	-- Coverage badge is meaningful only while the Slot Filter is active. The
	-- numerator counts checked Slots whose Drop survives the Loot Filter, so
	-- tightening the lens lowers the count (CONTEXT.md: Slot Coverage).
	local filtered = #checkedList > 0
	if filtered then
		local covered = 0
		for _, slot in ipairs(checkedList) do
			local r = resolved[slot.key]
			if r and r.passes then
				covered = covered + 1
			end
		end
		local badgeText = covered .. "/" .. #checkedList
		if covered == #checkedList then
			row.Badge:SetText(COLOR_FULL .. badgeText .. "|r")
			row.Bg:SetColorTexture(0.2, 0.8, 0.3, 0.16)
		elseif covered == 0 then
			row.Badge:SetText(COLOR_NONE .. badgeText .. "|r")
			row:SetAlpha(0.35)
		else
			row.Badge:SetText(COLOR_PARTIAL .. badgeText .. "|r")
		end
	end

	-- Always render the full column set in the same positions; filtering only
	-- dims, so nothing shifts. A cell is lit only when it passes BOTH the Slot
	-- Filter and the Loot Filter.
	for i = 1, numCols do
		local slot = columns[i]
		local cell = AcquireCell(row)
		cell:SetPoint("LEFT", row, "LEFT", GRID_START_X + (i - 1) * CELL, 0)
		cell.mapID = mapID
		cell.slotKey = slot.key
		cell.drops = bySlot[slot.key]
		cell.OpenPicker = OpenDropPicker
		-- Only enable claim gestures/marks while viewing the player's own spec.
		cell.voidTrack = ownSpec and voidTrack or nil
		local r = resolved[slot.key]
		if r then
			SetCellItem(cell, r.shown, r.extra)
			SetCellStar(cell, r.tier)
			SetCellHeart(cell, r.isFav)
			SetCellClaimed(cell, r.isClaimed)
		else
			SetCellEmpty(cell)
		end
		local slotLit = (not filtered) or checkedSet[slot.key]
		local filterLit = (lootFilter == "all") or (r and r.passes)
		cell:SetAlpha((slotLit and filterLit) and 1 or 0.25)
	end
end

function Render()
	if not window or not window:IsShown() then return end

	UpdateToolbarText()
	UpdateStatDropdowns()
	UpdateBanner()
	ReleaseAll()

	-- Stat Priority lens: when set, each row stars its best-tier drop per slot
	-- (bronze/silver/gold by the item's own secondaries vs the priority).
	local statPriority = CompactStatPriority(GetStatPriority())
	local statActive = #statPriority > 0
	-- Use the EFFECTIVE filter: a selected option whose data is gone (e.g. after a
	-- spec change) reads as "all" so the grid never blanks. Keep the dropdown label
	-- matching what's actually in effect.
	local lootFilter = EffectiveLootFilter()
	if filterDropdown then
		if lootFilter == "voidforge" then
			filterDropdown:SetText(VoidforgeLabel(GetVoidcoreTrack()))
		else
			for _, f in ipairs(LOOT_FILTERS) do
				if f.key == lootFilter then filterDropdown:SetText(f.label) end
			end
		end
	end

	-- The grid always shows every slot column in the same position, so items
	-- never jump when the filter changes. Filtering only dims the non-selected
	-- columns (handled per-cell / per-header). Badge room is always reserved on
	-- the right so the layout is identical filtered or not.
	local checkedList, checkedSet = GetCheckedSlots()
	local filtered = #checkedList > 0
	local columns = MythicLoot.Slots
	local maxCols = math.max(0, math.floor((LIST_WIDTH - BADGE_RESERVE - GRID_START_X) / CELL))
	local numCols = math.min(#columns, maxCols)
	UpdateHeaders(columns, numCols, checkedSet, filtered)
	UpdateColumnHighlights(columns, numCols, checkedSet, filtered)

	-- Show loot item levels at the "Help me reach" track (default Myth 1/6 when the
	-- dropdown is blank). The Journal rebuilds its links if this changed.
	if MythicLoot.Journal.SetDisplayTrack then
		MythicLoot.Journal:SetDisplayTrack(activeFloor or "Myth")
	end

	local classID, specID = GetSpecSelection()
	local data = MythicLoot.Journal:GetDungeonData(classID, specID)
	if not data then
		status:SetText("Requesting season dungeon list from the server…")
		scrollChild:SetHeight(1)
		return
	end

	local y = 0
	local anyLoading = false

	for _, d in ipairs(data) do
		local row = AcquireRow()
		row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
		LayoutDungeonRow(row, d.info, d.loot, checkedList, checkedSet, columns, numCols, statPriority, statActive, lootFilter)
		if not d.loot then
			anyLoading = true
		end
		y = y + ROW_HEIGHT + 2
	end

	scrollChild:SetHeight(math.max(y, 1))
	status:SetText(anyLoading and "Loading dungeon loot…" or "")

	-- Size the window to hug the rows — the list never scrolls, so there's no
	-- reason to leave dead space below the last dungeon. Chrome above/below the
	-- list is fixed (|SCROLL_TOP| + SCROLL_BOTTOM); the rest is row content, plus
	-- a touch of padding so the last row isn't flush against the bottom.
	local desired = math.max(y + 6 + (-SCROLL_TOP + SCROLL_BOTTOM), MIN_WINDOW_HEIGHT)
	if math.abs(desired - windowHeight) >= 1 then
		windowHeight = desired
		ApplyLayout()
	end

	if teleportsNeedSetup then
		ConfigureTeleports()
	end
end

-- ===== Window construction =====

local function SavePosition()
	local point, _, relativePoint, x, y = window:GetPoint()
	MythicLootGlobalDB.window = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition()
	local pos = MythicLootGlobalDB and MythicLootGlobalDB.window
	window:ClearAllPoints()
	if pos then
		window:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
	else
		window:SetPoint("CENTER")
	end
end

local function CreateToolbar()
	specDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	specDropdown:SetSize(200, 26)
	specDropdown:SetPoint("TOPLEFT", TOOLBAR_LEFT, -30)
	-- We manage dropdown text ourselves; stop the menu system overwriting it
	-- with auto-composed selection text.
	specDropdown.disableSelectionText = true
	specDropdown:SetupMenu(function(_, rootDescription)
		local selectedClass, selectedSpec = GetSpecSelection()
		for classID = 1, GetNumClasses() do
			local classInfo = C_CreatureInfo.GetClassInfo(classID)
			if classInfo then
				local classLabel = ClassIconMarkup(classInfo.classFile) .. classInfo.className
				local classButton = rootDescription:CreateButton(classLabel)
				for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
					local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classID, i)
					classButton:CreateRadio(SpecIconMarkup(specIcon) .. specName,
						function() return classID == selectedClass and specID == selectedSpec end,
						function() SetSpecSelection(classID, specID) end)
				end
			end
		end
	end)

	slotDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	slotDropdown:SetSize(150, 26)
	slotDropdown:SetPoint("LEFT", specDropdown, "RIGHT", 6, 0)
	slotDropdown.disableSelectionText = true
	slotDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:CreateButton("All Slots", function()
			wipe(MythicLootCharDB.slotFilter)
			ClearActiveFloor()
			Render()
		end)
		for _, slot in ipairs(MythicLoot.Slots) do
			rootDescription:CreateCheckbox(slot.label,
				function() return MythicLootCharDB.slotFilter[slot.key] == true end,
				function()
					if MythicLootCharDB.slotFilter[slot.key] then
						MythicLootCharDB.slotFilter[slot.key] = nil
					else
						MythicLootCharDB.slotFilter[slot.key] = true
					end
					ClearActiveFloor()
					Render()
				end)
		end
	end)

	local playingButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	playingButton:SetSize(80, 24)
	playingButton:SetPoint("LEFT", slotDropdown, "RIGHT", 6, 0)
	playingButton:SetText("My Spec")
	playingButton:SetScript("OnClick", function()
		SetSpecSelection(MythicLoot.GetPlayingSpec())
	end)

	local lootButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	lootButton:SetSize(80, 24)
	lootButton:SetPoint("LEFT", playingButton, "RIGHT", 4, 0)
	lootButton:SetText("Loot Spec")
	lootButton:SetScript("OnClick", function()
		SetSpecSelection(MythicLoot.GetLootSpec())
	end)

	-- Second row (collapsible): the floor dropdown IS the Find Upgrades action.
	-- Picking a track sets the goal and immediately seeds the Slot Filter from any
	-- slot whose own gear hasn't reached it — no separate trigger button needed.
	local goalLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	goalLabel:SetPoint("TOPLEFT", ROW2_LEFT, -74)
	goalLabel:SetText("Help me reach")
	table.insert(row2Widgets, goalLabel)

	floorDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	floorDropdown:SetSize(110, 24)
	floorDropdown:SetPoint("LEFT", goalLabel, "RIGHT", 8, 0)
	floorDropdown.disableSelectionText = true
	table.insert(row2Widgets, floorDropdown)
	floorDropdown:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText("Find Upgrades")
		GameTooltip:AddLine("Pick the track you want every slot to reach. Slots whose "
			.. "own gear is still below it get checked in the Slot Filter. Pick \"—\" "
			.. "or edit the slots by hand to step out of this mode.",
			0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	floorDropdown:HookScript("OnLeave", GameTooltip_Hide)
	floorDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:CreateRadio("—",
			function() return activeFloor == nil end,
			function() ClearActiveFloor() end)
		for _, track in ipairs(MythicLoot.TARGET_TRACKS) do
			rootDescription:CreateRadio(track,
				function() return activeFloor == track end,
				function()
					SetTrackFloor(track)
					activeFloor = track
					SeedNeededSlots()
					UpdateFloorDropdown()
				end)
		end
	end)
	UpdateFloorDropdown()

	-- Stat Priority (min-max lens) shares row 2, to the right of the Find Upgrades
	-- controls. Two ranked dropdowns (ADR 0006); a stat picked in one rank drops
	-- out of the other. Tier badges in the grid then grade drops by these stats.
	local statsLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statsLabel:SetPoint("LEFT", floorDropdown, "RIGHT", 16, 0)
	statsLabel:SetText("Stats:")
	table.insert(row2Widgets, statsLabel)

	local ordinals = { "1st", "2nd" }
	local anchor = statsLabel
	for i = 1, 2 do
		local ord = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		ord:SetText(ordinals[i])
		ord:SetPoint("LEFT", anchor, "RIGHT", (i == 1) and 8 or 7, 0)
		table.insert(row2Widgets, ord)

		local dd = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
		dd:SetSize(92, 24)
		dd:SetPoint("LEFT", ord, "RIGHT", 3, 0)
		dd.disableSelectionText = true
		dd:SetupMenu(function(_, rootDescription)
			rootDescription:CreateButton("—", function() SetStatRank(i, nil) end)
			for _, s in ipairs(MythicLoot.SECONDARY_STATS) do
				rootDescription:CreateRadio(s.label,
					function() return GetStatPriority()[i] == s.key end,
					function() SetStatRank(i, s.key) end)
			end
		end)
		statDropdowns[i] = dd
		table.insert(row2Widgets, dd)
		anchor = dd
	end
	UpdateStatDropdowns()

	-- Loot Filter: the lens that dims Cells whose Shown Drop fails the criterion
	-- (and feeds the Slot Coverage count). Took the 3rd Stat dropdown's spot.
	local showLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	showLabel:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
	showLabel:SetText("Show:")
	table.insert(row2Widgets, showLabel)

	filterDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	filterDropdown:SetSize(110, 24)
	filterDropdown:SetPoint("LEFT", showLabel, "RIGHT", 4, 0)
	filterDropdown.disableSelectionText = true
	filterDropdown:SetupMenu(function(_, rootDescription)
		for _, f in ipairs(LOOT_FILTERS) do
			local key = f.key
			-- The generator re-runs each time the menu opens, so a snapshot reason
			-- here reflects current state. Grey out options whose data isn't there
			-- yet, and explain why on hover.
			local reason = LootFilterReason(key)
			if key == "voidforge" and reason == nil then
				-- Voidforge carries a Track choice, so it's a submenu: picking a track
				-- both turns the lens on and sets which Voidcore pool to view. The
				-- Voidcore Track persists, so the always-on Claimed marks use it too.
				local sub = rootDescription:CreateButton(f.label)
				-- Voidcore tracks are the full ladder (TRACK_ORDER), independent of the
				-- "Help me reach" TARGET_TRACKS (which drops Explorer): a Voidcore can
				-- roll at any Gear Track, unrelated to the season ilvl bonus table.
				for _, track in ipairs(MythicLoot.TRACK_ORDER) do
					sub:CreateRadio(track,
						function()
							return EffectiveLootFilter() == "voidforge" and GetVoidcoreTrack() == track
						end,
						function()
							MythicLootCharDB.voidcoreTrack = track
							SetLootFilter("voidforge")
							filterDropdown:SetText(VoidforgeLabel(track))
						end)
				end
			else
				local radio = rootDescription:CreateRadio(f.label,
					function() return EffectiveLootFilter() == key end,
					function()
						SetLootFilter(key)
						filterDropdown:SetText(f.label)
					end)
				radio:SetEnabled(reason == nil)
				if reason then
					radio:SetTooltip(function(tooltip)
						GameTooltip_SetTitle(tooltip, f.label)
						GameTooltip_AddNormalLine(tooltip, reason)
					end)
				end
			end
		end
	end)
	table.insert(row2Widgets, filterDropdown)

	-- Reset: back to a clean slate — your playing spec, all slots shown, no track
	-- and no Loot Filter. Deliberately leaves Favorites (and per-cell Pins) alone.
	local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	resetButton:SetSize(64, 24)
	resetButton:SetPoint("LEFT", filterDropdown, "RIGHT", 10, 0)
	resetButton:SetText("Reset")
	resetButton:SetScript("OnClick", function()
		wipe(MythicLootCharDB.slotFilter)
		MythicLootCharDB.lootFilter = "all"
		activeFloor = nil
		UpdateFloorDropdown()
		if filterDropdown then filterDropdown:SetText(LOOT_FILTERS[1].label) end
		SetSpecSelection(MythicLoot.GetPlayingSpec()) -- re-renders
	end)
	resetButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText("Reset")
		GameTooltip:AddLine("Back to your current spec with all slots shown and no "
			.. "filters. Your favorites are kept.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	resetButton:SetScript("OnLeave", GameTooltip_Hide)
	table.insert(row2Widgets, resetButton)

	-- Advanced toggle, top-right (clear of the left-side dropdowns/buttons): shows
	-- or hides row 2 (Find Upgrades + Stat Priority). Lives on row 1 so it stays
	-- visible when row 2 is hidden. Label is set by ApplyToolsCollapse.
	collapseButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	collapseButton:SetSize(110, 24)
	collapseButton:SetPoint("TOPRIGHT", -10, -30)
	collapseButton:SetScript("OnClick", function()
		ApplyToolsCollapse(not MythicLootGlobalDB.toolsCollapsed)
	end)
	collapseButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText("Advanced tools")
		GameTooltip:AddLine("Find Upgrades and Stat Priority.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	collapseButton:SetScript("OnLeave", GameTooltip_Hide)

	-- Spec-mismatch warning. Anchored later (in CreateWindow) to ride just above
	-- the column header, so it tracks the header through collapse without needing
	-- its own reserved band in the toolbar.
	banner = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner:SetJustifyH("LEFT")
end

-- Show/hide the collapsible second row and reflow the banner, header, list, and
-- window to match. The list keeps its height; the window grows/shrinks by
-- ROW2_SPAN. State persists account-wide.
function ApplyToolsCollapse(collapsed)
	collapsed = collapsed or false
	MythicLootGlobalDB.toolsCollapsed = collapsed
	for _, w in ipairs(row2Widgets) do
		w:SetShown(not collapsed)
	end
	-- Label reflects what a click will do.
	collapseButton:SetText(collapsed and "Show Advanced" or "Hide Advanced")
	ApplyLayout()
end

-- Position the header, list, window, and inset for the current collapse + banner
-- state. Collapsing row 2 pulls everything UP by ROW2_SPAN (and shrinks the
-- window); showing the wrong-spec banner pushes the header/list DOWN by
-- BANNER_SPAN (and grows the window) so the banner gets its own line instead of
-- crowding the header. The visible list height is unchanged either way.
function ApplyLayout()
	local shift = (MythicLootGlobalDB.toolsCollapsed and ROW2_SPAN or 0)
	local banner_ = bannerShown and BANNER_SPAN or 0
	local off = shift - banner_
	headerFrame:ClearAllPoints()
	headerFrame:SetPoint("TOPLEFT", 10, HEADER_Y + off)
	scrollFrame:ClearAllPoints()
	scrollFrame:SetPoint("TOPLEFT", 10, SCROLL_TOP + off)
	scrollFrame:SetPoint("BOTTOMRIGHT", -32, SCROLL_BOTTOM)
	window:SetHeight(windowHeight - off)

	-- Recessed inset tracks the header so it keeps framing the list in all states.
	if window.Inset then
		window.Inset:ClearAllPoints()
		window.Inset:SetPoint("TOPLEFT", window, "TOPLEFT", 8, -100 + off)
		window.Inset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 30)
	end
end

local function CreateWindow()
	-- ButtonFrameTemplate: ornate gold border + portrait + a recessed Inset panel.
	-- The list/header stay parented to `window` and render on top of the inset, so
	-- the inset is purely the gray recess behind them (no coordinate-origin change).
	window = CreateFrame("Frame", "MythicLootWindow", UIParent, "ButtonFrameTemplate")
	window:SetSize(WINDOW_WIDTH, windowHeight)
	window:SetScale(UI_SCALE)
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	-- Title: PortraitFrame/ButtonFrame uses SetTitle; older templates use TitleText.
	if window.SetTitle then
		window:SetTitle("MythicLoot")
	elseif window.TitleText then
		window.TitleText:SetText("MythicLoot")
	end

	-- Portrait: the Mythic Keystone icon (inv_relics_hourglass), top-left — a crisp
	-- 64px icon. To use custom art instead, ship a .tga/.blp under MythicLoot/Media
	-- and point this at "Interface\\AddOns\\MythicLoot\\Media\\<file>" (no extension).
	local portraitIcon = "Interface\\Icons\\inv_relics_hourglass"
	if window.SetPortraitToAsset then
		window:SetPortraitToAsset(portraitIcon)
	elseif window.PortraitContainer and window.PortraitContainer.portrait then
		window.PortraitContainer.portrait:SetTexture(portraitIcon)
	end

	-- The recessed inset is reframed to sit behind the header+list (clear of the
	-- toolbar above and footer below) in ApplyToolsCollapse, so it tracks collapse.

	RestorePosition()

	CreateToolbar()

	-- Fixed column-header row above the (vertically scrolling) list.
	headerFrame = CreateFrame("Frame", nil, window)
	headerFrame:SetPoint("TOPLEFT", 10, HEADER_Y)
	headerFrame:SetSize(LIST_WIDTH, HEADER_CELL)

	local dungeonLabel = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dungeonLabel:SetPoint("LEFT", headerFrame, "LEFT", 6, 0)
	dungeonLabel:SetText("Dungeon")

	local divider = headerFrame:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -2)
	divider:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -2)
	divider:SetHeight(1)
	divider:SetColorTexture(1, 1, 1, 0.15)

	-- Banner is vertically centered in the space above the header (it moves with
	-- the header on collapse / banner-reserve).
	banner:SetPoint("LEFT", headerFrame, "TOPLEFT", 4, 18)

	scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 10, SCROLL_TOP)
	scrollFrame:SetPoint("BOTTOMRIGHT", -32, SCROLL_BOTTOM)
	-- No scrollbar: the season list fits without scrolling, so the bar is just
	-- visual noise. Hide it and keep it hidden if the template tries to reshow it.
	local scrollBar = scrollFrame.ScrollBar
	if scrollBar then
		scrollBar:Hide()
		scrollBar:SetScript("OnShow", scrollBar.Hide)
	end
	scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(LIST_WIDTH)
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)

	status = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("BOTTOM", 0, 26)

	-- Footer bar: a thin rule and a left-aligned addon name + version, read from
	-- the .toc at runtime (C_AddOns is the 12.0 namespace; global is deprecated).
	local footerRule = window:CreateTexture(nil, "ARTWORK")
	footerRule:SetHeight(1)
	footerRule:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 22)
	footerRule:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -8, 22)
	footerRule:SetColorTexture(1, 1, 1, 0.10)

	local version = (C_AddOns and C_AddOns.GetAddOnMetadata
		and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or ""
	local footer = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 8)
	footer:SetText("MythicLoot" .. (version ~= "" and ("  v" .. version) or ""))

	window:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	window:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
	window:RegisterEvent("SPELLS_CHANGED")          -- a teleport may have been learned
	window:RegisterEvent("SPELL_UPDATE_COOLDOWN")   -- refresh teleport cooldown swipes
	window:RegisterEvent("PLAYER_REGEN_ENABLED")    -- finish any teleport setup deferred by combat
	window:SetScript("OnEvent", function(self, event)
		if not self:IsShown() then return end
		if event == "SPELL_UPDATE_COOLDOWN" then
			UpdateTeleportCooldowns()
		elseif event == "PLAYER_REGEN_ENABLED" then
			if teleportsNeedSetup then ConfigureTeleports() end
		else
			if event == "SPELLS_CHANGED" then teleportsNeedSetup = true end
			Render()
		end
	end)
	window:SetScript("OnShow", function()
		local classID, specID = GetSpecSelection()
		MythicLoot.Journal:RequestLoot(classID, specID)
		Render()
	end)

	MythicLoot.Journal:SetCallback(Render)

	-- Apply the saved collapsed/expanded state (positions header, list, window).
	ApplyToolsCollapse(MythicLootGlobalDB.toolsCollapsed)

	-- Close on Escape like a normal game window.
	tinsert(UISpecialFrames, "MythicLootWindow")

	-- CreateFrame spawns visible; start hidden so the first toggle shows
	-- the window (and fires OnShow, which kicks off the loot request).
	window:Hide()
end

function MythicLoot:ToggleWindow()
	if not window then
		CreateWindow()
	end
	window:SetShown(not window:IsShown())
end
