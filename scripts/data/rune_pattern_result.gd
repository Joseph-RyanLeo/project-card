class_name RunePatternResult
extends RefCounted

enum PatternType {
	CHAOS,
	PAIR,
	THREE_OF_A_KIND,
	TWO_PAIR,
	SAME_ELEMENT_TWO_PAIR,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	FIVE_OF_A_KIND,
	STRAIGHT,
}

var pattern_type: PatternType = PatternType.CHAOS
var visible_runes: Array[CardData.ElementType] = []
var element_counts: Dictionary = {}
var participating_indices: Array[int] = []


func get_pattern_name() -> String:
	match pattern_type:
		PatternType.FIVE_OF_A_KIND:
			return "五条"
		PatternType.FOUR_OF_A_KIND:
			return "四条"
		PatternType.FULL_HOUSE:
			return "葫芦"
		PatternType.SAME_ELEMENT_TWO_PAIR:
			return "同花两对"
		PatternType.TWO_PAIR:
			return "两对"
		PatternType.THREE_OF_A_KIND:
			return "三条"
		PatternType.PAIR:
			return "对子"
		PatternType.STRAIGHT:
			return "顺子"
		_:
			return "混乱"


func get_element_count(element_type: CardData.ElementType) -> int:
	return int(element_counts.get(element_type, 0))


func is_rune_participating(visible_index: int) -> bool:
	return participating_indices.has(visible_index)
