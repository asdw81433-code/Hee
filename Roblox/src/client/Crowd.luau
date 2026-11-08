--[[
	Client-side crowd around each ring: low-detail spectators that bounce, raise fists, clap and jump up on
	big shots and knockdowns. Purely local, moved with BulkMoveTo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)

local Crowd = {}
local crowds = {}

local function ell(parent, size, color, mat)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CastShadow = false
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	p.Parent = parent
	return p
end

local function build(ring)
	local canvas = ring:FindFirstChild("Canvas")
	if not canvas then return end
	local center = canvas.Position
	local floorY = canvas.Position.Y - canvas.Size.Y / 2
	local folder = Instance.new("Folder")
	folder.Name = "Crowd"
	folder.Parent = workspace
	local rng = Random.new(ring:GetAttribute("RingOrder") or 1)
	local fans = {}
	local parts, cfs = {}, {}
	local count = ring:GetAttribute("CrowdSize") or 28
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Map") }
	local tries = 0
	while #fans < count and tries < count * 6 do
		tries += 1
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(Config.Ring.ropeHalf + 6, Config.Ring.ropeHalf + 15)
		local p = center + Vector3.new(math.cos(ang) * dist, 6, math.sin(ang) * dist)
		local hit = workspace:Raycast(p, Vector3.new(0, -14, 0), params)
		if hit and hit.Position.Y < floorY + 4 and hit.Instance.Name ~= "Canvas" then
			local ok = true
			for _, f in fans do if (f.base - hit.Position).Magnitude < 2.6 then ok = false break end end
			if ok then
				local skin = Config.SkinTones[rng:NextInteger(1, 7)]
				local shirt = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.2, 0.8), rng:NextNumber(0.15, 0.8))
				local f = {
					base = hit.Position, yaw = math.atan2(-(center.X - hit.Position.X), -(center.Z - hit.Position.Z)),
					phase = rng:NextNumber(0, 10), mood = rng:NextInteger(1, 3), excite = 0, jump = 0, scale = rng:NextNumber(0.9, 1.1),
					legs = ell(folder, Vector3.new(1.1, 2.9, 0.75), Color3.fromRGB(25, 25, 32), Enum.Material.Fabric),
					body = ell(folder, Vector3.new(1.45, 2.2, 0.95), shirt, Enum.Material.Fabric),
					head = ell(folder, Vector3.new(0.75, 0.9, 0.82), skin),
					hair = ell(folder, Vector3.new(0.8, 0.5, 0.86), Config.HairColors[rng:NextInteger(1, 6)], Enum.Material.Fabric),
					armL = ell(folder, Vector3.new(0.38, 1.7, 0.38), shirt, Enum.Material.Fabric),
					armR = ell(folder, Vector3.new(0.38, 1.7, 0.38), shirt, Enum.Material.Fabric),
				}
				if rng:NextNumber() < 0.25 then
					f.glow = ell(folder, Vector3.new(0.3, 0.3, 0.3), Config.Neon.Magenta:Lerp(Config.Neon.Cyan, rng:NextNumber()), Enum.Material.Neon)
				end
				for _, k in { "legs", "body", "head", "hair", "armL", "armR", "glow" } do
					if f[k] then table.insert(parts, f[k]) end
				end
				table.insert(fans, f)
			end
		end
	end
	crowds[ring] = { fans = fans, parts = parts, cfs = cfs, center = center, hype = 0.15 }
end

function Crowd.Excite(ring, amount)
	local c = ring and crowds[ring]
	if not c then return end
	c.hype = math.clamp(c.hype + amount * 0.5, 0, 1)
	for _, f in c.fans do
		f.excite = math.max(f.excite, amount * (0.6 + math.random() * 0.6))
		if amount > 0.5 and math.random() < 0.6 then f.jump = 0.4 + math.random() * 0.5 end
	end
end

function Crowd.Start()
	local map = workspace:WaitForChild("Map", 30)
	if not map then return end
	task.wait(1)
	for _, d in map:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("IsRing") then build(d) end
	end
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		local t = os.clock()
		for ring, c in crowds do
			if (cam.CFrame.Position - c.center).Magnitude < 180 then
				local busy = ring:GetAttribute("Busy")
				c.hype = math.max(busy and 0.3 or 0.08, c.hype - dt * 0.05)
				local i = 0
				for _, f in c.fans do
					f.excite = math.max(c.hype * 0.5, f.excite - dt * 0.4)
					f.jump = math.max(0, f.jump - dt * 0.5)
					local ex = f.excite
					local bounce = math.abs(math.sin(t * 7 + f.phase)) * 0.5 * f.jump + math.abs(math.sin(t * 3 + f.phase)) * 0.12 * ex
					local root = CFrame.new(f.base) * CFrame.Angles(0, f.yaw, 0) * CFrame.new(0, bounce, 0)
					local s = f.scale
					local arms = math.clamp((ex - 0.3) * 2 + f.jump, 0, 1)
					local pump = math.sin(t * 8 + f.phase) * 0.35
					local raiseL, raiseR
					if f.mood == 1 then raiseL, raiseR = arms * (2.6 + pump), arms * (2.6 - pump)
					elseif f.mood == 2 then raiseL, raiseR = 0.15, arms * (2.4 + pump * 1.5)
					else
						local clap = math.abs(math.sin(t * 9 + f.phase))
						raiseL, raiseR = arms * (1.2 + clap * 0.2), arms * (1.2 + clap * 0.2)
					end
					local function put(part, cf)
						i += 1
						c.cfs[i] = cf
						local _ = part
					end
					put(f.legs, root * CFrame.new(0, 1.45 * s, 0))
					put(f.body, root * CFrame.new(0, 3.6 * s, 0) * CFrame.Angles(-0.1 * ex, 0, 0))
					put(f.head, root * CFrame.new(0, 5.05 * s, -0.05) * CFrame.Angles(0.15 * ex, math.sin(t * 0.7 + f.phase) * 0.3, 0))
					put(f.hair, root * CFrame.new(0, 5.3 * s, 0.05))
					put(f.armL, root * CFrame.new(-0.85 * s, 4.3 * s, 0) * CFrame.Angles(raiseL, 0, -0.15) * CFrame.new(0, -0.75, 0))
					put(f.armR, root * CFrame.new(0.85 * s, 4.3 * s, 0) * CFrame.Angles(raiseR, 0, 0.15) * CFrame.new(0, -0.75, 0))
					if f.glow then put(f.glow, root * CFrame.new(0.85 * s, 4.3 * s, 0) * CFrame.Angles(raiseR, 0, 0.15) * CFrame.new(0, -1.6, 0)) end
				end
				workspace:BulkMoveTo(c.parts, c.cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end)
end

return Crowd
