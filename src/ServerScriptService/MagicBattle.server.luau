--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpellDefinitions = require(Shared:WaitForChild("SpellDefinitions"))

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local castSpell = remotes:FindFirstChild("CastSpell")
if not castSpell then
	castSpell = Instance.new("RemoteEvent")
	castSpell.Name = "CastSpell"
	castSpell.Parent = remotes
end

local world = workspace:WaitForChild("MagicGameWorld")
local portal = world:WaitForChild("BattlePortal") :: BasePart
local portalPrompt = portal:WaitForChild("ProximityPrompt") :: ProximityPrompt
local spawnPointsFolder = world:WaitForChild("BattleSpawnPoints")
local random = Random.new()

local portalDebounce: { [Player]: boolean } = {}
local lastCastAt: { [Player]: { [string]: number } } = {}

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function sendPlayerToBattle(player: Player)
	if portalDebounce[player] or player:GetAttribute("IsInBattle") then
		return
	end

	local character, _, root = getAliveCharacter(player)
	if not character or not root then
		return
	end

	local spawnPoints = spawnPointsFolder:GetChildren()
	if #spawnPoints == 0 then
		return
	end

	portalDebounce[player] = true
	player:SetAttribute("IsInBattle", true)

	local chosen = spawnPoints[random:NextInteger(1, #spawnPoints)]
	if chosen:IsA("BasePart") then
		local offset = Vector3.new(random:NextNumber(-2, 2), 4, random:NextNumber(-2, 2))
		character:PivotTo(chosen.CFrame + offset)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local forceField = Instance.new("ForceField")
	forceField.Visible = false
	forceField.Parent = character
	Debris:AddItem(forceField, 2)

	task.delay(1, function()
		portalDebounce[player] = nil
	end)
end

portal.Touched:Connect(function(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		sendPlayerToBattle(player)
	end
end)

portalPrompt.Triggered:Connect(sendPlayerToBattle)

local function findHumanoidFromPart(part: Instance?): Humanoid?
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function canDamage(attacker: Player, humanoid: Humanoid): boolean
	local targetCharacter = humanoid.Parent
	if not targetCharacter or targetCharacter == attacker.Character or humanoid.Health <= 0 then
		return false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	return targetPlayer ~= nil and targetPlayer:GetAttribute("IsInBattle") == true
end

local function applySlow(humanoid: Humanoid, duration: number)
	if duration <= 0 then
		return
	end

	local token = os.clock()
	local originalSpeed = humanoid.WalkSpeed
	humanoid:SetAttribute("FrostSlowToken", token)
	humanoid.WalkSpeed = math.min(originalSpeed, 9)

	task.delay(duration, function()
		if humanoid.Parent and humanoid:GetAttribute("FrostSlowToken") == token then
			humanoid.WalkSpeed = originalSpeed
			humanoid:SetAttribute("FrostSlowToken", nil)
		end
	end)
end

local function damageHumanoid(attacker: Player, humanoid: Humanoid, damage: number, slowDuration: number)
	if not canDamage(attacker, humanoid) then
		return
	end
	humanoid:TakeDamage(damage)
	applySlow(humanoid, slowDuration)
end

local function showImpact(position: Vector3, color: Color3, radius: number)
	local effect = Instance.new("Part")
	effect.Name = "MagicImpact"
	effect.Shape = Enum.PartType.Ball
	effect.Size = Vector3.new(1, 1, 1)
	effect.CFrame = CFrame.new(position)
	effect.Color = color
	effect.Material = Enum.Material.Neon
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanTouch = false
	effect.CanQuery = false
	effect.Transparency = 0.2
	effect.Parent = world

	local finalDiameter = math.max(3, radius * 2)
	TweenService:Create(
		effect,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(finalDiameter, finalDiameter, finalDiameter), Transparency = 1 }
	):Play()
	Debris:AddItem(effect, 0.35)
end

local function damageAtImpact(
	attacker: Player,
	hitPart: Instance?,
	position: Vector3,
	damage: number,
	blastRadius: number,
	slowDuration: number
)
	if blastRadius <= 0 then
		local humanoid = findHumanoidFromPart(hitPart)
		if humanoid then
			damageHumanoid(attacker, humanoid, damage, slowDuration)
		end
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = attacker.Character and { attacker.Character } or {}

	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(position, blastRadius, overlapParams) do
		local humanoid = findHumanoidFromPart(part)
		if humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			damageHumanoid(attacker, humanoid, damage, slowDuration)
		end
	end
end

local function launchProjectile(player: Player, spellName: string, targetPosition: Vector3)
	local definition = SpellDefinitions[spellName]
	if not definition or player:GetAttribute("IsInBattle") ~= true then
		return
	end

	local character, _, root = getAliveCharacter(player)
	if not character or not root then
		return
	end

	if targetPosition.X ~= targetPosition.X or targetPosition.Y ~= targetPosition.Y or targetPosition.Z ~= targetPosition.Z then
		return
	end

	local cooldowns = lastCastAt[player]
	if not cooldowns then
		cooldowns = {}
		lastCastAt[player] = cooldowns
	end

	local now = os.clock()
	if now - (cooldowns[spellName] or 0) < definition.Cooldown then
		return
	end
	cooldowns[spellName] = now

	local origin = root.Position + Vector3.new(0, 1.6, 0)
	local offset = targetPosition - origin
	if offset.Magnitude < 1 then
		return
	end
	local direction = offset.Unit

	local projectile = Instance.new("Part")
	projectile.Name = spellName
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.one * definition.ProjectileRadius * 2
	projectile.CFrame = CFrame.new(origin + direction * 3)
	projectile.Color = definition.Color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Parent = world

	local light = Instance.new("PointLight")
	light.Color = definition.Color
	light.Brightness = 2
	light.Range = 10
	light.Parent = projectile

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, projectile }
	raycastParams.IgnoreWater = true

	local position = projectile.Position
	local travelled = 0
	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not projectile.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local stepDistance = definition.Speed * math.min(deltaTime, 0.1)
		local step = direction * stepDistance
		local result = workspace:Raycast(position, step, raycastParams)

		if result then
			projectile.Position = result.Position
			showImpact(result.Position, definition.Color, definition.BlastRadius)
			damageAtImpact(
				player,
				result.Instance,
				result.Position,
				definition.Damage,
				definition.BlastRadius,
				definition.SlowDuration
			)
			if connection then
				connection:Disconnect()
			end
			projectile:Destroy()
			return
		end

		position += step
		travelled += stepDistance
		projectile.Position = position

		if travelled >= definition.Range then
			if connection then
				connection:Disconnect()
			end
			projectile:Destroy()
		end
	end)
end

(castSpell :: RemoteEvent).OnServerEvent:Connect(function(player: Player, spellName: unknown, targetPosition: unknown)
	if typeof(spellName) ~= "string" or typeof(targetPosition) ~= "Vector3" then
		return
	end
	launchProjectile(player, spellName :: string, targetPosition :: Vector3)
end)

local function configurePlayer(player: Player)
	player:SetAttribute("IsInBattle", false)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("IsInBattle", false)
	end)
end

Players.PlayerAdded:Connect(configurePlayer)
for _, player in Players:GetPlayers() do
	configurePlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	portalDebounce[player] = nil
	lastCastAt[player] = nil
end)

