-- ============================================================
--  ซอยเดือด : เอฟเฟกต์ฝั่ง client
--  เลือดเป็นหยดจริง (ตก กระเซ็น ติดพื้น/กำแพง), ฟันกระเด็น, คำการ์ตูน, กล้องสั่น, เสียง
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Effects = {}
local Config, Animator, Hud
local localPlayer = Players.LocalPlayer
local fxFolder
local rng = Random.new()

local drops = {}
local dropPool = {}
local stains = {}
local shake = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshFilter()
	local list = { fxFolder }
	for _, n in ipairs({ "Fighters", "BrawlWeapons", "BrawlGibs" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function myChar()
	return localPlayer.Character
end

-- ===== เสียง =====
function Effects.sound(name, pos, volMul)
	local def = Config.Sounds[name]
	if not def or not pos then
		return
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = (def.vol or 0.5) * (volMul or 1)
	s.PlaybackSpeed = (def.pitch or 1) * rng:NextNumber(0.9, 1.1)
	s.RollOffMaxDistance = 140
	s.RollOffMinDistance = 8
	s.Parent = att
	s:Play()
	Debris:AddItem(att, 4)
end

-- ===== กล้องสั่น =====
function Effects.shake(amount)
	shake = math.min(2.5, shake + amount * Config.CameraShake)
end

-- ===== คำการ์ตูนเด้ง =====
local WORD_COLORS = {
	Color3.fromRGB(255, 230, 40), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 40), Color3.fromRGB(120, 230, 255),
}
function Effects.word(pos, text, opts)
	opts = opts or {}
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - pos).Magnitude > 150 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = fxFolder
	local big = opts.big
	local small = opts.small
	local bb = Instance.new("BillboardGui")
	local w = big and 9 or (small and 5 or 6.5)
	bb.Size = UDim2.new(w, 0, w * 0.42, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.StudsOffset = Vector3.new(rng:NextNumber(-0.8, 0.8), 1.2, 0)
	bb.Adornee = anchor
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Size = UDim2.fromScale(0.2, 0.2)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = opts.color or WORD_COLORS[rng:NextInteger(1, #WORD_COLORS)]
	t.Rotation = rng:NextNumber(-14, 14)
	t.Parent = bb
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = big and 4 or 3
	stroke.Color = Color3.fromRGB(20, 10, 10)
	stroke.Parent = t
	TweenService:Create(t, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	task.delay(0.5, function()
		if bb.Parent then
			TweenService:Create(bb, TweenInfo.new(0.5), { StudsOffset = bb.StudsOffset + Vector3.new(0, 2, 0) }):Play()
			TweenService:Create(t, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(anchor, 1.1)
end

-- ===== รอยเลือดบนพื้น/กำแพง =====
local function bloodColor()
	return Config.BloodColor:Lerp(Color3.fromRGB(60, 0, 4), rng:NextNumber(0, 0.45))
end

function Effects.stain(pos, normal, size, inst, color)
	if Config.Blood <= 0 then
		return
	end
	local up = math.abs(normal.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local right = normal:Cross(up).Unit
	local d = size * rng:NextNumber(2.5, 6)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.05, d, d * rng:NextNumber(1, 1.7))
	p.CFrame = CFrame.fromMatrix(pos + normal * (0.03 + rng:NextNumber(0, 0.01)), normal, right) * CFrame.Angles(rng:NextNumber(0, 6.28), 0, 0)
	p.Color = color or bloodColor()
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.08
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if inst and not inst.Anchored then
		p.Anchored = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = inst
		w.Part1 = p
		w.Parent = p
	else
		p.Anchored = true
	end
	p.Parent = fxFolder
	table.insert(stains, { part = p, t = os.clock() })
	-- เลือดแห้งเข้มขึ้น
	TweenService:Create(p, TweenInfo.new(25), { Color = p.Color:Lerp(Color3.fromRGB(45, 4, 6), 0.6) }):Play()
	while #stains > Config.MaxStains do
		local old = table.remove(stains, 1)
		if old.part then
			old.part:Destroy()
		end
	end
	return p
end

-- ===== หยดเลือดลอยในอากาศ =====
local function getDrop()
	local p = table.remove(dropPool)
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.1
	end
	p.Parent = fxFolder
	return p
end

local function releaseDrop(p)
	p.Parent = nil
	table.insert(dropPool, p)
end

function Effects.spray(pos, dir, n, speed, color, sizeMul)
	if Config.Blood <= 0 and not color then
		return
	end
	n = math.min(n, 60)
	for _ = 1, n do
		if #drops > 350 then
			break
		end
		local spread = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1))
		local v = (dir * rng:NextNumber(0.4, 1.2) + spread * 0.7) * speed * rng:NextNumber(0.5, 1.2) + Vector3.new(0, rng:NextNumber(2, 9), 0)
		local s = rng:NextNumber(0.1, 0.28) * (sizeMul or 1)
		local p = getDrop()
		p.Size = Vector3.new(s, s, s * 2.2)
		p.Color = color or bloodColor()
		p.CFrame = CFrame.new(pos)
		table.insert(drops, { part = p, pos = pos + spread * 0.2, vel = v, size = s, life = 3, color = color })
	end
end

local function stepDrops(dt)
	local g = workspace.Gravity * 0.85
	for i = #drops, 1, -1 do
		local d = drops[i]
		d.vel = d.vel - Vector3.new(0, g * dt, 0)
		local np = d.pos + d.vel * dt
		local res = workspace:Raycast(d.pos, np - d.pos, rayParams)
		d.life = d.life - dt
		if res then
			if rng:NextNumber() < 0.75 then
				Effects.stain(res.Position, res.Normal, d.size, res.Instance, d.color)
			end
			releaseDrop(d.part)
			table.remove(drops, i)
		elseif d.life <= 0 then
			releaseDrop(d.part)
			table.remove(drops, i)
		else
			d.pos = np
			if d.vel.Magnitude > 0.1 then
				d.part.CFrame = CFrame.lookAt(np, np + d.vel)
			end
		end
	end
	-- ลบรอยเลือดเก่า
	local t = os.clock()
	while #stains > 0 and t - stains[1].t > Config.StainLife do
		local old = table.remove(stains, 1)
		if old.part then
			old.part:Destroy()
		end
	end
end

-- ===== ฟันกระเด็น =====
function Effects.teeth(pos, dir, n)
	for _ = 1, n do
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.16, 0.22, 0.14)
		p.Color = Color3.fromRGB(250, 248, 235)
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		p.CanQuery = false
		p.Parent = fxFolder
		p.AssemblyLinearVelocity = dir * rng:NextNumber(10, 22) + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(10, 20), rng:NextNumber(-6, 6))
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(-30, 30), rng:NextNumber(-30, 30))
		Debris:AddItem(p, 10)
	end
end

-- ===== แฟลชตัวที่โดนตี =====
local function flash(model, color)
	if not model or not model.Parent then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = color or Color3.new(1, 1, 1)
	h.FillTransparency = 0.25
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	Debris:AddItem(h, 0.09)
end

-- ===== ดาวหมุนเหนือหัวตอนมึน =====
local stars = {}
local function updateStars(model)
	local head = model:FindFirstChild("Head")
	local dizzy = model:GetAttribute("Dizzy") == true
	if dizzy and head and not stars[model] then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(4, 0, 1.4, 0)
		bb.StudsOffset = Vector3.new(0, 1.6, 0)
		bb.LightInfluence = 0
		bb.Adornee = head
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.TextScaled = true
		t.Text = "💫⭐💫"
		t.Parent = bb
		bb.Parent = fxFolder
		stars[model] = { gui = bb, label = t }
	elseif (not dizzy or not head) and stars[model] then
		stars[model].gui:Destroy()
		stars[model] = nil
	end
end

local function watchChar(model)
	model:GetAttributeChangedSignal("Dizzy"):Connect(function()
		updateStars(model)
	end)
	model.AncestryChanged:Connect(function()
		if not model.Parent and stars[model] then
			stars[model].gui:Destroy()
			stars[model] = nil
		end
	end)
end

-- ===== ตัวจัดการเหตุการณ์จาก server =====
local handlers = {}

handlers.hit = function(d)
	local pos, dir = d.pos, d.dir or Vector3.new(0, 0, -1)
	local mine = myChar()
	local power = d.power or 5
	Effects.word(pos, d.word or "ปั้ก!", { big = d.big })
	Effects.sound(d.sound or "hit", pos, math.clamp(power / 10, 0.5, 1.5))
	if d.blood and d.blood > 0 then
		Effects.spray(pos, dir, d.blood, 12 + power, nil, 1)
		if power >= 12 then
			Effects.spray(pos, -dir * 0.3 + Vector3.new(0, 0.6, 0), math.floor(d.blood / 3), 8, nil, 1.6)
		end
	elseif Config.Blood <= 0 then
		Effects.word(pos + Vector3.new(0, 1, 0), "⭐", { small = true })
	end
	if d.teeth and d.teeth > 0 then
		Effects.teeth(pos, dir, d.teeth)
		Effects.word(pos + Vector3.new(0, 1.2, 0), "🦷 ฟันหลุด!", { small = true, color = Color3.fromRGB(255, 255, 255) })
	end
	if d.victim and not d.impact then
		flash(d.victim, d.crit and Color3.fromRGB(255, 80, 60) or nil)
	end
	-- hit-stop + กล้องสั่น
	local stop = math.clamp(power / 120, 0.03, 0.12)
	if d.attacker then
		Animator.hitstop(d.attacker, stop)
	end
	if d.victim and not d.impact then
		Animator.hitstop(d.victim, stop)
	end
	if mine and (d.victim == mine) then
		Effects.shake(power / 14)
		if Hud then
			Hud.hurtFlash(power)
		end
	elseif mine and d.attacker == mine then
		Effects.shake(power / 30)
		if Hud then
			Hud.comboHit()
		end
	else
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - pos).Magnitude < 30 and power > 10 then
			Effects.shake(power / 60)
		end
	end
