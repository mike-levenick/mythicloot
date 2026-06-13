local ADDON_NAME, MythicLoot = ...

-- Width is chosen so all 15 slot columns fit at once — no horizontal scroll,
-- nothing runs off the right edge.
local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 560
-- User-adjustable overall scale, saved account-wide.
local DEFAULT_SCALE, MIN_SCALE, MAX_SCALE, SCALE_STEP = 1.15, 0.8, 1.6, 0.05
local SCROLL_TOP, SCROLL_BOTTOM = -120, 12
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
local HEADER_Y = -90

local COLOR_FULL = "|cff33ff66"
local COLOR_PARTIAL = "|cffffd100"
local COLOR_NONE = "|cffff4444"
local COLOR_WARN = "|cffff8000"

local window, specDropdown, slotDropdown, banner, status, scaleReadout
local scrollFrame, scrollChild, headerFrame
local Render -- forward declaration

-- ===== Scale =====

local function GetScale()
	return (MythicLootGlobalDB and MythicLootGlobalDB.scale) or DEFAULT_SCALE
end

local function ApplyScale(value)
	value = math.max(MIN_SCALE, math.min(MAX_SCALE, value))
	MythicLootGlobalDB.scale = value
	if window then window:SetScale(value) end
	if scaleReadout then
		scaleReadout:SetText(math.floor(value * 100 + 0.5) .. "%")
	end
end

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
	if classID == playingClass and specID == playingSpec then
		banner:SetText("")
	else
		banner:SetText(COLOR_WARN .. "Viewing:|r " .. SpecText(classID, specID)
			.. COLOR_WARN .. " — not your current spec|r")
	end
end

-- ===== Frame pools =====

local rowPool, rowsInUse = {}, {}
local cellPool, cellsInUse = {}, {}
local headerPool, headersInUse = {}, {}
local colHLPool, colHLInUse = {}, {} -- full-height column-highlight bands

local function CreateRow()
	local row = CreateFrame("Frame", nil, scrollChild)
	row:SetSize(LIST_WIDTH, ROW_HEIGHT)

	row.Bg = row:CreateTexture(nil, "BACKGROUND")
	row.Bg:SetAllPoints()

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

	cell:SetScript("OnEnter", function(self)
		if not (self.link or self.itemID) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.link then
			GameTooltip:SetHyperlink(self.link)
		else
			GameTooltip:SetItemByID(self.itemID)
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
end

local function SetCellEmpty(cell)
	cell.itemID = nil
	cell.link = nil
	cell.Icon:Hide()
	cell.Empty:Show()
	cell.Count:SetText("")
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
	h.Icon:SetVertexColor(1.5, 1.5, 1.5) -- brighten the dim slot silhouettes

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

-- ===== Rendering =====

local function LayoutDungeonRow(row, dungeon, loot, checkedList, checkedSet, columns, numCols)
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
			SetCellItem(cell, items[1], #items - 1)
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
	UpdateBanner()
	ReleaseAll()

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
		LayoutDungeonRow(row, d.info, d.loot, checkedList, checkedSet, columns, numCols)
		if not d.loot then
			anyLoading = true
		end
		y = y + ROW_HEIGHT + 2
	end

	scrollChild:SetHeight(math.max(y, 1))
	status:SetText(anyLoading and "Loading dungeon loot…" or "")
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
	specDropdown:SetPoint("TOPLEFT", 10, -30)
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

	-- Scale controls, top-right (clear of the left-side dropdowns/buttons).
	-- Stepper buttons rather than a drag slider: a click bumps the scale and the
	-- button barely moves, whereas a slider would rescale itself mid-drag.
	local scaleUp = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	scaleUp:SetSize(26, 24)
	scaleUp:SetPoint("TOPRIGHT", -10, -30)
	scaleUp:SetText("+")
	scaleUp:SetScript("OnClick", function() ApplyScale(GetScale() + SCALE_STEP) end)

	scaleReadout = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scaleReadout:SetPoint("RIGHT", scaleUp, "LEFT", -4, 0)
	scaleReadout:SetWidth(40)
	scaleReadout:SetJustifyH("CENTER")
	scaleReadout:SetText(math.floor(GetScale() * 100 + 0.5) .. "%")

	local scaleDown = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	scaleDown:SetSize(26, 24)
	scaleDown:SetPoint("RIGHT", scaleReadout, "LEFT", -4, 0)
	scaleDown:SetText("−")
	scaleDown:SetScript("OnClick", function() ApplyScale(GetScale() - SCALE_STEP) end)

	local scaleLabel = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	scaleLabel:SetPoint("RIGHT", scaleDown, "LEFT", -4, 0)
	scaleLabel:SetText("Scale")

	banner = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner:SetPoint("TOPLEFT", 14, -68)
	banner:SetJustifyH("LEFT")
end

local function CreateWindow()
	window = CreateFrame("Frame", "MythicLootWindow", UIParent, "BasicFrameTemplateWithInset")
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetScale(GetScale())
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
	if window.TitleText then
		window.TitleText:SetText("MythicLoot")
	end
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

	scrollFrame = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 10, SCROLL_TOP)
	scrollFrame:SetPoint("BOTTOMRIGHT", -32, SCROLL_BOTTOM)
	scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(LIST_WIDTH)
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)

	status = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("BOTTOM", 0, 16)

	window:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	window:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
	window:SetScript("OnEvent", function()
		if window:IsShown() then Render() end
	end)
	window:SetScript("OnShow", function()
		local classID, specID = GetSpecSelection()
		MythicLoot.Journal:RequestLoot(classID, specID)
		Render()
	end)

	MythicLoot.Journal:SetCallback(Render)

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
