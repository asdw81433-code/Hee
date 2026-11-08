--[[
	Skeleton of a NEON BAY fighter. Every bone is a small invisible part whose origin IS the joint, so a
	Motor6D with C0 = offset and C1 = identity rotates the bone around its joint through Motor6D.Transform.
	Coordinates: Roblox (front = -Z, right = +X), authored in meters and scaled to studs.
]]

local Config = require(script.Parent.Config)

local RigDef = {}

RigDef.Bones = {
	{ name = "LowerTorso", parent = "HumanoidRootPart", motor = "Root" },
	{ name = "Spine", parent = "LowerTorso", motor = "Waist" },
	{ name = "UpperTorso", parent = "Spine", motor = "Chest" },
	{ name = "Neck", parent = "UpperTorso", motor = "NeckJoint" },
	{ name = "Head", parent = "Neck", motor = "Neck" },
	{ name = "Jaw", parent = "Head", motor = "Jaw" },
	{ name = "LeftUpperArm", parent = "UpperTorso", motor = "LeftShoulder" },
	{ name = "LeftLowerArm", parent = "LeftUpperArm", motor = "LeftElbow" },
	{ name = "LeftHand", parent = "LeftLowerArm", motor = "LeftWrist" },
	{ name = "RightUpperArm", parent = "UpperTorso", motor = "RightShoulder" },
	{ name = "RightLowerArm", parent = "RightUpperArm", motor = "RightElbow" },
	{ name = "RightHand", parent = "RightLowerArm", motor = "RightWrist" },
	{ name = "LeftUpperLeg", parent = "LowerTorso", motor = "LeftHip" },
	{ name = "LeftLowerLeg", parent = "LeftUpperLeg", motor = "LeftKnee" },
	{ name = "LeftFoot", parent = "LeftLowerLeg", motor = "LeftAnkle" },
	{ name = "RightUpperLeg", parent = "LowerTorso", motor = "RightHip" },
	{ name = "RightLowerLeg", parent = "RightUpperLeg", motor = "RightKnee" },
	{ name = "RightFoot", parent = "RightLowerLeg", motor = "RightAnkle" },
}

RigDef.HipHeightM = 0.98
RigDef.UpperArm, RigDef.LowerArm = 0.29, 0.26
RigDef.UpperLeg, RigDef.LowerLeg = 0.44, 0.43

function RigDef.Dims(p)
	local b = math.clamp(p.bulk or 1, 0.85, 1.4)
	local m = math.clamp(p.muscle or 0.5, 0, 1)
	local f = p.female and 1 or 0
	local h = math.clamp(p.height or 1, 0.9, 1.1)
	return {
		b = b, m = m, f = f, h = h,
		sx = 0.168 + 0.05 * (b - 1) + 0.012 * m - 0.018 * f,
		hx = 0.088 + 0.015 * (b - 1) + 0.012 * f,
		scale = Config.S * h, -- studs per authored meter for this fighter
	}
end

--[[ Offsets in parent space, in studs. ]]
function RigDef.Offsets(p)
	local d = RigDef.Dims(p)
	local k = d.scale
	local o = {
		LowerTorso = Vector3.new(0, 0, 0),
		Spine = Vector3.new(0, 0.06, 0),
		UpperTorso = Vector3.new(0, 0.2, 0),
		Neck = Vector3.new(0, 0.225, 0.012),
		Head = Vector3.new(0, 0.095, -0.012),
		Jaw = Vector3.new(0, 0.11, -0.01),
		LeftUpperArm = Vector3.new(-d.sx, 0.185, 0.015),
		RightUpperArm = Vector3.new(d.sx, 0.185, 0.015),
		LeftLowerArm = Vector3.new(0, -RigDef.UpperArm, 0),
		RightLowerArm = Vector3.new(0, -RigDef.UpperArm, 0),
		LeftHand = Vector3.new(0, -RigDef.LowerArm, 0),
		RightHand = Vector3.new(0, -RigDef.LowerArm, 0),
		LeftUpperLeg = Vector3.new(-d.hx, -0.05, 0),
		RightUpperLeg = Vector3.new(d.hx, -0.05, 0),
		LeftLowerLeg = Vector3.new(0, -RigDef.UpperLeg, 0),
		RightLowerLeg = Vector3.new(0, -RigDef.UpperLeg, 0),
		LeftFoot = Vector3.new(0, -RigDef.LowerLeg, 0),
		RightFoot = Vector3.new(0, -RigDef.LowerLeg, 0),
	}
	for name, v in o do
		o[name] = v * k
	end
	return o, d
