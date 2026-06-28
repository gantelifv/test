-- SourceMovement.lua (BHOP + SURF + GUI) — Оптимизировано для инжекторов

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local gui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
local camera = workspace.CurrentCamera

-- ============================================================================
--  НАСТРОЙКИ
-- ============================================================================
local SETTINGS = {
	SourceMovementEnabled = false,
	AutoBhopEnabled = false,
	SurfEnabled = false,
	ShowSpeed = false,
	HideGuiKey = "F1",
	GuiPositionX = 100,
	GuiPositionY = 100,
	GuiSizeX = 280,
	GuiSizeY = 240,
	SavedMovementSettings = nil
}

if _G.SavedMovementSettings then
	pcall(function()
		local data = HttpService:JSONDecode(_G.SavedMovementSettings)
		for k, v in pairs(data) do
			if SETTINGS[k] ~= nil then SETTINGS[k] = v end
		end
	end)
end

local function saveSettings()
	pcall(function()
		local data = {
			SourceMovementEnabled = SETTINGS.SourceMovementEnabled,
			AutoBhopEnabled = SETTINGS.AutoBhopEnabled,
			HideGuiKey = SETTINGS.HideGuiKey,
			GuiPositionX = SETTINGS.GuiPositionX,
			GuiPositionY = SETTINGS.GuiPositionY,
			GuiSizeX = SETTINGS.GuiSizeX,
			GuiSizeY = SETTINGS.GuiSizeY
		}
		_G.SavedMovementSettings = HttpService:JSONEncode(data)
	end)
end

-- ============================================================================
--  ЦВЕТА GUI
-- ============================================================================
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

-- ============================================================================
--  ПЕРЕМЕННЫЕ GUI
-- ============================================================================
local isEnabled = SETTINGS.SourceMovementEnabled
local isAutoBhop = SETTINGS.AutoBhopEnabled
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
local settingsOpen = false
local savedCanvasY = 0
local savedSettingsCanvasY = 0
local speedPanel = nil
local enBtn, abBtn, abLbl, sfBtn, sfLbl

-- ============================================================================
--  НАСТРОЙКИ ФИЗИКИ
-- ============================================================================
local CFG = {
	GroundSpeed   = 21, GroundAccel = 10, Friction = 6, StopSpeed = 2,
	JumpVelocity = 45, FallGravityScale = 0.60,
	AirAccelerate = 50, AirWishSpeed = 1.5,
	CamRotateSpeed = 20, GroundRotateSpeed = 9,
	SurfEnabled = SETTINGS.SurfEnabled,
	SurfSlopeAngle = 5, SurfAccel = 22,
}

-- ============================================================================
--  СОСТОЯНИЕ ФИЗИКИ
-- ============================================================================
local character, humanoid, rootPart
local vel = Vector3.zero
local isGrounded = false
local wasGrounded = false
local jumpQueued = false
local justJumped = false
local spaceWasDown = false
local hasJumpedInAir = false
local isSurfing = false
local jumpBuffer = 0
local surfTime = 0
local wasSourceEnabled = true

local rayParams = nil
local function getRayParams()
	if not rayParams then
		rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	if character then
		rayParams.FilterDescendantsInstances = {character}
	end
	return rayParams
end

-- ============================================================================
--  ФУНКЦИИ ФИЗИКИ
-- ============================================================================
local function initCharacter()
	if not humanoid or not rootPart then return end
	pcall(function()
		humanoid.WalkSpeed = 0.01
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		rootPart.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 0, 0)
	end)
end

local function restoreDefaultPhysics()
	if not humanoid or not rootPart then return end
	pcall(function()
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.AutoRotate = true
		rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 0, 0)
	end)
	vel = Vector3.zero
	isGrounded = false
	wasGrounded = false
	jumpQueued = false
	justJumped = false
	spaceWasDown = false
	hasJumpedInAir = false
	isSurfing = false
	jumpBuffer = 0
	surfTime = 0
end

local function getCameraAxes()
	local cam = workspace.CurrentCamera or camera
	if not cam then return Vector3.new(1,0,0), Vector3.new(0,0,1) end
	local cf = cam.CFrame
	local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	if fwd.Magnitude > 0.001 then fwd = fwd.Unit end
	if right.Magnitude > 0.001 then right = right.Unit end
	return fwd, right
end

local function getWishDir()
	local fwd, right = getCameraAxes()
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + fwd end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - fwd end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
	if dir.Magnitude > 0.001 then return dir.Unit end
	return Vector3.zero
end

local function isShiftLocked()
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function isFirstPerson()
	local cam = workspace.CurrentCamera or camera
	local head = character and character:FindFirstChild("Head")
	if not head or not cam then return false end
	return (cam.CFrame.Position - head.Position).Magnitude < 1.5
end

local function shouldFollowCam()
	return isShiftLocked() or isFirstPerson()
end

local function checkGrounded()
	if not rootPart then return false end
	local params = getRayParams()
	local rayResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -3.2, 0), params)
	if rayResult then
		local normal = rayResult.Normal
		local up = Vector3.new(0, 1, 0)
		local dot = normal:Dot(up)
		if dot < 0.7 then return false end
		return true
	end
	return false
end

local function checkSurf()
	if not rootPart then return false, nil, nil end
	local params = getRayParams()
	local rayResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -3.5, 0), params)
	if rayResult then
		local normal = rayResult.Normal
		local up = Vector3.new(0, 1, 0)
		local dot = math.abs(normal:Dot(up))
		local angleDeg = math.deg(math.acos(dot))
		if angleDeg > CFG.SurfSlopeAngle and angleDeg <= 85 then
			return true, normal, rayResult.Position
		end
	end
	return false, nil, nil
