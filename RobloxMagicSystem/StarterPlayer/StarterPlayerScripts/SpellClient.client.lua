--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ElementDefs = require(Shared:WaitForChild("ElementDefs"))
local SpellDefs = require(Shared:WaitForChild("SpellDefs"))
local SharedUtil = require(Shared:WaitForChild("SharedUtil"))

-- 定義ファイルの世代差で Order が存在しない場合でも、UIが起動できるようにします。
-- 最新の ElementDefs / SpellDefs では各 Order が公開されています。
local function resolveOrder(candidate: any, fallback: {string}, label: string): {string}
	if typeof(candidate) == "table" and #candidate > 0 then
		return candidate :: {string}
	end

	warn(string.format("[Magic] %s が見つからないため既定順序を使用します。Shared定義ファイルを最新版へ置き換えてください。", label))
	return fallback
end

local ElementOrder = resolveOrder(ElementDefs.Order, {
	"Fire",
	"Ice",
	"Lightning",
	"Wind",
	"Poison",
	"Light",
}, "ElementDefs.Order")

local OriginOrder = resolveOrder(SpellDefs.OriginOrder, {
	"Throw",
	"Place",
	"Self",
	"Air",
	"Ground",
}, "SpellDefs.OriginOrder")

local FormOrder = resolveOrder(SpellDefs.FormOrder, {
	"Explosion",
	"Spread",
	"Homing",
	"Proximity",
	"Persistent",
}, "SpellDefs.FormOrder")

local function getElementDef(elementId: string): any?
	if typeof(ElementDefs.Get) == "function" then
		return ElementDefs.Get(elementId)
	end

	if typeof(ElementDefs.All) == "table" then
		return ElementDefs.All[elementId]
	end

	-- 古い定義形式（属性テーブルを直接 return）との互換用です。
	return ElementDefs[elementId]
end

local FALLBACK_ORIGINS: {[string]: any} = {
	Throw = { DisplayName = "投げる" },
	Place = { DisplayName = "置く" },
	Self = { DisplayName = "自分から出す" },
	Air = { DisplayName = "空中に出す" },
	Ground = { DisplayName = "地面から出す" },
}

local FALLBACK_FORMS: {[string]: any} = {
	Explosion = { DisplayName = "爆発" },
	Spread = { DisplayName = "拡散" },
	Homing = { DisplayName = "追尾" },
	Proximity = { DisplayName = "探知攻撃" },
	Persistent = { DisplayName = "持続範囲" },
}

local OriginDefs: {[string]: any}
if typeof(SpellDefs.Origins) == "table" then
	OriginDefs = SpellDefs.Origins
else
	warn("[Magic] SpellDefs.Origins がないため表示用の互換定義を使用します。SpellDefsを最新版へ置き換えてください。")
	OriginDefs = FALLBACK_ORIGINS
end

local FormDefs: {[string]: any}
if typeof(SpellDefs.Forms) == "table" then
	FormDefs = SpellDefs.Forms
else
	warn("[Magic] SpellDefs.Forms がないため表示用の互換定義を使用します。SpellDefsを最新版へ置き換えてください。")
	FormDefs = FALLBACK_FORMS
end

local defaultMaxMana = 100
if typeof(SpellDefs.Mana) == "table" and typeof(SpellDefs.Mana.DefaultMax) == "number" then
	defaultMaxMana = SpellDefs.Mana.DefaultMax
end

local maxAimDistance = 260
if typeof(SpellDefs.Security) == "table" and typeof(SpellDefs.Security.MaxAimDistance) == "number" then
	maxAimDistance = SpellDefs.Security.MaxAimDistance
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CastSpellRequest = Remotes:WaitForChild("CastSpellRequest") :: RemoteEvent
local SpellFx = Remotes:WaitForChild("SpellFx") :: RemoteEvent
local GetSpellPreview = Remotes:WaitForChild("GetSpellPreview") :: RemoteFunction

