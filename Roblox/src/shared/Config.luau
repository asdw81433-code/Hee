--[[
	NEON BAY: THE PIT  -  shared configuration
	Every number that shapes the fight lives here so the game can be tuned without touching the systems.

	SOUNDS: Roblox only plays audio the place is allowed to use. The defaults below are sounds that ship
	inside the Roblox client (rbxasset://), so they always work with zero setup. To use your own audio,
	upload it (or pick one from the Creator Store) and paste "rbxassetid://123456" over any id below.
]]

local Config = {}

Config.Version = "2.0"
Config.S = 3.2 -- studs per meter: every anatomy number is authored in meters and scaled by this

-- ring (studs, relative to the ring model's "Canvas" centre)
Config.Ring = {
	ropeHalf = 12, -- distance from centre to the rope line
	ropeHeights = { 1.5, 2.5, 3.5, 4.5 },
	postHeight = 4.9,
	fighterRadius = 0.95,
}

-- global damage tuning (shared by every punch); lower = longer fights
Config.DamageScale = 0.36
Config.PowerMult = 1.35
Config.CounterMult = 1.2

Config.Match = {
	introTime = 7,
	roundLength = 90,
	cornerTime = 11,
	resultTime = 9,
	countInterval = 1.0,
	countStartDelay = 1.6,
	pvpCountdown = 5,
}

Config.Movement = {
	lobbyWalkSpeed = 15,
	ringWalkSpeed = 10,
	ringJump = false,
}

Config.Sounds = {
	glove_head = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1.0, pitch = 1.45, distortion = 0.35 },
	glove_snap = { id = "rbxasset://sounds/snap.wav", volume = 0.35, pitch = 0.8 },
	glove_heavy = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1.0, pitch = 1.05, distortion = 0.55 },
	glove_body = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.95, pitch = 0.78, distortion = 0.2 },
	glove_block = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.8, pitch = 1.6 },
	whiff = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.22, pitch = 1.7 },
	bell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.9, pitch = 0.42, reverb = true },
	count = { id = "rbxasset://sounds/clickfast.wav", volume = 0.8, pitch = 0.7 },
	canvas = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1.0, pitch = 0.55, distortion = 0.3 },
	ko = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.9, pitch = 0.85 },
	rope = { id = "rbxasset://sounds/unsheath.wav", volume = 0.35, pitch = 0.45 },
	ui_click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.5, pitch = 1.2 },
	ui_good = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.3 },
	step = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.25, pitch = 1.0 },
	bag = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, pitch = 0.65 },
	-- optional ambience: paste a crowd loop id here to bring the stands to life
	crowd = { id = "", volume = 0.5, pitch = 1 },
}

-- ----------------------------------------------------------------- palette
Config.Neon = {
	Cyan = Color3.fromRGB(26, 242, 255),
	Magenta = Color3.fromRGB(255, 38, 191),
	Yellow = Color3.fromRGB(255, 216, 38),
	Orange = Color3.fromRGB(255, 115, 20),
	Red = Color3.fromRGB(255, 31, 38),
	Green = Color3.fromRGB(64, 255, 115),
	Purple = Color3.fromRGB(140, 51, 255),
	Blue = Color3.fromRGB(38, 115, 255),
	White = Color3.fromRGB(242, 247, 255),
}

Config.SkinTones = {
	Color3.fromRGB(245, 204, 176), Color3.fromRGB(230, 184, 143), Color3.fromRGB(204, 153, 110), Color3.fromRGB(171, 120, 82),
	Color3.fromRGB(133, 89, 59), Color3.fromRGB(92, 61, 41), Color3.fromRGB(64, 43, 31), Color3.fromRGB(179, 191, 204),
}
Config.ChromeSkin = 8

Config.HairColors = {
	Color3.fromRGB(13, 10, 10), Color3.fromRGB(64, 38, 20), Color3.fromRGB(166, 128, 77), Color3.fromRGB(230, 230, 235),
	Color3.fromRGB(255, 38, 191), Color3.fromRGB(26, 242, 255), Color3.fromRGB(230, 51, 51), Color3.fromRGB(64, 255, 115), Color3.fromRGB(140, 51, 255),
}
Config.HairColorNames = { "Black", "Brown", "Blonde", "Silver", "Neon Magenta", "Neon Cyan", "Red", "Toxic Green", "Violet" }

