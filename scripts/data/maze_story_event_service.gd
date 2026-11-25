extends RefCounted

## 只解析事件条件和抽取结果，不直接改金币、收藏或存档。
## 奖励由协调器放入原有事务，保存失败时能整体回退。
const CONFIG_PATH := "res://data/demo2/story_events.json"
const GENERAL_CONFIG_PATH := "res://data/events/general_story_events.json"
const TWISTED_VEIN_CONFIG_PATH := "res://data/events/twisted_vein_story_events.json"
const PREVIOUS_OPTIONS_PATH := "res://data/events/story_options_before_batch_2.json"
const PROBABILITY_TIERS := ["极小概率", "小概率", "中概率", "高概率", "极大概率"]
var config: Dictionary = {}
var _previous_options: Dictionary = {}


func load_config() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or not parsed.get("events") is Array:
		return false
	config = parsed
	config["activated_options"] = {}
	config["encounters"] = {}
	for path: String in [GENERAL_CONFIG_PATH, TWISTED_VEIN_CONFIG_PATH]:
		var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not extra is Dictionary or not extra.get("events") is Array or not extra.get("appearance") is Dictionary:
			return false
		config.appearance.merge(extra.appearance)
		config.events.append_array(extra.events)
		config.activated_options.merge(extra.get("activated_options", {}))
		config.encounters.merge(extra.get("encounters", {}))
	var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREVIOUS_OPTIONS_PATH))
	if not previous is Dictionary: return false
	_previous_options = previous
	return true


func can_appear(event: Dictionary, gold: int, floor_number: int, hero_id: String) -> bool:
	var conditions: Dictionary = config.appearance.get(event.path_id, {})
	return (not conditions.get("pending", false) and gold >= int(conditions.get("minimum_gold", 0))
		and (conditions.get("floors", []) as Array).any(func(value: Variant) -> bool: return int(value) == floor_number)
		and hero_id != conditions.get("excluded_hero", ""))


func is_formal_event(event: Dictionary) -> bool:
	return bool(config.appearance.get(event.path_id, {}).get("formal", false))


func required_pack(event: Dictionary) -> String:
	return String(config.appearance.get(event.path_id, {}).get("pack", ""))


func matches_saved_options(definition: Dictionary, saved: Variant) -> bool:
	if saved == definition.options: return true
	var previous: Dictionary = _previous_options.get(definition.path_id, {})
	if previous.is_empty(): return false
	# 已发出的事件沿用完整旧快照，包含原奖励、选项顺序和该次掷骰规则。
	var legacy: Array = definition.options.duplicate()
	for index: String in previous:
		legacy[int(index)] = previous[index]
	return saved == legacy


func runtime_option(event: Dictionary, index: int) -> Dictionary:
	var option: Dictionary = event.options[index]
	var outcomes: Dictionary = config.get("activated_options", {}).get(event.path_id, {}).get(str(index), {})
	if outcomes.is_empty(): return option
	# 老存档保留原选项与概率快照。新实现补齐动作时沿用原索引。
	option = option.duplicate(true)
	option.erase("unavailable_reason")
	for outcome_index: String in outcomes:
		option.outcomes[int(outcome_index)]["effects"] = outcomes[outcome_index]
	return option


func event_encounter(event_id: String, floor_number: int, enemy_first: bool) -> Dictionary:
	var encounter: Dictionary = config.encounters.get(event_id, {}).get(str(floor_number), {}).duplicate(true)
	if not encounter.is_empty(): encounter["enemy_first"] = enemy_first
	return encounter


func blocked_reason(option: Dictionary, gold: int) -> String:
	var unavailable := String(option.get("unavailable_reason", ""))
	if not unavailable.is_empty():
		return unavailable
	var cost := int(option.get("cost", 0))
	return "需要%d金币（当前%d）" % [cost, gold] if gold < cost else ""


