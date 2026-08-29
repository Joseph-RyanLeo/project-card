@tool
class_name CardData
extends Resource

## 单张卡牌的可序列化配置资源。
## 这里只保存不会随战斗临时变化的基础资料；卡牌节点负责显示，
## 小队顺序和遮挡关系则由 SquadData 保存。

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
@export var card_type: CardType = CardType.MINION # 卡牌大类，当前 Demo 主要使用随从
@export var action_type: ActionType = ActionType.MELEE # 行动图标与行动方式
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
@export var equipment_type: EquipmentType = EquipmentType.RANGED_WEAPON # 装备中央类型图标与搜索名称
@export_range(-99, 99, 1) var equipment_action_delta: int = 0 # 装备对基础行动数值的临时占位变化量
@export_range(-9.9, 9.9, 0.1) var equipment_cooldown_delta: float = 0.0 # 装备对基础冷却秒数的临时占位变化量
@export_range(0, 99, 1) var equipment_health_delta: int = 0 # 装备对生命值的临时占位加成
@export_range(0, 99, 1) var equipment_armor_delta: int = 0 # 装备对护甲值的临时占位加成

## 卡面美术字段：人物偏移只改变取景，不改变 99×136 卡牌逻辑尺寸。
@export var background_texture: Texture2D # 立绘透明区域下方的临时背景
@export var art_texture: Texture2D # 卡牌人物立绘
@export var art_normal_texture: Texture2D # 可选立绘法线贴图；为空时预览仍保留 3D 与整卡扫光
@export var art_offset: Vector2i = Vector2i.ZERO # 立绘在裁切窗口内的像素偏移
@export_multiline var effect_text: String = "" # 右键切换后显示的效果说明


func get_action_type_name() -> String:
	# 枚举到中文的转换集中在数据层，避免每个 UI 重复维护同一张表。
	match action_type:
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


func get_equipment_type_name() -> String:
	return ["远程武器", "近战武器", "防具", "饰品", "法器", "消耗品"][equipment_type]


func get_base_target_priority() -> int:
	# 受击权重只由行动方式决定，避免卡牌资源与规则表形成双重权威。
	match action_type:
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
