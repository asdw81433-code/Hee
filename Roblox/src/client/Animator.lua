-- ============================================================
--  ซอยเดือด : แอนิเมชันแบบ procedural + สปริง (มีน้ำหนัก ไม่แข็งทื่อ)
--  ทุก client ขยับ Motor6D.Transform ของทุกตัวละครเอง จาก Attribute ที่ server ส่งมา
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Animator = {}
local Anim
local chars = {} -- [model] = state
local localPlayer = Players.LocalPlayer

local MOTORS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	N = { "Torso", "Neck" },
	RS = { "Torso", "Right Shoulder" },
	LS = { "Torso", "Left Shoulder" },
	RH = { "Torso", "Right Hip" },
	LH = { "Torso", "Left Hip" },
}
local JOINTS = { "Root", "N", "RS", "LS", "RH", "LH" }
local rad = math.rad
local sin, cos, abs = math.sin, math.cos, math.abs
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshRayFilter()
	local list = {}
	for _, n in ipairs({ "Fighters", "BrawlFX", "BrawlWeapons" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function newSpring()
	return { x = { 0, 0, 0 }, v = { 0, 0, 0 } }
end

local function setup(model)
	if chars[model] then
		return
	end
	local st = {
		model = model,
		motors = {},
		springs = {},
		off = newSpring(),
		clip = nil,
		clipT = 0,
		freeze = 0,
		walkPhase = math.random() * 6,
		t = math.random() * 10,
		ready = false,
	}
	chars[model] = st
	task.spawn(function()
		for key, path in pairs(MOTORS) do
			local holder = model:WaitForChild(path[1], 10)
			local m = holder and holder:WaitForChild(path[2], 10)
			if not m then
				return
			end
			st.motors[key] = m
			st.springs[key] = newSpring()
		end
		st.hum = model:WaitForChild("Humanoid", 10)
		st.root = model:WaitForChild("HumanoidRootPart", 10)
		st.ready = st.hum ~= nil and st.root ~= nil
	end)
	st.conn = model:GetAttributeChangedSignal("ActN"):Connect(function()
		local name = model:GetAttribute("Act")
		-- ตัวเราเล่นท่าไปก่อนแล้ว (ไม่ต้องรอ server) -> ไม่เริ่มซ้ำ
		if st.localClip == name and os.clock() - st.localT < 0.35 then
			st.localClip = nil
			return
		end
		Animator.play(model, name)
	end)
end

local function cleanup(model)
	local st = chars[model]
	if st then
		if st.conn then
			st.conn:Disconnect()
		end
		chars[model] = nil
	end
end

function Animator.init(animModule)
	Anim = animModule
	for _, m in ipairs(CollectionService:GetTagged("BrawlChar")) do
		setup(m)
	end
	CollectionService:GetInstanceAddedSignal("BrawlChar"):Connect(setup)
	CollectionService:GetInstanceRemovedSignal("BrawlChar"):Connect(cleanup)
	refreshRayFilter()
	workspace.ChildAdded:Connect(refreshRayFilter)
	RunService.Stepped:Connect(function(_, dt)
		Animator.step(dt)
	end)
end

function Animator.play(model, name)
	local st = chars[model]
	local clip = Anim.Clips[name]
	if not st or not clip then
		return
	end
	st.clip = clip
	st.clipName = name
	st.clipT = 0
	if Animator.onPlay then
		Animator.onPlay(model, name)
	end
end

-- ตัวเรากดปุ่มแล้วเล่นท่าทันที (ไม่หน่วงตามปิง)
function Animator.playLocal(model, name)
	local st = chars[model]
	if not st then
		return
	end
	st.localClip = name
	st.localT = os.clock()
	Animator.play(model, name)
end

-- หยุดภาพแป๊บนึงตอนโดน (hit-stop ให้รู้สึกหนัก)
function Animator.hitstop(model, dur)
	local st = chars[model]
	if st then
		st.freeze = math.max(st.freeze, dur)
	end
end

Animator.localBlock = false

local function copy3(v)
	return { v[1], v[2], v[3] }
end

-- ท่าพื้นฐาน (ยืน/เดิน/กระโดด/มึน/การ์ด)
local function basePose(st, dt, out)
	local model = st.model
	local vel = st.root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local t = st.t
	local G = Anim.Guard
	for _, j in ipairs(JOINTS) do
		out[j] = copy3(G[j])
	end
	out.off = { 0, sin(t * 2.2) * 0.04, 0 }
	-- หายใจ/โยกตัว
	out.RS[1] = out.RS[1] + sin(t * 2.2) * rad(3)
	out.LS[1] = out.LS[1] + sin(t * 2.2 + 1) * rad(3)

	local weapon = model:GetAttribute("Weapon")
	if weapon then
		out.RS = copy3(Anim.WeaponArm)
	end

	-- ลอยอยู่ไหม (raycast ลงพื้น ใช้ได้กับทุกตัวละคร ไม่ต้องพึ่ง property ที่อาจไม่ replicate)
	st.airT = (st.airT or 0) - dt
	if st.airT <= 0 then
		st.airT = 0.08
		local res = workspace:Raycast(st.root.Position, Vector3.new(0, -3.8, 0), rayParams)
		st.air = res == nil and abs(vel.Y) > 2
	end
	local air = st.air
	if air then
		-- ลอยกลางอากาศ: แขนกวัดแกว่งฮาๆ
		local fl = sin(t * 16)
		local falling = vel.Y < -20
		local amp = falling and 40 or 18
		out.RS = { rad(150 + fl * amp), 0, rad(30) }
		out.LS = { rad(150 - fl * amp), 0, rad(-30) }
		out.RH = { rad(35 + (falling and fl * 25 or 0)), 0, rad(6) }
		out.LH = { rad(-15 - (falling and fl * 25 or 0)), 0, rad(-6) }
		out.Root = { rad(falling and 10 or -6), 0, 0 }
		out.N = { rad(falling and 20 or 0), 0, 0 }
		return
	end

	if speed > 1 then
		local k = math.clamp(speed / 18, 0, 1.3)
		st.walkPhase = st.walkPhase + dt * speed * 0.62
		local p = st.walkPhase
		local s = sin(p)
		out.RH = { s * rad(46) * k, 0, rad(3) }
		out.LH = { -s * rad(46) * k, 0, rad(-3) }
		out.off = { 0, abs(cos(p)) * 0.16 * k - 0.04, 0 }
		out.Root = { rad(-7) * k, rad(-15) * (1 - k) + s * rad(6) * k, s * rad(2.5) * k }
		if not weapon then
			-- วิ่ง: แขนแกว่งสลับขา (ยังยกหมัดอยู่ครึ่งๆ)
			out.RS = { rad(55) - s * rad(40) * k, rad(20), rad(6) }
			out.LS = { rad(55) + s * rad(40) * k, rad(-20), rad(-6) }
		else
			out.LS = { rad(30) + s * rad(40) * k, 0, rad(-6) }
		end
	end

	-- มึนหัว: โยกเยก
	if model:GetAttribute("Dizzy") then
		out.Root = { sin(t * 2.1) * rad(8), sin(t * 1.3) * rad(15), sin(t * 3.2) * rad(12) }
		out.N = { sin(t * 4) * rad(18), 0, cos(t * 4) * rad(18) }
		out.RS = { rad(18) + sin(t * 3) * rad(12), 0, rad(22) }
		out.LS = { rad(18) - sin(t * 3) * rad(12), 0, rad(-22) }
		out.RH = { sin(t * 3.2) * rad(10), 0, rad(8) }
		out.LH = { -sin(t * 3.2) * rad(10), 0, rad(-8) }
		return
	end

	local blocking = model:GetAttribute("Block")
	if model == (localPlayer and localPlayer.Character) then
		blocking = blocking or Animator.localBlock
	end
	if blocking then
		for j, v in pairs(Anim.Block) do
			if j ~= "off" then
				out[j] = copy3(v)
			end
		end
	end
end

local pose = {}
local OMEGA_BASE, ZETA_BASE = 15, 0.62
local OMEGA_ACT, ZETA_ACT = 38, 0.7

local function springStep(s, target, w, z, h)
	for i = 1, 3 do
		local a = w * w * (target[i] - s.x[i]) - 2 * z * w * s.v[i]
		s.v[i] = s.v[i] + a * h
		s.x[i] = s.x[i] + s.v[i] * h
	end
end

local function jointCF(v, offv)
	local cf = CFrame.Angles(0, v[2], 0) * CFrame.Angles(v[1], 0, 0) * CFrame.Angles(0, 0, v[3])
	if offv then
		return CFrame.new(offv[1], offv[2], offv[3]) * cf
	end
	return cf
end

function Animator.step(dt)
	dt = math.min(dt, 1 / 15)
	for model, st in pairs(chars) do
		if st.ready and model.Parent and st.hum and st.root then
			if model:GetAttribute("Ragdoll") then
				st.clip = nil
				-- ตอนลุก ให้เริ่มจากท่าปกติ
				for _, s in pairs(st.springs) do
					s.v = { 0, 0, 0 }
				end
			else
				local adt = dt
				if st.freeze > 0 then
					st.freeze = st.freeze - dt
					adt = dt * 0.08
				end
				st.t = st.t + adt
				basePose(st, adt, pose)
				local acting = false
				if st.clip then
					st.clipT = st.clipT + adt
					local clip = st.clip
					if clip.procedural == "dance" then
						if st.clipT < clip.len then
							Anim.dance(st.clipT, pose)
							acting = true
						else
							st.clip = nil
						end
					else
						local base = {}
						for _, j in ipairs(JOINTS) do
							base[j] = pose[j]
						end
						local w = Anim.sampleClip(clip, st.clipT, base, pose)
						acting = w > 0.5
						if st.clipT > clip.len + 0.2 then
							st.clip = nil
						end
					end
				end
				-- ชดเชย: ขา/หัวไม่บิดตามลำตัวมากเกินไป
				local root = pose.Root
				pose.RH = { pose.RH[1] - root[1], pose.RH[2] - root[2], pose.RH[3] - root[3] }
				pose.LH = { pose.LH[1] - root[1], pose.LH[2] - root[2], pose.LH[3] - root[3] }
				pose.N = { pose.N[1] - root[1] * 0.5, pose.N[2] - root[2] * 0.8, pose.N[3] }

				local w, z = OMEGA_BASE, ZETA_BASE
				if acting then
					w, z = OMEGA_ACT, ZETA_ACT
				end
				local steps = math.max(1, math.ceil(adt / (1 / 120)))
				local h = adt / steps
				for _ = 1, steps do
					for _, j in ipairs(JOINTS) do
						local s = st.springs[j]
						if s then
							local jw = w
							if j == "RH" or j == "LH" then
								jw = w * 1.15
							end
							springStep(s, pose[j], jw, z, h)
						end
					end
					springStep(st.off, pose.off or { 0, 0, 0 }, w, 0.8, h)
				end
				for _, j in ipairs(JOINTS) do
					local m = st.motors[j]
					local s = st.springs[j]
					if m and s then
						if j == "Root" then
							m.Transform = jointCF(s.x, st.off.x)
						else
							m.Transform = jointCF(s.x)
						end
					end
				end
			end
		end
	end
end

return Animator
