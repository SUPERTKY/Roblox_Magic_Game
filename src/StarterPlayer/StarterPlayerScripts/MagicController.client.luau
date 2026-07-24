--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local SpellDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpellDefinitions"))
local castSpell = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CastSpell") :: RemoteEvent

local spellOrder = { "Fireball", "FrostBolt", "ArcaneBolt" }
local selectedIndex = 1
local buttons: { TextButton } = {}
local localCooldowns: { [string]: number } = {}

local gui = Instance.new("ScreenGui")
gui.Name = "MagicBattleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local message = Instance.new("TextLabel")
message.Name = "BattleMessage"
message.AnchorPoint = Vector2.new(0.5, 0)
message.Position = UDim2.fromScale(0.5, 0.04)
message.Size = UDim2.fromOffset(430, 42)
message.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
message.BackgroundTransparency = 0.15
message.TextColor3 = Color3.fromRGB(235, 242, 255)
message.Font = Enum.Font.GothamBold
message.TextSize = 18
message.Text = "魔法ゲートに入ってバトルへ！"
message.Parent = gui

local messageCorner = Instance.new("UICorner")
messageCorner.CornerRadius = UDim.new(0, 10)
messageCorner.Parent = message

local hotbar = Instance.new("Frame")
hotbar.Name = "SpellHotbar"
hotbar.AnchorPoint = Vector2.new(0.5, 1)
hotbar.Position = UDim2.new(0.5, 0, 1, -24)
hotbar.Size = UDim2.fromOffset(444, 80)
hotbar.BackgroundColor3 = Color3.fromRGB(20, 23, 32)
hotbar.BackgroundTransparency = 0.12
hotbar.Parent = gui

local hotbarCorner = Instance.new("UICorner")
hotbarCorner.CornerRadius = UDim.new(0, 12)
hotbarCorner.Parent = hotbar

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 8)
layout.Parent = hotbar

local function refreshSelection()
	for index, button in buttons do
		local spellName = spellOrder[index]
		local definition = SpellDefinitions[spellName]
		if index == selectedIndex then
			button.BackgroundColor3 = definition.Color
			button.TextColor3 = Color3.fromRGB(15, 18, 24)
		else
			button.BackgroundColor3 = Color3.fromRGB(48, 53, 68)
			button.TextColor3 = Color3.fromRGB(240, 244, 255)
		end
	end
end

local function selectSpell(index: number)
	if spellOrder[index] then
		selectedIndex = index
		refreshSelection()
	end
end

for index, spellName in spellOrder do
	local definition = SpellDefinitions[spellName]
	local button = Instance.new("TextButton")
	button.Name = spellName
	button.Size = UDim2.fromOffset(136, 60)
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextWrapped = true
	button.Text = string.format("%d  %s", index, definition.DisplayName)
	button.Parent = hotbar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = button

	button.Activated:Connect(function()
		selectSpell(index)
	end)
	table.insert(buttons, button)
end

local castButton = Instance.new("TextButton")
castButton.Name = "CastButton"
castButton.AnchorPoint = Vector2.new(1, 1)
castButton.Position = UDim2.new(1, -24, 1, -120)
castButton.Size = UDim2.fromOffset(92, 92)
castButton.BackgroundColor3 = Color3.fromRGB(112, 78, 255)
castButton.BackgroundTransparency = 0.08
castButton.Text = "発射"
castButton.TextColor3 = Color3.fromRGB(255, 255, 255)
castButton.Font = Enum.Font.GothamBold
castButton.TextSize = 22
castButton.Visible = UserInputService.TouchEnabled
castButton.Parent = gui

local castCorner = Instance.new("UICorner")
castCorner.CornerRadius = UDim.new(1, 0)
castCorner.Parent = castButton

local crosshair = Instance.new("TextLabel")
crosshair.Name = "Crosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(28, 28)
crosshair.BackgroundTransparency = 1
crosshair.Text = "+"
crosshair.TextColor3 = Color3.fromRGB(255, 255, 255)
crosshair.TextStrokeTransparency = 0.35
crosshair.Font = Enum.Font.GothamBold
crosshair.TextSize = 28
crosshair.Visible = false
crosshair.Parent = gui

local function getAimPosition(): Vector3
	if UserInputService.TouchEnabled and camera then
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		return ray.Origin + ray.Direction * 300
	end
	return mouse.Hit.Position
end

local function tryCast()
	if player:GetAttribute("IsInBattle") ~= true then
		return
	end

	local spellName = spellOrder[selectedIndex]
	local definition = SpellDefinitions[spellName]
	local now = os.clock()
	if now - (localCooldowns[spellName] or 0) < definition.Cooldown then
		return
	end

	localCooldowns[spellName] = now
	castSpell:FireServer(spellName, getAimPosition())
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		selectSpell(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		selectSpell(2)
	elseif input.KeyCode == Enum.KeyCode.Three then
		selectSpell(3)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryCast()
	end
end)

castButton.Activated:Connect(tryCast)

local function refreshBattleState()
	local inBattle = player:GetAttribute("IsInBattle") == true
	message.Text = if inBattle then "バトル中：1 / 2 / 3 で魔法を選択" else "魔法ゲートに入ってバトルへ！"
	crosshair.Visible = inBattle
	hotbar.Visible = inBattle
	castButton.Visible = inBattle and UserInputService.TouchEnabled
end

player:GetAttributeChangedSignal("IsInBattle"):Connect(refreshBattleState)
refreshSelection()
refreshBattleState()

