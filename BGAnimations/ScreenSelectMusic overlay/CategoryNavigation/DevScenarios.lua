-- DevScenarios.lua
-- DEV-ONLY engine-state scenario driver for Keyboard Mode (Category Navigation + Omnibar).
-- Loaded only when Save/dev_scenarios.flag exists AND this file exists. It is never deployed
-- to the cabinet. The flag file's content selects the scenario. Output is Trace() lines
-- prefixed "KBDTEST " that tests/keyboard_mode/run_scenarios.py parses and asserts on.
--
-- Unlike handler-return-value tests, every assertion here reads ENGINE state:
-- GAMESTATE current song, SCREENMAN input redirection, screen name, player join state.

local api = SL.Global.KbdModeAPI
local name = (lua.ReadFile("Save/dev_scenarios.flag") or ""):gsub("%s+", "")

local function T(fmt, ...)
	Trace("KBDTEST " .. string.format(fmt, ...))
end

local function findSong(title)
	for s in ivalues(SONGMAN:GetAllSongs()) do
		if s:GetDisplayFullTitle() == title then return s end
	end
end

local function engineTitle()
	local s = GAMESTATE:GetCurrentSong()
	return s and s:GetDisplayFullTitle() or "<nil>"
end

local function snap(label)
	local st = api.catnav.State()
	local ob = api.omnibar.IsOpen()
	T('SNAP label=%s mode=%s highlighted="%s" engine="%s" synced=%s idx=%d/%d redirP1=%s redirP2=%s omnibar=%s',
		label, st.active and "KEYBOARD" or "WHEEL", tostring(st.selectedTitle), engineTitle(),
		tostring(st.selectedTitle == engineTitle()), st.selectedIdx or 0, st.total or 0,
		tostring(SCREENMAN:get_input_redirected(PLAYER_1)), tostring(SCREENMAN:get_input_redirected(PLAYER_2)),
		tostring(ob))
end

-- Type of the row the wheel is DISPLAYING at its centre (not merely its selection index), and
-- the number of row actors. Self-contained so it also works against code without WheelSync.
-- WheelItemDataType numbers: 0 Generic, 1 Section, 2 ParentSection, 3 Song.
local function centerRow(wheel)
	local n = 0
	while n < 64 do
		local ok = pcall(wheel.GetWheelItem, wheel, n)
		if not ok then break end
		n = n + 1
	end
	if n == 0 then return "none", 0, "" end
	local item = wheel:GetWheelItem(math.floor(n / 2))
	local ok, ty = pcall(item.GetType, item)
	local okT, title = pcall(function() return item:GetChild("SongName"):GetChild("Title"):GetText() end)
	return ok and tostring(ty) or "unloaded", n, (okT and title) or ""
end

local function logCenter(label)
	local wheel = SCREENMAN:GetTopScreen():GetMusicWheel()
	local ty, n, shown = centerRow(wheel)
	local cur = GAMESTATE:GetCurrentSong()
	local want = cur and cur:GetDisplayMainTitle() or ""
	T('WHEELCENTER label=%s center_type=%s rows=%d selected_type=%s engine="%s" displayed="%s" displayed_is_engine_song=%s',
		label, ty, n, tostring(wheel:GetSelectedType()), engineTitle(), shown, tostring(shown ~= "" and shown == want))
end

-- put the NATIVE wheel on a song exactly as a player scrolling to it would
local function landOnWheel(title)
	local song = findSong(title)
	if not song then T("ERROR song_not_found=%s", title) return end
	local top = SCREENMAN:GetTopScreen()
	local wheel = top:GetMusicWheel()
	GAMESTATE:SetPreferredSong(song)
	GAMESTATE:SetCurrentSong(song)
	wheel:SelectSong(song)
	top:PostScreenMessage("SM_SongChanged", 0)
end

local function ev(btn, gb, kind)
	return {
		type = kind or "InputEventType_FirstPress",
		DeviceInput = { button = btn },
		button = gb or "", GameButton = gb or "",
		PlayerNumber = "PlayerNumber_P1",
	}
end

-- model the engine: callbacks run in map order and stop at the first that returns true
local function deliver(order, e)
	for _, h in ipairs(order) do
		if h(e) then return true end
	end
	return false
