--!strict

local Workspace = game:GetService("Workspace")

if Workspace:FindFirstChild("MagicGameWorld") then
	return
end

local world = Instance.new("Folder")
world.Name = "MagicGameWorld"
world.Parent = Workspace

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Lobby
makePart(
	"LobbyFloor",
	Vector3.new(90, 2, 90),
	CFrame.new(0, 0, 0),
	Color3.fromRGB(48, 55, 72),
	Enum.Material.Slate,
	world
)

local lobbySpawn = Instance.new("SpawnLocation")
lobbySpawn.Name = "LobbySpawn"
lobbySpawn.Size = Vector3.new(8, 1, 8)
lobbySpawn.CFrame = CFrame.new(0, 1.5, 16)
lobbySpawn.Color = Color3.fromRGB(112, 255, 176)
lobbySpawn.Material = Enum.Material.Neon
lobbySpawn.Anchored = true
lobbySpawn.Neutral = true
lobbySpawn.Duration = 0
lobbySpawn.Parent = world

local forge = makePart(
	"SpellForge",
	Vector3.new(18, 1, 10),
	CFrame.new(0, 1.5, -7),
	Color3.fromRGB(147, 94, 255),
	Enum.Material.Neon,
	world
)
forge.CanCollide = true

local forgeSign = Instance.new("BillboardGui")
forgeSign.Name = "ForgeSign"
forgeSign.Size = UDim2.fromOffset(360, 70)
forgeSign.StudsOffset = Vector3.new(0, 5, 0)
forgeSign.AlwaysOnTop = true
forgeSign.Parent = forge

local forgeText = Instance.new("TextLabel")
forgeText.Size = UDim2.fromScale(1, 1)
forgeText.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
forgeText.BackgroundTransparency = 0.15
forgeText.Text = "先に自分の魔法を作成しよう"
forgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
forgeText.Font = Enum.Font.GothamBold
forgeText.TextScaled = true
forgeText.Parent = forgeSign

-- Magic gate
local gateColor = Color3.fromRGB(118, 74, 255)
makePart("GateLeft", Vector3.new(3, 15, 3), CFrame.new(-7, 7.5, -34), gateColor, Enum.Material.Slate, world)
makePart("GateRight", Vector3.new(3, 15, 3), CFrame.new(7, 7.5, -34), gateColor, Enum.Material.Slate, world)
makePart("GateTop", Vector3.new(17, 3, 3), CFrame.new(0, 14, -34), gateColor, Enum.Material.Slate, world)

local portal = makePart(
	"BattlePortal",
	Vector3.new(11, 11, 1),
	CFrame.new(0, 7.5, -34),
	Color3.fromRGB(80, 224, 255),
	Enum.Material.Neon,
	world
)
portal.CanCollide = false
portal.Transparency = 0.2
portal:SetAttribute("MagicBattlePortal", true)

local portalLight = Instance.new("PointLight")
portalLight.Color = portal.Color
portalLight.Brightness = 3
portalLight.Range = 22
portalLight.Parent = portal

local portalPrompt = Instance.new("ProximityPrompt")
portalPrompt.ActionText = "作成した魔法でバトルへ"
portalPrompt.ObjectText = "魔法作成後に入れるゲート"
portalPrompt.KeyboardKeyCode = Enum.KeyCode.E
portalPrompt.RequiresLineOfSight = false
portalPrompt.MaxActivationDistance = 12
portalPrompt.Parent = portal

-- Battlefield
local battlefieldCenter = Vector3.new(0, 0, -250)
makePart(
	"BattlefieldFloor",
	Vector3.new(220, 2, 220),
	CFrame.new(battlefieldCenter),
	Color3.fromRGB(37, 41, 52),
	Enum.Material.Basalt,
	world
)

local wallColor = Color3.fromRGB(72, 62, 102)
makePart("NorthWall", Vector3.new(224, 18, 4), CFrame.new(0, 9, -362), wallColor, Enum.Material.Rock, world)
makePart("SouthWall", Vector3.new(224, 18, 4), CFrame.new(0, 9, -138), wallColor, Enum.Material.Rock, world)
makePart("WestWall", Vector3.new(4, 18, 220), CFrame.new(-112, 9, -250), wallColor, Enum.Material.Rock, world)
makePart("EastWall", Vector3.new(4, 18, 220), CFrame.new(112, 9, -250), wallColor, Enum.Material.Rock, world)

-- Cover makes projectile battles more interesting.
local coverPositions = {
	Vector3.new(-42, 7, -250),
	Vector3.new(42, 7, -250),
	Vector3.new(0, 7, -207),
	Vector3.new(0, 7, -293),
}
for index, position in coverPositions do
	makePart(
		"Cover" .. index,
		Vector3.new(14, 14, 14),
		CFrame.new(position) * CFrame.Angles(0, math.rad(45), 0),
		Color3.fromRGB(61, 67, 83),
		Enum.Material.Slate,
		world
	)
end

local spawnPoints = Instance.new("Folder")
spawnPoints.Name = "BattleSpawnPoints"
spawnPoints.Parent = world

local spawnPositions = {
	Vector3.new(-78, 3, -328),
	Vector3.new(0, 3, -330),
	Vector3.new(78, 3, -328),
	Vector3.new(-80, 3, -250),
	Vector3.new(80, 3, -250),
	Vector3.new(-78, 3, -172),
	Vector3.new(0, 3, -170),
	Vector3.new(78, 3, -172),
}

for index, position in spawnPositions do
	local marker = makePart(
		"Spawn" .. index,
		Vector3.new(6, 1, 6),
		CFrame.lookAt(position, Vector3.new(0, position.Y, -250)),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.SmoothPlastic,
		spawnPoints
	)
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Transparency = 1
end
