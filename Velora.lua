local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local Velora = {}
Velora.__index = Velora
Velora.Version = "1.3.0"

local Typography = {
	Regular = Enum.Font.BuilderSans,
	Medium = Enum.Font.BuilderSansMedium,
	Bold = Enum.Font.BuilderSansBold,
	Mono = Enum.Font.RobotoMono,
}

local FontAliases = {
	[Enum.Font.Gotham] = Typography.Regular,
	[Enum.Font.GothamMedium] = Typography.Medium,
	[Enum.Font.GothamBold] = Typography.Bold,
	[Enum.Font.Code] = Typography.Mono,
}

local function resolveFont(font)
	return FontAliases[font] or font
end

local function truncateUtf8(text, maximumLength)
	local limit = math.max(0, math.floor(tonumber(maximumLength) or 0))
	local length = utf8.len(text)
	if length and length > limit then
		local nextByte = utf8.offset(text, limit + 1)
		return nextByte and string.sub(text, 1, nextByte - 1) or text, limit
	end
	if not length and #text > limit then
		local truncated = string.sub(text, 1, limit)
		return truncated, utf8.len(truncated) or #truncated
	end
	return text, length or #text
end

Velora.Fonts = Typography

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({
		_tasks = {},
		_cleaned = false,
	}, Maid)
end

function Maid:Give(item)
	if item == nil then
		return nil
	end
	if self._cleaned then
		local itemType = typeof(item)
		if itemType == "RBXScriptConnection" then
			item:Disconnect()
		elseif itemType == "Instance" then
			item:Destroy()
		elseif itemType == "Tween" then
			item:Cancel()
		elseif type(item) == "function" then
			item()
		elseif type(item) == "table" then
			if type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Disconnect) == "function" then
				item:Disconnect()
		end
		end
		return item
	end
	table.insert(self._tasks, item)
	return item
end

function Maid:Clean()
	if self._cleaned then
		return
	end
	self._cleaned = true
	for index = #self._tasks, 1, -1 do
		local item = self._tasks[index]
		self._tasks[index] = nil
		local itemType = typeof(item)
		if itemType == "RBXScriptConnection" then
			item:Disconnect()
		elseif itemType == "Instance" then
			item:Destroy()
		elseif itemType == "Tween" then
			item:Cancel()
		elseif type(item) == "function" then
			local ok, message = pcall(item)
			if not ok then
				warn("[Velora] Cleanup failed: " .. tostring(message))
			end
		elseif type(item) == "table" then
			if type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Disconnect) == "function" then
				item:Disconnect()
			end
		end
	end
end

Maid.Destroy = Maid.Clean

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_connections = {},
		_destroyed = false,
	}, Signal)
end

function Signal:Connect(callback)
	assert(type(callback) == "function", "Signal callback must be a function")
	local connection = {
		Connected = true,
		_callback = callback,
		_signal = self,
	}

	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		local owner = self._signal
		if owner then
			owner._connections[self] = nil
		end
		self._signal = nil
		self._callback = nil
	end

	if self._destroyed then
		connection:Disconnect()
		return connection
	end

	self._connections[connection] = true
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	if self._destroyed then
		return
	end
	local arguments = table.pack(...)
	for connection in pairs(self._connections) do
		if connection.Connected and connection._callback then
			local callback = connection._callback
			task.spawn(function()
				local ok, message = xpcall(function()
					callback(table.unpack(arguments, 1, arguments.n))
				end, debug.traceback)
				if not ok then
					warn("[Velora] Callback failed:\n" .. tostring(message))
				end
			end)
		end
	end
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for connection in pairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

local function shallowCopy(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function deepCopy(source, seen)
	if type(source) ~= "table" then
		return source
	end
	seen = seen or {}
	if seen[source] then
		return seen[source]
	end
	local result = {}
	seen[source] = result
	for key, value in pairs(source) do
		result[deepCopy(key, seen)] = deepCopy(value, seen)
	end
	return result
end

local function deepMerge(base, overrides)
	local result = deepCopy(base)
	for key, value in pairs(overrides or {}) do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = deepMerge(result[key], value)
		else
			result[key] = value
		end
	end
	return result
end

local function valuesEqual(first, second, seen)
	if first == second then
		return true
	end
	if type(first) ~= "table" or type(second) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[first] == second then
		return true
	end
	seen[first] = second
	for key, value in pairs(first) do
		if not valuesEqual(value, second[key], seen) then
			return false
		end
	end
	for key in pairs(second) do
		if first[key] == nil then
			return false
		end
	end
	return true
end

local function safeCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local arguments = table.pack(...)
	task.spawn(function()
		local ok, message = xpcall(function()
			callback(table.unpack(arguments, 1, arguments.n))
		end, debug.traceback)
		if not ok then
			warn("[Velora] Callback failed:\n" .. tostring(message))
		end
	end)
end

local function create(className, properties, children)
	local object = Instance.new(className)
	local parent = properties and properties.Parent
	if properties then
		for property, value in pairs(properties) do
			if property ~= "Parent" then
				object[property] = property == "Font" and resolveFont(value) or value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = object
		end
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function addCorner(object, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = object,
	})
end

local function addStroke(object, color, transparency, thickness)
	return create("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Transparency = transparency or 0,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = object,
	})
end

local function addPadding(object, top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		PaddingLeft = UDim.new(0, left or right or top or 0),
		Parent = object,
	})
end

local function normalizeOptions(first, second)
	local options
	if type(first) == "table" then
		options = shallowCopy(first)
	else
		options = shallowCopy(second)
		if type(first) == "string" then
			if second then
				options.Flag = options.Flag or first
				options.Title = options.Title or options.Name or first
			else
				options.Title = first
			end
		end
	end
	options.Description = options.Description or options.Desc
	return options
end

local function normalizeFlag(text)
	local flag = string.lower(tostring(text or "control"))
	flag = string.gsub(flag, "[^%w_%.%-]+", "_")
	flag = string.gsub(flag, "_+", "_")
	flag = string.gsub(flag, "^_", "")
	flag = string.gsub(flag, "_$", "")
	return flag ~= "" and flag or "control"
end

local function decimalPlaces(value)
	local text = string.lower(tostring(math.abs(tonumber(value) or 0)))
	local mantissa, exponentText = string.match(text, "^([%d%.]+)e([%+%-]?%d+)$")
	if mantissa then
		local decimal = string.find(mantissa, ".", 1, true)
		local fractionDigits = decimal and (#mantissa - decimal) or 0
		return math.min(15, math.max(0, fractionDigits - (tonumber(exponentText) or 0)))
	end
	text = string.gsub(text, "0+$", "")
	local decimal = string.find(text, ".", 1, true)
	return math.min(15, decimal and (#text - decimal) or 0)
end

local function roundToStep(value, step, minimum)
	step = math.abs(tonumber(step) or 1)
	minimum = tonumber(minimum) or 0
	if step == 0 then
		return value
	end
	local rounded = math.floor(((value - minimum) / step) + 0.5) * step + minimum
	local decimals = math.max(decimalPlaces(step), decimalPlaces(minimum))
	local multiplier = 10 ^ decimals
	return math.floor(rounded * multiplier + 0.5) / multiplier
end

local function textWidth(text, size, font)
	font = resolveFont(font)
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(tostring(text), size, font, Vector2.new(10000, 10000))
	end)
	return ok and bounds.X or (#tostring(text) * size * 0.55)
end

local function colorToHex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function hexToColor(value)
	if type(value) ~= "string" then
		return nil
	end
	local hex = string.gsub(value, "#", "")
	if #hex == 3 then
		hex = string.sub(hex, 1, 1) .. string.sub(hex, 1, 1)
			.. string.sub(hex, 2, 2) .. string.sub(hex, 2, 2)
			.. string.sub(hex, 3, 3) .. string.sub(hex, 3, 3)
	end
	if not string.match(hex, "^%x%x%x%x%x%x$") then
		return nil
	end
	return Color3.fromRGB(
		tonumber(string.sub(hex, 1, 2), 16),
		tonumber(string.sub(hex, 3, 4), 16),
		tonumber(string.sub(hex, 5, 6), 16)
	)
end

local Themes = {
	Midnight = {
		Background = Color3.fromRGB(13, 15, 21),
		Surface = Color3.fromRGB(19, 22, 30),
		SurfaceAlt = Color3.fromRGB(26, 30, 40),
		SurfaceHover = Color3.fromRGB(34, 39, 52),
		Border = Color3.fromRGB(46, 52, 68),
		Text = Color3.fromRGB(239, 241, 247),
		Muted = Color3.fromRGB(145, 153, 174),
		Accent = Color3.fromRGB(108, 82, 240),
		AccentDark = Color3.fromRGB(79, 58, 196),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(63, 201, 138),
		Warning = Color3.fromRGB(245, 181, 68),
		Danger = Color3.fromRGB(242, 92, 112),
		Overlay = Color3.fromRGB(4, 5, 8),
	},
	Light = {
		Background = Color3.fromRGB(241, 243, 248),
		Surface = Color3.fromRGB(255, 255, 255),
		SurfaceAlt = Color3.fromRGB(235, 238, 245),
		SurfaceHover = Color3.fromRGB(224, 228, 238),
		Border = Color3.fromRGB(205, 210, 222),
		Text = Color3.fromRGB(30, 34, 45),
		Muted = Color3.fromRGB(101, 108, 126),
		Accent = Color3.fromRGB(104, 82, 232),
		AccentDark = Color3.fromRGB(80, 62, 191),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(36, 158, 103),
		Warning = Color3.fromRGB(198, 128, 22),
		Danger = Color3.fromRGB(205, 61, 82),
		Overlay = Color3.fromRGB(18, 20, 28),
	},
	Emerald = {
		Background = Color3.fromRGB(10, 17, 17),
		Surface = Color3.fromRGB(15, 25, 24),
		SurfaceAlt = Color3.fromRGB(21, 34, 32),
		SurfaceHover = Color3.fromRGB(29, 46, 42),
		Border = Color3.fromRGB(42, 66, 60),
		Text = Color3.fromRGB(235, 246, 242),
		Muted = Color3.fromRGB(137, 166, 157),
		Accent = Color3.fromRGB(46, 204, 150),
		AccentDark = Color3.fromRGB(28, 153, 109),
		AccentText = Color3.fromRGB(5, 28, 20),
		Success = Color3.fromRGB(69, 215, 151),
		Warning = Color3.fromRGB(238, 180, 67),
		Danger = Color3.fromRGB(239, 96, 110),
		Overlay = Color3.fromRGB(3, 8, 7),
	},
	Rose = {
		Background = Color3.fromRGB(20, 13, 18),
		Surface = Color3.fromRGB(30, 19, 27),
		SurfaceAlt = Color3.fromRGB(42, 26, 37),
		SurfaceHover = Color3.fromRGB(55, 34, 49),
		Border = Color3.fromRGB(73, 44, 64),
		Text = Color3.fromRGB(250, 238, 246),
		Muted = Color3.fromRGB(179, 143, 166),
		Accent = Color3.fromRGB(204, 59, 128),
		AccentDark = Color3.fromRGB(164, 42, 99),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(71, 202, 137),
		Warning = Color3.fromRGB(242, 178, 68),
		Danger = Color3.fromRGB(246, 83, 102),
		Overlay = Color3.fromRGB(9, 4, 8),
	},
	Ocean = {
		Background = Color3.fromRGB(7, 18, 28),
		Surface = Color3.fromRGB(11, 27, 41),
		SurfaceAlt = Color3.fromRGB(16, 38, 56),
		SurfaceHover = Color3.fromRGB(22, 52, 73),
		Border = Color3.fromRGB(35, 73, 98),
		Text = Color3.fromRGB(230, 246, 255),
		Muted = Color3.fromRGB(129, 166, 188),
		Accent = Color3.fromRGB(48, 189, 255),
		AccentDark = Color3.fromRGB(20, 132, 190),
		AccentText = Color3.fromRGB(4, 24, 36),
		Success = Color3.fromRGB(54, 208, 151),
		Warning = Color3.fromRGB(246, 185, 73),
		Danger = Color3.fromRGB(242, 91, 113),
		Overlay = Color3.fromRGB(2, 8, 14),
	},
	Violet = {
		Background = Color3.fromRGB(17, 12, 28),
		Surface = Color3.fromRGB(26, 18, 41),
		SurfaceAlt = Color3.fromRGB(37, 26, 57),
		SurfaceHover = Color3.fromRGB(51, 36, 76),
		Border = Color3.fromRGB(71, 51, 99),
		Text = Color3.fromRGB(246, 239, 255),
		Muted = Color3.fromRGB(170, 148, 194),
		Accent = Color3.fromRGB(142, 79, 225),
		AccentDark = Color3.fromRGB(105, 55, 184),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(73, 209, 145),
		Warning = Color3.fromRGB(246, 185, 73),
		Danger = Color3.fromRGB(244, 86, 119),
		Overlay = Color3.fromRGB(6, 3, 12),
	},
	Amber = {
		Background = Color3.fromRGB(22, 17, 9),
		Surface = Color3.fromRGB(32, 25, 14),
		SurfaceAlt = Color3.fromRGB(45, 35, 19),
		SurfaceHover = Color3.fromRGB(60, 47, 26),
		Border = Color3.fromRGB(82, 64, 34),
		Text = Color3.fromRGB(252, 245, 226),
		Muted = Color3.fromRGB(185, 163, 118),
		Accent = Color3.fromRGB(247, 173, 56),
		AccentDark = Color3.fromRGB(194, 122, 23),
		AccentText = Color3.fromRGB(39, 24, 4),
		Success = Color3.fromRGB(88, 198, 126),
		Warning = Color3.fromRGB(255, 193, 70),
		Danger = Color3.fromRGB(235, 83, 91),
		Overlay = Color3.fromRGB(9, 6, 2),
	},
	Nord = {
		Background = Color3.fromRGB(22, 27, 37),
		Surface = Color3.fromRGB(30, 37, 49),
		SurfaceAlt = Color3.fromRGB(39, 48, 63),
		SurfaceHover = Color3.fromRGB(49, 61, 78),
		Border = Color3.fromRGB(67, 82, 103),
		Text = Color3.fromRGB(236, 239, 244),
		Muted = Color3.fromRGB(151, 163, 183),
		Accent = Color3.fromRGB(136, 192, 208),
		AccentDark = Color3.fromRGB(94, 142, 163),
		AccentText = Color3.fromRGB(18, 29, 38),
		Success = Color3.fromRGB(163, 190, 140),
		Warning = Color3.fromRGB(235, 203, 139),
		Danger = Color3.fromRGB(191, 97, 106),
		Overlay = Color3.fromRGB(8, 11, 16),
	},
	Sakura = {
		Background = Color3.fromRGB(250, 244, 247),
		Surface = Color3.fromRGB(255, 251, 253),
		SurfaceAlt = Color3.fromRGB(247, 233, 240),
		SurfaceHover = Color3.fromRGB(240, 220, 230),
		Border = Color3.fromRGB(222, 194, 207),
		Text = Color3.fromRGB(54, 37, 48),
		Muted = Color3.fromRGB(125, 91, 109),
		Accent = Color3.fromRGB(196, 72, 125),
		AccentDark = Color3.fromRGB(158, 51, 99),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(49, 156, 105),
		Warning = Color3.fromRGB(196, 126, 33),
		Danger = Color3.fromRGB(204, 64, 89),
		Overlay = Color3.fromRGB(42, 24, 34),
	},
	Latte = {
		Background = Color3.fromRGB(244, 239, 231),
		Surface = Color3.fromRGB(253, 250, 245),
		SurfaceAlt = Color3.fromRGB(235, 227, 216),
		SurfaceHover = Color3.fromRGB(225, 214, 200),
		Border = Color3.fromRGB(204, 189, 169),
		Text = Color3.fromRGB(56, 47, 42),
		Muted = Color3.fromRGB(117, 101, 91),
		Accent = Color3.fromRGB(174, 88, 45),
		AccentDark = Color3.fromRGB(139, 66, 32),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(68, 148, 104),
		Warning = Color3.fromRGB(185, 116, 29),
		Danger = Color3.fromRGB(190, 63, 72),
		Overlay = Color3.fromRGB(43, 34, 28),
	},
	Crimson = {
		Background = Color3.fromRGB(21, 10, 13),
		Surface = Color3.fromRGB(32, 14, 19),
		SurfaceAlt = Color3.fromRGB(45, 20, 27),
		SurfaceHover = Color3.fromRGB(60, 27, 35),
		Border = Color3.fromRGB(83, 38, 49),
		Text = Color3.fromRGB(253, 239, 242),
		Muted = Color3.fromRGB(184, 135, 146),
		Accent = Color3.fromRGB(211, 46, 73),
		AccentDark = Color3.fromRGB(169, 31, 54),
		AccentText = Color3.fromRGB(255, 255, 255),
		Success = Color3.fromRGB(67, 195, 129),
		Warning = Color3.fromRGB(241, 175, 64),
		Danger = Color3.fromRGB(255, 80, 101),
		Overlay = Color3.fromRGB(8, 3, 5),
	},
	Cyber = {
		Background = Color3.fromRGB(5, 9, 17),
		Surface = Color3.fromRGB(8, 16, 28),
		SurfaceAlt = Color3.fromRGB(12, 24, 40),
		SurfaceHover = Color3.fromRGB(18, 35, 55),
		Border = Color3.fromRGB(31, 59, 81),
		Text = Color3.fromRGB(224, 250, 251),
		Muted = Color3.fromRGB(104, 153, 164),
		Accent = Color3.fromRGB(31, 231, 213),
		AccentDark = Color3.fromRGB(12, 164, 154),
		AccentText = Color3.fromRGB(1, 27, 27),
		Success = Color3.fromRGB(57, 255, 147),
		Warning = Color3.fromRGB(255, 210, 63),
		Danger = Color3.fromRGB(255, 70, 122),
		Overlay = Color3.fromRGB(1, 3, 7),
	},
	HighContrast = {
		Background = Color3.fromRGB(0, 0, 0),
		Surface = Color3.fromRGB(8, 8, 8),
		SurfaceAlt = Color3.fromRGB(18, 18, 18),
		SurfaceHover = Color3.fromRGB(34, 34, 34),
		Border = Color3.fromRGB(126, 126, 126),
		Text = Color3.fromRGB(255, 255, 255),
		Muted = Color3.fromRGB(205, 205, 205),
		Accent = Color3.fromRGB(255, 214, 0),
		AccentDark = Color3.fromRGB(193, 160, 0),
		AccentText = Color3.fromRGB(0, 0, 0),
		Success = Color3.fromRGB(65, 255, 148),
		Warning = Color3.fromRGB(255, 205, 40),
		Danger = Color3.fromRGB(255, 79, 99),
		Overlay = Color3.fromRGB(0, 0, 0),
	},
}

local function colorLuminance(color)
	local function channel(value)
		if value <= 0.04045 then
			return value / 12.92
		end
		return ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function bestContrastingText(background)
	local light = Color3.fromRGB(255, 255, 255)
	local dark = Color3.fromRGB(15, 18, 24)
	local backgroundLuminance = colorLuminance(background)
	local lightContrast = 1.05 / (backgroundLuminance + 0.05)
	local darkContrast = (backgroundLuminance + 0.05) / (colorLuminance(dark) + 0.05)
	return lightContrast >= darkContrast and light or dark
end

local function darkerAccent(accent)
	return accent:Lerp(Color3.new(0, 0, 0), 0.22)
end

local function interactiveColor(background, foreground, strength)
	local target = colorLuminance(foreground) > 0.5 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
	return background:Lerp(target, strength)
end

for _, theme in pairs(Themes) do
	theme.DangerText = bestContrastingText(theme.Danger)
	theme.SuccessText = bestContrastingText(theme.Success)
	theme.WarningText = bestContrastingText(theme.Warning)
end

Velora.Themes = Themes

local State = {}
State.__index = State

function State.new(owner)
	return setmetatable({
		_owner = owner,
		_values = {},
		_controls = {},
		_observers = {},
	}, State)
end

function State:Register(flag, control, defaultValue)
	if not flag then
		return defaultValue
	end
	local existing = self._controls[flag]
	if existing and existing ~= control then
		if self._owner.Options.Debug then
			warn("[Velora] Duplicate flag: " .. tostring(flag))
		end
		flag = flag .. "_" .. tostring(self._owner:_nextId())
		control.Flag = flag
	end
	self._controls[flag] = control
	if self._values[flag] == nil then
		self._values[flag] = deepCopy(defaultValue)
	end
	return deepCopy(self._values[flag])
end

function State:Unregister(flag, control)
	if flag and self._controls[flag] == control then
		self._controls[flag] = nil
	end
end

function State:_Commit(flag, value, previous, options)
	if not flag then
		return
	end
	self._values[flag] = deepCopy(value)
	if options and options.Silent then
		return
	end
	local observer = self._observers[flag]
	if observer then
		observer:Fire(value, previous, (options and options.Source) or "api")
	end
	local config = self._owner.Options.Config
	if type(config) == "table" and config.AutoSave and (not options or options.Source ~= "config") then
		self._owner:_scheduleAutoSave()
	end
end

function State:Get(flag)
	return deepCopy(self._values[flag])
end

function State:Set(flag, value, options)
	local control = self._controls[flag]
	if control and type(control.Set) == "function" then
		return control:Set(value, options)
	end
	local previous = self._values[flag]
	if valuesEqual(previous, value) then
		return false
	end
	self:_Commit(flag, value, previous, options)
	return true
end

function State:Observe(flag, callback)
	if not self._observers[flag] then
		self._observers[flag] = Signal.new()
	end
	return self._observers[flag]:Connect(callback)
end

function State:Destroy()
	for _, observer in pairs(self._observers) do
		observer:Destroy()
	end
	table.clear(self._observers)
	table.clear(self._controls)
	table.clear(self._values)
end

local Control = {}
Control.__index = Control

function Control:Get()
	return deepCopy(self._value)
end

Control.GetValue = Control.Get

function Control:Set(value, options)
	if self._destroyed then
		return false
	end
	if type(options) == "boolean" then
		options = { Silent = options }
	else
		options = options or {}
	end
	if self._sanitize then
		local ok, sanitized = pcall(self._sanitize, value, self)
		if not ok then
			warn("[Velora] Invalid value for " .. tostring(self.Flag or self.Title) .. ": " .. tostring(sanitized))
			return false
		end
		value = sanitized
	end
	local previous = self._value
	if valuesEqual(previous, value) and not options.Force then
		return false
	end
	self._value = deepCopy(value)
	if self._render then
		self:_render(value, previous, options)
	end
	self._ui.State:_Commit(self.Flag, value, previous, options)
	if not options.Silent then
		self.Changed:Fire(value, previous, options.Source or "api")
		safeCall(self.Callback, value, previous, options.Source or "api")
	end
	return true
end

Control.SetValue = Control.Set

function Control:Reset(options)
	options = options or {}
	options.Source = options.Source or "reset"
	return self:Set(deepCopy(self.Default), options)
end

function Control:OnChanged(callback)
	return self.Changed:Connect(callback)
end

function Control:SetVisible(visible)
	if self.Root then
		self.Root.Visible = visible == true
	end
	return self
end

function Control:SetDisabled(disabled, reason)
	self.Disabled = disabled == true
	self.DisabledReason = reason
	if self.DisabledOverlay then
		self.DisabledOverlay.Text = tostring(reason or "Locked")
		self.DisabledOverlay.Visible = self.Disabled
	end
	if self.Root then
		self.Root.Active = not self.Disabled
	end
	return self
end

function Control:Lock(reason)
	return self:SetDisabled(true, reason)
end

function Control:Unlock()
	return self:SetDisabled(false)
end

function Control:Highlight(duration)
	if not self.Stroke or not self.Root then
		return self
	end
	duration = tonumber(duration) or 0.8
	local originalTransparency = self.Stroke.Transparency
	self.Stroke.Thickness = 2
	self.Stroke.Transparency = 0
	self._ui:_bindTheme(self.Stroke, { Color = "Accent" })
	task.delay(duration, function()
		if self.Root and self.Root.Parent then
			self.Stroke.Thickness = 1
			self.Stroke.Transparency = originalTransparency
			self._ui:_bindTheme(self.Stroke, { Color = "Border" })
		end
	end)
	return self
end

function Control:SetTitle(title)
	self.Title = tostring(title or "")
	if self.TitleLabel then
		self.TitleLabel.Text = self.Title
	end
	if self._searchEntry then
		self._ui:_refreshSearchItem(self._searchEntry, self.Title, self.Description)
	end
	return self
end

function Control:SetDescription(description)
	self.Description = tostring(description or "")
	if self.DescriptionLabel then
		self.DescriptionLabel.Text = self.Description
		self.DescriptionLabel.Visible = self.Description ~= ""
	end
	if type(self._setMobile) == "function" then
		self:_setMobile(self._section._tab._mobile)
	elseif self.Root and self.TitleLabel and self._desktopHeight then
		local hasDescription = self.Description ~= ""
		self.Root.Size = UDim2.new(1, 0, 0, hasDescription and math.max(64, self._desktopHeight) or self._desktopHeight)
		self.TitleLabel.Position = UDim2.fromOffset(12, hasDescription and 10 or 0)
		self.TitleLabel.Size = UDim2.new(1, -128, 0, hasDescription and 21 or self._desktopHeight)
	end
	if self._section and self._section._tab then
		task.defer(self._section._tab._updateCanvas)
	end
	if self._searchEntry then
		self._ui:_refreshSearchItem(self._searchEntry, self.Title, self.Description)
	end
	return self
end

function Control:Destroy()
	if self._destroyed then
		return
	end
	if self._ui._popupOwner == self then
		self._ui:_closePopup()
		self._ui._popupOwner = nil
	end
	self._destroyed = true
	self._ui.State:Unregister(self.Flag, self)
	self.Changed:Destroy()
	self._maid:Clean()
	if self.Root then
		self.Root:Destroy()
	end
	if self._section then
		local index = table.find(self._section._controls, self)
		if index then
			table.remove(self._section._controls, index)
		end
	end
	if self._searchEntry then
		self._ui:_removeSearchItem(self._searchEntry)
		self._searchEntry = nil
	end
	self.Root = nil
end

local Window = {}
Window.__index = Window

local OpenButtonHandle = {}
OpenButtonHandle.__index = OpenButtonHandle

local createOpenButton

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

local function getEnvironmentFunction(name)
	local environments = {}
	if type(getgenv) == "function" then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == "table" then
			table.insert(environments, environment)
		end
	end
	table.insert(environments, _G)
	for _, environment in ipairs(environments) do
		local value = rawget(environment, name)
		if type(value) == "function" then
			return value
		end
	end
	return nil
end

local function resolveParent(options)
	if typeof(options.Parent) == "Instance" then
		return options.Parent
	end
	if options.Parent == "CoreGui" then
		local ok, coreGui = pcall(game.GetService, game, "CoreGui")
		if ok then
			return coreGui
		end
	end
	if options.Parent == "Auto" or options.ExecutorParent then
		local getHiddenUi = getEnvironmentFunction("gethui")
		if getHiddenUi then
			local ok, hiddenUi = pcall(getHiddenUi)
			if ok and typeof(hiddenUi) == "Instance" then
				return hiddenUi
			end
		end
	end
	local player = Players.LocalPlayer
	if not player then
		Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
		player = Players.LocalPlayer
	end
	if player then
		return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	end
	error("Velora requires a LocalPlayer or an explicit Parent")
end

function Velora:_nextId()
	self._id = self._id + 1
	return self._id
end

function Velora:_bindTheme(object, mapping)
	if not object then
		return object
	end
	self._themeBindings[object] = mapping
	if not self._themeBindingConnections[object] then
		local connection
		connection = object.Destroying:Connect(function()
			self._themeBindings[object] = nil
			self._themeBindingConnections[object] = nil
		end)
		self._themeBindingConnections[object] = connection
	end
	for property, token in pairs(mapping) do
		local value = type(token) == "string" and self.Theme[token] or token
		if value ~= nil then
			object[property] = value
		end
	end
	return object
end

function Velora:_tween(object, duration, goals, style, direction)
	if not object or not object.Parent then
		return nil
	end
	local existing = self._activeTweens[object]
	if existing then
		existing:Cancel()
		self._activeTweens[object] = nil
	end
	if self.Options.ReducedMotion or duration <= 0 then
		for property, value in pairs(goals) do
			object[property] = value
		end
		return nil
	end
	local tween = TweenService:Create(
		object,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goals
	)
	self._activeTweens[object] = tween
	local connection
	connection = tween.Completed:Connect(function()
		if connection then
			connection:Disconnect()
		end
		if self._activeTweens[object] == tween then
			self._activeTweens[object] = nil
		end
	end)
	tween:Play()
	return tween
end

function Velora:RegisterTheme(name, tokens)
	assert(type(name) == "string", "Theme name must be a string")
	assert(type(tokens) == "table", "Theme tokens must be a table")
	local theme = deepMerge(Themes.Midnight, tokens)
	if tokens.Accent ~= nil then
		theme.AccentDark = tokens.AccentDark or darkerAccent(theme.Accent)
		theme.AccentText = tokens.AccentText or bestContrastingText(theme.Accent)
	end
	if tokens.Danger ~= nil and tokens.DangerText == nil then
		theme.DangerText = bestContrastingText(theme.Danger)
	end
	if tokens.Success ~= nil and tokens.SuccessText == nil then
		theme.SuccessText = bestContrastingText(theme.Success)
	end
	if tokens.Warning ~= nil and tokens.WarningText == nil then
		theme.WarningText = bestContrastingText(theme.Warning)
	end
	for token in pairs(Themes.Midnight) do
		assert(typeof(theme[token]) == "Color3", "Theme token " .. tostring(token) .. " must be a Color3")
	end
	self._themes[name] = theme
	return self._themes[name]
end

function Velora:_autoSaveIfEnabled(source, silent)
	local config = self.Options.Config
	if not silent and source ~= "config" and type(config) == "table" and config.AutoSave then
		self:_scheduleAutoSave()
	end
end

function Velora:SetTheme(theme, setOptions)
	setOptions = setOptions or {}
	local nextTheme
	local themeName
	if type(theme) == "string" then
		nextTheme = self._themes[theme]
		themeName = theme
	elseif type(theme) == "table" then
		nextTheme = deepMerge(self.Theme, theme)
		themeName = "Custom"
		if theme.Accent ~= nil then
			nextTheme.AccentDark = theme.AccentDark or darkerAccent(nextTheme.Accent)
			nextTheme.AccentText = theme.AccentText or bestContrastingText(nextTheme.Accent)
		end
		if theme.Danger ~= nil and theme.DangerText == nil then
			nextTheme.DangerText = bestContrastingText(nextTheme.Danger)
		end
		if theme.Success ~= nil and theme.SuccessText == nil then
			nextTheme.SuccessText = bestContrastingText(nextTheme.Success)
		end
		if theme.Warning ~= nil and theme.WarningText == nil then
			nextTheme.WarningText = bestContrastingText(nextTheme.Warning)
		end
	end
	if not nextTheme then
		return false, "Unknown theme"
	end
	for token in pairs(Themes.Midnight) do
		if typeof(nextTheme[token]) ~= "Color3" then
			return false, "Theme token " .. tostring(token) .. " must be a Color3"
		end
	end
	self.Theme = deepCopy(nextTheme)
	self.ThemeName = themeName
	if self.Options.Accent then
		self.Theme.Accent = self.Options.Accent
		self.Theme.AccentDark = darkerAccent(self.Options.Accent)
		self.Theme.AccentText = bestContrastingText(self.Options.Accent)
	end
	for object, mapping in pairs(self._themeBindings) do
		if object.Parent then
			local colorGoals = {}
			for property, token in pairs(mapping) do
				local value = type(token) == "string" and self.Theme[token] or token
				if value ~= nil then
					if typeof(value) == "Color3" and typeof(object[property]) == "Color3" then
						colorGoals[property] = value
					else
						object[property] = value
					end
				end
			end
			if next(colorGoals) then
				self:_tween(object, 0.18, colorGoals)
			end
		else
			self._themeBindings[object] = nil
			local connection = self._themeBindingConnections[object]
			if connection then
				connection:Disconnect()
				self._themeBindingConnections[object] = nil
			end
		end
	end
	self.ThemeChanged:Fire(themeName, deepCopy(self.Theme))
	self:_autoSaveIfEnabled(setOptions.Source, setOptions.Silent)
	return true
end

function Velora:SetAccent(color, setOptions)
	if type(color) == "string" then
		color = hexToColor(color)
	end
	if typeof(color) ~= "Color3" then
		return false
	end
	self.Options.Accent = color
	return self:SetTheme({
		Accent = color,
		AccentDark = darkerAccent(color),
		AccentText = bestContrastingText(color),
	}, setOptions)
end

function Velora:GetFlag(flag)
	return self.State:Get(flag)
end

function Velora:SetFlag(flag, value, options)
	return self.State:Set(flag, value, options)
end

function Velora:Observe(flag, callback)
	return self.State:Observe(flag, callback)
end

function Velora.new(options)
	assert(RunService:IsClient(), "Velora UI must be created from a LocalScript or client executor")
	options = deepMerge({
		Name = "VeloraUI",
		Parent = "Auto",
		Theme = "Midnight",
		Accent = nil,
		DisplayOrder = 1000,
		IgnoreGuiInset = false,
		ReducedMotion = false,
		ToggleKey = Enum.KeyCode.G,
		Mobile = true,
		Debug = false,
		DestroyExisting = false,
		OpenButton = {},
		Config = {
			Folder = "Velora",
			File = "default",
			AutoSave = false,
		},
	}, options or {})
	if type(options.Accent) == "string" then
		options.Accent = hexToColor(options.Accent)
	end
	assert(options.Accent == nil or typeof(options.Accent) == "Color3", "Accent must be a Color3 or hex string")

	local self = setmetatable({}, Velora)
	self.Options = options
	self._id = 0
	self._destroyed = false
	self._maid = Maid.new()
	self._themes = deepCopy(Themes)
	self.Theme = deepCopy(self._themes[options.Theme] or self._themes.Midnight)
	self.ThemeName = self._themes[options.Theme] and options.Theme or "Midnight"
	if options.Accent then
		self.Theme.Accent = options.Accent
		self.Theme.AccentDark = darkerAccent(options.Accent)
		self.Theme.AccentText = bestContrastingText(options.Accent)
	end
	self._themeBindings = {}
	self._themeBindingConnections = {}
	self._activeTweens = setmetatable({}, { __mode = "k" })
	self._windows = {}
	self._notifications = {}
	self._commands = {}
	self._searchItems = {}
	self._memoryConfigs = {}
	self._pendingTransparency = {}
	self._autosaveRevision = 0
	self._popupMaid = nil
	self._dialogMaid = nil
	self._capturingKeybind = nil
	self.ThemeChanged = Signal.new()
	self.State = State.new(self)
	self.Flags = self.State._values

	local parent = resolveParent(options)
	local modalName = options.Name .. "_Modal"
	local floatingName = options.Name .. "_Floating"
	if options.DestroyExisting then
		for _, guiName in ipairs({ options.Name, modalName, floatingName }) do
			for _, existing in ipairs(parent:GetChildren()) do
				if existing.Name == guiName and existing:IsA("ScreenGui") then
					existing:Destroy()
				end
			end
		end
	end

	self.ScreenGui = create("ScreenGui", {
		Name = options.Name,
		IgnoreGuiInset = options.IgnoreGuiInset == true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = options.DisplayOrder,
		Parent = parent,
	})
	self._maid:Give(self.ScreenGui)
	self._maid:Give(self.ScreenGui.Destroying:Connect(function()
		if not self._destroyed then
			self:Destroy()
		end
	end))
	self.FloatingGui = create("ScreenGui", {
		Name = floatingName,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = (tonumber(options.DisplayOrder) or 1000) + 1,
		Parent = parent,
	})
	self._maid:Give(self.FloatingGui)
	self._maid:Give(self.FloatingGui.Destroying:Connect(function()
		if not self._destroyed then
			self:Destroy()
		end
	end))
	self.ModalGui = create("ScreenGui", {
		Name = modalName,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = (tonumber(options.DisplayOrder) or 1000) + 2,
		Parent = parent,
	})
	self._maid:Give(self.ModalGui)
	self._maid:Give(self.ModalGui.Destroying:Connect(function()
		if not self._destroyed then
			self:Destroy()
		end
	end))

	self.WindowLayer = create("Frame", {
		Name = "Windows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = self.ScreenGui,
	})
	self.OpenButtonLayer = create("Frame", {
		Name = "FloatingControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 990,
		Parent = self.FloatingGui,
	})
	self.PopupLayer = create("Frame", {
		Name = "Popups",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 500,
		Parent = self.ScreenGui,
	})
	self.ModalLayer = create("Frame", {
		Name = "Modals",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 700,
		Parent = self.ModalGui,
	})
	self.NotificationLayer = create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(1, -24, 1, -32),
		ZIndex = 900,
		Parent = self.ScreenGui,
	})
	create("UISizeConstraint", {
		MaxSize = Vector2.new(340, 100000),
		MinSize = Vector2.new(140, 0),
		Parent = self.NotificationLayer,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.NotificationLayer,
	})
	local openButtonOptions = options.OpenButton
	if openButtonOptions == false then
		openButtonOptions = { Enabled = false }
	elseif type(openButtonOptions) ~= "table" then
		openButtonOptions = {}
	end
	self.OpenButton = createOpenButton(self, openButtonOptions)
	self.RestoreButton = self.OpenButton and self.OpenButton.Root or nil
	if self.OpenButton then
		self._maid:Give(self.OpenButton)
	end
	self._visible = true

	self._maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or self._capturingKeybind then
			return
		end
		if options.ToggleKey and input.KeyCode == options.ToggleKey then
			self:Toggle()
		elseif input.KeyCode == Enum.KeyCode.K and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			self:OpenCommandPalette()
		end
	end))

	local config = options.Config
	if type(config) == "table" and config.AutoLoad then
		task.defer(function()
			if not self._destroyed then
				self:LoadConfig(config.File, { Silent = config.SilentLoad == true })
			end
		end)
	end
	return self
