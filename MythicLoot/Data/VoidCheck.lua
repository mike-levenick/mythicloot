local ADDON_NAME, MythicLoot = ...

-- TEMPORARY verification tool for the Voidforge feature (ADR 0008). It gathers the
-- live facts we need before building auto-detect; delete this file once Voidforge
-- ships. Usage:
--   /ml voidcheck            cache-stamp inputs + your loot spec, and start watching roll events
--   /ml voidcheck arm        one-shot: dump the NEXT tooltip you hover (use on the roll popup —
--                            its "what's left / greyed out" list vanishes when you roll)
--   /ml voidcheck bag        list bag items (itemID + link) to help you find the Voidcore/container
--   /ml voidcheck <itemID>   dump that item's tooltip lines via C_TooltipInfo — does it list the
--                            remaining roll loot? (the retroactive-scrape path, if it works)

local function p(...)
	print("|cff8000ffMythicLoot voidcheck|r:", ...)
end

-- The "what's left / greyed out" list lives in the transient roll popup's mouseover
-- tooltip, which disappears when you roll. So: arm a one-shot capture, then hover
-- the popup — the next tooltip that shows is dumped automatically (no typing race).
local armed = false
local tipHooked = false
local function ArmTooltipCapture()
	if not tipHooked then
		tipHooked = true
		GameTooltip:HookScript("OnShow", function(self)
			if not armed then return end
			armed = false
			p("captured tooltip —", self:NumLines(), "lines:")
			for i = 1, self:NumLines() do
				local fs = _G["GameTooltipTextLeft" .. i]
				local t = fs and fs:GetText()
				if t and t ~= "" then print(string.format("  %2d: %s", i, t)) end
			end
			p("greyed-out (already-claimed) lines usually come through dimmed — note which.")
		end)
	end
	armed = true
	p("ARMED — now mouse over the roll popup (or its reward). The next tooltip is dumped.")
end

-- Watch the (reused) bonus-roll events so we can see which one fires on a Voidforge
-- win and what it carries. Registers only events that exist on this client.
local watcher
local function StartWatching()
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", function(_, event, ...)
			local n = select("#", ...)
			local parts = {}
			for i = 1, n do parts[i] = tostring((select(i, ...))) end
			p("EVENT", event, "→", (n > 0) and table.concat(parts, " | ") or "(no args)")
		end)
	end
	for _, ev in ipairs({
		"BONUS_ROLL_RESULT", "BONUS_ROLL_STARTED", "BONUS_ROLL_FAILED",
		"BONUS_ROLL_ACTIVATE", "BONUS_ROLL_DEACTIVATE", "SHOW_LOOT_TOAST",
	}) do
		pcall(watcher.RegisterEvent, watcher, ev)
	end
	p("watching roll events — do a Voidcore roll and watch chat for which event fires and its args.")
end

local function DumpTooltip(itemID)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		p("C_TooltipInfo.GetItemByID is unavailable on this client.")
		return
	end
	local data = C_TooltipInfo.GetItemByID(itemID)
	if not (data and data.lines) then
		p("no tooltip data for item", itemID, "— mouse over the item once to cache it, then retry.")
		return
	end
	p("tooltip for item", itemID, "—", #data.lines, "lines:")
	for i, line in ipairs(data.lines) do
		if line.leftText and line.leftText ~= "" then
			print(string.format("  %2d: %s", i, line.leftText))
		end
	end
	p("a bulleted list of item names near the bottom = the loot you can still roll on.")
end

local function DumpBags()
	if not (C_Container and C_Container.GetContainerNumSlots) then
		p("C_Container unavailable.")
		return
	end
	p("bag items (itemID — link):")
	for bag = 0, 5 do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				print(string.format("  %d — %s", info.itemID, info.hyperlink or "?"))
			end
		end
	end
end

function MythicLoot.VoidCheck(arg)
	arg = arg or ""
	local itemID = tonumber(arg)
	if itemID then
		DumpTooltip(itemID)
		return
	end
	if arg == "bag" then
		DumpBags()
		return
	end
	if arg == "arm" then
		ArmTooltipCapture()
		return
	end
	local tocVersion = select(4, GetBuildInfo())
	local season = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
	p("cache stamp inputs — toc/build:", tocVersion, " season:", tostring(season))
	local classID, specID = MythicLoot.GetLootSpec()
	p("loot spec — classID:", classID, " specID:", specID)
	StartWatching()
	p("subcommands:  /ml voidcheck bag  •  /ml voidcheck <itemID>")
end
