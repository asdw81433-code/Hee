--[[
	Knockout ragdoll: every body Motor6D is swapped for a BallSocket or Hinge constraint with anatomical limits
	(knees and elbows only bend one way), colliders switch on in a self-ignoring collision group, the server
	takes physics ownership and the punch's impulse throws the body.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local RigDef = require(Shared.RigDef)

local Ragdoll = {}

local function attach(part, cf, name)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = part
	return a
end

function Ragdoll.Enable(model, impulse: Vector3?, at: Vector3?)
	if model:GetAttribute("Ragdolled") then return end
	model:SetAttribute("Ragdolled", true)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = true
		hum.AutoRotate = false
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local face = hrp and hrp:FindFirstChild("Facing")
	if face then face.Enabled = false end
	for _, def in RigDef.Bones do
		local part = model:FindFirstChild(def.name)
		local motor = part and part:FindFirstChild(def.motor)
		local lim = RigDef.Joints[def.motor]
		if motor and motor:IsA("Motor6D") and def.motor ~= "Root" and def.motor ~= "Jaw" then
			local a0 = attach(motor.Part0, motor.C0, "RD0_" .. def.motor)
			local a1 = attach(motor.Part1, motor.C1, "RD1_" .. def.motor)
			local con
			if lim and lim.kind == "hinge" then
				con = Instance.new("HingeConstraint")
				con.LimitsEnabled = true
				con.LowerAngle = lim.lo
				con.UpperAngle = lim.hi
				-- hinge axis is the attachment's X axis: the character's left-right axis
			else
				con = Instance.new("BallSocketConstraint")
				con.LimitsEnabled = true
				con.UpperAngle = lim and lim.cone or 45
				con.TwistLimitsEnabled = true
				con.TwistLowerAngle = -(lim and lim.twist or 30)
				con.TwistUpperAngle = lim and lim.twist or 30
				-- ball socket cone axis is X: point it down the bone
				a0.CFrame = motor.C0 * CFrame.Angles(0, 0, math.rad(-90))
				a1.CFrame = motor.C1 * CFrame.Angles(0, 0, math.rad(-90))
			end
			con.Name = "RD_" .. def.motor
			con.Attachment0 = a0
			con.Attachment1 = a1
			con.Parent = part
			motor.Enabled = false
		end
	end
	-- the root holds the hips still no longer: weld HRP to the pelvis loosely so the body drags it along
	local root = model:FindFirstChild("LowerTorso") and model.LowerTorso:FindFirstChild("Root")
	if root then root.Enabled = true end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Col_" then
			d.CanCollide = true
			d.Massless = false
		end
	end
	if hrp then
		hrp.CanCollide = false
		hrp.Massless = true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function() d:SetNetworkOwner(nil) end)
		end
	end
	if impulse then
		local head = model:FindFirstChild("Col_Head") or model:FindFirstChild("Col_UpperTorso")
		local chest = model:FindFirstChild("Col_UpperTorso")
		task.defer(function()
			if head then pcall(function() head:ApplyImpulse(impulse) end) end
			if chest then pcall(function() chest:ApplyImpulse(impulse * 0.6) end) end
		end)
	end
end

return Ragdoll
