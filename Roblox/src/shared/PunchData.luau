--[[ The six punches. Times in seconds, damage in health points, reach in meters (scaled by Config.S). ]]

local PunchData = {}

PunchData.List = {
	{ id = 1, name = "Jab", code = "1", lead = true, kind = "straight", windup = 0.05, extend = 0.10, recover = 0.15, damage = 4.2, stamina = 2.4, reach = 0.86, twist = 12 },
	{ id = 2, name = "Cross", code = "2", lead = false, kind = "straight", windup = 0.09, extend = 0.13, recover = 0.22, damage = 9.5, stamina = 5.2, reach = 0.9, twist = 40 },
	{ id = 3, name = "Lead Hook", code = "3", lead = true, kind = "hook", windup = 0.11, extend = 0.13, recover = 0.25, damage = 10.5, stamina = 6.0, reach = 0.66, twist = 34 },
	{ id = 4, name = "Rear Hook", code = "4", lead = false, kind = "hook", windup = 0.14, extend = 0.14, recover = 0.28, damage = 12.5, stamina = 7.0, reach = 0.64, twist = 38 },
	{ id = 5, name = "Lead Uppercut", code = "5", lead = true, kind = "upper", windup = 0.12, extend = 0.12, recover = 0.25, damage = 10.5, stamina = 6.0, reach = 0.6, twist = 18 },
	{ id = 6, name = "Rear Uppercut", code = "6", lead = false, kind = "upper", windup = 0.15, extend = 0.13, recover = 0.28, damage = 13.5, stamina = 7.5, reach = 0.6, twist = 30 },
}

-- extra windup / recovery for power and body variants (before speed scaling)
PunchData.PowerWindup = 0.11
PunchData.PowerRecover = 0.09
PunchData.BodyWindup = 0.03
PunchData.WhiffRecover = 0.12

function PunchData.Get(id)
	return PunchData.List[id]
end

function PunchData.Timing(def, power, body, scale, whiffed)
	local w = (def.windup + (power and PunchData.PowerWindup or 0) + (body and PunchData.BodyWindup or 0)) * scale
	local e = def.extend * scale
	local r = (def.recover + (power and PunchData.PowerRecover or 0) + (whiffed and PunchData.WhiffRecover or 0)) * scale
	return w, e, r
end

return PunchData