end

function Velora:_updateRestoreButton()
	local handle = self.OpenButton
	if not handle or not handle:_isAlive() then
		return
	end
	local hasVisibleWindow = false
	local minimizedTarget
	for _, window in ipairs(self._windows) do
		if not window._destroyed and window.Root and window._minimizedToOpenButton then
			if handle.Target == window then
				minimizedTarget = window
			elseif not minimizedTarget then
				minimizedTarget = window
			end
		end
		if not window._destroyed and window.Root and window.Root.Visible then
			hasVisibleWindow = true
		end
	end
	if minimizedTarget then
		handle.Target = minimizedTarget
	end
	local hasWindows = #self._windows > 0
	local allWindowsHidden = hasWindows and not hasVisibleWindow
	local hidden = not self._visible or allWindowsHidden
	local automatic = hasWindows and hidden
	if handle.Options.OnlyMobile == true
		and not UserInputService.TouchEnabled
		and UserInputService.KeyboardEnabled
		and self.Options.ToggleKey ~= nil
		and not allWindowsHidden
	then
		automatic = false
	end
	local visible = minimizedTarget ~= nil
	if not visible then
		visible = handle._visibilityOverride
		if visible == nil then
			visible = automatic
		else
			visible = hasWindows and visible
		end
	end
	handle.Root.Visible = handle.Options.Enabled ~= false and visible
end

function Velora:_cancelKeybindCapture()
	local control = self._capturingKeybind
	if control and not control._destroyed and control._cancelCapture then
		control:_cancelCapture()
	else
		self._capturingKeybind = nil
	end
end

function Velora:SetVisible(visible)
	visible = visible == true
	self._visible = visible
	if not visible then
		self:_cancelKeybindCapture()
		self:_closePopup()
		self:CloseCommandPalette()
	end
	if self.WindowLayer then
		self.WindowLayer.Visible = visible
		self.PopupLayer.Visible = visible
		self.NotificationLayer.Visible = visible
	end
	if self.ModalGui then
		self.ModalGui.Enabled = visible
	end
	self:_updateRestoreButton()
	return self
end

function Velora:IsVisible()
	return not self._destroyed and self._visible == true and self.ScreenGui ~= nil and self.ScreenGui.Parent ~= nil
end

function Velora:Toggle()
	return self:SetVisible(not self:IsVisible())
end

function Velora:EditOpenButton(options)
	if self.OpenButton then
		return self.OpenButton:Edit(options)
	end
	return nil
end

function Velora:GetOpenButton()
	return self.OpenButton
end

function Velora:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._autosaveRevision = self._autosaveRevision + 1
	self:_closePopup()
	self:CloseCommandPalette()
	if self._dialogMaid then
		self._dialogMaid:Clean()
		self._dialogMaid = nil
	end
	for _, notification in ipairs(shallowCopy(self._notifications)) do
		notification._closed = true
		notification._revision = notification._revision + 1
		notification._maid:Clean()
	end
	for object, tween in pairs(self._activeTweens) do
		if object then
			tween:Cancel()
		end
	end
	for _, window in ipairs(shallowCopy(self._windows)) do
		window:Destroy()
	end
	self.State:Destroy()
	self.ThemeChanged:Destroy()
	self._maid:Clean()
	self.ScreenGui = nil
	self.FloatingGui = nil
	self.ModalGui = nil
	self.ModalLayer = nil
	self.WindowLayer = nil
	self.OpenButtonLayer = nil
	self.PopupLayer = nil
	self.NotificationLayer = nil
	table.clear(self._windows)
	table.clear(self._notifications)
	table.clear(self._commands)
	table.clear(self._searchItems)
	table.clear(self._pendingTransparency)
end

Velora.Unload = Velora.Destroy

function Velora:_closePopup()
	if self._popupMaid then
		self._popupMaid:Clean()
		self._popupMaid = nil
	end
end

function Velora:_openPopup(anchor, options)
	self:_closePopup()
	options = options or {}
	local maid = Maid.new()
	self._popupMaid = maid

	local blocker = create("TextButton", {
		Name = "PopupBlocker",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 500,
		Parent = self.PopupLayer,
	})
	maid:Give(blocker)

	local popup = create("Frame", {
		Name = options.Name or "Popup",
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(options.Width or 280, options.Height or 220),
		ZIndex = 502,
		Parent = self.PopupLayer,
	})
	addCorner(popup, 10)
	local popupStroke = addStroke(popup, self.Theme.Border, 0, 1)
	self:_bindTheme(popup, { BackgroundColor3 = "Surface" })
	self:_bindTheme(popupStroke, { Color = "Border" })
	maid:Give(popup)

	local function place()
		if not anchor or not anchor.Parent or not popup.Parent then
			return
		end
		local viewport = self.PopupLayer.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local anchorPosition = anchor.AbsolutePosition - self.PopupLayer.AbsolutePosition
		local anchorSize = anchor.AbsoluteSize
		local popupSize = popup.AbsoluteSize
		local maximumWidth = math.max(80, viewport.X - 20)
		local maximumHeight = math.max(40, viewport.Y - 20)
		if popupSize.X > maximumWidth or popupSize.Y > maximumHeight then
			popup.Size = UDim2.fromOffset(math.min(popupSize.X, maximumWidth), math.min(popupSize.Y, maximumHeight))
			popupSize = Vector2.new(math.min(popupSize.X, maximumWidth), math.min(popupSize.Y, maximumHeight))
		end
		local x = anchorPosition.X + anchorSize.X - popupSize.X
		local y = anchorPosition.Y + anchorSize.Y + 8
		if y + popupSize.Y > viewport.Y - 10 then
			y = anchorPosition.Y - popupSize.Y - 8
		end
		x = math.clamp(x, 10, math.max(10, viewport.X - popupSize.X - 10))
		y = math.clamp(y, 10, math.max(10, viewport.Y - popupSize.Y - 10))
		popup.Position = UDim2.fromOffset(x, y)
	end

	maid:Give(blocker.Activated:Connect(function()
		self:_closePopup()
	end))
	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			self:_closePopup()
		end
	end))
	maid:Give(anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
	maid:Give(anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	maid:Give(self.PopupLayer:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
	maid:Give(self.PopupLayer:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	task.defer(place)

	return popup, maid, place
end

local function makeIconLabel(parent, text, size, zIndex)
	local iconText = tostring(text or "*")
	local image
	if type(text) == "number" or string.match(iconText, "^%d+$") then
		image = "rbxassetid://" .. iconText
	elseif string.match(iconText, "^rbxasset") or string.match(iconText, "^rbxthumb") then
		image = iconText
	end
	if image then
		return create("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size or 20, size or 20),
			Image = image,
			ImageColor3 = Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex or 1,
			Parent = parent,
		})
	end
	if #iconText > 2 and string.match(iconText, "^[%w_%-]+$") then
		iconText = string.upper(string.sub(iconText, 1, 1))
	end
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size or 20, size or 20),
		Font = Enum.Font.GothamBold,
		Text = iconText,
		TextSize = math.floor((size or 20) * 0.62),
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
end

local function bindIconTheme(ui, icon, token)
	if icon:IsA("ImageLabel") then
		ui:_bindTheme(icon, { ImageColor3 = token })
	else
		ui:_bindTheme(icon, { TextColor3 = token })
	end
end

function OpenButtonHandle:_isAlive()
	return not self._destroyed and self.Root ~= nil and self.Root.Parent ~= nil and not self._ui._destroyed
end

function OpenButtonHandle:_resolveTitle()
	if self.Options.Title ~= nil then
		return tostring(self.Options.Title)
	end
	if self.Target and not self.Target._destroyed then
		return tostring(self.Target.Options.Title)
	end
	return tostring(self._ui.Options.Name)
end

function OpenButtonHandle:_resolveIcon()
	if self.Options.Icon ~= nil and self.Options.Icon ~= false then
		return self.Options.Icon
	end
	if self.Target and not self.Target._destroyed and self.Target.Options.Icon ~= nil then
		return self.Target.Options.Icon
	end
	return string.sub(self:_resolveTitle(), 1, 1)
end

local function defaultOpenButtonPosition()
	local topInset = 0
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(inset) == "Vector2" then
		topInset = math.max(0, inset.Y)
	end
	local topbarOk, topbarInset = pcall(function()
		return GuiService.TopbarInset
	end)
	if topbarOk and typeof(topbarInset) == "Rect" then
		topInset = math.max(topInset, topbarInset.Max.Y)
	end
	return UDim2.new(0.5, 0, 0, topInset + 34)
end

function OpenButtonHandle:_render()
	if not self:_isAlive() then
		return self
	end
	local title = self:_resolveTitle()
	local onlyIcon = self.Options.OnlyIcon == true
	local draggable = self.Options.Draggable ~= false
	local dragWidth = draggable and 40 or 0
	local actionWidth = onlyIcon and 44 or math.clamp(textWidth(title, 13, Typography.Medium) + 58, 104, 240)
	self.Root.Size = UDim2.fromOffset(dragWidth + actionWidth, 44)
	self.Root.BackgroundTransparency = math.clamp(tonumber(self.Options.Transparency) or 0.08, 0, 1)
	self.DragHandle.Visible = draggable
	self.Divider.Visible = draggable
	self.Action.Position = UDim2.fromOffset(dragWidth, 0)
	self.Action.Size = UDim2.new(1, -dragWidth, 1, 0)
	self.TitleLabel.Text = title
	self.TitleLabel.Visible = not onlyIcon
	self.IconHost.AnchorPoint = onlyIcon and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5)
	self.IconHost.Position = onlyIcon and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 12, 0.5, 0)
	if self.Icon then
		self._ui._themeBindings[self.Icon] = nil
		self.Icon:Destroy()
	end
	self.Icon = makeIconLabel(self.IconHost, self:_resolveIcon(), 22, 998)
	self.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
	self.Icon.Position = UDim2.fromScale(0.5, 0.5)
	bindIconTheme(self._ui, self.Icon, "Text")

	local scale = math.clamp(tonumber(self.Options.Scale) or 1, 0.6, 1.5)
	self.Scale.Scale = scale
	local radius = self.Options.CornerRadius
	if typeof(radius) == "UDim" then
		self.Corner.CornerRadius = radius
	elseif tonumber(radius) then
		self.Corner.CornerRadius = UDim.new(0, tonumber(radius))
	else
		self.Corner.CornerRadius = UDim.new(1, 0)
	end
	self.Stroke.Thickness = math.clamp(tonumber(self.Options.StrokeThickness) or 1, 0, 4)
	local color = self.Options.Color
	if typeof(color) == "Color3" then
		self._ui._themeBindings[self.Stroke] = nil
		self.Gradient.Enabled = false
		self.Stroke.Color = color
	elseif typeof(color) == "ColorSequence" then
		self._ui._themeBindings[self.Stroke] = nil
		self.Stroke.Color = Color3.new(1, 1, 1)
		self.Gradient.Color = color
		self.Gradient.Enabled = true
	else
		self.Gradient.Enabled = false
		self._ui:_bindTheme(self.Stroke, { Color = "Border" })
	end
	if typeof(self.Options.Position) == "UDim2" then
		self.Root.Position = self.Options.Position
	end
	self._ui:_updateRestoreButton()
	return self
end

function OpenButtonHandle:Edit(options)
	if self._destroyed then
		return self
	end
	if options == false then
		options = { Enabled = false }
	end
	if type(options) == "table" and options.Enabled == false then
		for _, window in ipairs(shallowCopy(self._ui._windows)) do
			if not window._destroyed and window._minimizedToOpenButton then
				window:Restore()
			end
		end
	end
	if type(options) == "table" then
		self.Options = deepMerge(self.Options, options)
	end
	return self:_render()
end

OpenButtonHandle.Update = OpenButtonHandle.Edit

function OpenButtonHandle:SetEnabled(enabled)
	return self:Edit({ Enabled = enabled == true })
end

function OpenButtonHandle:SetTitle(title)
	self.Options.Title = title
	return self:_render()
end

function OpenButtonHandle:SetIcon(icon)
	self.Options.Icon = icon
	return self:_render()
end

function OpenButtonHandle:SetPosition(position)
	if typeof(position) == "UDim2" then
		self.Options.Position = position
	end
	return self:_render()
end

function OpenButtonHandle:ResetPosition()
	self.Options.Position = defaultOpenButtonPosition()
	return self:_render()
end

function OpenButtonHandle:SetScale(scale)
	return self:Edit({ Scale = scale })
end

function OpenButtonHandle:Visible(visible)
	if self._destroyed or not self._ui then
		return self
	end
	if visible == false then
		for _, window in ipairs(shallowCopy(self._ui._windows)) do
			if not window._destroyed and window._minimizedToOpenButton then
				window:Restore()
			end
		end
	end
	if visible == nil then
		self._visibilityOverride = nil
	else
		self._visibilityOverride = visible == true
	end
	self._ui:_updateRestoreButton()
	return self
end

OpenButtonHandle.SetVisible = OpenButtonHandle.Visible

function OpenButtonHandle:IsVisible()
	return self:_isAlive() and self.Root.Visible or false
end

function OpenButtonHandle:Open()
	if not self:_isAlive() then
		return self
	end
	local target = self.Target
	if not target or target._destroyed or not target.Root then
		target = nil
		for _, window in ipairs(self._ui._windows) do
			if not window._destroyed and window.Root then
				target = window
				break
			end
		end
		self.Target = target
	end
	self._ui:SetVisible(true)
	if target then
		if target._minimized then
			target:Restore()
		else
			target:SetVisible(true)
		end
	end
	self._ui:_updateRestoreButton()
	return self
end

function OpenButtonHandle:Destroy()
	if self._destroyed then
		return
	end
	if self._ui and not self._ui._destroyed then
		for _, window in ipairs(shallowCopy(self._ui._windows)) do
			if not window._destroyed and window._minimizedToOpenButton then
				window:Restore()
			end
		end
	end
	self._destroyed = true
	local ui = self._ui
	self._maid:Clean()
	if ui and ui.OpenButton == self then
		ui.OpenButton = nil
		ui.RestoreButton = nil
	end
	self.Root = nil
	self.Target = nil
	self._ui = nil
end

