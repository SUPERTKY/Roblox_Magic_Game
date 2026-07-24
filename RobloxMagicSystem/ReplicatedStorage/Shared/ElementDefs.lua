--!strict

-- ElementDefs
-- 属性ごとの見た目・状態異常・係数を一元管理します。
-- サーバーが最終判定を行うため、クライアントから数値を受け取りません。

local Elements: {[string]: any} = {
	Fire = {
		Id = "Fire",
		DisplayName = "火",
		Color = Color3.fromRGB(255, 92, 43),
		DamageMultiplier = 1.00,
		ManaModifier = 2,
		CooldownModifier = 0.05,
		Burn = {
			DamagePerTick = 4,
			TickInterval = 1.0,
			Duration = 4.0,
		},
	},

	Ice = {
		Id = "Ice",
		DisplayName = "氷",
		Color = Color3.fromRGB(116, 218, 255),
		DamageMultiplier = 0.88,
		ManaModifier = 3,
		CooldownModifier = 0.10,
		Ice = {
			SlowReduction = 0.38,
			SlowDuration = 3.0,
			HitsToFreeze = 3,
			FreezeBuildWindow = 5.0,
			FreezeDuration = 1.45,
		},
	},

	Lightning = {
		Id = "Lightning",
		DisplayName = "雷",
		Color = Color3.fromRGB(255, 239, 95),
		DamageMultiplier = 0.93,
		ManaModifier = 5,
		CooldownModifier = 0.20,
		Shock = {
			Duration = 0.75,
			MoveMultiplier = 0.72,
		},
		Chain = {
			Count = 3,
			Range = 18,
			DamageFalloff = 0.72,
		},
	},

	Wind = {
		Id = "Wind",
		DisplayName = "風",
		Color = Color3.fromRGB(167, 255, 207),
		DamageMultiplier = 0.82,
		ManaModifier = 1,
		CooldownModifier = -0.05,
		Knockback = {
			HorizontalImpulse = 48,
			UpwardImpulse = 17,
		},
	},

	Poison = {
		Id = "Poison",
		DisplayName = "毒",
		Color = Color3.fromRGB(152, 255, 80),
		DamageMultiplier = 0.76,
		ManaModifier = 2,
		CooldownModifier = 0.05,
		Poison = {
			DamagePerTick = 3,
			TickInterval = 1.0,
			Duration = 6.0,
		},
	},

	Light = {
		Id = "Light",
		DisplayName = "光",
		Color = Color3.fromRGB(255, 246, 184),
		DamageMultiplier = 0.90,
		ManaModifier = 5,
		CooldownModifier = 0.18,
		HealMultiplier = 0.90,
		PierceCount = 3,
	},
}

local Order = {
	"Fire",
	"Ice",
	"Lightning",
	"Wind",
	"Poison",
	"Light",
}

local ElementDefs = {}

ElementDefs.All = Elements
ElementDefs.Order = Order

function ElementDefs.IsValid(elementId: any): boolean
	return typeof(elementId) == "string" and Elements[elementId] ~= nil
end

function ElementDefs.Get(elementId: string): any?
	return Elements[elementId]
end

return table.freeze(ElementDefs)
