--[[
	Procedural animation for every NEON BAY rig, done on each client through Motor6D.Transform.
	It runs its own forward kinematics so IK can place gloves on the opponent's chin and feet on the canvas
	in the same frame. Poses: lobby walk, boxing stance with planted-feet footwork, six punch paths,
	guard / slip / duck / pull-back, clinch, corner, celebrate, dejected, falls and get-ups.
	On top: sprung hit reactions, a living face (eyes, blinks, swelling lids, brows, jaw) and hair sway.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local RigDef = require(Shared.RigDef)
local PunchData = require(Shared.PunchData)
local Util = require(Shared.Util)

local Animator = {}
local rigs = {} -- model -> state
Animator.Rigs = rigs

local rad = math.rad
local A = CFrame.Angles
local V3 = Vector3.new
local UP = Vector3.yAxis
local camera = workspace.CurrentCamera

local function now() return workspace:GetServerTimeNow() end

-- ================================================================== rig registry
local function scan(st)
	local m = st.model
	st.motors, st.c0 = {}, {}
	for _, def in RigDef.Bones do
		local bone = m:FindFirstChild(def.name)
		local mo = bone and bone:FindFirstChild(def.motor)
		if mo and mo:IsA("Motor6D") then
			st.motors[def.motor] = mo
			st.c0[def.motor] = mo.C0
		end
	end
	st.face, st.strands, st.skinParts, st.injParts = {}, {}, {}, {}
	local cos = m:FindFirstChild("Cosmetics")
	if cos then
		for _, d in cos:GetDescendants() do
			if d:IsA("Motor6D") then
				local p1 = d.Part1
				if p1 and p1:GetAttribute("Role") == "Strand" then
					table.insert(st.strands, { motor = d, ax = 0, az = 0, vx = 0, vz = 0 })
				else
					st.face[d.Name] = d
				end
			elseif d:IsA("BasePart") then
				if d:GetAttribute("Skin") then table.insert(st.skinParts, d) end
				local tag = d:GetAttribute("Inj")
				if tag then
					local mesh = d:FindFirstChildOfClass("SpecialMesh")
					table.insert(st.injParts, { part = d, tag = tag, mesh = mesh, base = d.Color, shown = -1 })
				end
			end
		end
	end
	st.scanned = true
end

local function add(model)
	if rigs[model] then return end
	local st = {
		model = model, phase = math.random() * 6, idleT = math.random() * 10,
		headSnap = Vector3.zero, headV = Vector3.zero, chestSnap = Vector3.zero, chestV = Vector3.zero,
		feetInit = false, footL = Vector3.zero, footR = Vector3.zero, stepL = -1, stepR = -1,
		fromL = Vector3.zero, fromR = Vector3.zero, toL = Vector3.zero, toR = Vector3.zero,
		lean = Vector3.zero, guardHi = 0, guardLo = 0, bounce = 0, blinkT = -1, nextBlink = 1 + math.random() * 3,
		jaw = 0, jawV = 0, squint = 0, squintHold = 0, browUp = 0, pain = 0, saccade = Vector2.zero, saccadeT = 0,
		eye = Vector2.zero, lastHeadPos = nil, sweat = 0,
	}
	rigs[model] = st
	scan(st)
	model.ChildAdded:Connect(function(c) if c.Name == "Cosmetics" then task.defer(scan, st) end end)
end

local function remove(model) rigs[model] = nil end

function Animator.Get(model) return rigs[model] end

-- ================================================================== reactions (called from impact events)
function Animator.React(model, dirWorld: Vector3, power, headHit, bodyHit)
	local st = rigs[model]
	if not st then return end
	local head = model:FindFirstChild("Head")
	local cf = head and head.CFrame or model:GetPivot()
	local d = cf:VectorToObjectSpace(dirWorld.Magnitude > 0 and dirWorld.Unit or V3(0, 0, 1))
	power = math.clamp(power, 0, 2)
	if headHit then
		st.headV += V3((d.Z * 0.75 + d.Y) * 420, -d.X * 520, -d.X * 200) * power
		st.chestV += V3(30, -d.X * 60, 0) * power
		st.jawV += 9 * power + 2
		st.blinkT = 0
		st.squint = 1
		st.squintHold = 0.25 + 0.35 * power
		st.browUp = math.max(st.browUp, 0.6 * power)
		st.saccade += Vector2.new(-d.X, d.Y) * 18 * power
	end
	if bodyHit then
		st.chestV += V3(-260, -d.X * 160, d.X * 120) * power
		st.headV += V3(-120, 0, 0) * power
		st.jawV += 4 * power
		st.squint = math.max(st.squint, 0.6 + 0.4 * power)
		st.squintHold = 0.5 + power * 0.6
	end
	st.pain = math.max(st.pain, 0.5 * power)
end

-- local punch prediction for the local player's fighter
function Animator.Predict(model, id, body, power, scale)
	local st = rigs[model]
	if not st then return end
	st.predict = { id = id, body = body, power = power, t0 = now(), scale = scale or 1, actId = model:GetAttribute("ActId") or 0 }
end

-- ================================================================== helpers
local function spring(x: Vector3, v: Vector3, k, c, dt, limit)
	v += (-x * k - v * c) * dt
	x += v * dt
	if x.Magnitude > limit then x = x.Unit * limit end
	return x, v
end

local function deg(x, y, z) return A(rad(x), rad(y), rad(z)) end

local function lerpPose(a, b, t)
	local o = {}
	for k, v in b do
		local av = a[k]
		o[k] = av and av:Lerp(v, t) or v
	end
	for k, v in a do if not o[k] then o[k] = v end end
	return o
end

-- current punch (server attributes, or the local prediction)
local function currentPunch(st)
	local m = st.model
	local id = m:GetAttribute("Act") or 0
	local pr = st.predict
	if pr then
		local serverAct = m:GetAttribute("ActId") or 0
		if serverAct ~= pr.actId or now() - pr.t0 > 0.6 then
			st.predict = nil
		else
			return PunchData.Get(pr.id), pr.body, pr.power, now() - pr.t0, pr.scale, false
		end
	end
	if id == 0 then return nil end
	local t0 = m:GetAttribute("ActT0") or now()
	return PunchData.Get(id), m:GetAttribute("ActBody") == true, m:GetAttribute("ActPow") == true, now() - t0, m:GetAttribute("ActScale") or 1, m:GetAttribute("ActWhiff") == true
end

-- ================================================================== poses (local Motor6D transforms)
local function walkPose(st, dt, speedStuds, k)
	local speed = speedStuds / k -- m/s
	local amp = math.clamp(speed / 4.5, 0, 1)
	local run = math.clamp((speed - 3.6) / 3, 0, 1)
	local stride = Util.lerp(1.35, 2.5, run)
	st.phase += dt * (math.pi * 2 * speed / stride)
	st.idleT += dt
	local s, c = math.sin(st.phase), math.cos(st.phase)
	local Aw = (26 + run * 16) * amp
	local K = (38 + run * 50) * amp
	local thL, thR = s * Aw, -s * Aw
	local knL = -(math.max(0, c) * K + 4 + amp * 6)
	local knR = -(math.max(0, -c) * K + 4 + amp * 6)
	local sway = math.sin(st.idleT * 0.7) * (1 - amp)
	local bob = math.abs(c) * (0.02 + run * 0.03) * amp - 0.02 * amp
	local breathe = math.sin(st.idleT * (1.3 + run * 1.5))
	local armA = (24 + run * 26) * amp
	local elb = 14 + 18 * amp + 62 * run
	return {
		Root = CFrame.new((s * 0.018 * amp + sway * 0.012) * k, bob * k, 0) * deg(-3 * run, -s * 7 * amp, sway * 2),
		Waist = deg(-(3 * amp + 9 * run), s * 5 * amp, -sway * 1.5),
		Chest = deg(-(breathe * 1.2 + 3 * run), s * 7 * amp, 0),
		NeckJoint = deg(4 * amp + 8 * run, -s * 3 * amp, 0),
		Neck = deg((3 * amp + 9 * run) * 0.5 + breathe * 0.8, 0, 0),
		LeftHip = deg(thL, 0, -2), RightHip = deg(thR, 0, 2),
		LeftKnee = deg(knL, 0, 0), RightKnee = deg(knR, 0, 0),
		LeftAnkle = deg(-(thL + knL) * 0.6 + math.max(0, -s) * 18 * amp, 0, 0),
		RightAnkle = deg(-(thR + knR) * 0.6 + math.max(0, s) * 18 * amp, 0, 0),
		LeftShoulder = deg(-s * armA, 0, -(5 + run * 4)), RightShoulder = deg(s * armA, 0, 5 + run * 4),
		LeftElbow = deg(elb + math.max(0, s) * 18 * amp, 0, 0), RightElbow = deg(elb + math.max(0, -s) * 18 * amp, 0, 0),
		LeftWrist = CFrame.identity, RightWrist = CFrame.identity,
	}
end

local function downPose(st, k, u, fallBack, roll)
	-- u: 0 standing .. 1 flat on the canvas
	local buckle = math.clamp(u / 0.4, 0, 1)
	local fall = Util.smooth((u - 0.3) / 0.7)
	local tilt = (fallBack and 86 or -84) * fall
	local hipsDown = Util.lerp(0.22 * buckle, 0.84, fall)
	return {
		Root = CFrame.new(0, -hipsDown * k, (fallBack and 0.3 or -0.3) * fall * k) * deg(tilt, 0, roll * fall),
		Waist = deg(fallBack and -10 * fall or 8 * fall, 0, roll * 0.3),
		Chest = deg(0, 0, 0),
		NeckJoint = deg(fallBack and 15 * fall or -10 * fall, roll * 0.5, 0),
		Neck = deg(0, roll, roll * 0.4),
		LeftHip = deg(20 * fall + 30 * buckle * (1 - fall), 0, -8 * fall), RightHip = deg(35 * fall + 30 * buckle * (1 - fall), 0, 10 * fall),
		LeftKnee = deg(-60 * buckle * (1 - fall) - 25 * fall, 0, 0), RightKnee = deg(-60 * buckle * (1 - fall) - 50 * fall, 0, 0),
		LeftAnkle = deg(10 * fall, 0, 0), RightAnkle = deg(10 * fall, 0, 0),
		LeftShoulder = deg(20 * fall, 0, -(25 + 50 * fall)), RightShoulder = deg(10 * fall, 0, 25 + 60 * fall),
		LeftElbow = deg(30, 0, 0), RightElbow = deg(45 * fall + 20, 0, 0),
		LeftWrist = CFrame.identity, RightWrist = CFrame.identity,
	}
end

-- ================================================================== the boxing pose (FK + IK)
local function stepFoot(st, left, desired, dt, k, ground)
	local f = left and st.footL or st.footR
	local stepT = left and st.stepL or st.stepR
	local other = left and st.stepR or st.stepL
	if stepT >= 0 then
		stepT += dt / 0.13
		local u = math.clamp(stepT, 0, 1)
		local from = left and st.fromL or st.fromR
		local to = left and st.toL or st.toR
		f = from:Lerp(to, Util.smooth(u)) + V3(0, math.sin(u * math.pi) * 0.045 * k, 0)
		if stepT >= 1 then stepT = -1; f = to end
	elseif not (other >= 0 and other < 0.6) and Util.flat(f - desired).Magnitude > 0.1 * k then
		stepT = 0
		if left then st.fromL, st.toL = f, desired else st.fromR, st.toR = f, desired end
	else
		f = V3(f.X, ground, f.Z)
	end
	if left then st.footL, st.stepL = f, stepT else st.footR, st.stepR = f, stepT end
end

local function fightPose(st, dt, ctx)
	local m = st.model
	local k = ctx.k
	local hrpCF = ctx.hrpCF
	local fwd, right = hrpCF.LookVector, hrpCF.RightVector
	local southpaw = m:GetAttribute("Southpaw") == true
	local lead = southpaw and 1 or -1
	local stanceYaw = southpaw and 28 or -28
	local state = ctx.state
	local L = st.lean
	local duck, back, fwdLean = -math.min(0, L.Y), -math.min(0, L.Z), math.max(0, L.Z)
	local stam = m:GetAttribute("Stam") or 100
	local tired = stam < 30
	local rocked = (m:GetAttribute("Rocked") or 0) > 0
	local fatigue = m:GetAttribute("Fatigue") or 0
	st.clock = (st.clock or 0) + dt

	-- punch progress
	local def, body, power, t, scale, whiff = currentPunch(st)
	local twist, dip, ext = 0, 0, 0
	local w, e, r
	if def and state ~= "Clinch" then
		w, e, r = PunchData.Timing(def, power, body, scale, whiff)
		local wind = t < w and t / w or 0
		ext = t < w and 0 or (t < w + e and Util.easeOut((t - w) / e) or 1 - Util.smooth((t - w - e) / r))
		if t > w + e + r then def = nil; ext = 0 else
			local tw = def.twist * ext - def.twist * 0.25 * wind
			twist = -tw * (def.lead and 1 or -1) * (southpaw and -1 or 1)
			if body then dip = 0.6 * math.max(ext, wind) end
			if def.kind == "upper" then dip = math.max(dip, 0.4 * wind * (1 - ext) + 0.15 * ext) end
		end
	end

	-- body
	local moving = (ctx.vel.Magnitude / k) > 0.3
	local bounceAmp = ((state == "Intro" or moving) and 1 or 0.6) * (tired and 0.3 or 1) * (rocked and 0 or 1)
	st.bounce += dt * math.pi * 2 * (tired and 1.3 or 1.9)
	local bob = math.abs(math.sin(st.bounce)) * 0.016 * bounceAmp
	local wob = rocked and math.sin(st.clock * 2.3) * 6 or 0
	local hipDrop = 0.075 + duck * 0.2 + dip * 0.1 + (rocked and 0.04 or 0)
	local T = {}
	T.Root = CFrame.new(L.X * 0.11 * k, (-hipDrop + bob) * k, (0.02 + back * 0.06 - fwdLean * 0.04) * k)
		* deg(-(4 + duck * 10), stanceYaw * 0.8 + twist * 0.4, -L.X * 5 - wob * 0.5)
	T.Waist = deg(-(7 + duck * 24 + dip * 14 - back * 16 + fwdLean * 8), twist * 0.25 - stanceYaw * 0.15, -L.X * 13 - wob)
	T.Chest = deg(-(4 + duck * 8 - back * 7 + (tired and 6 or 0)) + st.chestSnap.X, twist * 0.35 - stanceYaw * 0.3 + st.chestSnap.Y, -L.X * 9 + st.chestSnap.Z)
	T.NeckJoint = deg(-(12 - duck * 6), 0, 0)
	T.Neck = deg(9 + duck * 10, 0, 0)
	if (m:GetAttribute("TauntT") or -9) > now() - 1.2 then
		T.Neck = deg(12, math.sin(st.clock * 14) * 15, 0)
		T.Chest = T.Chest * deg(8, 0, 0)
	end

	-- forward kinematics of the spine
	local c0 = st.c0
	local LT = hrpCF * c0.Root * T.Root
	local SP = LT * c0.Waist * T.Waist
	local UT = SP * c0.Chest * T.Chest

	-- feet: planted, stepping when the body moves away from them
	local ground = hrpCF.Position.Y - RigDef.HipHeightM * k
	local function off(isLead)
		return isLead and V3(lead * 0.05 * k, 0, -0.25 * k) or V3(-lead * 0.16 * k, 0, 0.19 * k)
	end
	local predict = ctx.vel * 0.16
	local dLead = hrpCF:PointToWorldSpace(off(true)) + predict
	local dRear = hrpCF:PointToWorldSpace(off(false)) + predict
	dLead = V3(dLead.X, ground, dLead.Z)
	dRear = V3(dRear.X, ground, dRear.Z)
	if not st.feetInit then
		st.footL = lead < 0 and dLead or dRear
		st.footR = lead < 0 and dRear or dLead
		st.feetInit = true
	end
	stepFoot(st, lead < 0, dLead, dt, k, ground)
	stepFoot(st, lead > 0, dRear, dt, k, ground)
	local function leg(isLeft)
		local hipName = isLeft and "LeftHip" or "RightHip"
		local kneeName = isLeft and "LeftKnee" or "RightKnee"
		local ankleName = isLeft and "LeftAnkle" or "RightAnkle"
		local isLead = (isLeft and lead < 0) or (not isLeft and lead > 0)
		local hipFrame = LT * c0[hipName]
		local foot = isLeft and st.footL or st.footR
		local footFwd = (CFrame.Angles(0, rad(stanceYaw * (isLead and 0.55 or 1.4)), 0) * fwd)
		if not isLead and def and not def.lead then footFwd = CFrame.Angles(0, rad(twist * 0.6), 0) * footFwd end
		local kneeDir = (fwd + right * (isLead and lead * -0.2 or -lead * 0.3)).Unit
		local upper, lower, tip = Util.twoBone(hipFrame.Position, foot + UP * 0.062 * k, hipFrame.Position + kneeDir * k, RigDef.UpperLeg * k, RigDef.LowerLeg * k, false, footFwd)
		T[hipName] = Util.relRot(hipFrame, upper)
		T[kneeName] = Util.relRot(upper * c0[kneeName], lower)
		local footCF = Util.flatLook(tip, footFwd)
		if not isLead then footCF = footCF * deg(-14, 0, 0) end
		T[ankleName] = Util.relRot(lower * c0[ankleName], footCF)
	end
	leg(true)
	leg(false)

	-- arms
	local O = UT:PointToWorldSpace(V3(0, 0.2 * k, -0.02 * k))
	local drop = math.clamp(fatigue * 0.7 + (rocked and 0.6 or 0), 0, 1)
	local guard = m:GetAttribute("Guard") or 0
	if ctx.isLocal and ctx.localGuard then guard = ctx.localGuard end
	st.guardHi = Util.moveTowards(st.guardHi, guard == 1 and 1 or 0, dt * 12)
	st.guardLo = Util.moveTowards(st.guardLo, guard == 2 and 1 or 0, dt * 12)
	local opp = ctx.opponent
	local function guardPos(isLead)
		local sx = isLead and lead or -lead
		local normal = isLead and (O + fwd * 0.25 * k + right * sx * 0.07 * k + UP * 0.1 * k) or (O + fwd * 0.13 * k + right * sx * 0.1 * k + UP * 0.13 * k)
		local high = O + fwd * (isLead and 0.15 or 0.12) * k + right * sx * 0.065 * k + UP * 0.2 * k
		local low = O + fwd * (isLead and 0.17 or 0.14) * k + right * sx * 0.09 * k + UP * (isLead and -0.1 or -0.15) * k
		local p = normal:Lerp(high, st.guardHi):Lerp(low, st.guardLo)
		p += UP * (-0.15 * drop * k) + fwd * (0.04 * drop * k)
		if state == "Intro" then p += (right * math.sin(st.clock * 3 + (isLead and 0 or 2)) * 0.03 + UP * math.sin(st.clock * 4.3 + sx) * 0.02) * k end
		return p
	end
	local function contactPoint()
		if opp then
			local oh = opp:FindFirstChild("Head")
			local ot = opp:FindFirstChild("UpperTorso")
			if body and ot then
				local leftHand = (def.lead and not southpaw) or (not def.lead and southpaw)
				local side = def.kind == "hook" and (leftHand and 1 or -1) or 0
				return ot.CFrame:PointToWorldSpace(V3(0.08 * side * k, 0.02 * k, -0.13 * k))
			elseif oh then
				return def.kind == "upper" and oh.CFrame:PointToWorldSpace(V3(0, 0.04 * k, -0.09 * k)) or oh.CFrame:PointToWorldSpace(V3(0, 0.12 * k, -0.1 * k))
			end
		end
		return O + fwd * 0.7 * k + UP * (body and -0.25 or 0.02) * k
	end
	for _, isLead in { true, false } do
		local rightArm = (isLead and lead > 0) or (not isLead and lead < 0)
		local sx = rightArm and 1 or -1
		local shName = rightArm and "RightShoulder" or "LeftShoulder"
		local elName = rightArm and "RightElbow" or "LeftElbow"
		local wrName = rightArm and "RightWrist" or "LeftWrist"
		local shFrame = UT * c0[shName]
		local sh = shFrame.Position
		local g = guardPos(isLead)
		local elbowHint = sh - UP * 0.35 * k + right * sx * 0.12 * k + fwd * 0.05 * k
		local backHand = (right * sx * 0.75 + fwd * 0.25 + UP * 0.2).Unit
		local target = g
		if def and def.lead == isLead and state ~= "Clinch" then
			local contact = contactPoint()
			local dirP = (contact - sh).Unit
			local wristAt = contact - dirP * 0.13 * k
			local maxR = 0.545 * k
			if (wristAt - sh).Magnitude > maxR then wristAt = sh + (wristAt - sh).Unit * maxR end
			local start, ctrl = g, nil
			if def.kind == "hook" then
				start = g + right * sx * 0.04 * k
				ctrl = g + right * sx * 0.34 * k + fwd * 0.12 * k + UP * (body and -0.1 or 0.02) * k
				elbowHint = sh + right * sx * 0.4 * k + UP * 0.2 * k
				backHand = backHand:Lerp(UP, ext).Unit
			elseif def.kind == "upper" then
				start = g - UP * 0.06 * k
				ctrl = g - UP * 0.22 * k + fwd * 0.1 * k - right * sx * 0.03 * k
				elbowHint = sh - UP * 0.4 * k + fwd * 0.1 * k
				backHand = backHand:Lerp(fwd, ext).Unit
			else
				ctrl = g:Lerp(wristAt, 0.5) + UP * 0.03 * k
				backHand = backHand:Lerp(UP, ext * 0.85).Unit
			end
			if t < w then target = g:Lerp(start - fwd * 0.035 * k, Util.smooth(t / w))
			elseif t < w + e then target = Util.bezier(start, ctrl, wristAt, Util.easeOut((t - w) / e))
			else target = wristAt:Lerp(g, Util.smooth((t - w - e) / r)) end
		elseif state == "Clinch" and opp and opp:FindFirstChild("UpperTorso") then
			target = opp.UpperTorso.CFrame:PointToWorldSpace(V3(0.2 * sx * k, 0.18 * k, 0.08 * k))
			elbowHint = sh + right * sx * 0.3 * k - UP * 0.1 * k
		elseif state == "Celebrate" then
			target = O + UP * 0.62 * k + right * sx * (0.24 + 0.04 * math.sin(st.clock * 6)) * k + fwd * 0.05 * k
			elbowHint = sh + right * sx * 0.4 * k
		elseif state == "Dejected" or (m:GetAttribute("TauntT") or -9) > now() - 1.2 then
			target = sh - UP * 0.5 * k + fwd * 0.08 * k + right * sx * 0.04 * k
		elseif state == "Corner" then
			target = O + right * sx * 0.58 * k + fwd * 0.2 * k + UP * 0.02 * k
			elbowHint = sh - UP * 0.3 * k
		end
		local upper, lower = Util.twoBone(sh, target, elbowHint, RigDef.UpperArm * k, RigDef.LowerArm * k, true, backHand)
		T[shName] = Util.relRot(shFrame, upper)
		T[elName] = Util.relRot(upper * c0[elName], lower)
		T[wrName] = CFrame.identity
	end
	if state == "Celebrate" then T.Root = CFrame.new(0, math.abs(math.sin(st.clock * 5)) * 0.08 * k, 0) * T.Root end
	return T
end

-- ================================================================== face
local function faceTick(st, dt, ctx)
	local f = st.face
	if not f.EyeL and not f.Jaw then return end
	local m = st.model
	local k = ctx.k
	local state = ctx.state
	local ko = state == "KO" or m:GetAttribute("Ragdolled") == true
	local down = state == "Down"
	local rocked = (m:GetAttribute("Rocked") or 0) > 0
	local fatigue = m:GetAttribute("Fatigue") or 0
	local daze = (rocked or down) and 0.8 or 0
	st.pain = Util.moveTowards(st.pain, 0, dt * 0.35)
	st.squintHold -= dt
	if st.squintHold <= 0 then st.squint = Util.moveTowards(st.squint, 0, dt * 2) end
	st.browUp = Util.moveTowards(st.browUp, 0, dt * 1.6)
	-- blink
	st.nextBlink -= dt
	if not ko and st.nextBlink <= 0 and st.blinkT < 0 then
		st.blinkT = 0
		st.nextBlink = (1.8 + math.random() * 3.7) * (daze > 0.3 and 0.5 or 1)
	end
	local blink = 0
	if st.blinkT >= 0 then
		st.blinkT += dt / 0.16
		blink = math.sin(math.clamp(st.blinkT, 0, 1) * math.pi)
		if st.blinkT >= 1 then st.blinkT = -1 end
	end
	-- jaw spring
	local tt = os.clock()
	local jawTarget = fatigue * (0.25 + 0.25 * (math.sin(tt * (2.5 + fatigue * 2)) * 0.5 + 0.5))
	if ko then jawTarget = 0.85 elseif daze > 0.2 then jawTarget = math.max(jawTarget, 0.3 * daze) end
	if (m:GetAttribute("SignalT") or -9) > now() - 0.8 then jawTarget = 0.35 + 0.25 * math.sin(tt * 13) end
	st.jawV += ((jawTarget - st.jaw) * 140 - st.jawV * 13) * dt
	st.jaw = math.clamp(st.jaw + st.jawV * dt, -0.05, 1.15)
	-- eyes
	st.saccadeT -= dt
	if st.saccadeT <= 0 then
		st.saccadeT = 0.4 + math.random() * 1.8
		st.saccadeTarget = Vector2.new(math.random() - 0.5, math.random() - 0.5) * (daze > 0.3 and 28 or 8)
	end
	st.saccade = st.saccade:Lerp(st.saccadeTarget or Vector2.zero, 1 - math.exp(-(daze > 0.3 and 3 or 25) * dt))
	local aim = Vector2.zero
	local head = m:FindFirstChild("Head")
	if ctx.lookAt and head then
		local l = head.CFrame:PointToObjectSpace(ctx.lookAt)
		aim = Vector2.new(math.clamp(math.deg(math.atan2(-l.X, -l.Z)), -32, 32), math.clamp(math.deg(math.atan2(l.Y - 0.158 * k, math.sqrt(l.X * l.X + l.Z * l.Z))), -25, 25))
	end
	st.eye = st.eye:Lerp(aim, 1 - math.exp(-18 * dt))
	local e = st.eye + st.saccade
	local roll = ko and 28 or daze * 6
	if f.EyeL then f.EyeL.Transform = deg(e.Y + roll, e.X - (daze > 0.4 and 5 or 0), 0) end
	if f.EyeR then f.EyeR.Transform = deg(e.Y + roll, e.X + (daze > 0.4 and 4 or 0), 0) end
	-- lids: swelling closes them
	local closeBase = ko and 0.62 or math.clamp(fatigue * 0.25 + daze * 0.35 + st.squint * 0.45, 0, 1)
	local function closure(side)
		local sw = m:GetAttribute("I_Eye" .. side) or 0
		local swell = math.clamp((sw - 0.35) * 1.4, 0, 1)
		return math.max(closeBase, blink, swell)
	end
	if f.LidL then f.LidL.Transform = CFrame.new(0, -0.021 * k * closure("L"), 0) end
	if f.LidR then f.LidR.Transform = CFrame.new(0, -0.021 * k * closure("R"), 0) end
	local up = (st.browUp * 0.006 - st.pain * 0.002 + daze * 0.002) * k
	if f.BrowL then f.BrowL.Transform = CFrame.new(0, up, 0) * deg(0, 0, -st.pain * 9) end
	if f.BrowR then f.BrowR.Transform = CFrame.new(0, up, 0) * deg(0, 0, st.pain * 9) end
end

local function jawTransform(st)
	return deg(-st.jaw * 21, 0, 0)
end

-- ================================================================== injuries, sweat, hair
local BRUISE = Color3.fromRGB(82, 26, 52)
local function injuryTick(st)
	local m = st.model
	for _, ip in st.injParts do
		local tag = ip.tag
		local v
		if tag == "CutBrowL" or tag == "CutCheekL" then v = m:GetAttribute("I_CutL") or 0
		elseif tag == "CutBrowR" or tag == "CutCheekR" then v = m:GetAttribute("I_CutR") or 0
		elseif tag == "StreakL" then v = math.max(0, (m:GetAttribute("I_CutL") or 0) - 0.25) * 1.5
		elseif tag == "StreakR" then v = math.max(0, (m:GetAttribute("I_CutR") or 0) - 0.25) * 1.5
		elseif tag == "NoseBlood" then v = math.max(0, (m:GetAttribute("I_Nose") or 0) - 0.45) * 2
		else v = m:GetAttribute("I_" .. tag) or 0 end
		local q = math.floor(v * 20) / 20
		if q ~= ip.shown then
			ip.shown = q
			local part = ip.part
			if q < 0.05 then
				part.LocalTransparencyModifier = 1
				part.Transparency = 1
			else
				part.Transparency = 0
				part.LocalTransparencyModifier = 0
				if string.find(tag, "Cut") or string.find(tag, "Streak") or tag == "NoseBlood" then
					if ip.mesh then ip.mesh.Scale = V3(math.min(1, 0.4 + q), math.min(1.2, 0.3 + q), 1) end
				else
					local s = 0.35 + q * 0.95
					if ip.mesh then ip.mesh.Scale = V3(s, s, 0.4 + q * 1.2) end
					part.Color = ip.base:Lerp(BRUISE, math.clamp(q * 0.7, 0, 0.75))
				end
			end
		end
	end
end

local function sweatTick(st, dt)
	local m = st.model
	local target = m:GetAttribute("Fighter") and math.clamp((m:GetAttribute("Fatigue") or 0) * 0.5 + 0.08, 0, 0.35) or 0
	local before = st.sweat
	st.sweat = Util.moveTowards(st.sweat, target, dt * 0.05)
	if math.abs(before - st.sweat) > 0 and math.floor(before * 50) ~= math.floor(st.sweat * 50) then
		for _, p in st.skinParts do
			if p.Material ~= Enum.Material.Metal then p.Reflectance = st.sweat end
		end
	end
end

local function hairTick(st, dt, headCF)
	if #st.strands == 0 then return end
	local prev = st.lastHeadPos
	local vel = prev and (headCF.Position - prev) / math.max(dt, 1 / 240) or Vector3.zero
	st.lastHeadPos = headCF.Position
	local lv = headCF:VectorToObjectSpace(vel)
	local g = headCF:VectorToObjectSpace(V3(0, -1, 0))
	for _, sd in st.strands do
		-- target angles: hang with gravity, trail behind motion
		local tx = math.clamp(-g.Z * 50 + lv.Z * 6, -60, 60)
		local tz = math.clamp(g.X * 50 - lv.X * 6, -60, 60)
		sd.vx += ((tx - sd.ax) * 60 - sd.vx * 7) * dt
		sd.vz += ((tz - sd.az) * 60 - sd.vz * 7) * dt
		sd.ax += sd.vx * dt
		sd.az += sd.vz * dt
		sd.motor.Transform = deg(sd.ax, 0, sd.az)
	end
end

-- ================================================================== main loop
local localPlayer = Players.LocalPlayer
Animator.LocalGuard = nil
Animator.LocalLean = nil

local function tickRig(st, dt)
	local m = st.model
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if not hrp or not m.Parent then return end
	if not st.scanned or not st.motors.Root then scan(st) end
	if not st.motors.Root then return end
	local k = m:GetAttribute("Scale") or 3.2
	local state = m:GetAttribute("State") or "Idle"
	local camPos = camera.CFrame.Position
	local dist = (hrp.Position - camPos).Magnitude
	-- far rigs update at a lower rate
	st.skip = ((st.skip or 0) + 1) % (dist > 140 and 4 or dist > 70 and 2 or 1)
	if st.skip ~= 0 then return end
	local isLocal = localPlayer and localPlayer.Character == m
	local oppVal = m:FindFirstChild("Opponent")
	local opp = oppVal and oppVal.Value
	local ragdolled = m:GetAttribute("Ragdolled") == true
	local ctx = { k = k, hrpCF = hrp.CFrame, vel = Util.flat(hrp.AssemblyLinearVelocity), state = state, opponent = opp, isLocal = isLocal }

	-- lean: local player sees their own input instantly
	local lean = V3(m:GetAttribute("LeanX") or 0, m:GetAttribute("LeanY") or 0, m:GetAttribute("LeanZ") or 0)
	if isLocal and Animator.LocalLean and m:GetAttribute("Fighter") then lean = Animator.LocalLean end
	if isLocal then ctx.localGuard = Animator.LocalGuard end
	st.lean = st.lean:Lerp(lean, 1 - math.exp(-14 * dt))

	-- springs
	st.headSnap, st.headV = spring(st.headSnap, st.headV, 180, 13, dt, 55)
	st.chestSnap, st.chestV = spring(st.chestSnap, st.chestV, 95, 11, dt, 35)

	local T
	if ragdolled then
		T = nil
	elseif state == "Down" or state == "KO" then
		local t0 = m:GetAttribute("DownT0") or now()
		local dir = m:GetAttribute("DownDir") or -hrp.CFrame.LookVector
		local fallBack = dir:Dot(hrp.CFrame.LookVector) < 0.3
		local roll = math.clamp(dir:Dot(hrp.CFrame.RightVector) * 40, -35, 35)
		T = downPose(st, k, math.clamp((now() - t0) / 0.75, 0, 1), fallBack, roll)
		st.downPose = T
		st.feetInit = false
	elseif state == "GetUp" then
		local t0 = m:GetAttribute("GetUpT0") or now()
		local u = math.clamp((now() - t0) / 1.5, 0, 1)
		local stand = fightPose(st, dt, ctx)
		T = lerpPose(st.downPose or downPose(st, k, 1, true, 0), stand, Util.smooth(u))
	elseif m:GetAttribute("Fighter") and state ~= "Idle" then
		T = fightPose(st, dt, ctx)
	else
		local def = currentPunch(st)
		if def then
			ctx.state = "Fight"
			T = fightPose(st, dt, ctx)
		else
			T = walkPose(st, dt, ctx.vel.Magnitude, k)
			st.feetInit = false
			-- referee signal arm
			local sigT = m:GetAttribute("SignalT")
			if sigT and now() - sigT < 0.9 then
				local kk = math.sin(math.clamp((now() - sigT) / 0.9, 0, 1) * math.pi)
				T.RightShoulder = deg(100 + 50 * kk, 0, 20)
				T.RightElbow = deg(30 - 20 * kk, 0, 0)
			end
		end
	end
	if T then
		-- sprung reactions on top of the pose
		local hs = st.headSnap
		T.NeckJoint = (T.NeckJoint or CFrame.identity) * deg(hs.X * 0.35, hs.Y * 0.35, hs.Z * 0.35)
		T.Neck = (T.Neck or CFrame.identity) * deg(hs.X * 0.65, hs.Y * 0.65, hs.Z * 0.65)
		-- head tracks the opponent / the camera
		local look = opp and opp:FindFirstChild("Head") and opp.Head.Position or (dist < 25 and camPos or nil)
		ctx.lookAt = look
		for name, mo in st.motors do
			local tr = T[name]
			if tr then mo.Transform = tr end
		end
	else
		ctx.lookAt = nil
	end
	if st.face.Jaw == nil and st.motors.Jaw then st.face.Jaw = st.motors.Jaw end
	if st.motors.Jaw then st.motors.Jaw.Transform = jawTransform(st) end
	if dist < 70 then
		if ctx.lookAt == nil and opp and opp:FindFirstChild("Head") then ctx.lookAt = opp.Head.Position end
		faceTick(st, dt, ctx)
		injuryTick(st)
		sweatTick(st, dt)
		local head = m:FindFirstChild("Head")
		if head then hairTick(st, dt, head.CFrame) end
	end
end

function Animator.Start()
	for _, m in CollectionService:GetTagged("NBRig") do add(m) end
	CollectionService:GetInstanceAddedSignal("NBRig"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("NBRig"):Connect(remove)
	RunService:BindToRenderStep("NeonBayAnimate", Enum.RenderPriority.Character.Value + 1, function(dt)
		camera = workspace.CurrentCamera
		for m, st in rigs do
			if m.Parent == nil then
				rigs[m] = nil
			else
				local ok, err = pcall(tickRig, st, dt)
				if not ok and not st.warned then
					st.warned = true
					warn("[NeonBay] animator:", err)
				end
			end
		end
	end)
end

return Animator
