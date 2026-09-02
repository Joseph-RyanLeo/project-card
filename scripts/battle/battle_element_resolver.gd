class_name BattleElementResolver
extends RefCounted

const BattleRules = preload("res://scripts/battle/battle_rules.gd")

## 把牌型结果解释为最多两个、按顺序执行的元素组。
## 这里只判定“哪些元素组生效”，不访问场景、不选择目标也不修改数值。


static func get_element_groups(pattern: RunePatternResult) -> Array[Dictionary]:
	if pattern == null:
		return []
	var runs := _build_runs(pattern.visible_runes)
	match pattern.pattern_type:
		RunePatternResult.PatternType.PAIR:
			return _first_runs_with_lengths(runs, [2])
		RunePatternResult.PatternType.THREE_OF_A_KIND:
			return _first_runs_with_lengths(runs, [3])
		RunePatternResult.PatternType.FOUR_OF_A_KIND:
			return _first_runs_with_lengths(runs, [4])
		RunePatternResult.PatternType.FIVE_OF_A_KIND:
			return _first_runs_with_lengths(runs, [5])
		RunePatternResult.PatternType.FULL_HOUSE:
			return _first_runs_with_lengths(runs, [3, 2])
		RunePatternResult.PatternType.TWO_PAIR:
			return _first_runs_with_lengths(runs, [2, 2])
		RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR:
			var groups := _first_runs_with_lengths(runs, [2])
			if not groups.is_empty():
				groups[0]["count"] = BattleRules.SAME_ELEMENT_TWO_PAIR_EFFECT_COUNT
			return groups
		_:
			return []


static func _build_runs(runes: Array[CardData.ElementType]) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for rune_index: int in runes.size():
		var element := runes[rune_index]
		if runs.is_empty() or int(runs[-1]["element"]) != int(element):
			runs.append({"element": element, "count": 1, "start": rune_index})
		else:
			runs[-1]["count"] = int(runs[-1]["count"]) + 1
	return runs


static func _first_runs_with_lengths(runs: Array[Dictionary], lengths: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Dictionary = {}
	for expected: int in lengths:
		for run_index: int in runs.size():
			if used.has(run_index) or int(runs[run_index]["count"]) != expected:
				continue
			var group := runs[run_index].duplicate()
			group["role"] = &"primary" if result.is_empty() else &"secondary"
			result.append(group)
			used[run_index] = true
			break
	return result
