local H = require("./harness")
local roblox = require("@lune/roblox")
local Config = H.load("src/shared/Config.luau")
local Util = H.load("src/shared/Util.luau")
local CS = H.load("src/server/CharacterService.luau")
local count, parts = 0, 0
local ok, err = pcall(function()
	for hair = 1, #Config.HairNames do
		for beard = 1, #Config.BeardNames do
			local p = Util.deepCopy(Config.DefaultProfile)
			p.hair, p.beard = hair, beard
			p.female = (hair + beard) % 4 == 0
			p.brows = (hair % 5) + 1
			p.skin = (beard % #Config.SkinTones) + 1
			p.bulk = 0.85 + (hair % 6) * 0.1
			p.muscle = (beard % 4) / 3
			p.outfit = (hair % 3 == 0) and "street" or "boxer"
			p.chromeArm = beard == 10
			p.tattoo = hair % 2 == 0
			p.beardColor = beard % 3
			local model = CS.BuildRig(p, "Test", "CPU", roblox.CFrame.new(0, 0, 0))
			count += 1
			for _, d in model:GetDescendants() do if d:IsA("BasePart") then parts += 1 end end
		end
	end
end)
print(ok and ("OK: built " .. count .. " rigs, avg parts " .. math.floor(parts / math.max(1, count))) or ("FAIL: " .. tostring(err)))
-- IK check
local up, low, tip = Util.twoBone(roblox.Vector3.new(0, 0, 0), roblox.Vector3.new(0.3, -0.2, -0.25), roblox.Vector3.new(0, -1, 0.3), 0.29, 0.26, true, roblox.Vector3.new(0, 1, 0))
local elbow = up.Position + (-up.UpVector) * 0.29
local wrist = elbow + (-low.UpVector) * 0.26
print("IK error:", (wrist - roblox.Vector3.new(0.3, -0.2, -0.25)).Magnitude, " elbow-start match:", (low.Position - elbow).Magnitude)