Config.TrunkColors = {
	Color3.fromRGB(184, 13, 26), Color3.fromRGB(15, 46, 153), Color3.fromRGB(13, 13, 15), Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(217, 158, 26), Color3.fromRGB(166, 20, 140), Color3.fromRGB(13, 153, 166), Color3.fromRGB(31, 115, 38),
}
Config.TrunkNames = { "Blood Red", "Royal Blue", "Midnight", "Ivory", "Gold", "Neon Orchid", "Cyan Static", "Jungle" }
Config.GloveColors = {
	Color3.fromRGB(191, 10, 15), Color3.fromRGB(15, 31, 140), Color3.fromRGB(15, 15, 18), Color3.fromRGB(230, 230, 230),
	Color3.fromRGB(230, 173, 26), Color3.fromRGB(230, 26, 153), Color3.fromRGB(26, 217, 230),
}
Config.GloveNames = { "Red", "Blue", "Black", "White", "Gold", "Magenta", "Cyan" }
Config.EyeColors = { Config.Neon.Cyan, Config.Neon.Magenta, Config.Neon.Yellow, Config.Neon.Orange, Config.Neon.Red, Config.Neon.Green, Config.Neon.Purple, Color3.fromRGB(90, 60, 30) }

Config.HairNames = {
	"Bald", "Buzz Cut", "Crew Cut", "High-Top Fade", "Slick Undercut", "Neon Mohawk", "Afro",
	"Dreadlocks", "Cornrows", "Man Bun", "Long & Loose", "Spiked", "Ponytail", "Messy Crop",
}
Config.BeardNames = { "Clean Shaven", "Stubble", "Mustache", "Goatee", "Chin Strap", "Short Beard", "Long Beard", "Mutton Chops", "Van Dyke", "Viking Braid" }
Config.BrowNames = { "Natural", "Heavy", "Arched", "Scarred", "None" }

Config.DefaultProfile = {
	name = "", nickname = "", female = false, skin = 3, hair = 5, hairColor = 1, beard = 2, beardColor = 0, brows = 1,
	eye = 1, jaw = 0.5, bulk = 1.0, muscle = 0.6, height = 1.0, trunks = 1, gloves = 1, accent = 2, southpaw = false, tattoo = false,
}

