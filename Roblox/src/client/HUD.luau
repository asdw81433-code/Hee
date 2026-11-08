--[[ Fight HUD: tale of the tape, health/body/stamina bars, clock, popups, count, corner, results. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local HUD = {}
local player = Players.LocalPlayer
local gui
local refs = {}
local popups = {}
local Controls -- set in Start

local FONT = Enum.Font.GothamBlack
local FONT2 = Enum.Font.GothamBold
local TITLE = Enum.Font.Michroma
local RED = Color3.fromRGB(242, 51, 64)
local BLUE = Color3.fromRGB(64, 128, 255)
local YELLOW = Config.Neon.Yellow
local CYAN = Config.Neon.Cyan

-- ------------------------------------------------------------------ tiny UI kit
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

local function frame(parent, pos, size, color, alpha, z)
	return make("Frame", { Position = pos, Size = size, BackgroundColor3 = color or Color3.new(0, 0, 0), BackgroundTransparency = alpha or 0, BorderSizePixel = 0, ZIndex = z or 1 }, parent)
end

local function label(parent, text, pos, size, color, font, align, z)
	return make("TextLabel", {
		Text = text, Position = pos, Size = size, TextColor3 = color or Color3.new(1, 1, 1), Font = font or FONT2, TextScaled = true,
		BackgroundTransparency = 1, TextXAlignment = align or Enum.TextXAlignment.Center, ZIndex = z or 2, RichText = true,
	}, parent)
end

local function stroke(o, color, th)
	return make("UIStroke", { Color = color, Thickness = th or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function corner(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local function button(parent, text, pos, size, color, cb)
	local b = make("TextButton", {
		Text = text, Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(14, 16, 26), TextColor3 = Color3.new(1, 1, 1),
		Font = FONT, TextScaled = true, AutoButtonColor = true, BorderSizePixel = 0, ZIndex = 5,
	}, parent)
	corner(b, 6)
	stroke(b, color or CYAN, 1.5)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
	b.MouseButton1Click:Connect(cb)
	return b
end
HUD.Make, HUD.Frame, HUD.Label, HUD.Button, HUD.Stroke, HUD.Corner = make, frame, label, button, stroke, corner

-- ------------------------------------------------------------------ bars
local function bar(parent, pos, size, color, mirror)
	local back = frame(parent, pos, size, Color3.new(0, 0, 0), 0.35, 2)
	local lost = frame(back, UDim2.new(mirror and 0 or 1, 0, 0, 0), UDim2.new(0, 0, 1, 0), Color3.fromRGB(70, 12, 14), 0.1, 3)
	lost.AnchorPoint = Vector2.new(mirror and 0 or 1, 0)
	local lag = frame(back, UDim2.new(mirror and 1 or 0, 0, 0, 0), UDim2.new(1, 0, 1, 0), Color3.new(1, 1, 1), 0.2, 3)
	lag.AnchorPoint = Vector2.new(mirror and 1 or 0, 0)
	local fill = frame(back, UDim2.new(mirror and 1 or 0, 0, 0, 0), UDim2.new(1, 0, 1, 0), color, 0, 4)
	fill.AnchorPoint = Vector2.new(mirror and 1 or 0, 0)
	make("UIGradient", { Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color), Rotation = 90 }, fill)
	return { back = back, fill = fill, lag = lag, lost = lost, lagV = 1 }
end

local function setBar(b, frac, cap, dt)
	frac = math.clamp(frac, 0, 1)
	cap = math.clamp(cap or 1, 0, 1)
	b.fill.Size = UDim2.new(frac, 0, 1, 0)
	if b.lagV < frac then b.lagV = frac else b.lagV = Util.moveTowards(b.lagV, frac, dt * 0.18) end
	b.lag.Size = UDim2.new(b.lagV, 0, 1, 0)
	b.lost.Size = UDim2.new(1 - cap, 0, 1, 0)
end

local function fighterPanel(parent, mirror)
	local p = frame(parent, UDim2.new(mirror and 1 or 0, mirror and -24 or 24, 0, 18), UDim2.new(0.36, 0, 0, 108), Color3.fromRGB(4, 4, 10), 0.35, 1)
	p.AnchorPoint = Vector2.new(mirror and 1 or 0, 0)
	corner(p, 8)
	local accent = frame(p, UDim2.new(mirror and 1 or 0, mirror and -5 or 0, 0, 0), UDim2.new(0, 5, 1, 0), mirror and BLUE or RED, 0, 2)
	local al = mirror and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	local name = label(p, "", UDim2.new(0, 14, 0, 6), UDim2.new(1, -28, 0, 28), Color3.new(1, 1, 1), FONT, al)
	local sub = label(p, "", UDim2.new(0, 14, 0, 34), UDim2.new(1, -28, 0, 16), Color3.fromRGB(150, 165, 185), FONT2, al)
	local head = bar(p, UDim2.new(0, 14, 0, 54), UDim2.new(1, -28, 0, 16), RED, mirror)
	local body = bar(p, UDim2.new(0, mirror and 14 or 14, 0, 74), UDim2.new(0.75, -14, 0, 7), Color3.fromRGB(255, 153, 51), mirror)
	if mirror then body.back.Position = UDim2.new(0.25, 0, 0, 74) end
	local stam = bar(p, UDim2.new(0, 14, 0, 86), UDim2.new(1, -28, 0, 9), YELLOW, mirror)
	local flags = label(p, "", UDim2.new(0, 14, 0, 96), UDim2.new(1, -28, 0, 12), Color3.new(1, 1, 1), FONT, al)
	local _ = accent
	return { root = p, name = name, sub = sub, head = head, body = body, stam = stam, flags = flags }
end

-- ------------------------------------------------------------------ build
local function build()
	gui = make("ScreenGui", { Name = "NeonBayHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, player:WaitForChild("PlayerGui"))
	-- swollen eye vignettes
	refs.eyeL = frame(gui, UDim2.new(0, 0, 0, 0), UDim2.new(0.5, 0, 1, 0), Color3.fromRGB(12, 0, 6), 1, 0)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 1) }) }, refs.eyeL)
	refs.eyeR = frame(gui, UDim2.new(0.5, 0, 0, 0), UDim2.new(0.5, 0, 1, 0), Color3.fromRGB(12, 0, 6), 1, 0)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(1, 0) }) }, refs.eyeR)
	refs.letterTop = frame(gui, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.1, 0), Color3.new(0, 0, 0), 0, 1)
	refs.letterBot = frame(gui, UDim2.new(0, 0, 0.9, 0), UDim2.new(1, 0, 0.1, 0), Color3.new(0, 0, 0), 0, 1)

	local fight = frame(gui, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), Color3.new(0, 0, 0), 1, 1)
	refs.fight = fight
	refs.red = fighterPanel(fight, false)
	refs.blue = fighterPanel(fight, true)
	local clock = frame(fight, UDim2.new(0.5, 0, 0, 14), UDim2.new(0, 190, 0, 96), Color3.fromRGB(4, 4, 10), 0.2, 2)
	clock.AnchorPoint = Vector2.new(0.5, 0)
	corner(clock, 8)
	stroke(clock, RED, 2)
	refs.round = label(clock, "ROUND 1 / 3", UDim2.new(0, 0, 0, 6), UDim2.new(1, 0, 0, 20), Color3.fromRGB(150, 165, 185), FONT2)
	refs.clock = label(clock, "1:30", UDim2.new(0, 0, 0, 28), UDim2.new(1, 0, 0, 60), Color3.new(1, 1, 1), FONT)
	refs.comment = label(fight, "", UDim2.new(0.5, 0, 1, -170), UDim2.new(0.7, 0, 0, 30), Color3.new(1, 1, 1), FONT2)
	refs.comment.AnchorPoint = Vector2.new(0.5, 0)
	refs.comment.BackgroundColor3 = Color3.new(0, 0, 0)
	refs.help = label(fight, "LMB jab · RMB cross · Q/E hooks · Z/X uppercuts · +CTRL body · +SHIFT power · SPACE block (tap = parry) · MOUSE slip/duck · C duck · F clinch · V taunt · B camera",
		UDim2.new(0.5, 0, 1, -34), UDim2.new(0.9, 0, 0, 20), Color3.fromRGB(170, 200, 220), FONT2)
	refs.help.AnchorPoint = Vector2.new(0.5, 0)

	-- count + get up
	refs.count = label(gui, "", UDim2.new(0.5, 0, 0.22, 0), UDim2.new(0, 260, 0, 170), Color3.new(1, 1, 1), FONT)
	refs.count.AnchorPoint = Vector2.new(0.5, 0)
	refs.countSub = label(gui, "", UDim2.new(0.5, 0, 0.22, 175), UDim2.new(0.6, 0, 0, 34), Color3.new(1, 1, 1), FONT2)
	refs.countSub.AnchorPoint = Vector2.new(0.5, 0)
	local gb = frame(gui, UDim2.new(0.5, 0, 0.64, 0), UDim2.new(0.42, 0, 0, 34), Color3.new(0, 0, 0), 0.25, 5)
	gb.AnchorPoint = Vector2.new(0.5, 0)
	stroke(gb, CYAN, 2)
	refs.getUp = gb
	refs.getUpZone = frame(gb, UDim2.new(0.375, 0, 0, 0), UDim2.new(0.25, 0, 1, 0), Config.Neon.Green, 0.45, 6)
	refs.getUpMarker = frame(gb, UDim2.new(0, 0, 0, -8), UDim2.new(0, 8, 1, 16), Color3.new(1, 1, 1), 0, 7)
	refs.getUpMeter = bar(gb, UDim2.new(0, 0, 1, 14), UDim2.new(1, 0, 0, 10), YELLOW, false)
	label(gb, "WILL TO CONTINUE  -  press SPACE / BLOCK in the green zone", UDim2.new(0, 0, 1, 28), UDim2.new(1, 0, 0, 18), Color3.fromRGB(180, 190, 200), FONT2)

	-- banner
	refs.banner = label(gui, "", UDim2.new(0.5, 0, 0.3, 0), UDim2.new(0.8, 0, 0, 90), Color3.new(1, 1, 1), TITLE)
	refs.banner.AnchorPoint = Vector2.new(0.5, 0)
	refs.bannerSub = label(gui, "", UDim2.new(0.5, 0, 0.3, 94), UDim2.new(0.6, 0, 0, 30), Color3.fromRGB(220, 220, 230), FONT2)
	refs.bannerSub.AnchorPoint = Vector2.new(0.5, 0)

	-- notifications
	refs.notify = label(gui, "", UDim2.new(0.5, 0, 0, 130), UDim2.new(0.5, 0, 0, 28), Color3.new(1, 1, 1), FONT2)
	refs.notify.AnchorPoint = Vector2.new(0.5, 0)
	refs.pads = label(gui, "", UDim2.new(0.5, 0, 0.75, 0), UDim2.new(0.6, 0, 0, 34), YELLOW, FONT)
	refs.pads.AnchorPoint = Vector2.new(0.5, 0)
