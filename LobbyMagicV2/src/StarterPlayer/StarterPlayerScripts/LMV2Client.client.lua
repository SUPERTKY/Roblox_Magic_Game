--!strict

-- UIとは独立した入力スクリプトです。
-- LMV2UIを削除・無効化しても、PC/ゲームパッド/タッチの発動はここに残ります。

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local systemRoot = ReplicatedStorage:WaitForChild("LobbyMagicV2")
local shared = systemRoot:WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))
local FireVFX = require(shared:WaitForChild("LMV2FireVFX"))
local remotes = systemRoot:WaitForChild("Remotes")
local castSpellRequest = remotes:WaitForChild("CastSpellRequest") :: RemoteEvent
local feedback = remotes:WaitForChild("Feedback") :: RemoteEvent
local vfxEvent = remotes:WaitForChild("VFXEvent") :: RemoteEvent

local clientVfxFolder = Workspace:FindFirstChild(string.format("LMV2_ClientVFX_%d", player.UserId))
if not clientVfxFolder then
	clientVfxFolder = Instance.new("Folder")
	clientVfxFolder.Name = string.format("LMV2_ClientVFX_%d", player.UserId)
	clientVfxFolder.Parent = Workspace
end

local ACTION_CAST = "LMV2_CastFirebomb"
local lastTouchViewportPosition: Vector2? = nil

local function isInGround(): boolean
	return player:GetAttribute(Config.StateAttribute) == "Ground"
end

local function getAimPosition(viewportPosition: Vector2?): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local point = viewportPosition
	if not point then
		point = camera.ViewportSize / 2
	end

	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	if player.Character then
		table.insert(excluded, player.Character)
	end
	local runtime = Workspace:FindFirstChild("LMV2_Runtime")
	if runtime then
		table.insert(excluded, runtime)
	end
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = false

	local result = Workspace:Raycast(ray.Origin, ray.Direction * Config.Security.MaxAimDistance, params)
	return if result then result.Position else ray.Origin + ray.Direction * Config.Security.MaxAimDistance
end

local function castAt(viewportPosition: Vector2?)
	if not isInGround() then
		return
	end

	local aimPosition = getAimPosition(viewportPosition)
	if aimPosition then
		castSpellRequest:FireServer({ AimPosition = aimPosition })
	end
end

local function onCastAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not isInGround() then
		return Enum.ContextActionResult.Pass
	end

	castAt(if UserInputService.TouchEnabled then lastTouchViewportPosition else nil)
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_CAST, onCastAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle(ACTION_CAST, "FIRE")
ContextActionService:SetDescription(ACTION_CAST, "ファイアボムを発動")
ContextActionService:SetPosition(ACTION_CAST, UDim2.new(1, -120, 1, -170))

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	local inset = GuiService:GetGuiInset()
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchViewportPosition = Vector2.new(input.Position.X, input.Position.Y) - inset
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mousePosition = UserInputService:GetMouseLocation() - inset
		castAt(mousePosition)
	end
end)

local function updateTouchButton()
	local button = ContextActionService:GetButton(ACTION_CAST)
	if button then
		button.Visible = isInGround()
	end
end

player:GetAttributeChangedSignal(Config.StateAttribute):Connect(updateTouchButton)
task.defer(updateTouchButton)

vfxEvent.OnClientEvent:Connect(function(kind: any, payload: any)
	if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
		return
	end

	local ok, message = pcall(function()
		if kind == "Cast" and typeof(payload.CFrame) == "CFrame" then
			FireVFX.Cast(payload.CFrame, clientVfxFolder)
		elseif kind == "Explosion" and typeof(payload.Position) == "Vector3" then
			FireVFX.Explode(payload.Position, clientVfxFolder)
		end
	end)
	if not ok then
		warn(string.format("[LobbyMagicV2] クライアントVFXの表示に失敗しました: %s", tostring(message)))
	end
end)

feedback.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Message) ~= "string" then
		return
	end
	if payload.Code == "Cooldown" then
		return
	end
	print(string.format("[LobbyMagicV2] %s", payload.Message))
end)