end

local function accelerate(curVel, wishDir, wishSpeed, accel, dt)
	if wishDir.Magnitude < 0.001 then return curVel end
	local hVel = Vector3.new(curVel.X, 0, curVel.Z)
	local currSp = hVel:Dot(wishDir)
	local speed = hVel.Magnitude
	local dynamicWish = wishSpeed + (speed * 0.1)
	local addSp = dynamicWish - currSp
	if addSp <= 0 then return curVel end
	local accelSp = math.min(accel * dynamicWish * dt, addSp)
	return curVel + Vector3.new(wishDir.X, 0, wishDir.Z) * accelSp
end

local function applyFriction(curVel, dt)
	local hVel = Vector3.new(curVel.X, 0, curVel.Z)
	local speed = hVel.Magnitude
	if speed < 0.05 then return Vector3.new(0, curVel.Y, 0) end
	local control = math.max(speed, CFG.StopSpeed)
	local drop = control * CFG.Friction * dt
	local newSpeed = math.max(speed - drop, 0)
	return Vector3.new(curVel.X * (newSpeed / speed), curVel.Y, curVel.Z * (newSpeed / speed))
end

local function smoothRotate(currentLook, targetDir, dt, rotateSpeed)
	if targetDir.Magnitude < 0.001 then return currentLook end
	local alpha = math.min(rotateSpeed * dt, 1)
	local result = currentLook:Lerp(targetDir, alpha)
	if result.Magnitude < 0.001 then return currentLook end
	return result.Unit
end

-- ============================================================================
--  ПОДКЛЮЧЕНИЕ ПЕРСОНАЖА
-- ============================================================================
local function onCharacterAdded(newChar)
	if not newChar then return end
	character = newChar
	humanoid = newChar:FindFirstChildOfClass("Humanoid") or newChar:WaitForChild("Humanoid", 5)
	rootPart = newChar:FindFirstChild("HumanoidRootPart") or newChar:WaitForChild("HumanoidRootPart", 5)
	camera = workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
	if isEnabled then initCharacter() end
	vel = Vector3.zero
	isGrounded = false
	wasGrounded = false
	jumpQueued = false
	justJumped = false
	spaceWasDown = false
	hasJumpedInAir = false
	isSurfing = false
	jumpBuffer = 0
	surfTime = 0
end

if player.Character then
	pcall(onCharacterAdded, player.Character)
end

pcall(function()
	player.CharacterAdded:Connect(function(char)
		task.wait(0.1)
		onCharacterAdded(char)
	end)
end)

-- ============================================================================
--  ВВОД
-- ============================================================================
UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.Space then
		spaceWasDown = true
		jumpQueued = true
		jumpBuffer = 0.25
	end
end)

UserInputService.InputEnded:Connect(function(inp)
	if inp.KeyCode == Enum.KeyCode.Space then
		spaceWasDown = false
		jumpQueued = false
	end
end)

