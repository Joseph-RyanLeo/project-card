extends RefCounted

## 只解析事件条件和抽取结果，不直接改金币、收藏或存档。
## 奖励由协调器放入原有事务，保存失败时能整体回退。
const CONFIG_PATH := "res://data/demo2/story_events.json"
const GENERAL_CONFIG_PATH := "res://data/events/general_story_events.json"
const TWISTED_VEIN_CONFIG_PATH := "res://data/events/twisted_vein_story_events.json"
var config: Dictionary = {}


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


func option_is_visible(event: Dictionary, option: Dictionary) -> bool:
	# 赌坊保留完整配置供旧档和原始概率校验，缺少依赖的分支在牌面隐藏。
	return event.path_id != "strange_casino" or not option.has("unavailable_reason")


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


func draw_outcome(option: Dictionary, rng: RandomNumberGenerator, dice_bonus: int = 0) -> Dictionary:
	var outcomes: Array = option.outcomes
	if option.has("roll_sides"):
		var roll := mini(rng.randi_range(1, _roll_max(option)) + dice_bonus, _roll_max(option))
		for index: int in outcomes.size():
			if _accepts_roll(outcomes[index], roll):
				return {"outcome_index": index, "roll": roll}
		return {}
	if outcomes.size() == 1:
		return {"outcome_index": 0}
	var total := 0.0
	for outcome: Dictionary in outcomes:
		total += float(outcome.get("weight", outcome.get("source_probability", 0)))
	var ticket := rng.randf() * total
	for index: int in outcomes.size():
		ticket -= float(outcomes[index].get("weight", outcomes[index].get("source_probability", 0)))
		if ticket < 0.0:
			return {"outcome_index": index}
	return {"outcome_index": outcomes.size() - 1}


func valid_result(event: Dictionary, result: Dictionary) -> bool:
	var option_index := int(result.get("option_index", -1))
	if option_index < 0 or option_index >= event.options.size():
		return false
	var option := runtime_option(event, option_index)
	var outcome_index := int(result.get("outcome_index", -1))
	if option.has("unavailable_reason") or outcome_index < 0 or outcome_index >= option.outcomes.size():
		return false
	if not option.has("roll_sides"): return true
	var value: Variant = result.get("roll")
	if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value)) != float(value): return false
	var roll := int(value)
	return roll >= 1 and roll <= _roll_max(option) and _accepts_roll(option.outcomes[outcome_index], roll)


func _roll_max(option: Dictionary) -> int:
	return clampi(int(option.get("roll_max", option.roll_sides)), 1, int(option.roll_sides))


func _accepts_roll(outcome: Dictionary, roll: int) -> bool:
	# JSON数组中的数值是float；逐项转int，避免Array.has把6和6.0视为不同值。
	for value: Variant in outcome.roll_values:
		if int(value) == roll:
			return true
	return false
