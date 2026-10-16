-- CategoryRibbon.lua
-- Renders the Tier 1 Category Tabs and Tier 2 Sub-Filter Chips for CategoryNavigation.
-- Positioned cleanly above the song column on the right half of the screen.

local CategoryEngine = LoadActor("CategoryEngine.lua")

local CategoryRibbon = {}

local ribbonX = IsUsingWideScreen() and (_screen.cx + _screen.w/4) or (_screen.cx + 160)
local ribbonW = IsUsingWideScreen() and 396 or 300

local categories = CategoryEngine.GetCategories()
local numTabs = #categories

local af = Def.ActorFrame {
	Name = "CategoryRibbonRoot",
	InitCommand = function(self)
		self:xy(ribbonX, 0)
		self:draworder(110)
	end,
}

-- -------------------------------------------------------------
-- Tier 1: Top Category Ribbon Tabs (y = 42, height = 16, spans y = 34..50)
-- -------------------------------------------------------------
local tabContainer = Def.ActorFrame {
	Name = "Tier1Tabs",
	InitCommand = function(self)
		self:y(42)
	end,

	-- Top hairline separator below header
	Def.Quad {
		InitCommand = function(self)
			self:y(-8)
			self:zoomto(ribbonW, 1)
			self:diffuse(color("0.20, 0.20, 0.25, 0.8"))
		end,
	},
	-- Background pill tray (cohesive dark theme color, no blue tint)
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW, 16)
			self:diffuse(color("0.05, 0.05, 0.07, 0.98"))
		end,
	},
}

-- Create individual tab actors
local tabSpacing = ribbonW / numTabs