end

-- ------------------------------------------------------------------ public: banners, popups, notes
local bannerToken = 0
function HUD.Banner(title, sub, color, t)
	bannerToken += 1
	local tok = bannerToken
	refs.banner.Text = title
	refs.banner.TextColor3 = color or Color3.new(1, 1, 1)
	refs.bannerSub.Text = sub or ""
	refs.banner.TextTransparency, refs.bannerSub.TextTransparency = 0, 0
	refs.banner.Size = UDim2.new(1.1, 0, 0, 110)
	TweenService:Create(refs.banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 90) }):Play()
	task.delay(t or 2.6, function()
		if tok ~= bannerToken then return end
		TweenService:Create(refs.banner, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(refs.bannerSub, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end)
end

local noteToken = 0
function HUD.Notify(text, color)
	noteToken += 1
	local tok = noteToken
	refs.notify.Text = text
	refs.notify.TextColor3 = color or Color3.new(1, 1, 1)
	refs.notify.TextTransparency = 0
	task.delay(3.5, function() if tok == noteToken then refs.notify.TextTransparency = 1 end end)
end

function HUD.Popup(text, color, at: Vector3, size)
	local l = label(gui, text, UDim2.new(0, 0, 0, 0), UDim2.new(0, 360 * (size or 1), 0, 46 * (size or 1)), color or Color3.new(1, 1, 1), FONT)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, l)
	table.insert(popups, { label = l, at = at, t = 1.1 })
end

-- ------------------------------------------------------------------ panels: tale of the tape, corner, result
local function clearPanel()
	if refs.panel then refs.panel:Destroy() refs.panel = nil end
end

local function panel(w, h)
	clearPanel()
	local p = frame(gui, UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0, w, 0, h), Color3.fromRGB(6, 7, 14), 0.08, 10)
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(p, 10)
	stroke(p, RED, 2)
	make("UISizeConstraint", { MaxSize = Vector2.new(w, h) }, p)
	p.Size = UDim2.new(0.94, 0, 0.9, 0)
	refs.panel = p
	return p
