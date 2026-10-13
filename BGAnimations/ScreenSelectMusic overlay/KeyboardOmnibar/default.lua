-- KeyboardOmnibar/default.lua
-- Master actor frame for the Mounted Keyboard Omnibar & Navigation System

local SongSearchEngine = LoadActor("SongSearchEngine.lua")
local KeyboardLayout = LoadActor("KeyboardLayout.lua")

-- State variables
local isOpen = false
local searchQuery = ""
local candidates = {}
local totalMatches = 0
local selectedIndex = 1
local topVisibleIndex = 1
local maxRows = 10

local isShiftHeld = false
local isCtrlHeld = false

-- History navigation state
local historyIndex = 0
local typedQueryBeforeHistory = ""

-- Audio preview debounce
local lastPreviewSong = nil

-- Category Navigation active tracking
local isCatNavActive = false

local function IsCategoryNavActive()
	if isCatNavActive then return true end
	if SL and SL.Global and SL.Global.CategoryNavActive == true then return true end
	local topScreen = SCREENMAN:GetTopScreen()
	if topScreen and topScreen.GetChild then
		local overlay = topScreen:GetChild("Overlay")
		if overlay and overlay.GetChild then
			local catMaster = overlay:GetChild("CategoryNavigationMaster")
			if catMaster and catMaster.GetVisible and catMaster:GetVisible() then
				return true
			end
		end
	end
	return false
end

-- References to UI Actors
local mainContainer = nil
local queryTextActor = nil
local placeholderTextActor = nil
local countTextActor = nil
local noResultsActor = nil
local rowActors = {}
for r = 1, maxRows do
	rowActors[r] = {}
end
local detailsPanel = {}

-- Map of Difficulty names to 1-5 keys
local diffKeyMap = {
	["1"] = "Difficulty_Beginner",
	["2"] = "Difficulty_Easy",
	["3"] = "Difficulty_Medium",
	["4"] = "Difficulty_Hard",
	["5"] = "Difficulty_Challenge",
}

