-- Hidra Hub UI library. One window with grouped tabs, two-column sections and the
-- usual controls. Every control keeps its value in Library.flags[flag], which is what
-- profiles save and load. Returns the Library table.
local playersService = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local lightingService = game:GetService("Lighting")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")

local localPlayer = playersService.LocalPlayer
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

-- Colours and transparencies mirror the approved HTML mock (teste-hub-lib.html).
local Theme = {
	accent = rgb(229, 50, 62),
	deep = rgb(58, 3, 6), -- dark end of every accent gradient
	window = rgb(36, 31, 33),
	windowTransparency = 0.28,
	panelTransparency = 0.965, -- white over the window
	rowTransparency = 0.955,
	rowHoverTransparency = 0.915,
	field = rgb(0, 0, 0),
	fieldTransparency = 0.8,
	lineTransparency = 0.915, -- white strokes
	lineStrongTransparency = 0.83,
	popover = rgb(36, 38, 43),
	text = rgb(243, 242, 246),
	sub = rgb(170, 168, 180),
	dim = rgb(122, 120, 132),
	danger = rgb(240, 106, 128),
	knobOff = rgb(207, 205, 216),
	font = "rbxasset://fonts/families/Montserrat.json",
}

local WINDOW_SIZE = Vector2.new(800, 500) -- design size in pixels; UIScale shrinks it on small screens
local SIDEBAR_WIDTH = 188
local COMPACT_SIDEBAR_WIDTH = 58
local COMPACT_BELOW = 720 -- screen width in pixels under which tabs show icons only and sections stack
local CONTROL_WIDTH = 130 -- dropdowns and text inputs
local TOAST_WIDTH = 300
local MAX_TOASTS = 5 -- the oldest slides out when a sixth arrives
-- Minimized bar: top centre, below Roblox's topbar buttons row height.
local LAUNCHER_SHOWN = UDim2.new(0.5, 0, 0, 12)
local LAUNCHER_HIDDEN = UDim2.new(0.5, 0, 0, -70)
-- Stats strip: under the minimized bar (46 tall), or in its place while the window is open.
local STATS_MINIMIZED = UDim2.new(0.5, 0, 0, 64)
local STATS_OPEN = UDim2.new(0.5, 0, 0, 12)
local STATS_INTERVAL = 0.5 -- seconds between refreshes
-- Value colours for stats that grade themselves (FPS, ping).
local STAT_GOOD = rgb(105, 207, 161)
local STAT_FAIR = rgb(255, 196, 92)
local BLUR_SIZE = 12
local AUTOSAVE_DELAY = 1 -- seconds after the last change before the auto save writes
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ACCENT_PRESETS = { rgb(229, 50, 62), rgb(255, 122, 69), rgb(176, 130, 252), rgb(93, 193, 218), rgb(105, 207, 161) }
local KEY_NAMES = { RightShift = "RShift", LeftShift = "LShift", RightControl = "RCtrl", LeftControl = "LCtrl", RightAlt = "RAlt", LeftAlt = "LAlt" }

-- Lucide icons uploaded to Roblox (ids from the Fluent library's icon table).
-- Add an icon: add a row; tabs and buttons take the key or a raw rbxassetid.
local Icons = {
	["alert-triangle"] = "rbxassetid://10709753149",
	["arrow-up-right"] = "rbxassetid://10709768787",
	["bell"] = "rbxassetid://10709775704",
	["bug"] = "rbxassetid://10709782845",
	["check"] = "rbxassetid://10709790644",
	["chevron-down"] = "rbxassetid://10709790948",
	["crosshair"] = "rbxassetid://10709818534",
	["download"] = "rbxassetid://10723344270",
	["egg"] = "rbxassetid://10723345518",
	["eye"] = "rbxassetid://10723346959",
	["gauge"] = "rbxassetid://10723395708",
	["gem"] = "rbxassetid://10723396000",
	["home"] = "rbxassetid://10723407389",
	["info"] = "rbxassetid://10723415903",
	["keyboard"] = "rbxassetid://10723416765",
	["layers"] = "rbxassetid://10723424505",
	["minus"] = "rbxassetid://10734896206",
	["palette"] = "rbxassetid://10734910430",
	["power"] = "rbxassetid://10734930466",
	["refresh-cw"] = "rbxassetid://10734933222",
	["rocket"] = "rbxassetid://10734934585",
	["save"] = "rbxassetid://10734941499",
	["search"] = "rbxassetid://10734943674",
	["settings"] = "rbxassetid://10734950309",
	["sliders"] = "rbxassetid://10734963400",
	["sword"] = "rbxassetid://10734975486",
	["target"] = "rbxassetid://10734977012",
	["trash-2"] = "rbxassetid://10747362241",
	["user"] = "rbxassetid://10747373176",
	["wrench"] = "rbxassetid://10747383470",
	["x"] = "rbxassetid://10747384394",
}

local Library = {
	flags = {},
	elements = {},
	connections = {},
	themed = {}, -- { object, property } painted with the accent
	gradients = {}, -- long-lived accent gradients
	searchIndex = {},
	keybinds = {},
	accent = Theme.accent,
	folder = "HidraHub", -- executor workspace folder for profiles and the auto save; createWindow appends spec.config
	restored = false, -- Library.restore ran; auto saves only start after it
	saveQueued = false,
	capturing = false, -- a keybind is waiting for a key
	dragging = nil, -- function(point) while a slider or picker is held
	window = nil,
	icons = Icons,
}

-- Instance helpers. Layout comes from UIListLayout/UIFlexItem; offsets only for small parts.
local UI = {
	regular = Font.new(Theme.font, Enum.FontWeight.Medium),
	semibold = Font.new(Theme.font, Enum.FontWeight.SemiBold),
	bold = Font.new(Theme.font, Enum.FontWeight.Bold),
}

function UI.new(class, properties, parent)
	local object = Instance.new(class)
	for key, value in properties do
		object[key] = value
	end
	object.Parent = parent
	return object
end

function UI.frame(parent, properties)
	properties.BackgroundTransparency = properties.BackgroundTransparency or 1
	properties.BorderSizePixel = 0
	return UI.new("Frame", properties, parent)
end

function UI.button(parent, properties)
	properties.Text = ""
	properties.AutoButtonColor = false
	properties.BorderSizePixel = 0
	properties.BackgroundColor3 = properties.BackgroundColor3 or WHITE
	properties.BackgroundTransparency = properties.BackgroundTransparency or 1
	return UI.new("TextButton", properties, parent)
end

function UI.text(parent, text, size, color, font, properties)
	properties = properties or {}
	properties.BackgroundTransparency = 1
	properties.Text = text
	properties.TextSize = size
	properties.TextColor3 = color
	properties.FontFace = font or UI.regular
	properties.TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left
	return UI.new("TextLabel", properties, parent)
end

function UI.icon(parent, name, size, color, properties)
	properties = properties or {}
	properties.BackgroundTransparency = 1
	properties.Image = Icons[name] or name
	properties.ImageColor3 = color
	properties.Size = UDim2.fromOffset(size, size)
	return UI.new("ImageLabel", properties, parent)
end

-- radius nil means fully round.
function UI.corner(object, radius)
	return UI.new("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0) }, object)
end

function UI.stroke(object, transparency, color)
	return UI.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or WHITE,
		Transparency = transparency or Theme.lineTransparency,
	}, object)
end

function UI.padding(object, left, right, top, bottom)
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right or left),
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
	}, object)
end

function UI.list(object, direction, gap, vertical, horizontal)
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
	}, object)
end

function UI.fill(object)
	return UI.new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }, object)
end

function UI.tween(object, properties, info)
	local tween = tweenService:Create(object, info or FAST, properties)
	tween:Play()
	return tween
end

function UI.hover(button, rest, over)
	button.MouseEnter:Connect(function()
		UI.tween(button, { BackgroundTransparency = over })
	end)
	button.MouseLeave:Connect(function()
		UI.tween(button, { BackgroundTransparency = rest })
	end)
end

function UI.accentSequence()
	return ColorSequence.new(Library.accent:Lerp(Theme.deep, 0.45), Library.accent)
end

-- Paints a property with the accent and keeps it in sync with Library.setAccent.
function UI.accent(object, property)
	object[property] = Library.accent
	table.insert(Library.themed, { object = object, property = property })
	return object
end

-- Accent gradient over a white background. Short-lived objects (toasts, popovers)
-- pass keep = false so they don't pile up in Library.gradients.
function UI.gradient(object, keep)
	local gradient = UI.new("UIGradient", { Color = UI.accentSequence() }, object)
	if keep ~= false then
		table.insert(Library.gradients, gradient)
	end
	return gradient
