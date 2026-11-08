--[[
	Lobby UI: record/cash bar, FIGHTER creator with a live 3D preview, CAREER ladder vs the Pit's ranked CPU
	fighters, TRAINING camp and MEDICAL. The creator opens automatically the first time you join.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local RigDef = require(Shared.RigDef)
local Appearance = require(Shared.Appearance)
local Util = require(Shared.Util)
local Remotes = ReplicatedStorage:WaitForChild("NeonBayRemotes")
local RequestFn = Remotes:WaitForChild("Request")

local HUD = require(script.Parent.HUD)
local FX = require(script.Parent.FX)

local Menus = {}
local player = Players.LocalPlayer
local make, frame, label, button, stroke, corner = HUD.Make, HUD.Frame, HUD.Label, HUD.Button, HUD.Stroke, HUD.Corner
local CYAN, YELLOW, RED = Config.Neon.Cyan, Config.Neon.Yellow, Color3.fromRGB(242, 51, 64)
local FONT, FONT2 = Enum.Font.GothamBlack, Enum.Font.GothamBold

local gui, topBar, panelRoot
local draft
local preview, previewBones
local Controls

local function request(kind, arg)
	local ok, a, b = pcall(function() return RequestFn:InvokeServer(kind, arg) end)
	if not ok then return false, "Network error" end
	return a, b
end

local function inFight()
	local c = player.Character
	return c and c:GetAttribute("Fighter") == true
end

-- ------------------------------------------------------------------ live preview rig (local only)
local function destroyPreview()
	if preview then preview:Destroy() preview = nil end
end

local function studioCF()
	local map = workspace:FindFirstChild("Map")
	local spot = map and map:FindFirstChild("CreatorStudio", true)
	if spot then return spot.CFrame * CFrame.new(0, spot.Size.Y / 2, 0) end
	local c = player.Character
	return c and c:GetPivot() * CFrame.new(0, -3, -12) or CFrame.new(0, 0, 0)
end

local function buildPreview()
	destroyPreview()
	local p = Util.deepCopy(draft)
	p.outfit = "boxer"
	local offsets, d = RigDef.Offsets(p)
	local model = Instance.new("Model")
	model.Name = "CreatorPreview"
	local base = studioCF()
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = RigDef.RootSize
	hrp.Transparency = 1
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.CFrame = CFrame.new(base.Position + Vector3.new(0, RigDef.HipHeightM * d.scale, 0)) * base.Rotation
	hrp.Parent = model
	local bones = { HumanoidRootPart = hrp }
	for _, def in RigDef.Bones do
		local part = Instance.new("Part")
		part.Name = def.name
		part.Size = Vector3.new(0.15, 0.15, 0.15)
		part.Transparency = 1
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
		part.CFrame = bones[def.parent].CFrame * CFrame.new(offsets[def.name])
		local m = Instance.new("Motor6D")
		m.Name = def.motor
		m.Part0 = bones[def.parent]
		m.Part1 = part
		m.C0 = CFrame.new(offsets[def.name])
		m.Parent = part
		part.Parent = model
		bones[def.name] = part
	end
	Appearance.Apply(model, bones, p)
	model:SetAttribute("Scale", d.scale)
	model:SetAttribute("Southpaw", p.southpaw == true)
	model:SetAttribute("State", "Idle")
	model.Parent = workspace
	CollectionService:AddTag(model, "NBRig")
	preview, previewBones = model, bones
end

local spin = 0
local zoomFace = false
RunService.RenderStepped:Connect(function(dt)
	if not preview then return end
	local cam = workspace.CurrentCamera
	local hrp = previewBones.HumanoidRootPart
	local head = previewBones.Head
	spin += dt * 0.25
	local center = hrp.Position
	local target = zoomFace and head.Position + Vector3.new(0, 0.42, 0) or center + Vector3.new(0, 0.6, 0)
	local dist = zoomFace and 3.4 or 11
	local look = hrp.CFrame.LookVector
	local ang = math.sin(spin) * 0.6
	local dir = (CFrame.Angles(0, ang, 0) * look)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(target + dir * dist + Vector3.new(0, zoomFace and 0.2 or 1, 0), target), 1 - math.exp(-6 * dt))
	cam.FieldOfView = 40
end)

-- ------------------------------------------------------------------ panels
local function clearPanel()
	if panelRoot then panelRoot:Destroy() panelRoot = nil end
	Controls.uiOpen = false
end

local function openPanel(title, w, h, side)
	clearPanel()
	Controls.uiOpen = true
	local p = frame(gui, UDim2.new(side and 0 or 0.5, side and 18 or 0, 0.5, 0), UDim2.new(0, w, 0, h), Color3.fromRGB(6, 7, 14), 0.06, 20)
	p.AnchorPoint = Vector2.new(side and 0 or 0.5, 0.5)
	corner(p, 10)
	stroke(p, CYAN, 2)
	make("UISizeConstraint", { MaxSize = Vector2.new(w, h), MinSize = Vector2.new(math.min(w, 300), 200) }, p)
	p.Size = UDim2.new(side and 0.46 or 0.92, 0, 0.88, 0)
	label(p, title, UDim2.new(0, 16, 0, 10), UDim2.new(1, -150, 0, 30), CYAN, FONT, Enum.TextXAlignment.Left)
	button(p, "CLOSE", UDim2.new(1, -120, 0, 10), UDim2.new(0, 104, 0, 32), RED, function()
		if title:find("FIGHTER") then
			destroyPreview()
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
		clearPanel()
	end)
	panelRoot = p
	local body = make("ScrollingFrame", { Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 1, -62), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 21 }, p)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	return body
