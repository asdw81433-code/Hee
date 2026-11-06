-- ============================================================
--  ALLEY BRAWL : ตัวคนสัดส่วนจริงแบบ gore-sandbox ragdoll (15 ชิ้น: หัว อกบน/ล่าง
--  ต้นแขน ปลายแขน มือ ต้นขา หน้าแข้ง เท้า) ข้อต่อกลม แขนขาหลุดได้ทุกข้อ มีแผลติดตัว
--  ถ้ามีโมเดล ServerStorage > Brawler จะใช้โมเดลนั้นแทน (แก้ใน Studio ได้)
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))

local CB = {}

local HEAD_SIZE = Vector3.new(0.85, 1.0, 0.95) -- หัวขนาดคนจริง (สูงรวม ~6.3 studs)
local HEAD = HEAD_SIZE.Y
local GRID = 16  -- หน้า 16x16 พิกเซล

local function newPart(props)
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function cosmetic(main, name, size, offset, color, material)
	local p = newPart({
		Name = name,
		Size = size,
		Color = color,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = true,
	})
	if material then
		p.Material = material
	end
	p.CFrame = main.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = main
	w.Part1 = p
	w.Parent = p
	p.Parent = main
	return p
end

local function motor(name, p0, p1, c0, c1, parent)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

-- ===== หน้าตาแบบสุ่ม (บอท) =====
function CB.randomLook(rng)
	rng = rng or Random.new()
	local L = {}
	for k, v in pairs(Config.Look) do
		L[k] = v
	end
	L.Skin = pick(Config.SkinTones, rng)
	L.Shirt = pick(Config.ShirtColors, rng)
	L.Pants = pick(Config.PantsColors, rng)
	L.Hair = pick(Config.HairColors, rng)
	L.Brows = L.Hair
	L.HairStyle = pick(Config.HairStyles, rng)
	if L.HairStyle == "bald" then
		L.Brows = Color3.fromRGB(60, 45, 38)
	end
	L.Belly = rng:NextNumber() < 0.25 -- พุงยื่น ฮาๆ
	return L
end

