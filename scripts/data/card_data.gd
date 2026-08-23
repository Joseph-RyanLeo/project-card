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

## 基础规则字段：由 .tres 卡牌资源编辑，运行时 UI 只读取。
@export var id: StringName = &"" # 卡牌数据的稳定标识，不使用显示名称代替
@export var display_name: String = "" # 卡面显示名称
@export var card_type: CardType = CardType.MINION # 卡牌大类，当前 Demo 主要使用随从
@export var action_type: ActionType = ActionType.MELEE # 行动图标与行动方式
@export var base_value: int = 1 # 行动的基础数值
@export var cooldown_seconds: float = 3.0 # 自动战斗中的行动冷却秒数
@export var max_health: int = 10 # 最大生命值
@export var armor: int = 0 # 初始护甲值
@export var target_priority: int = 1 # 未来自动战斗选择目标时的优先级
@export var runes: Array[ElementType] = [] # 卡面三个符文槽从左到右的元素
@export var race_type: RaceType = RaceType.HUMAN # 种族图标与种族规则来源
@export var rarity: Rarity = Rarity.I # 卡框、种族图标配色与稀有度显示

## 卡面美术字段：人物偏移只改变取景，不改变 99×136 卡牌逻辑尺寸。
@export var background_texture: Texture2D # 立绘透明区域下方的临时背景
@export var art_texture: Texture2D # 卡牌人物立绘
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
