-- ============================================================
--  ALLEY BRAWL : หน้าจอ HUD (ใช้รูป/อีโมจิแทนข้อความยาวๆ)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Hud = {}
local Config, Effects
local player = Players.LocalPlayer
local gui
local ui = {}
local combo = { n = 0, t = 0 }

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

local function stroke(o, th, col)
	return make("UIStroke", { Thickness = th or 2, Color = col or Color3.fromRGB(0, 0, 0) }, o)
end

local function label(parent, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.LuckiestGuy,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
	}, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end

local function bar(parent, pos, size, color, icon)
	local back = make("Frame", { Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(25, 20, 22), BorderSizePixel = 0 }, parent)
	corner(back, 8)
	stroke(back, 2, Color3.fromRGB(10, 8, 8))
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	corner(fill, 8)
	local txt = label(back, { Size = UDim2.new(1, -10, 1, -4), Position = UDim2.fromOffset(6, 2), TextXAlignment = Enum.TextXAlignment.Left, Text = icon, ZIndex = 3 })
	stroke(txt, 1.5)
	return back, fill, txt
end

-- ===== ป้ายใหญ่กลางจอ =====
function Hud.banner(text, color, dur, sub)
	local b = ui.banner
	b.Text = text
	b.TextColor3 = color or Color3.fromRGB(255, 220, 60)
	b.Visible = true
	b.Size = UDim2.fromScale(0.2, 0.05)
	TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.8, 0.14) }):Play()
	ui.bannerSub.Text = sub or ""
	ui.bannerSub.Visible = sub ~= nil
	local token = {}
	ui.bannerToken = token
	task.delay(dur or 2.2, function()
		if ui.bannerToken == token then
			b.Visible = false
			ui.bannerSub.Visible = false
		end
	end)
end

