-- ============================================================
--  ซอยเดือด : ท่าทาง/แอนิเมชันแบบ procedural (ReplicatedStorage > BrawlAnim)
--  มุมเป็นองศา {rx, ry, rz}
--   ไหล่ RS/LS: rx 0 = ห้อยลง, 90 = ชี้ไปหน้า, 180 = ชูขึ้นฟ้า
--        ry บวก = แขนขวาหุบเข้าใน (แขนซ้ายใช้ค่าลบ)   rz บวก = แขนขวากางออก (แขนซ้ายใช้ค่าลบ)
--   ศอก RE/LE: rx = มุมงอ (0 = เหยียดตรง, 120 = งอมาก)
--   สะโพก RH/LH: rx บวก = ยกขาไปหน้า, ลบ = ไปหลัง (เทียบกับโลก ระบบชดเชยการเอนให้เอง)
--   เข่า RK/LK: rx ลบ = งอเข่า
--   W(เอว): rx บวก = เอนหลัง, ry บวก = บิดไหล่ขวาไปหน้า   Root(สะโพกทั้งตัว): เหมือนกันแต่ขาไม่บิดตาม
--   N(คอ): rx บวก = เงยหน้า
--   off = เลื่อนสะโพก {x, y, z} (z ลบ = พุ่งไปหน้า)
--  key ที่มี hold = true จะก๊อปท่าก่อนหน้า (ค้างท่า)
-- ============================================================
local A = {}

