-- ============================================================
--  ซอยเดือด : สร้างแมพ "ซอยตึกแถว" ด้วยโค้ดทั้งหมด
--  ถนน 2 เลน + ฟุตบาท + ตึกแถว + เสาไฟสายไฟพันกัน + สังเวียนข้างทาง
-- ============================================================
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local MapBuilder = {}

local ROAD_HW = 16   -- ครึ่งความกว้างถนน
local FACADE = 22    -- แนวหน้าตึก
local LEN = 70       -- ครึ่งความยาวซอย
local rng = Random.new(20261106)
local folder
local remotes

local M = Enum.Material

local function P(name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = (props and props.Parent) or folder
	return p
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function label(part, face, text, color, bg, font)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.LightInfluence = 0.4
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = bg and 0 or 1
	if bg then
		t.BackgroundColor3 = bg
	end
	t.Text = text
	t.TextScaled = true
	t.Font = font or Enum.Font.GothamBlack
	t.TextColor3 = color
	t.Parent = g
	g.Parent = part
	return g
end

-- เส้นลวด/สายไฟระหว่าง 2 จุด (หย่อนตรงกลาง)
local function wire(a, b, sag, color)
	local mid = (a + b) / 2 - Vector3.new(0, sag, 0)
	for _, seg in ipairs({ { a, mid }, { mid, b } }) do
		local p0, p1 = seg[1], seg[2]
		local len = (p1 - p0).Magnitude
		P("Wire", Vector3.new(0.12, 0.12, len), CFrame.lookAt((p0 + p1) / 2, p1), color or rgb(20, 20, 22), M.SmoothPlastic, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
end

local SHOPS = {
	"ข้าวมันไก่", "ก๋วยเตี๋ยวเรือ", "ร้านตัดผม", "นวดแผนไทย", "ร้านชำ", "ซ่อมมือถือ", "หมูกระทะ",
	"ร้านยา", "ส้มตำแซ่บ", "เสริมสวย", "ผัดไทย", "ชานมไข่มุก", "ซักรีด", "ร้านเกม", "อู่ซ่อมรถ",
	"คลินิกทำฟัน 🦷", "ประกันชีวิต", "ร้านโลงศพ", "ข้าวต้มโต้รุ่ง", "ยาดม ยาหม่อง",
}
local PASTEL = {
	rgb(236, 222, 190), rgb(198, 222, 200), rgb(236, 200, 200), rgb(196, 214, 236), rgb(240, 232, 170),
	rgb(222, 200, 236), rgb(210, 210, 205), rgb(240, 214, 180),
}
local SIGN = {
	rgb(220, 40, 40), rgb(30, 110, 200), rgb(250, 200, 30), rgb(30, 160, 80), rgb(240, 120, 20), rgb(140, 40, 160),
}

-- ===== ของแตกได้ =====
local function breakGlass(glass)
	if glass:GetAttribute("Broken") then
		return
	end
	glass:SetAttribute("Broken", true)
	local cf, size = glass.CFrame, glass.Size
	glass.Transparency = 1
	glass.CanCollide = false
	glass.CanQuery = false
	for _ = 1, 12 do
		local s = P("Shard", Vector3.new(0.1, rng:NextNumber(0.4, 1.4), rng:NextNumber(0.4, 1.4)),
			cf * CFrame.new(0, rng:NextNumber(-size.Y / 2, size.Y / 2), rng:NextNumber(-size.Z / 2, size.Z / 2)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			rgb(190, 220, 235), M.Glass, { Anchored = false, Transparency = 0.35, CanQuery = false })
		s.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(2, 16), rng:NextNumber(-14, 14))
		Debris:AddItem(s, 6)
	end
	if remotes then
		remotes.Fx:FireAllClients("break", { pos = glass.Position, glass = true })
	end
	task.delay(25, function()
		glass.Transparency = 0.45
		glass.CanCollide = true
		glass.CanQuery = true
		glass:SetAttribute("Broken", false)
	end)
end

local function makeBreakable(part, kind)
	part:SetAttribute("Breakable", kind)
	part.Touched:Connect(function(hit)
		if hit.Anchored then
			return
		end
		local v = hit.AssemblyLinearVelocity.Magnitude
		if kind == "glass" and v > 26 then
			breakGlass(part)
		end
	end)
end

local function spawnMelon(pos)
	local melon = P("Watermelon", Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos), rgb(40, 130, 40), M.SmoothPlastic, { Anchored = false, Shape = Enum.PartType.Ball })
	local done = false
	melon.Touched:Connect(function(hit)
		if done or hit.Anchored or hit:IsDescendantOf(melon) then
			return
		end
		local rel = (hit.AssemblyLinearVelocity - melon.AssemblyLinearVelocity).Magnitude
		if rel > 24 then
			done = true
			local p = melon.Position
			for i = 1, 8 do
				local red = i % 2 == 0
				local c = P("MelonChunk", Vector3.new(0.5, 0.5, 0.5), CFrame.new(p), red and rgb(230, 60, 80) or rgb(40, 130, 40), M.SmoothPlastic, { Anchored = false, CanQuery = false })
				c.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(6, 22), rng:NextNumber(-18, 18))
				Debris:AddItem(c, 5)
			end
			if remotes then
				remotes.Fx:FireAllClients("melon", { pos = p })
			end
			melon:Destroy()
			task.delay(30, function()
				spawnMelon(pos)
			end)
		end
	end)
	return melon
