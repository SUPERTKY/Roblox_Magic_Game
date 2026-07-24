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