-- ============================================================================
--  ГЛАВНЫЙ ЦИКЛ ФИЗИКИ
-- ============================================================================
RunService.Heartbeat:Connect(function(dt)
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	local sourceEnabled = SETTINGS.SourceMovementEnabled

	if sourceEnabled ~= wasSourceEnabled then
		wasSourceEnabled = sourceEnabled
		if sourceEnabled then initCharacter(); vel = Vector3.zero
		else restoreDefaultPhysics() end
	end

	if not sourceEnabled then return end

	CFG.SurfEnabled = SETTINGS.SurfEnabled

	if jumpBuffer > 0 then jumpBuffer = jumpBuffer - dt end

	wasGrounded = isGrounded
	isGrounded = checkGrounded()
	justJumped = false

	local wishDir = getWishDir()
	local followCam = shouldFollowCam()
	local fwd, right = getCameraAxes()
	local hasMovement = wishDir.Magnitude > 0.001

	-- Поворот
	local currentLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if currentLook.Magnitude > 0.001 then currentLook = currentLook.Unit end
	local newLook = currentLook
	if followCam then
		if fwd.Magnitude > 0.001 then newLook = smoothRotate(currentLook, fwd, dt, CFG.CamRotateSpeed) end
	elseif hasMovement then
		local dotProduct = currentLook:Dot(wishDir)
		if dotProduct < -0.1 then newLook = smoothRotate(currentLook, wishDir, dt, CFG.GroundRotateSpeed)
		else newLook = smoothRotate(currentLook, wishDir, dt, CFG.GroundRotateSpeed * 0.8) end
	end
	if newLook.Magnitude > 0.001 then
		pcall(function()
			rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.lookAt(Vector3.zero, newLook)
		end)
	end
	pcall(function() rootPart.AssemblyAngularVelocity = Vector3.zero end)

	-- Приземление
	if isGrounded and not wasGrounded then
		vel = Vector3.new(vel.X, 0, vel.Z)
		hasJumpedInAir = false
		isSurfing = false
		surfTime = 0
	end

	-- Прыжок
	local autoBhopOn = SETTINGS.AutoBhopEnabled
	local wantJump = false
	if autoBhopOn then wantJump = spaceWasDown
	elseif jumpQueued and not hasJumpedInAir then wantJump = true end

	if isGrounded and wantJump then
		vel = Vector3.new(vel.X, CFG.JumpVelocity, vel.Z)
		isGrounded = false; isSurfing = false; jumpQueued = false
		justJumped = true; hasJumpedInAir = true
		pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end

	if isSurfing and (jumpQueued or jumpBuffer > 0) then
		vel = vel + Vector3.new(0, CFG.JumpVelocity * 1.6, 0)
		isGrounded = false; isSurfing = false; jumpQueued = false
		jumpBuffer = 0; justJumped = true; hasJumpedInAir = true; surfTime = 0
		pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end

	-- Физика на земле
	if isGrounded and not justJumped then
		vel = applyFriction(vel, dt)
		vel = accelerate(vel, wishDir, CFG.GroundSpeed, CFG.GroundAccel, dt)
		vel = Vector3.new(vel.X, 0, vel.Z)
	end

	-- Физика в воздухе
	if not isGrounded then
		local gravScale = (vel.Y < 0) and CFG.FallGravityScale or 1.0
		vel = Vector3.new(vel.X, vel.Y - workspace.Gravity * gravScale * dt, vel.Z)
		if not justJumped then vel = accelerate(vel, wishDir, CFG.AirWishSpeed, CFG.AirAccelerate, dt) end
		if vel.Y < -80 then vel = Vector3.new(vel.X, -80, vel.Z) end
		if vel.Y > 200 then vel = Vector3.new(vel.X, 200, vel.Z) end
		if not isSurfing and not hasJumpedInAir then
			local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpeed > 30 then vel = vel * (1 - 1.5 * dt) end
		end
	end

	-- Сёрф
	if CFG.SurfEnabled and not isGrounded then
		local isSurfNow, surfNormal, surfPos = checkSurf()
		if isSurfNow and surfNormal then
			isSurfing = true; hasJumpedInAir = false; surfTime = surfTime + dt
			local dot = vel:Dot(surfNormal)
			if dot < 0 then vel = vel - surfNormal * dot end
			local surfTangent = surfNormal:Cross(Vector3.new(0, 1, 0))
			if surfTangent.Magnitude < 0.01 then surfTangent = surfNormal:Cross(Vector3.new(1, 0, 0)) end
			surfTangent = surfTangent.Unit
			local slopeDown = Vector3.new(0, -1, 0) - surfNormal * Vector3.new(0, -1, 0):Dot(surfNormal)
			if slopeDown.Magnitude > 0.01 then
				slopeDown = slopeDown.Unit
				vel = vel + slopeDown * (1 + surfTime * 3) * dt
			end
			if hasMovement then vel = vel + surfTangent * wishDir:Dot(surfTangent) * CFG.SurfAccel * dt
			elseif vel.Magnitude < 30 then vel = vel + surfTangent * 5 * dt end
			if Vector3.new(vel.X, 0, vel.Z).Magnitude > 90 then vel = vel * 0.997 end
			pcall(function()
				local targetY = surfPos.Y + 3
				local diffY = targetY - rootPart.Position.Y
				vel = Vector3.new(vel.X, diffY * (1 / dt) * 0.2, vel.Z)
			end)
		else isSurfing = false; surfTime = 0 end
	end

	-- Анимация
	local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	pcall(function()
		if isSurfing then humanoid.WalkSpeed = 0.01
		elseif isGrounded then humanoid.WalkSpeed = (hSpeed < 0.5) and 0.01 or math.min(hSpeed / CFG.GroundSpeed * 16, 16)
		else humanoid.WalkSpeed = 0.01 end
	end)

	SETTINGS.CurrentSpeed = vel
	SETTINGS.CurrentHSpeed = hSpeed
	SETTINGS.CurrentVSpeed = math.abs(vel.Y)

	-- Применение
	pcall(function()
		if isGrounded then
			if wasGrounded and hSpeed < 0.5 then rootPart.AssemblyLinearVelocity = Vector3.zero
			elseif not wasGrounded then rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.min(vel.Y, -4), vel.Z)
			else rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z) end
		else rootPart.AssemblyLinearVelocity = vel end
	end)
end)

-- ============================================================================
--  ФУНКЦИИ GUI
-- ============================================================================
local function setCursor(id)
	pcall(function() mouse.Icon = id end)
end

local function setAutoBhop(state)
	isAutoBhop = state
	SETTINGS.AutoBhopEnabled = state
	if abBtn and abBtn.Parent then abBtn.BackgroundColor3 = state and C.On or C.Off end
	saveSettings()
end

local function setEnabled(state)
	isEnabled = state
	SETTINGS.SourceMovementEnabled = state
	if enBtn and enBtn.Parent then enBtn.BackgroundColor3 = state and C.On or C.Off end
	if not state then
		autoBhopWasOnBeforeDisable = isAutoBhop
		if abLbl then abLbl.TextColor3 = C.TxtDisabled end
		if abBtn then abBtn.Active = false; abBtn.BackgroundColor3 = isAutoBhop and Color3.fromRGB(40, 100, 40) or C.TxtDisabled end
		if sfLbl then sfLbl.TextColor3 = C.TxtDisabled end
		if sfBtn then sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and Color3.fromRGB(40, 100, 40) or C.TxtDisabled end
	else
		if abLbl then abLbl.TextColor3 = C.Txt end
		if abBtn then pcall(function() abBtn.Active = true; abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off end) end
		if sfLbl then sfLbl.TextColor3 = C.Txt end
		if sfBtn then pcall(function() sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and C.On or C.Off end) end
	end
	saveSettings()
end

