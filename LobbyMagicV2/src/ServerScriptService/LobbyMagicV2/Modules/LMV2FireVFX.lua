--!strict

-- RobloxMagicSystem/InstallRobloxMagicSystem.lua が作成する炎VFX専用アダプターです。
-- 旧FireballVFX ModuleScriptの飛行処理は呼ばず、Templatesの見た目だけを複製します。

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VFX_ROOT_NAME = "FireballVFX"
local TEMPLATES_NAME = "Templates"
local REQUIRED_TEMPLATES = {
	"Projectile",
	"Cast",
	"Explosion",
}

local FireVFX = {}

local function getTemplatesFolder(): Instance?
	local root = ReplicatedStorage:FindFirstChild(VFX_ROOT_NAME)
	return if root then root:FindFirstChild(TEMPLATES_NAME) else nil
end

function FireVFX.GetInstallStatus(): (boolean, string?)
	local templates = getTemplatesFolder()
	if not templates then
		return false, "ReplicatedStorage/FireballVFX/Templates"
	end

	for _, name in ipairs(REQUIRED_TEMPLATES) do
		local template = templates:FindFirstChild(name)
		if not template or not template:IsA("BasePart") then
			return false, string.format("ReplicatedStorage/FireballVFX/Templates/%s", name)
		end
	end

	return true, nil
end

local function cloneTemplate(name: string): BasePart
	local templates = getTemplatesFolder()
	local template = if templates then templates:FindFirstChild(name) else nil
	if not template or not template:IsA("BasePart") then
		error(
			string.format(
				"[LobbyMagicV2] %s がありません。RobloxMagicSystem/InstallRobloxMagicSystem.luaを実行してください。",
				name
			),
			2
		)
	end

	local clone = template:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = false
	clone:SetAttribute("LMV2_Runtime", true)
	return clone
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

function FireVFX.CreateProjectile(cframe: CFrame, parent: Instance): BasePart
	local projectile = cloneTemplate("Projectile")
	projectile.Name = "LMV2_FireProjectile"
	projectile.CFrame = cframe
	projectile.Parent = parent
	return projectile
end

function FireVFX.Cast(cframe: CFrame, parent: Instance)
	local effect = cloneTemplate("Cast")
	effect.Name = "LMV2_CastFx"
	effect.CFrame = cframe
	effect.Parent = parent
	emitStoredParticles(effect)
	Debris:AddItem(effect, 1.25)
end

function FireVFX.Explode(position: Vector3, parent: Instance)
	local effect = cloneTemplate("Explosion")
	effect.Name = "LMV2_ExplosionFx"
	effect.CFrame = CFrame.new(position)
	effect.Parent = parent
	emitStoredParticles(effect)

	local light = effect:FindFirstChildWhichIsA("PointLight", true)
	if light then
		TweenService:Create(
			light,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0, Range = 0 }
		):Play()
	end
	Debris:AddItem(effect, 1.6)
end

return FireVFX
