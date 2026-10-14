-- CategorySongWheel.lua
-- Virtual, high-performance song scroller for the active category in CategoryNavigation.
-- Renders 14 high-density cards with live metadata, difficulty badges, and scrollbar.

local CategorySongWheel = {}

local wheelX = IsUsingWideScreen() and (_screen.cx + _screen.w/4) or (_screen.cx + 160)
local wheelW = IsUsingWideScreen() and 396 or 300
local maxRows = 15
local rowHeight = 26.5
local startY = 86
_G.CategorySongWheel_MaxRows = maxRows

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

-- meterMin/meterMax: active METERS tier. When set, show the meter of the chart that MATCHED
-- the tier (highest in range) instead of the player's preferred difficulty.
local function GetSongDisplayMeter(entry, meterMin, meterMax)
	if not entry then return "", Color.White end

	if meterMin and entry.meters then
		local bestDiff, bestMeter = nil, nil
		for diff, m in pairs(entry.meters) do
			if m >= meterMin and m <= meterMax and (not bestMeter or m > bestMeter) then
				bestDiff, bestMeter = diff, m
			end
		end
		if bestDiff then return tostring(bestMeter), DifficultyColor(bestDiff) end
	end

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
	for _, pn in ipairs({ PLAYER_1, PLAYER_2 }) do
		local short = ToEnumShortString(pn)
		if GAMESTATE:IsPlayerEnabled(pn) and SL[short] and SL[short].Favorites and FindInTable then
			if FindInTable(song, SL[short].Favorites) then return true end
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
-- Song Cards (1 through 13)
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
				titleText:zoom(0.58)
				subText:diffuse(color("#ddeeff"))
				subText:zoom(0.46)
				bpmLengthText:diffuse(Color.White)
				bpmLengthText:zoom(0.48)
			else
				cardBg:diffuse(color("0.06, 0.08, 0.12, 0.90"))
				titleText:diffuse(color("#e2ecf7"))
				titleText:zoom(0.58)
				subText:diffuse(color("#adc4db"))
				subText:zoom(0.46)
				bpmLengthText:diffuse(color("#adc4db"))
				bpmLengthText:zoom(0.48)
			end

			titleText:settext(entry.title or "")

			local artist = entry.artist or ""
			local group = entry.group or ""
			if #artist > 0 and #group > 0 then
				subText:settext(artist .. "    •    " .. group)
			elseif #artist > 0 then
				subText:settext(artist)
			else
				subText:settext(group)
			end

			local bpmStr = FormatBPM(entry.bpms)
			local lenStr = FormatLength(entry.length)
			if #bpmStr > 0 and #lenStr > 0 then
				bpmLengthText:settext(bpmStr .. " BPM    " .. lenStr)
			elseif #bpmStr > 0 then
				bpmLengthText:settext(bpmStr .. " BPM")
			else
				bpmLengthText:settext(lenStr)
			end

			local mStr, mColor = GetSongDisplayMeter(entry, params.meterMin, params.meterMax)
			meterText:settext(mStr)
			meterBadgeBg:diffuse(mColor)

			local favBorder = self:GetChild("FavBadgeBorder")
			local isFav = entry.song and IsSongFavorite(entry.song) or false
			favBorder:visible(isFav)
		end,

		-- Card backdrop (compact 28px height)
		Def.Quad {
			Name = "CardBg",
			InitCommand = function(self)
				self:zoomto(wheelW, rowHeight - 2)
				self:diffuse(color("0.06, 0.08, 0.12, 0.90"))
			end,
		},

		-- Selection Highlight Quad (alpha 0.28)
		Def.Quad {
			Name = "CardHighlight",
			InitCommand = function(self)
				self:zoomto(wheelW, rowHeight - 2)
				self:diffuse(GetCurrentColor()):diffusealpha(0.28)
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor()):diffusealpha(0.28)
			end,
		},

		-- Left selection accent indicator (5px solid theme color bar)
		Def.Quad {
			Name = "LeftAccent",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 2.5)
				self:zoomto(5, rowHeight - 2)
				self:diffuse(GetCurrentColor())
				self:visible(false)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Favorite Glowing Gold Border around Meter Badge (30x23px)
		Def.Quad {
			Name = "FavBadgeBorder",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 18)
				self:zoomto(30, 23)
				self:diffuse(color("#ffd700"))
				self:visible(false)
			end,
		},

		-- Difficulty Meter Badge Quad (26x19px compact)
		Def.Quad {
			Name = "MeterBadgeBg",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 18)
				self:zoomto(26, 19)
				self:diffuse(color("0.15, 0.18, 0.26, 1.0"))
			end,
		},

		-- Difficulty Meter Text (zoom 0.58)
		LoadFont("Common Normal") .. {
			Name = "MeterText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 18)
				self:zoom(0.58)
				self:shadowlength(1)
				self:diffuse(Color.White)
				self:settext("")
			end,
		},

		-- Song Title (zoom 0.58)
		LoadFont("Common Normal") .. {
			Name = "TitleText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 38)
				self:y(-5.5)
				self:horizalign(left)
				self:zoom(0.58)
				self:maxwidth((wheelW - 150) / 0.58)
				self:diffuse(Color.White)
				self:shadowlength(1)
				self:settext("")
			end,
		},

		-- Artist & Pack Subtitle (zoom 0.46)
		LoadFont("Common Normal") .. {
			Name = "SubText",
			InitCommand = function(self)
				self:x(-wheelW / 2 + 38)
				self:y(6)
				self:horizalign(left)
				self:zoom(0.46)
				self:maxwidth((wheelW - 150) / 0.46)
				self:diffuse(color("#adc4db"))
				self:shadowlength(1)
				self:settext("")
			end,
		},

		-- BPM & Length (Right aligned, zoom 0.48)
		LoadFont("Common Normal") .. {
			Name = "BpmLengthText",
			InitCommand = function(self)
				self:x(wheelW / 2 - 8)
				self:horizalign(right)
				self:zoom(0.48)
				self:diffuse(color("#adc4db"))
				self:shadowlength(1)
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
		local total = params and params.songs and #params.songs or 0
		local query = params and params.filterQuery or ""
		if total == 0 then
			self:visible(true)
			local tit = self:GetChild("EmptyTitle")
			local sub = self:GetChild("EmptySubtitle")
			if #query > 0 then
				if tit then tit:settext("NO MATCHES IN SECTION") end
				if sub then sub:settext(string.format("No songs match \"%s\" in this section\n[ BackSpace ] Delete   •   [ Esc ] Clear   •   [ / ] Search All Songs", query)) end
			else
				if tit then tit:settext("NO SONGS FOUND") end
				if sub then sub:settext((params and params.emptyHint) or "No songs match this category filter.") end
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
			self:zoom(0.74)
			self:diffuse(color("#ffaa55"))
			self:shadowlength(1)
			self:settext("NO SONGS FOUND")
		end,
	},
	-- Subtitle explanation
	LoadFont("Common Normal") .. {
		Name = "EmptySubtitle",
		InitCommand = function(self)
			self:y(14)
			self:zoom(0.52)
			self:diffuse(color("#b8cce0"))
			self:shadowlength(1)
			self:settext("")
		end,
	},
}

