-- Minimal Roblox API mock for smoke-testing Luau scripts in a plain Lua 5.3 VM.
-- Catches nil-index errors, wrong method names, unexpected property reads.
SIM_T = 0
ERRORS = {}
PROPWRITES = {}
FXLOG = {}

local function report(msg)
	table.insert(ERRORS, msg)
	print("!! ERROR: " .. tostring(msg))
end

math.clamp = function(x, a, b)
	if a > b then error("math.clamp: min > max") end
	if x < a then return a elseif x > b then return b end
	return x
end
math.sign = function(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
math.round = function(x) return math.floor(x + 0.5) end
local realFloor = math.floor
os.clock = function() return SIM_T end
function tick() return SIM_T end
function time() return SIM_T end
function warn(...) print("WARN:", ...) end

local TYPES = setmetatable({}, { __mode = "k" })
local function typed(t, name) TYPES[t] = name return t end
function typeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt and mt.__typeof then return mt.__typeof end
		return TYPES[v] or "table"
	end
	return type(v)
end

-- ===== Vector3 =====
local V3mt = { __typeof = "Vector3" }
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt) end
local function isV3(v) return getmetatable(v) == V3mt end
V3mt.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
	if k == "Abs" then return function(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end end
	error("Vector3: invalid member " .. tostring(k), 2)
end
local function chk(v, what) if not isV3(v) then error("Vector3 arithmetic with " .. typeof(v) .. " (" .. what .. ")", 3) end end
V3mt.__add = function(a, b) chk(a, "+") chk(b, "+") return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) chk(a, "-") chk(b, "-") return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then chk(b, "*") return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then chk(a, "*") return v3(a.X * b, a.Y * b, a.Z * b) end
	chk(a, "*") chk(b, "*")
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	chk(b, "/") return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return string.format("%.2f, %.2f, %.2f", a.X, a.Y, a.Z) end
V3mt.__newindex = function() error("Vector3 is immutable", 2) end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

local V2mt = { __typeof = "Vector2" }
V2mt.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	error("Vector2: invalid member " .. tostring(k), 2)
end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end }
Vector2.zero = Vector2.new(0, 0)

-- ===== CFrame (R = 3x3, columns = right, up, back) =====
local CFmt = { __typeof = "CFrame" }
local function cf(px, py, pz, R)
	return setmetatable({ p = v3(px, py, pz), R = R or { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } }, CFmt)
end
local function isCF(c) return getmetatable(c) == CFmt end
local function matmul(A, B)
	local C = {}
	for i = 1, 3 do
		C[i] = {}
		for j = 1, 3 do C[i][j] = A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j] end
	end
	return C
end
local function matvec(A, v)
	return v3(A[1][1] * v.X + A[1][2] * v.Y + A[1][3] * v.Z, A[2][1] * v.X + A[2][2] * v.Y + A[2][3] * v.Z, A[3][1] * v.X + A[3][2] * v.Y + A[3][3] * v.Z)
end
local function transpose(A)
	return { { A[1][1], A[2][1], A[3][1] }, { A[1][2], A[2][2], A[3][2] }, { A[1][3], A[2][3], A[3][3] } }
end
local function col(A, j) return v3(A[1][j], A[2][j], A[3][j]) end
local function fromCols(x, y, z) return { { x.X, y.X, z.X }, { x.Y, y.Y, z.Y }, { x.Z, y.Z, z.Z } } end
CFmt.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X end
	if k == "Y" then return c.p.Y end
	if k == "Z" then return c.p.Z end
	if k == "LookVector" then return -col(c.R, 3) end
	if k == "RightVector" then return col(c.R, 1) end
	if k == "UpVector" then return col(c.R, 2) end
	if k == "Rotation" then return setmetatable({ p = v3(0, 0, 0), R = c.R }, CFmt) end
	if k == "Inverse" then
		return function(a)
			local Rt = transpose(a.R)
			local np = -matvec(Rt, a.p)
			return setmetatable({ p = np, R = Rt }, CFmt)
		end
	end
	if k == "PointToWorldSpace" then return function(a, v) return matvec(a.R, v) + a.p end end
	if k == "PointToObjectSpace" then return function(a, v) return matvec(transpose(a.R), v - a.p) end end
	if k == "VectorToWorldSpace" then return function(a, v) return matvec(a.R, v) end end
	if k == "VectorToObjectSpace" then return function(a, v) return matvec(transpose(a.R), v) end end
	if k == "Lerp" then return function(a, b, t) return setmetatable({ p = a.p:Lerp(b.p, t), R = (t < 0.5) and a.R or b.R }, CFmt) end end
	error("CFrame: invalid member " .. tostring(k), 2)
