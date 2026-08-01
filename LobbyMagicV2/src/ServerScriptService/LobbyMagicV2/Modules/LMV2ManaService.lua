--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("LobbyMagicV2"):WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))

type ManaState = {
	value: number,
	lastSpendAt: number,
	lastReplicatedAt: number,
}

local states: { [Player]: ManaState } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local ManaService = {}

local function serverTime(): number
	return workspace:GetServerTimeNow()
end

local function replicate(player: Player, state: ManaState, force: boolean?)
	local now = serverTime()
	if not force and now - state.lastReplicatedAt < Config.Mana.ReplicationStep then
		return
	end

	state.lastReplicatedAt = now
	player:SetAttribute(Config.ManaAttribute, state.value)
	player:SetAttribute(Config.MaxManaAttribute, Config.Mana.Maximum)
end

function ManaService.AddPlayer(player: Player)
	local state: ManaState = {
		value = Config.Mana.Maximum,
		lastSpendAt = -math.huge,
		lastReplicatedAt = -math.huge,
	}
	states[player] = state
	replicate(player, state, true)
end

function ManaService.RemovePlayer(player: Player)
	states[player] = nil
end

function ManaService.Get(player: Player): number
	local state = states[player]
	return if state then state.value else 0
end

function ManaService.SetFull(player: Player)
	local state = states[player]
	if not state then
		ManaService.AddPlayer(player)
		state = states[player]
	end
	if not state then
		return
	end

	state.value = Config.Mana.Maximum
	state.lastSpendAt = -math.huge
	replicate(player, state, true)
end

function ManaService.CanSpend(player: Player, amount: number): boolean
	local state = states[player]
	return state ~= nil and amount >= 0 and state.value + 1e-4 >= amount
end

function ManaService.Spend(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end

	local state = states[player]
	if not state or state.value + 1e-4 < amount then
		return false
	end

	state.value = math.max(0, state.value - amount)
	state.lastSpendAt = serverTime()
	replicate(player, state, true)
	return true
end

function ManaService.Start()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		local now = serverTime()
		local safeDelta = math.min(math.max(deltaTime, 0), 0.25)

		for player, state in pairs(states) do
			if player.Parent ~= Players then
				states[player] = nil
				continue
			end

			if now - state.lastSpendAt >= Config.Mana.RegenDelayAfterCast and state.value < Config.Mana.Maximum then
				state.value = math.min(Config.Mana.Maximum, state.value + Config.Mana.RegenPerSecond * safeDelta)
			end
			replicate(player, state, false)
		end
	end)
end

return ManaService