end

local order = 0
local function row(parent, h)
	order += 1
	local r = frame(parent, UDim2.new(0, 0, 0, 0), UDim2.new(1, -8, 0, h or 40), Color3.fromRGB(14, 16, 26), 0.2, 21)
	r.LayoutOrder = order
	corner(r, 6)
	return r
end

local function picker(parent, title, get, set, count, nameOf, rebuild)
	local r = row(parent, 40)
	label(r, title, UDim2.new(0, 10, 0, 6), UDim2.new(0.35, 0, 0, 28), Color3.fromRGB(170, 185, 205), FONT2, Enum.TextXAlignment.Left)
	local val = label(r, nameOf(get()), UDim2.new(0.45, 0, 0, 6), UDim2.new(0.38, 0, 0, 28), Color3.new(1, 1, 1), FONT2)
	local function change(d)
		local v = get() + d
		local lo = count[1]
		local hi = count[2]
		if v < lo then v = hi elseif v > hi then v = lo end
		set(v)
		val.Text = nameOf(v)
		FX.Play("ui_click")
		if rebuild ~= false then buildPreview() end
	end
	button(r, "<", UDim2.new(0.37, 0, 0, 4), UDim2.new(0, 36, 0, 32), CYAN, function() change(-1) end)
	button(r, ">", UDim2.new(0.85, 0, 0, 4), UDim2.new(0, 36, 0, 32), CYAN, function() change(1) end)
end

local function slider(parent, title, get, set, lo, hi, steps, fmt)
	local step = (hi - lo) / steps
	picker(parent, title, function() return math.floor((get() - lo) / step + 0.5) end, function(i) set(lo + i * step) end, { 0, steps }, function(i) return fmt(lo + i * step) end)
end

