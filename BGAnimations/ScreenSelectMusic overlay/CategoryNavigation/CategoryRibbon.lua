-- CategoryRibbon.lua
-- Renders the Tier 1 Category Tabs and Tier 2 Sub-Filter Chips for CategoryNavigation.
-- Positioned cleanly above the song column on the right half of the screen.

local CategoryEngine = LoadActor("CategoryEngine.lua")

local CategoryRibbon = {}

local ribbonX = IsUsingWideScreen() and (_screen.cx + _screen.w/4) or (_screen.cx + 160)
local ribbonW = IsUsingWideScreen() and 396 or 300

local categories = CategoryEngine.GetCategories()
local numTabs = 6 -- PACKS, FAVORITES, METERS, BPM, RANKED, A-Z

local af = Def.ActorFrame {
	Name = "CategoryRibbonRoot",
	InitCommand = function(self)
		self:xy(ribbonX, 0)
		self:draworder(110)
	end,
}

-- -------------------------------------------------------------
-- Tier 1: Top Category Ribbon Tabs (y = 44)
-- -------------------------------------------------------------
local tabContainer = Def.ActorFrame {
	Name = "Tier1Tabs",
	InitCommand = function(self)
		self:y(44)
	end,

	-- Border hairline
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW + 2, 24)
			self:diffuse(color("0.16, 0.20, 0.28, 0.85"))
		end,
	},
	-- Background pill tray
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW, 22)
			self:diffuse(color("0.07, 0.09, 0.13, 0.96"))
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
				self:zoomto(tabSpacing - 4, 18)
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
				self:y(9)
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
				self:zoom(0.50)
				self:shadowlength(0.2)
				self:settext(cat.name)
				if i == 1 then
					self:diffuse(Color.White)
				else
					self:diffuse(color("#778899"))
				end
			end,
			UpdateCategoryUIMessageCommand = function(self, params)
				if params and params.categoryIdx then
					if i == params.categoryIdx then
						self:diffuse(Color.White)
					else
						self:diffuse(color("#778899"))
					end
				end
			end,
		},
	}

	tabContainer[#tabContainer + 1] = tabAF
end

af[#af + 1] = tabContainer

-- -------------------------------------------------------------
-- Tier 2: Sub-Category Filter Chips Tray (y = 70)
-- -------------------------------------------------------------
local chipsContainer = Def.ActorFrame {
	Name = "Tier2Chips",
	InitCommand = function(self)
		self:y(70)
	end,

	-- Border hairline
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW + 2, 22)
			self:diffuse(color("0.14, 0.18, 0.25, 0.7"))
		end,
	},

	-- Background tray
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ribbonW, 20)
			self:diffuse(color("0.05, 0.07, 0.11, 0.92"))
		end,
	},

	-- Dynamic chips row text
	LoadFont("Common Normal") .. {
		Name = "ChipsText",
		InitCommand = function(self)
			self:zoom(0.45)
			self:shadowlength(0.2)
			self:diffuse(color("#ccddee"))
			self:settext("")
		end,
		UpdateCategoryUIMessageCommand = function(self, params)
			if not params then return end
			local catId = params.categoryId
			local subChips = params.subChips or {}
			local activeIdx = params.subChipIdx or 1
			local totalSongs = params.totalSongs or 0

			if catId == "packs" then
				local curChip = subChips[activeIdx]
				local packName = curChip and curChip.label or "All Packs"
				self:settext(string.format("< [   [%d/%d] %s (%d songs)   ] >", activeIdx, #subChips, packName, totalSongs))
			else
				local parts = {}
				for idx, chip in ipairs(subChips) do
					if idx == activeIdx then
						parts[#parts + 1] = "[ " .. chip.label .. " ]"
					else
						parts[#parts + 1] = chip.label
					end
				end
				local str = "< [   " .. table.concat(parts, "  •  ") .. "   ] >"
				self:settext(str)
			end
		end,
	},
}

af[#af + 1] = chipsContainer

return af
