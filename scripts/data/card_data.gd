@tool
class_name CardData
extends Resource

## 单张卡牌的可序列化配置资源。
## 这里只保存不会随战斗临时变化的基础资料；卡牌节点负责显示，
## 小队顺序和遮挡关系则由 SquadData 保存。

const CardFactionScript = preload("res://scripts/data/card_faction.gd")
const CardPackRegistryScript = preload("res://scripts/data/card_pack_registry.gd")

enum CardType {
	MINION,
	EQUIPMENT,
	SPELL,
	RESOURCE,
}

enum ActionType {
	MELEE,
	RANGED,
	MAGIC,
	HEAL,
	DEFENSE,
}

enum ElementType {
	FIRE,
	WATER,
	WOOD,
	LIGHT,
	DARK,
}

enum RaceType {
	HUMAN,
	ELF,
	DWARF,
	CONSTRUCT,
	ELEMENTAL,
	UNDEAD,
	DEMON,
	BEAST,
	PLANT,
}

enum Rarity {
	I,
	II,
	III,
	IV,
	V,
}

enum SpellType {
	ENHANCE,
	SUMMON,
	DAMAGE,
	SUPPORT,
	DISRUPTION,
}

enum SpellTriggerKind {
	UNASSIGNED,
	INSTANT,
	CONDITIONAL,
	PREPARED,
}

enum ResourceType {
	MINERAL,
	PLANT,
	RELIC,
	FOOD,
}

enum EquipmentType {
	RANGED_WEAPON,
	MELEE_WEAPON,
	ARMOR,
	ACCESSORY,
	FOCUS,
	CONSUMABLE,
}

const MAXIMUM_BASE_VALUE: int = 99 # 卡面基础行动数值上限；牌型倍率后的最终结果不受此上限限制
const MINIMUM_COOLDOWN_SECONDS: float = 0.5 # 卡牌可配置的最低基础冷却秒数
const MAXIMUM_COOLDOWN_SECONDS: float = 9.9 # 卡牌可配置及显示的最高基础冷却秒数
const MAXIMUM_HEALTH: int = 999 # 最大生命与战斗当前生命的统一上限
const MAXIMUM_ARMOR: int = 999 # 初始护甲与战斗临时护甲的统一上限

## 基础规则字段：由 .tres 卡牌资源编辑，运行时 UI 只读取。
@export var id: StringName = &"" # 卡牌数据的稳定标识，不使用显示名称代替
@export var display_name: String = "" # 卡面显示名称
@export var pack_id: StringName = &"" # 所属卡包稳定标识；开发测试卡使用独立标识，避免混入正式卡池
@export var faction: CardFaction.Id = CardFaction.Id.UNALIGNED # 卡牌显式阵营；未设置时继承所属卡包阵营
@export var is_available: bool = true # 是否进入当前可用卡池；停用卡仍可保留资源与美术
@export var effect_ids: Array[StringName] = [] # 绑定到通用效果目录的原子效果 ID
@export var keywords: Array[StringName] = [] # 卡牌关键词；由对应权威规则读取，不在这里直接运行战斗结算
@export var deferred_effect_hooks: Dictionary = {} # 尚未实现系统的严格后续钩子；运行时不得提前触发
@export var is_derived: bool = false # 是否为战斗衍生卡；死亡触发与奖励池会读取
@export var card_type: CardType = CardType.MINION # 卡牌大类，当前 Demo 主要使用随从
@export var action_type: ActionType = ActionType.MELEE # 行动图标与行动方式
@export_range(-1, 4, 1) var preferred_target_action_type: int = -1 # 普通攻击明确优先寻找的敌方行动类型；-1 表示没有额外目标偏好
@export_range(0, MAXIMUM_BASE_VALUE, 1) var base_value: int = 1: # 行动的基础数值
	set(value):
		base_value = clampi(value, 0, MAXIMUM_BASE_VALUE)
@export_range(MINIMUM_COOLDOWN_SECONDS, MAXIMUM_COOLDOWN_SECONDS, 0.1) var cooldown_seconds: float = 3.0: # 自动战斗中的行动冷却秒数
	set(value):
		cooldown_seconds = clampf(
			value,
			MINIMUM_COOLDOWN_SECONDS,
			MAXIMUM_COOLDOWN_SECONDS
		)
@export_range(0, MAXIMUM_HEALTH, 1) var max_health: int = 10: # 最大生命值
	set(value):
		max_health = clampi(value, 0, MAXIMUM_HEALTH)
@export_range(0, MAXIMUM_ARMOR, 1) var armor: int = 0: # 初始护甲值
	set(value):
		armor = clampi(value, 0, MAXIMUM_ARMOR)
