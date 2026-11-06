-- ============================================================
--  ซอยเดือด : ปุ่มควบคุม (คีย์บอร์ด/เมาส์, จอย, มือถือปุ่มรูป)
--  มี aim assist หันหาศัตรูใกล้สุดให้อัตโนมัติ + บัฟเฟอร์ปุ่ม
-- ============================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Controls = {}
local Config, remotes, Animator
local player = Players.LocalPlayer

local busyUntil = 0
local queued = nil
local combo = 0
local lastPunchEnd = -10
local blocking = false
local touchGui

local function char()
	return player.Character
end

local function alive(c)
	if not c or not c.Parent then
		return false
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and not c:GetAttribute("Ragdoll") and not c:GetAttribute("Dead")
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

-- หาศัตรูข้างหน้า (aim assist)
local function findEnemy(c, range, cone, wantDown)
	local root = c:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local look = flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local cam = workspace.CurrentCamera
	local camLook = cam and flat(cam.CFrame.LookVector) or look
	local best, bestScore = nil, math.huge
	for _, m in ipairs(CollectionService:GetTagged("BrawlChar")) do
		if m ~= c and m.Parent and not m:GetAttribute("Dead") then
			local down = m:GetAttribute("Ragdoll") == true
			if (wantDown and down) or (not wantDown and not down) then
				local part = down and m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
				if part then
					local d = part.Position - root.Position
					local fd = Vector3.new(d.X, 0, d.Z)
					local dist = fd.Magnitude
					if dist < range and math.abs(d.Y) < 5 then
						local dirTo = dist > 0.01 and fd.Unit or look
						local a1 = math.deg(math.acos(math.clamp(dirTo:Dot(look), -1, 1)))
						local a2 = math.deg(math.acos(math.clamp(dirTo:Dot(camLook), -1, 1)))
						local ang = math.min(a1, a2)
						if ang < cone then
							local score = dist + ang * 0.05
							if score < bestScore then
								best, bestScore = m, score
							end
						end
					end
				end
			end
		end
	end
	return best
end

local function aim(c)
	local root = c:FindFirstChild("HumanoidRootPart")
	local enemy = findEnemy(c, 11, 75, false)
	local dir = flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	if enemy then
		local ep = enemy:FindFirstChild("HumanoidRootPart").Position
		local d = flat(ep - root.Position)
		if d then
			dir = d
			root.CFrame = CFrame.lookAt(root.Position, root.Position + d)
		end
	end
	return dir
end

local function nearWeapon(c)
	local root = c:FindFirstChild("HumanoidRootPart")
	local wf = workspace:FindFirstChild("BrawlWeapons")
	if not root or not wf then
		return nil, math.huge
	end
	local best, bd = nil, 6
	for _, m in ipairs(wf:GetChildren()) do
		if m.PrimaryPart and not m:GetAttribute("Held") and not m:GetAttribute("Broken") and not m:GetAttribute("Thrown") then
			local d = (m.PrimaryPart.Position - root.Position).Magnitude
			if d < bd then
				best, bd = m, d
			end
		end
	end
	return best, bd
end

