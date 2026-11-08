--[[
	NEON BAY: THE PIT  -  server entry
	Players walk the warehouse as their custom boxer. Step on both corner pads of a ring for a PvP fight, or
	open CAREER to fight the Pit's ranked CPU fighters. All combat is resolved here (see Fighter / Match).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local TextService = game:GetService("TextService")

-- remotes first: other modules wait for them
local remotes = Instance.new("Folder")
remotes.Name = "NeonBayRemotes"
local function remote(name, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local InputEv = remote("Input")
local LeanEv
do
	local ok, ev = pcall(function() return remote("Lean", "UnreliableRemoteEvent") end)
	LeanEv = ok and ev or remote("Lean")
end
remote("Impact")
remote("MatchEvent")
local NotifyEv = remote("Notify")
local RequestFn = remote("Request", "RemoteFunction")
remotes.Parent = ReplicatedStorage

pcall(function()
	PhysicsService:RegisterCollisionGroup("Ragdoll")
	PhysicsService:CollisionGroupSetCollidable("Ragdoll", "Ragdoll", false)
end)

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local CharacterService = require(script.Parent.CharacterService)
local Data = require(script.Parent.Data)
local Match = require(script.Parent.Match)

local matches = {} -- ring -> match
local fighterOf = {} -- player -> match

local function notify(player, text, color)
	NotifyEv:FireClient(player, { text = text, color = color })
end

-- ---------------------------------------------------------------- helpers
local function rings()
	local map = workspace:FindFirstChild("Map")
	local list = {}
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("IsRing") then table.insert(list, d) end
		end
	end
	table.sort(list, function(a, b) return (a:GetAttribute("RingOrder") or 0) < (b:GetAttribute("RingOrder") or 0) end)
	return list
end

local function freeRing()
	for _, r in rings() do
		if not r:GetAttribute("Busy") then return r end
	end
	return nil
end

local function record(d)
	return string.format("%d-%d%s (%d KO)", d.wins, d.losses, d.draws > 0 and ("-" .. d.draws) or "", d.kos)
end

local function publish(player)
	local d = Data.Get(player)
	if not d then return end
	player:SetAttribute("Cash", d.cash)
	player:SetAttribute("Wins", d.wins)
	player:SetAttribute("Losses", d.losses)
	player:SetAttribute("Draws", d.draws)
	player:SetAttribute("KOs", d.kos)
	player:SetAttribute("Rank", d.rank)
	player:SetAttribute("Created", d.created)
	for k, v in d.train do player:SetAttribute("Train_" .. k, v) end
	local inj = 0
	for _, v in d.injuries do if type(v) == "number" then inj = math.max(inj, v) end end
	player:SetAttribute("Injured", inj)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Wins.Value = d.wins
		ls.KOs.Value = d.kos
	end
end

local function spawnPlayer(player)
	local d = Data.Get(player)
	if not d then return end
	local look = Util.deepCopy(d.look)
	look.outfit = "boxer"
	local model = CharacterService.SpawnPlayer(player, look, CharacterService.SpawnPoint())
	model:SetAttribute("Injuries", nil)
	-- carried damage shows on the face in the lobby too
	for k, v in d.injuries do
		if type(v) == "number" and k ~= "concussion" and k ~= "bodyTrauma" then model:SetAttribute("I_" .. k, v) end
	end
	return model
end

-- ---------------------------------------------------------------- referee
local REF_LOOK = {
	name = "Referee", nickname = "", female = false, skin = 4, hair = 3, hairColor = 4, beard = 3, beardColor = 4, brows = 1,
	eye = 8, jaw = 0.7, bulk = 1.05, muscle = 0.3, height = 1.0, trunks = 4, gloves = 3, accent = 9, outfit = "street",
}

local function buildReferee(m)
	local spot = m.ring:FindFirstChild("Neutral2")
	local at = CFrame.new((spot and spot.Position or m.center) + Vector3.new(0, 0.5, 0))
	local model = CharacterService.BuildRig(REF_LOOK, "Referee", "Referee", at)
	model.Parent = workspace
	pcall(function() model.HumanoidRootPart:SetNetworkOwner(nil) end)
	return model
end

local function tickReferee(m)
	local ref = m.referee
	if not ref or not ref.Parent then return end
	local hum = ref:FindFirstChildOfClass("Humanoid")
	local hrp = ref:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return end
	local a, b = m.Red.hrp.Position, m.Blue.hrp.Position
	local target
	if m.phase == "Knockdown" and m.downed then
		local dp = m.downed.hrp.Position
		target = dp - Util.flatUnit(dp - m.center) * 3.2
	else
		local mid = (a + b) / 2
		local line = Util.flatUnit(b - a)
		local perp = line:Cross(Vector3.yAxis)
		local c1, c2 = mid + perp * 5.5, mid - perp * 5.5
		target = (c1 - m.center).Magnitude < (c2 - m.center).Magnitude and c1 or c2
	end
	local lim = Config.Ring.ropeHalf - 1.4
	local l = target - m.center
	target = m.center + Vector3.new(math.clamp(l.X, -lim, lim), 0, math.clamp(l.Z, -lim, lim))
	if (Util.flat(target - hrp.Position)).Magnitude > 1 then hum:MoveTo(target) else hum:Move(Vector3.zero) end
end

-- ---------------------------------------------------------------- matches
local function entryForPlayer(player)
	local d = Data.Get(player)
	local look = d.look
	return {
		model = player.Character, player = player, name = (look.name ~= "" and look.name or player.DisplayName), nick = look.nickname or "",
		record = record(d), stats = Data.FightStats(d), style = "OutBoxer", southpaw = look.southpaw == true, injuries = d.injuries,
	}
end

local function closeMatch(m)
	matches[m.ring] = nil
	for _, f in { m.Red, m.Blue } do
		if f.player then
			fighterOf[f.player] = nil
			if f.player.Parent then spawnPlayer(f.player) end
		elseif f.model.Parent then
			f.model:Destroy()
		end
	end
	if m.referee then m.referee:Destroy() end
	m.ring:SetAttribute("Busy", false)
	m.ring:SetAttribute("Phase", "Idle")
	for _, n in { "RedModel", "BlueModel", "RefModel" } do
		local v = m.ring:FindFirstChild(n)
		if v then v.Value = nil end
	end
end

local function onMatchEnd(m, result)
	local extra = {}
	for _, f in { m.Red, m.Blue } do
		if f.player then
			local d = Data.Get(f.player)
			if d then
				local won = m.winner == f
				local draw = m.winner == nil
				local roster = f.opponent.entry.rosterIndex
				local purse
				if draw then
					d.draws += 1
					purse = roster and math.floor(Config.Roster[roster].purse / 2) or 250
				elseif won then
					d.wins += 1
					if result.ko then d.kos += 1 end
					purse = roster and math.floor(Config.Roster[roster].purse * (result.ko and 1.25 or 1)) or 600
					if roster and roster == d.rank + 1 then d.rank = math.min(#Config.Roster, d.rank + 1) end
				else
					d.losses += 1
					purse = roster and math.floor(Config.Roster[roster].purse / 4) or 150
				end
				d.cash += purse
				d.injuries = f:InjuryRecord()
				publish(f.player)
				Data.Save(f.player)
				extra[(f.corner == 0 and "redPurse" or "bluePurse")] = purse
			end
		end
	end
	return extra
end

local function startMatch(ring, red, blue, opts)
	opts = opts or {}
	opts.buildReferee = buildReferee
	opts.onEnd = onMatchEnd
	opts.onClose = closeMatch
	for _, e in { red, blue } do
		if e.player then
			fighterOf[e.player] = true
			e.model = e.player.Character
		end
	end
	local m = Match.new(ring, red, blue, opts)
	matches[ring] = m
	for _, e in { red, blue } do
		if e.player then fighterOf[e.player] = m end
	end
	return m
end

local function startCareer(player, rosterIndex)
	if fighterOf[player] then return false, "You're already fighting." end
	local d = Data.Get(player)
	if not d then return false, "Loading..." end
	local ring = freeRing()
	if not ring then return false, "Both rings are busy. Watch the fight or try again soon." end
	local idx = rosterIndex or math.min(#Config.Roster, d.rank + 1)
	if idx > d.rank + 1 then return false, "You have to climb the rankings first." end
	local opp = Config.Roster[idx]
	local look = Util.deepCopy(opp.look)
	look.outfit = "boxer"
	look.southpaw = opp.southpaw
	look.nickname = opp.nick
	local corner = ring:FindFirstChild("BlueCorner")
	local model = CharacterService.BuildRig(look, opp.name, "CPU", CFrame.new(corner.Position + Vector3.new(0, 0.5, 0)))
	model.Parent = workspace
	pcall(function() model.HumanoidRootPart:SetNetworkOwner(nil) end)
	local diff = math.clamp(0.45 + idx * 0.06, 0.45, 0.95)
	startMatch(ring, entryForPlayer(player), {
		model = model, name = opp.name, nick = opp.nick, record = string.format("%d-%d (%d KO)", opp.w, opp.l, opp.ko), stats = opp.stats,
		style = opp.style, southpaw = opp.southpaw, rosterIndex = idx,
	}, { rounds = opp.rounds, difficulty = diff, bio = opp.bio, cpuDamage = 0.9 })
	return true
end

-- ---------------------------------------------------------------- players
Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local w = Instance.new("IntValue"); w.Name = "Wins"; w.Parent = ls
	local k = Instance.new("IntValue"); k.Name = "KOs"; k.Parent = ls
	ls.Parent = player
	Data.Load(player)
	publish(player)
	spawnPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local m = fighterOf[player]
	if type(m) == "table" then m:PlayerLeft(player) end
	Data.Release(player)
	fighterOf[player] = nil
end)

-- ---------------------------------------------------------------- input
local function lobbyPunch(player, id)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if os.clock() - (char:GetAttribute("LastPunchClock") or 0) < 0.22 then return end
	char:SetAttribute("LastPunchClock", os.clock())
	local t0 = workspace:GetServerTimeNow()
	char:SetAttribute("Act", id)
	char:SetAttribute("ActId", (char:GetAttribute("ActId") or 0) + 1)
	char:SetAttribute("ActT0", t0)
	char:SetAttribute("ActScale", 1)
	task.delay(0.55, function()
		if char.Parent and char:GetAttribute("ActT0") == t0 then char:SetAttribute("Act", 0) end
	end)
	-- heavy bags
	local map = workspace:FindFirstChild("Map")
	if not map then return end
	for _, bag in map:GetDescendants() do
		if bag:IsA("BasePart") and bag.Name == "Bag" then
			local to = bag.Position - hrp.Position
			if Util.flat(to).Magnitude < 4.2 and math.abs(to.Y) < 4 and hrp.CFrame.LookVector:Dot(Util.flatUnit(to)) > 0.4 then
				task.delay(0.18, function()
					bag:ApplyImpulse(Util.flatUnit(to) * bag.AssemblyMass * (id == 1 and 9 or 16))
					ReplicatedStorage.NeonBayRemotes.Impact:FireAllClients({ type = "bag", pos = bag.Position, power = id ~= 1 })
				end)
				break
			end
		end
	end
end

InputEv.OnServerEvent:Connect(function(player, msg)
	if type(msg) ~= "table" then return end
	local m = fighterOf[player]
	if type(m) == "table" then
		m:Input(player, msg)
	elseif msg.k == "punch" then
		lobbyPunch(player, math.clamp(tonumber(msg.id) or 1, 1, 6))
	end
end)

LeanEv.OnServerEvent:Connect(function(player, x, y, z)
	local m = fighterOf[player]
	if type(m) == "table" then m:Input(player, { k = "lean", x = x, y = y, z = z }) end
end)

-- ---------------------------------------------------------------- requests from the UI
local function clampLook(look, old)
	local o = Util.deepCopy(old)
	local function int(k, lo, hi) if type(look[k]) == "number" then o[k] = math.clamp(math.floor(look[k]), lo, hi) end end
	local function num(k, lo, hi) if type(look[k]) == "number" then o[k] = math.clamp(look[k], lo, hi) end end
	local function bool(k) if type(look[k]) == "boolean" then o[k] = look[k] end end
	int("skin", 1, #Config.SkinTones); int("hair", 1, #Config.HairNames); int("hairColor", 1, #Config.HairColors)
	int("beard", 1, #Config.BeardNames); int("beardColor", 0, #Config.HairColors); int("brows", 1, #Config.BrowNames)
	int("eye", 1, #Config.EyeColors); int("trunks", 1, #Config.TrunkColors); int("gloves", 1, #Config.GloveColors); int("accent", 1, 9)
	num("jaw", 0, 1); num("bulk", 0.85, 1.35); num("muscle", 0, 1); num("height", 0.92, 1.08)
	bool("female"); bool("southpaw"); bool("tattoo")
	return o
end

local function filter(player, text)
	if type(text) ~= "string" then return "" end
	text = string.sub(text, 1, 18)
	if text == "" then return "" end
	local ok, res = pcall(function()
		local f = TextService:FilterStringAsync(text, player.UserId)
		return f:GetNonChatStringForBroadcastAsync()
	end)
	if ok then return res end
	-- text filtering is unavailable in some Studio sessions; only then fall back to the raw text
	return RunService:IsStudio() and text or ""
end

RequestFn.OnServerInvoke = function(player, kind, arg)
	local d = Data.Get(player)
	if not d then return false, "Loading..." end
	if kind == "saveLook" and type(arg) == "table" then
		if fighterOf[player] then return false, "Not during a fight." end
		local old = d.look
		local new = clampLook(arg, old)
		new.name = filter(player, arg.name)
		if new.name == "" then new.name = player.DisplayName end
		new.nickname = filter(player, arg.nickname)
		d.look = new
		d.created = true
		publish(player)
		local rebuild = new.bulk ~= old.bulk or new.height ~= old.height or new.female ~= old.female or new.muscle ~= old.muscle
		local char = player.Character
		if rebuild or not char then
			local at = char and char:GetPivot() or CharacterService.SpawnPoint()
			local look = Util.deepCopy(new); look.outfit = "boxer"
			CharacterService.SpawnPlayer(player, look, CFrame.new(at.Position - Vector3.new(0, 3, 0)) * at.Rotation)
		else
			local look = Util.deepCopy(new); look.outfit = "boxer"
			CharacterService.Redress(char, look)
		end
		Data.Save(player)
		return true
	elseif kind == "career" then
		return startCareer(player, nil)
	elseif kind == "exhibition" then
		local i = tonumber(arg)
		if not i or i < 1 or i > d.rank then return false, "You haven't beaten that fighter yet." end
		return startCareer(player, i)
	elseif kind == "train" then
		local key = tostring(arg)
		if d.train[key] == nil then return false, "?" end
		local lv = d.train[key]
		if lv >= Config.TrainMax then return false, "Maxed out." end
		local cost = Config.TrainCost(lv)
		if d.cash < cost then return false, "Not enough cash." end
		d.cash -= cost
		d.train[key] = lv + 1
		publish(player)
		return true
	elseif kind == "heal" then
		local cost = 200
		if d.cash < cost then return false, "Not enough cash." end
		d.cash -= cost
		d.injuries = {}
		publish(player)
		if not fighterOf[player] then spawnPlayer(player) end
		return true
	elseif kind == "profile" then
		return true, d
	end
	return false, "Unknown request"
end

-- ---------------------------------------------------------------- PvP corner pads
local padHold = {}
local function padOccupant(pad)
	for _, pl in Players:GetPlayers() do
		local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if hrp and not fighterOf[pl] and (Util.flat(hrp.Position - pad.Position)).Magnitude < pad.Size.X / 2 + 0.5 and math.abs(hrp.Position.Y - pad.Position.Y) < 6 then
			return pl
		end
	end
	return nil
end

task.spawn(function()
	while true do
		task.wait(0.25)
		for _, ring in rings() do
			if not ring:GetAttribute("Busy") then
				local rp, bp = ring:FindFirstChild("RedPad", true), ring:FindFirstChild("BluePad", true)
				if rp and bp then
					local a, b = padOccupant(rp), padOccupant(bp)
					ring:SetAttribute("PadRed", a and a.DisplayName or "")
					ring:SetAttribute("PadBlue", b and b.DisplayName or "")
					if a and b and a ~= b then
						padHold[ring] = (padHold[ring] or 0) + 0.25
						ring:SetAttribute("Countdown", math.max(0, Config.Match.pvpCountdown - padHold[ring]))
						if padHold[ring] >= Config.Match.pvpCountdown then
							padHold[ring] = 0
							ring:SetAttribute("Countdown", -1)
							startMatch(ring, entryForPlayer(a), entryForPlayer(b), { rounds = 3, difficulty = 0.6 })
						end
					else
						padHold[ring] = 0
						ring:SetAttribute("Countdown", -1)
					end
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------- main loop
RunService.Heartbeat:Connect(function(dt)
	for ring, m in matches do
		local ok, alive = pcall(function() return m:Tick(dt) end)
		if not ok then
			warn("[NeonBay] match error:", alive)
			pcall(closeMatch, m)
		elseif alive then
			tickReferee(m)
		end
	end
	-- fell out of the world
	for _, pl in Players:GetPlayers() do
		local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp.Position.Y < -60 and not fighterOf[pl] then spawnPlayer(pl) end
	end
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, pl in Players:GetPlayers() do Data.Save(pl) end
	end
end)

game:BindToClose(function()
	for _, pl in Players:GetPlayers() do Data.Save(pl) end
end)

-- heavy bags swing on server physics so every player sees the same swing
task.defer(function()
	local map = workspace:WaitForChild("Map", 10)
	if not map then return end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Bag" and not d.Anchored then
			pcall(function() d:SetNetworkOwner(nil) end)
		end
	end
end)

print("[NeonBay] THE PIT v" .. Config.Version .. " server ready")