end

local STAT_NAMES = { "power", "speed", "engine", "chin", "defense", "footwork", "heart" }

function HUD.Tape(ring)
	local p = panel(1100, 560)
	label(p, "TALE OF THE TAPE", UDim2.new(0, 0, 0, 14), UDim2.new(1, 0, 0, 46), YELLOW, TITLE)
	label(p, "THE PIT  //  " .. (ring:GetAttribute("Rounds") or 3) .. " ROUNDS  //  NEON BAY UNDERGROUND", UDim2.new(0, 0, 0, 62), UDim2.new(1, 0, 0, 20), Color3.fromRGB(150, 165, 185), FONT2)
	local function col(side, x, align, color)
		local nick = ring:GetAttribute(side .. "Nick") or ""
		label(p, (ring:GetAttribute(side .. "Name") or ""):upper(), UDim2.new(x, 0, 0, 96), UDim2.new(0.4, 0, 0, 38), color, FONT, align)
		label(p, (nick ~= "" and ('"' .. nick .. '"') or "") .. "\n" .. (ring:GetAttribute(side .. "Record") or "") .. "  ·  " .. (ring:GetAttribute(side .. "Style") or ""), UDim2.new(x, 0, 0, 136), UDim2.new(0.4, 0, 0, 44), Color3.new(1, 1, 1), FONT2, align)
		for i, n in STAT_NAMES do
			local v = (ring:GetAttribute(side .. "S_" .. n) or 50) / 100
			local b = frame(p, UDim2.new(x, 0, 0, 196 + i * 34), UDim2.new(0.38, 0, 0, 10), Color3.new(0, 0, 0), 0.3, 11)
			local fill = frame(b, UDim2.new(align == Enum.TextXAlignment.Right and 1 - v or 0, 0, 0, 0), UDim2.new(v, 0, 1, 0), color, 0, 12)
			local _ = fill
		end
	end
	col("Red", 0.05, Enum.TextXAlignment.Right, RED)
	col("Blue", 0.57, Enum.TextXAlignment.Left, BLUE)
	label(p, "VS", UDim2.new(0.45, 0, 0, 96), UDim2.new(0.1, 0, 0, 38), Color3.new(1, 1, 1), TITLE)
	for i, n in STAT_NAMES do
		label(p, n:upper(), UDim2.new(0.43, 0, 0, 190 + i * 34), UDim2.new(0.14, 0, 0, 20), Color3.fromRGB(150, 165, 185), FONT2)
	end
	label(p, '"' .. (ring:GetAttribute("Bio") or "") .. '"', UDim2.new(0.05, 0, 1, -64), UDim2.new(0.9, 0, 0, 40), Color3.fromRGB(170, 180, 195), FONT2)