function CB.playerLook(index)
	local L = {}
	for k, v in pairs(Config.Look) do
		L[k] = v
	end
	local shirts = Config.PlayerShirts
	L.Shirt = shirts[((index - 1) % #shirts) + 1]
	return L
end

-- ===== ทรงผม (ไม่บังหน้า: อยู่ด้านบน/หลัง/ข้างเท่านั้น) =====
local function buildHair(head, style, color)
	if style == "bald" then
		return
	end
	local hx, hy, hz = head.Size.X / 2, head.Size.Y / 2, head.Size.Z / 2
	local W, D = head.Size.X + 0.07, head.Size.Z + 0.07
	local mat = Enum.Material.SmoothPlastic
	if style == "box" or style == "long" or style == "flat" then
		-- ผมสั้นแนบหัว
		cosmetic(head, "HairTop", Vector3.new(W, 0.16, D), CFrame.new(0, hy + 0.05, 0.01), color, mat)
		cosmetic(head, "HairFringe", Vector3.new(W, 0.13, 0.08), CFrame.new(0, hy - 0.06, -hz - 0.03), color, mat)
		cosmetic(head, "HairSideL", Vector3.new(0.06, 0.36, head.Size.Z * 0.7), CFrame.new(-hx - 0.03, hy - 0.2, 0.1), color, mat)
		cosmetic(head, "HairSideR", Vector3.new(0.06, 0.36, head.Size.Z * 0.7), CFrame.new(hx + 0.03, hy - 0.2, 0.1), color, mat)
		if style == "long" then
			cosmetic(head, "HairBack", Vector3.new(W, head.Size.Y + 0.5, 0.1), CFrame.new(0, -0.2, hz + 0.04), color, mat)
		else
			cosmetic(head, "HairBack", Vector3.new(W, hy * 1.2, 0.08), CFrame.new(0, hy * 0.4, hz + 0.03), color, mat)
		end
	elseif style == "spike" then
		cosmetic(head, "HairTop", Vector3.new(W, 0.12, D), CFrame.new(0, hy + 0.04, 0), color, mat)
		for i = -1, 1 do
			cosmetic(head, "HairSpike" .. i, Vector3.new(0.18, 0.28, 0.18), CFrame.new(i * 0.24, hy + 0.17, 0.05 * i) * CFrame.Angles(0, math.rad(45), math.rad(i * 12)), color, mat)
		end
		cosmetic(head, "HairBack", Vector3.new(W, hy, 0.07), CFrame.new(0, hy * 0.45, hz + 0.03), color, mat)
	elseif style == "mohawk" then
		cosmetic(head, "HairMohawk", Vector3.new(0.16, 0.3, D), CFrame.new(0, hy + 0.13, 0.03), color, mat)
	elseif style == "cap" then
		cosmetic(head, "HairCap", Vector3.new(W + 0.02, 0.24, D + 0.02), CFrame.new(0, hy + 0.06, 0), color, mat)
		cosmetic(head, "HairBrim", Vector3.new(head.Size.X * 0.85, 0.05, 0.38), CFrame.new(0, hy - 0.04, -hz - 0.17), color, mat)
	elseif style == "afro" then
		cosmetic(head, "HairAfro", Vector3.new(head.Size.X + 0.55, 0.7, head.Size.Z + 0.5), CFrame.new(0, hy + 0.22, 0.15), color, mat)
	end
end

-- ===== ใบหน้าพิกเซล =====
local function px(parent, name, x, y, w, hgt, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(x / GRID, y / GRID)
	f.Size = UDim2.fromScale(w / GRID, hgt / GRID)
	f.ZIndex = z or 2
	f.Parent = parent
	return f
end

local function makeSurface(part, face, name)
	local g = Instance.new("SurfaceGui")
	g.Name = name
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 1
	g.ClipsDescendants = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Global
	g.Parent = part
	return g
end

local EXPR = {
	-- brows = ความสูงของคิ้ว 3 พิกเซล (ซ้าย->ขวา ของคิ้วซ้าย, คิ้วขวาสะท้อน)
	normal = { brows = { 5, 5, 5 }, eyes = "dot", mouth = "line" },
	angry = { brows = { 4, 5, 6 }, eyes = "dot", mouth = "line" },
	hurt = { brows = { 6, 5, 4 }, eyes = "squint", mouth = "open" },
	dizzy = { brows = { 6, 5, 4 }, eyes = "spiral", mouth = "wavy" },
	ko = { brows = { 6, 6, 6 }, eyes = "x", mouth = "tongue" },
	taunt = { brows = { 4, 5, 5 }, eyes = "dot", mouth = "smile" },
	block = { brows = { 4, 5, 6 }, eyes = "squint", mouth = "line" },
}

function CB.setFace(char, expr)
	local head = char:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Face")
	if not gui then
		return
	end
	if gui:GetAttribute("Expr") == expr then
		return
	end
	gui:SetAttribute("Expr", expr)
	local look = char:GetAttribute("BrowColor") or Config.Look.Brows
	local eyeC = Config.Look.Eyes
	local mouthC = Config.Look.Mouth
	local old = gui:FindFirstChild("Features")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Frame")
	f.Name = "Features"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 3
	f.Parent = gui
	local e = EXPR[expr] or EXPR.normal
	-- คิ้ว
	for i = 1, 3 do
		px(f, "BrowL" .. i, 2 + i, e.brows[i], 1, 1, look, 3)
		px(f, "BrowR" .. i, 13 - i, e.brows[i], 1, 1, look, 3)
	end
	-- ตา
	if e.eyes == "dot" then
		local white = Color3.fromRGB(240, 236, 228)
		px(f, "EyeL", 3, 7, 3, 1, white, 3)
		px(f, "EyeR", 10, 7, 3, 1, white, 3)
		px(f, "IrisL", 4.5, 7, 1.2, 1, eyeC, 4)
		px(f, "IrisR", 10.3, 7, 1.2, 1, eyeC, 4)
		local lid = (char:FindFirstChild("Head") and char.Head.Color or Color3.new(0.8, 0.6, 0.5)):Lerp(Color3.new(0, 0, 0), 0.25)
		px(f, "LidL", 3, 6.6, 3, 0.4, lid, 3)
		px(f, "LidR", 10, 6.6, 3, 0.4, lid, 3)
	elseif e.eyes == "squint" then
		px(f, "EyeL", 3, 8, 3, 1, eyeC, 3)
		px(f, "EyeR", 10, 8, 3, 1, eyeC, 3)
	else
		local txt = (e.eyes == "x") and "X" or "@"
		for i, x in ipairs({ 3.2, 9.2 }) do
			local t = Instance.new("TextLabel")
			t.Name = "Eye" .. i
			t.BackgroundTransparency = 1
			t.Text = txt
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = eyeC
			t.Position = UDim2.fromScale(x / GRID, 6 / GRID)
			t.Size = UDim2.fromScale(3.6 / GRID, 3.6 / GRID)
			t.ZIndex = 3
			t.Parent = f
		end
	end
	-- ปาก
	if e.mouth == "line" then
		px(f, "Mouth", 6, 12, 4, 1, mouthC, 3)
	elseif e.mouth == "open" then
		px(f, "Mouth", 6, 11, 4, 2, Color3.fromRGB(70, 20, 20), 3)
	elseif e.mouth == "wavy" then
		px(f, "M1", 5, 12, 1, 1, mouthC, 3)
		px(f, "M2", 6, 11, 2, 1, mouthC, 3)
		px(f, "M3", 8, 12, 2, 1, mouthC, 3)
		px(f, "M4", 10, 11, 1, 1, mouthC, 3)
	elseif e.mouth == "tongue" then
		px(f, "Mouth", 6, 12, 4, 1, mouthC, 3)
		px(f, "Tongue", 8, 13, 2, 1, Color3.fromRGB(230, 110, 120), 3)
	elseif e.mouth == "smile" then
		px(f, "M1", 5, 11, 1, 1, mouthC, 3)
		px(f, "M2", 6, 12, 4, 1, mouthC, 3)
		px(f, "M3", 10, 11, 1, 1, mouthC, 3)
	end
end

-- ===== เลือดบนหน้า (สะสมตามดาเมจ) =====
local BLOOD_STAGES = {
	-- {x, y, w, h, color?}
	{ { 7, 11, 1, 1 }, { 8, 11, 1, 2 } },                       -- 1 เลือดกำเดา
	{ { 3, 4, 2, 1 }, { 3, 5, 1, 2 } },                         -- 2 คิ้วแตก
	{ { 7, 12, 1, 2 }, { 8, 13, 1, 2 } },                       -- 3 กำเดาไหลยาว
	{ { 9, 6, 4, 1, "bruise" }, { 9, 9, 4, 1, "bruise" }, { 12, 7, 1, 2, "bruise" }, { 9, 7, 1, 2, "bruise" } }, -- 4 ตาเขียว
	{ { 10, 13, 1, 2 }, { 10, 15, 1, 1 } },                     -- 5 มุมปากแตก
	{ { 3, 7, 1, 3 }, { 2, 10, 1, 2 } },                        -- 6 เลือดจากคิ้วไหลลงแก้ม
	{ { 13, 10, 2, 2, "bruise" } },                             -- 7 แก้มช้ำ
	{ { 7, 14, 2, 2 }, { 6, 15, 1, 1 } },                       -- 8 คางเลือดเต็ม
}

function CB.addFaceBlood(char, amount)
	if not Config.FaceDamage then
		return
	end
	local head = char:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Face")
	if not gui then
		return
	end
	local lvl = char:GetAttribute("FaceLvl") or 0
	local target = math.min(#BLOOD_STAGES + 6, lvl + amount)
	local holder = gui:FindFirstChild("Blood")
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "Blood"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.ZIndex = 1
		holder.Parent = gui
	end
	local blood = Config.Blood > 0 and Config.BloodColor or Color3.fromRGB(140, 90, 160)
	local bruise = Color3.fromRGB(110, 70, 120)
	for s = lvl + 1, target do
		local stage = BLOOD_STAGES[s]
		if stage then
			for _, r in ipairs(stage) do
				local c = (r[5] == "bruise") and bruise or blood
				local fr = px(holder, "B" .. s, r[1], r[2], r[3], r[4], c, 2)
				if r[5] == "bruise" then
					fr.BackgroundTransparency = 0.35
				end
			end
		elseif Config.Blood > 0 then
			-- สะสมเพิ่มแบบสุ่ม
			px(holder, "BX" .. s, math.random(2, 13), math.random(9, 15), 1, math.random(1, 2), blood, 2)
		end
	end
	char:SetAttribute("FaceLvl", target)
end

-- เลือดหยดบนเสื้อ
function CB.addShirtBlood(char, n)
	if Config.Blood <= 0 then
		return
	end
	local torso = char:FindFirstChild("UpperTorso")
	local gui = torso and torso:FindFirstChild("ShirtBlood")
	if not gui then
		return
	end
	local count = #gui:GetChildren()
	for _ = 1, n do
		if count > 60 then
			return
		end
		count = count + 1
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Config.BloodColor:Lerp(Color3.new(0.2, 0, 0), math.random() * 0.4)
		local w = math.random(2, 7) / 100
		f.Size = UDim2.fromScale(w, w * math.random(10, 30) / 10)
		f.Position = UDim2.fromScale(0.3 + math.random() * 0.4 + (math.random() - 0.5) * 0.3, math.random() * 0.55)
		f.Parent = gui
	end
end

-- ===== ป้ายชื่อ + หลอดเลือดเหนือหัว =====
local function buildTag(head, displayName, player)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.new(0, 170, 0, 46)
	bb.StudsOffset = Vector3.new(0, HEAD / 2 + 1.5, 0)
	bb.MaxDistance = 90
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	if player then
		bb.PlayerToHideFrom = player
	end
	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 24)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.Text = displayName
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.2
	name.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.new(0.1, 0, 0, 28)
	back.Size = UDim2.new(0.8, 0, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local c2 = corner:Clone()
	c2.Parent = fill
	bb.Parent = head
	return bb
end

function CB.updateTag(char, frac)
	local head = char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("Tag")
	if not tag then
		return
	end
	local fill = tag.Bar.Fill
	frac = math.clamp(frac, 0, 1)
	fill.Size = UDim2.fromScale(frac, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 50):Lerp(Color3.fromRGB(90, 220, 90), frac)
end

-- ===== โครงตัวคนสัดส่วนจริง (เท้าแตะพื้นที่ y=0, สูงรวม ~6.35) =====
-- ชื่อชิ้น -> {ขนาด, ตำแหน่งจุดกลางตอนยืน, สี}
local BODY = {
	{ "LowerTorso", Vector3.new(1.3, 0.75, 0.75), Vector3.new(0, 3.375, 0), "Pants" },
	{ "UpperTorso", Vector3.new(1.55, 1.35, 0.8), Vector3.new(0, 4.425, 0), "Shirt" },
	{ "Head", HEAD_SIZE, Vector3.new(0, 5.85, 0), "Skin" },
	{ "RightUpperArm", Vector3.new(0.42, 1.25, 0.42), Vector3.new(0.985, 4.375, 0), "Skin" },
	{ "RightLowerArm", Vector3.new(0.38, 1.1, 0.38), Vector3.new(0.985, 3.2, 0), "Skin" },
	{ "RightHand", Vector3.new(0.3, 0.45, 0.2), Vector3.new(0.985, 2.425, 0), "Skin" },
	{ "LeftUpperArm", Vector3.new(0.42, 1.25, 0.42), Vector3.new(-0.985, 4.375, 0), "Skin" },
	{ "LeftLowerArm", Vector3.new(0.38, 1.1, 0.38), Vector3.new(-0.985, 3.2, 0), "Skin" },
	{ "LeftHand", Vector3.new(0.3, 0.45, 0.2), Vector3.new(-0.985, 2.425, 0), "Skin" },
	{ "RightUpperLeg", Vector3.new(0.6, 1.4, 0.6), Vector3.new(0.35, 2.4, 0), "Pants" },
	{ "RightLowerLeg", Vector3.new(0.5, 1.45, 0.5), Vector3.new(0.35, 0.975, 0), "Pants" },
	{ "RightFoot", Vector3.new(0.45, 0.25, 0.95), Vector3.new(0.35, 0.125, -0.15), "Shoes" },
	{ "LeftUpperLeg", Vector3.new(0.6, 1.4, 0.6), Vector3.new(-0.35, 2.4, 0), "Pants" },
	{ "LeftLowerLeg", Vector3.new(0.5, 1.45, 0.5), Vector3.new(-0.35, 0.975, 0), "Pants" },
	{ "LeftFoot", Vector3.new(0.45, 0.25, 0.95), Vector3.new(-0.35, 0.125, -0.15), "Shoes" },
}
local ROOT_SIZE = Vector3.new(1.6, 2, 1)
local ROOT_Y = 4.1   -- ก้น HumanoidRootPart อยู่ที่แนวสะโพก (3.1) = HipHeight
local HIP_HEIGHT = 3.1
-- ข้อต่อ: ชื่อ, Part0, Part1(เก็บ Motor ไว้ในชิ้นนี้), C0, C1
local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", CFrame.new(0, -1, 0), CFrame.new(0, -0.275, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", CFrame.new(0, 0.375, 0), CFrame.new(0, -0.675, 0) },
	{ "Neck", "UpperTorso", "Head", CFrame.new(0, 0.675, 0), CFrame.new(0, -0.75, 0) },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", CFrame.new(0.985, 0.475, 0), CFrame.new(0, 0.525, 0) },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", CFrame.new(0, -0.625, 0), CFrame.new(0, 0.55, 0) },
	{ "RightWrist", "RightLowerArm", "RightHand", CFrame.new(0, -0.55, 0), CFrame.new(0, 0.225, 0) },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", CFrame.new(-0.985, 0.475, 0), CFrame.new(0, 0.525, 0) },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", CFrame.new(0, -0.625, 0), CFrame.new(0, 0.55, 0) },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", CFrame.new(0, -0.55, 0), CFrame.new(0, 0.225, 0) },
	{ "RightHip", "LowerTorso", "RightUpperLeg", CFrame.new(0.35, -0.275, 0), CFrame.new(0, 0.7, 0) },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", CFrame.new(0, -0.7, 0), CFrame.new(0, 0.725, 0) },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", CFrame.new(0, -0.725, 0), CFrame.new(0, 0.125, 0.15) },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", CFrame.new(-0.35, -0.275, 0), CFrame.new(0, 0.7, 0) },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", CFrame.new(0, -0.7, 0), CFrame.new(0, 0.725, 0) },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", CFrame.new(0, -0.725, 0), CFrame.new(0, 0.125, 0.15) },
}
CB.JOINTS = JOINTS
CB.HIP_HEIGHT = HIP_HEIGHT
-- สีของชิ้นตามชื่อ
local COLOR_OF = {
	UpperTorso = "Shirt", Sleeve = "Shirt", Collar = "ShirtDark", Belly = "Shirt", Hem = "Shirt", ShoulderBall = "Shirt",
	LowerTorso = "Pants", RightUpperLeg = "Pants", RightLowerLeg = "Pants", LeftUpperLeg = "Pants", LeftLowerLeg = "Pants", KneeBall = "Pants", HipBall = "Pants",
	Head = "Skin", RightUpperArm = "Skin", RightLowerArm = "Skin", LeftUpperArm = "Skin", LeftLowerArm = "Skin", ElbowBall = "Skin",
	RightHand = "Skin", LeftHand = "Skin", NeckSkin = "Skin", Thumb = "Skin",
	EarL = "SkinDark", EarR = "SkinDark", Nose = "SkinNose", Jaw = "Skin",
	RightFoot = "Shoes", LeftFoot = "Shoes", Sole = "Sole", Belt = "Belt",
}