end
local function ortho(R)
	-- Gram-Schmidt on columns (Roblox keeps CFrames orthonormal)
	local x = col(R, 1)
	local y = col(R, 2)
	local xm = x.Magnitude
	if xm == 0 or xm ~= xm then return R end
	x = x / xm
	y = y - x * x:Dot(y)
	local ym = y.Magnitude
	if ym == 0 or ym ~= ym then return R end
	y = y / ym
	local z = x:Cross(y)
	return fromCols(x, y, z)
end
CFmt.__mul = function(a, b)
	if not isCF(a) then error("CFrame * with left " .. typeof(a), 2) end
	if isCF(b) then return setmetatable({ p = matvec(a.R, b.p) + a.p, R = ortho(matmul(a.R, b.R)) }, CFmt) end
	if isV3(b) then return matvec(a.R, b) + a.p end
	error("CFrame * " .. typeof(b), 2)
end
CFmt.__add = function(a, b) if not isV3(b) then error("CFrame + " .. typeof(b), 2) end return setmetatable({ p = a.p + b, R = a.R }, CFmt) end
CFmt.__sub = function(a, b) return setmetatable({ p = a.p - b, R = a.R }, CFmt) end
CFmt.__newindex = function() error("CFrame is immutable", 2) end
local function rx(a) local c, s = math.cos(a), math.sin(a) return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
local function ry(a) local c, s = math.cos(a), math.sin(a) return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end
local function rz(a) local c, s = math.cos(a), math.sin(a) return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } end
function cfBad(c)
	local R = c.R
	for j = 1, 3 do
		local n = R[1][j] * R[1][j] + R[2][j] * R[2][j] + R[3][j] * R[3][j]
		if math.abs(n - 1) > 1e-4 or n ~= n then return true end
	end
	return false
end
CFrame = {}
CFrame.new = function(a, b, c, ...)
	if a == nil then return cf(0, 0, 0) end
	if isV3(a) then
		if b ~= nil then error("CFrame.new(pos, lookAt) deprecated in this mock") end
		return cf(a.X, a.Y, a.Z)
	end
	if select("#", ...) > 0 then error("CFrame.new with 12 numbers not mocked") end
	if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then error("CFrame.new bad args", 2) end
	return cf(a, b, c)
end
CFrame.Angles = function(x, y, z)
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then error("CFrame.Angles needs 3 numbers", 2) end
	return cf(0, 0, 0, matmul(matmul(rx(x), ry(y)), rz(z)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.lookAt = function(eye, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - eye).Unit
	local right = look:Cross(up).Unit
	local up2 = right:Cross(look)
	local c = cf(eye.X, eye.Y, eye.Z, fromCols(right, up2, -look))
	return c
end
CFrame.fromMatrix = function(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, fromCols(vx, vy, vz))
end
CFrame.identity = cf(0, 0, 0)

-- ===== simple value types =====
local C3mt = { __typeof = "Color3" }
C3mt.__index = function(c, k)
	if k == "Lerp" then return function(a, b, t) return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C3mt) end end
	error("Color3: invalid member " .. tostring(k), 2)
end
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end,
	fromRGB = function(r, g, b)
		if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then error("fromRGB bad args", 2) end
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3mt)
	end,
}
local U2mt = { __typeof = "UDim2" }
U2mt.__add = function(a, b) return setmetatable({ X = { Scale = a.X.Scale + b.X.Scale, Offset = a.X.Offset + b.X.Offset }, Y = { Scale = a.Y.Scale + b.Y.Scale, Offset = a.Y.Offset + b.Y.Offset } }, U2mt) end
UDim2 = {
	new = function(a, b, c, d) return setmetatable({ X = { Scale = a or 0, Offset = b or 0 }, Y = { Scale = c or 0, Offset = d or 0 } }, U2mt) end,
}
UDim2.fromScale = function(a, b) return UDim2.new(a, 0, b, 0) end
UDim2.fromOffset = function(a, b) return UDim2.new(0, a, 0, b) end
UDim = { new = function(a, b) return typed({ Scale = a, Offset = b }, "UDim") end }
NumberSequenceKeypoint = { new = function(t, v) return typed({ Time = t, Value = v }, "NumberSequenceKeypoint") end }
NumberSequence = { new = function(a) return typed({ Keypoints = a }, "NumberSequence") end }
ColorSequence = { new = function(a) return typed({ a }, "ColorSequence") end }
NumberRange = { new = function(a, b) return typed({ Min = a, Max = b or a }, "NumberRange") end }
TweenInfo = { new = function(...) return typed({ ... }, "TweenInfo") end }
PhysicalProperties = { new = function(...) if select("#", ...) ~= 5 and select("#", ...) ~= 3 then error("PhysicalProperties args") end return typed({ ... }, "PhysicalProperties") end }
RaycastParams = { new = function() return typed({ FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false }, "RaycastParams") end }
Random = {
	new = function(seed)
		local r = {}
		function r:NextNumber(a, b)
			a = a or 0
			b = b or 1
			return a + math.random() * (b - a)
		end
		function r:NextInteger(a, b)
			if a > b then error("NextInteger: min > max") end
			return math.random(a, b)
		end
		return typed(r, "Random")
	end,
}

