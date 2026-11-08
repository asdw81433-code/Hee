--[[
	Builds a fighter's look on top of the skeleton: sculpted anatomy (pecs, abs, lats, delts, biceps, quads,
	calves), a full face (eyes that move, lids that blink and swell shut, brows, jaw, lips, teeth/mouthguard),
	14 hair styles, 10 facial hair styles, 5 brow styles, boxing trunks/gloves/boots, and hidden injury
	overlays (swelling, cuts, blood) the client reveals as a fight goes on.
	Everything is made of ellipsoids (SpecialMesh) so it needs no uploaded assets.
]]

local Config = require(script.Parent.Config)
local RigDef = require(script.Parent.RigDef)

local Appearance = {}

local SM = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

local function pickColor(list, i, fallback)
	return list[math.clamp(i or 1, 1, #list)] or fallback
end

local function colorsFor(p)
	local skin = pickColor(Config.SkinTones, p.skin, Config.SkinTones[3])
	local hair = pickColor(Config.HairColors, p.hairColor, Config.HairColors[1])
	local beard = (p.beardColor and p.beardColor > 0) and pickColor(Config.HairColors, p.beardColor, hair) or hair:Lerp(Color3.new(0, 0, 0), 0.15)
	local neonList = { Config.Neon.Cyan, Config.Neon.Magenta, Config.Neon.Yellow, Config.Neon.Orange, Config.Neon.Red, Config.Neon.Green, Config.Neon.Purple, Config.Neon.Blue, Config.Neon.White }
	return {
		skin = skin,
		hair = hair,
		beard = beard,
		trunks = pickColor(Config.TrunkColors, p.trunks, Config.TrunkColors[1]),
		gloves = pickColor(Config.GloveColors, p.gloves, Config.GloveColors[1]),
		accent = pickColor(neonList, p.accent, Config.Neon.Magenta),
		boots = Color3.fromRGB(20, 20, 24),
		white = Color3.fromRGB(235, 235, 232),
		lip = skin:Lerp(Color3.fromRGB(150, 60, 62), p.female and 0.45 or 0.28),
		eyeWhite = Color3.fromRGB(238, 230, 220),
		iris = pickColor(Config.EyeColors, p.eye, Config.Neon.Cyan),
		pupil = Color3.fromRGB(5, 5, 6),
		mouth = Color3.fromRGB(45, 10, 12),
		chrome = Color3.fromRGB(190, 196, 204),
		blood = Color3.fromRGB(110, 6, 10),
		bruise = Color3.fromRGB(82, 26, 52),
	}
end
Appearance.ColorsFor = colorsFor

-- ---------------------------------------------------------------- primitive builder
local Builder = {}
Builder.__index = Builder

local function newBuilder(model, bones, folder, scale)
	return setmetatable({ model = model, bones = bones, folder = folder, k = scale, parts = {} }, Builder)
end

local function meshFor(part, shape)
	if shape == "block" then
		return
	end
	local m = Instance.new("SpecialMesh")
	m.MeshType = shape == "cyl" and Enum.MeshType.Cylinder or shape == "pyr" and Enum.MeshType.Pyramid or shape == "wedge" and Enum.MeshType.Wedge or Enum.MeshType.Sphere
	m.Parent = part
end

-- pos/size in meters (bone space); rot in degrees
function Builder:add(boneName, name, pos, size, color, opts)
	opts = opts or {}
	local bone = self.bones[boneName]
	if not bone then
		return nil
	end
	local k = self.k
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(math.max(size.X * k, 0.002), math.max(size.Y * k, 0.002), math.max(size.Z * k, 0.002))
	p.Color = color
	p.Material = opts.mat or SM
	p.Reflectance = opts.refl or 0
	p.Transparency = opts.hidden and 1 or (opts.alpha or 0)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = opts.shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	meshFor(p, opts.shape or "ell")
	local rot = opts.rot and CFrame.Angles(math.rad(opts.rot.X), math.rad(opts.rot.Y), math.rad(opts.rot.Z)) or CFrame.identity
	local offset = CFrame.new(pos * k) * rot
	if opts.motor then
		-- animated piece: pivot (bone space, meters) is where it rotates; the part sits at pos
		local pivot = (opts.pivot or pos) * k
		local mo = Instance.new("Motor6D")
		mo.Name = opts.motor
		mo.Part0 = bone
		mo.Part1 = p
		mo.C0 = CFrame.new(pivot)
		mo.C1 = (CFrame.new(pivot):Inverse() * offset):Inverse()
		mo.Parent = p
	else
		local w = Instance.new("Weld")
		w.Name = "W"
		w.Part0 = bone
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
	end
	p.CFrame = bone.CFrame * offset
	if opts.tag then
		p:SetAttribute("Inj", opts.tag)
	end
	if opts.role then
		p:SetAttribute("Role", opts.role)
	end
	if opts.skin and not opts.hidden then
		p:SetAttribute("Skin", true)
	end
	p.Parent = self.folder
	table.insert(self.parts, p)
	return p
end

local V = Vector3.new

-- ---------------------------------------------------------------- body
local function buildBody(B, p, c, d)
	local b, m, f = d.b, d.m, d.f
	local boxer = p.outfit ~= "street"
	local skin, skinMat = c.skin, SM
	local chrome = p.skin == Config.ChromeSkin
	if chrome then skinMat = METAL end
	local hw = (1 + 0.1 * f) * math.sqrt(b)
	local dz = b ^ 0.7
	local ab = (b ^ 0.8) * (1 + 0.12 * m) * (1 - 0.15 * f)
	local lb = (b ^ 0.75) * (1 + 0.05 * f)
	local mm = 0.35 + m * 0.65
	local top = boxer and (f > 0 and c.accent or nil) or c.trunks
	local function S(o) o = o or {} o.mat = o.mat or skinMat o.refl = o.refl or (chrome and 0.35 or 0) o.skin = true return o end

	-- pelvis and trunks
	local trunkC = boxer and c.trunks or Color3.fromRGB(30, 30, 36)
	B:add("LowerTorso", "Pelvis", V(0, -0.03, 0.005), V(0.32 * hw, 0.25, 0.22 * dz), trunkC, { mat = boxer and SM or FABRIC, refl = boxer and 0.12 or 0 })
	B:add("LowerTorso", "GluteL", V(-0.065, -0.07, 0.065), V(0.15, 0.17, 0.13), trunkC, { mat = boxer and SM or FABRIC, refl = boxer and 0.12 or 0 })
	B:add("LowerTorso", "GluteR", V(0.065, -0.07, 0.065), V(0.15, 0.17, 0.13), trunkC, { mat = boxer and SM or FABRIC, refl = boxer and 0.12 or 0 })
	if boxer then
		B:add("LowerTorso", "Waistband", V(0, 0.095, 0.005), V(0.31 * hw, 0.07, 0.225 * dz), c.accent, { mat = NEON })
	end
	-- abdomen
	B:add("Spine", "Abdomen", V(0, 0.1, 0.0), V(0.28 * b * (1 - 0.08 * f), 0.32, 0.19 * dz), skin, S())
	if m > 0.25 and f == 0 then
		for row = 0, 2 do
			for sx = -1, 1, 2 do
				B:add("Spine", "Ab", V(0.032 * sx, 0.03 + row * 0.065, -0.088 * dz), V(0.05, 0.055, 0.03 * mm), skin, S({ shadow = false }))
			end
		end
	end
	B:add("Spine", "ObliqueL", V(-0.11 * b, 0.07, -0.02), V(0.08, 0.17, 0.12), skin, S())
	B:add("Spine", "ObliqueR", V(0.11 * b, 0.07, -0.02), V(0.08, 0.17, 0.12), skin, S())
	-- chest, pecs, lats, traps
	B:add("UpperTorso", "Ribcage", V(0, 0.12, 0.005), V(0.33 * b * (1 - 0.08 * f), 0.34, 0.21 * dz), skin, S())
	if f == 0 then
		B:add("UpperTorso", "PecL", V(-0.066 * b, 0.1, -0.085 * dz), V(0.13 * b, 0.1, 0.05 + 0.03 * mm), skin, S())
		B:add("UpperTorso", "PecR", V(0.066 * b, 0.1, -0.085 * dz), V(0.13 * b, 0.1, 0.05 + 0.03 * mm), skin, S())
	else
		B:add("UpperTorso", "BustL", V(-0.068, 0.085, -0.088), V(0.12, 0.115, 0.1), top or skin, top and { mat = SM, refl = 0.1 } or S())
		B:add("UpperTorso", "BustR", V(0.068, 0.085, -0.088), V(0.12, 0.115, 0.1), top or skin, top and { mat = SM, refl = 0.1 } or S())
		if top then
			B:add("UpperTorso", "SportsTop", V(0, 0.08, 0.005), V(0.34 * b, 0.16, 0.22 * dz), top, { mat = SM, refl = 0.1 })
		end
	end
	B:add("UpperTorso", "LatL", V(-0.13 * b, 0.06, 0.03), V(0.1 * mm + 0.03, 0.22, 0.14), skin, S())
	B:add("UpperTorso", "LatR", V(0.13 * b, 0.06, 0.03), V(0.1 * mm + 0.03, 0.22, 0.14), skin, S())
	B:add("UpperTorso", "TrapL", V(-0.07, 0.235, 0.025), V(0.13, 0.08 + 0.03 * mm, 0.1), skin, S())
	B:add("UpperTorso", "TrapR", V(0.07, 0.235, 0.025), V(0.13, 0.08 + 0.03 * mm, 0.1), skin, S())
	B:add("UpperTorso", "UpperBack", V(0, 0.14, 0.07), V(0.26 * b, 0.26, 0.08), skin, S())
	B:add("UpperTorso", "ShoulderL", V(-d.sx * 0.88, 0.18, 0.015), V(0.13, 0.12, 0.13), skin, S())
	B:add("UpperTorso", "ShoulderR", V(d.sx * 0.88, 0.18, 0.015), V(0.13, 0.12, 0.13), skin, S())
	if not boxer then
		B:add("UpperTorso", "Jacket", V(0, 0.1, 0.005), V(0.37 * b, 0.42, 0.25 * dz), c.trunks, { mat = FABRIC })
		B:add("Spine", "JacketLow", V(0, 0.08, 0), V(0.31 * b, 0.3, 0.215 * dz), c.trunks, { mat = FABRIC })
	end
	B:add("Neck", "Neck", V(0, 0.04, 0), V(0.105, 0.17, 0.11), skin, S())

	-- arms
	for _, side in { -1, 1 } do
		local L = side < 0 and "Left" or "Right"
		local armSkin, armMat = skin, skinMat
		if p.chromeArm and side > 0 then armSkin, armMat = c.chrome, METAL end
		local A = { mat = armMat, refl = armMat == METAL and 0.4 or 0 }
		B:add(L .. "UpperArm", "Deltoid", V(side * 0.012, -0.02, 0), V(0.125 * ab, 0.13, 0.125 * ab), armSkin, table.clone(A))
		B:add(L .. "UpperArm", "UpperArm", V(0, -0.14, 0), V(0.088 * ab, 0.3, 0.088 * ab), armSkin, table.clone(A))
		B:add(L .. "UpperArm", "Biceps", V(0, -0.13, -0.022), V(0.072 * ab, 0.15, 0.055 + 0.02 * mm), armSkin, table.clone(A))
		B:add(L .. "UpperArm", "Triceps", V(0, -0.12, 0.026), V(0.072 * ab, 0.17, 0.055 + 0.015 * mm), armSkin, table.clone(A))
		B:add(L .. "LowerArm", "Forearm", V(0, -0.075, 0), V(0.085 * ab, 0.17, 0.08 * ab), armSkin, table.clone(A))
		B:add(L .. "LowerArm", "ForearmLow", V(0, -0.16, 0), V(0.065 * ab, 0.24, 0.058 * ab), armSkin, table.clone(A))
		if p.chromeArm and side > 0 then
			B:add(L .. "LowerArm", "ChromeGlow", V(0, -0.14, -0.033 * ab), V(0.012, 0.2, 0.006), c.accent, { mat = NEON, shadow = false })
		end
		if not boxer then
			B:add(L .. "UpperArm", "Sleeve", V(0, -0.1, 0), V(0.12 * ab, 0.24, 0.12 * ab), c.trunks, { mat = FABRIC })
		end
		if boxer then
			B:add(L .. "Hand", "Glove", V(0, -0.12, -0.012), V(0.135, 0.23, 0.155), c.gloves, { refl = 0.18 })
			B:add(L .. "Hand", "GloveCuff", V(0, -0.025, 0), V(0.105, 0.075, 0.105), c.white, { mat = FABRIC })
			B:add(L .. "Hand", "Thumb", V(-side * 0.056, -0.1, -0.03), V(0.05, 0.09, 0.055), c.gloves, { refl = 0.18 })
			B:add(L .. "Hand", "GloveLogo", V(0, -0.11, -0.088), V(0.06, 0.02, 0.01), c.accent, { mat = NEON, shadow = false })
		else
			B:add(L .. "Hand", "Fist", V(0, -0.06, -0.005), V(0.085, 0.105, 0.065), armSkin, table.clone(A))
		end
	end

	-- legs
	for _, side in { -1, 1 } do
		local L = side < 0 and "Left" or "Right"
		B:add(L .. "UpperLeg", "Thigh", V(0, -0.2, 0), V(0.165 * lb, 0.46, 0.165 * lb), skin, S())
		B:add(L .. "UpperLeg", "Quad", V(0, -0.18, -0.04), V(0.12 * lb, 0.3, 0.07 + 0.02 * mm), skin, S())
		B:add(L .. "UpperLeg", "Hamstring", V(0, -0.2, 0.04), V(0.11 * lb, 0.3, 0.07), skin, S())
		B:add(L .. "UpperLeg", "Knee", V(0, -0.43, -0.012), V(0.1, 0.1, 0.1), skin, S())
		B:add(L .. "LowerLeg", "Calf", V(0, -0.13, 0.025), V(0.11 * lb, 0.2, 0.11 + 0.02 * mm), skin, S())
		B:add(L .. "LowerLeg", "Shin", V(0, -0.2, 0), V(0.085, 0.38, 0.085), skin, S())
		if boxer then
			B:add(L .. "UpperLeg", "TrunkLeg", V(0, -0.075, 0), V(0.21 * lb, 0.27, 0.21 * lb), c.trunks, { refl = 0.12 })
			B:add(L .. "UpperLeg", "TrunkStripe", V(side * 0.1 * lb, -0.075, 0), V(0.02, 0.25, 0.08), c.accent, { mat = NEON, shadow = false })
			B:add(L .. "LowerLeg", "Boot", V(0, -0.33, 0), V(0.11, 0.21, 0.11), c.boots, { refl = 0.15 })
			B:add(L .. "LowerLeg", "Sock", V(0, -0.225, 0), V(0.102, 0.035, 0.102), c.white, { mat = FABRIC })
		else
			B:add(L .. "UpperLeg", "Pants", V(0, -0.2, 0), V(0.19 * lb, 0.5, 0.19 * lb), Color3.fromRGB(28, 28, 34), { mat = FABRIC })
			B:add(L .. "LowerLeg", "PantsLow", V(0, -0.2, 0), V(0.12, 0.44, 0.12), Color3.fromRGB(28, 28, 34), { mat = FABRIC })
		end
		B:add(L .. "Foot", "Shoe", V(0, -0.03, -0.06), V(0.1, 0.07, 0.27), c.boots, { refl = 0.1 })
	end

	-- body bruise overlays (hidden until injured)
	B:add("UpperTorso", "Bruise_RibsL", V(-0.12, 0.05, -0.06), V(0.1, 0.1, 0.06), c.bruise, { hidden = true, tag = "RibsL", shadow = false })
	B:add("UpperTorso", "Bruise_RibsR", V(0.12, 0.05, -0.06), V(0.1, 0.1, 0.06), c.bruise, { hidden = true, tag = "RibsR", shadow = false })
end

-- ---------------------------------------------------------------- head and face
local function buildHead(B, p, c, d)
	local f = d.f
	local skin = c.skin
	local chrome = p.skin == Config.ChromeSkin
	local SK = { mat = chrome and METAL or SM, refl = chrome and 0.35 or 0, skin = true }
	local function S(extra)
		local o = table.clone(SK)
		if extra then for k, v in extra do o[k] = v end end
		return o
	end
	local jaw = math.clamp(p.jaw or 0.5, 0, 1)
	local jw = 1 + 0.1 * jaw - 0.08 * f
	B:add("Head", "Cranium", V(0, 0.155, 0.01), V(0.175, 0.23, 0.205), skin, S())
	B:add("Head", "Face", V(0, 0.118, -0.035), V(0.152, 0.15, 0.15), skin, S())
	B:add("Head", "CheekboneL", V(-0.046, 0.132, -0.074), V(0.05, 0.034, 0.03), skin, S())
	B:add("Head", "CheekboneR", V(0.046, 0.132, -0.074), V(0.05, 0.034, 0.03), skin, S())
	B:add("Head", "BrowRidge", V(0, 0.18, -0.086), V(0.13, 0.024 - 0.006 * f, 0.04), skin, S())
	B:add("Head", "NoseBridge", V(0, 0.15, -0.1), V(0.022, 0.048, 0.026), skin, S())
	B:add("Head", "NoseTip", V(0, 0.123, -0.118), V(0.03, 0.03, 0.03), skin, S())
	B:add("Head", "NostrilL", V(-0.011, 0.116, -0.11), V(0.021, 0.016, 0.019), skin, S({ shadow = false }))
	B:add("Head", "NostrilR", V(0.011, 0.116, -0.11), V(0.021, 0.016, 0.019), skin, S({ shadow = false }))
	B:add("Head", "EarL", V(-0.09, 0.148, 0.008), V(0.025, 0.056, 0.038), skin, S())
	B:add("Head", "EarR", V(0.09, 0.148, 0.008), V(0.025, 0.056, 0.038), skin, S())
	B:add("Head", "UpperLip", V(0, 0.098, -0.1), V(0.05, 0.014 + 0.004 * f, 0.02), c.lip, { shadow = false })
	B:add("Head", "Mouth", V(0, 0.088, -0.083), V(0.05, 0.022, 0.03), c.mouth, { shadow = false })
	local guard = p.outfit ~= "street"
	B:add("Head", "UpperTeeth", V(0, 0.094, -0.092), V(0.04, 0.01, 0.02), guard and c.accent or c.white, { mat = guard and NEON or SM, shadow = false })
	-- jaw (moves): chin mass, chin, lower lip, lower teeth
	B:add("Jaw", "JawMass", V(0, -0.055, -0.06), V(0.13 * jw, 0.075, 0.1), skin, S())
	B:add("Jaw", "Chin", V(0, -0.07, -0.09), V(0.06 * jw, 0.04, 0.04), skin, S())
	B:add("Jaw", "LowerLip", V(0, -0.026, -0.093), V(0.046, 0.015 + 0.004 * f, 0.02), c.lip, { shadow = false })
	B:add("Jaw", "LowerTeeth", V(0, -0.023, -0.083), V(0.036, 0.009, 0.018), guard and c.accent or c.white, { mat = guard and NEON or SM, shadow = false })
	if p.tattoo then
		B:add("Head", "Tattoo", V(0.058, 0.115, -0.087), V(0.005, 0.06, 0.004), c.accent, { mat = NEON, shadow = false, rot = V(0, 0, 8) })
	end
	-- eyes, lids, brows (animated through Motor6D)
	for _, side in { -1, 1 } do
		local s = side < 0 and "L" or "R"
		local center = V(0.033 * side, 0.158, -0.08)
		local e = B:add("Head", "Eye" .. s, center, V(0.027, 0.027, 0.027), c.eyeWhite, { motor = "Eye" .. s, refl = 0.15, shadow = false })
		if e then
			-- iris and pupil ride on the eyeball
			local k = B.k
			for _, piece in { { "Iris", V(0, 0, -0.0105), V(0.0135, 0.0135, 0.006), c.iris, NEON }, { "Pupil", V(0, 0, -0.0127), V(0.006, 0.006, 0.002), c.pupil, SM } } do
				local pp = Instance.new("Part")
				pp.Name = piece[1]
				pp.Size = piece[3] * k
				pp.Color = piece[4]
				pp.Material = piece[5]
				pp.CanCollide, pp.CanQuery, pp.CanTouch, pp.Massless, pp.CastShadow = false, false, false, true, false
				local sm = Instance.new("SpecialMesh")
				sm.MeshType = Enum.MeshType.Sphere
				sm.Parent = pp
				local w = Instance.new("Weld")
				w.Part0 = e
				w.Part1 = pp
				w.C0 = CFrame.new(piece[2] * k)
				w.Parent = pp
				pp.CFrame = e.CFrame * w.C0
				pp.Parent = B.folder
			end
		end
		B:add("Head", "Lid" .. s, center + V(0, 0.019, -0.005), V(0.032, 0.02, 0.03), skin, S({ motor = "Lid" .. s, pivot = center, shadow = false, skin = false }))
		local brow = p.brows or 1
		if brow < 5 then
			local size = brow == 2 and V(0.038, 0.011, 0.011) or brow == 3 and V(0.032, 0.006, 0.008) or V(0.034, 0.008, 0.009)
			local rot = V(0, 0, (brow == 3 and 10 or 4) * -side)
			local bp = center + V(0.003 * side, 0.024, -0.016)
			local br = B:add("Head", "Brow" .. s, bp, size, c.beard, { motor = "Brow" .. s, rot = rot, mat = FABRIC, shadow = false })
			if brow == 4 and br then
				B:add("Head", "BrowScar" .. s, bp + V(0.002 * side, 0, -0.006), V(0.004, 0.014, 0.004), skin:Lerp(Color3.new(1, 0.85, 0.85), 0.4), { shadow = false })
			end
		end
	end

	-- hidden injury overlays (the client shows/scales these from fight attributes)
	for _, side in { -1, 1 } do
		local s = side < 0 and "L" or "R"
		B:add("Head", "Swell_Eye" .. s .. "Up", V(0.045 * side, 0.168, -0.093), V(0.036, 0.022, 0.02), skin, S({ hidden = true, tag = "Eye" .. s, shadow = false }))
		B:add("Head", "Swell_Eye" .. s .. "Low", V(0.036 * side, 0.145, -0.089), V(0.03, 0.018, 0.018), skin, S({ hidden = true, tag = "Eye" .. s, shadow = false }))
		B:add("Head", "Swell_Cheek" .. s, V(0.055 * side, 0.128, -0.081), V(0.045, 0.04, 0.03), skin, S({ hidden = true, tag = "Cheek" .. s, shadow = false }))
		B:add("Head", "Cut_Brow" .. s, V(0.042 * side, 0.19, -0.099), V(0.022, 0.004, 0.006), c.blood, { hidden = true, tag = "CutBrow" .. s, shadow = false })
		B:add("Head", "Cut_Cheek" .. s, V(0.056 * side, 0.136, -0.09), V(0.018, 0.004, 0.006), c.blood, { hidden = true, tag = "CutCheek" .. s, shadow = false })
		B:add("Head", "Blood_Streak" .. s, V(0.046 * side, 0.155, -0.1), V(0.006, 0.065, 0.004), c.blood, { hidden = true, tag = "Streak" .. s, shadow = false })
	end
	B:add("Head", "Swell_Nose", V(0, 0.14, -0.106), V(0.03, 0.035, 0.025), skin, S({ hidden = true, tag = "Nose", shadow = false }))
	B:add("Head", "Blood_Nose", V(0, 0.103, -0.111), V(0.013, 0.026, 0.006), c.blood, { hidden = true, tag = "NoseBlood", shadow = false })
	B:add("Jaw", "Swell_Lip", V(0, -0.026, -0.097), V(0.05, 0.02, 0.024), c.lip, { hidden = true, tag = "Mouth", shadow = false })
end

-- ---------------------------------------------------------------- hair
local function capPart(B, c, y, z, size, mat, refl)
	return B:add("Head", "HairCap", V(0, y, z), size, c.hair, { mat = mat or FABRIC, refl = refl or 0 })
end

local function strand(B, c, name, pivot, pos, size, mat)
	return B:add("Head", name, pos, size, c.hair, { motor = name, pivot = pivot, mat = mat or FABRIC, role = "Strand" })
end

local function buildHair(B, p, c)
	local h = p.hair or 1
	local thin = V(0.181, 0.19, 0.21)
	if h == 2 then
		capPart(B, c, 0.178, 0.02, V(0.182, 0.2, 0.212))
	elseif h == 3 then
		capPart(B, c, 0.185, 0.02, V(0.188, 0.2, 0.215))
		B:add("Head", "HairTop", V(0, 0.235, 0.005), V(0.15, 0.07, 0.17), c.hair, { mat = FABRIC })
	elseif h == 4 then
		capPart(B, c, 0.17, 0.022, thin)
		B:add("Head", "HighTop", V(0, 0.272, 0.008), V(0.14, 0.11, 0.16), c.hair, { mat = FABRIC, shape = "block" })
	elseif h == 5 then
		capPart(B, c, 0.17, 0.022, thin)
		B:add("Head", "SlickTop", V(0, 0.236, 0.025), V(0.155, 0.075, 0.205), c.hair, { mat = SM, refl = 0.18 })
		B:add("Head", "Quiff", V(0, 0.245, -0.07), V(0.11, 0.065, 0.07), c.hair, { mat = SM, refl = 0.18 })
	elseif h == 6 then
		capPart(B, c, 0.17, 0.022, thin)
		for i = 0, 6 do
			local t = i / 6
			local y = 0.24 + math.sin(t * math.pi) * 0.04
			local z = -0.07 + t * 0.17
			B:add("Head", "Spike", V(0, y + 0.03, z), V(0.02, 0.07 + 0.02 * math.sin(i), 0.04), c.hair, { mat = NEON, shape = "pyr", rot = V(-25 + t * 50, 0, 0) })
		end
	elseif h == 7 then
		B:add("Head", "Afro", V(0, 0.205, 0.012), V(0.275, 0.27, 0.285), c.hair, { mat = FABRIC })
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			B:add("Head", "AfroPuff", V(math.cos(a) * 0.1, 0.26 + math.sin(i * 2.3) * 0.02, math.sin(a) * 0.1 + 0.01), V(0.1, 0.09, 0.1), c.hair, { mat = FABRIC })
		end
	elseif h == 8 then
		capPart(B, c, 0.178, 0.02, V(0.184, 0.2, 0.214))
		for i = 0, 11 do
			local a = math.rad(-40 + i * 23)
			local x, z = math.sin(a) * 0.075, math.cos(a) * 0.075 + 0.03
			strand(B, c, "Dread" .. i, V(x, 0.2, z), V(x * 1.3, 0.1, z * 1.25 + 0.01), V(0.028, 0.22, 0.028))
		end
	elseif h == 9 then
		capPart(B, c, 0.172, 0.022, V(0.183, 0.195, 0.212))
		for i = -2, 2 do
			B:add("Head", "Cornrow", V(i * 0.028, 0.235 - math.abs(i) * 0.012, 0.015), V(0.018, 0.024, 0.2), c.hair, { mat = FABRIC })
		end
	elseif h == 10 then
		capPart(B, c, 0.18, 0.022, V(0.184, 0.2, 0.214), SM, 0.15)
		B:add("Head", "Bun", V(0, 0.245, 0.085), V(0.07, 0.065, 0.07), c.hair, { mat = FABRIC })
		B:add("Head", "BunTie", V(0, 0.232, 0.068), V(0.05, 0.012, 0.05), c.accent, { mat = NEON, shape = "cyl", rot = V(0, 0, 90) })
	elseif h == 11 then
		capPart(B, c, 0.18, 0.02, V(0.188, 0.205, 0.218))
		strand(B, c, "LongBack", V(0, 0.2, 0.09), V(0, 0.09, 0.085), V(0.2, 0.3, 0.07))
		strand(B, c, "LockL", V(-0.08, 0.19, -0.02), V(-0.088, 0.1, -0.02), V(0.04, 0.2, 0.05))
		strand(B, c, "LockR", V(0.08, 0.19, -0.02), V(0.088, 0.1, -0.02), V(0.04, 0.2, 0.05))
	elseif h == 12 then
		capPart(B, c, 0.178, 0.02, V(0.184, 0.2, 0.214))
		for i = 0, 9 do
			local a = i * 2.4
			local r = 0.05 + (i % 3) * 0.015
			B:add("Head", "Spike", V(math.cos(a) * r, 0.27 - r * 0.4, math.sin(a) * r + 0.01), V(0.035, 0.06, 0.035), c.hair, { mat = FABRIC, shape = "pyr", rot = V(math.sin(a) * 30, 0, -math.cos(a) * 30) })
		end
	elseif h == 13 then
		capPart(B, c, 0.18, 0.022, V(0.184, 0.2, 0.214), SM, 0.15)
		strand(B, c, "Ponytail", V(0, 0.215, 0.1), V(0, 0.14, 0.13), V(0.05, 0.17, 0.05))
		B:add("Head", "PonyTie", V(0, 0.215, 0.1), V(0.04, 0.02, 0.04), c.accent, { mat = NEON })
	elseif h == 14 then
		capPart(B, c, 0.19, 0.018, V(0.196, 0.215, 0.222))
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			B:add("Head", "Tuft", V(math.cos(a) * 0.06, 0.255 + (i % 2) * 0.012, math.sin(a) * 0.07 + 0.01), V(0.06, 0.05, 0.06), c.hair, { mat = FABRIC })
		end
		B:add("Head", "Fringe", V(0, 0.214, -0.078), V(0.12, 0.05, 0.05), c.hair, { mat = FABRIC })
	end
end

-- ---------------------------------------------------------------- facial hair
local function mustache(B, c)
	B:add("Head", "Mustache", V(0, 0.105, -0.103), V(0.062, 0.017, 0.023), c.beard, { mat = FABRIC, shadow = false })
	B:add("Head", "MustacheL", V(-0.029, 0.098, -0.098), V(0.02, 0.022, 0.02), c.beard, { mat = FABRIC, shadow = false })
	B:add("Head", "MustacheR", V(0.029, 0.098, -0.098), V(0.02, 0.022, 0.02), c.beard, { mat = FABRIC, shadow = false })
end

local function buildBeard(B, p, c)
	local bd = p.female and 1 or (p.beard or 1)
	if bd <= 1 then return end
	local fuzzy = { mat = FABRIC }
	if bd == 2 then
		B:add("Jaw", "Stubble", V(0, -0.052, -0.062), V(0.138, 0.082, 0.106), c.beard, { mat = FABRIC, alpha = 0.55, shadow = false })
		B:add("Head", "StubbleLip", V(0, 0.104, -0.099), V(0.062, 0.02, 0.022), c.beard, { mat = FABRIC, alpha = 0.55, shadow = false })
	elseif bd == 3 then
		mustache(B, c)
	elseif bd == 4 then
		mustache(B, c)
		B:add("Jaw", "Goatee", V(0, -0.073, -0.095), V(0.052, 0.052, 0.036), c.beard, fuzzy)
		B:add("Jaw", "GoateeL", V(-0.025, -0.045, -0.098), V(0.013, 0.04, 0.016), c.beard, fuzzy)
		B:add("Jaw", "GoateeR", V(0.025, -0.045, -0.098), V(0.013, 0.04, 0.016), c.beard, fuzzy)
	elseif bd == 5 then
		B:add("Jaw", "StrapL", V(-0.06, -0.04, -0.045), V(0.018, 0.075, 0.07), c.beard, { mat = FABRIC, rot = V(0, 0, -15) })
		B:add("Jaw", "StrapR", V(0.06, -0.04, -0.045), V(0.018, 0.075, 0.07), c.beard, { mat = FABRIC, rot = V(0, 0, 15) })
		B:add("Jaw", "StrapChin", V(0, -0.08, -0.088), V(0.065, 0.02, 0.032), c.beard, fuzzy)
	elseif bd == 6 or bd == 7 or bd == 10 then
		B:add("Jaw", "Beard", V(0, -0.054, -0.066), V(0.145, 0.092, 0.115), c.beard, fuzzy)
		B:add("Head", "Sideburns", V(0, 0.115, -0.02), V(0.17, 0.07, 0.12), c.beard, fuzzy)
		mustache(B, c)
		if bd == 7 then
			B:add("Jaw", "BeardLong", V(0, -0.12, -0.085), V(0.11, 0.15, 0.07), c.beard, { mat = FABRIC, motor = "BeardSway", pivot = V(0, -0.07, -0.08), role = "Strand" })
		elseif bd == 10 then
			B:add("Jaw", "Braid", V(0, -0.13, -0.09), V(0.04, 0.12, 0.04), c.beard, { mat = FABRIC, motor = "BeardSway", pivot = V(0, -0.075, -0.088), role = "Strand" })
			B:add("Jaw", "BraidRing", V(0, -0.1, -0.089), V(0.045, 0.012, 0.045), c.accent, { mat = NEON, shape = "cyl", rot = V(0, 0, 90) })
		end
	elseif bd == 8 then
		mustache(B, c)
		B:add("Head", "ChopL", V(-0.072, 0.11, -0.035), V(0.032, 0.085, 0.07), c.beard, fuzzy)
		B:add("Head", "ChopR", V(0.072, 0.11, -0.035), V(0.032, 0.085, 0.07), c.beard, fuzzy)
	elseif bd == 9 then
		mustache(B, c)
		B:add("Jaw", "VanDyke", V(0, -0.088, -0.092), V(0.04, 0.065, 0.032), c.beard, { mat = FABRIC, shape = "pyr", rot = V(180, 0, 0) })
	end
end

-- ---------------------------------------------------------------- public
--[[
	Rebuilds the "Cosmetics" folder on a rig. bones: name -> bone part. p: profile table.
	p.outfit: "boxer" (default) or "street"; p.lod: 1 = crowd quality (no face details).
]]
function Appearance.Apply(model, bones, p)
	local old = model:FindFirstChild("Cosmetics")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "Cosmetics"
	local _, d = RigDef.Offsets(p)
	local c = colorsFor(p)
	local B = newBuilder(model, bones, folder, d.scale)
	buildBody(B, p, c, d)
	buildHead(B, p, c, d)
	buildHair(B, p, c)
	buildBeard(B, p, c)
	folder.Parent = model
	return folder
end

return Appearance