--@@DATA_BEGIN
local DATA = {
	Guard = {
		RS = { 35, 30, 10 }, RE = { 118, 0, 0 }, LS = { 48, -18, -8 }, LE = { 100, 0, 0 },
		RH = { -12, 0, 6 }, RK = { -14, 0, 0 }, LH = { 18, 0, -6 }, LK = { -18, 0, 0 },
		N = { -6, 0, 0 }, W = { -4, -10, 0 }, Root = { 0, -10, 0 },
	},
	Block = {
		RS = { 60, 38, 6 }, RE = { 125, 0, 0 }, LS = { 60, -38, -6 }, LE = { 125, 0, 0 }, N = { -14, 0, 0 }, W = { -8, 0, 0 },
	},
	WeaponArm = { 48, 10, 0 },
	WeaponElbow = { 20, 0, 0 },
	Clips = {
		jab = {
			{ t = 0.00, LS = { 50, -18, -8 }, LE = { 100, 0, 0 } },
			{ t = 0.08, LS = { 92, 12, 0 }, LE = { 4, 0, 0 }, RS = { 35, 34, 10 }, RE = { 122, 0, 0 }, W = { -6, -22, 0 }, Root = { 0, -12, 0 }, off = { 0, 0, -0.3 }, N = { -8, 10, 0 } },
			{ t = 0.15, hold = true },
			{ t = 0.30, LS = { 50, -14, -8 }, LE = { 95, 0, 0 } },
		},
		cross = {
			{ t = 0.00, RS = { 32, 30, 12 }, RE = { 118, 0, 0 }, W = { 0, -18, 0 } },
			{ t = 0.09, RS = { 92, -10, 0 }, RE = { 4, 0, 0 }, LS = { 60, -34, -6 }, LE = { 120, 0, 0 }, W = { -8, 28, 0 }, Root = { 0, 6, 0 }, off = { 0, 0, -0.4 }, RH = { -18, 0, 6 }, RK = { -6, 0, 0 }, N = { -8, -15, 0 } },
			{ t = 0.17, hold = true },
			{ t = 0.34, RS = { 35, 30, 10 }, RE = { 112, 0, 0 } },
		},
		upper = {
			{ t = 0.00, RS = { 15, 10, 14 }, RE = { 100, 0, 0 }, W = { 4, -24, 0 }, Root = { 0, -8, 0 }, off = { 0, -0.3, 0 }, RK = { -35, 0, 0 }, LK = { -35, 0, 0 }, RH = { -6, 0, 6 }, LH = { 18, 0, -6 }, N = { -8, 0, 0 } },
			{ t = 0.13, RS = { 62, 12, 0 }, RE = { 78, 0, 0 }, LS = { 60, -34, -6 }, LE = { 120, 0, 0 }, W = { 14, 22, 4 }, off = { 0, 0.25, -0.2 }, RK = { -4, 0, 0 }, LK = { -6, 0, 0 }, N = { 16, 0, 0 } },
			{ t = 0.23, hold = true },
			{ t = 0.50, RS = { 40, 28, 10 }, RE = { 110, 0, 0 }, W = { 0, -8, 0 } },
		},
		kick = {
			{ t = 0.00, RH = { 70, 0, 0 }, RK = { -95, 0, 0 }, LK = { -10, 0, 0 }, Root = { 6, -8, 0 }, W = { 6, 0, 0 }, RS = { 45, 25, 18 }, RE = { 90, 0, 0 }, LS = { 50, -20, -18 }, LE = { 90, 0, 0 } },
			{ t = 0.14, RH = { 92, 0, 0 }, RK = { -4, 0, 0 }, LH = { -6, 0, 0 }, LK = { -12, 0, 0 }, Root = { 12, -4, 0 }, W = { 8, 0, 0 }, off = { 0, 0.08, -0.3 }, RS = { 40, 10, 30 }, RE = { 40, 0, 0 }, LS = { 45, -10, -30 }, LE = { 40, 0, 0 } },
			{ t = 0.25, hold = true },
			{ t = 0.48, RH = { 30, 0, 0 }, RK = { -40, 0, 0 }, Root = { 4, -8, 0 } },
		},
		stomp = {
			{ t = 0.00, RH = { 75, 0, 0 }, RK = { -100, 0, 0 }, Root = { -8, 0, 0 }, W = { -10, 0, 0 }, N = { -30, 0, 0 }, RS = { 40, 0, 30 }, RE = { 60, 0, 0 }, LS = { 40, 0, -30 }, LE = { 60, 0, 0 } },
			{ t = 0.15, RH = { -2, 0, 0 }, RK = { 0, 0, 0 }, LH = { 8, 0, 0 }, LK = { -25, 0, 0 }, Root = { -12, 0, 0 }, W = { -14, 0, 0 }, off = { 0, -0.15, 0 }, N = { -34, 0, 0 }, RS = { 25, 0, 40 }, RE = { 30, 0, 0 }, LS = { 25, 0, -40 }, LE = { 30, 0, 0 } },
			{ t = 0.24, hold = true },
			{ t = 0.42, RH = { 0, 0, 0 }, RK = { 0, 0, 0 }, Root = { -4, 0, 0 } },
		},
		dive = {
			{ t = 0.00, RS = { 170, 10, 10 }, RE = { 20, 0, 0 }, LS = { 170, -10, -10 }, LE = { 20, 0, 0 }, W = { 10, 0, 0 }, RH = { 30, 0, 0 }, RK = { -60, 0, 0 }, LH = { -20, 0, 0 }, LK = { -40, 0, 0 } },
			{ t = 0.10, RS = { 60, 20, 0 }, RE = { 10, 0, 0 }, LS = { 60, -20, 0 }, LE = { 10, 0, 0 }, W = { -25, 0, 0 }, N = { -20, 0, 0 }, RH = { 40, 0, 0 }, RK = { -30, 0, 0 }, LH = { 10, 0, 0 }, LK = { -50, 0, 0 } },
			{ t = 0.25, hold = true },
			{ t = 0.45, RS = { 35, 30, 10 }, RE = { 118, 0, 0 }, LS = { 48, -18, -8 }, LE = { 100, 0, 0 }, W = { -4, -10, 0 } },
		},
		grab = {
			{ t = 0.00, RS = { 70, 15, 0 }, RE = { 40, 0, 0 }, LS = { 70, -15, 0 }, LE = { 40, 0, 0 }, W = { -6, 0, 0 } },
			{ t = 0.12, RS = { 92, 20, 0 }, RE = { 15, 0, 0 }, LS = { 92, -20, 0 }, LE = { 15, 0, 0 }, W = { -14, 0, 0 }, off = { 0, 0, -0.4 } },
			{ t = 0.20, hold = true },
			{ t = 0.36, RS = { 60, 25, 0 }, RE = { 70, 0, 0 }, LS = { 60, -25, 0 }, LE = { 70, 0, 0 } },
		},
		suplex = {
			{ t = 0.00, RS = { 95, 20, 0 }, RE = { 30, 0, 0 }, LS = { 95, -20, 0 }, LE = { 30, 0, 0 }, W = { -8, 0, 0 } },
			{ t = 0.15, RS = { 130, 15, 0 }, RE = { 40, 0, 0 }, LS = { 130, -15, 0 }, LE = { 40, 0, 0 }, W = { 10, 0, 0 }, off = { 0, 0.1, 0 }, RK = { -30, 0, 0 }, LK = { -30, 0, 0 } },
			{ t = 0.35, RS = { 175, 5, 0 }, RE = { 10, 0, 0 }, LS = { 175, -5, 0 }, LE = { 10, 0, 0 }, W = { 35, 0, 0 }, Root = { 15, 0, 0 }, off = { 0, 0.25, 0.4 }, N = { 35, 0, 0 }, RH = { 25, 0, 0 }, RK = { -60, 0, 0 }, LH = { 25, 0, 0 }, LK = { -60, 0, 0 } },
			{ t = 0.60, hold = true },
			{ t = 0.85, W = { 0, 0, 0 }, Root = { 0, 0, 0 } },
		},
		swing = {
			{ t = 0.00, RS = { 165, 8, 0 }, RE = { 50, 0, 0 }, LS = { 60, -20, -10 }, LE = { 60, 0, 0 }, W = { 10, -18, 0 }, N = { 8, 0, 0 } },
			{ t = 0.17, RS = { 85, 12, 0 }, RE = { 5, 0, 0 }, LS = { 50, -10, -25 }, LE = { 40, 0, 0 }, W = { -14, 24, 0 }, off = { 0, -0.05, -0.35 }, N = { -8, 0, 0 } },
			{ t = 0.27, RS = { 62, 14, 0 }, RE = { 5, 0, 0 }, LS = { 50, -10, -25 }, LE = { 40, 0, 0 }, W = { -16, 26, 0 }, off = { 0, -0.05, -0.4 }, N = { -10, 0, 0 } },
			{ t = 0.50, RS = { 48, 10, 0 }, RE = { 20, 0, 0 }, W = { 0, -6, 0 } },
		},
		throw = {
			{ t = 0.00, RS = { 160, -10, 10 }, RE = { 70, 0, 0 }, W = { 6, -28, 0 } },
			{ t = 0.10, RS = { 85, 0, 0 }, RE = { 5, 0, 0 }, W = { -12, 30, 0 }, off = { 0, 0, -0.3 } },
			{ t = 0.18, hold = true },
			{ t = 0.36, RS = { 48, 10, 0 }, RE = { 30, 0, 0 }, W = { 0, -8, 0 } },
		},
		super = {
			{ t = 0.00, RS = { -35, 0, 20 }, RE = { 80, 0, 0 }, LS = { 80, -35, 0 }, LE = { 60, 0, 0 }, W = { 6, -40, 0 }, Root = { 0, -10, 0 }, off = { 0, -0.3, 0.2 }, N = { 0, 30, 0 }, RH = { -16, 0, 0 }, RK = { -30, 0, 0 }, LH = { 24, 0, 0 }, LK = { -40, 0, 0 } },
			{ t = 0.36, RS = { -48, -6, 24 }, RE = { 90, 0, 0 }, LS = { 84, -38, 0 }, LE = { 60, 0, 0 }, W = { 8, -46, 0 }, Root = { 0, -12, 0 }, off = { 0, -0.35, 0.25 }, N = { 0, 34, 0 }, RH = { -18, 0, 0 }, RK = { -34, 0, 0 }, LH = { 26, 0, 0 }, LK = { -44, 0, 0 } },
			{ t = 0.42, RS = { 94, -8, 0 }, RE = { 0, 0, 0 }, LS = { 40, -10, -30 }, LE = { 30, 0, 0 }, W = { -16, 36, 0 }, Root = { 0, 10, 0 }, off = { 0, 0, -0.9 }, N = { -5, -20, 0 }, RH = { -30, 0, 0 }, RK = { -10, 0, 0 }, LH = { 35, 0, 0 }, LK = { -30, 0, 0 } },
			{ t = 0.75, hold = true },
			{ t = 1.05, RS = { 35, 30, 10 }, RE = { 118, 0, 0 }, W = { 0, -10, 0 }, Root = { 0, -10, 0 } },
		},
		pickup = {
			{ t = 0.00, W = { -35, 0, 0 }, Root = { -10, 0, 0 }, RS = { 40, 10, 0 }, RE = { 10, 0, 0 }, N = { -20, 0, 0 }, RK = { -35, 0, 0 }, LK = { -35, 0, 0 }, off = { 0, -0.3, 0 } },
			{ t = 0.15, W = { -40, 0, 0 }, Root = { -10, 0, 0 }, RS = { 25, 10, 0 }, RE = { 5, 0, 0 }, N = { -24, 0, 0 }, RK = { -45, 0, 0 }, LK = { -45, 0, 0 }, off = { 0, -0.4, 0 } },
			{ t = 0.30, W = { -5, 0, 0 }, RK = { -5, 0, 0 }, LK = { -5, 0, 0 } },
		},
		hurt = {
			{ t = 0.00, W = { 18, 0, -6 }, N = { 28, 0, 8 }, RS = { 40, 0, 40 }, RE = { 30, 0, 0 }, LS = { 40, 0, -40 }, LE = { 30, 0, 0 }, off = { 0, 0, 0.25 } },
			{ t = 0.12, W = { 12, 0, -3 }, N = { 14, 0, 4 }, RS = { 50, 10, 25 }, RE = { 60, 0, 0 }, LS = { 50, -10, -25 }, LE = { 60, 0, 0 }, off = { 0, 0, 0.15 } },
			{ t = 0.40, W = { 0, -8, 0 } },
		},
		hurtBody = {
			{ t = 0.00, W = { -30, 0, 4 }, N = { -12, 0, 0 }, RS = { 40, 40, 0 }, RE = { 80, 0, 0 }, LS = { 40, -40, 0 }, LE = { 80, 0, 0 }, off = { 0, -0.1, 0.3 }, RK = { -20, 0, 0 }, LK = { -20, 0, 0 } },
			{ t = 0.15, W = { -22, 0, 2 }, N = { -8, 0, 0 }, RS = { 45, 40, 0 }, RE = { 85, 0, 0 }, LS = { 45, -40, 0 }, LE = { 85, 0, 0 }, off = { 0, -0.05, 0.15 }, RK = { -15, 0, 0 }, LK = { -15, 0, 0 } },
			{ t = 0.45, W = { 0, -8, 0 } },
		},
		blockHit = {
			{ t = 0.00, RS = { 55, 40, 6 }, RE = { 120, 0, 0 }, LS = { 55, -40, -6 }, LE = { 120, 0, 0 }, W = { 10, 0, 0 }, N = { -6, 0, 0 }, off = { 0, 0, 0.3 } },
			{ t = 0.20, RS = { 60, 38, 6 }, RE = { 125, 0, 0 }, LS = { 60, -38, -6 }, LE = { 125, 0, 0 }, W = { -8, 0, 0 } },
		},
		taunt = {
			{ t = 0.00, procedural = "dance" },
			{ t = 1.60, procedural = "dance" },
		},
	},
}
--@@DATA_END

