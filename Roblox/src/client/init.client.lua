-- ============================================================
--  ซอยเดือด : SOI BRAWL  -  สคริปต์หลักฝั่ง Client
--  (StarterPlayer > StarterPlayerScripts > BrawlClient + ModuleScript ลูก 4 ตัว)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BrawlConfig"))
local Anim = require(ReplicatedStorage:WaitForChild("BrawlAnim"))
local remotes = {}
local rf = ReplicatedStorage:WaitForChild("BrawlRemotes")
for _, n in ipairs({ "Action", "Fx", "Knock", "Ragdoll", "Notify" }) do
	remotes[n] = rf:WaitForChild(n)
end

local Animator = require(script:WaitForChild("Animator"))
local Effects = require(script:WaitForChild("Effects"))
local Hud = require(script:WaitForChild("Hud"))
local Controls = require(script:WaitForChild("Controls"))

Animator.init(Anim)
Effects.init(Config, remotes, Animator)
Hud.init(Config, remotes, Effects)
Effects.setHud(Hud)
Controls.init(Config, remotes, Animator)

-- โดนผลัก (ตัวเราเป็นเจ้าของฟิสิกส์ของตัวเอง เลยต้องผลักฝั่งนี้)
remotes.Knock.OnClientEvent:Connect(function(vel, dur)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or typeof(vel) ~= "Vector3" then
		return
	end
	local att = root:FindFirstChild("PushAtt")
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
	lv.Parent = root
	Debris:AddItem(lv, math.clamp(tonumber(dur) or 0.15, 0.05, 0.5))
end)

-- ล้ม/ลุก (ให้ Humanoid ฝั่งเราเปลี่ยนสถานะตาม)
remotes.Ragdoll.OnClientEvent:Connect(function(on)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if on then
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	else
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			Effects.sound("getup", root.Position, 1)
		end
	end
end)

print("[ซอยเดือด] client พร้อม 👊")
