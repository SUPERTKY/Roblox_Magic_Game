--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SharedUtil = {}

function SharedUtil.IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function SharedUtil.IsFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and SharedUtil.IsFiniteNumber(value.X)
		and SharedUtil.IsFiniteNumber(value.Y)
		and SharedUtil.IsFiniteNumber(value.Z)
end

function SharedUtil.SafeUnit(vector: Vector3, fallback: Vector3?): Vector3
	if vector.Magnitude > 1e-4 then
		return vector.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end

function SharedUtil.GetHumanoidFromPart(part: Instance?): (Humanoid?, Model?)
	if not part then
		return nil, nil
	end

	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid, current
			end
		end
		current = current.Parent
	end

	return nil, nil
end

function SharedUtil.GetRootPart(modelOrHumanoid: Instance?): BasePart?
	if not modelOrHumanoid then
		return nil
	end

	local model: Model?
	if modelOrHumanoid:IsA("Humanoid") then
		model = modelOrHumanoid.Parent :: Model?
	elseif modelOrHumanoid:IsA("Model") then
		model = modelOrHumanoid
	else
		model = modelOrHumanoid:FindFirstAncestorOfClass("Model")
	end

	if not model then
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function SharedUtil.IsAlive(humanoid: Humanoid?): boolean
	return humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health > 0
end

local function getMagicTeamForPlayer(player: Player): string?
	local character = player.Character
	local custom = player:GetAttribute("MagicTeam")
	if typeof(custom) == "string" and custom ~= "" then
		return custom
	end
	if character then
		local characterCustom = character:GetAttribute("MagicTeam")
		if typeof(characterCustom) == "string" and characterCustom ~= "" then
			return characterCustom
		end
	end
	if player.Team and not player.Neutral then
		return "RobloxTeam:" .. player.Team.Name
	end
	return nil
end

local function getMagicTeamForModel(model: Model): string?
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return getMagicTeamForPlayer(player)
	end

	local custom = model:GetAttribute("MagicTeam")
	if typeof(custom) == "string" and custom ~= "" then
		return custom
	end
	return nil
end

function SharedUtil.AreFriendly(caster: Player, targetModel: Model): boolean
	if caster.Character == targetModel then
		return true
	end

	local casterTeam = getMagicTeamForPlayer(caster)
	local targetTeam = getMagicTeamForModel(targetModel)
	return casterTeam ~= nil and targetTeam ~= nil and casterTeam == targetTeam
end

function SharedUtil.FindHumanoidsInRadius(
	position: Vector3,
	radius: number,
	excludeInstances: {Instance}?,
	maxTargets: number?
): {Humanoid}
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excludeInstances or {}
	overlapParams.MaxParts = 256
	overlapParams.RespectCanCollide = false

	local parts = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	local found: {[Humanoid]: boolean} = {}
	local humanoids: {Humanoid} = {}
	local limit = maxTargets or 32

	for _, part in parts do
		local humanoid = SharedUtil.GetHumanoidFromPart(part)
		if humanoid and not found[humanoid] and SharedUtil.IsAlive(humanoid) then
			found[humanoid] = true
			table.insert(humanoids, humanoid)
			if #humanoids >= limit then
				break
			end
		end
	end

	return humanoids
end

function SharedUtil.MakeRaycastParams(excludeInstances: {Instance}?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeInstances or {}
	params.IgnoreWater = true
	params.RespectCanCollide = false
	return params
end

function SharedUtil.ClampLineOfSight(origin: Vector3, desiredPosition: Vector3, excludeInstances: {Instance}?): Vector3
	local offset = desiredPosition - origin
	if offset.Magnitude <= 0.05 then
		return desiredPosition
	end

	local result = Workspace:Raycast(origin, offset, SharedUtil.MakeRaycastParams(excludeInstances))
	if result then
		return result.Position - result.Normal * 0.15
	end
	return desiredPosition
end

function SharedUtil.FindGround(position: Vector3, excludeInstances: {Instance}?): Vector3
	local origin = position + Vector3.new(0, 70, 0)
	local result = Workspace:Raycast(
		origin,
		Vector3.new(0, -160, 0),
		SharedUtil.MakeRaycastParams(excludeInstances)
	)
	if result then
		return result.Position
	end
	return position
end

function SharedUtil.Round(value: number, decimals: number?): number
	local places = decimals or 0
	local multiplier = 10 ^ places
	return math.floor(value * multiplier + 0.5) / multiplier
end

return table.freeze(SharedUtil)
