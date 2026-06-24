-- SourceBhop.lua (ФИНАЛЬНЫЙ ФИКС + SURF + UNIVERSAL LADDER + FIXED DIR + CLIMB ANIM)
-- LocalScript → StarterCharacterScripts

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")
local camera    = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════
--  ЗАГРУЗКА НАСТРОЕК
-- ═══════════════════════════════════════════════════════════
local function loadSettings()
	if _G.SourceMovementEnabled == nil then
		local success, data = pcall(function()
			if _G.SavedMovementSettings then
				return HttpService:JSONDecode(_G.SavedMovementSettings)
			end
		end)
		if success and data then
			_G.SourceMovementEnabled = data.SourceMovementEnabled
			_G.AutoBhopEnabled = data.AutoBhopEnabled
		else
			_G.SourceMovementEnabled = true
			_G.AutoBhopEnabled = false
		end
	end
end
loadSettings()

-- ═══════════════════════════════════════════════════════════
--  НАСТРОЙКИ
-- ═══════════════════════════════════════════════════════════
local CFG = {
	GroundSpeed   = 21,
	GroundAccel   = 10,
	Friction      = 6,
	StopSpeed     = 2,

	JumpVelocity     = 45,
	FallGravityScale = 0.60,

	AirAccelerate = 50,
	AirWishSpeed  = 1.5,

	CamRotateSpeed = 20,
	GroundRotateSpeed = 9,

	-- СЁРФ
	SurfEnabled = true,
	SurfSlopeAngle = 5,
	SurfAccel = 22,

	-- ЛЕСТНИЦЫ
	LadderEnabled = true,
	LadderSpeed = 30,
	LadderAccel = 50,
	LadderJumpVelocity = 60,
}

-- ═══════════════════════════════════════════════════════════
--  ИНИЦИАЛИЗАЦИЯ
-- ═══════════════════════════════════════════════════════════
local function initCharacter()
	humanoid.WalkSpeed  = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 0, 0)
end
initCharacter()

-- ═══════════════════════════════════════════════════════════
--  СОСТОЯНИЕ
-- ═══════════════════════════════════════════════════════════
local vel         = Vector3.zero
local isGrounded  = false
local wasGrounded = false
local jumpQueued  = false
local justJumped  = false
local prevVelMagnitude = 0
local spaceWasDown = false
local hasJumpedInAir = false
local isSurfing = false
local jumpBuffer = 0
local surfTime = 0
local isOnLadder = false
local ladderAwayDir = nil

-- ═══════════════════════════════════════════════════════════
--  ВВОД
-- ═══════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════
--  ВСПОМОГАТЕЛЬНЫЕ
-- ═══════════════════════════════════════════════════════════

local function getCameraAxes()
	local cf    = camera.CFrame
	local fwd   = Vector3.new(cf.LookVector.X,  0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	if fwd.Magnitude   > 0.001 then fwd   = fwd.Unit   end
	if right.Magnitude > 0.001 then right = right.Unit end
	return fwd, right
end

local function getWishDir()
	local fwd, right = getCameraAxes()
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += fwd   end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= fwd   end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += right end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= right end
	if dir.Magnitude > 0.001 then return dir.Unit end
	return Vector3.zero
end

local function isShiftLocked()
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function isFirstPerson()
	local head = character:FindFirstChild("Head")
	if not head then return false end
	return (camera.CFrame.Position - head.Position).Magnitude < 1.5
end

local function shouldFollowCam()
	return isShiftLocked() or isFirstPerson()
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function checkGrounded()
	rayParams.FilterDescendantsInstances = {character}
	local rayResult = workspace:Raycast(
		rootPart.Position,
		Vector3.new(0, -3.2, 0),
		rayParams
	)

	if rayResult then
		local normal = rayResult.Normal
		local up = Vector3.new(0, 1, 0)
		local dot = normal:Dot(up)

		if dot < 0.7 then
			return false
		end

		return true
	end

	return false
end

local function checkSurf()
	rayParams.FilterDescendantsInstances = {character}
	local rayResult = workspace:Raycast(
		rootPart.Position,
		Vector3.new(0, -3.5, 0),
		rayParams
	)

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

local function checkLadder()
	local checkDirs = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 1).Unit,
		Vector3.new(-1, 0, 1).Unit,
		Vector3.new(1, 0, -1).Unit,
		Vector3.new(-1, 0, -1).Unit,
		rootPart.CFrame.LookVector,
		-rootPart.CFrame.LookVector,
		rootPart.CFrame.RightVector,
		-rootPart.CFrame.RightVector,
	}

	for _, dir in ipairs(checkDirs) do
		rayParams.FilterDescendantsInstances = {character}
		local rayResult = workspace:Raycast(
			rootPart.Position,
			dir * 2.0,
			rayParams
		)

		if rayResult then
			local normal = rayResult.Normal
			local up = Vector3.new(0, 1, 0)
			local angle = math.deg(math.acos(math.abs(normal:Dot(up))))

			if angle > 30 and angle < 150 then
				return true, rayResult.Normal, rayResult.Position
			end
		end
	end

	return false, nil, nil