-- Refresh UI Rows
local function RefreshResultsUI()
	if not mainContainer then return end

	-- Update Query Text & Placeholder
	if queryTextActor then
		if #searchQuery == 0 then
			queryTextActor:visible(false)
			if placeholderTextActor then placeholderTextActor:visible(true) end
		else
			queryTextActor:visible(true)
			if placeholderTextActor then placeholderTextActor:visible(false) end
			queryTextActor:settext(searchQuery)
		end
	end

	-- Update Match Counter
	if countTextActor then
		if #searchQuery == 0 then
			local hasRecents = (#candidates > 0 and candidates[1].isRecent)
			if hasRecents then
				countTextActor:settext(string.format("Recents & %d Total", totalMatches))
				countTextActor:diffuse(color("#ffcc66"))
			else
				countTextActor:settext(totalMatches .. " Total Songs")
				countTextActor:diffuse(color("#88aaff"))
			end
		elseif totalMatches == 0 then
			countTextActor:settext("0 Results Found")
			countTextActor:diffuse(Color.Red)
		else
			if historyIndex > 0 then
				countTextActor:settext(string.format("%d of %d (Hist #%d)", selectedIndex, totalMatches, historyIndex))
				countTextActor:diffuse(color("#ffaa55"))
			else
				countTextActor:settext(string.format("%d of %d Results", selectedIndex, totalMatches))
				countTextActor:diffuse(color("#88ff88"))
			end
		end
	end

	-- Update Empty State Message
	if noResultsActor then
		if totalMatches == 0 and #searchQuery > 0 then
			noResultsActor:visible(true)
			noResultsActor:settext(string.format("No songs matching \"%s\"\n\nSearch by Title, Artist (a:), Pack/Album (p:),\nAuthor/StepArtist (c:), Genre (g:), or Difficulty (d:10-12)", searchQuery))
		else
			noResultsActor:visible(false)
		end
	end

	-- Adjust viewport
	if selectedIndex < topVisibleIndex then
		topVisibleIndex = selectedIndex
	elseif selectedIndex >= topVisibleIndex + maxRows then
		topVisibleIndex = selectedIndex - maxRows + 1
	end

	-- Update Row Actors
	for r = 1, maxRows do
		local row = rowActors[r]
		local itemIdx = topVisibleIndex + r - 1
		local item = candidates[itemIdx]

		if row then
			if item then
				row.container:visible(true)
				local isSelected = (itemIdx == selectedIndex)

				-- Selection highlight & left accent indicator
				if isSelected then
					row.highlight:visible(true)
					row.highlight:diffuse(GetCurrentColor()):diffusealpha(0.35)
					if row.leftPill then
						row.leftPill:visible(true)
						row.leftPill:diffuse(GetCurrentColor())
					end
					row.title:diffuse(Color.White)
				else
					row.highlight:visible(false)
					if row.leftPill then row.leftPill:visible(false) end
					row.title:diffuse(color("#dddddd"))
				end

				-- Text labels
				row.title:settext(item.title)
				row.artist:settext(item.artist)
				if item.isRecent and #searchQuery == 0 then
					row.group:settext("[Recent] " .. item.group)
					row.group:diffuse(color("#ffdd77"))
				else
					row.group:settext("[" .. item.group .. "]")
					row.group:diffuse(color("#aaaaaa"))
				end

				-- BPM display
				local bpms = item.bpms
				if bpms and #bpms >= 2 then
					if bpms[1] == bpms[2] then
						row.bpm:settext(string.format("%.0f", bpms[1]))
					else
						row.bpm:settext(string.format("%.0f-%.0f", bpms[1], bpms[2]))
					end
				else
					row.bpm:settext("")
				end

				-- Difficulty Pill summary
				local mList = item.meterList
				local diffStr = ""
				if mList and #mList > 0 then
					for m = 1, math.min(#mList, 5) do
						diffStr = diffStr .. tostring(mList[m]) .. " "
					end
				end
				row.diffs:settext(diffStr)
			else
				row.container:visible(false)
			end
		end
	end

	-- Update Details Panel for selected item
	local selectedItem = candidates[selectedIndex]
	if detailsPanel and selectedItem then
		detailsPanel.container:visible(true)
		detailsPanel.title:settext(selectedItem.title)
		detailsPanel.artist:settext(selectedItem.artist)
		detailsPanel.pack:settext("Pack: " .. selectedItem.group)

		if detailsPanel.stepartist then
			if selectedItem.authors_display and #selectedItem.authors_display > 0 then
				detailsPanel.stepartist:visible(true)
				detailsPanel.stepartist:settext("Steps: " .. selectedItem.authors_display)
			else
				detailsPanel.stepartist:visible(false)
			end
		end

		if detailsPanel.genre then
			if selectedItem.genre and #selectedItem.genre > 0 then
				detailsPanel.genre:visible(true)
				detailsPanel.genre:settext("Genre: " .. selectedItem.genre)
			else
				detailsPanel.genre:visible(false)
			end
		end

		if selectedItem.song and selectedItem.song.GetBannerPath then
			local bPath = selectedItem.song:GetBannerPath()
			if bPath and bPath ~= "" then
				detailsPanel.banner:visible(true)
				detailsPanel.banner:Load(bPath)
				detailsPanel.banner:scaletoclipped(210, 80)
			else
				detailsPanel.banner:visible(false)
			end
		end

		local lenSec = selectedItem.length or 0
		local m = math.floor(lenSec / 60)
		local s = math.floor(lenSec % 60)
		local bpmStr = ""
		local bpms = selectedItem.bpms
		if bpms and #bpms >= 2 then
			if bpms[1] == bpms[2] then
				bpmStr = string.format("  BPM: %.0f", bpms[1])
			else
				bpmStr = string.format("  BPM: %.0f-%.0f", bpms[1], bpms[2])
			end
		end
		detailsPanel.meta:settext(string.format("Length: %d:%02d%s", m, s, bpmStr))
	elseif detailsPanel then
		detailsPanel.container:visible(false)
	end
end

-- Perform search and update UI
local function ExecuteSearch(newQuery)
	searchQuery = newQuery or ""
	candidates, totalMatches = SongSearchEngine.Search(searchQuery, 100)
	selectedIndex = 1
	topVisibleIndex = 1
	RefreshResultsUI()

	-- Trigger debounced audio preview
	if mainContainer then
		mainContainer:stoptweening()
		mainContainer:sleep(0.15)
		mainContainer:queuecommand("TriggerAudioPreview")
	end
end

-- Navigate search history (direction: 1 = older, -1 = newer)
local function StepHistory(direction)
	local history = SongSearchEngine.GetSearchHistory()
	if not history or #history == 0 then return false end

	if historyIndex == 0 and direction == 1 then
		typedQueryBeforeHistory = searchQuery
	end

	local newIdx = historyIndex + direction
	if newIdx < 0 then newIdx = 0 end
	if newIdx > #history then newIdx = #history end

	if newIdx == historyIndex then return false end
	historyIndex = newIdx

	if historyIndex == 0 then
		ExecuteSearch(typedQueryBeforeHistory)
	else
		ExecuteSearch(history[historyIndex])
	end
	return true
end

-- Open the Omnibar
local function OpenOmnibar(initialChar)
	if not ThemePrefs.Get("KeyboardFeatures") then return end
	if isOpen then return end
	isOpen = true
	KeyboardLayout.ReloadWindowsLayout()
	historyIndex = 0
	typedQueryBeforeHistory = ""
	searchQuery = initialChar or ""

	-- Redirect input so wheel doesn't scroll behind us
	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, true)
	end

	if mainContainer then
		mainContainer:visible(true)
	end

	MESSAGEMAN:Broadcast("ShowOmnibar")
	ExecuteSearch(searchQuery)
end

-- Close the Omnibar
local function CloseOmnibar()
	if not isOpen then return end
	isOpen = false

	-- Restore input back to engine
	for pn in ivalues(PlayerNumber) do
		SCREENMAN:set_input_redirected(pn, false)
	end

	if mainContainer then
		mainContainer:visible(false)
		mainContainer:stoptweening()
	end

	stop_music()
	lastPreviewSong = nil

	MESSAGEMAN:Broadcast("HideOmnibar")
end

-- Select the highlighted song and jump wheel
local function SelectSongAndClose(directPlay)
	local selected = candidates[selectedIndex]
	if not selected or not selected.song then
		CloseOmnibar()
		return
	end

	local song = selected.song
	GAMESTATE:SetPreferredSong(song)
	GAMESTATE:SetCurrentSong(song)
	SongSearchEngine.AddRecentSong(song)
	if #searchQuery > 0 then
		SongSearchEngine.AddSearchHistory(searchQuery)
	end
	CloseOmnibar()

	local topScreen = SCREENMAN:GetTopScreen()
	if topScreen then
		local curSort = GAMESTATE:GetSortOrder()
		if curSort == "SortOrder_Preferred" or curSort == "SortOrder_Popularity" or curSort == "SortOrder_Recent" then
			if topScreen.GetMusicWheel and topScreen:GetMusicWheel() then
				topScreen:GetMusicWheel():ChangeSort("SortOrder_Group")
			end
		end

		local wheel = topScreen.GetMusicWheel and topScreen:GetMusicWheel()
		local selectedViaWheel = false
		if wheel and wheel.SelectSong then
			if wheel.SetOpenSection and song.GetGroupName then
				wheel:SetOpenSection(song:GetGroupName())
			end
			selectedViaWheel = wheel:SelectSong(song)
		end

		if directPlay then
			topScreen:StartTransitioningScreen("SM_GoToNextScreen")
		elseif not selectedViaWheel then
			topScreen:SetNextScreenName("ScreenReloadSSM")
			topScreen:StartTransitioningScreen("SM_GoToNextScreen")
		end
	end
end

-- Jump to next or previous song pack (group)
local function JumpGroup(direction)
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.GetMusicWheel then return end
	local wheel = top:GetMusicWheel()
	if not wheel then return end

	if wheel.GetCurrentSections and wheel.GetSelectedSection and wheel.SetOpenSection then
		local sections = wheel:GetCurrentSections()
		if sections and #sections > 0 then
			local curSec = wheel:GetSelectedSection() or ""
			local curIdx = 1
			for i = 1, #sections do
				if sections[i] == curSec then
					curIdx = i
					break
				end
			end
			local nextIdx = curIdx + direction
			if nextIdx < 1 then nextIdx = #sections end
			if nextIdx > #sections then nextIdx = 1 end
			wheel:SetOpenSection(sections[nextIdx])
			SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "section music"))
			return
		end
	end

	if wheel.Move then
		wheel:Move(direction * 10)
	end
