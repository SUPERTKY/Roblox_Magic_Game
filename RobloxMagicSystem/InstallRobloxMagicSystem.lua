-- Roblox Magic System installer
-- Studioを停止した状態で View > Command Bar に全体を貼り付けて実行してください。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function upsertSource(parent, className, name, source, aliases)
	for _, alias in ipairs(aliases or {}) do
		local old = parent:FindFirstChild(alias)
		if old and old.Name ~= name then old:Destroy() end
	end
	local object = parent:FindFirstChild(name)
	if object and object.ClassName ~= className then object:Destroy(); object = nil end
	if not object then object = Instance.new(className); object.Name = name; object.Parent = parent end
	object.Source = source
	return object
end

local shared = ensureFolder(ReplicatedStorage, "Shared")
local remotes = ensureFolder(ReplicatedStorage, "Remotes")
local magic = ensureFolder(ServerScriptService, "Magic")
local modules = ensureFolder(magic, "Modules")
local starterScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local function ensureRemote(name, className)
	local object = remotes:FindFirstChild(name)
	if object and object.ClassName == className then return object end
	if object then object:Destroy() end
	object = Instance.new(className)
	object.Name = name
	object.Parent = remotes
	return object
end
ensureRemote("CastSpellRequest", "RemoteEvent")
ensureRemote("SpellFx", "RemoteEvent")
ensureRemote("GetSpellPreview", "RemoteFunction")

local SOURCE_1 = [==[
--!strict

-- ElementDefs
-- 属性ごとの見た目・状態異常・係数を一元管理します。
-- サーバーが最終判定を行うため、クライアントから数値を受け取りません。

local Elements: {[string]: any} = {
	Fire = {
		Id = "Fire",
		DisplayName = "火",
		Color = Color3.fromRGB(255, 92, 43),
		DamageMultiplier = 1.00,
		ManaModifier = 2,
		CooldownModifier = 0.05,
		Burn = {
			DamagePerTick = 4,
			TickInterval = 1.0,
			Duration = 4.0,
		},
	},

	Ice = {
		Id = "Ice",
		DisplayName = "氷",
		Color = Color3.fromRGB(116, 218, 255),
		DamageMultiplier = 0.88,
		ManaModifier = 3,
		CooldownModifier = 0.10,
		Ice = {
			SlowReduction = 0.38,
			SlowDuration = 3.0,
			HitsToFreeze = 3,
			FreezeBuildWindow = 5.0,
			FreezeDuration = 1.45,
		},
	},

	Lightning = {
		Id = "Lightning",
		DisplayName = "雷",
		Color = Color3.fromRGB(255, 239, 95),
		DamageMultiplier = 0.93,
		ManaModifier = 5,
		CooldownModifier = 0.20,
		Shock = {
			Duration = 0.75,
			MoveMultiplier = 0.72,
		},
		Chain = {
			Count = 3,
			Range = 18,
			DamageFalloff = 0.72,
		},
	},

	Wind = {
		Id = "Wind",
		DisplayName = "風",
		Color = Color3.fromRGB(167, 255, 207),
		DamageMultiplier = 0.82,
		ManaModifier = 1,
		CooldownModifier = -0.05,
		Knockback = {
			HorizontalImpulse = 48,
			UpwardImpulse = 17,
		},
	},

	Poison = {
		Id = "Poison",
		DisplayName = "毒",
		Color = Color3.fromRGB(152, 255, 80),
		DamageMultiplier = 0.76,
		ManaModifier = 2,
		CooldownModifier = 0.05,
		Poison = {
			DamagePerTick = 3,
			TickInterval = 1.0,
			Duration = 6.0,
		},
	},

	Light = {
		Id = "Light",
		DisplayName = "光",
		Color = Color3.fromRGB(255, 246, 184),
		DamageMultiplier = 0.90,
		ManaModifier = 5,
		CooldownModifier = 0.18,
		HealMultiplier = 0.90,
		PierceCount = 3,
	},
}

local Order = {
	"Fire",
	"Ice",
	"Lightning",
	"Wind",
	"Poison",
	"Light",
}

local ElementDefs = {}

ElementDefs.All = Elements
ElementDefs.Order = Order

function ElementDefs.IsValid(elementId: any): boolean
	return typeof(elementId) == "string" and Elements[elementId] ~= nil
end

function ElementDefs.Get(elementId: string): any?
	return Elements[elementId]
end

return table.freeze(ElementDefs)
]==]