-- ===== ขอบจอแดงตอนโดนตี =====
function Hud.hurtFlash(power)
	local a = math.clamp(power / 25, 0.25, 0.85)
	for _, e in ipairs(ui.edges) do
		e.BackgroundTransparency = 1 - a
		TweenService:Create(e, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end
end

function Hud.superFlash()
	ui.white.BackgroundTransparency = 0.2
	TweenService:Create(ui.white, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

-- ===== คอมโบ =====
function Hud.comboHit()
	local t = os.clock()
	if t - combo.t > 1.6 then
		combo.n = 0
	end
	combo.n = combo.n + 1
	combo.t = t
	if combo.n >= 2 then
		local c = ui.combo
		c.Text = combo.n .. "x COMBO!"
		c.Visible = true
		c.Rotation = math.random(-8, 8)
		c.Size = UDim2.fromOffset(150, 50)
		TweenService:Create(c, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(230, 70) }):Play()
	end
end

-- ===== killfeed =====
local function feed(text)
	local list = ui.feed
	local row = label(list, {
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = -math.floor(os.clock() * 100),
	})
	stroke(row, 1.5)
	local rows = {}
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(rows, c)
		end
	end
	if #rows > 5 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		rows[#rows]:Destroy()
	end
	task.delay(7, function()
		if row.Parent then
			TweenService:Create(row, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			task.delay(0.6, function()
				row:Destroy()
			end)
		end
	end)
end

-- ===== หน้าช่วยเหลือ (รูปปุ่ม) =====
local HELP = {
	{ "👊", "Punch", "Click / J", "Hit 3 times for an uppercut launcher" },
	{ "🦶", "Kick", "E / K", "Sends them flying. Near a downed guy = stomp" },
	{ "✊", "Grab / Pick up", "R / L", "Suplex! Holding a weapon = throw it" },
	{ "🛡️", "Block", "Q (hold)", "Stops punches. Kicks & grabs break it" },
	{ "⭐", "Rocket Punch", "F", "Use when the star meter is full" },
	{ "💃", "Taunt", "T", "Fills your star meter" },
	{ "⬆️", "Jump", "Space", "Jump + punch = ground pound" },
}

local function buildHelp(parent)
	local panel = make("Frame", {
		Name = "Help",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 520, 0, 420),
		BackgroundColor3 = Color3.fromRGB(28, 22, 26),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 20,
	}, parent)
	corner(panel, 16)
	stroke(panel, 3, Color3.fromRGB(255, 200, 40))
	make("UISizeConstraint", { MaxSize = Vector2.new(560, 440) }, panel)
	make("UIScale", { Name = "Scale" }, panel)
	label(panel, { Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 8), Text = "🔥 ALLEY BRAWL: HOW TO PLAY", TextColor3 = Color3.fromRGB(255, 210, 60), ZIndex = 21 })
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	for i, h in ipairs(HELP) do
		local y = 56 + (i - 1) * 48
		local icon = label(panel, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(16, y), Text = h[1], ZIndex = 21 })
		icon.Font = Enum.Font.GothamBlack
		label(panel, { Size = UDim2.fromOffset(150, 24), Position = UDim2.fromOffset(68, y), Text = h[2], TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
		if not touch then
			local key = label(panel, { Size = UDim2.fromOffset(110, 24), Position = UDim2.fromOffset(68, y + 22), Text = h[3], TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 210, 60), ZIndex = 21 })
			key.Font = Enum.Font.GothamBold
		end
		local tip = label(panel, { Size = UDim2.new(1, -240, 0, 40), Position = UDim2.fromOffset(225, y + 2), Text = h[4], TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(210, 210, 210), ZIndex = 21 })
		tip.Font = Enum.Font.Gotham
	end
	local close = make("TextButton", {
		Size = UDim2.fromOffset(160, 40),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Text = "👊 LET'S GO!",
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(30, 20, 10),
		BackgroundColor3 = Color3.fromRGB(255, 200, 40),
		ZIndex = 22,
	}, panel)
	corner(close, 10)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	return panel
end

local function fitHelp()
	local cam = workspace.CurrentCamera
	if not cam or not ui.help then
		return
	end
	local vs = cam.ViewportSize
	local s = math.min(1, (vs.X - 20) / 540, (vs.Y - 20) / 440)
	ui.help.Scale.Scale = math.max(0.45, s)
end

function Hud.init(config, remotes, effects)
	Config = config
	Effects = effects
	gui = make("ScreenGui", { Name = "BrawlHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))

	-- ขอบจอแดง + แฟลชขาว
	ui.edges = {}
	local edgeDefs = {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.18), 90 },
		{ UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.18), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.14, 1), 0 },
		{ UDim2.fromScale(0.86, 0), UDim2.fromScale(0.14, 1), 180 },
	}
	for _, e in ipairs(edgeDefs) do
		local f = make("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = Color3.fromRGB(200, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
		make("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
		table.insert(ui.edges, f)
	end
	ui.white = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30 }, gui)

	-- แผงสถานะซ้ายบน
	local panel = make("Frame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(250, 74), BackgroundTransparency = 1 }, gui)
	local _, hpFill, hpText = bar(panel, UDim2.fromOffset(0, 0), UDim2.fromOffset(250, 32), Color3.fromRGB(90, 220, 90), "❤️ 100")
	local _, spFill, spText = bar(panel, UDim2.fromOffset(0, 38), UDim2.fromOffset(200, 24), Color3.fromRGB(255, 200, 40), "⭐ 0%")
	ui.hpFill, ui.hpText, ui.spFill, ui.spText = hpFill, hpText, spFill, spText
	ui.weapon = label(panel, { Size = UDim2.fromOffset(250, 26), Position = UDim2.fromOffset(0, 66), Text = "", TextXAlignment = Enum.TextXAlignment.Left, Visible = false })
	stroke(ui.weapon, 1.5)
	local helpBtn = make("TextButton", { Size = UDim2.fromOffset(40, 24), Position = UDim2.fromOffset(208, 38), Text = "❓", TextScaled = true, Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(40, 34, 38), TextColor3 = Color3.new(1, 1, 1) }, panel)
	corner(helpBtn, 8)

	-- เวลา + อันดับ (กลางบน)
	ui.timer = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(200, 34), Text = "⏱ 3:00" })
	stroke(ui.timer, 2)
	ui.top = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.fromOffset(420, 22), Text = "", TextColor3 = Color3.fromRGB(255, 225, 120) })
	stroke(ui.top, 1.5)

	-- killfeed ขวาบน
	ui.feed = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(340, 160), BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Right }, ui.feed)

	-- ป้ายใหญ่
	ui.banner = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromScale(0.8, 0.14), Visible = false, ZIndex = 10 })
	stroke(ui.banner, 4)
	ui.bannerSub = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.7, 0.06), Visible = false, ZIndex = 10 })
	stroke(ui.bannerSub, 2.5)
	ui.combo = label(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.42, 0), Size = UDim2.fromOffset(230, 70), Visible = false, TextColor3 = Color3.fromRGB(255, 120, 40), ZIndex = 8 })
	stroke(ui.combo, 3)
	ui.dead = label(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.6, 0.07), Visible = false, Text = "", ZIndex = 9 })
	stroke(ui.dead, 3)

	-- คีย์ลัดแบบรูป (คอมพิวเตอร์)
	if UserInputService.KeyboardEnabled then
		ui.keys = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(620, 26), Text = "🖱️ 👊Punch   E 🦶Kick   R ✊Grab   Q 🛡️Block   F ⭐Super   T 💃Taunt", TextColor3 = Color3.fromRGB(240, 240, 240) })
		stroke(ui.keys, 1.5)
	end

	ui.help = buildHelp(gui)
	fitHelp()
	helpBtn.Activated:Connect(function()
		fitHelp()
		ui.help.Visible = not ui.help.Visible
	end)
	ui.help.Visible = true
	task.delay(10, function()
		ui.help.Visible = false
	end)

	-- ข่าวจาก server
	remotes.Notify.OnClientEvent:Connect(function(kind, d)
		if type(d) ~= "table" then
			return
		end
		local mine = player.Character
		if kind == "ko" then
			if d.killer then
				feed("👊 " .. d.killer .. "  ➜  😵 " .. d.victim)
			else
				feed("😵 " .. d.victim)
			end
			if d.victimModel and d.victimModel == mine then
				Hud.banner("K.O.!! 😵", Color3.fromRGB(255, 70, 50), 3, d.msg)
				ui.deadUntil = os.clock() + Config.RespawnTime
				ui.dead.Visible = true
			elseif d.killerModel and d.killerModel == mine then
				Hud.banner("K.O.!! 💥", Color3.fromRGB(255, 220, 60), 2.4, d.msg)
				if Effects then
					Effects.sound("ko", workspace.CurrentCamera.CFrame.Position, 1)
				end
			end
			if d.streak and d.killer then
				task.delay(1.2, function()
					Hud.banner(d.streak, Color3.fromRGB(255, 120, 40), 2.2, d.killer)
				end)
			end
		elseif kind == "round" then
			local lines = {}
			if d.king then
				table.insert(lines, "👑 King of the Alley: " .. d.king .. " (" .. d.kos .. " KOs)")
			end
			if d.brute then
				table.insert(lines, "💪 Heaviest Hitter: " .. d.brute .. " (" .. d.dmg .. " dmg)")
			end
			if d.potato then
				table.insert(lines, "🥔 Human Punching Bag: " .. d.potato .. " (" .. d.deaths .. " deaths)")
			end
			if d.dancer then
				table.insert(lines, "💃 Dance Machine: " .. d.dancer .. " (" .. d.taunts .. " taunts)")
			end
			Hud.banner("🔔 ROUND OVER!", Color3.fromRGB(255, 220, 60), Config.ResultTime, table.concat(lines, "   "))
		elseif kind == "newround" then
			Hud.banner("🔔 NEW ROUND! FIGHT!", Color3.fromRGB(120, 255, 140), 2)
		end
	end)

	-- อัปเดตทุกเฟรม
	local stateF = ReplicatedStorage:WaitForChild("BrawlState")
	local endV = stateF:WaitForChild("RoundEnd")
	local scoresF = stateF:WaitForChild("Scores")
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local frac = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
			ui.hpFill.Size = UDim2.fromScale(frac, 1)
			ui.hpFill.BackgroundColor3 = Color3.fromRGB(230, 50, 40):Lerp(Color3.fromRGB(90, 220, 90), frac)
			ui.hpText.Text = "❤️ " .. math.ceil(hum.Health)
			local sp = char:GetAttribute("Super") or 0
			local sf = math.clamp(sp / Config.SuperMax, 0, 1)
			ui.spFill.Size = UDim2.fromScale(sf, 1)
			if sf >= 1 then
				local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
				ui.spText.Text = touch and "⭐ READY! TAP ⭐" or "⭐ READY! PRESS F"
				ui.spFill.BackgroundColor3 = Color3.fromRGB(255, 200, 40):Lerp(Color3.fromRGB(255, 90, 40), (math.sin(os.clock() * 8) + 1) / 2)
			else
				ui.spText.Text = "⭐ " .. math.floor(sf * 100) .. "%"
				ui.spFill.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
			end
			local w = char:GetAttribute("Weapon")
			if w and Config.Weapons[w] then
				local def = Config.Weapons[w]
				local uses = char:GetAttribute("WeaponUses") or 0
				ui.weapon.Text = def.icon .. " " .. def.name .. (uses < 100 and ("  x" .. uses) or "") .. "   (R = throw)"
				ui.weapon.Visible = true
			else
				ui.weapon.Visible = false
			end
		end
		-- นับถอยหลังเกิดใหม่
		if ui.deadUntil then
			local left = ui.deadUntil - os.clock()
			if left > 0 then
				ui.dead.Text = "😵 Respawning in " .. math.ceil(left) .. "..."
			else
				ui.dead.Visible = false
				ui.deadUntil = nil
			end
		end
		if ui.combo.Visible and os.clock() - combo.t > 1.6 then
			ui.combo.Visible = false
		end
		acc = acc + dt
		if acc > 0.25 then
			acc = 0
			local left = math.max(0, endV.Value - workspace:GetServerTimeNow())
			ui.timer.Text = string.format("⏱ %d:%02d", math.floor(left / 60), math.floor(left % 60))
			local list = {}
			for _, v in ipairs(scoresF:GetChildren()) do
				if v:IsA("IntValue") then
					table.insert(list, { name = v:GetAttribute("DisplayName") or "?", ko = v.Value })
				end
			end
			table.sort(list, function(a, b)
				return a.ko > b.ko
			end)
			local medals = { "🥇", "🥈", "🥉" }
			local parts = {}
			for i = 1, math.min(3, #list) do
				if list[i].ko > 0 then
					table.insert(parts, medals[i] .. " " .. list[i].name .. " " .. list[i].ko)
				end
			end
			ui.top.Text = table.concat(parts, "   ")
		end
	end)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHelp)
end

function Hud.gui()
	return gui
end

return Hud
