--!strict

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpellDefinitions = require(Shared:WaitForChild("SpellDefinitions"))
local spellStore = DataStoreService:GetDataStore("PlayerCustomSpell_v1")

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function getOrCreateRemote(name: string, className: string): Instance
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local castSpell = getOrCreateRemote("CastSpell", "RemoteEvent") :: RemoteEvent
local saveCustomSpell = getOrCreateRemote("SaveCustomSpell", "RemoteFunction") :: RemoteFunction
local systemMessage = getOrCreateRemote("SystemMessage", "RemoteEvent") :: RemoteEvent

local BATTLE_GROUND_NAME = "BattleGround"
local BATTLE_BOUNDS_NAME = "BattleBounds"
local BATTLE_SPAWNS_NAME = "BattleSpawnPoints"
local DESTRUCTIBLE_BUILDING_TAG = "DestructibleBuilding"

local world = workspace:WaitForChild("MagicGameWorld")
local portal = world:WaitForChild("BattlePortal") :: BasePart
local portalPrompt = portal:WaitForChild("ProximityPrompt") :: ProximityPrompt
local random = Random.new()

local customSpells: { [Player]: any } = {}
local portalDebounce: { [Player]: boolean } = {}
local lastCastAt: { [Player]: number } = {}
local lastSaveRequestAt: { [Player]: number } = {}
local collapsedBuildings: { [Instance]: boolean } = {}

local function setSpellAttributes(player: Player, spell: any?)
	if not spell then
		player:SetAttribute("HasCustomSpell", false)
		player:SetAttribute("CustomSpellName", nil)
		player:SetAttribute("CustomSpellElement", nil)
		player:SetAttribute("CustomSpellStyle", nil)
		customSpells[player] = nil
		return
	end

	customSpells[player] = spell
	player:SetAttribute("CustomSpellName", spell.Name)
	player:SetAttribute("CustomSpellElement", spell.ElementId)
	player:SetAttribute("CustomSpellStyle", spell.StyleId)
	player:SetAttribute("HasCustomSpell", true)
end

local function loadCustomSpell(player: Player)
	player:SetAttribute("SpellDataLoaded", false)
	setSpellAttributes(player, nil)

	local success, saved = pcall(function()
		return spellStore:GetAsync(tostring(player.UserId))
	end)

	if player.Parent ~= Players then
		return
	end

	if success and typeof(saved) == "table" then
		local name = saved.Name
		local elementId = saved.ElementId
		local styleId = saved.StyleId
		if typeof(name) == "string" and typeof(elementId) == "string" and typeof(styleId) == "string" then
			local spell = SpellDefinitions.BuildSpell(name, elementId, styleId)
			if spell then
				setSpellAttributes(player, spell)
			end
		end
	elseif not success then
		warn("Custom spell load failed for " .. player.Name)
	end

	player:SetAttribute("SpellDataLoaded", true)
end