end
local function deliverAll(order, e)
	for _, h in ipairs(order) do h(e) end
end

local steps = {}
local function step(wait, fn) steps[#steps + 1] = { wait = wait, fn = fn } end
local function shot(label) T("SHOT %s", label) end

-- ---------------------------------------------------------------------------
if name == "enter" then
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.5, function() snap("wheel_on_song") end)
	step(1.4, function() shot("wheel_on_song") end)
	step(1.2, function() api.catnav.Enter() end)
	step(0.5, function() snap("keyboard_entered") end)
	step(1.4, function() shot("keyboard_entered") end)

elseif name == "omnibar" then
	step(1.0, function() landOnWheel("Danger Zone") end)
	step(0.8, function() api.catnav.Enter() end)
	step(0.8, function()
		local chips = api.engine.GetSubChips("packs")
		local idx = 1
		for i, c in ipairs(chips) do if c.id == "Fraxtil's Beast Beats" then idx = i end end
		api.catnav.SetCategory(1, idx)
	end)
	step(0.5, function() snap("keyboard_other_pack") end)
	step(0.2, function() api.omnibar.Open("") end)
	step(0.5, function() api.omnibar.Query("danger zone") end)
	step(1.4, function() shot("omnibar_open") end)
	step(0.2, function() api.omnibar.SelectCurrent(false) end)
	step(1.2, function() snap("after_omnibar_return") end)
	step(1.4, function() shot("after_omnibar_return") end)

elseif name == "start" then
	-- Keyboard-mode Start must go through ScreenSelectMusic::MenuStart: the engine finalizes the
	-- selection, shows "Press START for options" (OPTIONS_PROMPT below) and gives input back to
	-- the engine so a second Start opens Player Options.
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.8, function() api.catnav.Enter() end)
	step(0.8, function() snap("before_start") end)
	step(0.0, function()
		T("EVENT start_pressed")
		api.catnav.Handle(ev("DeviceButton_enter", "Start"))
	end)
	step(0.15, function() snap("start_t+150ms") end)
	step(0.35, function() snap("start_t+500ms") shot("options_prompt") end)
	step(0.9, function()
		snap("start_t+1400ms")
		T("RECENT first=%s", tostring((api.search.GetRecentSongDirs() or {})[1]))
	end)

elseif name == "omnibar_play" then
	-- Omnibar quick play (Shift+Enter) from wheel mode must take the same engine path.
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.5, function() api.omnibar.Open("") end)
	step(0.5, function() api.omnibar.Query("danger zone") end)
	step(0.5, function()
		T("EVENT quick_play")
		api.omnibar.SelectCurrent(true)
	end)
	step(0.5, function()
		local w = SCREENMAN:GetTopScreen():GetMusicWheel()
		T("QUICKPLAY t+500ms engine=\"%s\" wheel_type=%s redirP1=%s screen=%s", engineTitle(),
			tostring(w:GetSelectedType()), tostring(SCREENMAN:get_input_redirected(PLAYER_1)),
			tostring(SCREENMAN:GetTopScreen():GetName()))
		shot("quick_play_prompt")
	end)

