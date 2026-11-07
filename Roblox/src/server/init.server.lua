-- ============================================================
--  ALLEY BRAWL  -  สคริปต์หลักฝั่ง Server
--  (ServerScriptService > BrawlServer  + ModuleScript ลูก 6 ตัว)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))
local MapBuilder = require(script:WaitForChild("MapBuilder"))
local CB = require(script:WaitForChild("CharacterBuilder"))
local Ragdoll = require(script:WaitForChild("Ragdoll"))
local Combat = require(script:WaitForChild("Combat"))
local Weapons = require(script:WaitForChild("Weapons"))
local Bots = require(script:WaitForChild("Bots"))

Players.CharacterAutoLoads = false

-- ===== RemoteEvents =====
local remotes = {}
local rf = Instance.new("Folder")
rf.Name = "BrawlRemotes"
for _, n in ipairs({ "Action", "Fx", "Knock", "Ragdoll", "Notify" }) do
	local e = Instance.new("RemoteEvent")
	e.Name = n
	e.Parent = rf
	remotes[n] = e
end
rf.Parent = ReplicatedStorage

-- ===== สถานะเกม (client อ่าน) =====
local stateF = Instance.new("Folder")
stateF.Name = "BrawlState"
local phaseV = Instance.new("StringValue")
phaseV.Name = "Phase"
phaseV.Value = "fight"
phaseV.Parent = stateF
local endV = Instance.new("NumberValue")
endV.Name = "RoundEnd"
endV.Parent = stateF
local scoresF = Instance.new("Folder")
scoresF.Name = "Scores"
scoresF.Parent = stateF
stateF.Parent = ReplicatedStorage

-- ===== สร้างโลก =====
local map = MapBuilder.build(remotes)
local fightersFolder = Instance.new("Folder")
fightersFolder.Name = "Fighters"
fightersFolder.Parent = workspace

Ragdoll.init(remotes)
Combat.init({ remotes = remotes, Ragdoll = Ragdoll, CB = CB, Weapons = Weapons })
Weapons.init({ Combat = Combat, remotes = remotes, spawners = map.weaponSpawns })
Bots.init({ Combat = Combat, Ragdoll = Ragdoll, Weapons = Weapons })

-- ===== สถิติผู้เข้าแข่ง =====
local statsList = {} -- ทุกคน (ผู้เล่น+บอท)
local playerStats = {} -- [player] = stats
local scoreSeq = 0

local function newStats(name, isBot, player)
	scoreSeq = scoreSeq + 1
	local st = { name = name, isBot = isBot, player = player, kos = 0, deaths = 0, streak = 0, taunts = 0, dmg = 0 }
	local v = Instance.new("IntValue")
	v.Name = "S" .. scoreSeq
	v:SetAttribute("DisplayName", name)
	v:SetAttribute("IsBot", isBot)
	v.Parent = scoresF
	st.value = v
	table.insert(statsList, st)
	return st
end

local function removeStats(st)
	for i, s in ipairs(statsList) do
		if s == st then
			table.remove(statsList, i)
			break
		end
	end
	if st.value then
		st.value:Destroy()
	end
end

local function syncScores()
	for _, st in ipairs(statsList) do
		if st.value then
			st.value.Value = st.kos
			st.value:SetAttribute("Deaths", st.deaths)
		end
		if st.player and st.player.Parent then
			local ls = st.player:FindFirstChild("leaderstats")
			if ls then
				ls.KOs.Value = st.kos
				ls.Deaths.Value = st.deaths
			end
		end
	end
end
Combat.onScore = syncScores

-- ===== จุดเกิด: เลือกที่ห่างคนอื่นที่สุด =====
local function pickSpawn()
	local best, bestScore = map.spawns[1], -1
	for _, sp in ipairs(map.spawns) do
		local minD = 1e9
		for _, F in pairs(Combat.fighters) do
			if F.alive then
				minD = math.min(minD, (F.root.Position - sp).Magnitude)
			end
		end
		local score = minD + math.random() * 8
		if score > bestScore then
			best, bestScore = sp, score
		end
	end
	return best