-- ===== ส่งคำสั่ง =====
local function doAction(action)
	local c = char()
	if not alive(c) then
		return
	end
	local t = os.clock()
	if t < busyUntil then
		queued = { action = action, t = t }
		return
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local moves = Config.Moves
	local dir = aim(c)
	local air = hum.FloorMaterial == Enum.Material.Air
	local clip, dur = nil, 0.3
	if action == "punch" then
		if c:GetAttribute("Weapon") then
			clip, dur = "swing", moves.swing.dur
		elseif air then
			clip, dur = "dive", moves.dive.dur
		else
			if t - lastPunchEnd < Config.ComboWindow then
				combo = (combo % #Config.PunchCombo) + 1
			else
				combo = 1
			end
			local name = Config.PunchCombo[combo]
			clip, dur = moves[name].anim, moves[name].dur
			lastPunchEnd = t + dur
		end
	elseif action == "kick" then
		if findEnemy(c, moves.stomp.range + 0.8, 50, true) then
			clip, dur = "stomp", moves.stomp.dur
		else
			clip, dur = "kick", moves.kick.dur
		end
	elseif action == "grab" then
		if c:GetAttribute("Weapon") then
			clip, dur = "throw", moves.throw.dur
		else
			local w, wd = nearWeapon(c)
			local e = findEnemy(c, moves.grab.range + 0.8, 40, false)
			local ed = math.huge
			if e then
				ed = (e.HumanoidRootPart.Position - c.HumanoidRootPart.Position).Magnitude
			end
			if w and wd < ed then
				clip, dur = "pickup", moves.pickup.dur
			else
				clip, dur = "grab", moves.grab.dur
			end
		end
	elseif action == "super" then
		if (c:GetAttribute("Super") or 0) < Config.SuperMax then
			return
		end
		clip, dur = "super", moves.super.dur
	elseif action == "taunt" then
		clip, dur = "taunt", moves.taunt.dur
	end
	if blocking then
		Controls.setBlock(false)
	end
	busyUntil = t + dur
	if clip then
		Animator.playLocal(c, clip)
	end
	remotes.Action:FireServer(action, { dir = dir, air = air })
end
Controls.doAction = doAction

function Controls.setBlock(on)
	if blocking == on then
		return
	end
	blocking = on
	Animator.localBlock = on
	remotes.Action:FireServer("block", { on = on })
end

function Controls.jump()
	local c = char()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum and alive(c) then
		hum.Jump = true
	end
end

-- ===== คีย์บอร์ด / เมาส์ / จอย =====
local KEYS = {
	[Enum.KeyCode.J] = "punch",
	[Enum.KeyCode.E] = "kick",
	[Enum.KeyCode.K] = "kick",
	[Enum.KeyCode.R] = "grab",
	[Enum.KeyCode.L] = "grab",
	[Enum.KeyCode.F] = "super",
	[Enum.KeyCode.T] = "taunt",
	[Enum.KeyCode.ButtonX] = "punch",
	[Enum.KeyCode.ButtonY] = "kick",
	[Enum.KeyCode.ButtonB] = "grab",
	[Enum.KeyCode.ButtonR2] = "super",
	[Enum.KeyCode.DPadUp] = "taunt",
}
local BLOCK_KEYS = {
	[Enum.KeyCode.Q] = true,
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonL1] = true,
}

local function bindInput()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			doAction("punch")
			return
		end
		local a = KEYS[input.KeyCode]
		if a then
			doAction(a)
		elseif BLOCK_KEYS[input.KeyCode] then
			Controls.setBlock(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if BLOCK_KEYS[input.KeyCode] then
			Controls.setBlock(false)
		end
	end)
end

