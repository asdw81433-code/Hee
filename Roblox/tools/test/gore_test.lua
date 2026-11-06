local RS = game:GetService("ReplicatedStorage")
mountModule(RS, "BrawlConfig", "shared/BrawlConfig.lua")
mountModule(RS, "BrawlAnim", "shared/BrawlAnim.lua")
local Config = require(RS.BrawlConfig)
Config.DecapChance = 1
Config.BotCount = 3
local SSS = game:GetService("ServerScriptService")
local main = mountModule(SSS, "BrawlServer", "server/init.server.lua", "Script")
for _, n in ipairs({ "MapBuilder", "CharacterBuilder", "Ragdoll", "Combat", "Weapons", "Bots" }) do
	mountModule(main, n, "server/" .. n .. ".lua")
end
task.spawn(loadScript(main))
local Combat = require(main.Combat)
local Ragdoll = require(main.Ragdoll)
local function run(sec) for _ = 1, math.floor(sec * 30) do simStep(1 / 30) end end
run(3)
local bots = {}
for _, G in pairs(Combat.fighters) do if G.isBot then bots[#bots + 1] = G end end
assert(#bots >= 2, "need bots")
local A, B = bots[1], bots[2]
print("A parts:", #A.model:GetChildren())
-- sever both legs and an arm on a living bot
assert(Combat.sever(A.model, "RightLowerLeg", Vector3.new(0, 10, 0), A), "sever knee")
assert(Combat.sever(A.model, "LeftUpperLeg", Vector3.new(0, 10, 0), A), "sever hip")
assert(not Combat.sever(A.model, "LeftLowerLeg", Vector3.new(0, 10, 0), A), "lower leg already gone with hip")
assert(Combat.sever(A.model, "RightUpperArm", Vector3.new(0, 10, 0), A), "sever shoulder")
print("A speedMul", A.speedMul, "dmgMul", A.dmgMul, "HipHeight", A.hum.HipHeight, "gibs", #workspace.BrawlGibs:GetChildren())
assert(A.speedMul < 0.3 and A.hum.HipHeight < 1, "crawl")
assert(A.model:FindFirstChild("RightUpperArm") == nil and workspace.BrawlGibs:FindFirstChild("RightLowerArm"), "arm in gibs")
local stumps = 0
for _, d in ipairs(A.model:GetDescendants()) do if d.Name == "GoreStump" then stumps = stumps + 1 end end
print("stumps on body:", stumps)
-- ragdoll + recover with missing limbs, keep fighting
Combat.ragdoll(A, Vector3.new(5, 20, 0), Vector3.new(1, 2, 3), 1)
run(2)
print("A ragdolled after 2s:", Ragdoll.isRagdolled(A.model), "alive", A.alive)
Ragdoll.recover(A.model)
print("A ragdolled after direct recover:", Ragdoll.isRagdolled(A.model), "root y", A.root.Position.Y, "motors enabled:", A.model.UpperTorso.Waist.Enabled, A.model.LowerTorso.Root.Enabled)
assert(not Ragdoll.isRagdolled(A.model), "recover failed")
run(5)
-- decapitation on killing blow
B.hum.Health = 5
Combat.hit(A, B, Config.Moves.super, Vector3.new(0, 0, -1))
run(0.5)
print("B alive", B.alive, "head in body", B.model:FindFirstChild("Head") ~= nil)
-- hand + waist cut on a corpse
local D = bots[3]
if D then
	assert(Combat.sever(D.model, "LeftHand", Vector3.new(0, 5, 0), D), "hand")
	print("D dmgMul after hand:", D.dmgMul)
	D.hum.Health = 0
	run(0.2)
	assert(Combat.sever(D.model, "UpperTorso", Vector3.new(0, 5, 0), nil), "waist cut")
	print("waist cut: torso in gibs", workspace.BrawlGibs:FindFirstChild("UpperTorso") ~= nil, "head moved too", D.model:FindFirstChild("Head") == nil)
end
-- stomp the corpse until something falls off
local before = #workspace.BrawlGibs:GetChildren()
local C = A
for i = 1, 12 do
	if C.alive and not Ragdoll.isRagdolled(C.model) then
		local torso = B.model:FindFirstChild("UpperTorso")
		if torso then
			C.model:PivotTo(CFrame.lookAt(torso.Position + Vector3.new(0, 1, 2), torso.Position + Vector3.new(0, 1, 0)))
			Combat.request(C, "kick", { dir = Vector3.new(0, 0, -1) })
		end
	end
	run(0.6)
end
print("gibs before/after corpse stomps:", before, #workspace.BrawlGibs:GetChildren())
run(30)
print("gibs after GibLife:", #workspace.BrawlGibs:GetChildren())
print("ERRORS:", #ERRORS)