local selectedElementIndex = 1
local selectedOriginIndex = 1
local selectedFormIndex = 1
local previewData: {[string]: any}? = nil
local previewGeneration = 0
local cooldownsByKey: {[string]: number} = {}
local pendingUntil = 0
local toastGeneration = 0

local clientFxFolder = Workspace:FindFirstChild("MagicClientFx_" .. player.UserId)
if not clientFxFolder then
	clientFxFolder = Instance.new("Folder")
	clientFxFolder.Name = "MagicClientFx_" .. player.UserId
	clientFxFolder.Parent = Workspace
end

local function addCorner(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function addStroke(object: GuiObject, thickness: number, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Parent = object
end

local gui = Instance.new("ScreenGui")
gui.Name = "MagicHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "SpellPanel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.new(0.94, 0, 0, 158)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 38)
panel.BackgroundTransparency = 0.08
panel.Parent = gui
addCorner(panel, 16)
addStroke(panel, 2, 0.55)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(350, 145)
sizeConstraint.MaxSize = Vector2.new(720, 170)
sizeConstraint.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 8)
title.Size = UDim2.new(1, -36, 0, 25)
title.Font = Enum.Font.GothamBold
title.Text = "MAGIC FORGE"
title.TextColor3 = Color3.fromRGB(236, 238, 255)
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local selectorRow = Instance.new("Frame")
selectorRow.BackgroundTransparency = 1
selectorRow.Position = UDim2.fromOffset(16, 38)
selectorRow.Size = UDim2.new(1, -142, 0, 54)
selectorRow.Parent = panel

local selectorLayout = Instance.new("UIListLayout")
selectorLayout.FillDirection = Enum.FillDirection.Horizontal
selectorLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
selectorLayout.Padding = UDim.new(0, 8)
selectorLayout.Parent = selectorRow

local function makeSelectorButton(): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1 / 3, -6, 1, 0)
	button.BackgroundColor3 = Color3.fromRGB(43, 47, 72)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.TextWrapped = true
	button.Parent = selectorRow
	addCorner(button, 10)
	addStroke(button, 1, 0.72)
	return button
end

local elementButton = makeSelectorButton()
local originButton = makeSelectorButton()
local formButton = makeSelectorButton()

local castButton = Instance.new("TextButton")
castButton.Name = "CastButton"
castButton.AnchorPoint = Vector2.new(1, 0)
castButton.Position = UDim2.new(1, -16, 0, 38)
castButton.Size = UDim2.fromOffset(110, 54)
castButton.BackgroundColor3 = Color3.fromRGB(255, 92, 43)
castButton.Font = Enum.Font.GothamBlack
castButton.Text = "CAST\n[R]"
castButton.TextColor3 = Color3.fromRGB(20, 20, 28)
castButton.TextSize = 18
castButton.Parent = panel
addCorner(castButton, 12)
addStroke(castButton, 2, 0.35)

local manaBack = Instance.new("Frame")
manaBack.Position = UDim2.fromOffset(16, 105)
manaBack.Size = UDim2.new(1, -32, 0, 24)
manaBack.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
manaBack.Parent = panel
addCorner(manaBack, 8)

local manaFill = Instance.new("Frame")
manaFill.Size = UDim2.fromScale(1, 1)
manaFill.BackgroundColor3 = Color3.fromRGB(94, 148, 255)
manaFill.Parent = manaBack
addCorner(manaFill, 8)

local manaText = Instance.new("TextLabel")
manaText.BackgroundTransparency = 1
manaText.Size = UDim2.fromScale(1, 1)
manaText.Font = Enum.Font.GothamBold
manaText.TextColor3 = Color3.fromRGB(255, 255, 255)
manaText.TextSize = 14
manaText.Text = "MANA 100 / 100"
manaText.ZIndex = 3
manaText.Parent = manaBack