elseif name == "reload" then
	-- A FULL song reload (SongManager::Reload -> FreeSongs) with an unchanged song count.
	-- The sandbox's _fallback metrics send ScreenReloadSongs back to ScreenSelectMusic.
	-- Stage 2 never dereferences a cached Song: it only compares userdata pointers.
	local stage = SL.Global.DevReloadStage or 1
	if stage == 1 then
		step(0.8, function() api.catnav.Enter() end)
		step(0.5, function()
			local idx = api.search.GetIndex()
			SL.Global.DevReloadFirst = { group = idx[1].group, folder = idx[1].folder }
			SL.Global.DevReloadStage = 2
			T("RELOAD stage=1 index=%d first=%s/%s", #idx, idx[1].group, idx[1].folder)
			-- A real reload goes through the title menu, which resets game state. This shortcut
			-- does not, so drop the engine's own references to songs that are about to be freed.
			GAMESTATE:SetCurrentSong(nil)
			GAMESTATE:SetPreferredSong(nil)
			for pn in ivalues(PlayerNumber) do GAMESTATE:SetCurrentSteps(pn, nil) end
			SCREENMAN:SetNewScreen("ScreenReloadSongs")
		end)
	else
		local first = SL.Global.DevReloadFirst
		step(1.0, function()
			local live = SONGMAN:FindSong(first.group .. "/" .. first.folder)
			local idx = api.search.GetIndex()
			T("RELOAD stage=2 index=%d first_song_is_live=%s", #idx, tostring(idx[1].song == live))
		end)
	end

elseif name == "played_fx" then
	-- Building the PLAYED category must not insert score entries into the profile.
	step(0.8, function() api.catnav.Enter() end)
	step(0.5, function()
		local song = findSong("Conga!")
		local st = GAMESTATE:GetCurrentStyle():GetStepsType()
		local steps = song:GetStepsByStepsType(st)[1]
		local prof = PROFILEMAN:GetMachineProfile()
		local before = prof:GetHighScoreListIfExists(song, steps)
		api.engine.InvalidatePlayCache()
		local n = #api.engine.GetSongs("played", "all")
		local after = prof:GetHighScoreListIfExists(song, steps)
		T("PLAYEDFX entry_before=%s entry_after=%s played=%d", tostring(before ~= nil), tostring(after ~= nil), n)
	end)

elseif name == "ctrl_l" then
	-- Run with Save/WindowsKeyboardLayout.lua hidden (run_scenarios.py --hide-save-file).
	step(0.5, function()
		local h = api.omnibar.Handle
		for i = 1, 5 do
			h(ev("DeviceButton_left ctrl"))
			local ok, err = pcall(h, ev("DeviceButton_l"))
			h(ev("DeviceButton_left ctrl", "", "InputEventType_Release"))
			T("CTRL_L press=%d ok=%s layout=%s err=\"%s\"", i, tostring(ok), tostring(ThemePrefs.Get("KeyboardLayout")), tostring(ok and "" or err))
		end
	end)

elseif name == "ctrl_g" then
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.5, function()
		local h = api.omnibar.Handle
		h(ev("DeviceButton_left ctrl"))
		h(ev("DeviceButton_g"))
		h(ev("DeviceButton_left ctrl", "", "InputEventType_Release"))
		local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay")
		local lb = overlay:GetChild("LeaderboardMaster")
		T("CTRL_G leaderboard_visible=%s redirP1=%s redirP2=%s", tostring(lb and lb:GetVisible()),
			tostring(SCREENMAN:get_input_redirected(PLAYER_1)), tostring(SCREENMAN:get_input_redirected(PLAYER_2)))
	end)
	step(0.4, function()
		-- typing while the leaderboard is up must not open the Omnibar on top of it
		api.omnibar.Handle(ev("DeviceButton_a"))
		T("CTRL_G typing_opened_omnibar=%s", tostring(api.omnibar.IsOpen()))
		if api.omnibar.IsOpen() then api.omnibar.Close() end
	end)
	step(1.0, function() shot("leaderboard") end)

elseif name == "jump_group" then
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.8, function()
		local groups = SONGMAN:GetSongGroupNames()
		local cur = GAMESTATE:GetCurrentSong():GetGroupName()
		local ci = 1
		for i, g in ipairs(groups) do if g == cur then ci = i end end
		T("JUMP before group=\"%s\" expect_next=\"%s\"", cur, groups[(ci % #groups) + 1])
		api.omnibar.Handle(ev("DeviceButton_right bracket"))
	end)
	step(0.8, function()
		local w = SCREENMAN:GetTopScreen():GetMusicWheel()
		local s = GAMESTATE:GetCurrentSong()
		T("JUMP after engine=\"%s\" group=\"%s\" wheel_type=%s", engineTitle(), s and s:GetGroupName() or "<nil>", tostring(w:GetSelectedType()))
		logCenter("after_jump")
	end)
	step(1.4, function() shot("after_jump") end)

elseif name == "exit_visual" then
	-- Move the cursor in Keyboard Mode, then return to the wheel: the wheel must DISPLAY the
	-- song the engine is on, not the arrangement it had before Keyboard Mode.
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.8, function() api.catnav.Enter() end)
	step(0.8, function()
		local st = api.catnav.State()
		for k = 1, 6 do api.catnav.SelectIndex(st.selectedIdx + k) end
	end)
	step(0.6, function() snap("keyboard_moved") end)
	step(0.2, function() api.catnav.Exit() end)
	step(0.8, function()
		T('EXITVISUAL engine="%s"', engineTitle())
		logCenter("after_exit")
	end)
	step(1.4, function() shot("after_exit") end)

elseif name == "omnibar_wheel" then
	-- Omnibar search selection from plain wheel mode (the stock wheel is visible).
	step(1.0, function() landOnWheel("Conga!") end)
	step(0.5, function() api.omnibar.Open("") end)
	step(0.5, function() api.omnibar.Query("danger zone") end)
	step(0.2, function() api.omnibar.SelectCurrent(false) end)
	step(0.8, function()
		T('OMNIBARWHEEL engine="%s"', engineTitle())
		logCenter("after_omnibar_select")
	end)
	step(1.4, function() shot("after_omnibar_select") end)

elseif name == "arbit" then
	local catH, omniH = api.catnav.Handle, api.omnibar.Handle
	local function reset()
		if api.omnibar.IsOpen() then api.omnibar.Close() end
		if api.catnav.State().active then api.catnav.Exit() end
	end
	local function run(order, label)
		reset()
		-- Case 1: Tab pressed while the Omnibar is open (from wheel mode)
		api.omnibar.Open("")
		deliver(order, ev("DeviceButton_tab", "Select"))
		T("ARBIT case=tab_while_omnibar_open order=%s omnibar_open=%s catnav_active=%s",
			label, tostring(api.omnibar.IsOpen()), tostring(api.catnav.State().active))
		reset()
		-- Case 2: Ctrl+K in wheel mode
		deliverAll(order, ev("DeviceButton_left ctrl"))
		deliver(order, ev("DeviceButton_k"))
		T("ARBIT case=ctrl_k_in_wheel_mode order=%s omnibar_open=%s catnav_active=%s",
			label, tostring(api.omnibar.IsOpen()), tostring(api.catnav.State().active))
		deliverAll(order, ev("DeviceButton_left ctrl", "", "InputEventType_Release"))
		reset()
	end
	step(0.5, function() run({ catH, omniH }, "catnav_first") end)
	step(0.5, function() run({ omniH, catH }, "omnibar_first") end)

elseif name == "cats" then
	step(0.8, function() api.catnav.Enter() end)
	step(0.6, function()
		local cats = api.engine.GetCategories()
		for ci = 1, #cats do
			local cat = cats[ci]
			local chips = api.engine.GetSubChips(cat.id)
			for k, chip in ipairs(chips) do
				if cat.id ~= "packs" or k <= 2 then
					T("COUNT cat=%s name=%s chip=%s n=%d", cat.id, cat.name, chip.id, #api.engine.GetSongs(cat.id, chip.id))
				end
			end
		end
	end)
	step(0.5, function()
		-- BPM tier boundary probe using synthetic index rows (removed afterwards)
		local idxTbl = api.search.GetIndex()
		local probes = { 129.5, 130, 155, 180, 210 }
		local added = {}
		for _, b in ipairs(probes) do
			local e = { title = "__BPM" .. b, title_lower = "__bpm" .. b, group = "__T", group_lower = "__t",
				bpms = { b, b }, meterList = {}, meters = {}, song_dir = "/__T/bpm" .. b .. "/" }
			idxTbl[#idxTbl + 1] = e
			added[#added + 1] = e
		end
		for _, b in ipairs(probes) do
			local inTiers = {}
			for _, chip in ipairs(api.engine.GetSubChips("bpm")) do
				if chip.id ~= "all" then
					for _, r in ipairs(api.engine.GetSongs("bpm", chip.id)) do
						if r.title == "__BPM" .. b then inTiers[#inTiers + 1] = chip.id end
					end
				end
			end
			T("BPMPROBE bpm=%s tiers=%s", tostring(b), table.concat(inTiers, ","))
		end
		for i = #idxTbl, 1, -1 do
			for _, e in ipairs(added) do if idxTbl[i] == e then table.remove(idxTbl, i) break end end
		end
	end)
	step(0.5, function()
		-- Favorites probe: one real favorite + a same-titled song in another pack
		local real = findSong("Conga!")
		local dup = { title = "Conga!", title_lower = "conga!", group = "ZZ Other Pack", group_lower = "zz other pack",
			folder = "Other Conga", bpms = { 100, 100 }, meterList = {}, meters = {}, song_dir = "/Songs/ZZ Other Pack/Other Conga/" }
		local idxTbl = api.search.GetIndex()
		idxTbl[#idxTbl + 1] = dup
		local oldFav = SL.P1.Favorites
		SL.P1.Favorites = { real }
		-- The sandbox has no persistent profile, so point the (global) favorites path helper at a
		-- file we control. File-based engines read it; Song-object engines read SL.P1.Favorites.
		local oldPathFn = getFavoritesPath
		local path = "Save/dev_favorites.txt"
		getFavoritesPath = function() return path end
		local parts = {}
		for p in real:GetSongDir():gmatch("[^/]+") do parts[#parts + 1] = p end
		local f = RageFileUtil.CreateRageFile()
		if f:Open(path, 2) then f:Write(parts[2] .. "/" .. parts[3] .. string.char(10)) f:Close() f:destroy() end
		local res = api.engine.GetSongs("favorites", "p1_fav")
		local groups = {}
		for _, r in ipairs(res) do groups[#groups + 1] = r.title .. "@" .. tostring(r.group) end
		T("FAVPROBE n=%d truth=1 rows=%s", #res, table.concat(groups, " | "))
		for i = #idxTbl, 1, -1 do if idxTbl[i] == dup then table.remove(idxTbl, i) end end
		SL.P1.Favorites = oldFav
		getFavoritesPath = oldPathFn
		local clr = RageFileUtil.CreateRageFile()
		if clr:Open(path, 2) then clr:Write("") clr:Close() clr:destroy() end
	end)
	step(0.4, function() api.catnav.SetCategory(3, 5) end)
	step(0.6, function() snap("meters_13_14") end)
	step(1.4, function() shot("meters_13_14") end)
	step(0.2, function()
		local cats = api.engine.GetCategories()
		for ci = 1, #cats do if cats[ci].id == "groovestats" or cats[ci].id == "played" then api.catnav.SetCategory(ci, 2) end end
	end)
	step(0.6, function() snap("ranked_or_played_tab2") end)
	step(1.4, function() shot("ranked_or_played_tab2") end)

elseif name == "perf" then
	step(0.8, function() api.catnav.Enter() end)
	step(1.0, function()
		local t0 = GetTimeSinceStart()
		for i = 1, 60 do api.catnav.SelectIndex(1 + (i % 40)) end
		local t1 = GetTimeSinceStart()
		T("PERF moves=60 sync_loop_ms=%.1f per_move_ms=%.2f songs=%d", (t1 - t0) * 1000, (t1 - t0) * 1000 / 60, #SONGMAN:GetAllSongs())
	end)

elseif name == "index" then
	-- stage 1: first entry; stage 2: re-enter the screen (as after every song)
	local stage = SL.Global.DevIndexStage or 1
	T("INDEX stage=%d", stage)
	step(0.8, function() api.catnav.Enter() end)
	step(0.8, function() api.omnibar.Open("") end)
	step(0.8, function() api.omnibar.Close() end)
	step(0.5, function()
		if stage == 1 then
			SL.Global.DevIndexStage = 2
			SCREENMAN:SetNewScreen("ScreenSelectMusic")
		end
	end)

elseif name == "guard" then
	-- PreferredStyle=single. Calls the overlay's join-resolution function directly (the harness
	-- boots with TestInitialScreen, whose ScreenSelectMusic::Init forces master=P1 on every entry).
	local function setup(order)
		for pn in ivalues(PlayerNumber) do GAMESTATE:UnjoinPlayer(pn) end
		for _, pn in ipairs(order) do GAMESTATE:JoinPlayer(pn) end
	end
	local function report(label)
		T("GUARD case=%s humans=%d p1=%s p2=%s master=%s", label, #GAMESTATE:GetHumanPlayers(),
			tostring(GAMESTATE:IsHumanPlayer(PLAYER_1)), tostring(GAMESTATE:IsHumanPlayer(PLAYER_2)),
			tostring(GAMESTATE:GetMasterPlayerNumber()))
	end
	step(0.3, function()
		T("GUARD pref=%s", tostring(ThemePrefs.Get("PreferredStyle")))
		setup({ PLAYER_2, PLAYER_1 })      -- P2 pressed Start first => master P2, then P1 joined
		report("both_joined_master_P2:before")
		api.resolveSingleStyleJoin()
		report("both_joined_master_P2:after")
		setup({ PLAYER_2 })
		report("only_P2:before")
		api.resolveSingleStyleJoin()
		report("only_P2:after")
		setup({ PLAYER_1 })               -- restore
		report("restored")
	end)
	step(1.0, function() shot("guard_done") end)

elseif name == "section_filter" then
	step(1.0, function() landOnWheel("Danger Zone") end)
	step(0.8, function() api.catnav.Enter() end)
	step(0.5, function()
		local st = api.catnav.State()
		T('SECTION_FILTER initial active=%s total=%d unfil=%d query="%s"',
			tostring(st.active), st.total or 0, st.unfilteredTotal or 0, st.filterQuery or "")
	end)
	-- Type "d" -> starts section filter
	step(0.5, function()
		api.catnav.Handle(ev("DeviceButton_d"))
	end)
	step(0.5, function()
		local st = api.catnav.State()
		T('SECTION_FILTER step=typed_d query="%s" total=%d unfil=%d selected="%s"',
			st.filterQuery or "", st.total or 0, st.unfilteredTotal or 0, tostring(st.selectedTitle))
	end)
	-- Type "a" and "n" -> query becomes "dan"
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_a"))
	end)
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_n"))
	end)
	step(0.5, function()
		local st = api.catnav.State()
		T('SECTION_FILTER step=typed_dan query="%s" total=%d unfil=%d selected="%s"',
			st.filterQuery or "", st.total or 0, st.unfilteredTotal or 0, tostring(st.selectedTitle))
	end)
	-- BackSpace -> query becomes "da"
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_backspace"))
	end)
	step(0.5, function()
		local st = api.catnav.State()
		T('SECTION_FILTER step=backspace query="%s" total=%d unfil=%d',
			st.filterQuery or "", st.total or 0, st.unfilteredTotal or 0)
	end)
	-- Press Escape -> clears section filter, stays in keyboard mode
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_escape"))
	end)
	step(0.5, function()
		local st = api.catnav.State()
		T('SECTION_FILTER step=escape_cleared active=%s query="%s" total=%d unfil=%d',
			tostring(st.active), st.filterQuery or "", st.total or 0, st.unfilteredTotal or 0)
	end)
	-- Type "z" to filter again
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_z"))
	end)
	step(0.3, function()
		local st = api.catnav.State()
		T('SECTION_FILTER step=typed_z query="%s"', st.filterQuery or "")
	end)
	-- Press "/" -> clears section filter AND opens Omnibar (global search)
	step(0.3, function()
		api.catnav.Handle(ev("DeviceButton_slash"))
	end)
	step(0.5, function()
		local st = api.catnav.State()
		local ob = api.omnibar.IsOpen()
		T('SECTION_FILTER step=slash_omnibar omnibar_open=%s query="%s"',
			tostring(ob), st.filterQuery or "")
	end)
	step(0.8, function() shot("section_filter_done") end)
end

local idx = 0
return Def.ActorFrame {
	OnCommand = function(self)
		T("BEGIN scenario=%s steps=%d", name, #steps)
		self:sleep(3.0):queuecommand("Next")
	end,
	NextCommand = function(self)
		idx = idx + 1
		local s = steps[idx]
		if not s then T("DONE scenario=%s", name) return end
		local ok, err = pcall(s.fn, self)
		if not ok then T("ERROR step=%d err=%s", idx, tostring(err)) end
		self:sleep(s.wait or 0.5):queuecommand("Next")
	end,
	-- The engine plays this on the screen from MenuStart (finalized selection). It only fires when
	-- ScreenSelectMusic::MenuStart really ran.
	ShowPressStartForOptionsCommand = function(self)
		T("OPTIONS_PROMPT shown redirP1=%s redirP2=%s screen=%s",
			tostring(SCREENMAN:get_input_redirected(PLAYER_1)), tostring(SCREENMAN:get_input_redirected(PLAYER_2)),
			tostring(SCREENMAN:GetTopScreen():GetName()))
	end,
	StartFinalizedMessageCommand = function(self)
		T("START_FINALIZED engine=%s", engineTitle())
	end,
}