-- ============================================================================
--  СОЗДАНИЕ GUI
-- ============================================================================
local function createGUI()
	if not gui then gui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5) end
	if not gui then return end

	pcall(function() local old = gui:FindFirstChild("SourceMovementGUI"); if old then old:Destroy() end end)

	local sg; local success = pcall(function()
		sg = Instance.new("ScreenGui"); sg.Name = "SourceMovementGUI"; sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.Parent = gui
	end)
	if not success or not sg then return end

	local win = Instance.new("Frame")
	win.Name = "Window"; win.Size = UDim2.new(0, SETTINGS.GuiSizeX or 280, 0, SETTINGS.GuiSizeY or 240)
	win.Position = UDim2.new(0, SETTINGS.GuiPositionX or 100, 0, SETTINGS.GuiPositionY or 100)
	win.BackgroundColor3 = C.Bg; win.BorderSizePixel = 0; win.Active = true; win.ClipsDescendants = true; win.Parent = sg
	Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)
	local winStroke = Instance.new("UIStroke", win); winStroke.Color = C.Bdr; winStroke.Thickness = 1.5

	-- Шапка
	local hdr = Instance.new("Frame", win); hdr.Size = UDim2.new(1, 0, 0, 48); hdr.BackgroundColor3 = C.Hdr; hdr.BorderSizePixel = 0; hdr.Active = true
	Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 12)
	local hdrFix = Instance.new("Frame", hdr); hdrFix.Size = UDim2.new(1, 0, 0, 12); hdrFix.Position = UDim2.new(0, 0, 1, -12); hdrFix.BackgroundColor3 = C.Hdr; hdrFix.BorderSizePixel = 0
	local div = Instance.new("Frame", win); div.Size = UDim2.new(1, 0, 0, 1); div.Position = UDim2.new(0, 0, 0, 48); div.BackgroundColor3 = C.Bdr; div.BorderSizePixel = 0
	local title = Instance.new("TextLabel", hdr); title.Size = UDim2.new(1, -56, 1, 0); title.Position = UDim2.new(0, 14, 0, 0); title.BackgroundTransparency = 1; title.Text = "Source\nMovement"; title.TextColor3 = C.Txt; title.TextSize = 15; title.Font = Enum.Font.GothamBold; title.TextXAlignment = Enum.TextXAlignment.Left; title.TextYAlignment = Enum.TextYAlignment.Center
	local gear = Instance.new("TextButton", hdr); gear.Size = UDim2.new(0, 36, 0, 36); gear.Position = UDim2.new(1, -44, 0, 6); gear.BackgroundColor3 = C.Btn; gear.BorderSizePixel = 0; gear.Text = "✱"; gear.TextSize = 18; gear.TextColor3 = C.Txt2; gear.Font = Enum.Font.GothamBold; Instance.new("UICorner", gear).CornerRadius = UDim.new(0, 8)

	-- Тело
	local body = Instance.new("ScrollingFrame", win); body.Size = UDim2.new(1, -8, 1, -49); body.Position = UDim2.new(0, 4, 0, 49); body.BackgroundTransparency = 1; body.BorderSizePixel = 0; body.CanvasSize = UDim2.new(0, 0, 0, 250); body.ScrollBarThickness = 4; body.ScrollingDirection = Enum.ScrollingDirection.Y; body.CanvasPosition = Vector2.new(0, savedCanvasY)
	pcall(function() body:GetPropertyChangedSignal("CanvasPosition"):Connect(function() savedCanvasY = body.CanvasPosition.Y end) end)

	-- Enabled
	local enRow = Instance.new("Frame", body); enRow.Size = UDim2.new(1, -24, 0, 40); enRow.Position = UDim2.new(0, 12, 0, 10); enRow.BackgroundTransparency = 1
	local enLabel = Instance.new("TextLabel", enRow); enLabel.Size = UDim2.new(1, -52, 1, 0); enLabel.BackgroundTransparency = 1; enLabel.Text = "Enabled (Bhop)"; enLabel.TextColor3 = C.Txt; enLabel.TextSize = 17; enLabel.Font = Enum.Font.Gotham; enLabel.TextXAlignment = Enum.TextXAlignment.Left; enLabel.TextYAlignment = Enum.TextYAlignment.Center
	enBtn = Instance.new("TextButton", enRow); enBtn.Size = UDim2.new(0, 36, 0, 36); enBtn.Position = UDim2.new(1, -36, 0, 2); enBtn.BackgroundColor3 = isEnabled and C.On or C.Off; enBtn.BorderSizePixel = 0; enBtn.Text = ""; Instance.new("UICorner", enBtn).CornerRadius = UDim.new(0, 7)

	-- Auto Bhop
	local abRow = Instance.new("Frame", body); abRow.Size = UDim2.new(1, -24, 0, 40); abRow.Position = UDim2.new(0, 12, 0, 60); abRow.BackgroundTransparency = 1
	local branchLine = Instance.new("Frame", abRow); branchLine.Size = UDim2.new(0, 1, 0, 22); branchLine.Position = UDim2.new(0, 22, 0, -15); branchLine.BackgroundColor3 = Color3.fromRGB(77, 77, 77); branchLine.BorderSizePixel = 0
	abLbl = Instance.new("TextLabel", abRow); abLbl.Size = UDim2.new(1, -52, 1, 0); abLbl.Position = UDim2.new(0, 14, 0, 0); abLbl.BackgroundTransparency = 1; abLbl.Text = "Auto Bhop"; abLbl.TextColor3 = C.Txt; abLbl.TextSize = 17; abLbl.Font = Enum.Font.Gotham; abLbl.TextXAlignment = Enum.TextXAlignment.Left; abLbl.TextYAlignment = Enum.TextYAlignment.Center
	abBtn = Instance.new("TextButton", abRow); abBtn.Size = UDim2.new(0, 36, 0, 36); abBtn.Position = UDim2.new(1, -36, 0, 2); abBtn.BorderSizePixel = 0; abBtn.Text = ""; Instance.new("UICorner", abBtn).CornerRadius = UDim.new(0, 7)
	if not isEnabled and autoBhopWasOnBeforeDisable then abBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 40) else abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off end
	if not isEnabled then abLbl.TextColor3 = C.TxtDisabled; abBtn.Active = false; abBtn.BackgroundColor3 = autoBhopWasOnBeforeDisable and Color3.fromRGB(40, 100, 40) or C.TxtDisabled
	else abLbl.TextColor3 = C.Txt; abBtn.Active = true; abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off end

	-- Surf
	local sfRow = Instance.new("Frame", body); sfRow.Size = UDim2.new(1, -24, 0, 40); sfRow.Position = UDim2.new(0, 12, 0, 110); sfRow.BackgroundTransparency = 1
	local sfBranchLine = Instance.new("Frame", sfRow); sfBranchLine.Size = UDim2.new(0, 1, 0, 22); sfBranchLine.Position = UDim2.new(0, 22, 0, -15); sfBranchLine.BackgroundColor3 = Color3.fromRGB(77, 77, 77); sfBranchLine.BorderSizePixel = 0
	sfLbl = Instance.new("TextLabel", sfRow); sfLbl.Size = UDim2.new(1, -52, 1, 0); sfLbl.Position = UDim2.new(0, 14, 0, 0); sfLbl.BackgroundTransparency = 1; sfLbl.Text = "Surf"; sfLbl.TextColor3 = C.Txt; sfLbl.TextSize = 17; sfLbl.Font = Enum.Font.Gotham; sfLbl.TextXAlignment = Enum.TextXAlignment.Left; sfLbl.TextYAlignment = Enum.TextYAlignment.Center
	sfBtn = Instance.new("TextButton", sfRow); sfBtn.Size = UDim2.new(0, 36, 0, 36); sfBtn.Position = UDim2.new(1, -36, 0, 2); sfBtn.BorderSizePixel = 0; sfBtn.Text = ""; Instance.new("UICorner", sfBtn).CornerRadius = UDim.new(0, 7)
	if not isEnabled then sfLbl.TextColor3 = C.TxtDisabled; sfBtn.Active = false; sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and Color3.fromRGB(40, 100, 40) or C.TxtDisabled
	else sfLbl.TextColor3 = C.Txt; sfBtn.Active = true; sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and C.On or C.Off end

	-- ShowSpeed
	local speedToggleRow = Instance.new("Frame", body); speedToggleRow.Size = UDim2.new(1, -24, 0, 40); speedToggleRow.Position = UDim2.new(0, 12, 0, 160); speedToggleRow.BackgroundTransparency = 1
	local speedToggleLabel = Instance.new("TextLabel", speedToggleRow); speedToggleLabel.Size = UDim2.new(1, -52, 1, 0); speedToggleLabel.BackgroundTransparency = 1; speedToggleLabel.Text = "ShowSpeed"; speedToggleLabel.TextColor3 = C.Txt; speedToggleLabel.TextSize = 17; speedToggleLabel.Font = Enum.Font.Gotham; speedToggleLabel.TextXAlignment = Enum.TextXAlignment.Left; speedToggleLabel.TextYAlignment = Enum.TextYAlignment.Center
	local speedToggleBtn = Instance.new("TextButton", speedToggleRow); speedToggleBtn.Size = UDim2.new(0, 36, 0, 36); speedToggleBtn.Position = UDim2.new(1, -36, 0, 2); speedToggleBtn.BackgroundColor3 = SETTINGS.ShowSpeed and C.On or C.Off; speedToggleBtn.BorderSizePixel = 0; speedToggleBtn.Text = ""; Instance.new("UICorner", speedToggleBtn).CornerRadius = UDim.new(0, 7)
	speedToggleBtn.MouseButton1Click:Connect(function() SETTINGS.ShowSpeed = not SETTINGS.ShowSpeed; speedToggleBtn.BackgroundColor3 = SETTINGS.ShowSpeed and C.On or C.Off; if speedPanel then speedPanel.Visible = SETTINGS.ShowSpeed end end)

	-- Логика кнопок
	enBtn.MouseButton1Click:Connect(function() setEnabled(not isEnabled) end)
	abBtn.MouseButton1Click:Connect(function() if abBtn.Active then setAutoBhop(not isAutoBhop) end end)
	sfBtn.MouseButton1Click:Connect(function() if isEnabled then SETTINGS.SurfEnabled = not SETTINGS.SurfEnabled; sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and C.On or C.Off; saveSettings() end end)

	-- Настройки
	local settingsPage = Instance.new("ScrollingFrame", win); settingsPage.Size = UDim2.new(1, -8, 1, -49); settingsPage.Position = UDim2.new(0, 4, 0, 49); settingsPage.BackgroundColor3 = C.Bg; settingsPage.BorderSizePixel = 0; settingsPage.Visible = false; settingsPage.CanvasSize = UDim2.new(0, 0, 0, 400); settingsPage.ScrollBarThickness = 4; settingsPage.ScrollingDirection = Enum.ScrollingDirection.Y; settingsPage.CanvasPosition = Vector2.new(0, savedSettingsCanvasY); Instance.new("UICorner", settingsPage).CornerRadius = UDim.new(0, 12)
	pcall(function() settingsPage:GetPropertyChangedSignal("CanvasPosition"):Connect(function() savedSettingsCanvasY = settingsPage.CanvasPosition.Y end) end)

	local settingsTitle = Instance.new("TextLabel", settingsPage); settingsTitle.Size = UDim2.new(1, -20, 0, 30); settingsTitle.Position = UDim2.new(0, 10, 0, 10); settingsTitle.BackgroundTransparency = 1; settingsTitle.Text = "- - Binds - -"; settingsTitle.TextColor3 = C.Txt; settingsTitle.TextSize = 17; settingsTitle.Font = Enum.Font.Gotham; settingsTitle.TextXAlignment = Enum.TextXAlignment.Center

	-- Hide GUI Bind
	local hideGuiRow = Instance.new("Frame", settingsPage); hideGuiRow.Size = UDim2.new(1, -20, 0, 35); hideGuiRow.Position = UDim2.new(0, 10, 0, 50); hideGuiRow.BackgroundTransparency = 1
	local hideGuiLabel = Instance.new("TextLabel", hideGuiRow); hideGuiLabel.Size = UDim2.new(0, 120, 1, 0); hideGuiLabel.BackgroundTransparency = 1; hideGuiLabel.Text = "Hide GUI"; hideGuiLabel.TextColor3 = C.Txt; hideGuiLabel.TextSize = 17; hideGuiLabel.Font = Enum.Font.Gotham; hideGuiLabel.TextXAlignment = Enum.TextXAlignment.Left; hideGuiLabel.TextYAlignment = Enum.TextYAlignment.Center
	local hideGuiBind = Instance.new("TextButton", hideGuiRow); hideGuiBind.Size = UDim2.new(0, 50, 0, 28); hideGuiBind.Position = UDim2.new(1, -50, 0, 3); hideGuiBind.BackgroundColor3 = C.Btn; hideGuiBind.BorderSizePixel = 0; hideGuiBind.Text = SETTINGS.HideGuiKey or "F1"; hideGuiBind.TextColor3 = C.Txt; hideGuiBind.TextSize = 14; hideGuiBind.Font = Enum.Font.GothamBold; Instance.new("UICorner", hideGuiBind).CornerRadius = UDim.new(0, 6)
	local clearBind = Instance.new("TextButton", hideGuiRow); clearBind.Size = UDim2.new(0, 28, 0, 28); clearBind.Position = UDim2.new(1, -84, 0, 3); clearBind.BackgroundColor3 = C.Btn; clearBind.BorderSizePixel = 0; clearBind.Text = "×"; clearBind.TextColor3 = C.Txt; clearBind.TextSize = 18; clearBind.Font = Enum.Font.GothamBold; Instance.new("UICorner", clearBind).CornerRadius = UDim.new(0, 6)
	clearBind.MouseButton1Click:Connect(function() SETTINGS.HideGuiKey = ""; hideGuiBind.Text = ""; saveSettings() end)

	local versionLabel = Instance.new("TextLabel", settingsPage); versionLabel.Size = UDim2.new(1, -20, 0, 20); versionLabel.Position = UDim2.new(0, 10, 0, 370); versionLabel.BackgroundTransparency = 1; versionLabel.Text = "Source Movement v1.0.0"; versionLabel.TextColor3 = Color3.fromRGB(100, 100, 100); versionLabel.TextSize = 12; versionLabel.Font = Enum.Font.Gotham; versionLabel.TextXAlignment = Enum.TextXAlignment.Center

	local listeningForBind = false
	hideGuiBind.MouseButton1Click:Connect(function() listeningForBind = true; hideGuiBind.Text = "..." end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if listeningForBind and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
			SETTINGS.HideGuiKey = input.KeyCode.Name; hideGuiBind.Text = SETTINGS.HideGuiKey; listeningForBind = false; saveSettings()
		elseif not listeningForBind and SETTINGS.HideGuiKey and SETTINGS.HideGuiKey ~= "" and not gameProcessed then
			if input.KeyCode.Name == SETTINGS.HideGuiKey then sg.Enabled = not sg.Enabled end
		end
	end)

	gear.MouseButton1Click:Connect(function() settingsOpen = not settingsOpen; body.Visible = not settingsOpen; settingsPage.Visible = settingsOpen end)

	-- Перетаскивание
	hdr.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = Vector2.new(input.Position.X, input.Position.Y); pcall(function() winStart = win.AbsolutePosition end) end end)

	-- Hover эффекты
	enBtn.MouseEnter:Connect(function() pcall(function() enBtn.BackgroundColor3 = (isEnabled and C.On or C.Off):Lerp(Color3.new(1,1,1), 0.15) end) end)
	enBtn.MouseLeave:Connect(function() pcall(function() enBtn.BackgroundColor3 = isEnabled and C.On or C.Off end) end)
	abBtn.MouseEnter:Connect(function() if abBtn.Active then pcall(function() abBtn.BackgroundColor3 = (isAutoBhop and C.On or C.Off):Lerp(Color3.new(1,1,1), 0.15) end) end end)
	abBtn.MouseLeave:Connect(function() if abBtn.Active then pcall(function() abBtn.BackgroundColor3 = isAutoBhop and C.On or C.Off end) end end)
	sfBtn.MouseEnter:Connect(function() if sfBtn.Active then pcall(function() sfBtn.BackgroundColor3 = (SETTINGS.SurfEnabled and C.On or C.Off):Lerp(Color3.new(1,1,1), 0.15) end) end end)
	sfBtn.MouseLeave:Connect(function() if sfBtn.Active then pcall(function() sfBtn.BackgroundColor3 = SETTINGS.SurfEnabled and C.On or C.Off end) end end)
	gear.MouseEnter:Connect(function() pcall(function() gear.BackgroundColor3 = C.BtnH end) end)
	gear.MouseLeave:Connect(function() pcall(function() gear.BackgroundColor3 = C.Btn end) end)

	-- Счётчик скорости
	local screenWidth = (sg and sg.AbsoluteSize.X > 0) and sg.AbsoluteSize.X or 1920
	local screenHeight = (sg and sg.AbsoluteSize.Y > 0) and sg.AbsoluteSize.Y or 1080
	speedPanel = Instance.new("TextButton"); speedPanel.Size = UDim2.new(0, 180, 0, 80); speedPanel.Position = UDim2.new(0, SETTINGS.SpeedPanelX or (screenWidth - 190), 0, SETTINGS.SpeedPanelY or (screenHeight - 90)); speedPanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0); speedPanel.BackgroundTransparency = 0.5; speedPanel.BorderSizePixel = 0; speedPanel.Text = ""; speedPanel.ZIndex = 200; speedPanel.Visible = SETTINGS.ShowSpeed; speedPanel.Parent = sg; Instance.new("UICorner", speedPanel).CornerRadius = UDim.new(0, 8)

	local spDragging = false; local spDragStart = nil; local spStart = nil
	speedPanel.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then spDragging = true; spDragStart = Vector2.new(input.Position.X, input.Position.Y); pcall(function() spStart = speedPanel.AbsolutePosition end) end end)
	UserInputService.InputChanged:Connect(function(input) if spDragging and input.UserInputType == Enum.UserInputType.MouseMovement then local delta = Vector2.new(input.Position.X, input.Position.Y) - spDragStart; local nx = spStart.X + delta.X; local ny = spStart.Y + delta.Y; speedPanel.Position = UDim2.new(0, nx, 0, ny); SETTINGS.SpeedPanelX = nx; SETTINGS.SpeedPanelY = ny end end)
	UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then spDragging = false end end)

	local speedLabel = Instance.new("TextLabel", speedPanel); speedLabel.Size = UDim2.new(1, -10, 0, 30); speedLabel.Position = UDim2.new(0, 5, 0, 5); speedLabel.BackgroundTransparency = 1; speedLabel.Text = "Speed: 0"; speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255); speedLabel.TextSize = 14; speedLabel.Font = Enum.Font.Gotham; speedLabel.TextXAlignment = Enum.TextXAlignment.Left; speedLabel.ZIndex = 201
	local hSpeedLabel = Instance.new("TextLabel", speedPanel); hSpeedLabel.Size = UDim2.new(1, -10, 0, 20); hSpeedLabel.Position = UDim2.new(0, 5, 0, 32); hSpeedLabel.BackgroundTransparency = 1; hSpeedLabel.Text = "H: 0"; hSpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200); hSpeedLabel.TextSize = 12; hSpeedLabel.Font = Enum.Font.Gotham; hSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left; hSpeedLabel.ZIndex = 201
	local vSpeedLabel = Instance.new("TextLabel", speedPanel); vSpeedLabel.Size = UDim2.new(1, -10, 0, 20); vSpeedLabel.Position = UDim2.new(0, 5, 0, 52); vSpeedLabel.BackgroundTransparency = 1; vSpeedLabel.Text = "V: 0"; vSpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200); vSpeedLabel.TextSize = 12; vSpeedLabel.Font = Enum.Font.Gotham; vSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left; vSpeedLabel.ZIndex = 201

	pcall(function()
		RunService.Heartbeat:Connect(function()
			if SETTINGS.ShowSpeed then
				local char = player.Character
				if char then
					local rp = char:FindFirstChild("HumanoidRootPart")
					if rp then
						pcall(function()
							local v = rp.AssemblyLinearVelocity
							speedLabel.Text = "Speed: " .. tostring(math.floor(v.Magnitude))
							hSpeedLabel.Text = "H: " .. tostring(math.floor(Vector3.new(v.X, 0, v.Z).Magnitude))
							vSpeedLabel.Text = "V: " .. tostring(math.floor(math.abs(v.Y)))
						end)
					end
				end
			end
		end)
	end)

	return win, hdr, gear