-- ----- เตรียมข้อมูล: hold = ก๊อปท่าก่อนหน้า, แปลงองศาเป็นเรเดียน -----
local JOINTS = { "Root", "W", "N", "RS", "RE", "LS", "LE", "RH", "RK", "LH", "LK" }
A.JOINTS = JOINTS
local rad = math.rad

local function toRad(v)
	return { rad(v[1]), rad(v[2]), rad(v[3]) }
end
local function convertPose(p)
	local out = {}
	for _, j in ipairs(JOINTS) do
		if p[j] then
			out[j] = toRad(p[j])
		end
	end
	if p.off then
		out.off = { p.off[1], p.off[2], p.off[3] }
	end
	return out
end

A.Guard = convertPose(DATA.Guard)
A.Block = convertPose(DATA.Block)
A.WeaponArm = toRad(DATA.WeaponArm)
A.WeaponElbow = toRad(DATA.WeaponElbow)
A.Clips = {}
for name, keys in pairs(DATA.Clips) do
	local clip = { keys = {}, len = 0, procedural = nil }
	local prev = nil
	for i, k in ipairs(keys) do
		local ck
		if k.hold and prev then
			ck = {}
			for key, val in pairs(prev) do
				ck[key] = val
			end
		else
			ck = convertPose(k)
		end
		ck.t = k.t
		if k.procedural then
			clip.procedural = k.procedural
		end
		clip.keys[i] = ck
		prev = ck
		if k.t > clip.len then
			clip.len = k.t
		end
	end
	A.Clips[name] = clip
