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
