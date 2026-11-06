local RS = game:GetService("ReplicatedStorage")
mountModule(RS, "BrawlConfig", "shared/BrawlConfig.lua")
mountModule(RS, "BrawlAnim", "shared/BrawlAnim.lua")
local Config = require(RS.BrawlConfig)
Config.RoundTime = 40
Config.ResultTime = 3
local SSS = game:GetService("ServerScriptService")
local main = mountModule(SSS, "BrawlServer", "server/init.server.lua", "Script")
for _, n in ipairs({ "MapBuilder", "CharacterBuilder", "Ragdoll", "Combat", "Weapons", "Bots" }) do
	mountModule(main, n, "server/" .. n .. ".lua")
end
local counts = {}
MockOnFireAll = function(name, kind)
	local k = name .. ":" .. tostring(kind)
	counts[k] = (counts[k] or 0) + 1
end
task.spawn(loadScript(main))
local Combat = require(main.Combat)
local Weapons = require(main.Weapons)
local Ragdoll = require(main.Ragdoll)
local Players = game:GetService("Players")
local function addPlayer(name)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	local pg = Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = p
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	return p
end
local remotes = RS:WaitForChild("BrawlRemotes")
local function act(p, a, payload)
	remotes.Action.OnServerEvent:Fire(p, a, payload or {})
end

local A, B
local dt = 1 / 30
local nextAct = 0
local actions = { "punch", "punch", "punch", "kick", "grab", "taunt", "punch", "kick" }
local ai = 0
local didWeapon, didThrow, didGlass, didMelon, didSuper, killedBot = false, false, false, false, false, false
local hitsSeen = 0
for step = 1, math.floor(130 / dt) do
	local before = {}
	for m, G in pairs(Combat.fighters) do before[m] = { G.root.CFrame, G.torso.CFrame, G.model:GetAttribute("Act"), G.model:GetAttribute("Ragdoll") } end
	simStep(dt)
	local t = SIM_T
	for m, G in pairs(Combat.fighters) do
		local p = G.root.Position
		if p.X ~= p.X and not NANREPORTED then
			NANREPORTED = true
			print("NaN root at", t, G.name, "before:", before[m] and tostring(before[m][1].Position), before[m] and before[m][3], before[m] and tostring(before[m][4]), "torso:", tostring(G.torso.Position))
		end
	end
	if not A and t > 1 then A = addPlayer("Alice") end
	if not B and t > 2 then B = addPlayer("Bob") end
	if A and A.Character and t > 3 and t < 100 and t > nextAct then
		nextAct = t + 0.28
		local F = Combat.get(A.Character)
		if F and not Ragdoll.isRagdolled(F.model) then
			-- find nearest enemy
			local best, bd
			for m, G in pairs(Combat.fighters) do
				if G ~= F and G.alive then
					local d = (G.root.Position - F.root.Position).Magnitude
					if not bd or d < bd then best, bd = G, d end
				end
			end
			if best then
				local ep = best.root.Position
				local pos = ep + Vector3.new(0, 0, 3)
				F.model:PivotTo(CFrame.lookAt(pos, ep))
				ai = ai + 1
				local a = actions[(ai % #actions) + 1]
				if t > 20 and not didSuper then
					Combat.setSuper(F, 100)
					a = "super"
					didSuper = true
				end
				if a == "block" then
					act(A, "block", { on = true })
				else
					act(A, a, { dir = (ep - pos).Unit, air = (ai % 11 == 0) })
				end
			end
			-- weapon test
			if t > 10 and not didWeapon then
				local w = Weapons.findNear(F.root.Position, 500)
				if w then
					F.model:PivotTo(CFrame.new(w.PrimaryPart.Position + Vector3.new(0, 2, 0)))
					act(A, "grab", { dir = Vector3.new(0, 0, -1) })
					didWeapon = F.weapon ~= nil
					print("weapon picked:", didWeapon, F.model:GetAttribute("Weapon"))
				end
			end
			if didWeapon and not didThrow and t > 16 and F.weapon then
				act(A, "grab", { dir = Vector3.new(0, 0, -1) })
				didThrow = true
			end
		end
	end
	-- thrown weapons: simulate touching the nearest enemy
	local wf = workspace:FindFirstChild("BrawlWeapons")
	if wf then
		for _, m in ipairs(wf:GetChildren()) do
			if m:GetAttribute("Thrown") then
				for _, G in pairs(Combat.fighters) do
					if not A or G.model ~= A.Character then
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") then
								p.Touched:Fire(G.torso)
								break
							end
						end
						break
					end
				end
			end
		end
	end
	if t > 25 and not didGlass then
		didGlass = true
		local fast = Instance.new("Part")
		fast.AssemblyLinearVelocity = Vector3.new(40, 0, 0)
		for _, d in ipairs(workspace.SoiMap:GetChildren()) do
			if d:GetAttribute("Breakable") == "glass" then d.Touched:Fire(fast) break end
		end
		for _, d in ipairs(workspace.SoiMap:GetChildren()) do
			if d.Name == "Watermelon" then d.Touched:Fire(fast) didMelon = true break end
		end
	end
	if t > 30 and not killedBot then
		for _, G in pairs(Combat.fighters) do
			if G.isBot then G.hum.Health = 0 killedBot = true break end
		end
	end
	if t > 45 and t < 45 + dt and B and B.Character then
		local F = Combat.get(B.Character)
		if F then F.model:PivotTo(CFrame.new(0, -60, 0)) end -- fall off the map
	end
	if t > 100 and t < 100 + dt and A then
		A.Parent = nil
		Players.PlayerRemoving:Fire(A)
	end
end
print("---- server smoke test ----")
local keys = {}
for k in pairs(counts) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do print(string.format("  %-28s %d", k, counts[k])) end
local n, alive, bots = 0, 0, 0
for _, G in pairs(Combat.fighters) do
	n = n + 1
	if G.alive then alive = alive + 1 end
	if G.isBot then bots = bots + 1 end
end
print("fighters registered:", n, "alive:", alive, "bots:", bots)
for _, v in ipairs(RS.BrawlState.Scores:GetChildren()) do
	print("  score", v:GetAttribute("DisplayName"), v.Value, "deaths", v:GetAttribute("Deaths"))
end
print("weapon picked/thrown:", didWeapon, didThrow, "glass/melon:", didGlass, didMelon, "super:", didSuper)
print("ERRORS:", #ERRORS)
local pw = {}
for k in pairs(PROPWRITES) do pw[#pw + 1] = k end
table.sort(pw)
WRITTEN = pw
