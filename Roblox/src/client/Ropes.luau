--[[
	Ring ropes simulated with verlet integration on each client. Four ropes per side; fighters, the referee,
	lobby players and knocked-out bodies push them, they stretch, wobble and settle. Rendered as chains of
	cylinder parts moved with BulkMoveTo (only while the camera is near).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local Animator = require(script.Parent.Animator)

local Ropes = {}
local POINTS = 14
local rings = {}

local COLORS = {
	{ Config.Neon.Cyan, Enum.Material.Neon },
	{ Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic },
	{ Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic },
	{ Config.Neon.Red, Enum.Material.Neon },
}

local function build(ring)
	local canvas = ring:FindFirstChild("Canvas")
	if not canvas then return end
	local center = canvas.Position + Vector3.new(0, canvas.Size.Y / 2, 0)
	local half = ring:GetAttribute("RopeHalf") or Config.Ring.ropeHalf
	local folder = Instance.new("Folder")
	folder.Name = "SimRopes"
	folder.Parent = workspace
	local corners = { Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(half, 0, half), Vector3.new(-half, 0, half) }
	local outs = { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }
	local data = { ring = ring, center = center, half = half, ropes = {}, parts = {}, cfs = {} }
	for s = 1, 4 do
		for lv, h in Config.Ring.ropeHeights do
			local rope = { outward = outs[s], p = {}, prev = {}, rest = {}, segs = {} }
			local a = center + corners[s] + Vector3.new(0, h, 0)
			local b = center + corners[s % 4 + 1] + Vector3.new(0, h, 0)
			for i = 1, POINTS do
				local t = (i - 1) / (POINTS - 1)
				local pt = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * 0.08, 0)
				rope.p[i], rope.prev[i], rope.rest[i] = pt, pt, pt
			end
			rope.segLen = (b - a).Magnitude / (POINTS - 1)
			for i = 1, POINTS - 1 do
				local part = Instance.new("Part")
				part.Name = "Rope"
				part.Shape = Enum.PartType.Cylinder
				part.Anchored = true
				part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
				part.Size = Vector3.new(rope.segLen + 0.06, lv == 4 and 0.24 or 0.2, lv == 4 and 0.24 or 0.2)
				part.Color = COLORS[lv][1]
				part.Material = COLORS[lv][2]
				part.Parent = folder
				table.insert(rope.segs, part)
				table.insert(data.parts, part)
			end
			table.insert(data.ropes, rope)
		end
	end
	data.folder = folder
	rings[ring] = data
end

local function pushers(data)
	local list = {}
	local c, half = data.center, data.half + 3
	for model, _ in Animator.Rigs do
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp and model.Name ~= "CreatorPreview" then
			local l = hrp.Position - c
			if math.abs(l.X) < half and math.abs(l.Z) < half then
				if model:GetAttribute("Ragdolled") then
					for _, n in { "UpperTorso", "LowerTorso", "Head" } do
						local p = model:FindFirstChild(n)
						if p then table.insert(list, { pos = p.Position, r = n == "Head" and 0.5 or 0.8, y0 = p.Position.Y - 1.2, y1 = p.Position.Y + 1.2 }) end
					end
				else
					local ut = model:FindFirstChild("UpperTorso")
					local center = ut and ut.Position or hrp.Position
					table.insert(list, { pos = center, r = 0.95, y0 = hrp.Position.Y - 3, y1 = hrp.Position.Y + 2.6 })
				end
			end
		end
	end
	return list
end

local function simulate(data, dt)
	local ps = pushers(data)
	for _, rope in data.ropes do
		local p, prev, rest = rope.p, rope.prev, rope.rest
		local g = Vector3.new(0, -9.8 * dt * dt * 0.6, 0)
		for i = 2, POINTS - 1 do
			local v = (p[i] - prev[i]) * 0.965
			prev[i] = p[i]
			p[i] = p[i] + v + g + (rest[i] - p[i]) * 0.06
		end
		for _ = 1, 3 do
			for i = 1, POINTS - 1 do
				local d = p[i + 1] - p[i]
				local len = d.Magnitude
				if len > 1e-4 then
					local corr = d * ((len - rope.segLen) / len) * 0.5
					if i > 1 then p[i] += corr end
					if i + 1 < POINTS then p[i + 1] -= corr end
				end
			end
			for _, pu in ps do
				for i = 2, POINTS - 1 do
					local pt = p[i]
					if pt.Y > pu.y0 and pt.Y < pu.y1 then
						local dx = Vector3.new(pt.X - pu.pos.X, 0, pt.Z - pu.pos.Z)
						local dist = dx.Magnitude
						if dist < pu.r and dist > 1e-3 then
							local dir = dx / dist
							if dir:Dot(rope.outward) < 0 then dir = rope.outward end
							local np = Vector3.new(pu.pos.X, pt.Y, pu.pos.Z) + dir * pu.r
							local moved = (np - pt).Magnitude
							p[i] = np - Vector3.new(0, moved * 0.25, 0)
						end
					end
				end
			end
		end
	end
end

local function render(data)
	local i = 0
	for _, rope in data.ropes do
		for s, _ in rope.segs do
			local a, b = rope.p[s], rope.p[s + 1]
			i += 1
			local mid = (a + b) / 2
			local dir = b - a
			if dir.Magnitude < 1e-4 then dir = Vector3.xAxis end
			-- cylinder axis is X
			data.cfs[i] = CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, math.rad(90), 0)
		end
	end
	workspace:BulkMoveTo(data.parts, data.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function Ropes.Start()
	local map = workspace:WaitForChild("Map", 30)
	if not map then return end
	for _, d in map:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("IsRing") then build(d) end
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		local cam = workspace.CurrentCamera
		for _, data in rings do
			local near = (cam.CFrame.Position - data.center).Magnitude < 160
			if near then
				-- fixed 60 Hz steps for stable verlet
				local steps = 0
				local t = acc
				while t >= 1 / 60 and steps < 3 do
					simulate(data, 1 / 60)
					t -= 1 / 60
					steps += 1
				end
				render(data)
			end
		end
		while acc >= 1 / 60 do acc -= 1 / 60 end
	end)
end

local _ = Players
return Ropes
