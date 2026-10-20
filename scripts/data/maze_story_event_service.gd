extends RefCounted

## 只解析事件条件和抽取结果，不直接改金币、收藏或存档。
## 奖励由协调器放入原有事务，保存失败时能整体回退。
const CONFIG_PATH := "res://data/demo2/story_events.json"
var config: Dictionary = {}


func load_config() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or not parsed.get("events") is Array:
		return false
	config = parsed
	return true


func can_appear(event: Dictionary, gold: int, floor_number: int, hero_id: String) -> bool:
	if event.path_id == "strange_casino" and gold < 5:
		return false
	if bool(config.get("test_ignore_appearance_limits", false)):
		return true
	match String(event.path_id):
		"ioann_prayer": return floor_number == 3 and hero_id != "ioann_warden"
		"bone_tower": return floor_number == 2
	return floor_number in [1, 2, 3]


func blocked_reason(option: Dictionary, gold: int) -> String:
	var unavailable := String(option.get("unavailable_reason", ""))
	if not unavailable.is_empty():
		return unavailable
	var cost := int(option.get("cost", 0))
	return "需要%d金币（当前%d）" % [cost, gold] if gold < cost else ""


func draw_outcome(option: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var outcomes: Array = option.outcomes
	if option.has("roll_sides"):
		var roll := rng.randi_range(1, int(option.roll_sides))
		for index: int in outcomes.size():
			if _accepts_roll(outcomes[index], roll):
				return {"outcome_index": index, "roll": roll}
		return {}
	if outcomes.size() == 1:
		return {"outcome_index": 0}
	var total := 0.0
	for outcome: Dictionary in outcomes:
		total += float(outcome.weight)
	var ticket := rng.randf() * total
	for index: int in outcomes.size():
		ticket -= float(outcomes[index].weight)
		if ticket < 0.0:
			return {"outcome_index": index}
	return {"outcome_index": outcomes.size() - 1}


func valid_result(event: Dictionary, result: Dictionary) -> bool:
	var option_index := int(result.get("option_index", -1))
	if option_index < 0 or option_index >= event.options.size():
		return false
	var option: Dictionary = event.options[option_index]
	var outcome_index := int(result.get("outcome_index", -1))
	if option.has("unavailable_reason") or outcome_index < 0 or outcome_index >= option.outcomes.size():
		return false
	return not option.has("roll_sides") or _accepts_roll(option.outcomes[outcome_index], int(result.get("roll", 0)))


func _accepts_roll(outcome: Dictionary, roll: int) -> bool:
	# JSON数组中的数值是float；逐项转int，避免Array.has把6和6.0视为不同值。
	for value: Variant in outcome.roll_values:
		if int(value) == roll:
			return true
	return false
