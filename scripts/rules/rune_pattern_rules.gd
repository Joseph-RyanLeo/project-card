class_name RunePatternRules
extends RefCounted

## Demo 牌型的纯规则识别器。
## 输入只是一条从左到右的可见元素序列；这里不访问场景树、卡牌节点
## 或小队布局，因此规则可以独立测试，也不会被预览动画影响。

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
	# 先保留原始序列和总计数，再按连续区段与固定优先级选唯一牌型。
	var result := RunePatternResult.new()
	result.visible_runes.assign(visible_runes)
	for rune: CardData.ElementType in visible_runes:
		if int(rune) < 0:
			continue
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


static func identify_slots(slots: Array[Dictionary]) -> RunePatternResult:
	var runes: Array[CardData.ElementType] = []
	var wildcard := -1
	var candidates: Array[int] = []
	for index: int in slots.size():
		if bool(slots[index].get("hidden", false)):
			runes.append(-1 as CardData.ElementType)
			continue
		runes.append(int(slots[index].get("element", -1)) as CardData.ElementType)
		if String(slots[index].get("sticker_id", "")) == "万能贴纸":
			wildcard = index
		elif int(slots[index].get("element", -1)) >= 0 and not candidates.has(int(slots[index].element)):
			candidates.append(int(slots[index].element))
	for element: int in 5:
		if not candidates.has(element):
			candidates.append(element)
	var result := identify(runes)
	if wildcard >= 0:
		var best_score := -1
		# 相同牌型保留最左侧已出现元素；普通元素枚举仅补全未出现的候选。
		for element: int in candidates:
			runes[wildcard] = element as CardData.ElementType
			var candidate := identify(runes)
			var score := 1 if candidate.pattern_type == RunePatternResult.PatternType.STRAIGHT else int(candidate.pattern_type) * 2
			if score > best_score or (score == best_score and _is_leftmost(candidate.participating_indices, result.participating_indices)):
				best_score = score
				result = candidate
	return result


static func _is_leftmost(left: Array[int], right: Array[int]) -> bool:
	for index: int in mini(left.size(), right.size()):
		if left[index] != right[index]:
			return left[index] < right[index]
	return false


static func _build_consecutive_runs(
	visible_runes: Array[CardData.ElementType]
) -> Array[Dictionary]:
	# 把 AABAA 拆成 A×2、B×1、A×2；不同区段绝不跨越合并。
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
	# 只接受长度恰好相等的区段，四连不会同时充当三连。
	var matching_runs: Array[Dictionary] = []
	for run: Dictionary in runs:
		if int(run["element"]) >= 0 and int(run["length"]) == expected_length:
			matching_runs.append(run)
	return matching_runs


static func _has_same_element_two_pair(pair_runs: Array[Dictionary]) -> bool:
	return (
		pair_runs.size() >= 2
		and pair_runs[0]["element"] == pair_runs[1]["element"]
	)


static func _indices_for_runs(selected_runs: Array) -> Array[int]:
	# 高亮使用原序列下标，所以最终统一排序为从左到右。
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
	# 顺子必须正好五枚，并沿固定循环向前或向后连续移动一步。
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
