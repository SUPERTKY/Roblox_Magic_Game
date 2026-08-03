--!strict

-- 魔法工房の20項目を一元管理します。
-- クライアントからは選択IDだけを受け取り、戦闘値は必ずこのカタログで再計算します。

local Config = require(script.Parent:WaitForChild("LMV2Config"))

local BaseCost = {
	DisplayName = "基本",
	Mana = 5,
	Cooldown = 1.0,
}

local function option(
	id: string,
	displayName: string,
	mana: number,
	cooldown: number,
	extra: { [string]: any }?
): { [string]: any }
	local value: { [string]: any } = {
		Id = id,
		DisplayName = displayName,
		Mana = mana,
		Cooldown = cooldown,
	}
	if extra then
		for key, item in pairs(extra) do
			value[key] = item
		end
	end
	return value
end

local Components: { [string]: { [string]: { [string]: any } } } = {
	Attribute = {
		Fire = option("Fire", "火", 8, 0.5, { Element = "Fire", Color = Color3.fromRGB(255, 92, 35) }),
		Ice = option(
			"Ice",
			"氷",
			7,
			0.55,
			{ Element = "Ice", DamageMultiplier = 0.92, Control = "Slow", Color = Color3.fromRGB(105, 220, 255) }
		),
		Lightning = option(
			"Lightning",
			"雷",
			10,
			0.7,
			{ Element = "Lightning", DamageMultiplier = 1.08, Color = Color3.fromRGB(255, 231, 92) }
		),
		Wind = option(
			"Wind",
			"風",
			5,
			0.3,
			{ Element = "Wind", DamageMultiplier = 0.86, SpeedMultiplier = 1.18, Color = Color3.fromRGB(151, 255, 191) }
		),
		Earth = option(
			"Earth",
			"土",
			8,
			0.65,
			{
				Element = "Earth",
				DamageMultiplier = 1.12,
				SpeedMultiplier = 0.82,
				ProjectileScaleMultiplier = 1.15,
				Color = Color3.fromRGB(157, 111, 67),
			}
		),
		Light = option(
			"Light",
			"光",
			7,
			0.45,
			{ Element = "Light", DamageMultiplier = 0.9, SpeedMultiplier = 1.1, Color = Color3.fromRGB(255, 246, 190) }
		),
		Dark = option(
			"Dark",
			"闇",
			11,
			0.8,
			{ Element = "Dark", DamageMultiplier = 1.15, SpeedMultiplier = 0.9, Color = Color3.fromRGB(126, 76, 190) }
		),
	},
	Creation = {
		Projectile = option("Projectile", "魔法弾", 6, 0.4, { Delivery = "Projectile" }),
		Beam = option(
			"Beam",
			"ビーム",
			11,
			0.8,
			{ Delivery = "Beam", DamageMultiplier = 0.9, SpeedMultiplier = 2.5, RadiusMultiplier = 0.65 }
		),
		Placement = option(
			"Placement",
			"設置",
			8,
			0.6,
			{ Delivery = "Placement", DamageMultiplier = 0.9, RadiusMultiplier = 1.2 }
		),
		Trap = option("Trap", "罠", 7, 0.5, { Delivery = "Trap", DamageMultiplier = 1.15, RadiusMultiplier = 1.15 }),
		Field = option(
			"Field",
			"フィールド",
			12,
			1.0,
			{ Delivery = "Field", DamageMultiplier = 0.48, RadiusMultiplier = 1.35, Duration = 5 }
		),
	},
	Target = {
		Enemy = option("Enemy", "敵", 4, 0.2, { TargetMode = "Enemy" }),
		Ally = option("Ally", "味方", 5, 0.35, { TargetMode = "Ally", DamageMultiplier = 0.75 }),
		Self = option("Self", "自分", 2, 0.15, { TargetMode = "Self", DamageMultiplier = 0.7 }),
		Ground = option("Ground", "地面", 3, 0.2, { TargetMode = "Ground", RadiusMultiplier = 1.1 }),
	},
	Origin = {
		Self = option("Self", "術者の前", 0, 0, { OriginMode = "Self" }),
		AroundSelf = option(
			"AroundSelf",
			"術者の周囲",
			3,
			0.2,
			{ OriginMode = "AroundSelf", RadiusMultiplier = 1.08 }
		),
		TargetPoint = option("TargetPoint", "指定地点", 5, 0.35, { OriginMode = "TargetPoint" }),
		AboveTarget = option(
			"AboveTarget",
			"対象上空",
			7,
			0.5,
			{ OriginMode = "AboveTarget", DamageMultiplier = 1.05 }
		),
		Ground = option("Ground", "地面", 2, 0.15, { OriginMode = "Ground" }),
	},
	ProjectileCount = {
		One = option("One", "1球", 0, 0, { Count = 1, DamageMultiplier = 1, Angles = { 0 } }),
		Two = option("Two", "2球", 5, 0.35, { Count = 2, DamageMultiplier = 0.62, Angles = { -4, 4 } }),
		Three = option("Three", "3球", 9, 0.65, { Count = 3, DamageMultiplier = 0.48, Angles = { -7, 0, 7 } }),
		Five = option("Five", "5球", 15, 1.1, { Count = 5, DamageMultiplier = 0.32, Angles = { -12, -6, 0, 6, 12 } }),
		Eight = option(
			"Eight",
			"8球",
			20,
			1.45,
			{ Count = 8, DamageMultiplier = 0.22, Angles = { -18, -13, -8, -3, 3, 8, 13, 18 } }
		),
	},
	ProjectileSize = {
		Tiny = option(
			"Tiny",
			"極小",
			-5,
			-0.3,
			{ DamageMultiplier = 0.65, SpeedMultiplier = 1.3, ProjectileScaleMultiplier = 0.5 }
		),
		Small = option(
			"Small",
			"小",
			-3,
			-0.2,
			{ DamageMultiplier = 0.8, SpeedMultiplier = 1.15, ProjectileScaleMultiplier = 0.75 }
		),
		Normal = option("Normal", "普通", 0, 0, { ProjectileScaleMultiplier = 1 }),
		Large = option(
			"Large",
			"大",
			7,
			0.5,
			{ DamageMultiplier = 1.25, SpeedMultiplier = 0.8, ProjectileScaleMultiplier = 1.3, RadiusMultiplier = 1.08 }
		),
		Huge = option(
			"Huge",
			"巨大",
			13,
			0.9,
			{ DamageMultiplier = 1.5, SpeedMultiplier = 0.62, ProjectileScaleMultiplier = 1.65, RadiusMultiplier = 1.18 }
		),
	},
	ProjectileSpeed = {
		VerySlow = option("VerySlow", "とても遅い（50）", -4, -0.1, { Speed = 50, MaxDistance = 100 }),
		Slow = option("Slow", "遅い（70）", -2, 0, { Speed = 70, MaxDistance = 120 }),
		Normal = option("Normal", "普通（92）", 0, 0, { Speed = 92, MaxDistance = 145 }),
		Fast = option("Fast", "速い（130）", 4, 0.2, { Speed = 130, MaxDistance = 160 }),
		VeryFast = option("VeryFast", "超高速（175）", 8, 0.45, { Speed = 175, MaxDistance = 175 }),
	},
	Attack = {
		Direct = option(
			"Direct",
			"直撃",
			7,
			0.8,
			{ AttackMode = "Direct", DamageMultiplier = 1.2, ExplosionRadius = 0, VFXScale = 0.45 }
		),
		Explosion = option(
			"Explosion",
			"爆発",
			14,
			1.4,
			{ AttackMode = "Explosion", ExplosionRadius = 12, VFXScale = 1 }
		),
		Pierce = option(
			"Pierce",
			"貫通",
			12,
			1.0,
			{ AttackMode = "Pierce", DamageMultiplier = 0.82, ExplosionRadius = 0, VFXScale = 0.55, Penetrations = 2 }
		),
		Bounce = option(
			"Bounce",
			"跳弾",
			10,
			0.9,
			{ AttackMode = "Bounce", DamageMultiplier = 0.78, ExplosionRadius = 6, VFXScale = 0.7, Bounces = 2 }
		),
		Chain = option(
			"Chain",
			"連鎖",
			16,
			1.35,
			{ AttackMode = "Chain", DamageMultiplier = 0.72, ExplosionRadius = 8, VFXScale = 0.8, ChainCount = 3 }
		),
		PersistentField = option(
			"PersistentField",
			"持続エリア",
			18,
			1.6,
			{ AttackMode = "Field", DamageMultiplier = 0.42, ExplosionRadius = 14, VFXScale = 1.1, Duration = 5 }
		),
	},
	SpellShape = {
		Sphere = option("Sphere", "球", 0, 0, { Shape = "Sphere" }),
		Spear = option(
			"Spear",
			"槍",
			2,
			0.1,
			{ Shape = "Spear", DamageMultiplier = 1.08, ProjectileScaleMultiplier = 0.85 }
		),
		Disc = option("Disc", "円盤", 2, 0.15, { Shape = "Disc", RadiusMultiplier = 1.08 }),
		Ring = option("Ring", "リング", 3, 0.2, { Shape = "Ring", RadiusMultiplier = 1.15 }),
		Wall = option("Wall", "壁", 5, 0.35, { Shape = "Wall", DamageMultiplier = 0.8, RadiusMultiplier = 1.3 }),
	},
	Trajectory = {
		Straight = option("Straight", "直線", 0, 0, { Trajectory = "Straight" }),
		Arc = option("Arc", "放物線", -1, 0, { Trajectory = "Arc", RangeMultiplier = 1.05 }),
		Homing = option("Homing", "追尾", 9, 0.55, { Trajectory = "Homing", DamageMultiplier = 0.85 }),
		Spiral = option("Spiral", "螺旋", 4, 0.25, { Trajectory = "Spiral", ProjectileScaleMultiplier = 1.08 }),
		GroundFollow = option(
			"GroundFollow",
			"地面沿い",
			2,
			0.15,
			{ Trajectory = "GroundFollow", DamageMultiplier = 1.05 }
		),
	},
	Aiming = {
		Free = option("Free", "自由照準", 0, 0, { Aiming = "Free" }),
		LockOn = option("LockOn", "ロックオン", 8, 0.45, { Aiming = "LockOn", DamageMultiplier = 0.9 }),
		Nearest = option("Nearest", "最寄りの敵", 6, 0.35, { Aiming = "Nearest", DamageMultiplier = 0.86 }),
		GroundPoint = option("GroundPoint", "地点指定", 1, 0.05, { Aiming = "GroundPoint" }),
		DirectionFixed = option(
			"DirectionFixed",
			"方向固定",
			-2,
			-0.1,
			{ Aiming = "DirectionFixed", DamageMultiplier = 1.08 }
		),
	},
	FirePattern = {
		Simultaneous = option("Simultaneous", "同時", 0, 0, { FirePattern = "Simultaneous" }),
		Sequential = option("Sequential", "連射", 2, 0.2, { FirePattern = "Sequential", ShotInterval = 0.12 }),
		Burst = option(
			"Burst",
			"時間差",
			1,
			0.1,
			{ FirePattern = "Burst", ShotInterval = 0.22, DamageMultiplier = 1.04 }
		),
		Radial = option("Radial", "全方向", 5, 0.35, { FirePattern = "Radial", DamageMultiplier = 0.82 }),
		Orbit = option(
			"Orbit",
			"回転展開",
			7,
			0.5,
			{ FirePattern = "Orbit", ShotInterval = 0.08, DamageMultiplier = 0.9 }
		),
	},
	CastStyle = {
		Instant = option("Instant", "即時", 4, 0.15, { CastStyle = "Instant", CastDelay = 0 }),
		ShortChant = option(
			"ShortChant",
			"短詠唱",
			0,
			0,
			{ CastStyle = "ShortChant", CastDelay = 0.35, DamageMultiplier = 1.05 }
		),
		Charge = option(
			"Charge",
			"溜め",
			3,
			0.35,
			{ CastStyle = "Charge", CastDelay = 0.8, DamageMultiplier = 1.2, ProjectileScaleMultiplier = 1.12 }
		),
		Channel = option(
			"Channel",
			"継続詠唱",
			5,
			0.55,
			{ CastStyle = "Channel", CastDelay = 0.5, DamageMultiplier = 0.82, Duration = 3 }
		),
	},
	Performance = {
		Efficient = option("Efficient", "省魔力", -7, 0.35, { Performance = "Efficient", DamageMultiplier = 0.8 }),
		Balanced = option("Balanced", "均衡", 0, 0, { Performance = "Balanced" }),
		Power = option("Power", "高威力", 8, 0.65, { Performance = "Power", DamageMultiplier = 1.25 }),
		Rapid = option("Rapid", "短CD", 5, -0.55, { Performance = "Rapid", DamageMultiplier = 0.82 }),
		LongRange = option(
			"LongRange",
			"長射程",
			5,
			0.25,
			{ Performance = "LongRange", DamageMultiplier = 0.9, RangeMultiplier = 1.25 }
		),
	},
	Range = {
		Short = option("Short", "近距離", -3, -0.15, { RangeMultiplier = 0.65, DamageMultiplier = 1.08 }),
		Medium = option("Medium", "中距離", 0, 0, { RangeMultiplier = 1 }),
		Long = option("Long", "遠距離", 4, 0.25, { RangeMultiplier = 1.25, DamageMultiplier = 0.94 }),
		Extreme = option("Extreme", "超遠距離", 8, 0.5, { RangeMultiplier = 1.5, DamageMultiplier = 0.86 }),
	},
	Duration = {
		Instant = option("Instant", "一瞬", 0, 0, { Duration = 0 }),
		TwoSeconds = option("TwoSeconds", "2秒", 2, 0.15, { Duration = 2, DamageMultiplier = 0.92 }),
		FiveSeconds = option("FiveSeconds", "5秒", 5, 0.35, { Duration = 5, DamageMultiplier = 0.78 }),
		TenSeconds = option("TenSeconds", "10秒", 9, 0.7, { Duration = 10, DamageMultiplier = 0.6 }),
	},
	AreaShape = {
		Circle = option("Circle", "円", 0, 0, { AreaShape = "Circle" }),
		Cone = option("Cone", "扇形", 1, 0.1, { AreaShape = "Cone", DamageMultiplier = 1.05 }),
		Line = option("Line", "直線", 1, 0.1, { AreaShape = "Line", DamageMultiplier = 1.08 }),
		Ring = option("Ring", "リング", 2, 0.15, { AreaShape = "Ring", RadiusMultiplier = 1.15 }),
		Wall = option(
			"Wall",
			"壁状",
			3,
			0.2,
			{ AreaShape = "Wall", DamageMultiplier = 0.9, RadiusMultiplier = 1.25 }
		),
	},
	ControlEffect = {
		None = option("None", "なし", 0, 0, { ControlEffect = "None" }),
		Slow = option("Slow", "減速", 4, 0.25, { ControlEffect = "Slow", DamageMultiplier = 0.85 }),
		Push = option("Push", "押し出し", 3, 0.2, { ControlEffect = "Push", DamageMultiplier = 0.9 }),
		Pull = option("Pull", "引き寄せ", 5, 0.35, { ControlEffect = "Pull", DamageMultiplier = 0.82 }),
		Root = option("Root", "短時間拘束", 7, 0.5, { ControlEffect = "Root", DamageMultiplier = 0.72 }),
	},
	Movement = {
		Stop = option("Stop", "停止", -2, -0.1, { Movement = "Stop", DamageMultiplier = 1.12 }),
		Slow = option("Slow", "低速移動", 0, 0, { Movement = "Slow", DamageMultiplier = 1.05 }),
		Normal = option("Normal", "通常移動", 2, 0.1, { Movement = "Normal" }),
		Advance = option("Advance", "前進", 4, 0.25, { Movement = "Advance", DamageMultiplier = 0.92 }),
		Blink = option("Blink", "短距離転移", 8, 0.45, { Movement = "Blink", DamageMultiplier = 0.82 }),
	},
	Theme = {
		Simple = option("Simple", "シンプル", 0, 0, { Theme = "Simple", Color = Color3.fromRGB(255, 255, 255) }),
		Rune = option("Rune", "魔法陣", 0, 0, { Theme = "Rune", Color = Color3.fromRGB(175, 105, 255) }),
		Spark = option("Spark", "火花", 0, 0, { Theme = "Spark", Color = Color3.fromRGB(255, 225, 95) }),
		Mist = option("Mist", "霧", 0, 0, { Theme = "Mist", Color = Color3.fromRGB(175, 220, 235) }),
		Crystal = option("Crystal", "結晶", 0, 0, { Theme = "Crystal", Color = Color3.fromRGB(120, 235, 255) }),
		Ancient = option("Ancient", "古代文字", 0, 0, { Theme = "Ancient", Color = Color3.fromRGB(222, 173, 90) }),
	},
}