end

function HUD.Corner(ev)
	local p = panel(560, 560)
	p.Position = UDim2.new(1, -24, 0.5, 0)
	p.AnchorPoint = Vector2.new(1, 0.5)
	p.Size = UDim2.new(0.42, 0, 0.82, 0)
	label(p, "CORNER  //  AFTER ROUND " .. ev.round, UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, 30), CYAN, FONT, Enum.TextXAlignment.Left)
	local me, them = ev.me, ev.them
	local rows = {
		{ "Punches landed", me.landed .. " / " .. me.thrown, them.landed .. " / " .. them.thrown },
		{ "Power punches", tostring(me.powerLanded), tostring(them.powerLanded) },
		{ "Body shots", tostring(me.bodyLanded), tostring(them.bodyLanded) },
		{ "Evaded / blocked", me.evaded .. " / " .. me.blocked, them.evaded .. " / " .. them.blocked },
	}
	label(p, "YOU", UDim2.new(0.5, 0, 0, 46), UDim2.new(0.22, 0, 0, 20), RED, FONT)
	label(p, "THEM", UDim2.new(0.74, 0, 0, 46), UDim2.new(0.22, 0, 0, 20), BLUE, FONT)
	for i, r in rows do
		local y = 46 + i * 26
		label(p, r[1], UDim2.new(0, 16, 0, y), UDim2.new(0.45, 0, 0, 20), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
		label(p, r[2], UDim2.new(0.5, 0, 0, y), UDim2.new(0.22, 0, 0, 20), Color3.new(1, 1, 1), FONT2)
		label(p, r[3], UDim2.new(0.74, 0, 0, y), UDim2.new(0.22, 0, 0, 20), Color3.new(1, 1, 1), FONT2)
	end
	local dmg = { { "Cut", ev.cut, RED }, { "Left eye", ev.eyeL, Config.Neon.Purple }, { "Right eye", ev.eyeR, Config.Neon.Purple }, { "Concussion", ev.concussion, YELLOW }, { "Body", ev.ribs, Config.Neon.Orange } }
	label(p, "DAMAGE REPORT", UDim2.new(0, 16, 0, 186), UDim2.new(0.5, 0, 0, 16), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
	for i, d in dmg do
		local y = 186 + i * 22
		label(p, d[1], UDim2.new(0, 16, 0, y), UDim2.new(0.3, 0, 0, 16), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
		local b = frame(p, UDim2.new(0.36, 0, 0, y + 4), UDim2.new(0.58, 0, 0, 8), Color3.new(0, 0, 0), 0.3, 11)
		frame(b, UDim2.new(0, 0, 0, 0), UDim2.new(math.clamp(d[2] or 0, 0, 1), 0, 1, 0), d[3], 0, 12)
	end
	label(p, '<font color="#FFD826">COACH:</font> "' .. ev.advice .. '"', UDim2.new(0, 16, 0, 316), UDim2.new(1, -32, 0, 54), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
	for i, o in ev.options do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local b
		b = button(p, o, UDim2.new(0.03 + col * 0.485, 0, 0, 384 + row * 58), UDim2.new(0.455, 0, 0, 48), CYAN, function()
			Controls.SendCorner(i)
			for _, c in p:GetChildren() do if c:IsA("TextButton") then c.AutoButtonColor = false; c.BackgroundTransparency = 0.6 end end
			b.BackgroundTransparency = 0
			b.BackgroundColor3 = Color3.fromRGB(10, 80, 90)
		end)
	end
	label(p, "Pick one before the bell", UDim2.new(0, 16, 1, -34), UDim2.new(1, -32, 0, 18), Color3.fromRGB(150, 165, 185), FONT2)
end

function HUD.Result(ev)
	local p = panel(1180, 640)
	local mine = (ev.winner == "Red" and player.Character and player.Character:GetAttribute("Corner") == 0) or (ev.winner == "Blue" and player.Character and player.Character:GetAttribute("Corner") == 1)
	label(p, ev.title, UDim2.new(0, 0, 0, 14), UDim2.new(1, 0, 0, 58), ev.winner == "" and Color3.new(1, 1, 1) or (mine and YELLOW or RED), TITLE)
	label(p, ev.method, UDim2.new(0, 0, 0, 74), UDim2.new(1, 0, 0, 26), Color3.new(1, 1, 1), FONT2)
	label(p, "OFFICIAL SCORECARDS", UDim2.new(0.03, 0, 0, 120), UDim2.new(0.4, 0, 0, 18), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
	for i, c in ev.cards do
		local r, b, rounds = 0, 0, ""
		for j = 1, #c.red do r += c.red[j]; b += c.blue[j]; rounds ..= c.red[j] .. "-" .. c.blue[j] .. "  " end
		local y = 120 + i * 40
		label(p, c.name, UDim2.new(0.03, 0, 0, y), UDim2.new(0.25, 0, 0, 22), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
		label(p, (#c.red > 0) and (r .. " - " .. b) or "-", UDim2.new(0.28, 0, 0, y), UDim2.new(0.12, 0, 0, 22), r > b and RED or b > r and BLUE or Color3.new(1, 1, 1), FONT)
		label(p, rounds, UDim2.new(0.03, 0, 0, y + 22), UDim2.new(0.42, 0, 0, 14), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
	end
	local a, bb = ev.red, ev.blue
	local function pct(l, t) return t > 0 and (math.floor(100 * l / t + 0.5) .. "%") or "0%" end
	local stats = {
		{ "", ev.redName:split(" ")[1], ev.blueName:split(" ")[1] },
		{ "Total", a.landed .. "/" .. a.thrown .. " " .. pct(a.landed, a.thrown), bb.landed .. "/" .. bb.thrown .. " " .. pct(bb.landed, bb.thrown) },
		{ "Jabs", a.jabsLanded .. "/" .. a.jabsThrown, bb.jabsLanded .. "/" .. bb.jabsThrown },
		{ "Power", a.powerLanded .. "/" .. a.powerThrown, bb.powerLanded .. "/" .. bb.powerThrown },
		{ "Body / head", a.bodyLanded .. " / " .. a.headLanded, bb.bodyLanded .. " / " .. bb.headLanded },
		{ "Counters", tostring(a.counters), tostring(bb.counters) },
		{ "Knockdowns", tostring(a.knockdowns), tostring(bb.knockdowns) },
		{ "Evaded / blocked", a.evaded .. " / " .. a.blocked, bb.evaded .. " / " .. bb.blocked },
	}
	label(p, "PUNCH STATS", UDim2.new(0.52, 0, 0, 120), UDim2.new(0.4, 0, 0, 18), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
	for i, s in stats do
		local y = 120 + i * 30
		label(p, s[1], UDim2.new(0.52, 0, 0, y), UDim2.new(0.16, 0, 0, 22), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
		label(p, s[2], UDim2.new(0.68, 0, 0, y), UDim2.new(0.14, 0, 0, 22), RED, FONT2)
		label(p, s[3], UDim2.new(0.83, 0, 0, y), UDim2.new(0.14, 0, 0, 22), BLUE, FONT2)
	end
	local myCorner = player.Character and player.Character:GetAttribute("Corner")
	local purse = myCorner == 0 and ev.redPurse or myCorner == 1 and ev.bluePurse or nil
	if purse then
		label(p, "PURSE  $" .. purse .. "   ·   CAREER " .. (player:GetAttribute("Wins") or 0) .. "-" .. (player:GetAttribute("Losses") or 0) .. "  (" .. (player:GetAttribute("KOs") or 0) .. " KO)", UDim2.new(0, 0, 1, -70), UDim2.new(1, 0, 0, 30), YELLOW, FONT)
	end
	label(p, "Returning to the warehouse...", UDim2.new(0, 0, 1, -34), UDim2.new(1, 0, 0, 18), Color3.fromRGB(150, 165, 185), FONT2)
end

-- ------------------------------------------------------------------ per frame
local function ringOfInterest()
	local c = player.Character
	local r = c and c:FindFirstChild("Ring")
	if r and r.Value and c:GetAttribute("Fighter") then return r.Value, true end
	-- spectating: nearest busy ring
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local map = workspace:FindFirstChild("Map")
	if not hrp or not map then return nil end
	local best, bd = nil, 70
	for _, d in map:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("IsRing") and d:GetAttribute("Busy") then
			local cv = d:FindFirstChild("Canvas")
			if cv then
				local dist = (cv.Position - hrp.Position).Magnitude
				if dist < bd then best, bd = d, dist end
			end
		end
	end
	return best, false
end

local lastPhase, lastRing
local function updatePanel(fighter, ring)
	local function fill(pnl, m)
		if not m then return end
		local nick = m:GetAttribute("Nick") or ""
		local side = (m:GetAttribute("Corner") == 0) and "Red" or "Blue"
		pnl.name.Text = (ring:GetAttribute(side .. "Name") or m.Name):upper()
		local n = ring:GetAttribute(side .. "Nick") or nick
		pnl.sub.Text = (n ~= "" and ('"' .. n .. '"  ') or "") .. (ring:GetAttribute(side .. "Record") or "") .. "   " .. (ring:GetAttribute(side .. "Style") or "")
		local dt = 1 / 60
		setBar(pnl.head, (m:GetAttribute("HeadHP") or 100) / 100, (m:GetAttribute("HeadCap") or 100) / 100, dt)
		setBar(pnl.body, (m:GetAttribute("BodyHP") or 100) / 100, 1, dt)
		setBar(pnl.stam, (m:GetAttribute("Stam") or 100) / 110, (m:GetAttribute("StamMax") or 100) / 110, dt)
		local flags = {}
		if (m:GetAttribute("Rocked") or 0) > 0 then table.insert(flags, '<font color="#FF3344">ROCKED</font>') end
		if math.max(m:GetAttribute("I_CutL") or 0, m:GetAttribute("I_CutR") or 0) > 0.3 then table.insert(flags, '<font color="#FF5566">CUT</font>') end
		if (m:GetAttribute("Stam") or 100) < 20 then table.insert(flags, '<font color="#FFD826">GASSED</font>') end
		pnl.flags.Text = table.concat(flags, "  ")
	end
	local rm = ring:FindFirstChild("RedModel")
	local bm = ring:FindFirstChild("BlueModel")
	fill(refs.red, rm and rm.Value)
	fill(refs.blue, bm and bm.Value)
	local _ = fighter
end

function HUD.Start(controls)
	Controls = controls
	build()
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		-- popups
		for i = #popups, 1, -1 do
			local p = popups[i]
			p.t -= dt
			p.at += Vector3.new(0, dt * 1.1, 0)
			local sp, on = cam:WorldToViewportPoint(p.at)
			p.label.Visible = on
			p.label.Position = UDim2.new(0, sp.X, 0, sp.Y)
			p.label.TextTransparency = 1 - math.clamp(p.t * 2, 0, 1)
			if p.t <= 0 then p.label:Destroy(); table.remove(popups, i) end
		end
		local ring, mine = ringOfInterest()
		local c = player.Character
		refs.fight.Visible = ring ~= nil
		refs.help.Visible = mine == true and (ring and ring:GetAttribute("Phase") == "Fight")
		-- PvP pad prompt
		local padText = ""
		local map = workspace:FindFirstChild("Map")
		if map and not mine then
			for _, d in map:GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("IsRing") and not d:GetAttribute("Busy") then
					local a, b = d:GetAttribute("PadRed") or "", d:GetAttribute("PadBlue") or ""
					local me = player.DisplayName
					if a == me or b == me then
						local cd = d:GetAttribute("Countdown") or -1
						padText = (a ~= "" and b ~= "") and ("PvP FIGHT STARTS IN " .. math.ceil(cd)) or "WAITING FOR AN OPPONENT ON THE OTHER CORNER PAD..."
					end
				end
			end
		end
		refs.pads.Text = padText
		-- swollen eyes / letterbox
		local eyeL = mine and c and math.clamp(((c:GetAttribute("I_EyeL") or 0) - 0.35) * 1.4, 0, 1) or 0
		local eyeR = mine and c and math.clamp(((c:GetAttribute("I_EyeR") or 0) - 0.35) * 1.4, 0, 1) or 0
		refs.eyeL.BackgroundTransparency = 1 - eyeL * 0.95
		refs.eyeR.BackgroundTransparency = 1 - eyeR * 0.95
		local phase = ring and ring:GetAttribute("Phase") or ""
		local cine = phase == "Intro" or phase == "KO"
		refs.letterTop.Visible, refs.letterBot.Visible = cine and mine == true, cine and mine == true
		refs.count.Text, refs.countSub.Text = "", ""
		refs.getUp.Visible = false
		if not ring then
			if refs.panel and lastPhase ~= "Shop" then clearPanel() end
			lastPhase, lastRing = nil, nil
			return
		end
		updatePanel(c, ring)
		refs.round.Text = "ROUND " .. math.max(1, ring:GetAttribute("Round") or 1) .. " / " .. (ring:GetAttribute("Rounds") or 3)
		local clock = ring:GetAttribute("Clock") or 0
		refs.clock.Text = Util.formatTime(clock)
		refs.clock.TextColor3 = (clock < 10 and phase == "Fight") and RED:Lerp(Color3.new(1, 1, 1), (math.sin(os.clock() * 8) + 1) / 2) or Color3.new(1, 1, 1)
		local ct = ring:GetAttribute("CommentT") or -99
		local age = workspace:GetServerTimeNow() - ct
		refs.comment.Text = age < 3.5 and ('<font color="#FFD826">MIC MALONE:</font>  ' .. (ring:GetAttribute("Comment") or "")) or ""
		refs.comment.BackgroundTransparency = age < 3.5 and 0.5 or 1
		if phase == "Knockdown" then
			local n = ring:GetAttribute("Count") or 0
			refs.count.Text = n > 0 and tostring(n) or ""
			refs.count.TextColor3 = n >= 8 and RED or Color3.new(1, 1, 1)
			local downed = ring:GetAttribute("Downed") or ""
			local myCorner = c and c:GetAttribute("Corner")
			local meDown = mine and ((downed == "Red" and myCorner == 0) or (downed == "Blue" and myCorner == 1))
			refs.countSub.Text = meDown and "GET UP!" or (downed ~= "" and ((ring:GetAttribute(downed .. "Name") or ""):upper() .. " IS DOWN") or "HE'S UP!")
			if meDown and n >= 1 and Controls then
				local g = Controls.getUp
				refs.getUp.Visible = true
				refs.getUpZone.Size = UDim2.new(g.zone, 0, 1, 0)
				refs.getUpZone.Position = UDim2.new(0.5 - g.zone / 2, 0, 0, 0)
				refs.getUpMarker.Position = UDim2.new(g.marker, -4, 0, -8)
				setBar(refs.getUpMeter, g.meter or 0, 1, dt)
			end
		end
		if phase ~= lastPhase or ring ~= lastRing then
			if phase == "Intro" then HUD.Tape(ring)
			elseif phase ~= "Corner" and phase ~= "Result" and phase ~= "KO" then clearPanel() end
			lastPhase, lastRing = phase, ring
		end
	end)
end

return HUD
