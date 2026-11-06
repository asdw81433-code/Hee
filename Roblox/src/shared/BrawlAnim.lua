-- ============================================================
--  ซอยเดือด : ท่าทาง/แอนิเมชันแบบ procedural (ReplicatedStorage > BrawlAnim)
--  มุมเป็นองศา {rx, ry, rz}
--   แขน: rx 0 = ห้อยลง, 90 = ชี้ไปหน้า, 180 = ชูขึ้นฟ้า
--        ry บวก = แขนขวาหุบเข้าใน (แขนซ้ายใช้ค่าลบ)   rz บวก = แขนขวากางออก (แขนซ้ายใช้ค่าลบ)
--   ขา:  rx บวก = เตะไปหน้า, ลบ = ไปหลัง (ค่าขาเทียบกับโลก ระบบชดเชยการเอนตัวให้เอง)
--   Root(ลำตัว): rx บวก = เอนหลัง, ry บวก = บิดไหล่ขวาไปหน้า, rz บวก = เอียงซ้าย
--   N(คอ): rx บวก = เงยหน้า
--   off = เลื่อนลำตัว {x, y, z} (z ลบ = พุ่งไปหน้า)
--  key ที่มี hold = true จะก๊อปท่าก่อนหน้า (ค้างท่า)
-- ============================================================
local A = {}