end

local function accelerate(curVel, wishDir, wishSpeed, accel, dt)
	if wishDir.Magnitude < 0.001 then return curVel end
	local hVel   = Vector3.new(curVel.X, 0, curVel.Z)
	local currSp = hVel:Dot(wishDir)

	local speed = hVel.Magnitude
	local dynamicWish = wishSpeed + (speed * 0.1)

	local addSp  = dynamicWish - currSp
	if addSp <= 0 then return curVel end
	local accelSp = math.min(accel * dynamicWish * dt, addSp)
	return curVel + Vector3.new(wishDir.X, 0, wishDir.Z) * accelSp
end

local function applyFriction(curVel, dt)
	local hVel  = Vector3.new(curVel.X, 0, curVel.Z)
	local speed = hVel.Magnitude
	if speed < 0.05 then return Vector3.new(0, curVel.Y, 0) end
	local control  = math.max(speed, CFG.StopSpeed)
	local drop     = control * CFG.Friction * dt
	local newSpeed = math.max(speed - drop, 0)
	return Vector3.new(
		curVel.X * (newSpeed / speed),
		curVel.Y,
		curVel.Z * (newSpeed / speed)
	)
end

-- ═══════════════════════════════════════════════════════════
--  ПЛАВНЫЙ ПОВОРОТ
-- ═══════════════════════════════════════════════════════════
local function smoothRotate(currentLook, targetDir, dt, rotateSpeed)
	if targetDir.Magnitude < 0.001 then return currentLook end
	local alpha = math.min(rotateSpeed * dt, 1)
	local result = currentLook:Lerp(targetDir, alpha)
	if result.Magnitude < 0.001 then return currentLook end
	return result.Unit
end

-- ═══════════════════════════════════════════════════════════
--  ВОССТАНОВЛЕНИЕ СТАНДАРТНОЙ ФИЗИКИ
-- ═══════════════════════════════════════════════════════════
local function restoreDefaultPhysics()
	humanoid.WalkSpeed  = 16
	humanoid.JumpHeight = 7.2
	humanoid.AutoRotate = true
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 0, 0)
	vel         = Vector3.zero
	isGrounded  = false
	wasGrounded = false
	jumpQueued  = false
	justJumped  = false
	spaceWasDown = false
	hasJumpedInAir = false
	isSurfing = false
	jumpBuffer = 0
	surfTime = 0
	isOnLadder = false
	ladderAwayDir = nil
end

local wasSourceEnabled = true