createOpenButton = function(ui, options)
	local initialPosition = typeof(options.Position) == "UDim2" and options.Position or defaultOpenButtonPosition()
	local handle = setmetatable({
		_ui = ui,
		Options = deepMerge({
			Enabled = true,
			Position = initialPosition,
			OnlyIcon = false,
			OnlyMobile = false,
			Draggable = true,
			Scale = 1,
			Transparency = 0.08,
			CornerRadius = UDim.new(1, 0),
			StrokeThickness = 1,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 201, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 28, 255)),
			}),
		}, options),
		_maid = Maid.new(),
		_destroyed = false,
		_visibilityOverride = nil,
		Target = nil,
	}, OpenButtonHandle)

	local root = create("Frame", {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = initialPosition,
		Size = UDim2.fromOffset(148, 44),
		BackgroundColor3 = ui.Theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		Visible = false,
		ZIndex = 995,
		Parent = ui.OpenButtonLayer,
	})
	handle.Root = root
	handle._maid:Give(root)
	ui:_bindTheme(root, { BackgroundColor3 = "Surface" })
	handle.Corner = addCorner(root, 22)
	handle.Stroke = addStroke(root, Color3.new(1, 1, 1), 0, 1)
	handle.Gradient = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 201, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 28, 255)),
		}),
		Parent = handle.Stroke,
	})
	handle.Scale = create("UIScale", { Scale = 1, Parent = root })

	handle.DragHandle = create("TextButton", {
		Name = "Drag",
		Size = UDim2.fromOffset(40, 44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Typography.Bold,
		Text = "≡",
		TextSize = 17,
		TextColor3 = ui.Theme.Muted,
		ZIndex = 997,
		Parent = root,
	})
	ui:_bindTheme(handle.DragHandle, { TextColor3 = "Muted" })
	handle.Divider = create("Frame", {
		Position = UDim2.fromOffset(39, 10),
		Size = UDim2.fromOffset(1, 24),
		BackgroundColor3 = ui.Theme.Border,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 997,
		Parent = root,
	})
	ui:_bindTheme(handle.Divider, { BackgroundColor3 = "Border" })
	handle.Action = create("TextButton", {
		Name = "Action",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundColor3 = ui.Theme.SurfaceHover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 996,
		Parent = root,
	})
	ui:_bindTheme(handle.Action, { BackgroundColor3 = "SurfaceHover" })
	handle.IconHost = create("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ZIndex = 997,
		Parent = handle.Action,
	})
	handle.TitleLabel = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -54, 1, 0),
		BackgroundTransparency = 1,
		Font = Typography.Medium,
		Text = "",
		TextSize = 13,
		TextColor3 = ui.Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 997,
		Parent = handle.Action,
	})
	ui:_bindTheme(handle.TitleLabel, { TextColor3 = "Text" })

	handle._maid:Give(handle.Action.MouseEnter:Connect(function()
		ui:_tween(handle.Action, 0.12, { BackgroundTransparency = 0.86 })
	end))
	handle._maid:Give(handle.Action.MouseLeave:Connect(function()
		ui:_tween(handle.Action, 0.12, { BackgroundTransparency = 1 })
	end))
	handle._maid:Give(handle.Action.Activated:Connect(function()
		handle:Open()
	end))

	local dragging = false
	local dragInput
	local dragStart
	local startPosition
	local moved = false
	handle._maid:Give(handle.DragHandle.InputBegan:Connect(function(input)
		if dragging or handle.Options.Draggable == false then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		dragInput = input
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		startPosition = root.Position
		moved = false
	end))
	handle._maid:Give(UserInputService.InputChanged:Connect(function(input)
		if not dragging or not dragInput then
			return
		end
		local mouseDrag = dragInput.UserInputType == Enum.UserInputType.MouseButton1
		if input ~= dragInput and not (mouseDrag and input.UserInputType == Enum.UserInputType.MouseMovement) then
			return
		end
		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - dragStart
		if delta.Magnitude > 6 then
			moved = true
		end
		if moved then
			root.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end))
	handle._maid:Give(UserInputService.InputEnded:Connect(function(input)
		if not dragging or not dragInput then
			return
		end
		local mouseDrag = dragInput.UserInputType == Enum.UserInputType.MouseButton1
		if input ~= dragInput and not (mouseDrag and input.UserInputType == Enum.UserInputType.MouseButton1) then
			return
		end
		if moved then
			handle.Options.Position = root.Position
		end
		dragging = false
		dragInput = nil
	end))
	handle:_render()
	return handle
end

function Velora:CreateWindow(options)
	local providedOptions = options or {}
	options = deepMerge({
		Title = "Velora UI",
		Subtitle = "Universal interface",
		Icon = "V",
		Size = UDim2.fromOffset(900, 590),
		MinSize = Vector2.new(560, 390),
		MaxSize = Vector2.new(1280, 860),
		Resizable = true,
		Search = true,
		ShowUser = true,
		CloseBehavior = "Destroy",
		ConfirmOnClose = true,
		CloseConfirmTitle = "是否关闭窗口",
		CloseConfirmCancel = "否",
		CloseConfirmConfirm = "是",
		MinimizeToOpenButton = true,
	}, options or {})
	if providedOptions.Name and providedOptions.Title == nil then
		options.Title = providedOptions.Name
	end
	if providedOptions.ToggleUIKeybind then
		local key = providedOptions.ToggleUIKeybind
		if type(key) == "string" then
			local ok, enumKey = pcall(function()
				return Enum.KeyCode[key]
			end)
			key = ok and enumKey or nil
		end
		if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
			self.Options.ToggleKey = key
		end
	end
	if providedOptions.Theme then
		self:SetTheme(providedOptions.Theme)
	end

	local window = setmetatable({}, Window)
	window._ui = self
	window.Options = options
	window._maid = Maid.new()
	window._destroyed = false
	window._tabs = {}
	window._selectedTab = nil
	window._minimized = false
	window._minimizedToOpenButton = false
	window._closeDialog = nil
	window._mobile = false
	window._requestedSize = Vector2.new(options.Size.X.Offset, options.Size.Y.Offset)
	window._lastExpandedSize = options.Size
	window._id = self:_nextId()
	window.TabChanged = Signal.new()

	local root = create("Frame", {
		Name = "Window_" .. tostring(window._id),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = options.Position or UDim2.fromScale(0.5, 0.5),
		Size = options.Size,
		BackgroundTransparency = 1,
		Parent = self.WindowLayer,
	})
	window.Root = root
	window._maid:Give(root)

	local panel = create("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = root,
	})
	addCorner(panel, 14)
	self:_bindTheme(panel, { BackgroundColor3 = "Background" })
	window.Panel = panel

	local topbar = create("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = panel,
	})
	self:_bindTheme(topbar, { BackgroundColor3 = "Surface" })
	window.Topbar = topbar

	local accentLine = create("Frame", {
		Name = "Accent",
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = topbar,
	})
	self:_bindTheme(accentLine, { BackgroundColor3 = "Accent" })
	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = accentLine,
	})

	local brand = create("Frame", {
		Name = "Brand",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 9),
		Size = UDim2.fromOffset(200, 42),
		ZIndex = 6,
		Parent = topbar,
	})
	local logo = create("Frame", {
		Name = "Logo",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = brand,
	})
	addCorner(logo, 10)
	self:_bindTheme(logo, { BackgroundColor3 = "Accent" })
	local logoText = makeIconLabel(logo, options.Icon, 36, 8)
	logoText.Size = UDim2.fromScale(1, 1)
	bindIconTheme(self, logoText, "AccentText")

	local brandTitle = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -48, 0, 22),
		Font = Enum.Font.GothamBold,
		Text = tostring(options.Title),
		TextSize = 15,
		TextColor3 = self.Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = brand,
	})
	local brandSubtitle = create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 21),
		Size = UDim2.new(1, -48, 0, 17),
		Font = Enum.Font.Gotham,
		Text = tostring(options.Subtitle),
		TextSize = 11,
		TextColor3 = self.Theme.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = brand,
	})
	self:_bindTheme(brandTitle, { TextColor3 = "Text" })
	self:_bindTheme(brandSubtitle, { TextColor3 = "Muted" })
	window.BrandTitle = brandTitle
	window.BrandSubtitle = brandSubtitle

	local divider = create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(219, 12),
		Size = UDim2.fromOffset(1, 34),
		BackgroundColor3 = self.Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = topbar,
	})
	self:_bindTheme(divider, { BackgroundColor3 = "Border" })
	window.TopDivider = divider

	local pageTitle = create("TextLabel", {
		Name = "PageTitle",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(238, 0),
		Size = UDim2.new(1, -410, 1, 0),
		Font = Enum.Font.GothamMedium,
		Text = "Overview",
		TextSize = 14,
		TextColor3 = self.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = topbar,
	})
	self:_bindTheme(pageTitle, { TextColor3 = "Text" })
	window.PageTitle = pageTitle

	local function makeTopButton(name, text, order, danger)
		local button = create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(14 + ((order - 1) * 38)), 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			AutoButtonColor = false,
			BackgroundColor3 = self.Theme.SurfaceAlt,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 16,
			TextColor3 = self.Theme.Muted,
			ZIndex = 8,
			Parent = topbar,
		})
		addCorner(button, 9)
		self:_bindTheme(button, {
			BackgroundColor3 = "SurfaceAlt",
			TextColor3 = "Muted",
		})
		local hovered = false
		local pressed = false
		local function renderState(duration)
			local background = self.Theme.SurfaceAlt
			local foreground = self.Theme.Muted
			local transparency = 0.55
			if pressed then
				background = danger and self.Theme.Danger or self.Theme.SurfaceHover
				foreground = danger and self.Theme.DangerText or self.Theme.Text
				transparency = 0
			elseif hovered then
				background = danger and self.Theme.Danger or self.Theme.SurfaceHover
				foreground = danger and self.Theme.Danger or self.Theme.Text
				transparency = danger and 0.82 or 0
			end
			self:_tween(button, duration, {
				BackgroundColor3 = background,
				BackgroundTransparency = transparency,
				TextColor3 = foreground,
			})
		end
		window._maid:Give(button.MouseEnter:Connect(function()
			hovered = true
			renderState(0.12)
		end))
		window._maid:Give(button.MouseLeave:Connect(function()
			hovered = false
			pressed = false
			renderState(0.12)
		end))
		window._maid:Give(button.MouseButton1Down:Connect(function()
			pressed = true
			renderState(0.08)
		end))
		window._maid:Give(button.MouseButton1Up:Connect(function()
			pressed = false
			renderState(0.1)
		end))
		window._maid:Give(self.ThemeChanged:Connect(function()
			renderState(0.18)
		end))
		return button
	end

	local closeButton = makeTopButton("Close", "×", 1, true)
	local minimizeButton = makeTopButton("Minimize", "−", 2, false)
	local searchButton
	if options.Search then
		searchButton = makeTopButton("Search", "?", 3, false)
		searchButton.TextSize = 20
		window._maid:Give(searchButton.Activated:Connect(function()
			self:OpenCommandPalette()
		end))
	end

	local sidebar = create("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(0, 220, 1, -58),
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = panel,
	})
	self:_bindTheme(sidebar, { BackgroundColor3 = "Surface" })
	window.Sidebar = sidebar

	local sideBorder = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = self.Theme.Border,
		BorderSizePixel = 0,
		Parent = sidebar,
	})
	self:_bindTheme(sideBorder, { BackgroundColor3 = "Border" })

	local tabsLabel = create("TextLabel", {
		Name = "TabsLabel",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = "NAVIGATION",
		TextSize = 10,
		TextColor3 = self.Theme.Muted,
		TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = sidebar,
	})
	self:_bindTheme(tabsLabel, { TextColor3 = "Muted" })
	window.TabsLabel = tabsLabel

	local tabsList = create("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(10, 40),
		Size = UDim2.new(1, -20, 1, options.ShowUser and -122 or -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	})
	local tabsLayout = create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabsList,
	})
	window._maid:Give(tabsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabsList.CanvasSize = UDim2.fromOffset(0, tabsLayout.AbsoluteContentSize.Y + 4)
	end))
	window.TabsList = tabsList

	local userCard
	if options.ShowUser then
		local player = Players.LocalPlayer
		userCard = create("Frame", {
			Name = "UserCard",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -12),
			Size = UDim2.new(1, -20, 0, 58),
			BackgroundColor3 = self.Theme.SurfaceAlt,
			BorderSizePixel = 0,
			Parent = sidebar,
		})
		addCorner(userCard, 10)
		local userStroke = addStroke(userCard, self.Theme.Border, 0.25, 1)
		self:_bindTheme(userCard, { BackgroundColor3 = "SurfaceAlt" })
		self:_bindTheme(userStroke, { Color = "Border" })
		local avatar = create("ImageLabel", {
			BackgroundColor3 = self.Theme.Accent,
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(40, 40),
			Image = player and ("rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=100&h=100") or "",
			BorderSizePixel = 0,
			Parent = userCard,
		})
		addCorner(avatar, 20)
		self:_bindTheme(avatar, { BackgroundColor3 = "Accent" })
		local displayName = create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(58, 8),
			Size = UDim2.new(1, -66, 0, 22),
			Font = Enum.Font.GothamMedium,
			Text = player and player.DisplayName or "Player",
			TextSize = 12,
			TextColor3 = self.Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = userCard,
		})
		local username = create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(58, 29),
			Size = UDim2.new(1, -66, 0, 18),
			Font = Enum.Font.Gotham,
			Text = player and ("@" .. player.Name) or "Ready",
			TextSize = 10,
			TextColor3 = self.Theme.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = userCard,
		})
		self:_bindTheme(displayName, { TextColor3 = "Text" })
		self:_bindTheme(username, { TextColor3 = "Muted" })
	end
	window.UserCard = userCard

	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(220, 58),
		Size = UDim2.new(1, -220, 1, -58),
		BackgroundColor3 = self.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = panel,
	})
	self:_bindTheme(content, { BackgroundColor3 = "Background" })
	window.Content = content

	local emptyState = create("Frame", {
		Name = "EmptyState",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(280, 100),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local emptyTitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Font = Enum.Font.GothamBold,
		Text = "Ready when you are",
		TextSize = 17,
		TextColor3 = self.Theme.Text,
		Parent = emptyState,
	})
	local emptyText = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 44),
		Font = Enum.Font.Gotham,
		Text = "Add a tab and some controls to begin.",
		TextSize = 12,
		TextColor3 = self.Theme.Muted,
		TextWrapped = true,
		Parent = emptyState,
	})
	self:_bindTheme(emptyTitle, { TextColor3 = "Text" })
	self:_bindTheme(emptyText, { TextColor3 = "Muted" })
	window.EmptyState = emptyState

	local resizeGrip = create("TextButton", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "+",
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = self.Theme.Muted,
		ZIndex = 20,
		Visible = options.Resizable,
		Parent = panel,
	})
	self:_bindTheme(resizeGrip, { TextColor3 = "Muted" })
	window.ResizeGrip = resizeGrip

	window._maid:Give(closeButton.Activated:Connect(function()
		window:Close()
	end))
	window._maid:Give(minimizeButton.Activated:Connect(function()
		if window._minimized then
			window:Restore()
		else
			window:Minimize()
		end
	end))

	local dragging = false
	local dragInput
	local dragStart
	local startCenter
	local moved = false
	window._maid:Give(topbar.InputBegan:Connect(function(input)
		if dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local rightEdge = topbar.AbsolutePosition.X + topbar.AbsoluteSize.X - 132
		if input.Position.X >= rightEdge then
			return
		end
		dragging = true
		dragInput = input
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		startCenter = root.AbsolutePosition - self.WindowLayer.AbsolutePosition + root.AbsoluteSize / 2
		moved = false
	end))
	window._maid:Give(UserInputService.InputChanged:Connect(function(input)
		local mouseMovement = dragInput
			and dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if not dragging or (input ~= dragInput and not mouseMovement) then
			return
		end
		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - dragStart
		if delta.Magnitude > 6 then
			moved = true
		end
		if moved then
			local center = startCenter + delta
			root.Position = UDim2.fromOffset(center.X, center.Y)
		end
	end))
	local function finishWindowDragging(savePosition)
		local shouldSave = dragging and moved and savePosition
		dragging = false
		dragInput = nil
		if shouldSave then
			self:_autoSaveIfEnabled("ui")
		end
	end
	window._maid:Give(UserInputService.InputEnded:Connect(function(input)
		if not dragging or not dragInput then
			return
		end
		local mouseDragEnded = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if input == dragInput or mouseDragEnded then
			finishWindowDragging(true)
		end
	end))
	window._maid:Give(UserInputService.WindowFocusReleased:Connect(function()
		finishWindowDragging(true)
	end))

	local resizing = false
	local resizeInput
	local resizeStart
	local initialSize
	window._maid:Give(resizeGrip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeInput = input
			resizeStart = Vector2.new(input.Position.X, input.Position.Y)
			initialSize = root.AbsoluteSize
		end
	end))
	window._maid:Give(UserInputService.InputChanged:Connect(function(input)
		if not resizing or (input ~= resizeInput and input.UserInputType ~= Enum.UserInputType.MouseMovement) then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - resizeStart
		local viewport = self.WindowLayer.AbsoluteSize
		local maximum = Vector2.new(
			math.min(options.MaxSize.X, viewport.X - 20),
			math.min(options.MaxSize.Y, viewport.Y - 20)
		)
		local nextSize = Vector2.new(
			math.clamp(initialSize.X + delta.X, math.min(options.MinSize.X, maximum.X), maximum.X),
			math.clamp(initialSize.Y + delta.Y, math.min(options.MinSize.Y, maximum.Y), maximum.Y)
		)
		root.Size = UDim2.fromOffset(nextSize.X, nextSize.Y)
		window._requestedSize = nextSize
	end))
	window._maid:Give(UserInputService.InputEnded:Connect(function(input)
		if input == resizeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			local shouldSave = resizing
			resizing = false
			resizeInput = nil
			if shouldSave then
				self:_autoSaveIfEnabled("ui")
			end
		end
	end))

	local function updateResponsive()
		if window._destroyed then
			return
		end
		local viewport = self.WindowLayer.AbsoluteSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local mobile = self.Options.Mobile and (viewport.X < 720 or viewport.Y < 420)
		window._mobile = mobile
		local sidebarWidth = mobile and 70 or 220
		brand.Size = UDim2.fromOffset(sidebarWidth - 16, 42)
		brandTitle.Visible = not mobile
		brandSubtitle.Visible = not mobile
		divider.Position = UDim2.fromOffset(sidebarWidth - 1, 12)
		pageTitle.Position = UDim2.fromOffset(sidebarWidth + 18, 0)
		pageTitle.Size = UDim2.new(1, -(sidebarWidth + 170), 1, 0)
		sidebar.Size = UDim2.new(0, sidebarWidth, 1, -58)
		content.Position = UDim2.fromOffset(sidebarWidth, 58)
		content.Size = UDim2.new(1, -sidebarWidth, 1, -58)
		tabsLabel.Visible = not mobile
		tabsList.Position = UDim2.fromOffset(8, mobile and 12 or 40)
		tabsList.Size = UDim2.new(1, -16, 1, mobile and -24 or (options.ShowUser and -122 or -52))
		if userCard then
			userCard.Visible = not mobile
		end
		resizeGrip.Visible = options.Resizable and not mobile and not window._minimized
		for _, tab in ipairs(window._tabs) do
			tab:_setMobile(mobile)
		end
		if not window._minimized then
			local targetSize
			if mobile then
				targetSize = Vector2.new(math.max(1, viewport.X - 12), math.max(1, viewport.Y - 20))
			else
				targetSize = Vector2.new(
					math.clamp(window._requestedSize.X, math.min(options.MinSize.X, viewport.X - 20), math.min(options.MaxSize.X, viewport.X - 20)),
					math.clamp(window._requestedSize.Y, math.min(options.MinSize.Y, viewport.Y - 20), math.min(options.MaxSize.Y, viewport.Y - 20))
				)
			end
			root.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
		end
	end
	window._updateResponsive = updateResponsive
	local cameraConnection
	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
		end
	end
	window._maid:Give(function()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
	end)
	window._maid:Give(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		updateResponsive()
	end))
	window._maid:Give(self.WindowLayer:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateResponsive))
	window._maid:Give(self.WindowLayer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsive))
	bindCamera()
	task.defer(updateResponsive)

	table.insert(self._windows, window)
	if self.OpenButton then
		local openButtonOptions = providedOptions.OpenButton
		if not self.OpenButton.Target or openButtonOptions ~= nil then
			self.OpenButton.Target = window
		end
		if openButtonOptions == false then
			self.OpenButton:Edit({ Enabled = false })
		elseif type(openButtonOptions) == "table" then
			self.OpenButton:Edit(openButtonOptions)
		elseif openButtonOptions == true then
			self.OpenButton:Edit({ Enabled = true })
		else
			self.OpenButton:_render()
		end
	end
	self:_updateRestoreButton()
	return window
end

Velora.Create = Velora.CreateWindow

function Window:SetTitle(title, subtitle)
	self.Options.Title = tostring(title or "")
	self.BrandTitle.Text = self.Options.Title
	if subtitle ~= nil then
		self.Options.Subtitle = tostring(subtitle)
		self.BrandSubtitle.Text = self.Options.Subtitle
	end
	if self._ui.OpenButton and self._ui.OpenButton.Target == self then
		self._ui.OpenButton:_render()
	end
	return self
end

function Window:SetVisible(visible)
	visible = visible == true
	if not visible then
		self._ui:_cancelKeybindCapture()
	end
	if visible and self._minimized then
		self:Restore()
	elseif self.Root then
		self.Root.Visible = visible
	end
	self._ui:_updateRestoreButton()
	return self
end

function Window:IsVisible()
	return self.Root and self.Root.Visible and self._ui:IsVisible() or false
end

function Window:Toggle()
	if self:IsVisible() then
		self._ui:SetVisible(false)
	else
		self:SetVisible(true)
		self._ui:SetVisible(true)
	end
	return self
end

Window.Open = function(self)
	self:SetVisible(true)
	self._ui:SetVisible(true)
	return self
end

Window.SetVisibility = Window.SetVisible

function Window:Close()
	if self._destroyed or self._ui._destroyed then
		return self
	end
	local shouldDestroy = string.lower(tostring(self.Options.CloseBehavior or "Destroy")) == "destroy"
	local function closeWindow()
		if self._destroyed or self._ui._destroyed then
			return
		end
		if shouldDestroy then
			self:Destroy()
		else
			self._ui:SetVisible(false)
		end
	end
	if self.Options.ConfirmOnClose then
		if self._closeDialog and not self._closeDialog._closed then
			return self
		end
		local content = self.Options.CloseConfirmContent
		if content == nil then
			content = shouldDestroy
				and "关闭后将销毁当前窗口，且不会显示顶部恢复悬浮窗。"
				or "关闭后可使用快捷键重新打开窗口。"
		end
		local dialog = self._ui:Dialog({
			Title = tostring(self.Options.CloseConfirmTitle or "是否关闭窗口"),
			Content = tostring(content),
			Dismissible = self.Options.CloseConfirmDismissible ~= false,
			Buttons = {
				{ Title = tostring(self.Options.CloseConfirmCancel or "否"), Variant = "Secondary" },
				{
					Title = tostring(self.Options.CloseConfirmConfirm or "是"),
					Variant = "Danger",
					Callback = closeWindow,
				},
			},
		})
		self._closeDialog = dialog
		if dialog then
			dialog.Closed:Once(function()
				if self._closeDialog == dialog then
					self._closeDialog = nil
				end
			end)
		end
	else
		closeWindow()
	end
	return self
end

function Window:Minimize()
	if self._minimized or not self.Root then
		return self
	end
	local openButton = self._ui.OpenButton
	local useOpenButton = self.Options.MinimizeToOpenButton ~= false
		and openButton
		and openButton:_isAlive()
		and openButton.Options.Enabled ~= false
		and openButton._visibilityOverride ~= false
	self._minimized = true
	self._lastExpandedSize = self.Root.Size
	self._ui:_cancelKeybindCapture()
	self._ui:_closePopup()
	self._ui:CloseCommandPalette()
	if useOpenButton then
		for _, window in ipairs(shallowCopy(self._ui._windows)) do
			if window ~= self and not window._destroyed and window._minimizedToOpenButton then
				window:Restore()
			end
		end
		self._minimizedToOpenButton = true
		openButton.Target = self
		self.Root.Visible = false
		openButton:_render()
	else
		self._minimizedToOpenButton = false
		self.Sidebar.Visible = false
		self.Content.Visible = false
		self.TopDivider.Visible = false
		self.PageTitle.Visible = false
		self.ResizeGrip.Visible = false
		self._ui:_tween(self.Root, 0.2, { Size = UDim2.fromOffset(330, 58) })
	end
	self._ui:_updateRestoreButton()
	return self
end

function Window:Restore()
	if not self._minimized or not self.Root then
		return self
	end
	local minimizedToOpenButton = self._minimizedToOpenButton
	local expandedSize = self._lastExpandedSize or self.Options.Size
	self._minimized = false
	self._minimizedToOpenButton = false
	self.Root.Visible = true
	self.Sidebar.Visible = true
	self.Content.Visible = true
	self.TopDivider.Visible = true
	self.PageTitle.Visible = true
	self.ResizeGrip.Visible = self.Options.Resizable and not self._mobile
	if minimizedToOpenButton then
		self.Root.Size = expandedSize
	else
		self._ui:_tween(self.Root, 0.2, { Size = expandedSize })
	end
	if self._updateResponsive then
		task.defer(self._updateResponsive)
	end
	self._ui:_updateRestoreButton()
	return self
end

function Window:SetSize(size, setOptions)
	if typeof(size) == "Vector2" then
		size = UDim2.fromOffset(size.X, size.Y)
	end
	if typeof(size) ~= "UDim2" then
		return false
	end
	self._requestedSize = Vector2.new(size.X.Offset, size.Y.Offset)
	self.Root.Size = size
	if self._updateResponsive then
		self._updateResponsive()
	end
	self._ui:_autoSaveIfEnabled(setOptions and setOptions.Source, setOptions and setOptions.Silent)
	return true
end

function Window:SetToCenter(setOptions)
	if self.Root then
		self.Root.Position = UDim2.fromScale(0.5, 0.5)
		self._ui:_autoSaveIfEnabled(setOptions and setOptions.Source, setOptions and setOptions.Silent)
	end
	return self
end

function Window:SetToggleKey(key)
	if key == nil then
		self._ui.Options.ToggleKey = nil
		self._ui:_updateRestoreButton()
		return true
	end
	if type(key) == "string" then
		local ok, enumKey = pcall(function()
			return Enum.KeyCode[key]
		end)
		key = ok and enumKey or nil
	end
	if typeof(key) ~= "EnumItem" or key.EnumType ~= Enum.KeyCode then
		return false
	end
	self._ui.Options.ToggleKey = key
	self._ui:_updateRestoreButton()
	return true
end

function Window:EditOpenButton(options)
	local handle = self._ui.OpenButton
	if not handle then
		return nil
	end
	handle.Target = self
	return handle:Edit(options)
end

function Window:GetOpenButton()
	local handle = self._ui:GetOpenButton()
	if handle and not self._destroyed then
		handle.Target = self
		handle:_render()
	end
	return handle
end

function Window:LockAll(reason)
	for _, tab in ipairs(self._tabs) do
		tab:LockAll(reason)
	end
	return self
end

function Window:UnlockAll()
	for _, tab in ipairs(self._tabs) do
		tab:UnlockAll()
	end
	return self
