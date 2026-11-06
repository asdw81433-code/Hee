-- ============================================================
--  ซอยเดือด : Ragdoll ฟิสิกส์จริง (BallSocketConstraint 14 ข้อ: คอ เอว ไหล่ ศอก ข้อมือ สะโพก เข่า ข้อเท้า)
--  ตอนปกติข้อต่อเป็น Motor6D -> ตอนล้มสลับเป็นลูกหมากหมุนอิสระ
--  + ตัดข้อต่อ (แขนขาหลุด) ได้
-- ============================================================
local Players = game:GetService("Players")

local Ragdoll = {}
local data = {} -- [model] = {joints = {[name] = {motor, socket, a0, a1}}, colliders, token}
local remotes

-- ข้อต่อ -> ขีดจำกัด (cone = มุมกรวย, twist = มุมบิด, up = แกนชี้ขึ้น, hinge = ข้อพับทางเดียว)
local LIMITS = {
	Neck = { cone = 45, twist = 55, up = true },
	Waist = { cone = 35, twist = 40, up = true },
	RightShoulder = { cone = 125, twist = 70 },
	LeftShoulder = { cone = 125, twist = 70 },
	RightElbow = { cone = 75, twist = 10, bend = 1 },
	LeftElbow = { cone = 75, twist = 10, bend = 1 },
	RightHip = { cone = 75, twist = 35 },
	LeftHip = { cone = 75, twist = 35 },
	RightKnee = { cone = 75, twist = 8, bend = -1 },
	LeftKnee = { cone = 75, twist = 8, bend = -1 },
	RightWrist = { cone = 60, twist = 30 },
	LeftWrist = { cone = 60, twist = 30 },
	RightAnkle = { cone = 30, twist = 15 },
	LeftAnkle = { cone = 30, twist = 15 },
}
local LIMBS = {
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}
Ragdoll.LIMBS = LIMBS

function Ragdoll.init(r)
	remotes = r
end

local function axisCF(pos, lim)
	-- แกน X ของ Attachment = แกนกรวย
	if lim.up then
		return CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	end
	local cf = CFrame.new(pos) * CFrame.Angles(0, 0, -math.pi / 2)
	if lim.bend then
		-- ข้อพับ (ศอก/เข่า): เอียงแกนกรวยไปทางที่พับได้ ครึ่งหนึ่งของมุม
		cf = CFrame.new(pos) * CFrame.Angles(math.rad(lim.cone) * lim.bend, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2)
	end
	return cf
end

function Ragdoll.setup(model)
	local d = { joints = {}, colliders = {}, token = 0 }
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and LIMITS[m.Name] then
			local lim = LIMITS[m.Name]
			local a0 = Instance.new("Attachment")
			a0.Name = "RD0_" .. m.Name
			a0.CFrame = axisCF(m.C0.Position, lim)
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RD1_" .. m.Name
			a1.CFrame = axisCF(m.C1.Position, lim.up and lim or { cone = 0 })
			a1.Parent = m.Part1
			local s = Instance.new("BallSocketConstraint")
			s.Name = "RD_" .. m.Name
			s.Attachment0 = a0
			s.Attachment1 = a1
			s.LimitsEnabled = true
			s.UpperAngle = lim.cone
			s.TwistLimitsEnabled = true
			s.TwistLowerAngle = -lim.twist
			s.TwistUpperAngle = lim.twist
			s.Restitution = 0
			s.MaxFrictionTorque = 3
			s.Enabled = false
			s.Parent = m.Part0
			d.joints[m.Name] = { motor = m, socket = s, a0 = a0, a1 = a1 }
		end
	end
	-- ตัวชนของแขนขา (Humanoid มักปิดการชนของแขนขา เลยต้องมีตัวชนแยก)
	for _, name in ipairs(LIMBS) do
		local limb = model:FindFirstChild(name)
		if limb then
			local c = Instance.new("Part")
			c.Name = "RDCollider"
			c.Size = limb.Size * 0.88
			c.Transparency = 1
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = true
			c.Massless = true
			c.CFrame = limb.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0 = limb
			w.Part1 = c
			w.Parent = c
			c.Parent = limb
			d.colliders[name] = c
		end
	end
	-- ไม่ให้ชิ้นที่ติดกันชนกันเอง (กันสั่น)
	local function get(n)
		return d.colliders[n] or model:FindFirstChild(n)
	end
	local function nc(a, b)
		a, b = get(a), get(b)
		if a and b then
			local n = Instance.new("NoCollisionConstraint")
			n.Part0 = a
			n.Part1 = b
			n.Parent = a
		end
	end
	nc("LowerTorso", "UpperTorso")
	nc("UpperTorso", "Head")
	for _, side in ipairs({ "Right", "Left" }) do
		nc("UpperTorso", side .. "UpperArm")
		nc(side .. "UpperArm", side .. "LowerArm")
		nc("LowerTorso", side .. "UpperLeg")
		nc("UpperTorso", side .. "UpperLeg")
		nc(side .. "UpperLeg", side .. "LowerLeg")
		nc(side .. "LowerArm", side .. "Hand")
		nc(side .. "LowerLeg", side .. "Foot")
	end
	nc("RightFoot", "LeftFoot")
	nc("RightUpperLeg", "LeftUpperLeg")
	nc("RightLowerLeg", "LeftLowerLeg")
	data[model] = d
	model.Destroying:Connect(function()
		data[model] = nil
	end)