local function filterSpellName(player: Player, rawName: string): (string?, string?)
	local cleaned = string.match(rawName, "^%s*(.-)%s*$") or ""
	local characterCount = utf8.len(cleaned)
	if not characterCount or characterCount < 1 or characterCount > 20 then
		return nil, "魔法名は1〜20文字で入力してください"
	end

	local success, filtered = pcall(function()
		local result = TextService:FilterStringAsync(cleaned, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not success or typeof(filtered) ~= "string" or filtered == "" then
		return nil, "魔法名を確認できませんでした。別の名前を試してください"
	end

	return filtered, nil
end

saveCustomSpell.OnServerInvoke = function(player: Player, rawName: unknown, elementId: unknown, styleId: unknown)
	if player:GetAttribute("IsInBattle") == true then
		return { Success = false, Message = "バトル中は魔法を変更できません" }
	end
	local now = os.clock()
	if now - (lastSaveRequestAt[player] or 0) < 2 then
		return { Success = false, Message = "少し待ってからもう一度作成してください" }
	end
	lastSaveRequestAt[player] = now

	if typeof(rawName) ~= "string" or typeof(elementId) ~= "string" or typeof(styleId) ~= "string" then
		return { Success = false, Message = "魔法の設定が正しくありません" }
	end

	local filteredName, nameError = filterSpellName(player, rawName)
	if not filteredName then
		return { Success = false, Message = nameError }
	end

	local spell = SpellDefinitions.BuildSpell(filteredName, elementId, styleId)
	if not spell then
		return { Success = false, Message = "属性または戦闘スタイルが正しくありません" }
	end

	setSpellAttributes(player, spell)

	local saved, saveError = pcall(function()
		spellStore:SetAsync(tostring(player.UserId), {
			Name = spell.Name,
			ElementId = spell.ElementId,
			StyleId = spell.StyleId,
		})
	end)
	if not saved then
		warn("Custom spell save failed for " .. player.Name .. ": " .. tostring(saveError))
	end

	return {
		Success = true,
		Message = if saved then "魔法「" .. spell.Name .. "」を作成して保存しました" else "魔法を作成しました（今回は一時保存です）",
	}
end

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

local function getBattleSetup(): (Instance?, Instance?, BasePart?)
	local battleGround = workspace:FindFirstChild(BATTLE_GROUND_NAME)
	if not battleGround then
		return nil, nil, nil
	end

	local spawnPoints = battleGround:FindFirstChild(BATTLE_SPAWNS_NAME, true)
	local bounds = battleGround:FindFirstChild(BATTLE_BOUNDS_NAME, true)
	if not spawnPoints or not bounds or not bounds:IsA("BasePart") then
		return battleGround, spawnPoints, nil
	end

	return battleGround, spawnPoints, bounds
end

local function isPointInsidePart(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

local function isPlayerInsideBattleGround(player: Player): boolean
	if player:GetAttribute("IsInBattle") ~= true then
		return false
	end

	local _, _, bounds = getBattleSetup()
	local _, _, root = getAliveCharacter(player)
	return bounds ~= nil and root ~= nil and isPointInsidePart(bounds, root.Position)
end

local function sendPlayerToBattle(player: Player)
	if portalDebounce[player] or player:GetAttribute("IsInBattle") then
		return
	end
	if player:GetAttribute("SpellDataLoaded") ~= true then
		systemMessage:FireClient(player, "魔法データを読み込み中です")
		return
	end
	if player:GetAttribute("HasCustomSpell") ~= true or not customSpells[player] then
		systemMessage:FireClient(player, "先に名前・属性・戦闘スタイルを選んで魔法を作成してください")
		return
	end

	local character, _, root = getAliveCharacter(player)
	if not character or not root then
		return
	end

	local battleGround, spawnPointsFolder, battleBounds = getBattleSetup()
	if not battleGround or not spawnPointsFolder or not battleBounds then
		systemMessage:FireClient(player, "バトルグラウンドの設定が未完成です")
		return
	end

	local spawnPoints: { BasePart } = {}
	for _, candidate in spawnPointsFolder:GetChildren() do
		if candidate:IsA("BasePart") and isPointInsidePart(battleBounds, candidate.Position) then
			table.insert(spawnPoints, candidate)
		end
	end
	if #spawnPoints == 0 then
		systemMessage:FireClient(player, "BattleBounds内にスポーン地点がありません")
		return
	end

	portalDebounce[player] = true
	local chosen = spawnPoints[random:NextInteger(1, #spawnPoints)]
	local offset = Vector3.new(random:NextNumber(-2, 2), 4, random:NextNumber(-2, 2))
	character:PivotTo(chosen.CFrame + offset)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	player:SetAttribute("IsInBattle", true)

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
	return targetPlayer ~= nil and isPlayerInsideBattleGround(targetPlayer)
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

local function damageHumanoid(attacker: Player, humanoid: Humanoid, spell: any)
	if not canDamage(attacker, humanoid) then
		return
	end
	humanoid:TakeDamage(spell.Damage)
	applySlow(humanoid, spell.SlowDuration)
end

local function findDestructibleBuilding(hitPart: Instance?): Instance?
	local current: Instance? = hitPart
	while current and current ~= workspace do
		if CollectionService:HasTag(current, DESTRUCTIBLE_BUILDING_TAG)
			or current:GetAttribute("DestructibleBuilding") == true
		then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function collapseBuilding(hitPart: Instance?, impactPosition: Vector3, spell: any)
	if spell.CanDestroyBuildings ~= true then
		return
	end

	local building = findDestructibleBuilding(hitPart)
	if not building or collapsedBuildings[building] then
		return
	end
	collapsedBuildings[building] = true
	building:SetAttribute("CollapsedBySpell", true)

	local parts: { BasePart } = {}
	if building:IsA("BasePart") then
		table.insert(parts, building)
	end
	for _, descendant in building:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	local impulseStrength = math.clamp(spell.Damage * 2.5, 45, 90)
	for _, part in parts do
		part.Anchored = false
		part.CanCollide = true
		local away = part.Position - impactPosition
		local horizontalDirection = if away.Magnitude > 0.05 then away.Unit else Vector3.new(1, 0, 0)
		local impulseDirection = (horizontalDirection + Vector3.new(0, 0.35, 0)).Unit
		part:ApplyImpulse(impulseDirection * part.AssemblyMass * impulseStrength)
	end
end

local function showImpact(position: Vector3, spell: any)
	local effect = Instance.new("Part")
	effect.Name = spell.Name .. "_Impact"
	effect.Shape = Enum.PartType.Ball
	effect.Size = Vector3.one
	effect.CFrame = CFrame.new(position)
	effect.Color = spell.Color
	effect.Material = Enum.Material.Neon
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanTouch = false
	effect.CanQuery = false
	effect.Transparency = 0.2
	effect.Parent = world

	local finalDiameter = math.max(3, spell.BlastRadius * 2)
	TweenService:Create(
		effect,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * finalDiameter, Transparency = 1 }
	):Play()
	Debris:AddItem(effect, 0.35)
end

local function damageAtImpact(attacker: Player, hitPart: Instance?, position: Vector3, spell: any)
	if spell.BlastRadius <= 0 then
		local humanoid = findHumanoidFromPart(hitPart)
		if humanoid then
			damageHumanoid(attacker, humanoid, spell)
		end
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = attacker.Character and { attacker.Character } or {}

	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(position, spell.BlastRadius, overlapParams) do
		local humanoid = findHumanoidFromPart(part)
		if humanoid and not hitHumanoids[humanoid] then
			hitHumanoids[humanoid] = true
			damageHumanoid(attacker, humanoid, spell)
		end
	end
end

local function launchProjectile(player: Player, targetPosition: Vector3)
	local spell = customSpells[player]
	if not spell then
		return
	end

	local character, _, root = getAliveCharacter(player)
	if not character or not root then
		return
	end
	if not isPlayerInsideBattleGround(player) then
		if player:GetAttribute("IsInBattle") == true then
			player:SetAttribute("IsInBattle", false)
			systemMessage:FireClient(player, "魔法はバトルグラウンド内でのみ使えます")
		end
		return
	end
	if targetPosition.X ~= targetPosition.X or targetPosition.Y ~= targetPosition.Y or targetPosition.Z ~= targetPosition.Z then
		return
	end

	local now = os.clock()
	if now - (lastCastAt[player] or 0) < spell.Cooldown then
		return
	end

	local origin = root.Position + Vector3.new(0, 1.6, 0)
	local offset = targetPosition - origin
	if offset.Magnitude < 1 then
		return
	end
	lastCastAt[player] = now
	local direction = offset.Unit

	local projectile = Instance.new("Part")
	projectile.Name = spell.Name
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.one * spell.ProjectileRadius * 2
	projectile.CFrame = CFrame.new(origin + direction * 3)
	projectile.Color = spell.Color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Parent = world

	local light = Instance.new("PointLight")
	light.Color = spell.Color
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

		local stepDistance = spell.Speed * math.min(deltaTime, 0.1)
		local step = direction * stepDistance
		local result = workspace:Raycast(position, step, raycastParams)

		if result then
			projectile.Position = result.Position
			showImpact(result.Position, spell)
			collapseBuilding(result.Instance, result.Position, spell)
			damageAtImpact(player, result.Instance, result.Position, spell)
			if connection then
				connection:Disconnect()
			end
			projectile:Destroy()
			return
		end

		position += step
		travelled += stepDistance
		projectile.Position = position

		if travelled >= spell.Range then
			if connection then
				connection:Disconnect()
			end
			projectile:Destroy()
		end
	end)
end

castSpell.OnServerEvent:Connect(function(player: Player, targetPosition: unknown)
	if typeof(targetPosition) ~= "Vector3" then
		return
	end
	launchProjectile(player, targetPosition :: Vector3)
end)

local function configurePlayer(player: Player)
	player:SetAttribute("IsInBattle", false)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("IsInBattle", false)
	end)
	task.spawn(loadCustomSpell, player)
end

Players.PlayerAdded:Connect(configurePlayer)
for _, player in Players:GetPlayers() do
	configurePlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	customSpells[player] = nil
	portalDebounce[player] = nil
	lastCastAt[player] = nil
	lastSaveRequestAt[player] = nil
end)
