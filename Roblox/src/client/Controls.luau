--[[
	Fight controls for keyboard + mouse, gamepad and touch (mobile gets on-screen buttons automatically).

	KB+M:  LMB jab  RMB cross  Q/E hooks  Z/X uppercuts  hold CTRL body  hold SHIFT power
	       SPACE block (tap just before a punch lands = parry, CTRL+SPACE = body guard)
	       MOUSE slip / duck / lean back   C duck   F clinch   V taunt   B camera
	Pad:   X jab  Y cross  B lead hook  A rear hook  R1 uppercut  L2 body  R2 power  L1 block  right stick lean
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Util = require(Shared.Util)
local Remotes = ReplicatedStorage:WaitForChild("NeonBayRemotes")
local InputEv = Remotes:WaitForChild("Input")
local LeanEv = Remotes:WaitForChild("Lean")

local Animator = require(script.Parent.Animator)
local CameraController = require(script.Parent.CameraController)

local Controls = {}
local player = Players.LocalPlayer

local held = { block = false, body = false, power = false, duck = false }
local touchBody, touchPower = false, false
local leanAcc = Vector3.zero
local padLean = Vector2.zero
local lastLeanSend, sentLean = 0, Vector3.zero
local lastGuard = -1
Controls.getUp = { marker = 0, dir = 1, zone = 0.25, active = false }
Controls.uiOpen = false

local function myChar() return player.Character end

local function fighting()
	local c = myChar()
	if not c or not c:GetAttribute("Fighter") then return false end
	local r = c:FindFirstChild("Ring")
	return r and r.Value ~= nil
end

local function phase()
	local c = myChar()
	local r = c and c:FindFirstChild("Ring")
	return r and r.Value and r.Value:GetAttribute("Phase") or ""
end

local function send(msg) InputEv:FireServer(msg) end

local function punch(id)
	if Controls.uiOpen then return end
	local c = myChar()
	if not c then return end
	local body = held.body or touchBody
	local power = held.power or touchPower
	if fighting() then
		if phase() ~= "Fight" or c:GetAttribute("State") ~= "Fight" then return end
		if (c:GetAttribute("Act") or 0) == 0 then Animator.Predict(c, id, body, power, 1) end
	else
		Animator.Predict(c, id, body, power, 1)
	end
	send({ k = "punch", id = id, body = body, power = power })
end

local function getUpPress()
	local g = Controls.getUp
	if not g.active then return end
	local hit = math.abs(g.marker - 0.5) < g.zone * 0.5
	send({ k = "getup", hit = hit })
	g.flash = hit and 1 or -1
end

local function bind(name, fn, touchTitle, ...)
	ContextActionService:BindActionAtPriority(name, function(_, state, input)
		if state == Enum.UserInputState.Begin then fn(true, input) elseif state == Enum.UserInputState.End then fn(false, input) end
		if name == "NB_Block" or name == "NB_Jab" or name == "NB_Cross" then
			return fighting() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Pass
	end, touchTitle ~= nil, Enum.ContextActionPriority.High.Value, ...)
	if touchTitle then
		ContextActionService:SetTitle(name, touchTitle)
	end
end

function Controls.Start()
	bind("NB_Jab", function(down) if down then punch(1) end end, "JAB", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX)
	bind("NB_Cross", function(down) if down then punch(2) end end, "CROSS", Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonY)
	bind("NB_LeadHook", function(down) if down then punch(3) end end, "HOOK", Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	bind("NB_RearHook", function(down) if down then punch(4) end end, nil, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
	bind("NB_LeadUpper", function(down) if down then punch(5) end end, "UPPER", Enum.KeyCode.Z)
	bind("NB_RearUpper", function(down) if down then punch(6) end end, nil, Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
	bind("NB_Block", function(down)
		held.block = down
		if down then getUpPress() end
	end, "BLOCK", Enum.KeyCode.Space, Enum.KeyCode.ButtonL1)
	bind("NB_Body", function(down, input)
		held.body = down
		if down and input.UserInputType == Enum.UserInputType.Touch then touchBody = not touchBody end
	end, "BODY", Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonL2)
	bind("NB_Power", function(down, input)
		held.power = down
		if down and input.UserInputType == Enum.UserInputType.Touch then touchPower = not touchPower end
	end, "POWER", Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
	bind("NB_Duck", function(down) held.duck = down end, "DUCK", Enum.KeyCode.C)
	bind("NB_Clinch", function(down) if down and fighting() then send({ k = "clinch" }) end end, nil, Enum.KeyCode.F)
	bind("NB_Taunt", function(down) if down and fighting() then send({ k = "taunt" }) end end, nil, Enum.KeyCode.V)
	bind("NB_Cam", function(down) if down then CameraController.broadcast = not CameraController.broadcast end end, nil, Enum.KeyCode.B, Enum.KeyCode.ButtonSelect)

	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then padLean = Vector2.new(input.Position.X, input.Position.Y) end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local c = myChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local fight = fighting()
		if hum then
			pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not fight) end)
		end
		-- get-up minigame marker
		local g = Controls.getUp
		g.active = fight and c:GetAttribute("State") == "Down" and phase() == "Knockdown"
		if g.active then
			local ring = c.Ring.Value
			g.zone = ring:GetAttribute("GetUpZone") or 0.25
			g.marker += g.dir * dt * (1.1 + (c:GetAttribute("KD") or 0) * 0.25)
			if g.marker > 1 then g.marker, g.dir = 1, -1 elseif g.marker < 0 then g.marker, g.dir = 0, 1 end
			g.meter = ring:GetAttribute("GetUp") or 0
		end
		if not fight then
			Animator.LocalLean, Animator.LocalGuard = nil, nil
			if lastGuard ~= -1 then lastGuard = -1 end
			touchBody, touchPower = false, false
			return
		end
		-- face the opponent (we own our character's physics)
		local hrp = c:FindFirstChild("HumanoidRootPart")
		local opp = c:FindFirstChild("Opponent") and c.Opponent.Value
		local face = hrp and hrp:FindFirstChild("Facing")
		local st = c:GetAttribute("State")
		if face and opp and opp:FindFirstChild("HumanoidRootPart") and hrp then
			local look = Util.flatUnit(opp.HumanoidRootPart.Position - hrp.Position, hrp.CFrame.LookVector)
			if st == "Corner" or st == "Intro" then
				local ring = c.Ring.Value
				local canvas = ring and ring:FindFirstChild("Canvas")
				if canvas then look = Util.flatUnit(canvas.Position - hrp.Position, look) end
			end
			face.CFrame = CFrame.lookAt(Vector3.zero, look)
		end
		-- mouse lean (Undisputed-style right stick)
		local menus = phase() == "Corner" or phase() == "Result" or phase() == "KO"
		if not menus and not Controls.uiOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		local md = (not menus) and UserInputService:GetMouseDelta() or Vector2.zero
		leanAcc += Vector3.new(md.X * 0.012, 0, 0)
		if md.Y > 0 then leanAcc += Vector3.new(0, -md.Y * 0.013, 0) else leanAcc += Vector3.new(0, 0, md.Y * 0.013) end
		leanAcc = Util.moveTowardsV(leanAcc, Vector3.zero, dt * 2.6)
		leanAcc = Vector3.new(math.clamp(leanAcc.X, -1, 1), math.clamp(leanAcc.Y, -1, 0), math.clamp(leanAcc.Z, -1, 0.5))
		local lean = leanAcc
		if padLean.Magnitude > 0.2 then
			lean = Vector3.new(padLean.X, padLean.Y < 0 and padLean.Y or 0, padLean.Y > 0 and -padLean.Y or 0)
		end
		if held.duck then lean = Vector3.new(lean.X, -1, lean.Z) end
		if st ~= "Fight" then lean = Vector3.zero end
		Animator.LocalLean = lean
		local guard = (held.block and ((held.body or touchBody) and 2 or 1)) or 0
		Animator.LocalGuard = guard
		if guard ~= lastGuard then
			lastGuard = guard
			send({ k = "guard", g = guard })
		end
		local t = os.clock()
		if t - lastLeanSend > 1 / 15 and (lean - sentLean).Magnitude > 0.02 then
			lastLeanSend = t
			sentLean = lean
			LeanEv:FireServer(lean.X, lean.Y, lean.Z)
		end
	end)
end

function Controls.SendCorner(i) send({ k = "corner", i = i }) end

return Controls
