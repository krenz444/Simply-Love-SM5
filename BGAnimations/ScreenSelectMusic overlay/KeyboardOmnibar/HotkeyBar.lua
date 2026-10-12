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
-- 1. Top Header Search Pill (Docked cleanly inside top header bar)
-- Positioned at y = 16, directly above the MusicWheel column.
-- Completely above y = 32 so it NEVER collides with any wheel items.
-- -------------------------------------------------------------
local topPillX = IsUsingWideScreen() and (_screen.cx + 165) or (_screen.cx + 125)
local topPillW = IsUsingWideScreen() and 230 or 185
local topPillH = 22

local topPill = Def.ActorFrame {
	Name = "HeaderSearchPill",
	InitCommand = function(self)
		self:xy(topPillX, 16)
	end,

	-- Outer pill border
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW + 2, topPillH + 2)
			self:diffuse(GetCurrentColor()):diffusealpha(0.85)
		end,
		ColorSelectedMessageCommand = function(self)
			self:diffuse(GetCurrentColor()):diffusealpha(0.85)
		end,
	},

	-- Pill opaque dark background
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(topPillW, topPillH)
			self:diffuse(color("0.04, 0.05, 0.08, 1.0"))
		end,
	},

	-- Left search prompt text
	LoadFont("Common Normal") .. {
		Name = "SearchPrompt",
		InitCommand = function(self)
			self:x(-topPillW / 2 + 10)
			self:horizalign(left)
			self:zoom(0.52)
			self:diffuse(Color.White)
			self:settext("[ / ] Type to Search")
		end,
	},

	-- Right layout indicator badge
	LoadFont("Common Normal") .. {
		Name = "LayoutBadge",
		InitCommand = function(self)
			self:x(topPillW / 2 - 8)
			self:horizalign(right)
			self:zoom(0.50)
			self:playcommand("RefreshLayout")
		end,
		RefreshLayoutCommand = function(self)
			local layName = "QWERTY"
			if FILEMAN:DoesFileExist("Save/KeyboardLayout.txt") then
				local text = lua.ReadFile("Save/KeyboardLayout.txt") or ""
				local clean = text:gsub("^%s*(.-)%s*$", "%1"):lower()
				if clean == "colemak" then layName = "Colemak"
				elseif clean == "colemak-dh" then layName = "Colemak-DH"
				elseif clean == "windows_auto" then layName = "Win Auto" end
			end
			self:settext(string.format("[%s]", layName))
			if layName == "Colemak" or layName == "Colemak-DH" then
				self:diffuse(color("#ffdd55"))
			elseif layName == "Win Auto" then
				self:diffuse(color("#55ddff"))
			else
				self:diffuse(color("#55ff88"))
			end
		end,
		KeyboardLayoutChangedMessageCommand = function(self, params)
			local name = params and params.name or "QWERTY"
			self:settext(string.format("[%s]", name))
			if name == "Colemak" or name == "Colemak-DH" then
				self:diffuse(color("#ffdd55"))
			elseif name == "Win Auto" then
				self:diffuse(color("#55ddff"))
			else
				self:diffuse(color("#55ff88"))
			end
		end,
	},
}

af[#af + 1] = topPill

-- -------------------------------------------------------------
-- 2. Bottom Footer Hotkey Legend (Docked cleanly inside footer chrome)
-- Positioned at y = _screen.h - 16, right of EVENT MODE.
-- Zero overlap with any gameplay panes or wheel graphics.
-- -------------------------------------------------------------
local bottomX = IsUsingWideScreen() and (_screen.cx + 170) or (_screen.cx + 125)

local bottomLegend = Def.ActorFrame {
	Name = "FooterHotkeyLegend",
	InitCommand = function(self)
		self:xy(bottomX, _screen.h - 16)
	end,

	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:zoom(0.48)
			self:diffuse(color("#ddeeff"))
			self:shadowlength(0.2)
			self:settext("[ [ / ] ] Skip Pack   |   [ 1-5 ] Diff   |   [ S ] Sort")
		end,
	},
}

af[#af + 1] = bottomLegend

return af
