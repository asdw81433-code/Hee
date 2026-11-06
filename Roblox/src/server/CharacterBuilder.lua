-- ============================================================
--  ซอยเดือด : สร้างตัวละครเหลี่ยม R6 ด้วยโค้ด (หน้าวาดแบบพิกเซล)
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))

local CB = {}

local HEAD = 1.6 -- หัวเหลี่ยมใหญ่ (ลูกบาศก์)
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
	local h = HEAD / 2
	if style == "bald" then
		return
	end
	local mat = Enum.Material.SmoothPlastic
	if style == "box" or style == "long" then
		cosmetic(head, "HairTop", Vector3.new(HEAD + 0.12, 0.34, HEAD + 0.12), CFrame.new(0, h + 0.13, 0.02), color, mat)
		cosmetic(head, "HairFringe", Vector3.new(HEAD + 0.12, 0.26, 0.16), CFrame.new(0, h - 0.1, -h - 0.04), color, mat)
		cosmetic(head, "HairSideL", Vector3.new(0.14, 0.62, HEAD * 0.75), CFrame.new(-h - 0.06, h - 0.3, 0.2), color, mat)
		cosmetic(head, "HairSideR", Vector3.new(0.14, 0.62, HEAD * 0.75), CFrame.new(h + 0.06, h - 0.3, 0.2), color, mat)
		if style == "long" then
			cosmetic(head, "HairBack", Vector3.new(HEAD + 0.12, HEAD + 0.6, 0.22), CFrame.new(0, -0.15, h + 0.09), color, mat)
		else
			cosmetic(head, "HairBack", Vector3.new(HEAD + 0.12, HEAD * 0.7, 0.2), CFrame.new(0, h * 0.35, h + 0.08), color, mat)
		end
	elseif style == "flat" then
		cosmetic(head, "HairTop", Vector3.new(HEAD + 0.08, 0.22, HEAD + 0.08), CFrame.new(0, h + 0.08, 0), color, mat)
		cosmetic(head, "HairBack", Vector3.new(HEAD + 0.08, HEAD * 0.5, 0.14), CFrame.new(0, h * 0.5, h + 0.05), color, mat)
	elseif style == "spike" then
		cosmetic(head, "HairTop", Vector3.new(HEAD + 0.08, 0.22, HEAD + 0.08), CFrame.new(0, h + 0.08, 0), color, mat)
		for i = -1, 1 do
			cosmetic(head, "Spike" .. i, Vector3.new(0.38, 0.55, 0.38), CFrame.new(i * 0.5, h + 0.4, 0.1 * i) * CFrame.Angles(0, math.rad(45), math.rad(i * 12)), color, mat)
		end
		cosmetic(head, "HairBack", Vector3.new(HEAD + 0.08, HEAD * 0.6, 0.14), CFrame.new(0, h * 0.4, h + 0.05), color, mat)
	elseif style == "mohawk" then
		cosmetic(head, "Mohawk", Vector3.new(0.36, 0.6, HEAD + 0.1), CFrame.new(0, h + 0.28, 0.05), color, mat)
	elseif style == "cap" then
		cosmetic(head, "Cap", Vector3.new(HEAD + 0.14, 0.42, HEAD + 0.14), CFrame.new(0, h + 0.12, 0), color, mat)
		cosmetic(head, "Brim", Vector3.new(HEAD * 0.8, 0.1, 0.7), CFrame.new(0, h - 0.04, -h - 0.3), color, mat)
	elseif style == "afro" then
		cosmetic(head, "Afro", Vector3.new(HEAD + 0.9, 1.25, HEAD + 0.8), CFrame.new(0, h + 0.42, 0.3), color, mat)
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
		px(f, "EyeL", 4, 7, 2, 2, eyeC, 3)
		px(f, "EyeR", 10, 7, 2, 2, eyeC, 3)
		px(f, "GlintL", 4, 7, 1, 1, Color3.fromRGB(255, 255, 255), 4).BackgroundTransparency = 0.25
		px(f, "GlintR", 10, 7, 1, 1, Color3.fromRGB(255, 255, 255), 4).BackgroundTransparency = 0.25
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
	local torso = char:FindFirstChild("Torso")
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
	bb.StudsOffset = Vector3.new(0, HEAD / 2 + 1.6, 0)
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