local SOURCE_2 = [==[
--!strict

-- SpellDefs
-- 「属性 × 出し方 × 攻撃形態」から、サーバーが使用する最終スペル定義を構築します。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ElementDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ElementDefs"))

local Origins: {[string]: any} = {
	Throw = {
		Id = "Throw",
		DisplayName = "投げる",
		ManaModifier = 3,
		CooldownModifier = 0.00,
		CastRange = 240,
		ProjectileSpeed = 112,
		ProjectileLifetime = 4.0,
	},
	Place = {
		Id = "Place",
		DisplayName = "置く",
		ManaModifier = 5,
		CooldownModifier = 0.18,
		CastRange = 75,
	},
	Self = {
		Id = "Self",
		DisplayName = "自分から出す",
		ManaModifier = 1,
		CooldownModifier = -0.08,
		CastRange = 0,
	},
	Air = {
		Id = "Air",
		DisplayName = "空中に出す",
		ManaModifier = 6,
		CooldownModifier = 0.22,
		CastRange = 85,
		Height = 20,
	},
	Ground = {
		Id = "Ground",
		DisplayName = "地面から出す",
		ManaModifier = 4,
		CooldownModifier = 0.12,
		CastRange = 82,
	},
}

local OriginOrder = {
	"Throw",
	"Place",
	"Self",
	"Air",
	"Ground",
}

local Forms: {[string]: any} = {
	Explosion = {
		Id = "Explosion",
		DisplayName = "爆発",
		ManaCost = 14,
		Cooldown = 1.55,
		Damage = 25,
		Radius = 12,
		Delay = 0.28,
	},
	Spread = {
		Id = "Spread",
		DisplayName = "拡散",
		ManaCost = 15,
		Cooldown = 1.70,
		Damage = 13,
		Count = 6,
		ArcDegrees = 34,
		ProjectileSpeed = 105,
		ProjectileLifetime = 3.5,
	},
	Homing = {
		Id = "Homing",
		DisplayName = "追尾",
		ManaCost = 17,
		Cooldown = 2.20,
		Damage = 22,
		ProjectileSpeed = 82,
		ProjectileLifetime = 5.0,
		TurnRate = 7.5,
		LockRadius = 80,
	},
	Proximity = {
		Id = "Proximity",
		DisplayName = "探知攻撃",
		ManaCost = 18,
		Cooldown = 3.00,
		Damage = 27,
		ArmTime = 0.65,
		Lifetime = 18,
		TriggerRadius = 11,
		ExplosionRadius = 10,
	},
	Persistent = {
		Id = "Persistent",
		DisplayName = "持続範囲",
		ManaCost = 20,
		Cooldown = 4.10,
		Damage = 7,
		Radius = 11,
		Duration = 6.0,
		TickInterval = 0.65,
	},
}

local FormOrder = {
	"Explosion",
	"Spread",
	"Homing",
	"Proximity",
	"Persistent",
}

local SpellDefs = {}

SpellDefs.Mana = table.freeze({
	DefaultMax = 100,
	RegenPerSecond = 11,
	RegenDelayAfterSpend = 0.80,
	ReplicationStep = 0.10,
})

SpellDefs.Security = table.freeze({
	MaxAimDistance = 260,
	RemoteBurst = 7,
	RemoteRefillPerSecond = 5,
	GlobalCastInterval = 0.18,
	PreviewBurst = 10,
	PreviewRefillPerSecond = 6,
	MaxTargetsPerArea = 32,
})

SpellDefs.Origins = Origins
SpellDefs.OriginOrder = OriginOrder
SpellDefs.Forms = Forms
SpellDefs.FormOrder = FormOrder

function SpellDefs.IsValidOrigin(originId: any): boolean
	return typeof(originId) == "string" and Origins[originId] ~= nil
end

function SpellDefs.IsValidForm(formId: any): boolean
	return typeof(formId) == "string" and Forms[formId] ~= nil
end

function SpellDefs.Build(elementId: any, originId: any, formId: any): any?
	if not ElementDefs.IsValid(elementId) then
		return nil
	end
	if not SpellDefs.IsValidOrigin(originId) then
		return nil
	end
	if not SpellDefs.IsValidForm(formId) then
		return nil
	end

	local element = ElementDefs.Get(elementId)
	local origin = Origins[originId]
	local form = Forms[formId]
	if not element or not origin or not form then
		return nil
	end

	local manaCost = math.max(1, math.floor(form.ManaCost + origin.ManaModifier + element.ManaModifier + 0.5))
	local cooldown = math.max(0.25, form.Cooldown + origin.CooldownModifier + element.CooldownModifier)
	local damage = math.max(1, form.Damage * element.DamageMultiplier)

	return {
		Key = string.format("%s|%s|%s", elementId, originId, formId),
		Element = elementId,
		Origin = originId,
		Form = formId,
		ElementDef = element,
		OriginDef = origin,
		FormDef = form,
		ManaCost = manaCost,
		Cooldown = cooldown,
		Damage = damage,
		DisplayName = string.format("%s × %s × %s", element.DisplayName, origin.DisplayName, form.DisplayName),
	}
end

function SpellDefs.ToPreview(spec: any): {[string]: any}
	return {
		Key = spec.Key,
		Element = spec.Element,
		Origin = spec.Origin,
		Form = spec.Form,
		DisplayName = spec.DisplayName,
		ManaCost = spec.ManaCost,
		Cooldown = spec.Cooldown,
		Damage = spec.Damage,
		Color = spec.ElementDef.Color,
	}
end

return table.freeze(SpellDefs)
]==]

local SOURCE_3 = [==[
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
]==]

