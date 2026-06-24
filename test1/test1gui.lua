-- SourceMovementGUI.lua
-- LocalScript → StarterPlayerScripts

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local gui = player:WaitForChild("PlayerGui")

-- Удаляем старый GUI если есть
local oldGui = gui:FindFirstChild("SourceMovementGUI")
if oldGui then
	oldGui:Destroy()
end

-- ═══════════════════════════════════════════════════════════
--  НАСТРОЙКИ
-- ═══════════════════════════════════════════════════════════
if _G.SavedMovementSettings then
	pcall(function()
		local data = HttpService:JSONDecode(_G.SavedMovementSettings)
		_G.SourceMovementEnabled = data.SourceMovementEnabled
		_G.AutoBhopEnabled = data.AutoBhopEnabled
		_G.GuiPositionX = data.GuiPositionX
		_G.GuiPositionY = data.GuiPositionY
	end)
end
if _G.SourceMovementEnabled == nil then _G.SourceMovementEnabled = true end
if _G.AutoBhopEnabled == nil then _G.AutoBhopEnabled = false end
if _G.GuiPositionX == nil then _G.GuiPositionX = 100 end
if _G.GuiPositionY == nil then _G.GuiPositionY = 100 end

local function saveSettings()
	_G.SavedMovementSettings = HttpService:JSONEncode({
		SourceMovementEnabled = _G.SourceMovementEnabled,
		AutoBhopEnabled = _G.AutoBhopEnabled,
		GuiPositionX = _G.GuiPositionX,
		GuiPositionY = _G.GuiPositionY
	})
end

-- ═══════════════════════════════════════════════════════════
--  ЦВЕТА
-- ═══════════════════════════════════════════════════════════
local C = {
	Bg = Color3.fromRGB(35, 35, 35),
	Hdr = Color3.fromRGB(20, 20, 20),
	Bdr = Color3.fromRGB(60, 60, 60),
	Txt = Color3.fromRGB(220, 220, 220),
	Txt2 = Color3.fromRGB(180, 180, 180),
	TxtDisabled = Color3.fromRGB(80, 80, 80),
	Btn = Color3.fromRGB(50, 50, 50),
	BtnH = Color3.fromRGB(70, 70, 70),
	On = Color3.fromRGB(80, 200, 80),
	Off = Color3.fromRGB(120, 120, 120),
}

-- ═══════════════════════════════════════════════════════════
--  ПЕРЕМЕННЫЕ СОСТОЯНИЯ
-- ═══════════════════════════════════════════════════════════
local isEnabled = _G.SourceMovementEnabled ~= false
local isAutoBhop = _G.AutoBhopEnabled ~= false
local autoBhopWasOnBeforeDisable = isAutoBhop
local dragging = false
local dragStart = nil
local winStart = nil
local resizing = false
local resizeDir = nil
local resizeStartMouse = nil
local resizeStartSize = nil
local resizeStartPos = nil
local MIN_W = 200
local MIN_H = 150

-- ═══════════════════════════════════════════════════════════
--  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ═══════════════════════════════════════════════════════════
local function setCursor(id)
	pcall(function() mouse.Icon = id end)
end

-- ═══════════════════════════════════════════════════════════
--  ФУНКЦИИ ПЕРЕКЛЮЧЕНИЯ
-- ═══════════════════════════════════════════════════════════
local enBtn, abBtn, abLbl

local function setAutoBhop(state)
	isAutoBhop = state
	_G.AutoBhopEnabled = state
	if abBtn and abBtn.Parent then
		abBtn.BackgroundColor3 = state and C.On or C.Off
	end
	saveSettings()
end

local function setEnabled(state)
	isEnabled = state
	_G.SourceMovementEnabled = state
	if enBtn and enBtn.Parent then
		enBtn.BackgroundColor3 = state and C.On or C.Off
	end

	if not state then
		-- Выключаем Enabled
		autoBhopWasOnBeforeDisable = isAutoBhop
		setAutoBhop(false)
		if abLbl then abLbl.TextColor3 = C.TxtDisabled end
		if abBtn then 
			abBtn.Active = false
			abBtn.BackgroundColor3 = C.TxtDisabled  -- Серый квадратик вместо зелёного/серого
		end
	else
		-- Включаем Enabled
		if abLbl then abLbl.TextColor3 = C.Txt end
		if abBtn then 
			abBtn.Active = true
			abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off  -- Возвращаем нормальный цвет
		end
	end

	saveSettings()
