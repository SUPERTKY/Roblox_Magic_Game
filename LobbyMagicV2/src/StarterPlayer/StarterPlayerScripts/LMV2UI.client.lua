--!strict

-- StudioでScreenGuiを手作業しなくても使える、交換可能なUIです。
-- このLocalScriptを外しても、サーバー・ProximityPrompt・LMV2Clientは動き続けます。

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

local spell = SpellCatalog.BuildExample()
local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("LMV2_UI")
if oldGui then
	oldGui:Destroy()
end

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
	button.TextSize = 17
	button.Parent = parent
	addCorner(button, 12)
	addStroke(button, COLORS.OrangeBright, 0.45, 1)
	return button
end

-- ロビー用の魔法工房パネル
local lobbyPanel = Instance.new("Frame")
lobbyPanel.Name = "LobbyPanel"
lobbyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
lobbyPanel.Position = UDim2.fromScale(0.5, 0.52)
lobbyPanel.Size = UDim2.new(0.92, 0, 0, 430)
lobbyPanel.BackgroundColor3 = COLORS.Panel
lobbyPanel.BorderSizePixel = 0
lobbyPanel.Parent = gui
addCorner(lobbyPanel, 18)
addStroke(lobbyPanel, COLORS.Orange, 0.35, 2)

local lobbyConstraint = Instance.new("UISizeConstraint")
lobbyConstraint.MinSize = Vector2.new(300, 390)
lobbyConstraint.MaxSize = Vector2.new(580, 430)
lobbyConstraint.Parent = lobbyPanel

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Size = UDim2.new(1, 0, 0, 7)
accent.BackgroundColor3 = COLORS.Orange
accent.BorderSizePixel = 0
accent.Parent = lobbyPanel
addCorner(accent, 18)

local title =
	makeLabel(lobbyPanel, "Title", "🔥  LOBBY MAGIC FORGE V2", UDim2.new(1, -40, 0, 36), UDim2.fromOffset(20, 20))
title.Font = Enum.Font.GothamBlack
title.TextColor3 = COLORS.OrangeBright
title.TextSize = 22

local subtitle = makeLabel(
	lobbyPanel,
	"Subtitle",
	"組み合わせて、試して、グラウンドへ。",
	UDim2.new(1, -40, 0, 24),
	UDim2.fromOffset(20, 56)
)
subtitle.TextColor3 = COLORS.Muted
subtitle.TextSize = 14

local steps = makeLabel(
	lobbyPanel,
	"Steps",
	"1  魔法作成     →     2  出撃     →     3  バトル",
	UDim2.new(1, -40, 0, 34),
	UDim2.fromOffset(20, 91)
)
steps.BackgroundTransparency = 0
steps.BackgroundColor3 = COLORS.Background
steps.TextColor3 = COLORS.Cream
steps.TextXAlignment = Enum.TextXAlignment.Center
steps.Font = Enum.Font.GothamBold
steps.TextSize = 14
addCorner(steps, 10)

local spellCard = Instance.new("Frame")
spellCard.Name = "SpellCard"
spellCard.Position = UDim2.fromOffset(20, 139)
spellCard.Size = UDim2.new(1, -40, 0, 154)
spellCard.BackgroundColor3 = COLORS.PanelLight
spellCard.BorderSizePixel = 0
spellCard.Parent = lobbyPanel
addCorner(spellCard, 14)

local spellName =
	makeLabel(spellCard, "SpellName", spell.DisplayName, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(14, 12))
spellName.Font = Enum.Font.GothamBlack
spellName.TextColor3 = COLORS.OrangeBright
spellName.TextSize = 21

local recipe = makeLabel(
	spellCard,
	"Recipe",
	"火  ×  生成  ×  敵  ×  自分から  ×  指定地点へ投げて爆発",
	UDim2.new(1, -28, 0, 46),
	UDim2.fromOffset(14, 45)
)
recipe.TextWrapped = true
recipe.TextColor3 = COLORS.Cream
recipe.TextSize = 14

local cost = makeLabel(
	spellCard,
	"Cost",
	string.format(
		"🔥 ダメージ %d     ◉ マナ %d     ◷ %.1f秒",
		spell.Damage,
		spell.ManaCost,
		spell.Cooldown
	),
	UDim2.new(1, -28, 0, 28),
	UDim2.fromOffset(14, 96)
)
cost.Font = Enum.Font.GothamBold
cost.TextColor3 = COLORS.OrangeBright
cost.TextSize = 14

