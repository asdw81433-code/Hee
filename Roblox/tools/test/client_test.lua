local TOUCH = TOUCH_MODE == true
local RS = game:GetService("ReplicatedStorage")
mountModule(RS, "BrawlConfig", "shared/BrawlConfig.lua")
mountModule(RS, "BrawlAnim", "shared/BrawlAnim.lua")
local Config = require(RS.BrawlConfig)
local rf = Instance.new("Folder")
rf.Name = "BrawlRemotes"
for _, n in ipairs({ "Action", "Fx", "Knock", "Ragdoll", "Notify" }) do
	local e = Instance.new("RemoteEvent")
	e.Name = n
	e.Parent = rf
end
rf.Parent = RS
local st = Instance.new("Folder")
st.Name = "BrawlState"
local ph = Instance.new("StringValue") ph.Name = "Phase" ph.Value = "fight" ph.Parent = st
local re = Instance.new("NumberValue") re.Name = "RoundEnd" re.Value = 1000 + 150 re.Parent = st
local sc = Instance.new("Folder") sc.Name = "Scores" sc.Parent = st
for i = 1, 4 do
	local v = Instance.new("IntValue") v.Name = "S" .. i v.Value = i * 2 v:SetAttribute("DisplayName", "นักเลง" .. i) v.Parent = sc
end
st.Parent = RS
local Players = game:GetService("Players")
local lp = Instance.new("Player")
lp.Name = "Me"
local pg = Instance.new("PlayerGui") pg.Name = "PlayerGui" pg.Parent = lp
local ps = Instance.new("PlayerScripts") ps.Name = "PlayerScripts" ps.Parent = lp
lp.Parent = Players
rawget(Players, "__props").LocalPlayer = lp
local UIS = game:GetService("UserInputService")
rawget(UIS, "__props").TouchEnabled = TOUCH
rawget(UIS, "__props").KeyboardEnabled = not TOUCH
-- build characters with the real CharacterBuilder
local cbm = mountModule(RS, "CBTest", "server/CharacterBuilder.lua")
local CB = require(cbm)
local fighters = Instance.new("Folder") fighters.Name = "Fighters" fighters.Parent = workspace
local chars = {}
for i = 1, 3 do
	local m = CB.build(i == 1 and CB.playerLook(1) or CB.randomLook(Random.new()), "P" .. i, i == 1 and lp or nil)
	m:PivotTo(CFrame.new((i - 1) * 3.5, 3, 0) * CFrame.Angles(0, (i == 1) and math.pi / 2 or -math.pi / 2, 0))
	m.Parent = fighters
	m:SetAttribute("Super", 0)
	m:SetAttribute("ActN", 0)
	local att = Instance.new("Attachment") att.Name = "PushAtt" att.Parent = m.HumanoidRootPart
	chars[i] = m
end
lp.Character = chars[1]
-- a weapon on a pad
local wf = Instance.new("Folder") wf.Name = "BrawlWeapons" wf.Parent = workspace
local wm = Instance.new("Model") wm.Name = "W_pan"
local grip = Instance.new("Part") grip.Name = "Grip" grip.Anchored = true grip.CFrame = CFrame.new(2, 1.3, -3) grip.Parent = wm
wm.PrimaryPart = grip wm:SetAttribute("OnPad", true) wm:SetAttribute("WeaponId", "pan") wm.Parent = wf

local main = mountModule(ps, "BrawlClient", "client/init.client.lua", "LocalScript")
for _, n in ipairs({ "Animator", "Effects", "Hud", "Controls" }) do mountModule(main, n, "client/" .. n .. ".lua") end
task.spawn(loadScript(main))
local function frames(n) for _ = 1, n do simStep(1 / 60) end end
frames(30)
local A = require(main.Animator)
-- every clip on another character
local n = 0
for name in pairs(require(RS.BrawlAnim).Clips) do
	n = n + 1
	chars[2]:SetAttribute("Act", name)
	chars[2]:SetAttribute("ActN", n)
	frames(8)