local function textField(parent, title, get, set)
	local r = row(parent, 44)
	label(r, title, UDim2.new(0, 10, 0, 8), UDim2.new(0.35, 0, 0, 28), Color3.fromRGB(170, 185, 205), FONT2, Enum.TextXAlignment.Left)
	local tb = make("TextBox", { Text = get(), PlaceholderText = "type here", Position = UDim2.new(0.37, 0, 0, 6), Size = UDim2.new(0.6, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(4, 4, 8), TextColor3 = Color3.new(1, 1, 1), Font = FONT2, TextScaled = true, ClearTextOnFocus = false, ZIndex = 22 }, r)
	corner(tb, 6)
	stroke(tb, Color3.fromRGB(60, 70, 90), 1)
	tb.FocusLost:Connect(function() set(string.sub(tb.Text, 1, 18)) end)
end

function Menus.OpenCreator()
	if inFight() then return end
	draft = draft or Util.deepCopy(Config.DefaultProfile)
	local ok, d = request("profile")
	if ok and type(d) == "table" and d.look then
		for k, v in d.look do draft[k] = v end
	end
	if draft.name == "" then draft.name = player.DisplayName end
	local body = openPanel("FIGHTER  //  BUILD YOUR BOXER", 560, 760, true)
	buildPreview()
	local function G(k) return function() return draft[k] end end
	local function S(k) return function(v) draft[k] = v end end
	local tabs = row(body, 40)
	button(tabs, "FULL BODY", UDim2.new(0, 6, 0, 4), UDim2.new(0.48, -8, 0, 32), YELLOW, function() zoomFace = false end)
	button(tabs, "FACE CLOSE-UP", UDim2.new(0.5, 2, 0, 4), UDim2.new(0.48, -8, 0, 32), YELLOW, function() zoomFace = true end)
	textField(body, "NAME", G("name"), S("name"))
	textField(body, "RING NAME", G("nickname"), S("nickname"))
	picker(body, "BODY TYPE", function() return draft.female and 2 or 1 end, function(v) draft.female = v == 2 end, { 1, 2 }, function(v) return v == 2 and "Feminine" or "Masculine" end)
	picker(body, "SKIN", G("skin"), S("skin"), { 1, #Config.SkinTones }, function(v) return v == Config.ChromeSkin and "Full Chrome" or ("Tone " .. v) end)
	picker(body, "HAIR", G("hair"), S("hair"), { 1, #Config.HairNames }, function(v) return Config.HairNames[v] end)
	picker(body, "HAIR COLOR", G("hairColor"), S("hairColor"), { 1, #Config.HairColors }, function(v) return Config.HairColorNames[v] end)
	picker(body, "FACIAL HAIR", G("beard"), S("beard"), { 1, #Config.BeardNames }, function(v) return Config.BeardNames[v] end)
	picker(body, "BEARD COLOR", G("beardColor"), S("beardColor"), { 0, #Config.HairColors }, function(v) return v == 0 and "Match hair" or Config.HairColorNames[v] end)
	picker(body, "EYEBROWS", G("brows"), S("brows"), { 1, #Config.BrowNames }, function(v) return Config.BrowNames[v] end)
	picker(body, "CYBER-OPTICS", G("eye"), S("eye"), { 1, #Config.EyeColors }, function(v) return v == #Config.EyeColors and "Natural" or ("Glow " .. v) end)
	slider(body, "JAWLINE", G("jaw"), S("jaw"), 0, 1, 4, function(v) return v < 0.35 and "Narrow" or v < 0.7 and "Average" or "Square" end)
	slider(body, "BUILD", G("bulk"), S("bulk"), 0.85, 1.35, 5, function(v) return v < 0.95 and "Lean" or v < 1.15 and "Athletic" or "Heavy" end)
	slider(body, "MUSCLE", G("muscle"), S("muscle"), 0, 1, 4, function(v) return v < 0.3 and "Soft" or v < 0.65 and "Athletic" or "Shredded" end)
	slider(body, "HEIGHT", G("height"), S("height"), 0.92, 1.08, 4, function(v) return math.floor(178 * v) .. " cm" end)
	picker(body, "TRUNKS", G("trunks"), S("trunks"), { 1, #Config.TrunkColors }, function(v) return Config.TrunkNames[v] end)
	picker(body, "GLOVES", G("gloves"), S("gloves"), { 1, #Config.GloveColors }, function(v) return Config.GloveNames[v] end)
	picker(body, "NEON ACCENT", G("accent"), S("accent"), { 1, 9 }, function(v) return "Glow " .. v end)
	picker(body, "STANCE", function() return draft.southpaw and 2 or 1 end, function(v) draft.southpaw = v == 2 end, { 1, 2 }, function(v) return v == 2 and "Southpaw" or "Orthodox" end)
	picker(body, "FACE TATTOO", function() return draft.tattoo and 2 or 1 end, function(v) draft.tattoo = v == 2 end, { 1, 2 }, function(v) return v == 2 and "Glowing" or "None" end)
	local save = row(body, 54)
	button(save, "SAVE & STEP INTO THE PIT", UDim2.new(0, 6, 0, 6), UDim2.new(1, -12, 0, 42), YELLOW, function()
		local ok2, err = request("saveLook", draft)
		if ok2 then
			HUD.Notify("Fighter saved", Config.Neon.Green)
			FX.Play("ui_good")
			destroyPreview()
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			clearPanel()
		else
			HUD.Notify(err or "Couldn't save", RED)
		end
	end)
end

function Menus.OpenCareer()
	if inFight() then return end
	local body = openPanel("CAREER  //  THE PIT RANKINGS", 820, 700, false)
	local rank = player:GetAttribute("Rank") or 0
	for i = #Config.Roster, 1, -1 do
		local f = Config.Roster[i]
		local r = row(body, 74)
		local beaten = i <= rank
		local nextUp = i == rank + 1
		if nextUp then r.BackgroundColor3 = Color3.fromRGB(60, 10, 18) end
		label(r, i == #Config.Roster and "C" or ("#" .. (#Config.Roster - i + 1)), UDim2.new(0, 8, 0, 14), UDim2.new(0, 56, 0, 46), i == #Config.Roster and YELLOW or Color3.new(1, 1, 1), FONT)
		label(r, f.name .. '  <font color="#FFD826">"' .. f.nick .. '"</font>', UDim2.new(0, 72, 0, 6), UDim2.new(0.58, 0, 0, 26), beaten and Color3.fromRGB(140, 150, 165) or Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
		label(r, string.format("%d-%d (%d KO)  ·  %s%s  ·  %d rounds  ·  $%d", f.w, f.l, f.ko, Config.StyleNames[f.style], f.southpaw and "  ·  southpaw" or "", f.rounds, f.purse), UDim2.new(0, 72, 0, 32), UDim2.new(0.62, 0, 0, 16), Color3.fromRGB(150, 165, 185), FONT2, Enum.TextXAlignment.Left)
		label(r, f.bio, UDim2.new(0, 72, 0, 50), UDim2.new(0.62, 0, 0, 16), Color3.fromRGB(120, 130, 150), FONT2, Enum.TextXAlignment.Left)
		if nextUp then
			button(r, "FIGHT", UDim2.new(1, -170, 0, 16), UDim2.new(0, 160, 0, 42), YELLOW, function()
				local ok, err = request("career")
				if ok then clearPanel() else HUD.Notify(err or "Can't start", RED) end
			end)
		elseif beaten then
			button(r, "REMATCH", UDim2.new(1, -170, 0, 16), UDim2.new(0, 160, 0, 42), CYAN, function()
				local ok, err = request("exhibition", i)
				if ok then clearPanel() else HUD.Notify(err or "Can't start", RED) end
			end)
		else
			label(r, "LOCKED", UDim2.new(1, -170, 0, 22), UDim2.new(0, 160, 0, 28), Color3.fromRGB(100, 105, 120), FONT)
		end
	end
	local r = row(body, 40)
	label(r, "PvP: two players stand on a ring's RED and BLUE corner pads to start a fight.", UDim2.new(0, 10, 0, 6), UDim2.new(1, -20, 0, 28), Color3.fromRGB(170, 185, 205), FONT2, Enum.TextXAlignment.Left)
end

function Menus.OpenTraining()
	if inFight() then return end
	local body = openPanel("TRAINING CAMP  //  COACH MA RUIZ", 760, 560, false)
	for _, t in Config.Training do
		local r = row(body, 62)
		local lv = player:GetAttribute("Train_" .. t.key) or 0
		label(r, t.name, UDim2.new(0, 10, 0, 6), UDim2.new(0.55, 0, 0, 26), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
		for i = 1, Config.TrainMax do
			frame(r, UDim2.new(0, 10 + (i - 1) * 30, 0, 38), UDim2.new(0, 24, 0, 12), i <= lv and CYAN or Color3.new(0, 0, 0), i <= lv and 0 or 0.4, 22)
		end
		if lv < Config.TrainMax then
			button(r, "TRAIN  $" .. Config.TrainCost(lv), UDim2.new(1, -210, 0, 10), UDim2.new(0, 200, 0, 42), YELLOW, function()
				local ok, err = request("train", t.key)
				if ok then FX.Play("ui_good"); task.wait(0.15); Menus.OpenTraining() else HUD.Notify(err or "Can't train", RED) end
			end)
		else
			label(r, "MAXED", UDim2.new(1, -210, 0, 14), UDim2.new(0, 200, 0, 30), YELLOW, FONT)
		end
	end
end

function Menus.OpenMedical()
	if inFight() then return end
	local body = openPanel("MEDICAL  //  OLD TOMAS THE CUTMAN", 640, 360, false)
	local r = row(body, 60)
	local inj = player:GetAttribute("Injured") or 0
	label(r, inj > 0.05 and string.format("You're carrying damage from your last fight (%d%%). It shows on your face and you'll start the next fight hurt.", math.floor(inj * 100)) or "You're fight-ready.", UDim2.new(0, 10, 0, 6), UDim2.new(1, -20, 0, 48), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
	if inj > 0.05 then
		local r2 = row(body, 56)
		button(r2, "STITCH, ICE & PATCH ME UP  ($200)", UDim2.new(0, 6, 0, 6), UDim2.new(1, -12, 0, 44), YELLOW, function()
			local ok, err = request("heal")
			if ok then HUD.Notify("Good as new. Almost.", Config.Neon.Green); clearPanel() else HUD.Notify(err or "Can't heal", RED) end
		end)
	end
end

-- ------------------------------------------------------------------ top bar
local function buildTopBar()
	topBar = frame(gui, UDim2.new(0, 18, 0, 64), UDim2.new(0, 260, 0, 230), Color3.fromRGB(6, 7, 14), 0.2, 15)
	corner(topBar, 10)
	stroke(topBar, Color3.fromRGB(255, 38, 191), 1.5)
	make("UISizeConstraint", { MaxSize = Vector2.new(260, 230) }, topBar)
	local title = label(topBar, "THE PIT", UDim2.new(0, 10, 0, 6), UDim2.new(1, -20, 0, 30), Config.Neon.Magenta, Enum.Font.Michroma, Enum.TextXAlignment.Left)
	local stats = label(topBar, "", UDim2.new(0, 10, 0, 38), UDim2.new(1, -20, 0, 36), Color3.new(1, 1, 1), FONT2, Enum.TextXAlignment.Left)
	local y = 80
	for _, b in { { "FIGHTER", Menus.OpenCreator }, { "CAREER", Menus.OpenCareer }, { "TRAINING", Menus.OpenTraining }, { "MEDICAL", Menus.OpenMedical } } do
		button(topBar, b[1], UDim2.new(0, 10, 0, y), UDim2.new(1, -20, 0, 32), CYAN, b[2])
		y += 36
	end
	local _ = title
	RunService.RenderStepped:Connect(function()
		topBar.Visible = not inFight()
		stats.Text = string.format("$%d   ·   %d-%d-%d  (%d KO)\nRank: %s", player:GetAttribute("Cash") or 0, player:GetAttribute("Wins") or 0, player:GetAttribute("Losses") or 0, player:GetAttribute("Draws") or 0, player:GetAttribute("KOs") or 0,
			(player:GetAttribute("Rank") or 0) >= #Config.Roster and "UNDISPUTED CHAMPION" or ("#" .. (#Config.Roster - (player:GetAttribute("Rank") or 0) + 1) .. " contender"))
		if inFight() and panelRoot then clearPanel(); destroyPreview() end
	end)
end

function Menus.Start(controls)
	Controls = controls
	gui = make("ScreenGui", { Name = "NeonBayMenus", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 8 }, player:WaitForChild("PlayerGui"))
	buildTopBar()
	task.delay(2.5, function()
		if not player:GetAttribute("Created") then
			Menus.OpenCreator()
			HUD.Banner("WELCOME TO THE PIT", "Build your boxer, then climb the rankings", Config.Neon.Magenta, 4)
		end
	end)
end

return Menus
