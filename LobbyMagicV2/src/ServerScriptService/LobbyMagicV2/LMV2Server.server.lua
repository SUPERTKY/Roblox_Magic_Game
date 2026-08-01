--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local systemRoot = ReplicatedStorage:WaitForChild("LobbyMagicV2")
local shared = systemRoot:WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))
local SpellCatalog = require(shared:WaitForChild("LMV2SpellCatalog"))
local ManaService = require(script.Parent:WaitForChild("Modules"):WaitForChild("LMV2ManaService"))
local FireVFX = require(script.Parent:WaitForChild("Modules"):WaitForChild("LMV2FireVFX"))

local remotes = systemRoot:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = systemRoot
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function ensureRemoteFunction(name: string): RemoteFunction
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local lobbyActionRequest = ensureRemoteEvent("LobbyActionRequest")
local castSpellRequest = ensureRemoteEvent("CastSpellRequest")
local stateChanged = ensureRemoteEvent("StateChanged")
local feedback = ensureRemoteEvent("Feedback")
local getSnapshot = ensureRemoteFunction("GetSnapshot")

local runtimeFolder = Workspace:FindFirstChild("LMV2_Runtime")
if not runtimeFolder then
	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "LMV2_Runtime"
	runtimeFolder.Parent = Workspace
end

local exampleSpell = SpellCatalog.BuildExample()
local lastLobbyActionAt: { [Player]: number } = {}
local lastCastRequestAt: { [Player]: number } = {}
local activeProjectileCount: { [Player]: number } = {}
local promptConnections: { RBXScriptConnection } = {}

local function serverTime(): number
	return Workspace:GetServerTimeNow()
end

local function getState(player: Player): string
	local value = player:GetAttribute(Config.StateAttribute)
	return if typeof(value) == "string" then value else "Lobby"
end

local function hasExampleSpell(player: Player): boolean
	return player:GetAttribute(Config.HasSpellAttribute) == true
		and SpellCatalog.IsExampleSpellKey(player:GetAttribute(Config.SpellKeyAttribute))
end

local function worldRoot(): Instance?
	return Workspace:FindFirstChild(Config.World.FolderName)
end

local function worldPart(name: string): BasePart?
	local root = worldRoot()
	local object = if root then root:FindFirstChild(name) else nil
	return if object and object:IsA("BasePart") then object else nil
end

local function worldStatus(): { [string]: boolean }
	return {
		LobbySpawn = worldPart(Config.World.LobbySpawnName) ~= nil,
		GroundSpawn = worldPart(Config.World.GroundSpawnName) ~= nil,
		ForgeConsole = worldPart(Config.World.ForgeConsoleName) ~= nil,
		ExitGate = worldPart(Config.World.ExitGateName) ~= nil,
		ReturnGate = worldPart(Config.World.ReturnGateName) ~= nil,
	}
end

local function snapshot(player: Player): { [string]: any }
	local vfxReady, missingVfxObject = FireVFX.GetInstallStatus()
	return {
		SystemId = Config.SystemId,
		State = getState(player),
		HasSpell = hasExampleSpell(player),
		Spell = exampleSpell,
		Mana = ManaService.Get(player),
		MaxMana = Config.Mana.Maximum,
		CooldownEnd = tonumber(player:GetAttribute(Config.CooldownEndAttribute)) or 0,
		ServerTime = serverTime(),
		World = worldStatus(),
		FireVFXReady = vfxReady,
		MissingFireVFXObject = missingVfxObject,
	}
end

local function sendSnapshot(player: Player)
	stateChanged:FireClient(player, snapshot(player))
end

local function sendFeedback(player: Player, code: string, message: string)
	feedback:FireClient(player, {
		Code = code,
		Message = message,
		ServerTime = serverTime(),
	})
end

local function teleportCharacter(player: Player, destination: BasePart?): boolean
	if not destination then
		return false
	end

	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(destination.CFrame * CFrame.new(0, Config.World.TeleportHeight, 0))
	return true
end

local function setLobby(player: Player, shouldTeleport: boolean)
	player:SetAttribute(Config.StateAttribute, "Lobby")
	player:SetAttribute(Config.CooldownEndAttribute, 0)
	ManaService.SetFull(player)

	if shouldTeleport and not teleportCharacter(player, worldPart(Config.World.LobbySpawnName)) then
		sendFeedback(
			player,
			"WorldMissing",
			"LobbySpawn が見つからないため、ロビー位置へ移動できません。"
		)
	end

	sendSnapshot(player)