end

function Window:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	local closeDialog = self._closeDialog
	self._closeDialog = nil
	if closeDialog and not closeDialog._closed then
		closeDialog:Close(nil)
	end
	for _, tab in ipairs(shallowCopy(self._tabs)) do
		tab:Destroy()
	end
	self.TabChanged:Destroy()
	self._maid:Clean()
	local index = table.find(self._ui._windows, self)
	if index then
		table.remove(self._ui._windows, index)
	end
	table.clear(self._tabs)
	self.Root = nil
	if self._ui.OpenButton and self._ui.OpenButton.Target == self then
		local fallback
		for _, window in ipairs(self._ui._windows) do
			if not window._destroyed and window.Root and window._minimizedToOpenButton then
				fallback = window
				break
			end
		end
		self._ui.OpenButton.Target = fallback or self._ui._windows[1]
		self._ui.OpenButton:_render()
	end
	self._ui:_updateRestoreButton()
end

function Window:AddTab(options, icon)
	if type(options) == "string" then
		options = {
			Title = options,
			Icon = icon,
		}
	else
		options = shallowCopy(options)
	end
	options.Title = options.Title or options.Name or "Tab"
	options.Icon = options.Icon or string.sub(options.Title, 1, 1)
	options.Description = options.Description or options.Desc or ""

	local tab = setmetatable({}, Tab)
	tab._window = self
	tab._ui = self._ui
	tab.Options = options
	tab.Title = tostring(options.Title)
	tab.Icon = options.Icon
	tab._maid = Maid.new()
	tab._sections = {}
	tab._destroyed = false
	tab._mobile = self._mobile
	tab._id = self._ui:_nextId()
	tab.Selected = Signal.new()

	local button = create("TextButton", {
		Name = "Tab_" .. tostring(tab._id),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = self._ui.Theme.SurfaceAlt,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = #self._tabs + 1,
		Parent = self.TabsList,
	})
	addCorner(button, 9)
	self._ui:_bindTheme(button, { BackgroundColor3 = "SurfaceAlt" })
	tab.Button = button

	local indicator = create("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		BackgroundColor3 = self._ui.Theme.Accent,
		BorderSizePixel = 0,
		Parent = button,
	})
	addCorner(indicator, 3)
	self._ui:_bindTheme(indicator, { BackgroundColor3 = "Accent" })
	tab.Indicator = indicator

	local iconHolder = create("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(27, 27),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	})
	addCorner(iconHolder, 7)
	self._ui:_bindTheme(iconHolder, { BackgroundColor3 = "SurfaceHover" })
	local iconLabel = makeIconLabel(iconHolder, options.Icon, 27, 1)
	iconLabel.Size = UDim2.fromScale(1, 1)
	if iconLabel:IsA("TextLabel") then
		iconLabel.TextSize = 13
	end
	bindIconTheme(self._ui, iconLabel, "Muted")
	tab.IconLabel = iconLabel
	tab.IconHolder = iconHolder

	local titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(45, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Font = Enum.Font.GothamMedium,
		Text = tab.Title,
		TextSize = 12,
		TextColor3 = self._ui.Theme.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})
	self._ui:_bindTheme(titleLabel, { TextColor3 = "Muted" })
	tab.TitleLabel = titleLabel

	local page = create("ScrollingFrame", {
		Name = "Page_" .. tostring(tab._id),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = self._ui.Theme.Border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = self.Content,
	})
	self._ui:_bindTheme(page, { ScrollBarImageColor3 = "Border" })
	tab.Page = page

	local columnHost = create("Frame", {
		Name = "Columns",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 0),
		BackgroundTransparency = 1,
		Parent = page,
	})
	tab.ColumnHost = columnHost

	local leftColumn = create("Frame", {
		Name = "Left",
		Size = UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = columnHost,
	})
	local rightColumn = create("Frame", {
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = columnHost,
	})
	local leftLayout = create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = leftColumn,
	})
	local rightLayout = create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rightColumn,
	})
	tab.LeftColumn = leftColumn
	tab.RightColumn = rightColumn
	tab.LeftLayout = leftLayout
	tab.RightLayout = rightLayout

	local function updateCanvas()
		if tab._destroyed then
			return
		end
		local height
		if tab._mobile then
			height = leftLayout.AbsoluteContentSize.Y
		else
			height = math.max(leftLayout.AbsoluteContentSize.Y, rightLayout.AbsoluteContentSize.Y)
		end
		columnHost.Size = UDim2.new(1, -32, 0, height)
		page.CanvasSize = UDim2.fromOffset(0, height + 32)
	end
	tab._updateCanvas = updateCanvas
	tab._maid:Give(leftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))
	tab._maid:Give(rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas))

	function tab:_refreshVisual(selected)
		self._ui:_tween(button, 0.14, { BackgroundTransparency = selected and 0 or 1 })
		self._ui:_tween(indicator, 0.16, { Size = UDim2.fromOffset(3, selected and 20 or 0) })
		local color = selected and self._ui.Theme.Text or self._ui.Theme.Muted
		local iconColorProperty = iconLabel:IsA("ImageLabel") and "ImageColor3" or "TextColor3"
		self._ui:_bindTheme(titleLabel, { TextColor3 = selected and "Text" or "Muted" })
		self._ui:_bindTheme(iconLabel, { [iconColorProperty] = selected and "Accent" or "Muted" })
		self._ui:_tween(titleLabel, 0.14, { TextColor3 = color })
		self._ui:_tween(iconLabel, 0.14, { [iconColorProperty] = selected and self._ui.Theme.Accent or self._ui.Theme.Muted })
		self._ui:_tween(iconHolder, 0.14, { BackgroundTransparency = selected and 0 or 1 })
	end

	tab._maid:Give(button.MouseEnter:Connect(function()
		if self._selectedTab ~= tab then
			self._ui:_tween(button, 0.12, { BackgroundTransparency = 0.5 })
		end
	end))
	tab._maid:Give(button.MouseLeave:Connect(function()
		if self._selectedTab ~= tab then
			self._ui:_tween(button, 0.12, { BackgroundTransparency = 1 })
		end
	end))
	tab._maid:Give(button.Activated:Connect(function()
		self:SelectTab(tab)
	end))

	table.insert(self._tabs, tab)
	self.EmptyState.Visible = false
	tab._searchEntry = self._ui:_registerSearchItem({
		Title = tab.Title,
		Description = options.Description,
		Keywords = options.Keywords,
		Kind = "Tab",
		Target = tab,
		Action = function()
			self:SelectTab(tab)
		end,
	})
	if not self._selectedTab then
		self:SelectTab(tab)
	else
		tab:_refreshVisual(false)
	end
	tab:_setMobile(self._mobile)
	return tab
end

Window.CreateTab = Window.AddTab
Window.Tab = Window.AddTab

function Window:SelectTab(tabOrName, selectOptions)
	local target = tabOrName
	if type(tabOrName) == "string" then
		for _, tab in ipairs(self._tabs) do
			if tab.Title == tabOrName then
				target = tab
				break
			end
		end
	end
	if type(target) ~= "table" or target._window ~= self or target._destroyed then
		return false
	end
	if self._selectedTab == target then
		return true
	end
	for _, tab in ipairs(self._tabs) do
		local selected = tab == target
		tab.Page.Visible = selected
		tab:_refreshVisual(selected)
	end
	self._selectedTab = target
	self.PageTitle.Text = target.Title
	target.Selected:Fire()
	self.TabChanged:Fire(target)
	self._ui:_autoSaveIfEnabled(selectOptions and selectOptions.Source, selectOptions and selectOptions.Silent)
	return true
end

function Window:GetSelectedTab()
	return self._selectedTab
end

function Window:Notify(options)
	return self._ui:Notify(options)
end

function Window:Dialog(options)
	return self._ui:Dialog(options)
end

function Tab:_setMobile(mobile)
	self._mobile = mobile == true
	self.TitleLabel.Visible = not self._mobile
	self.IconHolder.Position = self._mobile and UDim2.new(0.5, -13, 0.5, 0) or UDim2.new(0, 9, 0.5, 0)
	self.LeftColumn.Size = self._mobile and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -6, 0, 0)
	self.RightColumn.Visible = not self._mobile
	for index, section in ipairs(self._sections) do
		if self._mobile then
			section.Root.Parent = self.LeftColumn
		else
			local side = section._side
			if side == "Right" then
				section.Root.Parent = self.RightColumn
			else
				section.Root.Parent = self.LeftColumn
			end
		end
		section.Root.LayoutOrder = index
		for _, control in ipairs(section._controls) do
			if type(control._setMobile) == "function" then
				control:_setMobile(self._mobile)
			end
		end
	end
	task.defer(self._updateCanvas)
end

function Tab:SetTitle(title)
	self.Title = tostring(title or "")
	self.TitleLabel.Text = self.Title
	if self._searchEntry then
		self._ui:_refreshSearchItem(self._searchEntry, self.Title, self.Options.Description)
	end
	if self._window._selectedTab == self then
		self._window.PageTitle.Text = self.Title
	end
	return self
end

function Tab:Select()
	return self._window:SelectTab(self)
end

function Tab:LockAll(reason)
	for _, section in ipairs(self._sections) do
		for _, control in ipairs(section._controls) do
			if type(control.SetDisabled) == "function" then
				control:SetDisabled(true, reason)
			end
		end
	end
	return self
end

function Tab:UnlockAll()
	for _, section in ipairs(self._sections) do
		for _, control in ipairs(section._controls) do
			if type(control.SetDisabled) == "function" then
				control:SetDisabled(false)
			end
		end
	end
	return self
end

function Tab:ScrollTo(control)
	if not control or not control.Root or control._section._tab ~= self then
		return false
	end
	self:Select()
	local relativeY = control.Root.AbsolutePosition.Y - self.Page.AbsolutePosition.Y + self.Page.CanvasPosition.Y
	self.Page.CanvasPosition = Vector2.new(0, math.max(0, relativeY - 70))
	control:Highlight()
	return true
end

function Tab:AddSection(options, side)
	if type(options) == "string" then
		options = {
			Title = options,
			Side = side,
		}
	else
		options = shallowCopy(options)
	end
	options.Title = options.Title or options.Name or "Section"
	options.Description = options.Description or options.Desc or ""
	if options.Collapsible == nil then
		options.Collapsible = true
	end

	local section = setmetatable({}, Section)
	section._tab = self
	section._window = self._window
	section._ui = self._ui
	section.Options = options
	section.Title = tostring(options.Title)
	section.Description = tostring(options.Description)
	section._maid = Maid.new()
	section._controls = {}
	section._destroyed = false
	section._collapsed = false
	section._id = self._ui:_nextId()
	local requestedSide = options.Side
	if requestedSide ~= "Left" and requestedSide ~= "Right" then
		requestedSide = (#self._sections % 2 == 0) and "Left" or "Right"
	end
	section._side = requestedSide

	local parent = (requestedSide == "Right" and not self._mobile) and self.RightColumn or self.LeftColumn
	local card = create("Frame", {
		Name = "Section_" .. tostring(section._id),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = self._ui.Theme.Surface,
		BorderSizePixel = 0,
		LayoutOrder = #self._sections + 1,
		Parent = parent,
	})
	addCorner(card, 11)
	local cardStroke = addStroke(card, self._ui.Theme.Border, 0.2, 1)
	self._ui:_bindTheme(card, { BackgroundColor3 = "Surface" })
	self._ui:_bindTheme(cardStroke, { Color = "Border" })
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})
	section.Root = card
	section._maid:Give(card)

	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, section.Description ~= "" and 62 or 52),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(15, section.Description ~= "" and 11 or 0),
		Size = UDim2.new(1, -50, 0, section.Description ~= "" and 20 or 52),
		Font = Enum.Font.GothamMedium,
		Text = section.Title,
		TextSize = 13,
		TextColor3 = self._ui.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	self._ui:_bindTheme(title, { TextColor3 = "Text" })
	section.TitleLabel = title
	local description
	if section.Description ~= "" then
		description = create("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(15, 32),
			Size = UDim2.new(1, -50, 0, 18),
			Font = Enum.Font.Gotham,
			Text = section.Description,
			TextSize = 10,
			TextColor3 = self._ui.Theme.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		})
		self._ui:_bindTheme(description, { TextColor3 = "Muted" })
	end
	section.DescriptionLabel = description

	local collapseIcon = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -15, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = options.Collapsible and "^" or "",
		TextSize = 14,
		TextColor3 = self._ui.Theme.Muted,
		Parent = header,
	})
	self._ui:_bindTheme(collapseIcon, { TextColor3 = "Muted" })
	section.CollapseIcon = collapseIcon
	local headerButton = create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Visible = options.Collapsible,
		Parent = header,
	})

	local divider = create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -30, 0, 1),
		Position = UDim2.new(0, 15, 1, -1),
		BackgroundColor3 = self._ui.Theme.Border,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = header,
	})
	self._ui:_bindTheme(divider, { BackgroundColor3 = "Border" })

	local holder = create("Frame", {
		Name = "Controls",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = card,
	})
	addPadding(holder, 10, 10, 12, 10)
	local holderLayout = create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	section.Holder = holder
	section.Layout = holderLayout
	section._maid:Give(holderLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(self._updateCanvas)
	end))
	section._maid:Give(headerButton.Activated:Connect(function()
		section:SetCollapsed(not section._collapsed)
	end))

	table.insert(self._sections, section)
	task.defer(self._updateCanvas)
	return section
end

Tab.CreateSection = Tab.AddSection
Tab.Section = Tab.AddSection

function Tab:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, section in ipairs(shallowCopy(self._sections)) do
		section:Destroy()
	end
	self.Selected:Destroy()
	self._maid:Clean()
	if self.Page then
		self.Page:Destroy()
	end
	if self.Button then
		self.Button:Destroy()
	end
	local index = table.find(self._window._tabs, self)
	if index then
		table.remove(self._window._tabs, index)
	end
	if self._window._selectedTab == self then
		self._window._selectedTab = nil
		if self._window._tabs[1] then
			self._window:SelectTab(self._window._tabs[1])
		else
			self._window.EmptyState.Visible = true
		end
	end
	self._ui:_removeSearchItem(self._searchEntry)
	self._searchEntry = nil
	table.clear(self._sections)
end

function Section:SetCollapsed(collapsed)
	if not self.Options.Collapsible then
		return self
	end
	self._collapsed = collapsed == true
	self.Holder.Visible = not self._collapsed
	self.CollapseIcon.Text = self._collapsed and "v" or "^"
	task.defer(self._tab._updateCanvas)
	return self
end

function Section:SetTitle(title, description)
	self.Title = tostring(title or "")
	self.TitleLabel.Text = self.Title
	if description ~= nil and self.DescriptionLabel then
		self.Description = tostring(description)
		self.DescriptionLabel.Text = self.Description
	end
	return self
end

function Section:SetVisible(visible)
	self.Root.Visible = visible == true
	task.defer(self._tab._updateCanvas)
	return self
end

function Section:LockAll(reason)
	for _, control in ipairs(self._controls) do
		if type(control.SetDisabled) == "function" then
			control:SetDisabled(true, reason)
		end
	end
	return self
end

function Section:UnlockAll()
	for _, control in ipairs(self._controls) do
		if type(control.SetDisabled) == "function" then
			control:SetDisabled(false)
		end
	end
	return self
end

function Section:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, control in ipairs(shallowCopy(self._controls)) do
		control:Destroy()
	end
	self._maid:Clean()
	local index = table.find(self._tab._sections, self)
	if index then
		table.remove(self._tab._sections, index)
	end
	table.clear(self._controls)
	task.defer(self._tab._updateCanvas)
end

function Velora:_registerSearchItem(item)
	item.Id = self:_nextId()
	item.Title = tostring(item.Title or "Untitled")
	item.Description = tostring(item.Description or "")
	if type(item.Keywords) == "table" then
		item.Keywords = table.concat(item.Keywords, " ")
	else
		item.Keywords = tostring(item.Keywords or "")
	end
	item.SearchText = string.lower(item.Title .. " " .. item.Description .. " " .. item.Keywords .. " " .. tostring(item.Kind or ""))
	table.insert(self._searchItems, item)
	return item
end

function Velora:_refreshSearchItem(item, title, description)
	if not item or item.Removed then
		return
	end
	item.Title = tostring(title or item.Title or "Untitled")
	item.Description = tostring(description or "")
	item.SearchText = string.lower(item.Title .. " " .. item.Description .. " " .. item.Keywords .. " " .. tostring(item.Kind or ""))
end

function Velora:_removeSearchItem(item)
	if not item then
		return
	end
	item.Removed = true
	local index = table.find(self._searchItems, item)
	if index then
		table.remove(self._searchItems, index)
	end
end

local function attachHover(ui, maid, object, restingTransparency, hoverTransparency)
	restingTransparency = restingTransparency or 0
	hoverTransparency = hoverTransparency or 0
	maid:Give(object.MouseEnter:Connect(function()
		ui:_tween(object, 0.12, { BackgroundTransparency = hoverTransparency })
	end))
	maid:Give(object.MouseLeave:Connect(function()
		ui:_tween(object, 0.12, { BackgroundTransparency = restingTransparency })
	end))
end

local function applyStackedControlLayout(control, mobile, target, desktopWidth, desktopHeight)
	mobile = mobile == true
	desktopHeight = desktopHeight or 32
	control._mobile = mobile
	local hasDescription = control.Description ~= ""
	if mobile then
		local targetY = hasDescription and 53 or 36
		control.Root.Size = UDim2.new(1, 0, 0, targetY + 44)
		control.TitleLabel.Position = UDim2.fromOffset(12, 6)
		control.TitleLabel.Size = UDim2.new(1, -24, 0, 22)
		if control.DescriptionLabel then
			control.DescriptionLabel.Position = UDim2.fromOffset(12, 28)
			control.DescriptionLabel.Size = UDim2.new(1, -24, 0, 18)
		end
		target.AnchorPoint = Vector2.new(0, 0)
		target.Position = UDim2.fromOffset(12, targetY)
		target.Size = UDim2.new(1, -24, 0, 32)
	else
		local titleY = hasDescription and 10 or 0
		local titleHeight = hasDescription and 21 or control._desktopHeight
		local reservedWidth = desktopWidth + 36
		control.Root.Size = UDim2.new(1, 0, 0, control._desktopHeight)
		control.TitleLabel.Position = UDim2.fromOffset(12, titleY)
		control.TitleLabel.Size = UDim2.new(1, -reservedWidth, 0, titleHeight)
		if control.DescriptionLabel then
			control.DescriptionLabel.Position = UDim2.fromOffset(12, 31)
			control.DescriptionLabel.Size = UDim2.new(1, -reservedWidth, 0, 20)
		end
		target.AnchorPoint = Vector2.new(1, 0.5)
		target.Position = UDim2.new(1, -12, 0.5, 0)
		target.Size = UDim2.fromOffset(desktopWidth, desktopHeight)
	end
	task.defer(control._section._tab._updateCanvas)
end

function Section:_makeControl(kind, options, defaultValue, sanitize, height)
	options = shallowCopy(options)
	options.Title = options.Title or options.Name or kind
	options.Description = options.Description or options.Desc or ""
	local control = setmetatable({}, Control)
	control._ui = self._ui
	control._section = self
	control._maid = Maid.new()
	control._destroyed = false
	control.Type = kind
	control.Title = tostring(options.Title)
	control.Description = tostring(options.Description)
	control.Callback = options.Callback
	control.Default = deepCopy(defaultValue)
	control.NoSave = options.NoSave == true or options.Save == false
	control.Disabled = options.Disabled == true
	control._sanitize = sanitize
	control.Changed = Signal.new()
	control.Flag = options.Flag
	if control.Flag == nil then
		control.Flag = normalizeFlag(self.Title .. "." .. control.Title)
	elseif control.Flag == false then
		control.Flag = nil
	else
		control.Flag = tostring(control.Flag)
	end

	local rowHeight = height or (control.Description ~= "" and 64 or 52)
	control._desktopHeight = rowHeight
	local root = create("Frame", {
		Name = kind .. "_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = self._ui.Theme.SurfaceAlt,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Active = true,
		Selectable = true,
		LayoutOrder = #self._controls + 1,
		Parent = self.Holder,
	})
	addCorner(root, 9)
	local stroke = addStroke(root, self._ui.Theme.Border, 0.55, 1)
	self._ui:_bindTheme(root, { BackgroundColor3 = "SurfaceAlt" })
	self._ui:_bindTheme(stroke, { Color = "Border" })
	control.Root = root
	control.Stroke = stroke

	local titleY = control.Description ~= "" and 10 or 0
	local titleHeight = control.Description ~= "" and 21 or rowHeight
	local titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, titleY),
		Size = UDim2.new(1, -128, 0, titleHeight),
		Font = Enum.Font.GothamMedium,
		Text = control.Title,
		TextSize = 12,
		TextColor3 = self._ui.Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 2,
		Parent = root,
	})
	self._ui:_bindTheme(titleLabel, { TextColor3 = "Text" })
	control.TitleLabel = titleLabel
	local descriptionLabel = create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 31),
		Size = UDim2.new(1, -128, 0, 20),
		Font = Enum.Font.Gotham,
		Text = control.Description,
		TextSize = 10,
		TextColor3 = self._ui.Theme.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = control.Description ~= "",
		ZIndex = 2,
		Parent = root,
	})
	self._ui:_bindTheme(descriptionLabel, { TextColor3 = "Muted" })
	control.DescriptionLabel = descriptionLabel

	local disabledOverlay = create("TextButton", {
		Name = "Disabled",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self._ui.Theme.Surface,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = options.DisabledReason or "Locked",
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = self._ui.Theme.Muted,
		Visible = control.Disabled,
		ZIndex = 50,
		Parent = root,
	})
	addCorner(disabledOverlay, 9)
	self._ui:_bindTheme(disabledOverlay, {
		BackgroundColor3 = "Surface",
		TextColor3 = "Muted",
	})
	control.DisabledOverlay = disabledOverlay
	control.DisabledReason = options.DisabledReason

	local registeredValue = self._ui.State:Register(control.Flag, control, defaultValue)
	local ok, sanitizedValue = pcall(function()
		return sanitize and sanitize(registeredValue, control) or registeredValue
	end)
	control._value = deepCopy(ok and sanitizedValue or defaultValue)
	if control.Flag then
		self._ui.State._values[control.Flag] = deepCopy(control._value)
	end
	table.insert(self._controls, control)
	control._searchEntry = self._ui:_registerSearchItem({
		Title = control.Title,
		Description = control.Description,
		Keywords = options.Keywords,
		Kind = kind,
		Target = control,
		Action = function()
			if control._destroyed then
				return
			end
			self._window:SelectTab(self._tab)
			control.Root.Visible = true
			local relativeY = control.Root.AbsolutePosition.Y - self._tab.Page.AbsolutePosition.Y + self._tab.Page.CanvasPosition.Y
			self._tab.Page.CanvasPosition = Vector2.new(0, math.max(0, relativeY - 80))
			local original = control.Stroke.Transparency
			control.Stroke.Transparency = 0
			control.Stroke.Thickness = 2
			self._ui:_bindTheme(control.Stroke, { Color = "Accent" })
			task.delay(0.9, function()
				if control.Root and control.Root.Parent then
					control.Stroke.Transparency = original
					control.Stroke.Thickness = 1
					self._ui:_bindTheme(control.Stroke, { Color = "Border" })
				end
			end)
		end,
	})
	attachHover(self._ui, control._maid, root, 0.12, 0)
	return control
end

function Section:_finishControl(control, fireOnInit)
	if type(control._setMobile) == "function" then
		control:_setMobile(self._tab._mobile)
	end
	if control._render then
		control:_render(control._value, nil, { Source = "init", Instant = true, Silent = true })
	end
	if fireOnInit then
		safeCall(control.Callback, control:Get(), nil, "init")
	end
	return control
end

function Section:AddButton(first, second)
	local options
	if type(first) == "string" and type(second) == "function" then
		options = { Title = first, Callback = second }
	else
		options = normalizeOptions(first, second)
	end
	options.Title = options.Title or options.Name or "Button"
	options.Description = options.Description or options.Desc or ""
	local control = self:_makeControl("Button", options, false, function(value)
		return value == true
	end)
	local registeredFlag = control.Flag
	control.Flag = nil
	if registeredFlag then
		self._ui.State:Unregister(registeredFlag, control)
		self._ui.State._values[registeredFlag] = nil
	end
	local actionText = tostring(options.ActionText or options.ButtonText or "Run")
	local actionWidth = math.clamp(textWidth(actionText, 11, Enum.Font.GothamMedium) + 25, 62, 120)
	local actionVariant = options.Variant or (options.Danger and "Danger" or "Secondary")
	local actionBackground = actionVariant == "Primary" and "Accent" or (actionVariant == "Danger" and "Danger" or "SurfaceHover")
	local actionForeground = actionVariant == "Secondary" and "Text" or (actionVariant == "Danger" and "DangerText" or "AccentText")
	local action = create("TextLabel", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(actionWidth, 30),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = actionText .. " >",
		TextSize = 11,
		TextColor3 = self._ui.Theme.Text,
		ZIndex = 4,
		Parent = control.Root,
	})
	function control:_setMobile(mobile)
		applyStackedControlLayout(self, mobile, action, actionWidth, 30)
	end
	addCorner(action, 7)
	self._ui:_bindTheme(action, {
		BackgroundColor3 = actionBackground,
		TextColor3 = actionForeground,
	})
	local hitbox = create("TextButton", {
		Name = "Hitbox",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 10,
		Parent = control.Root,
	})
	function control:Press()
		if self.Disabled then
			return false
		end
		local function execute()
			safeCall(options.Callback)
			self.Changed:Fire("press", nil, "user")
		end
		if options.Confirm then
			self._ui:Dialog({
				Title = options.ConfirmTitle or control.Title,
				Content = type(options.Confirm) == "string" and options.Confirm or "Are you sure?",
				Buttons = {
					{ Title = "Cancel", Variant = "Secondary" },
					{ Title = options.ConfirmText or "Confirm", Variant = options.Danger and "Danger" or "Primary", Callback = execute },
				},
			})
		else
			execute()
		end
		return true
	end
	control.Fire = control.Press
	control._maid:Give(hitbox.Activated:Connect(function()
		control:Press()
	end))
	control._maid:Give(hitbox.MouseButton1Down:Connect(function()
		if control._mobile then
			self._ui:_tween(action, 0.08, { BackgroundTransparency = 0.14 })
		else
			self._ui:_tween(action, 0.08, { Size = UDim2.fromOffset(math.max(58, action.AbsoluteSize.X - 3), 27) })
		end
	end))
	control._maid:Give(hitbox.MouseButton1Up:Connect(function()
		if control._mobile then
			self._ui:_tween(action, 0.1, { BackgroundTransparency = 0 })
		else
			self._ui:_tween(action, 0.1, { Size = UDim2.fromOffset(actionWidth, 30) })
		end
	end))
	return self:_finishControl(control, false)
