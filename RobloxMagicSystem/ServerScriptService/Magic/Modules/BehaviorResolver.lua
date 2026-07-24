--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpellDefs = require(Shared:WaitForChild("SpellDefs"))
local SharedUtil = require(Shared:WaitForChild("SharedUtil"))

local Modules = script.Parent
local statusModule = Modules:FindFirstChild("StatusService") or Modules:FindFirstChild("StatusService.lua")
if not statusModule or not statusModule:IsA("ModuleScript") then
	error("[Magic] Modules.StatusService (ModuleScript) がありません。StatusService.luaを配置するか、名前をStatusServiceに変更してください。")
end
local StatusService = require(statusModule)

local BehaviorResolver = {}

local spellFx: RemoteEvent? = nil
local runtimeFolder: Folder? = nil
local projectileFolder: Folder? = nil
local initialized = false
local activeProjectiles: {any} = {}

local function ensureRuntimeFolders()
	local runtime: Folder
	local existingRuntime = Workspace:FindFirstChild("MagicRuntime")
	if existingRuntime and existingRuntime:IsA("Folder") then
		runtime = existingRuntime
	else
		runtime = Instance.new("Folder")
		runtime.Name = "MagicRuntime"
		runtime.Parent = Workspace
	end
	runtimeFolder = runtime

	local projectiles: Folder
	local existingProjectiles = runtime:FindFirstChild("Projectiles")
	if existingProjectiles and existingProjectiles:IsA("Folder") then
		projectiles = existingProjectiles
	else
		projectiles = Instance.new("Folder")
		projectiles.Name = "Projectiles"
		projectiles.Parent = runtime
	end
	projectileFolder = projectiles
end

local function fireAll(kind: string, payload: {[string]: any})
	if spellFx then
		spellFx:FireAllClients(kind, payload)
	end
end

