--!strict

-- 最初のMVPでは、この組み合わせだけを作成できます。
-- 数値はすべて足し算で最終マナとクールダウンになります。

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
	Attack = {
		ThrowPointExplosion = {
			Id = "ThrowPointExplosion",
			DisplayName = "クリック・タップ地点へ投げて爆発",
			Mana = 14,
			Cooldown = 1.4,
		},
	},
}

local DefaultSelection: { [string]: string } = {
	Attribute = "Fire",
	Creation = "Generate",
	Target = "Enemy",
	Origin = "Self",
	Attack = "ThrowPointExplosion",
}

local ComponentOrder: { string } = {
	"Attribute",
	"Creation",
	"Target",
	"Origin",
	"Attack",
}

local CategoryDisplayNames: { [string]: string } = {
	Attribute = "属性",
	Creation = "生成方法",
	Target = "対象",
	Origin = "発生場所",
	Attack = "攻撃方法",
}

local OptionOrder: { [string]: { string } } = {
	Attribute = { "Fire" },
	Creation = { "Generate" },
	Target = { "Enemy" },
	Origin = { "Self" },
	Attack = { "ThrowPointExplosion" },
}

local Catalog = {}

local function copyComponent(component: { [string]: any }): { [string]: any }
	return {
		Id = component.Id,
		DisplayName = component.DisplayName,
		Mana = component.Mana,
		Cooldown = component.Cooldown,
	}
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
		local group = Components[category]
		local component = group[selectedId]
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

	return {
		Key = string.format(
			"LMV2_%s_%s_%s_%s_%s",
			normalizedSelection.Attribute,
			normalizedSelection.Creation,
			normalizedSelection.Target,
			normalizedSelection.Origin,
			normalizedSelection.Attack
		),
		DisplayName = "ファイアボム",
		Selection = normalizedSelection,
		CostBreakdown = costBreakdown,
		ManaCost = mana,
		Cooldown = cooldown,
		Damage = 25,
		ExplosionRadius = 12,
		ProjectileSpeed = 92,
		MaxDistance = 145,
	}
end

function Catalog.BuildExample(): { [string]: any }
	local spell = Catalog.Build(DefaultSelection)
	assert(spell, "既定の魔法設定が壊れています")
	return spell
end

function Catalog.IsExampleSpellKey(value: any): boolean
	return typeof(value) == "string" and value == Catalog.BuildExample().Key
end

Catalog.BaseCost = BaseCost
Catalog.Components = Components
Catalog.Selection = DefaultSelection
Catalog.DefaultSelection = DefaultSelection
Catalog.ComponentOrder = ComponentOrder
Catalog.CategoryDisplayNames = CategoryDisplayNames
Catalog.OptionOrder = OptionOrder

return table.freeze(Catalog)