local DefaultSelection: { [string]: string } = {
	Attribute = "Fire",
	Creation = "Projectile",
	Target = "Enemy",
	Origin = "Self",
	ProjectileCount = "One",
	ProjectileSize = "Normal",
	ProjectileSpeed = "Normal",
	Attack = "Explosion",
	SpellShape = "Sphere",
	Trajectory = "Straight",
	Aiming = "Free",
	FirePattern = "Simultaneous",
	CastStyle = "ShortChant",
	Performance = "Balanced",
	Range = "Medium",
	Duration = "Instant",
	AreaShape = "Circle",
	ControlEffect = "None",
	Movement = "Normal",
	Theme = "Simple",
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
	"SpellShape",
	"Trajectory",
	"Aiming",
	"FirePattern",
	"CastStyle",
	"Performance",
	"Range",
	"Duration",
	"AreaShape",
	"ControlEffect",
	"Movement",
	"Theme",
}

local ComponentGroups: { [string]: { string } } = {
	Basic = {
		"Attribute",
		"Creation",
		"Target",
		"Origin",
		"ProjectileCount",
		"ProjectileSize",
		"ProjectileSpeed",
		"Attack",
	},
	Advanced = {
		"SpellShape",
		"Trajectory",
		"Aiming",
		"FirePattern",
		"CastStyle",
		"Performance",
		"Range",
		"Duration",
		"AreaShape",
		"ControlEffect",
		"Movement",
	},
	Appearance = { "Theme" },
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
	SpellShape = "魔法形状",
	Trajectory = "軌道",
	Aiming = "照準方式",
	FirePattern = "発射パターン",
	CastStyle = "詠唱方式",
	Performance = "性能配分",
	Range = "射程",
	Duration = "持続時間",
	AreaShape = "範囲形状",
	ControlEffect = "制御効果",
	Movement = "発動中の移動",
	Theme = "演出テーマ",
}

