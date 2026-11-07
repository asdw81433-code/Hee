-- รันใน mock (tools/test/mock.lua): สร้างแมพ + โมเดลผู้เล่นด้วยโค้ดจริงของเกม
-- แล้วแปลงเป็น XML ของ Roblox (.rbxlx) เพื่อให้แมพเป็นชิ้นงานจริงใน Studio
local RS = game:GetService("ReplicatedStorage")
mountModule(RS, "BrawlConfig", "shared/BrawlConfig.lua")
mountModule(RS, "BrawlAnim", "shared/BrawlAnim.lua")
local Config = require(RS.BrawlConfig)
local SSS = game:GetService("ServerScriptService")
local main = mountModule(SSS, "BrawlServer", "server/init.server.lua", "Script")
for _, n in ipairs({ "MapBuilder", "CharacterBuilder" }) do
	mountModule(main, n, "server/" .. n .. ".lua")
end
local MapBuilder = require(main.MapBuilder)
local CB = require(main.CharacterBuilder)

local mapFolder = MapBuilder.buildGeometry()
MapBuilder.applyLighting()
local rig = CB.buildRig(Config.Look)
rig.Name = "Brawler"

-- ===== enum -> ตัวเลขใน XML =====
local ENUMS = {
	Material = { Plastic = 256, SmoothPlastic = 272, Neon = 288, Wood = 512, Concrete = 816, Pavement = 836, Brick = 848, CorrodedMetal = 1040, DiamondPlate = 1056, Metal = 1088, Fabric = 1312, Asphalt = 1376, Glass = 1568 },
	PartType = { Ball = 0, Block = 1, Cylinder = 2 },
	NormalId = { Right = 0, Top = 1, Back = 2, Left = 3, Bottom = 4, Front = 5 },
	SurfaceGuiSizingMode = { FixedSize = 0, PixelsPerStud = 1 },
	Font = { GothamBold = 19, GothamBlack = 20, PermanentMarker = 38 },
	SurfaceType = { Smooth = 0 },
	HumanoidRigType = { R6 = 0, R15 = 1 },
	HumanoidDisplayDistanceType = { Viewer = 0, Subject = 1, None = 2 },
	HumanoidHealthDisplayType = { DisplayWhenDamaged = 0, AlwaysOn = 1, AlwaysOff = 2 },
}
local function enumNum(e)
	local t = ENUMS[e.EnumType]
	local v = t and t[e.Name]
	if v == nil then
		error("exporter: no number for Enum." .. e.EnumType .. "." .. e.Name)
	end
	return v
end

local refN = 0
local refs = {}
local function ref(inst)
	if not refs[inst] then
		refN = refN + 1
		refs[inst] = string.format("RBXSOI%06d", refN)
	end
	return refs[inst]