end

Section.CreateButton = Section.AddButton
Section.Button = Section.AddButton

function Section:AddToggle(first, second)
	local options = normalizeOptions(first, second)
	local defaultValue = options.Default
	if defaultValue == nil then
		defaultValue = options.Value
	end
	if defaultValue == nil then
		defaultValue = options.CurrentValue
	end
	defaultValue = defaultValue == true
	local control = self:_makeControl("Toggle", options, defaultValue, function(value)
		return value == true
	end)
	local switch = create("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = control.Root,
	})
	addCorner(switch, 12)
	local switchStroke = addStroke(switch, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(switchStroke, { Color = "Border" })
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = self._ui.Theme.Muted,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = switch,
	})
	addCorner(knob, 9)
	local hitbox = create("TextButton", {
		Name = "Hitbox",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 10,
		Parent = control.Root,
	})
	function control:_render(value, _, renderOptions)
		local duration = renderOptions and renderOptions.Instant and 0 or 0.16
		self._ui:_tween(switch, duration, { BackgroundColor3 = value and self._ui.Theme.Accent or self._ui.Theme.SurfaceHover })
		self._ui:_tween(switchStroke, duration, {
			Color = value and self._ui.Theme.Accent or self._ui.Theme.Border,
			Transparency = value and 0.1 or 0.35,
		})
		self._ui:_tween(knob, duration, {
			Position = value and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = value and self._ui.Theme.AccentText or self._ui.Theme.Muted,
		})
	end
	control._maid:Give(self._ui.ThemeChanged:Connect(function()
		if not control._destroyed then
			control:_render(control._value, nil, { Source = "theme" })
		end
	end))
	control._maid:Give(hitbox.Activated:Connect(function()
		if not control.Disabled then
			control:Set(not control._value, { Source = "user" })
		end
	end))
	control._maid:Give(control.Root.InputBegan:Connect(function(input)
		if not control.Disabled and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			control:Set(not control._value, { Source = "keyboard" })
		end
	end))
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateToggle = Section.AddToggle
Section.Toggle = Section.AddToggle
Section.AddCheckbox = Section.AddToggle
Section.CreateCheckbox = Section.AddToggle
Section.Checkbox = Section.AddToggle