end

function Ragdoll.isRagdolled(model)
	return model:GetAttribute("Ragdoll") == true
end

local function setOwner(model, owner)
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(owner)
			end)
		end
	end
end

local function setLimp(d, on)
	for _, j in pairs(d.joints) do
		j.socket.Enabled = on
		j.motor.Enabled = not on
	end
	for _, c in pairs(d.colliders) do
		c.CanCollide = on
	end
end

-- เริ่มล้ม: vel = ความเร็ว (studs/s), spin = ความเร็วหมุน, duration = วินาที (nil = ตลอดไป/ตาย)
function Ragdoll.start(model, vel, spin, duration)
	local d = data[model]
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not d or not hum then
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	d.token = d.token + 1
	local token = d.token
	if not Ragdoll.isRagdolled(model) then
		model:SetAttribute("Ragdoll", true)
		hum.AutoRotate = false
		hum.PlatformStand = true
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		setLimp(d, true)
		-- ฟิสิกส์ฝั่ง server เพื่อให้ทุกคนเห็นตรงกัน
		setOwner(model, nil)
		if player and remotes then
			remotes.Ragdoll:FireClient(player, true)
		end
	end
	if vel then
		local rng = Random.new()
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then
				local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 1), rng:NextNumber(-1, 1)) * (vel.Magnitude * 0.12)
				p.AssemblyLinearVelocity = vel + jitter
			end
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	if spin and torso then
		torso.AssemblyAngularVelocity = spin
	end
	if duration then
		task.delay(duration, function()
			if data[model] and data[model].token == token then
				Ragdoll.recover(model)
			end
		end)
	end
end

function Ragdoll.recover(model)
	local d = data[model]
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not d or not hum or hum.Health <= 0 or not model.Parent then
		return
	end
	if not Ragdoll.isRagdolled(model) then
		return
	end
	d.token = d.token + 1
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("LowerTorso")
	-- ตั้งตัวตรงก่อนเปิดข้อต่อ
	if root and torso then
		local pos = torso.Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
		local floorY = hit and hit.Position.Y or (pos.Y - 1)
		local look = torso.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.2 then
			look = torso.CFrame.UpVector * Vector3.new(1, 0, 1)
		end
		if look.Magnitude < 0.2 then
			look = Vector3.new(0, 0, -1)
		end
		local p = Vector3.new(pos.X, floorY + hum.HipHeight + root.Size.Y / 2 + 0.05, pos.Z)
		root.CFrame = CFrame.lookAt(p, p + look.Unit)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	setLimp(d, false)
	hum.PlatformStand = false
	hum.AutoRotate = true
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	model:SetAttribute("Ragdoll", false)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		if root then
			pcall(function()
				root:SetNetworkOwner(player)
			end)
		end
		if remotes then
			remotes.Ragdoll:FireClient(player, false)
		end
	else
		setOwner(model, nil)
	end
end

-- ===== ตัดข้อ (แขนขา/หัวหลุด) =====
-- jointName = ข้อที่ขาด, pieces = ชิ้นที่หลุดไปด้วย (เช่น ต้นแขน + ปลายแขน), gibsFolder = ที่เก็บชิ้นส่วน
-- คืนค่า ตำแหน่งข้อที่ขาด
function Ragdoll.sever(model, jointName, pieces, gibsFolder)
	local d = data[model]
	if not d then
		return nil
	end
	local j = d.joints[jointName]
	if not j then
		return nil
	end
	local pos = j.a0.WorldPosition
	j.socket:Destroy()
	j.a0:Destroy()
	j.a1:Destroy()
	j.motor:Destroy()
	d.joints[jointName] = nil
	-- ข้อที่อยู่ในชิ้นที่หลุด (เช่น ศอก) ให้ห้อยต่องแต่ง และไม่ต้องกลับมาแข็งอีก
	local pieceSet = {}
	for _, p in ipairs(pieces) do
		pieceSet[p.Name] = true
	end
	for name, jj in pairs(d.joints) do
		if pieceSet[jj.motor.Part1 and jj.motor.Part1.Name or ""] and pieceSet[jj.motor.Part0 and jj.motor.Part0.Name or ""] then
			jj.motor.Enabled = false
			jj.socket.Enabled = true
			d.joints[name] = nil
		end
	end
	for _, p in ipairs(pieces) do
		local c = d.colliders[p.Name]
		if c then
			c.CanCollide = true
			d.colliders[p.Name] = nil
		end
		if p.Name == "Head" then
			p.CanCollide = true
		end
		p.Parent = gibsFolder
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
	end
	return pos
end

function Ragdoll.hasJoint(model, jointName)
	local d = data[model]
	return d ~= nil and d.joints[jointName] ~= nil
end

return Ragdoll
