-- CategoryNavigation/default.lua
-- Master controller and input router for Category Navigation in Simply Love.
-- Unifies CategoryEngine, CategoryRibbon, and CategorySongWheel.
-- Provides seamless instant switching between Normal Scroll Wheel and Keyboard Mode at any time.

local CategoryEngine = LoadActor("CategoryEngine.lua")
local CategoryRibbon = LoadActor("CategoryRibbon.lua")
local CategorySongWheel = LoadActor("CategorySongWheel.lua")

-- References to UI Actors
local rootActor = nil

-- State variables
local isNavActive = false
local wasNavActiveBeforeOmnibar = false
local activeCategoryIdx = 1
local activeSubChipIdx = 1
local currentSongs = {}
local selectedSongIdx = 1
local topVisibleIdx = 1
local maxRows = 14

local isShiftHeld = false
local isCtrlHeld = false

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
local RefreshCategorySongs = nil
local EnterKeyboardMode = nil
local ExitKeyboardMode = nil

-- Broadcast UI State to Ribbon and SongWheel
BroadcastUIState = function()
	local cat = categories[activeCategoryIdx]
	if not cat then return end
	local subChips = CategoryEngine.GetSubChips(cat.id)

	MESSAGEMAN:Broadcast("UpdateCategoryUI", {
		categoryIdx = activeCategoryIdx,
		categoryId = cat.id,
		subChipIdx = activeSubChipIdx,
		subChips = subChips,
		songs = currentSongs,
		totalSongs = #currentSongs,
		selectedIdx = selectedSongIdx,
		topIdx = topVisibleIdx,
	})
end

-- Sync current song with StepMania engine and native MusicWheel
SyncCurrentSong = function(song)
	if not song then return end
	GAMESTATE:SetPreferredSong(song)
	GAMESTATE:SetCurrentSong(song)

	local top = SCREENMAN:GetTopScreen()
	if top and top.GetMusicWheel then
		local wheel = top:GetMusicWheel()
		if wheel and wheel.SelectSong then
			if wheel.SetOpenSection and song.GetGroupName then
				wheel:SetOpenSection(song:GetGroupName())
			end
			wheel:SelectSong(song)
		end
	end

	MESSAGEMAN:Broadcast("CurrentSongChanged")
end

-- Refresh Songs for active Category & SubChip
RefreshCategorySongs = function()
	local cat = categories[activeCategoryIdx]
	if not cat then return end

	local subChips = CategoryEngine.GetSubChips(cat.id)
	local activeChip = subChips[activeSubChipIdx] or subChips[1]
	local chipId = activeChip and activeChip.id or "all"

	currentSongs = CategoryEngine.GetSongs(cat.id, chipId)
	selectedSongIdx = 1
	topVisibleIdx = 1

	if #currentSongs > 0 and currentSongs[1].song then
		SyncCurrentSong(currentSongs[1].song)
	end

	BroadcastUIState()
end

-- Cycle Category (1 to 6)
local function CycleCategory(delta)
	local numSelectable = 6 -- PACKS, FAVORITES, METERS, BPM, RANKED, A-Z
	activeCategoryIdx = activeCategoryIdx + delta
	if activeCategoryIdx < 1 then activeCategoryIdx = numSelectable end
	if activeCategoryIdx > numSelectable then activeCategoryIdx = 1 end

	activeSubChipIdx = 1
	RefreshCategorySongs()
end

-- Cycle SubChip
local function CycleSubChip(delta)
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

	if rootActor then
		rootActor:stoptweening()
		rootActor:sleep(0.12)
		rootActor:queuecommand("TriggerAudioPreview")
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

	local st = style:GetStepsType()
	local steps = song:GetOneSteps(st, targetDiff)
	if steps then
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			GAMESTATE:SetCurrentSteps(pn, steps)
			GAMESTATE:SetPreferredDifficulty(pn, targetDiff)
			local pShort = ToEnumShortString(pn)
			MESSAGEMAN:Broadcast("CurrentSteps" .. pShort .. "Changed")
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
	local newIdx = selectedSongIdx + delta
	if newIdx < 1 then newIdx = 1 end
	if newIdx > #currentSongs then newIdx = #currentSongs end
	if newIdx ~= selectedSongIdx then
		SelectSongAtIndex(newIdx, true)
	end
