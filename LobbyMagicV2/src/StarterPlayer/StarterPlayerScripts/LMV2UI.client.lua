--!strict

-- ForgeUIZone内だけで表示される、交換可能な魔法設定UIです。
-- 各項目は選択肢を追加したとき、そのまま左右ボタンで循環できます。

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
}

local selection = SpellCatalog.CopyDefaultSelection()
local selectedSpell = SpellCatalog.Build(selection) or SpellCatalog.BuildExample()
local selectorValues: { [string]: TextLabel } = {}
local zoneCheckElapsed = 0
local inForgeZone = false
local updateSelectionDisplay: () -> ()

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
	button.TextSize = 16
	button.Parent = parent
	addCorner(button, 10)
	addStroke(button, COLORS.OrangeBright, 0.5, 1)
	return button
end

-- 工房設定パネル
local lobbyPanel = Instance.new("Frame")
lobbyPanel.Name = "LobbyPanel"
lobbyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
lobbyPanel.Position = UDim2.fromScale(0.5, 0.5)
lobbyPanel.Size = UDim2.fromOffset(600, 560)
lobbyPanel.BackgroundColor3 = COLORS.Panel
lobbyPanel.BorderSizePixel = 0
lobbyPanel.Visible = false
lobbyPanel.Parent = gui
addCorner(lobbyPanel, 18)
addStroke(lobbyPanel, COLORS.Orange, 0.35, 2)

local panelScale = Instance.new("UIScale")
panelScale.Name = "ResponsiveScale"
panelScale.Parent = lobbyPanel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 7)
accent.BackgroundColor3 = COLORS.Orange
accent.BorderSizePixel = 0
accent.Parent = lobbyPanel
addCorner(accent, 18)

local title = makeLabel(lobbyPanel, "Title", "🔥  MAGIC FORGE", UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, 18))
title.Font = Enum.Font.GothamBlack
title.TextColor3 = COLORS.OrangeBright
title.TextSize = 22

local subtitle = makeLabel(
	lobbyPanel,
	"Subtitle",
	"項目を選んで、現在の設定を魔法として保存します。",
	UDim2.new(1, -40, 0, 22),
	UDim2.fromOffset(20, 53)
)
subtitle.TextColor3 = COLORS.Muted
subtitle.TextSize = 13

local steps = makeLabel(
	lobbyPanel,
	"Steps",
	"1  設定     →     2  魔法作成     →     3  出撃",
	UDim2.new(1, -40, 0, 34),
	UDim2.fromOffset(20, 84)
)
steps.BackgroundTransparency = 0
steps.BackgroundColor3 = COLORS.Background
steps.TextXAlignment = Enum.TextXAlignment.Center
steps.Font = Enum.Font.GothamBold
steps.TextSize = 14
addCorner(steps, 10)

local selectorContainer = Instance.new("Frame")
selectorContainer.Name = "Selectors"
selectorContainer.Position = UDim2.fromOffset(20, 130)
selectorContainer.Size = UDim2.new(1, -40, 0, 228)
selectorContainer.BackgroundTransparency = 1
selectorContainer.Parent = lobbyPanel

local selectorLayout = Instance.new("UIListLayout")
selectorLayout.FillDirection = Enum.FillDirection.Vertical
selectorLayout.Padding = UDim.new(0, 6)
selectorLayout.SortOrder = Enum.SortOrder.LayoutOrder
selectorLayout.Parent = selectorContainer

local toast: TextLabel

