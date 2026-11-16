class_name ShortMazeRunState
extends RefCounted

## D2-8 已确认的第一层八天流程。Main负责实际奖励、商店和战斗，
## 本类只保存推进状态，不能由动画回调替代正式事务调用。
enum Step { DAY_START, CHOOSING, EVENT, BATTLE_PREPARE, BATTLE_ACTIVE, BATTLE_RESULT, ENDED }

const DAYS: int = 8 # 短路线固定为第一层八天，第八天日末为Boss
const ROUND_KINDS: Array[String] = ["free_event", "paid_event", "shop", "battle"]
const INITIAL_FAILURE_PROTECTION: int = 2 # 前两次普通失败可继续，第三次结束

var route_days: int = DAYS # 本局路线终点；教程4天，第一层8天
var daily_pack_rewards: bool = true # 仅兼容Demo2固定日期礼包，新D3局按任务开放
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
	return not is_event_battle() and (day % DAYS == 0 or day == route_days)


func is_event_battle() -> bool:
	return selected_path.has("event_battle")


func battle_path() -> Dictionary:
	return selected_path.get("event_battle", selected_path)


func prepare_event_battle(encounter: Dictionary) -> bool:
	if step != Step.EVENT or round_index >= 2 or is_event_battle(): return false
	selected_path["event_battle"] = encounter
	step = Step.BATTLE_PREPARE
	return true


func set_paths(candidates: Array[Dictionary]) -> bool:
	if step != Step.CHOOSING or not paths.is_empty() or candidates.size() != 3:
		return false
	var seen_paths := {}
	for candidate: Dictionary in candidates:
		if not _valid_path(candidate, get_round_kind()):
			return false
		var path_id: String = candidate.path_id
		# 事件不足时允许重复发同一定义，商店及战斗仍须是独立路径。
		if seen_paths.has(path_id) and (round_index >= 2 or seen_paths[path_id] != candidate):
			return false
		seen_paths[path_id] = candidate
	paths.assign(candidates.duplicate(true))
	return true


func select_path(path_id: String, index: int = -1) -> bool:
	if step != Step.CHOOSING or paths.size() != 3:
		return false
	if index < 0:
		index = paths.find_custom(func(candidate: Dictionary) -> bool: return candidate.path_id == path_id)
	if index < 0 or index >= paths.size() or paths[index].path_id != path_id:
		return false
	selected_path = paths[index].duplicate(true)
	paths.clear()
	step = Step.BATTLE_PREPARE if round_index == 3 else Step.EVENT
	return true


func get_pending_start_packs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not daily_pack_rewards or step != Step.EVENT or round_index != 0 or day in claimed_pack_days:
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
	if daily_pack_rewards and round_index == 0 and day in [2, 3] and day not in claimed_pack_days:
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
		ending = ("cleared" if day == route_days else "") if won else "boss_loss"
		if not won:
			failure_protection = 0
	elif not won:
		if failure_protection == 0:
			ending = "ordinary_loss"
		else:
			failure_protection -= 1
	var result := {"day": day, "won": won, "ending": ending}
	if is_event_battle():
		result["extra"] = true
		result["event_round"] = round_index
	battle_results.append(result)
	step = Step.BATTLE_RESULT
	return true


func continue_after_battle() -> bool:
	if step != Step.BATTLE_RESULT:
		return false
	if not String(battle_results.back().ending).is_empty():
		step = Step.ENDED
	elif is_event_battle():
		step = Step.EVENT
		return complete_event()
	else:
		day += 1
		round_index = 0
		selected_path.clear()
		step = Step.DAY_START
	return true


func capture_state() -> Dictionary:
	return {
		"state_version": 2,
		"route_days": route_days,
		"daily_pack_rewards": daily_pack_rewards,
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
	route_days = int(snapshot.get("route_days", DAYS))
	daily_pack_rewards = snapshot.get("daily_pack_rewards", true)
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
	var saved_limit: Variant = snapshot.get("route_days", DAYS)
	if not _whole_number(saved_limit) or int(saved_limit) not in [4, 8, 16] or not snapshot.get("daily_pack_rewards", true) is bool: return false
	var saved_day := int(snapshot.day)
	var saved_round := int(snapshot.round_index)
	var saved_step := int(snapshot.step)
	if int(snapshot.state_version) != 2 or saved_day < 1 or saved_day > int(saved_limit) or saved_round < 0 or saved_round > 3:
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
		var seen_paths := {}
		for path: Variant in saved_paths:
			if not path is Dictionary or not _valid_path(path, ROUND_KINDS[saved_round]):
				return false
			if seen_paths.has(path.path_id) and (saved_round >= 2 or seen_paths[path.path_id] != path):
				return false
			seen_paths[path.path_id] = path
	elif saved_step == Step.DAY_START:
		if saved_round != 0 or not saved_paths.is_empty() or not saved_selected.is_empty():
			return false
	else:
		if not saved_paths.is_empty() or not _valid_path(saved_selected, ROUND_KINDS[saved_round]):
			return false
		if (saved_step == Step.EVENT) != (saved_round < 3 and not saved_selected.has("event_battle")):
			return false
		if saved_selected.has("event_battle") and (saved_round >= 2 or not saved_selected.event_battle is Dictionary):
			return false
	var saved_results: Array = snapshot.battle_results
	var after_battle := saved_step in [Step.BATTLE_RESULT, Step.ENDED]
	var expected_daily := saved_day if after_battle and not saved_selected.has("event_battle") else saved_day - 1
	var completed_days := 0
	var last_extra_day := 0
	var last_extra_round := -1
	var expected_protection := INITIAL_FAILURE_PROTECTION
	var expected_ending := ""
	for index: int in saved_results.size():
		var result: Variant = saved_results[index]
		if not result is Dictionary or not _whole_number(result.get("day")) or int(result.day) != completed_days + 1:
			return false
		if not result.get("won") is bool or not result.get("ending") is String or not expected_ending.is_empty():
			return false
		var extra: Variant = result.get("extra", false)
		if not extra is bool: return false
		if extra:
			if int(result.day) > saved_day: return false
			var event_round: Variant = result.get("event_round", int(saved_round) if after_battle and index == saved_results.size() - 1 else 0)
			if not _whole_number(event_round) or int(event_round) not in [0, 1]: return false
			if int(result.day) == last_extra_day and int(event_round) <= last_extra_round: return false
			last_extra_day = int(result.day)
			last_extra_round = int(event_round)
		else:
			completed_days += 1
		if not extra and (completed_days % DAYS == 0 or completed_days == int(saved_limit)):
			expected_ending = ("cleared" if completed_days == int(saved_limit) else "") if result.won else "boss_loss"
			if not result.won:
				expected_protection = 0
		elif not result.won:
			if expected_protection == 0:
				expected_ending = "ordinary_loss"
			else:
				expected_protection -= 1
		if result.ending != expected_ending:
			return false
	if completed_days != expected_daily: return false
	if after_battle and (saved_results.is_empty() or bool(saved_results.back().get("extra", false)) != saved_selected.has("event_battle")):
		return false
	if last_extra_day == saved_day and saved_round <= last_extra_round and not (after_battle and saved_selected.has("event_battle") and saved_round == last_extra_round):
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
		if snapshot.get("daily_pack_rewards", true) and (saved_day > reward_day or (saved_day == reward_day and saved_round > 0)) and reward_day not in seen_days:
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
