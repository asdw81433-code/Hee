--[[ NEON BAY: THE PIT - client entry. Wires server events into animation, effects, camera and UI. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local Remotes = ReplicatedStorage:WaitForChild("NeonBayRemotes")

local Animator = require(script.Parent.Animator)
local FX = require(script.Parent.FX)
local CameraController = require(script.Parent.CameraController)
local Controls = require(script.Parent.Controls)
local HUD = require(script.Parent.HUD)
local Menus = require(script.Parent.Menus)
local Ropes = require(script.Parent.Ropes)
local Crowd = require(script.Parent.Crowd)

local player = Players.LocalPlayer

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

Animator.Start()
CameraController.Start()
Controls.Start()
HUD.Start(Controls)
Menus.Start(Controls)
task.spawn(Ropes.Start)
task.spawn(Crowd.Start)

local function myModel() return player.Character end

local function ringOf(model)
	local r = model and model:FindFirstChild("Ring")
	return r and r.Value
end

-- ------------------------------------------------------------------ impacts
Remotes:WaitForChild("Impact").OnClientEvent:Connect(function(ev)
	if ev.type == "bag" then
		FX.Play("bag", ev.pos, ev.power and 1 or 0.7)
		return
	end
	local att, def = ev.att, ev.def
	if not att or not def then return end
	local me = myModel()
	local pos, dir = ev.pos, ev.dir
	local res = ev.res
	if res == "miss" then
		FX.Play("whiff", pos, 0.6)
		return
	end
	if res == "slip" then
		FX.Play("whiff", pos, 0.9, 0.85)
		HUD.Popup(((def:GetAttribute("LeanY") or 0) < -0.4) and "DUCKED" or "SLIPPED", Color3.fromRGB(150, 230, 255), pos + Vector3.new(0, 1, 0), 0.7)
		if def == me then FX.Kick(Vector3.new(0, (def:GetAttribute("LeanX") or 0) * 2, -(def:GetAttribute("LeanX") or 0) * 3)) end
		return
	end
	if res == "parry" then
		FX.Play("glove_block", pos, 1, 1.25)
		HUD.Popup("PARRY!", Config.Neon.Cyan, pos + Vector3.new(0, 1, 0), 1)
		Animator.React(att, -dir, 0.5, false, false)
		return
	end
	local pk = ev.pk or 0.5
	if res == "block" then
		FX.Play("glove_block", pos, 0.8)
		FX.ImpactPuff(pos, dir)
		Animator.React(def, dir, pk * 0.3, not ev.body, ev.body)
		if def == me then FX.Shake(0.06 + pk * 0.05); FX.Kick(Vector3.new(-1, 0, 0) * (1 + pk)) end
		return
	end
	-- clean
	Animator.React(def, dir, pk, not ev.body, ev.body)
	FX.Play(ev.body and "glove_body" or (pk > 0.9 and "glove_heavy" or "glove_head"), pos, 0.6 + 0.4 * math.min(pk, 1))
	if not ev.body then FX.Play("glove_snap", pos, 0.6) end
	if not ev.body then
		FX.Sweat(pos + Vector3.new(0, 0.4, 0), dir, math.floor(10 + pk * 26))
		local bleeding = (def:GetAttribute("I_Bleed") or 0) > 0.2 or pk > 1
		if bleeding then FX.BloodSpray(pos, dir, math.floor(2 + pk * 5)) end
	end
	local ring = ringOf(def)
	if pk > 0.75 or ev.counter then Crowd.Excite(ring, ev.counter and 0.45 or 0.3) end
	if ev.counter then HUD.Popup("COUNTER!", Config.Neon.Yellow, pos + Vector3.new(0, 1.2, 0), 1.1)
	elseif ev.power and pk > 0.8 then HUD.Popup("POWER SHOT", Config.Neon.Orange, pos + Vector3.new(0, 1.2, 0), 0.95)
	elseif ev.body and pk > 0.6 then HUD.Popup("BODY!", Color3.fromRGB(255, 153, 77), pos + Vector3.new(0, 0.6, 0), 0.8) end
	if ev.rocked and pk > 0.6 then HUD.Popup("ROCKED!", Config.Neon.Red, pos + Vector3.new(0, 1.8, 0), 1.2) end
	if att == me then
		FX.Shake(0.05 + pk * 0.1)
		FX.FovPunch(-pk * 1.2)
	end
	if def == me then
		FX.Shake(0.22 + pk * 0.28)
		local cam = workspace.CurrentCamera
		local l = cam.CFrame:VectorToObjectSpace(dir)
		FX.Kick(Vector3.new(-l.Y - math.abs(l.Z) * 0.6, -l.X, -l.X * 0.8) * (3 + pk * 5))
		FX.Flash(Color3.fromRGB(200, 20, 20), 0.2 + pk * 0.25)
		if ev.rocked then FX.Dizzy(0.6, 2.5); FX.Blur(0.4, 1) end
	end
end)

-- ------------------------------------------------------------------ match flow
Remotes:WaitForChild("MatchEvent").OnClientEvent:Connect(function(ev)
	local ring = ev.ring
	local me = myModel()
	local mine = me and ringOf(me) == ring and me:GetAttribute("Fighter")
	local near = false
	if ring and me and me:FindFirstChild("HumanoidRootPart") and ring:FindFirstChild("Canvas") then
		near = (ring.Canvas.Position - me.HumanoidRootPart.Position).Magnitude < 80
	end
	if not mine and not near then return end
	local t = ev.type
	if t == "intro" then
		Crowd.Excite(ring, 0.6)
	elseif t == "round" then
		HUD.Banner("ROUND " .. ev.n, ev.final and "FINAL ROUND" or ((ring:GetAttribute("RedName") or "") .. "  vs  " .. (ring:GetAttribute("BlueName") or "")), Config.Neon.Red)
	elseif t == "bell" then
		for i = 1, ev.count or 1 do task.delay((i - 1) * 0.32, function() FX.Play("bell", ring.Canvas.Position + Vector3.new(0, 6, 0), 1) end) end
	elseif t == "knockdown" then
		FX.Play("canvas", ring.Canvas.Position, 1)
		if ev.ko then FX.Play("ko", ring.Canvas.Position, 1) end
		Crowd.Excite(ring, 1)
		HUD.Banner(ev.ko and "KNOCKOUT!" or "KNOCKDOWN!", "", Config.Neon.Red, 2)
		FX.Shake(0.5)
		if ev.victim == me then FX.Flash(Color3.new(1, 1, 1), 0.8); FX.Dizzy(1, 3); FX.Blur(1, 2) end
	elseif t == "count" then
		FX.Play("count", nil, 0.8, 1 + ev.n * 0.02)
	elseif t == "getup" then
		Crowd.Excite(ring, 0.5)
	elseif t == "popup" then
		HUD.Popup(ev.text, ev.color, ev.at, 0.9)
	elseif t == "corner" and mine then
		HUD.Corner(ev)
	elseif t == "result" then
		Crowd.Excite(ring, 1)
		if mine then HUD.Result(ev) else HUD.Banner(ev.title, ev.method, Config.Neon.Yellow, 4) end
	end
end)

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(ev)
	HUD.Notify(ev.text, ev.color)
end)

print("[NeonBay] THE PIT client ready")
