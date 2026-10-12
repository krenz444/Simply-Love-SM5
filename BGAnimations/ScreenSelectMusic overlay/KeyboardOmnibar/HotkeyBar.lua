-- HotkeyBar.lua
-- Sleek, non-intrusive keyboard hotkey guide displayed above the MusicWheel

local af = Def.ActorFrame {
	Name = "KeyboardHotkeyBar",
	InitCommand = function(self)
		local xPos = IsUsingWideScreen() and (_screen.cx + 175) or _screen.cx
		local yPos = IsUsingWideScreen() and 53 or 38
		self:xy(xPos, yPos)
		self:draworder(100)
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

	-- Card backdrop
	Def.Quad {
		InitCommand = function(self)
			local w = IsUsingWideScreen() and 380 or (_screen.w - 20)
			self:zoomto(w, 32)
			self:diffuse(color("0.05, 0.06, 0.09, 0.96"))
		end,
	},

	-- Top accent hairline
	Def.Quad {
		InitCommand = function(self)
			local w = IsUsingWideScreen() and 380 or (_screen.w - 20)
			self:y(-15)
			self:zoomto(w, 1.5)
			self:diffuse(GetCurrentColor()):diffusealpha(0.8)
		end,
	},

	-- Line 1: Main navigation hotkeys
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:y(-6)
			self:zoom(0.55)
			self:diffuse(Color.White)
			self:settext("[ / ] Type to Search   |   [ [ / ] ] Skip Pack   |   [ 1-5 ] Difficulty")
		end,
	},

	-- Line 2: Feature hotkeys & layout indicator
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:y(7)
			self:zoom(0.48)
			self:diffuse(color("#bbccdd"))
			local layName = "QWERTY"
			if FILEMAN:DoesFileExist("Save/KeyboardLayout.txt") then
				local text = lua.ReadFile("Save/KeyboardLayout.txt") or ""
				local clean = text:gsub("^%s*(.-)%s*$", "%1"):lower()
				if clean == "colemak" then layName = "Colemak"
				elseif clean == "colemak-dh" then layName = "Colemak-DH" end
			end
			self:settext(string.format("[ F ] Favorite  |  [ L ] Scores  |  [ P ] Practice  |  [ S ] Sort  |  [ Ctrl+L ] Layout: %s", layName))
		end,
		KeyboardLayoutChangedMessageCommand = function(self, params)
			local name = params and params.name or "QWERTY"
			self:settext(string.format("[ F ] Favorite  |  [ L ] Scores  |  [ P ] Practice  |  [ S ] Sort  |  [ Ctrl+L ] Layout: %s", name))
		end,
	},
}

return af
