--[[
	Player data: look, career record, cash, training and injuries. Uses DataStoreService when the place is
	published with API access; otherwise (e.g. a local Studio test) it silently keeps data for the session.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("NeonBay")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Data = {}
Data.cache = {}

local store
do
	local ok, s = pcall(function() return DataStoreService:GetDataStore("NeonBayPit_v2") end)
	if ok then store = s end
end

local function defaults(player)
	local look = Util.deepCopy(Config.DefaultProfile)
	look.name = player and player.DisplayName or "Fighter"
	return {
		look = look,
		cash = Config.StartingCash,
		wins = 0, losses = 0, draws = 0, kos = 0, rank = 0,
		train = { pow = 0, spd = 0, eng = 0, chin = 0, def = 0, foot = 0 },
		injuries = {},
		created = false,
	}
end

local function merge(base, saved)
	if type(saved) ~= "table" then return base end
	for k, v in saved do
		if type(v) == "table" and type(base[k]) == "table" then
			merge(base[k], v)
		else
			base[k] = v
		end
	end
	return base
end

function Data.Load(player)
	local d = defaults(player)
	if store then
		local ok, saved = pcall(function() return store:GetAsync("p_" .. player.UserId) end)
		if ok and saved then merge(d, saved) end
	end
	Data.cache[player] = d
	return d
end

function Data.Get(player)
	return Data.cache[player]
end

function Data.Save(player)
	local d = Data.cache[player]
	if not d or not store then return end
	pcall(function() store:SetAsync("p_" .. player.UserId, d) end)
end

function Data.Release(player)
	Data.Save(player)
	Data.cache[player] = nil
end

--[[ Fight attributes of a player: RPG-free, driven by training. ]]
function Data.FightStats(d)
	local t = d.train
	return {
		power = 48 + t.pow * 4,
		speed = 50 + t.spd * 4,
		engine = 50 + t.eng * 4,
		chin = 48 + t.chin * 4,
		defense = 48 + t.def * 4,
		footwork = 50 + t.foot * 4,
		heart = 55 + (d.wins or 0) * 1.5,
	}
end

return Data
