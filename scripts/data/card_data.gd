class_name CardData
extends Resource

enum CardType {
	MINION,
	EQUIPMENT,
	SPELL,
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

@export var id: StringName = &""
@export var display_name: String = ""
@export var card_type: CardType = CardType.MINION
@export var action_type: ActionType = ActionType.MELEE
@export var base_value: int = 1
@export var cooldown_seconds: float = 3.0
@export var max_health: int = 10
@export var armor: int = 0
@export var target_priority: int = 1
@export var runes: Array[ElementType] = []
@export var race_type: RaceType = RaceType.HUMAN
@export var rarity: Rarity = Rarity.I
@export var background_texture: Texture2D
@export var art_texture: Texture2D
@export var art_offset: Vector2i = Vector2i.ZERO
@export_multiline var effect_text: String = ""


func get_action_type_name() -> String:
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


func get_rune_names() -> Array[String]:
	var names: Array[String] = []

	for rune: ElementType in runes:
		names.append(get_element_type_name(rune))

	return names


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
