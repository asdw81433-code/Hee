--[[ Math helpers shared by client and server: easing, damping and two-bone IK on CFrames. ]]

local Util = {}

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Util.easeOut(t)
	t = math.clamp(t, 0, 1)
	local u = 1 - t
	return 1 - u * u * u
end

function Util.damp(a, b, lambda, dt)
	return a + (b - a) * (1 - math.exp(-lambda * dt))
end

function Util.dampV(a: Vector3, b: Vector3, lambda, dt): Vector3
	return a:Lerp(b, 1 - math.exp(-lambda * dt))
end

function Util.moveTowards(a, b, d)
	if math.abs(b - a) <= d then
		return b
	end
	return a + math.sign(b - a) * d
end

function Util.moveTowardsV(a: Vector3, b: Vector3, d): Vector3
	local diff = b - a
	local m = diff.Magnitude
	if m <= d or m < 1e-6 then
		return b
	end
	return a + diff / m * d
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.flatUnit(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function Util.bezier(a: Vector3, c: Vector3, b: Vector3, t): Vector3
	local u = 1 - t
	return a * (u * u) + c * (2 * u * t) + b * (t * t)
end

--[[ CFrame whose -Y axis points along `down` and whose front (-Z, LookVector) faces `front` as closely as possible. ]]
function Util.alongDown(pos: Vector3, down: Vector3, front: Vector3): CFrame
	local d = down.Magnitude > 1e-6 and down.Unit or Vector3.new(0, -1, 0)
	local up = -d
	local f = front - up * front:Dot(up)
	if f.Magnitude < 1e-4 then
		local alt = math.abs(up.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		f = alt:Cross(up)
	end
	f = f.Unit
	return CFrame.fromMatrix(pos, f:Cross(up), up, -f)
end

--[[ Flat-on-the-floor orientation facing `look`. ]]
function Util.flatLook(pos: Vector3, look: Vector3): CFrame
	local f = Util.flatUnit(look)
	return CFrame.fromMatrix(pos, f:Cross(Vector3.yAxis), Vector3.yAxis, -f)
end

--[[
	Two-bone IK. Returns (upperCFrame, lowerCFrame) in world space.
	root = joint position, target = end position, hint = point the middle joint should bend towards,
	l1/l2 = bone lengths, bendFront: true when the lower bone folds towards the upper bone's front (elbows),
	false when it folds backwards (knees). lowerFront = desired front axis of the lower bone.
]]
function Util.twoBone(root: Vector3, target: Vector3, hint: Vector3, l1: number, l2: number, bendFront: boolean, lowerFront: Vector3)
	local d = target - root
	local dist = math.clamp(d.Magnitude, math.abs(l1 - l2) + 0.02, l1 + l2 - 0.002)
	local dir = d.Magnitude > 1e-6 and d.Unit or Vector3.new(0, -1, 0)
	local h = hint - root
	h = h - dir * h:Dot(dir)
	if h.Magnitude < 1e-5 then
		h = Vector3.new(0, 0, -1) - dir * dir.Z * -1
		if h.Magnitude < 1e-5 then
			h = Vector3.xAxis
		end
	end
	h = h.Unit
	local cosA = math.clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
	local a = math.acos(cosA)
	local mid = root + (dir * math.cos(a) + h * math.sin(a)) * l1
	local tip = root + dir * dist
	local upperDown = mid - root
	local lowerDown = tip - mid
	local lowerPerp = lowerDown - upperDown.Unit * lowerDown:Dot(upperDown.Unit)
	local upperFront = bendFront and lowerPerp or -lowerPerp
	if upperFront.Magnitude < 1e-5 then
		upperFront = bendFront and -h or h
	end
	local upperCF = Util.alongDown(root, upperDown, upperFront)
	local lowerCF = Util.alongDown(mid, lowerDown, lowerFront)
	return upperCF, lowerCF, tip
end

--[[ Rotation-only relative CFrame of child world `w1` against parent frame `frame0` (= Part0.CFrame * C0). ]]
function Util.relRot(frame0: CFrame, w1: CFrame): CFrame
	local rel = frame0:ToObjectSpace(w1)
	return rel - rel.Position
end

function Util.formatTime(t)
	t = math.max(0, t)
	return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

function Util.deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in t do
		o[k] = Util.deepCopy(v)
	end
	return o
end

return Util