local function makeMagicPart(
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.15
	part.Size = size
	part.Shape = shape or Enum.PartType.Ball
	part.Position = position
	return part
end

local function getTargetModel(humanoid: Humanoid): Model?
	local parent = humanoid.Parent
	if parent and parent:IsA("Model") then
		return parent
	end
	return nil
end

local function canAffect(caster: Player, spec: any, humanoid: Humanoid): boolean
	if not SharedUtil.IsAlive(humanoid) then
		return false
	end

	local model = getTargetModel(humanoid)
	if not model then
		return false
	end

	local friendly = SharedUtil.AreFriendly(caster, model)
	if spec.Element == "Light" then
		if friendly then
			return humanoid.Health < humanoid.MaxHealth - 0.01
		end
		return true
	end

	return not friendly
end

local chainLightning: (Player, any, Humanoid, number) -> ()

local function applyElementStatus(
	caster: Player,
	spec: any,
	humanoid: Humanoid,
	sourcePosition: Vector3,
	allowChain: boolean
)
	local element = spec.ElementDef
	if spec.Element == "Fire" then
		local burn = element.Burn
		StatusService.ApplyBurn(
			humanoid,
			burn.DamagePerTick,
			burn.TickInterval,
			burn.Duration,
			caster
		)
	elseif spec.Element == "Ice" then
		local ice = element.Ice
		StatusService.ApplyIce(
			humanoid,
			ice.SlowReduction,
			ice.SlowDuration,
			ice.HitsToFreeze,
			ice.FreezeBuildWindow,
			ice.FreezeDuration,
			caster
		)
	elseif spec.Element == "Lightning" then
		local shock = element.Shock
		StatusService.ApplyShock(humanoid, shock.Duration, shock.MoveMultiplier, caster)
		if allowChain then
			chainLightning(caster, spec, humanoid, spec.Damage)
		end
	elseif spec.Element == "Wind" then
		local targetRoot = SharedUtil.GetRootPart(humanoid)
		if targetRoot then
			local knockback = element.Knockback
			StatusService.ApplyKnockback(
				humanoid,
				targetRoot.Position - sourcePosition,
				knockback.HorizontalImpulse,
				knockback.UpwardImpulse
			)
		end
	elseif spec.Element == "Poison" then
		local poison = element.Poison
		StatusService.ApplyPoison(
			humanoid,
			poison.DamagePerTick,
			poison.TickInterval,
			poison.Duration,
			caster
		)
	end
end

local function applyToHumanoid(
	caster: Player,
	spec: any,
	humanoid: Humanoid,
	sourcePosition: Vector3,
	amount: number,
	allowChain: boolean?
): boolean
	if not canAffect(caster, spec, humanoid) then
		return false
	end

	local model = getTargetModel(humanoid)
	if not model then
		return false
	end

	local targetRoot = SharedUtil.GetRootPart(model)
	local targetPosition = if targetRoot then targetRoot.Position else sourcePosition
	local friendly = SharedUtil.AreFriendly(caster, model)

	if spec.Element == "Light" and friendly then
		local healed = StatusService.Heal(humanoid, amount * spec.ElementDef.HealMultiplier)
		if healed > 0 then
			fireAll("Heal", {
				Position = targetPosition,
				Color = spec.ElementDef.Color,
				Amount = healed,
			})
			return true
		end
		return false
	end

	humanoid:TakeDamage(math.max(0, amount))
	fireAll("Impact", {
		Position = targetPosition,
		Color = spec.ElementDef.Color,
	})
	applyElementStatus(caster, spec, humanoid, sourcePosition, allowChain ~= false)
	return true
end

chainLightning = function(caster: Player, spec: any, firstHumanoid: Humanoid, baseDamage: number)
	local chain = spec.ElementDef.Chain
	if not chain then
		return
	end

	local visited: {[Humanoid]: boolean} = { [firstHumanoid] = true }
	local currentHumanoid = firstHumanoid
	local currentDamage = baseDamage

	for _ = 1, chain.Count do
		local currentRoot = SharedUtil.GetRootPart(currentHumanoid)
		if not currentRoot then
			break
		end

		local candidates = SharedUtil.FindHumanoidsInRadius(
			currentRoot.Position,
			chain.Range,
			if runtimeFolder then { runtimeFolder } else {},
			SpellDefs.Security.MaxTargetsPerArea
		)

		local nearest: Humanoid? = nil
		local nearestDistance = math.huge
		for _, candidate in candidates do
			if not visited[candidate] and canAffect(caster, spec, candidate) then
				local candidateRoot = SharedUtil.GetRootPart(candidate)
				if candidateRoot then
					local distance = (candidateRoot.Position - currentRoot.Position).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearest = candidate
					end
				end
			end
		end

		if not nearest then
			break
		end

		local nearestRoot = SharedUtil.GetRootPart(nearest)
		if not nearestRoot then
			break
		end

		visited[nearest] = true
		currentDamage *= chain.DamageFalloff
		nearest:TakeDamage(math.max(1, currentDamage))
		local shock = spec.ElementDef.Shock
		StatusService.ApplyShock(nearest, shock.Duration, shock.MoveMultiplier, caster)
		fireAll("Chain", {
			From = currentRoot.Position,
			To = nearestRoot.Position,
			Color = spec.ElementDef.Color,
		})
		currentHumanoid = nearest
	end
end

local function detonate(caster: Player, spec: any, position: Vector3, radius: number, damage: number)
	fireAll("Explosion", {
		Position = position,
		Radius = radius,
		Color = spec.ElementDef.Color,
	})

	local targets = SharedUtil.FindHumanoidsInRadius(
		position,
		radius,
		if runtimeFolder then { runtimeFolder } else {},
		SpellDefs.Security.MaxTargetsPerArea
	)
	for _, humanoid in targets do
		applyToHumanoid(caster, spec, humanoid, position, damage, true)
	end
end

local function makeProjectileRaycastParams(projectile: any): RaycastParams
	local excludes: {Instance} = {}
	if runtimeFolder then
		table.insert(excludes, runtimeFolder)
	end
	if projectile.owner.Character then
		table.insert(excludes, projectile.owner.Character)
	end
	for model in projectile.ignoredModels do
		table.insert(excludes, model)
	end
	return SharedUtil.MakeRaycastParams(excludes)
end

local function destroyProjectile(projectile: any)
	if projectile.dead then
		return
	end
	projectile.dead = true
	if projectile.part then
		projectile.part:Destroy()
	end
end

local function spawnProjectile(
	caster: Player,
	spec: any,
	startPosition: Vector3,
	direction: Vector3,
	options: {[string]: any}
): any
	local radius = options.Radius or 0.72
	local part = makeMagicPart(
		"MagicProjectile",
		startPosition,
		Vector3.new(radius * 2, radius * 2, radius * 2),
		spec.ElementDef.Color,
		Enum.PartType.Ball,
		0.08
	)
	local projectiles = projectileFolder
	if not projectiles then
		error("Magic projectile folder is not initialized")
	end
	part.Parent = projectiles

	local projectile = {
		owner = caster,
		spec = spec,
		part = part,
		position = startPosition,
		direction = SharedUtil.SafeUnit(direction),
		speed = options.Speed or 100,
		expiresAt = os.clock() + (options.Lifetime or 4),
		homingTarget = options.HomingTarget,
		turnRate = options.TurnRate or 0,
		onImpact = options.OnImpact,
		onExpire = options.OnExpire,
		remainingPierces = options.Pierces or 0,
		ignoredModels = {},
		dead = false,
	}
	table.insert(activeProjectiles, projectile)

	fireAll("Cast", {
		Position = startPosition,
		Color = spec.ElementDef.Color,
	})
	return projectile
end

local function updateProjectiles(deltaTime: number)
	local now = os.clock()
	for index = #activeProjectiles, 1, -1 do
		local projectile = activeProjectiles[index]
		if projectile.dead or projectile.part.Parent == nil then
			table.remove(activeProjectiles, index)
			continue
		end

		if now >= projectile.expiresAt then
			if projectile.onExpire then
				local ok, err = pcall(projectile.onExpire, projectile.position)
				if not ok then
					warn("[Magic] Projectile OnExpire failed:", err)
				end
			end
			destroyProjectile(projectile)
			table.remove(activeProjectiles, index)
			continue
		end

		local targetHumanoid = projectile.homingTarget
		if targetHumanoid and SharedUtil.IsAlive(targetHumanoid) then
			local targetRoot = SharedUtil.GetRootPart(targetHumanoid)
			if targetRoot then
				local desired = SharedUtil.SafeUnit(targetRoot.Position - projectile.position, projectile.direction)
				local alpha = math.clamp(projectile.turnRate * deltaTime, 0, 1)
				projectile.direction = SharedUtil.SafeUnit(projectile.direction:Lerp(desired, alpha), desired)
			end
		end

		local displacement = projectile.direction * projectile.speed * deltaTime
		local rayResult = Workspace:Raycast(
			projectile.position,
			displacement,
			makeProjectileRaycastParams(projectile)
		)

		if rayResult then
			local humanoid, model = SharedUtil.GetHumanoidFromPart(rayResult.Instance)
			local action = "destroy"
			if projectile.onImpact then
				local ok, result = pcall(projectile.onImpact, rayResult.Position, humanoid, model, rayResult.Instance)
				if ok and typeof(result) == "string" then
					action = result
				elseif not ok then
					warn("[Magic] Projectile OnImpact failed:", result)
				end
			end

			if action == "ignore" and model then
				projectile.ignoredModels[model] = true
				projectile.position = rayResult.Position + projectile.direction * 0.35
				projectile.part.Position = projectile.position
			elseif action == "pierce" and model and projectile.remainingPierces > 0 then
				projectile.remainingPierces -= 1
				projectile.ignoredModels[model] = true
				projectile.position = rayResult.Position + projectile.direction * 0.35
				projectile.part.Position = projectile.position
			else
				destroyProjectile(projectile)
				table.remove(activeProjectiles, index)
			end
		else
			projectile.position += displacement
			projectile.part.CFrame = CFrame.lookAt(
				projectile.position,
				projectile.position + projectile.direction
			)
		end
	end
end

local function directImpactCallback(caster: Player, spec: any, damage: number)
	return function(position: Vector3, humanoid: Humanoid?, _model: Model?, _part: Instance): string
		if not humanoid then
			return "destroy"
		end
		if not canAffect(caster, spec, humanoid) then
			return "ignore"
		end

		applyToHumanoid(caster, spec, humanoid, position, damage, true)
		if spec.Element == "Light" then
			return "pierce"
		end
		return "destroy"
	end
end

local function createTrap(caster: Player, spec: any, position: Vector3)
	local form = spec.FormDef
	local trap = makeMagicPart(
		"MagicTrap",
		position,
		Vector3.new(2.4, 2.4, 2.4),
		spec.ElementDef.Color,
		Enum.PartType.Ball,
		0.28
	)
	local runtime = runtimeFolder
	if not runtime then
		error("Magic runtime folder is not initialized")
	end
	trap.Parent = runtime

	fireAll("TrapArmed", {
		Position = position,
		Radius = form.TriggerRadius,
		Color = spec.ElementDef.Color,
		Duration = form.Lifetime,
	})

	task.spawn(function()
		task.wait(form.ArmTime)
		local expiresAt = os.clock() + form.Lifetime
		while trap.Parent and os.clock() < expiresAt do
			local targets = SharedUtil.FindHumanoidsInRadius(
				trap.Position,
				form.TriggerRadius,
				if runtimeFolder then { runtimeFolder } else {},
				SpellDefs.Security.MaxTargetsPerArea
			)
			for _, humanoid in targets do
				if canAffect(caster, spec, humanoid) then
					local detonationPosition = trap.Position
					trap:Destroy()
					detonate(caster, spec, detonationPosition, form.ExplosionRadius, spec.Damage)
					return
				end
			end
			task.wait(0.16)
		end
		if trap.Parent then
			trap:Destroy()
		end
	end)
end

local function createPersistentArea(caster: Player, spec: any, position: Vector3, followRoot: BasePart?)
	local form = spec.FormDef
	local zone = makeMagicPart(
		"MagicPersistentArea",
		position + Vector3.new(0, 0.2, 0),
		Vector3.new(0.45, form.Radius * 2, form.Radius * 2),
		spec.ElementDef.Color,
		Enum.PartType.Cylinder,
		0.67
	)
	zone.CFrame = CFrame.new(zone.Position) * CFrame.Angles(0, 0, math.rad(90))
	local runtime = runtimeFolder
	if not runtime then
		error("Magic runtime folder is not initialized")
	end
	zone.Parent = runtime

	fireAll("Area", {
		Position = position,
		Radius = form.Radius,
		Duration = form.Duration,
		Color = spec.ElementDef.Color,
	})

	task.spawn(function()
		local expiresAt = os.clock() + form.Duration
		while zone.Parent and os.clock() < expiresAt do
			local currentPosition = position
			if followRoot and followRoot.Parent then
				currentPosition = followRoot.Position
				zone.CFrame = CFrame.new(currentPosition + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
			local targets = SharedUtil.FindHumanoidsInRadius(
				currentPosition,
				form.Radius,
				if runtimeFolder then { runtimeFolder } else {},
				SpellDefs.Security.MaxTargetsPerArea
			)
			for _, humanoid in targets do
				applyToHumanoid(caster, spec, humanoid, currentPosition, spec.Damage, true)
			end
			task.wait(form.TickInterval)
		end
		if zone.Parent then
			zone:Destroy()
		end
	end)
end

local function findBestHomingTarget(
	caster: Player,
	spec: any,
	searchCenter: Vector3,
	direction: Vector3,
	radius: number
): Humanoid?
	local targets = SharedUtil.FindHumanoidsInRadius(
		searchCenter,
		radius,
		if runtimeFolder then { runtimeFolder } else {},
		SpellDefs.Security.MaxTargetsPerArea
	)

	local best: Humanoid? = nil
	local bestScore = -math.huge
	for _, humanoid in targets do
		if canAffect(caster, spec, humanoid) then
			local root = SharedUtil.GetRootPart(humanoid)
			if root then
				local offset = root.Position - searchCenter
				local distance = math.max(1, offset.Magnitude)
				local dot = direction:Dot(SharedUtil.SafeUnit(offset, direction))
				local score = dot * 100 - distance
				if score > bestScore then
					bestScore = score
					best = humanoid
				end
			end
		end
	end
	return best
end

local function resolveCastContext(
	caster: Player,
	spec: any,
	aimPosition: Vector3,
	aimDirection: Vector3
): any?
	local character = caster.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = SharedUtil.GetRootPart(character)
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end

	local head = character:FindFirstChild("Head")
	local headPosition = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local groundPosition = SharedUtil.FindGround(
		aimPosition,
		if runtimeFolder then { character, runtimeFolder } else { character }
	)

	local spawnPosition: Vector3
	local targetPosition: Vector3
	if spec.Origin == "Throw" then
		spawnPosition = headPosition + aimDirection * 3
		targetPosition = aimPosition
	elseif spec.Origin == "Self" then
		spawnPosition = root.Position
		targetPosition = root.Position
	elseif spec.Origin == "Air" then
		spawnPosition = groundPosition + Vector3.new(0, spec.OriginDef.Height, 0)
		targetPosition = groundPosition
	else
		spawnPosition = groundPosition + Vector3.new(0, 0.8, 0)
		targetPosition = spawnPosition
	end

	return {
		character = character,
		humanoid = humanoid,
		root = root,
		spawnPosition = spawnPosition,
		targetPosition = targetPosition,
		aimPosition = aimPosition,
		aimDirection = aimDirection,
	}
end

local function castExplosion(caster: Player, spec: any, context: any)
	local form = spec.FormDef
	if spec.Origin == "Throw" then
		spawnProjectile(caster, spec, context.spawnPosition, context.aimDirection, {
			Speed = spec.OriginDef.ProjectileSpeed,
			Lifetime = spec.OriginDef.ProjectileLifetime,
			OnImpact = function(position: Vector3): string
				detonate(caster, spec, position, form.Radius, spec.Damage)
				return "destroy"
			end,
			OnExpire = function(position: Vector3)
				detonate(caster, spec, position, form.Radius, spec.Damage)
			end,
		})
	elseif spec.Origin == "Air" then
		spawnProjectile(caster, spec, context.spawnPosition, Vector3.new(0, -1, 0), {
			Speed = 76,
			Lifetime = 2.0,
			OnImpact = function(position: Vector3): string
				detonate(caster, spec, position, form.Radius, spec.Damage)
				return "destroy"
			end,
			OnExpire = function(position: Vector3)
				detonate(caster, spec, position, form.Radius, spec.Damage)
			end,
		})
	elseif spec.Origin == "Self" then
		detonate(caster, spec, context.spawnPosition, form.Radius, spec.Damage)
	else
		task.delay(form.Delay, function()
			detonate(caster, spec, context.spawnPosition, form.Radius, spec.Damage)
		end)
	end
end

local function castSpread(caster: Player, spec: any, context: any)
	local form = spec.FormDef
	local speed = form.ProjectileSpeed
	local lifetime = form.ProjectileLifetime
	local onImpact = directImpactCallback(caster, spec, spec.Damage)
	local pierces = if spec.Element == "Light" then spec.ElementDef.PierceCount else 0

	for index = 1, form.Count do
		local direction: Vector3
		if spec.Origin == "Self" or spec.Origin == "Place" or spec.Origin == "Ground" then
			local angle = (index - 1) / form.Count * math.pi * 2
			direction = SharedUtil.SafeUnit(Vector3.new(math.cos(angle), 0.08, math.sin(angle)))
		elseif spec.Origin == "Air" then
			local angle = (index - 1) / form.Count * math.pi * 2
			direction = SharedUtil.SafeUnit(Vector3.new(math.cos(angle) * 0.45, -1, math.sin(angle) * 0.45))
		else
			local centerOffset = (index - 1) - (form.Count - 1) / 2
			local normalized = if form.Count > 1 then centerOffset / ((form.Count - 1) / 2) else 0
			local radians = math.rad(form.ArcDegrees) * normalized
			direction = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), radians):VectorToWorldSpace(context.aimDirection)
		end

		spawnProjectile(caster, spec, context.spawnPosition, direction, {
			Speed = speed,
			Lifetime = lifetime,
			OnImpact = onImpact,
			Pierces = pierces,
			Radius = 0.55,
		})
	end
