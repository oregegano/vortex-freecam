local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

local player = players.LocalPlayer
local camera = workspace.CurrentCamera

local toggleKey = Enum.KeyCode.G
local defaultSpeed = 45
local speed1 = 5
local speed2 = 250
local scrollStep = 6
local boostMult = 2.5
local sensitivity = 0.004

local moveSpeed = defaultSpeed
local active = false
local renderConn: RBXScriptConnection? = nil
local groundConn: RBXScriptConnection? = nil

local camCFrame: CFrame = CFrame.identity
local yaw = 0
local pitch = 0
local lastMousePos: Vector2? = nil

local oldCamType: Enum.CameraType? = nil
local oldMouseMode: Enum.MouseBehavior? = nil

local hiddenParts: { [BasePart]: { Transparency: number, LocalTransparencyModifier: number? } } = {}
local hiddenDecals: { [Instance]: number } = {}

local function getLocalMod(part: BasePart): number?
	local ok, val = pcall(function()
		return (part :: any).LocalTransparencyModifier
	end)
	if ok and type(val) == "number" then
		return val
	end
	return nil
end

local function setLocalMod(part: BasePart, val: number)
	pcall(function()
		(part :: any).LocalTransparencyModifier = val
	end)
end

local savedChar = {
	root = nil :: BasePart?,
	hum = nil :: Humanoid?,
	anchored = false,
	walkSpeed = 16,
	jumpPower = 50,
	jumpHeight = 7.2,
}

local function hideCharacter()
	table.clear(hiddenParts)
	table.clear(hiddenDecals)

	local char = player.Character
	if not char then return end

	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			hiddenParts[desc] = {
				Transparency = desc.Transparency,
				LocalTransparencyModifier = getLocalMod(desc),
			}
			desc.Transparency = 1
			setLocalMod(desc, 1)
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			hiddenDecals[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end
end

local function showCharacter()
	for part, state in pairs(hiddenParts) do
		if part and part.Parent then
			part.Transparency = state.Transparency
			if state.LocalTransparencyModifier ~= nil then
				setLocalMod(part, state.LocalTransparencyModifier)
			end
		end
	end
	table.clear(hiddenParts)

	for item, oldTransparency in pairs(hiddenDecals) do
		if item and item.Parent then
			(item :: any).Transparency = oldTransparency
		end
	end
	table.clear(hiddenDecals)
end

local function captureCharState()
	local char = player.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") :: BasePart?)
	local hum = char and (char:FindFirstChildOfClass("Humanoid") :: Humanoid?)

	local jp = 50
	local jh = 7.2

	if hum then
		pcall(function() jp = hum.JumpPower end)
		pcall(function() jh = hum.JumpHeight end)
	end

	savedChar = {
		root = root,
		hum = hum,
		anchored = root and root.Anchored or false,
		walkSpeed = hum and hum.WalkSpeed or 16,
		jumpPower = jp,
		jumpHeight = jh,
	}
end

local function applyFreezeNow(hum: Humanoid?, root: BasePart?)
	if hum then
		hum.WalkSpeed = 0
		local ok, useJp = pcall(function()
			return hum.UseJumpPower
		end)
		if ok and useJp then
			pcall(function() hum.JumpPower = 0 end)
		else
			pcall(function() hum.JumpHeight = 0 end)
			pcall(function() hum.JumpPower = 0 end)
		end
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	end
end

local function isOnSurface(hum: Humanoid): boolean
	local mat = Enum.Material.Plastic
	pcall(function()
		mat = hum.FloorMaterial
	end)
	if mat == Enum.Material.Plastic then
		return true
	end
	local state = Enum.HumanoidStateType.None
	pcall(function()
		state = hum:GetState()
	end)
	return state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed
end

local function freezeWhenGrounded()
	if groundConn then
		groundConn:Disconnect()
		groundConn = nil
	end

	captureCharState()
	local hum = savedChar.hum
	local root = savedChar.root
	if not hum or not root then return end

	if root then
		root.Anchored = false
	end

	if isOnSurface(hum) then
		applyFreezeNow(hum, root)
		return
	end

	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end)

	groundConn = runService.Heartbeat:Connect(function()
		if not active then
			if groundConn then
				groundConn:Disconnect()
				groundConn = nil
			end
			return
		end

		local curHum = savedChar.hum
		local curRoot = savedChar.root
		if not curHum or not curHum.Parent or curHum.Health <= 0 or not curRoot or not curRoot.Parent then
			if groundConn then
				groundConn:Disconnect()
				groundConn = nil
			end
			return
		end

		if isOnSurface(curHum) then
			if groundConn then
				groundConn:Disconnect()
				groundConn = nil
			end
			applyFreezeNow(curHum, curRoot)
		end
	end)
end