local function ball(main, name, d, offset, color)
	local p = cosmetic(main, name, Vector3.new(d, d, d), offset, color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- สร้างโครงตัวเปล่า (ชิ้นส่วน + ข้อต่อ + ของตกแต่ง + Humanoid) ใช้ได้ทั้งตอนเล่นและตอน export โมเดล
function CB.buildRig(look)
	look = look or Config.Look
	local model = Instance.new("Model")
	model.Name = "Brawler"
	local parts = {}
	local root = newPart({ Name = "HumanoidRootPart", Size = ROOT_SIZE, Transparency = 1, CanCollide = false, CFrame = CFrame.new(0, ROOT_Y, 0) })
	root.Parent = model
	parts.HumanoidRootPart = root
	for _, b in ipairs(BODY) do
		local collide = (b[1] == "UpperTorso" or b[1] == "LowerTorso" or b[1] == "Head")
		local p = newPart({ Name = b[1], Size = b[2], CFrame = CFrame.new(b[3]), Color = look[b[4]], CanCollide = collide })
		p.Parent = model
		parts[b[1]] = p
	end
	for _, j in ipairs(JOINTS) do
		motor(j[1], parts[j[2]], parts[j[3]], j[4], j[5], parts[j[3]])
	end
	local skinDark = look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.12)
	-- เสื้อยืด: แขนสั้น ชายเสื้อ ปก + เข็มขัด
	cosmetic(parts.UpperTorso, "Collar", Vector3.new(0.6, 0.08, 0.06), CFrame.new(0, 0.63, -0.41), look.Shirt:Lerp(Color3.new(0, 0, 0), 0.25))
	cosmetic(parts.LowerTorso, "Hem", Vector3.new(1.34, 0.22, 0.79), CFrame.new(0, 0.27, 0), look.Shirt)
	cosmetic(parts.LowerTorso, "Belt", Vector3.new(1.33, 0.1, 0.78), CFrame.new(0, 0.12, 0), Color3.fromRGB(40, 30, 24))
	cosmetic(parts.UpperTorso, "NeckSkin", Vector3.new(0.36, 0.3, 0.36), CFrame.new(0, 0.8, 0.02), look.Skin)
	for _, side in ipairs({ "Right", "Left" }) do
		local sx = side == "Right" and 1 or -1
		cosmetic(parts[side .. "UpperArm"], "Sleeve", Vector3.new(0.47, 0.62, 0.47), CFrame.new(0, 0.33, 0), look.Shirt)
		-- ข้อต่อกลมแบบหุ่น ragdoll (กันเห็นช่องตอนงอ)
		ball(parts.UpperTorso, "ShoulderBall", 0.5, CFrame.new(0.82 * sx, 0.47, 0), look.Shirt)
		ball(parts[side .. "UpperArm"], "ElbowBall", 0.4, CFrame.new(0, -0.625, 0), look.Skin)
		ball(parts[side .. "UpperLeg"], "KneeBall", 0.52, CFrame.new(0, -0.7, 0), look.Pants)
		ball(parts.LowerTorso, "HipBall", 0.6, CFrame.new(0.35 * sx, -0.27, 0), look.Pants)
		cosmetic(parts[side .. "Hand"], "Thumb", Vector3.new(0.1, 0.2, 0.12), CFrame.new(-0.13 * sx, 0.04, -0.1), look.Skin)
		cosmetic(parts[side .. "Foot"], "Sole", Vector3.new(0.47, 0.06, 0.97), CFrame.new(0, -0.1, 0), Color3.fromRGB(20, 20, 20))
	end
	local hx, hz = HEAD_SIZE.X / 2, HEAD_SIZE.Z / 2
	cosmetic(parts.Head, "Jaw", Vector3.new(HEAD_SIZE.X * 0.82, 0.28, HEAD_SIZE.Z * 0.8), CFrame.new(0, -0.6, -0.03), look.Skin)
	cosmetic(parts.Head, "EarL", Vector3.new(0.07, 0.24, 0.16), CFrame.new(-hx - 0.03, 0, 0.05), skinDark)
	cosmetic(parts.Head, "EarR", Vector3.new(0.07, 0.24, 0.16), CFrame.new(hx + 0.03, 0, 0.05), skinDark)
	cosmetic(parts.Head, "Nose", Vector3.new(0.14, 0.22, 0.1), CFrame.new(0, -0.08, -hz - 0.04), look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.08))
	buildHair(parts.Head, "box", look.Hair)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = HIP_HEIGHT
	hum.AutomaticScalingEnabled = false
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model
	model.PrimaryPart = root
	return model