end

-- Enter Keyboard Mode (Hide native wheel, show category navigation)
EnterKeyboardMode = function()
	isNavActive = true
	lastTabTime = GetTimeSinceStart()
	tabRepeatCount = 0
	if SL and SL.Global then SL.Global.CategoryNavActive = true end
	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, true)
	end
	Trace("CATEGORY_NAV: EnterKeyboardMode - input redirected for all players")

	local top = SCREENMAN:GetTopScreen()
	if top and top.GetMusicWheel then
		local wheel = top:GetMusicWheel()
		if wheel then
			wheel:visible(false)
			wheel:diffusealpha(0)
		end
	end

	if rootActor then
		rootActor:visible(true)
	end

	local curSong = GAMESTATE:GetCurrentSong()
	RefreshCategorySongs()

	-- If a song was already selected on the native wheel, attempt to position on it
	if curSong and #currentSongs > 0 then
		for idx, entry in ipairs(currentSongs) do
			if entry.song == curSong then
				selectedSongIdx = idx
				if selectedSongIdx < topVisibleIdx or selectedSongIdx >= topVisibleIdx + maxRows then
					topVisibleIdx = math.max(1, math.min(#currentSongs - maxRows + 1, selectedSongIdx - 2))
				end
				break
			end
		end
	end

	SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
	BroadcastUIState()
	MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = isNavActive })
end

-- Exit Keyboard Mode (Hide category navigation, restore normal scroll wheel)
ExitKeyboardMode = function()
	isNavActive = false
	lastTabTime = 0
	tabRepeatCount = 0
	if SL and SL.Global then SL.Global.CategoryNavActive = false end
	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, false)
	end
	Trace("CATEGORY_NAV: ExitKeyboardMode - input un-redirected, normal wheel restored")

	if rootActor then
		rootActor:visible(false)
	end

	local top = SCREENMAN:GetTopScreen()
	if top and top.GetMusicWheel then
		local wheel = top:GetMusicWheel()
		if wheel then
			wheel:visible(true)
			wheel:diffusealpha(1)
			local curSong = GAMESTATE:GetCurrentSong()
			if curSong and wheel.SelectSong then
				if wheel.SetOpenSection and curSong.GetGroupName then
					wheel:SetOpenSection(curSong:GetGroupName())
				end
				wheel:SelectSong(curSong)
			end
		end
	end

	SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
	MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = isNavActive })
end

