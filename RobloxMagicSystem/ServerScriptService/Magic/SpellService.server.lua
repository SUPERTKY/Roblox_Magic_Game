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
