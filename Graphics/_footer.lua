-- tables of rgba values
local dark  = {0,0,0,0.9}
local light = {0.65,0.65,0.65,1}

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

local function UpdateFooter(self)
	local topScreen = SCREENMAN:GetTopScreen()
	local topscreen = topScreen and topScreen:GetName() or ""

	if topscreen == "ScreenSelectMusicCasual" then
		self:diffuse(dark)
	elseif ThemePrefs.Get("VisualStyle") == "SRPG10" then
		self:diffuse(GetCurrentColor(true))
	elseif ThemePrefs.Get("VisualStyle") == "Technique" then
		if topscreen == "ScreenSelectMusic" and not ThemePrefs.Get("RainbowMode") then
			self:diffuse(0, 0, 0, 0.5)
		else
			self:diffusealpha(0)
		end
	elseif DarkUI() then
		self:diffuse(dark)
	else
		self:diffuse(light)
	end

	-- In ScreenSelectMusic with Category Navigation (Keyboard Mode) active,
	-- hide the full-screen footer quad completely so the right side under the
	-- 15-row wheel is 100% transparent. Left side HUD is drawn by CategorySongWheel.
	if topscreen == "ScreenSelectMusic" and (IsCatNavActive() or ThemePrefs.Get("CategoryNavigation") == true) then
		self:visible(false)
	else
		self:visible(true)
	end
end

return Def.Quad{
	Name="Footer",
	InitCommand=function(self)
		self:draworder(90):zoomto(_screen.w, 32):vertalign(bottom):y(32)
		local catActive = (ThemePrefs.Get("CategoryNavigation") == true) or IsCatNavActive()
		isCatNavActive = catActive
		UpdateFooter(self)
	end,
	ScreenChangedMessageCommand=function(self)
		local catActive = (ThemePrefs.Get("CategoryNavigation") == true) or IsCatNavActive()
		isCatNavActive = catActive
		UpdateFooter(self)
	end,
	ColorSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "SRPG10" then
			self:diffuse(GetCurrentColor(true))
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		UpdateFooter(self)
	end,
	CategoryNavigationModeChangedMessageCommand=function(self, params)
		if params and params.active ~= nil then
			isCatNavActive = params.active
			UpdateFooter(self)
		end
	end,
}
