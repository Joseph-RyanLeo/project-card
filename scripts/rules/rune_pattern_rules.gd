class_name RunePatternRules
extends RefCounted

const STRAIGHT_CYCLE: Array[CardData.ElementType] = [
	CardData.ElementType.FIRE,
	CardData.ElementType.LIGHT,
	CardData.ElementType.DARK,
	CardData.ElementType.WATER,
	CardData.ElementType.WOOD,
] # 顺子的循环元素顺序；允许任意起点并可整体反向读取


static func identify(
	visible_runes: Array[CardData.ElementType]
) -> RunePatternResult:
	var result := RunePatternResult.new()
	result.visible_runes.assign(visible_runes)
	for rune: CardData.ElementType in visible_runes:
		result.element_counts[rune] = int(result.element_counts.get(rune, 0)) + 1

	var runs := _build_consecutive_runs(visible_runes)
	var five_runs := _find_runs_of_length(runs, 5)
	var four_runs := _find_runs_of_length(runs, 4)
	var three_runs := _find_runs_of_length(runs, 3)
	var pair_runs := _find_runs_of_length(runs, 2)

	# 相同元素被其他元素隔开后属于不同连续区段，绝不合并计数。
	# 这里继续严格按优先级选择，并把最终参与牌型的画面序号一并保存。
	if not five_runs.is_empty():
		result.pattern_type = RunePatternResult.PatternType.FIVE_OF_A_KIND
		result.participating_indices = _indices_for_runs([five_runs[0]])
	elif not four_runs.is_empty():
		result.pattern_type = RunePatternResult.PatternType.FOUR_OF_A_KIND
		result.participating_indices = _indices_for_runs([four_runs[0]])
	elif not three_runs.is_empty() and not pair_runs.is_empty():
		result.pattern_type = RunePatternResult.PatternType.FULL_HOUSE
		result.participating_indices = _indices_for_runs([
			three_runs[0], pair_runs[0]
		])
	elif _has_same_element_two_pair(pair_runs):
		result.pattern_type = (
			RunePatternResult.PatternType.SAME_ELEMENT_TWO_PAIR
		)
		result.participating_indices = _indices_for_runs([
			pair_runs[0], pair_runs[1]
		])
	elif pair_runs.size() >= 2:
		result.pattern_type = RunePatternResult.PatternType.TWO_PAIR
		result.participating_indices = _indices_for_runs([
			pair_runs[0], pair_runs[1]
		])
	elif not three_runs.is_empty():
		result.pattern_type = RunePatternResult.PatternType.THREE_OF_A_KIND
		result.participating_indices = _indices_for_runs([three_runs[0]])
	elif not pair_runs.is_empty():
		result.pattern_type = RunePatternResult.PatternType.PAIR
		result.participating_indices = _indices_for_runs([pair_runs[0]])
	elif _is_straight(visible_runes):
		# 顺子包含五种不同元素，只会与“混乱”重叠，因此在混乱前判断。
		result.pattern_type = RunePatternResult.PatternType.STRAIGHT
		result.participating_indices.assign(range(visible_runes.size()))
	else:
		result.pattern_type = RunePatternResult.PatternType.CHAOS
	return result


static func _build_consecutive_runs(
	visible_runes: Array[CardData.ElementType]
) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for rune_index: int in visible_runes.size():
		var rune := visible_runes[rune_index]
		if runs.is_empty() or runs[-1]["element"] != rune:
			runs.append({
				"element": rune,
				"start": rune_index,
				"length": 1,
			})
		else:
			runs[-1]["length"] = int(runs[-1]["length"]) + 1
	return runs


static func _find_runs_of_length(
	runs: Array[Dictionary], expected_length: int
) -> Array[Dictionary]:
	var matching_runs: Array[Dictionary] = []
	for run: Dictionary in runs:
		if int(run["length"]) == expected_length:
			matching_runs.append(run)
	return matching_runs


static func _has_same_element_two_pair(pair_runs: Array[Dictionary]) -> bool:
	return (
		pair_runs.size() >= 2
		and pair_runs[0]["element"] == pair_runs[1]["element"]
	)


static func _indices_for_runs(selected_runs: Array) -> Array[int]:
	var indices: Array[int] = []
	for run_value: Variant in selected_runs:
		var run := run_value as Dictionary
		var start := int(run["start"])
		var length := int(run["length"])
		for offset: int in length:
			indices.append(start + offset)
	indices.sort()
	return indices


static func _is_straight(
	visible_runes: Array[CardData.ElementType]
) -> bool:
	if visible_runes.size() != STRAIGHT_CYCLE.size():
		return false
	var first_cycle_index := STRAIGHT_CYCLE.find(visible_runes[0])
	var second_cycle_index := STRAIGHT_CYCLE.find(visible_runes[1])
	if first_cycle_index < 0 or second_cycle_index < 0:
		return false

	var direction: int = 0
	if second_cycle_index == (first_cycle_index + 1) % STRAIGHT_CYCLE.size():
		direction = 1
	elif second_cycle_index == (
		first_cycle_index - 1 + STRAIGHT_CYCLE.size()
	) % STRAIGHT_CYCLE.size():
		direction = -1
	else:
		return false

	for rune_index: int in range(2, visible_runes.size()):
		var expected_cycle_index := (
			first_cycle_index
			+ direction * rune_index
			+ STRAIGHT_CYCLE.size() * rune_index
		) % STRAIGHT_CYCLE.size()
		if visible_runes[rune_index] != STRAIGHT_CYCLE[expected_cycle_index]:
			return false
	return true
