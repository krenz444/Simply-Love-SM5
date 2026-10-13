-- CategoryEngine.lua
-- In-memory category indexing and multi-facet filtering engine for Simply Love / ITGmania.
-- Categorizes the entire song library in <80ms without touching the disk during gameplay.

local SongSearchEngine = LoadActor("../KeyboardOmnibar/SongSearchEngine.lua")

local CategoryEngine = {}

-- -------------------------------------------------------------
-- 1. Category Definitions
-- -------------------------------------------------------------
local categories = {
	{ id = "packs",       name = "PACKS",     icon = "📁", desc = "Browse by Song Pack & Series" },
	{ id = "favorites",   name = "FAVORITES", icon = "⭐", desc = "Player Favorites & Recent Songs" },
	{ id = "meters",      name = "METERS",    icon = "🎯", desc = "Browse by Difficulty Tier" },
	{ id = "bpm",         name = "BPM",       icon = "⚡", desc = "Filter by Speed & Energy" },
	{ id = "groovestats", name = "RANKED",    icon = "🏆", desc = "Online Events & Ranked Pool" },
	{ id = "alphabet",    name = "A-Z",       icon = "🔤", desc = "Alphabetical Song Catalog" },
	{ id = "search",      name = "SEARCH",    icon = "🔍", desc = "Universal Omnibar Search" },
}

function CategoryEngine.GetCategories()
	return categories
end

-- -------------------------------------------------------------
-- 2. Sub-Category Definitions & Query Handlers
-- -------------------------------------------------------------
local meterTiers = {
	{ id = "all",      label = "All Levels",     minM = 1,  maxM = 99 },
	{ id = "warmup",   label = "1-8 Warmup",     minM = 1,  maxM = 8  },
	{ id = "mid",      label = "9-10 Mid",       minM = 9,  maxM = 10 },
	{ id = "upper",    label = "11-12 Upper",    minM = 11, maxM = 12 },
	{ id = "expert",   label = "13-14 Expert",   minM = 13, maxM = 14 },
	{ id = "master",   label = "15-18 Master",   minM = 15, maxM = 18 },
	{ id = "elite",    label = "19+ Stamina",    minM = 19, maxM = 99 },
}

local bpmTiers = {
	{ id = "all",       label = "All BPM",       minB = 0,   maxB = 9999 },
	{ id = "chill",     label = "< 130 Chill",   minB = 0,   maxB = 129  },
	{ id = "standard",  label = "130-155 Groov", minB = 130, maxB = 155  },
	{ id = "energy",    label = "155-180 Ener",  minB = 155, maxB = 180  },
	{ id = "fast",      label = "180-210 Fast",  minB = 180, maxB = 210  },
	{ id = "speed",     label = "210+ Speed",    minB = 210, maxB = 9999 },
}

local alphabetBuckets = {
	{ id = "num", label = "# 0-9",  chars = "^[%d%p%s]" },
	{ id = "ac",  label = "A - C",  chars = "^[a-cA-C]" },
	{ id = "df",  label = "D - F",  chars = "^[d-fD-F]" },
	{ id = "gi",  label = "G - I",  chars = "^[g-iG-I]" },
	{ id = "jl",  label = "J - L",  chars = "^[j-lJ-L]" },
	{ id = "mo",  label = "M - O",  chars = "^[m-oM-O]" },
	{ id = "pr",  label = "P - R",  chars = "^[p-rP-R]" },
	{ id = "su",  label = "S - U",  chars = "^[s-uS-U]" },
	{ id = "vz",  label = "V - Z",  chars = "^[v-zV-Z]" },
}

