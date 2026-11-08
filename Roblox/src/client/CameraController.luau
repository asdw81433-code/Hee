--[[
	Fight camera: over-the-shoulder framing of both fighters, a broadcast side angle (B / gamepad Y-click),
	a low knockdown angle, a slow KO orbit, a corner close-up that shows the damage on your face, and a
	result hero shot. Every mode goes through FX for shake, kicks and FOV punches. Outside fights the
	default Roblox camera is used.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FX = require(script.Parent.FX)

local CameraController = {}
CameraController.broadcast = false
CameraController.active = false

local player = Players.LocalPlayer
local pos, rot, fov = nil, nil, 50
local orbit = 0

local function myFighter()
	local c = player.Character
	if c and c:GetAttribute("Fighter") then return c end
	return nil
end

local function head(m)
	local h = m and m:FindFirstChild("Head")
	return h and (h.CFrame * CFrame.new(0, 0.42, 0)).Position or (m and m:GetPivot().Position) or Vector3.zero
end

local function flatUnit(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

function CameraController.Start()
	RunService:BindToRenderStep("NeonBayCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local cam = workspace.CurrentCamera
		local me = myFighter()
		local ringVal = me and me:FindFirstChild("Ring")
		local ring = ringVal and ringVal.Value
		if not me or not ring then
			if CameraController.active then
				CameraController.active = false
				cam.CameraType = Enum.CameraType.Custom
				cam.FieldOfView = 70
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then cam.CameraSubject = hum end
			end
			return
		end
		CameraController.active = true
		cam.CameraType = Enum.CameraType.Scriptable
		local oppVal = me:FindFirstChild("Opponent")
		local opp = oppVal and oppVal.Value
		local phase = ring:GetAttribute("Phase") or "Fight"
		local canvas = ring:FindFirstChild("Canvas")
		local center = canvas and (canvas.Position + Vector3.new(0, canvas.Size.Y / 2, 0)) or me:GetPivot().Position
		local ph, oh = head(me), head(opp)
		local k = me:GetAttribute("Scale") or 3.2
		orbit += dt * 0.25
		local wantPos, wantLook, wantFov
		if phase == "Intro" then
			local a = orbit * 0.6 + 0.8
			wantPos = center + Vector3.new(math.cos(a) * 17, 6, math.sin(a) * 17)
			wantLook = center + Vector3.new(0, 4.5, 0)
			wantFov = 46
		elseif phase == "Corner" then
			local h = me:FindFirstChild("Head")
			local f = h and flatUnit(h.CFrame.LookVector) or flatUnit(me:GetPivot().LookVector)
			wantPos = ph + f * 2.7 + Vector3.new(0, 0.1, 0) + me:GetPivot().RightVector * 0.6
			wantLook = ph
			wantFov = 34
		elseif phase == "Knockdown" then
			local downedName = ring:GetAttribute("Downed")
			local dm = downedName == "Red" and ring:FindFirstChild("RedModel") or ring:FindFirstChild("BlueModel")
			local dmod = dm and dm.Value
			local dp = dmod and dmod:FindFirstChild("LowerTorso") and dmod.LowerTorso.Position or center
			local side = flatUnit(dp - center):Cross(Vector3.yAxis)
			wantPos = dp + side * 8.5 + Vector3.new(0, 1.8, 0) - flatUnit(dp - center) * 2
			wantLook = dp + Vector3.new(0, 0.8, 0)
			wantFov = 48
		elseif phase == "KO" or phase == "Result" then
			local winner = ring:GetAttribute("WinnerCorner") or ""
			local loserModel = (winner == "Red") and opp or me
			if winner == "" then loserModel = opp end
			if phase == "Result" then
				local hero = (winner == "Blue") and opp or me
				local hh = head(hero)
				local f = hero and flatUnit(hero:GetPivot().LookVector) or Vector3.new(0, 0, -1)
				wantPos = hh + f * 7.5 + Vector3.new(0, -1, 0) + (hero and hero:GetPivot().RightVector or Vector3.xAxis) * 2
				wantLook = hh
				wantFov = 42
			else
				local lt = loserModel and loserModel:FindFirstChild("LowerTorso")
				local focus = lt and lt.Position or center
				local a = orbit * 1.6
				wantPos = focus + Vector3.new(math.cos(a) * 10, 2.3, math.sin(a) * 10)
				wantLook = focus + Vector3.new(0, 1, 0)
				wantFov = 44
			end
		else
			local toOpp = Vector3.new(oh.X - ph.X, 0, oh.Z - ph.Z)
			local dist = math.max(1, toOpp.Magnitude)
			local dir = toOpp / dist
			local right = dir:Cross(Vector3.yAxis)
			if CameraController.broadcast then
				local mid = (ph + oh) / 2
				local side = right
				if side:Dot(Vector3.new(center.X - mid.X, 0, center.Z - mid.Z)) > 0 then side = -side end
				wantPos = mid - side * (11 + dist * 0.8) + Vector3.new(0, 1.2, 0)
				wantLook = mid - Vector3.new(0, 0.2, 0)
				wantFov = 44
			else
				local back = 5.6 + math.clamp((dist / k - 0.6) / 1.6, 0, 1) * 2.1
				wantPos = ph - dir * back + right * 1.75 + Vector3.new(0, 0.95, 0)
				wantLook = ph:Lerp(oh, 0.68) - Vector3.new(0, 0.25, 0)
				wantFov = 48 + math.clamp((dist / k - 0.7) / 1.5, 0, 1) * 8
			end
		end
		local posK = (phase == "Fight") and 9 or 4
		if not pos then pos, rot, fov = wantPos, CFrame.lookAt(wantPos, wantLook), wantFov end
		pos = pos:Lerp(wantPos, 1 - math.exp(-posK * dt))
		local wantRot = CFrame.lookAt(pos, wantLook)
		rot = rot:Lerp(wantRot, 1 - math.exp(-11 * dt))
		fov += (wantFov - fov) * (1 - math.exp(-5 * dt))
		local off = FX.ShakeOffset(os.clock())
		local shakePos = Vector3.new(math.noise(os.clock() * 21, 0.1, 2), math.noise(0.3, os.clock() * 21, 2), 0) * FX.trauma * FX.trauma * 0.6
		cam.CFrame = CFrame.new(pos) * (rot - rot.Position) * CFrame.new(shakePos) * CFrame.Angles(math.rad(off.X), math.rad(off.Y), math.rad(off.Z))
		cam.FieldOfView = fov + FX.fov
	end)
end

return CameraController
