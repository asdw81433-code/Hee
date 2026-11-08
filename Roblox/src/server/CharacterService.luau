--[[
	Builds fighter rigs from scratch (HumanoidRootPart + 18 bone parts joined by Motor6D) and dresses them
	with Appearance. Building our own rig keeps the game independent of avatar assets and guarantees every
	joint is a Motor6D the client animator can drive.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local RigDef = require(Shared.RigDef)
local Appearance = require(Shared.Appearance)

local CharacterService = {}

local function bonePart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.15, 0.15, 0.15)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

--[[ Returns model, bones. role: "Player", "CPU", "Referee", "Dummy". ]]
function CharacterService.BuildRig(profile, name, role, at: CFrame?)
	local model = Instance.new("Model")
	model.Name = name
	local offsets, d = RigDef.Offsets(profile)
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = RigDef.RootSize
	hrp.Transparency = 1
	hrp.CanCollide = true
	hrp.CanQuery = false
	hrp.CastShadow = false
	local base = at or CFrame.new(0, 20, 0)
	hrp.CFrame = base * CFrame.new(0, RigDef.HipHeightM * d.scale, 0)
	hrp.Parent = model
	model.PrimaryPart = hrp
	local bones = { HumanoidRootPart = hrp }
	for _, def in RigDef.Bones do
		local parent = bones[def.parent]
		local part = bonePart(def.name)
		local off = offsets[def.name]
		part.CFrame = parent.CFrame * CFrame.new(off)
		local m = Instance.new("Motor6D")
		m.Name = def.motor
		m.Part0 = parent
		m.Part1 = part
		m.C0 = CFrame.new(off)
		m.C1 = CFrame.identity
		m.Parent = part
		part.Parent = model
		bones[def.name] = part
	end
	-- colliders: used for ragdolls (they only collide while ragdolled)
	for boneName, col in RigDef.Colliders do
		local bone = bones[boneName]
		if bone then
			local c = Instance.new("Part")
			c.Name = "Col_" .. boneName
			c.Size = col.s * d.scale
			c.Transparency = 1
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.Massless = true
			c.CastShadow = false
			c.CollisionGroup = "Ragdoll"
			local w = Instance.new("Weld")
			w.Part0 = bone
			w.Part1 = c
			w.C0 = CFrame.new(col.c * d.scale)
			w.Parent = c
			c.CFrame = bone.CFrame * w.C0
			c.Parent = model
		end
	end
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.AutomaticScalingEnabled = false
	hum.HipHeight = RigDef.HipHeight(profile)
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = Config.Movement.lobbyWalkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = 38
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 40
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.DisplayName = profile.nickname ~= "" and profile.nickname or name
	hum.Parent = model
	-- facing control used in the ring
	local att = Instance.new("Attachment")
	att.Name = "FaceAtt"
	att.Parent = hrp
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Facing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 80
	ao.MaxTorque = 1e8
	ao.Enabled = false
	ao.Parent = hrp
	Appearance.Apply(model, bones, profile)
	model:SetAttribute("Role", role)
	model:SetAttribute("Southpaw", profile.southpaw == true)
	model:SetAttribute("Scale", d.scale)
	model:SetAttribute("State", "Idle")
	CollectionService:AddTag(model, "NBRig")
	return model, bones
end

function CharacterService.Bones(model)
	local bones = { HumanoidRootPart = model:FindFirstChild("HumanoidRootPart") }
	for _, def in RigDef.Bones do
		bones[def.name] = model:FindFirstChild(def.name)
	end
	return bones
end

--[[ Re-dress an existing rig (profile edits from the creator). Bone proportions are rebuilt by respawning. ]]
function CharacterService.Redress(model, profile)
	Appearance.Apply(model, CharacterService.Bones(model), profile)
	model:SetAttribute("Southpaw", profile.southpaw == true)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayName = profile.nickname ~= "" and profile.nickname or model.Name end
end

function CharacterService.SpawnPlayer(player: Player, profile, at: CFrame)
	local old = player.Character
	local model = CharacterService.BuildRig(profile, player.Name, "Player", at)
	model.Parent = workspace
	player.Character = model
	if old and old ~= model then old:Destroy() end
	return model
end

function CharacterService.SpawnPoint()
	local map = workspace:FindFirstChild("Map")
	local spawn = map and map:FindFirstChild("LobbySpawn", true)
	if spawn and spawn:IsA("BasePart") then
		local offset = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
		return CFrame.new(spawn.Position + offset + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(spawn.Orientation.Y), 0)
	end
	return CFrame.new(0, 3, 0)
end

-- keep Players from auto-loading default avatars
Players.CharacterAutoLoads = false

return CharacterService