af[#af + 1] = emptyStateAF

-- -------------------------------------------------------------
-- Streamlined Unified Control HUD in Left Footer Section
-- Positioned strictly on the left side under PaneDisplay
-- Right side under the 15-row song wheel is 100% transparent
-- -------------------------------------------------------------
local leftBarW = math.floor(_screen.w / 2 - 10)

local hudAF = Def.ActorFrame {
	Name = "UnifiedControlHUD",
	InitCommand = function(self)
		self:xy(-wheelX, _screen.h - 16)
		self:draworder(120)
	end,

	-- Semi-transparent footer quad (left side only, under PaneDisplay)
	Def.Quad {
		Name = "HudLeftBg",
		InitCommand = function(self)
			self:x(leftBarW / 2)
			self:zoomto(leftBarW, 32)
			self:diffuse(color("0.03, 0.04, 0.06, 0.95"))
		end,
	},

	-- Top accent hairline (left side only, 1px at y = -16 flush with screen bottom footer line)
	Def.Quad {
		Name = "HudTopAccent",
		InitCommand = function(self)
			self:x(leftBarW / 2)
			self:y(-16)
			self:zoomto(leftBarW, 1)
			self:diffuse(GetCurrentColor()):diffusealpha(0.8)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(0.8)
		end,
	},

	-- Unified Hotkeys and Status Text (centered in left footer section, 2 lines matching classic HUD)
	LoadFont("Common Normal") .. {
		Name = "UnifiedControlText",
		InitCommand = function(self)
			self:x(leftBarW / 2)
			self:y(0)
			self:horizalign(center)
			self:vertalign(middle)
			self:zoom(IsUsingWideScreen() and 0.52 or 0.44)
			self:vertspacing(-1)
			self:shadowlength(1)
			self:diffuse(Color.White)
			self:maxwidth((leftBarW - 16) / (IsUsingWideScreen() and 0.52 or 0.44))
			self:settext("")
		end,
		UpdateCategoryUIMessageCommand = function(self, params)
			if not params or not params.songs then return end
			local total = #params.songs
			local sel = params.selectedIdx or 1
			local query = params.filterQuery or ""
			if #query > 0 then
				if total == 0 then
					self:settext(string.format("NO MATCHES FOR \"%s\"\n[ BackSpace ] Delete   •   [ Esc ] Clear   •   [ / ] All Songs", query))
					self:diffuse(color("#ff6666"))
				else
					if IsUsingWideScreen() then
						self:settext(string.format("FILTER: \"%s\" (Song %d of %d)   •   [ Enter ] Play\n[ Up / Down ] Browse   •   [ BackSpace ] Del   •   [ Esc ] Clear   •   [ / ] All", query, sel, total))
					else
						self:settext(string.format("FILTER: \"%s\" (%d/%d)   •   [ Enter ] Play\n[ Up/Dn ] Browse   •   [ Bksp ] Del   •   [ Esc ] Clear   •   [ / ] All", query, sel, total))
					end
					self:diffuse(color("#66ffcc"))
				end
			else
				if total == 0 then
					self:settext("0 Songs in Category\n[ Tab ] Category   •   [ Left / Right ] Tabs   •   [ Esc ] Wheel")
					self:diffuse(color("#ffaa66"))
				else
					if IsUsingWideScreen() then
						self:settext(string.format("Song %d of %d   •   [ Enter ] Play   •   [ Up / Down ] Browse   •   [ 1-5 ] Diff\n[ Tab ] Category   •   [ Left / Right ] Tabs   •   [ Esc ] Wheel", sel, total))
					else
						self:settext(string.format("Song %d of %d   •   [ Enter ] Play   •   [ Up / Dn ] Browse   •   [ 1-5 ] Diff\n[ Tab ] Cat   •   [ L / R ] Tabs   •   [ Esc ] Wheel", sel, total))
					end
					self:diffuse(Color.White)
				end
			end
		end,
	},
}

af[#af + 1] = hudAF

return af
