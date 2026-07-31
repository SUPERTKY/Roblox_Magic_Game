-- Roblox Fireball VFX installer
-- Studioを停止した状態で View > Command Bar に全体を貼り付けて実行してください。
--
-- 重要:
-- この版は、最初に旧魔法システムと旧操作UIを削除してから、
-- 火球の発射・飛行・命中・爆発VFXをインストールします。
-- 画像IDが未設定でも、旧システムの削除処理までは必ず実行されます。

local TEXTURE_IDS = {
	FireSoftBlob = "0", -- fire_soft_blob の画像ID
	SparkStreak = "0", -- spark_streak の画像ID
	FlashSoft = "0", -- flash_soft の画像ID
	ExplosionRing = "0", -- explosion_ring の画像ID
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

if RunService:IsRunning() then
	warn("[Fireball Installer] Play中です。旧スクリプトの接続が残る場合があるため、停止してからもう一度実行してください。")
end

local removedCount = 0

local function destroyObject(object)
	if object and object.Parent then
		object:Destroy()
		removedCount += 1
	end
end

local function destroyNamedChildren(parent, names)
	if not parent then
		return
	end

	for _, name in ipairs(names) do
		destroyObject(parent:FindFirstChild(name))
	end
end

local LEGACY_SCRIPT_NAMES = {
	["MagicController"] = true,
	["MagicController.client.lua"] = true,
	["MagicController.client.luau"] = true,
	["SpellClient"] = true,
	["SpellClient.lua"] = true,
	["SpellClient.client.lua"] = true,
	["SpellClient.client.luau"] = true,
	["MagicBattle"] = true,
	["MagicBattle.server.lua"] = true,
	["MagicBattle.server.luau"] = true,
	["WorldBuilder"] = true,
	["WorldBuilder.server.lua"] = true,
	["WorldBuilder.server.luau"] = true,
	["SpellService"] = true,
	["SpellService.lua"] = true,
	["SpellService.server.lua"] = true,
	["SpellService.server.luau"] = true,
	["SpellDefinitions"] = true,
	["SpellDefinitions.lua"] = true,
	["SpellDefinitions.luau"] = true,
	["FireballServer"] = true,
	["FireballClient"] = true,
}

local LEGACY_SOURCE_MARKERS = {
	"CustomSpellKind",
	"SaveCustomSpell",
	"GetSpellPreview",
	"CastSpellRequest",
	"LOBBY MAGIC FORGE",
	"MagicHud",
}

local function scriptLooksLegacy(object)
	if not object:IsA("LuaSourceContainer") then
		return false
	end

	if LEGACY_SCRIPT_NAMES[object.Name] then
		return true
	end

	local ok, source = pcall(function()
		return object.Source
	end)
	if not ok or typeof(source) ~= "string" then
		return false
	end

	local markerCount = 0
	for _, marker in ipairs(LEGACY_SOURCE_MARKERS) do
		if string.find(source, marker, 1, true) then
			markerCount += 1
		end
	end

	return markerCount >= 2
end

local function instanceDepth(object)
	local depth = 0
	local current = object.Parent
	while current do
		depth += 1
		current = current.Parent
	end
	return depth
end

local function removeLegacyScriptsBelow(root)
	if not root then
		return
	end

	local targets = {}
	for _, object in ipairs(root:GetDescendants()) do
		if scriptLooksLegacy(object) then
			table.insert(targets, object)
		end
	end

	table.sort(targets, function(a, b)
		return instanceDepth(a) > instanceDepth(b)
	end)

	for _, object in ipairs(targets) do
		destroyObject(object)
	end
end

local function removeOldMagicSystem()
	-- サーバー側の旧制御
	destroyNamedChildren(ServerScriptService, {
		"Magic",
		"MagicBattle",
		"MagicBattle.server.lua",
		"MagicBattle.server.luau",
		"WorldBuilder",
		"WorldBuilder.server.lua",
		"WorldBuilder.server.luau",
		"SpellService",
		"SpellService.server.lua",
		"SpellService.server.luau",
		"FireballServer",
	})
	removeLegacyScriptsBelow(ServerScriptService)

	-- クライアント側の旧操作
	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local starterCharacterScripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")

	destroyNamedChildren(starterPlayerScripts, {
		"MagicController",
		"MagicController.client.lua",
		"MagicController.client.luau",
		"SpellClient",
		"SpellClient.lua",
		"SpellClient.client.lua",
		"SpellClient.client.luau",
		"FireballClient",
	})
	destroyNamedChildren(starterCharacterScripts, {
		"MagicController",
		"MagicController.client.lua",
		"MagicController.client.luau",
		"SpellClient",
		"SpellClient.lua",
		"SpellClient.client.lua",
		"SpellClient.client.luau",
	})
	removeLegacyScriptsBelow(StarterPlayer)

	-- 旧UI
	destroyNamedChildren(StarterGui, {
		"MagicHud",
		"MagicGui",
		"SpellGui",
		"MagicForge",
	})
	removeLegacyScriptsBelow(StarterGui)

	for _, player in ipairs(Players:GetPlayers()) do
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		destroyNamedChildren(playerGui, {
			"MagicHud",
			"MagicGui",
			"SpellGui",
			"MagicForge",
		})

		for _, attributeName in ipairs({
			"Mana",
			"MaxMana",
			"CustomSpellName",
			"CustomSpellKind",
			"CustomSpellElement",
			"CustomSpellOrigin",
			"CustomSpellForm",
		}) do
			player:SetAttribute(attributeName, nil)
		end
	end

	-- 旧共有モジュール
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	destroyNamedChildren(shared, {
		"ElementDefs",
		"ElementDefs.lua",
		"ElementDefs.luau",
		"SpellDefs",
		"SpellDefs.lua",
		"SpellDefs.luau",
		"SpellDefinitions",
		"SpellDefinitions.lua",
		"SpellDefinitions.luau",
		"SharedUtil",
		"SharedUtil.lua",
		"SharedUtil.luau",
	})
	if shared and #shared:GetChildren() == 0 then
		destroyObject(shared)
	end

	-- 旧Remote
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	destroyNamedChildren(remotes, {
		"CastSpellRequest",
		"SpellFx",
		"GetSpellPreview",
		"SaveCustomSpell",
	})
	if remotes and #remotes:GetChildren() == 0 then
		destroyObject(remotes)
	end

	destroyNamedChildren(ReplicatedStorage, {
		"MagicRemotes",
		"MagicSystem",
		"FireballVFX",
	})

	-- 旧ランタイム生成物
	destroyNamedChildren(Workspace, {
		"MagicRuntime",
		"FireballRuntime",
	})

	for _, object in ipairs(Workspace:GetChildren()) do
		if string.sub(object.Name, 1, 14) == "MagicClientFx_" then
			destroyObject(object)
		elseif object:GetAttribute("FireballVFXRuntime") == true then
			destroyObject(object)
		end
	end
end

-- 画像IDの検証より先に削除します。
removeOldMagicSystem()
print(string.format("[Fireball Installer] 旧魔法システムを削除しました (%d objects)", removedCount))

local function contentId(value, label)
	local digits = tostring(value):match("(%d+)")
	if not digits or not tonumber(digits) or tonumber(digits) <= 0 then
		error(
			string.format(
				"%s の画像IDが未設定です。旧魔法システムの削除は完了しています。TEXTURE_IDSを設定してもう一度実行してください。",
				label
			),
			0
		)
	end
	return "rbxassetid://" .. digits
end

local TEXTURES = {
	Fire = contentId(TEXTURE_IDS.FireSoftBlob, "FireSoftBlob"),
	Spark = contentId(TEXTURE_IDS.SparkStreak, "SparkStreak"),
	Flash = contentId(TEXTURE_IDS.FlashSoft, "FlashSoft"),
	Ring = contentId(TEXTURE_IDS.ExplosionRing, "ExplosionRing"),
}

local root = Instance.new("Folder")
root.Name = "FireballVFX"
root.Parent = ReplicatedStorage

local castRequest = Instance.new("RemoteEvent")
castRequest.Name = "CastRequest"
castRequest.Parent = root

local templates = Instance.new("Folder")
templates.Name = "Templates"
templates.Parent = root

local function createPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	return part
end

local function createAttachment(parent, name, position)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position or Vector3.zero
	attachment.Parent = parent
	return attachment
end

local function createEmitter(parent, name, texture)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.ZOffset = 1
	emitter.Parent = parent
	return emitter
end

local fireColors = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 205)),
	ColorSequenceKeypoint.new(0.32, Color3.fromRGB(255, 168, 45)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 38, 5)),
})