end

-- Dark field look shared by inputs, dropdowns and keybinds. Returns the stroke.
function UI.field(object)
	object.BackgroundColor3 = Theme.field
	object.BackgroundTransparency = Theme.fieldTransparency
	object.BorderSizePixel = 0
	UI.corner(object, 7)
	return UI.stroke(object)
end

function UI.textbox(parent, properties)
	properties.BackgroundTransparency = Theme.fieldTransparency
	properties.Text = properties.Text or ""
	properties.ClearTextOnFocus = false
	properties.FontFace = UI.regular
	properties.TextSize = 12
	properties.TextColor3 = Theme.text
	properties.PlaceholderColor3 = Theme.dim
	properties.TextXAlignment = Enum.TextXAlignment.Left
	local box = UI.new("TextBox", properties, parent)
	local stroke = UI.field(box)
	UI.padding(box, 9)
	box.Focused:Connect(function()
		stroke.Color = Library.accent
		stroke.Transparency = 0.35
	end)
	box.FocusLost:Connect(function()
		stroke.Color = WHITE
		stroke.Transparency = Theme.lineTransparency
	end)
	return box
end

-- Input point in AbsolutePosition space. Both exclude the topbar inset even under
-- IgnoreGuiInset (measured in Studio 2026-11-18: full-screen frame AbsolutePosition.Y = -58).
function UI.pointer(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

function UI.inside(object, point)
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= position.X and point.X <= position.X + size.X and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

-- Starts a drag on press; onMove gets the pointer until the button is released.
function UI.draggable(hitbox, onMove)
	hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Library.dragging = onMove
			onMove(UI.pointer(input))
		end
	end)
end

function UI.decimals(step)
	local fraction = string.match(tostring(step), "%.(%d+)")
	return if fraction then #fraction else 0
end

function Library.connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Library.connections, connection)
	return connection
end

function Library.fire(callback, ...)
	if callback then
		task.spawn(callback, ...)
	end
end

function Library.setAccent(color)
	Library.accent = color
	local sequence = UI.accentSequence()
	for _, entry in Library.themed do
		entry.object[entry.property] = color
	end
	for _, gradient in Library.gradients do
		gradient.Color = sequence
	end
	local window = Library.window
	if window and window.current then
		window.current.glyph.ImageColor3 = color
	end
end

-- Stores the element and applies its default without firing the callback. Every later set
-- (user, profile, code) goes through Library.changed, which feeds the auto save.
function Library.register(flag, element, default)
	Library.elements[flag] = element
	element.get = function()
		return Library.flags[flag]
	end
	element.set(default, true)
	local set = element.set
	element.set = function(value, silent)
		set(value, silent)
		Library.changed(flag)
	end
	return element
end


-- Flags as JSON-safe data. Profile bookkeeping flags (__profile*) are left out.
function Library.snapshot()
	local data = {}
	for flag, value in Library.flags do
		if string.sub(flag, 1, 9) == "__profile" then
			continue
		end
		data[flag] = if typeof(value) == "Color3" then { color = value:ToHex() } else value
	end
	return data
end

function Library.apply(data)
	for flag, value in data do
		local element = Library.elements[flag]
		if not element then
			continue
		end
		if type(value) == "table" and value.color then
			value = Color3.fromHex(value.color)
		end
		element.set(value)
	end
end

-- Profiles live in <workspace>/HidraHub/profiles when the executor has file functions,
-- otherwise only in memory for this session (Studio).
local Storage = {
	memory = {},
	memoryAuto = nil,
	files = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
		and typeof(isfolder) == "function" and typeof(makefolder) == "function" and typeof(listfiles) == "function",
}

-- Creates <Library.folder>/profiles, one path segment at a time (Library.folder can be nested).
function Storage.folder()
	local path = ""
	for segment in string.gmatch(`{Library.folder}/profiles`, "[^/]+") do
		path = if path == "" then segment else `{path}/{segment}`
		if not isfolder(path) then
			makefolder(path)
		end
	end
	return path
end

-- The last state, written by the auto save; nil when missing, unreadable or without files.
function Storage.readAutosave()
	if not Storage.files then
		return nil
	end
	local path = `{Library.folder}/autosave.json`
	if not isfile(path) then
		return nil
	end
	local ok, data = pcall(httpService.JSONDecode, httpService, readfile(path))
	if not ok then
		warn("[HidraLib] unreadable autosave", data)
		return nil
	end
	return data
end

function Storage.writeAutosave(data)
	if Storage.files then
		Storage.folder()
		writefile(`{Library.folder}/autosave.json`, httpService:JSONEncode(data))
	end
end

function Storage.list()
	local names = {}
	if Storage.files then
		for _, path in listfiles(Storage.folder()) do
			local name = string.match(path, "([^/\\]+)%.json$")
			if name then
				table.insert(names, name)
			end
		end
	else
		for name in Storage.memory do
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- Returns the saved flags, or nil when missing or unreadable.
function Storage.read(name)
	if not Storage.files then
		return Storage.memory[name]
	end
	local path = `{Storage.folder()}/{name}.json`
	if not isfile(path) then
		return nil
	end
	local ok, data = pcall(httpService.JSONDecode, httpService, readfile(path))
	if not ok then
		warn("[HidraLib] unreadable profile", name, data)
		return nil
	end
	return data
end

function Storage.write(name, data)
	if Storage.files then
		writefile(`{Storage.folder()}/{name}.json`, httpService:JSONEncode(data))
	else
		Storage.memory[name] = data
	end
end

function Storage.remove(name)
	if not Storage.files then
		Storage.memory[name] = nil
	elseif typeof(delfile) == "function" then
		delfile(`{Storage.folder()}/{name}.json`)
	end
end

function Storage.getAuto()
	if not Storage.files then
		return Storage.memoryAuto
	end
	local path = `{Library.folder}/autoload.txt`
	local name = if isfile(path) then readfile(path) else ""
	return if name ~= "" then name else nil
end

function Storage.setAuto(name)
	if Storage.files then
		Storage.folder()
		writefile(`{Library.folder}/autoload.txt`, name or "")
	else
		Storage.memoryAuto = name
	end
end

-- Schedules an auto save. Nothing is written before Library.restore ran, so building the
-- window with its defaults never overwrites the saved state.
function Library.changed(flag)
	if not Library.restored or Library.saveQueued then
		return
	end
	-- Turning auto save off is itself saved, so the next session starts with it off.
	if Library.flags.__autosave == false and flag ~= "__autosave" then
		return
	end
	Library.saveQueued = true
	task.delay(AUTOSAVE_DELAY, function()
		Library.saveQueued = false
		if not Library.unloaded then
			Storage.writeAutosave(Library.snapshot())
		end
	end)
end

-- Call once, after every tab (Settings included) is built: applies the "Load on start"
-- profile, or else the auto save, firing each callback; then starts auto saving.
function Library.restore()
	local startup = Storage.getAuto()
	local profile = startup and Storage.read(startup)
	if profile then
		Library.elements.__profile.set(startup, true)
		Library.elements.__profileAuto.set(true, true)
		Library.apply(profile)
	else
		local saved = Storage.readAutosave()
		if saved and saved.__autosave ~= false then
			Library.apply(saved)
		elseif saved then
			Library.elements.__autosave.set(false, true)
		end
	end
	Library.restored = true
end

local Section = {}
Section.__index = Section

local Tab = {}
Tab.__index = Tab

local Window = {}
Window.__index = Window