-- ===== Enum =====
local enumCache = {}
local EnumItemMt = { __typeof = "EnumItem" }
EnumItemMt.__tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end
Enum = setmetatable({}, {
	__index = function(_, typeName)
		enumCache[typeName] = enumCache[typeName] or setmetatable({}, {
			__index = function(t, itemName)
				local item = setmetatable({ EnumType = typeName, Name = itemName, Value = 0 }, EnumItemMt)
				rawset(t, itemName, item)
				return item
			end,
		})
		return enumCache[typeName]
	end,
})

-- ===== scheduler =====
local queue = {}
local function schedule(at, co, args)
	table.insert(queue, { at = at, co = co, args = args })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(debug.traceback(co, tostring(err)))
	end
end
task = {}
task.spawn = function(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
task.defer = function(fn, ...) schedule(SIM_T, coroutine.create(fn), table.pack(...)) end
task.delay = function(t, fn, ...)
	if type(t) ~= "number" then error("task.delay needs number", 2) end
	schedule(SIM_T + t, coroutine.create(fn), table.pack(...))
end
task.wait = function(t)
	local co = coroutine.running()
	schedule(SIM_T + (t or 0.03), co, nil)
	coroutine.yield()
	return t
end
function runScheduler()
	local again = true
	while again do
		again = false
		for i = 1, #queue do
			local q = queue[i]
			if q and q.at <= SIM_T then
				table.remove(queue, i)
				if coroutine.status(q.co) == "suspended" then
					if q.args then resume(q.co, table.unpack(q.args, 1, q.args.n)) else resume(q.co) end
				end
				again = true
				break
			end
		end
	end
end

-- ===== Signals =====
local function Signal(name)
	local s = { conns = {}, name = name }
	function s:Connect(fn)
		if type(fn) ~= "function" then error("Connect needs function", 2) end
		local c = { fn = fn, Connected = true }
		function c:Disconnect() self.Connected = false end
		table.insert(self.conns, c)
		return c
	end
	function s:Once(fn)
		local c
		c = self:Connect(function(...) c:Disconnect() fn(...) end)
		return c
	end
	function s:Fire(...)
		local list = {}
		for _, c in ipairs(self.conns) do list[#list + 1] = c end
		for _, c in ipairs(list) do
			if c.Connected then task.spawn(c.fn, ...) end
		end
	end
	return typed(s, "RBXScriptSignal")
end
MockSignal = Signal

-- ===== Instances =====
local SUPER = {
	Part = "BasePart", SpawnLocation = "Part", MeshPart = "BasePart", BasePart = "PVInstance", Model = "PVInstance", Workspace = "Model",
	Motor6D = "JointInstance", Weld = "JointInstance", JointInstance = "Instance",
	TextLabel = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject", Frame = "GuiObject", ImageLabel = "GuiObject", GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector", SurfaceGui = "LayerCollector", BillboardGui = "LayerCollector", LayerCollector = "GuiBase2d",
	IntValue = "ValueBase", NumberValue = "ValueBase", StringValue = "ValueBase",
	Script = "BaseScript", LocalScript = "Script", ModuleScript = "LuaSourceContainer", BaseScript = "LuaSourceContainer",
	BallSocketConstraint = "Constraint", NoCollisionConstraint = "Instance", LinearVelocity = "Constraint", WeldConstraint = "Instance",
	PointLight = "Light", Highlight = "Instance",
}
local EVENTS = {
	Touched = true, Destroying = true, AncestryChanged = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true,
	HealthChanged = true, Died = true, Changed = true, OnServerEvent = true, OnClientEvent = true, Activated = true,
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, InputBegan = true, InputEnded = true,
	CharacterAdded = true, CharacterRemoving = true, PlayerAdded = true, PlayerRemoving = true, Heartbeat = true, Stepped = true, RenderStepped = true,
	PreSimulation = true, PostSimulation = true, StateChanged = true, MoveToFinished = true,
}
local DEFAULTS = {
	Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, Massless = false, Transparency = 0, Reflectance = 0,
	Size = v3(4, 1, 2), AssemblyLinearVelocity = v3(), AssemblyAngularVelocity = v3(), Enabled = true, Visible = true,
	Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, AutoRotate = true, PlatformStand = false, Jump = false,
	MoveDirection = v3(), CameraOffset = v3(), FloorMaterial = Enum.Material.Plastic, Text = "", TextTransparency = 0,
	BackgroundTransparency = 0, Rotation = 0, Value = 0, LayoutOrder = 0, PrimaryPart = nil, StudsOffset = v3(),
	Transform = CFrame.identity, C0 = CFrame.identity, C1 = CFrame.identity, Gravity = 196.2, CharacterAutoLoads = true,
	FieldOfView = 70, ViewportSize = Vector2.new(1280, 720), ZIndex = 1, CastShadow = true, HipHeight = 2,
}
local Methods = {}
local InstMT = { __typeof = "Instance" }
local allInstances = setmetatable({}, { __mode = "k" })
HUMANOIDS = {}

local function isA(cls, want)
	if want == "Instance" then return true end
	local c = cls
	while c do
		if c == want then return true end
		c = SUPER[c]
	end
	return false
end

local function getSig(o, name)
	local sigs = rawget(o, "__signals")
	sigs[name] = sigs[name] or Signal(name)
	return sigs[name]
end

function Instance_new(class)
	local o = setmetatable({ __class = class, __props = { Name = class }, __children = {}, __attrs = {}, __signals = {}, __attrSig = {}, __propSig = {} }, InstMT)
	allInstances[o] = true
	if class == "Humanoid" then HUMANOIDS[o] = true end
	if isA(class, "BasePart") then
		o.__props.CFrame = CFrame.identity
	end
	return o
end
Instance = { new = function(class, parent)
	local o = Instance_new(class)
	if parent then o.Parent = parent end
	return o
end }

local function findChild(o, name)
	for _, c in ipairs(rawget(o, "__children")) do
		if rawget(c, "__props").Name == name then return c end
	end
end

InstMT.__index = function(o, k)
	local m = Methods[k]
	if m then return m end
	local props = rawget(o, "__props")
	if k == "Parent" then return rawget(o, "__parent") end
	if k == "ClassName" then return rawget(o, "__class") end
	local v = props[k]
	if v ~= nil then return v end
	local cls = rawget(o, "__class")
	if k == "Position" and props.CFrame then return props.CFrame.Position end
	if k == "WorldPosition" and cls == "Attachment" then
		local p = rawget(o, "__parent")
		local c = props.CFrame or CFrame.identity
		if p and rawget(p, "__props").CFrame then return (rawget(p, "__props").CFrame * c).Position end
		return c.Position
	end
	if k == "AssemblyMass" then return 1 end
	local child = findChild(o, k)
	if child then return child end
	if EVENTS[k] then return getSig(o, k) end
	if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
	if k == "CFrame" and cls == "Attachment" then return CFrame.identity end
	if k == "PrimaryPart" or k == "Character" or k == "Adornee" or k == "Part0" or k == "Part1" or k == "PlayerToHideFrom" or k == "LocalPlayer" then return nil end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(k), cls, tostring(props.Name)), 2)
