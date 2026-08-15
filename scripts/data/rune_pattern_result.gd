class_name RunePatternResult
extends RefCounted

## 一次纯牌型识别的只读语义结果。
## 规则层创建它，SquadView 只消费它；显示节点不得回写或改判牌型。

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

var pattern_type: PatternType = PatternType.CHAOS # 最终命中的唯一牌型
var visible_runes: Array[CardData.ElementType] = [] # 识别时从左到右的真实可见符文
var element_counts: Dictionary = {} # 按元素统计的总数量，供显示和后续规则查询
var participating_indices: Array[int] = [] # 参与牌型的 visible_runes 下标


func get_pattern_name() -> String:
	# 名称映射集中保存，避免规则层和 UI 各自维护一份中文文案。
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
