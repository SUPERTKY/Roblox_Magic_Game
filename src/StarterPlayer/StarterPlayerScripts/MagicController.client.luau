--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local SpellDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpellDefinitions"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local castSpell = remotes:WaitForChild("CastSpell") :: RemoteEvent
local saveCustomSpell = remotes:WaitForChild("SaveCustomSpell") :: RemoteFunction
local systemMessage = remotes:WaitForChild("SystemMessage") :: RemoteEvent

local selectedElementId = SpellDefinitions.ElementOrder[1]
local selectedStyleId = SpellDefinitions.StyleOrder[1]
local elementButtons: { [string]: TextButton } = {}
local styleButtons: { [string]: TextButton } = {}
local lastLocalCast = 0
local currentSpell: any? = nil
local refreshChoiceButtons: () -> ()

local gui = Instance.new("ScreenGui")
gui.Name = "MagicBattleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local message = Instance.new("TextLabel")
message.Name = "SystemMessage"
message.AnchorPoint = Vector2.new(0.5, 0)
message.Position = UDim2.fromScale(0.5, 0.035)
message.Size = UDim2.new(0.88, 0, 0, 44)
message.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
message.BackgroundTransparency = 0.1
message.TextColor3 = Color3.fromRGB(235, 242, 255)
message.Font = Enum.Font.GothamBold
message.TextSize = 17
message.Text = "魔法データを読み込んでいます…"
message.Parent = gui

local messageConstraint = Instance.new("UISizeConstraint")
messageConstraint.MaxSize = Vector2.new(620, 44)
messageConstraint.Parent = message

local messageCorner = Instance.new("UICorner")
messageCorner.CornerRadius = UDim.new(0, 10)
messageCorner.Parent = message

local creator = Instance.new("ScrollingFrame")
creator.Name = "SpellCreator"
creator.AnchorPoint = Vector2.new(0.5, 0.5)
creator.Position = UDim2.fromScale(0.5, 0.53)
creator.Size = UDim2.new(0.92, 0, 0.82, 0)
creator.BackgroundColor3 = Color3.fromRGB(24, 28, 39)
creator.BackgroundTransparency = 0.04
creator.AutomaticCanvasSize = Enum.AutomaticSize.Y
creator.CanvasSize = UDim2.fromOffset(0, 0)
creator.ScrollBarThickness = 6
creator.ScrollBarImageColor3 = Color3.fromRGB(151, 126, 255)
creator.Parent = gui

local creatorConstraint = Instance.new("UISizeConstraint")
creatorConstraint.MaxSize = Vector2.new(560, 500)
creatorConstraint.MinSize = Vector2.new(300, 320)
creatorConstraint.Parent = creator

local creatorCorner = Instance.new("UICorner")
creatorCorner.CornerRadius = UDim.new(0, 14)
creatorCorner.Parent = creator

local creatorPadding = Instance.new("UIPadding")
creatorPadding.PaddingLeft = UDim.new(0, 18)
creatorPadding.PaddingRight = UDim.new(0, 18)
creatorPadding.PaddingTop = UDim.new(0, 16)
creatorPadding.PaddingBottom = UDim.new(0, 16)
creatorPadding.Parent = creator

local creatorLayout = Instance.new("UIListLayout")
creatorLayout.Padding = UDim.new(0, 9)
creatorLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
creatorLayout.SortOrder = Enum.SortOrder.LayoutOrder
creatorLayout.Parent = creator

