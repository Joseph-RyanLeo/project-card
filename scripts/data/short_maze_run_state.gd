class_name ShortMazeRunState
extends RefCounted

## D2-8 已确认的第一层八天流程。Main负责实际奖励、商店和战斗，
## 本类只保存推进状态，不能由动画回调替代正式事务调用。
enum Step { DAY_START, CHOOSING, EVENT, BATTLE_PREPARE, BATTLE_ACTIVE, BATTLE_RESULT, ENDED }

const DAYS: int = 8 # 短路线固定为第一层八天，第八天日末为Boss
const ROUND_KINDS: Array[String] = ["free_event", "paid_event", "shop", "battle"]
const INITIAL_FAILURE_PROTECTION: int = 2 # 前两次普通失败可继续，第三次结束

var day: int = 1
var round_index: int = 0
var step: Step = Step.DAY_START
var failure_protection: int = INITIAL_FAILURE_PROTECTION
var paths: Array[Dictionary] = []
var selected_path: Dictionary = {}
var battle_results: Array[Dictionary] = []
var claimed_pack_days: Array[int] = []
var rng := RandomNumberGenerator.new()


func initialize(seed_value: int) -> void:
	day = 1
	round_index = 0
	step = Step.DAY_START
	failure_protection = INITIAL_FAILURE_PROTECTION
	paths.clear()
	selected_path.clear()
	battle_results.clear()
	claimed_pack_days.clear()
	rng.seed = seed_value


func commit_day_start() -> bool:
	if step != Step.DAY_START:
		return false
	step = Step.CHOOSING
	return true


func get_round_kind() -> String:
	return ROUND_KINDS[round_index]


func is_boss_day() -> bool:
	return day == DAYS


func set_paths(candidates: Array[Dictionary]) -> bool:
	if step != Step.CHOOSING or not paths.is_empty() or candidates.size() != 3:
		return false
	var seen_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		if not _valid_path(candidate, get_round_kind()):
			return false
		var path_id: String = candidate.path_id
		if path_id in seen_ids:
			return false
		seen_ids.append(path_id)
	paths.assign(candidates.duplicate(true))
	return true


func select_path(path_id: String) -> bool:
	if step != Step.CHOOSING or paths.size() != 3:
		return false
	for candidate: Dictionary in paths:
		if candidate.path_id != path_id:
			continue
		selected_path = candidate.duplicate(true)
		paths.clear()
		step = Step.BATTLE_PREPARE if round_index == 3 else Step.EVENT
		return true
	return false


func get_pending_start_packs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if step != Step.EVENT or round_index != 0 or day in claimed_pack_days:
		return result
	if day in [2, 3]:
		result.append({"pack_id": "ash_ledger", "size": "large"})
	if day == 3:
		result.append({"pack_id": "ash_ledger", "size": "small"})
	return result


func commit_start_packs() -> bool:
	if get_pending_start_packs().is_empty():
		return false
	claimed_pack_days.append(day)
	return true


func complete_event() -> bool:
	if step != Step.EVENT:
		return false
	# 指定日首事件的礼包未提交时，不能离开，以免丢失奖励。
	if round_index == 0 and day in [2, 3] and day not in claimed_pack_days:
		return false
	round_index += 1
	selected_path.clear()
	step = Step.CHOOSING
	return true


func start_battle() -> bool:
	if step != Step.BATTLE_PREPARE:
		return false
	step = Step.BATTLE_ACTIVE
	return true


func settle_battle(won: bool) -> bool:
	if step != Step.BATTLE_ACTIVE:
		return false
	var ending := ""
	if is_boss_day():
		ending = "cleared" if won else "boss_loss"
		if not won:
			failure_protection = 0
	elif not won:
		if failure_protection == 0:
			ending = "ordinary_loss"
		else:
			failure_protection -= 1
	battle_results.append({"day": day, "won": won, "ending": ending})
	step = Step.BATTLE_RESULT
	return true


func continue_after_battle() -> bool:
	if step != Step.BATTLE_RESULT:
		return false
	if not String(battle_results.back().ending).is_empty():
		step = Step.ENDED
	else:
		day += 1
		round_index = 0
		selected_path.clear()
		step = Step.DAY_START
	return true


func capture_state() -> Dictionary:
	return {
		"state_version": 2,
		"day": day,
		"round_index": round_index,
		# 战斗中存档与读档都回到本场准备，保留已选敌人和随机流。
		"step": int(Step.BATTLE_PREPARE if step == Step.BATTLE_ACTIVE else step),
		"failure_protection": failure_protection,
		"paths": paths.duplicate(true),
		"selected_path": selected_path.duplicate(true),
		"battle_results": battle_results.duplicate(true),
		"claimed_pack_days": claimed_pack_days.duplicate(),
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
	}


