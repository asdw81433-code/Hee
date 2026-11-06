-- ============================================================
--  ซอยเดือด : นักเลง AI
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))

local Bots = {}
local Combat, Ragdoll, Weapons
local brains = {} -- [F] = brain

local STRIKES = { jab = true, cross = true, upper = true, kick = true, swing = true, super = true, dive = true, grab = true }

local function now()
	return os.clock()
end

function Bots.init(deps)
	Combat = deps.Combat
	Ragdoll = deps.Ragdoll
	Weapons = deps.Weapons
end

function Bots.add(F)
	local root = F.root
	brains[F] = {
		target = nil,
		retargetT = 0,
		nextThink = now() + 1 + math.random(),
		blockUntil = 0,
		lastPos = root.Position,
		stuckT = 0,
		strafe = (math.random() < 0.5) and 1 or -1,
		strafeT = 0,
		wantWeapon = nil,
		face = nil,
		wanderT = 0,
		aggression = 0.6 + math.random() * 0.4,
	}
end

function Bots.remove(F)
	brains[F] = nil
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

local function pickTarget(F)
	local pos = F.root.Position
	local best, bestScore = nil, math.huge
	-- นับว่ามีบอทรุมใครอยู่บ้าง (กันรุมผู้เล่นคนเดียว)
	local crowd = {}
	for G, B in pairs(brains) do
		if G ~= F and B.target then
			crowd[B.target] = (crowd[B.target] or 0) + 1
		end
	end
	for _, G in pairs(Combat.fighters) do
		if G ~= F and G.alive and G.model.Parent then
			local d = (G.root.Position - pos).Magnitude
			local score = d + (crowd[G] or 0) * 10
			if G.player then
				score = score * 0.85
			end
			if Ragdoll.isRagdolled(G.model) then
				score = score + 6
			end
			if score < bestScore then
				best, bestScore = G, score
			end
		end
	end
	return best
end

local function think(F, B)
	local t = now()
	local skill = Config.BotSkill
	local hum = F.hum
	local pos = F.root.Position

	-- ติดอยู่กับที่ -> กระโดด
	if (pos - B.lastPos).Magnitude < 0.4 and hum.MoveDirection.Magnitude > 0.1 then
		B.stuckT = B.stuckT + 0.1
		if B.stuckT > 0.8 then
			hum.Jump = true
			B.stuckT = 0
			B.strafe = -B.strafe
		end
	else
		B.stuckT = 0
	end
	B.lastPos = pos

	if not B.target or not B.target.alive or t > B.retargetT then
		B.target = pickTarget(F)
		B.retargetT = t + 3 + math.random() * 4
	end

	-- อยากได้อาวุธ
	if not F.weapon and not B.wantWeapon and math.random() < 0.03 then
		local w = Weapons.findNear(pos, 26)
		if w then
			B.wantWeapon = w
		end
	end
	if B.wantWeapon then
		local w = B.wantWeapon
		if F.weapon or not w.Parent or w:GetAttribute("Held") or not w.PrimaryPart then
			B.wantWeapon = nil
		else
			local wp = w.PrimaryPart.Position
			if (Vector3.new(wp.X, pos.Y, wp.Z) - pos).Magnitude < 4.5 then
				Combat.request(F, "grab", { dir = flat(wp - pos) })
				B.wantWeapon = nil
			else
				B.face = nil
				hum.AutoRotate = true
				hum:MoveTo(wp)
				return
			end
		end
	end

	local T = B.target
	if not T then
		-- เดินเล่น
		B.face = nil
		hum.AutoRotate = true
		if t > B.wanderT then
			B.wanderT = t + 3
			hum:MoveTo(pos + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20)))
		end
		return
	end

	local tp = T.root.Position
	local to = tp - pos
	local dist = Vector3.new(to.X, 0, to.Z).Magnitude
	local dir = flat(to) or F.root.CFrame.LookVector
	local tDown = Ragdoll.isRagdolled(T.model)
	local ideal = F.weapon and 4.3 or 3.3
	if tDown then
		ideal = 2.6
	end

	-- การ์ดเมื่อเห็นอีกฝ่ายง้างหมัด
	local tAct = T.model:GetAttribute("Act")
	if t > B.blockUntil and dist < 7.5 and t < T.busyUntil and STRIKES[tAct] and math.random() < (0.12 + 0.45 * skill) then
		B.blockUntil = t + 0.45 + math.random() * 0.4
		Combat.request(F, "block", { on = true })
	end
	if F.blocking and t > B.blockUntil then
		Combat.request(F, "block", { on = false })
	end

	if dist > ideal + 0.8 then
		B.face = nil
		hum.AutoRotate = true
		hum:MoveTo(tp - dir * ideal)
		return
	end

	-- อยู่ในระยะ: หันหน้าเข้าหา + เดินวนนิดๆ
	hum.AutoRotate = false
	B.face = dir
	if t > B.strafeT then
		B.strafeT = t + 0.8 + math.random() * 1.5
		if math.random() < 0.4 then
			B.strafe = -B.strafe
		end
	end
	local side = Vector3.new(-dir.Z, 0, dir.X) * B.strafe
	hum:MoveTo(pos + side * 2.2 - dir * (ideal - dist))

	if t < B.nextThink or t < F.busyUntil or F.blocking then
		return
	end
	local react = 0.85 - 0.6 * skill
	B.nextThink = t + react * (0.6 + math.random() * 0.8) / B.aggression

	local action = nil
	local r = math.random()
	if F.super >= Config.SuperMax and r < 0.6 then
		action = "super"
	elseif tDown then
		if r < 0.55 then
			action = "kick" -- กระทืบ
		elseif r < 0.7 then
			action = "taunt"
		end
	elseif T.blocking then
		action = (r < 0.5) and "grab" or "kick"
	elseif r < 0.56 then
		action = "punch"
	elseif r < 0.76 then
		action = "kick"
	elseif r < 0.88 then
		action = "grab"
	elseif r < 0.92 then
		action = "taunt"
	end
	if action then
		Combat.request(F, action, { dir = dir })
	end
end

local acc = 0
function Bots.step(dt)
	acc = acc + dt
	local doThink = acc >= 0.1
	if doThink then
		acc = 0
	end
	for F, B in pairs(brains) do
		if F.alive and F.model.Parent and not Ragdoll.isRagdolled(F.model) then
			if doThink then
				think(F, B)
			end
			-- หมุนตัวเข้าหาเป้าแบบนุ่มๆ
			if B.face and not F.hum.AutoRotate then
				local cur = F.root.CFrame
				local look = flat(cur.LookVector) or B.face
				local a = math.min(1, dt * 10)
				local nd = look:Lerp(B.face, a)
				if nd.Magnitude > 0.01 then
					F.root.CFrame = CFrame.lookAt(cur.Position, cur.Position + nd.Unit)
				end
			end
		end
	end
end

return Bots
