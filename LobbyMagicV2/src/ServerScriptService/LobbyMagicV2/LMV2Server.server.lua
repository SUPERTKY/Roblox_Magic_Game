--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local systemRoot = ReplicatedStorage:WaitForChild("LobbyMagicV2")
local shared = systemRoot:WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))
local SpellCatalog = require(shared:WaitForChild("LMV2SpellCatalog"))
local FireVFX = require(shared:WaitForChild("LMV2FireVFX"))
local ManaService = require(script.Parent:WaitForChild("Modules"):WaitForChild("LMV2ManaService"))
local SpellStore = require(script.Parent:WaitForChild("Modules"):WaitForChild("LMV2SpellStore"))

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
local vfxEvent = ensureRemoteEvent("VFXEvent")
local getSnapshot = ensureRemoteFunction("GetSnapshot")

local runtimeFolder = Workspace:FindFirstChild("LMV2_Runtime")
if not runtimeFolder then
	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "LMV2_Runtime"
	runtimeFolder.Parent = Workspace
end

local lastLobbyActionAt: { [Player]: number } = {}
local lastCastRequestAt: { [Player]: number } = {}
local activeProjectileCount: { [Player]: number } = {}
local saveScheduled: { [Player]: boolean } = {}
local promptConnections: { RBXScriptConnection } = {}

local function serverTime(): number
	return Workspace:GetServerTimeNow()
end

local function getState(player: Player): string
	local value = player:GetAttribute(Config.StateAttribute)
	return if typeof(value) == "string" then value else "Lobby"
end

local function getActiveStoredSpell(player: Player): any?
	local session = SpellStore.Get(player)
	if not session or session.ActiveSlot < 1 then
		return nil
	end
	return session.Spells[session.ActiveSlot]
end

local function getPlayerSpell(player: Player): { [string]: any }?
	local storedSpell = getActiveStoredSpell(player)
	if not storedSpell then
		return nil
	end
	local spell = SpellCatalog.Build(storedSpell.Selection)
	if spell then
		spell.DisplayName = storedSpell.Name
	end
	return spell
end

local function hasActiveSpell(player: Player): boolean
	return player:GetAttribute(Config.HasSpellAttribute) == true and getPlayerSpell(player) ~= nil
end

local function syncActiveSpellAttributes(player: Player)
	local session = SpellStore.Get(player)
	local storedSpell = getActiveStoredSpell(player)
	local spell = getPlayerSpell(player)
	player:SetAttribute(Config.ActiveSlotAttribute, if session then session.ActiveSlot else 0)
	player:SetAttribute(Config.HasSpellAttribute, spell ~= nil)
	player:SetAttribute(Config.SpellKeyAttribute, if spell then spell.Key else "")

	local selection = if storedSpell then storedSpell.Selection else SpellCatalog.DefaultSelection
	for category, attributeName in pairs(Config.SelectionAttributes) do
		player:SetAttribute(attributeName, selection[category])
	end
end

local function publicSpellList(player: Player): { any }
	local result = {}
	local session = SpellStore.Get(player)
	if not session then
		return result
	end
	for slot, storedSpell in ipairs(session.Spells) do
		local spell = SpellCatalog.Build(storedSpell.Selection)
		if spell then
			table.insert(result, {
				Slot = slot,
				Name = storedSpell.Name,
				Selection = spell.Selection,
				ManaCost = spell.ManaCost,
				Cooldown = spell.Cooldown,
				Damage = spell.Damage,
				TotalDamage = spell.TotalDamage,
				ProjectileCount = spell.ProjectileCount,
				ExplosionRadius = spell.ExplosionRadius,
			})
		end
	end
	return result
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
		ForgeUIZone = worldPart(Config.World.ForgeUIZoneName) ~= nil,
		ExitGate = worldPart(Config.World.ExitGateName) ~= nil,
		ReturnGate = worldPart(Config.World.ReturnGateName) ~= nil,
	}
end