end

-- ระบายสีตาม look + ทำทรงผมใหม่
function CB.applyLook(model, look)
	local colors = {
		Shirt = look.Shirt,
		ShirtDark = look.Shirt:Lerp(Color3.new(0, 0, 0), 0.25),
		Pants = look.Pants,
		Skin = look.Skin,
		SkinDark = look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.12),
		SkinNose = look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.08),
		Shoes = look.Shoes,
		Sole = Color3.fromRGB(20, 20, 20),
		Belt = Color3.fromRGB(40, 30, 24),
	}
	local head = model:FindFirstChild("Head")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local key = COLOR_OF[d.Name]
			if key and colors[key] then
				d.Color = colors[key]
			end
			if string.sub(d.Name, 1, 4) == "Hair" then
				d:Destroy()
			elseif d.Name == "Nose" and not look.Nose then
				d:Destroy()
			end
		end
	end
	if head then
		buildHair(head, look.HairStyle, look.Hair)
	end
	local torso = model:FindFirstChild("UpperTorso")
	if look.Belly and torso and not torso:FindFirstChild("Belly") then
		cosmetic(torso, "Belly", Vector3.new(1.35, 0.75, 0.35), CFrame.new(0, -0.3, -0.45), look.Shirt)
	end
end

-- ===== แผลเลือดติดตัว (แปะที่ผิวชิ้นที่โดน หันหาทิศที่โดนตี) =====
function CB.addWound(char, part, fromDir)
	if not Config.Wounds or Config.Blood <= 0 or not part or not part.Parent then
		return
	end
	local n = char:GetAttribute("Wounds") or 0
	if n >= 18 then
		return
	end
	char:SetAttribute("Wounds", n + 1)
	-- หาด้านของชิ้นที่หันไปทางผู้ตี
	local localDir = part.CFrame:VectorToObjectSpace(-fromDir)
	local hs = part.Size / 2
	local ax, ay, az = math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z)
	local normal
	if ax >= ay and ax >= az then
		normal = Vector3.new(localDir.X >= 0 and 1 or -1, 0, 0)
	elseif ay >= az then
		normal = Vector3.new(0, localDir.Y >= 0 and 1 or -1, 0)
	else
		normal = Vector3.new(0, 0, localDir.Z >= 0 and 1 or -1)
	end
	local rnd = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2
	-- ขอบเผื่อไม่เกินครึ่งของชิ้น (ชิ้นเล็กอย่างมือ/เท้าก็ไม่พัง)
	local function inside(v, h)
		local m = math.max(0, h - math.min(0.2, h * 0.5))
		return math.clamp(v * h, -m, m)
	end
	local lp = Vector3.new(
		normal.X ~= 0 and normal.X * hs.X or inside(rnd.X, hs.X),
		normal.Y ~= 0 and normal.Y * hs.Y or inside(rnd.Y, hs.Y),
		normal.Z ~= 0 and normal.Z * hs.Z or inside(rnd.Z, hs.Z)
	)
	local s0 = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	local worldPos = part.CFrame * (lp + normal * 0.03)
	local worldN = part.CFrame:VectorToWorldSpace(normal)
	local s = math.min(0.25 + math.random() * 0.3, s0 * 0.9)
	local w = newPart({
		Name = "Wound",
		Size = Vector3.new(s, s * (0.8 + math.random() * 0.8), 0.05),
		Color = Config.BloodColor:Lerp(Color3.new(0.15, 0, 0), math.random() * 0.5),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		CastShadow = false,
	})
	local up = math.abs(worldN.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	w.CFrame = CFrame.lookAt(worldPos, worldPos + worldN, up) * CFrame.Angles(0, 0, math.random() * 6.28)
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = part
	wc.Part1 = w
	wc.Parent = w
	w.Parent = part
end

-- ===== สร้างตัวละครพร้อมเล่น =====
-- คืนค่า model (ยังไม่ parent)
function CB.build(look, displayName, player)
	local template = ServerStorage:FindFirstChild("Brawler")
	local model
	if template and template:IsA("Model") and template:FindFirstChild("HumanoidRootPart") and template:FindFirstChildOfClass("Humanoid") then
		model = template:Clone()
		model:PivotTo(CFrame.new(0, ROOT_Y, 0))
	else
		model = CB.buildRig(look)
	end
	model.Name = player and player.Name or displayName
	CB.applyLook(model, look)

	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	if not head:FindFirstChild("Face") then
		makeSurface(head, Enum.NormalId.Front, "Face")
	end
	if not torso:FindFirstChild("ShirtBlood") then
		local sb = makeSurface(torso, Enum.NormalId.Front, "ShirtBlood")
		sb.PixelsPerStud = 30
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = Config.MaxHealth
	hum.Health = Config.MaxHealth
	hum.WalkSpeed = Config.WalkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = Config.JumpPower
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false

	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	model:SetAttribute("BrowColor", look.Brows)
	model:SetAttribute("DisplayName", displayName)
	CB.setFace(model, "normal")
	buildTag(head, displayName, player)
	CollectionService:AddTag(model, "BrawlChar")
	return model
end

return CB