local SOURCE_4 = [==[
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpellDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpellDefs"))

local ManaService = {}

local initialized = false
local lastSpendAt: {[Player]: number} = {}
local accumulator = 0

local function getMaxMana(player: Player): number
	local value = player:GetAttribute("MaxMana")
	if typeof(value) ~= "number" or value <= 0 then
		return SpellDefs.Mana.DefaultMax
	end
	return value
end

local function getMana(player: Player): number
	local value = player:GetAttribute("Mana")
	if typeof(value) ~= "number" then
		return getMaxMana(player)
	end
	return math.clamp(value, 0, getMaxMana(player))
end

function ManaService.InitPlayer(player: Player)
	if typeof(player:GetAttribute("MaxMana")) ~= "number" then
		player:SetAttribute("MaxMana", SpellDefs.Mana.DefaultMax)
	end
	if typeof(player:GetAttribute("Mana")) ~= "number" then
		player:SetAttribute("Mana", getMaxMana(player))
	else
		player:SetAttribute("Mana", getMana(player))
	end
	lastSpendAt[player] = -math.huge
end

function ManaService.Get(player: Player): (number, number)
	return getMana(player), getMaxMana(player)
end

function ManaService.Set(player: Player, amount: number): number
	local nextMana = math.clamp(amount, 0, getMaxMana(player))
	player:SetAttribute("Mana", nextMana)
	return nextMana
end

function ManaService.Add(player: Player, amount: number): number
	return ManaService.Set(player, getMana(player) + amount)
end

function ManaService.TrySpend(player: Player, amount: number): (boolean, number)
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false, getMana(player)
	end

	local current = getMana(player)
	if current + 1e-4 < amount then
		return false, current
	end

	local remaining = ManaService.Set(player, current - amount)
	lastSpendAt[player] = os.clock()
	return true, remaining
end

function ManaService.Start()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(ManaService.InitPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastSpendAt[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		ManaService.InitPlayer(player)
	end

	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < SpellDefs.Mana.ReplicationStep then
			return
		end

		local step = accumulator
		accumulator = 0
		local now = os.clock()

		for _, player in Players:GetPlayers() do
			local current = getMana(player)
			local maximum = getMaxMana(player)
			local lastSpend = lastSpendAt[player] or -math.huge
			if current < maximum and now - lastSpend >= SpellDefs.Mana.RegenDelayAfterSpend then
				ManaService.Set(player, current + SpellDefs.Mana.RegenPerSecond * step)
			end
		end
	end)
end

return ManaService
]==]

local SOURCE_5 = [==[
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SharedUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedUtil"))

local StatusService = {}

type TimedStatus = {
	expiresAt: number,
	potency: number,
	nextTick: number?,
	interval: number?,
	source: Player?,
}

type HumanoidState = {
	statuses: {[string]: TimedStatus},
	iceHits: number,
	iceWindowEnds: number,
	movementApplied: boolean,
	baseWalkSpeed: number,
	baseJumpPower: number,
	baseJumpHeight: number,
	baseAutoRotate: boolean,
}

local states: {[Humanoid]: HumanoidState} = setmetatable({}, { __mode = "k" }) :: any
local initialized = false

local function ensureState(humanoid: Humanoid): HumanoidState
	local state = states[humanoid]
	if state then
		return state
	end

	state = {
		statuses = {},
		iceHits = 0,
		iceWindowEnds = 0,
		movementApplied = false,
		baseWalkSpeed = humanoid.WalkSpeed,
		baseJumpPower = humanoid.JumpPower,
		baseJumpHeight = humanoid.JumpHeight,
		baseAutoRotate = humanoid.AutoRotate,
	}
	states[humanoid] = state
	return state
end

local function setStatusAttribute(humanoid: Humanoid, statusName: string, enabled: boolean)
	local attributeName = "MagicStatus_" .. statusName
	if enabled then
		humanoid:SetAttribute(attributeName, true)
	else
		humanoid:SetAttribute(attributeName, nil)
	end
end

local function addOrRefreshStatus(
	humanoid: Humanoid,
	statusName: string,
	duration: number,
	potency: number,
	interval: number?,
	source: Player?
)
	if not SharedUtil.IsAlive(humanoid) then
		return
	end

	local now = os.clock()
	local state = ensureState(humanoid)
	local current = state.statuses[statusName]
	if current then
		current.expiresAt = math.max(current.expiresAt, now + duration)
		current.potency = math.max(current.potency, potency)
		current.interval = interval or current.interval
		current.source = source or current.source
		if interval and not current.nextTick then
			current.nextTick = now + interval
		end
	else
		state.statuses[statusName] = {
			expiresAt = now + duration,
			potency = potency,
			nextTick = if interval then now + interval else nil,
			interval = interval,
			source = source,
		}
		setStatusAttribute(humanoid, statusName, true)
	end
end

local function restoreMovement(humanoid: Humanoid, state: HumanoidState)
	if not state.movementApplied or humanoid.Parent == nil then
		return
	end

	humanoid.WalkSpeed = state.baseWalkSpeed
	humanoid.JumpPower = state.baseJumpPower
	humanoid.JumpHeight = state.baseJumpHeight
	humanoid.AutoRotate = state.baseAutoRotate
	state.movementApplied = false
end

local function applyMovement(humanoid: Humanoid, state: HumanoidState, multiplier: number, frozen: boolean)
	if not state.movementApplied then
		state.baseWalkSpeed = humanoid.WalkSpeed
		state.baseJumpPower = humanoid.JumpPower
		state.baseJumpHeight = humanoid.JumpHeight
		state.baseAutoRotate = humanoid.AutoRotate
		state.movementApplied = true
	end

	humanoid.WalkSpeed = state.baseWalkSpeed * multiplier
	if frozen then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	else
		humanoid.JumpPower = state.baseJumpPower
		humanoid.JumpHeight = state.baseJumpHeight
		humanoid.AutoRotate = state.baseAutoRotate
	end
end

local function tickDamage(humanoid: Humanoid, status: TimedStatus)
	if not SharedUtil.IsAlive(humanoid) then
		return
	end
	humanoid:TakeDamage(math.max(0, status.potency))
end

function StatusService.ApplyBurn(
	humanoid: Humanoid,
	damagePerTick: number,
	interval: number,
	duration: number,
	source: Player?
)
	addOrRefreshStatus(humanoid, "Burn", duration, damagePerTick, interval, source)
end

function StatusService.ApplyPoison(
	humanoid: Humanoid,
	damagePerTick: number,
	interval: number,
	duration: number,
	source: Player?
)
	addOrRefreshStatus(humanoid, "Poison", duration, damagePerTick, interval, source)
end

function StatusService.ApplyIce(
	humanoid: Humanoid,
	slowReduction: number,
	slowDuration: number,
	hitsToFreeze: number,
	buildWindow: number,
	freezeDuration: number,
	source: Player?
)
	if not SharedUtil.IsAlive(humanoid) then
		return
	end

	local now = os.clock()
	local state = ensureState(humanoid)
	if now > state.iceWindowEnds then
		state.iceHits = 0
	end
	state.iceHits += 1
	state.iceWindowEnds = now + buildWindow

	addOrRefreshStatus(humanoid, "Slow", slowDuration, math.clamp(slowReduction, 0, 0.95), nil, source)
	if state.iceHits >= math.max(1, hitsToFreeze) then
		state.iceHits = 0
		addOrRefreshStatus(humanoid, "Freeze", freezeDuration, 1, nil, source)
	end
end

function StatusService.ApplyShock(
	humanoid: Humanoid,
	duration: number,
	moveMultiplier: number,
	source: Player?
)
	local reduction = 1 - math.clamp(moveMultiplier, 0.05, 1)
	addOrRefreshStatus(humanoid, "Shock", duration, reduction, nil, source)
end

function StatusService.ApplyKnockback(
	humanoid: Humanoid,
	direction: Vector3,
	horizontalImpulse: number,
	upwardImpulse: number
)
	if not SharedUtil.IsAlive(humanoid) then
		return
	end

	local root = SharedUtil.GetRootPart(humanoid)
	if not root or root.Anchored then
		return
	end

	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	horizontal = SharedUtil.SafeUnit(horizontal, Vector3.new(0, 0, -1))
	local impulseVelocity = horizontal * horizontalImpulse + Vector3.new(0, upwardImpulse, 0)
	root:ApplyImpulse(impulseVelocity * root.AssemblyMass)
end

function StatusService.Heal(humanoid: Humanoid, amount: number): number
	if not SharedUtil.IsAlive(humanoid) or amount <= 0 then
		return 0
	end

	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	return humanoid.Health - before
end

function StatusService.Start()
	if initialized then
		return
	end
	initialized = true

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for humanoid, state in states do
			if humanoid.Parent == nil or humanoid.Health <= 0 then
				restoreMovement(humanoid, state)
				states[humanoid] = nil
				continue
			end

			local hasMovementStatus = false
			local movementMultiplier = 1.0
			local frozen = false
			local hasAnyStatus = false

			for statusName, status in state.statuses do
				if now >= status.expiresAt then
					state.statuses[statusName] = nil
					setStatusAttribute(humanoid, statusName, false)
					continue
				end

				hasAnyStatus = true
				if statusName == "Burn" or statusName == "Poison" then
					local interval = status.interval or 1
					local nextTick = status.nextTick or (now + interval)
					local catchup = 0
					while now >= nextTick and nextTick <= status.expiresAt and catchup < 3 do
						tickDamage(humanoid, status)
						nextTick += interval
						catchup += 1
					end
					status.nextTick = nextTick
				elseif statusName == "Slow" then
					hasMovementStatus = true
					movementMultiplier = math.min(movementMultiplier, 1 - status.potency)
				elseif statusName == "Shock" then
					hasMovementStatus = true
					movementMultiplier = math.min(movementMultiplier, 1 - status.potency)
				elseif statusName == "Freeze" then
					hasMovementStatus = true
					movementMultiplier = 0
					frozen = true
				end
			end

			if hasMovementStatus then
				applyMovement(humanoid, state, math.clamp(movementMultiplier, 0, 1), frozen)
			else
				restoreMovement(humanoid, state)
			end

			if now > state.iceWindowEnds then
				state.iceHits = 0
			end

			if not hasAnyStatus and state.iceHits == 0 and not state.movementApplied then
				states[humanoid] = nil
			end
		end
	end)
end

return StatusService
]==]

