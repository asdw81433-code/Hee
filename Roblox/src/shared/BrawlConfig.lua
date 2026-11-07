-- ============================================================
--  ALLEY BRAWL  -  ตั้งค่าเกมทั้งหมดอยู่ไฟล์นี้
--  (ReplicatedStorage > BrawlConfig)
--  แก้ตัวเลขตรงนี้ได้เลย ไม่ต้องแตะสคริปต์อื่น
-- ============================================================
local C = {}

C.GameName = "ALLEY BRAWL"

-- ===== กติกา =====
C.BotCount = 5            -- จำนวนนักเลง AI (0 = ไม่มีบอท)
C.BotsWhenPlayers = 3     -- ถ้ามีผู้เล่นจริง >= 4 คน ลดบอทเหลือเท่านี้
C.BotSkill = 0.5          -- 0 = อ่อนปวกเปียก, 1 = โหดมาก
C.RoundTime = 180         -- วินาทีต่อรอบ
C.ResultTime = 8          -- โชว์ผลจบรอบกี่วินาที
C.RespawnTime = 4
C.CorpseTime = 14         -- ร่างที่ล้มจะนอนอยู่กี่วินาที
C.MaxHealth = 100
C.WalkSpeed = 18
C.JumpPower = 52
C.SpawnProtect = 2.0      -- อมตะหลังเกิดกี่วินาที
C.GetUpProtect = 0.7      -- อมตะตอนลุกจากพื้น
C.RegenDelay = 6          -- ไม่โดนตีกี่วินาทีถึงเริ่มฟื้นเลือด
C.RegenRate = 3           -- เลือดต่อวินาที
C.SuperMax = 100
C.ComboWindow = 0.75      -- เวลาต่อคอมโบหมัด
C.DizzyAt = 60            -- สะสมอาการมึนถึงเท่านี้ = มึนหัว
C.DizzyTime = 2.4
C.ImpactDamage = 1        -- ดาเมจตอนร่างลอยไปกระแทกพื้น/กำแพง (ตัวคูณ)

-- ===== ความโหด =====
-- Blood: 0 = ไม่มีเลือด (เป็นดาวการ์ตูนแทน), 0.5 = น้อย, 1 = ปกติ, 2 = สาดกระจาย
-- ** ถ้าจะเปิดเกมสาธารณะ ให้กรอกแบบสอบถาม Maturity & Compliance ใน Creator Hub ตามจริง **
C.Blood = 1
C.Teeth = true            -- ฟันกระเด็น
C.FaceDamage = true       -- หน้าเลือดออก ตาเขียว
C.BloodColor = Color3.fromRGB(150, 8, 12)
C.Wounds = true           -- แผลเลือดติดตามตัวตรงจุดที่โดน
-- ===== แขนขาขาด (สไตล์ gore sandbox) =====
-- Dismember: true = แขน/ขา/หัวหลุดได้เมื่อโดนหนักๆ
-- GoreLevel: 0 = หลุดแบบบล็อกคลาสสิก (ไม่มีเนื้อแดง), 1 = มีตอแดง + กระดูก + เลือดพุ่ง
-- ** Roblox ไม่อนุญาตเนื้อหาชำแหละอวัยวะ (dismemberment/gore) ในเกมสาธารณะ
--    ถ้าจะ Publish ให้คนอื่นเล่น ให้ตั้ง GoreLevel = 0 หรือ Dismember = false **
C.Dismember = true
C.GoreLevel = 1
C.LimbHP = 38             -- ดาเมจสะสมที่แขน/ขาก่อนหลุด
C.MinSeverHit = 11        -- ต้องโดนแรงอย่างน้อยเท่านี้ในทีเดียวถึงจะหลุด
C.DecapChance = 0.35      -- โอกาสหัวหลุดตอนโดนน็อคด้วยท่าแรง (GoreLevel 1 เท่านั้น)
C.HalfChance = 0.3        -- โอกาสขาดครึ่งท่อนตอนโดนน็อคด้วยหมัดจรวด/อาวุธหนัก (GoreLevel 1 เท่านั้น)
C.GibLife = 20            -- ชิ้นส่วนที่หลุดอยู่กี่วินาที
C.MaxStains = 350         -- จำนวนรอยเลือดสูงสุดบนพื้น
C.StainLife = 90          -- รอยเลือดอยู่กี่วินาที
C.CameraShake = 1

