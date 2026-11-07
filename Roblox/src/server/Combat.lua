-- ============================================================
--  ALLEY BRAWL : ระบบต่อสู้ (ฝั่ง server ตัดสินทุกอย่าง)
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))

local Combat = {}
Combat.fighters = {} -- [model] = F
Combat.corpses = {}  -- [model] = true
Combat.onDeath = nil -- function(F, killerF)
Combat.onScore = nil -- function()

local remotes, Ragdoll, CB, Weapons
local gibsFolder
local fighters = Combat.fighters
local corpses = Combat.corpses

local function now()
	return os.clock()
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

local function pickWord(kind)
	local list = Config.Words[kind] or Config.Words.punch
	return list[math.random(1, #list)]
end

local function fx(kind, data)
	remotes.Fx:FireAllClients(kind, data)
end
Combat.fx = fx

function Combat.init(deps)
	remotes = deps.remotes
	Ragdoll = deps.Ragdoll
	CB = deps.CB
	Weapons = deps.Weapons
	gibsFolder = Instance.new("Folder")
	gibsFolder.Name = "BrawlGibs"
	gibsFolder.Parent = workspace
end

function Combat.get(model)
	if not model then
		return nil
	end
	local F = fighters[model]
	if F and F.alive then
		return F
	end
	return nil
end

function Combat.findFighterByPart(part)
	local inst = part and part.Parent
	while inst and inst ~= workspace do
		local F = fighters[inst]
		if F then
			return F
		end
		inst = inst.Parent
	end
	return nil
end

local function setAct(F, anim)
	F.actN = F.actN + 1
	F.model:SetAttribute("Act", anim)
	F.model:SetAttribute("ActN", F.actN)
	return F.actN
end
Combat.setAct = setAct

local function setSuper(F, v)
	F.super = math.clamp(v, 0, Config.SuperMax)
	F.model:SetAttribute("Super", F.super)
end
Combat.setSuper = setSuper

-- ผลักตัวละคร (ไม่ล้ม)
function Combat.push(F, vel, dur)
	if F.player then
		remotes.Knock:FireClient(F.player, vel, dur)
		return
	end
	local att = F.root:FindFirstChild("PushAtt")
	if not att then
		return
	end
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(vel.X, vel.Z)
	lv.MaxForce = 9e4
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = F.root
	Debris:AddItem(lv, dur)
end

function Combat.ragdoll(F, vel, spin, dur)
	F.impactGrace = now() + 0.15
	F.prevVel = nil
	Ragdoll.start(F.model, vel, spin, dur)
	if dur then
		F.stunUntil = now() + dur
	end
	if F.blocking then
		F.blocking = false
		F.model:SetAttribute("Block", false)
	end
	if F.weapon and Weapons then
		Weapons.drop(F, (vel or Vector3.zero) * 0.5 + Vector3.new(0, 10, 0))
	end
end

local function randomSpin(mag)
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * mag
end

-- ===== แขนขาหลุด (สไตล์ gore sandbox) =====
-- ชื่อชิ้น -> ข้อที่ต้องตัด (ชิ้นที่ต่ออยู่ปลายทางหลุดตามไปหมด)
local SEVER = {
	Head = { joint = "Neck", kind = "head" },
	UpperTorso = { joint = "Waist", kind = "torso" },
	RightUpperArm = { joint = "RightShoulder", kind = "arm", side = "R" },
	RightLowerArm = { joint = "RightElbow", kind = "arm", side = "R" },
	RightHand = { joint = "RightWrist", kind = "hand", side = "R" },
	LeftUpperArm = { joint = "LeftShoulder", kind = "arm", side = "L" },
	LeftLowerArm = { joint = "LeftElbow", kind = "arm", side = "L" },
	LeftHand = { joint = "LeftWrist", kind = "hand", side = "L" },
	RightUpperLeg = { joint = "RightHip", kind = "leg", side = "R" },
	RightLowerLeg = { joint = "RightKnee", kind = "leg", side = "R" },
	RightFoot = { joint = "RightAnkle", kind = "foot", side = "R" },
	LeftUpperLeg = { joint = "LeftHip", kind = "leg", side = "L" },
	LeftLowerLeg = { joint = "LeftKnee", kind = "leg", side = "L" },
	LeftFoot = { joint = "LeftAnkle", kind = "foot", side = "L" },
}
Combat.SEVER = SEVER
local MEAT = Color3.fromRGB(120, 10, 14)
local BONE = Color3.fromRGB(235, 228, 205)
local SEVER_WORD = { arm = "ARM OFF!!", hand = "HAND OFF!!", leg = "LEG OFF!!", foot = "FOOT OFF!!", head = "HEADLESS!!", torso = "CUT IN HALF!!" }

local function gorePiece(base, name, cf, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = base
	return p
end

-- ตอเนื้อแดง + กระดูก ที่ผิวของ part ตรงข้อต่อ (localPos = ตำแหน่งข้อในพิกัดของ part)
local function makeStump(part, localPos, width)
	local hs = part.Size / 2
	local ratios = { math.abs(localPos.X) / hs.X, math.abs(localPos.Y) / hs.Y, math.abs(localPos.Z) / hs.Z }
	local axis = 2
	if ratios[1] > ratios[2] and ratios[1] >= ratios[3] then
		axis = 1
	elseif ratios[3] > ratios[2] then
		axis = 3
	end
	local comps = { localPos.X, localPos.Y, localPos.Z }
	local sign = comps[axis] >= 0 and 1 or -1
	local halves = { hs.X, hs.Y, hs.Z }
	local p = {}
	for i = 1, 3 do
		if i == axis then
			p[i] = sign * (halves[i] + 0.01)
		else
			p[i] = math.clamp(comps[i], -halves[i] * 0.6, halves[i] * 0.6)
		end
	end
	local n = { 0, 0, 0 }
	n[axis] = sign
	local normal = Vector3.new(n[1], n[2], n[3])
	local pos = Vector3.new(p[1], p[2], p[3])
	local disc = { width, width, width }
	disc[axis] = 0.08
	gorePiece(part, "GoreStump", part.CFrame * CFrame.new(pos), Vector3.new(disc[1], disc[2], disc[3]), MEAT)
	local bw = math.max(0.12, width * 0.3)
	gorePiece(part, "GoreBone", part.CFrame * CFrame.new(pos + normal * 0.07), Vector3.new(bw, bw, bw), BONE)
	return part
end

-- ชิ้นที่อยู่ปลายทางของ part (ตามข้อต่อ Motor6D) เช่น ต้นแขน -> ปลายแขน -> มือ
local function downstream(model, part)
	local kids = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 then
			kids[m.Part0] = kids[m.Part0] or {}
			table.insert(kids[m.Part0], m.Part1)
		end
	end
	local out, queue = {}, { part }
	while #queue > 0 do
		local p = table.remove(queue, 1)
		table.insert(out, p)
		for _, c in ipairs(kids[p] or {}) do
			table.insert(queue, c)
		end
	end
	return out
end

local function updateLosses(F)
	local m = F.model
	local function gone(n)
		return m:FindFirstChild(n) == nil
	end
	local arms, legs = 0, 0
	local handsGone, feetGone = 0, 0
	for _, side in ipairs({ "Right", "Left" }) do
		if gone(side .. "UpperArm") or gone(side .. "LowerArm") then
			arms = arms + 1
		elseif gone(side .. "Hand") then
			handsGone = handsGone + 1
		end
		if gone(side .. "UpperLeg") or gone(side .. "LowerLeg") then
			legs = legs + 1
		elseif gone(side .. "Foot") then
			feetGone = feetGone + 1
		end
	end
	F.dmgMul = ((arms == 0) and 1 or ((arms == 1) and 0.8 or 0.5)) * (1 - handsGone * 0.1)
	F.speedMul = ((legs == 0) and 1 or ((legs == 1) and 0.45 or 0.22)) * (1 - feetGone * 0.2)
	if legs >= 2 then
		F.hum.HipHeight = 0.15 -- คลานด้วยลำตัว
	end
end

-- ตัดชิ้นส่วน partName ออกจาก model  (F = นักสู้ที่ยังมีชีวิต หรือ nil ถ้าเป็นศพ)
function Combat.sever(model, partName, vel, F)
	if not Config.Dismember then
		return false
	end
	local def = SEVER[partName]
	if not def or not Ragdoll.hasJoint(model, def.joint) then
		return false
	end
	if (def.kind == "head" or def.kind == "torso") and Config.GoreLevel < 1 then
		return false
	end
	local part = model:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(def.joint)
	if not part or not motor or not motor.Part0 then
		return false
	end
	local base = motor.Part0
	local c0, c1 = motor.C0.Position, motor.C1.Position
	local pieces = downstream(model, part)
	-- อาวุธที่ถืออยู่ในมือที่ขาด หลุดตามไปด้วย
	if F and F.weapon then
		local grip = F.weapon.model and F.weapon.model.PrimaryPart
		local gw = grip and grip:FindFirstChild("GripWeld")
		if gw then
			for _, p in ipairs(pieces) do
				if gw.Part0 == p then
					Weapons.drop(F, (vel or Vector3.zero) * 0.4 + Vector3.new(0, 10, 0))
					break
				end
			end
		end
	end
	local pos = Ragdoll.sever(model, def.joint, pieces, gibsFolder)
	if not pos then
		return false
	end
	local stumpPart = nil
	if Config.GoreLevel >= 1 then
		local width = math.min(part.Size.X, part.Size.Z) * 0.92
		stumpPart = makeStump(base, c0, width)
		makeStump(part, c1, width)
	end
	vel = vel or Vector3.zero
	for _, p in ipairs(pieces) do
		p.AssemblyLinearVelocity = vel + randomSpin(12) + Vector3.new(0, 14, 0)
		p.AssemblyAngularVelocity = randomSpin(25)
		Debris:AddItem(p, Config.GibLife)
	end
	if F then
		updateLosses(F)
	end
	fx("sever", { pos = pos, stump = stumpPart or base, piece = part, gore = Config.GoreLevel, word = SEVER_WORD[def.kind] or "OFF!!", victim = model })
	return true
end

-- เลือกว่าโดนชิ้นไหนของตัว
local LIMB_LIST = {
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}
local function pickPart(G, mv)
	local m = G.model
	local zone = mv.zone or "body"
	local list
	if mv.weapon then
		list = { "Head", "Head", "Head", "UpperTorso", "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightHand", "LeftHand", "RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg" }
	elseif zone == "head" then
		if math.random() < 0.72 and m:FindFirstChild("Head") then
			return m.Head
		end
		list = { "UpperTorso", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightHand", "LeftHand" }
	elseif zone == "limb" then
		list = { "Head", "UpperTorso", "LowerTorso" }
		for _, n in ipairs(LIMB_LIST) do
			table.insert(list, n)
			table.insert(list, n)
		end
	else
		list = { "UpperTorso", "UpperTorso", "UpperTorso", "LowerTorso", "RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg", "RightUpperArm", "LeftUpperArm" }
	end
	for _ = 1, 6 do
		local p = m:FindFirstChild(list[math.random(1, #list)])
		if p then
			return p
		end
	end
	return m:FindFirstChild("UpperTorso") or G.root
end

-- ===== ความเสียหาย =====
local function damage(G, amount, by)
	if not G.alive then
		return
	end
	local hum = G.hum
	G.lastDamageT = now()
	if by and by ~= G then
		G.lastHitBy = by
		G.lastHitT = now()
		if by.stats then
			by.stats.dmg = (by.stats.dmg or 0) + amount
		end
	end
	hum.Health = math.max(0, hum.Health - amount)
end
Combat.damage = damage

-- สร้างตารางท่าจากอาวุธ
function Combat.weaponMove(wdef, thrown)
	local mult = thrown and 1.15 or 1
	return {
		dmg = wdef.dmg * mult,
		knock = wdef.knock * (thrown and 1.3 or 1),
		lift = wdef.lift + (thrown and 8 or 0),
		stun = wdef.stun,
		daze = wdef.daze,
		ragdoll = (wdef.ragdoll and wdef.ragdoll > 0) and wdef.ragdoll or nil,
		ragdollChance = thrown and math.min(1, wdef.ragdollChance + 0.3) or wdef.ragdollChance,
		word = wdef.word,
		super = 6,
		zone = "head",
		teeth = 0.25,
		guardBreak = wdef.dmg >= 19,
		sound = wdef.sound,
		extraBlood = wdef.extraBlood,
		weapon = wdef,
	}
end

-- ===== โดนตี =====
-- F = ผู้ตี (อาจเป็น nil), G = ผู้โดน, mv = ตารางท่า, dir = ทิศทาง
function Combat.hit(F, G, mv, dir)
	local t = now()
	if not G or not G.alive then
		return false
	end
	if t < G.invulnUntil then
		return false
	end
	local victim = G.model
	local down = Ragdoll.isRagdolled(victim)
	dir = dir or (F and F.root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local dmg = (mv.dmg or 5) * (0.9 + math.random() * 0.2)
	if F and not mv.weapon then
		dmg = dmg * (F.dmgMul or 1)
	end

	-- ===== การ์ด =====
	if G.blocking and not down and not mv.unblockable then
		local attPos = F and F.root.Position or (G.root.Position - dir * 3)
		local toAtt = flat(attPos - G.root.Position)
		local facing = toAtt and G.root.CFrame.LookVector:Dot(toAtt) > 0.15
		if facing then
			if mv.guardBreak then
				G.blocking = false
				victim:SetAttribute("Block", false)
				G.stunUntil = t + 0.9
				setAct(G, "hurt")
				damage(G, dmg * 0.3, F)
				Combat.push(G, dir * 26, 0.2)
				fx("block", { pos = G.head.Position, word = pickWord("guard"), big = true, attacker = F and F.model, victim = victim })
			else
				damage(G, dmg * 0.12, F)
				setAct(G, "blockHit")
				Combat.push(G, dir * 10, 0.12)
				setSuper(G, G.super + 3)
				fx("block", { pos = G.head.Position + dir * -0.8, word = pickWord("block"), attacker = F and F.model, victim = victim })
			end
			return true
		end
	end

	-- ===== โดนจริง =====
	local crit = math.random() < 0.08
	if crit then
		dmg = dmg * 1.6
	end
	if t < G.dizzyUntil then
		dmg = dmg * 1.25
	end
	if down then
		dmg = dmg * 0.8
	end
	damage(G, dmg, F)
	if F and F.alive then
		setSuper(F, F.super + (mv.super or 6))
	end
	setSuper(G, G.super + 4)

	local hitPart = pickPart(G, mv)
	local zone = (hitPart.Name == "Head") and "head" or "body"
	local pos = hitPart.Position
	CB.addWound(victim, hitPart, dir)
	G.limbDmg[hitPart.Name] = (G.limbDmg[hitPart.Name] or 0) + dmg
	local bloodN = 0
	if Config.Blood > 0 then
		bloodN = math.floor((dmg * 0.9 + (mv.extraBlood or 0) * 6) * (crit and 1.6 or 1) * Config.Blood)
	end
	local teeth = 0
	if Config.Teeth and zone == "head" and math.random() < (mv.teeth or 0.08) * (crit and 2 or 1) then
		teeth = math.random(1, 3)
	end
	if zone == "head" then
		local fl = (dmg >= 12 or crit) and 2 or 1
		if math.random() < 0.55 + dmg * 0.02 then
			CB.addFaceBlood(victim, fl)
		end
		if (victim:GetAttribute("FaceLvl") or 0) >= 3 then
			CB.addShirtBlood(victim, math.floor(dmg / 4))
		end
	elseif Config.Blood > 0 and math.random() < 0.3 then
		CB.addShirtBlood(victim, 1)
	end

	local word = pickWord(mv.word or "punch")
	if crit then
		word = pickWord("crit")
	end
	fx("hit", {
		pos = pos,
		dir = dir,
		power = dmg,
		word = word,
		crit = crit,
		blood = bloodN,
		teeth = teeth,
		attacker = F and F.model,
		victim = victim,
		sound = mv.sound or ((dmg >= 12) and "heavy" or "hit"),
		big = dmg >= 14 or crit,
	})

	-- มึนหัว
	if not down and G.hum.Health > 0 then
		G.daze = G.daze + (mv.daze or 8) * (crit and 1.5 or 1)
		G.dazeT = t
		if G.daze >= Config.DizzyAt and t > G.dizzyUntil then
			G.daze = 0
			G.dizzyUntil = t + Config.DizzyTime
			victim:SetAttribute("Dizzy", true)
			fx("dizzy", { victim = victim, time = Config.DizzyTime })
		end
	end

	-- แขนขาหลุด
	local dead = G.hum.Health <= 0
	local sevVel = dir * (mv.knock or 10) * 0.8 + Vector3.new(0, (mv.lift or 0) * 0.5 + 12, 0)
	local strong = mv.heavy or mv.weapon or mv.onlyDown
	if Config.Dismember and (hitPart.Name == "UpperTorso" or hitPart.Name == "LowerTorso") then
		-- ท่าแรงสุดๆ ตอนน็อค: ขาดครึ่งท่อน
		if dead and (mv.unblockable or (mv.weapon and mv.weapon.heavy)) and Config.GoreLevel >= 1 and math.random() < Config.HalfChance then
			Combat.sever(victim, "UpperTorso", sevVel * 1.2 + Vector3.new(0, 16, 0), G)
		end
	elseif Config.Dismember and SEVER[hitPart.Name] then
		if hitPart.Name == "Head" then
			if dead and strong and Config.GoreLevel >= 1 and math.random() < Config.DecapChance then
				Combat.sever(victim, "Head", sevVel * 1.3 + Vector3.new(0, 20, 0), G)
			end
		elseif (dmg >= Config.MinSeverHit and G.limbDmg[hitPart.Name] >= Config.LimbHP and strong) or (dead and strong and math.random() < 0.6) then
			Combat.sever(victim, hitPart.Name, sevVel, G)
		end
	end

	-- ล้ม / กระเด็น
	local wantRag = mv.ragdoll ~= nil
	if mv.ragdollChance and math.random() > mv.ragdollChance then
		wantRag = false
	end
	if dead or wantRag or down then
		local vel = dir * (mv.knock or 10) + Vector3.new(0, mv.lift or 4, 0)
		if dead then
			vel = vel * 1.25 + Vector3.new(0, 12, 0)
		end
		local spin = randomSpin(dead and 26 or 14)
		Combat.ragdoll(G, vel, spin, (not dead) and (mv.ragdoll or 1.2) or nil)
	else
		G.stunUntil = t + (mv.stun or 0.3)
		setAct(G, zone == "body" and "hurtBody" or "hurt")
		Combat.push(G, dir * (mv.knock or 8) * 0.6, 0.15)
	end
	G.hurtT = t
	return true
end

-- ===== หาเป้า =====
local function findTarget(F, dir, mv)
	local origin = F.root.Position
	local best, bestD = nil, math.huge
	for _, G in pairs(fighters) do
		if G ~= F and G.alive and G.model.Parent then
			local down = Ragdoll.isRagdolled(G.model)
			local ok = true
			if mv.onlyDown and not down then
				ok = false
			end
			if down and not (mv.hitsDown or mv.onlyDown) then
				ok = false
			end
			if ok then
				local tp = down and G.torso.Position or G.root.Position
				local d = tp - origin
				local fd = Vector3.new(d.X, 0, d.Z)
				local dist = fd.Magnitude
				if dist <= (mv.range or 4.5) + 0.8 and math.abs(d.Y) < (down and 5.5 or 4.2) then
					local ang = 0
					if dist > 0.8 then
						ang = math.deg(math.acos(math.clamp(fd.Unit:Dot(dir), -1, 1)))
					end
					if ang <= (mv.arc or 70) / 2 and dist < bestD then
						best, bestD = G, dist
					end
				end
			end
		end
	end
	return best, bestD
end
Combat.findTarget = findTarget

-- เตะ/ทุบศพ (ฟิสิกส์ล้วน ฮาๆ)
local function hitCorpse(F, dir, mv)
	for model in pairs(corpses) do
		local torso = model.Parent and model:FindFirstChild("UpperTorso")
		if torso then
			local d = torso.Position - F.root.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude < (mv.range or 4.5) + 1 and math.abs(d.Y) < 5 then
				local vel = dir * ((mv.knock or 20) * 1.1 + 10) + Vector3.new(0, (mv.lift or 0) + 22, 0)
				for _, p in ipairs(model:GetChildren()) do
					if p:IsA("BasePart") then
						p.AssemblyLinearVelocity = vel + randomSpin(8)
					end
				end
				fx("hit", { pos = torso.Position, dir = dir, power = 8, word = pickWord("impact"), blood = math.floor(6 * Config.Blood), teeth = 0, attacker = F.model, victim = model, sound = "thud" })
				-- ศพโดนหนักๆ แขนขาหลุดได้
				if Config.Dismember and (mv.heavy or mv.weapon or mv.onlyDown) and math.random() < 0.45 then
					local names = {}
					for n, def in pairs(SEVER) do
						if model:FindFirstChild(n) and Ragdoll.hasJoint(model, def.joint) and def.kind ~= "torso" and (def.kind ~= "head" or Config.GoreLevel >= 1) then
							table.insert(names, n)
						end
					end
					if #names > 0 then
						Combat.sever(model, names[math.random(1, #names)], vel * 0.6, nil)
					end
				end
				return true
			end
		end
	end
	return false
end

-- ===== ท่าโจมตี =====
local function valid(F, id)
	return F.alive and F.actN == id and F.model.Parent ~= nil and not Ragdoll.isRagdolled(F.model)
end

local function faceDir(F, dir)
	if F.player then
		return -- client หมุนตัวเองแล้ว (aim assist)
	end
	local p = F.root.Position
	F.root.CFrame = CFrame.lookAt(p, p + dir)
end

local function doMove(F, name, dir)
	local mv = Config.Moves[name]
	local t = now()
	F.busyUntil = t + mv.dur
	local id = setAct(F, mv.anim)
	faceDir(F, dir)
	if mv.dash then
		task.delay(math.max(0, mv.wind - 0.06), function()
			if valid(F, id) then
				Combat.push(F, dir * mv.dash, 0.22)
			end
		end)
	end
	task.delay(mv.wind, function()
		if not valid(F, id) then
			return
		end
		local G = findTarget(F, dir, mv)
		if G then
			Combat.hit(F, G, mv, dir)
		else
			hitCorpse(F, dir, mv)
		end
	end)
	return id
end

local function doSwing(F, dir)
	local W = F.weapon
	local wdef = Config.Weapons[W.id]
	local mv = Config.Moves.swing
	local t = now()
	F.busyUntil = t + mv.dur
	local id = setAct(F, mv.anim)
	faceDir(F, dir)
	task.delay(mv.wind, function()
		if not valid(F, id) or F.weapon ~= W then
			return
		end
		local G = findTarget(F, dir, mv)
		if G then
			local m = Combat.weaponMove(wdef, false)
			if Combat.hit(F, G, m, dir) then
				Weapons.onHit(F, G)
			end
		else
			hitCorpse(F, dir, { range = mv.range, knock = wdef.knock, lift = wdef.lift, weapon = wdef })
		end
	end)
end

local function doGrab(F, dir)
	local mv = Config.Moves.grab
	local t = now()
	F.busyUntil = t + mv.dur
	local id = setAct(F, mv.anim)
	faceDir(F, dir)
	task.delay(mv.wind, function()
		if not valid(F, id) then
			return
		end
		local G = findTarget(F, dir, mv)
		if not G or now() < G.invulnUntil then
			return
		end
		-- จับได้! ซูเพล็กซ์
		local sx = Config.Moves.suplex
		local t2 = now()
		F.busyUntil = t2 + sx.dur
		local id2 = setAct(F, sx.anim)
		G.stunUntil = t2 + 1.2
		if G.blocking then
			G.blocking = false
			G.model:SetAttribute("Block", false)
		end
		setAct(G, "hurt")
		fx("word", { pos = G.head.Position, word = "GOTCHA!", big = false })
		task.delay(0.3, function()
			if not G.alive or not F.alive or F.actN ~= id2 then
				return
			end
			local vel = -dir * sx.knock + Vector3.new(0, sx.lift, 0)
			local spin = F.root.CFrame.RightVector * 12
			damage(G, sx.dmg, F)
			setSuper(F, F.super + sx.super)
			G.daze = G.daze + sx.daze
			fx("hit", { pos = G.head.Position, dir = -dir, power = sx.dmg, word = "SUPLEX!!", blood = math.floor(4 * Config.Blood), teeth = 0, attacker = F.model, victim = G.model, sound = "heavy", big = true })
			Combat.ragdoll(G, vel, spin, G.hum.Health > 0 and sx.ragdoll or nil)
		end)
	end)
end

-- ===== คำสั่งจากผู้เล่น/บอท =====
function Combat.request(F, action, payload)
	if not F or not F.alive then
		return
	end
	payload = payload or {}
	local t = now()
	local model = F.model
	if Ragdoll.isRagdolled(model) then
		return
	end
	if action == "block" then
		local on = payload.on == true
		if on and (t < F.stunUntil or t < F.dizzyUntil) then
			on = false
		end
		if F.blocking ~= on then
			F.blocking = on
			model:SetAttribute("Block", on)
		end
		return
	end
	-- เผื่อเวลา 0.06 วิ ให้ปุ่มที่กดรัวจาก client ไม่ถูกทิ้ง
	if t < F.busyUntil - 0.06 or t < F.stunUntil or t < F.dizzyUntil then
		return
	end
	if F.blocking then
		F.blocking = false
		model:SetAttribute("Block", false)
	end
	local dir = payload.dir or flat(F.root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	F.lastDir = dir

	if action == "punch" then
		if F.weapon then
			doSwing(F, dir)
		elseif payload.air then
			doMove(F, "dive", dir)
		else
			if t - F.lastPunchEnd < Config.ComboWindow then
				F.combo = (F.combo % #Config.PunchCombo) + 1
			else
				F.combo = 1
			end
			local name = Config.PunchCombo[F.combo]
			doMove(F, name, dir)
			F.lastPunchEnd = t + Config.Moves[name].dur
		end
	elseif action == "kick" then
		local downed = findTarget(F, dir, Config.Moves.stomp)
		if not downed then
			-- ศพอยู่ตรงหน้า = กระทืบ
			for model in pairs(corpses) do
				local torso = model.Parent and model:FindFirstChild("UpperTorso")
				if torso then
					local d = torso.Position - F.root.Position
					local fd = Vector3.new(d.X, 0, d.Z)
					if fd.Magnitude < Config.Moves.stomp.range + 0.8 and (fd.Magnitude < 1 or fd.Unit:Dot(dir) > 0.5) then
						downed = true
						break
					end
				end
			end
		end
		if downed then
			doMove(F, "stomp", dir)
		else
			doMove(F, "kick", dir)
		end
	elseif action == "grab" then
		if F.weapon then
			local mv = Config.Moves.throw
			F.busyUntil = t + mv.dur
			local id = setAct(F, mv.anim)
			faceDir(F, dir)
			task.delay(mv.wind, function()
				if valid(F, id) and F.weapon then
					Weapons.throw(F, dir)
				end
			end)
			return
		end
		local w, wd = Weapons.findNear(F.root.Position, 6)
		local enemy, ed = findTarget(F, dir, Config.Moves.grab)
		if w and (not enemy or wd < ed) then
			local mv = Config.Moves.pickup
			F.busyUntil = t + mv.dur
			setAct(F, mv.anim)
			Weapons.equip(F, w)
		else
			doGrab(F, dir)
		end
	elseif action == "super" then
		if F.super < Config.SuperMax then
			return
		end
		setSuper(F, 0)
		fx("super", { char = model, name = F.name })
		doMove(F, "super", dir)
	elseif action == "taunt" then
		local mv = Config.Moves.taunt
		F.busyUntil = t + mv.dur
		local id = setAct(F, mv.anim)
		fx("taunt", { char = model })
		task.delay(mv.dur, function()
			if F.alive and F.actN == id then
				setSuper(F, F.super + mv.super)
				if F.stats then
					F.stats.taunts = (F.stats.taunts or 0) + 1
				end
			end
		end)
	end
end

-- ===== ลงทะเบียนนักสู้ =====
function Combat.register(model, opts)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local F = {
		model = model,
		hum = hum,
		root = model:FindFirstChild("HumanoidRootPart"),
		torso = model:FindFirstChild("UpperTorso"),
		head = model:FindFirstChild("Head"),
		player = opts.player,
		name = opts.name,
		isBot = opts.isBot,
		stats = opts.stats,
		busyUntil = 0,
		stunUntil = 0,
		invulnUntil = now() + Config.SpawnProtect,
		dizzyUntil = 0,
		blocking = false,
		combo = 0,
		lastPunchEnd = -10,
		super = 0,
		daze = 0,
		dazeT = 0,
		lastHitBy = nil,
		lastHitT = -100,
		lastDamageT = -100,
		hurtT = -100,
		weapon = nil,
		actN = 0,
		alive = true,
		exprT = 0,
		limbDmg = {},
		dmgMul = 1,
		speedMul = 1,
	}
	local att = Instance.new("Attachment")
	att.Name = "PushAtt"
	att.Parent = F.root
	model:SetAttribute("Super", 0)
	model:SetAttribute("ActN", 0)
	model:SetAttribute("Block", false)
	model:SetAttribute("Dizzy", false)
	model:SetAttribute("Ragdoll", false)
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = model
	Debris:AddItem(ff, Config.SpawnProtect)

	hum.HealthChanged:Connect(function(h)
		CB.updateTag(model, h / hum.MaxHealth)
	end)
	hum.Died:Connect(function()
		Combat.kill(F)
	end)
	fighters[model] = F
	return F
end

function Combat.unregister(model)
	fighters[model] = nil
	corpses[model] = nil
end

-- ===== KO =====
function Combat.kill(F, reason)
	if not F.alive then
		return
	end
	F.alive = false
	local model = F.model
	local t = now()
	if F.hum.Health > 0 then
		F.hum.Health = 0
	end
	if not Ragdoll.isRagdolled(model) then
		Combat.ragdoll(F, F.root.CFrame.LookVector * -12 + Vector3.new(0, 10, 0), randomSpin(10), nil)
	else
		Ragdoll.start(model, nil, nil, nil) -- ทำให้ล้มถาวร
	end
	if F.weapon then
		Weapons.drop(F, Vector3.new(0, 12, 0))
	end
	model:SetAttribute("Dizzy", false)
	model:SetAttribute("Block", false)
	model:SetAttribute("Dead", true)
	CB.setFace(model, "ko")
	fighters[model] = nil
	corpses[model] = true
	model.Destroying:Connect(function()
		corpses[model] = nil
	end)

	local killer = nil
	if F.lastHitBy and F.lastHitBy ~= F and t - F.lastHitT < 10 then
		killer = F.lastHitBy
	end
	local msgList = (reason == "fall") and Config.FallMessages or Config.KOMessages
	local msg = string.format(msgList[math.random(1, #msgList)], F.name)
	if F.stats then
		F.stats.deaths = (F.stats.deaths or 0) + 1
		F.stats.streak = 0
	end
	local streakText = nil
	if killer and killer.stats then
		killer.stats.kos = (killer.stats.kos or 0) + 1
		killer.stats.streak = (killer.stats.streak or 0) + 1
		streakText = Config.StreakNames[killer.stats.streak]
		if killer.alive then
			setSuper(killer, killer.super + 25)
			-- ฟื้นเลือดนิดหน่อยเป็นรางวัล
			killer.hum.Health = math.min(killer.hum.MaxHealth, killer.hum.Health + 15)
		end
	end
	remotes.Notify:FireAllClients("ko", {
		victim = F.name,
		killer = killer and killer.name or nil,
		msg = msg,
		victimModel = model,
		killerModel = killer and killer.model or nil,
		streak = streakText,
	})
	task.delay(0.9, function()
		if model.Parent then
			local torso = model:FindFirstChild("UpperTorso")
			if torso then
				fx("pool", { pos = torso.Position })
			end
		end
	end)
	if Combat.onScore then
		Combat.onScore()
	end
	if Combat.onDeath then
		Combat.onDeath(F, killer)
	end
end

-- ===== อัปเดตทุกเฟรม =====
local exprAcc = 0
function Combat.step(dt)
	local t = now()
	exprAcc = exprAcc + dt
	local doExpr = exprAcc > 0.15
	if doExpr then
		exprAcc = 0
	end
	for model, F in pairs(fighters) do
		if F.alive and model.Parent then
			local hum = F.hum
			local rag = Ragdoll.isRagdolled(model)
			-- ตกแมพ
			if F.root.Position.Y < -40 then
				Combat.kill(F, "fall")
			else
				-- มึนหัวหาย
				if F.dizzyUntil > 0 and t > F.dizzyUntil then
					F.dizzyUntil = 0
					model:SetAttribute("Dizzy", false)
				end
				if t - F.dazeT > 1.5 and F.daze > 0 then
					F.daze = math.max(0, F.daze - 20 * dt)
				end
				-- ฟื้นเลือด
				if t - F.lastDamageT > Config.RegenDelay and hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.MaxHealth, hum.Health + Config.RegenRate * dt)
				end
				-- ความเร็วเดิน
				if not rag then
					local speed = Config.WalkSpeed * F.speedMul
					if t < F.dizzyUntil then
						speed = 4
					elseif t < F.stunUntil then
						speed = 3
					elseif F.blocking then
						speed = 7
					elseif t < F.busyUntil then
						speed = 8
					end
					if hum.WalkSpeed ~= speed then
						hum.WalkSpeed = speed
					end
					local jp = (t < F.stunUntil or t < F.dizzyUntil or F.speedMul < 0.3) and 0 or Config.JumpPower * math.max(0.6, F.speedMul)
					if hum.JumpPower ~= jp then
						hum.JumpPower = jp
					end
				end
				-- กระแทกพื้น/กำแพงตอนลอย = เจ็บ + เลือด
				if rag then
					local v = F.torso.AssemblyLinearVelocity
					if F.prevVel and t > (F.impactGrace or 0) then
						local dv = (F.prevVel - v).Magnitude
						if dv > 40 and t - (F.lastImpactT or 0) > 0.3 then
							F.lastImpactT = t
							local dmg = math.min(22, (dv - 40) * 0.33) * Config.ImpactDamage
							if dmg >= 1 then
								local by = (t - F.lastHitT < 4) and F.lastHitBy or nil
								damage(F, dmg, by)
								local fdir = F.prevVel.Magnitude > 0.1 and F.prevVel.Unit or Vector3.new(0, -1, 0)
								fx("hit", {
									pos = F.torso.Position,
									dir = fdir,
									power = dmg,
									word = pickWord(dmg > 8 and "slam" or "impact"),
									blood = math.floor(dmg * 0.8 * Config.Blood),
									teeth = 0,
									victim = model,
									sound = "thud",
									big = dmg > 10,
									impact = true,
								})
								if dmg > 6 then
									CB.addFaceBlood(model, 1)
								end
							end
						end
					end
					F.prevVel = v
				else
					F.prevVel = nil
				end
				-- สีหน้า
				if doExpr then
					local e = "normal"
					if t < F.dizzyUntil then
						e = "dizzy"
					elseif rag or t - F.hurtT < 0.45 then
						e = "hurt"
					elseif F.blocking then
						e = "block"
					elseif model:GetAttribute("Act") == "taunt" and t < F.busyUntil then
						e = "taunt"
					elseif t < F.busyUntil then
						e = "angry"
					end
					CB.setFace(model, e)
				end
			end
		end
	end
end

return Combat
