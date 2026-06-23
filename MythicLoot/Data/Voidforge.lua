local ADDON_NAME, MythicLoot = ...

-- Voidforge auto-detect (ADR 0008). The game reuses the classic bonus-roll
-- frame/events for Voidforge, and we track Claims two complementary ways:
--
-- 1. EVENT (the win): BONUS_ROLL_STARTED (popup opens) -> BONUS_ROLL_RESULT (the
--    win). Everything a Claim needs rides on the won item itself, which keeps this
--    path robust and free of list-text parsing (the only localized read is the
--    won item's own trackString, validated against the English Track ladder):
--      * itemID + link -> the BONUS_ROLL_RESULT reward (arg 2 is the hyperlink)
--      * Track ("Myth") -> read from the won item's own upgrade info
--      * dungeon        -> the active M+ map captured when the popup opened, with a
--                          fallback finding which rotation dungeon drops the item
--
-- 2. SNAPSHOT (retroactive reconcile): when the player mouses over the roll popup,
--    its reward tooltip lists the dungeon's REMAINING pool — won items are removed
--    from the list (verified in-game), so `claimed = (loot-spec pool) - (listed)`.
--    We read it to back-fill wins we missed and clear any stale marks at once.
--    Text-scraped, so English-only and defensive. The event path is authoritative
--    for new wins; the snapshot reconciles the rest.
--
-- Verified in-game (2026-06-17, Maisara Caverns):
--   BONUS_ROLL_RESULT -> "item", "[Traitor's Talon]"(link), 1, 104(specID), 3, ...
--   The won item was awarded at the Myth track shown on the roll popup, whose
--   tooltip listed the six remaining items under "Contains one of the following:".

local pendingMapID -- the active challenge map captured at BONUS_ROLL_STARTED

local function p(...)
	print("|cff8000ffMythicLoot|r:", ...)
end

local function ActiveChallengeMap()
	return C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
		and C_ChallengeMode.GetActiveChallengeMapID()
end

-- Is this challengeMapID one of our season-rotation dungeons?
local function InRotation(mapID)
	if not mapID then return false end
	local rot = MythicLoot.Journal and MythicLoot.Journal:GetRotation()
	if not rot then return false end
	for _, d in ipairs(rot) do
		if d.challengeMapID == mapID then return true end
	end
	return false
end

-- Fallback when the active map is gone (player already left the instance): find
-- the rotation dungeon whose loot table (for this loot spec) lists the won item.
-- Voidforge loot is dungeon-specific, so this resolves to exactly one in practice.
local function DungeonByItem(itemID, classID, specID)
	local data = MythicLoot.Journal and MythicLoot.Journal:GetDungeonData(classID, specID)
	if not data then return nil end
	for _, d in ipairs(data) do
		if d.loot and d.loot.items then
			for _, it in ipairs(d.loot.items) do
				if it.itemID == itemID then
					return d.info and d.info.challengeMapID
				end
			end
		end
	end
	return nil
end

local function DungeonName(mapID)
	local rot = MythicLoot.Journal and MythicLoot.Journal:GetRotation()
	if rot then
		for _, d in ipairs(rot) do
			if d.challengeMapID == mapID then return d.name end
		end
	end
	return "dungeon " .. tostring(mapID)
end

-- Record one win. The won item's data can lag the event by a moment, so the Track
-- read (off the item's upgrade info) may miss on the first try — retry a few times
-- before giving up rather than silently dropping the Claim. mapAtRoll is captured
-- at the event because pendingMapID is cleared right after.
local function TryRecord(rewardLink, itemID, classID, specID, mapAtRoll, attempt)
	local track = MythicLoot.GetItemTrackName(rewardLink)
	if not track then
		if attempt < 5 then
			C_Timer.After(0.5, function()
				TryRecord(rewardLink, itemID, classID, specID, mapAtRoll, attempt + 1)
			end)
		end
		-- Out of retries: no track means we can't place it in a Voidcore pool; the
		-- player can still mark it by hand. Stay quiet rather than guess.
		return
	end

	local mapID = mapAtRoll
	if not InRotation(mapID) then
		mapID = DungeonByItem(itemID, classID, specID)
	end
	if not mapID then return end -- can't place it; manual marking still covers it

	-- Key the Claim on the item's OWN Track (what it was won at), not the grid's
	-- viewing Track. They coincide in the normal case — you view the Voidcore Track
	-- you roll at — but if they differ, the grid surfaces the win only when its
	-- Voidcore Track matches, which is correct: removal is per-Track. The chat line
	-- names the Track so the player knows which view shows it.
	MythicLoot.MarkClaim(mapID, track, itemID)
	p("Voidforge win recorded — " .. rewardLink .. " at " .. track
		.. " in " .. DungeonName(mapID) .. ". It's now marked as claimed.")
end

local function OnRollResult(rewardType, rewardLink, quantity, specID)
	-- Only item rewards are Claims; gold/currency rolls (if any) aren't.
	if rewardType ~= "item" or not rewardLink then return end

	local itemID = tonumber(rewardLink:match("item:(%d+)"))
	if not itemID then return end

	-- The event tells us which spec the roll was for; pair it with the player's
	-- class (constant). Fall back to the live loot spec if the event omitted it.
	local classID = select(3, UnitClass("player"))
	if not (specID and specID > 0) then
		specID = select(2, MythicLoot.GetLootSpec())
	end

	TryRecord(rewardLink, itemID, classID, specID, pendingMapID, 1)
end

-- ===== Retroactive reconciliation from the roll-popup tooltip (ADR 0008) =====
--
-- When the roll popup is up and the player mouses over its reward (which they do
-- to read it), the tooltip lists the dungeon's REMAINING pool under "Contains one
-- of the following items:" — items already won are removed from the list (verified
-- in-game), not dimmed. So for that dungeon+Track:
--   claimed = (loot-spec pool) − (items still listed)
-- We mark the absent items claimed (back-filling wins the event path missed) and
-- clear any stale marks on the still-listed items, in one pass (proof > assertion).
-- Text-scraped, so English-only and defensive: if the format ever changes the read
-- simply no-ops and the event path + manual marking still work.

local reconciling = false

local function MapIDByName(name)
	if not name then return nil end
	local rot = MythicLoot.Journal and MythicLoot.Journal:GetRotation()
	if rot then
		for _, d in ipairs(rot) do
			if d.name == name then return d.challengeMapID end
		end
	end
	return nil
end

-- The dungeon's loot-spec pool as {itemID, name} rows (the Voidforge pool source).
local function PoolItems(mapID, classID, specID)
	local data = MythicLoot.Journal and MythicLoot.Journal:GetDungeonData(classID, specID)
	if not data then return nil end
	for _, d in ipairs(data) do
		if d.info and d.info.challengeMapID == mapID and d.loot and d.loot.items then
			return d.loot.items
		end
	end
	return nil
end

-- Read the live reward tooltip: dungeon name, Track, and the set of names still
-- listed (i.e. still rollable). Returns nil until the list has populated (it lags
-- the tooltip's first show by a tick).
local function ScrapeBonusRollTooltip()
	local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
	if not (first and first:find("Nebulous Voidcache:", 1, true)) then return nil end
	local dungeonName = first:match("Nebulous Voidcache:%s*(.-)%s*$")
	local track, listing, hasList = nil, false, false
	local listed = {}
	for i = 1, GameTooltip:NumLines() do
		local text = _G["GameTooltipTextLeft" .. i] and _G["GameTooltipTextLeft" .. i]:GetText()
		if text then
			if text:find("Upgrade Level:", 1, true) then
				track = text:match("Upgrade Level:%s*(%a+)")
			elseif text:find("Contains one of the following items:", 1, true) then
				listing, hasList = true, true
			elseif listing then
				local name = text:match("^[%s%-]*(.-)%s*$") -- strip leading "- " + spaces
				if name and name ~= "" then listed[name] = true end
			end
		end
	end
	-- Require the header AND at least one item: the list populates a tick after the
	-- header line appears, and acting on an empty list would read as "everything
	-- won" and wrongly claim the whole pool. Treat empty as not-ready (keep
	-- retrying); the event path covers the rare genuinely-exhausted case anyway.
	if not (hasList and next(listed)) then return nil end
	return dungeonName, track, listed
end

-- Reconcile Claims from the current tooltip. Returns true once it found a usable
-- list (so the caller stops retrying), false while the list is still populating.
local function ReconcileFromTooltip()
	if reconciling then return true end
	local dungeonName, track, listed = ScrapeBonusRollTooltip()
	if not listed then return false end -- list not up yet

	-- The Track line can lag the list by a tick: a missing Track is "not ready yet"
	-- (keep retrying), but a present-yet-unrecognised one is permanent (give up).
	if not track then return false end
	if not MythicLoot.IsKnownTrack(track) then return true end

	-- pendingMapID covers the in-dungeon case; the name fallback can miss while the
	-- rotation list is still loading, so treat a miss as not-ready and retry.
	local mapID = (InRotation(pendingMapID) and pendingMapID) or MapIDByName(dungeonName)
	if not mapID then return false end

	local classID, specID = MythicLoot.GetLootSpec()
	local pool = PoolItems(mapID, classID, specID)
	if not pool then
		-- Loot is bundled now (ADR 0009), so it's always available once the rotation
		-- is loaded; a nil pool means this dungeon/spec isn't in the bundle. Nothing
		-- to wait for — give up (return handled) and leave it to manual marking.
		return true
	end

	-- Safety net for the name-based match: every still-listed item must be a known
	-- pool item by name. If one isn't, our names have drifted from the live tooltip
	-- (or the bundle pool differs from Voidforge's) — bail rather than risk marking a
	-- genuinely-remaining item as won. The event path + manual marking still cover it.
	local poolNames = {}
	for _, it in ipairs(pool) do
		if it.name then poolNames[it.name] = true end
	end
	for name in pairs(listed) do
		if not poolNames[name] then return true end
	end

	reconciling = true
	local marked, cleared = 0, 0
	for _, it in ipairs(pool) do
		if it.name and it.itemID then
			if it.slotKey == "Other" then
				-- Voidforge only transmutes equippable gear, so "Other" items (crates,
				-- tokens, etc.) are never rollable — their absence from the list means
				-- "not eligible", NOT "won". Never claim them; clear any stale mark.
				MythicLoot.SetClaim(mapID, track, it.itemID, false)
			elseif listed[it.name] then
				if MythicLoot.SetClaim(mapID, track, it.itemID, false) then cleared = cleared + 1 end
			else
				if MythicLoot.SetClaim(mapID, track, it.itemID, true) then marked = marked + 1 end
			end
		end
	end
	reconciling = false

	if marked > 0 or cleared > 0 then
		MythicLoot.RefreshWindow()
		p("Synced " .. DungeonName(mapID) .. " (" .. track .. ") from the roll — "
			.. marked .. " marked won, " .. cleared .. " unmarked.")
	end
	return true
end

-- The list populates a tick after the tooltip first shows, so retry briefly while
-- the popup stays up.
local function OnTooltipShow()
	if not (BonusRollFrame and BonusRollFrame:IsShown()) then return end
	local function attempt(n)
		if not (BonusRollFrame and BonusRollFrame:IsShown()) then return end
		if ReconcileFromTooltip() then return end
		-- Retry while the popup's up — the tooltip's Track/list (and the rotation
		-- list) can populate a tick after it first shows.
		if n < 8 then C_Timer.After(0.25, function() attempt(n + 1) end) end
	end
	attempt(1)
end

GameTooltip:HookScript("OnShow", OnTooltipShow)

-- The dungeon the roll is for. Prefer the instance the player is standing in (the
-- one they just cleared and are rolling in) by name — reliable in any dungeon,
-- keystone or not — then the active keystone map id.
local function CurrentDungeonMapID()
	local name = GetInstanceInfo and GetInstanceInfo()
	local byName = name and MapIDByName(name)
	if byName then return byName end
	local cm = ActiveChallengeMap()
	if InRotation(cm) then return cm end
	return nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("BONUS_ROLL_STARTED")
f:RegisterEvent("BONUS_ROLL_RESULT")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "BONUS_ROLL_STARTED" then
		-- Capture the dungeon now, while we're still in/just-finished the instance;
		-- by the time the result fires the player may have started to leave. (Loot is
		-- bundled now, so there's nothing to pre-warm — it's always available.)
		pendingMapID = CurrentDungeonMapID()
	elseif event == "BONUS_ROLL_RESULT" then
		OnRollResult(...)
		pendingMapID = nil
	end
end)
