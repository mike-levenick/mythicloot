local ADDON_NAME, MythicLoot = ...

-- Loads the Season Rotation and per-spec loot from the game's Encounter
-- Journal at runtime (ADR 0002). All reads are async-tolerant: loot info
-- arrives over EJ_LOOT_DATA_RECIEVED (Blizzard's spelling) and we re-read
-- until every item resolves, then cache for the session.

local Journal = CreateFrame("Frame")
MythicLoot.Journal = Journal

local MYTHIC_DUNGEON_DIFFICULTY = 23
local MAX_RETRIES_PER_DUNGEON = 25
local RETRY_INTERVAL = 0.3

local rotation       -- array of {challengeMapID, name, icon, journalInstanceID, tier}
local instanceByName -- EJ dungeon name -> journalInstanceID, all expansions
local instanceTier   -- journalInstanceID -> EJ tier index it lives in
local cache = {}     -- "classID-specID" -> {byMap = {challengeMapID -> {items, slotSet}}, complete, loading}
local request        -- in-flight load: {key, entry, classID, specID, index, retries}
local pendingSpec    -- spec request parked while waiting for CHALLENGE_MODE_MAPS_UPDATE

-- The UI registers a single callback; fired after each dungeon finishes loading.
function Journal:SetCallback(callback)
	self.callback = callback
end

local function Notify()
	if Journal.callback then Journal.callback() end
end

local function SpecKey(classID, specID)
	return classID .. "-" .. (specID or 0)
end

-- Persistent loot cache (ADR 0007). The EJ is still read at runtime as ever, but
-- the resulting table is stored account-wide so a reopen paints instantly instead
-- of watching it load. Each spec's table is stamped with the content patch +
-- current M+ season; a mismatch (or no global DB yet) just means a cold read. The
-- EJ stays the source of truth — every open re-reads in the background and
-- overwrites, so a stale stamp self-heals within the session.
local function PersistentCache()
	MythicLootGlobalDB = MythicLootGlobalDB or {}
	MythicLootGlobalDB.lootCache = MythicLootGlobalDB.lootCache or {}
	return MythicLootGlobalDB.lootCache
end

local function CacheStamp()
	local tocVersion = select(4, GetBuildInfo())
	local season = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
	return tostring(tocVersion) .. ":" .. tostring(season or 0)
end

-- The Season Rotation spans expansions, so index dungeons from every EJ tier once.
local function BuildInstanceIndex()
	if instanceByName then return end
	instanceByName = {}
	instanceTier = {}
	for tier = 1, EJ_GetNumTiers() do
		EJ_SelectTier(tier)
		local index = 1
		while true do
			local instanceID, name = EJ_GetInstanceByIndex(index, false)
			if not instanceID then break end
			instanceByName[name] = instanceID
			instanceTier[instanceID] = tier
			index = index + 1
		end
	end
end

-- Challenge-map names normally equal EJ instance names; fall back to a
-- containment match for cases like megadungeon wings.
local function FindJournalInstance(challengeMapName)
	if instanceByName[challengeMapName] then
		return instanceByName[challengeMapName]
	end
	for name, instanceID in pairs(instanceByName) do
		if name:find(challengeMapName, 1, true) or challengeMapName:find(name, 1, true) then
			return instanceID
		end
	end
end

-- Returns the Season Rotation, or nil if the server hasn't sent the map
-- list yet (a request is issued; CHALLENGE_MODE_MAPS_UPDATE follows).
function Journal:GetRotation()
	if rotation then return rotation end
	local mapIDs = C_ChallengeMode.GetMapTable()
	if not mapIDs or #mapIDs == 0 then
		C_MythicPlus.RequestMapInfo()
		return nil
	end
	BuildInstanceIndex()
	rotation = {}
	for _, mapID in ipairs(mapIDs) do
		local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
		if name then
			local jid = FindJournalInstance(name)
			table.insert(rotation, {
				challengeMapID = mapID,
				name = name,
				icon = texture,
				journalInstanceID = jid,
				tier = jid and instanceTier[jid],
			})
		end
	end
	-- Diagnostic: distinct dungeons must map to distinct journal instances. If
	-- they don't, loot would be identical across rows for a different reason
	-- than the stale-read race; surface it so we know which bug we're chasing.
	local seenInstance = {}
	for _, dungeon in ipairs(rotation) do
		local id = dungeon.journalInstanceID
		if id then
			if seenInstance[id] then
				print("|cffff8000MythicLoot:|r '" .. dungeon.name
					.. "' resolved to the same journal instance as '" .. seenInstance[id]
					.. "' — loot mapping is wrong, please report.")
			else
				seenInstance[id] = dungeon.name
			end
		end
	end

	return rotation
end

local NextDungeon, TryRead -- mutually recursive

-- All re-reads funnel through here so the per-item EJ_LOOT_DATA_RECIEVED
-- spam and the retry timer can never stack parallel read chains.
local function ScheduleRead(delay)
	if not request or request.readScheduled then return end
	request.readScheduled = true
	local thisRequest = request
	C_Timer.After(delay, function()
		if request == thisRequest and request.readScheduled then
			TryRead()
		end
	end)
end

local function ApplyJournalFilters(dungeon)
	-- Select the instance's tier (expansion) first; the rotation spans
	-- expansions and EJ_SelectInstance may not switch loot across tiers otherwise.
	if dungeon.tier then
		EJ_SelectTier(dungeon.tier)
	end
	EJ_SelectInstance(dungeon.journalInstanceID)
	EJ_SetDifficulty(MYTHIC_DUNGEON_DIFFICULTY)
	C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
	EJ_SetLootFilter(request.classID, request.specID or 0)
end

local function FinishRequest()
	request.entry.loading = nil
	request.entry.complete = true
	-- Persist the freshly reconciled table for instant paint next session.
	PersistentCache()[request.key] = { stamp = CacheStamp(), byMap = request.entry.byMap }
	request = nil
	Journal:UnregisterEvent("EJ_LOOT_DATA_RECIEVED")
	Notify()
end

function NextDungeon()
	request.index = request.index + 1
	request.retries = 0
	request.readScheduled = nil
	local dungeon = rotation[request.index]
	if not dungeon then
		FinishRequest()
		return
	end
	if not dungeon.journalInstanceID then
		-- No EJ match (shouldn't happen for standard rotations); show an empty row rather than wedge the queue.
		request.entry.byMap[dungeon.challengeMapID] = { items = {}, slotSet = {}, missing = true }
		Notify()
		NextDungeon()
		return
	end
	TryRead()
end

function TryRead()
	request.readScheduled = nil
	local dungeon = rotation[request.index]
	-- Re-apply selection every read: the player browsing the Blizzard journal
	-- mid-load would otherwise clobber the global EJ selection state.
	ApplyJournalFilters(dungeon)

	local numLoot = EJ_GetNumLoot()
	local complete = numLoot > 0
	local items = {}
	for i = 1, numLoot do
		local info = C_EncounterJournal.GetLootInfoByIndex(i)
		if info and info.itemID then
			if not (info.name and info.icon) then
				complete = false
			end
			table.insert(items, {
				itemID = info.itemID,
				name = info.name,
				icon = info.icon,
				link = info.link,
				slotKey = MythicLoot.GetSlotForFilterType(info.filterType).key,
				slotOrder = MythicLoot.GetSlotForFilterType(info.filterType).order,
			})
		end
	end

	if complete or request.retries >= MAX_RETRIES_PER_DUNGEON then
		table.sort(items, function(a, b)
			if a.slotOrder ~= b.slotOrder then return a.slotOrder < b.slotOrder end
			return (a.name or "") < (b.name or "")
		end)
		local slotSet = {}
		for _, item in ipairs(items) do
			slotSet[item.slotKey] = true
		end
		request.entry.byMap[dungeon.challengeMapID] = { items = items, slotSet = slotSet }
		Notify()
		NextDungeon()
	else
		request.retries = request.retries + 1
		ScheduleRead(RETRY_INTERVAL)
	end
end

-- Live EJ read for one spec. Since the loot table now ships (ADR 0009), this is
-- used ONLY by the exporter (Data/Export.lua) to regenerate the bundle — it's the
-- last code path that touches the Encounter Journal. The normal runtime reads the
-- shipped table via GetDungeonData below.
function Journal:RequestLiveLoot(classID, specID)
	local key = SpecKey(classID, specID)
	local entry = cache[key]
	if entry and (entry.complete or entry.loading) then return end

	if not self:GetRotation() then
		pendingSpec = { classID = classID, specID = specID }
		self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
		return
	end

	-- A spec change mid-load cancels the old request so it can be retried later.
	if request then
		cache[request.key].loading = nil
		request = nil
	end

	if not entry then
		entry = { byMap = {} }
		-- Seed from last session's cache so the grid paints immediately; the read
		-- started below reconciles it. Only when the stamp still matches — otherwise
		-- prune the stale entry and fall back to a cold read.
		local saved = PersistentCache()[key]
		if saved and saved.byMap and saved.stamp == CacheStamp() then
			local seeded = {}
			for mapID, loot in pairs(saved.byMap) do seeded[mapID] = loot end
			entry.byMap = seeded
		elseif saved then
			PersistentCache()[key] = nil
		end
	end
	entry.loading = true
	cache[key] = entry
	request = { key = key, entry = entry, classID = classID, specID = specID, index = 0, retries = 0 }
	self:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
	NextDungeon()
end

-- Whether a spec's loot has finished loading (used by the data exporter to walk
-- specs one at a time). Note: in-instance this flips true immediately on the
-- cache-served entry, so the exporter must run out of a dungeon for real reads.
function Journal:IsSpecComplete(classID, specID)
	local entry = cache[SpecKey(classID, specID)]
	return entry ~= nil and entry.complete == true
end

-- Live (EJ-read) dungeon data, used by the exporter to harvest the bundle.
function Journal:GetLiveDungeonData(classID, specID)
	local rot = self:GetRotation()
	if not rot then return nil end
	local entry = cache[SpecKey(classID, specID)]
	local result = {}
	for _, dungeon in ipairs(rot) do
		table.insert(result, {
			info = dungeon,
			loot = entry and entry.byMap[dungeon.challengeMapID],
		})
	end
	return result
end

-- ===== Shipped loot (ADR 0009) — the normal runtime path =====
-- Read the bundled SeasonLoot table instead of the live EJ: no async, no
-- in-instance freeze, the same data everywhere including mid-dungeon. Built lazily
-- per spec into the shape the UI/Voidforge already expect, then memoised (the
-- bundle is static). A "item:<id>" itemString stands in for the full link — enough
-- for the tooltip, the Stat Tier read (C_Item.GetItemStats), and a chat insert.
local builtBySpec = {}

local function BuildSpec(classID, specID)
	local byMap = {}
	local bySpec = MythicLoot.SeasonLoot and MythicLoot.SeasonLoot[classID]
	local src = bySpec and bySpec[specID]
	if not src then return byMap end
	for mapID, rows in pairs(src) do
		local items, slotSet = {}, {}
		for _, r in ipairs(rows) do
			local slot = MythicLoot.GetSlotByKey(r.slot)
			items[#items + 1] = {
				itemID = r.id,
				name = r.name,
				icon = r.icon,
				link = "item:" .. r.id,
				slotKey = r.slot,
				slotOrder = slot and slot.order,
			}
			slotSet[r.slot] = true
		end
		byMap[mapID] = { items = items, slotSet = slotSet }
	end
	return byMap
end

-- Returns an array of {info = rotationEntry, loot = {items, slotSet} | nil}, or
-- nil while the Season Rotation itself is still unknown (the rotation list is the
-- only thing still fetched at runtime, via GetRotation).
function Journal:GetDungeonData(classID, specID)
	local rot = self:GetRotation()
	if not rot then return nil end
	local key = SpecKey(classID, specID)
	local byMap = builtBySpec[key]
	if not byMap then
		byMap = BuildSpec(classID, specID)
		builtBySpec[key] = byMap
	end
	local result = {}
	for _, dungeon in ipairs(rot) do
		table.insert(result, { info = dungeon, loot = byMap[dungeon.challengeMapID] })
	end
	return result
end

-- Loot is bundled, so there is nothing to load at runtime. Kept as a no-op so the
-- existing callers (window open, spec change, Voidforge) need no change.
function Journal:RequestLoot() end

Journal:RegisterEvent("PLAYER_LOGIN")
Journal:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		C_MythicPlus.RequestMapInfo()
	elseif event == "EJ_LOOT_DATA_RECIEVED" then
		-- Fires once per resolved item; debounce into one read.
		ScheduleRead(0.05)
	elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
		self:UnregisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
		if pendingSpec then
			local spec = pendingSpec
			pendingSpec = nil
			self:RequestLiveLoot(spec.classID, spec.specID)
		end
		Notify()
	end
end)