-- ===== ปุ่มมือถือ (รูปล้วน) =====
local function makeTouch()
	touchGui = Instance.new("ScreenGui")
	touchGui.Name = "BrawlTouch"
	touchGui.ResetOnSpawn = false
	touchGui.IgnoreGuiInset = true
	touchGui.DisplayOrder = 6
	touchGui.Parent = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = touchGui

	-- ตำแหน่งเทียบมุมขวาล่าง (หน่วย u = ขนาดตามความสูงจอ)
	local DEFS = {
		{ id = "punch", icon = "👊", x = -1.6, y = -1.2, s = 1.4, color = Color3.fromRGB(230, 70, 50) },
		{ id = "jump", icon = "⬆️", x = -0.55, y = -0.6, s = 0.95, color = Color3.fromRGB(70, 160, 230) },
		{ id = "kick", icon = "🦶", x = -0.6, y = -2.0, s = 1.0, color = Color3.fromRGB(240, 150, 40) },
		{ id = "grab", icon = "✊", x = -1.5, y = -2.55, s = 0.95, color = Color3.fromRGB(150, 90, 200) },
		{ id = "block", icon = "🛡️", x = -2.75, y = -0.75, s = 1.0, color = Color3.fromRGB(60, 140, 220) },
		{ id = "super", icon = "⭐", x = -2.65, y = -2.15, s = 0.95, color = Color3.fromRGB(255, 200, 40) },
		{ id = "taunt", icon = "💃", x = -0.55, y = -3.1, s = 0.75, color = Color3.fromRGB(230, 100, 180) },
	}
	local buttons = {}
	local function layout()
		local vs = workspace.CurrentCamera.ViewportSize
		local u = math.clamp(math.min(vs.X, vs.Y) * 0.15, 52, 100)
		for _, d in ipairs(DEFS) do
			local b = buttons[d.id]
			local size = u * d.s
			b.Size = UDim2.fromOffset(size, size)
			b.Position = UDim2.new(1, d.x * u - 12, 1, d.y * u - 12)
		end
	end
	for _, d in ipairs(DEFS) do
		local b = Instance.new("TextButton")
		b.Name = d.id
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Text = d.icon
		b.TextScaled = true
		b.Font = Enum.Font.GothamBlack
		b.BackgroundColor3 = d.color
		b.BackgroundTransparency = 0.25
		b.AutoButtonColor = false
		b.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = b
		local st = Instance.new("UIStroke")
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Thickness = 3
		st.Color = Color3.fromRGB(255, 255, 255)
		st.Transparency = 0.3
		st.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.18, 0)
		pad.PaddingBottom = UDim.new(0.18, 0)
		pad.PaddingLeft = UDim.new(0.18, 0)
		pad.PaddingRight = UDim.new(0.18, 0)
		pad.Parent = b
		buttons[d.id] = b
		b.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			b.BackgroundTransparency = 0.05
			if d.id == "block" then
				Controls.setBlock(true)
			elseif d.id == "jump" then
				Controls.jump()
			else
				doAction(d.id)
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			b.BackgroundTransparency = 0.25
			if d.id == "block" then
				Controls.setBlock(false)
			end
		end)
	end
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	-- ปุ่มท่าไม้ตายกะพริบเมื่อพร้อม
	RunService.RenderStepped:Connect(function()
		local c = char()
		local ready = c and (c:GetAttribute("Super") or 0) >= Config.SuperMax
		local b = buttons.super
		if ready then
			b.Rotation = math.sin(os.clock() * 10) * 8
			b.BackgroundTransparency = 0.05
		else
			b.Rotation = 0
		end
		buttons.grab.Text = (c and c:GetAttribute("Weapon")) and "🎯" or "✊"
	end)
	-- ซ่อนปุ่มกระโดดเดิมของ Roblox (เรามีปุ่ม ⬆️ เอง) แต่เก็บจอยซ้ายไว้
	task.spawn(function()
		while touchGui.Parent do
			local tg = player.PlayerGui:FindFirstChild("TouchGui")
			local frame = tg and tg:FindFirstChild("TouchControlFrame")
			local jb = frame and frame:FindFirstChild("JumpButton")
			if jb and jb.Visible then
				jb.Visible = false
			end
			task.wait(1)
		end
	end)
end

function Controls.init(config, r, animator)
	Config = config
	remotes = r
	Animator = animator
	bindInput()
	if UserInputService.TouchEnabled then
		makeTouch()
	end
	-- ปล่อยปุ่มที่บัฟเฟอร์ไว้เมื่อท่าเดิมจบ
	RunService.Heartbeat:Connect(function()
		if queued then
			local t = os.clock()
			if t - queued.t > 0.35 then
				queued = nil
			elseif t >= busyUntil then
				local a = queued.action
				queued = nil
				doAction(a)
			end
		end
		local c = char()
		if blocking and not alive(c) then
			blocking = false
			Animator.localBlock = false
		end
	end)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		queued = nil
		combo = 0
		blocking = false
		Animator.localBlock = false
	end)
end

return Controls