local function makeLabel(text: string, height: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(238, 243, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = creator
	return label
end

local title = makeLabel("自分だけの魔法を作成", 32, 24)
title.TextXAlignment = Enum.TextXAlignment.Center

local nameLabel = makeLabel("1. 魔法名（1〜20文字）", 22, 15)
local nameBox = Instance.new("TextBox")
nameBox.Name = "SpellName"
nameBox.Size = UDim2.new(1, 0, 0, 42)
nameBox.BackgroundColor3 = Color3.fromRGB(42, 47, 61)
nameBox.ClearTextOnFocus = false
nameBox.PlaceholderText = "例：ほしの一撃"
nameBox.Text = ""
nameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
nameBox.PlaceholderColor3 = Color3.fromRGB(151, 158, 178)
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 17
nameBox.Parent = creator

local nameCorner = Instance.new("UICorner")
nameCorner.CornerRadius = UDim.new(0, 8)
nameCorner.Parent = nameBox

makeLabel("2. 属性を選択", 22, 15)
local elementRow = Instance.new("Frame")
elementRow.Name = "ElementChoices"
elementRow.Size = UDim2.new(1, 0, 0, 54)
elementRow.BackgroundTransparency = 1
elementRow.Parent = creator

local elementLayout = Instance.new("UIListLayout")
elementLayout.FillDirection = Enum.FillDirection.Horizontal
elementLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
elementLayout.Padding = UDim.new(0, 8)
elementLayout.Parent = elementRow

makeLabel("3. 戦闘スタイルを選択", 22, 15)
local styleRow = Instance.new("Frame")
styleRow.Name = "StyleChoices"
styleRow.Size = UDim2.new(1, 0, 0, 62)
styleRow.BackgroundTransparency = 1
styleRow.Parent = creator

local styleLayout = Instance.new("UIListLayout")
styleLayout.FillDirection = Enum.FillDirection.Horizontal
styleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
styleLayout.Padding = UDim.new(0, 8)
styleLayout.Parent = styleRow

local preview = Instance.new("TextLabel")
preview.Name = "SpellPreview"
preview.Size = UDim2.new(1, 0, 0, 68)
preview.BackgroundColor3 = Color3.fromRGB(35, 39, 52)
preview.TextColor3 = Color3.fromRGB(230, 235, 249)
preview.Font = Enum.Font.Gotham
preview.TextSize = 14
preview.TextWrapped = true
preview.Parent = creator

local previewCorner = Instance.new("UICorner")
previewCorner.CornerRadius = UDim.new(0, 8)
previewCorner.Parent = preview

local createButton = Instance.new("TextButton")
createButton.Name = "CreateSpell"
createButton.Size = UDim2.new(1, 0, 0, 48)
createButton.BackgroundColor3 = Color3.fromRGB(113, 80, 255)
createButton.Text = "この魔法を作成"
createButton.TextColor3 = Color3.fromRGB(255, 255, 255)
createButton.Font = Enum.Font.GothamBold
createButton.TextSize = 18
createButton.Parent = creator

local createCorner = Instance.new("UICorner")
createCorner.CornerRadius = UDim.new(0, 9)
createCorner.Parent = createButton

local function makeChoiceButton(parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1 / 3, -6, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(48, 53, 68)
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = Color3.fromRGB(240, 244, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextWrapped = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

for _, elementId in SpellDefinitions.ElementOrder do
	local element = SpellDefinitions.Elements[elementId]
	local button = makeChoiceButton(elementRow, element.DisplayName)
	elementButtons[elementId] = button
	button.Activated:Connect(function()
		selectedElementId = elementId
		refreshChoiceButtons()
	end)
end

for _, styleId in SpellDefinitions.StyleOrder do
	local style = SpellDefinitions.Styles[styleId]
	local button = makeChoiceButton(styleRow, style.DisplayName)
	styleButtons[styleId] = button
	button.Activated:Connect(function()
		selectedStyleId = styleId
		refreshChoiceButtons()
	end)
end

refreshChoiceButtons = function()
	for elementId, button in elementButtons do
		local element = SpellDefinitions.Elements[elementId]
		button.BackgroundColor3 = if elementId == selectedElementId then element.Color else Color3.fromRGB(48, 53, 68)
	end
	for styleId, button in styleButtons do
		button.BackgroundColor3 = if styleId == selectedStyleId
			then Color3.fromRGB(113, 80, 255)
			else Color3.fromRGB(48, 53, 68)
	end

	local element = SpellDefinitions.Elements[selectedElementId]
	local style = SpellDefinitions.Styles[selectedStyleId]
	local spell = SpellDefinitions.BuildSpell(nameBox.Text, selectedElementId, selectedStyleId)
	if spell then
		preview.Text = string.format(
			"%s × %s\n%s／%s\nダメージ %d　クールダウン %.2f秒　射程 %d",
			element.DisplayName,
			style.DisplayName,
			element.Description,
			style.Description,
			spell.Damage,
			spell.Cooldown,
			spell.Range
		)
	end
end

nameBox:GetPropertyChangedSignal("Text"):Connect(refreshChoiceButtons)

local spellCard = Instance.new("TextLabel")
spellCard.Name = "CreatedSpell"
spellCard.AnchorPoint = Vector2.new(0.5, 1)
spellCard.Position = UDim2.new(0.5, 0, 1, -24)
spellCard.Size = UDim2.fromOffset(360, 70)
spellCard.BackgroundColor3 = Color3.fromRGB(24, 28, 39)
spellCard.BackgroundTransparency = 0.08
spellCard.TextColor3 = Color3.fromRGB(255, 255, 255)
spellCard.Font = Enum.Font.GothamBold
spellCard.TextSize = 17
spellCard.TextWrapped = true
spellCard.Parent = gui

local spellCardCorner = Instance.new("UICorner")
spellCardCorner.CornerRadius = UDim.new(0, 12)
spellCardCorner.Parent = spellCard

local castButton = Instance.new("TextButton")
castButton.Name = "CastButton"
castButton.AnchorPoint = Vector2.new(1, 1)
castButton.Position = UDim2.new(1, -24, 1, -112)
castButton.Size = UDim2.fromOffset(92, 92)
castButton.BackgroundColor3 = Color3.fromRGB(113, 80, 255)
castButton.Text = "発射"
castButton.TextColor3 = Color3.fromRGB(255, 255, 255)
castButton.Font = Enum.Font.GothamBold
castButton.TextSize = 22
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
crosshair.Parent = gui

local function getAimPosition(): Vector3
	local camera = workspace.CurrentCamera
	if UserInputService.TouchEnabled and camera then
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		return ray.Origin + ray.Direction * 300
	end
	return mouse.Hit.Position
end

local function tryCast()
	if player:GetAttribute("IsInBattle") ~= true or not currentSpell then
		return
	end

	local now = os.clock()
	if now - lastLocalCast < currentSpell.Cooldown then
		return
	end
	lastLocalCast = now
	castSpell:FireServer(getAimPosition())
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryCast()
	end
end)
castButton.Activated:Connect(tryCast)

local saving = false
createButton.Activated:Connect(function()
	if saving or player:GetAttribute("SpellDataLoaded") ~= true then
		return
	end

	saving = true
	createButton.Text = "作成中…"
	local invoked, result = pcall(function()
		return saveCustomSpell:InvokeServer(nameBox.Text, selectedElementId, selectedStyleId)
	end)

	if invoked and typeof(result) == "table" then
		message.Text = result.Message or "魔法を作成しました"
	else
		message.Text = "魔法を作成できませんでした。もう一度試してください"
	end
	saving = false
	createButton.Text = if player:GetAttribute("HasCustomSpell") then "この内容で保存し直す" else "この魔法を作成"
end)

systemMessage.OnClientEvent:Connect(function(text: string)
	message.Text = text
end)

local function refreshFromAttributes()
	local loaded = player:GetAttribute("SpellDataLoaded") == true
	local hasSpell = player:GetAttribute("HasCustomSpell") == true
	local inBattle = player:GetAttribute("IsInBattle") == true

	if hasSpell then
		local name = player:GetAttribute("CustomSpellName")
		local elementId = player:GetAttribute("CustomSpellElement")
		local styleId = player:GetAttribute("CustomSpellStyle")
		if typeof(name) == "string" and typeof(elementId) == "string" and typeof(styleId) == "string" then
			local spell = SpellDefinitions.BuildSpell(name, elementId, styleId)
			if spell then
				currentSpell = spell
				selectedElementId = elementId
				selectedStyleId = styleId
				if not nameBox:IsFocused() then
					nameBox.Text = name
				end
				local element = SpellDefinitions.Elements[elementId]
				local style = SpellDefinitions.Styles[styleId]
				spellCard.Text = string.format("「%s」\n%s × %s", name, element.DisplayName, style.DisplayName)
				castButton.BackgroundColor3 = spell.Color
			end
		end
	else
		currentSpell = nil
	end

	creator.Visible = loaded and not inBattle
	spellCard.Visible = inBattle and currentSpell ~= nil
	crosshair.Visible = inBattle and currentSpell ~= nil
	castButton.Visible = inBattle and currentSpell ~= nil and UserInputService.TouchEnabled
	createButton.Text = if hasSpell then "この内容で保存し直す" else "この魔法を作成"
	title.Text = if hasSpell then "作成済みの魔法を編集" else "自分だけの魔法を作成"

	if not loaded then
		message.Text = "魔法データを読み込んでいます…"
	elseif inBattle and currentSpell then
		message.Text = "「" .. currentSpell.Name .. "」でバトル中"
	elseif hasSpell and currentSpell then
		message.Text = "「" .. currentSpell.Name .. "」を使ってゲートへ入れます"
	else
		message.Text = "名前・属性・戦闘スタイルを選んで魔法を作成してください"
	end

	refreshChoiceButtons()
end

for _, attributeName in {
	"SpellDataLoaded",
	"HasCustomSpell",
	"CustomSpellName",
	"CustomSpellElement",
	"CustomSpellStyle",
	"IsInBattle",
} do
	player:GetAttributeChangedSignal(attributeName):Connect(refreshFromAttributes)
end

refreshChoiceButtons()
refreshFromAttributes()