end

-- Change steps directly via hotkey (1-5)
local function SetDifficultyDirect(diffKey)
	local targetDiff = diffKeyMap[diffKey]
	if not targetDiff then return end

	local song = GAMESTATE:GetCurrentSong()
	local style = GAMESTATE:GetCurrentStyle()
	if not song or not style then return end

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
	end
end

local function KeyboardInputHandler(event)
	Trace(string.format("RAW_INPUT: type=%s button=%s devButton=%s", 
		tostring(event and event.type), 
		tostring(event and event.button), 
		tostring(event and event.DeviceInput and event.DeviceInput.button)))
	if not event or not event.DeviceInput then return false end
	if not ThemePrefs.Get("KeyboardFeatures") then return false end

	local btn = event.DeviceInput.button
	local eventType = event.type

	Trace(string.format("KEY_INPUT: type=%s btn=%s isOpen=%s", tostring(eventType), tostring(btn), tostring(isOpen)))

	-- Track Modifier Keys
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

	-----------------------------------------------------------------
	-- CASE 1: Omnibar is OPEN
	-----------------------------------------------------------------
	if isOpen then
		-- Layout Toggle via Ctrl+L or Ctrl+U while Omnibar is open
		if isCtrlHeld and (btn == "DeviceButton_l" or btn == "DeviceButton_u") then
			KeyboardLayout.CycleLayout()
			return true
		end
		-- Escape: clear query or close
		if btn == "DeviceButton_escape" then
			if #searchQuery > 0 then
				ExecuteSearch("")
			else
				CloseOmnibar()
			end
			return true
		end

		-- Enter: select song (or Shift+Enter to quick play)
		if btn == "DeviceButton_enter" then
			SelectSongAndClose(isShiftHeld)
			return true
		end

		-- Backspace: delete character
		if btn == "DeviceButton_backspace" then
			historyIndex = 0
			typedQueryBeforeHistory = ""
			if #searchQuery > 0 then
				local newQ = searchQuery:sub(1, -2)
				ExecuteSearch(newQ)
			end
			return true
		end

		-- History Navigation via Ctrl+Up or Ctrl+P
		if (btn == "DeviceButton_up" and isCtrlHeld) or (btn == "DeviceButton_p" and isCtrlHeld) then
			if StepHistory(1) then return true end
		end

		-- History Navigation via Ctrl+Down or Ctrl+N
		if (btn == "DeviceButton_down" and isCtrlHeld) or (btn == "DeviceButton_n" and isCtrlHeld) then
			if StepHistory(-1) then return true end
		end

		-- Up / Down navigation
		if btn == "DeviceButton_up" or event.GameButton == "MenuUp" or event.GameButton == "MenuLeft" then
			if selectedIndex > 1 then
				selectedIndex = selectedIndex - 1
				RefreshResultsUI()
				if mainContainer then
					mainContainer:stoptweening()
					mainContainer:sleep(0.12)
					mainContainer:queuecommand("TriggerAudioPreview")
				end
				return true
			elseif #searchQuery == 0 and selectedIndex == 1 and btn == "DeviceButton_up" then
				-- At row 1 with empty query, Up Arrow recalls previous search from history!
				if StepHistory(1) then return true end
			end
			return true
		end

		if btn == "DeviceButton_down" or event.GameButton == "MenuDown" or event.GameButton == "MenuRight" then
			if historyIndex > 0 and selectedIndex == 1 and btn == "DeviceButton_down" then
				-- In history mode, Down Arrow steps towards newer history
				if StepHistory(-1) then return true end
			end

			if selectedIndex < totalMatches then
				selectedIndex = selectedIndex + 1
				RefreshResultsUI()
				if mainContainer then
					mainContainer:stoptweening()
					mainContainer:sleep(0.12)
					mainContainer:queuecommand("TriggerAudioPreview")
				end
			end
			return true
		end

		-- Page Up / Page Down (jump 8 items)
		if btn == "DeviceButton_page up" then
			selectedIndex = math.max(1, selectedIndex - 8)
			RefreshResultsUI()
			return true
		end
		if btn == "DeviceButton_page down" then
			selectedIndex = math.min(totalMatches, selectedIndex + 8)
			RefreshResultsUI()
			return true
		end

		-- Home / End
		if btn == "DeviceButton_home" then
			selectedIndex = 1
			RefreshResultsUI()
			return true
		end
		if btn == "DeviceButton_end" then
			selectedIndex = totalMatches
			RefreshResultsUI()
			return true
		end

		-- Arcade Start / Back buttons inside Omnibar
		if event.GameButton == "Start" then
			SelectSongAndClose(false)
			return true
		elseif event.GameButton == "Back" or event.GameButton == "Select" then
			CloseOmnibar()
			return true
		end

		-- Printable character typing
		local char = KeyboardLayout.TranslateButton(btn, isShiftHeld)
		if char then
			historyIndex = 0
			typedQueryBeforeHistory = ""
			ExecuteSearch(searchQuery .. char)
			return true
		end

		-- Consume all other keyboard presses while Omnibar is active
		return true
	end

	-----------------------------------------------------------------
	-- CASE 2: Omnibar is CLOSED (ScreenSelectMusic normal state)
	-----------------------------------------------------------------
	-- If Category Navigation is active, MUST NOT intercept normal typing keys!
	-- Return false immediately so Category Navigation handles all navigation, typing, and hotkeys.
	if IsCategoryNavActive() then
		return false
	end

	local logicalChar = KeyboardLayout.TranslateButton(btn, false)
	local typedChar = KeyboardLayout.TranslateButton(btn, isShiftHeld)

	-- 1. Modified / Control Key Hotkeys (when Ctrl is held)
	if isCtrlHeld then
		-- Ctrl+L: Cycle Keyboard Layout
		if btn == "DeviceButton_l" or btn == "DeviceButton_u" or logicalChar == "l" or logicalChar == "u" then
			KeyboardLayout.CycleLayout()
			return true
		end

		-- Ctrl+F or Ctrl+K: Open Omnibar (empty)
		if btn == "DeviceButton_f" or btn == "DeviceButton_k" or logicalChar == "f" or logicalChar == "k" then
			OpenOmnibar("")
			return true
		end

		-- Ctrl+S: Cycle Sort Order
		if btn == "DeviceButton_s" or logicalChar == "s" then
			local top = SCREENMAN:GetTopScreen()
			if top and top.GetMusicWheel then
				local curSort = GAMESTATE:GetSortOrder()
				local nextSort = "SortOrder_Group"
				if curSort == "SortOrder_Group" then nextSort = "SortOrder_Title"
				elseif curSort == "SortOrder_Title" then nextSort = "SortOrder_Artist"
				elseif curSort == "SortOrder_Artist" then nextSort = "SortOrder_BPM"
				elseif curSort == "SortOrder_BPM" then nextSort = "SortOrder_Meter"
				elseif curSort == "SortOrder_Meter" then nextSort = "SortOrder_Preferred"
				else nextSort = "SortOrder_Group" end
				top:GetMusicWheel():ChangeSort(nextSort)
			end
			return true
		end

		-- Ctrl+P: Practice Mode
		if btn == "DeviceButton_p" or logicalChar == "p" then
			local top = SCREENMAN:GetTopScreen()
			if top and GAMESTATE:GetCurrentSong() then
				top:SetNextScreenName("ScreenPractice")
				top:StartTransitioningScreen("SM_GoToNextScreen")
			end
			return true
		end

		-- Ctrl+G: GrooveStats Leaderboard
		if btn == "DeviceButton_g" or logicalChar == "g" then
			local top = SCREENMAN:GetTopScreen()
			if top and top:GetChild("Overlay") then
				top:GetChild("Overlay"):playcommand("ShowLeaderboard")
			end
			return true
		end

		-- Ctrl+D or Ctrl+B: Toggle Favorite
		if btn == "DeviceButton_d" or btn == "DeviceButton_b" or logicalChar == "d" or logicalChar == "b" then
			for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
				addOrRemoveFavorite(pn)
				break
			end
			return true
		end

		-- Ctrl+1 to Ctrl+5: Direct Difficulty Selection
		local numKey = btn:match("^DeviceButton_([1-5])$") or btn:match("^DeviceButton_kp%s*([1-5])$") or btn:match("^DeviceButton_KP%s*([1-5])$")
		if numKey then
			SetDifficultyDirect(numKey)
			return true
		end

		-- Pass any other unhandled Ctrl combinations through
		return false
	end

	-- 2. Non-Ctrl Navigation Hotkeys
	-- Direct Difficulty Selection via 1-5 (top row or numpad):
	-- Numbers 1-5 change difficulty directly in wheel mode; they must NEVER hijack into search!
	local numKey = btn:match("^DeviceButton_([1-5])$") or btn:match("^DeviceButton_kp%s*([1-5])$") or btn:match("^DeviceButton_KP%s*([1-5])$")
	if numKey then
		SetDifficultyDirect(numKey)
		return true
	end

	-- Slash [/]: Open Omnibar (empty)
	if btn == "DeviceButton_slash" or btn == "DeviceButton_/" or logicalChar == "/" or typedChar == "/" then
		OpenOmnibar("")
		return true
	end

	-- [ and ]: Skip Pack (PreviousGroup / NextGroup)
	if btn == "DeviceButton_left bracket" or btn == "DeviceButton_[" then
		JumpGroup(-1)
		return true
	elseif btn == "DeviceButton_right bracket" or btn == "DeviceButton_]" then
		JumpGroup(1)
		return true
	end

	-- Space: Toggle audio sample preview
	if btn == "DeviceButton_space" then
		play_sample_music()
		return true
	end

	-- 3. INSTANT TYPE-TO-SEARCH:
	-- Only alphabetical keys [a-zA-Z] trigger instant type-to-search when Omnibar is closed.
	-- Numbers, punctuation, and other non-alpha keys do NOT hijack into search!
	if typedChar and #typedChar == 1 and typedChar:match("^[a-zA-Z]$") then
		OpenOmnibar(typedChar)
		return true
	end

	return false
