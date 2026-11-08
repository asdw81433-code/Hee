--[[
	CPU boxer brain. Reads the player's punches with a human reaction delay and defends by style (slip, duck,
	shell, parry), throws style-specific combinations, counters after making you miss, cuts off the ring,
	escapes the ropes, clinches when hurt and goes for the finish when you're rocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local PunchData = require(Shared.PunchData)
local Util = require(Shared.Util)

local AI = {}
AI.__index = AI

local LIB = {
	OutBoxer = { "1", "1", "1 1", "1 2", "1 1 2", "1 2 3", "b1 1", "1 2 b3", "2 3 2" },
	Swarmer = { "b3 3", "1 2 b3", "3 2 3", "b4 b3 3", "5 2 3", "1 2 5 2", "b2 3", "3 b3 4" },
	Slugger = { "p2", "p4", "1 p2", "3 p2", "p6", "1 1 p2", "pb4" },
	Counter = { "1", "1 2", "b1", "1 b2" },
	Brawler = { "3 4 3", "p4 p3", "5 6 3 4", "1 2 3 4", "pb3 p3", "2 3 2 p3" },
}
local RANGE = { OutBoxer = 1.18, Swarmer = 0.72, Slugger = 0.9, Counter = 1.05, Brawler = 0.82 }

local function parse(s)
	local out = {}
	for tok in string.gmatch(s, "%S+") do
		local id = tonumber(string.sub(tok, -1)) or 1
		table.insert(out, { id = id, body = string.find(tok, "b") ~= nil, power = string.find(tok, "p") ~= nil })
	end
	return out
end

function AI.new(me, opp, difficulty)
	local self = setmetatable({}, AI)
	self.me, self.opp = me, opp
	self.style = me.style
	local overall = 0
	for _, v in me.stats do overall += v end
	overall /= 7
	self.skill = math.clamp((difficulty or 0.6) * 0.7 + overall / 100 * 0.4, 0, 1)
	self.combos = {}
	for _, s in LIB[self.style] or LIB.OutBoxer do table.insert(self.combos, parse(s)) end
	self.range = RANGE[self.style] or 1
	self.plan = {}
	self.comboCd, self.gap, self.defendHold, self.clinchCd, self.tauntCd, self.strafeT = 1.2, 0, 0, 3, 8, 0
	self.strafe = 1
	self.seen = nil
	return self
end

function AI:Def() return (self.me.stats.defense or 50) / 100 end

function AI:ChooseDefence(def, body)
	self.defendHold = 0.38
	self.defLean, self.defGuard = Vector3.zero, 0
	local r = math.random()
	if body then
		self.defGuard = 2
		if r < 0.25 then self.defLean = Vector3.new(0, 0, -1) end
		return
	end
	if def.kind == "straight" then
		if (self.style == "Counter" and r < 0.65) or r < 0.35 then
			self.defLean = Vector3.new(math.random() < 0.5 and -1 or 1, -0.1, 0)
		elseif r < 0.55 and self.skill > 0.6 then
			self.defGuard = 1
			self.defendHold = 0.2
		elseif r < 0.75 then
			self.defLean = Vector3.new(0, -1, 0)
		else
			self.defGuard = 1
		end
	elseif def.kind == "hook" then
		if r < 0.5 then self.defLean = Vector3.new(0, -1, 0) else self.defGuard = 1 end
	else
		if r < 0.55 then self.defLean = Vector3.new(0, 0, -1) else self.defGuard = 1 end
	end
end

--[[ Returns the move direction (world, flat) the server should feed into Humanoid:Move. ]]
function AI:Tick(dt, ring, tryClinch, taunt)
	local me, opp = self.me, self.opp
	if me.state == "Intro" then return Vector3.zero end
	if me.state ~= "Fight" then
		me.lean, me.guard = Vector3.zero, 0
		self.plan = {}
		return Vector3.zero
	end
	self.comboCd -= dt; self.gap -= dt; self.defendHold -= dt; self.clinchCd -= dt; self.tauntCd -= dt; self.strafeT -= dt
	local toOpp = Util.flat(opp.hrp.Position - me.hrp.Position)
	local dist = toOpp.Magnitude / me.scale
	local tired = 1 - math.clamp(me.stamina / 60, 0, 1)

	-- defence
	if opp.cur and opp.cur ~= self.seen then
		self.seen = opp.cur
		self.seenAt = os.clock()
		self.reacted = false
	end
	if not opp.cur then self.seen = nil end
	local reaction = Util.lerp(0.34, 0.1, self.skill * (0.5 + self:Def() * 0.5)) * (me.rocked > 0 and 1.8 or 1) * (1 + tired * 0.5)
	if self.seen and not self.reacted and os.clock() - self.seenAt >= reaction and opp:TimeToImpact() > 0.015 then
		self.reacted = true
		local chance = self:Def() * (0.5 + self.skill * 0.55) * (1 - tired * 0.4) * (me.rocked > 0 and 0.5 or 1)
		if self.style == "Counter" then chance += 0.15 end
		if self.style == "Slugger" or self.style == "Brawler" then chance -= 0.1 end
		if math.random() < chance and not me.cur then self:ChooseDefence(opp.cur.def, opp.cur.body) end
	end
	if self.defendHold > 0 then
		me.lean, me.guard = self.defLean, self.defGuard
	else
		local sway = (self.style == "Counter" or self.style == "Swarmer") and math.sin(os.clock() * 2.1) * 0.35 or 0
		me.lean = Vector3.new(sway, 0, 0)
		me.guard = ((self.style == "Swarmer" and dist < 1.4 and not me.cur and #self.plan == 0) or (me.rocked > 0 and math.random() < 0.6)) and 1 or 0
	end

	-- hurt: hold on
	if me.rocked > 0 and dist < 0.9 and self.clinchCd <= 0 and math.random() < 0.02 + (1 - me.headHP / 100) * 0.05 then
		self.clinchCd = 6
		tryClinch(me)
	end

	-- offence
	local oppHurt = opp.rocked > 0 or opp.stamina < 20
	local aggression = (self.style == "Swarmer" or self.style == "Brawler") and 1.2 or self.style == "Counter" and 0.55 or 0.9
	if oppHurt then aggression *= 1.8 end
	if me.rocked > 0 then aggression *= 0.3 end
	local reach = 0.92 + (self.style == "OutBoxer" and 0.12 or 0)
	local inRange = dist < reach
	if me.counterWindow > 0 and inRange and #self.plan == 0 and not me.cur and math.random() < 0.6 + self.skill * 0.3 then
		local c = self.style == "Counter" and (math.random() < 0.5 and "p2 3" or "3 p2") or (math.random() < 0.5 and "2" or "3 2")
		self.plan = parse(c)
		self.gap = 0
	end
	if #self.plan == 0 and self.comboCd <= 0 and inRange and me.stamina > 18 and math.random() < aggression * dt * 2.6 then
		local combo = self.combos[math.random(1, #self.combos)]
		local forceBody = opp.guard == 1 and math.random() < 0.6
		local forceHead = opp.guard == 2
		for _, p in combo do
			table.insert(self.plan, { id = p.id, body = (not forceHead) and (p.body or (forceBody and p.id ~= 1)), power = p.power or (oppHurt and math.random() < 0.4) })
		end
		self.comboCd = Util.lerp(1.6, 0.55, self.skill) / math.max(0.3, aggression) + tired * 1.2
	end
	if #self.plan > 0 and self.gap <= 0 and not me.cur and me:CanAct() then
		local n = table.remove(self.plan, 1)
		if dist < PunchData.Get(n.id).reach * 1.25 + 0.15 then
			me:QueuePunch(n.id, n.body, n.power and me.stamina > 30)
			self.gap = 0.02 + math.random() * 0.1
		else
			self.plan = {}
		end
	end

	-- footwork
	if self.strafeT <= 0 then
		self.strafeT = 1.2 + math.random() * 1.8
		self.strafe = math.random() < 0.5 and -1 or 1
	end
	local want = self.range * (oppHurt and 0.8 or 1) * (me.rocked > 0 and 1.5 or 1)
	if #self.plan > 0 then want = math.min(want, 0.85) end
	local fwd = math.clamp((dist - want) * 2.2, -1, 1)
	local lat = self.strafe * (self.style == "OutBoxer" and 0.85 or self.style == "Slugger" and 0.25 or 0.5)
	local f = dist > 0.01 and toOpp.Unit or me.hrp.CFrame.LookVector
	local right = f:Cross(Vector3.yAxis)
	if ring and ring.onRopes and ring.onRopes(me) then
		local toCenter = Util.flatUnit(ring.center - me.hrp.Position)
		lat = toCenter:Dot(right) > 0 and 1 or -1
		fwd = math.max(fwd, 0.2)
	end
	if ring and ring.onRopes and ring.onRopes(opp) and (self.style == "Swarmer" or self.style == "Brawler" or oppHurt) then
		lat *= 0.2
		fwd = math.max(fwd, 0.6)
	end
	me.move = Vector2.new(lat, fwd)

	-- showboat
	if self.tauntCd <= 0 and me.headHP > opp.headHP + 35 and not me.cur and math.random() < 0.004 then
		self.tauntCd = 14
		taunt(me)
	end
	local dir = right * lat + f * fwd
	if dir.Magnitude > 1 then dir = dir.Unit end
	return dir
end

return AI
