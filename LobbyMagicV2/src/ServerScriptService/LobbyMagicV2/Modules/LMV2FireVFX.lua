--!strict

-- 旧システムのコードは呼び出しません。
-- ReplicatedStorage/FireballVFX/Templates があれば、見た目のテンプレートだけを複製します。
-- テンプレートが無いPlaceでも確認できるように、内蔵テクスチャのフォールバックを持ちます。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FireVFX = {}

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local fireColors = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 205)),
	ColorSequenceKeypoint.new(0.32, Color3.fromRGB(255, 168, 45)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 38, 5)),
})

local function preparePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("LMV2_Runtime", true)
end

local function findLegacyTemplate(name: string): BasePart?
	local legacyRoot = ReplicatedStorage:FindFirstChild("FireballVFX")
	local templates = if legacyRoot then legacyRoot:FindFirstChild("Templates") else nil
	local template = if templates then templates:FindFirstChild(name) else nil
	return if template and template:IsA("BasePart") then template else nil
end

local function cloneLegacyTemplate(name: string): BasePart?
	local template = findLegacyTemplate(name)
	if not template then
		return nil
	end

	local clone = template:Clone()
	preparePart(clone)
	return clone
end

local function makeHiddenPart(name: string, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Transparency = 1
	part.CFrame = cframe
	preparePart(part)
	return part
end

local function emitStoredParticles(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local count = descendant:GetAttribute("EmitCount")
			if typeof(count) == "number" and count > 0 then
				descendant:Emit(math.floor(count))
			end
		end
	end
end

local function makeEmitter(parent: Instance, name: string, texture: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.ZOffset = 1
	emitter.Parent = parent
	return emitter
end

local function createFallbackProjectile(cframe: CFrame): BasePart
	local projectile = Instance.new("Part")
	projectile.Name = "LMV2_FireProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.72, 0.72, 0.72)
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(255, 128, 28)
	projectile.Transparency = 0.08
	projectile.CFrame = cframe
	preparePart(projectile)

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = projectile

	local flame = makeEmitter(center, "Flame", FIRE_TEXTURE)
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

	local sparks = makeEmitter(center, "FlightSparks", SPARK_TEXTURE)
	sparks.Enabled = true
	sparks.Rate = 7
	sparks.Lifetime = NumberRange.new(0.08, 0.16)
	sparks.Speed = NumberRange.new(2.5, 5.5)
	sparks.Drag = 2
	sparks.EmissionDirection = Enum.NormalId.Back
	sparks.SpreadAngle = Vector2.new(22, 22)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Color = fireColors
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.26),
		NumberSequenceKeypoint.new(1, 0),
	})

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 0.25, 0)
	top.Parent = projectile

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -0.25, 0)
	bottom.Parent = projectile

	local trail = Instance.new("Trail")
	trail.Name = "FireTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.Lifetime = 0.15
	trail.MinLength = 0.03
	trail.LightEmission = 1
	trail.Color = fireColors
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = projectile

	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = Color3.fromRGB(255, 125, 28)
	light.Brightness = 2.4
	light.Range = 9
	light.Shadows = false
	light.Parent = projectile

	return projectile
end

function FireVFX.CreateProjectile(cframe: CFrame, parent: Instance): BasePart
	local projectile = cloneLegacyTemplate("Projectile") or createFallbackProjectile(cframe)
	projectile.Name = "LMV2_FireProjectile"
	projectile.CFrame = cframe
	projectile.Parent = parent
	return projectile
end

function FireVFX.Cast(cframe: CFrame, parent: Instance)
	local effect = cloneLegacyTemplate("Cast")
	if effect then
		effect.Name = "LMV2_CastFx"
		effect.CFrame = cframe
		effect.Parent = parent
		emitStoredParticles(effect)
		Debris:AddItem(effect, 1.25)
		return
	end

	local part = makeHiddenPart("LMV2_CastFx", cframe)
	part.Parent = parent
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local burst = makeEmitter(attachment, "CastFire", FIRE_TEXTURE)
	burst.Enabled = false
	burst.Lifetime = NumberRange.new(0.14, 0.3)
	burst.Speed = NumberRange.new(3, 8)
	burst.Drag = 3
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Color = fireColors
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst:Emit(12)
	Debris:AddItem(part, 1)
end

function FireVFX.Explode(position: Vector3, parent: Instance)
	local effect = cloneLegacyTemplate("Explosion")
	if effect then
		effect.Name = "LMV2_ExplosionFx"
		effect.CFrame = CFrame.new(position)
		effect.Parent = parent
		emitStoredParticles(effect)

		local light = effect:FindFirstChildWhichIsA("PointLight", true)
		if light then
			TweenService:Create(light, TweenInfo.new(0.22), { Brightness = 0, Range = 0 }):Play()
		end
		Debris:AddItem(effect, 1.6)
		return
	end

	local part = makeHiddenPart("LMV2_ExplosionFx", CFrame.new(position))
	part.Parent = parent
	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local fire = makeEmitter(attachment, "ExplosionFire", FIRE_TEXTURE)
	fire.Enabled = false
	fire.Lifetime = NumberRange.new(0.24, 0.48)
	fire.Speed = NumberRange.new(3, 9)
	fire.Drag = 5
	fire.Acceleration = Vector3.new(0, 3, 0)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rotation = NumberRange.new(-30, 30)
	fire.RotSpeed = NumberRange.new(-65, 65)
	fire.Color = fireColors
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.38),
		NumberSequenceKeypoint.new(0.25, 1.85),
		NumberSequenceKeypoint.new(0.66, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	fire:Emit(18)

	local sparks = makeEmitter(attachment, "ExplosionSparks", SPARK_TEXTURE)
	sparks.Enabled = false
	sparks.Lifetime = NumberRange.new(0.15, 0.34)
	sparks.Speed = NumberRange.new(11, 25)
	sparks.Drag = 5
	sparks.Acceleration = Vector3.new(0, -15, 0)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Color = fireColors
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.38),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks:Emit(28)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 125, 25)
	light.Brightness = 7
	light.Range = 18
	light.Shadows = false
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(0.22), { Brightness = 0, Range = 0 }):Play()
	Debris:AddItem(part, 1.6)
end

return FireVFX
