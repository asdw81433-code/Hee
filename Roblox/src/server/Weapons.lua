-- ============================================================
--  ซอยเดือด : อาวุธข้างถนน (กระทะ ไม้หน้าสาม เก้าอี้ ปลาทู กรวย ขวดน้ำปลา)
--  อาวุธสร้างใน "พื้นที่มือ": จุด (0,0,0) = มือ, ตัวอาวุธยื่นไปทางแกน -Y
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))

local Weapons = {}
local Combat, remotes
local folder
local spawners = {} -- {pos, current, nextT}

local function now()
	return os.clock()
end

local function wpart(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.Anchored = true
	p.Parent = model
	return p
end

local CYL = Enum.PartType.Cylinder
local DEG = math.rad

local BUILD = {
	pan = function(m)
		wpart(m, "Handle", Vector3.new(0.24, 1.4, 0.24), CFrame.new(0, -0.4, 0), Color3.fromRGB(40, 28, 22), Enum.Material.Wood)
		wpart(m, "Pan", Vector3.new(0.18, 1.9, 1.9), CFrame.new(0, -1.95, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(55, 55, 60), Enum.Material.Metal, CYL)
		wpart(m, "Rim", Vector3.new(0.3, 1.5, 1.5), CFrame.new(0, -1.95, 0.05) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, CYL)
		return 2.9
	end,
	plank = function(m)
		wpart(m, "Plank", Vector3.new(0.32, 3.8, 0.75), CFrame.new(0, -1.55, 0), Color3.fromRGB(176, 132, 84), Enum.Material.Wood)
		wpart(m, "Nail", Vector3.new(0.06, 0.06, 0.45), CFrame.new(0.05, -3.1, 0.45), Color3.fromRGB(140, 140, 145), Enum.Material.Metal)
		wpart(m, "Tape", Vector3.new(0.36, 0.5, 0.79), CFrame.new(0, 0.05, 0), Color3.fromRGB(30, 30, 30))
		return 3.8
	end,
	chair = function(m)
		local red = Color3.fromRGB(205, 40, 40)
		wpart(m, "Back", Vector3.new(1.6, 1.4, 0.16), CFrame.new(0, -0.6, 0), red)
		wpart(m, "Seat", Vector3.new(1.6, 0.16, 1.6), CFrame.new(0, -1.35, -0.72), red)
		for i, x in ipairs({ -0.68, 0.68 }) do
			wpart(m, "LegB" .. i, Vector3.new(0.18, 1.5, 0.18), CFrame.new(x, -2.05, 0) * CFrame.Angles(DEG(-8), 0, 0), red)
			wpart(m, "LegF" .. i, Vector3.new(0.18, 1.5, 0.18), CFrame.new(x, -2.05, -1.45) * CFrame.Angles(DEG(8), 0, 0), red)
		end
		return 2.8
	end,
	fish = function(m)
		local silver = Color3.fromRGB(128, 150, 170)
		wpart(m, "Tail", Vector3.new(0.12, 0.55, 0.95), CFrame.new(0, -0.15, 0), Color3.fromRGB(90, 110, 130))
		wpart(m, "Body", Vector3.new(0.5, 2.6, 0.95), CFrame.new(0, -1.75, 0), silver, Enum.Material.Metal)
		wpart(m, "Belly", Vector3.new(0.52, 2.0, 0.3), CFrame.new(0, -1.85, -0.36), Color3.fromRGB(220, 225, 230))
		wpart(m, "Head", Vector3.new(0.5, 0.7, 0.85), CFrame.new(0, -3.35, 0), Color3.fromRGB(110, 130, 150), Enum.Material.Metal)
		wpart(m, "EyeL", Vector3.new(0.54, 0.16, 0.16), CFrame.new(0, -3.3, 0.2), Color3.fromRGB(15, 15, 15))
		wpart(m, "Mouth", Vector3.new(0.3, 0.12, 0.3), CFrame.new(0, -3.72, -0.2), Color3.fromRGB(170, 70, 70))
		return 3.8
	end,
	cone = function(m)
		local orange = Color3.fromRGB(255, 110, 20)
		local white = Color3.fromRGB(245, 245, 245)
		wpart(m, "Tip", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, -0.15, 0), orange)
		wpart(m, "C1", Vector3.new(0.55, 0.45, 0.55), CFrame.new(0, -0.55, 0), white)
		wpart(m, "C2", Vector3.new(0.8, 0.45, 0.8), CFrame.new(0, -0.98, 0), orange)
		wpart(m, "C3", Vector3.new(1.05, 0.45, 1.05), CFrame.new(0, -1.42, 0), orange)
		wpart(m, "Base", Vector3.new(1.5, 0.16, 1.5), CFrame.new(0, -1.72, 0), Color3.fromRGB(25, 25, 25))
		return 1.8
	end,
	bottle = function(m)
		local glass = Color3.fromRGB(120, 66, 22)
		wpart(m, "Cap", Vector3.new(0.28, 0.14, 0.28), CFrame.new(0, 0.12, 0), Color3.fromRGB(200, 30, 30))
		local neck = wpart(m, "Neck", Vector3.new(0.24, 0.65, 0.24), CFrame.new(0, -0.3, 0), glass, Enum.Material.Glass)
		neck.Transparency = 0.15
		local body = wpart(m, "Body", Vector3.new(0.55, 1.2, 0.55), CFrame.new(0, -1.2, 0), glass, Enum.Material.Glass)
		body.Transparency = 0.15
		wpart(m, "Label", Vector3.new(0.57, 0.45, 0.57), CFrame.new(0, -1.2, 0), Color3.fromRGB(240, 220, 120))
		return 1.9
	end,
}

-- สร้างโมเดลอาวุธ
local function make(id)
	local m = Instance.new("Model")
	m.Name = "W_" .. id
	local grip = wpart(m, "Grip", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1))
	grip.Transparency = 1
	local len = BUILD[id](m)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p ~= grip then
			local w = Instance.new("WeldConstraint")
			w.Part0 = grip
			w.Part1 = p
			w.Parent = p
		end
	end
	m.PrimaryPart = grip
	m:SetAttribute("WeaponId", id)
	m:SetAttribute("Uses", Config.Weapons[id].uses)
	m:SetAttribute("Len", len)
	-- ไอคอนลอยเหนืออาวุธ
	local bb = Instance.new("BillboardGui")
	bb.Name = "Icon"
	bb.Size = UDim2.fromOffset(46, 46)
	bb.StudsOffset = Vector3.new(0, 1.8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 70
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = Config.Weapons[id].icon
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Parent = bb
	bb.Parent = grip
	return m
end

local function setPhysics(m, held)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = held
			p.CanQuery = not held
			p.CanCollide = (not held) and p.Name ~= "Grip"
			p.CanTouch = true
		end
	end
end

local function placeOnPad(m, pos)
	local len = m:GetAttribute("Len") or 2
	local spin = math.random() * math.pi * 2
	local cf = CFrame.new(pos + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, spin, 0) * CFrame.new(0, 0, len / 2) * CFrame.Angles(math.pi / 2, 0, 0)
	m:PivotTo(cf)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end
	m:SetAttribute("OnPad", true)
end

function Weapons.init(deps)
	Combat = deps.Combat
	remotes = deps.remotes
	folder = Instance.new("Folder")
	folder.Name = "BrawlWeapons"
	folder.Parent = workspace
	for _, pos in ipairs(deps.spawners or {}) do
		table.insert(spawners, { pos = pos, current = nil, nextT = now() + math.random() * 3 })
	end
	task.spawn(function()
		while true do
			task.wait(1)
			Weapons.tick()
		end
	end)
end

function Weapons.tick()
	local t = now()
	local count = 0
	for _, m in ipairs(folder:GetChildren()) do
		if not m:GetAttribute("Broken") then
			count = count + 1
		end
		-- อาวุธที่ตกพื้นนานเกินไป หายไป
		local dt = m:GetAttribute("DroppedT")
		if dt and t - dt > 45 and not m:GetAttribute("Held") then
			m:Destroy()
		end
	end
	for _, s in ipairs(spawners) do
		if s.current and (not s.current.Parent or s.current.Parent ~= folder or s.current:GetAttribute("Held")) then
			s.current = nil
			s.nextT = t + Config.WeaponRespawn
		end
		if not s.current and t >= s.nextT and count < Config.MaxWeaponsOnMap then
			local id = Config.WeaponOrder[math.random(1, #Config.WeaponOrder)]
			local m = make(id)
			placeOnPad(m, s.pos)
			m.Parent = folder
			s.current = m
			count = count + 1
		end
	end
end

-- หาอาวุธใกล้ๆ ที่หยิบได้
function Weapons.findNear(pos, radius)
	local best, bestD = nil, radius
	for _, m in ipairs(folder:GetChildren()) do
		if m.PrimaryPart and not m:GetAttribute("Held") and not m:GetAttribute("Broken") and not m:GetAttribute("Thrown") then
			local d = (m.PrimaryPart.Position - pos).Magnitude
			if m:GetAttribute("OnPad") then
				d = d - 1
			end
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best, bestD
end

function Weapons.equip(F, m)
	if F.weapon or not m.Parent then
		return
	end
	-- ถือด้วยมือขวา ถ้าแขนขวาขาดใช้มือซ้าย
	local arm = F.model:FindFirstChild("RightHand") or F.model:FindFirstChild("LeftHand")
	if not arm then
		return
	end
	local id = m:GetAttribute("WeaponId")
	m:SetAttribute("Held", true)
	m:SetAttribute("OnPad", false)
	m:SetAttribute("DroppedT", nil)
	setPhysics(m, true)
	local grip = m.PrimaryPart
	m:PivotTo(arm.CFrame * CFrame.new(0, -0.1, 0))
	local w = Instance.new("Weld")
	w.Name = "GripWeld"
	w.Part0 = arm
	w.Part1 = grip
	w.C0 = CFrame.new(0, -0.1, 0)
	w.C1 = CFrame.new()
	w.Parent = grip
	local icon = grip:FindFirstChild("Icon")
	if icon then
		icon.Enabled = false
	end
	m.Parent = F.model
	F.weapon = { model = m, id = id }
	F.model:SetAttribute("Weapon", id)
	F.model:SetAttribute("WeaponUses", m:GetAttribute("Uses"))
	Combat.fx("word", { pos = F.head.Position, word = Config.Weapons[id].icon .. " " .. Config.Weapons[id].name, small = true })
end

-- ปล่อยอาวุธ (คืนค่าโมเดล)
function Weapons.drop(F, vel)
	local W = F.weapon
	if not W then
		return nil
	end
	F.weapon = nil
	F.model:SetAttribute("Weapon", nil)
	F.model:SetAttribute("WeaponUses", nil)
	local m = W.model
	if not m or not m.Parent then
		return nil
	end
	local grip = m.PrimaryPart
	local gw = grip:FindFirstChild("GripWeld")
	if gw then
		gw:Destroy()
	end
	m.Parent = folder
	setPhysics(m, false)
	m:SetAttribute("Held", false)
	m:SetAttribute("DroppedT", now())
	local icon = grip:FindFirstChild("Icon")
	if icon then
		icon.Enabled = true
	end
	pcall(function()
		grip:SetNetworkOwner(nil)
	end)
	grip.AssemblyLinearVelocity = vel or Vector3.zero
	grip.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10
	return m
end

-- อาวุธแตกเป็นชิ้นๆ
function Weapons.shatter(m, pos)
	m:SetAttribute("Broken", true)
	m:SetAttribute("Held", false)
	m.Parent = folder
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = false
			p.CanCollide = p.Name ~= "Grip"
			p.CanQuery = false
			p.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.3, math.random() - 0.5) * 34
			p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		end
	end
	Combat.fx("break", { pos = pos or (m.PrimaryPart and m.PrimaryPart.Position) or Vector3.zero, glass = m:GetAttribute("WeaponId") == "bottle" })
	Debris:AddItem(m, 5)
end

-- กรวยติดหัว
local function coneHat(m, G)
	m.Parent = G.model
	setPhysics(m, true)
	local grip = m.PrimaryPart
	for _, d in ipairs(grip:GetChildren()) do
		if d:IsA("Weld") then
			d:Destroy()
		end
	end
	local icon = grip:FindFirstChild("Icon")
	if icon then
		icon.Enabled = false
	end
	local hs = G.head.Size.Y / 2
	local w = Instance.new("Weld")
	w.Name = "GripWeld"
	w.Part0 = G.head
	w.Part1 = grip
	w.C0 = CFrame.new(0, hs + 1.82, 0) * CFrame.Angles(0, math.random() * 6.28, math.rad(math.random(-12, 12)))
	w.Parent = grip
	m:SetAttribute("Held", true)
	task.delay(12, function()
		if m.Parent == G.model then
			if w.Parent then
				w:Destroy()
			end
			m.Parent = folder
			setPhysics(m, false)
			m:SetAttribute("Held", false)
			m:SetAttribute("DroppedT", now())
			if icon then
				icon.Enabled = true
			end
		end
	end)
end

-- ตีโดนแล้ว: ลดความทนทาน / แตก / กรวยติดหัว
function Weapons.onHit(F, G)
	local W = F.weapon
	if not W then
		return
	end
	local wdef = Config.Weapons[W.id]
	local m = W.model
	local uses = (m:GetAttribute("Uses") or 1) - 1
	m:SetAttribute("Uses", uses)
	F.model:SetAttribute("WeaponUses", uses)
	if wdef.hat and G and G.alive then
		F.weapon = nil
		F.model:SetAttribute("Weapon", nil)
		F.model:SetAttribute("WeaponUses", nil)
		coneHat(m, G)
		Combat.fx("word", { pos = G.head.Position + Vector3.new(0, 2, 0), word = "หัวกรวย! 🤡", big = true })
		return
	end
	if uses <= 0 then
		F.weapon = nil
		F.model:SetAttribute("Weapon", nil)
		F.model:SetAttribute("WeaponUses", nil)
		Weapons.shatter(m, G and G.head.Position)
	end
end

-- ขว้างอาวุธ!
function Weapons.throw(F, dir)
	local W = F.weapon
	if not W then
		return
	end
	local wdef = Config.Weapons[W.id]
	local start = F.root.Position + dir * 2.6 + Vector3.new(0, 1.2, 0)
	local m = Weapons.drop(F, Vector3.zero)
	if not m then
		return
	end
	local grip = m.PrimaryPart
	m:PivotTo(CFrame.lookAt(start, start + dir) * CFrame.Angles(math.pi / 2, 0, 0))
	grip.AssemblyLinearVelocity = dir * Config.ThrowSpeed + Vector3.new(0, 12, 0)
	grip.AssemblyAngularVelocity = F.root.CFrame.RightVector * -18
	m:SetAttribute("Thrown", true)
	local conns = {}
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		if m.Parent then
			m:SetAttribute("Thrown", false)
		end
	end
	local function onTouch(hit)
		if done then
			return
		end
		local G = Combat.findFighterByPart(hit)
		if G and G ~= F and G.alive then
			local speed = grip.AssemblyLinearVelocity.Magnitude
			if speed > 20 then
				finish()
				local mv = Combat.weaponMove(wdef, true)
				if Combat.hit(F, G, mv, dir) then
					local uses = (m:GetAttribute("Uses") or 1) - 1
					m:SetAttribute("Uses", uses)
					if wdef.hat then
						coneHat(m, G)
						Combat.fx("word", { pos = G.head.Position + Vector3.new(0, 2, 0), word = "หัวกรวย! 🤡", big = true })
					elseif uses <= 0 then
						Weapons.shatter(m, hit.Position)
					end
				end
			end
		end
	end
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(conns, p.Touched:Connect(onTouch))
		end
	end
	Combat.fx("word", { pos = start, word = "ขว้าง!", small = true })
	task.delay(2.2, finish)
end

return Weapons
