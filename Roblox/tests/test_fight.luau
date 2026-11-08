local H = require("./harness")
local roblox = require("@lune/roblox")
local V3, CF = roblox.Vector3, roblox.CFrame

-- generic instances (ObjectValue etc.) as plain tables
H.env.Instance = { new = function(class) return { ClassName = class, Name = class } end }

local function mockPart(pos, size)
	local p = { Position = pos, CFrame = CF.new(pos), Size = size or V3.new(1, 1, 1), AssemblyLinearVelocity = V3.zero, children = {} }
	function p:FindFirstChild(n) return self.children[n] end
	return p
end

local function mockModel(name, pos)
	local attrs = {}
	local m = { Name = name, Parent = true, children = {} }
	local hrp = mockPart(pos + V3.new(0, 3.136, 0), V3.new(1.6, 2, 1.3))
	hrp.children.Facing = { CFrame = CF.identity, Enabled = false }
	local hum = { HipHeight = 2.136, WalkSpeed = 10, JumpPower = 38, AutoRotate = true, dir = V3.zero }
	function hum:Move(d) self.dir = d end
	function hum:MoveTo(p) self.dir = (p - hrp.Position).Unit end
	function hum:ChangeState() end
	m.hrp, m.hum = hrp, hum
	function m:GetAttribute(k) return attrs[k] end
	function m:SetAttribute(k, v) attrs[k] = v end
	function m:FindFirstChild(n)
		if n == "HumanoidRootPart" then return hrp end
		return self.children[n]
	end
	function m:FindFirstChildOfClass(c) if c == "Humanoid" then return hum end end
	function m:GetPivot() return hrp.CFrame end
	function m:PivotTo(cf) hrp.CFrame = cf; hrp.Position = cf.Position end
	function m:GetChildren() return {} end
	function m:GetDescendants() return {} end
	function m:Destroy() self.Parent = nil end
	m.attrs = attrs
	return m
end

local function mockRing()
	local center = V3.new(0, 0, 0)
	local r = { children = {}, attrs = {} }
	r.children.Canvas = mockPart(center + V3.new(0, 3.0, 0), V3.new(25.6, 0.2, 25.6))
	r.children.RedCorner = mockPart(center + V3.new(-8.4, 3.1, -8.4))
	r.children.BlueCorner = mockPart(center + V3.new(8.4, 3.1, 8.4))
	r.children.Neutral1 = mockPart(center + V3.new(9.2, 3.1, -9.2))
	r.children.Neutral2 = mockPart(center + V3.new(-9.2, 3.1, 9.2))
	function r:FindFirstChild(n) return self.children[n] end
	function r:GetAttribute(k) return self.attrs[k] end
	function r:SetAttribute(k, v) self.attrs[k] = v end
	return r
end

local Config = H.load("src/shared/Config.luau")
local Match = H.load("src/server/Match.luau")