end

handlers.block = function(d)
	Effects.word(d.pos, d.word or "กัน!", { big = d.big, color = Color3.fromRGB(120, 230, 255) })
	Effects.sound("clang", d.pos, d.big and 1.2 or 0.7)
	if d.victim then
		flash(d.victim, Color3.fromRGB(120, 200, 255))
	end
	local mine = myChar()
	if mine and (d.victim == mine or d.attacker == mine) then
		Effects.shake(d.big and 0.6 or 0.2)
	end
end

handlers.word = function(d)
	Effects.word(d.pos, d.word, { big = d.big, small = d.small })
end

handlers.dizzy = function(d)
	if d.victim then
		local head = d.victim:FindFirstChild("Head")
		if head then
			Effects.word(head.Position + Vector3.new(0, 1.5, 0), "มึนตึ้บ! 😵", { big = true, color = Color3.fromRGB(200, 160, 255) })
		end
	end
end

handlers.super = function(d)
	local char = d.char
	local head = char and char:FindFirstChild("Head")
	if head then
		Effects.word(head.Position + Vector3.new(0, 2, 0), "หมัดจรวด!!! 🚀", { big = true, color = Color3.fromRGB(255, 80, 40) })
		Effects.sound("super", head.Position, 1.4)
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - head.Position).Magnitude < 60 then
			Effects.shake(0.5)
		end
	end
	if char and char == myChar() and Hud then
		Hud.superFlash()
	end
