--!strict

-- SpellDefs
-- 「属性 × 出し方 × 攻撃形態」から、サーバーが使用する最終スペル定義を構築します。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ElementDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ElementDefs"))

local Origins: {[string]: any} = {
	Throw = {
		Id = "Throw",
		DisplayName = "投げる",
		ManaModifier = 3,
		CooldownModifier = 0.00,
		CastRange = 240,
		ProjectileSpeed = 112,
		ProjectileLifetime = 4.0,
	},
	Place = {
		Id = "Place",
		DisplayName = "置く",
		ManaModifier = 5,
		CooldownModifier = 0.18,
		CastRange = 75,
	},
	Self = {
		Id = "Self",
		DisplayName = "自分から出す",
		ManaModifier = 1,
		CooldownModifier = -0.08,
		CastRange = 0,
	},
	Air = {
		Id = "Air",
		DisplayName = "空中に出す",
		ManaModifier = 6,
		CooldownModifier = 0.22,
		CastRange = 85,
		Height = 20,
	},
	Ground = {
		Id = "Ground",
		DisplayName = "地面から出す",
		ManaModifier = 4,
		CooldownModifier = 0.12,
		CastRange = 82,
	},
}

local OriginOrder = {
	"Throw",
	"Place",
	"Self",
	"Air",
	"Ground",
}

local Forms: {[string]: any} = {
	Explosion = {
		Id = "Explosion",
		DisplayName = "爆発",
		ManaCost = 14,
		Cooldown = 1.55,
		Damage = 25,
		Radius = 12,
		Delay = 0.28,
	},
	Spread = {
		Id = "Spread",
		DisplayName = "拡散",
		ManaCost = 15,
		Cooldown = 1.70,
		Damage = 13,
		Count = 6,
		ArcDegrees = 34,
		ProjectileSpeed = 105,
		ProjectileLifetime = 3.5,
	},
	Homing = {
		Id = "Homing",
		DisplayName = "追尾",
		ManaCost = 17,
		Cooldown = 2.20,
		Damage = 22,
		ProjectileSpeed = 82,
		ProjectileLifetime = 5.0,
		TurnRate = 7.5,
		LockRadius = 80,
	},
	Proximity = {
		Id = "Proximity",
		DisplayName = "探知攻撃",
		ManaCost = 18,
		Cooldown = 3.00,
		Damage = 27,
		ArmTime = 0.65,
		Lifetime = 18,
		TriggerRadius = 11,
		ExplosionRadius = 10,
	},
	Persistent = {
		Id = "Persistent",
		DisplayName = "持続範囲",
		ManaCost = 20,
		Cooldown = 4.10,
		Damage = 7,
		Radius = 11,
		Duration = 6.0,
		TickInterval = 0.65,
	},
}

local FormOrder = {
	"Explosion",
	"Spread",
	"Homing",
	"Proximity",
	"Persistent",
}

local SpellDefs = {}

SpellDefs.Mana = table.freeze({
	DefaultMax = 100,
	RegenPerSecond = 11,
	RegenDelayAfterSpend = 0.80,
	ReplicationStep = 0.10,
})

SpellDefs.Security = table.freeze({
	MaxAimDistance = 260,
	RemoteBurst = 7,
	RemoteRefillPerSecond = 5,
	GlobalCastInterval = 0.18,
	PreviewBurst = 10,
	PreviewRefillPerSecond = 6,
	MaxTargetsPerArea = 32,
})

SpellDefs.Origins = Origins
SpellDefs.OriginOrder = OriginOrder
SpellDefs.Forms = Forms
SpellDefs.FormOrder = FormOrder

function SpellDefs.IsValidOrigin(originId: any): boolean
	return typeof(originId) == "string" and Origins[originId] ~= nil
end

function SpellDefs.IsValidForm(formId: any): boolean
	return typeof(formId) == "string" and Forms[formId] ~= nil
end

function SpellDefs.Build(elementId: any, originId: any, formId: any): any?
	if not ElementDefs.IsValid(elementId) then
		return nil
	end
	if not SpellDefs.IsValidOrigin(originId) then
		return nil
	end
	if not SpellDefs.IsValidForm(formId) then
		return nil
	end

	local element = ElementDefs.Get(elementId)
	local origin = Origins[originId]
	local form = Forms[formId]
	if not element or not origin or not form then
		return nil
	end

	local manaCost = math.max(1, math.floor(form.ManaCost + origin.ManaModifier + element.ManaModifier + 0.5))
	local cooldown = math.max(0.25, form.Cooldown + origin.CooldownModifier + element.CooldownModifier)
	local damage = math.max(1, form.Damage * element.DamageMultiplier)

	return {
		Key = string.format("%s|%s|%s", elementId, originId, formId),
		Element = elementId,
		Origin = originId,
		Form = formId,
		ElementDef = element,
		OriginDef = origin,
		FormDef = form,
		ManaCost = manaCost,
		Cooldown = cooldown,
		Damage = damage,
		DisplayName = string.format("%s × %s × %s", element.DisplayName, origin.DisplayName, form.DisplayName),
	}
end

function SpellDefs.ToPreview(spec: any): {[string]: any}
	return {
		Key = spec.Key,
		Element = spec.Element,
		Origin = spec.Origin,
		Form = spec.Form,
		DisplayName = spec.DisplayName,
		ManaCost = spec.ManaCost,
		Cooldown = spec.Cooldown,
		Damage = spec.Damage,
		Color = spec.ElementDef.Color,
	}
end

return table.freeze(SpellDefs)
