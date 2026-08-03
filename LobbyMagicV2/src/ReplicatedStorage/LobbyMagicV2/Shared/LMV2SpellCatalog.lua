--!strict

-- 魔法の各設定は一つずつ選択します。選択肢の総数ではなく、
-- 実際に選んだ設定だけを加算し、魔力80以内に収めます。

local Config = require(script.Parent:WaitForChild("LMV2Config"))

local BaseCost = {
	DisplayName = "基本",
	Mana = 5,
	Cooldown = 1.0,
}

local Components: { [string]: { [string]: { [string]: any } } } = {
	Attribute = {
		Fire = {
			Id = "Fire",
			DisplayName = "火",
			Mana = 8,
			Cooldown = 0.5,
		},
	},
	Creation = {
		Generate = {
			Id = "Generate",
			DisplayName = "生成",
			Mana = 6,
			Cooldown = 0.4,
		},
	},
	Target = {
		Enemy = {
			Id = "Enemy",
			DisplayName = "敵",
			Mana = 4,
			Cooldown = 0.2,
		},
	},
	Origin = {
		Self = {
			Id = "Self",
			DisplayName = "自分",
			Mana = 0,
			Cooldown = 0,
		},
	},
	ProjectileCount = {
		One = {
			Id = "One",
			DisplayName = "1球",
			Mana = 0,
			Cooldown = 0,
			Count = 1,
			DamageMultiplier = 1.0,
			Angles = { 0 },
		},
		Two = {
			Id = "Two",
			DisplayName = "2球",
			Mana = 5,
			Cooldown = 0.35,
			Count = 2,
			DamageMultiplier = 0.62,
			Angles = { -4, 4 },
		},
		Three = {
			Id = "Three",
			DisplayName = "3球",
			Mana = 9,
			Cooldown = 0.65,
			Count = 3,
			DamageMultiplier = 0.48,
			Angles = { -7, 0, 7 },
		},
		Five = {
			Id = "Five",
			DisplayName = "5球",
			Mana = 15,
			Cooldown = 1.1,
			Count = 5,
			DamageMultiplier = 0.32,
			Angles = { -12, -6, 0, 6, 12 },
		},
	},
	ProjectileSize = {
		Small = {
			Id = "Small",
			DisplayName = "小",
			Mana = -3,
			Cooldown = -0.2,
			DamageMultiplier = 0.8,
			SpeedMultiplier = 1.15,
			VisualScale = 0.75,
		},
		Normal = {
			Id = "Normal",
			DisplayName = "普通",
			Mana = 0,
			Cooldown = 0,
			DamageMultiplier = 1.0,
			SpeedMultiplier = 1.0,
			VisualScale = 1.0,
		},
		Large = {
			Id = "Large",
			DisplayName = "大",
			Mana = 7,
			Cooldown = 0.5,
			DamageMultiplier = 1.25,
			SpeedMultiplier = 0.8,
			VisualScale = 1.3,
		},
	},
	ProjectileSpeed = {
		Slow = {
			Id = "Slow",
			DisplayName = "遅い（70）",
			Mana = -2,
			Cooldown = 0,
			Speed = 70,
			MaxDistance = 120,
		},
		Normal = {
			Id = "Normal",
			DisplayName = "普通（92）",
			Mana = 0,
			Cooldown = 0,
			Speed = 92,
			MaxDistance = 145,
		},
		Fast = {
			Id = "Fast",
			DisplayName = "速い（130）",
			Mana = 4,
			Cooldown = 0.2,
			Speed = 130,
			MaxDistance = 160,
		},
	},
	Attack = {
		Direct = {
			Id = "Direct",
			DisplayName = "直撃",
			Mana = 7,
			Cooldown = 0.8,
			DamageMultiplier = 1.2,
			ExplosionRadius = 0,
			VFXScale = 0.45,
		},
		SmallExplosion = {
			Id = "SmallExplosion",
			DisplayName = "小爆発（6stud）",
			Mana = 10,
			Cooldown = 1.1,
			DamageMultiplier = 1.05,
			ExplosionRadius = 6,
			VFXScale = 0.65,
		},
		StandardExplosion = {
			Id = "StandardExplosion",
			DisplayName = "通常爆発（12stud）",
			Mana = 14,
			Cooldown = 1.4,
			DamageMultiplier = 1.0,
			ExplosionRadius = 12,
			VFXScale = 1.0,
		},
		LargeExplosion = {
			Id = "LargeExplosion",
			DisplayName = "大爆発（18stud）",
			Mana = 22,
			Cooldown = 1.8,
			DamageMultiplier = 0.85,
			ExplosionRadius = 18,
			VFXScale = 1.35,
		},
	},
}

local DefaultSelection: { [string]: string } = {
	Attribute = "Fire",
	Creation = "Generate",
	Target = "Enemy",
	Origin = "Self",
	ProjectileCount = "One",
	ProjectileSize = "Normal",
	ProjectileSpeed = "Normal",
	Attack = "StandardExplosion",
}

local ComponentOrder: { string } = {
	"Attribute",
	"Creation",
	"Target",
	"Origin",
	"ProjectileCount",
	"ProjectileSize",
	"ProjectileSpeed",
	"Attack",
}

