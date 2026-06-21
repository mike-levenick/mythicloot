local ADDON_NAME, MythicLoot = ...

-- Loot-data exporter (ADR 0009). Walks the Encounter Journal reader we already
-- have across every class/spec × every rotation dungeon and dumps the result into
-- a SavedVariable, which WoW serialises to disk as a ready-made Lua table. That
-- file is then hand-copied into the shipped Data/SeasonLoot.lua so the addon can
-- read loot from the bundle instead of the live EJ.
--
-- This is the only thing that reads the EJ at runtime; it is a maintenance tool,
-- run once per season/patch. The harvest is clean-room: the data comes from
-- Blizzard's Encounter Journal via our own reader, never another addon (ADR 0001).
--
-- MUST be run OUTSIDE a dungeon — the EJ freezes to the current instance while
-- you're inside one (see Journal.lua / ADR 0009), so in-instance reads are wrong.

local function p(...)
	print("|cff33ff66MythicLoot export|r:", ...)
end

-- Every (classID, specID) in the game, in a stable order.
local function AllSpecs()
	local jobs = {}
	for classID = 1, GetNumClasses() do
		local n = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
		for i = 1, n do
			local specID = GetSpecializationInfoForClassID(classID, i)
			if specID then table.insert(jobs, { classID = classID, specID = specID }) end
		end
	end
	return jobs
end

-- Trim a loaded spec's loot to the shipped shape: per dungeon, a list of
-- {id, slot, name, icon} — enough to render a cell offline (tooltip via
-- SetItemByID, chat link resolved lazily), nothing player- or session-specific.
local function HarvestSpec(classID, specID)
	local data = MythicLoot.Journal:GetDungeonData(classID, specID)
	local byMap = {}
	for _, d in ipairs(data) do
		if d.loot and d.loot.items and d.info and d.info.challengeMapID then
			local items = {}
			for _, it in ipairs(d.loot.items) do
				if it.itemID and it.slotKey then
					table.insert(items, {
						id = it.itemID,
						slot = it.slotKey,
						name = it.name,
						icon = it.icon,
					})
				end
			end
			byMap[d.info.challengeMapID] = items
		end
	end
	return byMap
end

local running = false

local function Run()
	if running then p("already running…"); return end
	if IsInInstance() then
		p("|cffff4444Run this OUTSIDE a dungeon|r — the Encounter Journal freezes to "
			.. "the instance you're in, so the reads would be wrong.")
		return
	end
	if not MythicLoot.Journal:GetRotation() then
		p("season rotation not loaded yet — try again in a few seconds.")
		return
	end

	running = true
	local jobs = AllSpecs()
	local out = {}
	p("harvesting " .. #jobs .. " specs across the rotation — this takes a minute, "
		.. "leave the game alone…")

	local function step(n)
		if n > #jobs then
			MythicLootGlobalDB.seasonLoot = out
			MythicLootGlobalDB.seasonLootStamp = {
				toc = select(4, GetBuildInfo()),
				season = C_MythicPlus and C_MythicPlus.GetCurrentSeason
					and C_MythicPlus.GetCurrentSeason() or 0,
			}
			running = false
			p("|cff33ff66done|r — " .. #jobs .. " specs harvested.")
			p("Now: /reload (or log out), then copy MythicLootGlobalDB.seasonLoot from "
				.. "your SavedVariables/MythicLoot.lua and send it over.")
			return
		end
		local job = jobs[n]
		MythicLoot.Journal:RequestLoot(job.classID, job.specID)
		local function wait(tries)
			if MythicLoot.Journal:IsSpecComplete(job.classID, job.specID) then
				out[job.classID] = out[job.classID] or {}
				out[job.classID][job.specID] = HarvestSpec(job.classID, job.specID)
				if n % 5 == 0 or n == #jobs then p("  " .. n .. "/" .. #jobs .. "…") end
				step(n + 1)
			elseif tries > 60 then
				-- ~18s with nothing: skip this spec rather than wedge the whole run.
				p("  spec " .. job.classID .. "/" .. job.specID .. " timed out, skipping.")
				step(n + 1)
			else
				C_Timer.After(0.3, function() wait(tries + 1) end)
			end
		end
		wait(0)
	end
	step(1)
end

MythicLoot.ExportLoot = Run