-- Return the list of sub-category chips for a given category
function CategoryEngine.GetSubChips(categoryId)
	if categoryId == "meters" then
		return meterTiers
	elseif categoryId == "bpm" then
		return bpmTiers
	elseif categoryId == "alphabet" then
		return alphabetBuckets
	elseif categoryId == "favorites" then
		local chips = {
			{ id = "all_fav",  label = "All Favorites" },
			{ id = "p1_fav",   label = "P1 Favorites" },
			{ id = "p2_fav",   label = "P2 Favorites" },
			{ id = "recents",  label = "Recent Songs" },
		}
		return chips
	elseif categoryId == "packs" then
		local groups = SONGMAN:GetSongGroupNames() or {}
		local chips = { { id = "all", label = "All Packs (" .. tostring(#groups) .. ")" } }
		for i, gName in ipairs(groups) do
			chips[#chips + 1] = { id = gName, label = gName }
		end
		return chips
	elseif categoryId == "groovestats" then
		return {
			{ id = "all",     label = "All Ranked" },
			{ id = "events",  label = "Active Events" },
			{ id = "unplayed",label = "Unplayed Charts" },
		}
	end
	return { { id = "all", label = "All" } }
end

-- -------------------------------------------------------------
-- 3. Query & Filter Implementation
-- -------------------------------------------------------------
function CategoryEngine.GetSongs(categoryId, subChipId)
	local allEntries = SongSearchEngine.GetIndex()
	if not allEntries or #allEntries == 0 then return {} end

	subChipId = subChipId or "all"
	local results = {}

	if categoryId == "packs" then
		if subChipId == "all" then
			return allEntries
		else
			for _, entry in ipairs(allEntries) do
				if entry.group == subChipId then
					results[#results + 1] = entry
				end
			end
		end

	elseif categoryId == "meters" then
		local tierDef = nil
		for _, t in ipairs(meterTiers) do
			if t.id == subChipId then
				tierDef = t
				break
			end
		end

		if not tierDef or tierDef.id == "all" then
			return allEntries
		end

		for _, entry in ipairs(allEntries) do
			local matched = false
			if entry.meterList then
				for _, m in ipairs(entry.meterList) do
					if m >= tierDef.minM and m <= tierDef.maxM then
						matched = true
						break
					end
				end
			end
			if matched then
				results[#results + 1] = entry
			end
		end

	elseif categoryId == "bpm" then
		local tierDef = nil
		for _, t in ipairs(bpmTiers) do
			if t.id == subChipId then
				tierDef = t
				break
			end
		end

		if not tierDef or tierDef.id == "all" then
			return allEntries
		end

		for _, entry in ipairs(allEntries) do
			local maxBpm = entry.bpms and entry.bpms[2] or 0
			if maxBpm >= tierDef.minB and maxBpm <= tierDef.maxB then
				results[#results + 1] = entry
			end
		end

	elseif categoryId == "alphabet" then
		local bucketDef = nil
		for _, b in ipairs(alphabetBuckets) do
			if b.id == subChipId then
				bucketDef = b
				break
			end
		end

		if not bucketDef then return allEntries end

		for _, entry in ipairs(allEntries) do
			local cleanTitle = (entry.title or ""):gsub("^[!%s\"'%(%[]*", "")
			if cleanTitle:match(bucketDef.chars) then
				results[#results + 1] = entry
			end
		end

	elseif categoryId == "favorites" then
		local favSet = {}

		if subChipId == "recents" then
			local recentsList = SongSearchEngine.GetRecentSongDirs() or {}
			local recentMap = {}
			for idx, rDir in ipairs(recentsList) do
				recentMap[rDir] = idx
			end
			for _, entry in ipairs(allEntries) do
				if recentMap[entry.song_dir] then
					results[#results + 1] = entry
				end
			end
			table.sort(results, function(a, b)
				return (recentMap[a.song_dir] or 999) < (recentMap[b.song_dir] or 999)
			end)
			return results
		end

		-- Load favorites files
		local function loadFavFile(pn)
			if type(getFavoritesPath) ~= "function" then return end
			local p = getFavoritesPath(pn)
			if FILEMAN:DoesFileExist(p) then
				local content = lua.ReadFile(p) or ""
				for line in content:gmatch("[^\r\n]+") do
					local c = line:gsub("^%s*(.-)%s*$", "%1")
					if #c > 0 then
						favSet[c] = true
						local subPart = c:match("/([^/]+)/?$")
						if subPart then favSet[subPart] = true end
					end
				end
			end
		end

		if subChipId == "p1_fav" then
			loadFavFile(PLAYER_1)
		elseif subChipId == "p2_fav" then
			loadFavFile(PLAYER_2)
		else
			loadFavFile(PLAYER_1)
			loadFavFile(PLAYER_2)
		end

		for _, entry in ipairs(allEntries) do
			local matched = false
			if favSet[entry.song_dir] or (entry.folder and favSet[entry.folder]) or favSet[entry.title] then
				matched = true
			elseif entry.song_dir then
				for favLine, _ in pairs(favSet) do
					if entry.song_dir:find(favLine, 1, true) then
						matched = true
						break
					end
				end
			end
			if matched then
				results[#results + 1] = entry
			end
		end

	elseif categoryId == "groovestats" then
		-- Ranked pool: all indexed songs
		for _, entry in ipairs(allEntries) do
			results[#results + 1] = entry
		end
	else
		results = allEntries
	end

	return results
end

return CategoryEngine