local function run(redIdx, blueIdx, playerRed, seed)
	math.randomseed(seed)
	local ring = mockRing()
	local function entry(i, isPlayer)
		local f = Config.Roster[i]
		local e = { model = mockModel(f.name, V3.zero), name = f.name, nick = f.nick, record = "x", stats = f.stats, style = f.style, southpaw = f.southpaw, rosterIndex = i }
		if isPlayer then e.player = { Name = "Tester" } end
		return e
	end
	local red, blue = entry(redIdx, playerRed), entry(blueIdx, false)
	local ended, result = false, nil
	local m = Match.new(ring, red, blue, {
		rounds = 3, difficulty = 0.7,
		onEnd = function(_, res) result = res end,
		onClose = function() ended = true end,
	})
	local dt = 1 / 30
	local t = 0
	local botT = 0
	while not ended and t < 900 do
		H.advance(dt); t += dt
		H.runDeferred()
		-- scripted "player": jabs, crosses, hooks, guards, slips, gets up, picks corner options
		if playerRed then
			botT -= dt
			local f = m.Red
			if botT <= 0 then
				botT = 0.25 + math.random() * 0.4
				local r = math.random()
				if r < 0.45 then m:Input(red.player, { k = "punch", id = math.random(1, 6), body = math.random() < 0.25, power = math.random() < 0.2 })
				elseif r < 0.6 then m:Input(red.player, { k = "guard", g = math.random(0, 2) })
				elseif r < 0.75 then m:Input(red.player, { k = "lean", x = math.random() * 2 - 1, y = -math.random(), z = 0 })
				elseif r < 0.8 then m:Input(red.player, { k = "clinch" })
				else m:Input(red.player, { k = "lean", x = 0, y = 0, z = 0 }) end
			end
			if m.phase == "Knockdown" and m.downed == f then m:Input(red.player, { k = "getup", hit = math.random() < 0.7 }); f.lastGetUpPress = -1 end
			if m.phase == "Corner" then m:Input(red.player, { k = "corner", i = math.random(1, 4) }) end
			-- player movement: walk toward the opponent a bit
			local toOpp = (m.Blue.hrp.Position - f.hrp.Position)
			f.hum.dir = V3.new(toOpp.X, 0, toOpp.Z).Unit * (toOpp.Magnitude > 4 and 1 or 0.2)
			f.hrp.children.Facing.CFrame = CF.lookAt(V3.zero, V3.new(toOpp.X, 0, toOpp.Z).Unit)
		end
		local alive = m:Tick(dt)
		-- integrate movement + facing like Roblox physics would
		for _, f in { m.Red, m.Blue } do
			local hrp, hum = f.hrp, f.hum
			local d = hum.dir
			local pos = hrp.Position
			if d.Magnitude > 0.01 and hum.WalkSpeed > 0 then pos += V3.new(d.X, 0, d.Z).Unit * hum.WalkSpeed * dt * math.min(1, d.Magnitude) end
			local lim = 12 - 0.8
			pos = V3.new(math.clamp(pos.X, -lim, lim), pos.Y, math.clamp(pos.Z, -lim, lim))
			local rot = hrp.children.Facing.CFrame
			hrp.CFrame = CF.new(pos) * (rot - rot.Position)
			hrp.Position = pos
		end
		local a, b = m.Red.hrp.Position, m.Blue.hrp.Position
		local sep = V3.new(b.X - a.X, 0, b.Z - a.Z)
		if sep.Magnitude < 1.7 and sep.Magnitude > 0 then
			local push = sep.Unit * (1.7 - sep.Magnitude) * 0.5
			m.Red.hrp.Position -= push; m.Blue.hrp.Position += push
			m.Red.hrp.CFrame = CF.new(m.Red.hrp.Position) * (m.Red.hrp.CFrame - m.Red.hrp.CFrame.Position)
			m.Blue.hrp.CFrame = CF.new(m.Blue.hrp.Position) * (m.Blue.hrp.CFrame - m.Blue.hrp.CFrame.Position)
		end
		if alive == false then break end
	end
	local s1, s2 = m.Red.total, m.Blue.total
	return string.format("%-16s vs %-16s | %-22s %-36s | rounds %d | R %3d/%3d (%2dkd)  B %3d/%3d (%2dkd) | %.0fs",
		Config.Roster[redIdx].name .. (playerRed and "*" or ""), Config.Roster[blueIdx].name, result and result.title or "NO RESULT", result and result.method or "", m.round,
		s1.landed, s1.thrown, s1.knockdowns, s2.landed, s2.thrown, s2.knockdowns, t)
end

local pairs_ = { { 1, 2, false }, { 3, 4, false }, { 5, 6, false }, { 7, 8, false }, { 2, 8, false }, { 1, 1, true }, { 4, 6, true }, { 8, 3, true } }
local okAll = true
for i, p in pairs_ do
	local ok, res = pcall(run, p[1], p[2], p[3], i * 17)
	if not ok then okAll = false end
	print(ok and res or ("ERROR: " .. tostring(res)))
end
local impacts, clean = 0, 0
for _, f in H.fired do if f.name == "Impact" then impacts += 1; if f.ev.res == "clean" then clean += 1 end end end
print("impact events:", impacts, "clean:", clean, okAll and "ALL MATCHES COMPLETED" or "SOME MATCHES FAILED")
