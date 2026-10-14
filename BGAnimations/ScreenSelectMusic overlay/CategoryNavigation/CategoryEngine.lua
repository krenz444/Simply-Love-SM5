-- CategoryEngine.lua
-- In-memory category indexing and multi-facet filtering for Simply Love / ITGmania Keyboard Mode.
--
-- Returned song lists are shared with the search index and MUST be treated as read-only.

local SongSearchEngine = LoadActor("../KeyboardOmnibar/SongSearchEngine.lua")

local CategoryEngine = {}

-- -------------------------------------------------------------
-- 1. Category Definitions (order = tab order; every entry is reachable from the ribbon)
-- -------------------------------------------------------------
local categories = {
	{ id = "packs",     name = "PACKS",     desc = "Browse by Song Pack & Series" },
	{ id = "favorites", name = "FAVORITES", desc = "Player Favorites & Recent Songs" },
	{ id = "meters",    name = "METERS",    desc = "Songs that have a chart in a difficulty tier" },
	{ id = "bpm",       name = "BPM",       desc = "Filter by Speed & Energy" },
	{ id = "played",    name = "PLAYED",    desc = "Songs you have played, cleared or not yet tried" },
	{ id = "alphabet",  name = "A-Z",       desc = "Alphabetical Song Catalog" },
}

function CategoryEngine.GetCategories()
	return categories
end

-- Exposed so every consumer shares the single search/index instance.
function CategoryEngine.GetSearchEngine()
	return SongSearchEngine
end

-- -------------------------------------------------------------
-- 2. Sub-Category Definitions
-- -------------------------------------------------------------
-- METERS: a song matches a tier when ANY of its charts (current style, no edits) falls in range.
local meterTiers = {
	{ id = "all",      label = "All Levels",     minM = 1,  maxM = 99 },
	{ id = "warmup",   label = "1-8 Warmup",     minM = 1,  maxM = 8  },
	{ id = "mid",      label = "9-10 Mid",       minM = 9,  maxM = 10 },
	{ id = "upper",    label = "11-12 Upper",    minM = 11, maxM = 12 },
	{ id = "expert",   label = "13-14 Expert",   minM = 13, maxM = 14 },
	{ id = "master",   label = "15-18 Master",   minM = 15, maxM = 18 },
	{ id = "elite",    label = "19+ Stamina",    minM = 19, maxM = 99 },
}

-- BPM tiers are half-open [minB, maxB) on the song's MAX display BPM, so the tiers partition
-- the library: no BPM (including fractional ones like 129.5) falls between two tiers and
-- a boundary BPM (155, 180, 210) belongs to exactly one tier.
local bpmTiers = {
	{ id = "all",       label = "All BPM",       minB = 0,   maxB = math.huge },
	{ id = "chill",     label = "< 130 Chill",   minB = 0,   maxB = 130 },
	{ id = "standard",  label = "130-155 Groov", minB = 130, maxB = 155 },
	{ id = "energy",    label = "155-180 Ener",  minB = 155, maxB = 180 },
	{ id = "fast",      label = "180-210 Fast",  minB = 180, maxB = 210 },
	{ id = "speed",     label = "210+ Speed",    minB = 210, maxB = math.huge },
}

-- A-Z: every song falls in exactly one bucket. The key is the transliterated title (what
-- StepMania itself sorts by), so a title in kanji or kana lands under its Latin reading; a title
-- with no Latin letter or digit at all goes to "#".
local alphabetBuckets = {
	{ id = "num", label = "# 0-9",  letters = "" },
	{ id = "ac",  label = "A - C",  letters = "abc" },
	{ id = "df",  label = "D - F",  letters = "def" },
	{ id = "gi",  label = "G - I",  letters = "ghi" },
	{ id = "jl",  label = "J - L",  letters = "jkl" },
	{ id = "mo",  label = "M - O",  letters = "mno" },
	{ id = "pr",  label = "P - R",  letters = "pqr" },
	{ id = "su",  label = "S - U",  letters = "stu" },
	{ id = "vz",  label = "V - Z",  letters = "vwxyz" },
}

local letterToBucket = {}
for _, b in ipairs(alphabetBuckets) do
	for i = 1, #b.letters do
		letterToBucket[b.letters:sub(i, i)] = b.id
	end
end