end

-- ═══════════════════════════════════════════════════════════
--  ФУНКЦИЯ СОЗДАНИЯ GUI
-- ═══════════════════════════════════════════════════════════
local function createGUI()
	mouse = player:GetMouse()
	gui = player:WaitForChild("PlayerGui")

	local old = gui:FindFirstChild("SourceMovementGUI")
	if old then old:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name = "SourceMovementGUI"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = gui

	local win = Instance.new("Frame")
	win.Name = "Window"
	win.Size = UDim2.new(0, 280, 0, 240)
	win.Position = UDim2.new(0, _G.GuiPositionX or 100, 0, _G.GuiPositionY or 100)
	win.BackgroundColor3 = C.Bg
	win.BorderSizePixel = 0
	win.Active = true
	win.Parent = sg

	Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)

	local winStroke = Instance.new("UIStroke", win)
	winStroke.Color = C.Bdr
	winStroke.Thickness = 1.5

	-- Шапка
	local hdr = Instance.new("Frame", win)
	hdr.Size = UDim2.new(1, 0, 0, 48)
	hdr.BackgroundColor3 = C.Hdr
	hdr.BorderSizePixel = 0
	hdr.Active = true

	Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 12)

	local hdrFix = Instance.new("Frame", hdr)
	hdrFix.Size = UDim2.new(1, 0, 0, 12)
	hdrFix.Position = UDim2.new(0, 0, 1, -12)
	hdrFix.BackgroundColor3 = C.Hdr
	hdrFix.BorderSizePixel = 0

	local div = Instance.new("Frame", win)
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, 48)
	div.BackgroundColor3 = C.Bdr
	div.BorderSizePixel = 0

	local title = Instance.new("TextLabel", hdr)
	title.Size = UDim2.new(1, -56, 1, 0)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Source\nMovement"
	title.TextColor3 = C.Txt
	title.TextSize = 15
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center

	local gear = Instance.new("TextButton", hdr)
	gear.Size = UDim2.new(0, 36, 0, 36)
	gear.Position = UDim2.new(1, -44, 0, 6)
	gear.BackgroundColor3 = C.Btn
	gear.BorderSizePixel = 0
	gear.Text = "✱"
	gear.TextSize = 18
	gear.TextColor3 = C.Txt2
	gear.Font = Enum.Font.GothamBold
	Instance.new("UICorner", gear).CornerRadius = UDim.new(0, 8)

	-- Тело
	local body = Instance.new("Frame", win)
	body.Size = UDim2.new(1, 0, 1, -49)
	body.Position = UDim2.new(0, 0, 0, 49)
	body.BackgroundTransparency = 1

	-- Enabled
	local enRow = Instance.new("Frame", body)
	enRow.Size = UDim2.new(1, -24, 0, 40)
	enRow.Position = UDim2.new(0, 12, 0, 10)
	enRow.BackgroundTransparency = 1

	local enLbl = Instance.new("TextLabel", enRow)
	enLbl.Size = UDim2.new(1, -52, 1, 0)
	enLbl.BackgroundTransparency = 1
	enLbl.Text = "Enabled"
	enLbl.TextColor3 = C.Txt
	enLbl.TextSize = 17
	enLbl.Font = Enum.Font.Gotham
	enLbl.TextXAlignment = Enum.TextXAlignment.Left
	enLbl.TextYAlignment = Enum.TextYAlignment.Center

	enBtn = Instance.new("TextButton", enRow)
	enBtn.Size = UDim2.new(0, 36, 0, 36)
	enBtn.Position = UDim2.new(1, -36, 0, 2)
	enBtn.BackgroundColor3 = isEnabled and C.On or C.Off
	enBtn.BorderSizePixel = 0
	enBtn.Text = ""
	Instance.new("UICorner", enBtn).CornerRadius = UDim.new(0, 7)

	-- Auto Bhop
	local abRow = Instance.new("Frame", body)
	abRow.Size = UDim2.new(1, -24, 0, 40)
	abRow.Position = UDim2.new(0, 12, 0, 60)
	abRow.BackgroundTransparency = 1

	abLbl = Instance.new("TextLabel", abRow)
	abLbl.Size = UDim2.new(1, -52, 1, 0)
	abLbl.BackgroundTransparency = 1
	abLbl.Text = "Auto Bhop"
	abLbl.TextColor3 = C.Txt
	abLbl.TextSize = 17
	abLbl.Font = Enum.Font.Gotham
	abLbl.TextXAlignment = Enum.TextXAlignment.Left
	abLbl.TextYAlignment = Enum.TextYAlignment.Center

	abBtn = Instance.new("TextButton", abRow)
	abBtn.Size = UDim2.new(0, 36, 0, 36)
	abBtn.Position = UDim2.new(1, -36, 0, 2)
	abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off
	abBtn.BorderSizePixel = 0
	abBtn.Text = ""
	Instance.new("UICorner", abBtn).CornerRadius = UDim.new(0, 7)

	-- Применяем начальное состояние Enabled
	if not isEnabled then
		abLbl.TextColor3 = C.TxtDisabled
		abBtn.Active = false
		abBtn.BackgroundColor3 = C.Off
	else
		abLbl.TextColor3 = C.Txt
		abBtn.Active = true
	end

	-- ═══════════════════════════════════════════════════════
	--  ЛОГИКА КНОПОК
	-- ═══════════════════════════════════════════════════════
	enBtn.MouseButton1Click:Connect(function()
		setEnabled(not isEnabled)
	end)

	abBtn.MouseButton1Click:Connect(function()
		if abBtn.Active then
			setAutoBhop(not isAutoBhop)
		end
	end)

	gear.MouseButton1Click:Connect(function()
		gear.BackgroundColor3 = C.BtnH
		task.delay(0.1, function() gear.BackgroundColor3 = C.Btn end)
	end)

	-- Перетаскивание
	hdr.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			winStart = win.AbsolutePosition
		end
	end)

	-- Hover эффекты
	enBtn.MouseEnter:Connect(function()
		enBtn.BackgroundColor3 = (isEnabled and C.On or C.Off):Lerp(Color3.new(1,1,1), 0.15)
	end)
	enBtn.MouseLeave:Connect(function()
		enBtn.BackgroundColor3 = isEnabled and C.On or C.Off
	end)
	abBtn.MouseEnter:Connect(function()
		if abBtn.Active then
			abBtn.BackgroundColor3 = (isAutoBhop and C.On or C.Off):Lerp(Color3.new(1,1,1), 0.15)
		end
	end)
	abBtn.MouseLeave:Connect(function()
		if abBtn.Active then
			abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off
		end
	end)
	gear.MouseEnter:Connect(function() gear.BackgroundColor3 = C.BtnH end)
	gear.MouseLeave:Connect(function() gear.BackgroundColor3 = C.Btn end)

	return win, hdr, gear
