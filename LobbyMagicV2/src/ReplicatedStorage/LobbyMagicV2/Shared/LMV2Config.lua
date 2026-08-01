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
	TeamAttribute = "LMV2_Team",
	SelectionAttributes = {
		Attribute = "LMV2_SelectedAttribute",
		Creation = "LMV2_SelectedCreation",
		Target = "LMV2_SelectedTarget",
		Origin = "LMV2_SelectedOrigin",
		Attack = "LMV2_SelectedAttack",
	},

	-- falseにするとLobbyMagicV2UIは何も作りません。
	-- ProximityPromptとLMV2Clientによる発動は残るため、ゲーム機能は止まりません。
	EnableGeneratedUI = true,

	World = {
		FolderName = "LMV2_World",
		LobbySpawnName = "LobbySpawn",
		GroundSpawnName = "GroundSpawn",
		ForgeConsoleName = "ForgeConsole",
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
		MaxProjectilesPerPlayer = 2,
	},
}

return table.freeze(Config)