@export var runes: Array[ElementType] = [] # 卡面三个符文槽从左到右的元素
@export var race_type: RaceType = RaceType.HUMAN # 种族图标与种族规则来源
@export var rarity: Rarity = Rarity.I # 卡框、种族图标配色与稀有度显示
@export var spell_type: SpellType = SpellType.ENHANCE # 法术中央类型图标与搜索名称
@export var spell_trigger_kind: SpellTriggerKind = SpellTriggerKind.UNASSIGNED # 法术启动类别；旧占位卡待确认后再分配
@export var equipment_type: EquipmentType = EquipmentType.RANGED_WEAPON # 装备中央类型图标与搜索名称
@export var resource_type: ResourceType = ResourceType.MINERAL # 资源卡立绘下部的种类图标
@export_range(-99, 99, 1) var equipment_action_delta: int = 0 # 装备对基础行动数值的临时占位变化量
@export_range(-99, 99, 1) var equipment_zeal_delta: int = 0 # 装备提供的带正负号热诚层数；每层按现有战斗规则改变5%冷却速度
@export_range(0, 99, 1) var equipment_health_delta: int = 0 # 装备对生命值的临时占位加成
@export_range(0, 99, 1) var equipment_armor_delta: int = 0 # 装备对护甲值的临时占位加成
@export_range(0, 99, 1) var wound_slot_count: int = 0 # 共享定义只保存槽位数量；实际伤势属于OwnedCard实例
@export_range(0, 99, 1) var emblem_slot_count: int = 0 # 共享定义只保存槽位数量；实际纹章属于OwnedCard实例

## 卡面美术字段：人物偏移只改变取景，不改变 99×136 卡牌逻辑尺寸。
@export var background_texture: Texture2D # 立绘透明区域下方的临时背景
@export var art_texture: Texture2D # 卡牌人物立绘
@export var art_normal_texture: Texture2D # 可选立绘法线贴图；为空时预览仍保留 3D 与整卡扫光
@export var art_offset: Vector2i = Vector2i.ZERO # 立绘在裁切窗口内的像素偏移
@export_multiline var effect_text: String = "" # 右键切换后显示的效果说明


func get_action_type_name() -> String:
	# 枚举到中文的转换集中在数据层，避免每个 UI 重复维护同一张表。
	return get_action_type_name_for(action_type)


func has_keyword(keyword: StringName) -> bool:
	# 关键词判断集中在卡牌数据层，避免编队、战斗和 UI 各自比较不同字符串。
	return keywords.has(keyword)


static func get_action_type_name_for(value: ActionType) -> String:
	match value:
		ActionType.MELEE:
			return "近战"
		ActionType.RANGED:
			return "远程"
		ActionType.MAGIC:
			return "法术"
		ActionType.HEAL:
			return "治疗"
		ActionType.DEFENSE:
			return "防御"
		_:
			return "未知"


func get_card_type_name() -> String:
	return ["随从", "装备", "法术", "资源"][card_type]


func get_spell_type_name() -> String:
	return ["强化", "召唤", "伤害", "支援", "干扰"][spell_type]


func get_spell_preparation_column() -> int:
	# 逻辑列序是准备栏从左到右：即时、条件、准备；与原素材列序不同。
	match spell_trigger_kind:
		SpellTriggerKind.INSTANT:
			return 0
		SpellTriggerKind.CONDITIONAL:
			return 1
		SpellTriggerKind.PREPARED:
			return 2
		_:
			return -1


func get_equipment_type_name() -> String:
	return ["远程武器", "近战武器", "防具", "饰品", "法器", "消耗品"][equipment_type]


func get_resource_type_name() -> String:
	return ["矿物", "植物", "遗物", "食物"][resource_type]


func get_effective_faction() -> CardFaction.Id:
	return (
		faction
		if faction != CardFaction.Id.UNALIGNED
		else CardPackRegistryScript.get_faction(pack_id)
	)


func get_faction_name() -> String:
	return CardFactionScript.get_display_name(get_effective_faction())


func get_base_target_priority() -> int:
	# 受击权重只由行动方式决定，避免卡牌资源与规则表形成双重权威。
	return get_base_target_priority_for_action(action_type)


static func get_base_target_priority_for_action(value: ActionType) -> int:
	match value:
		ActionType.MELEE:
			return 4
		ActionType.RANGED:
			return 2
		ActionType.MAGIC:
			return 3
		ActionType.HEAL:
			return 1
		ActionType.DEFENSE:
			return 5
		_:
			return 1


func get_element_type_name(element_type: ElementType) -> String:
	match element_type:
		ElementType.FIRE:
			return "火"
		ElementType.WATER:
			return "水"
		ElementType.WOOD:
			return "木"
		ElementType.LIGHT:
			return "光"
		ElementType.DARK:
			return "暗"
		_:
			return "未知"


func get_race_asset_key() -> String:
	# 数组顺序必须与 RaceType 枚举一致；键名用于拼接资源路径。
	return [
		"human",
		"elf",
		"dwarf",
		"construct",
		"elemental",
		"undead",
		"demon",
		"beast",
		"plant",
	][race_type]


func get_rarity_asset_key() -> String:
	# 数组顺序必须与 Rarity 枚举一致。
	return ["i", "ii", "iii", "iv", "v"][rarity]


func get_race_name() -> String:
	return [
		"人类",
		"精灵",
		"矮人",
		"造物",
		"元素",
		"亡灵",
		"魔族",
		"野兽",
		"植物",
	][race_type]


func get_rarity_name() -> String:
	return ["I", "II", "III", "IV", "V"][rarity]
