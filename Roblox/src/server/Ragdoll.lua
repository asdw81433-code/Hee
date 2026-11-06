-- ============================================================
--  ซอยเดือด : Ragdoll ฟิสิกส์จริง (BallSocketConstraint)
--  ตอนปกติข้อต่อเป็น Motor6D -> ตอนล้มสลับเป็นลูกหมากหมุนอิสระ
-- ============================================================
local Players = game:GetService("Players")

local Ragdoll = {}
local data = {} -- [model] = {sockets, motors, colliders, nocollide, token}
local remotes

-- ข้อต่อ -> (ขีดจำกัดกรวย, ขีดจำกัดบิด, ทิศแกนหลัก)
local LIMITS = {
	["Neck"] = { cone = 45, twist = 55, up = true },
	["Right Shoulder"] = { cone = 125, twist = 70 },
	["Left Shoulder"] = { cone = 125, twist = 70 },
	["Right Hip"] = { cone = 75, twist = 35 },
	["Left Hip"] = { cone = 75, twist = 35 },
}
local LIMBS = { "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

function Ragdoll.init(r)
	remotes = r
end

local function axisCF(pos, up)
	-- แกน X ของ Attachment = แกนกรวย: ชี้ลง (แขน/ขา) หรือชี้ขึ้น (คอ)
	if up then
		return CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	end
	return CFrame.new(pos) * CFrame.Angles(0, 0, -math.pi / 2)
end

function Ragdoll.setup(model)
	local d = { sockets = {}, motors = {}, colliders = {}, nocollide = {}, token = 0 }
	local torso = model:FindFirstChild("Torso")
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and LIMITS[m.Name] then
			local lim = LIMITS[m.Name]
			local a0 = Instance.new("Attachment")
			a0.Name = "RD0_" .. m.Name
			a0.CFrame = axisCF(m.C0.Position, lim.up)
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RD1_" .. m.Name
			a1.CFrame = axisCF(m.C1.Position, lim.up)
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
			s.MaxFrictionTorque = 4
			s.Enabled = false
			s.Parent = m.Part0
			table.insert(d.sockets, s)
			table.insert(d.motors, m)
		end
	end
	-- ตัวชนของแขนขา (Humanoid ปิดการชนของแขนขา R6 เลยต้องมีตัวชนแยก)
	for _, name in ipairs(LIMBS) do
		local limb = model:FindFirstChild(name)
		if limb then
			local c = Instance.new("Part")
			c.Name = "RDCollider"
			c.Size = Vector3.new(0.9, 1.8, 0.9)
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
			table.insert(d.colliders, c)
		end
	end
	-- ไม่ให้ชิ้นส่วนตัวเองชนกันเอง (กันสั่น)
	local head = model:FindFirstChild("Head")
	local function nc(a, b)
		if a and b then
			local n = Instance.new("NoCollisionConstraint")
			n.Part0 = a
			n.Part1 = b
			n.Enabled = true
			n.Parent = a
			table.insert(d.nocollide, n)
		end
	end
	nc(torso, head)
	for i, c in ipairs(d.colliders) do
		nc(c, torso)
		nc(c, head)
		for j = i + 1, #d.colliders do
			nc(c, d.colliders[j])
		end
	end
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
		for _, s in ipairs(d.sockets) do
			s.Enabled = true
		end
		for _, m in ipairs(d.motors) do
			m.Enabled = false
		end
		for _, c in ipairs(d.colliders) do
			c.CanCollide = true
		end
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
	local torso = model:FindFirstChild("Torso")
	if spin and torso then
		torso.AssemblyAngularVelocity = spin
	end
	if duration then
		model:SetAttribute("DownUntil", os.clock() + duration)
		task.delay(duration, function()
			if data[model] and data[model].token == token then
				Ragdoll.recover(model)
			end
		end)
	else
		model:SetAttribute("DownUntil", math.huge)
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
	local torso = model:FindFirstChild("Torso")
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
		local p = Vector3.new(pos.X, floorY + 3.05, pos.Z)
		root.CFrame = CFrame.lookAt(p, p + look.Unit)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	for _, s in ipairs(d.sockets) do
		s.Enabled = false
	end
	for _, m in ipairs(d.motors) do
		m.Enabled = true
	end
	for _, c in ipairs(d.colliders) do
		c.CanCollide = false
	end
	hum.PlatformStand = false
	hum.AutoRotate = true
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	model:SetAttribute("Ragdoll", false)
	model:SetAttribute("DownUntil", 0)
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

return Ragdoll