local sparkColors = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 225)),
	ColorSequenceKeypoint.new(0.40, Color3.fromRGB(255, 190, 65)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(225, 65, 8)),
})

-- 飛行中の火球
local projectile = createPart("Projectile")
projectile.Shape = Enum.PartType.Ball
projectile.Size = Vector3.new(0.72, 0.72, 0.72)
projectile.Material = Enum.Material.Neon
projectile.Color = Color3.fromRGB(255, 128, 28)
projectile.Transparency = 0.08
projectile.Parent = templates

local projectileCenter = createAttachment(projectile, "Center", Vector3.zero)

local flame = createEmitter(projectileCenter, "Flame", TEXTURES.Fire)
flame.Enabled = true
flame.Rate = 34
flame.Lifetime = NumberRange.new(0.16, 0.30)
flame.Speed = NumberRange.new(0.8, 2.2)
flame.Drag = 2
flame.EmissionDirection = Enum.NormalId.Back
flame.SpreadAngle = Vector2.new(28, 28)
flame.Rotation = NumberRange.new(-18, 18)
flame.RotSpeed = NumberRange.new(-55, 55)
flame.Color = fireColors
flame.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.34),
	NumberSequenceKeypoint.new(0.32, 0.82),
	NumberSequenceKeypoint.new(1, 0),
})
flame.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.02),
	NumberSequenceKeypoint.new(0.62, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})