end

local function fireProp(o, k)
	local s = rawget(o, "__propSig")[k]
	if s then s:Fire() end
end

local function setParent(o, p)
	local old = rawget(o, "__parent")
	if old == p then return end
	if rawget(o, "__destroyed") then error("The Parent property of " .. tostring(rawget(o, "__props").Name) .. " is locked", 3) end
	if old then
		local ch = rawget(old, "__children")
		for i, c in ipairs(ch) do if c == o then table.remove(ch, i) break end end
	end
	rawset(o, "__parent", p)
	if p then
		table.insert(rawget(p, "__children"), o)
		getSig(p, "ChildAdded"):Fire(o)
	end
	getSig(o, "AncestryChanged"):Fire(o, p)
end

InstMT.__newindex = function(o, k, v)
	local cls = rawget(o, "__class")
	PROPWRITES[cls .. "." .. k] = true
	if k == "Parent" then setParent(o, v) return end
	local props = rawget(o, "__props")
	if k == "Position" and props.CFrame then
		local c = props.CFrame
		props.CFrame = setmetatable({ p = v, R = c.R }, CFmt)
		return
	end
	if k == "WorldPosition" and cls == "Attachment" then
		local p = rawget(o, "__parent")
		if p and rawget(p, "__props").CFrame then
			props.CFrame = rawget(p, "__props").CFrame:Inverse() * CFrame.new(v)
		else
			props.CFrame = CFrame.new(v)
		end
		return
	end
	if k == "CFrame" and not (getmetatable(v) == CFmt) then error("CFrame must be a CFrame, got " .. typeof(v), 2) end
	if k == "CFrame" and (v.p.X ~= v.p.X or v.R[1][1] ~= v.R[1][1] or v.R[2][2] ~= v.R[2][2]) then error("NaN CFrame written to " .. cls .. " " .. tostring(props.Name), 2) end
	if k == "CFrame" and cfBad(v) then error("non-orthonormal CFrame written to " .. cls .. " " .. tostring(props.Name), 2) end
	if isV3(v) and (v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z) then error("NaN Vector3 written to " .. cls .. "." .. k, 2) end
	if ((k == "Size" and isA(cls, "BasePart")) or k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" or k == "StudsOffset" or k == "CameraOffset") and not isV3(v) then
		error(k .. " must be Vector3, got " .. typeof(v), 2)
	end
	if (k == "Color" or k == "BackgroundColor3" or k == "TextColor3") and getmetatable(v) ~= C3mt then error(k .. " must be Color3", 2) end
	if (k == "Size" or k == "Position") and (isA(cls, "GuiObject") or cls == "BillboardGui") and typeof(v) ~= "UDim2" then
		error(k .. " must be UDim2 on " .. cls, 2)
	end
	if k == "Health" and cls == "Humanoid" then
		if v ~= v then error("Health NaN", 2) end
		local maxh = props.MaxHealth or 100
		local old = props.Health or 100
		v = math.max(0, math.min(maxh, v))
		props.Health = v
		if v ~= old then getSig(o, "HealthChanged"):Fire(v) end
		if v <= 0 and old > 0 and not rawget(o, "__dead") then
			rawset(o, "__dead", true)
			getSig(o, "Died"):Fire()
		end
		return
	end
	if type(v) == "number" and v ~= v then error("NaN written to " .. cls .. "." .. k, 2) end
	if k == "Character" and cls == "Player" then
		props.Character = v
		if v then getSig(o, "CharacterAdded"):Fire(v) end
		return
	end
	local old = props[k]
	props[k] = v
	if old ~= v then fireProp(o, k) end
end

InstMT.__tostring = function(o) return rawget(o, "__props").Name end

function Methods.FindFirstChild(o, name, recursive)
	local c = findChild(o, name)
	if c or not recursive then return c end
	for _, ch in ipairs(rawget(o, "__children")) do
		local r = Methods.FindFirstChild(ch, name, true)
		if r then return r end
	end
end
function Methods.WaitForChild(o, name, timeout)
	local c = findChild(o, name)
	if not c then
		-- emulate yield up to 1 sim second
		for _ = 1, 30 do
			if coroutine.isyieldable() then task.wait(0.03) else break end
			c = findChild(o, name)
			if c then break end
		end
	end
	if not c then print("WARN: WaitForChild timed out: " .. tostring(rawget(o, "__props").Name) .. "." .. name) end
	return c
end
function Methods.GetChildren(o)
	local t = {}
	for i, c in ipairs(rawget(o, "__children")) do t[i] = c end
	return t
end
function Methods.GetDescendants(o)
	local t = {}
	local function walk(x)
		for _, c in ipairs(rawget(x, "__children")) do
			t[#t + 1] = c
			walk(c)
		end
	end
	walk(o)
	return t
end
function Methods.IsA(o, cls) return isA(rawget(o, "__class"), cls) end
function Methods.FindFirstChildOfClass(o, cls)
	for _, c in ipairs(rawget(o, "__children")) do if rawget(c, "__class") == cls then return c end end
end
function Methods.FindFirstChildWhichIsA(o, cls)
	for _, c in ipairs(rawget(o, "__children")) do if isA(rawget(c, "__class"), cls) then return c end end
end
function Methods.FindFirstAncestorOfClass(o, cls)
	local p = rawget(o, "__parent")
	while p do
		if rawget(p, "__class") == cls then return p end
		p = rawget(p, "__parent")
	end
end
function Methods.FindFirstAncestor(o, name)
	local p = rawget(o, "__parent")
	while p do
		if rawget(p, "__props").Name == name then return p end
		p = rawget(p, "__parent")
	end
end
function Methods.IsDescendantOf(o, x)
	local p = rawget(o, "__parent")
	while p do
		if p == x then return true end
		p = rawget(p, "__parent")
	end
	return false
end
function Methods.Destroy(o)
	if rawget(o, "__destroyed") then return end
	getSig(o, "Destroying"):Fire()
	for _, c in ipairs(Methods.GetChildren(o)) do Methods.Destroy(c) end
	setParent(o, nil)
	rawset(o, "__destroyed", true)
	if MockOnDestroy then MockOnDestroy(o) end
end
function Methods.ClearAllChildren(o) for _, c in ipairs(Methods.GetChildren(o)) do Methods.Destroy(c) end end
local function cloneRec(o, map)
	local n = Instance_new(rawget(o, "__class"))
	map[o] = n
	for k, v in pairs(rawget(o, "__props")) do rawget(n, "__props")[k] = v end
	for k, v in pairs(rawget(o, "__attrs")) do rawget(n, "__attrs")[k] = v end
	rawset(n, "__source", rawget(o, "__source"))
	for _, c in ipairs(rawget(o, "__children")) do
		local cc = cloneRec(c, map)
		setParent(cc, n)
	end
	return n
end
function Methods.Clone(o)
	local map = {}
	local n = cloneRec(o, map)
	-- like Roblox: references to instances inside the cloned tree point to the copies
	for _, copy in pairs(map) do
		local pr = rawget(copy, "__props")
		for k, v in pairs(pr) do
			if type(v) == "table" and map[v] then pr[k] = map[v] end
		end
	end
	return n
end
function Methods.SetAttribute(o, k, v)
	local t = typeof(v)
	if v ~= nil and t ~= "number" and t ~= "string" and t ~= "boolean" and t ~= "Color3" and t ~= "Vector3" and t ~= "UDim2" and t ~= "CFrame" then
		error("SetAttribute: unsupported type " .. t .. " for " .. k, 2)
	end
	if type(v) == "number" and v == math.huge then
		-- Roblox supports inf
	end
	local attrs = rawget(o, "__attrs")
	local old = attrs[k]
	attrs[k] = v
	if old ~= v then
		local s = rawget(o, "__attrSig")[k]
		if s then s:Fire() end
	end
end
function Methods.GetAttribute(o, k) return rawget(o, "__attrs")[k] end
function Methods.GetAttributeChangedSignal(o, k)
	local t = rawget(o, "__attrSig")
	t[k] = t[k] or Signal("attr:" .. k)
	return t[k]
end
function Methods.GetPropertyChangedSignal(o, k)
	local t = rawget(o, "__propSig")
	t[k] = t[k] or Signal("prop:" .. k)
	return t[k]
end
local function parts(o)
	local t = {}
	if isA(rawget(o, "__class"), "BasePart") then t[1] = o end
	for _, d in ipairs(Methods.GetDescendants(o)) do
		if isA(rawget(d, "__class"), "BasePart") then t[#t + 1] = d end
	end
	return t
end
function Methods.GetPivot(o)
	if isA(rawget(o, "__class"), "BasePart") then return o.CFrame end
	local pp = rawget(o, "__props").PrimaryPart
	if pp then return pp.CFrame end
	local ps = parts(o)
	if #ps == 0 then return CFrame.identity end
	local s = v3()
	for _, p in ipairs(ps) do s = s + p.CFrame.Position end
	return CFrame.new(s / #ps)
end
function Methods.PivotTo(o, target)
	if getmetatable(target) ~= CFmt then error("PivotTo needs CFrame", 2) end
	if target.p.X ~= target.p.X or target.R[1][1] ~= target.R[1][1] then error("PivotTo NaN", 2) end
	if cfBad(target) then error("PivotTo non-orthonormal target", 2) end
	local pivot = Methods.GetPivot(o)
	local delta = target * pivot:Inverse()
	for _, p in ipairs(parts(o)) do
		local nc = delta * p.CFrame
		if nc.p.X ~= nc.p.X then error("PivotTo produced NaN for " .. tostring(rawget(p, "__props").Name) .. " pivot=" .. tostring(pivot.p) .. " R11=" .. tostring(pivot.R[1][1]) .. " partCF=" .. tostring(p.CFrame.p) .. " R=" .. tostring(p.CFrame.R[1][1]), 2) end
		rawget(p, "__props").CFrame = nc
	end
end
function Methods.GetBoundingBox(o) return Methods.GetPivot(o), v3(4, 5, 2) end
function Methods.SetNetworkOwner(o, owner)
	if not isA(rawget(o, "__class"), "BasePart") then error("SetNetworkOwner on non-part", 2) end
	if o.Anchored then error("Network Ownership API cannot be called on Anchored parts", 2) end
	if not o:IsDescendantOf(workspace) then error("Can only call SetNetworkOwner on descendants of Workspace", 2) end
end
function Methods.ChangeState(o, s) rawset(o, "__state", s) end
function Methods.GetState(o) return rawget(o, "__state") or Enum.HumanoidStateType.Running end
function Methods.MoveTo(o, pos, part)
	if not isV3(pos) then error("MoveTo needs Vector3", 2) end
	if pos.X ~= pos.X then error("MoveTo NaN", 2) end
	rawset(o, "__moveTarget", pos)
end
function Methods.TakeDamage(o, d) o.Health = o.Health - d end
function Methods.Play(o) end
function Methods.Stop(o) end
function Methods.FireServer(o, ...) table.insert(FXLOG, { "server", rawget(o, "__props").Name, ... }) end
function Methods.FireClient(o, player, ...)
	if typeof(player) ~= "Instance" or rawget(player, "__class") ~= "Player" then error("FireClient needs Player", 2) end
	table.insert(FXLOG, { "client", rawget(o, "__props").Name, ... })
end
function Methods.FireAllClients(o, ...)
	local args = { ... }
	table.insert(FXLOG, { "all", rawget(o, "__props").Name, ... })
	if MockOnFireAll then MockOnFireAll(rawget(o, "__props").Name, table.unpack(args)) end
end
function Methods.GetService(o, name)
	local s = findChild(o, name)
	if s then return s end
	s = Instance_new(name)
	rawget(s, "__props").Name = name
	setParent(s, o)
	return s
end
-- service-specific methods (bound on all instances; fine for a mock)
function Methods.GetPlayers(o)
	local t = {}
	for _, c in ipairs(rawget(o, "__children")) do if rawget(c, "__class") == "Player" then t[#t + 1] = c end end
	return t
end
function Methods.GetPlayerFromCharacter(o, model)
	for _, p in ipairs(Methods.GetPlayers(o)) do if rawget(p, "__props").Character == model then return p end end
end
function Methods.Raycast(o, origin, dir, params)
	if not isV3(origin) or not isV3(dir) then error("Raycast args", 2) end
	if origin.X ~= origin.X or dir.X ~= dir.X then error("Raycast NaN", 2) end
	if params ~= nil and typeof(params) ~= "RaycastParams" then error("Raycast params type", 2) end
	-- ground plane y = 0
	if dir.Y < 0 and origin.Y >= 0 and origin.Y + dir.Y <= 0 then
		local t = origin.Y / -dir.Y
		return { Position = origin + dir * t, Normal = v3(0, 1, 0), Instance = MOCK_GROUND, Material = Enum.Material.Asphalt, Distance = dir.Magnitude * t }
	end
	return nil
end
function Methods.GetServerTimeNow(o) return SIM_T + 1000 end
function Methods.AddItem(o, inst, t) task.delay(t or 10, function() if inst then inst:Destroy() end end) end
local tagged = {}
local tagAdded, tagRemoved = {}, {}
function Methods.AddTag(o, inst, tag)
	tagged[tag] = tagged[tag] or {}
	if not tagged[tag][inst] then
		tagged[tag][inst] = true
		if tagAdded[tag] then tagAdded[tag]:Fire(inst) end
	end
end
function Methods.RemoveTag(o, inst, tag)
	if tagged[tag] and tagged[tag][inst] then
		tagged[tag][inst] = nil
		if tagRemoved[tag] then tagRemoved[tag]:Fire(inst) end
	end
end
function Methods.HasTag(o, inst, tag) return tagged[tag] and tagged[tag][inst] or false end
function Methods.GetTagged(o, tag)
	local t = {}
	for inst in pairs(tagged[tag] or {}) do
		if not rawget(inst, "__destroyed") then t[#t + 1] = inst end
	end
	return t
end
function Methods.GetInstanceAddedSignal(o, tag) tagAdded[tag] = tagAdded[tag] or Signal("tagAdded") return tagAdded[tag] end
function Methods.GetInstanceRemovedSignal(o, tag) tagRemoved[tag] = tagRemoved[tag] or Signal("tagRemoved") return tagRemoved[tag] end
MockOnDestroy = function(o)
	for tag, set in pairs(tagged) do
		if set[o] then
			set[o] = nil
			if tagRemoved[tag] then tagRemoved[tag]:Fire(o) end
		end
	end
end
function Methods.Create(o, inst, info, goals)
	if typeof(inst) ~= "Instance" then error("Tween target must be Instance", 2) end
	if typeof(info) ~= "TweenInfo" then error("TweenInfo expected", 2) end
	local tw = {}
	function tw:Play() for k, v in pairs(goals) do inst[k] = v end end
	function tw:Cancel() end
	return tw
end
function Methods.BindToRenderStep(o, name, prio, fn) getSig(o, "RenderStepped"):Connect(fn) end
function Methods.GetGuiInset(o) return Vector2.new(0, 36), Vector2.new(0, 0) end

-- ===== world =====
game = Instance_new("DataModel")
rawget(game, "__props").Name = "Game"
workspace = game:GetService("Workspace")
local cam = Instance_new("Camera")
cam.CFrame = CFrame.new(0, 10, 20)
cam.Parent = workspace
rawget(workspace, "__props").CurrentCamera = cam
local terrain = Instance_new("Terrain")
terrain.Parent = workspace
rawget(workspace, "__props").Terrain = terrain
MOCK_GROUND = Instance_new("Part")
MOCK_GROUND.Anchored = true
MOCK_GROUND.Name = "MockGround"
MOCK_GROUND.Parent = workspace

-- ===== require =====
local moduleCache = {}
function loadScript(inst, isModule)
	local path = rawget(inst, "__source")
	local src = SOURCES[path]
	if not src then error("no source for " .. tostring(path)) end
	local env = setmetatable({ script = inst }, { __index = _G, __newindex = function(t, k, v)
		report("global assignment '" .. tostring(k) .. "' in " .. path)
		rawset(t, k, v)
	end })
	local fn, err = load(src, "@" .. path, "t", env)
	if not fn then error("compile " .. path .. ": " .. tostring(err)) end
	return fn
end
function require(inst)
	if typeof(inst) ~= "Instance" then error("require expects ModuleScript instance", 2) end
	if moduleCache[inst] ~= nil then return moduleCache[inst] end
	local fn = loadScript(inst, true)
	local r = fn()
	if r == nil then error("module returned nil: " .. rawget(inst, "__source")) end
	moduleCache[inst] = r
	return r
end
function mountModule(parent, name, path, class)
	local m = Instance_new(class or "ModuleScript")
	m.Name = name
	rawset(m, "__source", path)
	m.Parent = parent
	return m
end

-- humanoid locomotion: walk toward MoveTo target
function stepHumanoids(dt)
	for hum in pairs(HUMANOIDS) do
		local model = rawget(hum, "__parent")
		local target = rawget(hum, "__moveTarget")
		if model and not rawget(model, "__destroyed") and target and hum.Health > 0 and not hum.PlatformStand then
			local root = model:FindFirstChild("HumanoidRootPart")
			if root then
				local d = target - root.Position
				d = v3(d.X, 0, d.Z)
				local dist = d.Magnitude
				if dist > 0.3 then
					local step = math.min(dist, hum.WalkSpeed * dt)
					model:PivotTo(root.CFrame + d.Unit * step)
					rawget(hum, "__props").MoveDirection = d.Unit
				else
					rawget(hum, "__props").MoveDirection = v3()
				end
			end
		end
	end
end

function simStep(dt)
	SIM_T = SIM_T + dt
	runScheduler()
	stepHumanoids(dt)
	local rs = game:GetService("RunService")
	rs.Stepped:Fire(SIM_T, dt)
	rs.Heartbeat:Fire(dt)
	rs.RenderStepped:Fire(dt)
	runScheduler()
end

function getTaggedMock(tag) return game:GetService("CollectionService"):GetTagged(tag) end