end

local function createExampleSpell(player: Player)
	if getState(player) ~= "Lobby" then
		sendFeedback(player, "LobbyOnly", "魔法はロビーの工房で作成してください。")
		return
	end

	player:SetAttribute(Config.HasSpellAttribute, true)
	player:SetAttribute(Config.SpellKeyAttribute, exampleSpell.Key)
	ManaService.SetFull(player)
	sendFeedback(
		player,
		"SpellCreated",
		string.format(
			"%s を作成しました（マナ%d / クールダウン%.1f秒）",
			exampleSpell.DisplayName,
			exampleSpell.ManaCost,
			exampleSpell.Cooldown
		)
	)
	sendSnapshot(player)
end

local function enterGround(player: Player)
	if getState(player) ~= "Lobby" then
		return
	end
	if not hasExampleSpell(player) then
		sendFeedback(player, "NeedSpell", "先に ForgeConsole で炎魔法を作ってください。")
		return
	end

	local destination = worldPart(Config.World.GroundSpawnName)
	if not destination then
		sendFeedback(player, "WorldMissing", "GroundSpawn が見つかりません。")
		return
	end

	player:SetAttribute(Config.StateAttribute, "Ground")
	player:SetAttribute(Config.CooldownEndAttribute, 0)
	ManaService.SetFull(player)
	teleportCharacter(player, destination)
	sendFeedback(
		player,
		"EnteredGround",
		"グラウンドへ出ました。F・左クリック・タッチボタンで発動できます。"
	)
	sendSnapshot(player)
end

local function isFiniteVector3(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < 100000
		and math.abs(value.Y) < 100000
		and math.abs(value.Z) < 100000
end

local function getTeamId(player: Player?, character: Model?): string?
	if player then
		local playerTeam = player:GetAttribute(Config.TeamAttribute)
		if typeof(playerTeam) == "string" and playerTeam ~= "" then
			return playerTeam
		end
	end

	if character then
		local characterTeam = character:GetAttribute(Config.TeamAttribute)
		if typeof(characterTeam) == "string" and characterTeam ~= "" then
			return characterTeam
		end
	end
	return nil
end

local function isEnemy(caster: Player, targetPlayer: Player?, targetCharacter: Model): boolean
	if targetPlayer == caster or targetCharacter == caster.Character then
		return false
	end
	if targetPlayer and getState(targetPlayer) ~= "Ground" then
		return false
	end

	if targetPlayer and not caster.Neutral and not targetPlayer.Neutral and caster.Team == targetPlayer.Team then
		return false
	end

	local casterTeam = getTeamId(caster, caster.Character)
	local targetTeam = getTeamId(targetPlayer, targetCharacter)
	if casterTeam and targetTeam and casterTeam == targetTeam then
		return false
	end

	return true
end

local function findCharacterModel(part: BasePart): Model?
	local current: Instance? = part
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function damageEnemies(caster: Player, position: Vector3)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = if caster.Character
		then { runtimeFolder, caster.Character }
		else { runtimeFolder }
	overlap.MaxParts = Config.Security.MaxExplosionParts

	local damaged: { [Humanoid]: boolean } = {}
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(position, exampleSpell.ExplosionRadius, overlap)) do
		local character = findCharacterModel(part)
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or damaged[humanoid] then
			continue
		end

		local targetPlayer = Players:GetPlayerFromCharacter(character)
		if not isEnemy(caster, targetPlayer, character) then
			continue
		end

		damaged[humanoid] = true
		humanoid:TakeDamage(exampleSpell.Damage)
	end
end