end
-- states
chars[2]:SetAttribute("Dizzy", true) frames(20) chars[2]:SetAttribute("Dizzy", false)
chars[2]:SetAttribute("Block", true) frames(10) chars[2]:SetAttribute("Block", false)
chars[3]:SetAttribute("Weapon", "pan") chars[3]:SetAttribute("WeaponUses", 3) frames(10)
chars[1]:SetAttribute("Weapon", "fish") chars[1]:SetAttribute("WeaponUses", 999) frames(5)
chars[2]:SetAttribute("Ragdoll", true) frames(10) chars[2]:SetAttribute("Ragdoll", false)
chars[3].HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(10, -30, 0) frames(10)
chars[3].HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(12, 0, 0) frames(30)
-- server events
local fx = rf.Fx.OnClientEvent
local head = chars[1].Head.Position
fx:Fire("hit", { pos = head, dir = Vector3.new(1, 0, 0), power = 14, word = "ปั้ก!", crit = true, blood = 25, teeth = 2, attacker = chars[2], victim = chars[1], sound = "heavy", big = true })
fx:Fire("hit", { pos = head, dir = Vector3.new(-1, 0, 0), power = 8, word = "ผัวะ!", blood = 8, teeth = 0, attacker = chars[1], victim = chars[2], sound = "hit" })
fx:Fire("hit", { pos = head, dir = Vector3.new(0, -1, 0), power = 9, word = "โครม!", blood = 6, teeth = 0, victim = chars[3], sound = "thud", impact = true })
fx:Fire("block", { pos = head, word = "กัน!", attacker = chars[2], victim = chars[1] })
fx:Fire("block", { pos = head, word = "การ์ดแตก!!", big = true, attacker = chars[1], victim = chars[2] })
fx:Fire("word", { pos = head, word = "จับได้!" })
fx:Fire("dizzy", { victim = chars[2], time = 2 })
fx:Fire("super", { char = chars[1], name = "Me" })
fx:Fire("taunt", { char = chars[2] })
fx:Fire("break", { pos = head, glass = true })
fx:Fire("break", { pos = head, glass = false })
fx:Fire("melon", { pos = head })
fx:Fire("pool", { pos = chars[3].Torso.Position })
frames(200)
local nt = rf.Notify.OnClientEvent
nt:Fire("ko", { victim = "P2", killer = "Me", msg = "P2 หลับปุ๋ย", victimModel = chars[2], killerModel = chars[1], streak = "🔥 ร้อนแรง!" })
nt:Fire("ko", { victim = "Me", killer = "P3", msg = "Me บินไปดาวอังคาร", victimModel = chars[1], killerModel = chars[3] })
nt:Fire("ko", { victim = "P3", msg = "P3 ตกขอบโลก", victimModel = chars[3] })
nt:Fire("round", { king = "Me", kos = 5, potato = "P2", deaths = 4, dancer = "P3", taunts = 3, brute = "Me", dmg = 230 })
nt:Fire("newround", {})
frames(120)
rf.Knock.OnClientEvent:Fire(Vector3.new(20, 0, 5), 0.2)
rf.Ragdoll.OnClientEvent:Fire(true)
rf.Ragdoll.OnClientEvent:Fire(false)
frames(30)
-- inputs
chars[1]:SetAttribute("Weapon", nil)
local function key(kc) UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = kc }, false) frames(40) UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = kc }, false) end
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
frames(5)
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false) -- buffered
frames(40)
key(Enum.KeyCode.E)
key(Enum.KeyCode.R)
key(Enum.KeyCode.T)
chars[1]:SetAttribute("Super", 100)
key(Enum.KeyCode.F)
key(Enum.KeyCode.Q)
chars[1]:SetAttribute("Weapon", "pan")
key(Enum.KeyCode.R)
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }, false)
frames(40)
chars[2]:SetAttribute("Ragdoll", true)
key(Enum.KeyCode.E) -- stomp prediction
if TOUCH then
	local tg = pg:FindFirstChild("BrawlTouch")
	print("touch gui:", tg ~= nil)
	local holder = tg and tg:GetChildren()[1]
	for _, b in ipairs(holder and holder:GetChildren() or {}) do
		b.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch })
		frames(30)
		b.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch })
		frames(5)
	end
end
frames(300)
local sent = {}
for _, e in ipairs(FXLOG) do if e[1] == "server" then sent[#sent + 1] = tostring(e[3]) end end
print("actions sent to server:", table.concat(sent, ","))
local fxCount = 0
for _ in ipairs(workspace.BrawlFX:GetChildren()) do fxCount = fxCount + 1 end
print("fx parts alive:", fxCount)
print("hud:", pg:FindFirstChild("BrawlHUD") ~= nil)
print("ERRORS:", #ERRORS)