-- ===== สร้างตัวละคร =====
-- คืนค่า model (ยังไม่ parent)
function CB.build(look, displayName, player)
	local model = Instance.new("Model")
	model.Name = player and player.Name or displayName

	local root = newPart({ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Transparency = 1, CanCollide = false })
	local torso = newPart({ Name = "Torso", Size = Vector3.new(2, 2, 1), Color = look.Shirt })
	local head = newPart({ Name = "Head", Size = Vector3.new(HEAD, HEAD, HEAD), Color = look.Skin })
	local ra = newPart({ Name = "Right Arm", Size = Vector3.new(1, 2, 1), Color = look.Skin, CanCollide = false })
	local la = newPart({ Name = "Left Arm", Size = Vector3.new(1, 2, 1), Color = look.Skin, CanCollide = false })
	local rl = newPart({ Name = "Right Leg", Size = Vector3.new(1, 2, 1), Color = look.Pants, CanCollide = false })
	local ll = newPart({ Name = "Left Leg", Size = Vector3.new(1, 2, 1), Color = look.Pants, CanCollide = false })

	local base = CFrame.new(0, 3, 0)
	root.CFrame = base
	torso.CFrame = base
	head.CFrame = base * CFrame.new(0, 1 + HEAD / 2, 0)
	ra.CFrame = base * CFrame.new(1.5, 0, 0)
	la.CFrame = base * CFrame.new(-1.5, 0, 0)
	rl.CFrame = base * CFrame.new(0.5, -2, 0)
	ll.CFrame = base * CFrame.new(-0.5, -2, 0)
	for _, p in ipairs({ root, torso, head, ra, la, rl, ll }) do
		p.Parent = model
	end

	-- ข้อต่อ (C0/C1 ไม่หมุน -> Transform หมุนในแกนของลำตัวตรงๆ)
	motor("RootJoint", root, torso, CFrame.new(0, -1, 0), CFrame.new(0, -1, 0), root)
	motor("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -HEAD / 2, 0), torso)
	motor("Right Shoulder", torso, ra, CFrame.new(1.5, 0.5, 0), CFrame.new(0, 0.5, 0), torso)
	motor("Left Shoulder", torso, la, CFrame.new(-1.5, 0.5, 0), CFrame.new(0, 0.5, 0), torso)
	motor("Right Hip", torso, rl, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0), torso)
	motor("Left Hip", torso, ll, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0), torso)

	-- เสื้อแขนสั้น รองเท้า ฯลฯ
	cosmetic(ra, "Sleeve", Vector3.new(1.06, 0.78, 1.06), CFrame.new(0, 0.62, 0), look.Shirt)
	cosmetic(la, "Sleeve", Vector3.new(1.06, 0.78, 1.06), CFrame.new(0, 0.62, 0), look.Shirt)
	cosmetic(rl, "Shoe", Vector3.new(1.06, 0.42, 1.2), CFrame.new(0, -0.8, -0.08), look.Shoes)
	cosmetic(ll, "Shoe", Vector3.new(1.06, 0.42, 1.2), CFrame.new(0, -0.8, -0.08), look.Shoes)
	cosmetic(torso, "Collar", Vector3.new(0.9, 0.12, 0.08), CFrame.new(0, 0.94, -0.52), look.Shirt:Lerp(Color3.new(0, 0, 0), 0.25))
	if look.Belly then
		cosmetic(torso, "Belly", Vector3.new(1.7, 1.1, 0.5), CFrame.new(0, -0.35, -0.6), look.Shirt)
	end
	-- หู + จมูกเล็ก (ตามภาพอ้างอิง)
	local h = HEAD / 2
	local earC = look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.12)
	cosmetic(head, "EarL", Vector3.new(0.14, 0.4, 0.32), CFrame.new(-h - 0.07, 0, 0.08), earC)
	cosmetic(head, "EarR", Vector3.new(0.14, 0.4, 0.32), CFrame.new(h + 0.07, 0, 0.08), earC)
	if look.Nose then
		cosmetic(head, "Nose", Vector3.new(0.26, 0.28, 0.12), CFrame.new(0, -0.18, -h - 0.06), look.Skin:Lerp(Color3.new(0.5, 0.25, 0.2), 0.08))
	end
	buildHair(head, look.HairStyle, look.Hair)

	-- หน้า + เลือดบนเสื้อ
	makeSurface(head, Enum.NormalId.Front, "Face")
	local sb = makeSurface(torso, Enum.NormalId.Front, "ShirtBlood")
	sb.PixelsPerStud = 30

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.MaxHealth = Config.MaxHealth
	hum.Health = Config.MaxHealth
	hum.WalkSpeed = Config.WalkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = Config.JumpPower
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("BrowColor", look.Brows)
	model:SetAttribute("DisplayName", displayName)
	CB.setFace(model, "normal")
	buildTag(head, displayName, player)
	CollectionService:AddTag(model, "BrawlChar")
	return model
end

return CB