local SOURCE_6 = [==[
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
]==]

local SOURCE_7 = [==[
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpellDefs = require(Shared:WaitForChild("SpellDefs"))
local SharedUtil = require(Shared:WaitForChild("SharedUtil"))

local Modules = script.Parent:FindFirstChild("Modules")
if not Modules or not Modules:IsA("Folder") then
	error("[Magic] ServerScriptService.Magic.Modules (Folder) がありません。ZIPのModulesフォルダを配置してください。")
end

local function requireMagicModule(name: string): any
	local candidate = Modules:FindFirstChild(name) or Modules:FindFirstChild(name .. ".lua")
	if not candidate or not candidate:IsA("ModuleScript") then
		error(string.format(
			"[Magic] ServerScriptService.Magic.Modules.%s (ModuleScript) がありません。%s.luaをModuleScriptとして配置するか、名前を%sに変更してください。",
			name,
			name,
			name
		))
	end
	return require(candidate)
end

local ManaService = requireMagicModule("ManaService")
local BehaviorResolver = requireMagicModule("BehaviorResolver")

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemote(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotes = ensureFolder(ReplicatedStorage, "Remotes")
local castSpellRequest = ensureRemote(remotes, "CastSpellRequest", "RemoteEvent") :: RemoteEvent
local spellFx = ensureRemote(remotes, "SpellFx", "RemoteEvent") :: RemoteEvent
local getSpellPreview = ensureRemote(remotes, "GetSpellPreview", "RemoteFunction") :: RemoteFunction

type RateState = {
	tokens: number,
	lastRefill: number,
}

type PlayerState = {
	castRate: RateState,
	previewRate: RateState,
	globalReadyAt: number,
	cooldowns: {[string]: number},
}

local playerStates: {[Player]: PlayerState} = {}

local function newRateState(burst: number): RateState
	return {
		tokens = burst,
		lastRefill = os.clock(),
	}
end

local function getPlayerState(player: Player): PlayerState
	local existing = playerStates[player]
	if existing then
		return existing
	end

	local state: PlayerState = {
		castRate = newRateState(SpellDefs.Security.RemoteBurst),
		previewRate = newRateState(SpellDefs.Security.PreviewBurst),
		globalReadyAt = 0,
		cooldowns = {},
	}

	playerStates[player] = state
	return state
end

local function takeToken(rate: RateState, burst: number, refillPerSecond: number): boolean
	local now = os.clock()
	local elapsed = math.max(0, now - rate.lastRefill)

	rate.lastRefill = now
	rate.tokens = math.min(burst, rate.tokens + elapsed * refillPerSecond)

	if rate.tokens < 1 then
		return false
	end

	rate.tokens -= 1
	return true
end

local function reject(player: Player, reason: string)
	spellFx:FireClient(player, "CastRejected", {
		Reason = reason,
	})
end

local function getCharacterOrigin(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = SharedUtil.GetRootPart(character)

	if not humanoid or humanoid.Health <= 0 or not root then
		return character, humanoid, root
	end

	return character, humanoid, root
end

local function sanitizeAim(player: Player, spec: any, payload: any): (Vector3?, Vector3?, string?)
	local character, humanoid, root = getCharacterOrigin(player)
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, "キャラクターの準備中です"
	end

	local aimPosition = payload.AimPosition
	local requestedDirection = payload.AimDirection

	if not SharedUtil.IsFiniteVector3(aimPosition) or not SharedUtil.IsFiniteVector3(requestedDirection) then
		return nil, nil, "照準データが正しくありません"
	end

	local originPosition = root.Position + Vector3.new(0, 1.5, 0)
	local offset = aimPosition - originPosition
	local maxDistance = SpellDefs.Security.MaxAimDistance

	if spec.Origin ~= "Self" and typeof(spec.OriginDef.CastRange) == "number" then
		maxDistance = math.min(maxDistance, spec.OriginDef.CastRange)
	end

	if spec.Origin == "Self" then
		return root.Position, root.CFrame.LookVector, nil
	end

	local fallbackDirection = SharedUtil.SafeUnit(requestedDirection, root.CFrame.LookVector)
	local direction = SharedUtil.SafeUnit(offset, fallbackDirection)
	local distance = math.clamp(offset.Magnitude, 1, maxDistance)
	local sanitizedPosition = originPosition + direction * distance

	if spec.Origin ~= "Throw" then
		local runtime = Workspace:FindFirstChild("MagicRuntime")
		local excludes: {Instance} = {character}

		if runtime then
			table.insert(excludes, runtime)
		end

		sanitizedPosition = SharedUtil.ClampLineOfSight(originPosition, sanitizedPosition, excludes)
	end

	return sanitizedPosition, direction, nil
end

local function parseSpec(payload: any): (any?, string?)
	if typeof(payload) ~= "table" then
		return nil, "リクエスト形式が正しくありません"
	end

	local spec = SpellDefs.Build(payload.Element, payload.Origin, payload.Form)
	if not spec then
		return nil, "存在しない魔法の組み合わせです"
	end

	return spec, nil
end

local function getCooldownRemaining(state: PlayerState, specKey: string): number
	local readyAt = state.cooldowns[specKey] or 0
	return math.max(0, readyAt - os.clock())
end

local function handlePlayerAdded(player: Player)
	getPlayerState(player)
end

local function handlePlayerRemoving(player: Player)
	playerStates[player] = nil
end

local function handlePreviewRequest(player: Player, payload: any): any
	local state = getPlayerState(player)
	local previewAllowed = takeToken(
		state.previewRate,
		SpellDefs.Security.PreviewBurst,
		SpellDefs.Security.PreviewRefillPerSecond
	)

	if not previewAllowed then
		return {
			Ok = false,
			Reason = "プレビューの更新が速すぎます",
		}
	end

	local spec, errorMessage = parseSpec(payload)
	if not spec then
		return {
			Ok = false,
			Reason = errorMessage,
		}
	end

	local preview = SpellDefs.ToPreview(spec)
	local mana, maxMana = ManaService.Get(player)

	preview.Ok = true
	preview.Mana = mana
	preview.MaxMana = maxMana
	preview.CooldownRemaining = getCooldownRemaining(state, spec.Key)

	return preview
end

local function callBehaviorResolver(
	player: Player,
	spec: any,
	aimPosition: Vector3,
	aimDirection: Vector3
): (boolean, any, any)
	local callOk, castOk, castError = pcall(
		BehaviorResolver.Cast,
		player,
		spec,
		aimPosition,
		aimDirection
	)

	return callOk, castOk, castError
end

local function handleCastRequest(player: Player, payload: any)
	local state = getPlayerState(player)
	local castAllowed = takeToken(
		state.castRate,
		SpellDefs.Security.RemoteBurst,
		SpellDefs.Security.RemoteRefillPerSecond
	)

	if not castAllowed then
		reject(player, "入力が速すぎます")
		return
	end

	local spec, parseError = parseSpec(payload)
	if not spec then
		reject(player, parseError or "魔法を構築できません")
		return
	end

	local now = os.clock()
	if now < state.globalReadyAt then
		reject(player, "詠唱準備中です")
		return
	end

	local cooldownRemaining = getCooldownRemaining(state, spec.Key)
	if cooldownRemaining > 0 then
		reject(player, string.format("クールダウン %.1f秒", cooldownRemaining))
		return
	end

	local aimPosition, aimDirection, aimError = sanitizeAim(player, spec, payload)
	if not aimPosition or not aimDirection then
		reject(player, aimError or "照準を確認できません")
		return
	end

	local spent, remainingMana = ManaService.TrySpend(player, spec.ManaCost)
	if not spent then
		reject(player, "魔力が足りません")
		return
	end

	state.globalReadyAt = now + SpellDefs.Security.GlobalCastInterval
	state.cooldowns[spec.Key] = now + spec.Cooldown

	local callOk, castOk, castError = callBehaviorResolver(
		player,
		spec,
		aimPosition,
		aimDirection
	)

	if not callOk or castOk ~= true then
		ManaService.Add(player, spec.ManaCost)
		state.cooldowns[spec.Key] = nil

		local reason: any
		if callOk then
			reason = castError
		else
			reason = castOk
		end

		warn("[Magic] Cast failed:", reason)
		reject(player, "魔法の発動に失敗しました")
		return
	end

	spellFx:FireClient(player, "CastAccepted", {
		Key = spec.Key,
		Cooldown = spec.Cooldown,
		Mana = remainingMana,
		ManaCost = spec.ManaCost,
		DisplayName = spec.DisplayName,
		Color = spec.ElementDef.Color,
	})
end

ManaService.Start()
BehaviorResolver.Init(spellFx)

Players.PlayerAdded:Connect(handlePlayerAdded)
Players.PlayerRemoving:Connect(handlePlayerRemoving)
getSpellPreview.OnServerInvoke = handlePreviewRequest
castSpellRequest.OnServerEvent:Connect(handleCastRequest)

for _, player in Players:GetPlayers() do
	getPlayerState(player)
end
]==]

local SOURCE_8 = [==[
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ElementDefs = require(Shared:WaitForChild("ElementDefs"))
local SpellDefs = require(Shared:WaitForChild("SpellDefs"))
local SharedUtil = require(Shared:WaitForChild("SharedUtil"))

-- 定義ファイルの世代差で Order が存在しない場合でも、UIが起動できるようにします。
-- 最新の ElementDefs / SpellDefs では各 Order が公開されています。
local function resolveOrder(candidate: any, fallback: {string}, label: string): {string}
	if typeof(candidate) == "table" and #candidate > 0 then
		return candidate :: {string}
	end

	warn(string.format("[Magic] %s が見つからないため既定順序を使用します。Shared定義ファイルを最新版へ置き換えてください。", label))
	return fallback
end

local ElementOrder = resolveOrder(ElementDefs.Order, {
	"Fire",
	"Ice",
	"Lightning",
	"Wind",
	"Poison",
	"Light",
}, "ElementDefs.Order")

local OriginOrder = resolveOrder(SpellDefs.OriginOrder, {
	"Throw",
	"Place",
	"Self",
	"Air",
	"Ground",
}, "SpellDefs.OriginOrder")

local FormOrder = resolveOrder(SpellDefs.FormOrder, {
	"Explosion",
	"Spread",
	"Homing",
	"Proximity",
	"Persistent",
}, "SpellDefs.FormOrder")

local function getElementDef(elementId: string): any?
	if typeof(ElementDefs.Get) == "function" then
		return ElementDefs.Get(elementId)
	end

	if typeof(ElementDefs.All) == "table" then
		return ElementDefs.All[elementId]
	end

	-- 古い定義形式（属性テーブルを直接 return）との互換用です。
	return ElementDefs[elementId]
end

local FALLBACK_ORIGINS: {[string]: any} = {
	Throw = { DisplayName = "投げる" },
	Place = { DisplayName = "置く" },
	Self = { DisplayName = "自分から出す" },
	Air = { DisplayName = "空中に出す" },
	Ground = { DisplayName = "地面から出す" },
}

local FALLBACK_FORMS: {[string]: any} = {
	Explosion = { DisplayName = "爆発" },
	Spread = { DisplayName = "拡散" },
	Homing = { DisplayName = "追尾" },
	Proximity = { DisplayName = "探知攻撃" },
	Persistent = { DisplayName = "持続範囲" },
}

local OriginDefs: {[string]: any}
if typeof(SpellDefs.Origins) == "table" then
	OriginDefs = SpellDefs.Origins
else
	warn("[Magic] SpellDefs.Origins がないため表示用の互換定義を使用します。SpellDefsを最新版へ置き換えてください。")
	OriginDefs = FALLBACK_ORIGINS
end

local FormDefs: {[string]: any}
if typeof(SpellDefs.Forms) == "table" then
	FormDefs = SpellDefs.Forms
else
	warn("[Magic] SpellDefs.Forms がないため表示用の互換定義を使用します。SpellDefsを最新版へ置き換えてください。")
	FormDefs = FALLBACK_FORMS
end

local defaultMaxMana = 100
if typeof(SpellDefs.Mana) == "table" and typeof(SpellDefs.Mana.DefaultMax) == "number" then
	defaultMaxMana = SpellDefs.Mana.DefaultMax
end

local maxAimDistance = 260
if typeof(SpellDefs.Security) == "table" and typeof(SpellDefs.Security.MaxAimDistance) == "number" then
	maxAimDistance = SpellDefs.Security.MaxAimDistance
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CastSpellRequest = Remotes:WaitForChild("CastSpellRequest") :: RemoteEvent
local SpellFx = Remotes:WaitForChild("SpellFx") :: RemoteEvent
local GetSpellPreview = Remotes:WaitForChild("GetSpellPreview") :: RemoteFunction

local selectedElementIndex = 1
local selectedOriginIndex = 1
local selectedFormIndex = 1
local previewData: {[string]: any}? = nil
local previewGeneration = 0
local cooldownsByKey: {[string]: number} = {}
local pendingUntil = 0
local toastGeneration = 0

local clientFxFolder = Workspace:FindFirstChild("MagicClientFx_" .. player.UserId)
if not clientFxFolder then
	clientFxFolder = Instance.new("Folder")
	clientFxFolder.Name = "MagicClientFx_" .. player.UserId
	clientFxFolder.Parent = Workspace
end

local function addCorner(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function addStroke(object: GuiObject, thickness: number, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Parent = object
end

local gui = Instance.new("ScreenGui")
gui.Name = "MagicHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "SpellPanel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.new(0.94, 0, 0, 158)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 38)
panel.BackgroundTransparency = 0.08
panel.Parent = gui
addCorner(panel, 16)
addStroke(panel, 2, 0.55)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(350, 145)
sizeConstraint.MaxSize = Vector2.new(720, 170)
sizeConstraint.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 8)
title.Size = UDim2.new(1, -36, 0, 25)
title.Font = Enum.Font.GothamBold
title.Text = "MAGIC FORGE"
title.TextColor3 = Color3.fromRGB(236, 238, 255)
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local selectorRow = Instance.new("Frame")
selectorRow.BackgroundTransparency = 1
selectorRow.Position = UDim2.fromOffset(16, 38)
selectorRow.Size = UDim2.new(1, -142, 0, 54)
selectorRow.Parent = panel

local selectorLayout = Instance.new("UIListLayout")
selectorLayout.FillDirection = Enum.FillDirection.Horizontal
selectorLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
selectorLayout.Padding = UDim.new(0, 8)
selectorLayout.Parent = selectorRow

local function makeSelectorButton(): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1 / 3, -6, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(43, 47, 72)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.TextWrapped = true
	button.Parent = selectorRow
	addCorner(button, 10)
	addStroke(button, 1, 0.72)
	return button
end

local elementButton = makeSelectorButton()
local originButton = makeSelectorButton()
local formButton = makeSelectorButton()

local castButton = Instance.new("TextButton")
castButton.Name = "CastButton"
castButton.AnchorPoint = Vector2.new(1, 0)
castButton.Position = UDim2.new(1, -16, 0, 38)
castButton.Size = UDim2.fromOffset(110, 54)
castButton.BackgroundColor3 = Color3.fromRGB(255, 92, 43)
castButton.Font = Enum.Font.GothamBlack
castButton.Text = "CAST\n[R]"
castButton.TextColor3 = Color3.fromRGB(20, 20, 28)
castButton.TextSize = 18
castButton.Parent = panel
addCorner(castButton, 12)
addStroke(castButton, 2, 0.35)

local manaBack = Instance.new("Frame")
manaBack.Position = UDim2.fromOffset(16, 105)
manaBack.Size = UDim2.new(1, -32, 0, 24)
manaBack.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
manaBack.Parent = panel
addCorner(manaBack, 8)

local manaFill = Instance.new("Frame")
manaFill.Size = UDim2.fromScale(1, 1)
manaFill.BackgroundColor3 = Color3.fromRGB(94, 148, 255)
manaFill.Parent = manaBack
addCorner(manaFill, 8)

local manaText = Instance.new("TextLabel")
manaText.BackgroundTransparency = 1
manaText.Size = UDim2.fromScale(1, 1)
manaText.Font = Enum.Font.GothamBold
manaText.TextColor3 = Color3.fromRGB(255, 255, 255)
manaText.TextSize = 14
manaText.Text = "MANA 100 / 100"
manaText.ZIndex = 3
manaText.Parent = manaBack

local infoText = Instance.new("TextLabel")
infoText.BackgroundTransparency = 1
infoText.Position = UDim2.fromOffset(18, 132)
infoText.Size = UDim2.new(1, -36, 0, 20)
infoText.Font = Enum.Font.GothamMedium
infoText.TextColor3 = Color3.fromRGB(194, 200, 224)
infoText.TextSize = 13
infoText.TextXAlignment = Enum.TextXAlignment.Left
infoText.Text = "Q: 属性 / E: 出し方 / F: 攻撃形態 / R・左クリック: 発動"
infoText.Parent = panel

local cooldownText = Instance.new("TextLabel")
cooldownText.AnchorPoint = Vector2.new(0.5, 0.5)
cooldownText.Position = UDim2.fromScale(0.5, 0.45)
cooldownText.Size = UDim2.fromOffset(360, 70)
cooldownText.BackgroundTransparency = 1
cooldownText.Font = Enum.Font.GothamBlack
cooldownText.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownText.TextStrokeTransparency = 0.35
cooldownText.TextSize = 32
cooldownText.Text = ""
cooldownText.Visible = false
cooldownText.Parent = gui

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 28)
toast.Size = UDim2.new(0.9, 0, 0, 48)
toast.BackgroundColor3 = Color3.fromRGB(22, 24, 40)
toast.BackgroundTransparency = 0.12
toast.Font = Enum.Font.GothamBold
toast.TextColor3 = Color3.fromRGB(255, 255, 255)
toast.TextSize = 17
toast.Text = ""
toast.Visible = false
toast.Parent = gui
addCorner(toast, 12)
addStroke(toast, 1, 0.55)
local toastConstraint = Instance.new("UISizeConstraint")
toastConstraint.MinSize = Vector2.new(280, 48)
toastConstraint.MaxSize = Vector2.new(520, 48)
toastConstraint.Parent = toast

local function currentSelection(): (string, string, string)
	return ElementOrder[selectedElementIndex], OriginOrder[selectedOriginIndex], FormOrder[selectedFormIndex]
end

local function spellKey(elementId: string, originId: string, formId: string): string
	return string.format("%s|%s|%s", elementId, originId, formId)
end

local function showToast(message: string, color: Color3?)
	toastGeneration += 1
	local generation = toastGeneration
	toast.Text = message
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.12
	toast.Visible = true

	task.delay(1.7, function()
		if generation ~= toastGeneration then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.25), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if generation == toastGeneration then
			toast.Visible = false
		end
	end)
end

local function updateMana()
	local mana = player:GetAttribute("Mana")
	local maxMana = player:GetAttribute("MaxMana")
	if typeof(mana) ~= "number" then
		mana = 0
	end
	if typeof(maxMana) ~= "number" or maxMana <= 0 then
		maxMana = defaultMaxMana
	end

	local ratio = math.clamp(mana / maxMana, 0, 1)
	TweenService:Create(manaFill, TweenInfo.new(0.12), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()
	manaText.Text = string.format("MANA %d / %d", math.floor(mana + 0.5), math.floor(maxMana + 0.5))
end

local function updateSelectionLabels()
	local elementId, originId, formId = currentSelection()
	local element = getElementDef(elementId)
	local origin = OriginDefs[originId]
	local form = FormDefs[formId]
	if not element or not origin or not form then
		return
	end

	elementButton.Text = "属性 [Q]\n" .. element.DisplayName
	originButton.Text = "出し方 [E]\n" .. origin.DisplayName
	formButton.Text = "攻撃形態 [F]\n" .. form.DisplayName
	elementButton.BackgroundColor3 = element.Color:Lerp(Color3.fromRGB(30, 32, 50), 0.46)
	castButton.BackgroundColor3 = element.Color
end

local function requestPreview()
	previewGeneration += 1
	local generation = previewGeneration
	local elementId, originId, formId = currentSelection()

	task.delay(0.08, function()
		if generation ~= previewGeneration then
			return
		end

		local ok, result = pcall(function()
			return GetSpellPreview:InvokeServer({
				Element = elementId,
				Origin = originId,
				Form = formId,
			})
		end)
		if generation ~= previewGeneration then
			return
		end
		if not ok or typeof(result) ~= "table" or result.Ok ~= true then
			previewData = nil
			infoText.Text = "プレビューを取得できません"
			return
		end

		previewData = result
		infoText.Text = string.format(
			"消費魔力 %d / ダメージ %.0f / CD %.1f秒",
			result.ManaCost,
			result.Damage,
			result.Cooldown
		)
		if typeof(result.CooldownRemaining) == "number" and typeof(result.Key) == "string" then
			cooldownsByKey[result.Key] = math.max(
				cooldownsByKey[result.Key] or 0,
				os.clock() + result.CooldownRemaining
			)
		end
	end)
end

local function selectionChanged()
	updateSelectionLabels()
	requestPreview()
end

local function cycleElement()
	selectedElementIndex = selectedElementIndex % #ElementOrder + 1
	selectionChanged()
end

local function cycleOrigin()
	selectedOriginIndex = selectedOriginIndex % #OriginOrder + 1
	selectionChanged()
end

local function cycleForm()
	selectedFormIndex = selectedFormIndex % #FormOrder + 1
	selectionChanged()
end

elementButton.Activated:Connect(cycleElement)
originButton.Activated:Connect(cycleOrigin)
formButton.Activated:Connect(cycleForm)

local function getAim(): (Vector3, Vector3)
	camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end

	local viewportPoint: Vector2
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		viewportPoint = camera.ViewportSize / 2
	else
		viewportPoint = UserInputService:GetMouseLocation()
	end

	local unitRay = camera:ViewportPointToRay(viewportPoint.X, viewportPoint.Y)
	local direction = SharedUtil.SafeUnit(unitRay.Direction)
	local excludes: {Instance} = {}
	if player.Character then
		table.insert(excludes, player.Character)
	end
	local runtime = Workspace:FindFirstChild("MagicRuntime")
	if runtime then
		table.insert(excludes, runtime)
	end
	if clientFxFolder then
		table.insert(excludes, clientFxFolder)
	end

	local result = Workspace:Raycast(
		unitRay.Origin,
		direction * maxAimDistance,
		SharedUtil.MakeRaycastParams(excludes)
	)
	local position = if result then result.Position else unitRay.Origin + direction * maxAimDistance
	return position, direction
end

local function castSpell()
	local now = os.clock()
	if now < pendingUntil then
		return
	end
	local elementId, originId, formId = currentSelection()
	local key = spellKey(elementId, originId, formId)
	local readyAt = cooldownsByKey[key] or 0
	if now < readyAt then
		showToast(string.format("クールダウン %.1f秒", readyAt - now), Color3.fromRGB(255, 214, 120))
		return
	end

	if previewData then
		local mana = player:GetAttribute("Mana")
		if typeof(mana) == "number" and mana < previewData.ManaCost then
			showToast("魔力が足りません", Color3.fromRGB(255, 133, 133))
			return
		end
	end

	local aimPosition, aimDirection = getAim()
	pendingUntil = now + 0.16
	CastSpellRequest:FireServer({
		Element = elementId,
		Origin = originId,
		Form = formId,
		AimPosition = aimPosition,
		AimDirection = aimDirection,
	})
end

castButton.Activated:Connect(castSpell)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		cycleElement()
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleOrigin()
	elseif input.KeyCode == Enum.KeyCode.F then
		cycleForm()
	elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonR2 then
		castSpell()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		castSpell()
	end
end)

local function makeFxPart(
	position: Vector3,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.12
	part.Size = size
	part.Shape = shape or Enum.PartType.Ball
	part.Position = position
	part.Parent = clientFxFolder
	return part
end

local function pulseSphere(position: Vector3, color: Color3, finalDiameter: number, duration: number)
	local part = makeFxPart(position, Vector3.new(0.4, 0.4, 0.4), color, Enum.PartType.Ball, 0.12)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(finalDiameter, finalDiameter, finalDiameter),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function ring(position: Vector3, color: Color3, radius: number, duration: number, startTransparency: number?)
	local part = makeFxPart(
		position + Vector3.new(0, 0.15, 0),
		Vector3.new(0.18, 0.5, 0.5),
		color,
		Enum.PartType.Cylinder,
		startTransparency or 0.35
	)
	part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, 0, math.rad(90))
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.18, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function beam(fromPosition: Vector3, toPosition: Vector3, color: Color3, duration: number)
	local delta = toPosition - fromPosition
	local distance = delta.Magnitude
	if distance <= 0.05 then
		return
	end
	local midpoint = fromPosition + delta * 0.5
	local part = makeFxPart(midpoint, Vector3.new(0.28, 0.28, distance), color, Enum.PartType.Block, 0.04)
	part.CFrame = CFrame.lookAt(midpoint, toPosition)
	local tween = TweenService:Create(part, TweenInfo.new(duration), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, distance),
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

SpellFx.OnClientEvent:Connect(function(kind: string, payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	if kind == "CastAccepted" then
		pendingUntil = 0
		if typeof(payload.Cooldown) == "number" and typeof(payload.Key) == "string" then
			cooldownsByKey[payload.Key] = os.clock() + payload.Cooldown
		end
		showToast(payload.DisplayName or "魔法発動！", payload.Color)
	elseif kind == "CastRejected" then
		pendingUntil = 0
		showToast(payload.Reason or "発動できません", Color3.fromRGB(255, 135, 135))
	elseif kind == "Cast" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 3.4, 0.22)
	elseif kind == "Impact" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 2.8, 0.20)
	elseif kind == "Explosion" and typeof(payload.Position) == "Vector3" then
		local radius = payload.Radius or 8
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), radius * 2, 0.42)
		ring(payload.Position, payload.Color or Color3.new(1, 1, 1), radius, 0.48, 0.18)
	elseif kind == "Chain" and typeof(payload.From) == "Vector3" and typeof(payload.To) == "Vector3" then
		beam(payload.From, payload.To, payload.Color or Color3.new(1, 1, 1), 0.24)
	elseif kind == "Area" and typeof(payload.Position) == "Vector3" then
		ring(
			payload.Position,
			payload.Color or Color3.new(1, 1, 1),
			payload.Radius or 10,
			math.min(payload.Duration or 3, 6),
			0.48
		)
	elseif kind == "TrapArmed" and typeof(payload.Position) == "Vector3" then
		ring(payload.Position, payload.Color or Color3.new(1, 1, 1), payload.Radius or 8, 0.65, 0.38)
	elseif kind == "GroundRise" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 5.5, 0.32)
	elseif kind == "Heal" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 4.5, 0.38)
	end