-- ----------------------------------------------------------------- career roster (the Pit's rankings, weakest first)
local function look(t)
	local p = table.clone(Config.DefaultProfile)
	for k, v in t do p[k] = v end
	return p
end

Config.Roster = {
	{ id = "nico", name = "Nico Ruiz", nick = "Neon", style = "OutBoxer", southpaw = false, w = 4, l = 3, ko = 1, purse = 450, rounds = 3,
		bio = "A Neon Strip bouncer who thinks the jab is a personality. Busy, light-footed, glass jaw.",
		stats = { power = 38, speed = 62, engine = 55, chin = 35, defense = 52, footwork = 64, heart = 45 },
		look = look({ skin = 3, hair = 12, hairColor = 1, beard = 3, bulk = 0.92, muscle = 0.45, trunks = 7, gloves = 7, accent = 1, jaw = 0.3 }) },
	{ id = "brick", name = "Sammy Kowalski", nick = "Brick", style = "Slugger", southpaw = false, w = 9, l = 6, ko = 8, purse = 700, rounds = 3,
		bio = "Dock worker. Hits like a falling container and moves like one too.",
		stats = { power = 72, speed = 30, engine = 45, chin = 70, defense = 30, footwork = 28, heart = 65 },
		look = look({ skin = 1, hair = 3, hairColor = 3, beard = 7, bulk = 1.32, muscle = 0.3, trunks = 3, gloves = 3, accent = 4, jaw = 1, brows = 2 }) },
	{ id = "fang", name = "Lee Fang", nick = "Twin Fang", style = "Swarmer", southpaw = true, w = 12, l = 4, ko = 7, purse = 1000, rounds = 4,
		bio = "Southpaw pressure fighter. Her brother is the other Fang. Neither of them backs up.",
		stats = { power = 55, speed = 66, engine = 70, chin = 55, defense = 50, footwork = 58, heart = 70 },
		look = look({ female = true, skin = 2, hair = 6, hairColor = 5, beard = 1, bulk = 1.0, muscle = 0.75, trunks = 6, gloves = 6, accent = 2, tattoo = true, jaw = 0.4 }) },
	{ id = "dara", name = "Dara Okafor", nick = "Static", style = "Counter", southpaw = false, w = 15, l = 2, ko = 6, purse = 1500, rounds = 4,
		bio = "Former Helix security. Patient, precise and impossible to hit clean.",
		stats = { power = 56, speed = 70, engine = 62, chin = 60, defense = 78, footwork = 66, heart = 60 },
		look = look({ skin = 6, hair = 9, hairColor = 1, beard = 5, bulk = 1.02, muscle = 0.8, trunks = 2, gloves = 2, accent = 8, jaw = 0.6 }) },
	{ id = "crane", name = "Mikhail Volkov", nick = "The Crane", style = "OutBoxer", southpaw = false, w = 18, l = 3, ko = 9, purse = 2100, rounds = 5,
		bio = "Seven feet of reach and a Russian accent from a holo-drama. Jab, jab, jab, goodnight.",
		stats = { power = 60, speed = 58, engine = 68, chin = 58, defense = 66, footwork = 70, heart = 58 },
		look = look({ skin = 1, hair = 5, hairColor = 4, beard = 9, bulk = 1.05, muscle = 0.6, trunks = 4, gloves = 4, accent = 9, height = 1.08, jaw = 0.8 }) },
	{ id = "lupe", name = "Lupe Santos", nick = "Lowtown Lightning", style = "Swarmer", southpaw = false, w = 21, l = 1, ko = 14, purse = 2800, rounds = 5,
		bio = "Fastest hands in Lowtown. Grew up dodging Jackal patrols, now she dodges everything.",
		stats = { power = 58, speed = 85, engine = 78, chin = 58, defense = 68, footwork = 80, heart = 75 },
		look = look({ female = true, skin = 4, hair = 13, hairColor = 2, bulk = 0.95, muscle = 0.85, trunks = 5, gloves = 5, accent = 3, height = 0.95, jaw = 0.35 }) },
	{ id = "benny", name = "Benny Castellano", nick = "Chrome Jaw", style = "Brawler", southpaw = false, w = 25, l = 5, ko = 21, purse = 3800, rounds = 6,
		bio = "Had his jaw replaced with titanium after his first loss. Has not been dropped since.",
		stats = { power = 76, speed = 50, engine = 60, chin = 92, defense = 40, footwork = 45, heart = 80 },
		look = look({ skin = 2, hair = 7, hairColor = 1, beard = 8, bulk = 1.22, muscle = 0.55, trunks = 1, gloves = 1, accent = 5, jaw = 1, brows = 4 }) },
	{ id = "polly", name = "Polly Marchetti", nick = "IRON POLLY", style = "Brawler", southpaw = false, w = 41, l = 0, ko = 38, purse = 6000, rounds = 6,
		bio = "Undefeated queen of the Pit. Reinforced titanium shins, a chrome right arm and zero mercy.",
		stats = { power = 88, speed = 66, engine = 80, chin = 85, defense = 62, footwork = 60, heart = 95 },
		look = look({ female = true, skin = 5, hair = 8, hairColor = 1, bulk = 1.25, muscle = 0.95, trunks = 3, gloves = 5, accent = 5, tattoo = true, eye = 5, chromeArm = true, jaw = 0.7 }) },
}

Config.StyleNames = { OutBoxer = "Out-Boxer", Swarmer = "Swarmer", Slugger = "Slugger", Counter = "Counter-Puncher", Brawler = "Brawler" }
Config.StyleDesc = {
	OutBoxer = "Lives behind the jab, circles away and wins rounds on the cards.",
	Swarmer = "Walks you down behind a high guard and digs to the body.",
	Slugger = "Slow feet, heavy hands. One clean shot can end the night.",
	Counter = "Waits for you to miss, then makes you pay double.",
	Brawler = "Wild, chrome-plated and fearless. Throws everything.",
}

Config.Training = {
	{ key = "pow", name = "Power (heavy bag)" },
	{ key = "spd", name = "Hand Speed (speed bag)" },
	{ key = "eng", name = "Engine (roadwork)" },
	{ key = "chin", name = "Chin (neck work)" },
	{ key = "def", name = "Defense (slip rope)" },
	{ key = "foot", name = "Footwork (ladder drills)" },
}
Config.TrainMax = 10
function Config.TrainCost(level)
	return 250 + level * 220
end

Config.StartingCash = 500

return Config