-- ===== หน้าตาตัวละคร (คนสัดส่วนจริงแบบ ragdoll: เสื้อยืดเทา กางเกงเขียว ผมสั้น) =====
C.Look = {
	Skin = Color3.fromRGB(232, 188, 146),
	Shirt = Color3.fromRGB(128, 131, 137),
	Pants = Color3.fromRGB(66, 112, 58),
	Hair = Color3.fromRGB(44, 33, 28),
	Shoes = Color3.fromRGB(52, 44, 40),
	Eyes = Color3.fromRGB(24, 20, 20),
	Brows = Color3.fromRGB(44, 33, 28),
	Mouth = Color3.fromRGB(150, 82, 70),
	HairStyle = "box",
	Nose = true,
}
-- ผู้เล่นคนแรกได้หน้าตาตามภาพเป๊ะ คนต่อไปเปลี่ยนสีเสื้อให้แยกออก
C.PlayerShirts = {
	Color3.fromRGB(128, 131, 137), Color3.fromRGB(196, 58, 52), Color3.fromRGB(52, 98, 190),
	Color3.fromRGB(236, 190, 40), Color3.fromRGB(240, 240, 240), Color3.fromRGB(150, 70, 190),
	Color3.fromRGB(30, 30, 34), Color3.fromRGB(240, 130, 40),
}
C.SkinTones = {
	Color3.fromRGB(232, 188, 146), Color3.fromRGB(214, 160, 116), Color3.fromRGB(176, 120, 82),
	Color3.fromRGB(120, 80, 56), Color3.fromRGB(245, 210, 180),
}
C.ShirtColors = {
	Color3.fromRGB(128, 131, 137), Color3.fromRGB(196, 58, 52), Color3.fromRGB(52, 98, 190),
	Color3.fromRGB(236, 190, 40), Color3.fromRGB(240, 240, 240), Color3.fromRGB(30, 30, 34),
	Color3.fromRGB(240, 130, 40), Color3.fromRGB(60, 160, 120), Color3.fromRGB(230, 120, 170),
}
C.PantsColors = {
	Color3.fromRGB(66, 112, 58), Color3.fromRGB(40, 52, 90), Color3.fromRGB(30, 30, 34),
	Color3.fromRGB(120, 92, 60), Color3.fromRGB(90, 90, 96), Color3.fromRGB(150, 40, 40),
}
C.HairColors = {
	Color3.fromRGB(44, 33, 28), Color3.fromRGB(20, 20, 22), Color3.fromRGB(120, 72, 36),
	Color3.fromRGB(220, 190, 110), Color3.fromRGB(200, 200, 205), Color3.fromRGB(190, 50, 50),
}
C.HairStyles = { "box", "box", "flat", "spike", "mohawk", "bald", "cap", "long", "afro" }

-- ===== ชื่อนักเลง AI =====
C.BotNames = {
	"Big Earl", "Knuckles McGee", "Granny Gertrude", "Crazy Steve", "Tiny Tony",
	"Disco Dave", "Sweaty Gary", "Mad Dog Murphy", "Pizza Pete", "Doughnut Dan",
	"Chad Thunderfist", "Uncle Rick", "Meatball Marco", "Sir Slaps-a-Lot", "Lunchbox Larry",
}

