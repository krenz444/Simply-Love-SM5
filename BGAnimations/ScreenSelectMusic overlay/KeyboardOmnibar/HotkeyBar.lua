-- HotkeyBar.lua
-- Seamless, non-intrusive keyboard navigation & search affordance dock for Simply Love.
-- Docked cleanly inside the top header bar between the session timer and ITG logo.
-- Completely above y = 32 so it NEVER collides with any wheel items.
-- Automatically hidden while Category Navigation or Keyboard Omnibar is active.

local isCatNavActive = false

local function IsCatNavActive()
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

local af = Def.ActorFrame {
	Name = "KeyboardHotkeyBar",
	InitCommand = function(self)
		self:draworder(105)
		local catActive = (ThemePrefs.Get("CategoryNavigation") == true) or IsCatNavActive()
		isCatNavActive = catActive
		self:visible(ThemePrefs.Get("KeyboardFeatures") and not catActive)
	end,
	OnCommand = function(self)
		local catActive = (ThemePrefs.Get("CategoryNavigation") == true) or IsCatNavActive()
		isCatNavActive = catActive
		self:visible(ThemePrefs.Get("KeyboardFeatures") and not catActive)
	end,
	ShowOmnibarMessageCommand = function(self)
		self:visible(false)
	end,
	HideOmnibarMessageCommand = function(self)
		self:visible(ThemePrefs.Get("KeyboardFeatures") and not IsCatNavActive())
	end,
	CategoryNavigationModeChangedMessageCommand = function(self, params)
		if params and params.active ~= nil then
			isCatNavActive = params.active
			self:visible(ThemePrefs.Get("KeyboardFeatures") and not isCatNavActive)
		end
	end,
}

-- -------------------------------------------------------------
-- Dual-Action Header Dock (Search & Category Navigation)
-- Positioned at y = 16, centered perfectly in the header between timer and ITG logo.
-- -------------------------------------------------------------
local topPillX = IsUsingWideScreen() and (_screen.cx + 181) or (_screen.cx + 132)
local topPillW = IsUsingWideScreen() and 236 or 176
local topPillH = 24

local topPill = Def.ActorFrame {
	Name = "HeaderActionDock",
	InitCommand = function(self)
		self:xy(topPillX, 16)
	end,

	-- Outer accent frame / solid theme border
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW + 2, topPillH + 2)
			self:diffuse(GetCurrentColor()):diffusealpha(0.9)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(0.9)
		end,
	},

	-- Elevated dark slate button surface
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW, topPillH)
			self:diffuse(color("0.10, 0.13, 0.20, 0.98"))
		end,
	},

	-- Center subtle vertical divider
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(1.5, 14)
			self:diffuse(color("0.25, 0.32, 0.44, 0.85"))
		end,
	},

	-- Action 1: Search ([ / ])
	Def.ActorFrame {
		Name = "SearchAction",
		InitCommand = function(self)
			self:x(-topPillW / 4)
		end,

		-- Keycap solid background pill
		Def.Quad {
			InitCommand = function(self)
				self:x(-24)
				self:zoomto(26, 16)
				self:diffuse(GetCurrentColor())
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Keycap text inside badge
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:x(-24)
				self:zoom(0.55)
				self:diffuse(color("0.05, 0.05, 0.08, 1.0"))
				self:shadowlength(0)
				self:settext("[/]")
			end,
		},

		-- Action label
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:x(10)
				self:zoom(0.58)
				self:diffuse(Color.White)
				self:shadowlength(1)
				self:settext("Search")
			end,
		},
	},

	-- Action 2: Keyboard Mode ([Tab])
	Def.ActorFrame {
		Name = "CategoriesAction",
		InitCommand = function(self)
			self:x(topPillW / 4)
		end,

		-- Keycap solid background pill
		Def.Quad {
			InitCommand = function(self)
				self:x(IsUsingWideScreen() and -38 or -28)
				self:zoomto(IsUsingWideScreen() and 28 or 24, 16)
				self:diffuse(GetCurrentColor())
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Keycap text inside badge
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:x(IsUsingWideScreen() and -38 or -28)
				self:zoom(IsUsingWideScreen() and 0.52 or 0.44)
				self:diffuse(color("0.05, 0.05, 0.08, 1.0"))
				self:shadowlength(0)
				self:settext("Tab")
			end,
		},

		-- Action label
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:x(IsUsingWideScreen() and 14 or 10)
				self:zoom(IsUsingWideScreen() and 0.50 or 0.42)
				self:maxwidth((topPillW / 2 - (IsUsingWideScreen() and 34 or 28)) / (IsUsingWideScreen() and 0.50 or 0.42))
				self:diffuse(Color.White)
				self:shadowlength(1)
				self:settext("Keyboard Mode")
			end,
		},
	},
}

af[#af + 1] = topPill

return af