-- Bucket id for an index entry (cached on the entry: entries are built once per library).
local function AlphabetBucketId(entry)
	local cached = entry._azBucket
	if cached then return cached end
	local key = entry.translit_title
	if not key or key == "" then key = entry.title or "" end
	-- first ASCII letter/digit, skipping leading symbols and any non-ASCII bytes
	local c = key:match("^[^%w]*(%w)")
	local id = "num"
	if c and not c:match("%d") then
		id = letterToBucket[c:lower()] or "num"
	end
	entry._azBucket = id
	return id
end

function CategoryEngine.GetSubChips(categoryId)
	if categoryId == "meters" then
		return meterTiers
	elseif categoryId == "bpm" then
		return bpmTiers
	elseif categoryId == "alphabet" then
		return alphabetBuckets
	elseif categoryId == "favorites" then
		return {
			{ id = "all_fav",  label = "All Favorites" },
			{ id = "p1_fav",   label = "P1 Favorites" },
			{ id = "p2_fav",   label = "P2 Favorites" },
			{ id = "recents",  label = "Recent Songs" },
		}
	elseif categoryId == "packs" then
		local groups = SONGMAN:GetSongGroupNames() or {}
		local chips = { { id = "all", label = "All Packs (" .. tostring(#groups) .. ")" } }
		for i, gName in ipairs(groups) do
			chips[#chips + 1] = { id = gName, label = gName }
		end
		return chips
	elseif categoryId == "played" then
		return {
			{ id = "all",      label = "All Played" },
			{ id = "unplayed", label = "Unplayed" },
			{ id = "cleared",  label = "Cleared" },
		}
	end
	return { { id = "all", label = "All" } }
end

-- Meter range of the active METERS tier (nil for every other category / "All Levels").
-- The song wheel uses it to show the meter of the chart that actually matched.
function CategoryEngine.GetMeterRange(categoryId, subChipId)
	if categoryId ~= "meters" then return nil end
	for _, t in ipairs(meterTiers) do
		if t.id == subChipId and t.id ~= "all" then return t.minM, t.maxM end
	end
	return nil
end

function CategoryEngine.GetEmptyHint(categoryId, subChipId)
	if categoryId == "favorites" and subChipId == "recents" then
		return "No recent songs yet.\nSongs you start or search for appear here."
	elseif categoryId == "favorites" then
		return "You haven't added any favorites yet.\nPress [ Ctrl + D ] to favorite any song!"
	elseif categoryId == "played" and subChipId ~= "unplayed" then
		return "No scores recorded yet.\nFinish a song and it will show up here."
	end
	return "No songs match this category filter.\nPress [ Left / Right ] or [ Tab ] to browse other categories."
end

-- -------------------------------------------------------------
-- 3. PLAYED status (from the engine's per-profile high score lists)
-- -------------------------------------------------------------
-- status[song_dir] = 0 never played, 1 played, 2 cleared (some score that is not a fail)
local playStatus = nil

function CategoryEngine.InvalidatePlayCache()
	playStatus = nil
end

local function ProfilesToCheck()
	local list = {}
	for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
		if PROFILEMAN:IsPersistentProfile(pn) then
			list[#list + 1] = PROFILEMAN:GetProfile(pn)
		end
	end
	if #list == 0 then list[1] = PROFILEMAN:GetMachineProfile() end
	return list
end

-- NOTE: Profile:GetHighScoreList() and HasPassedAnyStepsInSong() INSERT an empty score entry for
-- every (song, chart) they are asked about (std::map operator[]). With a whole library that
-- pollutes the profile in memory, so only the read-only queries are used here:
--   GetSongNumTimesPlayed(song)               -> never inserts
--   GetHighScoreListIfExists(song, steps)     -> nil when the chart has no entry
local function BuildPlayStatus(allEntries)
	local status = {}
	local style = GAMESTATE:GetCurrentStyle()
	local stepsType = style and style:GetStepsType() or nil
	local profiles = ProfilesToCheck()

	for _, e in ipairs(allEntries) do
		local level = 0
		local song = e.song
		if song then
			for _, prof in ipairs(profiles) do
				if prof and prof:GetSongNumTimesPlayed(song) > 0 then
					level = 1
					break
				end
			end
			if level == 1 and stepsType then
				-- played: cleared if any recorded score on any chart is not a fail
				for steps in ivalues(song:GetStepsByStepsType(stepsType)) do
					for _, prof in ipairs(profiles) do
						local list = prof and prof:GetHighScoreListIfExists(song, steps)
						if list then
							for hs in ivalues(list:GetHighScores()) do
								if hs:GetGrade() ~= "Grade_Failed" then level = 2 break end
							end
						end
						if level == 2 then break end
					end
					if level == 2 then break end
				end
			end
		end
		status[e.song_dir] = level
	end
	return status
end

local function GetPlayStatus(allEntries)
	if not playStatus then
		local ok, res = pcall(BuildPlayStatus, allEntries)
		if ok then
			playStatus = res
		else
			Warn("CategoryEngine: could not read high scores: " .. tostring(res))
			playStatus = {}
		end
	end
	return playStatus
end

-- -------------------------------------------------------------
-- 4. Favorites: same source as the gold badge (SL[pn].Favorites, a list of Song objects)
-- -------------------------------------------------------------
local function FavoriteDirSet(playerNumbers)
	local set = {}
	for _, pn in ipairs(playerNumbers) do
		local slp = SL[ToEnumShortString(pn)]
		if slp and slp.Favorites and GAMESTATE:IsPlayerEnabled(pn) then
			for song in ivalues(slp.Favorites) do
				local dir = song.GetSongDir and song:GetSongDir()
				if dir then set[dir] = true end
			end
		end
	end
	return set
end

-- -------------------------------------------------------------
-- 5. Query & Filter Implementation
-- -------------------------------------------------------------
function CategoryEngine.GetSongs(categoryId, subChipId)
	local allEntries = SongSearchEngine.GetIndex()
	if not allEntries or #allEntries == 0 then return {} end

	subChipId = subChipId or "all"
	local results = {}

	if categoryId == "packs" then
		if subChipId == "all" then return allEntries end
		for _, entry in ipairs(allEntries) do
			if entry.group == subChipId then results[#results + 1] = entry end
		end

	elseif categoryId == "meters" then
		local minM, maxM = CategoryEngine.GetMeterRange("meters", subChipId)
		if not minM then return allEntries end
		for _, entry in ipairs(allEntries) do
			for _, m in ipairs(entry.meterList or {}) do
				if m >= minM and m <= maxM then
					results[#results + 1] = entry
					break
				end
			end
		end

	elseif categoryId == "bpm" then
		local tier
		for _, t in ipairs(bpmTiers) do if t.id == subChipId then tier = t break end end
		if not tier or tier.id == "all" then return allEntries end
		for _, entry in ipairs(allEntries) do
			local maxBpm = entry.bpms and entry.bpms[2] or 0
			if maxBpm >= tier.minB and maxBpm < tier.maxB then
				results[#results + 1] = entry
			end
		end

	elseif categoryId == "alphabet" then
		local bucket
		for _, b in ipairs(alphabetBuckets) do if b.id == subChipId then bucket = b break end end
		if not bucket then return allEntries end
		for _, entry in ipairs(allEntries) do
			if AlphabetBucketId(entry) == bucket.id then results[#results + 1] = entry end
		end

	elseif categoryId == "favorites" then
		if subChipId == "recents" then
			local recentMap = {}
			for idx, dir in ipairs(SongSearchEngine.GetRecentSongDirs() or {}) do recentMap[dir] = idx end
			for _, entry in ipairs(allEntries) do
				if recentMap[entry.song_dir] then results[#results + 1] = entry end
			end
			table.sort(results, function(a, b)
				return (recentMap[a.song_dir] or 999) < (recentMap[b.song_dir] or 999)
			end)
			return results
		end

		local who
		if subChipId == "p1_fav" then who = { PLAYER_1 }
		elseif subChipId == "p2_fav" then who = { PLAYER_2 }
		else who = { PLAYER_1, PLAYER_2 } end
		local favDirs = FavoriteDirSet(who)
		for _, entry in ipairs(allEntries) do
			if favDirs[entry.song_dir] then results[#results + 1] = entry end
		end

	elseif categoryId == "played" then
		local status = GetPlayStatus(allEntries)
		for _, entry in ipairs(allEntries) do
			local level = status[entry.song_dir] or 0
			if subChipId == "unplayed" then
				if level == 0 then results[#results + 1] = entry end
			elseif subChipId == "cleared" then
				if level == 2 then results[#results + 1] = entry end
			elseif level >= 1 then
				results[#results + 1] = entry
			end
		end

	else
		results = allEntries
	end

	return results
end

return CategoryEngine
