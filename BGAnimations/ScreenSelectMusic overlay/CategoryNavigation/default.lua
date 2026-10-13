-- CategoryNavigation/default.lua
-- Master controller and input router for Category Navigation in Simply Love.
-- Unifies CategoryEngine, CategoryRibbon, and CategorySongWheel.

local CategoryEngine = LoadActor("CategoryEngine.lua")
local CategoryRibbon = LoadActor("CategoryRibbon.lua")
local CategorySongWheel = LoadActor("CategorySongWheel.lua")

-- State variables
local isNavActive = false
local activeCategoryIdx = 1
local activeSubChipIdx = 1
local currentSongs = {}
local selectedSongIdx = 1
local topVisibleIdx = 1
local maxRows = 8

local isShiftHeld = false
local isCtrlHeld = false

local categories = CategoryEngine.GetCategories()

-- Broadcast UI State to Ribbon and SongWheel
local function BroadcastUIState()
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
local function SyncCurrentSong(song)
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
			wheel:Move(1)
			wheel:Move(-1)
			wheel:Move(0)
		end
	end

	MESSAGEMAN:Broadcast("CurrentSongChanged")
end

-- Refresh Songs for active Category & SubChip
local function RefreshCategorySongs()
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

-- Master Actor Frame
local af = Def.ActorFrame {
	Name = "CategoryNavigationMaster",
	InitCommand = function(self)
		local isEnabled = (ThemePrefs.Get("CategoryNavigation") == true)
		self:visible(isEnabled)
		isNavActive = isEnabled
	end,
	OnCommand = function(self)
		local top = SCREENMAN:GetTopScreen()
		if top and top.AddInputCallback then
			top:AddInputCallback(CategoryInputHandler)
		end

		local isEnabled = (ThemePrefs.Get("CategoryNavigation") == true)
		self:visible(isEnabled)
		isNavActive = isEnabled

		if isEnabled then
			if top and top.GetMusicWheel then
				local wheel = top:GetMusicWheel()
				if wheel then
					wheel:visible(false)
					wheel:diffusealpha(0)
				end
			end
			RefreshCategorySongs()

			if FILEMAN:DoesFileExist("Save/run_category_test.flag") then
				Trace("CATEGORY_TEST: Flag detected, starting test sequence")
				self:sleep(1.0):queuecommand("TestCatReady")
			end
		end
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
		local top = SCREENMAN:GetTopScreen()
		if top and top.RemoveInputCallback then
			top:RemoveInputCallback(CategoryInputHandler)
		end
		isNavActive = false
	end,
	ShowOmnibarMessageCommand = function(self)
		self:visible(false)
		isNavActive = false
	end,
	HideOmnibarMessageCommand = function(self)
		local isEnabled = (ThemePrefs.Get("CategoryNavigation") == true)
		self:visible(isEnabled)
		isNavActive = isEnabled
		if isEnabled then
			BroadcastUIState()
		end
	end,
	TestCategoryNavNextTabCommand = function(self)
		CycleCategory(1)
	end,
	TestCategoryNavNextChipCommand = function(self)
		CycleSubChip(1)
	end,
	TestCategoryNavDownCommand = function(self)
		ScrollSong(1)
	end,
}

af[#af + 1] = CategoryRibbon
af[#af + 1] = CategorySongWheel

-- Input Router for Category Navigation
function CategoryInputHandler(event)
	if not ThemePrefs.Get("CategoryNavigation") then return false end
	if not isNavActive then return false end
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

	local isDown = (eventType == "InputEventType_FirstPress" or eventType == "InputEventType_Repeat")
	if not isDown then return false end

	-- Tab: Cycle Category Tabs
	if btn == "DeviceButton_tab" or event.GameButton == "Select" then
		CycleCategory(isShiftHeld and -1 or 1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
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

	-- Left / Right or MenuLeft / MenuRight: Cycle Sub-Chips
	if btn == "DeviceButton_left" or event.GameButton == "MenuLeft" then
		CycleSubChip(-1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	elseif btn == "DeviceButton_right" or event.GameButton == "MenuRight" then
		CycleSubChip(1)
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "select down"))
		return true
	end

	-- Up / Down or MenuUp / MenuDown: Navigate Song List
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

	-- Enter / Start:
	-- Pass through to ScreenSelectMusic to begin the song or open player options!
	if btn == "DeviceButton_enter" or event.GameButton == "Start" then
		return false
	end

	-- All other keys (like A-Z letters for instant type-to-search) pass through
	return false
end

return af
