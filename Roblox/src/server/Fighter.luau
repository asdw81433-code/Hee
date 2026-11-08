--[[
	Server-authoritative fighter. Owns vitals, the punch timeline, defence and damage. Everything the clients
	need to animate (current punch, guard, lean, state, injuries) is published as attributes on the model.
	Hit detection uses virtual head/body points computed from the HumanoidRootPart plus the fighter's lean,
	so it is deterministic and independent of client animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local PunchData = require(Shared.PunchData)
local Util = require(Shared.Util)

local Fighter = {}
Fighter.__index = Fighter

local INJ = { "EyeL", "EyeR", "CheekL", "CheekR", "Nose", "Mouth", "CutL", "CutR", "RibsL", "RibsR", "Liver" }

function Fighter.new(model, opts)
	local self = setmetatable({}, Fighter)
	self.model = model
	self.hrp = model:FindFirstChild("HumanoidRootPart")
	self.hum = model:FindFirstChildOfClass("Humanoid")
	self.player = opts.player
	self.isNPC = opts.player == nil
	self.name = opts.name or model.Name
	self.nick = opts.nick or ""
	self.stats = opts.stats
	self.southpaw = opts.southpaw == true
	self.style = opts.style or "OutBoxer"
	self.record = opts.record or "0-0"
	self.scale = model:GetAttribute("Scale") or 3.2
	self.corner = opts.corner or 0
	self.headHP, self.headCap, self.bodyHP = 100, 100, 100
	self.staminaMax = Util.lerp(92, 108, (self.stats.engine or 50) / 100)
	self.stamina = self.staminaMax
	self.recentHead, self.rocked, self.openT, self.counterWindow = 0, 0, 0, 0
	self.lastHit = -99
	self.kdRound, self.kdTotal = 0, 0
	self.state = "Intro"
	self.move = Vector2.zero
	self.lean = Vector3.zero
	self.leanCur = Vector3.zero
	self.guard = 0
	self.guardPressed = 99
	self.lastGuard = 0
	self.cur = nil
	self.queued = nil
	self.combo = 0
	self.lastPunchEnd = -9
	self.lastLead = false
	self.actId = 0
	self.inj = {}
	for _, k in INJ do self.inj[k] = 0 end
	self.round = Fighter.NewStats()
	self.total = Fighter.NewStats()
	self.syncT = 0
	self.liverT = -1
	if opts.injuries then
		for k, v in opts.injuries do
			if self.inj[k] ~= nil then self.inj[k] = v end
		end
		self.headCap = 100 - (opts.injuries.concussion or 0) * 35
		self.headHP = self.headCap
	end
	return self
end

function Fighter.NewStats()
	return { thrown = 0, landed = 0, jabsThrown = 0, jabsLanded = 0, powerThrown = 0, powerLanded = 0, bodyLanded = 0, headLanded = 0, blocked = 0, evaded = 0, knockdowns = 0, counters = 0, damage = 0, center = 0, pressure = 0 }
end

local function addStats(a, b)
	for k, v in b do a[k] = (a[k] or 0) + v end
end
Fighter.AddStats = addStats

-- ---------------------------------------------------------------- derived
function Fighter:Stat(n) return self.stats[n] or 50 end
function Fighter:PowerFactor() return 0.72 + self:Stat("power") / 100 * 0.65 end
function Fighter:SpeedFactor() return 1.16 - self:Stat("speed") / 100 * 0.32 end
function Fighter:StaminaFactor() return Util.lerp(0.5, 1, math.clamp(self.stamina / 45, 0, 1)) end
function Fighter:Fatigue() return math.clamp(1 - self.stamina / 60, 0, 1) * 0.7 + math.clamp(1 - self.staminaMax / 100, 0, 1) * 0.5 end
function Fighter:IsDown() return self.state == "Down" or self.state == "KO" end
function Fighter:CanAct() return self.state == "Fight" and self.openT <= 0 end

function Fighter:Chin()
	return (1.28 - self:Stat("chin") / 100 * 0.55) * (1 + (self.concussion or 0) * 0.8)
end

local function now() return workspace:GetServerTimeNow() end

function Fighter:Timing()
	local c = self.cur
	if not c then return 0, 0, 0 end
	return PunchData.Timing(c.def, c.power, c.body, c.scale, c.whiffed)
end

function Fighter:TimeToImpact()
	local c = self.cur
	if not c or c.impact then return 99 end
	local w, e = self:Timing()
	return math.max(0, w + e - (now() - c.t0))
end

function Fighter:WindingUp()
	local c = self.cur
	if not c then return false end
	local w = self:Timing()
	return now() - c.t0 < w
end

function Fighter:InRecovery() return self.cur ~= nil and self.cur.impact end

-- ---------------------------------------------------------------- geometry (virtual, server side)
function Fighter:LeanOffset()
	local l = self.leanCur
	local k = self.scale
	return Vector3.new(l.X * 0.18 * k, math.min(0, l.Y) * 0.26 * k, -l.Z * 0.15 * k)
end

function Fighter:HeadPoint()
	local cf = self.hrp.CFrame
	return cf:PointToWorldSpace(Vector3.new(0, 0.71 * self.scale, -0.04 * self.scale) + self:LeanOffset())
end

function Fighter:ChinPoint()
	return self:HeadPoint() + Vector3.new(0, -0.08 * self.scale, 0) - self.hrp.CFrame.LookVector * 0.06 * self.scale
end

function Fighter:BodyPoint(side)
	local off = self:LeanOffset() * 0.4
	return self.hrp.CFrame:PointToWorldSpace(Vector3.new(0.08 * side * self.scale, 0.36 * self.scale, -0.12 * self.scale) + off)
end

function Fighter:ShoulderPoint(lead)
	local leftHand = (lead and not self.southpaw) or (not lead and self.southpaw)
	local x = (leftHand and -1 or 1) * 0.17 * self.scale
	return self.hrp.CFrame:PointToWorldSpace(Vector3.new(x, 0.45 * self.scale, 0))
end

-- ---------------------------------------------------------------- commands
function Fighter:QueuePunch(id, body, power)
	local def = PunchData.Get(id)
	if not def or self.state ~= "Fight" then return end
	if not self.cur and self.openT <= 0 then
		self:StartPunch(def, body, power)
	else
		self.queued = { def = def, body = body, power = power, age = 0 }
	end
end

function Fighter:StartPunch(def, body, power)
	local t = now()
	local chained = t - self.lastPunchEnd < 0.32
	local alternate = self.combo > 0 and def.lead ~= self.lastLead
	self.combo = chained and self.combo + 1 or 1
	local scale = self:SpeedFactor() * (self.rocked > 0 and 1.25 or 1) * Util.lerp(1.3, 1, math.clamp(self.stamina / 35, 0, 1))
	if chained and alternate then scale *= 0.82 end
	self.cur = { def = def, body = body, power = power, t0 = t, scale = scale, impact = false, whiffed = false }
	local cost = def.stamina * (power and 1.6 or 1) * (body and 1.1 or 1)
	self.stamina = math.max(0, self.stamina - cost)
	self.staminaMax = math.max(45, self.staminaMax - cost * 0.035)
	self.round.thrown += 1
	if def.id == 1 then self.round.jabsThrown += 1 else self.round.powerThrown += 1 end
	self.lastLead = def.lead
	self.actId += 1
	local m = self.model
	m:SetAttribute("Act", def.id)
	m:SetAttribute("ActId", self.actId)
	m:SetAttribute("ActT0", t)
	m:SetAttribute("ActScale", scale)
	m:SetAttribute("ActBody", body)
	m:SetAttribute("ActPow", power)
end

function Fighter:OnPunchResult(res)
	if not self.cur then return end
	if res == "miss" or res == "slip" then
		self.cur.whiffed = true
		self.stamina = math.max(0, self.stamina - self.cur.def.stamina * 0.45)
		self.model:SetAttribute("ActWhiff", true)
	end
	if res == "parry" then self.openT = 0.42 end
	if res == "slip" then self.openT = math.max(self.openT, 0.18) end
end

-- ---------------------------------------------------------------- defence
function Fighter:Evaluate(attacker, def, body)
	local mult = 1
	local l = self.leanCur
	local slip, duck, back = math.abs(l.X), -math.min(0, l.Y), -math.min(0, l.Z)
	if not body then
		if def.kind == "straight" then
			if slip > 0.55 or duck > 0.6 or back > 0.78 then return "slip", 1 end
		elseif def.kind == "hook" then
			if duck > 0.55 or back > 0.85 then return "slip", 1 end
			if slip > 0.5 then mult *= 1.15 end
		else
			if back > 0.6 or slip > 0.72 then return "slip", 1 end
			if duck > 0.4 then mult *= 1.3 end
		end
		if l.Z > 0.3 then mult *= 1.12 end
	elseif back > 0.9 and def.kind == "straight" then
		return "slip", 1
	end
	local parryable = not body and def.kind ~= "upper"
	if parryable and self.guard == 1 and self.guardPressed < 0.16 and self.stamina > 6 then
		return "parry", 0
	end
	local blocking = (self.guard == 1 and not body) or (self.guard == 2 and body)
	if blocking then
		local frac = body and 0.22 or def.kind == "straight" and 0.12 or def.kind == "hook" and 0.28 or 0.6
		if self.stamina < 8 then frac = math.min(1, frac * 2.6) end
		return "block", mult * frac
	end
	if not body and self.guard == 0 and def.kind == "straight" and math.random() < 0.25 + self:Stat("defense") / 400 then
		return "block", mult * 0.55
	end
	if body and self.guard == 1 then mult *= 1.2 end
	if self:InRecovery() or self:WindingUp() then mult *= 1.15 end
	return "clean", mult
end

local function bump(self, key, amount)
	self.inj[key] = math.clamp((self.inj[key] or 0) + amount, 0, 1)
end

--[[ Apply a resolved hit. Returns true when it knocks the fighter down. side: +1 = landed on my right. ]]
function Fighter:TakeHit(attacker, def, body, power, damage, res, side, counter)
	self.lastHit = now()
	local pk = math.clamp(damage / 14, 0.15, 1.6)
	if res == "block" then
		self.stamina = math.max(0, self.stamina - def.stamina * 0.9 * (power and 1.4 or 1))
		if body then self.bodyHP -= damage * 0.5 else self.headHP -= damage * 0.5 end
		self.counterWindow = 0.3
		return false
	end
	local kd = false
	local sev = math.clamp(damage / 28, 0, 1) * (counter and 1.3 or 1) * (power and 1.2 or 1)
	if not body then
		local d = damage * self:Chin()
		self.headHP -= d
		self.headCap = math.max(30, self.headCap - d * 0.16)
		self.recentHead += d
		self.stamina = math.max(0, self.stamina - d * 0.25)
		self.concussion = math.clamp((self.concussion or 0) + sev * 0.12, 0, 1)
		local rockLine = Util.lerp(14, 24, self:Stat("chin") / 100) / self:Chin()
		if self.recentHead > rockLine or (self.headHP < 28 and d > 6) then
			self:Rock(Util.lerp(1.6, 3.6, math.clamp(self.recentHead / 50, 0, 1)))
		end
		-- injuries
		local s = side > 0 and "R" or "L"
		if def.kind == "hook" then
			local r = math.random()
			if r < 0.5 then bump(self, "Cheek" .. s, sev * 0.45) else bump(self, "Eye" .. s, sev * 0.32) end
			if math.random() < 0.1 * (0.3 + (self.inj["Eye" .. s] or 0)) then bump(self, "Cut" .. s, 0.18 + sev * 0.3) end
		elseif def.kind == "upper" then
			bump(self, "Mouth", sev * 0.5)
		else
			local r = math.random()
			if r < 0.4 then bump(self, "Nose", sev * 0.4) elseif r < 0.6 then bump(self, "Mouth", sev * 0.3) else bump(self, "Eye" .. s, sev * 0.3) end
			if math.random() < (0.04 + (power and 0.05 or 0)) * (0.3 + self.inj.Nose) then bump(self, "Cut" .. s, 0.15 + sev * 0.25) end
		end
		if self.headHP <= 0 then kd = true
		elseif self.rocked > 0 and (counter or power) and d > 6 and self.headHP < 50 and math.random() < 0.3 then kd = true
		elseif counter and power and d > 9 and self.headHP < 40 and math.random() < 0.2 then kd = true end
	else
		local d = damage * (1 + (self.bodyTrauma or 0) * 0.6)
		self.bodyHP -= d
		self.stamina = math.max(0, self.stamina - d * 1.15)
		self.staminaMax = math.max(40, self.staminaMax - d * 0.22)
		self.bodyTrauma = math.clamp((self.bodyTrauma or 0) + sev * 0.12, 0, 1)
		local liver = side > 0 and def.kind == "hook"
		bump(self, liver and "Liver" or side > 0 and "RibsR" or "RibsL", sev * 0.5)
		if liver and self.bodyHP < 45 and d > 8 and math.random() < 0.55 then self.liverT = 0.55 end
		if self.bodyHP <= 0 then self.liverT = 0.3; self.bodyHP = 8 end
	end
	self:SyncInjuries()
	return kd
end

function Fighter:Rock(t)
	self.rocked = math.max(self.rocked, t)
	if self.cur and not self.cur.impact then self:CancelPunch() end
end

function Fighter:CancelPunch()
	self.cur = nil
	self.model:SetAttribute("Act", 0)
end

function Fighter:SyncInjuries()
	local m = self.model
	for k, v in self.inj do m:SetAttribute("I_" .. k, math.floor(v * 100 + 0.5) / 100) end
	local bleed = math.max(self.inj.CutL, self.inj.CutR) + math.max(0, self.inj.Nose - 0.45)
	m:SetAttribute("I_Bleed", math.floor(bleed * 100) / 100)
end

function Fighter:InjuryRecord()
	local r = { concussion = self.concussion or 0, bodyTrauma = self.bodyTrauma or 0 }
	for k, v in self.inj do r[k] = v end
	return r
end

function Fighter:Treat(cutWork, iceWork)
	self.inj.CutL = math.max(0, self.inj.CutL - cutWork)
	self.inj.CutR = math.max(0, self.inj.CutR - cutWork)
	for _, k in { "EyeL", "EyeR", "CheekL", "CheekR", "Nose", "Mouth" } do
		self.inj[k] = math.max(0, self.inj[k] - iceWork)
	end
	self:SyncInjuries()
end

function Fighter:EyeClosure(left)
	return math.clamp(((self.inj[left and "EyeL" or "EyeR"] or 0) - 0.35) * 1.4, 0, 1)
end

function Fighter:MaxCut() return math.max(self.inj.CutL, self.inj.CutR) end

-- ---------------------------------------------------------------- state changes
function Fighter:SetState(s)
	self.state = s
	self.model:SetAttribute("State", s)
	if s ~= "Fight" then self.move = Vector2.zero end
end

function Fighter:KnockDown(dir, ko)
	self.cur = nil
	self.queued = nil
	self.kdRound += 1
	self.kdTotal += 1
	self:SetState(ko and "KO" or "Down")
	self.model:SetAttribute("DownT0", now())
	self.model:SetAttribute("DownDir", dir)
	self.model:SetAttribute("Act", 0)
end

function Fighter:GetUp()
	if self.state ~= "Down" then return end
	self:SetState("GetUp")
	self.model:SetAttribute("GetUpT0", now())
	local heart = self:Stat("heart") / 100
	self.headHP = math.max(self.headHP, Util.lerp(28, 55, heart) * Util.lerp(1, 0.6, math.clamp((self.kdTotal - 1) / 3, 0, 1)))
	self.recentHead = 0
	self.stamina = math.max(self.stamina, self.staminaMax * 0.5)
	self.rocked = 0
end

function Fighter:Recover(k)
	self.staminaMax = math.min(108, self.staminaMax + 4 * k)
	self.stamina = self.staminaMax
	self.headHP = math.min(self.headCap, self.headHP + Util.lerp(10, 20, self:Stat("heart") / 100) * k)
	self.bodyHP = math.min(100, self.bodyHP + 10 * k)
	self.recentHead = 0
	self.rocked = 0
end

-- ---------------------------------------------------------------- tick
function Fighter:Tick(dt, onImpact, onLiver)
	self.guardPressed += dt
	if self.guard == 1 and self.lastGuard ~= 1 then self.guardPressed = 0 end
	self.lastGuard = self.guard
	self.openT -= dt
	self.counterWindow -= dt
	self.recentHead = Util.moveTowards(self.recentHead, 0, dt * 7)
	if self.rocked > 0 then self.rocked -= dt end
	if self.liverT > 0 then
		self.liverT -= dt
		if self.liverT <= 0 and self.state == "Fight" and onLiver then onLiver(self) end
	end
	if self.state == "Down" or self.state == "KO" then
		self:Sync(dt)
		return
	end
	-- punch timeline
	local c = self.cur
	if c then
		local w, e, r = self:Timing()
		local t = now() - c.t0
		if not c.impact and t >= w + e then
			c.impact = true
			if onImpact then onImpact(self, c.def, c.body, c.power) end
		end
		if self.cur == c and t >= w + e + r then
			self.cur = nil
			self.lastPunchEnd = now()
			self.model:SetAttribute("Act", 0)
			self.model:SetAttribute("ActWhiff", false)
		end
	end
	local q = self.queued
	if q then
		q.age += dt
		if q.age > 0.4 then
			self.queued = nil
		elseif not self.cur and self:CanAct() then
			self.queued = nil
			self:StartPunch(q.def, q.body, q.power)
		end
	end
	-- recovery
	local active = self.state == "Fight" or self.state == "Clinch"
	if active and not self.cur then
		local regen = (9 + self:Stat("engine") / 100 * 8) * (1 - (self.bodyTrauma or 0) * 0.4) * (self.guard == 1 and 0.6 or 1) * (self.state == "Clinch" and 1.6 or 1)
		if self.move.Magnitude > 0.1 then regen *= 0.8 end
		self.stamina = math.min(self.staminaMax, self.stamina + regen * dt)
	end
	if now() - self.lastHit > 3 then self.headHP = math.min(self.headCap, self.headHP + dt * 0.9) end
	self.bodyHP = math.min(100, self.bodyHP + dt * 0.15)
	-- lean follows the command with lag: timing matters
	local leanSpeed = Util.lerp(5, 9, self:Stat("defense") / 100) * (self.rocked > 0 and 0.5 or 1) * Util.lerp(0.7, 1, self.stamina / 100)
	local cmd = self.state == "Fight" and self.lean or Vector3.zero
	if self.cur then cmd *= 0.35 end
	self.leanCur = Util.moveTowardsV(self.leanCur, cmd, dt * leanSpeed)
	if math.abs(self.leanCur.X) > 0.3 or self.leanCur.Y < -0.3 then self.stamina = math.max(0, self.stamina - dt * 3) end
	-- movement speed reflects condition
	if self.hum then
		local foot = 0.85 + self:Stat("footwork") / 100 * 0.35
		local spd = 10 * foot * Util.lerp(0.65, 1, math.clamp(self.stamina / 40, 0, 1)) * (self.rocked > 0 and 0.45 or 1) * (self.cur and 0.45 or 1) * (self.guard == 1 and 0.75 or 1)
		if self.state ~= "Fight" then spd = (self.state == "Corner" or self.state == "Walk") and 8 or 0 end
		self.hum.WalkSpeed = spd
	end
	self:Sync(dt)
end

function Fighter:Sync(dt)
	self.syncT -= dt
	if self.syncT > 0 then return end
	self.syncT = 0.05
	local m = self.model
	m:SetAttribute("HeadHP", math.floor(self.headHP * 10) / 10)
	m:SetAttribute("HeadCap", math.floor(self.headCap))
	m:SetAttribute("BodyHP", math.floor(self.bodyHP * 10) / 10)
	m:SetAttribute("Stam", math.floor(self.stamina * 10) / 10)
	m:SetAttribute("StamMax", math.floor(self.staminaMax * 10) / 10)
	m:SetAttribute("Rocked", math.max(0, math.floor(self.rocked * 10) / 10))
	m:SetAttribute("Guard", self.guard)
	m:SetAttribute("LeanX", math.floor(self.leanCur.X * 100) / 100)
	m:SetAttribute("LeanY", math.floor(self.leanCur.Y * 100) / 100)
	m:SetAttribute("LeanZ", math.floor(self.leanCur.Z * 100) / 100)
	m:SetAttribute("Fatigue", math.floor(self:Fatigue() * 100) / 100)
end

return Fighter