function Section:AddSlider(first, second)
	local options = normalizeOptions(first, second)
	local valueOptions = type(options.Value) == "table" and options.Value or nil
	if type(options.Range) == "table" then
		options.Min = options.Min or options.Range[1]
		options.Max = options.Max or options.Range[2]
	end
	if valueOptions then
		options.Min = options.Min or valueOptions.Min
		options.Max = options.Max or valueOptions.Max
	end
	options.Min = tonumber(options.Min) or 0
	options.Max = tonumber(options.Max) or 100
	if options.Min > options.Max then
		options.Min, options.Max = options.Max, options.Min
	end
	options.Step = math.abs(tonumber(options.Step or options.Increment) or 1)
	local defaultValue = options.Default
	if defaultValue == nil then
		if valueOptions then
			defaultValue = valueOptions.Default
		else
			defaultValue = options.Value
		end
	end
	defaultValue = tonumber(defaultValue or options.CurrentValue) or options.Min
	local function sanitize(value)
		value = tonumber(value)
		if not value then
			error("Slider value must be a number")
		end
		if value <= options.Min then
			return options.Min
		elseif value >= options.Max then
			return options.Max
		end
		return math.clamp(roundToStep(value, options.Step, options.Min), options.Min, options.Max)
	end
	local control = self:_makeControl("Slider", options, sanitize(defaultValue), sanitize, options.Description and 82 or 72)
	control.Min = options.Min
	control.Max = options.Max
	control.Step = options.Step

	local valueLabel = create("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(96, 23),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextSize = 11,
		TextColor3 = self._ui.Theme.Text,
		ZIndex = 4,
		Parent = control.Root,
	})
	addCorner(valueLabel, 6)
	self._ui:_bindTheme(valueLabel, {
		BackgroundColor3 = "SurfaceHover",
		TextColor3 = "Text",
	})
	control.ValueLabel = valueLabel

	local track = create("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 8),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = control.Root,
	})
	addCorner(track, 4)
	self._ui:_bindTheme(track, { BackgroundColor3 = "SurfaceHover" })
	local trackStroke = addStroke(track, self._ui.Theme.Border, 0.4, 1)
	self._ui:_bindTheme(trackStroke, { Color = "Border" })
	local sliderHitbox = create("TextButton", {
		Name = "Hitbox",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -2),
		Size = UDim2.new(1, -12, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 9,
		Parent = control.Root,
	})
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = self._ui.Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = track,
	})
	addCorner(fill, 4)
	self._ui:_bindTheme(fill, { BackgroundColor3 = "Accent" })
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(15, 15),
		BackgroundColor3 = self._ui.Theme.AccentText,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = track,
	})
	addCorner(knob, 8)
	local knobStroke = addStroke(knob, self._ui.Theme.Accent, 0, 2)
	self._ui:_bindTheme(knob, { BackgroundColor3 = "AccentText" })
	self._ui:_bindTheme(knobStroke, { Color = "Accent" })
	local dragging = false

	local function formatValue(value)
		if type(options.Format) == "function" then
			local ok, formatted = pcall(options.Format, value)
			if ok then
				return tostring(formatted)
			end
		end
		local prefix = tostring(options.Prefix or "")
		local suffix = tostring(options.Suffix or "")
		return prefix .. tostring(value) .. suffix
	end

	function control:_render(value, _, renderOptions)
		local range = math.max(0.000001, self.Max - self.Min)
		local ratio = math.clamp((value - self.Min) / range, 0, 1)
		valueLabel.Text = formatValue(value)
		if dragging then
			return
		end
		local duration = renderOptions and renderOptions.Instant and 0 or 0.08
		self._ui:_tween(fill, duration, { Size = UDim2.fromScale(ratio, 1) })
		self._ui:_tween(knob, duration, { Position = UDim2.fromScale(ratio, 0.5) })
	end

	local dragInput
	local page = self._tab.Page
	local pageScrollingEnabled
	local pageScrollLocked = false
	local function lockPageScrolling()
		if pageScrollLocked or not page then
			return
		end
		pageScrollingEnabled = page.ScrollingEnabled
		page.ScrollingEnabled = false
		pageScrollLocked = true
	end
	local function finishDragging(instant)
		dragging = false
		dragInput = nil
		if pageScrollLocked then
			pageScrollLocked = false
			if page and page.Parent then
				page.ScrollingEnabled = pageScrollingEnabled
			end
			pageScrollingEnabled = nil
		end
		if knob and knob.Parent then
			local range = math.max(0.000001, control.Max - control.Min)
			local ratio = math.clamp((control._value - control.Min) / range, 0, 1)
			local duration = instant and 0 or 0.12
			self._ui:_tween(fill, duration, { Size = UDim2.fromScale(ratio, 1) })
			self._ui:_tween(knob, duration, {
				Position = UDim2.fromScale(ratio, 0.5),
				Size = UDim2.fromOffset(15, 15),
			})
		end
	end
	local function updateFromPosition(position)
		if control.Disabled or track.AbsoluteSize.X <= 0 then
			return
		end
		local ratio = math.clamp((position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local value = control.Min + ((control.Max - control.Min) * ratio)
		control:Set(value, { Source = "user" })
		self._ui:_tween(fill, 0, { Size = UDim2.fromScale(ratio, 1) })
		self._ui:_tween(knob, 0, {
			Position = UDim2.fromScale(ratio, 0.5),
			Size = UDim2.fromOffset(19, 19),
		})
	end
	control._maid:Give(sliderHitbox.InputBegan:Connect(function(input)
		if not control.Disabled and not dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = true
			dragInput = input
			lockPageScrolling()
			updateFromPosition(input.Position)
		end
	end))
	control._maid:Give(UserInputService.InputChanged:Connect(function(input)
		local mouseMovement = dragInput
			and dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if dragging and (input == dragInput or mouseMovement) then
			updateFromPosition(input.Position)
		end
	end))
	control._maid:Give(UserInputService.InputEnded:Connect(function(input)
		local mouseDragEnded = dragInput
			and dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if dragging and (input == dragInput or mouseDragEnded) then
			finishDragging(false)
		end
	end))
	control._maid:Give(function()
		finishDragging(true)
	end)
	control._maid:Give(control.Root.InputBegan:Connect(function(input)
		if control.Disabled then
			return
		end
		local keyboardStep = control.Step > 0 and control.Step or math.max((control.Max - control.Min) / 100, 0.000001)
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Down then
			local target = control._value - keyboardStep
			if control.Step > 0 and control._value >= control.Max then
				local lastFullStep = control.Min + math.floor((control.Max - control.Min) / control.Step) * control.Step
				if lastFullStep < control.Max then
					target = lastFullStep
				end
			end
			control:Set(target, { Source = "keyboard" })
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Up then
			control:Set(control._value + keyboardStep, { Source = "keyboard" })
		end
	end))

	function control:SetRange(minimum, maximum)
		minimum = tonumber(minimum)
		maximum = tonumber(maximum)
		if not minimum or not maximum then
			return false
		end
		if minimum > maximum then
			minimum, maximum = maximum, minimum
		end
		self.Min = minimum
		self.Max = maximum
		options.Min = minimum
		options.Max = maximum
		self:Set(self._value, { Force = true, Source = "range" })
		return true
	end

	function control:SetMin(minimum)
		return self:SetRange(minimum, self.Max)
	end

	function control:SetMax(maximum)
		return self:SetRange(self.Min, maximum)
	end

	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateSlider = Section.AddSlider
Section.Slider = Section.AddSlider

function Section:AddInput(first, second)
	local options = normalizeOptions(first, second)
	local defaultValue = options.Default
	if defaultValue == nil then
		defaultValue = options.Value
	end
	if defaultValue == nil then
		defaultValue = options.CurrentValue
	end
	if defaultValue == nil then
		defaultValue = ""
	end
	local function sanitize(value)
		local text = tostring(value == nil and "" or value)
		if options.MaxLength then
			text = truncateUtf8(text, options.MaxLength)
		end
		if options.Numeric then
			local number = tonumber(text)
			if not number then
				error("Input must contain a number")
			end
			if options.Min then
				number = math.max(number, options.Min)
			end
			if options.Max then
				number = math.min(number, options.Max)
			end
			return number
		end
		return text
	end
	local height = options.Multiline and 112 or (options.Description and 66 or 58)
	local control = self:_makeControl("Input", options, sanitize(defaultValue), sanitize, height)
	local textBox
	if options.Multiline then
		control.TitleLabel.Position = UDim2.fromOffset(12, options.Description and 7 or 6)
		control.TitleLabel.Size = UDim2.new(1, -24, 0, options.Description and 22 or 25)
		if control.DescriptionLabel then
			control.DescriptionLabel.Position = UDim2.fromOffset(12, 31)
			control.DescriptionLabel.Size = UDim2.new(1, -24, 0, 20)
		end
		textBox = create("TextBox", {
			Name = "TextBox",
			Position = UDim2.fromOffset(12, options.Description and 52 or 38),
			Size = UDim2.new(1, -24, 0, 50),
			BackgroundColor3 = self._ui.Theme.Surface,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			MultiLine = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = Enum.Font.Gotham,
			Text = "",
			PlaceholderText = tostring(options.Placeholder or options.PlaceholderText or "Type here..."),
			PlaceholderColor3 = self._ui.Theme.Muted,
			TextColor3 = self._ui.Theme.Text,
			TextSize = 11,
			ZIndex = 4,
			Parent = control.Root,
		})
		addPadding(textBox, 8, 9, 8, 9)
	else
		textBox = create("TextBox", {
			Name = "TextBox",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(options.Width or 150, 32),
			BackgroundColor3 = self._ui.Theme.Surface,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			Text = "",
			PlaceholderText = tostring(options.Placeholder or options.PlaceholderText or "Type here..."),
			PlaceholderColor3 = self._ui.Theme.Muted,
			TextColor3 = self._ui.Theme.Text,
			TextSize = 11,
			ZIndex = 4,
			Parent = control.Root,
		})
		addPadding(textBox, 0, 9, 0, 9)
	end
	addCorner(textBox, 7)
	local boxStroke = addStroke(textBox, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(textBox, {
		BackgroundColor3 = "Surface",
		TextColor3 = "Text",
		PlaceholderColor3 = "Muted",
	})
	self._ui:_bindTheme(boxStroke, { Color = "Border" })
	control.TextBox = textBox
	if options.Multiline then
		function control:_setMobile(mobile)
			self._mobile = mobile == true
			local hasDescription = self.Description ~= ""
			self.Root.Size = UDim2.new(1, 0, 0, self._desktopHeight)
			self.TitleLabel.Position = UDim2.fromOffset(12, hasDescription and 7 or 6)
			self.TitleLabel.Size = UDim2.new(1, -24, 0, hasDescription and 22 or 25)
			self.DescriptionLabel.Position = UDim2.fromOffset(12, 31)
			self.DescriptionLabel.Size = UDim2.new(1, -24, 0, 20)
			textBox.Position = UDim2.fromOffset(12, hasDescription and 52 or 38)
			task.defer(self._section._tab._updateCanvas)
		end
	else
		local inputWidth = options.Width or 150
		function control:_setMobile(mobile)
			applyStackedControlLayout(self, mobile, textBox, inputWidth)
		end
	end

	function control:_render(value)
		if not textBox:IsFocused() then
			textBox.Text = tostring(value)
		end
	end

	function control:Focus()
		if not self.Disabled then
			textBox:CaptureFocus()
		end
	end

	local liveGuard = false
	if options.Live then
		control._maid:Give(textBox:GetPropertyChangedSignal("Text"):Connect(function()
			if liveGuard or not textBox:IsFocused() then
				return
			end
			local text = textBox.Text
			local truncatedLength
			if options.MaxLength then
				local truncated
				truncated, truncatedLength = truncateUtf8(text, options.MaxLength)
				if truncated ~= text then
					liveGuard = true
					text = truncated
					textBox.Text = text
					textBox.CursorPosition = truncatedLength + 1
					liveGuard = false
				end
			end
			if not options.Numeric or tonumber(text) then
				control:Set(text, { Source = "user" })
			end
		end))
	end
	control._maid:Give(textBox.Focused:Connect(function()
		self._ui:_tween(boxStroke, 0.12, { Color = self._ui.Theme.Accent, Transparency = 0 })
	end))
	control._maid:Give(textBox.FocusLost:Connect(function(enterPressed)
		self._ui:_tween(boxStroke, 0.12, { Color = self._ui.Theme.Border, Transparency = 0.35 })
		local changed = control:Set(textBox.Text, { Source = "user" })
		if not changed then
			textBox.Text = tostring(control._value)
		end
		if options.ClearOnFocusLost or options.RemoveTextAfterFocusLost then
			textBox.Text = ""
		end
		if enterPressed then
			safeCall(options.OnEnter, control:Get())
		end
	end))
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateInput = Section.AddInput
Section.Input = Section.AddInput
Section.AddTextbox = Section.AddInput
Section.CreateTextbox = Section.AddInput
Section.Textbox = Section.AddInput

local function normalizeChoices(values)
	local choices = {}
	for index, item in ipairs(values or {}) do
		local choice
		if type(item) == "table" and (item.Value ~= nil or item.Title or item.Name or item.Label) then
			choice = shallowCopy(item)
			if choice.Value == nil then
				choice.Value = choice.Title or choice.Name or choice.Label
			end
			choice.Title = tostring(choice.Title or choice.Name or choice.Label or choice.Value)
			choice.Description = tostring(choice.Description or choice.Desc or "")
		else
			choice = {
				Title = tostring(item),
				Description = "",
				Value = item,
			}
		end
		choice.Index = index
		table.insert(choices, choice)
	end
	return choices
end

local function findChoice(choices, value)
	for _, choice in ipairs(choices) do
		if valuesEqual(choice.Value, value) then
			return choice
		end
	end
	return nil
end

function Section:AddDropdown(first, second)
	local options = normalizeOptions(first, second)
	local choices = normalizeChoices(options.Values or options.Options or {})
	local multi = options.Multi == true or options.Multiple == true or options.MultipleOptions == true
	local allowNone = options.AllowNone ~= false
	local defaultValue = options.Default
	if defaultValue == nil then
		defaultValue = options.Value
	end
	if defaultValue == nil then
		defaultValue = options.CurrentOption
	end
	if multi then
		if type(defaultValue) ~= "table" then
			defaultValue = defaultValue ~= nil and { defaultValue } or {}
		end
	else
		if type(defaultValue) == "table" and defaultValue[1] ~= nil then
			defaultValue = defaultValue[1]
		end
		if defaultValue == nil and not allowNone and choices[1] then
			defaultValue = choices[1].Value
		end
	end

	local function sanitize(value)
		if multi then
			local result = {}
			if type(value) ~= "table" then
				value = value == nil and {} or { value }
			end
			for _, selected in ipairs(value) do
				local choice = findChoice(choices, selected)
				if choice and not table.find(result, choice.Value) then
					table.insert(result, choice.Value)
				end
			end
			return result
		end
		if value == nil and allowNone then
			return nil
		end
		local choice = findChoice(choices, value)
		if not choice then
			error("Dropdown value is not in Values")
		end
		return choice.Value
	end

	local control = self:_makeControl("Dropdown", options, sanitize(defaultValue), sanitize, options.Description and 66 or 58)
	control.Values = choices
	control.Multi = multi
	local selector = create("TextButton", {
		Name = "Selector",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(options.Width or 168, 32),
		BackgroundColor3 = self._ui.Theme.Surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = control.Root,
	})
	addCorner(selector, 7)
	local selectorStroke = addStroke(selector, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(selector, { BackgroundColor3 = "Surface" })
	self._ui:_bindTheme(selectorStroke, { Color = "Border" })
	local selectedText = create("TextLabel", {
		Name = "Selected",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -34, 1, 0),
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 10,
		TextColor3 = self._ui.Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = selector,
	})
	local arrow = create("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "v",
		TextSize = 10,
		TextColor3 = self._ui.Theme.Muted,
		ZIndex = 6,
		Parent = selector,
	})
	self._ui:_bindTheme(selectedText, { TextColor3 = "Text" })
	self._ui:_bindTheme(arrow, { TextColor3 = "Muted" })
	control.Selector = selector
	local selectorWidth = options.Width or 168
	function control:_setMobile(mobile)
		applyStackedControlLayout(self, mobile, selector, selectorWidth)
	end

	local function displayValue(value)
		if multi then
			local labels = {}
			for _, selected in ipairs(value or {}) do
				local choice = findChoice(choices, selected)
				if choice then
					table.insert(labels, choice.Title)
				end
			end
			if #labels == 0 then
				return tostring(options.Placeholder or "Select...")
			elseif #labels > 2 then
				return labels[1] .. ", " .. labels[2] .. " +" .. tostring(#labels - 2)
			end
			return table.concat(labels, ", ")
		end
		local choice = findChoice(choices, value)
		return choice and choice.Title or tostring(options.Placeholder or "Select...")
	end

	function control:_render(value)
		selectedText.Text = displayValue(value)
		local hasSelection = (multi and #value > 0) or (not multi and value ~= nil)
		selectedText.TextColor3 = hasSelection and self._ui.Theme.Text or self._ui.Theme.Muted
	end

	function control:Close()
		if self._ui._popupOwner == self then
			self._ui:_closePopup()
			self._ui._popupOwner = nil
		end
		arrow.Text = "v"
	end

	function control:Open()
		if self.Disabled then
			return false
		end
		self._ui._popupOwner = self
		arrow.Text = "^"
		local searchable = options.Searchable ~= false and (#choices > 7 or options.Searchable == true)
		local visibleRows = math.min(#choices, options.MaxVisible or 7)
		local popupHeight = (searchable and 48 or 12) + math.max(40, visibleRows * 42) + 12
		local popup, popupMaid = self._ui:_openPopup(selector, {
			Name = "Dropdown",
			Width = math.max(options.PopupWidth or 280, selector.AbsoluteSize.X),
			Height = math.min(options.MaxHeight or 330, popupHeight),
		})
		local searchBox
		local listTop = 8
		if searchable then
			searchBox = create("TextBox", {
				Name = "Search",
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(1, -16, 0, 34),
				BackgroundColor3 = self._ui.Theme.SurfaceAlt,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Enum.Font.Gotham,
				Text = "",
				PlaceholderText = "Search options...",
				PlaceholderColor3 = self._ui.Theme.Muted,
				TextColor3 = self._ui.Theme.Text,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 505,
				Parent = popup,
			})
			addCorner(searchBox, 7)
			addPadding(searchBox, 0, 10, 0, 10)
			self._ui:_bindTheme(searchBox, {
				BackgroundColor3 = "SurfaceAlt",
				TextColor3 = "Text",
				PlaceholderColor3 = "Muted",
			})
			listTop = 48
		end
		local list = create("ScrollingFrame", {
			Name = "Options",
			Position = UDim2.fromOffset(8, listTop),
			Size = UDim2.new(1, -16, 1, -(listTop + 8)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = self._ui.Theme.Border,
			ZIndex = 504,
			Parent = popup,
		})
		local layout = create("UIListLayout", {
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		self._ui:_bindTheme(list, { ScrollBarImageColor3 = "Border" })
		popupMaid:Give(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
		end))

		local optionButtons = {}
		local function isSelected(value)
			if multi then
				for _, selected in ipairs(control._value) do
					if valuesEqual(selected, value) then
						return true
					end
				end
				return false
			end
			return valuesEqual(control._value, value)
		end
		local function refreshVisuals()
			for choice, buttonData in pairs(optionButtons) do
				local selected = isSelected(choice.Value)
				self._ui:_tween(buttonData.Button, 0.12, {
					BackgroundTransparency = selected and 0 or 0.55,
					BackgroundColor3 = selected and self._ui.Theme.Accent or self._ui.Theme.SurfaceAlt,
				})
				buttonData.Mark.Text = selected and "+" or ""
				buttonData.Title.TextColor3 = selected and self._ui.Theme.AccentText or self._ui.Theme.Text
			end
		end
		local function build(filter)
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("GuiButton") then
					child:Destroy()
				end
			end
			table.clear(optionButtons)
			filter = string.lower(filter or "")
			local rendered = 0
			for _, choice in ipairs(choices) do
				local searchableText = string.lower(choice.Title .. " " .. choice.Description)
				if filter == "" or string.find(searchableText, filter, 1, true) then
					rendered = rendered + 1
					if rendered > (options.RenderLimit or 100) then
						break
					end
					local rowHeight = choice.Description ~= "" and 46 or 38
					local optionButton = create("TextButton", {
						Name = "Option_" .. tostring(choice.Index),
						Size = UDim2.new(1, -2, 0, rowHeight),
						BackgroundColor3 = self._ui.Theme.SurfaceAlt,
						BackgroundTransparency = 0.55,
						BorderSizePixel = 0,
						AutoButtonColor = false,
						Text = "",
						Active = not (choice.Disabled or choice.Locked),
						ZIndex = 506,
						Parent = list,
					})
					addCorner(optionButton, 7)
					local optionTitle = create("TextLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(10, choice.Description ~= "" and 5 or 0),
						Size = UDim2.new(1, -48, 0, choice.Description ~= "" and 19 or rowHeight),
						Font = Enum.Font.GothamMedium,
						Text = choice.Title,
						TextSize = 11,
						TextColor3 = self._ui.Theme.Text,
						TextTransparency = (choice.Disabled or choice.Locked) and 0.55 or 0,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 507,
						Parent = optionButton,
					})
					if choice.Description ~= "" then
						local optionDescription = create("TextLabel", {
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(10, 24),
							Size = UDim2.new(1, -48, 0, 16),
							Font = Enum.Font.Gotham,
							Text = choice.Description,
							TextSize = 9,
							TextColor3 = self._ui.Theme.Muted,
							TextTruncate = Enum.TextTruncate.AtEnd,
							TextXAlignment = Enum.TextXAlignment.Left,
							ZIndex = 507,
							Parent = optionButton,
						})
						self._ui:_bindTheme(optionDescription, { TextColor3 = "Muted" })
					end
					local mark = create("TextLabel", {
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.fromOffset(22, 22),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Text = "",
						TextSize = 13,
						TextColor3 = self._ui.Theme.AccentText,
						ZIndex = 507,
						Parent = optionButton,
					})
					optionButtons[choice] = {
						Button = optionButton,
						Title = optionTitle,
						Mark = mark,
					}
					popupMaid:Give(optionButton.Activated:Connect(function()
						if choice.Disabled or choice.Locked then
							return
						end
						if multi then
							local nextValue = deepCopy(control._value)
							local foundIndex
							for index, selected in ipairs(nextValue) do
								if valuesEqual(selected, choice.Value) then
									foundIndex = index
									break
								end
							end
							if foundIndex then
								table.remove(nextValue, foundIndex)
							else
								table.insert(nextValue, choice.Value)
							end
							control:Set(nextValue, { Source = "user" })
							refreshVisuals()
						else
							control:Set(choice.Value, { Source = "user" })
							safeCall(choice.Callback, choice.Value)
							control:Close()
						end
					end))
				end
			end
			refreshVisuals()
		end
		build("")
		if searchBox then
			local revision = 0
			popupMaid:Give(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
				revision = revision + 1
				local currentRevision = revision
				task.delay(0.08, function()
					if currentRevision == revision and searchBox.Parent then
						build(searchBox.Text)
					end
				end)
			end))
			task.defer(function()
				if searchBox.Parent then
					searchBox:CaptureFocus()
				end
			end)
		end
		popupMaid:Give(function()
			arrow.Text = "v"
			if self._ui._popupOwner == control then
				self._ui._popupOwner = nil
			end
		end)
		return true
	end

	function control:SetValues(values, preserveSelection)
		choices = normalizeChoices(values)
		self.Values = choices
		if preserveSelection then
			self:Set(self._value, { Force = true, Source = "values" })
		elseif multi then
			self:Set({}, { Source = "values" })
		else
			self:Set((not allowNone and choices[1]) and choices[1].Value or nil, { Source = "values" })
		end
		return self
	end

	control.Refresh = control.SetValues
	control.Select = control.Set
	control._maid:Give(selector.Activated:Connect(function()
		if self._ui._popupOwner == control then
			control:Close()
		else
			control:Open()
		end
	end))
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateDropdown = Section.AddDropdown
Section.Dropdown = Section.AddDropdown

function Section:AddMultiDropdown(first, second)
	local options = normalizeOptions(first, second)
	options.Multi = true
	return self:AddDropdown(options)
end

Section.CreateMultiDropdown = Section.AddMultiDropdown
Section.MultiDropdown = Section.AddMultiDropdown

local function normalizeBinding(value)
	if value == nil or value == "None" then
		return nil
	end
	if typeof(value) == "EnumItem" then
		return value
	end
	if type(value) == "string" then
		local keyOk, key = pcall(function()
			return Enum.KeyCode[value]
		end)
		if keyOk and key then
			return key
		end
		local inputOk, inputType = pcall(function()
			return Enum.UserInputType[value]
		end)
		if inputOk and inputType then
			return inputType
		end
	end
	error("Keybind must be an EnumItem, key name, or nil")
end

local function inputMatchesBinding(input, binding)
	if not binding then
		return false
	end
	if binding.EnumType == Enum.KeyCode then
		return input.KeyCode == binding
	end
	if binding.EnumType == Enum.UserInputType then
		return input.UserInputType == binding
	end
	return false
end

local function bindingName(binding)
	if not binding then
		return "None"
	end
	local names = {
		LeftControl = "L-Ctrl",
		RightControl = "R-Ctrl",
		LeftShift = "L-Shift",
		RightShift = "R-Shift",
		LeftAlt = "L-Alt",
		RightAlt = "R-Alt",
		MouseButton1 = "Mouse 1",
		MouseButton2 = "Mouse 2",
		MouseButton3 = "Mouse 3",
	}
	return names[binding.Name] or binding.Name
end

function Section:AddKeybind(first, second)
	local options = normalizeOptions(first, second)
	local defaultValue = options.Default
	if defaultValue == nil then
		defaultValue = options.Value or options.CurrentKeybind
	end
	defaultValue = normalizeBinding(defaultValue)
	local control = self:_makeControl("Keybind", options, defaultValue, normalizeBinding, options.Description and 66 or 58)
	control.Mode = options.Mode or (options.HoldToInteract and "Hold" or "Press")
	control.Active = false
	control.Capturing = false
	control.Triggered = Signal.new()
	control._maid:Give(control.Triggered)
	local activationCallback = options.OnActivated or options.Activated
	if options.CallOnChange == true then
		control.Callback = options.OnChanged or options.Callback
	else
		activationCallback = activationCallback or options.Callback
		control.Callback = options.OnChanged
	end

	local selector = create("TextButton", {
		Name = "Selector",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(options.Width or 100, 32),
		BackgroundColor3 = self._ui.Theme.Surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = "None",
		TextSize = 10,
		TextColor3 = self._ui.Theme.Text,
		ZIndex = 5,
		Parent = control.Root,
	})
	addCorner(selector, 7)
	local selectorStroke = addStroke(selector, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(selector, {
		BackgroundColor3 = "Surface",
		TextColor3 = "Text",
	})
	self._ui:_bindTheme(selectorStroke, { Color = "Border" })
	control.Selector = selector
	local selectorWidth = options.Width or 100
	function control:_setMobile(mobile)
		applyStackedControlLayout(self, mobile, selector, selectorWidth)
	end

	function control:_render(value)
		if not self.Capturing then
			selector.Text = bindingName(value)
		end
	end

	function control:SetKey(value, setOptions)
		return self:Set(value, setOptions)
	end

	function control:SetMode(mode)
		if mode ~= "Press" and mode ~= "Toggle" and mode ~= "Hold" then
			return false
		end
		self.Mode = mode
		return true
	end

	function control:IsActive()
		return self.Active
	end

	local function setCapturing(capturing)
		if capturing then
			local previous = self._ui._capturingKeybind
			if previous and previous ~= control and not previous._destroyed and previous._cancelCapture then
				previous:_cancelCapture()
			end
			control.Capturing = true
			self._ui._capturingKeybind = control
			selector.Text = "Press a key..."
			self._ui:_tween(selectorStroke, 0.12, { Color = self._ui.Theme.Accent, Transparency = 0 })
		else
			control.Capturing = false
			if self._ui._capturingKeybind == control then
				self._ui._capturingKeybind = nil
			end
			control:_render(control._value)
			self._ui:_tween(selectorStroke, 0.12, { Color = self._ui.Theme.Border, Transparency = 0.35 })
		end
	end

	function control:_cancelCapture()
		setCapturing(false)
	end

	local function trigger(active, source)
		control.Active = active == true
		control.Triggered:Fire(control.Active, source)
		safeCall(activationCallback, control.Active, control:Get(), source)
	end

	control._maid:Give(selector.Activated:Connect(function()
		if control.Disabled or options.CanChange == false then
			return
		end
		setCapturing(true)
	end))
	control._maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if control.Capturing then
			if input.KeyCode == Enum.KeyCode.Escape then
				setCapturing(false)
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				setCapturing(false)
				control:Set(nil, { Source = "user" })
			else
				local candidate = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
				local blocked = false
				for _, binding in ipairs(options.BlackList or options.Blacklist or {}) do
					if normalizeBinding(binding) == candidate then
						blocked = true
						break
					end
				end
				if not blocked and candidate ~= Enum.UserInputType.Keyboard then
					setCapturing(false)
					control:Set(candidate, { Source = "user" })
				end
			end
			return
		end
		if processed or control.Disabled or UserInputService:GetFocusedTextBox() or not inputMatchesBinding(input, control._value) then
			return
		end
		if control.Mode == "Toggle" then
			trigger(not control.Active, "input")
		else
			trigger(true, "input")
			if control.Mode == "Press" then
				task.defer(function()
					if not control._destroyed then
						control.Active = false
					end
				end)
			end
		end
	end))
	control._maid:Give(UserInputService.InputEnded:Connect(function(input)
		if control.Mode == "Hold" and control.Active and inputMatchesBinding(input, control._value) then
			trigger(false, "input")
		end
	end))
	control._maid:Give(function()
		if self._ui._capturingKeybind == control then
			self._ui._capturingKeybind = nil
		end
	end)
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateKeybind = Section.AddKeybind
Section.Keybind = Section.AddKeybind

function Section:AddColorPicker(first, second)
	local options = normalizeOptions(first, second)
	local defaultColor = options.Default or options.Value or options.Color or Color3.fromRGB(124, 99, 255)
	local function sanitize(value)
		if typeof(value) == "Color3" then
			return value
		end
		if type(value) == "string" then
			local color = hexToColor(value)
			if color then
				return color
			end
		end
		error("ColorPicker value must be a Color3 or hex string")
	end
	defaultColor = sanitize(defaultColor)
	local control = self:_makeControl("ColorPicker", options, defaultColor, sanitize, options.Description and 66 or 58)
	local defaultTransparency = math.clamp(tonumber(options.Transparency) or 0, 0, 1)
	control.Transparency = defaultTransparency
	control.DefaultTransparency = defaultTransparency
	local pendingTransparency = control.Flag and self._ui._pendingTransparency[control.Flag] or nil
	control.AllowTransparency = options.AllowTransparency == true or options.Transparency ~= nil or pendingTransparency ~= nil
	if pendingTransparency ~= nil then
		control.Transparency = math.clamp(tonumber(pendingTransparency) or defaultTransparency, 0, 1)
		self._ui._pendingTransparency[control.Flag] = nil
	end
	control.TransparencyChanged = Signal.new()
	control._maid:Give(control.TransparencyChanged)

	local selector = create("TextButton", {
		Name = "Selector",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(options.Width or 118, 32),
		BackgroundColor3 = self._ui.Theme.Surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Parent = control.Root,
	})
	addCorner(selector, 7)
	local selectorStroke = addStroke(selector, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(selector, { BackgroundColor3 = "Surface" })
	self._ui:_bindTheme(selectorStroke, { Color = "Border" })
	local swatch = create("Frame", {
		Name = "Swatch",
		Position = UDim2.fromOffset(5, 5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = defaultColor,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = selector,
	})
	addCorner(swatch, 6)
	addStroke(swatch, Color3.new(1, 1, 1), 0.72, 1)
	local hexLabel = create("TextLabel", {
		Name = "Hex",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -42, 1, 0),
		Font = Enum.Font.Code,
		Text = colorToHex(defaultColor),
		TextSize = 10,
		TextColor3 = self._ui.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = selector,
	})
	self._ui:_bindTheme(hexLabel, { TextColor3 = "Text" })
	control.Selector = selector
	control.Swatch = swatch
	local selectorWidth = options.Width or 118
	function control:_setMobile(mobile)
		applyStackedControlLayout(self, mobile, selector, selectorWidth)
	end

	local hue, saturation, brightness = defaultColor:ToHSV()
	function control:_render(value)
		if not self._preserveHSV then
			hue, saturation, brightness = value:ToHSV()
		end
		swatch.BackgroundColor3 = value
		swatch.BackgroundTransparency = self.Transparency
		hexLabel.Text = colorToHex(value)
	end

	function control:GetTransparency()
		return self.Transparency
	end

	function control:SetTransparency(value, setOptions)
		value = math.clamp(tonumber(value) or 0, 0, 1)
		setOptions = setOptions or {}
		local previous = self.Transparency
		if previous == value and not setOptions.Force then
			return false
		end
		self.AllowTransparency = true
		self.Transparency = value
		swatch.BackgroundTransparency = value
		if not setOptions.Silent then
			self.TransparencyChanged:Fire(value, previous, setOptions.Source or "api")
			safeCall(options.OnTransparencyChanged, value, previous, setOptions.Source or "api")
		end
		self._ui:_autoSaveIfEnabled(setOptions.Source, setOptions.Silent)
		return true
	end

	function control:OnTransparencyChanged(callback)
		return self.TransparencyChanged:Connect(callback)
	end

	function control:Reset(resetOptions)
		resetOptions = resetOptions or {}
		resetOptions.Source = resetOptions.Source or "reset"
		local colorChanged = Control.Reset(self, resetOptions)
		local transparencyChanged = self:SetTransparency(self.DefaultTransparency, resetOptions)
		return colorChanged or transparencyChanged
	end

	function control:Close()
		if self._ui._popupOwner == self then
			self._ui:_closePopup()
			self._ui._popupOwner = nil
		end
	end

	function control:Open()
		if self.Disabled then
			return false
		end
		self._ui._popupOwner = self
		local popupHeight = self.AllowTransparency and 300 or 272
		local popup, popupMaid = self._ui:_openPopup(selector, {
			Name = "ColorPicker",
			Width = 292,
			Height = popupHeight,
		})
		local content = create("ScrollingFrame", {
			Name = "Content",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, popupHeight),
			ScrollBarThickness = 0,
			ScrollBarImageColor3 = self._ui.Theme.Border,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollingEnabled = false,
			ZIndex = 504,
			Parent = popup,
		})
		self._ui:_bindTheme(content, { ScrollBarImageColor3 = "Border" })
		local function updateScrolling()
			local scrolling = popup.AbsoluteSize.Y + 1 < popupHeight
			content.ScrollingEnabled = scrolling
			content.ScrollBarThickness = scrolling and 2 or 0
		end
		popupMaid:Give(popup:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScrolling))
		task.defer(updateScrolling)
		local saturationArea = create("TextButton", {
			Name = "Saturation",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -56, 0, 174),
			BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 505,
			Parent = content,
		})
		addCorner(saturationArea, 8)
		local whiteLayer = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 506,
			Parent = saturationArea,
		})
		addCorner(whiteLayer, 8)
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = whiteLayer,
		})
		local blackLayer = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 507,
			Parent = saturationArea,
		})
		addCorner(blackLayer, 8)
		create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = blackLayer,
		})
		local saturationPoint = create("Frame", {
			Name = "Point",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 509,
			Parent = saturationArea,
		})
		addCorner(saturationPoint, 7)
		addStroke(saturationPoint, Color3.fromRGB(20, 20, 20), 0, 2)

		local hueBar = create("TextButton", {
			Name = "Hue",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(24, 174),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 505,
			Parent = content,
		})
		addCorner(hueBar, 8)
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
				ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
				ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
				ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
			}),
			Parent = hueBar,
		})
		local huePoint = create("Frame", {
			Name = "Point",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, hue),
			Size = UDim2.new(1, 6, 0, 4),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 509,
			Parent = hueBar,
		})
		addCorner(huePoint, 2)
		addStroke(huePoint, Color3.fromRGB(20, 20, 20), 0.2, 1)

		local controlsTop = 196
		local alphaBar
		local alphaPoint
		if self.AllowTransparency then
			alphaBar = create("TextButton", {
				Name = "Alpha",
				Position = UDim2.fromOffset(12, controlsTop),
				Size = UDim2.new(1, -24, 0, 18),
				BackgroundColor3 = self._value,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 505,
				Parent = content,
			})
			addCorner(alphaBar, 5)
			create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = alphaBar,
			})
			alphaPoint = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(self.Transparency, 0.5),
				Size = UDim2.fromOffset(6, 24),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 509,
				Parent = alphaBar,
			})
			addCorner(alphaPoint, 3)
			addStroke(alphaPoint, Color3.fromRGB(20, 20, 20), 0.2, 1)
			controlsTop = controlsTop + 28
		end

		local preview = create("Frame", {
			Name = "Preview",
			Position = UDim2.fromOffset(12, controlsTop),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = self._value,
			BackgroundTransparency = self.Transparency,
			BorderSizePixel = 0,
			ZIndex = 505,
			Parent = content,
		})
		addCorner(preview, 7)
		local hexBox = create("TextBox", {
			Name = "Hex",
			Position = UDim2.fromOffset(54, controlsTop),
			Size = UDim2.new(1, -122, 0, 34),
			BackgroundColor3 = self._ui.Theme.SurfaceAlt,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.Code,
			Text = colorToHex(self._value),
			TextSize = 11,
			TextColor3 = self._ui.Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 505,
			Parent = content,
		})
		addCorner(hexBox, 7)
		self._ui:_bindTheme(hexBox, {
			BackgroundColor3 = "SurfaceAlt",
			TextColor3 = "Text",
		})
		local close = create("TextButton", {
			Name = "Done",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, controlsTop),
			Size = UDim2.fromOffset(52, 34),
			BackgroundColor3 = self._ui.Theme.Accent,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamMedium,
			Text = "Done",
			TextSize = 10,
			TextColor3 = self._ui.Theme.AccentText,
			ZIndex = 505,
			Parent = content,
		})
		addCorner(close, 7)
		self._ui:_bindTheme(close, {
			BackgroundColor3 = "Accent",
			TextColor3 = "AccentText",
		})

		local function updateVisuals()
			local color = Color3.fromHSV(hue, saturation, brightness)
			saturationArea.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			saturationPoint.Position = UDim2.fromScale(saturation, 1 - brightness)
			huePoint.Position = UDim2.fromScale(0.5, hue)
			preview.BackgroundColor3 = color
			preview.BackgroundTransparency = control.Transparency
			hexBox.Text = colorToHex(color)
			if alphaBar then
				alphaBar.BackgroundColor3 = color
				alphaPoint.Position = UDim2.fromScale(control.Transparency, 0.5)
			end
		end

		local activeArea
		local activeInput
		local function updateFromInput(input)
			if activeArea == "saturation" then
				saturation = math.clamp((input.Position.X - saturationArea.AbsolutePosition.X) / saturationArea.AbsoluteSize.X, 0, 1)
				brightness = 1 - math.clamp((input.Position.Y - saturationArea.AbsolutePosition.Y) / saturationArea.AbsoluteSize.Y, 0, 1)
				control._preserveHSV = true
				control:Set(Color3.fromHSV(hue, saturation, brightness), { Source = "user" })
				control._preserveHSV = false
			elseif activeArea == "hue" then
				hue = math.clamp((input.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
				control._preserveHSV = true
				control:Set(Color3.fromHSV(hue, saturation, brightness), { Source = "user" })
				control._preserveHSV = false
			elseif activeArea == "alpha" and alphaBar then
				local alpha = math.clamp((input.Position.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
				control:SetTransparency(alpha, { Source = "user" })
			end
			updateVisuals()
		end
		local function beginDrag(area, input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				activeArea = area
				activeInput = input
				updateFromInput(input)
			end
		end
		popupMaid:Give(saturationArea.InputBegan:Connect(function(input)
			beginDrag("saturation", input)
		end))
		popupMaid:Give(hueBar.InputBegan:Connect(function(input)
			beginDrag("hue", input)
		end))
		if alphaBar then
			popupMaid:Give(alphaBar.InputBegan:Connect(function(input)
				beginDrag("alpha", input)
			end))
		end
		popupMaid:Give(UserInputService.InputChanged:Connect(function(input)
			if activeArea and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
				updateFromInput(input)
			end
		end))
		popupMaid:Give(UserInputService.InputEnded:Connect(function(input)
			if input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
				activeArea = nil
				activeInput = nil
			end
		end))
		popupMaid:Give(hexBox.FocusLost:Connect(function()
			local color = hexToColor(hexBox.Text)
			if color then
				control:Set(color, { Source = "user" })
				hue, saturation, brightness = color:ToHSV()
			else
				hexBox.Text = colorToHex(control._value)
			end
			updateVisuals()
		end))
		popupMaid:Give(close.Activated:Connect(function()
			control:Close()
		end))
		popupMaid:Give(function()
			if self._ui._popupOwner == control then
				self._ui._popupOwner = nil
			end
		end)
		updateVisuals()
		return true
	end

	control.Update = control.Set
	control._maid:Give(selector.Activated:Connect(function()
		if self._ui._popupOwner == control then
			control:Close()
		else
			control:Open()
		end
	end))
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateColorPicker = Section.AddColorPicker
Section.AddColorpicker = Section.AddColorPicker
Section.CreateColorpicker = Section.AddColorPicker
Section.ColorPicker = Section.AddColorPicker
Section.Colorpicker = Section.AddColorPicker

function Section:AddProgress(first, second)
	local options = normalizeOptions(first, second)
	local valueOptions = type(options.Value) == "table" and options.Value or nil
	if valueOptions then
		options.Min = options.Min or valueOptions.Min
		options.Max = options.Max or valueOptions.Max
	end
	options.Min = tonumber(options.Min) or 0
	options.Max = tonumber(options.Max) or 100
	if options.Min > options.Max then
		options.Min, options.Max = options.Max, options.Min
	end
	local defaultValue = options.Default
	if defaultValue == nil then
		if valueOptions then
			defaultValue = valueOptions.Default
		else
			defaultValue = options.Value
		end
	end
	defaultValue = tonumber(defaultValue) or options.Min
	local function sanitize(value)
		value = tonumber(value)
		if not value then
			error("Progress value must be a number")
		end
		return math.clamp(value, options.Min, options.Max)
	end
	local control = self:_makeControl("Progress", options, sanitize(defaultValue), sanitize, options.Description and 82 or 72)
	control.Min = options.Min
	control.Max = options.Max
	control.Indeterminate = false
	control._indeterminateRevision = 0
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(76, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "0%",
		TextSize = 10,
		TextColor3 = self._ui.Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = control.Root,
	})
	self._ui:_bindTheme(valueLabel, { TextColor3 = "Muted" })
	local track = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 7),
		BackgroundColor3 = self._ui.Theme.Border,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = control.Root,
	})
	addCorner(track, 4)
	self._ui:_bindTheme(track, { BackgroundColor3 = "Border" })
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = self._ui.Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(fill, 4)
	self._ui:_bindTheme(fill, { BackgroundColor3 = "Accent" })

	local function format(value, percentage)
		if type(options.Format) == "function" then
			local ok, result = pcall(options.Format, value, percentage)
			if ok then
				return tostring(result)
			end
		end
		if options.DisplayMode == "Value" then
			return tostring(value) .. tostring(options.Suffix or "")
		end
		return tostring(math.floor(percentage * 100 + 0.5)) .. "%"
	end

	function control:_render(value, _, renderOptions)
		if self.Indeterminate then
			return
		end
		local ratio = math.clamp((value - self.Min) / math.max(0.000001, self.Max - self.Min), 0, 1)
		valueLabel.Text = format(value, ratio)
		self._ui:_tween(fill, renderOptions and renderOptions.Instant and 0 or 0.18, {
			Position = UDim2.new(),
			Size = UDim2.fromScale(ratio, 1),
		})
	end

	function control:GetRatio()
		return math.clamp((self._value - self.Min) / math.max(0.000001, self.Max - self.Min), 0, 1)
	end

	function control:GetPercentage()
		return self:GetRatio() * 100
	end

	function control:SetRange(minimum, maximum)
		minimum = tonumber(minimum)
		maximum = tonumber(maximum)
		if not minimum or not maximum then
			return false
		end
		if minimum > maximum then
			minimum, maximum = maximum, minimum
		end
		self.Min = minimum
		self.Max = maximum
		options.Min = minimum
		options.Max = maximum
		self:Set(self._value, { Force = true, Source = "range" })
		return true
	end

	function control:SetIndeterminate(enabled)
		self.Indeterminate = enabled == true
		self._indeterminateRevision = self._indeterminateRevision + 1
		local revision = self._indeterminateRevision
		if not self.Indeterminate then
			self:_render(self._value, nil, {})
			return self
		end
		valueLabel.Text = "Working..."
		task.spawn(function()
			while not self._destroyed and self.Indeterminate and revision == self._indeterminateRevision do
				fill.Position = UDim2.fromScale(-0.35, 0)
				fill.Size = UDim2.fromScale(0.35, 1)
				self._ui:_tween(fill, 0.85, { Position = UDim2.fromScale(1.05, 0) }, Enum.EasingStyle.Quad)
				task.wait(0.9)
			end
		end)
		return self
	end

	control._maid:Give(function()
		control._indeterminateRevision = control._indeterminateRevision + 1
	end)
	self:_finishControl(control, options.FireOnInit)
	if options.Indeterminate then
		control:SetIndeterminate(true)
	end
	return control
end

Section.CreateProgress = Section.AddProgress
Section.AddProgressBar = Section.AddProgress
Section.CreateProgressBar = Section.AddProgress
Section.ProgressBar = Section.AddProgress
Section.Progress = Section.AddProgress

function Section:AddSegmented(first, second)
	local options = normalizeOptions(first, second)
	local choices = normalizeChoices(options.Values or options.Options or {})
	assert(#choices > 0, "Segmented control requires at least one value")
	local defaultValue = options.Default or options.Value or choices[1].Value
	local function sanitize(value)
		local choice = findChoice(choices, value)
		if not choice then
			error("Segmented value is not in Values")
		end
		return choice.Value
	end
	local control = self:_makeControl("Segmented", options, sanitize(defaultValue), sanitize, options.Description and 98 or 88)
	control.Values = choices
	control.TitleLabel.Size = UDim2.new(1, -24, 0, 24)
	local holder = create("Frame", {
		Name = "Segments",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundColor3 = self._ui.Theme.Surface,
		BorderSizePixel = 0,
		Parent = control.Root,
	})
	addCorner(holder, 8)
	addPadding(holder, 3, 3, 3, 3)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	self._ui:_bindTheme(holder, { BackgroundColor3 = "Surface" })
	local buttons = {}
	local segmentMaid = Maid.new()
	control._maid:Give(function()
		segmentMaid:Clean()
	end)

	local function build()
		segmentMaid:Clean()
		segmentMaid = Maid.new()
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		table.clear(buttons)
		local widthScale = 1 / math.max(1, #choices)
		for index, choice in ipairs(choices) do
			local button = create("TextButton", {
				Name = "Segment_" .. tostring(index),
				Size = UDim2.new(widthScale, -3, 1, 0),
				BackgroundColor3 = self._ui.Theme.Accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Enum.Font.GothamMedium,
				Text = choice.Title,
				TextSize = 10,
				TextColor3 = self._ui.Theme.Muted,
				LayoutOrder = index,
				Parent = holder,
			})
			addCorner(button, 6)
			buttons[choice] = button
			segmentMaid:Give(button.Activated:Connect(function()
				if not control.Disabled and not choice.Disabled and not choice.Locked then
					control:Set(choice.Value, { Source = "user" })
				end
			end))
		end
	end

	function control:_render(value, _, renderOptions)
		for choice, button in pairs(buttons) do
			local selected = valuesEqual(value, choice.Value)
			self._ui:_tween(button, renderOptions and renderOptions.Instant and 0 or 0.12, {
				BackgroundTransparency = selected and 0 or 1,
				TextColor3 = selected and self._ui.Theme.AccentText or self._ui.Theme.Muted,
			})
		end
	end

	function control:SetValues(values, preserveSelection)
		choices = normalizeChoices(values)
		if #choices == 0 then
			return false
		end
		self.Values = choices
		build()
		if preserveSelection and findChoice(choices, self._value) then
			self:Set(self._value, { Force = true, Source = "values" })
		else
			self:Set(choices[1].Value, { Source = "values" })
		end
		return true
	end

	build()
	return self:_finishControl(control, options.FireOnInit)
end

Section.CreateSegmented = Section.AddSegmented
Section.Segmented = Section.AddSegmented
Section.AddRadio = Section.AddSegmented
Section.CreateRadio = Section.AddSegmented
Section.Radio = Section.AddSegmented

function Section:_makeStaticControl(kind, value, options)
	local control = setmetatable({}, Control)
	control._ui = self._ui
	control._section = self
	control._maid = Maid.new()
	control._destroyed = false
	control.Type = kind
	control.Title = tostring(options.Title or options.Name or kind)
	control.Description = tostring(options.Description or "")
	control.Callback = options.Callback
	control.Default = deepCopy(value)
	control._value = deepCopy(value)
	control.Flag = nil
	control.Changed = Signal.new()
	table.insert(self._controls, control)
	return control
end

function Section:AddLabel(first, second)
	local options = normalizeOptions(first, second)
	local text = options.Text or options.Title or options.Name or "Label"
	local control = self:_makeStaticControl("Label", tostring(text), options)
	control._sanitize = function(value)
		return tostring(value or "")
	end
	local root = create("Frame", {
		Name = "Label_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, options.Height or 34),
		BackgroundTransparency = 1,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = options.Bold and Enum.Font.GothamMedium or Enum.Font.Gotham,
		Text = tostring(text),
		TextSize = options.TextSize or 11,
		TextColor3 = self._ui.Theme[options.ColorToken or "Muted"] or self._ui.Theme.Muted,
		TextWrapped = options.Wrap == true,
		RichText = options.RichText == true,
		TextXAlignment = options.Alignment or Enum.TextXAlignment.Left,
		Parent = root,
	})
	self._ui:_bindTheme(label, { TextColor3 = options.ColorToken or "Muted" })
	control.Root = root
	control.TitleLabel = label
	function control:_render(value)
		label.Text = tostring(value)
	end
	control._searchEntry = self._ui:_registerSearchItem({
		Title = tostring(text),
		Kind = "Label",
		Target = control,
		Action = function()
			self._window:SelectTab(self._tab)
		end,
	})
	return control
end

Section.CreateLabel = Section.AddLabel
Section.Label = Section.AddLabel

function Section:AddParagraph(first, second)
	local options = normalizeOptions(first, second)
	if type(first) == "string" and type(second) == "string" then
		options = { Title = first, Content = second }
	end
	options.Title = options.Title or options.Name or "Paragraph"
	options.Content = options.Content or options.Text or options.Description or ""
	local value = { Title = tostring(options.Title), Content = tostring(options.Content) }
	local control = self:_makeStaticControl("Paragraph", value, options)
	control._sanitize = function(nextValue)
		if type(nextValue) == "string" then
			return { Title = control._value.Title, Content = nextValue }
		end
		if type(nextValue) ~= "table" then
			error("Paragraph value must be a string or table")
		end
		return {
			Title = tostring(nextValue.Title or control._value.Title),
			Content = tostring(nextValue.Content or nextValue.Text or ""),
		}
	end
	local root = create("Frame", {
		Name = "Paragraph_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = self._ui.Theme.SurfaceAlt,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	addCorner(root, 9)
	local stroke = addStroke(root, self._ui.Theme.Border, 0.55, 1)
	self._ui:_bindTheme(root, { BackgroundColor3 = "SurfaceAlt" })
	self._ui:_bindTheme(stroke, { Color = "Border" })
	addPadding(root, 12, 12, 12, 12)
	create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	local titleLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = value.Title,
		TextSize = 12,
		TextColor3 = self._ui.Theme.Text,
		TextWrapped = true,
		RichText = options.RichText == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = root,
	})
	local contentLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = value.Content,
		TextSize = 10,
		TextColor3 = self._ui.Theme.Muted,
		TextWrapped = true,
		RichText = options.RichText == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = root,
	})
	self._ui:_bindTheme(titleLabel, { TextColor3 = "Text" })
	self._ui:_bindTheme(contentLabel, { TextColor3 = "Muted" })
	control.Root = root
	control.TitleLabel = titleLabel
	control.DescriptionLabel = contentLabel
	function control:_render(nextValue)
		titleLabel.Text = nextValue.Title
		contentLabel.Text = nextValue.Content
	end
	control._searchEntry = self._ui:_registerSearchItem({
		Title = value.Title,
		Description = value.Content,
		Kind = "Paragraph",
		Target = control,
		Action = function()
			self._window:SelectTab(self._tab)
		end,
	})
	return control
end

Section.CreateParagraph = Section.AddParagraph
Section.Paragraph = Section.AddParagraph

function Section:AddDivider(options)
	options = type(options) == "table" and options or {}
	local control = self:_makeStaticControl("Divider", true, options)
	local root = create("Frame", {
		Name = "Divider_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, options.Height or 13),
		BackgroundTransparency = 1,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	local line = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = self._ui.Theme.Border,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = root,
	})
	self._ui:_bindTheme(line, { BackgroundColor3 = "Border" })
	control.Root = root
	return control
end

Section.CreateDivider = Section.AddDivider
Section.Divider = Section.AddDivider

function Section:AddSpacer(height)
	local options = type(height) == "table" and height or { Height = height }
	local control = self:_makeStaticControl("Spacer", true, options)
	control.Root = create("Frame", {
		Name = "Spacer_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, tonumber(options.Height) or 8),
		BackgroundTransparency = 1,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	return control
end

Section.CreateSpacer = Section.AddSpacer
Section.Space = Section.AddSpacer
Section.Spacer = Section.AddSpacer

function Section:AddCode(first, second)
	local options = normalizeOptions(first, second)
	if type(first) == "string" and second == nil then
		options = { Code = first, Title = "Code" }
	end
	options.Title = options.Title or options.Name or "Code"
	local codeValue = tostring(options.Code or options.Value or "")
	local copyText = tostring(options.CopyText or "Copy")
	local copiedText = tostring(options.CopiedText or "Copied")
	local failedText = tostring(options.FailedText or "Failed")
	local unavailableText = tostring(options.UnavailableText or "Unavailable")
	local control = self:_makeStaticControl("Code", codeValue, options)
	control._sanitize = function(value)
		return tostring(value or "")
	end
	local root = create("Frame", {
		Name = "Code_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, options.Height or 170),
		BackgroundColor3 = self._ui.Theme.SurfaceAlt,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	addCorner(root, 9)
	local rootStroke = addStroke(root, self._ui.Theme.Border, 0.35, 1)
	self._ui:_bindTheme(root, { BackgroundColor3 = "SurfaceAlt" })
	self._ui:_bindTheme(rootStroke, { Color = "Border" })
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	local headerDivider = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, 0),
		Size = UDim2.new(1, -20, 0, 1),
		BackgroundColor3 = self._ui.Theme.Border,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = header,
	})
	self._ui:_bindTheme(headerDivider, { BackgroundColor3 = "Border" })
	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -96, 1, 0),
		Font = Enum.Font.GothamMedium,
		Text = tostring(options.Title),
		TextSize = 12,
		TextColor3 = self._ui.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	self._ui:_bindTheme(title, { TextColor3 = "Text" })
	local copyButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(64, 26),
		BackgroundColor3 = self._ui.Theme.SurfaceHover,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		Text = copyText,
		TextSize = 10,
		TextColor3 = self._ui.Theme.Text,
		Parent = header,
	})
	addCorner(copyButton, 6)
	local copyStroke = addStroke(copyButton, self._ui.Theme.Border, 0.55, 1)
	self._ui:_bindTheme(copyButton, {
		BackgroundColor3 = "SurfaceHover",
		TextColor3 = "Text",
	})
	self._ui:_bindTheme(copyStroke, { Color = "Border" })
	local scroll = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self._ui.Theme.Border,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Parent = root,
	})
	self._ui:_bindTheme(scroll, { ScrollBarImageColor3 = "Border" })
	local codeLabel = create("TextLabel", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = codeValue,
		TextSize = options.TextSize or 12,
		TextColor3 = self._ui.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = scroll,
	})
	self._ui:_bindTheme(codeLabel, { TextColor3 = "Text" })
	local function updateCanvas()
		scroll.CanvasSize = UDim2.fromOffset(codeLabel.AbsoluteSize.X + 24, codeLabel.AbsoluteSize.Y + 20)
	end
	control._maid:Give(codeLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas))
	control._maid:Give(copyButton.Activated:Connect(function()
		local setClipboard = getEnvironmentFunction("setclipboard") or getEnvironmentFunction("toclipboard")
		if setClipboard then
			local ok = pcall(setClipboard, control._value)
			copyButton.Text = ok and copiedText or failedText
		else
			copyButton.Text = unavailableText
		end
		task.delay(1.1, function()
			if copyButton.Parent then
				copyButton.Text = copyText
			end
		end)
	end))
	control.Root = root
	control.TitleLabel = title
	function control:_render(value)
		codeLabel.Text = value
		task.defer(updateCanvas)
	end
	control.SetCode = control.Set
	control._searchEntry = self._ui:_registerSearchItem({
		Title = tostring(options.Title),
		Description = codeValue,
		Kind = "Code",
		Target = control,
		Action = function()
			self._window:SelectTab(self._tab)
		end,
	})
	task.defer(updateCanvas)
	return control