-- Master Actor Frame
local af = Def.ActorFrame {
	Name = "CategoryNavigationMaster",
	InitCommand = function(self)
		rootActor = self
		local startInCatNav = (ThemePrefs.Get("CategoryNavigation") == true)
		self:visible(startInCatNav)
		isNavActive = startInCatNav
		if SL and SL.Global then SL.Global.CategoryNavActive = startInCatNav end
	end,
	OnCommand = function(self)
		local top = SCREENMAN:GetTopScreen()
		if top and top.AddInputCallback then
			top:AddInputCallback(CategoryInputHandler)
		end

		local startInCatNav = (ThemePrefs.Get("CategoryNavigation") == true)
		self:visible(startInCatNav)
		isNavActive = startInCatNav
		if SL and SL.Global then SL.Global.CategoryNavActive = startInCatNav end
		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = isNavActive })

		if startInCatNav then
			for pn in ivalues(PlayerNumber) do
				SCREENMAN:set_input_redirected(pn, true)
			end
			if top and top.GetMusicWheel then
				local wheel = top:GetMusicWheel()
				if wheel then
					wheel:visible(false)
					wheel:diffusealpha(0)
				end
			end
			RefreshCategorySongs()
		else
			for pn in ivalues(PlayerNumber) do
				SCREENMAN:set_input_redirected(pn, false)
			end
			-- Ensure normal wheel is visible and active
			if top and top.GetMusicWheel then
				local wheel = top:GetMusicWheel()
				if wheel then
					wheel:visible(true)
					wheel:diffusealpha(1)
				end
			end
		end

		if FILEMAN:DoesFileExist("Save/run_category_test.flag") then
			Trace("CATEGORY_TEST: Flag detected, starting test sequence")
			self:sleep(1.0):queuecommand("TestCatReady")
		end

		if FILEMAN:DoesFileExist("Save/run_switch_test.flag") then
			Trace("SWITCH_TEST: Flag detected, starting mode switch test sequence")
			self:sleep(1.0):queuecommand("TestSwitchInitial")
		end

		if FILEMAN:DoesFileExist("Save/run_escape_test.flag") then
			Trace("ESCAPE_TEST: Flag detected, starting escape test sequence")
			self:sleep(1.0):queuecommand("TestEscapeEnterKey")
		end

		if FILEMAN:DoesFileExist("Save/run_tab_test.flag") then
			Trace("TAB_TEST: Flag detected, starting tab repeat test sequence")
			self:sleep(1.0):queuecommand("TestTabRepeat")
		end

		if FILEMAN:DoesFileExist("Save/run_sequence_test.flag") then
			Trace("SEQUENCE_TEST: Flag detected, starting sequence toggle test")
			self:sleep(1.0):queuecommand("TestSequenceStart")
		end
	end,
	TestSequenceStartCommand = function(self)
		Trace("SEQUENCE_TEST_STEP: step1_exit_keyboard_mode")
		ExitKeyboardMode()
		local redir1 = SCREENMAN:get_input_redirected(PLAYER_1)
		Trace(string.format("SEQUENCE_TEST_STATE: step1 isNavActive=%s redir=%s", tostring(isNavActive), tostring(redir1)))
		self:sleep(0.5):queuecommand("TestSequenceStep2")
	end,
	TestSequenceStep2Command = function(self)
		Trace("SEQUENCE_TEST_STEP: step2_enter_keyboard_mode_via_tab")
		CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_tab" },
			GameButton = "Select",
		})
		local redir2 = SCREENMAN:get_input_redirected(PLAYER_1)
		Trace(string.format("SEQUENCE_TEST_STATE: step2 isNavActive=%s redir=%s", tostring(isNavActive), tostring(redir2)))
		self:sleep(0.5):queuecommand("TestSequenceStep3")
	end,
	TestSequenceStep3Command = function(self)
		Trace("SEQUENCE_TEST_STEP: step3_exit_keyboard_mode_via_esc")
		CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_escape" },
			GameButton = "Back",
		})
		local redir3 = SCREENMAN:get_input_redirected(PLAYER_1)
		Trace(string.format("SEQUENCE_TEST_STATE: step3 isNavActive=%s redir=%s", tostring(isNavActive), tostring(redir3)))
		self:sleep(0.5):queuecommand("TestSequenceStep4")
	end,
	TestSequenceStep4Command = function(self)
		Trace("SEQUENCE_TEST_STEP: step4_verify_inputs_on_wheel")
		local handledRight = CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_right" },
			GameButton = "MenuRight",
		})
		local handledLeft = CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_left" },
			GameButton = "MenuLeft",
		})
		local handledEnter = CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_enter" },
			GameButton = "Start",
		})
		local handledEsc = CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_escape" },
			GameButton = "Back",
		})

		Trace(string.format("SEQUENCE_TEST_VERIFY: handledRight=%s handledLeft=%s handledEnter=%s handledEsc=%s",
			tostring(handledRight), tostring(handledLeft), tostring(handledEnter), tostring(handledEsc)))

		local success = (handledRight == false) and (handledLeft == false) and (handledEnter == false) and (handledEsc == false)
		Trace(string.format("SEQUENCE_TEST_FINISH: success=%s", tostring(success)))
	end,
	TestTabRepeatCommand = function(self)
		Trace("TAB_TEST_STEP: start")
		EnterKeyboardMode()
		local startCat = activeCategoryIdx
		Trace("TAB_TEST: initial cat = " .. tostring(startCat))

		-- 1. FirstPress should advance category immediately
		CategoryInputHandler({ type = "InputEventType_FirstPress", DeviceInput = { button = "DeviceButton_tab" } })
		local catAfter1 = activeCategoryIdx
		Trace("TAB_TEST: after FirstPress = " .. tostring(catAfter1))

		-- 2. Immediate Repeat (simulating high-speed hardware repeat) should be IGNORED
		CategoryInputHandler({ type = "InputEventType_Repeat", DeviceInput = { button = "DeviceButton_tab" } })
		local catAfterImmediateRepeat = activeCategoryIdx
		Trace("TAB_TEST: after immediate Repeat = " .. tostring(catAfterImmediateRepeat))

		-- Queue next step after 0.5s to test delayed repeat
		self:sleep(0.5):queuecommand("TestTabDelayedRepeat")
	end,
	TestTabDelayedRepeatCommand = function(self)
		-- 3. Repeat after 0.5s (>= 0.40s) should advance category
		CategoryInputHandler({ type = "InputEventType_Repeat", DeviceInput = { button = "DeviceButton_tab" } })
		local catAfterDelayedRepeat = activeCategoryIdx
		Trace("TAB_TEST: after 0.5s Repeat = " .. tostring(catAfterDelayedRepeat))

		-- 4. Immediate repeat again should be ignored
		CategoryInputHandler({ type = "InputEventType_Repeat", DeviceInput = { button = "DeviceButton_tab" } })
		local catAfterSubsequentFastRepeat = activeCategoryIdx
		Trace("TAB_TEST: after subsequent fast Repeat = " .. tostring(catAfterSubsequentFastRepeat))

		-- Queue finish after 0.35s
		self:sleep(0.35):queuecommand("TestTabRepeatInterval")
	end,
	TestTabRepeatIntervalCommand = function(self)
		-- 5. Repeat after 0.35s (>= 0.28s) should advance category
		CategoryInputHandler({ type = "InputEventType_Repeat", DeviceInput = { button = "DeviceButton_tab" } })
		local catAfterIntervalRepeat = activeCategoryIdx
		Trace("TAB_TEST: after interval Repeat = " .. tostring(catAfterIntervalRepeat))

		-- 6. Release resets state
		CategoryInputHandler({ type = "InputEventType_Release", DeviceInput = { button = "DeviceButton_tab" } })
		Trace("TAB_TEST_STEP: finished")
	end,
	TestEscapeEnterKeyCommand = function(self)
		EnterKeyboardMode()
		Trace("ESCAPE_TEST_STEP: keyboard_ready")
	end,
	TestSwitchInitialCommand = function(self)
		Trace("SWITCH_TEST_STEP: wheel_initial")
		self:sleep(1.5):queuecommand("TestSwitchEnterKey")
	end,
	TestSwitchEnterKeyCommand = function(self)
		EnterKeyboardMode()
		Trace("SWITCH_TEST_STEP: keyboard_switched")
		self:sleep(1.5):queuecommand("TestSwitchExitKey")
	end,
	TestSwitchExitKeyCommand = function(self)
		CategoryInputHandler({
			type = "InputEventType_FirstPress",
			DeviceInput = { button = "DeviceButton_escape" }
		})
		Trace("SWITCH_TEST_STEP: wheel_returned")
		self:sleep(1.5):queuecommand("TestSwitchDone")
	end,
	TestSwitchDoneCommand = function(self)
		Trace("SWITCH_TEST_STEP: finished")
	end,
	TestCatReadyCommand = function(self)
		Trace("CATEGORY_TEST_STEP: cat_ready")
		self:sleep(1.2):queuecommand("TestCatMeters")
	end,
	TestCatMetersCommand = function(self)
		CycleCategory(2)
		Trace("CATEGORY_TEST_STEP: cat_meters")
		self:sleep(1.2):queuecommand("TestCatChips")
	end,
	TestCatChipsCommand = function(self)
		CycleSubChip(2)
		Trace("CATEGORY_TEST_STEP: cat_chips")
		self:sleep(1.2):queuecommand("TestCatScroll")
	end,
	TestCatScrollCommand = function(self)
		ScrollSong(2)
		Trace("CATEGORY_TEST_STEP: cat_scroll")
		self:sleep(1.2):queuecommand("TestCatBPM")
	end,
	TestCatBPMCommand = function(self)
		CycleCategory(1)
		Trace("CATEGORY_TEST_STEP: cat_bpm")
		self:sleep(1.2):queuecommand("TestCatDone")
	end,
	TestCatDoneCommand = function(self)
		Trace("CATEGORY_TEST_STEP: finished")
	end,
	OffCommand = function(self)
		for pn in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(pn, false)
		end
		local top = SCREENMAN:GetTopScreen()
		if top and top.RemoveInputCallback then
			top:RemoveInputCallback(CategoryInputHandler)
		end
		isNavActive = false
		if SL and SL.Global then SL.Global.CategoryNavActive = false end
		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
	end,
	ShowOmnibarMessageCommand = function(self)
		self:visible(false)
		wasNavActiveBeforeOmnibar = isNavActive
		isNavActive = false
		if SL and SL.Global then SL.Global.CategoryNavActive = false end
		MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
	end,
	HideOmnibarMessageCommand = function(self)
		if wasNavActiveBeforeOmnibar then
			self:visible(true)
			isNavActive = true
			if SL and SL.Global then SL.Global.CategoryNavActive = true end
			for pn in ivalues(PlayerNumber) do
				SCREENMAN:set_input_redirected(pn, true)
			end
			local curSong = GAMESTATE:GetCurrentSong()
			if curSong then
				local found = false
				for idx, entry in ipairs(currentSongs) do
					if entry.song == curSong then
						selectedSongIdx = idx
						if selectedSongIdx < topVisibleIdx or selectedSongIdx >= topVisibleIdx + maxRows then
							topVisibleIdx = math.max(1, math.min(#currentSongs - maxRows + 1, selectedSongIdx - 2))
						end
						found = true
						break
					end
				end

				-- If the song is NOT in the current category/subchip, automatically switch to PACKS category
				-- and locate the song's pack so the wheel displays the newly selected song seamlessly!
				if not found and curSong.GetGroupName then
					local packName = curSong:GetGroupName()
					activeCategoryIdx = 1 -- Switch to PACKS category
					local subChips = CategoryEngine.GetSubChips("packs")
					activeSubChipIdx = 1
					for cIdx, chip in ipairs(subChips) do
						if chip.id == packName then
							activeSubChipIdx = cIdx
							break
						end
					end
					RefreshCategorySongs()
					for idx, entry in ipairs(currentSongs) do
						if entry.song == curSong then
							selectedSongIdx = idx
							topVisibleIdx = math.max(1, math.min(#currentSongs - maxRows + 1, selectedSongIdx - 2))
							break
						end
					end
				end
			end
			BroadcastUIState()
			MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = true })
		else
			self:visible(false)
			isNavActive = false
			if SL and SL.Global then SL.Global.CategoryNavActive = false end
			for pn in ivalues(PlayerNumber) do
				SCREENMAN:set_input_redirected(pn, false)
			end
			MESSAGEMAN:Broadcast("CategoryNavigationModeChanged", { active = false })
		end
	end,
	CodeMessageCommand = function(self, params)
		if params and (params.Name == "Favorite1" or params.Name == "Favorite2") then
			if categories[activeCategoryIdx] and categories[activeCategoryIdx].id == "favorites" then
				RefreshCategorySongs()
			else
				BroadcastUIState()
			end
		end
	end,
	ToggleCategoryNavigationMessageCommand = function(self)
		if isNavActive then
			ExitKeyboardMode()
		else
			EnterKeyboardMode()
		end
	end,
	TriggerAudioPreviewCommand = function(self)
		if isNavActive then
			play_sample_music()
		end
	end,
}

af[#af + 1] = CategoryRibbon
af[#af + 1] = CategorySongWheel

-- Input Router for Category Navigation & Mode Switching
CategoryInputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	local btn = event.DeviceInput.button
	local eventType = event.type

	Trace(string.format("CAT_INPUT: type=%s btn=%s gameBtn=%s isNavActive=%s",
		tostring(eventType), tostring(btn), tostring(event.GameButton), tostring(isNavActive)))

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

	-- =========================================================
	-- CASE 1: In Normal Scroll Wheel Mode (isNavActive == false)
	-- =========================================================
	if not isNavActive then
		-- Check if player pressed Tab, F3, or Ctrl+K to switch into Keyboard Mode!
		if btn == "DeviceButton_tab" or btn == "DeviceButton_f3" or (isCtrlHeld and (btn == "DeviceButton_k" or btn == "DeviceButton_K")) then
			if eventType == "InputEventType_FirstPress" then
				lastTabTime = GetTimeSinceStart()
				tabRepeatCount = 0
				EnterKeyboardMode()
				return true
			end
			return true
		end

		-- All other inputs (arcade cabinet buttons MenuLeft, MenuRight, MenuUp, MenuDown, Start, Select,
		-- and keyboard arrows / alphanumeric letters) pass through completely!
		-- Standard DDR cabinet input works natively with 100% Simply Love wheel behavior!
		return false
	end

	-- =========================================================
	-- CASE 2: In Keyboard Mode (isNavActive == true)
	-- =========================================================

	-- Escape, Back, F3, or Ctrl+K: Switch BACK to Normal Scroll Wheel at any time!
	if btn == "DeviceButton_escape" or btn == "DeviceButton_f3" or (isCtrlHeld and (btn == "DeviceButton_k" or btn == "DeviceButton_K")) or event.GameButton == "Back" then
		Trace("CATEGORY_NAV: Escape/Back pressed - exiting to wheel cleanly without prompt")
		ExitKeyboardMode()
		return true
	end

	-- Omnibar / Search hotkeys:
	if btn == "DeviceButton_slash" or (isCtrlHeld and (btn == "DeviceButton_f" or btn == "DeviceButton_F")) then
		MESSAGEMAN:Broadcast("OpenOmnibarWithQuery", { query = "" })
		return true
	end

	-- Ctrl+D or Ctrl+B: Toggle Favorite on current song
	if isCtrlHeld and (btn == "DeviceButton_d" or btn == "DeviceButton_D" or btn == "DeviceButton_b" or btn == "DeviceButton_B") then
		for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
			addOrRemoveFavorite(pn)
			break
		end
		if categories[activeCategoryIdx] and categories[activeCategoryIdx].id == "favorites" then
			RefreshCategorySongs()
		else
			BroadcastUIState()
		end
		return true
	end

	-- Tab: Cycle Category Tabs (paced repeat rate limiting)
	if btn == "DeviceButton_tab" or event.GameButton == "Select" then
		local now = GetTimeSinceStart()
		if eventType == "InputEventType_FirstPress" then
			lastTabTime = now
			tabRepeatCount = 0
			CycleCategory(isShiftHeld and -1 or 1)
			SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
			return true
		elseif eventType == "InputEventType_Repeat" then
			if tabRepeatCount == 0 then
				if (now - lastTabTime) >= TAB_INITIAL_DELAY then
					lastTabTime = now
					tabRepeatCount = 1
					CycleCategory(isShiftHeld and -1 or 1)
					SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
				end
			else
				if (now - lastTabTime) >= TAB_REPEAT_INTERVAL then
					lastTabTime = now
					tabRepeatCount = tabRepeatCount + 1
					CycleCategory(isShiftHeld and -1 or 1)
					SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
				end
			end
			return true
		end
	end

	-- [ / ]: Cycle Sub-Chips
	if btn == "DeviceButton_left bracket" or btn == "DeviceButton_[" then
		CycleSubChip(-1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	elseif btn == "DeviceButton_right bracket" or btn == "DeviceButton_]" then
		CycleSubChip(1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	end

	-- Left / Right or MenuLeft / MenuRight: Cycle Sub-Chips (pad or keyboard)
	if btn == "DeviceButton_left" or event.GameButton == "MenuLeft" then
		CycleSubChip(-1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	elseif btn == "DeviceButton_right" or event.GameButton == "MenuRight" then
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

	-- Page Up / Page Down (jump 8 songs)
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

	-- Number keys 1-5 (top row or numpad): Direct Difficulty Selection
	local numKey = btn:match("^DeviceButton_([1-5])$")
		or btn:match("^DeviceButton_[kK][pP]%s*([1-5])$")
		or btn:match("^DeviceButton_[nN][uU][mM]%s*([1-5])$")
		or btn:match("^([1-5])$")
	if numKey then
		SetDifficultyDirect(numKey)
		return true
	end

	-- Enter / Start:
	-- Un-redirect input and begin the song or transition to player options!
	if btn == "DeviceButton_enter" or event.GameButton == "Start" then
		for pn in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(pn, false)
		end
		local top = SCREENMAN:GetTopScreen()
		if top and top.StartTransitioningScreen then
			SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
			top:StartTransitioningScreen("SM_GoToNextScreen")
			return true
		end
		return true
	end

	-- All other keys (like A-Z letters for instant type-to-search) pass through
	return false
end

return af
