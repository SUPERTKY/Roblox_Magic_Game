--!strict

export type SpellDefinition = {
	DisplayName: string,
	Description: string,
	Damage: number,
	Cooldown: number,
	Range: number,
	Speed: number,
	ProjectileRadius: number,
	BlastRadius: number,
	SlowDuration: number,
	Color: Color3,
}

local spells: { [string]: SpellDefinition } = {
	Fireball = {
		DisplayName = "Fireball",
		Description = "着弾地点の周囲にもダメージ",
		Damage = 30,
		Cooldown = 1.4,
		Range = 120,
		Speed = 100,
		ProjectileRadius = 1.0,
		BlastRadius = 8,
		SlowDuration = 0,
		Color = Color3.fromRGB(255, 106, 35),
	},
	FrostBolt = {
		DisplayName = "Frost Bolt",
		Description = "相手を短時間スロー",
		Damage = 20,
		Cooldown = 0.9,
		Range = 135,
		Speed = 135,
		ProjectileRadius = 0.75,
		BlastRadius = 0,
		SlowDuration = 2.5,
		Color = Color3.fromRGB(80, 205, 255),
	},
	ArcaneBolt = {
		DisplayName = "Arcane Bolt",
		Description = "連射しやすい直線魔法",
		Damage = 16,
		Cooldown = 0.45,
		Range = 105,
		Speed = 165,
		ProjectileRadius = 0.55,
		BlastRadius = 0,
		SlowDuration = 0,
		Color = Color3.fromRGB(191, 86, 255),
	},
}

return table.freeze(spells)