end

handlers.taunt = function(d)
	local head = d.char and d.char:FindFirstChild("Head")
	if head then
		Effects.word(head.Position + Vector3.new(0, 2, 0), "🎵 ยั่วๆ 🎶", { small = true, color = Color3.fromRGB(255, 150, 220) })
		task.delay(0.7, function()
			if head.Parent then
				Effects.word(head.Position + Vector3.new(0, 2.4, 0), "💃🕺", { small = true })
			end
		end)
	end
end

handlers["break"] = function(d)
	Effects.word(d.pos, d.glass and "เพล้ง!!" or "พัง!!", { big = true, color = Color3.fromRGB(200, 240, 255) })
	Effects.sound(d.glass and "glass" or "wood", d.pos, 1.2)
	if d.glass then
		for _ = 1, 10 do
			local p = Instance.new("Part")
			p.Size = Vector3.new(0.06, rng:NextNumber(0.15, 0.5), rng:NextNumber(0.15, 0.5))
			p.Color = Color3.fromRGB(200, 230, 245)
			p.Material = Enum.Material.Glass
			p.Transparency = 0.3
			p.CFrame = CFrame.new(d.pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			p.CanQuery = false
			p.Parent = fxFolder
			p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(4, 16), rng:NextNumber(-14, 14))
			Debris:AddItem(p, 5)
		end
	end
end

handlers.melon = function(d)
	Effects.word(d.pos, (Config.Words.melon or { "แตงโมแตก!" })[1], { big = true, color = Color3.fromRGB(120, 255, 120) })
	Effects.sound("thud", d.pos, 1)
	Effects.spray(d.pos, Vector3.new(0, 1, 0), 30, 14, Color3.fromRGB(235, 60, 85), 1.2)
end

