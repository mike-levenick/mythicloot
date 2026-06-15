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

local COLOR_FULL = "|cff33ff66"
local COLOR_PARTIAL = "|cffffd100"
local COLOR_NONE = "|cffff4444"
local COLOR_WARN = "|cffff8000"

-- Stat Tier badge uses the profession material-quality medallion atlas:
-- Tier1 = bronze, Tier2 = silver, Tier3 = gold — matching our 1/2/3 tiers.
local STAR_TOOLTIP = {
	[1] = "Bronze: has a secondary stat you want.",
	[2] = "Silver: has your top-priority stat.",
	[3] = "Gold: has your top stat and a secondary.",
}

local window, specDropdown, slotDropdown, floorDropdown, banner, status
local windowHeight = DEFAULT_WINDOW_HEIGHT -- mutable; refit to the row count once loaded
local bannerShown = false -- whether the wrong-spec banner is currently reserving a line
local statDropdowns = {} -- the three Stat Priority rank dropdowns (1st/2nd/3rd)
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
-- sparse) 1..3 table of stat keys for the three rank dropdowns.
local function StatKey()
	local classID, specID = GetSpecSelection()
	return classID .. "-" .. (specID or 0)
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
-- gaps (a "—" in the middle), so compact it preserving rank order.
local function CompactStatPriority(sel)
	local p = {}
	for i = 1, 3 do
		if sel[i] then table.insert(p, sel[i]) end
	end
	return p
end

-- Assign rank i to a stat (or nil to clear), removing that stat from any other
-- rank so it can't be double-picked. Render() refreshes the dropdown labels.
local function SetStatRank(i, statKey)
	local sel = GetStatPriority()
	if statKey then
		for j = 1, 3 do
			if j ~= i and sel[j] == statKey then sel[j] = nil end
		end
	end
	sel[i] = statKey
	Render()
end

local function UpdateStatDropdowns()
	if not statDropdowns[1] then return end
	local sel = GetStatPriority()
	for i = 1, 3 do
		statDropdowns[i]:SetText(sel[i] and StatLabel(sel[i]) or "—")
	end
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

	-- Gold star: this drop's secondary stats fit better than what you're wearing
	-- (Stat Improvement). Sits in the top-left corner, clear of the icon center.
	-- Stat Tier badge (profession material-quality medallion), atlas set per tier.
	cell.Star = cell:CreateTexture(nil, "OVERLAY")
	cell.Star:SetSize(16, 16)
	cell.Star:SetPoint("TOPLEFT", -3, 3)
	cell.Star:Hide()

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
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	cell:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick("CHATLINK") then
			ChatEdit_InsertLink(self.link)
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
	cell.statTier = 0
	cell.Star:Hide()
end

local function SetCellEmpty(cell)
	cell.itemID = nil
	cell.link = nil
	cell.Icon:Hide()
	cell.Empty:Show()
	cell.Count:SetText("")
	cell.statTier = 0
	cell.Star:Hide()
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

local function LayoutDungeonRow(row, dungeon, loot, checkedList, checkedSet, columns, numCols, statPriority, statActive)
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

	-- Coverage badge is meaningful only while filtering.
	local filtered = #checkedList > 0
	if filtered then
		local covered = 0
		for _, slot in ipairs(checkedList) do
			if loot.slotSet[slot.key] then
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

	-- Group this dungeon's items by slot so each column shows its slot's drops.
	local bySlot = {}
	for _, item in ipairs(loot.items) do
		local list = bySlot[item.slotKey]
		if not list then
			list = {}
			bySlot[item.slotKey] = list
		end
		table.insert(list, item)
	end

	-- Always render the full column set in the same positions; when filtering,
	-- the non-selected columns dim so nothing shifts as the filter changes.
	for i = 1, numCols do
		local slot = columns[i]
		local cell = AcquireCell(row)
		cell:SetPoint("LEFT", row, "LEFT", GRID_START_X + (i - 1) * CELL, 0)
		local items = bySlot[slot.key]
		if items then
			-- With the Stat Priority lens on, surface this slot's best-tier drop
			-- and star it by tier (the item's own secondaries vs your priority).
			local shown, extra = items[1], #items - 1
			local tier = 0
			-- "Other" is the non-gear catch-all (mounts, recipes, …) — never a Slot
			-- to min-max, so it gets no Stat Badge even if an item carries secondaries.
			if statActive and slot.key ~= "Other" then
				local best, bestTier = items[1], 0
				for _, it in ipairs(items) do
					local t = MythicLoot.ItemStatTier(it.link, statPriority)
					if t > bestTier then best, bestTier = it, t end
				end
				shown, tier = best, bestTier
			end
			SetCellItem(cell, shown, extra)
			SetCellStar(cell, tier)
		else
			SetCellEmpty(cell)
		end
		local active = (not filtered) or checkedSet[slot.key]
		cell:SetAlpha(active and 1 or 0.25)
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
		LayoutDungeonRow(row, d.info, d.loot, checkedList, checkedSet, columns, numCols, statPriority, statActive)
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
	goalLabel:SetPoint("TOPLEFT", TOOLBAR_LEFT, -74)
	goalLabel:SetText("Find Upgrades to reach")
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
			.. "own gear is still below it get checked in the Slot Filter.",
			0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	floorDropdown:HookScript("OnLeave", GameTooltip_Hide)
	floorDropdown:SetupMenu(function(_, rootDescription)
		for _, track in ipairs(MythicLoot.TRACK_ORDER) do
			rootDescription:CreateRadio(track,
				function() return GetTrackFloor() == track end,
				function()
					SetTrackFloor(track)
					floorDropdown:SetText(track)
					SeedNeededSlots()
				end)
		end
	end)
	floorDropdown:SetText(GetTrackFloor())

	-- Stat Priority (min-max lens) shares row 2, to the right of the Find Upgrades
	-- controls. Three ranked dropdowns; a stat picked in one rank drops out of the
	-- others. Tier badges in the grid then grade drops by these stats.
	local statsLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statsLabel:SetPoint("LEFT", floorDropdown, "RIGHT", 24, 0)
	statsLabel:SetText("Stats:")
	table.insert(row2Widgets, statsLabel)

	local ordinals = { "1st", "2nd", "3rd" }
	local anchor = statsLabel
	for i = 1, 3 do
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
