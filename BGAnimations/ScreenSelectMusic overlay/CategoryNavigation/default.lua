-- CategoryNavigation/default.lua
-- Master controller and input router for Category Navigation ("Keyboard Mode") in Simply Love.
-- Unifies CategoryEngine, CategoryRibbon, and CategorySongWheel and provides instant switching
-- between the normal scroll wheel and Keyboard Mode at any time.
--
-- Engine facts this file relies on (verified against the ITGmania C++ source):
--  * ScreenManager::Input() calls Screen::Input() FIRST (unless the player is redirected) and
--    then PassInputToLua(); the Lua callback's return value is IGNORED for the top screen.
--    The only thing that stops the engine from acting on a key is SCREENMAN:set_input_redirected.
--  * Lua input callbacks are stored in a std::map keyed by closure address, so their relative
--    order is arbitrary. Handlers must therefore own DISJOINT keys/states (see the Omnibar guard).
--  * GAMESTATE current song / the banner / steps / density graph are driven by the wheel's
--    SM_SongChanged -> ScreenSelectMusic::AfterMusicChange(). SelectSong() alone does not post it.
--  * The per-screen redirect flag is discarded with the screen, so it is NOT cleared on Off.

local CategoryEngine = LoadActor("CategoryEngine.lua")
local CategoryRibbon = LoadActor("CategoryRibbon.lua")
local CategorySongWheel = LoadActor("CategorySongWheel.lua")
local SongSearchEngine = CategoryEngine.GetSearchEngine()
local WheelSync = LoadActor("../KeyboardOmnibar/WheelSync.lua")
local KeyboardLayout = LoadActor("../KeyboardOmnibar/KeyboardLayout.lua")

-- References to UI Actors
local rootActor = nil

-- State variables
local isNavActive = false
local wasNavActiveBeforeOmnibar = false
local activeCategoryIdx = 1
local activeSubChipIdx = 1
local currentSongs = {}
local unfilteredSongs = {}
local filterQuery = ""
local selectedSongIdx = 1
local topVisibleIdx = 1
local maxRows = 14
local isStarting = false           -- Start was handed to the engine; ignore further input
local isLeaving = false            -- the screen's Off sequence has begun

local isShiftHeld = false
local isCtrlHeld = false

-- The cheap part of a selection change (GAMESTATE song + broadcast) happens immediately; the
-- expensive part (wheel rebuild + engine SM_SongChanged: banner, steps, graph, preview music)
-- is coalesced so holding Up/Down does not rebuild the wheel on every repeat.
local SETTLE_DELAY = 0.12
local pendingWheelSong = nil

-- Tab Repeat Pacing & Debounce
local lastTabTime = 0
local tabRepeatCount = 0
local TAB_INITIAL_DELAY = 0.40   -- Seconds before first repeat when held
local TAB_REPEAT_INTERVAL = 0.28  -- Seconds between subsequent repeats when held

local categories = CategoryEngine.GetCategories()

-- Forward declarations
local CategoryInputHandler = nil
local BroadcastUIState = nil
local SyncCurrentSong = nil
local ApplyFilter = nil
local RefreshCategorySongs = nil
local EnterKeyboardMode = nil
local ExitKeyboardMode = nil

-- -------------------------------------------------------------
-- Small helpers
-- -------------------------------------------------------------
local function SetRedirect(on)
	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, on)
	end
end

local function GetTopAndWheel()
	local top = SCREENMAN:GetTopScreen()
	if top and top.GetMusicWheel then
		return top, top:GetMusicWheel()
	end
	return top, nil
end

local function SetNavActive(active)
	isNavActive = active
	if SL and SL.Global then SL.Global.CategoryNavActive = active end
end