local function snapshot(player: Player): { [string]: any }
	local vfxReady, missingVfxObject = FireVFX.GetInstallStatus()
	local spell = getPlayerSpell(player)
	return {
		SystemId = Config.SystemId,
		State = getState(player),
		HasSpell = hasActiveSpell(player),
		Spell = spell,
		Selection = if spell then spell.Selection else SpellCatalog.CopyDefaultSelection(),
		Spells = publicSpellList(player),
		ActiveSlot = tonumber(player:GetAttribute(Config.ActiveSlotAttribute)) or 0,
		DataReady = player:GetAttribute(Config.DataReadyAttribute) == true,
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

local spawnRandom = Random.new()

local function randomSpawnCFrame(destination: BasePart): CFrame
	local padding = math.max(0, Config.World.SpawnEdgePadding)
	local halfWidth = math.max(0, destination.Size.X * 0.5 - padding)
	local halfDepth = math.max(0, destination.Size.Z * 0.5 - padding)
	local x = if halfWidth > 0 then spawnRandom:NextNumber(-halfWidth, halfWidth) else 0
	local z = if halfDepth > 0 then spawnRandom:NextNumber(-halfDepth, halfDepth) else 0
	local y = destination.Size.Y * 0.5 + Config.World.TeleportHeight

	return destination.CFrame * CFrame.new(x, y, z)
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
	character:PivotTo(randomSpawnCFrame(destination))
	return true
end

local function playerIsInsidePart(player: Player, part: BasePart?): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not part or not root or not root:IsA("BasePart") then
		return false
	end

	local localPosition = part.CFrame:PointToObjectSpace(root.Position)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
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

local function canEditSpells(player: Player): boolean
	if player:GetAttribute(Config.DataReadyAttribute) ~= true or not SpellStore.Get(player) then
		sendFeedback(player, "DataNotReady", "魔法データを準備中です。少し待ってください。")
		return false
	end
	if getState(player) ~= "Lobby" then
		sendFeedback(player, "LobbyOnly", "魔法の作成と削除はロビーの工房で行ってください。")
		return false
	end
	if not playerIsInsidePart(player, worldPart(Config.World.ForgeUIZoneName)) then
		sendFeedback(
			player,
			"ForgeZoneOnly",
			"魔法の作成と削除は ForgeUIZone の中で行ってください。"
		)
		return false
	end
	return true
end

local function saveSpellData(player: Player)
	SpellStore.MarkDirty(player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(1, function()
		saveScheduled[player] = nil
		if player.Parent ~= Players then
			return
		end
		local ok, message = SpellStore.Save(player)
		if not ok then
			sendFeedback(
				player,
				"SaveFailed",
				"魔法データの保存に失敗しました。自動的に再試行します。"
			)
			warn(string.format("[LobbyMagicV2] %s の保存に失敗: %s", player.Name, message or "unknown"))
		end
	end)
end

local function createSpell(player: Player, requestedName: any, requestedSelection: any)
	if not canEditSpells(player) then
		return
	end
	local session = SpellStore.Get(player)
	if not session then
		return
	end
	if #session.Spells >= Config.Inventory.MaximumSpells then
		sendFeedback(
			player,
			"InventoryFull",
			"魔法は最大5個です。工房で不要な魔法を削除してください。"
		)
		return
	end

	local name = SpellCatalog.NormalizeName(requestedName)
	if not name then
		sendFeedback(
			player,
			"InvalidSpellName",
			string.format("魔法名は1〜%d文字で入力してください。", Config.Inventory.MaximumNameLength)
		)
		return
	end
	local spell = SpellCatalog.Build(requestedSelection)
	if not spell then
		sendFeedback(player, "InvalidSelection", "選択された魔法設定は使用できません。")
		return
	end

	table.insert(session.Spells, {
		Name = name,
		Selection = SpellStore.CopySelection(spell.Selection),
	})
	session.ActiveSlot = #session.Spells
	syncActiveSpellAttributes(player)
	ManaService.SetFull(player)
	saveSpellData(player)
	sendFeedback(
		player,
		"SpellCreated",
		string.format(
			"%d番に「%s」を保存しました（%d球 / マナ%d / CD %.1f秒）",
			session.ActiveSlot,
			name,
			spell.ProjectileCount,
			spell.ManaCost,
			spell.Cooldown
		)
	)
	sendSnapshot(player)
end

local function deleteSpell(player: Player, requestedSlot: any)
	if not canEditSpells(player) then
		return
	end
	local session = SpellStore.Get(player)
	local slot = if typeof(requestedSlot) == "number" then math.floor(requestedSlot) else 0
	if not session or slot < 1 or slot > #session.Spells then
		sendFeedback(player, "InvalidSlot", "削除する魔法スロットを選んでください。")
		return
	end

	local removedName = session.Spells[slot].Name
	table.remove(session.Spells, slot)
	if #session.Spells == 0 then
		session.ActiveSlot = 0
	elseif session.ActiveSlot > slot then
		session.ActiveSlot -= 1
	elseif session.ActiveSlot == slot then
		session.ActiveSlot = math.min(slot, #session.Spells)
	end
	syncActiveSpellAttributes(player)
	saveSpellData(player)
	sendFeedback(player, "SpellDeleted", string.format("「%s」を削除しました。", removedName))
	sendSnapshot(player)
end

local function equipSpell(player: Player, requestedSlot: any)
	local session = SpellStore.Get(player)
	local slot = if typeof(requestedSlot) == "number" then math.floor(requestedSlot) else 0
	if player:GetAttribute(Config.DataReadyAttribute) ~= true or not session then
		return
	end
	if slot < 1 or slot > #session.Spells or slot == session.ActiveSlot then
		return
	end
	session.ActiveSlot = slot
	syncActiveSpellAttributes(player)
	saveSpellData(player)
	sendFeedback(
		player,
		"SpellEquipped",
		string.format("%d番「%s」を装備しました。", slot, session.Spells[slot].Name)
	)
	sendSnapshot(player)
end

local function enterGround(player: Player)
	if getState(player) ~= "Lobby" then
		return
	end
	if not hasActiveSpell(player) then
		sendFeedback(player, "NeedSpell", "先に ForgeUIZone で魔法を作ってください。")
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

local function damageEnemies(caster: Player, position: Vector3, spell: { [string]: any })
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = if caster.Character
		then { runtimeFolder, caster.Character }
		else { runtimeFolder }
	overlap.MaxParts = Config.Security.MaxExplosionParts

	local damaged: { [Humanoid]: boolean } = {}
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(position, spell.ExplosionRadius, overlap)) do
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
		humanoid:TakeDamage(spell.Damage)
	end
end

local function damageDirect(caster: Player, hitPart: BasePart?, spell: { [string]: any })
	if not hitPart then
		return
	end
	local character = findCharacterModel(hitPart)
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local targetPlayer = Players:GetPlayerFromCharacter(character)
	if humanoid and humanoid.Health > 0 and isEnemy(caster, targetPlayer, character) then
		humanoid:TakeDamage(spell.Damage)
	end
end

local function launchProjectile(player: Player, requestedAim: Vector3, spell: { [string]: any }, spreadAngle: number)
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
	local distance = math.min(offset.Magnitude, spell.MaxDistance, Config.Security.MaxAimDistance)
	local aimCFrame = CFrame.lookAt(Vector3.zero, offset.Unit)
	local direction = (aimCFrame * CFrame.Angles(0, math.rad(spreadAngle), 0)).LookVector
	local targetPosition = origin + direction * distance

	local castCFrame = CFrame.lookAt(origin, targetPosition)
	vfxEvent:FireAllClients("Cast", { CFrame = castCFrame, Scale = spell.ProjectileScale })
	local projectile = FireVFX.CreateProjectile(castCFrame, runtimeFolder)
	projectile.Size *= spell.ProjectileScale
	projectile:SetAttribute("LMV2_OwnerUserId", player.UserId)
	activeProjectileCount[player] = (activeProjectileCount[player] or 0) + 1

	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = { character, runtimeFolder }
	raycast.IgnoreWater = true

	local traveled = 0
	local finished = false
	local connection: RBXScriptConnection? = nil

	local function finish(position: Vector3, shouldImpact: boolean, hitPart: BasePart?)
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

		if shouldImpact then
			vfxEvent:FireAllClients("Explosion", {
				Position = position,
				Scale = spell.ExplosionVFXScale,
			})
			if spell.IsDirect then
				damageDirect(player, hitPart, spell)
			else
				damageEnemies(player, position, spell)
			end
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

		local stepDistance = math.min(spell.ProjectileSpeed * math.min(deltaTime, 0.1), remaining)
		local currentPosition = projectile.Position
		local result = Workspace:Raycast(currentPosition, direction * stepDistance, raycast)
		if result then
			finish(result.Position, true, result.Instance)
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

local function launchSpell(player: Player, requestedAim: Vector3, spell: { [string]: any })
	for _, angle in ipairs(spell.SpreadAngles) do
		launchProjectile(player, requestedAim, spell, angle)
	end
end

local function handleCastRequest(player: Player, payload: any)
	local now = serverTime()
	local previousRequest = lastCastRequestAt[player] or -math.huge
	if now - previousRequest < Config.Security.MinCastInterval then
		return
	end
	lastCastRequestAt[player] = now

	local spell = getPlayerSpell(player)
	if getState(player) ~= "Ground" or not hasActiveSpell(player) or not spell then
		sendFeedback(
			player,
			"CannotCastHere",
			"魔法を作成・装備してから、グラウンドで使用してください。"
		)
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

	if
		spell.ProjectileCount > Config.Security.MaxProjectilesPerCast
		or (activeProjectileCount[player] or 0) + spell.ProjectileCount > Config.Security.MaxProjectilesPerPlayer
	then
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
	if not ManaService.Spend(player, spell.ManaCost) then
		sendFeedback(player, "ManaLow", string.format("マナが%d必要です。", spell.ManaCost))
		return
	end

	player:SetAttribute(Config.CooldownEndAttribute, now + spell.Cooldown)
	launchSpell(player, aimPosition, spell)
	sendSnapshot(player)
end

local function handleLobbyAction(player: Player, action: any)
	local actionName: string?
	local requestedSelection: any = nil
	local requestedName: any = nil
	local requestedSlot: any = nil
	if typeof(action) == "string" then
		actionName = action
	elseif typeof(action) == "table" and typeof(action.Action) == "string" then
		actionName = action.Action
		requestedSelection = action.Selection
		requestedName = action.Name
		requestedSlot = action.Slot
	else
		return
	end

	local now = serverTime()
	local previous = lastLobbyActionAt[player] or -math.huge
	if now - previous < Config.Security.LobbyActionInterval then
		return
	end
	lastLobbyActionAt[player] = now

	if actionName == "CreateSpell" then
		createSpell(player, requestedName, requestedSelection)
	elseif actionName == "DeleteSpell" then
		deleteSpell(player, requestedSlot)
	elseif actionName == "EquipSpell" then
		equipSpell(player, requestedSlot)
	elseif actionName == "EnterGround" then
		enterGround(player)
	elseif actionName == "ReturnLobby" and getState(player) == "Ground" then
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

	local exitGate = worldPart(Config.World.ExitGateName)
	local returnGate = worldPart(Config.World.ReturnGateName)

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
	player:SetAttribute(Config.ActiveSlotAttribute, 0)
	player:SetAttribute(Config.DataReadyAttribute, false)
	for category, attributeName in pairs(Config.SelectionAttributes) do
		player:SetAttribute(attributeName, SpellCatalog.DefaultSelection[category])
	end
	ManaService.AddPlayer(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	local loaded, loadMessage = SpellStore.Load(player)
	if player.Parent ~= Players then
		SpellStore.Remove(player)
		return
	end
	if not loaded then
		warn(
			string.format(
				"[LobbyMagicV2] %s のDataStore読み込みに失敗: %s",
				player.Name,
				loadMessage or "unknown"
			)
		)
		sendFeedback(
			player,
			"LoadFailed",
			"魔法データを読み込めませんでした。再参加してください。"
		)
		sendSnapshot(player)
		return
	end

	player:SetAttribute(Config.DataReadyAttribute, true)
	syncActiveSpellAttributes(player)
	if loadMessage then
		sendFeedback(player, "StudioDataFallback", loadMessage)
	end
	sendSnapshot(player)
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
		or instance.Name == Config.World.ForgeUIZoneName
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
	local saved, saveMessage = SpellStore.Save(player, true)
	if not saved then
		warn(string.format("[LobbyMagicV2] %s の退出時保存に失敗: %s", player.Name, saveMessage or "unknown"))
	end
	SpellStore.Remove(player)
	ManaService.RemovePlayer(player)
	lastLobbyActionAt[player] = nil
	lastCastRequestAt[player] = nil
	activeProjectileCount[player] = nil
	saveScheduled[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

task.spawn(function()
	while true do
		task.wait(Config.Persistence.AutosaveSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			local saved, saveMessage = SpellStore.Save(player)
			if not saved then
				warn(
					string.format(
						"[LobbyMagicV2] %s の自動保存に失敗: %s",
						player.Name,
						saveMessage or "unknown"
					)
				)
			end
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local saved, saveMessage = SpellStore.Save(player, true)
		if not saved then
			warn(
				string.format(
					"[LobbyMagicV2] %s の終了時保存に失敗: %s",
					player.Name,
					saveMessage or "unknown"
				)
			)
		end
	end
end)

print("[LobbyMagicV2] サーバー起動完了。旧Magicシステムとは独立して動作します。")