local function launchFireball(player: Player, requestedAim: Vector3)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	local origin = root.Position + root.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0)
	local offset = requestedAim - origin
	if offset.Magnitude < 2 then
		offset = root.CFrame.LookVector * 12
	end
	local distance = math.min(offset.Magnitude, exampleSpell.MaxDistance, Config.Security.MaxAimDistance)
	local direction = offset.Unit
	local targetPosition = origin + direction * distance

	FireVFX.Cast(CFrame.lookAt(origin, targetPosition), runtimeFolder)
	local projectile = FireVFX.CreateProjectile(CFrame.lookAt(origin, targetPosition), runtimeFolder)
	projectile:SetAttribute("LMV2_OwnerUserId", player.UserId)
	activeProjectileCount[player] = (activeProjectileCount[player] or 0) + 1

	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = { character, runtimeFolder }
	raycast.IgnoreWater = true

	local traveled = 0
	local finished = false
	local connection: RBXScriptConnection? = nil

	local function finish(position: Vector3, shouldExplode: boolean)
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
		if player.Parent == Players then
			activeProjectileCount[player] = math.max(0, (activeProjectileCount[player] or 1) - 1)
		else
			activeProjectileCount[player] = nil
		end

		if shouldExplode then
			FireVFX.Explode(position, runtimeFolder)
			damageEnemies(player, position)
		end
	end

	connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if player.Parent ~= Players or not projectile.Parent then
			finish(projectile.Position, false)
			return
		end

		local remaining = distance - traveled
		if remaining <= 0 then
			finish(targetPosition, true)
			return
		end

		local stepDistance = math.min(exampleSpell.ProjectileSpeed * math.min(deltaTime, 0.1), remaining)
		local currentPosition = projectile.Position
		local result = Workspace:Raycast(currentPosition, direction * stepDistance, raycast)
		if result then
			finish(result.Position, true)
			return
		end

		local nextPosition = currentPosition + direction * stepDistance
		projectile.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
		traveled += stepDistance
		if traveled >= distance then
			finish(targetPosition, true)
		end
	end)
end

local function handleCastRequest(player: Player, payload: any)
	local now = serverTime()
	local previousRequest = lastCastRequestAt[player] or -math.huge
	if now - previousRequest < Config.Security.MinCastInterval then
		return
	end
	lastCastRequestAt[player] = now

	if getState(player) ~= "Ground" or not hasExampleSpell(player) then
		sendFeedback(player, "CannotCastHere", "炎魔法は作成後、グラウンドでのみ使えます。")
		return
	end

	local aimPosition = if typeof(payload) == "table" then payload.AimPosition else payload
	if not isFiniteVector3(aimPosition) then
		sendFeedback(player, "InvalidAim", "狙う位置を取得できませんでした。")
		return
	end

	local cooldownEnd = tonumber(player:GetAttribute(Config.CooldownEndAttribute)) or 0
	if now < cooldownEnd then
		sendFeedback(player, "Cooldown", string.format("あと%.1f秒です。", cooldownEnd - now))
		return
	end

	if (activeProjectileCount[player] or 0) >= Config.Security.MaxProjectilesPerPlayer then
		return
	end
	local vfxReady, missingVfxObject = FireVFX.GetInstallStatus()
	if not vfxReady then
		sendFeedback(
			player,
			"FireVFXMissing",
			string.format(
				"炎エフェクトがありません（%s）。InstallRobloxMagicSystem.luaを実行してください。",
				missingVfxObject or "FireballVFX/Templates"
			)
		)
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local characterRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if
		not character
		or not humanoid
		or humanoid.Health <= 0
		or not characterRoot
		or not characterRoot:IsA("BasePart")
	then
		return
	end
	if not ManaService.Spend(player, exampleSpell.ManaCost) then
		sendFeedback(player, "ManaLow", string.format("マナが%d必要です。", exampleSpell.ManaCost))
		return
	end

	player:SetAttribute(Config.CooldownEndAttribute, now + exampleSpell.Cooldown)
	launchFireball(player, aimPosition)
	sendSnapshot(player)
end

local function handleLobbyAction(player: Player, action: any)
	if typeof(action) ~= "string" then
		return
	end

	local now = serverTime()
	local previous = lastLobbyActionAt[player] or -math.huge
	if now - previous < Config.Security.LobbyActionInterval then
		return
	end
	lastLobbyActionAt[player] = now

	if action == "CreateExampleSpell" then
		createExampleSpell(player)
	elseif action == "EnterGround" then
		enterGround(player)
	elseif action == "ReturnLobby" and getState(player) == "Ground" then
		setLobby(player, true)
		sendFeedback(player, "ReturnedLobby", "ロビーへ戻りました。")
	end
end

local function ensurePrompt(part: BasePart, name: string, actionText: string, objectText: string): ProximityPrompt
	local existing = part:FindFirstChild(name)
	local prompt: ProximityPrompt
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		if existing then
			existing:Destroy()
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.Parent = part
	end

	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = Config.World.PromptDistance
	prompt.RequiresLineOfSight = false
	return prompt