func draw_outcome(option: Dictionary, rng: RandomNumberGenerator, dice_bonus: int = 0, forced_roll: int = 0) -> Dictionary:
	var outcomes: Array = option.outcomes
	if option.has("roll_sides"):
		var roll_limit := _roll_max(option)
		var roll := _adjust_roll(rng.randi_range(1, roll_limit), dice_bonus, roll_limit) if forced_roll == 0 else forced_roll
		if roll < 1 or roll > roll_limit: return {}
		var index := _rolled_outcome(outcomes, roll)
		return {"outcome_index": index, "roll": roll} if index >= 0 else {}
	if outcomes.size() == 1:
		return {"outcome_index": 0}
	var ticket := rng.randf() * _total_weight(outcomes)
	for index: int in outcomes.size():
		ticket -= _weight(outcomes[index])
		if ticket < 0.0:
			return {"outcome_index": index}
	return {"outcome_index": outcomes.size() - 1}


func outcome_probabilities(option: Dictionary, dice_bonus: int = 0, guaranteed: bool = false) -> Array[float]:
	var outcomes: Array = option.outcomes
	var probabilities: Array[float] = []
	probabilities.resize(outcomes.size())
	probabilities.fill(0.0)
	if outcomes.is_empty(): return probabilities
	if guaranteed:
		probabilities[0] = 1.0
	elif option.has("roll_sides"):
		var limit := _roll_max(option)
		for face: int in range(1, limit + 1):
			var index := _rolled_outcome(outcomes, _adjust_roll(face, dice_bonus, limit))
			if index >= 0: probabilities[index] += 1.0
		for index: int in probabilities.size():
			probabilities[index] /= limit
	elif outcomes.size() == 1:
		probabilities[0] = 1.0
	else:
		var total := _total_weight(outcomes)
		if total > 0.0:
			for index: int in outcomes.size():
				probabilities[index] = _weight(outcomes[index]) / total
		else:
			probabilities[-1] = 1.0
	return probabilities


func probability_tier(probability: float) -> String:
	if probability >= 1.0: return "必定"
	return PROBABILITY_TIERS[clampi(floori(probability * 5.0), 0, PROBABILITY_TIERS.size() - 1)]


func outcome_discovery_key(event: Dictionary, option_index: int, outcome_index: int) -> String:
	var id := String(event.path_id)
	if event.get("tutorial", false):
		id = id.left(id.rfind("_")) if id.get_slice("_", id.get_slice_count("_") - 1) in ["0", "1", "2"] else id
		if id == "tutorial_fortuna": id = "fortuna_gift"
	return "%s:%d:%d" % [id, option_index, outcome_index]


func _total_weight(outcomes: Array) -> float:
	var total := 0.0
	for outcome: Dictionary in outcomes:
		total += _weight(outcome)
	return total


func _weight(outcome: Dictionary) -> float:
	return float(outcome.get("weight", outcome.get("source_probability", 0)))


func _adjust_roll(roll: int, bonus: int, limit: int) -> int:
	return mini(roll + bonus, limit)


func _rolled_outcome(outcomes: Array, roll: int) -> int:
	for index: int in outcomes.size():
		if _accepts_roll(outcomes[index], roll): return index
	return -1


func valid_result(event: Dictionary, result: Dictionary) -> bool:
	var awarded: Variant = result.get("gold_awarded", 0)
	if not (awarded is int or awarded is float) or not is_finite(float(awarded)) or awarded < 0 or floorf(float(awarded)) != float(awarded): return false
	var option_index := int(result.get("option_index", -1))
	if option_index < 0 or option_index >= event.options.size():
		return false
	var option := runtime_option(event, option_index)
	var outcome_index := int(result.get("outcome_index", -1))
	if option.has("unavailable_reason") or outcome_index < 0 or outcome_index >= option.outcomes.size():
		return false
	if option.has("sculptors"):
		var sculptor: Variant = result.get("sculptor")
		if not sculptor is String or sculptor not in option.sculptors: return false
		var instance: Variant = result.get("sculptor_instance_id")
		if not instance is String or instance.is_empty(): return false
	if not option.has("roll_sides"): return true
	var value: Variant = result.get("roll")
	if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value)) != float(value): return false
	var roll := int(value)
	return roll >= 1 and roll <= _roll_max(option) and _rolled_outcome(option.outcomes, roll) == outcome_index


func _roll_max(option: Dictionary) -> int:
	return clampi(int(option.get("roll_max", option.roll_sides)), 1, int(option.roll_sides))


func _accepts_roll(outcome: Dictionary, roll: int) -> bool:
	# JSON数组中的数值是float；逐项转int，避免Array.has把6和6.0视为不同值。
	for value: Variant in outcome.roll_values:
		if int(value) == roll:
			return true
	return false