end

-- Создаём GUI
local win, hdr, gear = createGUI()

-- ============================================================================
--  ЗОНЫ РЕСАЙЗА
-- ============================================================================
local CORNER, EDGE, OVER = 24, 14, 8
local resizeZones = {
	{name = "RB", dir = "corner_rb", cur = "rbxasset://textures/Cursors/DragCorner.png", check = function(x, y, ax, ay, sx, sy) return x >= ax + sx - CORNER and x <= ax + sx + OVER and y >= ay + sy - CORNER and y <= ay + sy + OVER end},
	{name = "LB", dir = "corner_lb", cur = "rbxasset://textures/Cursors/DragCorner.png", check = function(x, y, ax, ay, sx, sy) return x >= ax - OVER and x <= ax + CORNER and y >= ay + sy - CORNER and y <= ay + sy + OVER end},
	{name = "RT", dir = "corner_rt", cur = "rbxasset://textures/Cursors/DragCorner.png", check = function(x, y, ax, ay, sx, sy) return x >= ax + sx - CORNER and x <= ax + sx + OVER and y >= ay + 48 - OVER and y <= ay + 48 + CORNER end},
	{name = "LT", dir = "corner_lt", cur = "rbxasset://textures/Cursors/DragCorner.png", check = function(x, y, ax, ay, sx, sy) return x >= ax - OVER and x <= ax + CORNER and y >= ay + 48 - OVER and y <= ay + 48 + CORNER end},
	{name = "R", dir = "right", cur = "rbxasset://textures/Cursors/DragHorizontal.png", check = function(x, y, ax, ay, sx, sy) if y < ay + 48 + CORNER or y > ay + sy - CORNER then return false end return x >= ax + sx - EDGE and x <= ax + sx + OVER end},
	{name = "L", dir = "left", cur = "rbxasset://textures/Cursors/DragHorizontal.png", check = function(x, y, ax, ay, sx, sy) if y < ay + 48 + CORNER or y > ay + sy - CORNER then return false end return x >= ax - OVER and x <= ax + EDGE end},
	{name = "B", dir = "bottom", cur = "rbxasset://textures/Cursors/DragVertical.png", check = function(x, y, ax, ay, sx, sy) if x < ax + CORNER or x > ax + sx - CORNER then return false end return y >= ay + sy - EDGE and y <= ay + sy + OVER end},
}