local function ClampTop(sel)
	return math.max(1, math.min(#currentSongs - maxRows + 1, sel - 2))
end

local function RecordRecent(song)
	if song and SongSearchEngine and SongSearchEngine.AddRecentSong then
		SongSearchEngine.AddRecentSong(song)
	end
end

-- Bring the (hidden) native wheel and the engine's selection-driven UI in line with `pendingWheelSong`.
-- Returns true when the wheel accepted the song.
local function FlushWheelSync()
	local song = pendingWheelSong
	if not song then return false end
	pendingWheelSong = nil
	local top, wheel = GetTopAndWheel()
	if not wheel then return false end
	-- Selects the song, redraws the wheel rows, and posts SM_SongChanged so that
	-- ScreenSelectMusic::AfterMusicChange() sets m_pCurSong from the wheel and refreshes banner /
	-- steps / density graph / sample music exactly as a normal wheel move does.
	return WheelSync.SelectSong(top, wheel, song)
end

local function ScheduleSettle()
	if rootActor then
		rootActor:stoptweening():sleep(SETTLE_DELAY):queuecommand("SettleSelection")
	end
end

-- Seconds left on the screen's menu timer (99 when the timer is disabled), or nil if unreadable.
-- When the timer expires the ENGINE starts whatever the native wheel has selected, so the wheel
-- must never lag the highlighted row near expiry.
local function MenuTimerSecondsLeft()
	local top = SCREENMAN:GetTopScreen()
	local timer = top and top.GetChild and top:GetChild("Timer")
	if timer and timer.GetSeconds then return timer:GetSeconds() end
	return nil
end

-- Filter a list of songs by query (case-insensitive multi-token matching across title, artist, subtitle, folder)
local function FilterSongList(songs, query)
	if not query or query == "" then return songs end
	local clean = query:lower():gsub("^%s*(.-)%s*$", "%1")
	if clean == "" then return songs end

	local tokens = {}
	for tok in clean:gmatch("%S+") do
		tokens[#tokens + 1] = tok
	end
	if #tokens == 0 then return songs end

	local results = {}
	for _, entry in ipairs(songs) do
		local t = entry.title_lower or (entry.title and entry.title:lower()) or ""
		local tt = entry.translit_lower or (entry.translit_title and entry.translit_title:lower()) or ""
		local a = entry.artist_lower or (entry.artist and entry.artist:lower()) or ""
		local ta = entry.translit_artist_lower or ""
		local sub = entry.subtitle_lower or (entry.subtitle and entry.subtitle:lower()) or ""
		local folder = entry.folder_lower or (entry.folder and entry.folder:lower()) or ""

		local matchAll = true
		for _, tok in ipairs(tokens) do
			if not (t:find(tok, 1, true) or tt:find(tok, 1, true)
				or a:find(tok, 1, true) or ta:find(tok, 1, true)
				or sub:find(tok, 1, true) or folder:find(tok, 1, true)) then
				matchAll = false
				break
			end
		end

		if matchAll then
			results[#results + 1] = entry
		end
	end
	return results
end

-- Apply the active section filter (or restore unfiltered list) and update the cursor and UI
ApplyFilter = function(anchorSong, fallbackIdx)
	if not filterQuery or filterQuery == "" then
		currentSongs = unfilteredSongs
	else
		currentSongs = FilterSongList(unfilteredSongs, filterQuery)
	end

	local idx = nil
	if anchorSong then
		for i, entry in ipairs(currentSongs) do
			if entry.song == anchorSong then idx = i break end
		end
	end
	if not idx and fallbackIdx and #currentSongs > 0 then
		idx = math.min(math.max(fallbackIdx, 1), #currentSongs)
	end
	selectedSongIdx = idx or 1
	topVisibleIdx = ClampTop(selectedSongIdx)

	local entry = currentSongs[selectedSongIdx]
	if entry and entry.song then
		SyncCurrentSong(entry.song)
	end

	BroadcastUIState()
end

-- Broadcast UI State to Ribbon and SongWheel
BroadcastUIState = function()
	local cat = categories[activeCategoryIdx]
	if not cat then return end
	local subChips = CategoryEngine.GetSubChips(cat.id)
	local chip = subChips[activeSubChipIdx] or subChips[1]
	local chipId = chip and chip.id or "all"
	local meterMin, meterMax = CategoryEngine.GetMeterRange(cat.id, chipId)

	MESSAGEMAN:Broadcast("UpdateCategoryUI", {
		categoryIdx = activeCategoryIdx,
		categoryId = cat.id,
		subChipIdx = activeSubChipIdx,
		subChips = subChips,
		songs = currentSongs,
		totalSongs = #currentSongs,
		unfilteredTotal = #unfilteredSongs,
		filterQuery = filterQuery,
		selectedIdx = selectedSongIdx,
		topIdx = topVisibleIdx,
		meterMin = meterMin,
		meterMax = meterMax,
		emptyHint = CategoryEngine.GetEmptyHint(cat.id, chipId),
	})
end

-- Make `song` the engine's current song immediately; defer the wheel/engine refresh.
SyncCurrentSong = function(song)
	if not song then return end
	GAMESTATE:SetPreferredSong(song)
	-- BroadcastOnChangePtr::Set() already broadcasts CurrentSongChanged; an extra explicit
	-- broadcast only made every listener (info pane, density graph, ...) work twice per move.
	GAMESTATE:SetCurrentSong(song)
	pendingWheelSong = song
	local left = MenuTimerSecondsLeft()
	if left and left < 1.5 then
		FlushWheelSync()
	else
		ScheduleSettle()
	end
end

-- Rebuild the list for the active Category & SubChip.
-- anchorSong: keep the cursor on this song when it is in the new list (and sync the engine to
--             THAT song once, instead of to the first row followed by a cursor-only move).
-- fallbackIdx: when the anchor is absent, keep roughly the same row (e.g. after un-favoriting).
RefreshCategorySongs = function(anchorSong, fallbackIdx)
	local cat = categories[activeCategoryIdx]
	if not cat then return end

	local subChips = CategoryEngine.GetSubChips(cat.id)
	if activeSubChipIdx > #subChips then activeSubChipIdx = 1 end
	local chip = subChips[activeSubChipIdx] or subChips[1]
	unfilteredSongs = CategoryEngine.GetSongs(cat.id, chip and chip.id or "all")

	ApplyFilter(anchorSong, fallbackIdx)
end

-- Cycle Category
local function CycleCategory(delta)
	filterQuery = ""
	local numSelectable = #categories
	activeCategoryIdx = activeCategoryIdx + delta
	if activeCategoryIdx < 1 then activeCategoryIdx = numSelectable end
	if activeCategoryIdx > numSelectable then activeCategoryIdx = 1 end

	activeSubChipIdx = 1
	RefreshCategorySongs()
end

-- Cycle SubChip
local function CycleSubChip(delta)
	filterQuery = ""
	local cat = categories[activeCategoryIdx]
	if not cat then return end
	local subChips = CategoryEngine.GetSubChips(cat.id)
	if #subChips == 0 then return end

	activeSubChipIdx = activeSubChipIdx + delta
	if activeSubChipIdx < 1 then activeSubChipIdx = #subChips end
	if activeSubChipIdx > #subChips then activeSubChipIdx = 1 end

	MESSAGEMAN:Broadcast("CategorySubChipCycled", { dir = delta })
	RefreshCategorySongs()
end

-- Select song at specific index
local function SelectSongAtIndex(idx, playSound)
	if idx < 1 or idx > #currentSongs then return end
	selectedSongIdx = idx

	-- Keep selectedSongIdx within visible viewport (1..maxRows)
	if selectedSongIdx < topVisibleIdx then
		topVisibleIdx = selectedSongIdx
	elseif selectedSongIdx >= topVisibleIdx + maxRows then
		topVisibleIdx = selectedSongIdx - maxRows + 1
	end

	local entry = currentSongs[selectedSongIdx]
	if entry and entry.song then
		SyncCurrentSong(entry.song)
	end

	if playSound then
		SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
	end

	BroadcastUIState()
end

-- Direct Difficulty Selection (1-5)
local diffKeyMap = {
	["1"] = "Difficulty_Beginner",
	["2"] = "Difficulty_Easy",
	["3"] = "Difficulty_Medium",
	["4"] = "Difficulty_Hard",
	["5"] = "Difficulty_Challenge",
}

local function SetDifficultyDirect(diffKey)
	local targetDiff = diffKeyMap[diffKey]
	if not targetDiff then return false end

	local song = GAMESTATE:GetCurrentSong()
	if not song and currentSongs[selectedSongIdx] then
		song = currentSongs[selectedSongIdx].song
	end
	local style = GAMESTATE:GetCurrentStyle()
	if not song or not style then return false end

	local steps = song:GetOneSteps(style:GetStepsType(), targetDiff)
	if steps then
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			GAMESTATE:SetCurrentSteps(pn, steps)
			GAMESTATE:SetPreferredDifficulty(pn, targetDiff)
			MESSAGEMAN:Broadcast("CurrentSteps" .. ToEnumShortString(pn) .. "Changed")
		end
		MESSAGEMAN:Broadcast("CurrentStepsChanged")
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "difficulty easier"))
		BroadcastUIState()
		return true
	end
	return false
end

-- Scroll song by delta
local function ScrollSong(delta)
	if #currentSongs == 0 then return end
	local newIdx = math.max(1, math.min(#currentSongs, selectedSongIdx + delta))
	if newIdx ~= selectedSongIdx then
		SelectSongAtIndex(newIdx, true)
	end
end

-- Enter Keyboard Mode (hide native wheel, show category navigation)
EnterKeyboardMode = function(silent)
	if isNavActive then return end
	filterQuery = ""
	SetNavActive(true)
	lastTabTime = GetTimeSinceStart()
	tabRepeatCount = 0
	isStarting = false
	SetRedirect(true)

	local _, wheel = GetTopAndWheel()
	if wheel then
		wheel:visible(false)
		wheel:diffusealpha(0)
	end
	if rootActor then rootActor:visible(true) end

	CategoryEngine.InvalidatePlayCache()
	-- Anchor on the song the player is already on: sync the engine to THAT song once.
	RefreshCategorySongs(GAMESTATE:GetCurrentSong())

	if not silent then SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down")) end
	MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = true })
end

-- Exit Keyboard Mode (hide category navigation, restore normal scroll wheel)
ExitKeyboardMode = function()
	if not isNavActive then return end
	filterQuery = ""
	SetNavActive(false)
	lastTabTime = 0
	tabRepeatCount = 0
	SetRedirect(false)

	if rootActor then rootActor:visible(false) end

	local _, wheel = GetTopAndWheel()
	if wheel then
		wheel:visible(true)
		wheel:diffusealpha(1)
	end
	-- Put the native wheel (and banner/steps/graph) on whatever is current right now.
	local cur = GAMESTATE:GetCurrentSong()
	if cur then pendingWheelSong = cur end
	FlushWheelSync()

	SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
	MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
end

-- Start the highlighted song THROUGH THE ENGINE'S OWN Start handling.
--
-- The previous version went straight to StartTransitioningScreen("SM_BeginFadingOut"), which
-- skips ScreenSelectMusic::MenuStart: no "Press START for options" window (so ScreenPlayerOptions
-- - speed mods etc. - was unreachable from Keyboard Mode), no m_SelectionState = Finalized, no
-- StepsChosen / compatible-style / prepare_song_for_gameplay.
--
-- The screen's SM_MenuTimer handler is exactly "FinishChangingSorts(); MenuStart()", so once the
-- native wheel is on the highlighted song we hand the start over to it. MenuStart then runs the
-- stock sequence (finalize, options prompt, fade-out) and the Off commands give input back to
-- the engine, so a second Start during the prompt opens Player Options as usual.
local function AbortStart(reason)
	isStarting = false
	Trace("CATEGORY_NAV: start aborted: " .. tostring(reason))
	SOUND:PlayOnce(THEME:GetPathS("Common", "invalid"))
	SCREENMAN:SystemMessage("Could not start that song (" .. tostring(reason) .. ")")
end

local function StartSelectedSong()
	if isStarting then return end
	local entry = currentSongs[selectedSongIdx]
	local top = SCREENMAN:GetTopScreen()
	if not (entry and entry.song and top and top.PostScreenMessage and rootActor) then
		SOUND:PlayOnce(THEME:GetPathS("Common", "invalid"))
		return
	end
	isStarting = true

	-- The highlighted row IS the song that will be played: engine song + native wheel selection.
	GAMESTATE:SetPreferredSong(entry.song)
	GAMESTATE:SetCurrentSong(entry.song)
	pendingWheelSong = entry.song
	if not FlushWheelSync() then
		AbortStart("the wheel did not select it")
		return
	end
	RecordRecent(entry.song)

	-- Give ScreenSelectMusic a few frames to process SM_SongChanged (AfterMusicChange) before
	-- the engine starts; StartEngine re-checks that the wheel really is on this song.
	rootActor:stoptweening():sleep(0.06):queuecommand("StartEngine")
end

local function StartEngine()
	local entry = currentSongs[selectedSongIdx]
	local top, wheel = GetTopAndWheel()
	-- MenuStart plays the wheel's selection (or a RANDOM song if nothing is selected), so make
	-- sure the selection is a song and that it is the one that is highlighted.
	if not (entry and top and wheel
		and wheel:GetSelectedType() == "WheelItemDataType_Song"
		and GAMESTATE:GetCurrentSong() == entry.song) then
		AbortStart("the wheel is not on that song")
		return
	end
	SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
	top:PostScreenMessage("SM_MenuTimer", 0)
	-- If MenuStart declined (e.g. the screen's input lock right after loading) nothing leaves;
	-- let the player try again instead of staying stuck in isStarting.
	rootActor:sleep(1.2):queuecommand("StartWatchdog")
end

-- Wheel mode: remember songs the player actually starts so "Recent Songs" means played songs.
local function NoteWheelStart(event)
	local pn = event.PlayerNumber
	if not (pn and GAMESTATE:IsHumanPlayer(pn)) then return end
	local _, wheel = GetTopAndWheel()
	if wheel and wheel.GetSelectedType and wheel:GetSelectedType() == "WheelItemDataType_Song" then
		RecordRecent(GAMESTATE:GetCurrentSong())
	end
end

-- Master Actor Frame
local af = Def.ActorFrame {
	Name = "CategoryNavigationMaster",
	InitCommand = function(self)
		rootActor = self
		self:visible(false)
		SetNavActive(false)
	end,
	OnCommand = function(self)
		local top = SCREENMAN:GetTopScreen()
		if top and top.AddInputCallback then
			top:AddInputCallback(CategoryInputHandler)
		end

		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
		if ThemePrefs.Get("CategoryNavigation") == true then
			EnterKeyboardMode(true)
		end
	end,
	SettleSelectionCommand = function(self)
		if isNavActive and not isStarting then FlushWheelSync() end
	end,
	StartEngineCommand = function(self)
		StartEngine()
	end,
	StartWatchdogCommand = function(self)
		-- still here a second after handing the start to the engine: it declined; allow a retry
		if not isLeaving then isStarting = false end
	end,
	-- The Omnibar (Shift+Enter) hands its own start to the engine: stop syncing the wheel.
	EngineStartRequestedMessageCommand = function(self)
		isStarting = true
		pendingWheelSong = nil
		self:stoptweening()
	end,
	OffCommand = function(self)
		-- NOTE: input redirection is deliberately NOT touched here. The stock SortMenu's own
		-- OffCommand hands input back to the engine, which is exactly what the engine's "Press
		-- START for options" window needs; the per-screen flag dies with the screen anyway.
		isLeaving = true
		local top = SCREENMAN:GetTopScreen()
		if top and top.RemoveInputCallback then
			top:RemoveInputCallback(CategoryInputHandler)
		end
		SetNavActive(false)
		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
	end,
	ShowOmnibarMessageCommand = function(self)
		self:visible(false)
		wasNavActiveBeforeOmnibar = isNavActive
		SetNavActive(false)
		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
	end,
	HideOmnibarMessageCommand = function(self)
		if wasNavActiveBeforeOmnibar then
			wasNavActiveBeforeOmnibar = false
			self:visible(true)
			SetNavActive(true)
			SetRedirect(true)

			-- If the searched song is not in the current category/chip, switch to its pack.
			local cur = GAMESTATE:GetCurrentSong()
			local found = false
			if cur then
				for _, entry in ipairs(currentSongs) do
					if entry.song == cur then found = true break end
				end
			end
			if cur and not found and cur.GetGroupName then
				local packName = cur:GetGroupName()
				activeCategoryIdx = 1
				activeSubChipIdx = 1
				for cIdx, chip in ipairs(CategoryEngine.GetSubChips("packs")) do
					if chip.id == packName then activeSubChipIdx = cIdx break end
				end
			end
			-- Anchored refresh: cursor AND engine land on the searched song (one sync).
			RefreshCategorySongs(cur)
			MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = true })
		else
			self:visible(false)
			SetNavActive(false)
			SetRedirect(false)
			MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
		end
	end,
	CodeMessageCommand = function(self, params)
		if isNavActive and params and (params.Name == "Favorite1" or params.Name == "Favorite2") then
			if categories[activeCategoryIdx] and categories[activeCategoryIdx].id == "favorites" then
				RefreshCategorySongs(nil, selectedSongIdx)
			else
				BroadcastUIState()
			end
		end
	end,
	ToggleCategoryNavigationMessageCommand = function(self)
		if isNavActive then ExitKeyboardMode() else EnterKeyboardMode() end
	end,
}

af[#af + 1] = CategoryRibbon
af[#af + 1] = CategorySongWheel

-- Input Router for Category Navigation & Mode Switching
-- Ownership (so the arbitrary callback order never matters):
--   Omnibar open            -> Omnibar only (this handler returns false, apart from modifier tracking)
--   Keyboard Mode           -> this handler only (the Omnibar handler returns false)
--   Wheel mode, Omnibar shut-> Tab/F3 here; typing, Ctrl+K/F, "/" in the Omnibar handler
CategoryInputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	local btn = event.DeviceInput.button
	local eventType = event.type

	-- Modifier Tracking
	if btn == "DeviceButton_left shift" or btn == "DeviceButton_right shift" then
		isShiftHeld = (eventType ~= "InputEventType_Release")
		return false
	end
	if btn == "DeviceButton_left ctrl" or btn == "DeviceButton_right ctrl" then
		isCtrlHeld = (eventType ~= "InputEventType_Release")
		return false
	end

	-- Key Release Tracking (resets hold/repeat state so subsequent taps respond immediately)
	if eventType == "InputEventType_Release" then
		if btn == "DeviceButton_tab" or event.GameButton == "Select" then
			lastTabTime = 0
			tabRepeatCount = 0
		end
		return false
	end

	local isDown = (eventType == "InputEventType_FirstPress" or eventType == "InputEventType_Repeat")
	if not isDown then return false end

	-- The Omnibar owns the keyboard while it is open.
	if SL and SL.Global and SL.Global.OmnibarOpen then return false end

	-- =========================================================
	-- CASE 1: Normal Scroll Wheel Mode
	-- =========================================================
	if not isNavActive then
		-- Keyboard Mode is off and the Omnibar is shut, so any input redirection belongs to a
		-- stock modal (Sort Menu, Leaderboard, Test Input, song search). It owns the keyboard:
		-- never switch modes underneath it.
		if SCREENMAN:get_input_redirected(PLAYER_1) or SCREENMAN:get_input_redirected(PLAYER_2) then
			return false
		end

		if btn == "DeviceButton_tab" or btn == "DeviceButton_f3" then
			if eventType == "InputEventType_FirstPress" then
				EnterKeyboardMode()
			end
			return true
		end

		if event.GameButton == "Start" and eventType == "InputEventType_FirstPress" then
			NoteWheelStart(event)
		end

		-- Everything else (cabinet buttons, arrows, letters, Ctrl+K) passes through untouched.
		return false
	end

	-- =========================================================
	-- CASE 2: Keyboard Mode
	-- =========================================================
	if isStarting then return true end

	local logicalChar = KeyboardLayout.TranslateButton(btn, false)
	local typedChar = KeyboardLayout.TranslateButton(btn, isShiftHeld)

	-- Search Everything: "/", Ctrl+F or Ctrl+K open the full Omnibar (search across all songs)
	if btn == "DeviceButton_slash" or btn == "DeviceButton_/" or logicalChar == "/" or typedChar == "/"
		or (isCtrlHeld and (btn == "DeviceButton_f" or btn == "DeviceButton_F" or btn == "DeviceButton_k" or btn == "DeviceButton_K")) then
		if eventType == "InputEventType_FirstPress" then
			if #filterQuery > 0 then
				filterQuery = ""
				ApplyFilter()
			end
			MESSAGEMAN:Broadcast("OpenOmnibarWithQuery", { query = "" })
		end
		return true
	end

	-- Escape / Back / F3: return to Normal Scroll Wheel (or clear section filter if active)
	if btn == "DeviceButton_escape" or btn == "DeviceButton_f3" or event.GameButton == "Back" then
		if eventType == "InputEventType_FirstPress" then
			if #filterQuery > 0 then
				filterQuery = ""
				local cur = currentSongs[selectedSongIdx]
				ApplyFilter(cur and cur.song, selectedSongIdx)
				SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
			else
				ExitKeyboardMode()
			end
		end
		return true
	end

	-- BackSpace / Delete: delete last character of section filter
	if btn == "DeviceButton_backspace" or btn == "DeviceButton_delete" then
		if eventType == "InputEventType_FirstPress" or eventType == "InputEventType_Repeat" then
			if #filterQuery > 0 then
				filterQuery = filterQuery:sub(1, -2)
				local cur = currentSongs[selectedSongIdx]
				ApplyFilter(cur and cur.song, selectedSongIdx)
				SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
				return true
			end
		end
		return true
	end

	-- Ctrl+L: Cycle Keyboard Layout
	if isCtrlHeld and (btn == "DeviceButton_l" or btn == "DeviceButton_L" or logicalChar == "l") then
		if eventType == "InputEventType_FirstPress" then
			KeyboardLayout.CycleLayout()
		end
		return true
	end

	-- Ctrl+D or Ctrl+B: Toggle Favorite on current song
	if isCtrlHeld and (btn == "DeviceButton_d" or btn == "DeviceButton_D" or btn == "DeviceButton_b" or btn == "DeviceButton_B") then
		if eventType == "InputEventType_FirstPress" then
			for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
				addOrRemoveFavorite(pn)
				break
			end
			if categories[activeCategoryIdx] and categories[activeCategoryIdx].id == "favorites" then
				RefreshCategorySongs(nil, selectedSongIdx)   -- stay on the same row
			else
				BroadcastUIState()
			end
		end
		return true
	end

	-- Direct Difficulty Selection via 1-5 (top row or numpad)
	local numKey = btn:match("^DeviceButton_([1-5])$")
		or btn:match("^DeviceButton_[kK][pP]%s*([1-5])$")
		or btn:match("^DeviceButton_[nN][uU][mM]%s*([1-5])$")
		or btn:match("^([1-5])$")
	if numKey and (isCtrlHeld or #filterQuery == 0) then
		if eventType == "InputEventType_FirstPress" then
			SetDifficultyDirect(numKey)
		end
		return true
	end

	-- Tab: Cycle Category Tabs (paced repeat rate limiting)
	if btn == "DeviceButton_tab" or event.GameButton == "Select" then
		local now = GetTimeSinceStart()
		local dir = isShiftHeld and -1 or 1
		if eventType == "InputEventType_FirstPress" then
			lastTabTime = now
			tabRepeatCount = 0
			CycleCategory(dir)
			SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		elseif eventType == "InputEventType_Repeat" then
			local needed = (tabRepeatCount == 0) and TAB_INITIAL_DELAY or TAB_REPEAT_INTERVAL
			if (now - lastTabTime) >= needed then
				lastTabTime = now
				tabRepeatCount = tabRepeatCount + 1
				CycleCategory(dir)
				SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
			end
		end
		return true
	end

	-- [ / ] and Left / Right (or MenuLeft / MenuRight): Cycle Sub-Chips
	if btn == "DeviceButton_left bracket" or btn == "DeviceButton_[" or btn == "DeviceButton_left" or event.GameButton == "MenuLeft" then
		CycleSubChip(-1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	elseif btn == "DeviceButton_right bracket" or btn == "DeviceButton_]" or btn == "DeviceButton_right" or event.GameButton == "MenuRight" then
		CycleSubChip(1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	end

	-- Up / Down or MenuUp / MenuDown: Navigate Song List (pad or keyboard)
	if btn == "DeviceButton_up" or event.GameButton == "MenuUp" then
		ScrollSong(-1)
		return true
	elseif btn == "DeviceButton_down" or event.GameButton == "MenuDown" then
		ScrollSong(1)
		return true
	end

	-- Page Up / Page Down
	if btn == "DeviceButton_page up" then
		ScrollSong(-maxRows)
		return true
	elseif btn == "DeviceButton_page down" then
		ScrollSong(maxRows)
		return true
	end

	-- Home / End
	if btn == "DeviceButton_home" then
		SelectSongAtIndex(1, true)
		return true
	elseif btn == "DeviceButton_end" then
		SelectSongAtIndex(#currentSongs, true)
		return true
	end

	-- Enter / Start
	if btn == "DeviceButton_enter" or event.GameButton == "Start" then
		if eventType == "InputEventType_FirstPress" then StartSelectedSong() end
		return true
	end

	-- Type-to-Filter on the Current Section:
	-- When filter is not active: letters [a-zA-Z] or other non-1..5 characters start the filter.
	-- When filter is active: any printable character (including digits 0-9, space, punctuation) appends to the filter.
	if not isCtrlHeld and typedChar and #typedChar == 1 and (eventType == "InputEventType_FirstPress" or eventType == "InputEventType_Repeat") then
		if #filterQuery == 0 then
			if typedChar:match("^[%w%-%_%.%'\"]$") and not typedChar:match("^[1-5]$") then
				filterQuery = typedChar
				local cur = currentSongs[selectedSongIdx]
				ApplyFilter(cur and cur.song, 1)
				SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
				return true
			end
		else
			if typedChar:match("^[%w%s%-%_%.%'\"]$") then
				filterQuery = filterQuery .. typedChar
				local cur = currentSongs[selectedSongIdx]
				ApplyFilter(cur and cur.song, selectedSongIdx)
				SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
				return true
			end
		end
	end

	return false
end

-- -------------------------------------------------------------
-- Read-only/driver API (used by tests/keyboard_mode; harmless otherwise)
-- -------------------------------------------------------------
SL.Global.KbdModeAPI = SL.Global.KbdModeAPI or {}
SL.Global.KbdModeAPI.engine = CategoryEngine
SL.Global.KbdModeAPI.search = SongSearchEngine
SL.Global.KbdModeAPI.catnav = {
	Enter = function() EnterKeyboardMode() end,
	Exit = function() ExitKeyboardMode() end,
	Handle = function(e) return CategoryInputHandler(e) end,
	SelectIndex = function(i) SelectSongAtIndex(i, false) end,
	SetCategory = function(catIdx, chipIdx)
		activeCategoryIdx = catIdx
		activeSubChipIdx = chipIdx or 1
		filterQuery = ""
		RefreshCategorySongs()
	end,
	Filter = function(q)
		filterQuery = q or ""
		ApplyFilter()
	end,
	State = function()
		local e = currentSongs[selectedSongIdx]
		return { active = isNavActive, selectedIdx = selectedSongIdx, total = #currentSongs,
			unfilteredTotal = #unfilteredSongs, filterQuery = filterQuery,
			selectedTitle = e and e.title or nil, categoryIdx = activeCategoryIdx, chipIdx = activeSubChipIdx }
	end,
}

-- Dev-only scenario driver: loaded only if BOTH the flag and the file exist. The file is not
-- part of cabinet deployments (see tools/deploy_cabinet.py), so this is inert in production.
if FILEMAN:DoesFileExist("Save/dev_scenarios.flag") then
	local devPath = THEME:GetCurrentThemeDirectory() .. "BGAnimations/ScreenSelectMusic overlay/CategoryNavigation/DevScenarios.lua"
	if FILEMAN:DoesFileExist(devPath) then af[#af + 1] = LoadActor("DevScenarios.lua") end
end

return af