end

Section.CreateCode = Section.AddCode
Section.Code = Section.AddCode

function Section:AddImage(options)
	options = type(options) == "table" and shallowCopy(options) or { Image = options }
	local imageValue = tostring(options.Image or options.Asset or "")
	if tonumber(imageValue) then
		imageValue = "rbxassetid://" .. imageValue
	end
	local control = self:_makeStaticControl("Image", imageValue, options)
	control._sanitize = function(value)
		value = tostring(value or "")
		if tonumber(value) then
			value = "rbxassetid://" .. value
		end
		return value
	end
	local root = create("Frame", {
		Name = "Image_" .. tostring(self._ui:_nextId()),
		Size = UDim2.new(1, 0, 0, options.Height or 180),
		BackgroundColor3 = self._ui.Theme.SurfaceAlt,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = #self._controls,
		Parent = self.Holder,
	})
	addCorner(root, 9)
	local rootStroke = addStroke(root, self._ui.Theme.Border, 0.45, 1)
	self._ui:_bindTheme(root, { BackgroundColor3 = "SurfaceAlt" })
	self._ui:_bindTheme(rootStroke, { Color = "Border" })
	local image = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = imageValue,
		ImageColor3 = options.ImageColor or Color3.new(1, 1, 1),
		ImageTransparency = options.Transparency or 0,
		ScaleType = options.ScaleType or Enum.ScaleType.Crop,
		Parent = root,
	})
	if options.Title then
		local scrim = create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.38,
			BorderSizePixel = 0,
			Parent = root,
		})
		local title = create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = tostring(options.Title),
			TextSize = 12,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = scrim,
		})
		control.TitleLabel = title
	end
	control.Root = root
	control.Image = image
	function control:_render(value)
		image.Image = value
	end
	control.SetImage = control.Set
	return control
end

Section.CreateImage = Section.AddImage
Section.Image = Section.AddImage

local Notification = {}
Notification.__index = Notification

local function getNotificationViewport(ui)
	local width = ui.NotificationLayer.AbsoluteSize.X
	local height = ui.NotificationLayer.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		width = math.min(340, math.max(140, viewport.X - 24))
		height = math.max(76, viewport.Y - 32)
	end
	return math.max(140, width), math.max(76, height)
end

local function measureNotification(content, width, actionCount, availableHeight)
	local actionHeight = actionCount > 0 and 40 or 0
	local contentWidth = math.max(70, width - 70)
	local measuredHeight = math.max(18, TextService:GetTextSize(content, 10, Typography.Regular, Vector2.new(contentWidth, 1000)).Y)
	local minimumHeight = actionHeight > 0 and 113 or 76
	local maximumHeight = math.max(minimumHeight, math.min(190, availableHeight))
	local cardHeight = math.clamp(55 + measuredHeight + actionHeight, minimumHeight, maximumHeight)
	local visibleContentHeight = math.max(18, cardHeight - 55 - actionHeight)
	return cardHeight, visibleContentHeight, actionHeight
end

local function trimNotificationStack(ui, maxVisible, extraHeight, preserve)
	maxVisible = math.max(1, math.floor(tonumber(maxVisible) or 4))
	local _, availableHeight = getNotificationViewport(ui)
	local function stackHeight()
		local total = tonumber(extraHeight) or 0
		local count = extraHeight and 1 or 0
		for _, notification in ipairs(ui._notifications) do
			if not notification._closed and notification.Root then
				total = total + notification.Root.Size.Y.Offset
				count = count + 1
			end
		end
		return total + math.max(0, count - 1) * 10, count
	end
	while true do
		local total, count = stackHeight()
		if count <= maxVisible and total <= availableHeight then
			break
		end
		local candidate
		for _, notification in ipairs(ui._notifications) do
			if notification ~= preserve and not notification._closed then
				candidate = notification
				break
			end
		end
		if not candidate then
			break
		end
		if candidate.Root then
			candidate.Root.Visible = false
		end
		candidate:Close("overflow")
	end
end

function Velora:Notify(options)
	if type(options) == "string" then
		options = { Title = "Notification", Content = options }
	else
		options = shallowCopy(options)
	end
	options.Title = tostring(options.Title or "Notification")
	options.Content = tostring(options.Content or options.Description or "")
	options.Type = options.Type or "Info"
	local notificationId = options.Id or (options.Title .. "\0" .. options.Content)
	if options.Deduplicate ~= false then
		for _, existing in ipairs(self._notifications) do
			if not existing._closed and existing.Id == notificationId then
				existing:Update(options)
				return existing
			end
		end
	end

	local handle = setmetatable({}, Notification)
	handle._ui = self
	handle._maid = Maid.new()
	handle._closed = false
	handle._revision = 0
	handle.Id = notificationId
	handle.Options = options
	handle.Closed = Signal.new()
	handle._maid:Give(handle.Closed)

	local typeTokens = {
		Info = "Accent",
		Success = "Success",
		Warning = "Warning",
		Error = "Danger",
		Loading = "Accent",
	}
	local typeLetters = {
		Info = "i",
		Success = "+",
		Warning = "!",
		Error = "x",
		Loading = "...",
	}
	local token = typeTokens[options.Type] or "Accent"
	local actionCount = type(options.Actions) == "table" and math.min(#options.Actions, 3) or 0
	local notificationWidth, availableHeight = getNotificationViewport(self)
	local cardHeight, contentHeight, actionHeight = measureNotification(options.Content, notificationWidth, actionCount, availableHeight)
	trimNotificationStack(self, options.MaxVisible, cardHeight)
	local card = create("CanvasGroup", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, cardHeight),
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		LayoutOrder = self:_nextId(),
		ZIndex = 901,
		Parent = self.NotificationLayer,
	})
	addCorner(card, 11)
	local cardStroke = addStroke(card, self.Theme.Border, 0.15, 1)
	self:_bindTheme(card, { BackgroundColor3 = "Surface" })
	self:_bindTheme(cardStroke, { Color = "Border" })
	handle.Root = card
	handle._maid:Give(card)

	local stripe = create("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = self.Theme[token],
		BorderSizePixel = 0,
		ZIndex = 902,
		Parent = card,
	})
	self:_bindTheme(stripe, { BackgroundColor3 = token })
	local icon = create("Frame", {
		Name = "Icon",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = self.Theme[token],
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 902,
		Parent = card,
	})
	addCorner(icon, 8)
	self:_bindTheme(icon, { BackgroundColor3 = token })
	local iconLabel = makeIconLabel(icon, options.Icon or options.Image or typeLetters[options.Type] or "i", 30, 903)
	iconLabel.Size = UDim2.fromScale(1, 1)
	if iconLabel:IsA("TextLabel") then
		iconLabel.TextSize = options.Type == "Loading" and 9 or 13
	end
	bindIconTheme(self, iconLabel, token)

	local titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 11),
		Size = UDim2.new(1, -90, 0, 22),
		Font = Enum.Font.GothamMedium,
		Text = options.Title,
		TextSize = 12,
		TextColor3 = self.Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 902,
		Parent = card,
	})
	local contentLabel = create("TextLabel", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(54, 34),
		Size = UDim2.new(1, -70, 0, contentHeight),
		Font = Enum.Font.Gotham,
		Text = options.Content,
		TextSize = 10,
		TextColor3 = self.Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 902,
		Parent = card,
	})
	self:_bindTheme(titleLabel, { TextColor3 = "Text" })
	self:_bindTheme(contentLabel, { TextColor3 = "Muted" })
	handle.TitleLabel = titleLabel
	handle.ContentLabel = contentLabel

	local closeButton = create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "×",
		TextSize = 10,
		TextColor3 = self.Theme.Muted,
		Visible = options.CanClose ~= false,
		ZIndex = 904,
		Parent = card,
	})
	self:_bindTheme(closeButton, { TextColor3 = "Muted" })
	handle._maid:Give(closeButton.Activated:Connect(function()
		handle:Close("user")
	end))

	local actions
	if actionHeight > 0 then
		actions = create("Frame", {
			Name = "Actions",
			Position = UDim2.new(0, 54, 1, -42),
			Size = UDim2.new(1, -68, 0, 30),
			BackgroundTransparency = 1,
			ZIndex = 902,
			Parent = card,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Parent = actions,
		})
		local primaryTextTokens = {
			Accent = "AccentText",
			Success = "SuccessText",
			Warning = "WarningText",
			Danger = "DangerText",
		}
		for index, actionOptions in ipairs(options.Actions) do
			if index > 3 then
				break
			end
			local actionTitle = tostring(actionOptions.Title or actionOptions.Name or "Action")
			local primary = actionOptions.Variant == "Primary"
			local backgroundToken = primary and token or "SurfaceHover"
			local textToken = primary and (primaryTextTokens[token] or "AccentText") or "Text"
			local actionButton = create("TextButton", {
				Size = UDim2.new(1 / actionCount, -((actionCount - 1) * 6 / actionCount), 0, 28),
				BackgroundColor3 = self.Theme[backgroundToken],
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Enum.Font.GothamMedium,
				Text = actionTitle,
				TextSize = 9,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = self.Theme[textToken],
				LayoutOrder = index,
				ZIndex = 903,
				Parent = actions,
			})
			addCorner(actionButton, 6)
			self:_bindTheme(actionButton, {
				BackgroundColor3 = backgroundToken,
				TextColor3 = textToken,
			})
			handle._maid:Give(actionButton.Activated:Connect(function()
				safeCall(actionOptions.Callback, handle)
				if actionOptions.Close ~= false then
					handle:Close("action")
				end
			end))
		end
	end
	handle.ActionsFrame = actions

	local progress = create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = self.Theme[token],
		BorderSizePixel = 0,
		ZIndex = 904,
		Parent = card,
	})
	self:_bindTheme(progress, { BackgroundColor3 = token })
	handle.Progress = progress

	function handle:_relayout()
		if self._closed or not card.Parent then
			return
		end
		local width, height = getNotificationViewport(self._ui)
		local nextHeight, nextContentHeight = measureNotification(self.Options.Content, width, actionCount, height)
		card.Size = UDim2.new(1, 0, 0, nextHeight)
		contentLabel.Size = UDim2.new(1, -70, 0, nextContentHeight)
		trimNotificationStack(self._ui, self.Options.MaxVisible, nil, self)
	end

	function handle:Update(nextOptions)
		if self._closed then
			return self
		end
		nextOptions = nextOptions or {}
		if nextOptions.Title then
			self.Options.Title = tostring(nextOptions.Title)
			self.TitleLabel.Text = self.Options.Title
		end
		if nextOptions.Content or nextOptions.Description then
			self.Options.Content = tostring(nextOptions.Content or nextOptions.Description)
			self.ContentLabel.Text = self.Options.Content
		end
		self:_relayout()
		if nextOptions.Duration then
			self.Options.Duration = nextOptions.Duration
			self:_startTimer()
		end
		return self
	end

	function handle:_startTimer()
		self._revision = self._revision + 1
		local revision = self._revision
		local duration = tonumber(self.Options.Duration)
		if duration == nil then
			duration = math.clamp(3 + (#self.Options.Content / 55), 3, 10)
		end
		progress.Size = UDim2.new(1, 0, 0, 2)
		if duration <= 0 or duration == math.huge then
			progress.Visible = false
			return
		end
		progress.Visible = true
		self._ui:_tween(progress, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
		task.delay(duration, function()
			if not self._closed and self._revision == revision then
				self:Close("timeout")
			end
		end)
	end

	function handle:Close(reason)
		if self._closed then
			return
		end
		self._closed = true
		self._revision = self._revision + 1
		local index = table.find(self._ui._notifications, self)
		if index then
			table.remove(self._ui._notifications, index)
		end
		self.Closed:Fire(reason or "api")
		safeCall(self.Options.OnClose, reason or "api")
		self._ui:_tween(card, 0.14, { GroupTransparency = 1 })
		task.delay(self._ui.Options.ReducedMotion and 0 or 0.16, function()
			self._maid:Clean()
		end)
	end

	table.insert(self._notifications, handle)
	handle._maid:Give(self.NotificationLayer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		handle:_relayout()
	end))
	handle:_relayout()
	self:_tween(card, 0.18, { GroupTransparency = 0 })
	handle:_startTimer()
	return handle
end

function Velora:Dialog(options)
	if self._destroyed or not self.ModalLayer or not self.ModalLayer.Parent then
		return nil
	end
	options = type(options) == "table" and shallowCopy(options) or { Content = tostring(options or "") }
	options.Title = tostring(options.Title or "Dialog")
	options.Content = tostring(options.Content or options.Description or "")
	options.Buttons = options.Buttons or { { Title = "OK", Variant = "Primary" } }
	if self._dialogMaid then
		self._dialogMaid:Clean()
	end
	local maid = Maid.new()
	self._dialogMaid = maid
	local closed = Signal.new()
	maid:Give(closed)
	local handle = { Closed = closed, _closed = false }

	local overlay = create("TextButton", {
		Name = "DialogOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.Overlay,
		BackgroundTransparency = 0.32,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 701,
		Parent = self.ModalLayer,
	})
	self:_bindTheme(overlay, { BackgroundColor3 = "Overlay" })
	maid:Give(overlay)
	local viewportWidth = self.ModalLayer.AbsoluteSize.X
	if viewportWidth <= 0 then
		local camera = workspace.CurrentCamera
		viewportWidth = camera and camera.ViewportSize.X or 1280
	end
	local dialogWidth = math.min(tonumber(options.Width) or 410, math.max(120, viewportWidth - 24))
	local measurementWidth = math.max(80, dialogWidth - 40)
	local contentHeight = math.max(22, TextService:GetTextSize(options.Content, 12, Typography.Regular, Vector2.new(measurementWidth, 1000)).Y)
	local cardHeight = math.clamp(120 + math.min(contentHeight, 240), 176, 360)
	local card = create("CanvasGroup", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 703,
		Parent = self.ModalLayer,
	})
	create("UISizeConstraint", {
		MaxSize = Vector2.new(dialogWidth, cardHeight),
		Parent = card,
	})
	maid:Give(card)
	addCorner(card, 13)
	local cardStroke = addStroke(card, self.Theme.Border, 0.35, 1)
	self:_bindTheme(card, { BackgroundColor3 = "Surface" })
	self:_bindTheme(cardStroke, { Color = "Border" })
	local accentMark = create("Frame", {
		Position = UDim2.fromOffset(20, 19),
		Size = UDim2.fromOffset(3, 24),
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 704,
		Parent = card,
	})
	addCorner(accentMark, 2)
	self:_bindTheme(accentMark, { BackgroundColor3 = "Accent" })

	local titleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(32, 17),
		Size = UDim2.new(1, -52, 0, 28),
		Font = Enum.Font.GothamBold,
		Text = options.Title,
		TextSize = 17,
		TextColor3 = self.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 704,
		Parent = card,
	})
	local contentScroll = create("ScrollingFrame", {
		Name = "ContentScroll",
		Position = UDim2.fromOffset(20, 54),
		Size = UDim2.new(1, -40, 1, -120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.Theme.Border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 704,
		Parent = card,
	})
	self:_bindTheme(contentScroll, { ScrollBarImageColor3 = "Border" })
	local contentLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.Gotham,
		Text = options.Content,
		TextSize = 12,
		TextColor3 = self.Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 704,
		Parent = contentScroll,
	})
	self:_bindTheme(titleLabel, { TextColor3 = "Text" })
	self:_bindTheme(contentLabel, { TextColor3 = "Muted" })
	local function updateContentCanvas()
		contentScroll.CanvasSize = UDim2.fromOffset(0, contentLabel.AbsoluteSize.Y + 2)
	end
	maid:Give(contentLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContentCanvas))
	task.defer(updateContentCanvas)
	local actionDivider = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -63),
		Size = UDim2.new(1, -40, 0, 1),
		BackgroundColor3 = self.Theme.Border,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 704,
		Parent = card,
	})
	self:_bindTheme(actionDivider, { BackgroundColor3 = "Border" })
	local actions = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.new(1, -40, 0, 36),
		BackgroundTransparency = 1,
		ZIndex = 704,
		Parent = card,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = actions,
	})

	function handle:Close(result)
		if self._closed then
			return
		end
		self._closed = true
		closed:Fire(result)
		if self._ui then
			self._ui:_tween(card, 0.14, { GroupTransparency = 1 })
		end
		task.delay(self._ui.Options.ReducedMotion and 0 or 0.15, function()
			maid:Clean()
		end)
	end
	handle._ui = self

	local buttonCount = math.min(#options.Buttons, 3)
	for index = 1, buttonCount do
		local buttonOptions = options.Buttons[index]
		local buttonTitle = tostring(buttonOptions.Title or buttonOptions.Name or "OK")
		local variant = buttonOptions.Variant or (index == buttonCount and "Primary" or "Secondary")
		local backgroundToken = variant == "Danger" and "Danger" or (variant == "Primary" and "Accent" or "SurfaceAlt")
		local textToken = variant == "Secondary" and "Text" or (variant == "Danger" and "DangerText" or "AccentText")
		local button = create("TextButton", {
			Size = UDim2.new(1 / buttonCount, -((8 * (buttonCount - 1)) / buttonCount), 0, 36),
			BackgroundColor3 = self.Theme[backgroundToken],
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Enum.Font.GothamMedium,
			Text = buttonTitle,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = self.Theme[textToken],
			LayoutOrder = index,
			ZIndex = 705,
			Parent = actions,
		})
		addCorner(button, 9)
		self:_bindTheme(button, {
			BackgroundColor3 = backgroundToken,
			TextColor3 = textToken,
		})
		local buttonHovered = false
		local function renderButton(state, duration)
			local baseColor = self.Theme[backgroundToken]
			local foreground = self.Theme[textToken]
			local targetColor = baseColor
			if state == "pressed" then
				targetColor = interactiveColor(baseColor, foreground, 0.13)
			elseif state == "hover" then
				targetColor = variant == "Secondary"
					and self.Theme.SurfaceHover
					or interactiveColor(baseColor, foreground, 0.08)
			end
			self:_tween(button, duration, { BackgroundColor3 = targetColor })
		end
		maid:Give(button.MouseEnter:Connect(function()
			buttonHovered = true
			renderButton("hover", 0.12)
		end))
		maid:Give(button.MouseLeave:Connect(function()
			buttonHovered = false
			renderButton("rest", 0.12)
		end))
		maid:Give(button.MouseButton1Down:Connect(function()
			renderButton("pressed", 0.08)
		end))
		maid:Give(button.MouseButton1Up:Connect(function()
			renderButton(buttonHovered and "hover" or "rest", 0.1)
		end))
		maid:Give(self.ThemeChanged:Connect(function()
			renderButton(buttonHovered and "hover" or "rest", 0.18)
		end))
		maid:Give(button.Activated:Connect(function()
			local result = buttonOptions.Value
			if result == nil then
				result = buttonOptions.Title or buttonOptions.Name
			end
			safeCall(buttonOptions.Callback, result, handle)
			if buttonOptions.Close ~= false then
				handle:Close(result)
			end
		end))
	end

	if options.Dismissible ~= false then
		maid:Give(overlay.Activated:Connect(function()
			handle:Close(nil)
		end))
	end
	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and options.Dismissible ~= false then
			handle:Close(nil)
		end
	end))
	maid:Give(function()
		if not handle._closed then
			handle._closed = true
			closed:Fire(nil)
		end
		if self._dialogMaid == maid then
			self._dialogMaid = nil
		end
	end)
	self:_tween(card, 0.18, { GroupTransparency = 0 })
	return handle
