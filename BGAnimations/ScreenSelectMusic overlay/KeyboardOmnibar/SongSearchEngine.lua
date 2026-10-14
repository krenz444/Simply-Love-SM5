-- SongSearchEngine.lua
-- High-performance in-memory search and indexing for ITGmania / Simply Love
--
-- This file is LoadActor()'d from several places (Omnibar, CategoryEngine, ...). LoadActor runs
-- the chunk every time, so without the guard below each caller got its own module instance:
-- three copies of the index (and of the recents/history caches), each rebuilt on every
-- ScreenSelectMusic entry. The first instance is kept on SL.Global and shared from then on.
if SL and SL.Global and SL.Global.SongSearchEngineShared then
	return SL.Global.SongSearchEngineShared
end

local SongSearchEngine = {}
if SL and SL.Global then SL.Global.SongSearchEngineShared = SongSearchEngine end

local currentStyleCached = nil
local cachedSongCount = -1
local indexData = {}
local songDirMap = {}

local historyFile = "Save/KeyboardSearchHistory.txt"
local recentsFile = "Save/KeyboardRecentSongs.txt"
local searchHistory = nil
local recentSongDirs = nil

local function LoadHistory()
	if searchHistory then return searchHistory end
	searchHistory = {}
	if FILEMAN:DoesFileExist(historyFile) then
		local text = lua.ReadFile(historyFile) or ""
		for line in text:gmatch("[^\r\n]+") do
			local clean = line:gsub("^%s*(.-)%s*$", "%1")
			if #clean > 0 and #searchHistory < 20 then
				table.insert(searchHistory, clean)
			end
		end
	end
	return searchHistory
end

local function SaveHistory()
	if not searchHistory then return end
	local file = RageFileUtil.CreateRageFile()
	if file:Open(historyFile, 2) then
		local str = table.concat(searchHistory, "\n") .. "\n"
		file:Write(str)
		file:Close()
		file:destroy()
	end
end

local function LoadRecents()
	if recentSongDirs then return recentSongDirs end
	recentSongDirs = {}
	if FILEMAN:DoesFileExist(recentsFile) then
		local text = lua.ReadFile(recentsFile) or ""
		for line in text:gmatch("[^\r\n]+") do
			local clean = line:gsub("^%s*(.-)%s*$", "%1")
			if #clean > 0 and #recentSongDirs < 20 then
				table.insert(recentSongDirs, clean)
			end
		end
	end
	return recentSongDirs
end

local function SaveRecents()
	if not recentSongDirs then return end
	local file = RageFileUtil.CreateRageFile()
	if file:Open(recentsFile, 2) then
		local str = table.concat(recentSongDirs, "\n") .. "\n"
		file:Write(str)
		file:Close()
		file:destroy()
	end
end

function SongSearchEngine.GetSearchHistory()
	return LoadHistory()
end

function SongSearchEngine.AddSearchHistory(query)
	if not query then return end
	local clean = query:gsub("^%s*(.-)%s*$", "%1")
	if #clean == 0 then return end
	local hist = LoadHistory()
	for i = #hist, 1, -1 do
		if hist[i]:lower() == clean:lower() then
			table.remove(hist, i)
		end
	end
	table.insert(hist, 1, clean)
	while #hist > 20 do
		table.remove(hist)
	end
	SaveHistory()
end

function SongSearchEngine.GetRecentSongDirs()
	return LoadRecents()
end

function SongSearchEngine.AddRecentSong(song)
	if not song or not song.GetSongDir then return end
	local dir = song:GetSongDir()
	if not dir or #dir == 0 then return end
	local recents = LoadRecents()
	for i = #recents, 1, -1 do
		if recents[i] == dir then
			table.remove(recents, i)
		end
	end
	table.insert(recents, 1, dir)
	while #recents > 20 do
		table.remove(recents)
	end
	SaveRecents()
end

-- Helper to safely convert nil to empty string
local function safeLower(s)
	if s == nil then return "" end
	return tostring(s):lower()
end

local function trim(s)
	if s == nil then return "" end
	return tostring(s):gsub("^%s*(.-)%s*$", "%1")
end