-- ============================================================================
--  ЛОГИКА РЕСАЙЗА И ПЕРЕТАСКИВАНИЯ
-- ============================================================================
local function checkResizeZones(mx, my)
	if not win or not win.Parent then return nil end
	local a, s; local success = pcall(function() a = win.AbsolutePosition; s = win.AbsoluteSize end)
	if not success or not a or not s then return nil end
	for _, z in ipairs(resizeZones) do if z.check(mx, my, a.X, a.Y, s.X, s.Y) then return z end end
	return nil
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local zone = checkResizeZones(input.Position.X, input.Position.Y)
	if zone then resizing = true; resizeDir = zone.dir; resizeStartMouse = Vector2.new(input.Position.X, input.Position.Y); if win and win.Parent then pcall(function() resizeStartSize = win.AbsoluteSize; resizeStartPos = win.AbsolutePosition end) end end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if resizing then resizing = false; resizeDir = nil; setCursor(""); saveSettings() end
		if dragging then dragging = false; saveSettings() end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local mx, my = input.Position.X, input.Position.Y
	if dragging and win and win.Parent and not resizing then
		if not dragStart or not winStart then return end
		local delta = Vector2.new(mx, my) - dragStart; local nx, ny = winStart.X + delta.X, winStart.Y + delta.Y
		win.Position = UDim2.new(0, nx, 0, ny); SETTINGS.GuiPositionX = nx; SETTINGS.GuiPositionY = ny
	elseif resizing and resizeDir and win and win.Parent then
		if not resizeStartMouse or not resizeStartSize or not resizeStartPos then return end
		local delta = Vector2.new(mx, my) - resizeStartMouse; local nw, nh = resizeStartSize.X, resizeStartSize.Y; local nx, ny = resizeStartPos.X, resizeStartPos.Y
		if resizeDir == "right" or resizeDir == "corner_rb" or resizeDir == "corner_rt" then nw = math.max(resizeStartSize.X + delta.X, MIN_W) end
		if resizeDir == "left" or resizeDir == "corner_lb" or resizeDir == "corner_lt" then nw = math.max(resizeStartSize.X - delta.X, MIN_W); nx = resizeStartPos.X + (resizeStartSize.X - nw) end
		if resizeDir == "bottom" or resizeDir == "corner_rb" or resizeDir == "corner_lb" then nh = math.max(resizeStartSize.Y + delta.Y, MIN_H) end
		if resizeDir == "corner_rt" or resizeDir == "corner_lt" then nh = math.max(resizeStartSize.Y - delta.Y, MIN_H); ny = resizeStartPos.Y + (resizeStartSize.Y - nh) end
		win.Size = UDim2.new(0, nw, 0, nh); win.Position = UDim2.new(0, nx, 0, ny)
		SETTINGS.GuiPositionX = nx; SETTINGS.GuiPositionY = ny; SETTINGS.GuiSizeX = nw; SETTINGS.GuiSizeY = nh
	elseif not resizing and win and win.Parent then
		local zone = checkResizeZones(mx, my)
		if zone then setCursor(zone.cur)
		else
			local a, s; local success = pcall(function() a = win.AbsolutePosition; s = win.AbsoluteSize end)
			if success and a and s then
				if mx >= a.X and mx <= a.X + s.X and my >= a.Y and my <= a.Y + 48 and not (mx >= a.X + s.X - 50 and my >= a.Y) then setCursor("rbxasset://textures/Cursors/DragCursor.png")
				else setCursor("") end
			else setCursor("") end
		end
	end
end)

-- ============================================================================
--  РЕСПАВН GUI
-- ============================================================================
pcall(function()
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		local wasSettingsOpen = settingsOpen
		win, hdr, gear = createGUI()
		settingsOpen = wasSettingsOpen
		if settingsOpen and win then
			local body = win:FindFirstChild("ScrollingFrame")
			local settingsPage = nil
			for _, child in ipairs(win:GetChildren()) do
				if child:IsA("ScrollingFrame") and child ~= body then settingsPage = child; break end
			end
			if body and settingsPage then body.Visible = false; settingsPage.Visible = true end
		end
	end)
end)

pcall(function() player.Destroying:Connect(saveSettings) end)
saveSettings()
