-- ============================================================
--  ALLEY BRAWL : แมพตรอกเมืองอเมริกัน (ตึกอิฐ บันไดหนีไฟ แท็กซี่ รถฮอทด็อก) ด้วยโค้ด
--  ถนน 2 เลน + ฟุตบาท + ตึกแถว + เสาไฟสายไฟพันกัน + สังเวียนข้างทาง
-- ============================================================
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local MapBuilder = {}

local ROAD_HW = 16   -- ครึ่งความกว้างถนน
local FACADE = 22    -- แนวหน้าตึก
local LEN = 70       -- ครึ่งความยาวซอย
local rng = Random.new(20261106)
local DEFAULT_WEAPON_SPAWNS = {
	Vector3.new(0, 0, -50), Vector3.new(-11, 0, -22), Vector3.new(11, 0, -15), Vector3.new(-11, 0, 8),
	Vector3.new(11, 0, 14), Vector3.new(0, 0, 58), Vector3.new(0, 1.2, 30),
}
local DEFAULT_SPAWNS = {
	Vector3.new(-9, 0, -60), Vector3.new(9, 0, -58), Vector3.new(-10, 0, -36), Vector3.new(10, 0, -30),
	Vector3.new(-8, 0, -6), Vector3.new(8, 0, -2), Vector3.new(-6, 0, 12), Vector3.new(6, 0, 18),
	Vector3.new(-10, 0, 60), Vector3.new(10, 0, 62),
}
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
	"PAWN SHOP", "PIZZA", "LAUNDROMAT", "24/7 DINER", "TATTOO", "BARBER", "DONUTS", "GROCERY",
	"PHONE REPAIR", "GYM", "ARCADE", "HARDWARE", "DENTIST", "BAIL BONDS", "INSURANCE", "CHECK CASHING",
	"TACOS", "SHOE REPAIR", "PET SHOP", "KARATE DOJO", "FUNERAL HOME", "ICE CREAM",
}
local NEON = { "HOTEL", "OPEN 24H", "MOTEL", "ARCADE", "PIZZA", "DINER", "TATTOO", "VACANCY", "BOXING" }
local BRICK = {
	rgb(150, 72, 58), rgb(126, 82, 64), rgb(176, 112, 84), rgb(110, 62, 52), rgb(140, 132, 124), rgb(188, 160, 124), rgb(96, 88, 90),
}
local SIGN = {
	rgb(200, 30, 30), rgb(25, 70, 150), rgb(230, 180, 20), rgb(20, 120, 60), rgb(30, 30, 34), rgb(120, 30, 120),
}
local IRON = rgb(30, 30, 33)

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

local function makeMelon(pos)
	return P("Watermelon", Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos), rgb(40, 130, 40), M.SmoothPlastic, { Anchored = false, Shape = Enum.PartType.Ball })
end

local hookMelon
hookMelon = function(melon, pos)
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
				hookMelon(makeMelon(pos), pos)
			end)
		end
	end)
end