end

-- HumanoidRootPart is centred on the hip joint
RigDef.RootSize = Vector3.new(1.6, 2, 1.3)

function RigDef.HipHeight(p)
	local d = RigDef.Dims(p)
	return RigDef.HipHeightM * d.scale - RigDef.RootSize.Y / 2
end

-- ragdoll / hit colliders per bone: centre (m, bone space) and size (m)
RigDef.Colliders = {
	LowerTorso = { c = Vector3.new(0, -0.03, 0), s = Vector3.new(0.3, 0.2, 0.2) },
	Spine = { c = Vector3.new(0, 0.1, 0), s = Vector3.new(0.27, 0.25, 0.18) },
	UpperTorso = { c = Vector3.new(0, 0.12, 0), s = Vector3.new(0.36, 0.3, 0.22) },
	Head = { c = Vector3.new(0, 0.13, -0.01), s = Vector3.new(0.2, 0.25, 0.22) },
	LeftUpperArm = { c = Vector3.new(0, -0.145, 0), s = Vector3.new(0.1, 0.32, 0.1) },
	RightUpperArm = { c = Vector3.new(0, -0.145, 0), s = Vector3.new(0.1, 0.32, 0.1) },
	LeftLowerArm = { c = Vector3.new(0, -0.17, 0), s = Vector3.new(0.09, 0.4, 0.09) },
	RightLowerArm = { c = Vector3.new(0, -0.17, 0), s = Vector3.new(0.09, 0.4, 0.09) },
	LeftUpperLeg = { c = Vector3.new(0, -0.22, 0), s = Vector3.new(0.15, 0.48, 0.15) },
	RightUpperLeg = { c = Vector3.new(0, -0.22, 0), s = Vector3.new(0.15, 0.48, 0.15) },
	LeftLowerLeg = { c = Vector3.new(0, -0.22, 0), s = Vector3.new(0.11, 0.48, 0.11) },
	RightLowerLeg = { c = Vector3.new(0, -0.22, 0), s = Vector3.new(0.11, 0.48, 0.11) },
	LeftFoot = { c = Vector3.new(0, -0.03, -0.05), s = Vector3.new(0.09, 0.06, 0.25) },
	RightFoot = { c = Vector3.new(0, -0.03, -0.05), s = Vector3.new(0.09, 0.06, 0.25) },
}

-- ragdoll joint limits: "ball" = cone + twist, "hinge" = bend in one direction (degrees)
RigDef.Joints = {
	Waist = { kind = "ball", cone = 25, twist = 20 },
	Chest = { kind = "ball", cone = 20, twist = 18 },
	NeckJoint = { kind = "ball", cone = 25, twist = 25 },
	Neck = { kind = "ball", cone = 35, twist = 45 },
	LeftShoulder = { kind = "ball", cone = 85, twist = 55 },
	RightShoulder = { kind = "ball", cone = 85, twist = 55 },
	LeftElbow = { kind = "hinge", lo = -3, hi = 140 },
	RightElbow = { kind = "hinge", lo = -3, hi = 140 },
	LeftHip = { kind = "ball", cone = 70, twist = 25 },
	RightHip = { kind = "ball", cone = 70, twist = 25 },
	LeftKnee = { kind = "hinge", lo = -135, hi = 3 },
	RightKnee = { kind = "hinge", lo = -135, hi = 3 },
	LeftWrist = { kind = "ball", cone = 30, twist = 20 },
	RightWrist = { kind = "ball", cone = 30, twist = 20 },
	LeftAnkle = { kind = "ball", cone = 25, twist = 10 },
	RightAnkle = { kind = "ball", cone = 25, twist = 10 },
}

return RigDef