-- ===== ท่าต่อสู้ =====
-- wind = เวลาก่อนโดน(วินาที)  dur = ทั้งท่า  dmg = ดาเมจ  range/arc = ระยะ/มุม
-- knock = แรงผลัก  lift = แรงยก  ragdoll = ล้มกี่วินาที  daze = สะสมมึน  super = เพิ่มเกจท่าไม้ตาย
C.Moves = {
	jab    = { anim = "jab",   wind = 0.08, dur = 0.30, dmg = 6,  range = 4.8, arc = 80, knock = 9,  lift = 0,  stun = 0.30, daze = 10, word = "punch", super = 6, zone = "head" },
	cross  = { anim = "cross", wind = 0.09, dur = 0.34, dmg = 8,  range = 5.0, arc = 75, knock = 14, lift = 0,  stun = 0.34, daze = 14, word = "punch", super = 7, zone = "head" },
	upper  = { anim = "upper", wind = 0.13, dur = 0.50, dmg = 12, range = 4.8, arc = 75, knock = 22, lift = 48, stun = 0.5, daze = 24, word = "upper", super = 10, zone = "head", ragdoll = 1.6, teeth = 0.7, heavy = true },
	kick   = { anim = "kick",  wind = 0.14, dur = 0.48, dmg = 11, range = 5.8, arc = 65, knock = 58, lift = 14, stun = 0.5, daze = 12, word = "kick", super = 8, zone = "body", ragdoll = 1.5, guardBreak = true },
	stomp  = { anim = "stomp", wind = 0.15, dur = 0.42, dmg = 9,  range = 4.8, arc = 90, knock = 6,  lift = 4,  stun = 0,   daze = 0,  word = "stomp", super = 5, zone = "limb", onlyDown = true },
	dive   = { anim = "dive",  wind = 0.10, dur = 0.45, dmg = 13, range = 5.5, arc = 110, knock = 20, lift = 10, stun = 0.5, daze = 18, word = "slam", super = 8, zone = "head", ragdoll = 1.3, hitsDown = true },
	grab   = { anim = "grab",  wind = 0.12, dur = 0.36, range = 4.4, arc = 75 },
	suplex = { anim = "suplex", dur = 0.85, dmg = 10, knock = 15, lift = 46, daze = 20, super = 10, ragdoll = 2.2 },
	swing  = { anim = "swing", wind = 0.17, dur = 0.50, range = 6.0, arc = 85, super = 6 },
	throw  = { anim = "throw", wind = 0.10, dur = 0.36 },
	super  = { anim = "super", wind = 0.42, dur = 1.05, dmg = 30, range = 7.0, arc = 85, knock = 95, lift = 60, stun = 1, daze = 60, word = "super", zone = "head", ragdoll = 3.2, unblockable = true, dash = 60, teeth = 1, heavy = true },
	taunt  = { anim = "taunt", dur = 1.6, super = 12 },
	pickup = { anim = "pickup", dur = 0.30 },
}
-- คอมโบปุ่มต่อย: กด 3 ครั้งติด = หมัดแย็บ > หมัดตรง > อัปเปอร์คัต (ลอย!)
C.PunchCombo = { "jab", "cross", "upper" }

-- ===== อาวุธข้างถนน =====
C.Weapons = {
	pan    = { name = "Frying Pan",      icon = "🍳", dmg = 15, knock = 30, lift = 10, stun = 0.6, daze = 26, uses = 10, word = "pan",   ragdoll = 1.2, ragdollChance = 0.35, sound = "clang" },
	plank  = { name = "2x4 With A Nail", icon = "🪵", dmg = 19, knock = 26, lift = 8,  stun = 0.5, daze = 20, uses = 7,  word = "wood",  ragdoll = 1.4, ragdollChance = 0.45, sound = "wood", heavy = true },
	chair  = { name = "Folding Chair",   icon = "🪑", dmg = 22, knock = 42, lift = 18, stun = 0.7, daze = 30, uses = 3,  word = "chair", ragdoll = 1.8, ragdollChance = 1, sound = "wood", heavy = true },
	fish   = { name = "Giant Fish",      icon = "🐟", dmg = 5,  knock = 75, lift = 38, stun = 0.4, daze = 6,  uses = 999, word = "fish", ragdoll = 2.0, ragdollChance = 1, sound = "slap" },
	cone   = { name = "Traffic Cone",    icon = "🔺", dmg = 7,  knock = 14, lift = 4,  stun = 0.6, daze = 12, uses = 1,  word = "cone",  ragdoll = 0, ragdollChance = 0, sound = "thud", hat = true },
	bottle = { name = "Ketchup Bottle",  icon = "🍅", dmg = 17, knock = 16, lift = 4,  stun = 0.7, daze = 30, uses = 1,  word = "glass", ragdoll = 1.2, ragdollChance = 0.5, sound = "glass", extraBlood = 2 },
}
C.WeaponOrder = { "pan", "plank", "chair", "fish", "cone", "bottle" }
C.WeaponRespawn = 10      -- วินาที
C.MaxWeaponsOnMap = 9
C.ThrowSpeed = 85