func restore_state(snapshot: Dictionary) -> bool:
	if int(snapshot.get("state_version", 0)) == 1:
		snapshot = snapshot.duplicate(true)
		var old_round := int(snapshot.get("round_index", -1))
		if old_round not in range(4):
			return false
		# 日初尚未进入旧商店，应直接开始新版随机事件；进行中的路径按种类对齐。
		snapshot["round_index"] = 0 if int(snapshot.get("step", -1)) == Step.DAY_START else [2, 0, 1, 3][old_round]
		snapshot["state_version"] = 2
	if not _valid_snapshot(snapshot):
		return false
	day = int(snapshot.day)
	round_index = int(snapshot.round_index)
	step = int(snapshot.step) as Step
	failure_protection = int(snapshot.failure_protection)
	paths.assign((snapshot.paths as Array).duplicate(true))
	selected_path = (snapshot.selected_path as Dictionary).duplicate(true)
	battle_results.assign((snapshot.battle_results as Array).duplicate(true))
	claimed_pack_days.assign(snapshot.claimed_pack_days)
	rng.seed = int(snapshot.rng_seed)
	rng.state = int(snapshot.rng_state)
	return true


func _valid_snapshot(snapshot: Dictionary) -> bool:
	for key: String in ["state_version", "day", "round_index", "step", "failure_protection"]:
		if not _whole_number(snapshot.get(key)):
			return false
	var saved_day := int(snapshot.day)
	var saved_round := int(snapshot.round_index)
	var saved_step := int(snapshot.step)
	if int(snapshot.state_version) != 2 or saved_day < 1 or saved_day > DAYS or saved_round < 0 or saved_round > 3:
		return false
	if saved_step < Step.DAY_START or saved_step > Step.ENDED or saved_step == Step.BATTLE_ACTIVE:
		return false
	for key: String in ["paths", "battle_results", "claimed_pack_days"]:
		if not snapshot.get(key) is Array:
			return false
	if not snapshot.get("selected_path") is Dictionary or not _json_value(snapshot):
		return false
	for key: String in ["rng_seed", "rng_state"]:
		var value: Variant = snapshot.get(key)
		if not value is String or not value.is_valid_int():
			return false
	if int(snapshot.rng_state) == 0:
		return false
	var saved_paths: Array = snapshot.paths
	var saved_selected: Dictionary = snapshot.selected_path
	if saved_step == Step.CHOOSING:
		if not saved_selected.is_empty() or saved_paths.size() not in [0, 3]:
			return false
		var seen_ids: Array[String] = []
		for path: Variant in saved_paths:
			if not path is Dictionary or not _valid_path(path, ROUND_KINDS[saved_round]):
				return false
			if path.path_id in seen_ids:
				return false
			seen_ids.append(path.path_id)
	elif saved_step == Step.DAY_START:
		if saved_round != 0 or not saved_paths.is_empty() or not saved_selected.is_empty():
			return false
	else:
		if not saved_paths.is_empty() or not _valid_path(saved_selected, ROUND_KINDS[saved_round]):
			return false
		if (saved_step == Step.EVENT) != (saved_round < 3):
			return false
	var saved_results: Array = snapshot.battle_results
	var after_battle := saved_step in [Step.BATTLE_RESULT, Step.ENDED]
	if saved_results.size() != (saved_day if after_battle else saved_day - 1):
		return false
	var expected_protection := INITIAL_FAILURE_PROTECTION
	var expected_ending := ""
	for index: int in saved_results.size():
		var result: Variant = saved_results[index]
		if not result is Dictionary or not _whole_number(result.get("day")) or int(result.day) != index + 1:
			return false
		if not result.get("won") is bool or not result.get("ending") is String or not expected_ending.is_empty():
			return false
		if index + 1 == DAYS:
			expected_ending = "cleared" if result.won else "boss_loss"
			if not result.won:
				expected_protection = 0
		elif not result.won:
			if expected_protection == 0:
				expected_ending = "ordinary_loss"
			else:
				expected_protection -= 1
		if result.ending != expected_ending:
			return false
	if int(snapshot.failure_protection) != expected_protection:
		return false
	if not expected_ending.is_empty() and not after_battle:
		return false
	if saved_step == Step.ENDED and expected_ending.is_empty():
		return false
	var seen_days: Array[int] = []
	for claimed_day: Variant in snapshot.claimed_pack_days:
		if not _whole_number(claimed_day) or int(claimed_day) not in [2, 3] or int(claimed_day) > saved_day or int(claimed_day) in seen_days:
			return false
		if int(claimed_day) == saved_day and saved_round == 0 and saved_step in [Step.DAY_START, Step.CHOOSING]:
			return false
		seen_days.append(int(claimed_day))
	for reward_day: int in [2, 3]:
		if (saved_day > reward_day or (saved_day == reward_day and saved_round > 0)) and reward_day not in seen_days:
			return false
	return true


func _valid_path(path: Dictionary, kind: String) -> bool:
	return path.get("path_id") is String and not String(path.path_id).is_empty() and path.get("kind") == kind and path.get("hint") is String and not String(path.hint).is_empty() and _json_value(path)


func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func _json_value(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not _json_value(item):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key]):
				return false
		return true
	return false