end
local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local function num(n)
	if n ~= n or n == math.huge or n == -math.huge then
		error("exporter: bad number")
	end
	local s = string.format("%.5f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end

local function props(inst)
	return rawget(inst, "__props")
end

-- ===== ตัวเขียน property แต่ละชนิด =====
local W = {}
function W.string(n, v) return string.format('<string name="%s">%s</string>', n, esc(v)) end
function W.bool(n, v) return string.format('<bool name="%s">%s</bool>', n, v and "true" or "false") end
function W.float(n, v) return string.format('<float name="%s">%s</float>', n, num(v)) end
function W.token(n, v) return string.format('<token name="%s">%.0f</token>', n, type(v) == "number" and v or enumNum(v)) end
function W.Vector3(n, v) return string.format('<Vector3 name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>', n, num(v.X), num(v.Y), num(v.Z)) end
function W.CFrame(n, c)
	local R = c.R
	return string.format('<CoordinateFrame name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z><R00>%s</R00><R01>%s</R01><R02>%s</R02><R10>%s</R10><R11>%s</R11><R12>%s</R12><R20>%s</R20><R21>%s</R21><R22>%s</R22></CoordinateFrame>',
		n, num(c.p.X), num(c.p.Y), num(c.p.Z), num(R[1][1]), num(R[1][2]), num(R[1][3]), num(R[2][1]), num(R[2][2]), num(R[2][3]), num(R[3][1]), num(R[3][2]), num(R[3][3]))
end
function W.Color3uint8(c)
	local r = math.floor(math.max(0, math.min(1, c.R)) * 255 + 0.5)
	local g = math.floor(math.max(0, math.min(1, c.G)) * 255 + 0.5)
	local b = math.floor(math.max(0, math.min(1, c.B)) * 255 + 0.5)
	return string.format('<Color3uint8 name="Color3uint8">%.0f</Color3uint8>', 4278190080 + r * 65536 + g * 256 + b)
end
function W.Color3(n, c) return string.format('<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>', n, num(c.R), num(c.G), num(c.B)) end
function W.UDim2(n, u) return string.format('<UDim2 name="%s"><XS>%s</XS><XO>%.0f</XO><YS>%s</YS><YO>%.0f</YO></UDim2>', n, num(u.X.Scale), math.floor(u.X.Offset), num(u.Y.Scale), math.floor(u.Y.Offset)) end
function W.Ref(n, inst) return string.format('<Ref name="%s">%s</Ref>', n, inst and ref(inst) or "null") end
function W.Phys(n, pp)
	local t = pp
	return string.format('<PhysicalProperties name="%s"><CustomPhysics>true</CustomPhysics><Density>%s</Density><Friction>%s</Friction><Elasticity>%s</Elasticity><FrictionWeight>%s</FrictionWeight><ElasticityWeight>%s</ElasticityWeight></PhysicalProperties>',
		n, num(t[1]), num(t[2]), num(t[3]), num(t[4] or 1), num(t[5] or 1))
end

-- คุณสมบัติที่ export ต่อคลาส: {ชื่อใน Lua, ชนิด, ชื่อใน XML, ค่าเริ่มต้นถ้าไม่ได้ตั้ง}
local PART = {
	{ "Anchored", "bool", nil, false }, { "CFrame", "CFrame" }, { "Size", "Vector3", "size" }, { "Color", "Color3uint8" },
	{ "Material", "token", nil, Enum.Material.Plastic }, { "Transparency", "float", nil, 0 }, { "Reflectance", "float", nil, 0 },
	{ "CanCollide", "bool", nil, true }, { "CanQuery", "bool", nil, true }, { "CanTouch", "bool", nil, true },
	{ "CastShadow", "bool", nil, true }, { "Massless", "bool", nil, false }, { "Shape", "token", "shape" },
	{ "CustomPhysicalProperties", "Phys" },
}
local CLASS = {
	Folder = {},
	Model = { { "PrimaryPart", "Ref" } },
	Part = PART,
	SurfaceGui = { { "Face", "token" }, { "SizingMode", "token" }, { "PixelsPerStud", "float" }, { "LightInfluence", "float" } },
	TextLabel = { { "Size", "UDim2" }, { "BackgroundTransparency", "float" }, { "BackgroundColor3", "Color3" }, { "Text", "string" }, { "TextScaled", "bool" }, { "Font", "token" }, { "TextColor3", "Color3" } },
	PointLight = { { "Range", "float" }, { "Brightness", "float" }, { "Color", "Color3" }, { "Shadows", "bool" } },
	WeldConstraint = { { "Part0", "Ref" }, { "Part1", "Ref" } },
	Motor6D = { { "Part0", "Ref" }, { "Part1", "Ref" }, { "C0", "CFrame" }, { "C1", "CFrame" } },
	Humanoid = { { "RigType", "token" }, { "HipHeight", "float" }, { "AutomaticScalingEnabled", "bool" }, { "BreakJointsOnDeath", "bool" }, { "RequiresNeck", "bool" }, { "DisplayDistanceType", "token" }, { "HealthDisplayType", "token" } },
	Atmosphere = { { "Density", "float" }, { "Offset", "float" }, { "Color", "Color3" }, { "Decay", "Color3" }, { "Glare", "float" }, { "Haze", "float" } },
	BloomEffect = { { "Intensity", "float" }, { "Size", "float" }, { "Threshold", "float" } },
	ColorCorrectionEffect = { { "Brightness", "float" }, { "Contrast", "float" }, { "Saturation", "float" }, { "TintColor", "Color3" } },
}
local STATS = {}

local function writeProp(spec, v)
	local name, kind, xmlName = spec[1], spec[2], spec[3] or spec[1]
	if kind == "Color3uint8" then
		return W.Color3uint8(v)
	elseif kind == "Phys" then
		return W.Phys(xmlName, v)
	end
	return W[kind](xmlName, v)
end

local function item(inst, ind)
	local cls = rawget(inst, "__class")
	local spec = CLASS[cls]
	if not spec then
		error("exporter: class not supported " .. cls .. " (" .. tostring(props(inst).Name) .. ")")
	end
	STATS[cls] = (STATS[cls] or 0) + 1
	local pad = string.rep("\t", ind)
	local out = { pad .. string.format('<Item class="%s" referent="%s">', cls, ref(inst)), pad .. "\t<Properties>", pad .. "\t\t" .. W.string("Name", props(inst).Name) }
	local P = props(inst)
	for _, sp in ipairs(spec) do
		local v = P[sp[1]]
		if v == nil then
			v = sp[4]
		end
		if v ~= nil then
			table.insert(out, pad .. "\t\t" .. writeProp(sp, v))
		end
	end
	if cls == "Part" then
		table.insert(out, pad .. "\t\t" .. W.token("TopSurface", 0))
		table.insert(out, pad .. "\t\t" .. W.token("BottomSurface", 0))
	end
	table.insert(out, pad .. "\t</Properties>")
	for _, c in ipairs(rawget(inst, "__children")) do
		table.insert(out, item(c, ind + 1))
	end
	table.insert(out, pad .. "</Item>")
	return table.concat(out, "\n")
end

-- ===== Lighting =====
local Lighting = game:GetService("Lighting")
local L = props(Lighting)
local ct = L.ClockTime or 14
local hh = math.floor(ct)
local mm = math.floor((ct - hh) * 60 + 0.5)
local lightProps = {
	W.string("TimeOfDay", string.format("%02d:%02d:00", hh, mm)),
	W.float("Brightness", L.Brightness),
	W.Color3("Ambient", L.Ambient),
	W.Color3("OutdoorAmbient", L.OutdoorAmbient),
	W.float("EnvironmentDiffuseScale", L.EnvironmentDiffuseScale),
	W.float("EnvironmentSpecularScale", L.EnvironmentSpecularScale),
	W.bool("GlobalShadows", L.GlobalShadows),
	W.Color3("ColorShift_Top", L.ColorShift_Top),
}
local lightKids = {}
for _, c in ipairs(rawget(Lighting, "__children")) do
	table.insert(lightKids, item(c, 2))
end

XML_LIGHTING_PROPS = "\t\t\t" .. table.concat(lightProps, "\n\t\t\t")
XML_LIGHTING_KIDS = table.concat(lightKids, "\n")
XML_MAP = item(mapFolder, 2)
XML_TEMPLATE = item(rig, 2)
local st = {}
for k, v in pairs(STATS) do
	st[#st + 1] = k .. "=" .. v
end
table.sort(st)
EXPORT_STATS = table.concat(st, " ")
if #ERRORS > 0 then
	error("exporter: mock errors " .. #ERRORS)
end