-- Liveness probes: a few index entries whose Song* the engine resolves back to themselves
-- ("Pack/Song" -> SONGMAN:FindSong). A full "Reload Songs" (SongManager::Reload -> FreeSongs)
-- deletes every Song and builds new ones; when the library size is unchanged the count check
-- alone cannot see that, and the cached entries would point at freed memory. FindSong() is a
-- map lookup and comparing the returned userdata only compares the stored pointers, so the
-- probe never dereferences a possibly dangling Song.
local probes = {}

local function IndexIsLive()
	for _, p in ipairs(probes) do
		if SONGMAN:FindSong(p.key) ~= p.song then
			return false
		end
	end
	return true
end

local function PickProbes()
	probes = {}
	local n = #indexData
	if n == 0 then return end
	local seen = {}
	for _, i in ipairs({ 1, math.ceil(n / 2), n }) do
		local e = indexData[i]
		if e and not seen[i] and e.group and #e.group > 0 and e.folder and #e.folder > 0 then
			seen[i] = true
			local key = e.group .. "/" .. e.folder
			-- Only keep probes that resolve to themselves right now (duplicate pack/folder names
			-- across song folders would otherwise report "stale" forever and thrash the index).
			if SONGMAN:FindSong(key) == e.song then
				probes[#probes + 1] = { key = key, song = e.song }
			end
		end
	end
end

-- Drop the cached index (e.g. after the song library was reloaded with an unchanged count).
function SongSearchEngine.Invalidate()
	cachedSongCount = -1
end

-- Initialize or retrieve the cached song index
function SongSearchEngine.GetIndex()
	local style = GAMESTATE:GetCurrentStyle()
	local stepsType = style and style:GetStepsType() or nil
	local numSongs = SONGMAN:GetNumSongs()

	-- Cached, same library size and style, and the engine still hands out the same Song objects:
	-- nothing to do. (An earlier version called SONGMAN:GetAllSongs(), a 9.5k-element table, on
	-- every keystroke just to compare its length.)
	if cachedSongCount == numSongs and currentStyleCached == stepsType and #indexData > 0
		and IndexIsLive() then
		return indexData
	end

	local buildStart = GetTimeSinceStart()
	local allSongs = SONGMAN:GetAllSongs()
	cachedSongCount = numSongs
	currentStyleCached = stepsType
	indexData = {}
	songDirMap = {}
	probes = {}

	for i = 1, #allSongs do
		local song = allSongs[i]
		if song and (not stepsType or song:HasStepsType(stepsType)) then
			local fullTitle = song:GetDisplayFullTitle() or ""
			local mainTitle = song:GetDisplayMainTitle() or ""
			local subTitle = song:GetDisplaySubTitle() or ""
			local translitTitle = song:GetTranslitFullTitle() or ""
			local translitSubTitle = (song.GetTranslitSubTitle and song:GetTranslitSubTitle()) or ""
			local artist = song:GetDisplayArtist() or ""
			local translitArtist = (song.GetTranslitArtist and song:GetTranslitArtist()) or ""
			local group = song:GetGroupName() or ""
			local genre = (song.GetGenre and song:GetGenre()) or ""
			local sDir = song:GetSongDir() or ""
			local folderName = sDir:match(".*/([^/]+)/?$") or ""

			-- Cache meters for current stepsType
			local meters = {}
			local meterList = {}
			if stepsType then
				local stepsList = song:GetStepsByStepsType(stepsType)
				for steps in ivalues(stepsList) do
					local diff = steps:GetDifficulty()
					if diff ~= "Difficulty_Edit" then
						local m = steps:GetMeter()
						meters[diff] = m
						meterList[#meterList + 1] = m
					end
				end
			end

			-- Collect unique chart authors / stepartists across all steps
			local authors = {}
			local authorSet = {}
			local function addAuthor(name)
				if name and #name > 0 then
					local clean = trim(name)
					local lower = clean:lower()
					if #clean > 0 and not authorSet[lower] then
						authorSet[lower] = true
						authors[#authors + 1] = clean
					end
				end
			end

			if song.GetCredit then
				addAuthor(song:GetCredit())
			end

			local allSteps = (song.GetAllSteps and song:GetAllSteps()) or (stepsType and song:GetStepsByStepsType(stepsType)) or {}
			for steps in ivalues(allSteps) do
				if steps then
					if steps.GetAuthorCredit then addAuthor(steps:GetAuthorCredit()) end
					if steps.GetDescription then addAuthor(steps:GetDescription()) end
					if steps.GetChartName then addAuthor(steps:GetChartName()) end
				end
			end

			local bpms = song:GetDisplayBpms() or {0, 0}
			local authorsDisplay = table.concat(authors, ", ")
			local searchBlob = safeLower(fullTitle .. " " .. translitTitle .. " " .. subTitle .. " " .. artist .. " " .. translitArtist .. " " .. group .. " " .. folderName .. " " .. genre .. " " .. authorsDisplay)

			local entry = {
				song = song,
				song_dir = sDir,
				title = fullTitle,
				title_lower = safeLower(fullTitle),
				main_title = mainTitle,
				main_title_lower = safeLower(mainTitle),
				subtitle = subTitle,
				subtitle_lower = safeLower(subTitle),
				translit_title = translitTitle,
				translit_lower = safeLower(translitTitle),
				translit_subtitle_lower = safeLower(translitSubTitle),
				artist = artist,
				artist_lower = safeLower(artist),
				translit_artist = translitArtist,
				translit_artist_lower = safeLower(translitArtist),
				group = group,
				group_lower = safeLower(group),
				folder = folderName,
				folder_lower = safeLower(folderName),
				genre = genre,
				genre_lower = safeLower(genre),
				authors = authors,
				authors_display = authorsDisplay,
				authors_lower = safeLower(table.concat(authors, " ")),
				search_blob = searchBlob,
				meters = meters,
				meterList = meterList,
				bpms = bpms,
				length = song:MusicLengthSeconds() or 0,
			}
			table.insert(indexData, entry)
			if sDir and #sDir > 0 then
				songDirMap[sDir] = entry
			end
		end
	end

	PickProbes()
	Trace(string.format("SONG_INDEX_BUILD instance=%s songs=%d ms=%.1f probes=%d",
		tostring(SongSearchEngine), #indexData, (GetTimeSinceStart() - buildStart) * 1000, #probes))
	return indexData
end

-- Check if song matches a specific difficulty
local function HasDifficulty(entry, targetMeter)
	for i = 1, #entry.meterList do
		if entry.meterList[i] == targetMeter then
			return true
		end
	end
	return false
end

-- Check if song matches a difficulty range
local function HasDifficultyRange(entry, minMeter, maxMeter)
	for i = 1, #entry.meterList do
		local m = entry.meterList[i]
		if m >= minMeter and m <= maxMeter then
			return true
		end
	end
	return false
end

-- Check if song matches BPM tier
local function MatchesBpm(entry, targetBpm)
	local b = entry.bpms
	if not b or #b == 0 then return false end
	local low = b[1] or 0
	local high = b[2] or low
	return (low - 10 <= targetBpm and targetBpm <= high + 10)
end

-- Search function
function SongSearchEngine.Search(query, maxResults)
	maxResults = maxResults or 100
	local index = SongSearchEngine.GetIndex()

	if not query or query:match("^%s*$") then
		local defaultResults = {}
		local addedDirs = {}

		-- 1. Prepend recently selected songs
		local recents = LoadRecents()
		for _, dir in ipairs(recents) do
			local entry = songDirMap[dir]
			if entry and not addedDirs[dir] then
				addedDirs[dir] = true
				local rEntry = {}
				for k, v in pairs(entry) do rEntry[k] = v end
				rEntry.isRecent = true
				table.insert(defaultResults, rEntry)
			end
		end

		-- 2. Fill remaining slots with standard library index
		for i = 1, #index do
			if #defaultResults >= maxResults then break end
			local entry = index[i]
			if not addedDirs[entry.song_dir] then
				table.insert(defaultResults, entry)
			end
		end
		return defaultResults, #index
	end

	-- Normalize query
	local raw = safeLower(query):gsub("^%s*(.-)%s*$", "%1")

	-- Tokenize supporting quotes and prefix-quotes
	local tokens = {}
	local pos = 1
	local len = #raw
	while pos <= len do
		local spaceEnd = raw:find("%S", pos)
		if not spaceEnd then break end
		pos = spaceEnd

		local preStart, preEnd = raw:find("^[%a_]+:\"", pos)
		if preStart then
			local qEnd = raw:find("\"", preEnd + 1)
			if qEnd then
				tokens[#tokens + 1] = raw:sub(pos, qEnd)
				pos = qEnd + 1
			else
				tokens[#tokens + 1] = raw:sub(pos)
				break
			end
		elseif raw:sub(pos, pos) == "\"" then
			local qEnd = raw:find("\"", pos + 1)
			if qEnd then
				local inner = raw:sub(pos + 1, qEnd - 1)
				if #inner > 0 then
					tokens[#tokens + 1] = inner
				end
				pos = qEnd + 1
			else
				local rest = raw:sub(pos + 1)
				if #rest > 0 then tokens[#tokens + 1] = rest end
				break
			end
		else
			local nextSpace = raw:find("%s", pos)
			if nextSpace then
				tokens[#tokens + 1] = raw:sub(pos, nextSpace - 1)
				pos = nextSpace + 1
			else
				tokens[#tokens + 1] = raw:sub(pos)
				break
			end
		end
	end

	if #tokens == 0 then
		return {}, 0
	end

	local results = {}

	for i = 1, #index do
		local entry = index[i]
		local matchAll = true
		local score = 0

		for t = 1, #tokens do
			local tok = tokens[t]
			local tokMatched = false

			-- 1. Explicit difficulty prefix: d:11, #11, lvl:11, diff:11
			local diffMatch = tok:match("^d:(%d+)$") or tok:match("^#(%d+)$") or tok:match("^lvl:(%d+)$") or tok:match("^diff:(%d+)$")
			if diffMatch then
				local m = tonumber(diffMatch)
				if HasDifficulty(entry, m) then
					tokMatched = true
					score = score + 60
				end
			-- Difficulty range: d:10-12, diff:10-12, or 10-12
			elseif tok:match("^d:(%d+)%-(%d+)$") or tok:match("^diff:(%d+)%-(%d+)$") or tok:match("^(%d+)%-(%d+)$") then
				local lo, hi = tok:match("(%d+)%-(%d+)")
				if lo and hi and HasDifficultyRange(entry, tonumber(lo), tonumber(hi)) then
					tokMatched = true
					score = score + 50
				end
			-- 2. Explicit BPM prefix: b:180, bpm:180
			elseif tok:match("^b:(%d+)$") or tok:match("^bpm:(%d+)$") then
				local b = tonumber(tok:match("(%d+)"))
				if MatchesBpm(entry, b) then
					tokMatched = true
					score = score + 40
				end
			-- 3. Explicit Artist prefix: a:name, artist:name
			elseif tok:match("^a:(.+)$") or tok:match("^artist:(.+)$") then
				local a = tok:match("^a:(.+)$") or tok:match("^artist:(.+)$")
				a = a:gsub('^"', ''):gsub('"$', '')
				if #a > 0 and (entry.artist_lower:find(a, 1, true) or entry.translit_artist_lower:find(a, 1, true)) then
					tokMatched = true
					score = score + 120
					if entry.artist_lower == a then score = score + 40 end
				end
			-- 4. Explicit Pack / Album / Group prefix: p:name, pack:name, album:name, group:name, folder:name
			elseif tok:match("^p:(.+)$") or tok:match("^pack:(.+)$") or tok:match("^album:(.+)$") or tok:match("^group:(.+)$") or tok:match("^folder:(.+)$") then
				local p = tok:match("^p:(.+)$") or tok:match("^pack:(.+)$") or tok:match("^album:(.+)$") or tok:match("^group:(.+)$") or tok:match("^folder:(.+)$")
				p = p:gsub('^"', ''):gsub('"$', '')
				if #p > 0 and (entry.group_lower:find(p, 1, true) or entry.folder_lower:find(p, 1, true)) then
					tokMatched = true
					score = score + 100
				end
			-- 5. Explicit Author / Stepartist / Charter prefix: author:name, charter:name, stepper:name, stepartist:name, c:name
			elseif tok:match("^author:(.+)$") or tok:match("^charter:(.+)$") or tok:match("^stepper:(.+)$") or tok:match("^stepartist:(.+)$") or tok:match("^c:(.+)$") then
				local auth = tok:match("^author:(.+)$") or tok:match("^charter:(.+)$") or tok:match("^stepper:(.+)$") or tok:match("^stepartist:(.+)$") or tok:match("^c:(.+)$")
				auth = auth:gsub('^"', ''):gsub('"$', '')
				if #auth > 0 and entry.authors_lower:find(auth, 1, true) then
					tokMatched = true
					score = score + 110
				end
			-- 6. Explicit Genre prefix: genre:name, gen:name, g:name
			elseif tok:match("^genre:(.+)$") or tok:match("^gen:(.+)$") or tok:match("^g:(.+)$") then
				local g = tok:match("^genre:(.+)$") or tok:match("^gen:(.+)$") or tok:match("^g:(.+)$")
				g = g:gsub('^"', ''):gsub('"$', '')
				if #g > 0 and entry.genre_lower:find(g, 1, true) then
					tokMatched = true
					score = score + 100
				end
			-- 7. Explicit Title prefix: t:name, title:name
			elseif tok:match("^t:(.+)$") or tok:match("^title:(.+)$") then
				local tVal = tok:match("^t:(.+)$") or tok:match("^title:(.+)$")
				tVal = tVal:gsub('^"', ''):gsub('"$', '')
				if #tVal > 0 and (entry.title_lower:find(tVal, 1, true) or entry.translit_lower:find(tVal, 1, true)) then
					tokMatched = true
					score = score + 150
				end
			-- 8. Explicit Subtitle prefix: sub:name, subtitle:name
			elseif tok:match("^sub:(.+)$") or tok:match("^subtitle:(.+)$") then
				local subVal = tok:match("^sub:(.+)$") or tok:match("^subtitle:(.+)$")
				subVal = subVal:gsub('^"', ''):gsub('"$', '')
				if #subVal > 0 and (entry.subtitle_lower:find(subVal, 1, true) or entry.translit_subtitle_lower:find(subVal, 1, true)) then
					tokMatched = true
					score = score + 120
				end
			-- 9. Favorites filter: fav, favorite
			elseif tok == "fav" or tok == "favorite" then
				local isFav = false
				for player in ivalues(GAMESTATE:GetHumanPlayers()) do
					local pStr = ToEnumShortString(player)
					if SL and SL[pStr] and SL[pStr].Favorites and entry.song then
						if FindInTable and FindInTable(entry.song, SL[pStr].Favorites) then
							isFav = true
							break
						end
					end
				end
				if isFav then
					tokMatched = true
					score = score + 60
				end
			-- 10. Standalone number: check if it's a difficulty or BPM
			elseif tonumber(tok) and tonumber(tok) <= 30 and HasDifficulty(entry, tonumber(tok)) then
				tokMatched = true
				score = score + 40
				if entry.title_lower:find(tok, 1, true) then
					score = score + 50
				end
			elseif tonumber(tok) and tonumber(tok) > 30 and MatchesBpm(entry, tonumber(tok)) then
				tokMatched = true
				score = score + 40
				if entry.title_lower:find(tok, 1, true) then
					score = score + 50
				end
			-- 11. Free text match across all metadata fields
			else
				local cleanTok = tok:gsub('^"', ''):gsub('"$', '')
				if #cleanTok > 0 then
					if entry.title_lower:find(cleanTok, 1, true) then
						tokMatched = true
						if entry.title_lower == cleanTok then
							score = score + 300
						elseif entry.title_lower:sub(1, #cleanTok) == cleanTok then
							score = score + 160
						else
							score = score + 100
						end
					end
					if entry.translit_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 70
					end
					if entry.subtitle_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 75
					end
					if entry.artist_lower:find(cleanTok, 1, true) then
						tokMatched = true
						if entry.artist_lower == cleanTok then
							score = score + 160
						elseif entry.artist_lower:sub(1, #cleanTok) == cleanTok then
							score = score + 110
						else
							score = score + 75
						end
					end
					if entry.translit_artist_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 70
					end
					if entry.group_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 50
					end
					if entry.folder_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 45
					end
					if entry.authors_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 65
					end
					if entry.genre_lower:find(cleanTok, 1, true) then
						tokMatched = true
						score = score + 55
					end
				end
			end

			if not tokMatched then
				matchAll = false
				break
			end
		end

		if matchAll then
			table.insert(results, { score = score, entry = entry })
		end
	end

	-- Sort by score descending, then title ascending
	table.sort(results, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.entry.title_lower < b.entry.title_lower
	end)

	local finalResults = {}
	local totalCount = #results
	for i = 1, math.min(totalCount, maxResults) do
		table.insert(finalResults, results[i].entry)
	end

	return finalResults, totalCount
end

return SongSearchEngine
