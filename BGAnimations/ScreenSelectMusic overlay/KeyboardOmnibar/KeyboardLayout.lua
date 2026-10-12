-- KeyboardLayout.lua
-- Dynamic keyboard layout management for ITGmania / Simply Love
-- Supports QWERTY, Colemak, and Colemak-DH with persistent preference and Ctrl+L toggling

local KeyboardLayout = {}

local layoutFile = "Save/KeyboardLayout.txt"
local windowsLayoutFile = "Save/WindowsKeyboardLayout.lua"

local layouts = {
	["qwerty"] = {
		id = "qwerty",
		name = "QWERTY",
		desc = "Standard QWERTY",
		map = {},
		shift_map = {},
	},
	["colemak"] = {
		id = "colemak",
		name = "Colemak",
		desc = "Standard Colemak",
		map = {
			["e"] = "f",
			["r"] = "p",
			["t"] = "g",
			["y"] = "j",
			["u"] = "l",
			["i"] = "u",
			["o"] = "y",
			["p"] = ";",
			["s"] = "r",
			["d"] = "s",
			["f"] = "t",
			["g"] = "d",
			["j"] = "n",
			["k"] = "e",
			["l"] = "i",
			["colon"] = "o",
			["semicolon"] = "o",
			[";"] = "o",
			[":"] = "o",
			["n"] = "k",
		},
		shift_map = {
			["p"] = ":",
			["colon"] = "O",
			["semicolon"] = "O",
			[";"] = "O",
			[":"] = "O",
		},
	},
	["colemak-dh"] = {
		id = "colemak-dh",
		name = "Colemak-DH",
		desc = "Colemak Mod-DH",
		map = {
			["e"] = "f",
			["r"] = "p",
			["t"] = "b",
			["y"] = "j",
			["u"] = "l",
			["i"] = "u",
			["o"] = "y",
			["p"] = ";",
			["s"] = "r",
			["d"] = "s",
			["f"] = "t",
			["g"] = "g",
			["h"] = "m",
			["j"] = "n",
			["k"] = "e",
			["l"] = "i",
			["colon"] = "o",
			["semicolon"] = "o",
			[";"] = "o",
			[":"] = "o",
			["v"] = "d",
			["b"] = "v",
			["n"] = "k",
			["m"] = "h",
		},
		shift_map = {
			["p"] = ":",
			["colon"] = "O",
			["semicolon"] = "O",
			[";"] = "O",
			[":"] = "O",
		},
	},
}

local layoutOrder = { "windows_auto", "qwerty", "colemak", "colemak-dh" }
local activeLayoutId = nil

local function LoadWindowsLayout()
	if not FILEMAN:DoesFileExist(windowsLayoutFile) then return nil end
	local content = lua.ReadFile(windowsLayoutFile)
	if not content or #content == 0 then return nil end
	local chunk, err = loadstring(content)
	if chunk then
		local ok, def = pcall(chunk)
		if ok and type(def) == "table" and def.map then
			return def
		end
	end
	return nil
end

-- Refresh / register Windows layout if available
local winDef = LoadWindowsLayout()
if winDef then
	layouts["windows_auto"] = winDef
else
	layoutOrder = { "qwerty", "colemak", "colemak-dh" }
end

-- Key mapping table for raw device buttons to characters
local keyCharMap = {
	["DeviceButton_space"] = " ",
	["DeviceButton_ "] = " ",
	["DeviceButton_slash"] = "/",
	["DeviceButton_/"] = "/",
	["DeviceButton_minus"] = "-",
	["DeviceButton_hyphen"] = "-",
	["DeviceButton_-"] = "-",
	["DeviceButton_equals"] = "=",
	["DeviceButton_equal"] = "=",
	["DeviceButton_="] = "=",
	["DeviceButton_period"] = ".",
	["DeviceButton_."] = ".",
	["DeviceButton_comma"] = ",",
	["DeviceButton_,"] = ",",
	["DeviceButton_colon"] = ";",
	["DeviceButton_semicolon"] = ";",
	["DeviceButton_;"] = ";",
	["DeviceButton_:"] = ":",
	["DeviceButton_apostrophe"] = "'",
	["DeviceButton_quote"] = "'",
	["DeviceButton_'"] = "'",
	["DeviceButton_left bracket"] = "[",
	["DeviceButton_["] = "[",
	["DeviceButton_right bracket"] = "]",
	["DeviceButton_]"] = "]",
	["DeviceButton_backslash"] = "\\",
	["DeviceButton_\\"] = "\\",
	["DeviceButton_`"] = "`",
	["DeviceButton_grave"] = "`",
}

local shiftCharMap = {
	["1"] = "!",
	["2"] = "@",
	["3"] = "#",
	["4"] = "$",
	["5"] = "%",
	["6"] = "^",
	["7"] = "&",
	["8"] = "*",
	["9"] = "(",
	["0"] = ")",
	["-"] = "_",
	["="] = "+",
	["/"] = "?",
	[";"] = ":",
	[":"] = ":",
	["'"] = "\"",
	[","] = "<",
	["."] = ">",
	["["] = "{",
	["]"] = "}",
	["\\"] = "|",
	["`"] = "~",
}