end

function Velora:RegisterCommand(options)
	assert(type(options) == "table", "Command options must be a table")
	assert(type(options.Callback) == "function", "Command Callback must be a function")
	local command = {
		Id = options.Id or ("command_" .. tostring(self:_nextId())),
		Title = tostring(options.Title or options.Name or "Command"),
		Description = tostring(options.Description or ""),
		Keywords = type(options.Keywords) == "table" and table.concat(options.Keywords, " ") or tostring(options.Keywords or ""),
		Callback = options.Callback,
		Removed = false,
	}
	command.SearchText = string.lower(command.Title .. " " .. command.Description .. " " .. command.Keywords)
	local owner = self
	function command:Destroy()
		if self.Removed then
			return
		end
		self.Removed = true
		local index = table.find(owner._commands, self)
		if index then
			table.remove(owner._commands, index)
		end
	end
	table.insert(self._commands, command)
	return command
end

function Velora:CloseCommandPalette()
	if self._commandMaid then
		self._commandMaid:Clean()
		self._commandMaid = nil
	end
end

function Velora:OpenCommandPalette()
	if self._destroyed then
		return false
	end
	self:CloseCommandPalette()
	local maid = Maid.new()
	self._commandMaid = maid
	local overlay = create("TextButton", {
		Name = "CommandOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self.Theme.Overlay,
		BackgroundTransparency = 0.48,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 751,
		Parent = self.ModalLayer,
	})
	self:_bindTheme(overlay, { BackgroundColor3 = "Overlay" })
	maid:Give(overlay)
	local card = create("CanvasGroup", {
		Name = "CommandPalette",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -48),
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 753,
		Parent = self.ModalLayer,
	})
	create("UISizeConstraint", {
		MaxSize = Vector2.new(540, 410),
		MinSize = Vector2.new(180, 160),
		Parent = card,
	})
	maid:Give(card)
	addCorner(card, 13)
	local cardStroke = addStroke(card, self.Theme.Border, 0, 1)
	self:_bindTheme(card, { BackgroundColor3 = "Surface" })
	self:_bindTheme(cardStroke, { Color = "Border" })

	local search = create("TextBox", {
		Name = "Search",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 0, 46),
		BackgroundColor3 = self.Theme.SurfaceAlt,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		Text = "",
		PlaceholderText = "Search tabs, controls and commands...",
		PlaceholderColor3 = self.Theme.Muted,
		TextColor3 = self.Theme.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 754,
		Parent = card,
	})
	addCorner(search, 9)
	addPadding(search, 0, 14, 0, 14)
	local searchStroke = addStroke(search, self.Theme.Border, 0.35, 1)
	self:_bindTheme(search, {
		BackgroundColor3 = "SurfaceAlt",
		TextColor3 = "Text",
		PlaceholderColor3 = "Muted",
	})
	self:_bindTheme(searchStroke, { Color = "Border" })
	local hint = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 67),
		Size = UDim2.new(1, -36, 0, 20),
		Font = Enum.Font.GothamMedium,
		Text = "QUICK SEARCH   -   Up/Down to navigate, Enter to open",
		TextSize = 9,
		TextColor3 = self.Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 754,
		Parent = card,
	})
	self:_bindTheme(hint, { TextColor3 = "Muted" })
	local results = create("ScrollingFrame", {
		Name = "Results",
		Position = UDim2.fromOffset(12, 92),
		Size = UDim2.new(1, -24, 1, -104),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.Theme.Border,
		ZIndex = 754,
		Parent = card,
	})
	local layout = create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = results,
	})
	self:_bindTheme(results, { ScrollBarImageColor3 = "Border" })
	maid:Give(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		results.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
	end))

	local displayed = {}
	local selectedIndex = 1
	local resultMaid = Maid.new()
	maid:Give(function()
		resultMaid:Clean()
	end)
	local function score(text, query, title)
		if query == "" then
			return 1
		end
		local startIndex = string.find(text, query, 1, true)
		if not startIndex then
			return nil
		end
		local lowerTitle = string.lower(title)
		if string.sub(lowerTitle, 1, #query) == query then
			return 1000 - #lowerTitle
		end
		return 500 - startIndex
	end
	local function refreshSelection()
		for index, data in ipairs(displayed) do
			local selected = index == selectedIndex
			self:_tween(data.Button, 0.08, { BackgroundTransparency = selected and 0 or 0.5 })
			data.Marker.Visible = selected
		end
		local current = displayed[selectedIndex]
		if current then
			local top = current.Button.AbsolutePosition.Y - results.AbsolutePosition.Y + results.CanvasPosition.Y
			if top < results.CanvasPosition.Y then
				results.CanvasPosition = Vector2.new(0, top)
			elseif top + current.Button.AbsoluteSize.Y > results.CanvasPosition.Y + results.AbsoluteSize.Y then
				results.CanvasPosition = Vector2.new(0, top + current.Button.AbsoluteSize.Y - results.AbsoluteSize.Y)
			end
		end
	end
	local function runItem(item)
		self:CloseCommandPalette()
		if item.Kind == "Command" then
			safeCall(item.Callback)
		elseif type(item.Action) == "function" then
			item.Action()
		end
	end
	local function build(query)
		resultMaid:Clean()
		resultMaid = Maid.new()
		for _, child in ipairs(results:GetChildren()) do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		table.clear(displayed)
		query = string.lower(string.gsub(query or "", "^%s+", ""))
		local candidates = {}
		for _, command in ipairs(self._commands) do
			if not command.Removed then
				local itemScore = score(command.SearchText, query, command.Title)
				if itemScore then
					table.insert(candidates, {
						Score = itemScore + 40,
						Kind = "Command",
						Title = command.Title,
						Description = command.Description,
						Callback = command.Callback,
					})
				end
			end
		end
		for _, item in ipairs(self._searchItems) do
			local targetDestroyed = item.Target and item.Target._destroyed
			if not item.Removed and not targetDestroyed then
				local itemScore = score(item.SearchText, query, item.Title)
				if itemScore then
					table.insert(candidates, {
						Score = itemScore,
						Kind = item.Kind,
						Title = item.Title,
						Description = item.Description,
						Action = item.Action,
					})
				end
			end
		end
		table.sort(candidates, function(first, second)
			if first.Score == second.Score then
				return first.Title < second.Title
			end
			return first.Score > second.Score
		end)
		for index, item in ipairs(candidates) do
			if index > 24 then
				break
			end
			local button = create("TextButton", {
				Name = "Result_" .. tostring(index),
				Size = UDim2.new(1, -2, 0, item.Description ~= "" and 52 or 44),
				BackgroundColor3 = self.Theme.SurfaceAlt,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				ZIndex = 755,
				Parent = results,
			})
			addCorner(button, 8)
			local marker = create("Frame", {
				Size = UDim2.fromOffset(3, 20),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				BackgroundColor3 = self.Theme.Accent,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 756,
				Parent = button,
			})
			addCorner(marker, 2)
			self:_bindTheme(marker, { BackgroundColor3 = "Accent" })
			local title = create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(13, item.Description ~= "" and 5 or 0),
				Size = UDim2.new(1, -94, 0, item.Description ~= "" and 22 or button.Size.Y.Offset),
				Font = Enum.Font.GothamMedium,
				Text = item.Title,
				TextSize = 11,
				TextColor3 = self.Theme.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 756,
				Parent = button,
			})
			self:_bindTheme(title, { TextColor3 = "Text" })
			if item.Description ~= "" then
				local description = create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(13, 27),
					Size = UDim2.new(1, -94, 0, 17),
					Font = Enum.Font.Gotham,
					Text = item.Description,
					TextSize = 9,
					TextColor3 = self.Theme.Muted,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 756,
					Parent = button,
				})
				self:_bindTheme(description, { TextColor3 = "Muted" })
			end
			local kind = create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(70, 22),
				BackgroundColor3 = self.Theme.SurfaceHover,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				Text = tostring(item.Kind),
				TextSize = 8,
				TextColor3 = self.Theme.Muted,
				ZIndex = 756,
				Parent = button,
			})
			addCorner(kind, 6)
			self:_bindTheme(kind, {
				BackgroundColor3 = "SurfaceHover",
				TextColor3 = "Muted",
			})
			table.insert(displayed, { Button = button, Marker = marker, Item = item })
			resultMaid:Give(button.Activated:Connect(function()
				runItem(item)
			end))
			resultMaid:Give(button.MouseEnter:Connect(function()
				selectedIndex = index
				refreshSelection()
			end))
		end
		selectedIndex = math.clamp(selectedIndex, 1, math.max(1, #displayed))
		refreshSelection()
	end

	local revision = 0
	maid:Give(search:GetPropertyChangedSignal("Text"):Connect(function()
		revision = revision + 1
		local currentRevision = revision
		task.delay(0.06, function()
			if currentRevision == revision and search.Parent then
				build(search.Text)
			end
		end)
	end))
	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			self:CloseCommandPalette()
		elseif input.KeyCode == Enum.KeyCode.Down and #displayed > 0 then
			selectedIndex = math.min(#displayed, selectedIndex + 1)
			refreshSelection()
		elseif input.KeyCode == Enum.KeyCode.Up and #displayed > 0 then
			selectedIndex = math.max(1, selectedIndex - 1)
			refreshSelection()
		elseif input.KeyCode == Enum.KeyCode.Return and displayed[selectedIndex] then
			runItem(displayed[selectedIndex].Item)
		end
	end))
	maid:Give(overlay.Activated:Connect(function()
		self:CloseCommandPalette()
	end))
	maid:Give(function()
		if self._commandMaid == maid then
			self._commandMaid = nil
		end
	end)
	build("")
	self:_tween(card, 0.16, { GroupTransparency = 0 })
	task.defer(function()
		if search.Parent then
			search:CaptureFocus()
		end
	end)
	return true
end

local function encodeConfigValue(value, seen)
	local valueType = typeof(value)
	if valueType == "Color3" then
		return {
			__velora = "Color3",
			R = value.R,
			G = value.G,
			B = value.B,
		}
	elseif valueType == "EnumItem" then
		return {
			__velora = "Enum",
			Enum = string.gsub(tostring(value.EnumType), "^Enum%.", ""),
			Name = value.Name,
		}
	elseif valueType == "Vector2" then
		return {
			__velora = "Vector2",
			X = value.X,
			Y = value.Y,
		}
	elseif valueType == "Vector3" then
		return {
			__velora = "Vector3",
			X = value.X,
			Y = value.Y,
			Z = value.Z,
		}
	elseif valueType == "CFrame" then
		return {
			__velora = "CFrame",
			Components = { value:GetComponents() },
		}
	elseif valueType == "UDim2" then
		return {
			__velora = "UDim2",
			XS = value.X.Scale,
			XO = value.X.Offset,
			YS = value.Y.Scale,
			YO = value.Y.Offset,
		}
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return value
	elseif valueType ~= "table" then
		if valueType == "string" or valueType == "boolean" or valueType == "nil" then
			return value
		end
		return nil
	end
	seen = seen or {}
	if seen[value] then
		error("Cannot encode a circular table")
	end
	seen[value] = true
	local result = {}
	for key, child in pairs(value) do
		local keyType = typeof(key)
		if keyType == "string" or keyType == "number" then
			local encoded = encodeConfigValue(child, seen)
			if encoded ~= nil then
				result[key] = encoded
			end
		end
	end
	seen[value] = nil
	return result
end

local function decodeConfigValue(value)
	if type(value) ~= "table" then
		return value
	end
	if value.__velora == "Color3" then
		return Color3.new(tonumber(value.R) or 0, tonumber(value.G) or 0, tonumber(value.B) or 0)
	elseif value.__velora == "Color4" then
		return {
			__color4 = true,
			Color = Color3.new(tonumber(value.R) or 0, tonumber(value.G) or 0, tonumber(value.B) or 0),
			Transparency = math.clamp(tonumber(value.A) or 0, 0, 1),
		}
	elseif value.__velora == "Enum" then
		local ok, enumItem = pcall(function()
			local enumType = Enum[value.Enum]
			return enumType and enumType[value.Name] or nil
		end)
		return ok and enumItem or nil
	elseif value.__velora == "Vector2" then
		return Vector2.new(tonumber(value.X) or 0, tonumber(value.Y) or 0)
	elseif value.__velora == "Vector3" then
		return Vector3.new(tonumber(value.X) or 0, tonumber(value.Y) or 0, tonumber(value.Z) or 0)
	elseif value.__velora == "CFrame" and type(value.Components) == "table" then
		local ok, cframe = pcall(CFrame.new, table.unpack(value.Components))
		return ok and cframe or nil
	elseif value.__velora == "UDim2" then
		return UDim2.new(
			tonumber(value.XS) or 0,
			tonumber(value.XO) or 0,
			tonumber(value.YS) or 0,
			tonumber(value.YO) or 0
		)
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = decodeConfigValue(child)
	end
	return result
end

local function sanitizeConfigName(value)
	local name = tostring(value or "default")
	name = string.gsub(name, "[^%w%._%-]+", "_")
	name = string.gsub(name, "^%.*", "")
	return name ~= "" and name or "default"
end

function Velora:ExportConfig(options)
	if type(options) == "boolean" then
		options = { AsTable = options }
	else
		options = options or {}
	end
	local data = {
		Schema = 1,
		Library = "Velora",
		Version = Velora.Version,
		Theme = self.ThemeName,
		Values = {},
	}
	if self.ThemeName == "Custom" or not Themes[self.ThemeName] then
		data.ThemeTokens = encodeConfigValue(self.Theme)
	end
	for flag, control in pairs(self.State._controls) do
		if not control._destroyed and not control.NoSave and control.Type ~= "Button" then
			local value = control:Get()
			if control.Type == "ColorPicker" and control.AllowTransparency then
				data.Values[flag] = {
					__velora = "Color4",
					R = value.R,
					G = value.G,
					B = value.B,
					A = control:GetTransparency(),
				}
			else
				local ok, encoded = pcall(encodeConfigValue, value)
				if ok then
					data.Values[flag] = encoded
				elseif self.Options.Debug then
					warn("[Velora] Skipped unserializable flag " .. tostring(flag) .. ": " .. tostring(encoded))
				end
			end
		end
	end
	if options.WindowState ~= false and self._windows[1] and self._windows[1].Root then
		local window = self._windows[1]
		data.Window = {
			Size = encodeConfigValue(UDim2.fromOffset(window._requestedSize.X, window._requestedSize.Y)),
			Position = encodeConfigValue(window.Root.Position),
			SelectedTab = window._selectedTab and window._selectedTab.Title or nil,
		}
	end
	if options.AsTable then
		return deepCopy(data)
	end
	local ok, result = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

function Velora:ImportConfig(payload, options)
	options = options or {}
	local data = payload
	if type(payload) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, payload)
		if not ok then
			return false, "Invalid JSON: " .. tostring(decoded)
		end
		data = decoded
	end
	if type(data) ~= "table" or type(data.Values) ~= "table" then
		return false, "Invalid Velora configuration"
	end
	local schema = data.Schema ~= nil and tonumber(data.Schema) or 1
	if not schema then
		return false, "Invalid configuration schema"
	end
	if schema > 1 then
		return false, "Configuration schema is newer than this library"
	end
	if options.ApplyTheme ~= false then
		local customTheme = decodeConfigValue(data.ThemeTokens)
		if type(customTheme) == "table" then
			self:SetTheme(customTheme, { Source = "config", Silent = true })
		elseif data.Theme and self._themes[data.Theme] then
			self:SetTheme(data.Theme, { Source = "config", Silent = true })
		end
	end
	local report = { Applied = 0, Pending = 0, Skipped = 0, Errors = {} }
	for flag, encoded in pairs(data.Values) do
		local control = self.State._controls[flag]
		if control and control.NoSave then
			report.Skipped = report.Skipped + 1
		else
			local value = decodeConfigValue(encoded)
			local isColor4 = type(value) == "table" and value.__color4 == true
			if not isColor4 then
				self._pendingTransparency[flag] = nil
			end
			local ok, changed
			if control and isColor4 and control.Type == "ColorPicker" then
				ok, changed = pcall(function()
					local didChange = control:Set(value.Color, { Source = "config", Silent = options.Silent == true })
					control:SetTransparency(value.Transparency, { Source = "config", Silent = options.Silent == true })
					return didChange
				end)
			elseif not control and isColor4 then
				ok, changed = pcall(self.State.Set, self.State, flag, value.Color, {
					Source = "config",
					Silent = options.Silent == true,
				})
				if ok then
					self._pendingTransparency[flag] = value.Transparency
				end
			elseif control and isColor4 then
				ok = false
				changed = "Color4 configuration requires a ColorPicker control"
			else
				local valid, validationError = true, nil
				if control and control._sanitize then
					valid, validationError = pcall(control._sanitize, value, control)
				end
				if valid then
					ok, changed = pcall(self.State.Set, self.State, flag, value, {
						Source = "config",
						Silent = options.Silent == true,
					})
				else
					ok = false
					changed = validationError
				end
			end
			if ok then
				if control then
					report.Applied = report.Applied + 1
				else
					report.Pending = report.Pending + 1
				end
			else
				report.Skipped = report.Skipped + 1
				table.insert(report.Errors, tostring(flag) .. ": " .. tostring(changed))
			end
		end
	end
	if options.WindowState ~= false and type(data.Window) == "table" and self._windows[1] then
		local window = self._windows[1]
		local size = decodeConfigValue(data.Window.Size)
		local position = decodeConfigValue(data.Window.Position)
		if typeof(size) == "UDim2" then
			window:SetSize(size, { Source = "config", Silent = true })
		end
		if typeof(position) == "UDim2" and window.Root then
			window.Root.Position = position
		end
		if data.Window.SelectedTab then
			window:SelectTab(data.Window.SelectedTab, { Source = "config", Silent = true })
		end
	end
	return true, report
end

function Velora:_configOptions()
	local config = self.Options.Config
	if type(config) ~= "table" then
		config = {}
	end
	return config
end

function Velora:_configKey(name)
	local config = self:_configOptions()
	local folder = sanitizeConfigName(config.Folder or "Velora")
	return folder .. "/" .. sanitizeConfigName(name or config.File or "default") .. ".json"
end

function Velora:_writeConfig(key, content)
	local config = self:_configOptions()
	if type(config.Storage) == "table" and type(config.Storage.Write) == "function" then
		local ok, result = pcall(config.Storage.Write, config.Storage, key, content)
		return ok and result ~= false, ok and "adapter" or tostring(result)
	end
	local writeFile = getEnvironmentFunction("writefile")
	local makeFolder = getEnvironmentFunction("makefolder")
	local isFolder = getEnvironmentFunction("isfolder")
	if writeFile then
		local folder = string.match(key, "^(.*)/[^/]+$")
		if folder and makeFolder then
			local checkOk, exists = true, false
			if isFolder then
				checkOk, exists = pcall(isFolder, folder)
			end
			if not checkOk or not exists then
				pcall(makeFolder, folder)
			end
		end
		local ok, message = pcall(writeFile, key, content)
		return ok, ok and "filesystem" or tostring(message)
	end
	self._memoryConfigs[key] = content
	return true, "memory"
end

function Velora:_readConfig(key)
	local config = self:_configOptions()
	if type(config.Storage) == "table" and type(config.Storage.Read) == "function" then
		local ok, content = pcall(config.Storage.Read, config.Storage, key)
		return ok and content or nil, ok and nil or tostring(content)
	end
	local readFile = getEnvironmentFunction("readfile")
	local isFile = getEnvironmentFunction("isfile")
	if readFile then
		if isFile then
			local ok, exists = pcall(isFile, key)
			if not ok or not exists then
				return nil, "Configuration does not exist"
			end
		end
		local ok, content = pcall(readFile, key)
		return ok and content or nil, ok and nil or tostring(content)
	end
	local content = self._memoryConfigs[key]
	return content, content and nil or "Configuration does not exist in memory"
end

function Velora:SaveConfig(name)
	local content, encodeError = self:ExportConfig()
	if not content then
		return false, encodeError
	end
	local key = self:_configKey(name)
	local ok, backend = self:_writeConfig(key, content)
	return ok, backend, key
end

function Velora:LoadConfig(name, options)
	local key = self:_configKey(name)
	local content, readError = self:_readConfig(key)
	if not content then
		return false, readError
	end
	return self:ImportConfig(content, options)
end

function Velora:DeleteConfig(name)
	local key = self:_configKey(name)
	local config = self:_configOptions()
	if type(config.Storage) == "table" and type(config.Storage.Delete) == "function" then
		local ok, result = pcall(config.Storage.Delete, config.Storage, key)
		return ok and result ~= false, ok and nil or tostring(result)
	end
	local deleteFile = getEnvironmentFunction("delfile")
	local isFile = getEnvironmentFunction("isfile")
	if deleteFile then
		if isFile then
			local ok, exists = pcall(isFile, key)
			if ok and not exists then
				return false, "Configuration does not exist"
			end
		end
		local ok, message = pcall(deleteFile, key)
		return ok, ok and nil or tostring(message)
	end
	if self._memoryConfigs[key] then
		self._memoryConfigs[key] = nil
		return true
	end
	return false, "Configuration does not exist in memory"
end

function Velora:ListConfigs()
	local config = self:_configOptions()
	if type(config.Storage) == "table" and type(config.Storage.List) == "function" then
		local ok, list = pcall(config.Storage.List, config.Storage, sanitizeConfigName(config.Folder or "Velora"))
		return ok and list or {}
	end
	local results = {}
	local seen = {}
	local listFiles = getEnvironmentFunction("listfiles")
	if listFiles then
		local folder = sanitizeConfigName(config.Folder or "Velora")
		local ok, files = pcall(listFiles, folder)
		if ok and type(files) == "table" then
			for _, path in ipairs(files) do
				local name = string.match(path, "([^/\\]+)%.json$")
				if name and not seen[name] then
					seen[name] = true
					table.insert(results, name)
				end
			end
		end
	end
	for key in pairs(self._memoryConfigs) do
		local name = string.match(key, "([^/]+)%.json$")
		if name and not seen[name] then
			seen[name] = true
			table.insert(results, name)
		end
	end
	table.sort(results)
	return results
end

function Velora:_scheduleAutoSave()
	local config = self:_configOptions()
	self._autosaveRevision = self._autosaveRevision + 1
	local revision = self._autosaveRevision
	task.delay(tonumber(config.Debounce) or 0.45, function()
		if not self._destroyed and revision == self._autosaveRevision then
			local ok, message = self:SaveConfig(config.File)
			if not ok and self.Options.Debug then
				warn("[Velora] AutoSave failed: " .. tostring(message))
			end
		end
	end)
end

function Tab:_getDefaultSection()
	if self._defaultSection and not self._defaultSection._destroyed then
		return self._defaultSection
	end
	self._defaultSection = self:AddSection({
		Title = self.Options.DefaultSectionTitle or "General",
		Description = self.Options.DefaultSectionDescription or "",
		Side = "Left",
		Collapsible = false,
	})
	return self._defaultSection
end

local function delegateTabMethod(sectionMethod)
	return function(tab, ...)
		local section = tab:_getDefaultSection()
		return section[sectionMethod](section, ...)
	end
end

local tabDelegates = {
	AddButton = "AddButton",
	CreateButton = "AddButton",
	Button = "AddButton",
	AddToggle = "AddToggle",
	CreateToggle = "AddToggle",
	Toggle = "AddToggle",
	AddCheckbox = "AddToggle",
	CreateCheckbox = "AddToggle",
	Checkbox = "AddToggle",
	AddSlider = "AddSlider",
	CreateSlider = "AddSlider",
	Slider = "AddSlider",
	AddInput = "AddInput",
	CreateInput = "AddInput",
	Input = "AddInput",
	AddTextbox = "AddInput",
	CreateTextbox = "AddInput",
	Textbox = "AddInput",
	AddDropdown = "AddDropdown",
	CreateDropdown = "AddDropdown",
	Dropdown = "AddDropdown",
	AddMultiDropdown = "AddMultiDropdown",
	CreateMultiDropdown = "AddMultiDropdown",
	MultiDropdown = "AddMultiDropdown",
	AddKeybind = "AddKeybind",
	CreateKeybind = "AddKeybind",
	Keybind = "AddKeybind",
	AddColorPicker = "AddColorPicker",
	CreateColorPicker = "AddColorPicker",
	AddColorpicker = "AddColorPicker",
	CreateColorpicker = "AddColorPicker",
	ColorPicker = "AddColorPicker",
	Colorpicker = "AddColorPicker",
	AddProgress = "AddProgress",
	CreateProgress = "AddProgress",
	AddProgressBar = "AddProgress",
	CreateProgressBar = "AddProgress",
	ProgressBar = "AddProgress",
	Progress = "AddProgress",
	AddSegmented = "AddSegmented",
	CreateSegmented = "AddSegmented",
	Segmented = "AddSegmented",
	AddRadio = "AddSegmented",
	CreateRadio = "AddSegmented",
	Radio = "AddSegmented",
	AddLabel = "AddLabel",
	CreateLabel = "AddLabel",
	Label = "AddLabel",
	AddParagraph = "AddParagraph",
	CreateParagraph = "AddParagraph",
	Paragraph = "AddParagraph",
	AddDivider = "AddDivider",
	CreateDivider = "AddDivider",
	Divider = "AddDivider",
	AddSpacer = "AddSpacer",
	CreateSpacer = "AddSpacer",
	Space = "AddSpacer",
	Spacer = "AddSpacer",
	AddCode = "AddCode",
	CreateCode = "AddCode",
	Code = "AddCode",
	AddImage = "AddImage",
	CreateImage = "AddImage",
	Image = "AddImage",
}

for methodName, sectionMethod in pairs(tabDelegates) do
	Tab[methodName] = delegateTabMethod(sectionMethod)
end

function Velora:GetThemes()
	return deepCopy(self._themes)
end

function Velora:GetCurrentTheme()
	return self.ThemeName
end

function Velora:GetWindowSize()
	local window = self._windows[1]
	return window and window.Root and window.Root.Size or nil
end

function Velora:GetFlags()
	return deepCopy(self.State._values)
end

function Window:ModifyTheme(theme)
	return self._ui:SetTheme(theme)
end

Window.SetTheme = Window.ModifyTheme
Window.CreateNotification = Window.Notify
Velora.New = Velora.new

return Velora