local infoText = Instance.new("TextLabel")
infoText.BackgroundTransparency = 1
infoText.Position = UDim2.fromOffset(18, 132)
infoText.Size = UDim2.new(1, -36, 0, 20)
infoText.Font = Enum.Font.GothamMedium
infoText.TextColor3 = Color3.fromRGB(194, 200, 224)
infoText.TextSize = 13
infoText.TextXAlignment = Enum.TextXAlignment.Left
infoText.Text = "Q: 属性 / E: 出し方 / F: 攻撃形態 / R・左クリック: 発動"
infoText.Parent = panel

local cooldownText = Instance.new("TextLabel")
cooldownText.AnchorPoint = Vector2.new(0.5, 0.5)
cooldownText.Position = UDim2.fromScale(0.5, 0.45)
cooldownText.Size = UDim2.fromOffset(360, 70)
cooldownText.BackgroundTransparency = 1
cooldownText.Font = Enum.Font.GothamBlack
cooldownText.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownText.TextStrokeTransparency = 0.35
cooldownText.TextSize = 32
cooldownText.Text = ""
cooldownText.Visible = false
cooldownText.Parent = gui

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 28)
toast.Size = UDim2.new(0.9, 0, 0, 48)
toast.BackgroundColor3 = Color3.fromRGB(22, 24, 40)
toast.BackgroundTransparency = 0.12
toast.Font = Enum.Font.GothamBold
toast.TextColor3 = Color3.fromRGB(255, 255, 255)
toast.TextSize = 17
toast.Text = ""
toast.Visible = false
toast.Parent = gui
addCorner(toast, 12)
addStroke(toast, 1, 0.55)
local toastConstraint = Instance.new("UISizeConstraint")
toastConstraint.MinSize = Vector2.new(280, 48)
toastConstraint.MaxSize = Vector2.new(520, 48)
toastConstraint.Parent = toast

local function currentSelection(): (string, string, string)
	return ElementOrder[selectedElementIndex], OriginOrder[selectedOriginIndex], FormOrder[selectedFormIndex]
end

local function spellKey(elementId: string, originId: string, formId: string): string
	return string.format("%s|%s|%s", elementId, originId, formId)
end

local function showToast(message: string, color: Color3?)
	toastGeneration += 1
	local generation = toastGeneration
	toast.Text = message
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.12
	toast.Visible = true

	task.delay(1.7, function()
		if generation ~= toastGeneration then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.25), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Wait()
		if generation == toastGeneration then
			toast.Visible = false
		end
	end)
end