end

local function castHoming(caster: Player, spec: any, context: any)
	local form = spec.FormDef
	local searchCenter = if spec.Origin == "Throw" then context.spawnPosition else context.targetPosition
	local direction = if spec.Origin == "Air" then Vector3.new(0, -1, 0) else context.aimDirection
	local target = findBestHomingTarget(caster, spec, searchCenter, direction, form.LockRadius)
	local pierces = if spec.Element == "Light" then spec.ElementDef.PierceCount else 0

	spawnProjectile(caster, spec, context.spawnPosition, direction, {
		Speed = form.ProjectileSpeed,
		Lifetime = form.ProjectileLifetime,
		HomingTarget = target,
		TurnRate = form.TurnRate,
		OnImpact = directImpactCallback(caster, spec, spec.Damage),
		Pierces = pierces,
		Radius = 0.78,
	})
end

local function castProximity(caster: Player, spec: any, context: any)
	if spec.Origin == "Throw" then
		spawnProjectile(caster, spec, context.spawnPosition, context.aimDirection, {
			Speed = spec.OriginDef.ProjectileSpeed,
			Lifetime = spec.OriginDef.ProjectileLifetime,
			OnImpact = function(position: Vector3): string
				createTrap(caster, spec, position)
				return "destroy"
			end,
			OnExpire = function(position: Vector3)
				createTrap(caster, spec, position)
			end,
		})
	else
		createTrap(caster, spec, context.spawnPosition)
	end