end

-----------------------------------------------------------------
-- Master Actor Frame
-----------------------------------------------------------------
local boxWidth = IsUsingWideScreen() and 780 or 620
local boxHeight = 390

local af = Def.ActorFrame {
	Name = "KeyboardOmnibarRoot",
	InitCommand = function(self)
		local p1 = GAMESTATE:IsHumanPlayer(PLAYER_1)
		local p2 = GAMESTATE:IsHumanPlayer(PLAYER_2)
		local sides = GAMESTATE:GetNumSidesJoined()
		local style = GAMESTATE:GetCurrentStyle()
		Trace(string.format("DEBUG_STATE: sides=%s p1=%s p2=%s style=%s", tostring(sides), tostring(p1), tostring(p2), tostring(style and style:GetName())))
		mainContainer = self:GetChild("OmnibarModal")
		if mainContainer then
			mainContainer:visible(false)
		end
		isCatNavActive = (ThemePrefs.Get("CategoryNavigation") == true)
	end,
	OnCommand = function(self)
		isCatNavActive = (ThemePrefs.Get("CategoryNavigation") == true) or IsCategoryNavActive()
		local top = SCREENMAN:GetTopScreen()
		Trace("OMNIBAR: OnCommand top=" .. tostring(top and top:GetName()))
		if top and top.AddInputCallback then
			top:AddInputCallback(KeyboardInputHandler)
		end

		if FILEMAN:DoesFileExist("Save/run_test.flag") then
			Trace("OMNIBAR_TEST: Flag detected, starting test sequence")
			self:sleep(1.0):queuecommand("TestStepReady")
		end
	end,
	TestStepReadyCommand = function(self)
		Trace("OMNIBAR_TEST_STEP: ready")
		self:sleep(1.5):queuecommand("TestStepOpen")
	end,
	TestStepOpenCommand = function(self)
		OpenOmnibar("")
		Trace("OMNIBAR_TEST_STEP: open")
		self:sleep(1.2):queuecommand("TestStepColemak")
	end,
	TestStepColemakCommand = function(self)
		-- Verify active layout mappings
		local winName = KeyboardLayout.GetLayoutName()

		Trace(string.format("VERIFY_WINDOWS_AUTO: name=%s winO=%s winOShift=%s winP=%s",
			tostring(winName), tostring(winO), tostring(winOShift), tostring(winP)))

		Trace(string.format("VERIFY_KEYS: colemakO=%s colemakOShift=%s colemakSemi=%s colemakColon=%s qwO=%s qwColon=%s qwColonShift=%s",
			tostring(colemakO), tostring(colemakOShift), tostring(colemakSemi), tostring(colemakColon),
			tostring(qwertyO), tostring(qwertyColon), tostring(qwertyColonShift)))

		-- Simulate typing physical keys on Colemak: B, A, G (which translates to 'b', 'a', 'd'!)
		local c1 = KeyboardLayout.TranslateButton("DeviceButton_b", false)
		local c2 = KeyboardLayout.TranslateButton("DeviceButton_a", false)
		local c3 = KeyboardLayout.TranslateButton("DeviceButton_g", false)
		local typed = c1 .. c2 .. c3
		ExecuteSearch(typed)
		Trace("OMNIBAR_TEST_STEP: colemak_typed")
		self:sleep(1.2):queuecommand("TestStepSearchBad")
	end,
	TestStepSearchBadCommand = function(self)
		ExecuteSearch("bad")
		Trace("OMNIBAR_TEST_STEP: search_bad")
		self:sleep(1.2):queuecommand("TestStepSearchArtist")
	end,
	TestStepSearchArtistCommand = function(self)
		ExecuteSearch("artist:thorogood")
		Trace("OMNIBAR_TEST_STEP: search_artist")
		self:sleep(1.2):queuecommand("TestStepSearchAuthor")
	end,
	TestStepSearchAuthorCommand = function(self)
		ExecuteSearch("author:hellkite")
		Trace("OMNIBAR_TEST_STEP: search_author")
		self:sleep(1.2):queuecommand("TestStepSearchAlbum")
	end,
	TestStepSearchAlbumCommand = function(self)
		ExecuteSearch("album:80s")
		Trace("OMNIBAR_TEST_STEP: search_album")
		self:sleep(1.2):queuecommand("TestStepSearchDiff")
	end,
	TestStepSearchDiffCommand = function(self)
		ExecuteSearch("d:10-12")
		Trace("OMNIBAR_TEST_STEP: search_diff")
		self:sleep(1.2):queuecommand("TestStepSearchZero")
	end,
	TestStepSearchZeroCommand = function(self)
		ExecuteSearch("nonexistingsong123")
		Trace("OMNIBAR_TEST_STEP: search_zero")
		self:sleep(1.2):queuecommand("TestStepSelectSong")
	end,
	TestStepSelectSongCommand = function(self)
		ExecuteSearch("bad")
		SelectSongAndClose(false)
		Trace("OMNIBAR_TEST_STEP: selected")
		self:sleep(1.2):queuecommand("TestStepReopenRecents")
	end,
	TestStepReopenRecentsCommand = function(self)
		OpenOmnibar("")
		Trace("OMNIBAR_TEST_STEP: reopen_recents")
		self:sleep(1.2):queuecommand("TestStepHistoryRecall")
	end,
	TestStepHistoryRecallCommand = function(self)
		StepHistory(1)
		Trace("OMNIBAR_TEST_STEP: history_recall")
		self:sleep(1.2):queuecommand("TestStepFinish")
	end,
	TestStepFinishCommand = function(self)
		CloseOmnibar()
		if FILEMAN:DoesFileExist("Save/WindowsKeyboardLayout.lua") then
			KeyboardLayout.SetLayout("windows_auto")
		else
			KeyboardLayout.SetLayout("qwerty")
		end
		Trace("OMNIBAR_TEST_STEP: finished")
	end,
	OffCommand = function(self)
		CloseOmnibar()
		local top = SCREENMAN:GetTopScreen()
		if top and top.RemoveInputCallback then
			top:RemoveInputCallback(KeyboardInputHandler)
		end
	end,
	CategoryNavigationModeChangedMessageCommand = function(self, params)
		if params and params.active ~= nil then
			isCatNavActive = params.active
		end
	end,
	OpenOmnibarWithQueryMessageCommand = function(self, params)
		if not ThemePrefs.Get("KeyboardFeatures") then return end
		local q = ""
		if params and type(params) == "table" and params.query then
			q = tostring(params.query)
		end
		OpenOmnibar(q)
	end,
	TriggerAudioPreviewCommand = function(self)
		if not isOpen then return end
		local selected = candidates[selectedIndex]
		if selected and selected.song and selected.song ~= lastPreviewSong then
			lastPreviewSong = selected.song
			local songpath = selected.song:GetMusicPath()
			local sample_start = selected.song:GetSampleStart()
			local sample_len = selected.song:GetSampleLength()
			if songpath and sample_start and sample_len and sample_len > 0 then
				SOUND:DimMusic(PREFSMAN:GetPreference("SoundVolume"), math.huge)
				local loops = ThemePrefs.Get("SampleMusicLoops")
				if loops == nil then loops = true end
				SOUND:PlayMusicPart(songpath, sample_start, sample_len, 0.3, 1.5, loops, true)
			end
		end
	end,
}