local function showToast(message: string)
	toast.Text = message
	local version = (tonumber(toast:GetAttribute("Version")) or 0) + 1
	toast:SetAttribute("Version", version)
	TweenService:Create(toast, TweenInfo.new(0.16), {
		BackgroundTransparency = 0.08,
		TextTransparency = 0,
	}):Play()
	task.delay(2.5, function()
		if toast:GetAttribute("Version") ~= version then
			return
		end
		TweenService:Create(toast, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
	end)
end

local function cycleSelection(category: string, direction: number)
	local options = SpellCatalog.GetOptionIds(category)
	if #options == 0 then
		return
	end
	if #options == 1 then
		showToast(string.format("%sは現在1種類だけです。", SpellCatalog.CategoryDisplayNames[category]))
		return
	end

	local currentIndex = table.find(options, selection[category]) or 1
	local nextIndex = ((currentIndex - 1 + direction) % #options) + 1
	selection[category] = options[nextIndex]
	updateSelectionDisplay()
end

for order, category in ipairs(SpellCatalog.ComponentOrder) do
	local row = Instance.new("Frame")
	row.Name = category
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = COLORS.PanelLight
	row.BorderSizePixel = 0
	row.Parent = selectorContainer
	addCorner(row, 10)

	local categoryName = makeLabel(
		row,
		"Category",
		SpellCatalog.CategoryDisplayNames[category],
		UDim2.fromOffset(96, 40),
		UDim2.fromOffset(12, 0)
	)
	categoryName.Font = Enum.Font.GothamBold
	categoryName.TextColor3 = COLORS.Muted
	categoryName.TextSize = 13

	local previous = makeButton(row, "Previous", "‹")
	previous.Position = UDim2.fromOffset(110, 5)
	previous.Size = UDim2.fromOffset(34, 30)
	previous.TextSize = 22

	local value = makeLabel(row, "Value", "", UDim2.new(1, -198, 1, 0), UDim2.fromOffset(151, 0))
	value.Font = Enum.Font.GothamBold
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.TextSize = if category == "Attack" then 12 else 14
	value.TextWrapped = true
	selectorValues[category] = value

	local nextButton = makeButton(row, "Next", "›")
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.new(1, -8, 0, 5)
	nextButton.Size = UDim2.fromOffset(34, 30)
	nextButton.TextSize = 22

	previous.Activated:Connect(function()
		cycleSelection(category, -1)
	end)
	nextButton.Activated:Connect(function()
		cycleSelection(category, 1)
	end)
end

local spellSummary = Instance.new("Frame")
spellSummary.Name = "SpellSummary"
spellSummary.Position = UDim2.fromOffset(20, 370)
spellSummary.Size = UDim2.new(1, -40, 0, 82)
spellSummary.BackgroundColor3 = COLORS.Background
spellSummary.BorderSizePixel = 0
spellSummary.Parent = lobbyPanel
addCorner(spellSummary, 12)

local spellName = makeLabel(spellSummary, "SpellName", "", UDim2.new(0.45, -16, 0, 28), UDim2.fromOffset(14, 10))
spellName.Font = Enum.Font.GothamBlack
spellName.TextColor3 = COLORS.OrangeBright
spellName.TextSize = 19

local cost = makeLabel(spellSummary, "Cost", "", UDim2.new(0.55, -16, 0, 28), UDim2.new(0.45, 0, 0, 10))
cost.Font = Enum.Font.GothamBold
cost.TextColor3 = COLORS.OrangeBright
cost.TextXAlignment = Enum.TextXAlignment.Right
cost.TextSize = 13

local formula = makeLabel(spellSummary, "Formula", "", UDim2.new(1, -28, 0, 32), UDim2.fromOffset(14, 42))
formula.TextColor3 = COLORS.Muted
formula.TextSize = 11
formula.TextWrapped = true

local forgeButton = makeButton(lobbyPanel, "CreateSpellButton", "この設定で魔法を作る")
forgeButton.Position = UDim2.fromOffset(20, 466)
forgeButton.Size = UDim2.new(0.5, -26, 0, 48)

local enterButton = makeButton(lobbyPanel, "EnterGroundButton", "グラウンドへ出る")
enterButton.Position = UDim2.new(0.5, 6, 0, 466)
enterButton.Size = UDim2.new(0.5, -26, 0, 48)

local lobbyHint = makeLabel(
	lobbyPanel,
	"Hint",
	"このUIは ForgeUIZone の中にいる間だけ表示されます。",
	UDim2.new(1, -40, 0, 26),
	UDim2.fromOffset(20, 523)
)
lobbyHint.TextColor3 = COLORS.Muted
lobbyHint.TextXAlignment = Enum.TextXAlignment.Center
lobbyHint.TextSize = 12

-- グラウンド用HUD
local hud = Instance.new("Frame")
hud.Name = "BattleHUD"
hud.Position = UDim2.fromOffset(18, 18)
hud.Size = UDim2.fromOffset(330, 126)
hud.BackgroundColor3 = COLORS.Panel
hud.BackgroundTransparency = 0.08
hud.BorderSizePixel = 0
hud.Visible = false
hud.Parent = gui
addCorner(hud, 15)
addStroke(hud, COLORS.Orange, 0.4, 1)

local hudTitle =
	makeLabel(hud, "SpellName", "🔥 ファイアボム", UDim2.new(1, -24, 0, 27), UDim2.fromOffset(14, 11))
hudTitle.Font = Enum.Font.GothamBold
hudTitle.TextColor3 = COLORS.OrangeBright
hudTitle.TextSize = 18

local manaText = makeLabel(hud, "ManaText", "MANA 100 / 100", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 43))
manaText.Font = Enum.Font.GothamBold
manaText.TextSize = 13

local manaBack = Instance.new("Frame")
manaBack.Name = "ManaBack"
manaBack.Position = UDim2.fromOffset(14, 67)
manaBack.Size = UDim2.new(1, -28, 0, 13)
manaBack.BackgroundColor3 = COLORS.Background
manaBack.BorderSizePixel = 0
manaBack.Parent = hud
addCorner(manaBack, 7)

local manaFill = Instance.new("Frame")
manaFill.Name = "ManaFill"
manaFill.Size = UDim2.fromScale(1, 1)
manaFill.BackgroundColor3 = COLORS.Mana
manaFill.BorderSizePixel = 0
manaFill.Parent = manaBack
addCorner(manaFill, 7)

local castStatus = makeLabel(
	hud,
	"CastStatus",
	"発動可能  |  左クリック / F / R2 / FIRE",
	UDim2.new(1, -28, 0, 27),
	UDim2.fromOffset(14, 87)
)
castStatus.Font = Enum.Font.GothamBold
castStatus.TextColor3 = COLORS.Green
castStatus.TextSize = 12

local returnHint =
	makeLabel(hud, "ReturnHint", "ReturnGateでロビーへ", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 106))
