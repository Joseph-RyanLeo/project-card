class_name BattleFormulaData
extends RefCounted

## 单个战斗数值的可检查公式快照。
## 它保存结算当时的输入，不回读后来变化的卡牌或小队状态。

var display_name: String = ""
var exact_result: float = 0.0
var action_type: CardData.ActionType = CardData.ActionType.MELEE
var base_value: float = 0.0
var additive_terms: Array[Dictionary] = []
var pattern_multiplier: float = 1.0
var element_multiplier: float = 1.0
var other_multipliers: Array[Dictionary] = []
var final_flat_bonus: float = 0.0
var source: BattleSquadState
var target: BattleSquadState
var fractional_remainder: float = 0.0


static func create(
	value_name: String,
	mode: CardData.ActionType,
	base: float,
	pattern: float,
	element: float,
	source_state: BattleSquadState,
	target_state: BattleSquadState,
	other: Array[Dictionary] = [],
	additions: Array[Dictionary] = [],
	flat_bonus: float = 0.0
) -> BattleFormulaData:
	var formula := BattleFormulaData.new()
	formula.display_name = value_name
	formula.action_type = mode
	formula.base_value = base
	formula.pattern_multiplier = pattern
	formula.element_multiplier = element
	formula.source = source_state
	formula.target = target_state
	formula.other_multipliers.assign(other)
	formula.additive_terms.assign(additions)
	formula.final_flat_bonus = flat_bonus
	formula.exact_result = formula.calculate_result()
	return formula


func calculate_result() -> float:
	var additive_total := base_value
	for term: Dictionary in additive_terms:
		additive_total += float(term.get("value", 0.0))
	var result := additive_total * pattern_multiplier * element_multiplier
	for term: Dictionary in other_multipliers:
		result *= float(term.get("value", 1.0))
	return result + final_flat_bonus


func duplicate_for_target(target_state: BattleSquadState) -> BattleFormulaData:
	var copy := BattleFormulaData.create(
		display_name,
		action_type,
		base_value,
		pattern_multiplier,
		element_multiplier,
		source,
		target_state,
		other_multipliers,
		additive_terms,
		final_flat_bonus
	)
	copy.exact_result = exact_result
	copy.fractional_remainder = fractional_remainder
	return copy