end

-- ===== ตึกแถว 1 ห้อง =====
local function shophouse(side, z, w)
	local floors = rng:NextInteger(2, 4)
	local H = floors * 9 + 0.5
	local depth = 12
	local x = side * (FACADE + depth / 2)
	local fx = side * FACADE -- ระนาบหน้าตึก
	local col = PASTEL[rng:NextInteger(1, #PASTEL)]
	local face = side > 0 and Enum.NormalId.Left or Enum.NormalId.Right -- ด้านที่หันเข้าถนน
	P("Building", Vector3.new(depth, H, w), at(x, H / 2, z), col, M.Concrete)
	-- ชั้นล่าง: ร้านค้า
	local shopC = rgb(30, 26, 24)
	P("ShopInside", Vector3.new(0.2, 7, w - 1.6), at(fx - side * 0.1, 4, z), shopC, M.SmoothPlastic)
	local shutterOpen = rng:NextNumber(0.25, 0.6)
	local sh = 7 * shutterOpen
	P("Shutter", Vector3.new(0.3, sh, w - 1.4), at(fx - side * 0.25, 7.5 - sh / 2, z), rgb(150, 152, 156), M.CorrodedMetal)
	-- ป้ายร้าน
	local sign = P("ShopSign", Vector3.new(0.5, 1.8, w - 1), at(fx - side * 0.35, 8.5, z), SIGN[rng:NextInteger(1, #SIGN)], M.SmoothPlastic)
	label(sign, face, SHOPS[rng:NextInteger(1, #SHOPS)], rgb(255, 255, 255))
	-- กระจกหน้าร้าน (แตกได้!)
	if rng:NextNumber() < 0.55 then
		local g = P("ShopGlass", Vector3.new(0.3, 5.2, w - 2.2), at(fx - side * 0.62, 3.1, z), rgb(170, 210, 230), M.Glass, { Transparency = 0.45 })
		makeBreakable(g, "glass")
	end
	-- ชั้นบน: หน้าต่าง แอร์ ระเบียง
	for f = 1, floors - 1 do
		local y = f * 9 + 0.5
		P("Ledge", Vector3.new(0.8, 0.4, w), at(fx - side * 0.2, y, z), col:Lerp(rgb(0, 0, 0), 0.15), M.Concrete)
		for i = -1, 1, 2 do
			local wz = z + i * w * 0.22
			P("Window", Vector3.new(0.3, 3.4, 2.8), at(fx - side * 0.1, y + 4.5, wz), rgb(40, 60, 90), M.Glass, { Reflectance = 0.15 })
			P("Frame", Vector3.new(0.25, 3.8, 3.2), at(fx - side * 0.04, y + 4.5, wz), rgb(235, 235, 230))
			if rng:NextNumber() < 0.35 then
				P("AC", Vector3.new(1.3, 1.4, 2.2), at(fx - side * 0.75, y + 2, wz), rgb(232, 232, 228), M.SmoothPlastic)
			end
		end
		if rng:NextNumber() < 0.4 then
			P("Balcony", Vector3.new(1.6, 0.3, w * 0.7), at(fx - side * 0.8, y + 1, z), col:Lerp(rgb(0, 0, 0), 0.2), M.Concrete)
			P("Rail", Vector3.new(0.15, 1.4, w * 0.7), at(fx - side * 1.55, y + 1.85, z), rgb(60, 60, 64), M.Metal)
			-- ผ้าตากหลากสี ฮาๆ
			for k = 1, 3 do
				P("Laundry", Vector3.new(0.1, 1.2, 0.9), at(fx - side * 1.5, y + 2.6, z - w * 0.25 + k * w * 0.13), SIGN[rng:NextInteger(1, #SIGN)], M.Fabric, { CanCollide = false })
			end
		end
	end
	P("Parapet", Vector3.new(depth, 1, w), at(x, H + 0.5, z), col:Lerp(rgb(0, 0, 0), 0.1), M.Concrete)
	-- ป้ายนีออนแนวตั้ง
	if rng:NextNumber() < 0.35 then
		local ns = P("NeonSign", Vector3.new(3, 5, 0.4), at(fx - side * 1.8, 12 + rng:NextNumber(0, 3), z + w / 2 - 0.6), SIGN[rng:NextInteger(1, #SIGN)], M.Neon)
		label(ns, Enum.NormalId.Front, SHOPS[rng:NextInteger(1, #SHOPS)], rgb(255, 255, 255))
		label(ns, Enum.NormalId.Back, SHOPS[rng:NextInteger(1, #SHOPS)], rgb(255, 255, 255))
	end
end

local function pole(x, z)
	P("Pole", Vector3.new(0.9, 24, 0.9), at(x, 12.5, z), rgb(160, 158, 150), M.Concrete)
	P("CrossArm", Vector3.new(0.4, 0.4, 6), at(x, 22.5, z), rgb(70, 70, 70), M.Metal)
	if rng:NextNumber() < 0.4 then
		P("Transformer", Vector3.new(1.6, 2.4, 1.6), at(x - math.sign(x) * 0.9, 18, z), rgb(110, 115, 110), M.Metal)
	end
	-- โคมไฟถนน
	local arm = P("LampArm", Vector3.new(3.5, 0.3, 0.3), at(x - math.sign(x) * 1.8, 16, z), rgb(70, 70, 70), M.Metal)
	local lamp = P("Lamp", Vector3.new(1.2, 0.4, 0.8), at(x - math.sign(x) * 3.4, 15.7, z), rgb(255, 220, 160), M.Neon)
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.3
	light.Color = rgb(255, 210, 150)
	light.Shadows = false
	light.Parent = lamp
	return arm
end

-- ===== ตุ๊กตุ๊ก =====
local function tuktuk(cf)
	local blue, yellow, dark = rgb(30, 90, 190), rgb(250, 200, 30), rgb(25, 25, 28)
	P("TukBase", Vector3.new(4.2, 1.2, 7), cf * at(0, 1.6, 0), blue, M.Metal)
	P("TukNose", Vector3.new(2.2, 2.6, 1.6), cf * at(0, 2.6, -3.4), blue, M.Metal)
	P("TukRoof", Vector3.new(4.6, 0.3, 5.4), cf * at(0, 6.4, 0.6), yellow, M.Metal)
	for _, px in ipairs({ -2, 2 }) do
		P("TukPost", Vector3.new(0.2, 4.2, 0.2), cf * at(px, 4.3, 3), dark, M.Metal)
		P("TukPost", Vector3.new(0.2, 4.2, 0.2), cf * at(px, 4.3, -1.8), dark, M.Metal)
	end
	P("TukSeat", Vector3.new(3.8, 1.4, 1.6), cf * at(0, 2.9, 2.2), rgb(150, 30, 30), M.Fabric)
	P("TukWindshield", Vector3.new(3.8, 2, 0.15), cf * at(0, 4.6, -2), rgb(180, 220, 240), M.Glass, { Transparency = 0.5 })
	for _, w in ipairs({ { 0, -3.2 }, { -2.1, 2.4 }, { 2.1, 2.4 } }) do
		P("Wheel", Vector3.new(0.6, 1.8, 1.8), cf * at(w[1], 0.9, w[2]), dark, M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	local plate = P("TukSign", Vector3.new(4.2, 0.9, 0.2), cf * at(0, 7.0, -2.0), yellow, M.SmoothPlastic)
	label(plate, Enum.NormalId.Front, "TAXI ตุ๊กตุ๊ก", dark)
end

local function motorbike(cf, color)
	local dark = rgb(25, 25, 28)
	P("BikeBody", Vector3.new(0.9, 1.4, 3.6), cf * at(0, 1.9, 0), color, M.Metal)
	P("BikeSeat", Vector3.new(1, 0.4, 1.8), cf * at(0, 2.8, 0.6), dark, M.Fabric)
	P("BikeBar", Vector3.new(2.4, 0.2, 0.2), cf * at(0, 3.4, -1.6), dark, M.Metal)
	for _, z in ipairs({ -1.6, 1.6 }) do
		P("Wheel", Vector3.new(0.4, 1.8, 1.8), cf * at(0, 0.9, z), dark, M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
end

local function stall(cf)
	local steel = rgb(190, 192, 196)
	P("Cart", Vector3.new(5, 2.6, 2.6), cf * at(0, 1.8, 0), steel, M.DiamondPlate)
	P("Display", Vector3.new(4.6, 1.6, 2.2), cf * at(0, 3.9, 0), rgb(200, 230, 240), M.Glass, { Transparency = 0.5 })
	P("UmbrellaPole", Vector3.new(0.2, 8, 0.2), cf * at(2.6, 4.5, 0), rgb(60, 60, 60), M.Metal)
	P("Umbrella", Vector3.new(0.4, 9, 9), cf * at(2.6, 8.6, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(220, 50, 50), M.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local s = P("StallSign", Vector3.new(4.6, 1, 0.2), cf * at(0, 5.2, -1.2), rgb(250, 200, 30))
	label(s, Enum.NormalId.Front, "หมูปิ้ง ไม้ละ 10.-", rgb(120, 20, 20))
end

-- ของฟิสิกส์ที่เตะกระจาย
local function prop(name, size, pos, color, material, shape)
	local p = P(name, size, CFrame.new(pos), color, material, { Anchored = false })
	if shape then
		p.Shape = shape
	end
	return p
end

function MapBuilder.build(r)
	remotes = r
	-- ลบ Baseplate / SpawnLocation จากเทมเพลต (ถ้ามี) กันพื้นซ้อนกัน
	for _, d in ipairs(workspace:GetChildren()) do
		if (d.Name == "Baseplate" and d:IsA("BasePart")) or d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "SoiMap"
	folder.Parent = workspace

	-- พื้นถนน + ฟุตบาท
	P("Road", Vector3.new(ROAD_HW * 2, 2, LEN * 2 + 10), at(0, -1, 0), rgb(62, 62, 66), M.Asphalt)
	for _, s in ipairs({ -1, 1 }) do
		P("Sidewalk", Vector3.new(FACADE - ROAD_HW, 1.5, LEN * 2 + 10), at(s * (ROAD_HW + FACADE) / 2, -0.25, 0), rgb(176, 170, 160), M.Pavement)
		-- ขอบฟุตบาทแดงขาว
		local segs = math.floor((LEN * 2) / 6)
		for i = 0, segs - 1 do
			local z = -LEN + i * 6 + 3
			P("Curb", Vector3.new(0.4, 0.54, 6), at(s * (ROAD_HW + 0.2), 0.24, z), (i % 2 == 0) and rgb(210, 40, 40) or rgb(240, 240, 240), M.SmoothPlastic)
		end
	end
	-- เส้นถนน
	for z = -LEN + 5, LEN - 5, 10 do
		P("LaneMark", Vector3.new(0.4, 0.05, 4.5), at(0, 0.01, z), rgb(250, 200, 30), M.SmoothPlastic, { CanCollide = false })
	end
	for i = -6, 6 do
		P("Zebra", Vector3.new(1.3, 0.05, 6), at(i * 2.3, 0.01, -32), rgb(240, 240, 240), M.SmoothPlastic, { CanCollide = false })
	end
	-- แอ่งน้ำ
	for _ = 1, 6 do
		P("Puddle", Vector3.new(rng:NextNumber(3, 7), 0.04, rng:NextNumber(2, 5)), at(rng:NextNumber(-12, 12), 0.02, rng:NextNumber(-60, 60)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(40, 52, 64), M.Glass, { CanCollide = false, Reflectance = 0.35, Transparency = 0.2 })
	end

	-- ตึกแถวสองฝั่ง
	local w = 10
	for _, s in ipairs({ -1, 1 }) do
		for z = -LEN + w / 2, LEN - w / 2, w do
			shophouse(s, z, w)
		end
	end
	-- ปลายซอย
	local wallC = rgb(150, 92, 72)
	P("EndWallS", Vector3.new(FACADE * 2 + 4, 16, 2), at(0, 8, -LEN - 2), wallC, M.Brick)
	local gs = P("Graffiti", Vector3.new(30, 6, 0.3), at(0, 7, -LEN - 0.85), rgb(255, 255, 255), M.SmoothPlastic, { Transparency = 1 })
	label(gs, Enum.NormalId.Back, "ซอยเดือด 🔥 SOI BRAWL", rgb(255, 70, 40))
	P("EndWallN", Vector3.new(FACADE * 2 + 4, 16, 2), at(0, 8, LEN + 2), wallC, M.Brick)
	local dead = P("DeadEnd", Vector3.new(12, 3, 0.3), at(0, 9, LEN + 0.85), rgb(250, 200, 30), M.SmoothPlastic)
	label(dead, Enum.NormalId.Front, "ทางตัน ⛔ ห้ามต่อยกันในซอย", rgb(160, 20, 20))
	-- ป้ายซุ้มทางเข้า
	local banner = P("Banner", Vector3.new(ROAD_HW * 2 + 2, 4, 0.4), at(0, 17, -LEN + 6), rgb(190, 30, 30), M.Fabric, { CanCollide = false })
	label(banner, Enum.NormalId.Front, "ยินดีต้อนรับสู่ ซอยเดือด", rgb(255, 230, 120))
	label(banner, Enum.NormalId.Back, "ซอยเดือด  SOI BRAWL", rgb(255, 230, 120))

	-- กำแพงล่องหน (กันร่างบินออก/ขึ้นหลังคา)
	local inv = { Transparency = 1, CanQuery = false, CastShadow = false }
	for _, s in ipairs({ -1, 1 }) do
		P("InvisWall", Vector3.new(1, 200, LEN * 2 + 8), at(s * (FACADE - 0.6), 112, 0), rgb(0, 0, 0), M.SmoothPlastic, inv)
	end
	P("InvisWall", Vector3.new(FACADE * 2, 220, 1), at(0, 110, -LEN - 0.5), rgb(0, 0, 0), M.SmoothPlastic, inv)
	P("InvisWall", Vector3.new(FACADE * 2, 220, 1), at(0, 110, LEN + 0.5), rgb(0, 0, 0), M.SmoothPlastic, inv)

	-- เสาไฟ + สายไฟพันกันระโยงระยาง
	local poles = {}
	for _, s in ipairs({ -1, 1 }) do
		for z = -60, 60, 20 do
			pole(s * (ROAD_HW + 1.2), z)
			table.insert(poles, { x = s * (ROAD_HW + 1.2), z = z })
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		for z = -60, 40, 20 do
			for k = 1, 3 do
				local y = 21 + k * 0.6
				wire(Vector3.new(s * (ROAD_HW + 1.2), y, z), Vector3.new(s * (ROAD_HW + 1.2), y, z + 20), 1.2 + k * 0.5)
			end
		end
	end
	for z = -60, 60, 20 do
		for k = 1, 4 do
			local y = 19 + k * 0.9
			wire(Vector3.new(-(ROAD_HW + 1.2), y, z + rng:NextNumber(-1, 1)), Vector3.new(ROAD_HW + 1.2, y + rng:NextNumber(-1, 1), z + rng:NextNumber(-3, 3)), 1.5 + k * 0.6)
		end
	end

	-- สังเวียนข้างทาง
	local ringZ = 30
	local ring = P("Ring", Vector3.new(16, 1.2, 16), at(0, 0.6, ringZ), rgb(40, 90, 170), M.Fabric)
	label(ring, Enum.NormalId.Top, "สังเวียนซอย", rgb(255, 255, 255))
	P("RingApron", Vector3.new(17, 1, 17), at(0, 0.4, ringZ), rgb(30, 30, 34), M.SmoothPlastic)
	local cornerC = { rgb(220, 40, 40), rgb(40, 80, 220), rgb(240, 240, 240), rgb(240, 240, 240) }
	local corners = { { -7.7, -7.7 }, { 7.7, 7.7 }, { 7.7, -7.7 }, { -7.7, 7.7 } }
	for i, c in ipairs(corners) do
		P("RingPost", Vector3.new(0.6, 5, 0.6), at(c[1], 3.4, ringZ + c[2]), cornerC[i], M.Metal)
	end
	local ropeC = { rgb(220, 40, 40), rgb(240, 240, 240) }
	for k, y in ipairs({ 3.0, 4.4 }) do
		for i = 1, 4 do
			local a = corners[({ 1, 3, 2, 4 })[i]]
			local b = corners[({ 3, 2, 4, 1 })[i]]
			local pa = Vector3.new(a[1], y, ringZ + a[2])
			local pb = Vector3.new(b[1], y, ringZ + b[2])
			P("Rope", Vector3.new(0.25, 0.25, (pb - pa).Magnitude), CFrame.lookAt((pa + pb) / 2, pb), ropeC[k], M.Fabric, { CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 1, 1, 100) })
		end
	end

	-- ยานพาหนะ ร้านรถเข็น
	tuktuk(at(-11, 0, -44) * CFrame.Angles(0, math.rad(8), 0))
	motorbike(at(13, 0, -40) * CFrame.Angles(0, math.rad(-20), 0), rgb(200, 30, 30))
	motorbike(at(14.5, 0, -36) * CFrame.Angles(0, math.rad(-15), 0), rgb(30, 30, 30))
	stall(at(-12.5, 0, 52) * CFrame.Angles(0, math.rad(90), 0))
	-- รถเข็นแตงโม
	P("MelonCart", Vector3.new(5, 1.6, 3), at(12, 1.6, 50), rgb(130, 90, 50), M.Wood)
	P("CartRim", Vector3.new(5, 0.8, 0.2), at(12, 2.8, 48.6), rgb(130, 90, 50), M.Wood)
	P("CartRim", Vector3.new(5, 0.8, 0.2), at(12, 2.8, 51.4), rgb(130, 90, 50), M.Wood)
	for i = 0, 5 do
		spawnMelon(Vector3.new(10.6 + (i % 3) * 1.45, 3.3, 49.3 + math.floor(i / 3) * 1.45))
	end

	-- ของเตะได้: ถังขยะ กล่อง เก้าอี้พลาสติก
	for i = 1, 8 do
		local s = (i % 2 == 0) and 1 or -1
		local z = -55 + i * 13 + rng:NextNumber(-2, 2)
		local bin = prop("TrashBin", Vector3.new(2, 2.6, 2), Vector3.new(s * (ROAD_HW + 3), 2, z), (i % 3 == 0) and rgb(240, 130, 30) or rgb(40, 130, 60), M.SmoothPlastic)
		local lid = P("Lid", Vector3.new(2.1, 0.3, 2.1), bin.CFrame * at(0, 1.45, 0), rgb(30, 30, 30), M.SmoothPlastic, { Anchored = false, Massless = true })
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = bin
		wc.Part1 = lid
		wc.Parent = lid
	end
	for _, st in ipairs({ { -13, -14 }, { 13, 6 }, { -13, 20 } }) do
		for i = 0, 4 do
			prop("Box", Vector3.new(1.6, 1.6, 1.6), Vector3.new(st[1] + (i % 2) * 1.7 - 0.8, 0.85 + math.floor(i / 2) * 1.62, st[2] + (i % 3) * 0.2), rgb(176, 136, 90), M.Cardboard)
		end
	end
	for i = 1, 10 do
		prop("Stool", Vector3.new(1.1, 1.3, 1.1), Vector3.new(-9 + (i % 5) * 1.8, 0.7, 47 + math.floor(i / 5) * 3), (i % 2 == 0) and rgb(220, 40, 40) or rgb(40, 90, 210), M.SmoothPlastic)
	end
	prop("Table", Vector3.new(4, 0.25, 2.6), Vector3.new(-6, 2.2, 50), rgb(240, 240, 240), M.SmoothPlastic)
	for _, pz in ipairs({ { -7.7, 49 }, { -4.3, 49 }, { -7.7, 51 }, { -4.3, 51 } }) do
		prop("TableLeg", Vector3.new(0.25, 2, 0.25), Vector3.new(pz[1], 1, pz[2]), rgb(200, 200, 200), M.Metal)
	end

	-- จุดอาวุธ
	local weaponSpawns = {
		Vector3.new(0, 0, -50), Vector3.new(-11, 0, -22), Vector3.new(11, 0, -15), Vector3.new(-11, 0, 8),
		Vector3.new(11, 0, 14), Vector3.new(0, 0, 58), Vector3.new(0, 1.2, 30),
	}
	for _, p in ipairs(weaponSpawns) do
		P("WeaponPad", Vector3.new(0.12, 3.4, 3.4), at(p.X, p.Y + 0.04, p.Z) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 210, 40), M.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
	end
	-- จุดเกิด
	local spawns = {
		Vector3.new(-9, 0, -60), Vector3.new(9, 0, -58), Vector3.new(-10, 0, -36), Vector3.new(10, 0, -30),
		Vector3.new(-8, 0, -6), Vector3.new(8, 0, -2), Vector3.new(-6, 0, 12), Vector3.new(6, 0, 18),
		Vector3.new(-10, 0, 60), Vector3.new(10, 0, 62),
	}

	-- แสงยามเย็น
	Lighting.ClockTime = 17.4
	Lighting.Brightness = 2.4
	Lighting.Ambient = rgb(90, 80, 80)
	Lighting.OutdoorAmbient = rgb(160, 150, 145)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = rgb(255, 210, 170)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.3
	atmo.Offset = 0.15
	atmo.Color = rgb(255, 200, 160)
	atmo.Decay = rgb(130, 90, 100)
	atmo.Glare = 0.3
	atmo.Haze = 1.4
	atmo.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 22
	bloom.Threshold = 1.7
	bloom.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = rgb(255, 246, 236)
	cc.Parent = Lighting

	return { spawns = spawns, weaponSpawns = weaponSpawns, folder = folder }
end

return MapBuilder