returnHint.TextColor3 = COLORS.Muted
returnHint.TextSize = 11

toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -36)
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
toast.Parent = gui
addCorner(toast, 12)
local toastConstraint = Instance.new("UISizeConstraint")
toastConstraint.MaxSize = Vector2.new(560, 48)
toastConstraint.Parent = toast

local function hasSpell(): boolean
	return player:GetAttribute(Config.HasSpellAttribute) == true
end

updateSelectionDisplay = function()
	selectedSpell = SpellCatalog.Build(selection) or selectedSpell
	for _, category in ipairs(SpellCatalog.ComponentOrder) do
		local component = SpellCatalog.GetComponent(category, selection[category])
		local value = selectorValues[category]
		if component and value then
			value.Text = component.DisplayName
		end
	end

	spellName.Text = selectedSpell.DisplayName
	cost.Text = string.format(
		"ダメージ %d   マナ %d   CD %.1f秒",
		selectedSpell.Damage,
		selectedSpell.ManaCost,
		selectedSpell.Cooldown
	)
	local manaParts = {}
	local cooldownParts = {}
	for _, item in ipairs(selectedSpell.CostBreakdown) do
		table.insert(manaParts, tostring(item.Mana))
		table.insert(cooldownParts, string.format("%.1f", item.Cooldown))
	end
	formula.Text = string.format(
		"マナ %s = %d   /   CD %s = %.1f",
		table.concat(manaParts, "+"),
		selectedSpell.ManaCost,
		table.concat(cooldownParts, "+"),
		selectedSpell.Cooldown
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
	lobbyPanel.Visible = not inGround and inForgeZone
	hud.Visible = inGround

	local ready = hasSpell()
	forgeButton.Text = if ready then "設定を保存し直す" else "この設定で魔法を作る"
	forgeButton.BackgroundColor3 = if ready then COLORS.Green else COLORS.Orange
	enterButton.Active = ready
	enterButton.AutoButtonColor = ready
	enterButton.BackgroundColor3 = if ready then COLORS.Orange else COLORS.Disabled
	enterButton.TextTransparency = if ready then 0 else 0.25
end

forgeButton.Activated:Connect(function()
	lobbyActionRequest:FireServer({
		Action = "CreateSpell",
		Selection = table.clone(selection),
	})
end)

enterButton.Activated:Connect(function()
	if hasSpell() then
		lobbyActionRequest:FireServer("EnterGround")
	else
		showToast("先に現在の設定で魔法を作ってください。")
	end
end)

player:GetAttributeChangedSignal(Config.StateAttribute):Connect(updateMode)
player:GetAttributeChangedSignal(Config.HasSpellAttribute):Connect(updateMode)

stateChanged.OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) == "table" then
		loadSelection(snapshot.Selection)
	end
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
		panelScale.Scale = math.min(1, camera.ViewportSize.X / 640, camera.ViewportSize.Y / 600)
	end

	if not hud.Visible then
		return
	end
	local mana = tonumber(player:GetAttribute(Config.ManaAttribute)) or 0
	local maximum = tonumber(player:GetAttribute(Config.MaxManaAttribute)) or Config.Mana.Maximum
	local ratio = if maximum > 0 then math.clamp(mana / maximum, 0, 1) else 0
	manaFill.Size = UDim2.fromScale(ratio, 1)
	manaText.Text = string.format("MANA %d / %d", math.floor(mana + 0.5), math.floor(maximum + 0.5))

	local cooldownEnd = tonumber(player:GetAttribute(Config.CooldownEndAttribute)) or 0
	local remaining = math.max(0, cooldownEnd - Workspace:GetServerTimeNow())
	if remaining > 0 then
		castStatus.Text = string.format("クールダウン  %.1f秒", remaining)
		castStatus.TextColor3 = COLORS.OrangeBright
	elseif mana + 1e-4 < selectedSpell.ManaCost then
		castStatus.Text = string.format("マナ回復中  |  必要 %d", selectedSpell.ManaCost)
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
	if ok and typeof(result) == "table" then
		loadSelection(result.Selection)
	end
	updateMode()
end)

updateSelectionDisplay()
updateMode()
