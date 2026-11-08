--[[
	One fight in one ring: intro, timed rounds, the referee and his ten-count, the get-up minigame, three
	judges with their own habits, the corner between rounds, doctor stoppages, KO ragdolls and the result.
	The ring model publishes the match state as attributes so every client can draw the HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local PunchData = require(Shared.PunchData)
local Util = require(Shared.Util)

local Fighter = require(script.Parent.Fighter)
local AI = require(script.Parent.AI)
local Ragdoll = require(script.Parent.Ragdoll)

local Remotes = ReplicatedStorage:WaitForChild("NeonBayRemotes")
local ImpactEv = Remotes:WaitForChild("Impact")
local MatchEv = Remotes:WaitForChild("MatchEvent")

local Match = {}
Match.__index = Match

local function now() return workspace:GetServerTimeNow() end

local JUDGES = {
	{ name = "Marisol Vega", power = 1.2, activity = 0.8, defense = 1.0, ring = 1.0 },
	{ name = "Hank 'Two-Cards' Doyle", power = 1.6, activity = 0.6, defense = 0.5, ring = 0.8 },
	{ name = "Dr. Anan Sirikul", power = 0.9, activity = 1.3, defense = 1.2, ring = 1.2 },
}

local CORNER = { "WORK THE CUT", "ICE THE SWELLING", "CATCH YOUR BREATH", "GO FOR THE KO" }
Match.CornerOptions = CORNER

--[[
	ring: the ring model (must contain Canvas, RedCorner, BlueCorner, Neutral1, Neutral2 parts)
	red / blue: { model, player?, name, nick, record, stats, style, southpaw, injuries?, rosterId? }
	hooks: { onEnd(match, result), buildReferee(ring) -> model }
]]
function Match.new(ring, red, blue, opts)
	local self = setmetatable({}, Match)
	self.ring = ring
	self.canvas = ring:FindFirstChild("Canvas")
	self.center = self.canvas.Position + Vector3.new(0, self.canvas.Size.Y / 2, 0)
	self.opts = opts or {}
	self.rounds = math.max(3, self.opts.rounds or 3)
	self.round = 0
	self.clock = Config.Match.roundLength
	self.phase = "Intro"
	self.phaseT = 0
	self.Red = Fighter.new(red.model, { player = red.player, name = red.name, nick = red.nick, record = red.record, stats = red.stats, style = red.style, southpaw = red.southpaw, injuries = red.injuries, corner = 0 })
	self.Blue = Fighter.new(blue.model, { player = blue.player, name = blue.name, nick = blue.nick, record = blue.record, stats = blue.stats, style = blue.style, southpaw = blue.southpaw, injuries = blue.injuries, corner = 1 })
	self.Red.opponent, self.Blue.opponent = self.Blue, self.Red
	self.Red.entry, self.Blue.entry = red, blue
	self.ais = {}
	local diff = self.opts.difficulty or 0.6
	if self.Red.isNPC then self.ais[self.Red] = AI.new(self.Red, self.Blue, diff) end
	if self.Blue.isNPC then self.ais[self.Blue] = AI.new(self.Blue, self.Red, diff) end
	self.judges = {}
	for _, j in JUDGES do table.insert(self.judges, { def = j, red = {}, blue = {} }) end
	self.cornerChoice = {}
	self.getUp = 0
	self.count = 0
	self.countT = 0
	self.clinchT = 0
	self.referee = self.opts.buildReferee and self.opts.buildReferee(self) or nil
	-- publish
	ring:SetAttribute("Busy", true)
	ring:SetAttribute("WinnerCorner", "")
	ring:SetAttribute("Comment", "")
	self:SetRingValue("RedModel", self.Red.model)
	self:SetRingValue("BlueModel", self.Blue.model)
	self:SetRingValue("RefModel", self.referee)
	ring:SetAttribute("RedName", self.Red.name)
	ring:SetAttribute("BlueName", self.Blue.name)
	ring:SetAttribute("RedNick", self.Red.nick)
	ring:SetAttribute("BlueNick", self.Blue.nick)
	ring:SetAttribute("RedRecord", self.Red.record)
	ring:SetAttribute("BlueRecord", self.Blue.record)
	ring:SetAttribute("RedStyle", Config.StyleNames[self.Red.style] or self.Red.style)
	ring:SetAttribute("BlueStyle", Config.StyleNames[self.Blue.style] or self.Blue.style)
	ring:SetAttribute("Rounds", self.rounds)
	ring:SetAttribute("Bio", self.opts.bio or "")
	for k, v in self.Red.stats do ring:SetAttribute("RedS_" .. k, v) end
	for k, v in self.Blue.stats do ring:SetAttribute("BlueS_" .. k, v) end
	for _, f in { self.Red, self.Blue } do
		f.model:SetAttribute("Fighter", true)
		f.model:SetAttribute("Corner", f.corner)
		local ov = f.model:FindFirstChild("Opponent") or Instance.new("ObjectValue")
		ov.Name = "Opponent"
		ov.Value = f.opponent.model
		ov.Parent = f.model
		local rv = f.model:FindFirstChild("Ring") or Instance.new("ObjectValue")
		rv.Name = "Ring"
		rv.Value = ring
		rv.Parent = f.model
		local hrp = f.hrp
		if f.hum then
			f.hum.AutoRotate = false
			f.hum.JumpPower = 0
		end
		local face = hrp:FindFirstChild("Facing")
		if face then face.Enabled = true end
		f:SyncInjuries()
	end
	self:PlaceInCorners()
	self:SetPhase("Intro")
	self:Event({ type = "intro" })
	return self
end

function Match:SetRingValue(name, inst)
	local v = self.ring:FindFirstChild(name)
	if not v then
		v = Instance.new("ObjectValue")
		v.Name = name
		v.Parent = self.ring
	end
	v.Value = inst
end

function Match:Event(t)
	t.ring = self.ring
	MatchEv:FireAllClients(t)
end

function Match:Say(text)
	self.ring:SetAttribute("Comment", text)
	self.ring:SetAttribute("CommentT", now())
end

function Match:Signal(text)
	if self.referee then
		self.referee:SetAttribute("Signal", text)
		self.referee:SetAttribute("SignalT", now())
	end
end

function Match:SetPhase(p)
	self.phase = p
	self.phaseT = 0
	self.ring:SetAttribute("Phase", p)
end

function Match:Corner(name)
	local c = self.ring:FindFirstChild(name)
	return c and c.Position or self.center
end

function Match:Place(f, cornerName)
	local pos = self:Corner(cornerName)
	local look = Util.flatUnit(self.center - pos)
	local y = self.center.Y + (f.hum and f.hum.HipHeight or 2) + f.hrp.Size.Y / 2 + 0.05
	local cf = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + look)
	-- the model pivot is the root part, so move the root and let the welded/motored rig follow
	f.model:PivotTo(cf * f.hrp.CFrame:ToObjectSpace(f.model:GetPivot()))
	f.hrp.AssemblyLinearVelocity = Vector3.zero
end

function Match:PlaceInCorners()
	self:Place(self.Red, "RedCorner")
	self:Place(self.Blue, "BlueCorner")
end

function Match:OnRopes(f)
	local l = f.hrp.Position - self.center
	local lim = Config.Ring.ropeHalf - 1.6
	return math.abs(l.X) > lim or math.abs(l.Z) > lim
end

-- ---------------------------------------------------------------- input from players
function Match:FighterFor(player)
	if self.Red.player == player then return self.Red end
	if self.Blue.player == player then return self.Blue end
	return nil
end

function Match:Input(player, msg)
	local f = self:FighterFor(player)
	if not f then return end
	local k = msg.k
	if k == "punch" then
		if self.phase == "Fight" then f:QueuePunch(math.clamp(tonumber(msg.id) or 1, 1, 6), msg.body == true, msg.power == true) end
	elseif k == "guard" then
		f.guard = math.clamp(tonumber(msg.g) or 0, 0, 2)
	elseif k == "lean" then
		local x, y, z = tonumber(msg.x) or 0, tonumber(msg.y) or 0, tonumber(msg.z) or 0
		f.lean = Vector3.new(math.clamp(x, -1, 1), math.clamp(y, -1, 0), math.clamp(z, -1, 0.5))
	elseif k == "clinch" then
		self:TryClinch(f)
	elseif k == "taunt" then
		self:Taunt(f)
	elseif k == "getup" then
		if self.phase == "Knockdown" and self.downed == f and os.clock() - (f.lastGetUpPress or 0) > 0.2 then
			f.lastGetUpPress = os.clock()
			if msg.hit then
				self.getUp += 1 / (2 + f.kdTotal)
			else
				self.getUp = math.max(0, self.getUp - 0.15)
			end
			self.ring:SetAttribute("GetUp", self.getUp)
		end
	elseif k == "corner" then
		if self.phase == "Corner" and not self.cornerChoice[f] then
			local i = math.clamp(tonumber(msg.i) or 3, 1, 4)
			self.cornerChoice[f] = i
			if i == 1 then f:Treat(0.55, 0.08)
			elseif i == 2 then f:Treat(0.1, 0.35)
			elseif i == 3 then f.staminaMax = math.min(105, f.staminaMax + 8); f.headHP = math.min(f.headCap, f.headHP + 8)
			else f.aggression = 1 end
			if i ~= 4 then f.aggression = 0 end
		end
	end
end

function Match:Taunt(f)
	if f.state ~= "Fight" or f.cur then return end
	f.model:SetAttribute("TauntT", now())
	f.stamina = math.min(f.staminaMax, f.stamina + 6)
	self:Event({ type = "popup", text = "SHOWBOAT!", color = Config.Neon.Magenta, at = f:HeadPoint() })
end

function Match:TryClinch(f)
	local o = f.opponent
	if f.state ~= "Fight" or o.state ~= "Fight" then return end
	if (f.hrp.Position - o.hrp.Position).Magnitude > 0.95 * f.scale + 1 then return end
	f:SetState("Clinch")
	o:SetState("Clinch")
	f:CancelPunch(); o:CancelPunch()
	self.clinchT = 1.4 + math.random() * 1
	self:Say(f.name:split(" ")[1] .. " ties him up!")
end

function Match:BreakClinch()
	for _, f in { self.Red, self.Blue } do
		if f.state == "Clinch" then f:SetState("Fight") end
	end
	self:Signal("BREAK!")
	local d = Util.flatUnit(self.Blue.hrp.Position - self.Red.hrp.Position)
	self.Red.model:PivotTo(self.Red.model:GetPivot() - d * 1.2)
	self.Blue.model:PivotTo(self.Blue.model:GetPivot() + d * 1.2)
end

-- ---------------------------------------------------------------- punches
function Match:ResolvePunch(a, def, body, power)
	local d = a.opponent
	if not d or d:IsDown() or self.phase ~= "Fight" then a:OnPunchResult("miss") return end
	local sh = a:ShoulderPoint(def.lead)
	local target
	if body then
		local leftHand = (def.lead and not a.southpaw) or (not def.lead and a.southpaw)
		local side = def.kind == "hook" and (leftHand and 1 or -1) or 0
		target = d:BodyPoint(side)
	elseif def.kind == "upper" then
		target = d:ChinPoint()
	else
		target = d:HeadPoint()
	end
	local reach = def.reach * a.scale * (power and 1.04 or 1) + 0.06 * a.scale
	local toT = target - sh
	local dir = toT.Magnitude > 0 and toT.Unit or a.hrp.CFrame.LookVector
	local facing = a.hrp.CFrame.LookVector:Dot(Util.flatUnit(d.hrp.Position - a.hrp.Position))
	local inRange = toT.Magnitude <= reach and facing > 0.5 and d.state ~= "Clinch"
	local base = { type = "impact", att = a.model, def = d.model, id = def.id, body = body, power = power, pos = target, dir = dir }
	if not inRange then
		a:OnPunchResult("miss")
		base.res = "miss"
		ImpactEv:FireAllClients(base)
		return
	end
	local res, mult = d:Evaluate(a, def, body)
	local counter = res == "clean" and (d:InRecovery() or d:WindingUp() or a.counterWindow > 0)
	if res == "slip" then
		a:OnPunchResult("slip")
		d.counterWindow = 0.6
		d.round.evaded += 1
		base.res = "slip"
		ImpactEv:FireAllClients(base)
		return
	end
	if res == "parry" then
		a:OnPunchResult("parry")
		d.counterWindow = 0.7
		d.round.evaded += 1
		base.res = "parry"
		ImpactEv:FireAllClients(base)
		return
	end
	local dmg = def.damage * Config.DamageScale * a:PowerFactor() * (power and Config.PowerMult or 1) * a:StaminaFactor() * mult * (0.9 + math.random() * 0.2)
	if counter then dmg *= Config.CounterMult end
	dmg *= 1 + (a.aggression or 0) * 0.1
	dmg *= 1 + (d.aggression or 0) * 0.12
	if d.rocked > 0 and not body then dmg *= 1.1 end
	if a.isNPC and d.player then dmg *= self.opts.cpuDamage or 1 end
	local side = (d.hrp.CFrame.RightVector:Dot(dir) > 0) and -1 or 1
	local kd = d:TakeHit(a, def, body, power, dmg, res, side, counter)
	local pk = math.clamp(dmg / 14, 0.1, 1.6)
	base.dmg, base.pk, base.counter = dmg, pk, counter
	if res == "block" then
		a:OnPunchResult("block")
		d.round.blocked += 1
		base.res = "block"
		ImpactEv:FireAllClients(base)
		return
	end
	a:OnPunchResult("clean")
	local r = a.round
	r.landed += 1
	if def.id == 1 then r.jabsLanded += 1 else r.powerLanded += 1 end
	if body then r.bodyLanded += 1 else r.headLanded += 1 end
	if counter then r.counters += 1 end
	r.damage += dmg
	base.res = "clean"
	base.rocked = d.rocked > 0
	ImpactEv:FireAllClients(base)
	if d.rocked > 1.5 and not kd and os.clock() - (self.lastRockSay or 0) > 2.5 then
		self.lastRockSay = os.clock()
		self:Say(d.name:split(" ")[1]:upper() .. " IS HURT! He's in trouble!")
	end
	if kd then self:Knockdown(d, a, dir, pk) end
end

-- ---------------------------------------------------------------- knockdowns
function Match:Knockdown(v, by, dir, pk)
	local ko = v.headHP < -28 or v.kdRound >= 2 or (v.kdTotal >= 3 and math.random() < 0.6)
	by.round.knockdowns += 1
	v:KnockDown(dir, ko)
	self:Event({ type = "knockdown", victim = v.model, ko = ko, dir = dir })
	self:Say(ko and ("DOWN GOES " .. v.name:upper() .. "! HE'S OUT COLD!") or ("DOWN GOES " .. v.name:upper() .. "!"))
	self.downed = v
	if v.kdRound >= 3 then
		self:KO(v, dir, pk)
		self:End(by, "TKO", "Three knockdowns in round " .. self.round)
		return
	end
	if ko then
		self:KO(v, dir, pk)
		self:End(by, "KO", "Knockout, round " .. self.round .. " " .. Util.formatTime(Config.Match.roundLength - self.clock))
		return
	end
	self:SetPhase("Knockdown")
	self.count = 0
	self.countT = -Config.Match.countStartDelay
	self.getUp = 0
	self.ring:SetAttribute("Count", 0)
	self.ring:SetAttribute("GetUp", 0)
	self.ring:SetAttribute("Downed", v.corner == 0 and "Red" or "Blue")
	self.ring:SetAttribute("GetUpZone", Util.lerp(0.12, 0.3, v:Stat("heart") / 100) * Util.lerp(1, 0.6, math.clamp((v.kdTotal - 1) / 3, 0, 1)))
	by:SetState("Corner")
	-- send the other fighter to the farther neutral corner
	local hp = v.hrp.Position
	local n1, n2 = self:Corner("Neutral1"), self:Corner("Neutral2")
	task.delay(0.8, function()
		if self.phase == "Knockdown" then self:Place(by, (n1 - hp).Magnitude > (n2 - hp).Magnitude and "Neutral1" or "Neutral2") end
	end)
	if v.isNPC then
		local will = v:Stat("heart") / 100 + 0.4 - (v.kdTotal - 1) * 0.15 - math.clamp(-v.headHP / 40, 0, 1) * 0.35
		self.aiGetUpAt = will > math.random() * 0.9 and math.random(4, 9) or 11
	end
end

function Match:KO(v, dir, pk)
	v:SetState("KO")
	local impulse = (Util.flatUnit(dir) * (420 + pk * 380) + Vector3.new(0, 140, 0))
	task.delay(0.12, function()
		if v.model.Parent then Ragdoll.Enable(v.model, impulse) end
	end)
end

function Match:LiverKnockdown(v)
	if self.phase ~= "Fight" or v:IsDown() then return end
	self:Say("A LIVER SHOT! " .. v.name:split(" ")[1] .. " folds in half!")
	self:Event({ type = "popup", text = "LIVER SHOT", color = Config.Neon.Orange, at = v:BodyPoint(0) })
	self:Knockdown(v, v.opponent, -v.hrp.CFrame.LookVector, 0.4)
end

function Match:TickCount(dt)
	local v = self.downed
	if not v then
		self.resumeT -= dt
		if self.resumeT <= 0 then
			for _, f in { self.Red, self.Blue } do
				if f.state == "GetUp" or f.state == "Corner" then f:SetState("Fight") end
			end
			self:SetPhase("Fight")
			self:Signal("BOX!")
		end
		return
	end
	self.countT += dt
	if self.countT >= Config.Match.countInterval then
		self.countT -= Config.Match.countInterval
		self.count += 1
		self.ring:SetAttribute("Count", self.count)
		self:Signal(tostring(self.count))
		self:Event({ type = "count", n = self.count })
		if self.count >= 10 then
			self:KO(v, -v.hrp.CFrame.LookVector, 0.2)
			self:End(v.opponent, "KO", "Counted out, round " .. self.round)
			return
		end
	end
	if self.count < 1 then return end
	if (v.isNPC and self.count >= (self.aiGetUpAt or 11)) or (not v.isNPC and self.getUp >= 1) then
		v:GetUp()
		self:Signal("Can you continue?")
		self:Say(v.name:split(" ")[1] .. " beats the count at " .. self.count .. "!")
		self.downed = nil
		self.resumeT = 2.4
		self.ring:SetAttribute("Downed", "")
		self:Event({ type = "getup", victim = v.model })
	end
end

-- ---------------------------------------------------------------- rounds
function Match:StartRound(n)
	self.round = n
	self.clock = Config.Match.roundLength
	self.ring:SetAttribute("Round", n)
	self.ring:SetAttribute("Clock", self.clock)
	for _, f in { self.Red, self.Blue } do
		f.kdRound = 0
		f.round = Fighter.NewStats()
		f:SetState("Intro")
	end
	self:PlaceInCorners()
	self:SetPhase("RoundStart")
	self:Event({ type = "round", n = n, final = n == self.rounds })
end

function Match:EndRound()
	self:Event({ type = "bell", count = 3 })
	self:Signal("TIME!")
	self:ScoreRound()
	for _, f in { self.Red, self.Blue } do f:SetState("Corner"); f:CancelPunch() end
	self:SetPhase("RoundEnd")
end

local function points(me, j)
	return me.jabsLanded * 1 * j.activity + me.powerLanded * 1.9 * j.power + me.damage * 0.06 * j.power + me.evaded * 0.35 * j.defense
		+ me.blocked * 0.15 * j.defense + me.center * 0.05 * j.ring + me.pressure * 0.03 * j.ring + me.thrown * 0.08 * j.activity + me.counters * 0.8
end

function Match:ScoreRound()
	for _, j in self.judges do
		local r, b = points(self.Red.round, j.def), points(self.Blue.round, j.def)
		local margin = (r - b) / math.max(1, r + b) + (math.random() - 0.5) * 0.16
		local rs, bs = 10, 10
		if margin > 0.06 then bs = 9 elseif margin < -0.06 then rs = 9 elseif math.random() < 0.5 then if margin >= 0 then bs = 9 else rs = 9 end end
		rs -= self.Blue.round.knockdowns
		bs -= self.Red.round.knockdowns
		rs, bs = math.max(rs, 6), math.max(bs, 6)
		if rs == bs and rs < 10 then rs += 1; bs += 1 end
		table.insert(j.red, rs)
		table.insert(j.blue, bs)
	end
	Fighter.AddStats(self.Red.total, self.Red.round)
	Fighter.AddStats(self.Blue.total, self.Blue.round)
end

function Match:CornerBegin()
	self.cornerChoice = {}
	-- doctor
	for _, f in { self.Red, self.Blue } do
		if self.round >= 2 and (f:MaxCut() > 0.95 or f:EyeClosure(true) > 0.98 or f:EyeClosure(false) > 0.98) and math.random() < 0.5 then
			self:Say("The ringside doctor waves it off! " .. f.name:split(" ")[1] .. " can't continue!")
			self:End(f.opponent, "TKO", "Doctor stoppage after round " .. self.round)
			return
		end
	end
	if self.round >= self.rounds then
		self:Decision()
		return
	end
	for _, f in { self.Red, self.Blue } do
		if f.player then
			local r, o = f.round, f.opponent.round
			local advice
			if f:MaxCut() > 0.4 then advice = "That cut is ugly. Let me work on it or the doc stops this."
			elseif math.max(f:EyeClosure(true), f:EyeClosure(false)) > 0.3 then advice = "Your eye is closing. Keep that side covered."
			elseif f.stamina < 35 or f.staminaMax < 70 then advice = "You're gassing! Stop loading up on every punch and breathe."
			elseif r.landed < o.landed then advice = "He's outworking you. Double the jab and go downstairs."
			else advice = "Good round! Hands up, make him miss, make him pay." end
			MatchEv:FireClient(f.player, { ring = self.ring, type = "corner", round = self.round, advice = advice, options = CORNER,
				me = r, them = o, cut = f:MaxCut(), eyeL = f:EyeClosure(true), eyeR = f:EyeClosure(false), concussion = f.concussion or 0, ribs = f.bodyTrauma or 0 })
		else
			f:Treat(0.25, 0.15)
		end
	end
end

function Match:CornerEnd()
	for _, f in { self.Red, self.Blue } do
		if not self.cornerChoice[f] and f.player then f:Treat(0.2, 0.1) end
		f:Recover(1)
	end
	self:StartRound(self.round + 1)
end

function Match:Decision()
	local r, b = 0, 0
	for _, j in self.judges do
		local jr, jb = 0, 0
		for i = 1, #j.red do jr += j.red[i]; jb += j.blue[i] end
		if jr > jb then r += 1 elseif jb > jr then b += 1 end
	end
	local w, method
	if r >= 2 and b == 0 then w, method = self.Red, (r == 3 and "UNANIMOUS DECISION" or "MAJORITY DECISION")
	elseif b >= 2 and r == 0 then w, method = self.Blue, (b == 3 and "UNANIMOUS DECISION" or "MAJORITY DECISION")
	elseif r == 2 then w, method = self.Red, "SPLIT DECISION"
	elseif b == 2 then w, method = self.Blue, "SPLIT DECISION"
	else method = "DRAW" end
	self:End(w, method, "After " .. self.rounds .. " rounds")
end

function Match:End(winner, method, detail)
	if self.ended then return end
	self.ended = true
	self.winner = winner
	self:SetPhase(method == "KO" and "KO" or "Result")
	for _, f in { self.Red, self.Blue } do
		if not f:IsDown() then f:SetState(f == winner and "Celebrate" or "Dejected") end
	end
	if self.round > 0 and #self.judges[1].red < self.round then
		Fighter.AddStats(self.Red.total, self.Red.round)
		Fighter.AddStats(self.Blue.total, self.Blue.round)
	end
	local cards = {}
	for _, j in self.judges do table.insert(cards, { name = j.def.name, red = j.red, blue = j.blue }) end
	local result = {
		type = "result",
		title = winner and (winner.name:upper() .. " WINS") or "DRAW",
		method = method .. "  -  " .. detail,
		winner = winner and (winner.corner == 0 and "Red" or "Blue") or "",
		ko = method == "KO" or method == "TKO",
		cards = cards,
		red = self.Red.total, blue = self.Blue.total,
		redName = self.Red.name, blueName = self.Blue.name,
	}
	self.result = result
	self.ring:SetAttribute("WinnerCorner", result.winner)
	if self.opts.onEnd then
		local extra = self.opts.onEnd(self, result)
		if extra then for k, v in extra do result[k] = v end end
	end
	self:Event(result)
	self:Event({ type = "bell", count = 3 })
end

-- ---------------------------------------------------------------- tick
function Match:Tick(dt)
	self.phaseT += dt
	local p = self.phase
	if p == "Intro" then
		if self.phaseT > Config.Match.introTime then self:StartRound(1) end
	elseif p == "RoundStart" then
		if self.phaseT > 1.6 then
			self:SetPhase("Fight")
			self.Red:SetState("Fight"); self.Blue:SetState("Fight")
			self:Event({ type = "bell", count = 1 })
			self:Signal("FIGHT!")
		end
	elseif p == "Fight" then
		self.clock -= dt
		self.ring:SetAttribute("Clock", math.max(0, self.clock))
		local rc, bc = Util.flat(self.Red.hrp.Position - self.center).Magnitude, Util.flat(self.Blue.hrp.Position - self.center).Magnitude
		if rc < bc - 1.3 then self.Red.round.center += dt elseif bc < rc - 1.3 then self.Blue.round.center += dt end
		for _, f in { self.Red, self.Blue } do
			if f.move.Y > 0.3 then f.round.pressure += dt end
		end
		if self.Red.state == "Clinch" then
			self.clinchT -= dt
			if self.clinchT <= 0 then self:BreakClinch() end
		end
		if self.clock <= 0 then self:EndRound() end
	elseif p == "Knockdown" then
		self:TickCount(dt)
	elseif p == "RoundEnd" then
		if self.phaseT > 2.4 then
			self:SetPhase("Corner")
			self:PlaceInCorners()
			self:CornerBegin()
		end
	elseif p == "Corner" then
		if self.phaseT > Config.Match.cornerTime then self:CornerEnd() end
	elseif p == "KO" then
		if self.phaseT > 4 then self:SetPhase("Result") end
	elseif p == "Result" then
		if self.phaseT > Config.Match.resultTime then
			self:SetPhase("Done")
			if self.opts.onClose then self.opts.onClose(self) end
			return false
		end
	end

	-- fighters
	local onImpact = function(f, def, body, power) self:ResolvePunch(f, def, body, power) end
	local onLiver = function(f) self:LiverKnockdown(f) end
	local ring = { center = self.center, onRopes = function(f) return self:OnRopes(f) end }
	for _, f in { self.Red, self.Blue } do
		local ai = self.ais[f]
		if ai and (p == "Fight" or p == "Intro" or p == "RoundStart") then
			local dir = ai:Tick(dt, ring, function(x) self:TryClinch(x) end, function(x) self:Taunt(x) end)
			if f.hum and f.state == "Fight" then f.hum:Move(dir, false) elseif f.hum then f.hum:Move(Vector3.zero, false) end
		elseif ai and f.hum then
			f.hum:Move(Vector3.zero, false)
		end
		if p ~= "Fight" and f.player then f.lean, f.guard = Vector3.zero, 0 end
		f:Tick(dt, onImpact, onLiver)
		-- NPCs face their opponent (players' own clients steer their facing)
		if f.isNPC and f.state ~= "KO" then
			local face = f.hrp:FindFirstChild("Facing")
			local look = Util.flatUnit(f.opponent.hrp.Position - f.hrp.Position, f.hrp.CFrame.LookVector)
			if (f.state == "Corner" or f.state == "Intro") and p ~= "Fight" then look = Util.flatUnit(self.center - f.hrp.Position, look) end
			if face then face.CFrame = CFrame.lookAt(Vector3.zero, look) end
		end
	end
	return true
end

function Match:PlayerLeft(player)
	local f = self:FighterFor(player)
	if f and not self.ended then
		self:End(f.opponent, "TKO", "Opponent left the arena")
	end
end

return Match
