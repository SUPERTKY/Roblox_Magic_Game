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
local Config = require(systemRoot:WaitForChild("Shared"):WaitForChild("LMV2Config"))
local remotes = systemRoot:WaitForChild("Remotes")
local castSpellRequest = remotes:WaitForChild("CastSpellRequest") :: RemoteEvent
local feedback = remotes:WaitForChild("Feedback") :: RemoteEvent

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

feedback.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Message) ~= "string" then
		return
	end
	if payload.Code == "Cooldown" then
		return
	end
	print(string.format("[LobbyMagicV2] %s", payload.Message))
end)
