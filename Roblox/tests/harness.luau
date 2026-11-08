--[[ Runs the real game modules under Lune with a small mock of the Roblox runtime. ]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local H = {}
local SRC = "src"
local clock = 0
H.now = function() return clock end
H.advance = function(dt) clock += dt end

local deferred = {}
local taskLib = {
	delay = function(t, fn, ...) table.insert(deferred, { at = clock + t, fn = fn, args = { ... } }) end,
	defer = function(fn, ...) table.insert(deferred, { at = clock, fn = fn, args = { ... } }) end,
	spawn = function(fn, ...) table.insert(deferred, { at = clock, fn = fn, args = { ... } }) end,
	wait = function() return 0 end,
}
function H.runDeferred()
	local keep = {}
	local run = {}
	for _, d in deferred do if d.at <= clock then table.insert(run, d) else table.insert(keep, d) end end
	deferred = keep
	for _, d in run do d.fn(table.unpack(d.args)) end
end

-- services
local services = {}
local function signal() return { Connect = function() return { Disconnect = function() end } end } end
local fired = {}
H.fired = fired
local function remote(name)
	return { Name = name, FireAllClients = function(_, ev) table.insert(fired, { name = name, ev = ev }) end, FireClient = function(_, _, ev) table.insert(fired, { name = name, ev = ev }) end, OnServerEvent = signal() }
end
local remotesFolder = { Impact = remote("Impact"), MatchEvent = remote("MatchEvent"), Notify = remote("Notify"), Input = remote("Input"), Lean = remote("Lean") }
function remotesFolder:WaitForChild(n) return self[n] end

local moduleCache = {}
local function makeScriptNode(dir, name)
	return { __dir = dir, __name = name }
end

local env
local function loadModule(path)
	if moduleCache[path] then return moduleCache[path] end
	local src = fs.readFile(path)
	local dir = string.match(path, "^(.*)/[^/]+$")
	local scriptObj = setmetatable({}, { __index = function(_, k)
		if k == "Parent" then
			return setmetatable({}, { __index = function(_, child) return { __path = dir .. "/" .. child .. ".luau" } end })
		end
		return nil
	end })
	local e = { script = scriptObj }
	for k, v in env do e[k] = v end
	for _, k in { "math", "string", "table", "print", "pcall", "type", "tostring", "tonumber", "pairs", "ipairs", "setmetatable", "getmetatable", "error", "select", "next", "rawget", "rawset", "assert", "xpcall" } do
		if e[k] == nil then e[k] = (_G :: any)[k] end
	end
	local fn = luau.load(src, { debugName = path, environment = e })
	local result = fn()
	moduleCache[path] = result
	return result
end

local sharedFolder = setmetatable({}, { __index = function(_, k) return { __path = SRC .. "/shared/" .. k .. ".luau" } end })
services.ReplicatedStorage = { WaitForChild = function(_, n) if n == "NeonBay" then return sharedFolder end if n == "NeonBayRemotes" then return remotesFolder end end }
services.CollectionService = { AddTag = function() end, GetTagged = function() return {} end }
services.Players = { CharacterAutoLoads = true, GetPlayers = function() return {} end, PlayerAdded = signal(), PlayerRemoving = signal() }
services.RunService = { Heartbeat = signal(), RenderStepped = signal() }
services.DataStoreService = { GetDataStore = function() error("no API access in tests") end }
services.TextService = {}
services.PhysicsService = {}

local Workspace = { Gravity = 196.2 }
function Workspace:GetServerTimeNow() return clock end

env = setmetatable({
	game = { GetService = function(_, n) return services[n] or {} end, BindToClose = function() end },
	workspace = Workspace,
	Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
	Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence, BrickColor = roblox.BrickColor,
	task = taskLib, warn = function(...) print("WARN", ...) end,
	require = function(m)
		if type(m) == "table" and m.__path then return loadModule(m.__path) end
		error("bad require " .. tostring(m))
	end,
}, { __index = _G })
for _, k in { "math", "string", "table", "os", "print", "pcall", "type", "typeof", "tostring", "tonumber", "pairs", "ipairs", "setmetatable", "getmetatable", "error", "select", "next", "rawget", "rawset", "assert", "unpack" } do
	if env[k] == nil then env[k] = (_G :: any)[k] end
end
env.os = { clock = function() return clock end, time = os.time }
env.typeof = typeof

H.load = loadModule
H.env = env
H.remotes = remotesFolder
H.SRC = SRC
return H