end

-- Создаём GUI
local win, hdr, gear = createGUI()

-- ═══════════════════════════════════════════════════════════
--  ЗОНЫ РЕСАЙЗА
-- ═══════════════════════════════════════════════════════════
local CORNER = 24
local EDGE = 14
local OVER = 8

local resizeZones = {
	{name = "RB", dir = "corner_rb", cur = "rbxasset://textures/Cursors/DragCorner.png",
		check = function(x, y, ax, ay, sx, sy)
			return x >= ax + sx - CORNER and x <= ax + sx + OVER and y >= ay + sy - CORNER and y <= ay + sy + OVER
		end},
	{name = "LB", dir = "corner_lb", cur = "rbxasset://textures/Cursors/DragCorner.png",
		check = function(x, y, ax, ay, sx, sy)
			return x >= ax - OVER and x <= ax + CORNER and y >= ay + sy - CORNER and y <= ay + sy + OVER
		end},
	{name = "RT", dir = "corner_rt", cur = "rbxasset://textures/Cursors/DragCorner.png",
		check = function(x, y, ax, ay, sx, sy)
			return x >= ax + sx - CORNER and x <= ax + sx + OVER and y >= ay + 48 - OVER and y <= ay + 48 + CORNER
		end},
	{name = "LT", dir = "corner_lt", cur = "rbxasset://textures/Cursors/DragCorner.png",
		check = function(x, y, ax, ay, sx, sy)
			return x >= ax - OVER and x <= ax + CORNER and y >= ay + 48 - OVER and y <= ay + 48 + CORNER
		end},
	{name = "R", dir = "right", cur = "rbxasset://textures/Cursors/DragHorizontal.png",
		check = function(x, y, ax, ay, sx, sy)
			if y < ay + 48 + CORNER or y > ay + sy - CORNER then return false end
			return x >= ax + sx - EDGE and x <= ax + sx + OVER
		end},
	{name = "L", dir = "left", cur = "rbxasset://textures/Cursors/DragHorizontal.png",
		check = function(x, y, ax, ay, sx, sy)
			if y < ay + 48 + CORNER or y > ay + sy - CORNER then return false end
			return x >= ax - OVER and x <= ax + EDGE
		end},
	{name = "B", dir = "bottom", cur = "rbxasset://textures/Cursors/DragVertical.png",
		check = function(x, y, ax, ay, sx, sy)
			if x < ax + CORNER or x > ax + sx - CORNER then return false end
			return y >= ay + sy - EDGE and y <= ay + sy + OVER
		end},
}