end)

player:GetAttributeChangedSignal("Mana"):Connect(updateMana)
player:GetAttributeChangedSignal("MaxMana"):Connect(updateMana)

RunService.RenderStepped:Connect(function()
	local elementId, originId, formId = currentSelection()
	local remaining = (cooldownsByKey[spellKey(elementId, originId, formId)] or 0) - os.clock()
	if remaining > 0 then
		cooldownText.Visible = true
		cooldownText.Text = string.format("COOLDOWN %.1f", remaining)
		castButton.Text = string.format("%.1f", remaining)
	else
		cooldownText.Visible = false
		castButton.Text = "CAST\n[R]"
	end
end)

updateSelectionLabels()
updateMana()
requestPreview()
]==]

upsertSource(shared, "ModuleScript", "ElementDefs", SOURCE_1, {"ElementDefs.lua"})
upsertSource(shared, "ModuleScript", "SpellDefs", SOURCE_2, {"SpellDefs.lua"})
upsertSource(shared, "ModuleScript", "SharedUtil", SOURCE_3, {"SharedUtil.lua"})
upsertSource(modules, "ModuleScript", "ManaService", SOURCE_4, {"ManaService.lua"})
upsertSource(modules, "ModuleScript", "StatusService", SOURCE_5, {"StatusService.lua"})
upsertSource(modules, "ModuleScript", "BehaviorResolver", SOURCE_6, {"BehaviorResolver.lua"})
upsertSource(magic, "Script", "SpellService", SOURCE_7, {"SpellService.server.lua", "SpellService.lua"})
upsertSource(starterScripts, "LocalScript", "SpellClient", SOURCE_8, {"SpellClient.client.lua", "SpellClient.lua"})

print("[Magic Installer] 完了: Shared、Modules、Remotes、SpellService、SpellClientを最新版へ更新しました。")