--@@DATA_BEGIN
local DATA = {
	Guard = {
		RS = { 80, 30, 0 }, LS = { 92, -12, 0 }, RH = { -10, 0, 3 }, LH = { 16, 0, -3 },
		N = { 0, 0, 0 }, Root = { 0, -15, 0 },
	},
	Block = {
		RS = { 128, 46, 0 }, LS = { 128, -46, 0 }, N = { -14, 0, 0 }, Root = { 4, -6, 0 },
	},
	WeaponArm = { 52, 12, 0 },
	Clips = {
		jab = {
			{ t = 0.00, LS = { 80, -18, 0 } },
			{ t = 0.08, LS = { 96, 16, 0 }, RS = { 92, 40, 0 }, Root = { -4, -28, 0 }, off = { 0, 0, -0.3 } },
			{ t = 0.15, hold = true },
			{ t = 0.30, LS = { 86, -12, 0 } },
		},
		cross = {
			{ t = 0.00, RS = { 70, 28, 0 }, Root = { 0, -24, 0 } },
			{ t = 0.09, RS = { 97, -16, 0 }, LS = { 108, -40, 0 }, Root = { -6, 26, 0 }, off = { 0, 0, -0.4 }, RH = { -18, 0, 4 } },
			{ t = 0.17, hold = true },
			{ t = 0.34, RS = { 82, 26, 0 } },
		},
		upper = {
			{ t = 0.00, RS = { 25, 10, 12 }, Root = { 6, -26, 0 }, off = { 0, -0.25, 0 }, N = { -8, 0, 0 } },
			{ t = 0.13, RS = { 142, 16, 0 }, LS = { 110, -38, 0 }, Root = { 12, 22, 4 }, off = { 0, 0.3, -0.25 }, N = { 18, 0, 0 } },
			{ t = 0.23, hold = true },
			{ t = 0.50, RS = { 95, 22, 0 }, Root = { 4, -8, 0 } },
		},
		kick = {
			{ t = 0.00, RH = { 45, 0, 0 }, Root = { 8, -10, 0 }, RS = { 70, 25, 15 }, LS = { 75, -20, -15 } },
			{ t = 0.14, RH = { 98, 0, 0 }, LH = { -6, 0, 0 }, Root = { 16, -6, 0 }, off = { 0, 0.1, -0.3 }, RS = { 60, 10, 28 }, LS = { 70, -10, -28 } },
			{ t = 0.25, hold = true },
			{ t = 0.48, RH = { 20, 0, 0 }, Root = { 4, -10, 0 } },
		},
		stomp = {
			{ t = 0.00, RH = { 65, 0, 0 }, Root = { -8, 0, 0 }, N = { -28, 0, 0 }, RS = { 50, 0, 30 }, LS = { 50, 0, -30 } },
			{ t = 0.15, RH = { -4, 0, 0 }, LH = { 6, 0, 0 }, Root = { -14, 0, 0 }, off = { 0, -0.1, 0 }, N = { -32, 0, 0 }, RS = { 30, 0, 40 }, LS = { 30, 0, -40 } },
			{ t = 0.24, hold = true },
			{ t = 0.42, RH = { 0, 0, 0 }, Root = { -4, 0, 0 } },
		},
		dive = {
			{ t = 0.00, RS = { 170, 10, 10 }, LS = { 170, -10, -10 }, Root = { 10, 0, 0 }, RH = { 30, 0, 0 }, LH = { -20, 0, 0 } },
			{ t = 0.10, RS = { 50, 20, 0 }, LS = { 50, -20, 0 }, Root = { -24, 0, 0 }, N = { -20, 0, 0 }, RH = { 40, 0, 0 }, LH = { 10, 0, 0 } },
			{ t = 0.25, hold = true },
			{ t = 0.45, RS = { 80, 30, 0 }, LS = { 88, -28, 0 }, Root = { 0, -10, 0 } },
		},
		grab = {
			{ t = 0.00, RS = { 70, 15, 0 }, LS = { 70, -15, 0 }, Root = { -6, 0, 0 } },
			{ t = 0.12, RS = { 95, 18, 0 }, LS = { 95, -18, 0 }, Root = { -12, 0, 0 }, off = { 0, 0, -0.4 } },
			{ t = 0.20, hold = true },
			{ t = 0.36, RS = { 80, 25, 0 }, LS = { 85, -25, 0 } },
		},
		suplex = {
			{ t = 0.00, RS = { 95, 20, 0 }, LS = { 95, -20, 0 }, Root = { -8, 0, 0 } },
			{ t = 0.15, RS = { 130, 15, 0 }, LS = { 130, -15, 0 }, Root = { 10, 0, 0 }, off = { 0, 0.1, 0 } },
			{ t = 0.35, RS = { 175, 5, 0 }, LS = { 175, -5, 0 }, Root = { 40, 0, 0 }, off = { 0, 0.25, 0.4 }, N = { 35, 0, 0 }, RH = { 15, 0, 0 }, LH = { 15, 0, 0 } },
			{ t = 0.60, hold = true },
			{ t = 0.85, Root = { 5, 0, 0 } },
		},
		swing = {
			{ t = 0.00, RS = { 172, 8, 0 }, LS = { 70, -20, -10 }, Root = { 8, -18, 0 }, N = { 8, 0, 0 } },
			{ t = 0.17, RS = { 86, 12, 0 }, LS = { 60, -10, -25 }, Root = { -12, 22, 0 }, off = { 0, -0.05, -0.35 }, N = { -8, 0, 0 } },
			{ t = 0.27, RS = { 60, 14, 0 }, LS = { 60, -10, -25 }, Root = { -14, 24, 0 }, off = { 0, -0.05, -0.4 }, N = { -10, 0, 0 } },
			{ t = 0.50, RS = { 45, 10, 0 }, Root = { 0, -6, 0 } },
		},
		throw = {
			{ t = 0.00, RS = { 165, -10, 10 }, Root = { 6, -28, 0 } },
			{ t = 0.10, RS = { 85, 0, 0 }, Root = { -12, 30, 0 }, off = { 0, 0, -0.3 } },
			{ t = 0.18, hold = true },
			{ t = 0.36, RS = { 60, 15, 0 }, Root = { 0, -8, 0 } },
		},
		super = {
			{ t = 0.00, RS = { -35, 0, 20 }, LS = { 100, -35, 0 }, Root = { 6, -38, 0 }, off = { 0, -0.3, 0.2 }, N = { 0, 30, 0 }, RH = { -14, 0, 0 }, LH = { 22, 0, 0 } },
			{ t = 0.36, RS = { -48, -6, 24 }, LS = { 104, -38, 0 }, Root = { 8, -44, 0 }, off = { 0, -0.35, 0.25 }, N = { 0, 34, 0 }, RH = { -16, 0, 0 }, LH = { 24, 0, 0 } },
			{ t = 0.42, RS = { 96, -8, 0 }, LS = { 60, -10, -30 }, Root = { -16, 34, 0 }, off = { 0, 0, -0.9 }, N = { -5, -20, 0 }, RH = { -30, 0, 0 }, LH = { 30, 0, 0 } },
			{ t = 0.75, hold = true },
			{ t = 1.05, RS = { 84, 26, 0 }, Root = { 0, -10, 0 } },
		},
		pickup = {
			{ t = 0.00, Root = { -30, 0, 0 }, RS = { 40, 10, 0 }, N = { -20, 0, 0 } },
			{ t = 0.15, Root = { -32, 0, 0 }, RS = { 20, 10, 0 }, N = { -24, 0, 0 } },
			{ t = 0.30, Root = { -5, 0, 0 } },
		},
		hurt = {
			{ t = 0.00, Root = { 16, 0, -6 }, N = { 28, 0, 8 }, RS = { 40, 0, 40 }, LS = { 40, 0, -40 }, off = { 0, 0, 0.25 } },
			{ t = 0.12, Root = { 10, 0, -3 }, N = { 14, 0, 4 }, RS = { 55, 10, 25 }, LS = { 55, -10, -25 }, off = { 0, 0, 0.15 } },
			{ t = 0.40, Root = { 0, -8, 0 } },
		},
		hurtBody = {
			{ t = 0.00, Root = { -24, 0, 4 }, N = { -12, 0, 0 }, RS = { 40, 40, 0 }, LS = { 40, -40, 0 }, off = { 0, -0.1, 0.3 } },
			{ t = 0.15, Root = { -18, 0, 2 }, N = { -8, 0, 0 }, RS = { 45, 40, 0 }, LS = { 45, -40, 0 }, off = { 0, -0.05, 0.15 } },
			{ t = 0.45, Root = { 0, -8, 0 } },
		},
		blockHit = {
			{ t = 0.00, RS = { 120, 46, 0 }, LS = { 120, -46, 0 }, Root = { 10, 0, 0 }, N = { -6, 0, 0 }, off = { 0, 0, 0.3 } },
			{ t = 0.20, RS = { 128, 46, 0 }, LS = { 128, -46, 0 }, Root = { 4, -6, 0 } },
		},
		taunt = {
			{ t = 0.00, procedural = "dance" },
			{ t = 1.60, procedural = "dance" },
		},
	},
}
--@@DATA_END

-- ----- เตรียมข้อมูล: hold = ก๊อปท่าก่อนหน้า, แปลงองศาเป็นเรเดียน -----
local JOINTS = { "Root", "N", "RS", "LS", "RH", "LH" }
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

-- ท่าเต้นยั่ว (ไก่ย่างแดนซ์)
function A.dance(t, out)
	local s = math.sin(t * 9)
	local flap = rad(50 + math.sin(t * 18) * 35)
	out.RS = { rad(20), 0, flap }
	out.LS = { rad(20), 0, -flap }
	out.RH = { rad(math.max(0, s) * 45), 0, rad(4) }
	out.LH = { rad(math.max(0, -s) * 45), 0, rad(-4) }
	out.Root = { rad(-4), rad(math.sin(t * 4.5) * 20), rad(s * 8) }
	out.N = { rad(math.abs(s) * 10), rad(math.sin(t * 4.5) * 25), rad(-s * 10) }
	out.off = { 0, math.abs(s) * 0.25, 0 }
end

return A