local flightSparks = createEmitter(projectileCenter, "FlightSparks", TEXTURES.Spark)
flightSparks.Enabled = true
flightSparks.Rate = 7
flightSparks.Lifetime = NumberRange.new(0.08, 0.16)
flightSparks.Speed = NumberRange.new(2.5, 5.5)
flightSparks.Drag = 2
flightSparks.EmissionDirection = Enum.NormalId.Back
flightSparks.SpreadAngle = Vector2.new(22, 22)
flightSparks.Orientation = Enum.ParticleOrientation.VelocityParallel
flightSparks.Color = sparkColors
flightSparks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.26),
	NumberSequenceKeypoint.new(1, 0),
})
flightSparks.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.70, 0.20),
	NumberSequenceKeypoint.new(1, 1),
})

local trailTop = createAttachment(projectile, "TrailTop", Vector3.new(0, 0.25, 0))
local trailBottom = createAttachment(projectile, "TrailBottom", Vector3.new(0, -0.25, 0))
local trail = Instance.new("Trail")
trail.Name = "FireTrail"
trail.Attachment0 = trailTop
trail.Attachment1 = trailBottom
trail.FaceCamera = true
trail.Lifetime = 0.15
trail.MinLength = 0.03
trail.LightEmission = 1
trail.Texture = TEXTURES.Spark
trail.TextureMode = Enum.TextureMode.Stretch
trail.Color = fireColors
trail.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.55, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})
trail.WidthScale = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0),
})
trail.Parent = projectile

local projectileLight = Instance.new("PointLight")
projectileLight.Name = "FireLight"
projectileLight.Color = Color3.fromRGB(255, 125, 28)
projectileLight.Brightness = 2.4
projectileLight.Range = 9
projectileLight.Shadows = false
projectileLight.Parent = projectile

-- 発射時
local cast = createPart("Cast")
cast.Parent = templates
local castAttachment = createAttachment(cast, "Center", Vector3.zero)

local castFlash = createEmitter(castAttachment, "CastFlash", TEXTURES.Flash)
castFlash:SetAttribute("EmitCount", 1)
castFlash.Lifetime = NumberRange.new(0.08, 0.13)
castFlash.Speed = NumberRange.new(0)
castFlash.Color = ColorSequence.new(Color3.fromRGB(255, 215, 125))
castFlash.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(0.20, 2.0),
	NumberSequenceKeypoint.new(1, 3.2),
})
castFlash.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 0.05),
	NumberSequenceKeypoint.new(1, 1),
})

