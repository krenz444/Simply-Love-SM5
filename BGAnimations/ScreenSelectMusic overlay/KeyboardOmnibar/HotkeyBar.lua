-- HotkeyBar.lua
-- Seamless, non-intrusive keyboard search affordance & hotkey guide for Simply Love.
-- Integrates directly into top header and bottom footer chrome with ZERO gameplay/wheel obstruction.

local af = Def.ActorFrame {
	Name = "KeyboardHotkeyBar",
	InitCommand = function(self)
		self:draworder(105)
		self:visible(ThemePrefs.Get("KeyboardFeatures"))
	end,
	OnCommand = function(self)
		self:visible(ThemePrefs.Get("KeyboardFeatures"))
	end,
	ShowOmnibarMessageCommand = function(self)
		self:visible(false)
	end,
	HideOmnibarMessageCommand = function(self)
		self:visible(ThemePrefs.Get("KeyboardFeatures"))
	end,
}

-- -------------------------------------------------------------
-- 1. Top Header Search Button (Docked cleanly inside top header bar)
-- Positioned at y = 16, directly above the MusicWheel column.
-- Completely above y = 32 so it NEVER collides with any wheel items.
-- High-visibility elevated button with keycap badge and bold label.
-- -------------------------------------------------------------
local topPillX = IsUsingWideScreen() and (_screen.cx + 185) or (_screen.cx + 135)
local topPillW = IsUsingWideScreen() and 244 or 160
local topPillH = 26

local topPill = Def.ActorFrame {
	Name = "HeaderSearchPill",
	InitCommand = function(self)
		self:xy(topPillX, 16)
	end,

	-- Outer accent frame / solid 2px theme border
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW + 4, topPillH + 4)
			self:diffuse(GetCurrentColor()):diffusealpha(1.0)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(1.0)
		end,
	},

	-- Elevated dark slate button surface (high contrast against pure black header)
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW, topPillH)
			self:diffuse(color("0.13, 0.16, 0.25, 1.0"))
		end,
	},

	-- Bottom edge highlight for 3D button depth
	Def.Quad {
		InitCommand = function(self)
			self:y(topPillH / 2 - 1)
			self:zoomto(topPillW - 2, 2)
			self:diffuse(GetCurrentColor()):diffusealpha(0.85)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(0.85)
		end,
	},

	-- Keycap badge container (solid theme-colored keycap affordance)
	Def.ActorFrame {
		Name = "KeycapBadge",
		InitCommand = function(self)
			self:x(-topPillW / 2 + 28)
		end,

		-- Keycap solid background pill
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(42, 20)
				self:diffuse(GetCurrentColor())
			end,
			ColorSelectedMessageCommand = function(self)
				self:diffuse(GetCurrentColor())
			end,
		},

		-- Keycap text inside badge (clean, high-contrast dark text)
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:zoom(0.72)
				self:diffuse(color("0.05, 0.05, 0.08, 1.0"))
				self:settext("[ / ]")
			end,
		},
	},

	-- Primary Action Label ("SEARCH SONGS" in crisp bright white)
	LoadFont("Common Normal") .. {
		Name = "SearchPrompt",
		InitCommand = function(self)
			self:x(24)
			self:horizalign(center)
			self:zoom(IsUsingWideScreen() and 0.86 or 0.68)
			self:diffuse(Color.White)
			self:shadowlength(1)
			self:settext("SEARCH SONGS")
		end,
	},
}

af[#af + 1] = topPill

-- -------------------------------------------------------------
-- 2. Bottom Footer Hotkey Legend (Docked cleanly inside footer chrome)
-- Positioned at y = _screen.h - 16, right of EVENT MODE.
-- Matches Simply Love's native Common Footer typography with zero screen-edge clipping.
-- -------------------------------------------------------------
local bottomX = IsUsingWideScreen() and (_screen.cx + 165) or (_screen.cx + 120)

local bottomLegend = Def.ActorFrame {
	Name = "FooterHotkeyLegend",
	InitCommand = function(self)
		self:xy(bottomX, _screen.h - 18)
	end,
	CategoryNavigationModeChangedMessageCommand = function(self, params)
		if params and params.active ~= nil then
			self:visible(not params.active)
		end
	end,

	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:zoom(0.44)
			self:diffuse(color("#ddeeff"))
			self:shadowlength(0)
			self:settext("[Tab] Keyboard Mode   |   [/] Search   |   [ [ / ] ] Skip Pack")
		end,
	},
}

af[#af + 1] = bottomLegend

return af