-- Omnibar Modal Window
local modal = Def.ActorFrame {
	Name = "OmnibarModal",
	InitCommand = function(self)
		self:xy(_screen.cx, _screen.cy)
		self:draworder(250)
		self:visible(false)
	end,

	-- Fullscreen dark backdrop dimming everything smoothly
	Def.Quad {
		Name = "DimBackdrop",
		InitCommand = function(self)
			self:xy(0, 0)
			self:zoomto(_screen.w, _screen.h)
			self:diffuse(color("0, 0, 0, 0.88"))
		end,
	},

	-- Window border
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(boxWidth + 4, boxHeight + 4)
			self:diffuse(GetCurrentColor())
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor())
		end,
	},

	-- Window body
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(boxWidth, boxHeight)
			self:diffuse(color("0.05, 0.06, 0.09, 0.98"))
		end,
	},

	-- Top accent hairline
	Def.Quad {
		InitCommand = function(self)
			self:xy(0, -boxHeight / 2 + 1)
			self:zoomto(boxWidth, 2)
			self:diffuse(GetCurrentColor()):diffusealpha(0.8)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(0.8)
		end,
	},

	-- Search Header Bar Background
	Def.Quad {
		InitCommand = function(self)
			self:xy(0, -boxHeight / 2 + 25)
			self:zoomto(boxWidth - 16, 38)
			self:diffuse(color("0.10, 0.12, 0.16, 0.95"))
		end,
	},

	-- "SEARCH:" label (cleanly spaced, no overlap)
	LoadFont("Common Bold") .. {
		InitCommand = function(self)
			self:xy(-boxWidth / 2 + 20, -boxHeight / 2 + 25)
			self:horizalign(left)
			self:zoom(0.55)
			self:diffuse(GetCurrentColor())
			self:settext("SEARCH:")
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor())
		end,
	},

	-- Search input box frame quad (positioned cleanly to the right of SEARCH:)
	Def.Quad {
		InitCommand = function(self)
			local inputStartX = IsUsingWideScreen() and (-boxWidth / 2 + 165) or (-boxWidth / 2 + 155)
			local inputW = IsUsingWideScreen() and 380 or 280
			self:xy(inputStartX + inputW / 2, -boxHeight / 2 + 25)
			self:zoomto(inputW + 2, 28)
			self:diffuse(color("0.22, 0.26, 0.35, 0.70"))
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			local inputStartX = IsUsingWideScreen() and (-boxWidth / 2 + 165) or (-boxWidth / 2 + 155)
			local inputW = IsUsingWideScreen() and 380 or 280
			self:xy(inputStartX + inputW / 2, -boxHeight / 2 + 25)
			self:zoomto(inputW, 26)
			self:diffuse(color("0.04, 0.05, 0.07, 0.96"))
		end,
	},

	-- Placeholder Text
	LoadFont("Common Normal") .. {
		Name = "PlaceholderText",
		InitCommand = function(self)
			local inputStartX = IsUsingWideScreen() and (-boxWidth / 2 + 165) or (-boxWidth / 2 + 155)
			local inputW = IsUsingWideScreen() and 380 or 280
			placeholderTextActor = self
			self:xy(inputStartX + 10, -boxHeight / 2 + 25)
			self:horizalign(left)
			self:zoom(0.60)
			self:maxwidth((inputW - 20) / 0.60)
			self:diffuse(color("#556677"))
			self:settext("Type song, artist, pack, or diff (d:10)...")
		end,
	},

	-- Live Query Text
	LoadFont("Common Normal") .. {
		Name = "QueryText",
		InitCommand = function(self)
			local inputStartX = IsUsingWideScreen() and (-boxWidth / 2 + 165) or (-boxWidth / 2 + 155)
			local inputW = IsUsingWideScreen() and 380 or 280
			queryTextActor = self
			self:xy(inputStartX + 10, -boxHeight / 2 + 25)
			self:horizalign(left)
			self:zoom(0.72)
			self:maxwidth((inputW - 20) / 0.72)
			self:diffuse(Color.White)
			self:settext("")
		end,
	},

	-- Match Count Text
	LoadFont("Common Normal") .. {
		Name = "CountText",
		InitCommand = function(self)
			countTextActor = self
			self:xy(boxWidth / 2 - 20, -boxHeight / 2 + 25)
			self:horizalign(right)
			self:zoom(0.68)
			self:diffuse(color("#88aaff"))
			self:settext("0 Results")
		end,
	},

	-- Empty state helper text
	LoadFont("Common Normal") .. {
		Name = "NoResultsMessage",
		InitCommand = function(self)
			noResultsActor = self
			self:xy(-boxWidth / 4 + 20, 0)
			self:zoom(0.72)
			self:diffuse(color("#8899aa"))
			self:visible(false)
		end,
	},

	-- Footer Key Legend
	Def.Quad {
		InitCommand = function(self)
			self:xy(0, boxHeight / 2 - 16)
			self:zoomto(boxWidth, 28)
			self:diffuse(color("0.08, 0.09, 0.12, 0.95"))
		end,
	},

	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(0, boxHeight / 2 - 16)
			self:zoom(0.56)
			self:diffuse(color("#bbbbbb"))
			self:settext("[ ↑ / ↓ ] Navigate   |   [ Ctrl+↑ / ↓ ] History   |   [ Enter ] Select   |   [ Esc ] Close")
		end,
	},
}

