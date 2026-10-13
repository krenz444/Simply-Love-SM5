-- CategorySongWheel.lua
-- Virtual, high-performance song scroller for the active category in CategoryNavigation.
-- Renders 8 high-density cards with live metadata, difficulty badges, and scrollbar.

local CategorySongWheel = {}

local wheelX = IsUsingWideScreen() and (_screen.cx + _screen.w/4) or (_screen.cx + 160)
local wheelW = IsUsingWideScreen() and 396 or 300
local maxRows = 8
local rowHeight = 38
local startY = 100

-- Format helpers
local function FormatLength(seconds)
	if not seconds or seconds <= 0 then return "" end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function FormatBPM(bpms)
	if not bpms or #bpms == 0 then return "" end
	local minB = math.floor(bpms[1] or 0)
	local maxB = math.floor(bpms[2] or minB)
	if minB == maxB or maxB == 0 then
		return tostring(minB)
	else
		return tostring(minB) .. "-" .. tostring(maxB)
	end
end

local function GetSongDisplayMeter(entry)
	if not entry then return "", Color.White end
	local p = (GAMESTATE:IsPlayerEnabled(PLAYER_1) and PLAYER_1) or (GAMESTATE:IsPlayerEnabled(PLAYER_2) and PLAYER_2) or nil
	local pDiff = p and GAMESTATE:GetPreferredDifficulty(p) or "Difficulty_Hard"

	if entry.meters and entry.meters[pDiff] then
		return tostring(entry.meters[pDiff]), DifficultyColor(pDiff)
	end

	local fallbackDiffs = { "Difficulty_Hard", "Difficulty_Medium", "Difficulty_Challenge", "Difficulty_Easy", "Difficulty_Beginner" }
	for _, diff in ipairs(fallbackDiffs) do
		if entry.meters and entry.meters[diff] then
			return tostring(entry.meters[diff]), DifficultyColor(diff)
		end
	end

	if entry.meterList and #entry.meterList > 0 then
		return tostring(entry.meterList[#entry.meterList]), color("#ffaa00")
	end

	return "?", Color.White
end

local function IsSongFavorite(song)
	if not song then return false end
	for _, pn in ipairs({ "P1", "P2" }) do
		if SL[pn] and SL[pn].Favorites and FindInTable then
			if FindInTable(song, SL[pn].Favorites) then return true end
		end
	end
	return false
end

local af = Def.ActorFrame {
	Name = "CategorySongWheelRoot",
	InitCommand = function(self)
		self:xy(wheelX, 0)
		self:draworder(105)
	end,
}

-- -------------------------------------------------------------
-- Song Cards (1 through 8)
-- -------------------------------------------------------------
for r = 1, maxRows do
	local cardY = startY + (r - 1) * rowHeight

	local rowAF = Def.ActorFrame {
		Name = "SongCard_" .. r,
		InitCommand = function(self)
			self:y(cardY)
			self:visible(false)
		end,
		UpdateCategoryUIMessageCommand = function(self, params)
			if not params or not params.songs then
				self:visible(false)
				return
			end

			local songIdx = (params.topIdx or 1) + (r - 1)
			local entry = params.songs[songIdx]
			if not entry then
				self:visible(false)
				return
			end

			self:visible(true)
			local isSelected = (songIdx == (params.selectedIdx or 1))

			local cardBg = self:GetChild("CardBg")
			local cardHighlight = self:GetChild("CardHighlight")
			local leftAccent = self:GetChild("LeftAccent")
			local meterBadgeBg = self:GetChild("MeterBadgeBg")
			local meterText = self:GetChild("MeterText")
			local titleText = self:GetChild("TitleText")
			local subText = self:GetChild("SubText")
			local bpmLengthText = self:GetChild("BpmLengthText")

			cardHighlight:visible(isSelected)
			leftAccent:visible(isSelected)
			if isSelected then
				cardBg:diffuse(color("0.13, 0.17, 0.26, 0.98"))
				titleText:diffuse(Color.White)
				titleText:zoom(0.57)
				subText:diffuse(color("#ccddee"))
				bpmLengthText:diffuse(Color.White)
				bpmLengthText:zoom(0.46)
			else
				cardBg:diffuse(color("0.06, 0.08, 0.12, 0.90"))
				titleText:diffuse(color("#c8d6e5"))
				titleText:zoom(0.53)
				subText:diffuse(color("#778899"))
				bpmLengthText:diffuse(color("#778899"))
				bpmLengthText:zoom(0.42)
			end

			titleText:settext(entry.title or "")
			subText:settext((entry.artist or "") .. "  •  " .. (entry.group or ""))

			local bpmStr = FormatBPM(entry.bpms)
			local lenStr = FormatLength(entry.length)
			if #bpmStr > 0 and #lenStr > 0 then
				bpmLengthText:settext(bpmStr .. " BPM  " .. lenStr)
			elseif #bpmStr > 0 then
				bpmLengthText:settext(bpmStr .. " BPM")
			else
				bpmLengthText:settext(lenStr)
			end

			local mStr, mColor = GetSongDisplayMeter(entry)
			meterText:settext(mStr)
			meterBadgeBg:diffuse(mColor)

			local favBorder = self:GetChild("FavBadgeBorder")
			local isFav = entry.song and IsSongFavorite(entry.song) or false
			favBorder:visible(isFav)
		end,

		-- Card backdrop
		Def.Quad {
			Name = "CardBg",
			InitCommand = function(self)
				self:zoomto(wheelW, rowHeight - 3)
				self:diffuse(color("0.06, 0.08, 0.12, 0.90"))
			end,
		},

		-- Selection Highlight Quad
		Def.Quad {
			Name = "CardHighlight",
			InitCommand = function(self)
				self:zoomto(wheelW, rowHeight - 3)
				self:diffuse(GetCurrentColor()):diffusealpha(0.32)
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor()):diffusealpha(0.32)
			end,
		},

		-- Left selection accent indicator (prominent 6px cursor bar)
		Def.Quad {
			Name = "LeftAccent",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 3)
				self:zoomto(6, rowHeight - 3)
				self:diffuse(GetCurrentColor())
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Favorite Glowing Gold Border around Meter Badge
		Def.Quad {
			Name = "FavBadgeBorder",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 24)
				self:zoomto(32, 26)
				self:diffuse(color("#ffd700"))
				self:visible(false)
			end,
		},

		-- Difficulty Meter Badge Quad
		Def.Quad {
			Name = "MeterBadgeBg",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 24)
				self:zoomto(28, 22)
				self:diffuse(color("0.15, 0.18, 0.26, 1.0"))
			end,
		},

		-- Difficulty Meter Text
		LoadFont("Common Normal") .. {
			Name = "MeterText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 24)
				self:zoom(0.58)
				self:shadowlength(0)
				self:diffuse(Color.White)
				self:settext("")
			end,
		},

		-- Song Title
		LoadFont("Common Normal") .. {
			Name = "TitleText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 44)
				self:y(-7)
				self:horizalign(left)
				self:zoom(0.55)
				self:maxwidth((wheelW - 145) / 0.55)
				self:diffuse(Color.White)
				self:shadowlength(0)
				self:settext("")
			end,
		},

		-- Artist & Pack Subtitle
		LoadFont("Common Normal") .. {
			Name = "SubText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 44)
				self:y(7)
				self:horizalign(left)
				self:zoom(0.40)
				self:maxwidth((wheelW - 145) / 0.40)
				self:diffuse(color("#8899aa"))
				self:shadowlength(0)
				self:settext("")
			end,
		},

		-- BPM & Length (Right aligned)
		LoadFont("Common Normal") .. {
			Name = "BpmLengthText",
			InitCommand = function(self)
				self:x(wheelW / 2 - 10)
				self:horizalign(right)
				self:zoom(0.44)
				self:diffuse(color("#aaccdd"))
				self:settext("")
			end,
		},
	}

	af[#af + 1] = rowAF
end

-- -------------------------------------------------------------
-- Scrollbar Track & Thumb
-- -------------------------------------------------------------
local trackH = maxRows * rowHeight
af[#af + 1] = Def.Quad {
	Name = "ScrollTrack",
	InitCommand = function(self)
		self:x(wheelW / 2 + 4)
		self:y(startY + trackH / 2 - rowHeight / 2)
		self:zoomto(3, trackH)
		self:diffuse(color("0.14, 0.18, 0.25, 0.5"))
	end,
}

af[#af + 1] = Def.Quad {
	Name = "ScrollThumb",
	InitCommand = function(self)
		self:x(wheelW / 2 + 4)
		self:y(startY)
		self:zoomto(4, 30)
		self:diffuse(GetCurrentColor())
	end,
	ColorSelectedMessageCommand = function(self)
		self:diffuse(GetCurrentColor())
	end,
	UpdateCategoryUIMessageCommand = function(self, params)
		if not params or not params.songs or #params.songs == 0 then
			self:visible(false)
			return
		end
		self:visible(true)
		local total = #params.songs
		local thumbH = math.max(18, math.min(trackH, trackH * (maxRows / total)))
		self:zoomto(4, thumbH)
		local progress = total > maxRows and ((params.topIdx - 1) / (total - maxRows)) or 0
		local trackStartY = startY - rowHeight / 2 + thumbH / 2
		local trackEndY = startY + trackH - rowHeight / 2 - thumbH / 2
		self:y(trackStartY + progress * (trackEndY - trackStartY))
	end,
}


-- -------------------------------------------------------------
-- Empty State Helper (displayed when 0 songs match category/filter)
-- -------------------------------------------------------------
local emptyStateAF = Def.ActorFrame {
	Name = "EmptyStateMessage",
	InitCommand = function(self)
		self:y(startY + trackH / 2 - rowHeight / 2)
		self:visible(false)
	end,
	UpdateCategoryUIMessageCommand = function(self, params)
		if not params or not params.songs or #params.songs == 0 then
			self:visible(true)
			local catId = params and params.categoryId or ""
			local sub = self:GetChild("EmptySubtitle")
			if catId == "favorites" then
				sub:settext("You haven't added any favorites yet.\nPress [Ctrl+D] or pad Select code to favorite any song!")
			else
				sub:settext("No songs match this category filter.\nPress [Left / Right] or [Tab] to browse other categories.")
			end
		else
			self:visible(false)
		end
	end,

	-- Border hairline
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(wheelW - 38, 76)
			self:diffuse(color("0.16, 0.20, 0.28, 0.85"))
		end,
	},
	-- Background surface
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(wheelW - 40, 74)
			self:diffuse(color("0.07, 0.09, 0.13, 0.96"))
		end,
	},
	-- Title
	LoadFont("Common Normal") .. {
		Name = "EmptyTitle",
		InitCommand = function(self)
			self:y(-14)
			self:zoom(0.66)
			self:diffuse(color("#ffaa55"))
			self:shadowlength(0)
			self:settext("NO SONGS FOUND")
		end,
	},
	-- Subtitle explanation
	LoadFont("Common Normal") .. {
		Name = "EmptySubtitle",
		InitCommand = function(self)
			self:y(14)
			self:zoom(0.44)
			self:diffuse(color("#8899aa"))
			self:shadowlength(0)
			self:settext("")
		end,
	},
}