local castFire = createEmitter(castAttachment, "CastFire", TEXTURES.Fire)
castFire:SetAttribute("EmitCount", 8)
castFire.Lifetime = NumberRange.new(0.16, 0.30)
castFire.Speed = NumberRange.new(2, 5)
castFire.Drag = 3
castFire.SpreadAngle = Vector2.new(180, 180)
castFire.Rotation = NumberRange.new(-25, 25)
castFire.RotSpeed = NumberRange.new(-65, 65)
castFire.Color = fireColors
castFire.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.22),
	NumberSequenceKeypoint.new(0.30, 0.68),
	NumberSequenceKeypoint.new(1, 0),
})
castFire.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.04),
	NumberSequenceKeypoint.new(0.70, 0.30),
	NumberSequenceKeypoint.new(1, 1),
})

local castSparks = createEmitter(castAttachment, "CastSparks", TEXTURES.Spark)
castSparks:SetAttribute("EmitCount", 12)
castSparks.Lifetime = NumberRange.new(0.12, 0.24)
castSparks.Speed = NumberRange.new(5, 12)
castSparks.Drag = 4
castSparks.SpreadAngle = Vector2.new(180, 180)
castSparks.Orientation = Enum.ParticleOrientation.VelocityParallel
castSparks.Color = sparkColors
castSparks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.30),
	NumberSequenceKeypoint.new(1, 0),
})
castSparks.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.65, 0.18),
	NumberSequenceKeypoint.new(1, 1),
})

-- 命中・爆発
local explosion = createPart("Explosion")
explosion.Parent = templates
local explosionAttachment = createAttachment(explosion, "Center", Vector3.zero)

local explosionFlash = createEmitter(explosionAttachment, "ExplosionFlash", TEXTURES.Flash)
explosionFlash:SetAttribute("EmitCount", 1)
explosionFlash.Lifetime = NumberRange.new(0.07, 0.11)
explosionFlash.Speed = NumberRange.new(0)
explosionFlash.Color = ColorSequence.new(Color3.fromRGB(255, 226, 145))
explosionFlash.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.65),
	NumberSequenceKeypoint.new(0.18, 4.0),
	NumberSequenceKeypoint.new(1, 5.8),
})
explosionFlash.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.20, 0.04),
	NumberSequenceKeypoint.new(1, 1),
})

local explosionRing = createEmitter(explosionAttachment, "ExplosionRing", TEXTURES.Ring)
explosionRing:SetAttribute("EmitCount", 1)
explosionRing.Lifetime = NumberRange.new(0.18, 0.23)
explosionRing.Speed = NumberRange.new(0)
explosionRing.Orientation = Enum.ParticleOrientation.FacingCamera
explosionRing.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 242, 190)),
	ColorSequenceKeypoint.new(0.52, Color3.fromRGB(255, 150, 30)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 48, 5)),
})
explosionRing.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(0.42, 7.2),
	NumberSequenceKeypoint.new(1, 10.5),
})
explosionRing.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.04),
	NumberSequenceKeypoint.new(0.50, 0.22),
	NumberSequenceKeypoint.new(1, 1),
})

local explosionSparks = createEmitter(explosionAttachment, "ExplosionSparks", TEXTURES.Spark)
explosionSparks:SetAttribute("EmitCount", 28)
explosionSparks.Lifetime = NumberRange.new(0.15, 0.34)
explosionSparks.Speed = NumberRange.new(11, 25)
explosionSparks.Drag = 5
explosionSparks.Acceleration = Vector3.new(0, -15, 0)
explosionSparks.SpreadAngle = Vector2.new(180, 180)
explosionSparks.Orientation = Enum.ParticleOrientation.VelocityParallel
explosionSparks.Color = sparkColors
explosionSparks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.38),
	NumberSequenceKeypoint.new(0.55, 0.20),
	NumberSequenceKeypoint.new(1, 0),
})
explosionSparks.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.70, 0.20),
	NumberSequenceKeypoint.new(1, 1),
})