end

local function placeModel(model)
	local sp = pickSpawn()
	model:PivotTo(CFrame.new(sp + Vector3.new(0, 3.3, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
end

-- ===== ผู้เล่น =====
local playerIndex = 0
local spawnPlayer

local function scheduleRespawn(player)
	task.delay(Config.RespawnTime, function()
		if player.Parent then
			spawnPlayer(player)
		end
	end)
end

spawnPlayer = function(player)
	local st = playerStats[player]
	if not st or not player.Parent then
		return
	end
	local model = CB.build(CB.playerLook(st.index), player.DisplayName, player)
	Ragdoll.setup(model)
	placeModel(model)
	player.Character = model
	model.Parent = fightersFolder
	pcall(function()
		model.HumanoidRootPart:SetNetworkOwner(player)
	end)
	Combat.register(model, { player = player, name = player.DisplayName, stats = st })
end

local function onPlayerAdded(player)
	playerIndex = playerIndex + 1
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local ko = Instance.new("IntValue")
	ko.Name = "KOs"
	ko.Parent = ls
	local dn = Instance.new("IntValue")
	dn.Name = "Deaths"
	dn.Parent = ls
	ls.Parent = player
	player.CameraMaxZoomDistance = 40
	player.CameraMinZoomDistance = 6
	local st = newStats(player.DisplayName, false, player)
	st.index = playerIndex
	playerStats[player] = st
	task.delay(0.5, function()
		spawnPlayer(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	local char = player.Character
	if char then
		local F = Combat.fighters[char]
		if F then
			Bots.remove(F)
		end
		Combat.unregister(char)
		char:Destroy()
	end
	local st = playerStats[player]
	if st then
		removeStats(st)
		playerStats[player] = nil
	end
end)

-- ===== บอท =====
local botSlots = {}
local usedNames = {}

local function botName()
	local pool = {}
	for _, n in ipairs(Config.BotNames) do
		if not usedNames[n] then
			table.insert(pool, n)
		end
	end
	if #pool == 0 then
		return "Thug #" .. math.random(10, 99)
	end
	local n = pool[math.random(1, #pool)]
	usedNames[n] = true
	return n
end

local function spawnBot(slot)
	if not slot.active then
		return
	end
	local model = CB.build(slot.look, slot.name, nil)
	Ragdoll.setup(model)
	placeModel(model)
	model.Parent = fightersFolder
	pcall(function()
		model.HumanoidRootPart:SetNetworkOwner(nil)
	end)
	local F = Combat.register(model, { name = slot.name, isBot = true, stats = slot.stats })
	slot.F = F
	Bots.add(F)
end

local function desiredBots()
	local n = #Players:GetPlayers()
	if n >= 4 then
		return math.min(Config.BotCount, Config.BotsWhenPlayers)
	end
	return Config.BotCount
end

local function updateBots()
	local want = desiredBots()
	local active = 0
	for _, s in ipairs(botSlots) do
		if s.active then
			active = active + 1
		end
	end
	while active < want do
		local rng = Random.new()
		local slot = { active = true, name = botName(), look = CB.randomLook(rng) }
		slot.stats = newStats(slot.name, true, nil)
		table.insert(botSlots, slot)
		spawnBot(slot)
		active = active + 1
	end
	if active > want then
		for i = #botSlots, 1, -1 do
			local s = botSlots[i]
			if s.active and active > want then
				s.active = false
				active = active - 1
				if s.F then
					Bots.remove(s.F)
					Combat.unregister(s.F.model)
					s.F.model:Destroy()
				end
				usedNames[s.name] = nil
				removeStats(s.stats)
				table.remove(botSlots, i)
			end
		end
	end
end

Combat.onDeath = function(F)
	-- ร่างนอนสักพักแล้วหายไป
	local model = F.model
	task.delay(Config.CorpseTime, function()
		Combat.unregister(model)
		if model.Parent then
			model:Destroy()
		end
	end)
	if F.player then
		scheduleRespawn(F.player)
	elseif F.isBot then
		Bots.remove(F)
		for _, s in ipairs(botSlots) do
			if s.F == F then
				task.delay(Config.RespawnTime, function()
					if s.active then
						s.look = CB.randomLook(Random.new())
						spawnBot(s)
					end
				end)
			end
		end
	end
end

task.delay(1, updateBots)
Players.PlayerAdded:Connect(function()
	task.delay(1, updateBots)
end)
Players.PlayerRemoving:Connect(function()
	task.delay(1, updateBots)
end)

-- ===== คำสั่งจากผู้เล่น =====
local rate = {}
remotes.Action.OnServerEvent:Connect(function(player, action, payload)
	if typeof(action) ~= "string" then
		return
	end
	local t = os.clock()
	local r = rate[player]
	if not r or t - r.t > 1 then
		r = { t = t, n = 0 }
		rate[player] = r
	end
	r.n = r.n + 1
	if r.n > 25 then
		return
	end
	local F = Combat.get(player.Character)
	if not F then
		return
	end
	if typeof(payload) ~= "table" then
		payload = {}
	end
	local dir = payload.dir
	if typeof(dir) == "Vector3" then
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 0.1 and dir.Magnitude == dir.Magnitude then
			dir = dir.Unit
		else
			dir = nil
		end
	else
		dir = nil
	end
	Combat.request(F, action, { dir = dir, air = payload.air == true, on = payload.on == true })
end)
Players.PlayerRemoving:Connect(function(p)
	rate[p] = nil
end)

-- ===== ลูปหลัก =====
RunService.Heartbeat:Connect(function(dt)
	Combat.step(dt)
	Bots.step(dt)
end)

-- กันผู้เล่นค้างไม่มีตัว
task.spawn(function()
	while true do
		task.wait(3)
		for player, st in pairs(playerStats) do
			local char = player.Character
			if player.Parent and (not char or not char.Parent) and not st.pending then
				st.pending = true
				task.delay(1, function()
					st.pending = false
					local c = player.Character
					if player.Parent and (not c or not c.Parent) then
						spawnPlayer(player)
					end
				end)
			end
		end
	end
end)

-- ===== รอบการแข่ง =====
local function bestBy(field)
	local best, bv = nil, -1
	for _, st in ipairs(statsList) do
		local v = st[field] or 0
		if v > bv then
			best, bv = st, v
		end
	end
	if bv <= 0 then
		return nil, 0
	end
	return best, bv
end

task.spawn(function()
	while true do
		phaseV.Value = "fight"
		endV.Value = workspace:GetServerTimeNow() + Config.RoundTime
		task.wait(Config.RoundTime)
		local king, kos = bestBy("kos")
		local potato, deaths = bestBy("deaths")
		local dancer, taunts = bestBy("taunts")
		local brute, dmg = bestBy("dmg")
		remotes.Notify:FireAllClients("round", {
			king = king and king.name, kos = kos,
			potato = potato and potato.name, deaths = deaths,
			dancer = dancer and dancer.name, taunts = taunts,
			brute = brute and brute.name, dmg = math.floor(dmg),
		})
		phaseV.Value = "results"
		endV.Value = workspace:GetServerTimeNow() + Config.ResultTime
		task.wait(Config.ResultTime)
		for _, st in ipairs(statsList) do
			st.kos, st.deaths, st.streak, st.taunts, st.dmg = 0, 0, 0, 0, 0
		end
		syncScores()
		remotes.Notify:FireAllClients("newround", {})
	end
end)

print("[ALLEY BRAWL] ready to rumble! 🔥")