local OptionOrder: { [string]: { string } } = {
	Attribute = { "Fire", "Ice", "Lightning", "Wind", "Earth", "Light", "Dark" },
	Creation = { "Projectile", "Beam", "Placement", "Trap", "Field" },
	Target = { "Enemy", "Ally", "Self", "Ground" },
	Origin = { "Self", "AroundSelf", "TargetPoint", "AboveTarget", "Ground" },
	ProjectileCount = { "One", "Two", "Three", "Five", "Eight" },
	ProjectileSize = { "Tiny", "Small", "Normal", "Large", "Huge" },
	ProjectileSpeed = { "VerySlow", "Slow", "Normal", "Fast", "VeryFast" },
	Attack = { "Direct", "Explosion", "Pierce", "Bounce", "Chain", "PersistentField" },
	SpellShape = { "Sphere", "Spear", "Disc", "Ring", "Wall" },
	Trajectory = { "Straight", "Arc", "Homing", "Spiral", "GroundFollow" },
	Aiming = { "Free", "LockOn", "Nearest", "GroundPoint", "DirectionFixed" },
	FirePattern = { "Simultaneous", "Sequential", "Burst", "Radial", "Orbit" },
	CastStyle = { "Instant", "ShortChant", "Charge", "Channel" },
	Performance = { "Efficient", "Balanced", "Power", "Rapid", "LongRange" },
	Range = { "Short", "Medium", "Long", "Extreme" },
	Duration = { "Instant", "TwoSeconds", "FiveSeconds", "TenSeconds" },
	AreaShape = { "Circle", "Cone", "Line", "Ring", "Wall" },
	ControlEffect = { "None", "Slow", "Push", "Pull", "Root" },
	Movement = { "Stop", "Slow", "Normal", "Advance", "Blink" },
	Theme = { "Simple", "Rune", "Spark", "Mist", "Crystal", "Ancient" },
}

