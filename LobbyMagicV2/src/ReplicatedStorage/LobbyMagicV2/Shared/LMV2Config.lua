--!strict

-- LobbyMagicV2だけが参照する設定です。
-- 旧Magic / FireballServer / FireballClientとは名前も保存先も分けています。

local Config = {
	SystemId = "LobbyMagicV2",
	StateAttribute = "LMV2_State",
	HasSpellAttribute = "LMV2_HasExampleSpell",
	SpellKeyAttribute = "LMV2_SpellKey",
	ManaAttribute = "LMV2_Mana",
	MaxManaAttribute = "LMV2_MaxMana",
	CooldownEndAttribute = "LMV2_CooldownEnd",
	ActiveSlotAttribute = "LMV2_ActiveSpellSlot",
	DataReadyAttribute = "LMV2_DataReady",
	TeamAttribute = "LMV2_Team",
	SelectionAttributes = {
		Attribute = "LMV2_SelectedAttribute",
		Creation = "LMV2_SelectedCreation",
		Target = "LMV2_SelectedTarget",
		Origin = "LMV2_SelectedOrigin",
		ProjectileCount = "LMV2_SelectedProjectileCount",
		ProjectileSize = "LMV2_SelectedProjectileSize",
		ProjectileSpeed = "LMV2_SelectedProjectileSpeed",
		Attack = "LMV2_SelectedAttack",
	},

	Inventory = {
		MaximumSpells = 5,
		MaximumNameLength = 20,
		MaximumManaCost = 80,
	},

	Persistence = {
		DataStoreName = "LobbyMagicV2_Spells_v1",
		DataVersion = 1,
		AutosaveSeconds = 60,
	},

	-- falseにするとLobbyMagicV2UIは何も作りません。
	-- 魔法を作成するには、LobbyActionRequestを使う別のUIが必要です。
	EnableGeneratedUI = true,

	World = {
		FolderName = "LMV2_World",
		LobbySpawnName = "LobbySpawn",
		GroundSpawnName = "GroundSpawn",
		ForgeUIZoneName = "ForgeUIZone",
		ExitGateName = "ExitGate",
		ReturnGateName = "ReturnGate",
		TeleportHeight = 4,
		PromptDistance = 12,
	},

	Mana = {
		Maximum = 100,
		RegenPerSecond = 11,
		RegenDelayAfterCast = 0.8,
		ReplicationStep = 0.1,
	},

	Security = {
		MaxAimDistance = 160,
		MinCastInterval = 0.18,
		LobbyActionInterval = 0.25,
		MaxExplosionParts = 120,
		MaxProjectilesPerCast = 5,
		MaxProjectilesPerPlayer = 6,
	},
}

return table.freeze(Config)