local explosionFire = createEmitter(explosionAttachment, "ExplosionFire", TEXTURES.Fire)
explosionFire:SetAttribute("EmitCount", 16)
explosionFire.Lifetime = NumberRange.new(0.24, 0.48)
explosionFire.Speed = NumberRange.new(3, 9)
explosionFire.Drag = 5
explosionFire.Acceleration = Vector3.new(0, 3, 0)
explosionFire.SpreadAngle = Vector2.new(180, 180)
explosionFire.Rotation = NumberRange.new(-30, 30)
explosionFire.RotSpeed = NumberRange.new(-65, 65)
explosionFire.Color = fireColors
explosionFire.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.38),
	NumberSequenceKeypoint.new(0.25, 1.85),
	NumberSequenceKeypoint.new(0.66, 1.20),
	NumberSequenceKeypoint.new(1, 0),
})
explosionFire.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.04),
	NumberSequenceKeypoint.new(0.66, 0.28),
	NumberSequenceKeypoint.new(1, 1),
})

local explosionLight = Instance.new("PointLight")
explosionLight.Name = "ExplosionLight"
explosionLight.Color = Color3.fromRGB(255, 125, 25)
explosionLight.Brightness = 7
explosionLight.Range = 18
explosionLight.Shadows = false
explosionLight.Parent = explosion

local module = Instance.new("ModuleScript")
module.Name = "FireballVFX"
module.Parent = root
module.Source = [==[
--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ROOT = script.Parent
local TEMPLATES = ROOT:WaitForChild("Templates")
local FireballVFX = {}

local function markRuntime(object: Instance)
	object:SetAttribute("FireballVFXRuntime", true)
end

local function destroyLater(object: Instance, seconds: number)
	task.delay(seconds, function()
		if object.Parent then
			object:Destroy()
		end
	end)
end

local function emitStoredParticles(container: Instance)
	for _, object in ipairs(container:GetDescendants()) do
		if object:IsA("ParticleEmitter") then
			local count = object:GetAttribute("EmitCount")
			if typeof(count) == "number" and count > 0 then
				object:Emit(math.floor(count))
			end
		end
	end
end

function FireballVFX.Cast(cframe: CFrame): BasePart
	local effect = (TEMPLATES:WaitForChild("Cast") :: BasePart):Clone()
	markRuntime(effect)
	effect.CFrame = cframe
	effect.Parent = Workspace
	emitStoredParticles(effect)
	destroyLater(effect, 1)
	return effect
end

function FireballVFX.Explode(positionOrCFrame: Vector3 | CFrame): BasePart
	local cframe = if typeof(positionOrCFrame) == "CFrame"
		then positionOrCFrame
		else CFrame.new(positionOrCFrame)

	local effect = (TEMPLATES:WaitForChild("Explosion") :: BasePart):Clone()
	markRuntime(effect)
	effect.CFrame = cframe
	effect.Parent = Workspace
	emitStoredParticles(effect)

	local light = effect:FindFirstChildOfClass("PointLight")
	if light then
		TweenService:Create(
			light,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0, Range = 0 }
		):Play()
	end

	destroyLater(effect, 1.5)
	return effect
end

function FireballVFX.CreateProjectile(cframe: CFrame): BasePart
	local projectile = (TEMPLATES:WaitForChild("Projectile") :: BasePart):Clone()
	markRuntime(projectile)
	projectile.CFrame = cframe
	projectile.Parent = Workspace
	return projectile
end

function FireballVFX.Launch(config: {
	origin: Vector3,
	direction: Vector3,
	speed: number?,
	maxDistance: number?,
	ignore: {Instance}?,
	onHit: ((RaycastResult?) -> ())?,
}): BasePart
	assert(typeof(config) == "table", "Launchには設定テーブルを渡してください")
	assert(typeof(config.origin) == "Vector3", "originにはVector3を指定してください")
	assert(
		typeof(config.direction) == "Vector3" and config.direction.Magnitude > 0,
		"directionには0以外のVector3を指定してください"
	)

	local direction = config.direction.Unit
	local speed = math.max(1, tonumber(config.speed) or 92)
	local maxDistance = math.max(1, tonumber(config.maxDistance) or 145)
	local startCFrame = CFrame.lookAt(config.origin, config.origin + direction)

	FireballVFX.Cast(startCFrame)
	local projectile = FireballVFX.CreateProjectile(startCFrame)

	local ignoredInstances = {}
	if typeof(config.ignore) == "table" then
		for _, object in ipairs(config.ignore) do
			if typeof(object) == "Instance" then
				table.insert(ignoredInstances, object)
			end
		end
	end
	table.insert(ignoredInstances, projectile)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoredInstances
	params.IgnoreWater = true

	local traveled = 0
	local finished = false
	local connection: RBXScriptConnection?

	local function finish(position: Vector3, result: RaycastResult?)
		if finished then
			return
		end
		finished = true

		if connection then
			connection:Disconnect()
		end
		if projectile.Parent then
			projectile:Destroy()
		end

		FireballVFX.Explode(position)
		if typeof(config.onHit) == "function" then
			task.spawn(config.onHit, result)
		end
	end

	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not projectile.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local remaining = maxDistance - traveled
		if remaining <= 0 then
			finish(projectile.Position, nil)
			return
		end

		local stepDistance = math.min(speed * deltaTime, remaining)
		local currentPosition = projectile.Position
		local result = Workspace:Raycast(currentPosition, direction * stepDistance, params)
		if result then
			finish(result.Position, result)
			return
		end

		local nextPosition = currentPosition + direction * stepDistance
		projectile.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
		traveled += stepDistance

		if traveled >= maxDistance then
			finish(nextPosition, nil)
		end
	end)

	return projectile