-- ===== ตึกอิฐอเมริกัน 1 ห้อง (หน้าร้าน + กันสาด + บันไดหนีไฟ + ถังน้ำบนหลังคา) =====
local function building(side, z, w)
	local floors = rng:NextInteger(2, 4)
	local H = floors * 9 + 0.5
	local depth = 12
	local x = side * (FACADE + depth / 2)
	local fx = side * FACADE -- ระนาบหน้าตึก
	local col = BRICK[rng:NextInteger(1, #BRICK)]
	local trim = col:Lerp(rgb(235, 225, 210), 0.55)
	local face = side > 0 and Enum.NormalId.Left or Enum.NormalId.Right -- ด้านที่หันเข้าถนน
	P("Building", Vector3.new(depth, H, w), at(x, H / 2, z), col, M.Brick)
	-- ชั้นล่าง: หน้าร้าน
	P("ShopInside", Vector3.new(0.2, 7, w - 1.6), at(fx - side * 0.1, 4, z), rgb(26, 24, 24), M.SmoothPlastic)
	P("ShopFrame", Vector3.new(0.3, 7.6, 0.5), at(fx - side * 0.15, 4, z - w / 2 + 0.55), trim, M.Concrete)
	P("ShopFrame", Vector3.new(0.3, 7.6, 0.5), at(fx - side * 0.15, 4, z + w / 2 - 0.55), trim, M.Concrete)
	if rng:NextNumber() < 0.35 then
		local sh = 7 * rng:NextNumber(0.3, 0.7)
		P("Shutter", Vector3.new(0.3, sh, w - 1.4), at(fx - side * 0.25, 7.5 - sh / 2, z), rgb(140, 142, 146), M.CorrodedMetal)
	end
	-- ป้ายร้าน + กันสาดผ้าเอียง
	local sign = P("ShopSign", Vector3.new(0.5, 1.6, w - 1.2), at(fx - side * 0.35, 8.6, z), SIGN[rng:NextInteger(1, #SIGN)], M.SmoothPlastic)
	label(sign, face, SHOPS[rng:NextInteger(1, #SHOPS)], rgb(255, 255, 255))
	if rng:NextNumber() < 0.6 then
		P("Awning", Vector3.new(2.6, 0.15, w - 1.4), at(fx - side * 1.25, 7.55, z) * CFrame.Angles(0, 0, math.rad(-22 * side)), SIGN[rng:NextInteger(1, #SIGN)], M.Fabric, { CanCollide = false })
	end
	-- กระจกหน้าร้าน (แตกได้!)
	if rng:NextNumber() < 0.6 then
		P("ShopGlass", Vector3.new(0.3, 5.2, w - 2.2), at(fx - side * 0.62, 3.1, z), rgb(170, 210, 230), M.Glass, { Transparency = 0.45 })
	end
	-- ชั้นบน: หน้าต่างกรอบขาว แอร์ บันไดหนีไฟ
	local fireEscape = rng:NextNumber() < 0.5
	for f = 1, floors - 1 do
		local y = f * 9 + 0.5
		P("Cornice", Vector3.new(0.6, 0.35, w), at(fx - side * 0.15, y, z), trim, M.Concrete)
		for i = -1, 1, 2 do
			local wz = z + i * w * 0.24
			P("Window", Vector3.new(0.3, 3.8, 2.4), at(fx - side * 0.1, y + 4.4, wz), rgb(36, 46, 62), M.Glass, { Reflectance = 0.2 })
			P("Frame", Vector3.new(0.25, 4.3, 2.9), at(fx - side * 0.04, y + 4.4, wz), trim)
			P("Sill", Vector3.new(0.5, 0.25, 3.1), at(fx - side * 0.2, y + 2.25, wz), trim, M.Concrete)
			if rng:NextNumber() < 0.25 then
				P("AC", Vector3.new(1.2, 1.2, 1.8), at(fx - side * 0.7, y + 2.95, wz), rgb(225, 225, 220), M.SmoothPlastic)
			end
		end
		if fireEscape then
			-- ชานบันไดหนีไฟเหล็กดำ + ราว + บันไดเฉียง
			P("FireEscape", Vector3.new(2, 0.2, w * 0.7), at(fx - side * 1, y + 0.9, z), IRON, M.Metal)
			P("FERail", Vector3.new(0.12, 1.2, w * 0.7), at(fx - side * 1.95, y + 1.6, z), IRON, M.Metal)
			P("FERailTop", Vector3.new(0.18, 0.12, w * 0.7), at(fx - side * 1.95, y + 2.2, z), IRON, M.Metal)
			if f < floors - 1 then
				local a = Vector3.new(fx - side * 1.1, y + 1, z - w * 0.3)
				local b2 = Vector3.new(fx - side * 1.1, y + 9.9, z + w * 0.15)
				P("FEStairs", Vector3.new(1.4, 0.15, (b2 - a).Magnitude), CFrame.lookAt((a + b2) / 2, b2), IRON, M.Metal, { CanCollide = false })
			end
		end
	end
	P("Parapet", Vector3.new(depth, 1, w), at(x, H + 0.5, z), trim:Lerp(col, 0.5), M.Concrete)
	-- ถังน้ำบนหลังคาแบบนิวยอร์ก
	if rng:NextNumber() < 0.2 then
		local tx = x + side * 1.5
		P("WaterTower", Vector3.new(4, 3.4, 3.4), at(tx, H + 4.5, z) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 86, 60), M.Wood, { Shape = Enum.PartType.Cylinder })
		for _, o in ipairs({ { -1.2, -1.2 }, { 1.2, -1.2 }, { -1.2, 1.2 }, { 1.2, 1.2 } }) do
			P("TowerLeg", Vector3.new(0.2, 2.6, 0.2), at(tx + o[1], H + 1.8, z + o[2]), IRON, M.Metal)
		end
	end
	-- ป้ายนีออนแนวตั้ง
	if rng:NextNumber() < 0.3 then
		local ns = P("NeonSign", Vector3.new(2.6, 6, 0.4), at(fx - side * 1.8, 12 + rng:NextNumber(0, 3), z + w / 2 - 0.6), SIGN[rng:NextInteger(1, #SIGN)], M.Neon)
		local word = NEON[rng:NextInteger(1, #NEON)]
		label(ns, Enum.NormalId.Front, word, rgb(255, 255, 255))
		label(ns, Enum.NormalId.Back, word, rgb(255, 255, 255))
	end
end

-- เสาไฟถนนเหล็ก (cobra head)
local function streetLamp(x, z)
	local dark = rgb(48, 52, 50)
	P("LampPost", Vector3.new(0.5, 15, 0.5), at(x, 8, z), dark, M.Metal)
	P("LampBase", Vector3.new(0.9, 1, 0.9), at(x, 1, z), dark, M.Metal)
	P("LampArm", Vector3.new(3.6, 0.25, 0.25), at(x - math.sign(x) * 1.8, 15.4, z), dark, M.Metal)
	local lamp = P("Lamp", Vector3.new(1.4, 0.35, 0.8), at(x - math.sign(x) * 3.5, 15.2, z), rgb(255, 225, 170), M.Neon)
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.3
	light.Color = rgb(255, 210, 150)
	light.Shadows = false
	light.Parent = lamp
end

-- เสาไฟฟ้าไม้ + สายไฟเรียบร้อย
local function utilityPole(x, z)
	P("UtilityPole", Vector3.new(0.8, 22, 0.8), at(x, 11.5, z), rgb(92, 70, 50), M.Wood)
	P("CrossArm", Vector3.new(0.35, 0.35, 5), at(x, 21.5, z), rgb(92, 70, 50), M.Wood)
	if rng:NextNumber() < 0.4 then
		P("Transformer", Vector3.new(1.2, 2, 1.2), at(x - math.sign(x) * 0.8, 18.5, z), rgb(120, 125, 120), M.Metal, { Shape = Enum.PartType.Block })
	end
end

-- ===== แท็กซี่เหลือง =====
local function taxi(cf)
	local yellow, dark, glass = rgb(245, 196, 20), rgb(25, 25, 28), rgb(60, 80, 100)
	P("TaxiBody", Vector3.new(4.4, 1.8, 10), cf * at(0, 1.9, 0), yellow, M.Metal)
	P("TaxiCabin", Vector3.new(4, 1.6, 5.2), cf * at(0, 3.6, 0.4), yellow, M.Metal)
	P("TaxiWindshield", Vector3.new(3.8, 1.3, 0.15), cf * at(0, 3.6, -2.25), glass, M.Glass, { Transparency = 0.2 })
	P("TaxiRearGlass", Vector3.new(3.8, 1.3, 0.15), cf * at(0, 3.6, 3.05), glass, M.Glass, { Transparency = 0.2 })
	for _, sx in ipairs({ -1, 1 }) do
		P("TaxiSideGlass", Vector3.new(0.12, 1.1, 4.4), cf * at(sx * 2.02, 3.65, 0.4), glass, M.Glass, { Transparency = 0.2 })
		P("Headlight", Vector3.new(0.9, 0.4, 0.1), cf * at(sx * 1.5, 2.2, -5.02), rgb(255, 250, 220), M.Neon)
		P("Taillight", Vector3.new(0.8, 0.4, 0.1), cf * at(sx * 1.6, 2.2, 5.02), rgb(200, 20, 20), M.Neon)
	end
	P("Checker", Vector3.new(4.42, 0.3, 6), cf * at(0, 2.2, 0), dark, M.SmoothPlastic)
	P("Bumper", Vector3.new(4.5, 0.4, 0.3), cf * at(0, 1.2, -5.1), rgb(160, 160, 165), M.Metal)
	for _, wpos in ipairs({ { -2.1, -3.2 }, { 2.1, -3.2 }, { -2.1, 3.2 }, { 2.1, 3.2 } }) do
		P("Wheel", Vector3.new(0.7, 1.8, 1.8), cf * at(wpos[1], 0.9, wpos[2]), dark, M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	local roof = P("TaxiSign", Vector3.new(2, 0.6, 0.7), cf * at(0, 4.7, 0.4), rgb(255, 250, 230), M.Neon)
	label(roof, Enum.NormalId.Front, "TAXI", dark)
	label(roof, Enum.NormalId.Back, "TAXI", dark)
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

local function hotdogCart(cf)
	local steel = rgb(190, 192, 196)
	P("Cart", Vector3.new(5, 2.6, 2.6), cf * at(0, 1.8, 0), steel, M.DiamondPlate)
	P("Grill", Vector3.new(4.4, 0.3, 2), cf * at(0, 3.25, 0), rgb(40, 40, 42), M.Metal)
	for i = -2, 2 do
		P("HotDog", Vector3.new(0.9, 0.22, 0.22), cf * at(i * 0.8, 3.5, 0.2), rgb(170, 70, 40), M.SmoothPlastic)
	end
	for _, wz in ipairs({ -1.4, 1.4 }) do
		P("Wheel", Vector3.new(0.3, 1.4, 1.4), cf * at(-2.2, 0.7, wz) * CFrame.Angles(0, math.pi / 2, 0), rgb(25, 25, 28), M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	P("UmbrellaPole", Vector3.new(0.2, 8, 0.2), cf * at(2.6, 4.5, 0), rgb(60, 60, 60), M.Metal)
	P("Umbrella", Vector3.new(0.4, 9, 9), cf * at(2.6, 8.6, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(230, 190, 30), M.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local s2 = P("StallSign", Vector3.new(4.6, 1, 0.2), cf * at(0, 5.2, -1.2), rgb(200, 30, 30))
	label(s2, Enum.NormalId.Front, "HOT DOGS $2", rgb(255, 230, 120))
end

-- ถังขยะใหญ่ (หนัก ตัวละครบินชนแล้วเด้ง)
local function dumpster(pos, ry, color)
	local cf = CFrame.new(pos) * CFrame.Angles(0, ry, 0)
	local body = P("Dumpster", Vector3.new(6, 3.6, 3.4), cf * at(0, 1.9, 0), color, M.Metal, { Anchored = false })
	local lid = P("DumpsterLid", Vector3.new(6.1, 0.25, 3.5), cf * at(0, 3.85, 0) * CFrame.Angles(math.rad(-6), 0, 0), rgb(30, 30, 32), M.SmoothPlastic, { Anchored = false, Massless = true })
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = lid
	w.Parent = lid
end

local function hydrant(pos)
	local red = rgb(200, 30, 30)
	P("Hydrant", Vector3.new(0.8, 1.6, 0.8), CFrame.new(pos + Vector3.new(0, 0.8, 0)), red, M.Metal)
	P("HydrantCap", Vector3.new(1.0, 0.3, 1.0), CFrame.new(pos + Vector3.new(0, 1.7, 0)), red, M.Metal)
	P("HydrantArm", Vector3.new(1.4, 0.35, 0.35), CFrame.new(pos + Vector3.new(0, 1.1, 0)), red, M.Metal)
end

-- ของฟิสิกส์ที่เตะกระจาย
local function prop(name, size, pos, color, material, shape)
	local p = P(name, size, CFrame.new(pos), color, material, { Anchored = false })
	if shape then
		p.Shape = shape
	end
	return p
end

-- สร้างตัวแมพทั้งหมด (ใช้ตอนไม่มีแมพในไฟล์ หรือตอน export ไฟล์ .rbxlx)
function MapBuilder.buildGeometry()
	folder = Instance.new("Folder")
	folder.Name = "AlleyMap"
	folder.Parent = workspace

	-- พื้นถนน + ฟุตบาท
	P("Road", Vector3.new(ROAD_HW * 2, 2, LEN * 2 + 10), at(0, -1, 0), rgb(62, 62, 66), M.Asphalt)
	for _, s in ipairs({ -1, 1 }) do
		P("Sidewalk", Vector3.new(FACADE - ROAD_HW, 1.5, LEN * 2 + 10), at(s * (ROAD_HW + FACADE) / 2, -0.25, 0), rgb(176, 170, 160), M.Pavement)
		-- ขอบฟุตบาทแดงขาว
		local segs = math.floor((LEN * 2) / 6)
		for i = 0, segs - 1 do
			local z = -LEN + i * 6 + 3
			local fireLane = (i % 7 == 3)
			P("Curb", Vector3.new(0.4, 0.54, 6), at(s * (ROAD_HW + 0.2), 0.24, z), fireLane and rgb(200, 40, 40) or rgb(190, 188, 182), M.Concrete)
		end
	end
	-- เส้นถนน
	-- เส้นเหลืองคู่กลางถนน + เส้นขาวขอบทาง + ฝาท่อ
	for _, x in ipairs({ -0.35, 0.35 }) do
		P("CenterLine", Vector3.new(0.25, 0.05, LEN * 2), at(x, 0.01, 0), rgb(245, 190, 30), M.SmoothPlastic, { CanCollide = false })
	end
	for _, x in ipairs({ -ROAD_HW + 1.2, ROAD_HW - 1.2 }) do
		P("EdgeLine", Vector3.new(0.3, 0.05, LEN * 2), at(x, 0.01, 0), rgb(235, 235, 235), M.SmoothPlastic, { CanCollide = false })
	end
	for _, z in ipairs({ -48, -12, 16, 44 }) do
		P("Manhole", Vector3.new(0.06, 2.4, 2.4), at(rng:NextNumber(-8, 8), 0.02, z) * CFrame.Angles(0, 0, math.pi / 2), rgb(55, 55, 58), M.DiamondPlate, { Shape = Enum.PartType.Cylinder, CanCollide = false })
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
			building(s, z, w)
		end
	end
	-- ปลายซอย
	local wallC = rgb(132, 66, 52)
	P("EndWallS", Vector3.new(FACADE * 2 + 4, 16, 2), at(0, 8, -LEN - 2), wallC, M.Brick)
	local gs = P("Graffiti", Vector3.new(30, 6, 0.3), at(0, 7, -LEN - 0.85), rgb(255, 255, 255), M.SmoothPlastic, { Transparency = 1 })
	label(gs, Enum.NormalId.Back, "ALLEY BRAWL", rgb(255, 70, 40), nil, Enum.Font.PermanentMarker)
	P("EndWallN", Vector3.new(FACADE * 2 + 4, 16, 2), at(0, 8, LEN + 2), wallC, M.Brick)
	local dead = P("DeadEnd", Vector3.new(8, 2.2, 0.3), at(-5, 9, LEN + 0.85), rgb(250, 200, 30), M.SmoothPlastic)
	label(dead, Enum.NormalId.Front, "DEAD END", rgb(20, 20, 20))
	local nofight = P("NoFighting", Vector3.new(7, 2.2, 0.3), at(6, 9, LEN + 0.85), rgb(240, 240, 240), M.SmoothPlastic)
	label(nofight, Enum.NormalId.Front, "NO FIGHTING ⛔", rgb(190, 20, 20))
	-- รั้วลวดตาข่ายหน้ากำแพง
	for i = -3, 3 do
		P("FencePost", Vector3.new(0.25, 10, 0.25), at(i * 6, 5, LEN - 1.5), rgb(150, 150, 155), M.Metal)
	end
	P("ChainLink", Vector3.new(36, 9, 0.1), at(0, 4.8, LEN - 1.5), rgb(170, 170, 175), M.DiamondPlate, { Transparency = 0.55 })
	local graf = P("Graffiti2", Vector3.new(14, 4, 0.3), at(0, 4, -LEN - 0.85), rgb(255, 255, 255), M.SmoothPlastic, { Transparency = 1 })
	label(graf, Enum.NormalId.Back, "NO RULES", rgb(60, 200, 255), nil, Enum.Font.PermanentMarker)
	-- ป้ายซุ้มทางเข้า
	local banner = P("Banner", Vector3.new(ROAD_HW * 2 + 2, 4, 0.4), at(0, 17, -LEN + 6), rgb(30, 30, 34), M.Fabric, { CanCollide = false })
	label(banner, Enum.NormalId.Front, "WELCOME TO THE ALLEY", rgb(255, 210, 60))
	label(banner, Enum.NormalId.Back, "ALLEY BRAWL • FIGHT NIGHT", rgb(255, 210, 60))

	-- กำแพงล่องหน (กันร่างบินออก/ขึ้นหลังคา)
	local inv = { Transparency = 1, CanQuery = false, CastShadow = false }
	for _, s in ipairs({ -1, 1 }) do
		P("InvisWall", Vector3.new(1, 200, LEN * 2 + 8), at(s * (FACADE - 0.6), 112, 0), rgb(0, 0, 0), M.SmoothPlastic, inv)
	end
	P("InvisWall", Vector3.new(FACADE * 2, 220, 1), at(0, 110, -LEN - 0.5), rgb(0, 0, 0), M.SmoothPlastic, inv)
	P("InvisWall", Vector3.new(FACADE * 2, 220, 1), at(0, 110, LEN + 0.5), rgb(0, 0, 0), M.SmoothPlastic, inv)

	-- เสาไฟถนน + เสาไฟฟ้าไม้ สายไฟเรียบๆ ไม่พันกัน
	for _, sgn in ipairs({ -1, 1 }) do
		for z = -60, 60, 20 do
			streetLamp(sgn * (ROAD_HW + 1.2), z + (sgn > 0 and 10 or 0))
		end
		for z = -55, 55, 22 do
			utilityPole(sgn * (FACADE - 1.5), z)
		end
		for z = -55, 33, 22 do
			for k = 1, 2 do
				wire(Vector3.new(sgn * (FACADE - 1.5) + (k - 1.5) * 3, 21.4, z), Vector3.new(sgn * (FACADE - 1.5) + (k - 1.5) * 3, 21.4, z + 22), 1.4)
			end
		end
	end
	for _, z in ipairs({ -33, 11 }) do
		wire(Vector3.new(-(FACADE - 1.5), 21.4, z), Vector3.new(FACADE - 1.5, 21.4, z), 2.5)
	end

	-- สังเวียนข้างทาง
	local ringZ = 30
	local ring = P("Ring", Vector3.new(16, 1.2, 16), at(0, 0.6, ringZ), rgb(40, 90, 170), M.Fabric)
	label(ring, Enum.NormalId.Top, "FIGHT NIGHT", rgb(255, 255, 255))
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

	-- เก้าอี้พับเหล็กรอบสังเวียน (เตะกระจายได้)
	for i = 1, 8 do
		local a2 = i / 8 * math.pi * 2
		prop("RingsideChair", Vector3.new(1.4, 1.6, 1.4), Vector3.new(math.cos(a2) * 11.5, 0.8, ringZ + math.sin(a2) * 11.5), rgb(120, 122, 128), M.Metal)
	end

	-- รถ ร้านรถเข็น
	taxi(at(-11.5, 0, -44) * CFrame.Angles(0, math.rad(4), 0))
	motorbike(at(13, 0, -40) * CFrame.Angles(0, math.rad(-20), 0), rgb(30, 30, 30))
	motorbike(at(14.5, 0, -36) * CFrame.Angles(0, math.rad(-15), 0), rgb(140, 20, 20))
	hotdogCart(at(-12.5, 0, 52) * CFrame.Angles(0, math.rad(90), 0))
	-- แผงผลไม้ (แตงโมแตกได้)
	P("FruitStand", Vector3.new(5, 1.6, 3), at(12, 1.6, 50), rgb(110, 80, 50), M.Wood)
	P("CartRim", Vector3.new(5, 0.8, 0.2), at(12, 2.8, 48.6), rgb(110, 80, 50), M.Wood)
	P("CartRim", Vector3.new(5, 0.8, 0.2), at(12, 2.8, 51.4), rgb(110, 80, 50), M.Wood)
	local fs = P("FruitSign", Vector3.new(4.6, 1, 0.2), at(12, 4.6, 48.4), rgb(30, 120, 50))
	label(fs, Enum.NormalId.Front, "FRESH FRUIT", rgb(255, 255, 255))
	for i = 0, 5 do
		makeMelon(Vector3.new(10.6 + (i % 3) * 1.45, 3.3, 49.3 + math.floor(i / 3) * 1.45))
	end

	-- ของข้างทาง: ถังขยะใหญ่ ถังขยะเหล็ก กล่อง พาเลท หัวดับเพลิง ตู้หนังสือพิมพ์
	dumpster(Vector3.new(-18.8, 0.5, -24), 0, rgb(40, 90, 60))
	dumpster(Vector3.new(18.8, 0.5, 2), 0, rgb(40, 70, 130))
	dumpster(Vector3.new(-18.8, 0.5, 36), 0, rgb(40, 90, 60))
	for i = 1, 8 do
		local sgn = (i % 2 == 0) and 1 or -1
		local z = -55 + i * 13 + rng:NextNumber(-2, 2)
		local can = prop("TrashCan", Vector3.new(1.6, 2.4, 1.6), Vector3.new(sgn * (ROAD_HW + 3), 1.7, z), rgb(150, 152, 156), M.Metal)
		local lid = P("Lid", Vector3.new(1.75, 0.25, 1.75), can.CFrame * at(0, 1.3, 0), rgb(120, 122, 126), M.Metal, { Anchored = false, Massless = true })
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = can
		wc.Part1 = lid
		wc.Parent = lid
	end
	for _, st in ipairs({ { -13, -14 }, { 13, 6 }, { -13, 20 } }) do
		for i = 0, 4 do
			prop("Box", Vector3.new(1.6, 1.6, 1.6), Vector3.new(st[1] + (i % 2) * 1.7 - 0.8, 0.85 + math.floor(i / 2) * 1.62, st[2] + (i % 3) * 0.2), rgb(176, 136, 90), M.SmoothPlastic)
		end
		prop("Pallet", Vector3.new(3.6, 0.5, 3.6), Vector3.new(st[1], 0.3, st[2] + 3.5), rgb(160, 130, 90), M.Wood)
	end
	for _, z in ipairs({ -50, -6, 26, 58 }) do
		hydrant(Vector3.new((z % 2 == 0) and 17.5 or -17.5, 0.5, z))
	end
	for i, z in ipairs({ -30, 8, 40 }) do
		local nb = P("NewsBox", Vector3.new(1.4, 2.6, 1.2), at(i % 2 == 0 and 20.6 or -20.6, 1.8, z), (i % 2 == 0) and rgb(30, 70, 160) or rgb(190, 30, 30), M.Metal)
		label(nb, i % 2 == 0 and Enum.NormalId.Left or Enum.NormalId.Right, "NEWS", rgb(255, 255, 255))
	end
	for i = 1, 6 do
		prop("TrafficCone", Vector3.new(0.9, 1.4, 0.9), Vector3.new(rng:NextNumber(-10, 10), 0.75, -38 + i * 1.6), rgb(255, 110, 20), M.SmoothPlastic)
	end

	-- จุดอาวุธ (แท่นเหลือง) + จุดเกิด (บล็อกล่องหน) : ย้ายใน Studio ได้ เกมอ่านตำแหน่งจากชิ้นพวกนี้
	for _, p in ipairs(DEFAULT_WEAPON_SPAWNS) do
		P("WeaponPad", Vector3.new(0.12, 3.4, 3.4), at(p.X, p.Y + 0.04, p.Z) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 210, 40), M.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
	end
	for _, p in ipairs(DEFAULT_SPAWNS) do
		P("SpawnPoint", Vector3.new(2, 0.2, 2), at(p.X, p.Y + 0.1, p.Z), rgb(80, 220, 120), M.SmoothPlastic, { Transparency = 0.6, CanCollide = false, CanQuery = false, CanTouch = false })
	end
	return folder
end

local function applyLighting()
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
end
MapBuilder.applyLighting = applyLighting

-- เรียกตอนเริ่มเกม: ใช้แมพที่อยู่ในไฟล์ (Workspace > AlleyMap) ถ้ามี ไม่มีก็สร้างใหม่
function MapBuilder.build(r)
	remotes = r
	-- ลบ Baseplate / SpawnLocation จากเทมเพลต (ถ้ามี) กันพื้นซ้อนกัน
	for _, d in ipairs(workspace:GetChildren()) do
		if (d.Name == "Baseplate" and d:IsA("BasePart")) or d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end
	local existing = workspace:FindFirstChild("AlleyMap")
	if existing then
		folder = existing
	else
		MapBuilder.buildGeometry()
	end
	-- ผูกของแตกได้ + อ่านจุดเกิด/จุดอาวุธจากชิ้นในแมพ
	local spawns, weaponSpawns = {}, {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ShopGlass" then
				makeBreakable(d, "glass")
			elseif d.Name == "Watermelon" then
				hookMelon(d, d.Position)
			elseif d.Name == "WeaponPad" then
				table.insert(weaponSpawns, d.Position - Vector3.new(0, 0.04, 0))
			elseif d.Name == "SpawnPoint" then
				table.insert(spawns, d.Position - Vector3.new(0, 0.1, 0))
				d.Transparency = 1
			end
		end
	end
	if #spawns == 0 then
		spawns = DEFAULT_SPAWNS
	end
	if #weaponSpawns == 0 then
		weaponSpawns = DEFAULT_WEAPON_SPAWNS
	end
	applyLighting()
	return { spawns = spawns, weaponSpawns = weaponSpawns, folder = folder }
end

return MapBuilder
