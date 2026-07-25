--!strict

export type ElementDefinition = {
	DisplayName: string,
	Description: string,
	Color: Color3,
	DamageMultiplier: number,
	BlastBonus: number,
	SlowDuration: number,
}

export type StyleDefinition = {
	DisplayName: string,
	Description: string,
	Damage: number,
	Cooldown: number,
	Range: number,
	Speed: number,
	ProjectileRadius: number,
	BlastRadius: number,
}

export type SpellDefinition = {
	Name: string,
	ElementId: string,
	StyleId: string,
	Damage: number,
	Cooldown: number,
	Range: number,
	Speed: number,
	ProjectileRadius: number,
	BlastRadius: number,
	SlowDuration: number,
	Color: Color3,
	CanDestroyBuildings: boolean,
}

local elements: { [string]: ElementDefinition } = {
	Flame = {
		DisplayName = "炎",
		Description = "着弾時の爆発範囲が広がる",
		Color = Color3.fromRGB(255, 106, 35),
		DamageMultiplier = 1.0,
		BlastBonus = 3,
		SlowDuration = 0,
	},
	Frost = {
		DisplayName = "氷",
		Description = "命中した相手を短時間スロー",
		Color = Color3.fromRGB(80, 205, 255),
		DamageMultiplier = 1.0,
		BlastBonus = 0,
		SlowDuration = 2.5,
	},
	Arcane = {
		DisplayName = "魔力",
		Description = "魔力を集中し、ダメージが少し高い",
		Color = Color3.fromRGB(191, 86, 255),
		DamageMultiplier = 1.15,
		BlastBonus = 0,
		SlowDuration = 0,
	},
}

local styles: { [string]: StyleDefinition } = {
	Power = {
		DisplayName = "高威力型",
		Description = "遅いが強力な一撃",
		Damage = 28,
		Cooldown = 1.4,
		Range = 120,
		Speed = 100,
		ProjectileRadius = 1.0,
		BlastRadius = 5,
	},
	Balanced = {
		DisplayName = "バランス型",
		Description = "威力・速度・連射のバランスが良い",
		Damage = 22,
		Cooldown = 0.85,
		Range = 135,
		Speed = 135,
		ProjectileRadius = 0.75,
		BlastRadius = 1,
	},
	Rapid = {
		DisplayName = "連射型",
		Description = "威力は低いが素早く連射できる",
		Damage = 15,
		Cooldown = 0.45,
		Range = 105,
		Speed = 165,
		ProjectileRadius = 0.55,
		BlastRadius = 0,
	},
}

local elementOrder = { "Flame", "Frost", "Arcane" }
local styleOrder = { "Power", "Balanced", "Rapid" }

local function buildSpell(name: string, elementId: string, styleId: string): SpellDefinition?
	local element = elements[elementId]
	local style = styles[styleId]
	if not element or not style then
		return nil
	end

	return {
		Name = name,
		ElementId = elementId,
		StyleId = styleId,
		Damage = math.round(style.Damage * element.DamageMultiplier),
		Cooldown = style.Cooldown,
		Range = style.Range,
		Speed = style.Speed,
		ProjectileRadius = style.ProjectileRadius,
		BlastRadius = style.BlastRadius + element.BlastBonus,
		SlowDuration = element.SlowDuration,
		Color = element.Color,
		CanDestroyBuildings = true,
	}
end

return table.freeze({
	Elements = table.freeze(elements),
	Styles = table.freeze(styles),
	ElementOrder = table.freeze(elementOrder),
	StyleOrder = table.freeze(styleOrder),
	BuildSpell = buildSpell,
})