local function unfreezePlayer()
	if groundConn then
		groundConn:Disconnect()
		groundConn = nil
	end

	local hum = savedChar.hum
	local root = savedChar.root

	if root and root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = savedChar.anchored
	end

	if hum and hum.Parent and hum.Health > 0 then
		hum.WalkSpeed = savedChar.walkSpeed > 0 and savedChar.walkSpeed or 16
		local ok, useJp = pcall(function()
			return hum.UseJumpPower
		end)
		if ok and useJp then
			pcall(function()
				hum.JumpPower = savedChar.jumpPower > 0 and savedChar.jumpPower or 50
			end)
		else
			pcall(function()
				hum.JumpHeight = savedChar.jumpHeight > 0 and savedChar.jumpHeight or 7.2
			end)
			pcall(function()
				hum.JumpPower = savedChar.jumpPower > 0 and savedChar.jumpPower or 50
			end)
		end
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	savedChar.root = nil
	savedChar.hum = nil
end

local function lockMouseCenter()
	pcall(function()
		userInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)
end

local function setFreecam(enabled: boolean)
	camera = workspace.CurrentCamera
	if not camera then return end

	if enabled then
		if active then return end
		active = true

		oldCamType = camera.CameraType
		oldMouseMode = userInputService.MouseBehavior
		camera.CameraType = Enum.CameraType.Scriptable
		lockMouseCenter()

		camCFrame = camera.CFrame
		local _, yRot, xRot = camCFrame:ToEulerAnglesYXZ()
		yaw = yRot
		pitch = xRot
		lastMousePos = userInputService:GetMouseLocation()

		hideCharacter()
		freezeWhenGrounded()

		renderConn = runService.RenderStepped:Connect(function(dt: number)
			if not active then return end
			camera = workspace.CurrentCamera
			if not camera then return end

			if userInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
				lockMouseCenter()
			end

			for part in pairs(hiddenParts) do
				if part and part.Parent then
					part.Transparency = 1
					setLocalMod(part, 1)
				end
			end

			if userInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				local delta = userInputService:GetMouseDelta()
				yaw -= delta.X * sensitivity
				pitch = math.clamp(pitch - delta.Y * sensitivity, math.rad(-85), math.rad(85))
			else
				local curMouse = userInputService:GetMouseLocation()
				if lastMousePos then
					local delta = curMouse - lastMousePos
					yaw -= delta.X * sensitivity
					pitch = math.clamp(pitch - delta.Y * sensitivity, math.rad(-85), math.rad(85))
				end
				lastMousePos = curMouse
			end

			local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
			local dir = Vector3.zero

			if userInputService:IsKeyDown(Enum.KeyCode.W) then dir += rot.LookVector end
			if userInputService:IsKeyDown(Enum.KeyCode.S) then dir -= rot.LookVector end
			if userInputService:IsKeyDown(Enum.KeyCode.D) then dir += rot.RightVector end
			if userInputService:IsKeyDown(Enum.KeyCode.A) then dir -= rot.RightVector end
			if userInputService:IsKeyDown(Enum.KeyCode.E) then dir += Vector3.new(0, 1, 0) end
			if userInputService:IsKeyDown(Enum.KeyCode.Q) then dir -= Vector3.new(0, 1, 0) end

			if dir.Magnitude > 0 then
				dir = dir.Unit
				local curSpeed = moveSpeed
				if userInputService:IsKeyDown(Enum.KeyCode.LeftShift) or userInputService:IsKeyDown(Enum.KeyCode.RightShift) then
					curSpeed *= boostMult
				end
				camCFrame = CFrame.new(camCFrame.Position + dir * curSpeed * dt) * rot
			else
				camCFrame = CFrame.new(camCFrame.Position) * rot
			end

			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = camCFrame
		end)
	else
		if not active then return end
		active = false

		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end

		lastMousePos = nil

		if camera then
			camera.CameraType = oldCamType or Enum.CameraType.Custom
		end
		pcall(function()
			userInputService.MouseBehavior = oldMouseMode or Enum.MouseBehavior.Default
		end)

		oldCamType = nil
		oldMouseMode = nil

		showCharacter()
		unfreezePlayer()
	end
end

userInputService.InputChanged:Connect(function(input: InputObject, _gp: boolean)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		moveSpeed = math.clamp(moveSpeed + (input.Position.Z * scrollStep), speed1, speed2)
	end
end)

userInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if gp then return end
	if input.KeyCode == toggleKey then
		setFreecam(not active)
	end
end)

player.CharacterRemoving:Connect(function()
	table.clear(hiddenParts)
	table.clear(hiddenDecals)
	if groundConn then
		groundConn:Disconnect()
		groundConn = nil
	end
	if active then
		active = false
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		lastMousePos = nil
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		pcall(function()
			userInputService.MouseBehavior = oldMouseMode or Enum.MouseBehavior.Default
		end)
		oldCamType = nil
		oldMouseMode = nil
		savedChar.root = nil
		savedChar.hum = nil
	end
end)
