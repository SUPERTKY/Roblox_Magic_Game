--!strict

-- ForgeUIZone内の魔法工房と、戦闘中の5スロット・HUDを生成します。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local systemRoot = ReplicatedStorage:WaitForChild("LobbyMagicV2")
local shared = systemRoot:WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))
if not Config.EnableGeneratedUI then
	return
end

local SpellCatalog = require(shared:WaitForChild("LMV2SpellCatalog"))
local remotes = systemRoot:WaitForChild("Remotes")
local lobbyActionRequest = remotes:WaitForChild("LobbyActionRequest") :: RemoteEvent
local stateChanged = remotes:WaitForChild("StateChanged") :: RemoteEvent
local feedback = remotes:WaitForChild("Feedback") :: RemoteEvent
local getSnapshot = remotes:WaitForChild("GetSnapshot") :: RemoteFunction

local COLORS = {
	Background = Color3.fromRGB(18, 17, 24),
	Panel = Color3.fromRGB(31, 28, 39),
	PanelLight = Color3.fromRGB(45, 39, 49),
	Orange = Color3.fromRGB(255, 117, 45),
	OrangeBright = Color3.fromRGB(255, 171, 75),
	Cream = Color3.fromRGB(255, 239, 207),
	Muted = Color3.fromRGB(188, 177, 184),
	Green = Color3.fromRGB(93, 216, 148),
	Disabled = Color3.fromRGB(78, 72, 80),
	Mana = Color3.fromRGB(74, 168, 255),
	Red = Color3.fromRGB(210, 72, 72),
}

local selection = SpellCatalog.CopyDefaultSelection()
local selectedSpell = SpellCatalog.Build(selection) or SpellCatalog.BuildExample()
local inventory: { any } = {}
local activeSlot = 0
local selectedInventorySlot = 0
local deleteConfirmSlot = 0
local deleteConfirmVersion = 0
local dataReady = false
local inForgeZone = false
local zoneCheckElapsed = 0
local selectorValues: { [string]: TextLabel } = {}
local selectorRows: { [string]: Frame } = {}
local inventoryButtons: { TextButton } = {}
local hotbarButtons: { TextButton } = {}

local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("LMV2_UI")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "LMV2_UI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, transparency: number?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = COLORS.Cream
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = COLORS.Orange
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = COLORS.Cream
	button.TextSize = 14
	button.Parent = parent
	addCorner(button, 9)
	addStroke(button, COLORS.OrangeBright, 0.55, 1)
	return button
end

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -24)
toast.Size = UDim2.new(0.88, 0, 0, 48)
toast.BackgroundColor3 = COLORS.Background
toast.BackgroundTransparency = 1
toast.BorderSizePixel = 0
toast.Font = Enum.Font.GothamBold
toast.Text = ""
toast.TextColor3 = COLORS.Cream
toast.TextSize = 14
toast.TextTransparency = 1
toast.TextWrapped = true
toast.ZIndex = 30
toast.Parent = gui
addCorner(toast, 12)

