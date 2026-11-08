--[[ Client effects: sounds, sweat spray, blood mist and drops, canvas stains, screen flash/blur, camera trauma. ]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)

local FX = {}

-- ------------------------------------------------------------------ camera feel (read by CameraController)
FX.trauma = 0
FX.kick = Vector3.zero
FX.kickV = Vector3.zero
FX.fov = 0
FX.fovV = 0
FX.dizzy = 0
FX.dizzyHold = 0

function FX.Shake(a) FX.trauma = math.clamp(FX.trauma + a, 0, 1) end
function FX.Kick(euler: Vector3) FX.kickV += euler * 22 end
function FX.FovPunch(d) FX.fovV += d * 18 end
function FX.Dizzy(a, hold) FX.dizzy = math.max(FX.dizzy, a); FX.dizzyHold = math.max(FX.dizzyHold, hold or 1) end

local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "NeonBayHitFX"
cc.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "NeonBayBlur"
blur.Size = 0
blur.Parent = Lighting
local flash, flashColor, blurAmt, blurHold = 0, Color3.new(1, 1, 1), 0, 0

function FX.Flash(color, amount) flashColor = color; flash = math.max(flash, amount) end
function FX.Blur(amount, hold) blurAmt = math.max(blurAmt, amount); blurHold = math.max(blurHold, hold or 0.5) end

RunService.RenderStepped:Connect(function(dt)
	FX.trauma = math.max(0, FX.trauma - dt * 1.35)
	FX.kickV += (-FX.kick * 260 - FX.kickV * 22) * dt
	FX.kick += FX.kickV * dt
	FX.fovV += (-FX.fov * 200 - FX.fovV * 18) * dt
	FX.fov += FX.fovV * dt
	FX.dizzyHold -= dt
	if FX.dizzyHold <= 0 then FX.dizzy = math.max(0, FX.dizzy - dt * 0.35) end
	flash = math.max(0, flash - dt * 2.6)
	blurHold -= dt
	if blurHold <= 0 then blurAmt = math.max(0, blurAmt - dt * 0.9) end
	cc.TintColor = Color3.new(1, 1, 1):Lerp(flashColor, flash * 0.6)
	cc.Brightness = flash * 0.08
	cc.Saturation = -FX.dizzy * 0.4
	blur.Size = math.max(blurAmt, FX.dizzy * 0.5) * 14
end)

function FX.ShakeOffset(t)
	local s = FX.trauma * FX.trauma
	local n = function(a, b) return math.noise(a, b, 0.5) end
	local rot = Vector3.new(n(t * 24, 3.1), n(5.3, t * 24), n(t * 24, 7.7)) * s * 9
	local sway = Vector3.new(math.sin(t * 1.3) * 1.6, math.sin(t * 0.83) * 2.4, math.sin(t * 1.1) * 3.5) * FX.dizzy
	return rot + FX.kick + sway
end

-- ------------------------------------------------------------------ sound
local soundCache = {}
local function makeSound(name)
	local def = Config.Sounds[name]
	if not def or def.id == "" then return nil end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Volume = def.volume or 1
	s.PlaybackSpeed = def.pitch or 1
	if def.distortion then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = def.distortion
		d.Parent = s
	end
	if def.reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = 2.4
		r.WetLevel = -4
		r.Parent = s
	end
	return s
end

function FX.Play(name, at: Vector3?, volume, pitch)
	local proto = soundCache[name]
	if proto == nil then
		proto = makeSound(name) or false
		soundCache[name] = proto
	end
	if not proto then return end
	local s = proto:Clone()
	s.Volume *= volume or 1
	s.PlaybackSpeed *= (pitch or 1) * (0.94 + math.random() * 0.12)
	if at then
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = CFrame.new(at)
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 140
		s.Parent = p
		p.Parent = workspace
		s:Play()
		Debris:AddItem(p, 4)
	else
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 4)
	end
end

-- ------------------------------------------------------------------ particles
local holder = Instance.new("Part")
holder.Name = "NeonBayFX"
holder.Anchored = true
holder.CanCollide, holder.CanQuery, holder.CanTouch = false, false, false
holder.Transparency = 1
holder.Size = Vector3.new(0.2, 0.2, 0.2)
holder.Parent = workspace

local function emitter(name, color, size, life, speed, grav, light)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = holder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 0
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(life * 0.5, life)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -grav, 0)
	e.Drag = 2
	e.LightEmission = light or 0
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = a
	return a, e
end

local sweatAtt, sweatEm = emitter("Sweat", Color3.fromRGB(215, 235, 255), 0.12, 0.6, 14, 30, 0.2)
local bloodAtt, bloodEm = emitter("Blood", Color3.fromRGB(120, 8, 12), 0.18, 0.55, 10, 28, 0)
local sparkAtt, sparkEm = emitter("Spark", Color3.fromRGB(255, 240, 220), 0.25, 0.2, 6, 0, 0.6)

local function aim(att, pos: Vector3, dir: Vector3)
	local look = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, -1)
	att.CFrame = holder.CFrame:ToObjectSpace(CFrame.lookAt(pos, pos + look))
end

function FX.Sweat(pos, dir, n)
	aim(sweatAtt, pos, dir + Vector3.new(0, 0.3, 0))
	sweatEm:Emit(n or 14)
end

function FX.BloodSpray(pos, dir, n)
	aim(bloodAtt, pos, dir)
	bloodEm:Emit(n or 6)
	for _ = 1, math.max(1, math.floor((n or 6) / 3)) do
		FX.Drop(pos, dir * 6 + Vector3.new(math.random() - 0.5, 1, math.random() - 0.5) * 4)
	end
end

function FX.ImpactPuff(pos, dir)
	aim(sparkAtt, pos, -dir)
	sparkEm:Emit(4)
end

-- falling drops that leave stains on the canvas / floor
local drops = {}
local stainCount = 0
function FX.Drop(pos: Vector3, vel: Vector3)
	if #drops > 60 then return end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.08, 0.08, 0.08)
	p.Color = Color3.fromRGB(110, 6, 10)
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.2
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	table.insert(drops, { part = p, vel = vel, life = 2.5 })
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function stain(pos: Vector3, normal: Vector3)
	stainCount += 1
	local s = Instance.new("Part")
	s.Name = "BloodStain"
	s.Anchored = true
	s.CanCollide, s.CanQuery, s.CanTouch = false, false, false
	s.CastShadow = false
	local sz = 0.15 + math.random() * 0.35
	s.Size = Vector3.new(sz, 0.02, sz * (0.7 + math.random() * 0.6))
	s.Color = Color3.fromRGB(90, 4, 8)
	s.Material = Enum.Material.SmoothPlastic
	s.Reflectance = 0.15
	s.Transparency = 0.15
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = s
	s.CFrame = CFrame.new(pos + normal * 0.01) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	s.Parent = workspace
	Debris:AddItem(s, 90)
end

RunService.Heartbeat:Connect(function(dt)
	if #drops == 0 then return end
	local map = workspace:FindFirstChild("Map")
	rayParams.FilterDescendantsInstances = map and { map } or {}
	for i = #drops, 1, -1 do
		local d = drops[i]
		d.life -= dt
		d.vel += Vector3.new(0, -workspace.Gravity * 0.3 * dt, 0)
		local from = d.part.Position
		local step = d.vel * dt
		local hit = workspace:Raycast(from, step, rayParams)
		if hit or d.life <= 0 then
			if hit then stain(hit.Position, hit.Normal) end
			d.part:Destroy()
			table.remove(drops, i)
		else
			d.part.CFrame = CFrame.new(from + step)
		end
	end
end)

return FX