af[#af + 1] = emptyStateAF

-- -------------------------------------------------------------
-- Dual-Tier Navigation Control HUD (y = 401 & y = 424)
-- Tier 1: Primary Actions (Song Count, Play Confirmation, Browse, Return)
-- Tier 2: Hotkeys & Secondary Controls (Category, Filter, Search, Difficulty)
-- -------------------------------------------------------------
local hudAF = Def.ActorFrame {
	Name = "DualTierControlHUD",

	-- Deck 1: Primary Action Dock (y = 401)
	Def.ActorFrame {
		Name = "PrimaryActionDock",
		InitCommand = function(self)
			self:y(startY + trackH - rowHeight / 2 + 16)
		end,
		-- Border hairline
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(wheelW + 2, 24)
				self:diffuse(color("0.16, 0.20, 0.28, 0.85"))
			end,
		},
		-- Background quad
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(wheelW, 22)
				self:diffuse(color("0.07, 0.09, 0.14, 0.96"))
			end,
		},
		-- Top accent hairline
		Def.Quad {
			InitCommand = function(self)
				self:y(-10)
				self:zoomto(wheelW, 1.5)
				self:diffuse(GetCurrentColor()):diffusealpha(0.7)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor()):diffusealpha(0.7)
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "PrimaryActionText",
			InitCommand = function(self)
				self:zoom(0.44)
				self:shadowlength(0)
				self:diffuse(Color.White)
				self:settext("")
			end,
			UpdateCategoryUIMessageCommand = function(self, params)
				if not params or not params.songs then return end
				local total = #params.songs
				local sel = params.selectedIdx or 1
				if total == 0 then
					self:settext("0 Songs   •   [Tab] Category   •   [Esc] Wheel Mode")
					self:diffuse(color("#ffaa66"))
				else
					self:settext(string.format("Song %d of %d   •   [Enter / Start] Play   •   [Up/Down] Browse   •   [Esc] Wheel", sel, total))
					self:diffuse(Color.White)
				end
			end,
		},
	},

	-- Deck 2: Hotkeys & Filters Map (y = 424)
	Def.ActorFrame {
		Name = "SecondaryControlsDock",
		InitCommand = function(self)
			self:y(startY + trackH - rowHeight / 2 + 39)
		end,
		-- Border hairline
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(wheelW + 2, 20)
				self:diffuse(color("0.13, 0.17, 0.24, 0.75"))
			end,
		},
		-- Background quad
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(wheelW, 18)
				self:diffuse(color("0.05, 0.07, 0.11, 0.94"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "SecondaryControlsText",
			InitCommand = function(self)
				self:zoom(0.38)
				self:shadowlength(0)
				self:diffuse(color("#aaccdd"))
				self:settext("[Tab] Category   •   [Left/Right] Filter   •   Type to Search   •   [1-5] Diff   •   [Ctrl+D] Fav")
			end,
		},
	},
}

af[#af + 1] = hudAF

return af