-- ===== คำการ์ตูนเด้งตอนตี =====
C.Words = {
	punch = { "POW!", "BAM!", "WHAM!", "SMACK!", "BOP!" },
	upper = { "KAPOW!!", "LIFTOFF!", "UPPERCUT!!", "SKY HIGH!!" },
	kick  = { "THWACK!", "BOOT!", "WHUMP!", "YEET!!" },
	stomp = { "STOMP!", "CRUNCH!", "SQUISH!", "CURB STOMP!" },
	slam  = { "CRASH!!", "BOOM!!", "THUD!!", "OOF!" },
	block = { "BLOCKED!", "NOPE!", "DENIED!" },
	guard = { "GUARD BREAK!!" },
	crit  = { "CRITICAL!!", "BRUTAL!!", "OUCH!!" },
	pan   = { "CLANG!!", "BONK!!", "DONG!!" },
	wood  = { "THOCK!!", "WHACK!!", "CRACK!!" },
	chair = { "CRASH!!", "SLAM!!", "BANG!!" },
	fish  = { "SLAP!", "FISH SLAP!!", "SPLOOSH!", "SMELLY!" },
	cone  = { "BONK!", "CONEHEAD!" },
	glass = { "SMASH!!", "SHATTER!!", "KETCHUP!!" },
	super = { "ROCKET PUNCH!!!", "TO THE MOON!!!" },
	impact = { "THUD!", "CRASH!", "OOF!", "WHUMP!" },
	melon = { "SPLAT!!", "JUICY!" },
	sever = { "ARM OFF!!", "LEG OFF!!", "HEADLESS!!" },
}

-- ===== Funny KO messages (%s = the one who got knocked out) =====
C.KOMessages = {
	"%s is taking a dirt nap 💤",
	"%s is seeing stars ⭐",
	"%s lost all their teeth 🦷",
	"%s got launched to Mars 🚀",
	"%s needs a minute... or ten 😵",
	"%s is crying for mommy 😭",
	"%s became a doormat 🧽",
	"%s got absolutely folded 🫠",
	"%s is going home in a bucket 🪣",
	"%s forgot their own name 🤪",
}
C.FallMessages = { "%s fell off the world 🌍", "%s took a wrong turn 🗺️" }
C.StreakNames = { [3] = "🔥 ON FIRE!", [5] = "👹 RAMPAGE!", [8] = "💀 GOD OF THE ALLEY!", [12] = "👑 GRIM REAPER!" }

-- ===== เสียง (เปลี่ยนเป็น rbxassetid://เลขเสียงของคุณเองได้) =====
C.Sounds = {
	swing  = { id = "rbxasset://sounds/swordlunge.wav", vol = 0.5 },
	hit    = { id = "rbxasset://sounds/swordslash.wav", vol = 0.45, pitch = 0.6 },
	heavy  = { id = "rbxasset://sounds/action_jump_land.mp3", vol = 1.0, pitch = 0.7 },
	thud   = { id = "rbxasset://sounds/action_jump_land.mp3", vol = 0.9 },
	clang  = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.8, pitch = 0.5 },
	wood   = { id = "rbxasset://sounds/action_jump_land.mp3", vol = 1.0, pitch = 1.4 },
	slap   = { id = "rbxasset://sounds/swordslash.wav", vol = 0.6, pitch = 1.5 },
	glass  = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.6, pitch = 1.8 },
	ouch   = { id = "rbxasset://sounds/uuhhh.mp3", vol = 0.7 },
	ko     = { id = "rbxasset://sounds/uuhhh.mp3", vol = 1.0, pitch = 0.8 },
	getup  = { id = "rbxasset://sounds/action_get_up.mp3", vol = 0.5 },
	super  = { id = "rbxasset://sounds/swordlunge.wav", vol = 1.0, pitch = 0.5 },
	ui     = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.4 },
}

return C
