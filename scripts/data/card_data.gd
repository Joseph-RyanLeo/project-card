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