function KeyboardLayout.ReloadWindowsLayout()
	local freshWin = LoadWindowsLayout()
	if freshWin then
		layouts["windows_auto"] = freshWin
		if layoutOrder[1] ~= "windows_auto" then
			table.insert(layoutOrder, 1, "windows_auto")
		end
	end

	if FILEMAN:DoesFileExist(layoutFile) then
		local text = lua.ReadFile(layoutFile) or ""
		local clean = text:gsub("^%s*(.-)%s*$", "%1"):lower()
		if layouts[clean] then
			activeLayoutId = clean
			return activeLayoutId
		end
	end

	if layouts["windows_auto"] then
		activeLayoutId = "windows_auto"
	else
		activeLayoutId = "qwerty"
	end
	return activeLayoutId
end

function KeyboardLayout.GetLayout()
	if activeLayoutId then return activeLayoutId end
	return KeyboardLayout.ReloadWindowsLayout()
end

function KeyboardLayout.SetLayout(id)
	if not layouts[id] then return end
	activeLayoutId = id
	local file = RageFileUtil.CreateRageFile()
	if file:Open(layoutFile, 2) then
		file:Write(activeLayoutId .. "\n")
		file:Close()
		file:destroy()
	end
end

function KeyboardLayout.CycleLayout()
	local cur = KeyboardLayout.GetLayout()
	local nextId = "qwerty"
	for i, id in ipairs(layoutOrder) do
		if id == cur then
			nextId = layoutOrder[(i % #layoutOrder) + 1]
			break
		end
	end
	KeyboardLayout.SetLayout(nextId)
	return nextId, layouts[nextId].name
end

function KeyboardLayout.GetLayoutName()
	local cur = KeyboardLayout.GetLayout()
	return layouts[cur] and layouts[cur].name or "QWERTY"
end

function KeyboardLayout.TranslateButton(btn, shift)
	if not btn then return nil end
	local cur = KeyboardLayout.GetLayout()
	local layoutDef = layouts[cur] or layouts["windows_auto"] or layouts["qwerty"]

	-- 0. Check direct full-key map (provided by Windows auto-export)
	if layoutDef and layoutDef.map then
		if shift and layoutDef.shift_map and layoutDef.shift_map[btn] then
			return layoutDef.shift_map[btn]
		elseif not shift and layoutDef.map[btn] then
			return layoutDef.map[btn]
		end
	end

	-- 1. Check layout-specific shift mapping (e.g. shift+p in colemak is ':')
	if shift and layoutDef.shift_map then
		local rawLetter = btn:match("^DeviceButton_([a-zA-Z])$")
		if rawLetter then rawLetter = rawLetter:lower() end
		local rawSpecial = btn:match("^DeviceButton_(.*)$")
		if rawLetter and layoutDef.shift_map[rawLetter] then
			return layoutDef.shift_map[rawLetter]
		end
		if rawSpecial and layoutDef.shift_map[rawSpecial] then
			return layoutDef.shift_map[rawSpecial]
		end
	end

	-- 2. Check layout-specific unshifted/shifted mapping
	if layoutDef.map then
		local rawLetter = btn:match("^DeviceButton_([a-zA-Z])$")
		if rawLetter then rawLetter = rawLetter:lower() end
		if rawLetter and layoutDef.map[rawLetter] then
			local mapped = layoutDef.map[rawLetter]
			if mapped == ";" then
				return shift and ":" or ";"
			end
			return shift and mapped:upper() or mapped
		end

		local rawSpecial = btn:match("^DeviceButton_(.*)$")
		if rawSpecial and layoutDef.map[rawSpecial] then
			local mapped = layoutDef.map[rawSpecial]
			if mapped == ";" then
				return shift and ":" or ";"
			end
			return shift and mapped:upper() or mapped
		end
	end

	-- 3. Standard letter fallback
	local letter = btn:match("^DeviceButton_([a-zA-Z])$")
	if letter then
		return shift and letter:upper() or letter:lower()
	end

	-- 4. Numbers: DeviceButton_0 .. DeviceButton_9
	local num = btn:match("^DeviceButton_(%d)$")
	if num then
		if shift and shiftCharMap[num] then
			return shiftCharMap[num]
		end
		return num
	end

	-- 5. Numpad / Keypad
	local kpNum = btn:match("^DeviceButton_KP (%d)$") or btn:match("^DeviceButton_num (%d)$")
	if kpNum then return kpNum end
	if btn == "DeviceButton_KP slash" or btn == "DeviceButton_num slash" or btn == "DeviceButton_KP divide" then return "/" end
	if btn == "DeviceButton_KP minus" or btn == "DeviceButton_num minus" then return "-" end
	if btn == "DeviceButton_KP plus" or btn == "DeviceButton_num plus" then return "+" end
	if btn == "DeviceButton_KP period" or btn == "DeviceButton_num period" then return "." end

	-- 6. Punctuation
	local special = keyCharMap[btn]
	if special then
		if shift and shiftCharMap[special] then
			return shiftCharMap[special]
		end
		return special
	end

	return nil
end

return KeyboardLayout