-- ═══════════════════════════════════════════════════════════
--  ГЛАВНЫЙ ЦИКЛ
-- ═══════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function(dt)
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	local sourceEnabled = _G.SourceMovementEnabled ~= false

	if sourceEnabled ~= wasSourceEnabled then
		wasSourceEnabled = sourceEnabled
		if sourceEnabled then
			initCharacter()
			vel = Vector3.zero
		else
			restoreDefaultPhysics()
		end
	end

	if not sourceEnabled then return end

	if jumpBuffer > 0 then
		jumpBuffer = jumpBuffer - dt
	end

	wasGrounded = isGrounded
	isGrounded  = checkGrounded()
	justJumped  = false

	local wishDir    = getWishDir()
	local followCam  = shouldFollowCam()
	local fwd, right = getCameraAxes()
	local hasMovement = wishDir.Magnitude > 0.001

	-- ── 1. ПОВОРОТ ───────────────────────────────────────
	if isOnLadder then
		if ladderAwayDir then
			if shouldFollowCam() then
				local camLook = camera.CFrame.LookVector
				local camAngle = math.atan2(camLook.X, camLook.Z)
				local cosA = math.cos(camAngle)
				local sinA = math.sin(camAngle)
				local lookDir = Vector3.new(
					ladderAwayDir.X * cosA - ladderAwayDir.Z * sinA,
					0,
					-(ladderAwayDir.X * sinA + ladderAwayDir.Z * cosA)
				)
				rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + lookDir)
			end
		end
	else
		local currentLook = Vector3.new(
			rootPart.CFrame.LookVector.X,
			0,
			rootPart.CFrame.LookVector.Z
		)
		if currentLook.Magnitude > 0.001 then
			currentLook = currentLook.Unit
		end

		local newLook = currentLook

		if followCam then
			if fwd.Magnitude > 0.001 then
				newLook = smoothRotate(currentLook, fwd, dt, CFG.CamRotateSpeed)
			end
		elseif hasMovement then
			local dotProduct = currentLook:Dot(wishDir)
			if dotProduct < -0.1 then
				newLook = smoothRotate(currentLook, wishDir, dt, CFG.GroundRotateSpeed)
			else
				newLook = smoothRotate(currentLook, wishDir, dt, CFG.GroundRotateSpeed * 0.8)
			end
		end

		if newLook.Magnitude > 0.001 then
			rootPart.CFrame = CFrame.new(rootPart.Position)
				* CFrame.lookAt(Vector3.zero, newLook)
		end
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- ── 2. ПРИЗЕМЛЕНИЕ ───────────────────────────────────
	if isGrounded and not wasGrounded then
		vel = Vector3.new(vel.X, 0, vel.Z)
		hasJumpedInAir = false
		isSurfing = false
		isOnLadder = false
		ladderAwayDir = nil
		surfTime = 0
	end

	-- ── 3. ПРЫЖОК ────────────────────────────────────────
	local autoBhopOn = _G.AutoBhopEnabled ~= false

	local wantJump = false
	if autoBhopOn then
		wantJump = spaceWasDown
	else
		if jumpQueued and not hasJumpedInAir then
			wantJump = true
		end
	end

	if isGrounded and wantJump then
		vel = Vector3.new(vel.X, CFG.JumpVelocity, vel.Z)
		isGrounded = false
		isSurfing = false
		isOnLadder = false
		ladderAwayDir = nil
		jumpQueued = false
		justJumped = true
		hasJumpedInAir = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	if isSurfing and (jumpQueued or jumpBuffer > 0) then
		vel = vel + Vector3.new(0, CFG.JumpVelocity * 1.6, 0)
		isGrounded = false
		isSurfing = false
		jumpQueued = false
		jumpBuffer = 0
		justJumped = true
		hasJumpedInAir = true
		surfTime = 0
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	if isOnLadder and (jumpQueued or jumpBuffer > 0) then
		local launchDir = rootPart.CFrame.LookVector
		vel = launchDir * CFG.LadderJumpVelocity + Vector3.new(0, CFG.LadderJumpVelocity * 0.5, 0)
		isOnLadder = false
		ladderAwayDir = nil
		jumpQueued = false
		jumpBuffer = 0
		justJumped = true
		hasJumpedInAir = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	-- ── 4. ФИЗИКА НА ЗЕМЛЕ ──────────────────────────────
	if isGrounded and not justJumped then
		vel = applyFriction(vel, dt)
		vel = accelerate(vel, wishDir, CFG.GroundSpeed, CFG.GroundAccel, dt)
		vel = Vector3.new(vel.X, 0, vel.Z)
	end

	-- ── 5. ФИЗИКА В ВОЗДУХЕ ─────────────────────────────
	if not isGrounded and not isOnLadder then
		local gravScale = (vel.Y < 0) and CFG.FallGravityScale or 1.0
		vel = Vector3.new(
			vel.X,
			vel.Y - workspace.Gravity * gravScale * dt,
			vel.Z
		)
		if not justJumped then
			vel = accelerate(vel, wishDir, CFG.AirWishSpeed, CFG.AirAccelerate, dt)
		end

		if vel.Y < -80 then
			vel = Vector3.new(vel.X, -80, vel.Z)
		end
		if vel.Y > 200 then
			vel = Vector3.new(vel.X, 200, vel.Z)
		end

		if not isSurfing and not hasJumpedInAir then
			local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpeed > 30 then
				vel = vel * (1 - 1.5 * dt)
			end
		end
	end

	if isOnLadder then
		vel = Vector3.new(vel.X, math.max(vel.Y, 0), vel.Z)
	end

	-- ── 5.5. СЁРФ ────────────────────────────────────────
	if CFG.SurfEnabled and not isGrounded and not isOnLadder then
		local isSurfNow, surfNormal, surfPos = checkSurf()

		if isSurfNow and surfNormal then
			isSurfing = true
			hasJumpedInAir = false
			surfTime = surfTime + dt

			local dot = vel:Dot(surfNormal)
			if dot < 0 then
				vel = vel - surfNormal * dot
			end

			local surfTangent = surfNormal:Cross(Vector3.new(0, 1, 0))
			if surfTangent.Magnitude < 0.01 then
				surfTangent = surfNormal:Cross(Vector3.new(1, 0, 0))
			end
			surfTangent = surfTangent.Unit

			local slopeDown = Vector3.new(0, -1, 0) - surfNormal * Vector3.new(0, -1, 0):Dot(surfNormal)
			if slopeDown.Magnitude > 0.01 then
				slopeDown = slopeDown.Unit
				local surfAccel = 1 + surfTime * 3
				vel = vel + slopeDown * surfAccel * dt
			end

			if hasMovement then
				local strafeForce = wishDir:Dot(surfTangent)
				vel = vel + surfTangent * strafeForce * CFG.SurfAccel * dt
			else
				local currentSpeed = vel.Magnitude
				if currentSpeed < 30 then
					vel = vel + surfTangent * 5 * dt
				end
			end

			local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpeed > 90 then
				vel = vel * 0.997
			end

			rootPart.Position = Vector3.new(rootPart.Position.X, surfPos.Y + 3, rootPart.Position.Z)
		else
			isSurfing = false
			surfTime = 0
		end
	end

	-- ── 5.6. ЛЕСТНИЦЫ ────────────────────────────────────
	if CFG.LadderEnabled then
		local onLadder, ladderNorm, ladderPos = checkLadder()

		if onLadder and ladderNorm and ladderPos then
			if not isOnLadder then
				isOnLadder = true
				isSurfing = false
				local away = -ladderNorm
				ladderAwayDir = Vector3.new(away.X, 0, away.Z)
				if ladderAwayDir.Magnitude > 0.01 then
					ladderAwayDir = ladderAwayDir.Unit
				end
			end

			local targetPos = ladderPos + ladderNorm * 0.3
			local currentPos = rootPart.Position
			local diff = targetPos - currentPos

			local up = Vector3.new(0, 1, 0)

			local moveUp = 0

			if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveUp = 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveUp = -1 end

			local camRight = camera.CFrame.RightVector

			local moveRight = 0
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveRight = 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveRight = -1 end

			vel = up * moveUp * CFG.LadderSpeed 
				+ camRight * moveRight * CFG.LadderSpeed * 0.5
				+ diff * 5

			if vel.Y < 0 and moveUp == 0 then
				vel = Vector3.new(vel.X, 0, vel.Z)
			end

			if moveUp == 0 and moveRight == 0 then
				rootPart.Position = Vector3.new(rootPart.Position.X, ladderPos.Y, rootPart.Position.Z)
			end

			humanoid.AutoRotate = false

		else
			if isOnLadder then
				humanoid.AutoRotate = true
			end
			isOnLadder = false
			ladderAwayDir = nil
		end
	end

	-- ── 6. УПРАВЛЕНИЕ АНИМАЦИЕЙ ──────────────────────────
	local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	if isSurfing or isOnLadder then
		humanoid.WalkSpeed = 0
	elseif isGrounded then
		if hSpeed < 0.5 then
			humanoid.WalkSpeed = 0
		else
			humanoid.WalkSpeed = math.min(hSpeed / CFG.GroundSpeed * 16, 16)
		end
	else
		humanoid.WalkSpeed = 0
	end

	prevVelMagnitude = hSpeed

	-- ── 7. ПРИМЕНЕНИЕ ────────────────────────────────────
	if isOnLadder then
		rootPart.AssemblyLinearVelocity = vel
	elseif isGrounded then
		if wasGrounded and hSpeed < 0.5 then
			rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		elseif not wasGrounded then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.min(vel.Y, -4), vel.Z)
		else
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
	else
		rootPart.AssemblyLinearVelocity = vel
	end
end)

-- ═══════════════════════════════════════════════════════════
--  RESPAWN
-- ═══════════════════════════════════════════════════════════
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid  = newChar:WaitForChild("Humanoid")
	rootPart  = newChar:WaitForChild("HumanoidRootPart")
	camera    = workspace.CurrentCamera

	if _G.SourceMovementEnabled ~= false then
		initCharacter()
	end

	vel         = Vector3.zero
	isGrounded  = false
	wasGrounded = false
	jumpQueued  = false
	justJumped  = false
	spaceWasDown = false
	hasJumpedInAir = false
	isSurfing = false
	jumpBuffer = 0
	surfTime = 0
	isOnLadder = false
	ladderAwayDir = nil
end)