-- ═══════════════════════════════════════════════════════════
--  ГЛОБАЛЬНЫЕ ОБРАБОТЧИКИ
-- ═══════════════════════════════════════════════════════════

local function checkResizeZones(mx, my)
	if not win or not win.Parent then return nil end
	local a = win.AbsolutePosition
	local s = win.AbsoluteSize

	for _, z in ipairs(resizeZones) do
		if z.check(mx, my, a.X, a.Y, s.X, s.Y) then
			return z
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local mx = input.Position.X
	local my = input.Position.Y

	local zone = checkResizeZones(mx, my)
	if zone then
		resizing = true
		resizeDir = zone.dir
		resizeStartMouse = Vector2.new(mx, my)
		if win and win.Parent then
			resizeStartSize = win.AbsoluteSize
			resizeStartPos = win.AbsolutePosition
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if resizing then
			resizing = false
			resizeDir = nil
			setCursor("")
			saveSettings()
		end
		if dragging then
			dragging = false
			saveSettings()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

	local mx = input.Position.X
	local my = input.Position.Y

	if dragging and win and win.Parent and not resizing then
		local delta = Vector2.new(mx, my) - dragStart
		local newX = winStart.X + delta.X
		local newY = winStart.Y + delta.Y
		win.Position = UDim2.new(0, newX, 0, newY)
		_G.GuiPositionX = newX
		_G.GuiPositionY = newY
		return
	end

	if resizing and resizeDir and win and win.Parent then
		local delta = Vector2.new(mx, my) - resizeStartMouse
		local nw, nh = resizeStartSize.X, resizeStartSize.Y
		local nx, ny = resizeStartPos.X, resizeStartPos.Y

		if resizeDir == "right" or resizeDir == "corner_rb" or resizeDir == "corner_rt" then
			nw = math.max(resizeStartSize.X + delta.X, MIN_W)
		end
		if resizeDir == "left" or resizeDir == "corner_lb" or resizeDir == "corner_lt" then
			nw = math.max(resizeStartSize.X - delta.X, MIN_W)
			nx = resizeStartPos.X + (resizeStartSize.X - nw)
		end
		if resizeDir == "bottom" or resizeDir == "corner_rb" or resizeDir == "corner_lb" then
			nh = math.max(resizeStartSize.Y + delta.Y, MIN_H)
		end
		if resizeDir == "corner_rt" or resizeDir == "corner_lt" then
			nh = math.max(resizeStartSize.Y - delta.Y, MIN_H)
			ny = resizeStartPos.Y + (resizeStartSize.Y - nh)
		end

		win.Size = UDim2.new(0, nw, 0, nh)
		win.Position = UDim2.new(0, nx, 0, ny)
		_G.GuiPositionX = nx
		_G.GuiPositionY = ny
		return
	end

	if not resizing and win and win.Parent then
		local zone = checkResizeZones(mx, my)
		if zone then
			setCursor(zone.cur)
		else
			local a = win.AbsolutePosition
			local s = win.AbsoluteSize
			if mx >= a.X and mx <= a.X + s.X and my >= a.Y and my <= a.Y + 48 and
				not (mx >= a.X + s.X - 50 and my >= a.Y) then
				setCursor("rbxasset://textures/Cursors/DragCursor.png")
			else
				setCursor("")
			end
		end
	end
end)

-- ═══════════════════════════════════════════════════════════
--  РЕСПАВН
-- ═══════════════════════════════════════════════════════════
player.CharacterAdded:Connect(function()
	win, hdr, gear = createGUI()
end)

-- Синхронизация
RunService.Heartbeat:Connect(function()
	if (_G.SourceMovementEnabled ~= false) ~= isEnabled then
		setEnabled(_G.SourceMovementEnabled ~= false)
	end
	if (_G.AutoBhopEnabled ~= false) ~= isAutoBhop then
		setAutoBhop(_G.AutoBhopEnabled ~= false)
	end
end)

game:BindToClose(saveSettings)
