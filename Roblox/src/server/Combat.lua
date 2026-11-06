-- ============================================================
--  ซอยเดือด : ระบบต่อสู้ (ฝั่ง server ตัดสินทุกอย่าง)
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

	local zone = mv.zone or "body"
	local pos = (zone == "head") and G.head.Position or G.torso.Position
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

	-- ล้ม / กระเด็น
	local dead = G.hum.Health <= 0
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
		local torso = model.Parent and model:FindFirstChild("Torso")
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
			hitCorpse(F, dir, { range = mv.range, knock = wdef.knock, lift = wdef.lift })
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
		fx("word", { pos = G.head.Position, word = "จับได้!", big = false })
		task.delay(0.3, function()
			if not G.alive or not F.alive or F.actN ~= id2 then
				return
			end
			local vel = -dir * sx.knock + Vector3.new(0, sx.lift, 0)
			local spin = F.root.CFrame.RightVector * 12
			damage(G, sx.dmg, F)
			setSuper(F, F.super + sx.super)
			G.daze = G.daze + sx.daze
			fx("hit", { pos = G.head.Position, dir = -dir, power = sx.dmg, word = "ซูเพล็กซ์!!", blood = math.floor(4 * Config.Blood), teeth = 0, attacker = F.model, victim = G.model, sound = "heavy", big = true })
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
		torso = model:FindFirstChild("Torso"),
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
			local torso = model:FindFirstChild("Torso")
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
					local speed = Config.WalkSpeed
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
					local jp = (t < F.stunUntil or t < F.dizzyUntil) and 0 or Config.JumpPower
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