end

local function castPersistent(caster: Player, spec: any, context: any)
	if spec.Origin == "Throw" then
		spawnProjectile(caster, spec, context.spawnPosition, context.aimDirection, {
			Speed = spec.OriginDef.ProjectileSpeed,
			Lifetime = spec.OriginDef.ProjectileLifetime,
			OnImpact = function(position: Vector3): string
				createPersistentArea(caster, spec, position)
				return "destroy"
			end,
			OnExpire = function(position: Vector3)
				createPersistentArea(caster, spec, position)
			end,
		})
	else
		local followRoot = if spec.Origin == "Self" then context.root else nil
		createPersistentArea(caster, spec, context.spawnPosition, followRoot)
	end
end

function BehaviorResolver.Init(remote: RemoteEvent)
	if initialized then
		return
	end
	initialized = true
	spellFx = remote
	ensureRuntimeFolders()
	StatusService.Start()
	RunService.Heartbeat:Connect(updateProjectiles)
end

function BehaviorResolver.Cast(
	caster: Player,
	spec: any,
	aimPosition: Vector3,
	aimDirection: Vector3
): (boolean, string?)
	if not initialized then
		return false, "BehaviorResolver is not initialized"
	end

	local context = resolveCastContext(caster, spec, aimPosition, aimDirection)
	if not context then
		return false, "Character is not ready"
	end

	if spec.Origin == "Ground" then
		fireAll("GroundRise", {
			Position = context.spawnPosition,
			Color = spec.ElementDef.Color,
		})
	end

	if spec.Form == "Explosion" then
		castExplosion(caster, spec, context)
	elseif spec.Form == "Spread" then
		castSpread(caster, spec, context)
	elseif spec.Form == "Homing" then
		castHoming(caster, spec, context)
	elseif spec.Form == "Proximity" then
		castProximity(caster, spec, context)
	elseif spec.Form == "Persistent" then
		castPersistent(caster, spec, context)
	else
		return false, "Unsupported spell form"
	end

	return true, nil
end

return BehaviorResolver