end

return FireballVFX
]==]

local server = Instance.new("Script")
server.Name = "FireballServer"
server.Parent = ServerScriptService
server.Source = [==[
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("FireballVFX")
local castRequest = root:WaitForChild("CastRequest") :: RemoteEvent
local VFX = require(root:WaitForChild("FireballVFX"))

local COOLDOWN = 0.45
local lastCast: {[Player]: number} = {}

local function isFiniteVector3(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < 1000000
		and math.abs(value.Y) < 1000000
		and math.abs(value.Z) < 1000000
end

castRequest.OnServerEvent:Connect(function(player: Player, requestedDirection: any)
	local now = os.clock()
	if now - (lastCast[player] or 0) < COOLDOWN then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local direction = rootPart.CFrame.LookVector
	if isFiniteVector3(requestedDirection) and requestedDirection.Magnitude > 0.05 then
		direction = requestedDirection.Unit
	end

	lastCast[player] = now
	local origin = rootPart.Position + direction * 4 + Vector3.new(0, 1.35, 0)

	VFX.Launch({
		origin = origin,
		direction = direction,
		speed = 92,
		maxDistance = 145,
		ignore = { character },
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastCast[player] = nil
end)
]==]

local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local client = Instance.new("LocalScript")
client.Name = "FireballClient"
client.Parent = starterPlayerScripts
client.Source = [==[
--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 旧UIが保存・複製されていた場合も消します。
for _, name in ipairs({ "MagicHud", "MagicGui", "SpellGui", "MagicForge" }) do
	local oldGui = playerGui:FindFirstChild(name)
	if oldGui then
		oldGui:Destroy()
	end
end

for _, object in ipairs(Workspace:GetChildren()) do
	if string.sub(object.Name, 1, 14) == "MagicClientFx_" then
		object:Destroy()
	end
end

-- 過去のContextAction名が残っている場合に備えて解除します。
for _, actionName in ipairs({
	"CastSpell",
	"CastMagic",
	"MagicCast",
	"CycleElement",
	"CycleOrigin",
	"CycleForm",
	"CycleKind",
	"CastFireball",
}) do
	ContextActionService:UnbindAction(actionName)
end

local castRequest = ReplicatedStorage
	:WaitForChild("FireballVFX")
	:WaitForChild("CastRequest") :: RemoteEvent

local ACTION_NAME = "CastFireball"

local function castFireball(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	local camera = Workspace.CurrentCamera
	if camera then
		castRequest:FireServer(camera.CFrame.LookVector)
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(
	ACTION_NAME,
	castFireball,
	true,
	Enum.KeyCode.F,
	Enum.UserInputType.MouseButton1
)
ContextActionService:SetTitle(ACTION_NAME, "FIRE")
ContextActionService:SetPosition(ACTION_NAME, UDim2.fromScale(0.84, 0.72))
]==]

print("[Fireball Installer] インストール完了")
print("Play開始後、Fキー・左クリック・モバイルボタンで火球を発射できます")