local function showToast(message: string)
	toast.Text = message
	local version = (tonumber(toast:GetAttribute("Version")) or 0) + 1
	toast:SetAttribute("Version", version)
	TweenService:Create(toast, TweenInfo.new(0.16), {
		BackgroundTransparency = 0.08,
		TextTransparency = 0,
	}):Play()
	task.delay(2.6, function()
		if toast:GetAttribute("Version") ~= version then
			return
		end
		TweenService:Create(toast, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
	end)
end

-- 魔法工房
local forgePanel = Instance.new("Frame")
forgePanel.Name = "ForgePanel"
forgePanel.AnchorPoint = Vector2.new(0.5, 0.5)
forgePanel.Position = UDim2.fromScale(0.5, 0.5)
forgePanel.Size = UDim2.fromOffset(660, 690)
forgePanel.BackgroundColor3 = COLORS.Panel
forgePanel.BorderSizePixel = 0
forgePanel.Visible = false
forgePanel.Parent = gui
addCorner(forgePanel, 18)
addStroke(forgePanel, COLORS.Orange, 0.35, 2)

local panelScale = Instance.new("UIScale")
panelScale.Parent = forgePanel

local accent = Instance.new("Frame")
accent.Size = UDim2.new(1, 0, 0, 7)
accent.BackgroundColor3 = COLORS.Orange
accent.BorderSizePixel = 0
accent.Parent = forgePanel
addCorner(accent, 18)

local title = makeLabel(forgePanel, "Title", "🔥  MAGIC FORGE", UDim2.new(1, -40, 0, 32), UDim2.fromOffset(20, 16))
title.Font = Enum.Font.GothamBlack
title.TextColor3 = COLORS.OrangeBright
title.TextSize = 22

local subtitle = makeLabel(
	forgePanel,
	"Subtitle",
	"名前と設定を決めて保存。最大5個まで持てます。",
	UDim2.new(1, -40, 0, 22),
	UDim2.fromOffset(20, 49)
)
subtitle.TextColor3 = COLORS.Muted
subtitle.TextSize = 13

local slotsFrame = Instance.new("Frame")
slotsFrame.Name = "SavedSpells"
slotsFrame.Position = UDim2.fromOffset(20, 78)
slotsFrame.Size = UDim2.new(1, -40, 0, 54)
slotsFrame.BackgroundTransparency = 1
slotsFrame.Parent = forgePanel

for slot = 1, Config.Inventory.MaximumSpells do
	local button = makeButton(slotsFrame, string.format("Slot%d", slot), string.format("%d\n空き", slot))
	button.Position = UDim2.new((slot - 1) / Config.Inventory.MaximumSpells, 4, 0, 0)
	button.Size = UDim2.new(1 / Config.Inventory.MaximumSpells, -8, 1, 0)
	button.TextSize = 11
	button.TextWrapped = true
	inventoryButtons[slot] = button
	button.Activated:Connect(function()
		if inventory[slot] then
			selectedInventorySlot = slot
			lobbyActionRequest:FireServer({ Action = "EquipSpell", Slot = slot })
		end
	end)
end

local nameLabel = makeLabel(forgePanel, "NameLabel", "魔法名", UDim2.fromOffset(72, 38), UDim2.fromOffset(20, 142))
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextColor3 = COLORS.Muted
nameLabel.TextSize = 13

local nameBox = Instance.new("TextBox")
nameBox.Name = "SpellNameInput"
nameBox.Position = UDim2.fromOffset(92, 142)
nameBox.Size = UDim2.new(1, -292, 0, 38)
nameBox.BackgroundColor3 = COLORS.Background
nameBox.BorderSizePixel = 0
nameBox.ClearTextOnFocus = false
nameBox.Font = Enum.Font.GothamBold
nameBox.PlaceholderText = "1〜20文字で魔法名を入力"
nameBox.PlaceholderColor3 = COLORS.Muted
nameBox.Text = ""
nameBox.TextColor3 = COLORS.Cream
nameBox.TextSize = 14
nameBox.TextXAlignment = Enum.TextXAlignment.Left
nameBox.Parent = forgePanel
addCorner(nameBox, 9)

local deleteButton = makeButton(forgePanel, "DeleteSpellButton", "選択中を削除")
deleteButton.Position = UDim2.new(1, -190, 0, 142)
deleteButton.Size = UDim2.fromOffset(170, 38)
deleteButton.BackgroundColor3 = COLORS.Red

local selectorTabs = Instance.new("Frame")
selectorTabs.Name = "SelectorTabs"
selectorTabs.Position = UDim2.fromOffset(20, 190)
selectorTabs.Size = UDim2.new(1, -40, 0, 32)
selectorTabs.BackgroundTransparency = 1
selectorTabs.Parent = forgePanel

local selectorContainer = Instance.new("ScrollingFrame")
selectorContainer.Name = "Selectors"
selectorContainer.Position = UDim2.fromOffset(20, 228)
selectorContainer.Size = UDim2.new(1, -40, 0, 250)
selectorContainer.BackgroundTransparency = 1
selectorContainer.BorderSizePixel = 0
selectorContainer.ScrollBarThickness = 6
selectorContainer.ScrollBarImageColor3 = COLORS.Orange
selectorContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
selectorContainer.CanvasSize = UDim2.new()
selectorContainer.Parent = forgePanel

local selectorLayout = Instance.new("UIListLayout")
selectorLayout.FillDirection = Enum.FillDirection.Vertical
selectorLayout.Padding = UDim.new(0, 4)
selectorLayout.SortOrder = Enum.SortOrder.LayoutOrder
selectorLayout.Parent = selectorContainer

local updateSelectionDisplay: () -> ()

local function cycleSelection(category: string, direction: number)
	local options = SpellCatalog.GetOptionIds(category)
	if #options <= 1 then
		showToast(string.format("%sは現在1種類だけです。", SpellCatalog.CategoryDisplayNames[category]))
		return
	end
	local currentIndex = table.find(options, selection[category]) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	local previousId = selection[category]
	selection[category] = options[nextIndex]
	if not SpellCatalog.Build(selection) then
		selection[category] = previousId
		showToast("魔力上限を超える組み合わせです。別の設定を下げてください。")
		return
	end
	updateSelectionDisplay()
end

for order, category in ipairs(SpellCatalog.ComponentOrder) do
	local row = Instance.new("Frame")
	row.Name = category
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = COLORS.PanelLight
	row.BorderSizePixel = 0
	row.Parent = selectorContainer
	selectorRows[category] = row
	addCorner(row, 8)

	local categoryName = makeLabel(
		row,
		"Category",
		SpellCatalog.CategoryDisplayNames[category],
		UDim2.fromOffset(100, 32),
		UDim2.fromOffset(10, 0)
	)
	categoryName.Font = Enum.Font.GothamBold
	categoryName.TextColor3 = COLORS.Muted
	categoryName.TextSize = 12

	local previous = makeButton(row, "Previous", "‹")
	previous.Position = UDim2.fromOffset(112, 3)
	previous.Size = UDim2.fromOffset(30, 26)
	previous.TextSize = 19

	local value = makeLabel(row, "Value", "", UDim2.new(1, -190, 1, 0), UDim2.fromOffset(150, 0))
	value.Font = Enum.Font.GothamBold
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.TextSize = 12
	value.TextWrapped = true
	selectorValues[category] = value

	local nextButton = makeButton(row, "Next", "›")
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.new(1, -8, 0, 3)
	nextButton.Size = UDim2.fromOffset(30, 26)
	nextButton.TextSize = 19

	previous.Activated:Connect(function()
		cycleSelection(category, -1)
	end)
	nextButton.Activated:Connect(function()
		cycleSelection(category, 1)
	end)
end

local activeSelectorGroup = "Basic"
local tabButtons: { [string]: TextButton } = {}
local groupOrder = { "Basic", "Advanced", "Appearance" }
local groupNames: { [string]: string } = { Basic = "基本設定", Advanced = "詳細設定", Appearance = "見た目" }

local function showSelectorGroup(groupName: string)
	activeSelectorGroup = groupName
	local visibleCategories: { [string]: boolean } = {}
	for _, category in ipairs(SpellCatalog.ComponentGroups[groupName]) do
		visibleCategories[category] = true
	end
	for category, row in pairs(selectorRows) do
		row.Visible = visibleCategories[category] == true
	end
	selectorContainer.CanvasPosition = Vector2.zero
	for name, button in pairs(tabButtons) do
		button.BackgroundColor3 = if name == groupName then COLORS.Orange else COLORS.PanelLight
	end
end

for index, groupName in ipairs(groupOrder) do
	local button = makeButton(selectorTabs, groupName, groupNames[groupName])
	button.Position = UDim2.new((index - 1) / #groupOrder, 3, 0, 0)
	button.Size = UDim2.new(1 / #groupOrder, -6, 1, 0)
	button.TextSize = 12
	tabButtons[groupName] = button
	button.Activated:Connect(function()
		showSelectorGroup(groupName)
	end)
end

showSelectorGroup(activeSelectorGroup)

local spellSummary = Instance.new("Frame")
spellSummary.Position = UDim2.fromOffset(20, 490)
spellSummary.Size = UDim2.new(1, -40, 0, 82)
spellSummary.BackgroundColor3 = COLORS.Background
spellSummary.BorderSizePixel = 0
spellSummary.Parent = forgePanel
addCorner(spellSummary, 12)

local previewName = makeLabel(spellSummary, "PreviewName", "", UDim2.new(0.42, -12, 0, 26), UDim2.fromOffset(14, 8))
previewName.Font = Enum.Font.GothamBlack
previewName.TextColor3 = COLORS.OrangeBright
previewName.TextSize = 17

local stats = makeLabel(spellSummary, "Stats", "", UDim2.new(0.58, -16, 0, 26), UDim2.new(0.42, 0, 0, 8))
stats.Font = Enum.Font.GothamBold
stats.TextColor3 = COLORS.OrangeBright
stats.TextXAlignment = Enum.TextXAlignment.Right
stats.TextSize = 12

local details = makeLabel(spellSummary, "Details", "", UDim2.new(1, -28, 0, 39), UDim2.fromOffset(14, 38))
details.TextColor3 = COLORS.Muted
details.TextSize = 11
details.TextWrapped = true

local createButton = makeButton(forgePanel, "CreateSpellButton", "新しい魔法として保存")
createButton.Position = UDim2.fromOffset(20, 586)
createButton.Size = UDim2.new(0.5, -26, 0, 46)

local enterButton = makeButton(forgePanel, "EnterGroundButton", "グラウンドへ出る")
enterButton.Position = UDim2.new(0.5, 6, 0, 586)
enterButton.Size = UDim2.new(0.5, -26, 0, 46)

local forgeHint = makeLabel(
	forgePanel,
	"Hint",
	"スロットを選ぶと装備、削除は工房内だけ。戦闘中は1〜5キーでも切替できます。",
	UDim2.new(1, -40, 0, 28),
	UDim2.fromOffset(20, 646)
)
forgeHint.TextColor3 = COLORS.Muted
forgeHint.TextXAlignment = Enum.TextXAlignment.Center
forgeHint.TextSize = 11

-- 戦闘HUD
local hud = Instance.new("Frame")
hud.Name = "BattleHUD"
hud.Position = UDim2.fromOffset(18, 18)
hud.Size = UDim2.fromOffset(345, 126)
hud.BackgroundColor3 = COLORS.Panel
hud.BackgroundTransparency = 0.08
hud.BorderSizePixel = 0
hud.Visible = false
hud.Parent = gui
addCorner(hud, 15)
addStroke(hud, COLORS.Orange, 0.4, 1)

local hudTitle = makeLabel(hud, "SpellName", "魔法未装備", UDim2.new(1, -24, 0, 27), UDim2.fromOffset(14, 11))
hudTitle.Font = Enum.Font.GothamBold
hudTitle.TextColor3 = COLORS.OrangeBright
hudTitle.TextSize = 18

local manaText = makeLabel(hud, "ManaText", "MANA 100 / 100", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 43))
manaText.Font = Enum.Font.GothamBold
manaText.TextSize = 13

local manaBack = Instance.new("Frame")
manaBack.Position = UDim2.fromOffset(14, 67)
manaBack.Size = UDim2.new(1, -28, 0, 13)
manaBack.BackgroundColor3 = COLORS.Background
manaBack.BorderSizePixel = 0
manaBack.Parent = hud
addCorner(manaBack, 7)

local manaFill = Instance.new("Frame")
manaFill.Size = UDim2.fromScale(1, 1)
manaFill.BackgroundColor3 = COLORS.Mana
manaFill.BorderSizePixel = 0
manaFill.Parent = manaBack
addCorner(manaFill, 7)

local castStatus = makeLabel(hud, "CastStatus", "", UDim2.new(1, -28, 0, 27), UDim2.fromOffset(14, 87))
castStatus.Font = Enum.Font.GothamBold
castStatus.TextColor3 = COLORS.Green
castStatus.TextSize = 12

local returnHint =
	makeLabel(hud, "ReturnHint", "ReturnGateでロビーへ", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 106))
returnHint.TextColor3 = COLORS.Muted
returnHint.TextSize = 11

local hotbar = Instance.new("Frame")
hotbar.Name = "SpellHotbar"
hotbar.AnchorPoint = Vector2.new(0.5, 1)
hotbar.Position = UDim2.new(0.5, 0, 1, -24)
hotbar.Size = UDim2.fromOffset(590, 58)
hotbar.BackgroundColor3 = COLORS.Panel
hotbar.BackgroundTransparency = 0.08
hotbar.BorderSizePixel = 0
hotbar.Visible = false
hotbar.Parent = gui
addCorner(hotbar, 13)
addStroke(hotbar, COLORS.Orange, 0.45, 1)

for slot = 1, Config.Inventory.MaximumSpells do
	local button = makeButton(hotbar, string.format("Hotbar%d", slot), tostring(slot))
	button.Position = UDim2.new((slot - 1) / Config.Inventory.MaximumSpells, 5, 0, 5)
	button.Size = UDim2.new(1 / Config.Inventory.MaximumSpells, -10, 1, -10)
	button.TextSize = 11
	button.TextWrapped = true
	hotbarButtons[slot] = button
	button.Activated:Connect(function()
		lobbyActionRequest:FireServer({ Action = "EquipSpell", Slot = slot })
	end)
end

local function getSpellAt(slot: number): any?
	return inventory[slot]
end

local function updateInventoryDisplay()
	for slot = 1, Config.Inventory.MaximumSpells do
		local stored = getSpellAt(slot)
		local name = if stored and typeof(stored.Name) == "string" then stored.Name else "空き"
		local selected = slot == activeSlot
		local forgeButton = inventoryButtons[slot]
		forgeButton.Text = string.format("%d\n%s", slot, name)
		forgeButton.BackgroundColor3 = if selected
			then COLORS.Green
			else if stored then COLORS.PanelLight else COLORS.Disabled

		local hotbarButton = hotbarButtons[slot]
		hotbarButton.Text = string.format("%d  %s", slot, name)
		hotbarButton.BackgroundColor3 = if selected
			then COLORS.Green
			else if stored then COLORS.PanelLight else COLORS.Disabled
		hotbarButton.Active = stored ~= nil
		hotbarButton.AutoButtonColor = stored ~= nil
	end

	local selectedStored = getSpellAt(selectedInventorySlot)
	deleteButton.Active = selectedStored ~= nil
	deleteButton.AutoButtonColor = selectedStored ~= nil
	deleteButton.BackgroundColor3 = if selectedStored then COLORS.Red else COLORS.Disabled
	deleteButton.Text = if selectedStored
		then string.format("%d番を削除", selectedInventorySlot)
		else "削除する魔法を選択"

	local active = getSpellAt(activeSlot)
	hudTitle.Text = if active then string.format("%d  %s", activeSlot, active.Name) else "魔法未装備"
end

updateSelectionDisplay = function()
	local built = SpellCatalog.Build(selection)
	if built then
		selectedSpell = built
	else
		showToast("この組み合わせは魔力上限を超えています。")
		return
	end
	for _, category in ipairs(SpellCatalog.ComponentOrder) do
		local component = SpellCatalog.GetComponent(category, selection[category])
		local value = selectorValues[category]
		if component and value then
			value.Text = component.DisplayName
		end
	end

	local typedName = SpellCatalog.NormalizeName(nameBox.Text)
	previewName.Text = typedName or selectedSpell.GeneratedName
	stats.Text = string.format(
		"%d球 × %dダメージ（最大%d）  マナ%d  CD %.1f秒",
		selectedSpell.ProjectileCount,
		selectedSpell.Damage,
		selectedSpell.TotalDamage,
		selectedSpell.ManaCost,
		selectedSpell.Cooldown
	)
	details.Text = string.format(
		"速度 %.0f / 射程 %d / 範囲 %d / %s / %s",
		selectedSpell.ProjectileSpeed,
		selectedSpell.MaxDistance,
		selectedSpell.ExplosionRadius,
		selectedSpell.Delivery,
		selectedSpell.ControlEffect
	)
end

local function loadSelection(source: any)
	if typeof(source) ~= "table" then
		return
	end
	local candidate: { [string]: string } = {}
	for _, category in ipairs(SpellCatalog.ComponentOrder) do
		candidate[category] = source[category]
	end
	if SpellCatalog.Build(candidate) then
		selection = candidate
		updateSelectionDisplay()
	end
end

local function applySnapshot(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	inventory = if typeof(snapshot.Spells) == "table" then snapshot.Spells else {}
	activeSlot = if typeof(snapshot.ActiveSlot) == "number" then math.floor(snapshot.ActiveSlot) else 0
	dataReady = snapshot.DataReady == true
	if selectedInventorySlot == 0 or not inventory[selectedInventorySlot] then
		selectedInventorySlot = activeSlot
	end
	if snapshot.Spell and snapshot.Selection then
		loadSelection(snapshot.Selection)
	end
	updateInventoryDisplay()
end

local function findForgeZone(): BasePart?
	local world = Workspace:FindFirstChild(Config.World.FolderName)
	local zone = if world then world:FindFirstChild(Config.World.ForgeUIZoneName) else nil
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function playerIsInsideForgeZone(): boolean
	if player:GetAttribute(Config.StateAttribute) ~= "Lobby" then
		return false
	end
	local zone = findForgeZone()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not zone or not root or not root:IsA("BasePart") then
		return false
	end
	local localPosition = zone.CFrame:PointToObjectSpace(root.Position)
	local halfSize = zone.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function updateMode()
	local inGround = player:GetAttribute(Config.StateAttribute) == "Ground"
	forgePanel.Visible = not inGround and inForgeZone
	hud.Visible = inGround
	hotbar.Visible = inGround
	toast.Position = if inGround then UDim2.new(0.5, 0, 1, -92) else UDim2.new(0.5, 0, 1, -24)

	local full = #inventory >= Config.Inventory.MaximumSpells
	createButton.Active = dataReady and not full
	createButton.AutoButtonColor = dataReady and not full
	createButton.BackgroundColor3 = if dataReady and not full then COLORS.Orange else COLORS.Disabled
	createButton.Text = if not dataReady
		then "データ準備中"
		else if full
			then "5個保存済み"
			else string.format("新しい魔法として保存（%d/5）", #inventory)

	local hasSpell = #inventory > 0
	enterButton.Active = hasSpell
	enterButton.AutoButtonColor = hasSpell
	enterButton.BackgroundColor3 = if hasSpell then COLORS.Orange else COLORS.Disabled
end

nameBox:GetPropertyChangedSignal("Text"):Connect(updateSelectionDisplay)

createButton.Activated:Connect(function()
	lobbyActionRequest:FireServer({
		Action = "CreateSpell",
		Name = nameBox.Text,
		Selection = table.clone(selection),
	})
end)

deleteButton.Activated:Connect(function()
	local slot = selectedInventorySlot
	if slot <= 0 or not inventory[slot] then
		return
	end
	if deleteConfirmSlot == slot then
		deleteConfirmSlot = 0
		deleteConfirmVersion += 1
		lobbyActionRequest:FireServer({ Action = "DeleteSpell", Slot = slot })
		return
	end

	deleteConfirmSlot = slot
	deleteConfirmVersion += 1
	local version = deleteConfirmVersion
	deleteButton.Text = "もう一度押して削除"
	showToast("削除する場合は3秒以内にもう一度押してください。")
	task.delay(3, function()
		if deleteConfirmVersion == version then
			deleteConfirmSlot = 0
			updateInventoryDisplay()
		end
	end)
end)

enterButton.Activated:Connect(function()
	if #inventory > 0 then
		lobbyActionRequest:FireServer("EnterGround")
	else
		showToast("先に魔法を1個作ってください。")
	end
end)

player:GetAttributeChangedSignal(Config.StateAttribute):Connect(updateMode)

stateChanged.OnClientEvent:Connect(function(snapshot: any)
	applySnapshot(snapshot)
	updateMode()
end)

feedback.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" and typeof(payload.Message) == "string" then
		showToast(payload.Message)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime: number)
	zoneCheckElapsed += deltaTime
	if zoneCheckElapsed >= 0.1 then
		zoneCheckElapsed = 0
		local nextInside = playerIsInsideForgeZone()
		if nextInside ~= inForgeZone then
			inForgeZone = nextInside
			updateMode()
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		panelScale.Scale = math.min(1, camera.ViewportSize.X / 700, camera.ViewportSize.Y / 730)
	end

	if not hud.Visible then
		return
	end
	local mana = tonumber(player:GetAttribute(Config.ManaAttribute)) or 0
	local maximum = tonumber(player:GetAttribute(Config.MaxManaAttribute)) or Config.Mana.Maximum
	local ratio = if maximum > 0 then math.clamp(mana / maximum, 0, 1) else 0
	manaFill.Size = UDim2.fromScale(ratio, 1)
	manaText.Text = string.format("MANA %d / %d", math.floor(mana + 0.5), math.floor(maximum + 0.5))

	local active = getSpellAt(activeSlot)
	local manaCost = if active and typeof(active.ManaCost) == "number" then active.ManaCost else math.huge
	local cooldownEnd = tonumber(player:GetAttribute(Config.CooldownEndAttribute)) or 0
	local remaining = math.max(0, cooldownEnd - Workspace:GetServerTimeNow())
	if not active then
		castStatus.Text = "魔法を装備してください"
		castStatus.TextColor3 = COLORS.Muted
	elseif remaining > 0 then
		castStatus.Text = string.format("クールダウン  %.1f秒", remaining)
		castStatus.TextColor3 = COLORS.OrangeBright
	elseif mana + 1e-4 < manaCost then
		castStatus.Text = string.format("マナ回復中  |  必要 %d", manaCost)
		castStatus.TextColor3 = COLORS.Mana
	else
		castStatus.Text = "発動可能  |  左クリック / F / R2 / FIRE"
		castStatus.TextColor3 = COLORS.Green
	end
end)

task.spawn(function()
	local ok, result = pcall(function()
		return getSnapshot:InvokeServer()
	end)
	if ok then
		applySnapshot(result)
	end
	updateMode()
end)

updateSelectionDisplay()
updateInventoryDisplay()
updateMode()