for i = 1, numTabs do
	local cat = categories[i]
	local tabX = -ribbonW / 2 + (i - 0.5) * tabSpacing

	local tabAF = Def.ActorFrame {
		Name = "Tab_" .. cat.id,
		InitCommand = function(self)
			self:x(tabX)
		end,

		-- Active Tab Indicator Highlight
		Def.Quad {
			Name = "TabHighlight",
			InitCommand = function(self)
				self:zoomto(tabSpacing - 4, 13)
				self:visible(i == 1)
				self:diffuse(GetCurrentColor()):diffusealpha(0.35)
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor()):diffusealpha(0.35)
			end,
			UpdateCategoryUIMessageCommand = function(self, params)
				if params and params.categoryIdx then
					self:visible(i == params.categoryIdx)
				end
			end,
		},

		-- Active Tab Bottom Accent Seam
		Def.Quad {
			Name = "TabUnderline",
			InitCommand = function(self)
				self:y(7)
				self:zoomto(tabSpacing - 4, 2)
				self:visible(i == 1)
				self:diffuse(GetCurrentColor())
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
			UpdateCategoryUIMessageCommand = function(self, params)
				if params and params.categoryIdx then
					self:visible(i == params.categoryIdx)
				end
			end,
		},

		-- Tab Label Text
		LoadFont("Common Normal") .. {
			Name = "TabLabel",
			InitCommand = function(self)
				self:y(-1)
				self:zoom(0.52)
				self:shadowlength(1)
				self:maxwidth((tabSpacing - 4) / 0.52)
				self:settext(cat.name)
				if i == 1 then
					self:diffuse(Color.White)
				else
					self:diffuse(color("#a8bdd4"))
				end
			end,
			UpdateCategoryUIMessageCommand = function(self, params)
				if params and params.categoryIdx then
					if i == params.categoryIdx then
						self:diffuse(Color.White)
					else
						self:diffuse(color("#a8bdd4"))
					end
				end
			end,
		},
	}

	tabContainer[#tabContainer + 1] = tabAF
end

af[#af + 1] = tabContainer

-- -------------------------------------------------------------
-- Tier 2: Sub-Category Visual Tab Control (y = 52, height = 18, spans y = 43..61)
-- Visual segmented tabs with prominent Left/Right arrow keycaps
-- -------------------------------------------------------------
local maxVisualTabs = 9
local keyW = IsUsingWideScreen() and 48 or 40
local keyTextZoom = IsUsingWideScreen() and 0.44 or 0.36
local leftKeyX = -ribbonW / 2 + keyW / 2 + 2
local rightKeyX = ribbonW / 2 - keyW / 2 - 2
local tabAreaW = (rightKeyX - keyW / 2 - 3) - (leftKeyX + keyW / 2 + 3)

local function GetChipShortLabel(catId, chip)
	if not chip then return "" end
	local id = chip.id
	if catId == "meters" then
		if id == "all" then return "All" end
		if id == "warmup" then return "1-8" end
		if id == "mid" then return "9-10" end
		if id == "upper" then return "11-12" end
		if id == "expert" then return "13-14" end
		if id == "master" then return "15-18" end
		if id == "elite" then return "19+" end
	elseif catId == "bpm" then
		if id == "all" then return "All" end
		if id == "chill" then return "< 130" end
		if id == "standard" then return "130-155" end
		if id == "energy" then return "155-180" end
		if id == "fast" then return "180-210" end
		if id == "speed" then return "210+" end
	elseif catId == "alphabet" then
		if id == "num" then return "#" end
		if id == "ac" then return "A-C" end
		if id == "df" then return "D-F" end
		if id == "gi" then return "G-I" end
		if id == "jl" then return "J-L" end
		if id == "mo" then return "M-O" end
		if id == "pr" then return "P-R" end
		if id == "su" then return "S-U" end
		if id == "vz" then return "V-Z" end
	elseif catId == "favorites" then
		if id == "all_fav" then return "All Fav" end
		if id == "p1_fav" then return "P1 Fav" end
		if id == "p2_fav" then return "P2 Fav" end
		if id == "recents" then return "Recent" end
	elseif catId == "played" then
		if id == "all" then return "Played" end
		if id == "unplayed" then return "Unplayed" end
		if id == "cleared" then return "Cleared" end
	end
	return chip.label or id or ""
end

local lastCategoryUIParams = nil

local chipsContainer = Def.ActorFrame {
	Name = "Tier2Chips",
	InitCommand = function(self)
		self:y(61)
	end,

	-- Top hairline separator between Tier 1 tabs and Tier 2 tabs
	Def.Quad {
		InitCommand = function(self)
			self:y(-8)
			self:zoomto(ribbonW, 1)
			self:diffuse(color("0.16, 0.16, 0.22, 0.8"))
		end,
	},

	-- Background tray (dark, cohesive)
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW, 16)
			self:diffuse(color("0.04, 0.04, 0.06, 0.96"))
		end,
	},

	-- Bottom hairline separator before song cards
	Def.Quad {
		InitCommand = function(self)
			self:y(8)
			self:zoomto(ribbonW, 1)
			self:diffuse(color("0.16, 0.16, 0.22, 0.8"))
		end,
	},

	-- ---------------------------------------------------------
	-- Left Arrow Keycap Button (affordance for keyboard Left arrow / pad MenuLeft)
	-- ---------------------------------------------------------
	Def.ActorFrame {
		Name = "LeftArrowKeycap",
		InitCommand = function(self)
			self:x(leftKeyX)
		end,
		CategorySubChipCycledMessageCommand = function(self, params)
			if params and params.dir == -1 then
				self:stoptweening():zoom(1.15):decelerate(0.12):zoom(1.0)
			end
		end,
		Def.Quad {
			Name = "KeyBg",
			InitCommand = function(self)
				self:zoomto(keyW, 13)
				self:diffuse(color("0.15, 0.18, 0.24, 0.95"))
			end,
		},
		Def.Quad {
			Name = "KeyTopBevel",
			InitCommand = function(self)
				self:y(-5.5)
				self:zoomto(keyW, 1)
				self:diffuse(color("0.35, 0.42, 0.55, 0.8"))
			end,
		},
		Def.Quad {
			Name = "KeyBottomShadow",
			InitCommand = function(self)
				self:y(5.5)
				self:zoomto(keyW, 1)
				self:diffuse(color("0.08, 0.09, 0.12, 0.9"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "KeyLabel",
			InitCommand = function(self)
				self:y(-0.5)
				self:zoom(keyTextZoom)
				self:shadowlength(1)
				self:diffuse(color("#eef4ff"))
				self:settext("<  Left")
			end,
		},
	},

	-- ---------------------------------------------------------
	-- Right Arrow Keycap Button (affordance for keyboard Right arrow / pad MenuRight)
	-- ---------------------------------------------------------
	Def.ActorFrame {
		Name = "RightArrowKeycap",
		InitCommand = function(self)
			self:x(rightKeyX)
		end,
		CategorySubChipCycledMessageCommand = function(self, params)
			if params and params.dir == 1 then
				self:stoptweening():zoom(1.15):decelerate(0.12):zoom(1.0)
			end
		end,
		Def.Quad {
			Name = "KeyBg",
			InitCommand = function(self)
				self:zoomto(keyW, 13)
				self:diffuse(color("0.16, 0.20, 0.28, 0.95"))
			end,
		},
		Def.Quad {
			Name = "KeyTopBevel",
			InitCommand = function(self)
				self:y(-5.5)
				self:zoomto(keyW, 1)
				self:diffuse(color("0.40, 0.48, 0.65, 0.85"))
			end,
		},
		Def.Quad {
			Name = "KeyBottomShadow",
			InitCommand = function(self)
				self:y(5.5)
				self:zoomto(keyW, 1)
				self:diffuse(color("0.06, 0.08, 0.12, 0.95"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "KeyLabel",
			InitCommand = function(self)
				self:y(-0.5)
				self:zoom(keyTextZoom)
				self:shadowlength(1)
				self:diffuse(color("#eef4ff"))
				self:settext("Right  >")
			end,
		},
	},
}

-- -------------------------------------------------------------
-- Visual Tab Slots Actor Pool (1 through 9)
-- -------------------------------------------------------------
local tabsGroup = Def.ActorFrame {
	Name = "VisualTabsGroup",
}

for slot = 1, maxVisualTabs do
	tabsGroup[#tabsGroup + 1] = Def.ActorFrame {
		Name = "Tab_" .. slot,
		InitCommand = function(self)
			self:visible(false)
		end,

		-- Tab Pill Background
		Def.Quad {
			Name = "TabBg",
			InitCommand = function(self)
				self:zoomto(40, 13)
				self:diffuse(color("0.10, 0.12, 0.16, 0.85"))
			end,
		},

		-- Tab Top Accent Highlight / Glow
		Def.Quad {
			Name = "TabTopGlow",
			InitCommand = function(self)
				self:y(-5.5)
				self:zoomto(40, 1)
				self:diffuse(color("0.25, 0.28, 0.35, 0.3"))
			end,
		},

		-- Tab Label Text
		LoadFont("Common Normal") .. {
			Name = "TabLabel",
			InitCommand = function(self)
				self:y(-0.5)
				self:zoom(0.40)
				self:shadowlength(1)
				self:diffuse(color("#a8bdd4"))
				self:settext("")
			end,
		},
	}
end

chipsContainer[#chipsContainer + 1] = tabsGroup

-- -------------------------------------------------------------
-- In-Place Active Filter Bar (replaces Tier 2 visual tabs while typing)
-- -------------------------------------------------------------
local activeFilterBar = Def.ActorFrame {
	Name = "ActiveFilterBar",
	InitCommand = function(self)
		self:visible(false)
	end,
	SetCommand = function(self, params)
		if not params then return end
		local query = params.filterQuery or ""
		local total = params.songs and #params.songs or 0
		local unfilTotal = params.unfilteredTotal or total
		local isMatch = (total > 0)
		local themeColor = GetCurrentColor()

		local bg = self:GetChild("FilterBg")
		local border = self:GetChild("FilterBorder")
		local glow = self:GetChild("FilterTopGlow")
		local leftText = self:GetChild("FilterLeftText")
		local rightText = self:GetChild("FilterRightText")

		if isMatch then
			if bg then bg:diffuse(color("0.05, 0.08, 0.13, 0.98")) end
			if border then border:diffuse(themeColor):diffusealpha(0.85) end
			if glow then glow:diffuse(Color.White):diffusealpha(0.75) end
		else
			if bg then bg:diffuse(color("0.16, 0.05, 0.05, 0.98")) end
			if border then border:diffuse(color("#ff4444")):diffusealpha(0.95) end
			if glow then glow:diffuse(color("#ff8888")):diffusealpha(0.85) end
		end

		if leftText then
			leftText:settext(string.format("FILTER:  \"%s_\"", query))
			leftText:diffuse(Color.White)
		end

		if rightText then
			local rStr = ""
			if IsUsingWideScreen() then
				if isMatch then
					rStr = string.format("(%d of %d songs)   •   [Bksp] Del   [Esc] Clear   [/] All", total, unfilTotal)
					rightText:diffuse(color("#66ffcc"))
				else
					rStr = string.format("(0 of %d matches)   •   [Bksp] Del   [Esc] Clear   [/] All", unfilTotal)
					rightText:diffuse(color("#ff7777"))
				end
			else
				if isMatch then
					rStr = string.format("(%d/%d) • [Bksp] [Esc] Clear", total, unfilTotal)
					rightText:diffuse(color("#66ffcc"))
				else
					rStr = string.format("(0/%d) • [Bksp] [Esc] Clear", unfilTotal)
					rightText:diffuse(color("#ff7777"))
				end
			end
			rightText:settext(rStr)
		end
	end,
	ColorSelectedMessageCommand = function(self)
		if lastCategoryUIParams and lastCategoryUIParams.filterQuery and #lastCategoryUIParams.filterQuery > 0 then
			self:playcommand("Set", lastCategoryUIParams)
		end
	end,

	-- Outer Border Quad
	Def.Quad {
		Name = "FilterBorder",
		InitCommand = function(self)
			self:zoomto(ribbonW - 4, 16)
			self:diffuse(GetCurrentColor()):diffusealpha(0.85)
		end,
	},

	-- Dark Inner Background Quad
	Def.Quad {
		Name = "FilterBg",
		InitCommand = function(self)
			self:zoomto(ribbonW - 6, 14)
			self:diffuse(color("0.05, 0.08, 0.13, 0.98"))
		end,
	},

	-- Top Glow Accent Line
	Def.Quad {
		Name = "FilterTopGlow",
		InitCommand = function(self)
			self:y(-5.5)
			self:zoomto(ribbonW - 6, 1)
			self:diffuse(Color.White):diffusealpha(0.75)
		end,
	},

	-- Bottom Shadow Accent Line
	Def.Quad {
		Name = "FilterBottomShadow",
		InitCommand = function(self)
			self:y(5.5)
			self:zoomto(ribbonW - 6, 1)
			self:diffuse(color("0.02, 0.03, 0.05, 0.95"))
		end,
	},

	-- Left Text: FILTER: "query_"
	LoadFont("Common Normal") .. {
		Name = "FilterLeftText",
		InitCommand = function(self)
			local lx = -ribbonW / 2 + (IsUsingWideScreen() and 10 or 6)
			self:x(lx)
			self:y(-0.5)
			self:horizalign(left)
			local z = IsUsingWideScreen() and 0.44 or 0.36
			self:zoom(z)
			self:shadowlength(1)
			self:diffuse(Color.White)
			local maxW = (ribbonW * 0.48) / z
			self:maxwidth(maxW)
			self:settext("")
		end,
	},

	-- Right Text: (X of Y songs) • [Bksp] Del • [Esc] Clear • [/] All
	LoadFont("Common Normal") .. {
		Name = "FilterRightText",
		InitCommand = function(self)
			local rx = ribbonW / 2 - (IsUsingWideScreen() and 10 or 6)
			self:x(rx)
			self:y(-0.5)
			self:horizalign(right)
			local z = IsUsingWideScreen() and 0.38 or 0.30
			self:zoom(z)
			self:shadowlength(1)
			self:diffuse(color("#66ffcc"))
			local maxW = (ribbonW * 0.50) / z
			self:maxwidth(maxW)
			self:settext("")
		end,
	},
}

chipsContainer[#chipsContainer + 1] = activeFilterBar

-- Update Visual Tabs dynamically when category or filter changes
local function UpdateVisualTabs(self, params)
	if not params then return end
	lastCategoryUIParams = params

	local query = params.filterQuery or ""
	local filterBar = self:GetChild("ActiveFilterBar")
	local leftKey = self:GetChild("LeftArrowKeycap")
	local rightKey = self:GetChild("RightArrowKeycap")
	local tabsAF = self:GetChild("VisualTabsGroup")

	if #query > 0 then
		if leftKey then leftKey:visible(false) end
		if rightKey then rightKey:visible(false) end
		if tabsAF then tabsAF:visible(false) end
		if filterBar then
			filterBar:visible(true)
			filterBar:playcommand("Set", params)
		end
		return
	else
		if filterBar then filterBar:visible(false) end
		if leftKey then leftKey:visible(true) end
		if rightKey then rightKey:visible(true) end
		if tabsAF then tabsAF:visible(true) end
	end

	local catId = params.categoryId
	local subChips = params.subChips or {}
	local activeIdx = params.subChipIdx or 1
	local totalSongs = params.totalSongs or 0
	local numChips = #subChips

	if not tabsAF then return end

	-- Hide all tab slots initially
	for slot = 1, maxVisualTabs do
		local tab = tabsAF:GetChild("Tab_" .. slot)
		if tab then tab:visible(false) end
	end

	if numChips == 0 then return end

	local themeColor = GetCurrentColor()

	-- CASE A: Single Chip (e.g. Empty or Search)
	if numChips == 1 then
		local tab = tabsAF:GetChild("Tab_1")
		if tab then
			tab:visible(true)
			tab:x(0)
			local bg = tab:GetChild("TabBg")
			local glow = tab:GetChild("TabTopGlow")
			local lbl = tab:GetChild("TabLabel")
			local chip = subChips[1]
			local w = tabAreaW - 4
			bg:zoomto(w, 13):diffuse(themeColor):diffusealpha(0.85)
			glow:y(-5.5):zoomto(w, 1):diffuse(Color.White):diffusealpha(0.7)
			local aZoom = IsUsingWideScreen() and 0.46 or 0.38
			lbl:zoom(aZoom):diffuse(Color.White):shadowlength(1):maxwidth((w - 8) / aZoom)
			lbl:settext(string.format("%s  (%d songs)", chip.label or "", totalSongs))
		end
		return
	end

	-- CASE B: Finite list of categories (numChips <= 9 and catId ~= "packs")
	-- Displays ALL tabs simultaneously with accordion focus on active tab
	if numChips <= 9 and catId ~= "packs" then
		local w_active = 0
		local w_inactive = 0

		if numChips <= 4 then
			w_inactive = math.floor(tabAreaW / numChips)
			w_active = w_inactive
		else
			if numChips == 5 or numChips == 6 then
				w_inactive = IsUsingWideScreen() and 38 or 28
			elseif numChips == 7 then -- METERS
				w_inactive = IsUsingWideScreen() and 32 or 23
			else -- 8 or 9 (ALPHABET)
				w_inactive = IsUsingWideScreen() and 26 or 19
			end
			w_active = tabAreaW - (numChips - 1) * w_inactive
		end

		local curLeft = -tabAreaW / 2
		for i = 1, numChips do
			local tab = tabsAF:GetChild("Tab_" .. i)
			if tab then
				tab:visible(true)
				local chip = subChips[i]
				local isActive = (i == activeIdx)
				local thisW = isActive and w_active or w_inactive
				local thisCenterX = curLeft + thisW / 2
				curLeft = curLeft + thisW

				tab:x(thisCenterX)
				local bg = tab:GetChild("TabBg")
				local glow = tab:GetChild("TabTopGlow")
				local lbl = tab:GetChild("TabLabel")

				local quadW = math.max(10, thisW - 2)
				bg:zoomto(quadW, 13)
				glow:y(-5.5):zoomto(quadW, 1)

				if isActive then
					bg:diffuse(themeColor):diffusealpha(0.90)
					glow:diffuse(Color.White):diffusealpha(0.8)
					lbl:diffuse(Color.White)
					local activeZoom = IsUsingWideScreen() and 0.46 or 0.38
					lbl:zoom(activeZoom)
					lbl:shadowlength(1)
					lbl:maxwidth((quadW - 4) / activeZoom)
					local txt = ""
					if catId == "meters" then
						txt = string.format("%s (%d)", chip.label or "", totalSongs)
					else
						local sLbl = GetChipShortLabel(catId, chip)
						txt = string.format("%s (%d)", sLbl, totalSongs)
					end
					lbl:settext(txt)
				else
					bg:diffuse(color("0.10, 0.12, 0.16, 0.85"))
					glow:diffuse(color("0.25, 0.28, 0.35, 0.35"))
					lbl:diffuse(color("#a8bdd4"))
					local inactiveZoom = IsUsingWideScreen() and 0.40 or 0.32
					lbl:zoom(inactiveZoom)
					lbl:shadowlength(1)
					lbl:maxwidth((quadW - 4) / inactiveZoom)
					local sLbl = GetChipShortLabel(catId, chip)
					lbl:settext(sLbl)
				end
			end
		end
		return
	end

	-- CASE C: PACKS or Large Collections (numChips > 9 or catId == "packs")
	-- 3-tab sliding carousel: [Prev Pack] [Active Pack with counter & count] [Next Pack]
	local prevIdx = (activeIdx > 1) and (activeIdx - 1) or numChips
	local nextIdx = (activeIdx < numChips) and (activeIdx + 1) or 1

	local w_side = IsUsingWideScreen() and 74 or 52
	local w_center = tabAreaW - 2 * w_side

	local slots = {
		{ slot = 1, idx = prevIdx, x = -tabAreaW / 2 + w_side / 2, w = w_side, isActive = false },
		{ slot = 2, idx = activeIdx, x = 0, w = w_center, isActive = true },
		{ slot = 3, idx = nextIdx, x = tabAreaW / 2 - w_side / 2, w = w_side, isActive = false },
	}

	for _, s in ipairs(slots) do
		local tab = tabsAF:GetChild("Tab_" .. s.slot)
		if tab then
			tab:visible(true)
			tab:x(s.x)
			local chip = subChips[s.idx] or {}
			local bg = tab:GetChild("TabBg")
			local glow = tab:GetChild("TabTopGlow")
			local lbl = tab:GetChild("TabLabel")

			local quadW = math.max(10, s.w - 3)
			bg:zoomto(quadW, 13)
			glow:y(-5.5):zoomto(quadW, 1)

			if s.isActive then
				bg:diffuse(themeColor):diffusealpha(0.90)
				glow:diffuse(Color.White):diffusealpha(0.8)
				lbl:diffuse(Color.White)
				local cZoom = IsUsingWideScreen() and 0.46 or 0.38
				lbl:zoom(cZoom)
				lbl:shadowlength(1)
				lbl:maxwidth((quadW - 6) / cZoom)
				lbl:settext(string.format("[%d/%d]  %s (%d)", activeIdx, numChips, chip.label or "", totalSongs))
			else
				bg:diffuse(color("0.10, 0.12, 0.16, 0.85"))
				glow:diffuse(color("0.25, 0.28, 0.35, 0.35"))
				lbl:diffuse(color("#a8bdd4"))
				local sZoom = IsUsingWideScreen() and 0.40 or 0.32
				lbl:zoom(sZoom)
				lbl:shadowlength(1)
				lbl:maxwidth((quadW - 4) / sZoom)
				lbl:settext(chip.label or "")
			end
		end
	end
end

chipsContainer.UpdateCategoryUIMessageCommand = function(self, params)
	UpdateVisualTabs(self, params)
end

chipsContainer.ColorSelectedMessageCommand = function(self)
	if lastCategoryUIParams then
		UpdateVisualTabs(self, lastCategoryUIParams)
	end
end

af[#af + 1] = chipsContainer

return af


