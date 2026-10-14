-- WheelSync.lua
-- One place that moves the native MusicWheel (and everything the engine derives from its
-- selection) onto a given song. Used by Keyboard Mode, the Omnibar and the pack jump.
--
-- Engine facts (ITGmania MusicWheel.cpp / ScreenSelectMusic.cpp):
--  * MusicWheel::SelectSong() only sets the wheel's selection INDEX (after opening the song's
--    section). It does not rebuild the on-screen rows, so the highlight keeps showing the old
--    arrangement; SetOpenSection() ends in RebuildWheelItems() and re-selects the item that was
--    selected before, so calling it after SelectSong() re-centres the rows on the song.
--  * It also posts nothing: ScreenSelectMusic::AfterMusicChange() (current song, banner, steps,
--    density graph, preview music) runs on SM_SongChanged, which must be posted explicitly.
--  * Under SORT_PREFERRED / SORT_METER SelectSong() re-opens the last section opened by hand
--    (sLastOpenSection) instead of the song's, and the Popularity / Recent sorts show only some
--    songs, so the song may not be on the wheel at all. ChangeSort(Group) avoids all of that
--    (it also clears sLastOpenSection), exactly as stock SongSearch does.
if SL and SL.Global and SL.Global.KbdWheelSync then
	return SL.Global.KbdWheelSync
end

local WheelSync = {}
if SL and SL.Global then SL.Global.KbdWheelSync = WheelSync end

local unreliableSorts = {
	SortOrder_Preferred = true,
	SortOrder_Meter = true,
	SortOrder_Popularity = true,
	SortOrder_Recent = true,
}

function WheelSync.EnsureSortable(wheel)
	if unreliableSorts[GAMESTATE:GetSortOrder()] then
		wheel:ChangeSort("SortOrder_Group")
	end
end

-- Select `song` on the native wheel of `top` (the ScreenSelectMusic). Returns true when the
-- wheel accepted it. Does NOT change GAMESTATE's current song (callers decide that).
function WheelSync.SelectSong(top, wheel, song)
	if not (top and wheel and song) then return false end
	WheelSync.EnsureSortable(wheel)
	if not wheel:SelectSong(song) then return false end

	-- Re-centre the rows on the selection.
	if GAMESTATE:GetExpandedParentSectionName() == "" then
		local section = GAMESTATE:GetExpandedSectionName()
		if section ~= "" then
			wheel:SetOpenSection(section)
		end
	else
		-- The song sits in a child section under a parent (Series sort). SetOpenSection() cannot
		-- re-open a parent, so nudge the wheel one row and back: both moves rebuild the rows.
		wheel:Move(1)
		wheel:Move(-1)
		wheel:Move(0)
	end

	top:PostScreenMessage("SM_SongChanged", 0)
	return true
end

-- Type and text of the row the wheel is DISPLAYING at its centre (not just its selection
-- index). Used by the engine-state tests to catch a wheel that is selected but not redrawn.
function WheelSync.CenterRow(wheel)
	local n = 0
	while n < 64 do
		local ok = pcall(wheel.GetWheelItem, wheel, n)
		if not ok then break end
		n = n + 1
	end
	if n == 0 then return nil end
	local item = wheel:GetWheelItem(math.floor(n / 2))
	local ok, ty = pcall(item.GetType, item)
	local okT, title = pcall(function() return item:GetChild("SongName"):GetChild("Title"):GetText() end)
	return (ok and ty) or nil, (okT and title) or "", n
end

return WheelSync