-- Row shared by every control: title, optional description, control on the right.
-- Returns row, title label, stroke, description label (or nil).
function Section:row(spec, hoverable)
	self.count += 1
	self.tab.weights[self.column] += if spec.description then 1.4 else 1
	local row = UI.button(self.frame, {
		Name = spec.title,
		Size = UDim2.new(1, 0, 0, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = Theme.rowTransparency,
		LayoutOrder = self.count,
	})
	UI.corner(row, 7)
	local stroke = UI.stroke(row, 0.945)
	UI.padding(row, 11, 11, 7, 7)
	UI.list(row, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)
	local label = UI.frame(row, { Name = "Label", Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	UI.fill(label)
	UI.list(label, Enum.FillDirection.Vertical, 2)
	local title = UI.text(label, spec.title, 13, Theme.text, UI.semibold, {
		Size = UDim2.new(1, 0, 0, 15),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 1,
	})
	local description
	if spec.description then
		description = UI.text(label, spec.description, 11, Theme.sub, UI.regular, {
			Size = UDim2.new(1, 0, 0, 13),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end
	if hoverable then
		UI.hover(row, Theme.rowTransparency, Theme.rowHoverTransparency)
	end
	table.insert(Library.searchIndex, { title = spec.title, tab = self.tab, section = self.title, row = row, stroke = stroke })
	return row, title, stroke, description
end

-- spec: title, description, default, callback(value)
function Section:addToggle(flag, spec)
	local row = self:row(spec, true)
	local track = UI.frame(row, { Name = "Switch", Size = UDim2.fromOffset(38, 20), BackgroundColor3 = WHITE, BackgroundTransparency = 0.89, LayoutOrder = 2 })
	UI.corner(track)
	local fill = UI.frame(track, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
	UI.corner(fill)
	UI.gradient(fill)
	local knob = UI.frame(track, { Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = Theme.knobOff, BackgroundTransparency = 0, ZIndex = 2 })
	UI.corner(knob)
	local element = {}
	function element.set(value, silent)
		value = value == true
		Library.flags[flag] = value
		UI.tween(fill, { BackgroundTransparency = if value then 0 else 1 })
		UI.tween(knob, { Position = UDim2.fromOffset(if value then 21 else 3, 3), BackgroundColor3 = if value then WHITE else Theme.knobOff })
		if not silent then
			Library.fire(spec.callback, value)
		end
	end
	row.Activated:Connect(function()
		element.set(not Library.flags[flag])
	end)
	return Library.register(flag, element, spec.default)
end

-- spec: title, description, min, max, step, default, suffix, callback(value)
function Section:addSlider(flag, spec)
	local row = self:row(spec)
	local step = spec.step or 1
	local decimals = UI.decimals(step)
	local holder = UI.frame(row, { Name = "Slider", Size = UDim2.fromOffset(140, 26), LayoutOrder = 2 })
	UI.list(holder, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	local track = UI.button(holder, { Name = "Track", Size = UDim2.new(1, -60, 0, 18), LayoutOrder = 1 })
	local bar = UI.frame(track, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
	})
	UI.corner(bar)
	local fill = UI.frame(bar, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	UI.corner(fill)
	UI.gradient(fill)
	local knob = UI.frame(track, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(13, 13),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		ZIndex = 2,
	})
	UI.corner(knob)
	UI.accent(UI.new("UIStroke", { Thickness = 3, Transparency = 0.6 }, knob), "Color")
	local box = UI.textbox(holder, { Name = "Value", Size = UDim2.fromOffset(52, 26), LayoutOrder = 2 })
	box.TextXAlignment = Enum.TextXAlignment.Center
	box:FindFirstChildOfClass("UIPadding"):Destroy()
	local element = {}
	function element.set(value, silent)
		value = tonumber(value) or spec.min
		value = math.clamp(spec.min + math.round((value - spec.min) / step) * step, spec.min, spec.max)
		local text = string.format(`%.{decimals}f`, value)
		value = tonumber(text)
		local alpha = (value - spec.min) / (spec.max - spec.min)
		Library.flags[flag] = value
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		box.Text = text .. (spec.suffix or "")
		if not silent then
			Library.fire(spec.callback, value)
		end
	end
	UI.draggable(track, function(point)
		local alpha = math.clamp((point.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local value = spec.min + alpha * (spec.max - spec.min)
		if math.abs(value - Library.flags[flag]) >= step / 2 then
			element.set(value)
		end
	end)
	box.Focused:Connect(function()
		box.Text = tostring(Library.flags[flag])
	end)
	box.FocusLost:Connect(function()
		element.set(string.match(box.Text, "[-%d%.]+"))
	end)
	return Library.register(flag, element, spec.default)
end

-- spec: title, description, values (array or function returning one), default, multi, callback(value),
-- icons (optional: value -> image asset shown next to that option)
function Section:addDropdown(flag, spec)
	local row = self:row(spec)
	local button = UI.button(row, { Name = "Dropdown", Size = UDim2.fromOffset(CONTROL_WIDTH, 28), LayoutOrder = 2 })
	UI.field(button)
	UI.padding(button, 10, 8)
	local caption = UI.text(button, "", 12, Theme.text, UI.regular, { Size = UDim2.new(1, -20, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.icon(button, "chevron-down", 14, Theme.sub, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5) })
	local element = {}
	function element.set(value, silent)
		if spec.multi then
			value = table.clone(value or {})
			caption.Text = if #value == 0 then "None" elseif #value == 1 then tostring(value[1]) else `{#value} selected`
		else
			caption.Text = if value == nil then "None" else tostring(value)
		end
		Library.flags[flag] = value
		if not silent then
			Library.fire(spec.callback, value)
		end
	end
	button.Activated:Connect(function()
		self.tab.window:togglePopover(button, CONTROL_WIDTH, function(popover)
			self.tab.window:buildOptions(popover, flag, spec, element)
		end)
	end)
	return Library.register(flag, element, spec.default)
end

-- spec: title, description, icon, variant ("primary" | "danger"), callback()
function Section:addButton(spec)
	local primary = spec.variant == "primary"
	local row, title, stroke = self:row(spec, not primary)
	local glyph = UI.icon(row, spec.icon or "arrow-up-right", 16, Theme.dim, { LayoutOrder = 2 })
	if primary then
		row.BackgroundColor3 = rgb(225, 225, 225)
		row.BackgroundTransparency = 0
		UI.gradient(row)
		stroke.Transparency = 0.7
		title.TextColor3 = WHITE
		glyph.ImageColor3 = WHITE
		row.MouseEnter:Connect(function()
			UI.tween(row, { BackgroundColor3 = WHITE })
		end)
		row.MouseLeave:Connect(function()
			UI.tween(row, { BackgroundColor3 = rgb(225, 225, 225) })
		end)
	elseif spec.variant == "danger" then
		title.TextColor3 = Theme.danger
		glyph.ImageColor3 = Theme.danger
	end
	row.Activated:Connect(function()
		Library.fire(spec.callback)
	end)
	return {
		row = row,
		setTitle = function(text)
			title.Text = text
		end,
	}
end

-- spec: title, description, placeholder, default, callback(text)
function Section:addInput(flag, spec)
	local row = self:row(spec)
	local box = UI.textbox(row, {
		Name = "Input",
		Size = UDim2.fromOffset(CONTROL_WIDTH, 28),
		PlaceholderText = spec.placeholder or "",
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
	})
	local element = {}
	function element.set(value, silent)
		value = tostring(value or "")
		Library.flags[flag] = value
		box.Text = value
		if not silent then
			Library.fire(spec.callback, value)
		end
	end
	box.FocusLost:Connect(function()
		element.set(box.Text)
	end)
	return Library.register(flag, element, spec.default)
end

-- spec: title, description, default (KeyCode name), callback(keyName), pressed()
-- The value is a KeyCode name, or false when cleared with Backspace.
function Section:addKeybind(flag, spec)
	local row = self:row(spec)
	local button = UI.button(row, { Name = "Keybind", Size = UDim2.fromOffset(58, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	local stroke = UI.field(button)
	UI.padding(button, 10)
	UI.list(button, Enum.FillDirection.Horizontal, 0, Enum.VerticalAlignment.Center, Enum.HorizontalAlignment.Center)
	local caption = UI.text(button, "", 11, Theme.sub, UI.semibold, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X })
	local element = {}
	local function paint(listening)
		local key = Library.flags[flag]
		caption.Text = if listening then "Press a key" elseif key then KEY_NAMES[key] or key else "None"
		caption.TextColor3 = if listening then Library.accent else Theme.sub
		stroke.Color = if listening then Library.accent else WHITE
		stroke.Transparency = if listening then 0.3 else Theme.lineTransparency
	end
	function element.set(value, silent)
		Library.flags[flag] = value or false
		paint(false)
		if not silent then
			Library.fire(spec.callback, value or false)
		end
	end
	button.Activated:Connect(function()
		if Library.capturing then
			return
		end
		Library.capturing = true
		paint(true)
		local connection
		connection = userInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			connection:Disconnect()
			-- Cleared after every InputBegan listener ran, so this key doesn't also trigger the menu.
			task.defer(function()
				Library.capturing = false
			end)
			if input.KeyCode == Enum.KeyCode.Escape then
				paint(false)
			elseif input.KeyCode == Enum.KeyCode.Backspace then
				element.set(false)
			else
				element.set(input.KeyCode.Name)
			end
		end)
	end)
	table.insert(Library.keybinds, { flag = flag, pressed = spec.pressed })
	return Library.register(flag, element, spec.default)
end

-- spec: title, description, default (Color3), callback(color)
function Section:addColor(flag, spec)
	local row = self:row(spec)
	local button = UI.button(row, { Name = "Color", Size = UDim2.fromOffset(40, 28), LayoutOrder = 2 })
	UI.field(button)
	local swatch = UI.frame(button, { Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 0 })
	UI.corner(swatch, 4)
	local element = {}
	function element.set(color, silent)
		Library.flags[flag] = color
		swatch.BackgroundColor3 = color
		if not silent then
			Library.fire(spec.callback, color)
		end
	end
	button.Activated:Connect(function()
		self.tab.window:togglePopover(button, 220, function(popover)
			self.tab.window:buildPicker(popover, flag, element)
		end)
	end)
	return Library.register(flag, element, spec.default)
end

-- spec: title, content
function Section:addParagraph(spec)
	local row, title, stroke, content = self:row({ title = spec.title, description = spec.content })
	row.BackgroundTransparency = 1
	stroke.Transparency = 0.88
	return {
		row = row,
		setTitle = function(text)
			title.Text = text
		end,
		setContent = function(text)
			content.Text = text
		end,
	}
end

-- A row whose control is built by the caller: build(row) parents it with LayoutOrder 2.
function Section:addCustom(spec, build)
	local row = self:row(spec)
	build(row)
	return row
end

-- Sections go to the shorter column; in compact mode they stack in creation order.
function Tab:addSection(title)
	local column = if self.weights[1] <= self.weights[2] then 1 else 2
	self.weights[column] += 1.2
	local section = setmetatable({ tab = self, title = title, column = column, count = 0, order = #self.sections + 1 }, Section)
	section.frame = UI.frame(self.columns[column], {
		Name = title,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = Theme.panelTransparency,
		LayoutOrder = section.order,
	})
	UI.corner(section.frame, 9)
	UI.stroke(section.frame)
	UI.padding(section.frame, 6, 6, 6, 6)
	UI.list(section.frame, Enum.FillDirection.Vertical, 5)
	local header = UI.text(section.frame, title, 13, Theme.text, UI.bold, { Name = "Header", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0 })
	UI.padding(header, 7, 7, 0, 2)
	table.insert(self.sections, section)
	if self.window.compact then
		section.frame.Parent = self.columns[1]
	end
	return section
end

function Tab:arrange(compact)
	self.columns[2].Visible = not compact
	self.columns[1].Size = if compact then UDim2.fromScale(1, 0) else UDim2.new(0.5, -4, 0, 0)
	for _, section in self.sections do
		section.frame.Parent = if compact then self.columns[1] else self.columns[section.column]
	end
end

-- spec: title, subtitle, logo (image content id, optional), menuKey (KeyCode name),
-- config (folder name under HidraHub/ for this hub's profiles and auto save, optional)
function Library.createWindow(spec)
	local guiParent = if typeof(gethui) == "function" then gethui() else localPlayer:WaitForChild("PlayerGui")
	local self = setmetatable({ tabs = {}, groupHeaders = {}, visible = true, order = 0, toastCount = 0, toastList = {} }, Window)
	Library.window = self
	Library.flags.__menuKey = spec.menuKey or "RightShift"
	if spec.config then
		Library.folder = `HidraHub/{spec.config}`
	end

	self.gui = UI.new("ScreenGui", {
		Name = "HidraHub",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
	}, guiParent)
	self.root = UI.frame(self.gui, {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
		BackgroundColor3 = Theme.window,
		BackgroundTransparency = Theme.windowTransparency,
		Active = true,
	})
	UI.corner(self.root, 12)
	UI.stroke(self.root, Theme.lineStrongTransparency)
	self.scale = UI.new("UIScale", {}, self.root)

	self:buildTitlebar(spec)
	self:buildSidebar()
	self.pages = UI.frame(self.root, { Name = "Pages" })

	self.layer = UI.frame(self.gui, { Name = "Popovers", Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	self.layerScale = UI.new("UIScale", {}, self.layer)
	self.toasts = UI.frame(self.gui, {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(TOAST_WIDTH, 600),
		ZIndex = 60,
	})
	UI.list(self.toasts, Enum.FillDirection.Vertical, 6, Enum.VerticalAlignment.Bottom)
	self.toastScale = UI.new("UIScale", {}, self.toasts)

	self:buildLauncher(spec)
	self:buildStats()

	Library.connect(userInputService.InputBegan, function(input, processed)
		self:onInput(input, processed)
	end)
	Library.connect(userInputService.InputChanged, function(input)
		if Library.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			Library.dragging(UI.pointer(input))
		end
	end)
	Library.connect(userInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Library.dragging = nil
		end
	end)
	Library.connect(self.gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:fit()
	end)
	self:fit()
	return self
end

function Window:logo(parent, image, size)
	if image then
		return UI.new("ImageLabel", { Name = "Logo", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(size, size) }, parent)
	end
	return UI.accent(UI.icon(parent, "layers", size - 6, WHITE, { Name = "Logo" }), "ImageColor3")
end

-- Bar shown at the top centre while the window is minimized. Clicking anywhere on it reopens.
function Window:buildLauncher(spec)
	local launcher = UI.button(self.gui, {
		Name = "Launcher",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = LAUNCHER_HIDDEN,
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.window,
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 40,
	})
	self.launcher = launcher
	UI.corner(launcher, 12)
	local stroke = UI.stroke(launcher, Theme.lineStrongTransparency)

	-- Accent glow along the bottom edge, fading out at both ends.
	local glow = UI.frame(launcher, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.7, 0, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	UI.corner(glow)
	UI.gradient(glow).Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })

	local content = UI.frame(launcher, { Name = "Content", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X })
	UI.padding(content, 8, 8)
	UI.list(content, Enum.FillDirection.Horizontal, 10, Enum.VerticalAlignment.Center)

	local logo = self:logo(content, spec.logo, 28)
	logo.LayoutOrder = 1
	local text = UI.frame(content, { Name = "Text", Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	UI.list(text, Enum.FillDirection.Vertical, 1, Enum.VerticalAlignment.Center)
	UI.text(text, spec.title, 13, Theme.text, UI.bold, { Size = UDim2.fromOffset(0, 15), AutomaticSize = Enum.AutomaticSize.X })
	UI.text(text, spec.subtitle or "Minimized", 10, Theme.sub, UI.regular, { Size = UDim2.fromOffset(0, 12), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })

	UI.frame(content, { Name = "Divider", Size = UDim2.fromOffset(1, 22), BackgroundColor3 = WHITE, BackgroundTransparency = Theme.lineTransparency, LayoutOrder = 3 })

	local keyChip = UI.frame(content, { Name = "Key", Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 4 })
	UI.field(keyChip)
	UI.padding(keyChip, 8)
	UI.list(keyChip, Enum.FillDirection.Horizontal, 5, Enum.VerticalAlignment.Center)
	UI.icon(keyChip, "keyboard", 12, Theme.dim, { LayoutOrder = 1 })
	self.launcherKey = UI.text(keyChip, "", 11, Theme.sub, UI.semibold, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })

	local open = UI.frame(content, { Name = "Open", Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, BackgroundTransparency = 0, LayoutOrder = 5 })
	UI.corner(open, 8)
	UI.gradient(open)
	UI.padding(open, 12, 12)
	UI.list(open, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Center)
	UI.text(open, "Open", 12, WHITE, UI.semibold, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	UI.icon(open, "chevron-down", 14, WHITE, { LayoutOrder = 2 })

	launcher.MouseEnter:Connect(function()
		UI.tween(stroke, { Transparency = 0.6 })
		UI.tween(launcher, { BackgroundTransparency = 0 })
	end)
	launcher.MouseLeave:Connect(function()
		UI.tween(stroke, { Transparency = Theme.lineStrongTransparency })
		UI.tween(launcher, { BackgroundTransparency = 0.08 })
	end)
	launcher.Activated:Connect(function()
		self:setVisible(true)
	end)
end

-- Always-on strip of live values at the top centre. Library.addStat adds more from a hub.
function Window:buildStats()
	local strip = UI.frame(self.gui, {
		Name = "Stats",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = STATS_OPEN,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.window,
		BackgroundTransparency = 0.08,
		ZIndex = 40,
	})
	self.stats = strip
	self.statRows = {}
	UI.corner(strip, 8)
	UI.stroke(strip, Theme.lineStrongTransparency)
	UI.padding(strip, 10)
	UI.list(strip, Enum.FillDirection.Horizontal, 12, Enum.VerticalAlignment.Center)

	-- Frames counted between refreshes.
	local frames = 0
	Library.connect(runService.RenderStepped, function()
		frames += 1
	end)
	local fps = 0
	local startedAt = os.clock()
	Library.addStat("FPS", function()
		return tostring(fps), if fps >= 50 then STAT_GOOD elseif fps >= 30 then STAT_FAIR else Theme.danger
	end)
	Library.addStat("Ping", function()
		local ping = math.round(localPlayer:GetNetworkPing() * 1000)
		return `{ping}ms`, if ping <= 100 then STAT_GOOD elseif ping <= 200 then STAT_FAIR else Theme.danger
	end)
	Library.addStat("Players", function()
		return `{#playersService:GetPlayers()}/{playersService.MaxPlayers}`
	end)
	Library.addStat("Time", function()
		local seconds = math.floor(os.clock() - startedAt)
		return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
	end)

	task.spawn(function()
		local last = os.clock()
		while not Library.unloaded do
			task.wait(STATS_INTERVAL)
			local now = os.clock()
			fps = math.round(frames / (now - last))
			frames, last = 0, now
			self:refreshStats()
		end
	end)
end

-- name: the label; read() returns the value text and optionally its colour. Runs every STATS_INTERVAL.
function Library.addStat(name, read)
	local window = Library.window
	local strip = window and window.stats
	if not strip then
		return
	end
	local row = UI.frame(strip, { Name = name, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = #window.statRows + 1 })
	UI.list(row, Enum.FillDirection.Horizontal, 5, Enum.VerticalAlignment.Center)
	UI.text(row, string.upper(name), 10, Theme.dim, UI.semibold, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 })
	local value = UI.text(row, "", 11, Theme.text, UI.bold, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	table.insert(window.statRows, { read = read, value = value })
	window:refreshStats()
end

function Window:refreshStats()
	if not self.stats.Visible then
		return
	end
	for _, stat in self.statRows do
		local ok, text, color = pcall(stat.read)
		stat.value.Text = if ok then tostring(text) else "-"
		stat.value.TextColor3 = if ok and color then color else Theme.text
	end
end

function Window:iconButton(parent, name, order, callback, danger)
	local button = UI.button(parent, { Name = name, Size = UDim2.fromOffset(30, 30), LayoutOrder = order })
	UI.corner(button, 7)
	local glyph = UI.icon(button, name, 16, Theme.sub, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = if danger then Theme.danger else WHITE
		UI.tween(button, { BackgroundTransparency = if danger then 0.85 else Theme.rowHoverTransparency })
		glyph.ImageColor3 = if danger then Theme.danger else Theme.text
	end)
	button.MouseLeave:Connect(function()
		UI.tween(button, { BackgroundTransparency = 1 })
		glyph.ImageColor3 = Theme.sub
	end)
	button.Activated:Connect(callback)
	return button
end

function Window:buildTitlebar(spec)
	local bar = UI.frame(self.root, { Name = "Titlebar", Size = UDim2.new(1, 0, 0, 48), Active = true })
	UI.padding(bar, 16, 8)
	UI.list(bar, Enum.FillDirection.Horizontal, 10, Enum.VerticalAlignment.Center)

	self.brand = UI.frame(bar, { Name = "Brand", Size = UDim2.fromOffset(178, 36), LayoutOrder = 1 })
	UI.list(self.brand, Enum.FillDirection.Horizontal, 10, Enum.VerticalAlignment.Center)
	self:logo(self.brand, spec.logo, 30)
	self.brandText = UI.frame(self.brand, { Name = "Text", Size = UDim2.fromOffset(136, 32), LayoutOrder = 2 })
	UI.list(self.brandText, Enum.FillDirection.Vertical, 1, Enum.VerticalAlignment.Center)
	UI.text(self.brandText, spec.title, 14, Theme.text, UI.bold, { Size = UDim2.new(1, 0, 0, 17), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.text(self.brandText, spec.subtitle or "", 11, Theme.sub, UI.regular, { Size = UDim2.new(1, 0, 0, 13), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })

	self.pageTitle = UI.text(bar, "", 14, Theme.text, UI.bold, { Name = "PageTitle", Size = UDim2.fromOffset(0, 20), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
	UI.fill(self.pageTitle)

	self.searchFrame = UI.frame(bar, { Name = "Search", Size = UDim2.fromOffset(230, 30), LayoutOrder = 3 })
	UI.field(self.searchFrame)
	UI.padding(self.searchFrame, 10)
	UI.list(self.searchFrame, Enum.FillDirection.Horizontal, 7, Enum.VerticalAlignment.Center)
	UI.icon(self.searchFrame, "search", 14, Theme.dim, { LayoutOrder = 1 })
	self.searchBox = UI.new("TextBox", {
		Name = "Query",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Search features",
		ClearTextOnFocus = false,
		FontFace = UI.regular,
		TextSize = 12,
		TextColor3 = Theme.text,
		PlaceholderColor3 = Theme.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	}, self.searchFrame)
	UI.fill(self.searchBox)
	self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self:search(self.searchBox.Text)
	end)
	self.searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and self.hits and self.hits[1] then
			self:reveal(self.hits[1])
		end
	end)

	self:iconButton(bar, "minus", 4, function()
		self:setVisible(false)
	end)
	self:iconButton(bar, "x", 5, function()
		self:dialog({
			title = "Close hub?",
			content = "Reopen it with the launcher button or the menu key.",
			buttons = { { title = "Cancel" }, { title = "Close", variant = "primary", callback = function()
				self:setVisible(false)
			end } },
		})
	end, true)

	-- Dragging the bar moves the window.
	bar.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local start, origin = UI.pointer(input), self.root.Position
		Library.dragging = function(point)
			local delta = point - start
			self.root.Position = origin + UDim2.fromOffset(delta.X, delta.Y)
		end
	end)
end

function Window:buildSidebar()
	self.sidebar = UI.frame(self.root, {
		Name = "Sidebar",
		Position = UDim2.fromOffset(8, 48),
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -56),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = Theme.panelTransparency,
	})
	UI.corner(self.sidebar, 9)
	UI.stroke(self.sidebar)
	self.tabList = UI.new("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self.sidebar)
	UI.padding(self.tabList, 6, 6, 4, 6)
	UI.list(self.tabList, Enum.FillDirection.Vertical, 2)

	local footer = UI.frame(self.sidebar, { Name = "Profile", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 52) })
	UI.frame(footer, { Name = "Divider", Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = Theme.lineTransparency })
	local content = UI.frame(footer, { Name = "Content", Size = UDim2.fromScale(1, 1) })
	UI.padding(content, 12, 8, 1, 0)
	self.footerLayout = UI.list(content, Enum.FillDirection.Horizontal, 9, Enum.VerticalAlignment.Center)
	local avatar = UI.new("ImageLabel", {
		Name = "Avatar",
		Size = UDim2.fromOffset(32, 32),
		Image = `rbxthumb://type=AvatarHeadShot&id={localPlayer.UserId}&w=48&h=48`,
		BorderSizePixel = 0,
	}, content)
	UI.accent(avatar, "BackgroundColor3")
	UI.corner(avatar, 9)
	self.footerText = UI.frame(content, { Name = "Text", Size = UDim2.new(1, -41, 0, 30), LayoutOrder = 2 })
	UI.list(self.footerText, Enum.FillDirection.Vertical, 1, Enum.VerticalAlignment.Center)
	UI.text(self.footerText, localPlayer.DisplayName, 12, Theme.text, UI.semibold, { Size = UDim2.new(1, 0, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.text(self.footerText, `@{localPlayer.Name}`, 11, Theme.sub, UI.regular, { Size = UDim2.new(1, 0, 0, 13), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
end

-- Scales the window to the screen and switches to the compact layout on narrow screens.
function Window:fit()
	local screen = self.gui.AbsoluteSize
	if screen.X == 0 then
		return
	end
	local compact = screen.X < COMPACT_BELOW
	local scale = if compact then 1 else math.clamp(math.min((screen.X - 24) / WINDOW_SIZE.X, (screen.Y - 24) / WINDOW_SIZE.Y), 0.5, 1)
	self.scale.Scale = scale
	self.layerScale.Scale = scale
	self.toastScale.Scale = scale
	self.root.Size = if compact then UDim2.fromOffset(screen.X - 16, screen.Y - 16) else UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y)
	if compact == self.compact then
		return
	end
	self.compact = compact
	self:closePopover()
	local sidebarWidth = if compact then COMPACT_SIDEBAR_WIDTH else SIDEBAR_WIDTH
	self.sidebar.Size = UDim2.new(0, sidebarWidth, 1, -56)
	self.pages.Position = UDim2.fromOffset(sidebarWidth + 16, 48)
	self.pages.Size = UDim2.new(1, -(sidebarWidth + 24), 1, -56)
	self.brandText.Visible = not compact
	self.brand.Size = UDim2.fromOffset(if compact then 30 else 178, 36)
	self.pageTitle.Visible = not compact
	self.footerText.Visible = not compact
	self.footerLayout.HorizontalAlignment = if compact then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	for _, header in self.groupHeaders do
		header.Visible = not compact
	end
	for _, tab in self.tabs do
		tab.label.Visible = not compact
		tab.glyph.AnchorPoint = Vector2.new(if compact then 0.5 else 0, 0.5)
		tab.glyph.Position = if compact then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 10, 0.5, 0)
		tab:arrange(compact)
	end
end

-- spec: title, icon, group, description
function Window:addTab(spec)
	if spec.group and spec.group ~= self.lastGroup then
		self.lastGroup = spec.group
		self.order += 1
		local header = UI.text(self.tabList, spec.group, 10, Theme.dim, UI.bold, {
			Name = spec.group,
			Size = UDim2.new(1, 0, 0, if #self.groupHeaders == 0 then 20 else 28),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			LayoutOrder = self.order,
			Visible = not self.compact,
		})
		UI.padding(header, 10, 0, 0, 5)
		table.insert(self.groupHeaders, header)
	end
	self.order += 1
	local button = UI.button(self.tabList, { Name = spec.title, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = self.order })
	UI.corner(button, 7)
	local active = UI.frame(button, { Name = "Active", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, Visible = false, ZIndex = 0 })
	UI.corner(active, 7)
	UI.gradient(active).Transparency = NumberSequence.new(0, 0.9)
	local glyph = UI.icon(button, spec.icon, 16, Theme.sub, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
	local label = UI.text(button, spec.title, 13, Theme.sub, UI.regular, { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -46, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local stroke = UI.stroke(button, 1)

	local tab = setmetatable({ window = self, title = spec.title, button = button, active = active, glyph = glyph, label = label, stroke = stroke, sections = {}, columns = {}, weights = { 0, 0 } }, Tab)
	tab.page = UI.new("ScrollingFrame", {
		Name = spec.title,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = WHITE,
		ScrollBarImageTransparency = 0.8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Visible = false,
	}, self.pages)
	UI.list(tab.page, Enum.FillDirection.Vertical, 0)
	if spec.description then
		local description = UI.text(tab.page, spec.description, 12, Theme.sub, UI.regular, {
			Name = "Description",
			Size = UDim2.new(1, 0, 0, 24),
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
		})
		UI.padding(description, 4, 4, 0, 0)
	end
	local columns = UI.frame(tab.page, { Name = "Columns", Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.list(columns, Enum.FillDirection.Horizontal, 8)
	for index = 1, 2 do
		tab.columns[index] = UI.frame(columns, { Name = `Column{index}`, Size = UDim2.new(0.5, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = index })
		UI.list(tab.columns[index], Enum.FillDirection.Vertical, 8)
	end
	if self.compact then
		label.Visible = false
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		tab:arrange(true)
	end

	button.MouseEnter:Connect(function()
		if self.current ~= tab then
			UI.tween(button, { BackgroundTransparency = Theme.rowTransparency })
		end
	end)
	button.MouseLeave:Connect(function()
		UI.tween(button, { BackgroundTransparency = 1 })
	end)
	button.Activated:Connect(function()
		self:selectTab(tab)
	end)
	table.insert(self.tabs, tab)
	if #self.tabs == 1 then
		self:selectTab(tab)
	end
	return tab
end

function Window:selectTab(tab)
	for _, other in self.tabs do
		local on = other == tab
		other.page.Visible = on
		other.active.Visible = on
		other.stroke.Transparency = if on then Theme.lineTransparency else 1
		other.label.TextColor3 = if on then Theme.text else Theme.sub
		other.glyph.ImageColor3 = if on then Library.accent else Theme.sub
		other.button.BackgroundTransparency = 1
	end
	self.current = tab
	self.pageTitle.Text = tab.title
	tab.page.CanvasPosition = Vector2.zero
end

function Window:setVisible(visible)
	self.visible = visible
	self.root.Visible = visible
	self:closePopover()
	self:updateBlur()
	UI.tween(self.stats, { Position = if visible then STATS_OPEN else STATS_MINIMIZED }, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	if visible then
		self.launcher.Visible = false
		return
	end
	local key = Library.flags.__menuKey
	self.launcherKey.Text = if key then KEY_NAMES[key] or key else "None"
	self.launcherKey.Parent.Visible = key ~= false
	self.launcher.Position = LAUNCHER_HIDDEN
	self.launcher.Visible = true
	UI.tween(self.launcher, { Position = LAUNCHER_SHOWN }, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
end

function Window:updateBlur()
	local on = self.visible and Library.flags.__blur == true
	if on and not self.blur then
		self.blur = UI.new("BlurEffect", { Name = "HidraHubBlur", Size = 0 }, lightingService)
	end
	if self.blur then
		UI.tween(self.blur, { Size = if on then BLUR_SIZE else 0 })
	end
end

function Window:onInput(input, processed)
	local kind = input.UserInputType
	if self.popover and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
		local point = UI.pointer(input)
		if not UI.inside(self.popover.frame, point) and not UI.inside(self.popover.anchor, point) then
			self:closePopover()
		end
	end
	if kind ~= Enum.UserInputType.Keyboard or Library.capturing or processed or userInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode.Name
	if key == Library.flags.__menuKey then
		self:setVisible(not self.visible)
		return
	end
	for _, bind in Library.keybinds do
		if bind.pressed and Library.flags[bind.flag] == key then
			Library.fire(bind.pressed)
		end
	end
end

-- Opens a popover under anchor (above it when there is no room). build(frame) fills it.
function Window:openPopover(anchor, width, build)
	self:closePopover()
	local scale = self.layerScale.Scale
	local frame = UI.frame(self.layer, {
		Name = "Popover",
		Size = UDim2.fromOffset(math.max(width, anchor.AbsoluteSize.X / scale), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.popover,
		BackgroundTransparency = 0.04,
		Active = true,
	})
	UI.corner(frame, 9)
	UI.stroke(frame, Theme.lineStrongTransparency)
	local padding = UI.padding(frame, 4, 4, 4, 4)
	UI.list(frame, Enum.FillDirection.Vertical, 4)
	self.popover = { anchor = anchor, frame = frame, padding = padding }
	build(frame)
	self:placePopover()
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:placePopover()
	end)
end

function Window:togglePopover(anchor, width, build)
	if self.popover and self.popover.anchor == anchor then
		self:closePopover()
		return
	end
	self:openPopover(anchor, width, build)
end

function Window:placePopover()
	local popover = self.popover
	if not popover then
		return
	end
	local scale = self.layerScale.Scale
	local anchor, frame, screen = popover.anchor, popover.frame, self.gui.AbsoluteSize
	-- Positions relative to the layer, whose AbsolutePosition carries the inset offset.
	local origin = self.layer.AbsolutePosition
	local anchorPosition = anchor.AbsolutePosition - origin
	local x = math.min(anchorPosition.X, screen.X - frame.AbsoluteSize.X - 8)
	local y = anchorPosition.Y + anchor.AbsoluteSize.Y + 4
	if y + frame.AbsoluteSize.Y > screen.Y - 8 then
		y = anchorPosition.Y - frame.AbsoluteSize.Y - 4
	end
	frame.Position = UDim2.fromOffset(x / scale, y / scale)
end

function Window:closePopover()
	if self.popover then
		self.popover.frame:Destroy()
		self.popover = nil
	end
end

-- image (optional): an asset shown at the start of the row, in its own colours.
function Window:option(parent, text, selected, order, image)
	local option = UI.button(parent, { Name = text, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order })
	UI.corner(option, 6)
	UI.hover(option, 1, Theme.rowHoverTransparency)
	-- With an image the check moves to the right edge, so the image starts the row instead of an empty check slot.
	local textX, rightPad = 30, 6
	if image then
		UI.icon(option, image, 20, WHITE, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0) })
		UI.icon(option, "check", 14, Library.accent, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Visible = selected })
		textX, rightPad = 34, 28
	else
		UI.icon(option, "check", 14, Library.accent, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Visible = selected })
	end
	UI.text(option, text, 12, if selected then Theme.text else Theme.sub, UI.regular, { Position = UDim2.fromOffset(textX, 0), Size = UDim2.new(1, -textX - rightPad, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	return option
end

function Window:buildOptions(popover, flag, spec, element)
	local values = if type(spec.values) == "function" then spec.values() else spec.values
	local filter
	if #values > 6 then
		filter = UI.textbox(popover, { Name = "Filter", PlaceholderText = "Filter", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1 })
	end
	local list = UI.new("ScrollingFrame", {
		Name = "Options",
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = WHITE,
		ScrollBarImageTransparency = 0.8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		LayoutOrder = 2,
	}, popover)
	UI.list(list, Enum.FillDirection.Vertical, 2)
	local function draw()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local term = if filter then string.lower(filter.Text) else ""
		local current = Library.flags[flag]
		local count = 0
		for _, value in values do
			local text = tostring(value)
			if term ~= "" and not string.find(string.lower(text), term, 1, true) then
				continue
			end
			count += 1
			local selected = if spec.multi then table.find(current, value) ~= nil else current == value
			local option = self:option(list, text, selected, count, spec.icons and spec.icons[value])
			option.Activated:Connect(function()
				if not spec.multi then
					element.set(value)
					self:closePopover()
					return
				end
				local nextValue = table.clone(Library.flags[flag])
				local index = table.find(nextValue, value)
				if index then
					table.remove(nextValue, index)
				else
					table.insert(nextValue, value)
				end
				element.set(nextValue)
				draw()
			end)
		end
		if count == 0 then
			local empty = UI.text(list, if #values == 0 then "Nothing here yet." else "Nothing matches.", 12, Theme.dim, UI.regular, { Size = UDim2.new(1, 0, 0, 30) })
			UI.padding(empty, 10)
		end
		list.Size = UDim2.new(1, 0, 0, math.min(math.max(count, 1) * 32, 200))
	end
	draw()
	if filter then
		filter:GetPropertyChangedSignal("Text"):Connect(draw)
		filter:CaptureFocus()
	end
end

-- Saturation/value square, hue bar and hex box. Every change goes through element.set.
function Window:buildPicker(popover, flag, element)
	self.popover.padding.PaddingLeft = UDim.new(0, 10)
	self.popover.padding.PaddingRight = UDim.new(0, 10)
	self.popover.padding.PaddingTop = UDim.new(0, 10)
	self.popover.padding.PaddingBottom = UDim.new(0, 10)
	popover:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 10)
	local hue, saturation, value = Library.flags[flag]:ToHSV()

	local square = UI.button(popover, { Name = "Square", Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 0, LayoutOrder = 1 })
	UI.corner(square, 6)
	local whiteFade = UI.frame(square, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	UI.corner(whiteFade, 6)
	UI.new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, whiteFade)
	local blackFade = UI.frame(square, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0 })
	UI.corner(blackFade, 6)
	UI.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, blackFade)
	local cursor = UI.frame(square, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 3 })
	UI.corner(cursor)
	UI.new("UIStroke", { Color = WHITE, Thickness = 2 }, cursor)

	local hueBar = UI.button(popover, { Name = "Hue", Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 0, LayoutOrder = 2 })
	UI.corner(hueBar)
	local rainbow = {}
	for index = 0, 6 do
		table.insert(rainbow, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6 % 1, 1, 1)))
	end
	UI.new("UIGradient", { Color = ColorSequence.new(rainbow) }, hueBar)
	local hueKnob = UI.frame(hueBar, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = WHITE, BackgroundTransparency = 0, ZIndex = 2 })
	UI.corner(hueKnob)
	UI.stroke(hueKnob, 0.6, Color3.new())

	local hex = UI.textbox(popover, { Name = "Hex", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3 })
	local function paint(commit)
		square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		cursor.Position = UDim2.fromScale(saturation, 1 - value)
		hueKnob.Position = UDim2.fromScale(hue, 0.5)
		local color = Color3.fromHSV(hue, saturation, value)
		hex.Text = "#" .. string.upper(color:ToHex())
		if commit then
			element.set(color)
		end
	end
	UI.draggable(square, function(point)
		saturation = math.clamp((point.X - square.AbsolutePosition.X) / square.AbsoluteSize.X, 0, 1)
		value = 1 - math.clamp((point.Y - square.AbsolutePosition.Y) / square.AbsoluteSize.Y, 0, 1)
		paint(true)
	end)
	UI.draggable(hueBar, function(point)
		hue = math.clamp((point.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
		paint(true)
	end)
	hex.FocusLost:Connect(function()
		local ok, color = pcall(Color3.fromHex, hex.Text)
		if ok then
			hue, saturation, value = color:ToHSV()
		end
		paint(ok)
	end)
	paint(false)
end

-- Searches every element title. Enter opens the first hit.
function Window:search(term)
	term = string.lower(term)
	if term == "" then
		self.hits = nil
		if self.popover and self.popover.anchor == self.searchFrame then
			self:closePopover()
		end
		return
	end
	local hits = {}
	for _, entry in Library.searchIndex do
		if string.find(string.lower(entry.title), term, 1, true) then
			table.insert(hits, entry)
			if #hits == 8 then
				break
			end
		end
	end
	self.hits = hits
	self:openPopover(self.searchFrame, 300, function(popover)
		for index, entry in hits do
			local result = UI.button(popover, { Name = entry.title, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = if index == 1 then Theme.rowHoverTransparency else 1, LayoutOrder = index })
			UI.corner(result, 6)
			UI.hover(result, if index == 1 then Theme.rowHoverTransparency else 1, Theme.rowHoverTransparency)
			UI.padding(result, 9)
			UI.list(result, Enum.FillDirection.Vertical, 1, Enum.VerticalAlignment.Center)
			UI.text(result, entry.title, 12, Theme.text, UI.semibold, { Size = UDim2.new(1, 0, 0, 15) })
			UI.text(result, `{entry.tab.title} › {entry.section}`, 11, Theme.dim, UI.regular, { Size = UDim2.new(1, 0, 0, 13), LayoutOrder = 2 })
			result.Activated:Connect(function()
				self:reveal(entry)
			end)
		end
		if #hits == 0 then
			local empty = UI.text(popover, "No feature matches that.", 12, Theme.dim, UI.regular, { Size = UDim2.new(1, 0, 0, 30) })
			UI.padding(empty, 9)
		end
	end)
end

function Window:reveal(entry)
	self:closePopover()
	self.searchBox.Text = ""
	self:selectTab(entry.tab)
	task.defer(function()
		local page = entry.tab.page
		local offset = (entry.row.AbsolutePosition.Y - page.AbsolutePosition.Y) / self.scale.Scale + page.CanvasPosition.Y - 40
		page.CanvasPosition = Vector2.new(0, math.max(0, offset))
	end)
	entry.stroke.Color = Library.accent
	entry.stroke.Transparency = 0
	task.delay(0.9, function()
		UI.tween(entry.stroke, { Color = WHITE, Transparency = 0.945 }, TweenInfo.new(0.4))
	end)
end

-- spec: title, content, buttons = { { title, variant ("primary" | "danger"), callback } }
function Window:dialog(spec)
	local scrim = UI.button(self.root, { Name = "Dialog", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 8, 12), BackgroundTransparency = 0.4, ZIndex = 20, Modal = true })
	UI.corner(scrim, 12)
	local box = UI.frame(scrim, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = rgb(40, 42, 47),
		BackgroundTransparency = 0.03,
		Active = true,
	})
	UI.corner(box, 12)
	UI.stroke(box, Theme.lineStrongTransparency)
	UI.padding(box, 16, 16, 16, 16)
	UI.list(box, Enum.FillDirection.Vertical, 6)
	UI.text(box, spec.title, 14, Theme.text, UI.bold, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1 })
	UI.text(box, spec.content or "", 12, Theme.sub, UI.regular, { Size = UDim2.new(1, 0, 0, 15), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 })
	local actions = UI.frame(box, { Name = "Actions", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 3 })
	UI.padding(actions, 0, 0, 8, 0)
	UI.list(actions, Enum.FillDirection.Horizontal, 6, Enum.VerticalAlignment.Center, Enum.HorizontalAlignment.Right)
	for index, choice in spec.buttons do
		local filled = choice.variant ~= nil
		local button = UI.button(actions, {
			Name = choice.title,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = if choice.variant == "danger" then Theme.danger else WHITE,
			BackgroundTransparency = if filled then 0 else Theme.rowHoverTransparency,
			LayoutOrder = index,
		})
		UI.corner(button, 7)
		UI.padding(button, 14)
		if choice.variant == "primary" then
			UI.gradient(button, false)
		end
		UI.text(button, choice.title, 12, if filled then WHITE else Theme.text, UI.semibold, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X })
		button.Activated:Connect(function()
			scrim:Destroy()
			Library.fire(choice.callback)
		end)
	end
	scrim.Activated:Connect(function()
		scrim:Destroy()
	end)
end

-- spec: title, content, duration (seconds), icon
function Library.notify(spec)
	local window = Library.window
	if not window then
		return
	end
	local duration = spec.duration or 4
	local offscreen = UDim2.fromOffset(TOAST_WIDTH + 24, 0)
	window.toastCount += 1

	-- The slot keeps its place in the stack while the card slides in and out of it.
	local slot = UI.frame(window.toasts, { Name = spec.title, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = window.toastCount })
	local card = UI.button(slot, {
		Name = "Card",
		Position = offscreen,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.popover,
		BackgroundTransparency = 0.04,
	})
	UI.corner(card, 10)
	UI.stroke(card, Theme.lineStrongTransparency)
	-- Stripe and timer sit on the card itself; the list layout only arranges the content row.
	local stripe = UI.frame(card, { Name = "Stripe", Position = UDim2.fromOffset(6, 10), Size = UDim2.new(0, 3, 1, -20), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	UI.corner(stripe)
	UI.gradient(stripe, false).Rotation = 90
	local content = UI.frame(card, { Name = "Content", Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.padding(content, 18, 10, 12, 15)
	UI.list(content, Enum.FillDirection.Horizontal, 11)

	local chip = UI.frame(content, { Name = "Icon", Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Library.accent, BackgroundTransparency = 0.82, LayoutOrder = 1 })
	UI.corner(chip, 8)
	UI.icon(chip, spec.icon or "bell", 16, Library.accent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })

	local body = UI.frame(content, { Name = "Body", Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	UI.fill(body)
	UI.list(body, Enum.FillDirection.Vertical, 3)
	UI.padding(body, 0, 0, 1, 0)
	UI.text(body, spec.title, 13, Theme.text, UI.bold, { Size = UDim2.new(1, 0, 0, 15), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
	if spec.content then
		UI.text(body, spec.content, 12, Theme.sub, UI.regular, { Size = UDim2.new(1, 0, 0, 14), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 })
	end

	local close = UI.button(content, { Name = "Close", Size = UDim2.fromOffset(22, 22), LayoutOrder = 3 })
	UI.corner(close, 6)
	UI.hover(close, 1, Theme.rowHoverTransparency)
	UI.icon(close, "x", 12, Theme.dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })

	-- Time left, drained left to right along the bottom edge.
	local track = UI.frame(card, { Name = "Timer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -6), Size = UDim2.new(1, -30, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.92 })
	UI.corner(track)
	local fill = UI.frame(track, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	UI.corner(fill)
	UI.gradient(fill, false)
	UI.tween(fill, { Size = UDim2.fromScale(0, 1) }, TweenInfo.new(duration, Enum.EasingStyle.Linear))

	UI.tween(card, { Position = UDim2.new() }, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	local entry = {}
	function entry.dismiss()
		if entry.gone then
			return
		end
		entry.gone = true
		local index = table.find(window.toastList, entry)
		if index then
			table.remove(window.toastList, index)
		end
		UI.tween(card, { Position = offscreen }, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)).Completed:Once(function()
			slot:Destroy()
		end)
	end
	table.insert(window.toastList, entry)
	if #window.toastList > MAX_TOASTS then
		window.toastList[1].dismiss()
	end
	card.Activated:Connect(entry.dismiss)
	close.Activated:Connect(entry.dismiss)
	task.delay(duration, entry.dismiss)
end

-- Settings tab every hub gets: interface options, profiles, auto save and unload.
-- Call it after every other tab, then Library.restore().
function Library.addSettingsTab(window, group)
	local tab = window:addTab({ title = "Settings", icon = "settings", group = group, description = "Interface, keybinds and saved profiles." })
	local interface = tab:addSection("Interface")
	interface:addKeybind("__menuKey", { title = "Menu key", description = "Shows or hides the window.", default = Library.flags.__menuKey })

	local dots = {}
	local function markPreset(color)
		for _, dot in dots do
			dot.ring.Transparency = if dot.color == color then 0 else 1
		end
	end
	local accent = interface:addColor("__accent", { title = "Accent color", description = "Used for selections, switches and highlights.", default = Library.accent, callback = function(color)
		Library.setAccent(color)
		markPreset(color)
	end })
	interface:addCustom({ title = "Accent presets" }, function(row)
		local holder = UI.frame(row, { Name = "Presets", Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
		UI.list(holder, Enum.FillDirection.Horizontal, 7, Enum.VerticalAlignment.Center)
		for index, color in ACCENT_PRESETS do
			local dot = UI.button(holder, { Name = color:ToHex(), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = color, BackgroundTransparency = 0, LayoutOrder = index })
			UI.corner(dot)
			local ring = UI.new("UIStroke", { Color = color, Thickness = 2, Transparency = 1 }, dot)
			table.insert(dots, { color = color, ring = ring })
			dot.Activated:Connect(function()
				accent.set(color)
			end)
		end
	end)
	markPreset(Library.accent)
	interface:addSlider("__opacity", { title = "Window opacity", min = 40, max = 100, step = 1, default = math.round((1 - Theme.windowTransparency) * 100), suffix = "%", callback = function(percent)
		window.root.BackgroundTransparency = 1 - percent / 100
	end })
	interface:addToggle("__blur", { title = "Background blur", description = "Blurs the game while the window is open.", default = false, callback = function()
		window:updateBlur()
	end })
	interface:addToggle("__stats", { title = "Stats bar", description = "FPS, ping and more at the top of the screen.", default = true, callback = function(on)
		window.stats.Visible = on
		window:refreshStats()
	end })

	local profiles = tab:addSection("Profiles")
	profiles:addInput("__profileName", { title = "Profile name", placeholder = "farm night" })
	local saved = profiles:addDropdown("__profile", { title = "Saved profiles", values = Storage.list, callback = function(name)
		Library.elements.__profileName.set(name or "", true)
	end })
	profiles:addButton({ title = "Save profile", icon = "save", variant = "primary", callback = function()
		local name = string.match(Library.flags.__profileName, "^%s*(.-)%s*$")
		if name == "" or #name > 32 or string.find(name, "[^%w%s%-_]") then
			Library.notify({ title = "Profiles", content = "Use 1 to 32 letters, numbers, spaces, - or _." })
			return
		end
		local function commit()
			Storage.write(name, Library.snapshot())
			saved.set(name, true)
			Library.notify({ title = "Profile saved", content = name, icon = "save" })
		end
		if Storage.read(name) then
			window:dialog({ title = "Replace profile?", content = `"{name}" already exists.`, buttons = { { title = "Cancel" }, { title = "Replace", variant = "primary", callback = commit } } })
		else
			commit()
		end
	end })
	profiles:addButton({ title = "Load profile", icon = "download", callback = function()
		local name = Library.flags.__profile
		local data = name and Storage.read(name)
		if not data then
			Library.notify({ title = "Profiles", content = "Pick a saved profile first." })
			return
		end
		Library.apply(data)
		Library.notify({ title = "Profile loaded", content = name, icon = "download" })
	end })
	profiles:addButton({ title = "Delete profile", icon = "trash-2", variant = "danger", callback = function()
		local name = Library.flags.__profile
		if not name then
			Library.notify({ title = "Profiles", content = "Pick a saved profile first." })
			return
		end
		window:dialog({ title = "Delete profile?", content = `"{name}" will be removed for good.`, buttons = { { title = "Cancel" }, { title = "Delete", variant = "danger", callback = function()
			Storage.remove(name)
			if Storage.getAuto() == name then
				Storage.setAuto(nil)
				Library.elements.__profileAuto.set(false, true)
			end
			saved.set(nil, true)
			Library.notify({ title = "Profile deleted", content = name, icon = "trash-2" })
		end } } })
	end })
	profiles:addToggle("__autosave", { title = "Auto save", description = "Saves every change and restores it next time.", default = true })
	profiles:addToggle("__profileAuto", { title = "Load on start", description = "Applies the selected profile when the hub opens.", callback = function(on)
		local name = Library.flags.__profile
		if on and not name then
			Library.notify({ title = "Profiles", content = "Pick a saved profile first." })
			Library.elements.__profileAuto.set(false, true)
			return
		end
		Storage.setAuto(if on then name else nil)
	end })

	local session = tab:addSection("Session")
	session:addButton({ title = "Unload hub", description = "Stops every feature and removes the interface.", icon = "power", variant = "danger", callback = function()
		window:dialog({ title = "Unload hub?", content = "Every feature stops and the window is removed.", buttons = { { title = "Cancel" }, { title = "Unload", variant = "danger", callback = Library.destroy } } })
	end })

	return tab
end

-- Hubs set this to stop their features when the user unloads.
Library.onUnload = nil

function Library.destroy()
	if Library.unloaded then
		return
	end
	Library.unloaded = true
	Library.fire(Library.onUnload)
	for _, connection in Library.connections do
		connection:Disconnect()
	end
	table.clear(Library.connections)
	local window = Library.window
	if window then
		window:closePopover()
		if window.blur then
			window.blur:Destroy()
		end
		window.gui:Destroy()
	end
	Library.window = nil
end

return Library