local LegacyIds: { [string]: { [string]: string } } = {
	Creation = { Generate = "Projectile" },
	Attack = {
		SmallExplosion = "Explosion",
		StandardExplosion = "Explosion",
		LargeExplosion = "Explosion",
	},
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
	local damageMultiplier = 1
	local speedMultiplier = 1
	local rangeMultiplier = 1
	local radiusMultiplier = 1
	local projectileScaleMultiplier = 1
	local normalizedSelection: { [string]: string } = {}
	local resolved: { [string]: any } = {}
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
		if selectedId == nil then
			selectedId = DefaultSelection[category]
		end
		if typeof(selectedId) ~= "string" then
			return nil
		end
		local categoryLegacyIds = LegacyIds[category]
		if categoryLegacyIds and categoryLegacyIds[selectedId] then
			selectedId = categoryLegacyIds[selectedId]
		end
		local component = Components[category][selectedId]
		if not component then
			return nil
		end
		normalizedSelection[category] = selectedId
		resolved[category] = component
		mana += component.Mana
		cooldown += component.Cooldown
		damageMultiplier *= component.DamageMultiplier or 1
		speedMultiplier *= component.SpeedMultiplier or 1
		rangeMultiplier *= component.RangeMultiplier or 1
		radiusMultiplier *= component.RadiusMultiplier or 1
		projectileScaleMultiplier *= component.ProjectileScaleMultiplier or 1
		local publicComponent = copyComponent(component)
		publicComponent.Category = category
		table.insert(costBreakdown, publicComponent)
	end

	mana = math.max(1, round(mana))
	if mana > Config.Inventory.MaximumManaCost then
		return nil
	end

	local count = resolved.ProjectileCount
	local speed = resolved.ProjectileSpeed
	local attack = resolved.Attack
	local attribute = resolved.Attribute
	local theme = resolved.Theme
	local duration = math.max(
		resolved.Creation.Duration or 0,
		attack.Duration or 0,
		resolved.CastStyle.Duration or 0,
		resolved.Duration.Duration or 0
	)
	local color = attribute.Color:Lerp(theme.Color, 0.28)
	local damage = math.max(1, round(25 * damageMultiplier))
	local radius = math.max(0, round((attack.ExplosionRadius or 0) * radiusMultiplier))
	local projectileSpeed = math.clamp(speed.Speed * speedMultiplier, 25, 240)
	local maxDistance = math.clamp(round(speed.MaxDistance * rangeMultiplier), 45, Config.Security.MaxAimDistance)
	local keyParts = { "LMV2" }
	for _, category in ipairs(ComponentOrder) do
		table.insert(keyParts, normalizedSelection[category])
	end

	return {
		Key = table.concat(keyParts, "_"),
		GeneratedName = string.format("%s・%s", attribute.DisplayName, attack.DisplayName),
		DisplayName = "名前未設定",
		Selection = normalizedSelection,
		CostBreakdown = costBreakdown,
		ManaCost = mana,
		Cooldown = math.max(0.5, cooldown),
		Damage = damage,
		HealAmount = math.max(1, round(damage * 0.8)),
		TotalDamage = damage * count.Count,
		ExplosionRadius = radius,
		ProjectileSpeed = projectileSpeed,
		MaxDistance = maxDistance,
		ProjectileCount = count.Count,
		SpreadAngles = table.clone(count.Angles),
		ProjectileScale = math.clamp(projectileScaleMultiplier, 0.35, 2),
		ExplosionVFXScale = math.clamp(
			(attack.VFXScale or 1) * projectileScaleMultiplier * math.max(0.7, radiusMultiplier),
			0.35,
			2
		),
		IsDirect = (attack.AttackMode == "Direct" or attack.AttackMode == "Pierce") and radius <= 0,
		Element = attribute.Element,
		Color = color,
		Delivery = resolved.Creation.Delivery,
		TargetMode = resolved.Target.TargetMode,
		OriginMode = resolved.Origin.OriginMode,
		AttackMode = attack.AttackMode,
		Shape = resolved.SpellShape.Shape,
		Trajectory = resolved.Trajectory.Trajectory,
		Aiming = resolved.Aiming.Aiming,
		FirePattern = resolved.FirePattern.FirePattern,
		ShotInterval = resolved.FirePattern.ShotInterval or 0,
		CastStyle = resolved.CastStyle.CastStyle,
		CastDelay = resolved.CastStyle.CastDelay or 0,
		Performance = resolved.Performance.Performance,
		Duration = duration,
		AreaShape = resolved.AreaShape.AreaShape,
		ControlEffect = if resolved.ControlEffect.ControlEffect ~= "None"
			then resolved.ControlEffect.ControlEffect
			else (attribute.Control or "None"),
		Movement = resolved.Movement.Movement,
		Theme = theme.Theme,
		Penetrations = attack.Penetrations or 0,
		Bounces = attack.Bounces or 0,
		ChainCount = attack.ChainCount or 0,
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
Catalog.ComponentGroups = ComponentGroups
Catalog.CategoryDisplayNames = CategoryDisplayNames
Catalog.OptionOrder = OptionOrder

return table.freeze(Catalog)