local function updateMana()
	local mana = player:GetAttribute("Mana")
	local maxMana = player:GetAttribute("MaxMana")
	if typeof(mana) ~= "number" then
		mana = 0
	end
	if typeof(maxMana) ~= "number" or maxMana <= 0 then
		maxMana = defaultMaxMana
	end

	local ratio = math.clamp(mana / maxMana, 0, 1)
	TweenService:Create(manaFill, TweenInfo.new(0.12), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()
	manaText.Text = string.format("MANA %d / %d", math.floor(mana + 0.5), math.floor(maxMana + 0.5))
end

local function updateSelectionLabels()
	local elementId, originId, formId = currentSelection()
	local element = getElementDef(elementId)
	local origin = OriginDefs[originId]
	local form = FormDefs[formId]
	if not element or not origin or not form then
		return
	end

	elementButton.Text = "属性 [Q]\n" .. element.DisplayName
	originButton.Text = "出し方 [E]\n" .. origin.DisplayName
	formButton.Text = "攻撃形態 [F]\n" .. form.DisplayName
	elementButton.BackgroundColor3 = element.Color:Lerp(Color3.fromRGB(30, 32, 50), 0.46)
	castButton.BackgroundColor3 = element.Color
end

local function requestPreview()
	previewGeneration += 1
	local generation = previewGeneration
	local elementId, originId, formId = currentSelection()

	task.delay(0.08, function()
		if generation ~= previewGeneration then
			return
		end

		local ok, result = pcall(function()
			return GetSpellPreview:InvokeServer({
				Element = elementId,
				Origin = originId,
				Form = formId,
			})
		end)
		if generation ~= previewGeneration then
			return
		end
		if not ok or typeof(result) ~= "table" or result.Ok ~= true then
			previewData = nil
			infoText.Text = "プレビューを取得できません"
			return
		end

		previewData = result
		infoText.Text = string.format(
			"消費魔力 %d / ダメージ %.0f / CD %.1f秒",
			result.ManaCost,
			result.Damage,
			result.Cooldown
		)
		if typeof(result.CooldownRemaining) == "number" and typeof(result.Key) == "string" then
			cooldownsByKey[result.Key] = math.max(
				cooldownsByKey[result.Key] or 0,
				os.clock() + result.CooldownRemaining
			)
		end
	end)
end

local function selectionChanged()
	updateSelectionLabels()
	requestPreview()
end

local function cycleElement()
	selectedElementIndex = selectedElementIndex % #ElementOrder + 1
	selectionChanged()
end

local function cycleOrigin()
	selectedOriginIndex = selectedOriginIndex % #OriginOrder + 1
	selectionChanged()
end

local function cycleForm()
	selectedFormIndex = selectedFormIndex % #FormOrder + 1
	selectionChanged()
end

elementButton.Activated:Connect(cycleElement)
originButton.Activated:Connect(cycleOrigin)
formButton.Activated:Connect(cycleForm)

local function getAim(): (Vector3, Vector3)
	camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end

	local viewportPoint: Vector2
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		viewportPoint = camera.ViewportSize / 2
	else
		viewportPoint = UserInputService:GetMouseLocation()
	end

	local unitRay = camera:ViewportPointToRay(viewportPoint.X, viewportPoint.Y)
	local direction = SharedUtil.SafeUnit(unitRay.Direction)
	local excludes: {Instance} = {}
	if player.Character then
		table.insert(excludes, player.Character)
	end
	local runtime = Workspace:FindFirstChild("MagicRuntime")
	if runtime then
		table.insert(excludes, runtime)
	end
	if clientFxFolder then
		table.insert(excludes, clientFxFolder)
	end

	local result = Workspace:Raycast(
		unitRay.Origin,
		direction * maxAimDistance,
		SharedUtil.MakeRaycastParams(excludes)
	)
	local position = if result then result.Position else unitRay.Origin + direction * maxAimDistance
	return position, direction
end

local function castSpell()
	local now = os.clock()
	if now < pendingUntil then
		return
	end
	local elementId, originId, formId = currentSelection()
	local key = spellKey(elementId, originId, formId)
	local readyAt = cooldownsByKey[key] or 0
	if now < readyAt then
		showToast(string.format("クールダウン %.1f秒", readyAt - now), Color3.fromRGB(255, 214, 120))
		return
	end

	if previewData then
		local mana = player:GetAttribute("Mana")
		if typeof(mana) == "number" and mana < previewData.ManaCost then
			showToast("魔力が足りません", Color3.fromRGB(255, 133, 133))
			return
		end
	end

	local aimPosition, aimDirection = getAim()
	pendingUntil = now + 0.16
	CastSpellRequest:FireServer({
		Element = elementId,
		Origin = originId,
		Form = formId,
		AimPosition = aimPosition,
		AimDirection = aimDirection,
	})
end

castButton.Activated:Connect(castSpell)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		cycleElement()
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleOrigin()
	elseif input.KeyCode == Enum.KeyCode.F then
		cycleForm()
	elseif input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonR2 then
		castSpell()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		castSpell()
	end
end)