local formula = makeLabel(
	spellCard,
	"Formula",
	"マナ 5+8+6+4+0+14 = 37   /   CD 1.0+0.5+0.4+0.2+0+1.4 = 3.5",
	UDim2.new(1, -28, 0, 22),
	UDim2.fromOffset(14, 124)
)
formula.TextColor3 = COLORS.Muted
formula.TextSize = 12

local forgeButton = makeButton(lobbyPanel, "CreateSpellButton", "炎魔法を作る")
forgeButton.Position = UDim2.new(0, 20, 1, -116)
forgeButton.Size = UDim2.new(0.5, -26, 0, 48)

local enterButton = makeButton(lobbyPanel, "EnterGroundButton", "グラウンドへ出る")
enterButton.Position = UDim2.new(0.5, 6, 1, -116)
enterButton.Size = UDim2.new(0.5, -26, 0, 48)

local lobbyHint = makeLabel(
	lobbyPanel,
	"Hint",
	"UIを閉じても ForgeConsole と ExitGate のProximityPromptで操作できます。",
	UDim2.new(1, -40, 0, 42),
	UDim2.new(0, 20, 1, -58)
)
lobbyHint.TextWrapped = true
lobbyHint.TextColor3 = COLORS.Muted
lobbyHint.TextSize = 12
lobbyHint.TextXAlignment = Enum.TextXAlignment.Center

-- グラウンド用HUD
local hud = Instance.new("Frame")
hud.Name = "BattleHUD"
hud.Position = UDim2.fromOffset(18, 18)
hud.Size = UDim2.fromOffset(330, 126)
hud.BackgroundColor3 = COLORS.Panel
hud.BackgroundTransparency = 0.08
hud.BorderSizePixel = 0
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
manaText.TextColor3 = COLORS.Cream
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

-- 一時メッセージ
local toast = Instance.new("TextLabel")
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

local toastVersion = 0
local function showToast(message: string)
	toastVersion += 1
	local version = toastVersion
	toast.Text = message
	TweenService:Create(toast, TweenInfo.new(0.16), {
		BackgroundTransparency = 0.08,
		TextTransparency = 0,
	}):Play()
	task.delay(2.8, function()
		if version ~= toastVersion then
			return
		end
		TweenService:Create(toast, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
	end)
end

local function hasSpell(): boolean
	return player:GetAttribute(Config.HasSpellAttribute) == true
end

local function updateMode()
	local state = player:GetAttribute(Config.StateAttribute)
	local inGround = state == "Ground"
	lobbyPanel.Visible = not inGround
	hud.Visible = inGround

	local ready = hasSpell()
	forgeButton.Text = if ready then "✓ 炎魔法 作成済み" else "炎魔法を作る"
	forgeButton.BackgroundColor3 = if ready then COLORS.Green else COLORS.Orange
	enterButton.Active = ready
	enterButton.AutoButtonColor = ready
	enterButton.BackgroundColor3 = if ready then COLORS.Orange else COLORS.Disabled
	enterButton.TextTransparency = if ready then 0 else 0.25
end

local function request(action: string)
	lobbyActionRequest:FireServer(action)
end

forgeButton.Activated:Connect(function()
	request("CreateExampleSpell")
end)

enterButton.Activated:Connect(function()
	if hasSpell() then
		request("EnterGround")
	else
		showToast("先に炎魔法を作ってください。")
	end
end)

player:GetAttributeChangedSignal(Config.StateAttribute):Connect(updateMode)
player:GetAttributeChangedSignal(Config.HasSpellAttribute):Connect(updateMode)

stateChanged.OnClientEvent:Connect(function(_snapshot: any)
	updateMode()
end)

feedback.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" and typeof(payload.Message) == "string" then
		showToast(payload.Message)
	end
end)

RunService.RenderStepped:Connect(function()
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
	elseif mana + 1e-4 < spell.ManaCost then
		castStatus.Text = string.format("マナ回復中  |  必要 %d", spell.ManaCost)
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
		updateMode()
	end
end)

updateMode()
