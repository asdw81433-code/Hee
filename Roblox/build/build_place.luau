--[[
	Builds NeonBay_ThePit.rbxlx: the full warehouse map + lighting + every script, ready to open in Roblox
	Studio and press Play. Also writes build/Map.rbxmx for the Rojo project.

	Run from the Roblox folder:   lune run build/build_place.luau
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance, Vector3, CFrame, Color3, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
local UDim2, NumberRange, NumberSequence, ColorSequence = roblox.UDim2, roblox.NumberRange, roblox.NumberSequence, roblox.ColorSequence
local rgb = Color3.fromRGB

local game = Instance.new("DataModel")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

-- ======================================================================= helpers
local NEON = {
	cyan = rgb(26, 242, 255), magenta = rgb(255, 38, 191), yellow = rgb(255, 216, 38), orange = rgb(255, 115, 20),
	red = rgb(255, 31, 38), green = rgb(64, 255, 115), purple = rgb(140, 51, 255), blue = rgb(38, 115, 255), white = rgb(242, 247, 255),
}

local function P(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or rgb(60, 60, 66)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in extra do p[k] = v end
	end
	p.Parent = parent
	return p
end

local function sphereMesh(p, scale)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	if scale then m.Scale = scale end
	m.Parent = p
	return m
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function light(parent, kind, color, brightness, range, extra)
	local l = Instance.new(kind)
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	if extra then for k, v in extra do l[k] = v end end
	l.Parent = parent
	return l
end

--[[ Neon sign: dark backing board, glowing text on the front face, neon frame, coloured light spill. ]]
local function sign(parent, text, cf, w, h, color, opts)
	opts = opts or {}
	local m = model(parent, "Sign_" .. string.gsub(text, "%W", ""))
	local board = P(m, "Board", Vector3.new(w, h, 0.3), cf, rgb(10, 10, 14), Enum.Material.Metal)
	local sg = Instance.new("SurfaceGui")
	sg.Face = opts.face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Brightness = 2.5
	sg.Parent = board
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextScaled = true
	tl.Font = opts.font or Enum.Font.Michroma
	tl.TextStrokeColor3 = color
	tl.TextStrokeTransparency = 0.55
	tl.Parent = sg
	if opts.back then
		local sg2 = sg:Clone()
		sg2.Face = Enum.NormalId.Back
		sg2.Parent = board
	end
	-- neon frame
	local t = 0.18
	local front = cf * CFrame.new(0, 0, -0.2)
	P(m, "FrameTop", Vector3.new(w + t, t, t), front * CFrame.new(0, h / 2, 0), color, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	P(m, "FrameBot", Vector3.new(w + t, t, t), front * CFrame.new(0, -h / 2, 0), color, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	P(m, "FrameL", Vector3.new(t, h, t), front * CFrame.new(-w / 2, 0, 0), color, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	P(m, "FrameR", Vector3.new(t, h, t), front * CFrame.new(w / 2, 0, 0), color, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	if opts.light ~= false then
		light(board, "SurfaceLight", color, opts.brightness or 2.5, opts.range or 16, { Face = sg.Face, Angle = 110 })
	end
	return m
end

local function graffiti(parent, text, cf, w, h, color)
	local p = P(parent, "Graffiti", Vector3.new(w, h, 0.05), cf, rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 25
	sg.LightInfluence = 0.6
	sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextScaled = true
	tl.Font = Enum.Font.PermanentMarker
	tl.Rotation = -4
	tl.Parent = sg
	return p
end

local function smokeEmitter(parent, color, rate, size, speed, lifetime)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Size = NumberSequence.new(size, size * 2.5)
	e.Transparency = NumberSequence.new(0.65, 1)
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	e.SpreadAngle = roblox.Vector2.new(12, 12)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 0.6
	e.Parent = parent
	return e
end

-- ======================================================================= lighting & services
Lighting.Technology = Enum.Technology.Future
Lighting.ClockTime = 0.2
Lighting.Brightness = 1
Lighting.Ambient = rgb(28, 24, 40)
Lighting.OutdoorAmbient = rgb(36, 34, 58)
Lighting.EnvironmentDiffuseScale = 0.35
Lighting.EnvironmentSpecularScale = 0.7
Lighting.GlobalShadows = true
Lighting.ExposureCompensation = 0.15
Lighting.ShadowSoftness = 0.25

local atmo = Instance.new("Atmosphere")
atmo.Density = 0.33
atmo.Offset = 0.12
atmo.Color = rgb(150, 120, 200)
atmo.Decay = rgb(60, 30, 90)
atmo.Glare = 0
atmo.Haze = 1.6
atmo.Parent = Lighting

local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.9
bloom.Size = 32
bloom.Threshold = 0.95
bloom.Parent = Lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "Grade"
grade.Contrast = 0.14
grade.Saturation = 0.14
grade.Brightness = 0.02
grade.TintColor = rgb(255, 244, 252)
grade.Parent = Lighting

local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.12
dof.FocusDistance = 40
dof.InFocusRadius = 60
dof.NearIntensity = 0
dof.Parent = Lighting

Players.CharacterAutoLoads = false
StarterPlayer.EnableMouseLockOption = false
StarterPlayer.CameraMaxZoomDistance = 45
StarterPlayer.CameraMinZoomDistance = 6
SoundService.AmbientReverb = Enum.ReverbType.Hangar
Workspace.FallenPartsDestroyHeight = -200

-- ======================================================================= the map
local Map = folder(Workspace, "Map")
local W, D, H = 170, 130, 36 -- warehouse interior size
local hx, hz = W / 2, D / 2

-- floor with wet patches
local floor = folder(Map, "Floor")
P(floor, "Concrete", Vector3.new(W + 4, 2, D + 4), CFrame.new(0, -1, 0), rgb(38, 38, 44), Enum.Material.Concrete)
local seed = 7
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for i = 1, 16 do
	local x, z = (rnd() - 0.5) * (W - 20), (rnd() - 0.5) * (D - 20)
	if math.abs(x) > 18 or math.abs(z - 8) > 18 then
		local s = 4 + rnd() * 9
		local pd = P(floor, "Puddle", Vector3.new(s, 0.05, s * (0.5 + rnd() * 0.6)), CFrame.new(x, 0.03, z) * CFrame.Angles(0, rnd() * 3, 0), rgb(12, 14, 22), Enum.Material.Glass, { Reflectance = 0.55, Transparency = 0.25, CanCollide = false, CastShadow = false })
		sphereMesh(pd)
	end
end
-- painted lines and hazard stripes
for i = -3, 3 do
	P(floor, "FloorLine", Vector3.new(0.4, 0.04, D - 8), CFrame.new(i * 24, 0.02, 0), rgb(200, 170, 40), Enum.Material.SmoothPlastic, { CanCollide = false, Transparency = 0.6 })
end

-- walls with windows onto the city
local walls = folder(Map, "Walls")
local brick = rgb(78, 40, 36)
local function wallWithWindows(len, cf, windows)
	local m = model(walls, "Wall")
	P(m, "Lower", Vector3.new(len, 10, 2), cf * CFrame.new(0, 5, 0), brick, Enum.Material.Brick)
	P(m, "Upper", Vector3.new(len, H - 22, 2), cf * CFrame.new(0, 22 + (H - 22) / 2, 0), brick, Enum.Material.Brick)
	local n = windows
	local seg = len / n
	for i = 0, n - 1 do
		local x = -len / 2 + seg * i + seg / 2
		P(m, "Pillar", Vector3.new(seg * 0.35, 12, 2.2), cf * CFrame.new(x - seg * 0.325, 16, 0), brick, Enum.Material.Brick)
		P(m, "Glass", Vector3.new(seg * 0.65, 12, 0.3), cf * CFrame.new(x + seg * 0.175, 16, 0), rgb(120, 160, 220), Enum.Material.Glass, { Transparency = 0.55, Reflectance = 0.2 })
		P(m, "Mullion", Vector3.new(0.3, 12, 0.5), cf * CFrame.new(x + seg * 0.175, 16, 0), rgb(30, 30, 34), Enum.Material.Metal)
		P(m, "Sill", Vector3.new(seg * 0.65, 0.4, 2.8), cf * CFrame.new(x + seg * 0.175, 9.8, 0), rgb(50, 50, 55), Enum.Material.Concrete)
	end
	return m
end
wallWithWindows(W, CFrame.new(0, 0, -hz - 1), 8)
wallWithWindows(W, CFrame.new(0, 0, hz + 1) * CFrame.Angles(0, math.pi, 0), 8)
P(walls, "East", Vector3.new(2, H, D), CFrame.new(hx + 1, H / 2, 0), brick, Enum.Material.Brick)
P(walls, "West", Vector3.new(2, H, D), CFrame.new(-hx - 1, H / 2, 0), brick, Enum.Material.Brick)
-- roof and trusses
P(walls, "Roof", Vector3.new(W + 4, 1.5, D + 4), CFrame.new(0, H + 0.75, 0), rgb(22, 22, 26), Enum.Material.Metal)
for i = -3, 3 do
	P(walls, "Truss", Vector3.new(1.2, 1.6, D), CFrame.new(i * 24, H - 1.5, 0), rgb(40, 40, 46), Enum.Material.DiamondPlate)
end
for j = -2, 2 do
	P(walls, "Purlin", Vector3.new(W, 0.8, 0.8), CFrame.new(0, H - 3, j * 25), rgb(40, 40, 46), Enum.Material.Metal)
end
-- hanging work lamps
for i = -2, 2 do
	for j = -1, 1 do
		local x, z = i * 32, j * 40
		if math.abs(x) > 15 or math.abs(z - 8) > 15 then
			P(walls, "LampCord", Vector3.new(0.12, 8, 0.12), CFrame.new(x, H - 6, z), rgb(15, 15, 15), Enum.Material.SmoothPlastic, { CanCollide = false })
			local shade = P(walls, "LampShade", Vector3.new(2.4, 0.9, 2.4), CFrame.new(x, H - 10.3, z), rgb(30, 30, 34), Enum.Material.Metal, { CanCollide = false })
			light(shade, "SpotLight", rgb(255, 196, 140), 2.2, 30, { Face = Enum.NormalId.Bottom, Angle = 95, Shadows = true })
			P(walls, "Bulb", Vector3.new(0.6, 0.3, 0.6), CFrame.new(x, H - 10.85, z), rgb(255, 210, 160), Enum.Material.Neon, { CanCollide = false, CastShadow = false })
		end
	end
end

-- ======================================================================= rings
local function buildRing(name, center, order, crowd)
	local r = model(Map, name)
	r:SetAttribute("IsRing", true)
	r:SetAttribute("RingOrder", order)
	r:SetAttribute("RopeHalf", 12)
	r:SetAttribute("CrowdSize", crowd)
	r:SetAttribute("Phase", "Idle")
	local half = 13.5
	P(r, "Platform", Vector3.new(half * 2, 3, half * 2), CFrame.new(center + Vector3.new(0, 1.5, 0)), rgb(20, 20, 26), Enum.Material.Metal)
	local canvas = P(r, "Canvas", Vector3.new(25.6, 0.2, 25.6), CFrame.new(center + Vector3.new(0, 3.0, 0)), rgb(70, 74, 86), Enum.Material.Fabric)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0.4
	sg.Brightness = 1.4
	sg.Parent = canvas
	local logo = Instance.new("TextLabel")
	logo.Size = UDim2.fromScale(0.8, 0.3)
	logo.Position = UDim2.fromScale(0.1, 0.35)
	logo.BackgroundTransparency = 1
	logo.Text = "NEON BAY"
	logo.TextColor3 = NEON.magenta
	logo.TextTransparency = 0.35
	logo.TextScaled = true
	logo.Font = Enum.Font.Michroma
	logo.Parent = sg
	local sub = logo:Clone()
	sub.Text = "THE PIT"
	sub.TextColor3 = NEON.cyan
	sub.Size = UDim2.fromScale(0.5, 0.12)
	sub.Position = UDim2.fromScale(0.25, 0.64)
	sub.Parent = sg
	-- apron skirt with lettering
	for s = 0, 3 do
		local rot = CFrame.Angles(0, s * math.pi / 2, 0)
		local skirt = P(r, "Apron", Vector3.new(half * 2 + 0.2, 2.8, 0.2), CFrame.new(center) * rot * CFrame.new(0, 1.4, -half - 0.1), rgb(110, 12, 20), Enum.Material.Fabric)
		local asg = Instance.new("SurfaceGui")
		asg.Face = Enum.NormalId.Front
		asg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		asg.PixelsPerStud = 25
		asg.LightInfluence = 0.3
		asg.Parent = skirt
		local at = Instance.new("TextLabel")
		at.Size = UDim2.fromScale(1, 1)
		at.BackgroundTransparency = 1
		at.Text = "THE PIT  ·  NEON BAY UNDERGROUND  ·  EST. 2089"
		at.TextColor3 = rgb(255, 230, 230)
		at.TextScaled = true
		at.Font = Enum.Font.Michroma
		at.Parent = asg
		P(r, "ApronGlow", Vector3.new(half * 2 + 0.4, 0.15, 0.15), CFrame.new(center) * rot * CFrame.new(0, 0.12, -half - 0.25), NEON.red, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
	-- posts, pads, neon strips
	local corners = { { -1, -1, rgb(200, 15, 25) }, { 1, -1, rgb(235, 235, 240) }, { 1, 1, rgb(20, 50, 190) }, { -1, 1, rgb(235, 235, 240) } }
	for _, c in corners do
		local px, pz = c[1] * 12.2, c[2] * 12.2
		local post = P(r, "Post", Vector3.new(5.0, 0.7, 0.7), CFrame.new(center + Vector3.new(px, 3.1 + 2.5, pz)) * CFrame.Angles(0, 0, math.rad(90)), rgb(25, 25, 30), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		local _ = post
		P(r, "PostCap", Vector3.new(0.9, 0.3, 0.9), CFrame.new(center + Vector3.new(px, 3.1 + 5.1, pz)), c[3], Enum.Material.Neon, { CastShadow = false })
		local inward = Vector3.new(-c[1], 0, -c[2]).Unit
		for lv, h in { 2.5, 3.5, 4.5 } do
			local pad = P(r, "Turnbuckle", Vector3.new(1.0, 0.9, 0.8), CFrame.lookAt(center + Vector3.new(px, 3.1 + h, pz) + inward * 0.45, center + Vector3.new(px, 3.1 + h, pz) + inward * 2), c[3], Enum.Material.SmoothPlastic, { CanCollide = false })
			sphereMesh(pad)
			local _l = lv
		end
		P(r, "PostNeon", Vector3.new(0.15, 4.6, 0.15), CFrame.new(center + Vector3.new(px, 3.1 + 2.4, pz) + inward * 0.42), c[3] == rgb(235, 235, 240) and NEON.magenta or c[3], Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
	-- invisible rope walls (fighters stay in, lobby players stay out)
	for s = 0, 3 do
		local rot = CFrame.Angles(0, s * math.pi / 2, 0)
		P(r, "RopeWall", Vector3.new(24.6, 12, 0.4), CFrame.new(center) * rot * CFrame.new(0, 3.1 + 6, -12.25), rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false, CastShadow = false })
	end
	-- corner markers used by the match director
	local function marker(n, x, z)
		P(r, n, Vector3.new(1, 0.2, 1), CFrame.new(center + Vector3.new(x, 3.1, z)), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	end
	marker("RedCorner", -8.4, -8.4)
	marker("BlueCorner", 8.4, 8.4)
	marker("Neutral1", 9.2, -9.2)
	marker("Neutral2", -9.2, 9.2)
	-- steps at the red and blue corners
	for _, c in { { -1, -1 }, { 1, 1 } } do
		for i = 0, 2 do
			local d = 14.3 + i * 1.6
			P(r, "Step", Vector3.new(4, 3 - i, 1.6), CFrame.lookAt(center + Vector3.new(c[1] * d * 0.72, (3 - i) / 2, c[2] * d * 0.72), center + Vector3.new(0, (3 - i) / 2, 0)), rgb(35, 35, 40), Enum.Material.DiamondPlate)
		end
	end
	-- PvP corner pads outside the ring
	local function pad(n, x, z, color, text)
		local p = P(r, n, Vector3.new(0.3, 6, 6), CFrame.new(center + Vector3.new(x, 0.15, z)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, Transparency = 0.25 })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(240, 60)
		bb.StudsOffset = Vector3.new(4, 0, 0)
		bb.MaxDistance = 60
		bb.LightInfluence = 0
		bb.Parent = p
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = text
		tl.TextColor3 = color
		tl.TextScaled = true
		tl.Font = Enum.Font.GothamBlack
		tl.TextStrokeTransparency = 0.3
		tl.Parent = bb
		light(p, "PointLight", color, 1.5, 12)
	end
	pad("RedPad", -19, -19, NEON.red, "RED CORNER\nstand here for PvP")
	pad("BluePad", 19, 19, NEON.blue, "BLUE CORNER\nstand here for PvP")
	-- light rig
	local rigY = 3.1 + 16
	for s = 0, 3 do
		local rot = CFrame.Angles(0, s * math.pi / 2, 0)
		P(r, "LightTruss", Vector3.new(30, 1, 1), CFrame.new(center) * rot * CFrame.new(0, rigY, -14.5), rgb(30, 30, 34), Enum.Material.DiamondPlate, { CanCollide = false })
		P(r, "TrussNeon", Vector3.new(30, 0.2, 0.2), CFrame.new(center) * rot * CFrame.new(0, rigY - 0.65, -14.5), s % 2 == 0 and NEON.magenta or NEON.cyan, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local pos = center + Vector3.new(c[1] * 9, rigY - 0.8, c[2] * 9)
		local can = P(r, "RingLamp", Vector3.new(1.4, 1.4, 1.4), CFrame.lookAt(pos, center + Vector3.new(0, 4, 0)), rgb(20, 20, 24), Enum.Material.Metal, { CanCollide = false })
		light(can, "SpotLight", rgb(255, 240, 225), 5, 42, { Face = Enum.NormalId.Front, Angle = 60, Shadows = true })
	end
	-- hanging sign
	sign(r, "THE PIT", CFrame.new(center + Vector3.new(0, rigY + 4.5, 0)), 16, 4, NEON.red, { back = true, range = 24 })
	return r
end

buildRing("MainRing", Vector3.new(0, 0, 8), 1, 36)
buildRing("SparringRing", Vector3.new(52, 0, -30), 2, 18)

-- bleachers around the main ring
local stands = folder(Map, "Bleachers")
for side = 0, 2 do
	local rot = CFrame.Angles(0, side * math.pi / 2 + math.pi / 2, 0)
	for row = 0, 3 do
		P(stands, "Bench", Vector3.new(34, 1 + row * 1.6, 3), CFrame.new(0, 0, 8) * rot * CFrame.new(0, (1 + row * 1.6) / 2, -27 - row * 3), rgb(48, 34, 26), Enum.Material.WoodPlanks)
	end
end

-- ======================================================================= lobby, bar, gym, creator studio
local lobby = folder(Map, "Lobby")
local spawnPad = P(lobby, "LobbySpawn", Vector3.new(10, 0.2, 10), CFrame.new(-50, 0.1, 42), NEON.cyan, Enum.Material.Neon, { CanCollide = false, Transparency = 0.6, CastShadow = false })
sphereMesh(spawnPad, Vector3.new(1, 0.2, 1))
sign(lobby, "WELCOME TO THE PIT", CFrame.new(-50, 12, hz - 0.4) * CFrame.Angles(0, math.pi, 0), 22, 4, NEON.cyan)
sign(lobby, "NO CHROME IN THE RING", CFrame.new(hx - 0.4, 14, 20) * CFrame.Angles(0, -math.pi / 2, 0), 18, 3, NEON.yellow)
sign(lobby, "BOXING", CFrame.new(-hx + 0.4, 18, 8) * CFrame.Angles(0, math.pi / 2, 0), 16, 5, NEON.magenta)
sign(lobby, "BETS · ODDS · GLORY", CFrame.new(30, 13, -hz + 0.4), 16, 3, NEON.green)

-- the bar
local bar = model(Map, "Bar")
P(bar, "Counter", Vector3.new(26, 4, 3.5), CFrame.new(-60, 2, -50), rgb(40, 24, 18), Enum.Material.Wood)
P(bar, "CounterTop", Vector3.new(26.6, 0.4, 4.2), CFrame.new(-60, 4.2, -50), rgb(20, 20, 24), Enum.Material.Marble, { Reflectance = 0.15 })
P(bar, "CounterGlow", Vector3.new(26, 0.15, 0.15), CFrame.new(-60, 0.3, -48.2), NEON.magenta, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
P(bar, "Shelf", Vector3.new(24, 0.4, 2), CFrame.new(-60, 9, -hz + 1.2), rgb(30, 30, 34), Enum.Material.Metal)
for i = 0, 15 do
	local colors = { NEON.cyan, NEON.green, NEON.orange, NEON.magenta, NEON.yellow }
	local b = P(bar, "Bottle", Vector3.new(0.5, 1.6, 0.5), CFrame.new(-71 + i * 1.45, 10, -hz + 1.2) * CFrame.Angles(0, 0, math.rad(90)), colors[i % 5 + 1], Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.3, CanCollide = false })
	local _ = b
end
for i = 0, 6 do
	P(bar, "Stool", Vector3.new(2.6, 0.4, 2.6), CFrame.new(-70 + i * 3.4, 2.8, -46) * CFrame.Angles(0, 0, math.rad(90)), rgb(160, 20, 30), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	P(bar, "StoolLeg", Vector3.new(0.3, 2.6, 0.3), CFrame.new(-70 + i * 3.4, 1.3, -46), rgb(30, 30, 34), Enum.Material.Metal)
end
sign(bar, "BAR", CFrame.new(-60, 14, -hz + 0.4), 8, 3.4, NEON.orange)

-- heavy bags
local gym = model(Map, "Gym")
P(gym, "BagBeam", Vector3.new(26, 1, 1.2), CFrame.new(46, 16, 34), rgb(35, 35, 40), Enum.Material.Metal)
P(gym, "BeamPostL", Vector3.new(1, 16, 1), CFrame.new(33.5, 8, 34), rgb(35, 35, 40), Enum.Material.Metal)
P(gym, "BeamPostR", Vector3.new(1, 16, 1), CFrame.new(58.5, 8, 34), rgb(35, 35, 40), Enum.Material.Metal)
for i = 0, 2 do
	local x = 38 + i * 8
	local anchor = P(gym, "BagHook", Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, 15.3, 34), rgb(80, 80, 85), Enum.Material.Metal)
	local bag = P(gym, "Bag", Vector3.new(2.6, 5, 2.6), CFrame.new(x, 8.2, 34), i == 1 and rgb(150, 20, 28) or rgb(30, 30, 34), Enum.Material.Leather or Enum.Material.SmoothPlastic, { Anchored = false, Reflectance = 0.1 })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Cylinder
	m.Parent = bag
	bag.Size = Vector3.new(5, 2.6, 2.6)
	bag.CFrame = CFrame.new(x, 8.2, 34) * CFrame.Angles(0, 0, math.rad(90))
	local a0 = Instance.new("Attachment")
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(2.5, 0, 0)
	a1.Parent = bag
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = 4.6
	rope.Visible = true
	rope.Color = roblox.BrickColor.new("Really black")
	rope.Thickness = 0.12
	rope.Parent = bag
end
sign(gym, "TRAIN HARD · HIT HARDER", CFrame.new(46, 20, hz - 0.4) * CFrame.Angles(0, math.pi, 0), 18, 3, NEON.green)

-- creator studio nook (live preview of your fighter)
local studio = model(Map, "Studio")
local sp = P(studio, "CreatorStudio", Vector3.new(8, 0.6, 8), CFrame.lookAt(Vector3.new(-72, 0.3, 14), Vector3.new(-60, 0.3, 14)), rgb(14, 14, 20), Enum.Material.Metal, { Reflectance = 0.2 })
local _sp = sp
P(studio, "StudioRing", Vector3.new(0.3, 8.6, 8.6), CFrame.new(-72, 0.35, 14) * CFrame.Angles(0, 0, math.rad(90)), NEON.magenta, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, Transparency = 0.5 })
P(studio, "Backdrop", Vector3.new(0.6, 16, 18), CFrame.new(-hx + 0.6, 8, 14), rgb(12, 12, 20), Enum.Material.SmoothPlastic)
for i = 0, 4 do
	P(studio, "BackdropNeon", Vector3.new(0.2, 0.18, 16), CFrame.new(-hx + 1.0, 3 + i * 2.6, 14), i % 2 == 0 and NEON.cyan or NEON.magenta, Enum.Material.Neon, { CanCollide = false, CastShadow = false })
end
local key = P(studio, "KeyLight", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(-62, 10, 8), Vector3.new(-72, 5, 14)), rgb(20, 20, 20), Enum.Material.Metal, { CanCollide = false })
light(key, "SpotLight", rgb(255, 235, 220), 3, 30, { Face = Enum.NormalId.Front, Angle = 50, Shadows = true })
local rim = P(studio, "RimLight", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(-78, 9, 20), Vector3.new(-72, 5, 14)), rgb(20, 20, 20), Enum.Material.Metal, { CanCollide = false })
light(rim, "SpotLight", NEON.cyan, 3, 24, { Face = Enum.NormalId.Front, Angle = 60 })

-- clutter: lockers, crates, barrels, fire barrels, steam vents, graffiti
local clutter = folder(Map, "Clutter")
for i = 0, 9 do
	P(clutter, "Locker", Vector3.new(3, 8, 2.2), CFrame.new(-hx + 1.8, 4, -40 + i * 3.2) * CFrame.Angles(0, math.pi / 2, 0), i % 3 == 0 and rgb(40, 70, 90) or rgb(60, 64, 70), Enum.Material.Metal)
end
for i = 1, 14 do
	local x, z = (rnd() - 0.5) * (W - 30), (rnd() < 0.5 and -1 or 1) * (hz - 4 - rnd() * 6)
	local s = 3 + rnd() * 2
	P(clutter, "Crate", Vector3.new(s, s, s), CFrame.new(x, s / 2, z) * CFrame.Angles(0, rnd() * 3, 0), rgb(92, 66, 40), Enum.Material.WoodPlanks)
	if rnd() < 0.5 then P(clutter, "Crate", Vector3.new(s * 0.8, s * 0.8, s * 0.8), CFrame.new(x + 0.3, s + s * 0.4, z) * CFrame.Angles(0, rnd() * 3, 0), rgb(80, 58, 36), Enum.Material.WoodPlanks) end
end
local fireSpots = { Vector3.new(-30, 0, 40), Vector3.new(32, 0, -48), Vector3.new(-66, 0, -20), Vector3.new(70, 0, 46) }
for _, pos in fireSpots do
	local b = P(clutter, "FireBarrel", Vector3.new(3.4, 2.4, 2.4), CFrame.new(pos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 40, 30), Enum.Material.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
	local f = Instance.new("Fire")
	f.Size = 4
	f.Heat = 6
	f.Color = rgb(255, 120, 40)
	f.SecondaryColor = rgb(255, 40, 10)
	f.Parent = b
	light(b, "PointLight", rgb(255, 130, 60), 2.2, 18, { Shadows = true })
end
for _, pos in { Vector3.new(-20, 0, -40), Vector3.new(60, 0, 10), Vector3.new(-40, 0, 0) } do
	local vent = P(clutter, "SteamVent", Vector3.new(3, 0.3, 3), CFrame.new(pos + Vector3.new(0, 0.15, 0)), rgb(30, 30, 34), Enum.Material.DiamondPlate)
	local att = Instance.new("Attachment")
	att.Orientation = Vector3.new(0, 0, 0)
	att.Parent = vent
	smokeEmitter(att, rgb(200, 205, 215), 6, 2, 6, 4)
end
graffiti(clutter, "JACKALS RUN LOWTOWN", CFrame.new(20, 6, -hz + 0.1), 14, 4, NEON.orange)
graffiti(clutter, "STATIC SAINTS", CFrame.new(-hx + 0.1, 6, 40) * CFrame.Angles(0, math.pi / 2, 0), 12, 4, NEON.green)
graffiti(clutter, "IRON POLLY 41-0", CFrame.new(hx - 0.1, 7, -10) * CFrame.Angles(0, -math.pi / 2, 0), 14, 4, NEON.red)

-- the champions board
local board = sign(lobby, "PIT RANKINGS", CFrame.new(-20, 10, hz - 0.4) * CFrame.Angles(0, math.pi, 0), 14, 2.6, NEON.yellow)
local list = P(board, "List", Vector3.new(14, 12, 0.3), CFrame.new(-20, 2.5 + 0, hz - 0.4) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 1.4, 0), rgb(8, 8, 12), Enum.Material.Metal)
local lsg = Instance.new("SurfaceGui")
lsg.Face = Enum.NormalId.Front
lsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
lsg.PixelsPerStud = 30
lsg.LightInfluence = 0
lsg.Parent = list
local ltl = Instance.new("TextLabel")
ltl.Size = UDim2.fromScale(0.92, 0.92)
ltl.Position = UDim2.fromScale(0.04, 0.04)
ltl.BackgroundTransparency = 1
ltl.TextXAlignment = Enum.TextXAlignment.Left
ltl.TextYAlignment = Enum.TextYAlignment.Top
ltl.Text = "C   IRON POLLY ......... 41-0\n#1  Benny 'Chrome Jaw' .. 25-5\n#2  Lupe 'Lightning' .... 21-1\n#3  Mikhail 'The Crane' . 18-3\n#4  Dara 'Static' ....... 15-2\n#5  Lee 'Twin Fang' ..... 12-4\n#6  Sammy 'Brick' ........ 9-6\n#7  Nico 'Neon' .......... 4-3\n\nCAREER button: climb the card."
ltl.TextColor3 = rgb(230, 235, 245)
ltl.TextScaled = true
ltl.Font = Enum.Font.Code
ltl.Parent = lsg
local _ = rnd

-- ======================================================================= the city outside (Neon Bay skyline)
local city = folder(Map, "Skyline")
local cseed = 99
local function crnd() cseed = (cseed * 1103515245 + 12345) % 2147483648; return cseed / 2147483648 end
local neonList = { NEON.cyan, NEON.magenta, NEON.yellow, NEON.orange, NEON.purple, NEON.blue }
for side = -1, 1, 2 do
	for i = 0, 13 do
		local x = -150 + i * 22 + crnd() * 8
		local z = side * (hz + 30 + crnd() * 60)
		local h = 60 + crnd() * 170
		local w = 14 + crnd() * 12
		P(city, "Tower", Vector3.new(w, h, w), CFrame.new(x, h / 2 - 2, z), rgb(14 + crnd() * 10, 14 + crnd() * 10, 22 + crnd() * 14), Enum.Material.SmoothPlastic, { CastShadow = false, CanCollide = false })
		local color = neonList[math.floor(crnd() * #neonList) + 1]
		for k = 1, 3 do
			local y = 12 + crnd() * (h - 20)
			P(city, "Strip", Vector3.new(w + 0.2, 0.5, w + 0.2), CFrame.new(x, y, z), color, Enum.Material.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.2 })
			local _k = k
		end
		if crnd() < 0.4 then
			P(city, "Billboard", Vector3.new(w * 0.8, w * 0.45, 0.4), CFrame.new(x, h * 0.75, z - side * (w / 2 + 0.3)), neonList[math.floor(crnd() * #neonList) + 1], Enum.Material.Neon, { CastShadow = false, CanCollide = false, Transparency = 0.35 })
		end
	end
end
-- rain outside the windows
for side = -1, 1, 2 do
	local rainBox = P(city, "RainEmitter", Vector3.new(W + 40, 1, 20), CFrame.new(0, 70, side * (hz + 14)), rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(rgb(170, 200, 255))
	e.Size = NumberSequence.new(0.12)
	e.Transparency = NumberSequence.new(0.4)
	e.Lifetime = NumberRange.new(1.4, 1.8)
	e.Speed = NumberRange.new(60, 70)
	e.Rate = 400
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LightEmission = 0.3
	e.Parent = rainBox
end

-- ======================================================================= scripts
local function readSource(path)
	return fs.readFile(path)
end

local function loadDir(dir, parentFolder, entryMap)
	for _, name in fs.readDir(dir) do
		if string.sub(name, -5) == ".luau" then
			local base = string.sub(name, 1, -6)
			local class = "ModuleScript"
			if string.sub(base, -7) == ".server" then
				class = "Script"; base = string.sub(base, 1, -8)
			elseif string.sub(base, -7) == ".client" then
				class = "LocalScript"; base = string.sub(base, 1, -8)
			end
			local s = Instance.new(class)
			s.Name = base
			s.Source = readSource(dir .. "/" .. name)
			s.Parent = parentFolder
			if entryMap then entryMap[base] = s end
		end
	end
end

local shared = folder(ReplicatedStorage, "NeonBay")
loadDir("src/shared", shared)
local server = folder(ServerScriptService, "NeonBay")
loadDir("src/server", server)
local sps = Instance.new("StarterPlayerScripts")
sps.Parent = StarterPlayer
local scs = Instance.new("StarterCharacterScripts")
scs.Parent = StarterPlayer
local client = folder(sps, "NeonBay")
loadDir("src/client", client)

local readme = Instance.new("StringValue")
readme.Name = "READ_ME"
readme.Value = "NEON BAY: THE PIT. Press Play. Solo: open CAREER to fight the CPU ladder. Multiplayer: test with Test > Clients and Servers (2 players) and stand on both corner pads of a ring. Enable Game Settings > Security > Enable Studio Access to API Services to test saving."
readme.Parent = Workspace

-- ======================================================================= write
fs.writeFile("NeonBay_ThePit.rbxlx", roblox.serializePlace(game, true))
fs.writeFile("build/Map.rbxmx", roblox.serializeModel({ Map }, true))
local count = 0
for _, d in game:GetDescendants() do
	if d:IsA("BasePart") then count += 1 end
end
print("Built NeonBay_ThePit.rbxlx with " .. count .. " parts")