-- แขนขาหลุด: เลือดพุ่งจากตอเป็นจังหวะตามหัวใจ
local spurts = {}
handlers.sever = function(d)
	local pos = d.pos
	if not pos then
		return
	end
	Effects.word(pos + Vector3.new(0, 1, 0), d.word or "หลุด!!", { big = true, color = Color3.fromRGB(255, 70, 60) })
	Effects.sound("heavy", pos, 1.3)
	Effects.shake(0.3)
	if d.gore and d.gore >= 1 and Config.Blood > 0 then
		Effects.spray(pos, Vector3.new(0, 1, 0), math.floor(30 * Config.Blood), 16, nil, 1.3)
		if d.stump then
			table.insert(spurts, { part = d.stump, untilT = os.clock() + 3.5, nextT = 0, beat = 0 })
		end
		if d.piece then
			table.insert(spurts, { part = d.piece, untilT = os.clock() + 1.5, nextT = 0, beat = 0 })
		end
	else
		-- โหมดคลาสสิก: ฝุ่นบล็อกแทนเลือด
		Effects.spray(pos, Vector3.new(0, 1, 0), 10, 10, Color3.fromRGB(200, 200, 200), 1)
	end
end

local function stepSpurts()
	local t = os.clock()
	for i = #spurts, 1, -1 do
		local sp = spurts[i]
		local part = sp.part
		if not part or not part.Parent or t > sp.untilT then
			table.remove(spurts, i)
		elseif t >= sp.nextT then
			sp.beat = sp.beat + 1
			-- ตุบ...ตุบ แรงตอนหัวใจบีบ แล้วค่อยๆ อ่อนลง
			local strong = (sp.beat % 6) < 2
			sp.nextT = t + 0.06
			local left = (sp.untilT - t) / 3.5
			local dir = (part.CFrame.UpVector + Vector3.new(0, 0.6, 0)).Unit
			Effects.spray(part.Position, dir, strong and 4 or 1, (strong and 14 or 6) * (0.4 + left), nil, 0.9)
		end
	end
end

handlers.pool = function(d)
	if Config.Blood <= 0 then
		return
	end
	local res = workspace:Raycast(d.pos + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), rayParams)
	if not res then
		return
	end
	local p = Effects.stain(res.Position, res.Normal, 0.3, res.Instance, Config.BloodColor:Lerp(Color3.fromRGB(70, 0, 5), 0.3))
	if p then
		local target = math.clamp(4 * Config.Blood, 2, 7)
		TweenService:Create(p, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, target, target * 1.3) }):Play()
	end
end

function Effects.init(config, remotes, animator)
	Config = config
	Animator = animator
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "BrawlFX"
	fxFolder.Parent = workspace
	refreshFilter()
	workspace.ChildAdded:Connect(refreshFilter)

	remotes.Fx.OnClientEvent:Connect(function(kind, data)
		local h = handlers[kind]
		if h and type(data) == "table" then
			local ok, err = pcall(h, data)
			if not ok then
				warn("[ซอยเดือด] fx error", kind, err)
			end
		end
	end)

	-- เสียงวืดตอนออกท่า
	local STRIKE = { jab = 0.7, cross = 0.8, upper = 1, kick = 1, swing = 1.1, super = 1.4, dive = 1, throw = 1, stomp = 0.8 }
	Animator.onPlay = function(model, name)
		local v = STRIKE[name]
		local root = model:FindFirstChild("HumanoidRootPart")
		if v and root then
			Effects.sound("swing", root.Position, v)
		end
	end

	for _, m in ipairs(CollectionService:GetTagged("BrawlChar")) do
		watchChar(m)
	end
	CollectionService:GetInstanceAddedSignal("BrawlChar"):Connect(watchChar)

	RunService.Heartbeat:Connect(function(dt)
		stepDrops(dt)
		stepSpurts()
		-- ดาวหมุน
		for _, s in pairs(stars) do
			s.label.Rotation = (s.label.Rotation + dt * 160) % 360
		end
		-- อาวุธบนแท่นหมุนช้าๆ (หมุนเฉพาะในเครื่องเรา)
		local wf = workspace:FindFirstChild("BrawlWeapons")
		if wf then
			for _, m in ipairs(wf:GetChildren()) do
				if m:GetAttribute("OnPad") and m.PrimaryPart and m.PrimaryPart.Anchored then
					local c = m:GetBoundingBox().Position
					local rot = CFrame.new(c) * CFrame.Angles(0, dt * 1.6, 0) * CFrame.new(-c)
					m:PivotTo(rot * m:GetPivot())
				end
			end
		end
	end)

	-- กล้องสั่น (ผ่าน CameraOffset ปลอดภัยกับสคริปต์กล้องปกติ)
	RunService.RenderStepped:Connect(function(dt)
		local char = myChar()
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		if shake > 0.01 then
			hum.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5)) * shake * 0.6
			shake = shake * math.exp(-dt * 10)
		elseif hum.CameraOffset.Magnitude > 0 then
			hum.CameraOffset = Vector3.zero
			shake = 0
		end
	end)
end

function Effects.setHud(h)
	Hud = h
end

return Effects