-- 10 Rows for Results List
local rowStartX = -boxWidth / 2 + 16
local rowStartY = -boxHeight / 2 + 65
local rowHeight = 28
local rowWidth = IsUsingWideScreen() and 500 or 380

for r = 1, maxRows do
	local yPos = rowStartY + (r - 1) * rowHeight

	local rowFrame = Def.ActorFrame {
		Name = "Row_" .. r,
		InitCommand = function(self)
			rowActors[r].container = self
			self:xy(rowStartX, yPos)
			self:visible(false)
		end,

		-- Row highlight Quad
		Def.Quad {
			InitCommand = function(self)
				rowActors[r].highlight = self
				self:xy(rowWidth / 2, 0)
				self:zoomto(rowWidth, rowHeight - 2)
				self:diffuse(GetCurrentColor()):diffusealpha(0.35)
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor()):diffusealpha(0.35)
			end,
		},

		-- Row Left Accent Indicator (3px wide)
		Def.Quad {
			InitCommand = function(self)
				rowActors[r].leftPill = self
				self:xy(1.5, 0)
				self:zoomto(3, rowHeight - 2)
				self:diffuse(GetCurrentColor())
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Row Title
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				rowActors[r].title = self
				self:xy(10, 0)
				self:horizalign(left)
				self:zoom(0.68)
				local maxW = IsUsingWideScreen() and 170 or 125
				self:maxwidth(maxW / 0.68)
				self:diffuse(Color.White)
			end,
		},

		-- Row Artist
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				rowActors[r].artist = self
				local xA = IsUsingWideScreen() and 190 or 140
				self:xy(xA, 0)
				self:horizalign(left)
				self:zoom(0.58)
				local maxW = IsUsingWideScreen() and 90 or 65
				self:maxwidth(maxW / 0.58)
				self:diffuse(color("#aaaaaa"))
			end,
		},

		-- Row Pack
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				rowActors[r].group = self
				local xG = IsUsingWideScreen() and 290 or 210
				self:xy(xG, 0)
				self:horizalign(left)
				self:zoom(0.52)
				local maxW = IsUsingWideScreen() and 90 or 65
				self:maxwidth(maxW / 0.52)
				self:diffuse(color("#77bbff"))
			end,
		},

		-- Row BPM
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				rowActors[r].bpm = self
				local xB = IsUsingWideScreen() and 420 or 310
				self:xy(xB, 0)
				self:horizalign(right)
				self:zoom(0.52)
				self:maxwidth(45 / 0.52)
				self:diffuse(color("#bbbbbb"))
			end,
		},

		-- Row Difficulties
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				rowActors[r].diffs = self
				local xD = IsUsingWideScreen() and 492 or 372
				self:xy(xD, 0)
				self:horizalign(right)
				self:zoom(0.52)
				self:maxwidth(65 / 0.52)
				self:diffuse(GetCurrentColor())
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},
	}

	modal[#modal + 1] = rowFrame
end

-- Details Panel on Right Side
local detailsX = boxWidth / 2 - (IsUsingWideScreen() and 125 or 105)
local detailsY = -boxHeight / 2 + 50

local detailsFrame = Def.ActorFrame {
	Name = "DetailsPanel",
	InitCommand = function(self)
		detailsPanel.container = self
		self:xy(detailsX, detailsY)
	end,

	-- Divider line
	Def.Quad {
		InitCommand = function(self)
			local divX = IsUsingWideScreen() and -125 or -105
			self:xy(divX, 120)
			self:zoomto(1.5, 275)
			self:diffuse(color("1,1,1,0.15"))
		end,
	},

	-- Banner
	Def.Sprite {
		Name = "DetailBanner",
		InitCommand = function(self)
			detailsPanel.banner = self
			self:xy(0, 48)
			self:setsize(218, 84)
		end,
	},

	-- Title
	LoadFont("Common Bold") .. {
		InitCommand = function(self)
			detailsPanel.title = self
			self:xy(0, 102)
			self:zoom(0.74)
			self:maxwidth(215 / 0.74)
			self:diffuse(Color.White)
		end,
	},

	-- Artist
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			detailsPanel.artist = self
			self:xy(0, 122)
			self:zoom(0.62)
			self:maxwidth(215 / 0.62)
			self:diffuse(color("#99aacc"))
		end,
	},

	-- Pack
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			detailsPanel.pack = self
			self:xy(0, 140)
			self:zoom(0.58)
			self:maxwidth(215 / 0.58)
			self:diffuse(color("#66ccff"))
		end,
	},

	-- Stepartist / Author
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			detailsPanel.stepartist = self
			self:xy(0, 158)
			self:zoom(0.55)
			self:maxwidth(215 / 0.55)
			self:diffuse(color("#ffcc66"))
		end,
	},

	-- Genre
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			detailsPanel.genre = self
			self:xy(0, 175)
			self:zoom(0.55)
			self:maxwidth(215 / 0.55)
			self:diffuse(color("#bbaaff"))
		end,
	},

	-- Meta (Length & BPM)
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			detailsPanel.meta = self
			self:xy(0, 194)
			self:zoom(0.58)
			self:maxwidth(215 / 0.58)
			self:diffuse(color("#aaaaaa"))
		end,
	},
}

modal[#modal + 1] = detailsFrame
af[#af + 1] = modal

return af