local CategoryDisplayNames: { [string]: string } = {
	Attribute = "属性",
	Creation = "生成方法",
	Target = "対象",
	Origin = "発生場所",
	ProjectileCount = "球数",
	ProjectileSize = "球サイズ",
	ProjectileSpeed = "球速",
	Attack = "着弾方法",
}

local OptionOrder: { [string]: { string } } = {
	Attribute = { "Fire" },
	Creation = { "Generate" },
	Target = { "Enemy" },
	Origin = { "Self" },
	ProjectileCount = { "One", "Two", "Three", "Five" },
	ProjectileSize = { "Small", "Normal", "Large" },
	ProjectileSpeed = { "Slow", "Normal", "Fast" },
	Attack = { "Direct", "SmallExplosion", "StandardExplosion", "LargeExplosion" },
}

local Catalog = {}

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function copyComponent(component: { [string]: any }): { [string]: any }
	return {
		Id = component.Id,
		DisplayName = component.DisplayName,
		Mana = component.Mana,
		Cooldown = component.Cooldown,
	}
end

function Catalog.NormalizeName(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local name = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
	if name == "" or string.find(name, "[%c]") then
		return nil
	end
	local length = utf8.len(name)
	if not length or length > Config.Inventory.MaximumNameLength then
		return nil
	end
	return name
end

function Catalog.CopyDefaultSelection(): { [string]: string }
	return table.clone(DefaultSelection)
end

function Catalog.GetOptionIds(category: any): { string }
	if typeof(category) ~= "string" then
		return {}
	end
	local options = OptionOrder[category]
	return if options then table.clone(options) else {}
end

function Catalog.GetComponent(category: any, componentId: any): { [string]: any }?
	if typeof(category) ~= "string" or typeof(componentId) ~= "string" then
		return nil
	end
	local group = Components[category]
	return if group then group[componentId] else nil
end

function Catalog.Build(selection: any): { [string]: any }?
	if typeof(selection) ~= "table" then
		return nil
	end

	local mana = BaseCost.Mana
	local cooldown = BaseCost.Cooldown
	local normalizedSelection: { [string]: string } = {}
	local costBreakdown = {
		{
			Category = "Base",
			Id = "Base",
			DisplayName = BaseCost.DisplayName,
			Mana = BaseCost.Mana,
			Cooldown = BaseCost.Cooldown,
		},
	}

	for _, category in ipairs(ComponentOrder) do
		local selectedId = selection[category]
		if typeof(selectedId) ~= "string" then
			return nil
		end
		local component = Components[category][selectedId]
		if not component then
			return nil
		end
		normalizedSelection[category] = selectedId
		mana += component.Mana
		cooldown += component.Cooldown

		local publicComponent = copyComponent(component)
		publicComponent.Category = category
		table.insert(costBreakdown, publicComponent)
	end

	if mana > Config.Inventory.MaximumManaCost then
		return nil
	end

	local count = Components.ProjectileCount[normalizedSelection.ProjectileCount]
	local size = Components.ProjectileSize[normalizedSelection.ProjectileSize]
	local speed = Components.ProjectileSpeed[normalizedSelection.ProjectileSpeed]
	local attack = Components.Attack[normalizedSelection.Attack]
	local damage = round(25 * count.DamageMultiplier * size.DamageMultiplier * attack.DamageMultiplier)
	local angles = table.clone(count.Angles)

	return {
		Key = string.format(
			"LMV2_%s_%s_%s_%s_%s_%s_%s_%s",
			normalizedSelection.Attribute,
			normalizedSelection.Creation,
			normalizedSelection.Target,
			normalizedSelection.Origin,
			normalizedSelection.ProjectileCount,
			normalizedSelection.ProjectileSize,
			normalizedSelection.ProjectileSpeed,
			normalizedSelection.Attack
		),
		GeneratedName = string.format("%s・%s", count.DisplayName, attack.DisplayName),
		DisplayName = "名前未設定",
		Selection = normalizedSelection,
		CostBreakdown = costBreakdown,
		ManaCost = math.max(1, mana),
		Cooldown = math.max(0.5, cooldown),
		Damage = math.max(1, damage),
		TotalDamage = math.max(1, damage) * count.Count,
		ExplosionRadius = attack.ExplosionRadius,
		ProjectileSpeed = speed.Speed * size.SpeedMultiplier,
		MaxDistance = speed.MaxDistance,
		ProjectileCount = count.Count,
		SpreadAngles = angles,
		ProjectileScale = size.VisualScale,
		ExplosionVFXScale = attack.VFXScale * size.VisualScale,
		IsDirect = attack.ExplosionRadius <= 0,
	}
end

function Catalog.BuildExample(): { [string]: any }
	local spell = Catalog.Build(DefaultSelection)
	assert(spell, "既定の魔法設定が壊れています")
	return spell
end

Catalog.BaseCost = BaseCost
Catalog.Components = Components
Catalog.DefaultSelection = DefaultSelection
Catalog.ComponentOrder = ComponentOrder
Catalog.CategoryDisplayNames = CategoryDisplayNames
Catalog.OptionOrder = OptionOrder

return table.freeze(Catalog)
