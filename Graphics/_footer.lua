-- tables of rgba values
local dark  = {0,0,0,0.9}
local light = {0.65,0.65,0.65,1}

return Def.Quad{
	Name="Footer",
	InitCommand=function(self)
		local h = (SL and SL.Global and SL.Global.CategoryNavActive) and 24 or 32
		self:draworder(90):zoomto(_screen.w, h):vertalign(bottom):y(32)
		if ThemePrefs.Get("VisualStyle") == "SRPG10" then
			self:diffuse(GetCurrentColor(true))
		elseif DarkUI() then
			self:diffuse(dark)
		elseif ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		else
			self:diffuse(light)
		end
	end,
	CategoryNavigationModeChangedMessageCommand=function(self, params)
		local h = (params and params.active) and 24 or 32
		self:zoomto(_screen.w, h):vertalign(bottom):y(32)
	end,
	ScreenChangedMessageCommand=function(self)
		local topscreen = SCREENMAN:GetTopScreen():GetName()
		if topscreen == "ScreenSelectMusicCasual" then
			self:diffuse(dark)
		end
		if ThemePrefs.Get("VisualStyle") == "SRPG10" then
			self:diffuse(GetCurrentColor(true))
		end
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			if topscreen == "ScreenSelectMusic" and not ThemePrefs.Get("RainbowMode") then
				self:diffuse(0, 0, 0, 0.5)
			else
				self:diffusealpha(0)
			end
		end
	end,
	ColorSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "SRPG10" then
			self:diffuse(GetCurrentColor(true))
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		end
	end,
}