end

-- smoothstep
local function ease(a)
	return a * a * (3 - 2 * a)
end
A.ease = ease

-- ค่าของ joint j จาก pose (ถ้าไม่มี ใช้ base)
local function jv(pose, base, j)
	return pose[j] or base[j]
end

-- ประเมินท่าของคลิป ณ เวลา t; เขียนผลทับลงใน out (ตาราง joint -> {rx,ry,rz})
-- คืนค่า น้ำหนัก(0..1) ของคลิป (ใช้เฟดออก)
function A.sampleClip(clip, t, base, out)
	local keys = clip.keys
	local n = #keys
	if n == 0 then
		return 0
	end
	local fade = 0.14
	if t >= keys[n].t then
		-- จบคลิปแล้ว เฟดจาก key สุดท้ายกลับไป base
		local w = 1 - math.clamp((t - keys[n].t) / fade, 0, 1)
		local last = keys[n]
		for _, j in ipairs(JOINTS) do
			local v = last[j]
			if v then
				local b = base[j]
				out[j] = { b[1] + (v[1] - b[1]) * w, b[2] + (v[2] - b[2]) * w, b[3] + (v[3] - b[3]) * w }
			end
		end
		if last.off then
			out.off = { last.off[1] * w, last.off[2] * w, last.off[3] * w }
		end
		return w
	end
	local k1, k2 = keys[1], keys[1]
	for i = 1, n - 1 do
		if t >= keys[i].t and t < keys[i + 1].t then
			k1, k2 = keys[i], keys[i + 1]
			break
		end
	end
	local span = k2.t - k1.t
	local a = 1
	if span > 0 then
		a = ease(math.clamp((t - k1.t) / span, 0, 1))
	end
	for _, j in ipairs(JOINTS) do
		if k1[j] or k2[j] then
			local v1 = jv(k1, base, j)
			local v2 = jv(k2, base, j)
			out[j] = { v1[1] + (v2[1] - v1[1]) * a, v1[2] + (v2[2] - v1[2]) * a, v1[3] + (v2[3] - v1[3]) * a }
		end
	end
	local o1 = k1.off or { 0, 0, 0 }
	local o2 = k2.off or { 0, 0, 0 }
	if k1.off or k2.off then
		out.off = { o1[1] + (o2[1] - o1[1]) * a, o1[2] + (o2[2] - o1[2]) * a, o1[3] + (o2[3] - o1[3]) * a }
	end
	return 1
end

-- ท่าเต้นยั่ว (ไก่ย่างแดนซ์: กางศอกกระพือปีก + ยกเข่าสลับ)
function A.dance(t, out)
	local s = math.sin(t * 9)
	local flap = rad(40 + math.sin(t * 18) * 35)
	out.RS = { rad(15), 0, flap }
	out.LS = { rad(15), 0, -flap }
	out.RE = { rad(110), 0, 0 }
	out.LE = { rad(110), 0, 0 }
	out.RH = { rad(math.max(0, s) * 55), 0, rad(4) }
	out.RK = { -rad(math.max(0, s) * 80), 0, 0 }
	out.LH = { rad(math.max(0, -s) * 55), 0, rad(-4) }
	out.LK = { -rad(math.max(0, -s) * 80), 0, 0 }
	out.Root = { 0, 0, rad(s * 6) }
	out.W = { rad(-4), rad(math.sin(t * 4.5) * 20), rad(s * 6) }
	out.N = { rad(math.abs(s) * 12), rad(math.sin(t * 4.5) * 25), rad(-s * 10) }
	out.off = { 0, math.abs(s) * 0.2, 0 }
end

return A