end

local function disconnectPromptConnections()
	for _, connection in ipairs(promptConnections) do
		connection:Disconnect()
	end
	table.clear(promptConnections)
end

local function setupWorldPrompts()
	disconnectPromptConnections()

	local forge = worldPart(Config.World.ForgeConsoleName)
	local exitGate = worldPart(Config.World.ExitGateName)
	local returnGate = worldPart(Config.World.ReturnGateName)

	if forge then
		local prompt = ensurePrompt(forge, "LMV2_ForgePrompt", "炎魔法を作る", "魔法工房")
		table.insert(promptConnections, prompt.Triggered:Connect(createExampleSpell))
	end
	if exitGate then
		local prompt = ensurePrompt(exitGate, "LMV2_ExitPrompt", "出撃する", "グラウンドゲート")
		table.insert(promptConnections, prompt.Triggered:Connect(enterGround))
	end
	if returnGate then
		local prompt = ensurePrompt(returnGate, "LMV2_ReturnPrompt", "ロビーへ戻る", "帰還ゲート")
		table.insert(
			promptConnections,
			prompt.Triggered:Connect(function(player: Player)
				if getState(player) == "Ground" then
					setLobby(player, true)
					sendFeedback(player, "ReturnedLobby", "ロビーへ戻りました。")
				end
			end)
		)
	end

	local status = worldStatus()
	for name, ready in pairs(status) do
		if not ready then
			warn(
				string.format(
					"[LobbyMagicV2] Workspace/%s/%s が見つかりません。READMEの3D構造を確認してください。",
					Config.World.FolderName,
					name
				)
			)
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	character:WaitForChild("HumanoidRootPart", 10)
	task.defer(function()
		if player.Character ~= character then
			return
		end
		local destination = if getState(player) == "Ground"
			then worldPart(Config.World.GroundSpawnName)
			else worldPart(Config.World.LobbySpawnName)
		teleportCharacter(player, destination)
	end)

	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			if player.Character == character then
				setLobby(player, false)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Config.StateAttribute, "Lobby")
	player:SetAttribute(Config.HasSpellAttribute, false)
	player:SetAttribute(Config.SpellKeyAttribute, "")
	player:SetAttribute(Config.CooldownEndAttribute, 0)
	ManaService.AddPlayer(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

ManaService.Start()
setupWorldPrompts()

local fireVfxReady, missingFireVfxObject = FireVFX.GetInstallStatus()
if not fireVfxReady then
	warn(
		string.format(
			"[LobbyMagicV2] 炎VFXが未導入です: %s。RobloxMagicSystem/InstallRobloxMagicSystem.luaを実行してください。",
			missingFireVfxObject or "ReplicatedStorage/FireballVFX/Templates"
		)
	)
end

local function isDirectWorldChild(instance: Instance): boolean
	local root = worldRoot()
	if not root or instance.Parent ~= root then
		return false
	end

	return instance.Name == Config.World.LobbySpawnName
		or instance.Name == Config.World.GroundSpawnName
		or instance.Name == Config.World.ForgeConsoleName
		or instance.Name == Config.World.ExitGateName
		or instance.Name == Config.World.ReturnGateName
end

Workspace.ChildAdded:Connect(function(child: Instance)
	if child.Name == Config.World.FolderName then
		task.defer(setupWorldPrompts)
	end
end)
Workspace.DescendantAdded:Connect(function(descendant: Instance)
	if isDirectWorldChild(descendant) then
		task.defer(setupWorldPrompts)
	end
end)
Workspace.DescendantRemoving:Connect(function(descendant: Instance)
	if isDirectWorldChild(descendant) then
		task.defer(setupWorldPrompts)
	end
end)

lobbyActionRequest.OnServerEvent:Connect(handleLobbyAction)
castSpellRequest.OnServerEvent:Connect(handleCastRequest)
getSnapshot.OnServerInvoke = function(player: Player)
	return snapshot(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	ManaService.RemovePlayer(player)
	lastLobbyActionAt[player] = nil
	lastCastRequestAt[player] = nil
	activeProjectileCount[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[LobbyMagicV2] サーバー起動完了。旧Magicシステムとは独立して動作します。")