local function makeFxPart(
	position: Vector3,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0.12
	part.Size = size
	part.Shape = shape or Enum.PartType.Ball
	part.Position = position
	part.Parent = clientFxFolder
	return part
end

local function pulseSphere(position: Vector3, color: Color3, finalDiameter: number, duration: number)
	local part = makeFxPart(position, Vector3.new(0.4, 0.4, 0.4), color, Enum.PartType.Ball, 0.12)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(finalDiameter, finalDiameter, finalDiameter),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function ring(position: Vector3, color: Color3, radius: number, duration: number, startTransparency: number?)
	local part = makeFxPart(
		position + Vector3.new(0, 0.15, 0),
		Vector3.new(0.18, 0.5, 0.5),
		color,
		Enum.PartType.Cylinder,
		startTransparency or 0.35
	)
	part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, 0, math.rad(90))
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.18, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

local function beam(fromPosition: Vector3, toPosition: Vector3, color: Color3, duration: number)
	local delta = toPosition - fromPosition
	local distance = delta.Magnitude
	if distance <= 0.05 then
		return
	end
	local midpoint = fromPosition + delta * 0.5
	local part = makeFxPart(midpoint, Vector3.new(0.28, 0.28, distance), color, Enum.PartType.Block, 0.04)
	part.CFrame = CFrame.lookAt(midpoint, toPosition)
	local tween = TweenService:Create(part, TweenInfo.new(duration), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, distance),
	})
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

SpellFx.OnClientEvent:Connect(function(kind: string, payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	if kind == "CastAccepted" then
		pendingUntil = 0
		if typeof(payload.Cooldown) == "number" and typeof(payload.Key) == "string" then
			cooldownsByKey[payload.Key] = os.clock() + payload.Cooldown
		end
		showToast(payload.DisplayName or "魔法発動！", payload.Color)
	elseif kind == "CastRejected" then
		pendingUntil = 0
		showToast(payload.Reason or "発動できません", Color3.fromRGB(255, 135, 135))
	elseif kind == "Cast" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 3.4, 0.22)
	elseif kind == "Impact" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 2.8, 0.20)
	elseif kind == "Explosion" and typeof(payload.Position) == "Vector3" then
		local radius = payload.Radius or 8
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), radius * 2, 0.42)
		ring(payload.Position, payload.Color or Color3.new(1, 1, 1), radius, 0.48, 0.18)
	elseif kind == "Chain" and typeof(payload.From) == "Vector3" and typeof(payload.To) == "Vector3" then
		beam(payload.From, payload.To, payload.Color or Color3.new(1, 1, 1), 0.24)
	elseif kind == "Area" and typeof(payload.Position) == "Vector3" then
		ring(
			payload.Position,
			payload.Color or Color3.new(1, 1, 1),
			payload.Radius or 10,
			math.min(payload.Duration or 3, 6),
			0.48
		)
	elseif kind == "TrapArmed" and typeof(payload.Position) == "Vector3" then
		ring(payload.Position, payload.Color or Color3.new(1, 1, 1), payload.Radius or 8, 0.65, 0.38)
	elseif kind == "GroundRise" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 5.5, 0.32)
	elseif kind == "Heal" and typeof(payload.Position) == "Vector3" then
		pulseSphere(payload.Position, payload.Color or Color3.new(1, 1, 1), 4.5, 0.38)
	end
end)

player:GetAttributeChangedSignal("Mana"):Connect(updateMana)
player:GetAttributeChangedSignal("MaxMana"):Connect(updateMana)

RunService.RenderStepped:Connect(function()
	local elementId, originId, formId = currentSelection()
	local remaining = (cooldownsByKey[spellKey(elementId, originId, formId)] or 0) - os.clock()
	if remaining > 0 then
		cooldownText.Visible = true
		cooldownText.Text = string.format("COOLDOWN %.1f", remaining)
		castButton.Text = string.format("%.1f", remaining)
	else
		cooldownText.Visible = false
		castButton.Text = "CAST\n[R]"
	end
end)

updateSelectionLabels()
updateMana()
requestPreview()
