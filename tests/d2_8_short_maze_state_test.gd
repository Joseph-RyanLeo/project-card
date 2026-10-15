extends SceneTree

const MazeState = preload("res://scripts/data/short_maze_run_state.gd")
const SaveService = preload("res://scripts/data/run_save_service.gd")
const SAVE_PATH := "/private/tmp/project-card-d2-8-short-maze.json"
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _paths(kind: String) -> Array[Dictionary]:
	return [
		{"path_id": "test_a", "kind": kind, "hint": "测试暗示甲", "payload": {"enemy": ["militia"]}},
		{"path_id": "test_b", "kind": kind, "hint": "测试暗示乙"},
		{"path_id": "test_c", "kind": kind, "hint": "测试暗示丙"},
	]


func _to_battle(maze: MazeState) -> void:
	_expect(maze.commit_day_start(), "本日日初可提交")
	_expect(not maze.commit_day_start(), "重复日初拒绝提交")
	for kind: String in ["shop", "free_event", "paid_event"]:
		_expect(maze.get_round_kind() == kind, "前三轮顺序为商店、免费、付费事件")
		_expect(maze.set_paths(_paths(kind)), "生成三个合法候选")
		_expect(not maze.set_paths(_paths(kind)), "已有候选不能重新生成")
		_expect(maze.select_path("test_b") and not maze.select_path("test_a"), "确认选择后不能更换")
		if kind == "shop" and maze.day in [2, 3]:
			_expect(not maze.complete_event(), "指定日礼包未提交不能离开首事件")
			var packs: Array[Dictionary] = maze.get_pending_start_packs()
			_expect(packs.size() == (1 if maze.day == 2 else 2), "第二天一大包，第三天一大一小")
			_expect(packs[0] == {"pack_id": "ash_ledger", "size": "large"}, "礼包使用灰烬证册大包")
			if maze.day == 3:
				_expect(packs[1] == {"pack_id": "ash_ledger", "size": "small"}, "第三天额外小包")
			_expect(maze.commit_start_packs() and not maze.commit_start_packs(), "同日礼包只可提交一次")
		_expect(maze.complete_event() and not maze.complete_event(), "事件完成只推进一次")
	_expect(maze.get_round_kind() == "battle" and maze.set_paths(_paths("battle")), "第四轮固定战斗三选一")
	_expect(maze.select_path("test_a") and maze.start_battle(), "选择后才可开战")


func _run() -> void:
	var maze := MazeState.new()
	maze.initialize(18003)
	_expect(maze.day == 1 and maze.failure_protection == 2, "第一天开局有两次普通失败保护")
	_expect(not maze.select_path("test_a") and not maze.start_battle(), "日初前不能选路或开战")
	_expect(not maze.settle_battle(true), "没有战斗不能直接结算")
	_to_battle(maze)
	var interrupted := maze.capture_state()
	_expect(int(interrupted.step) == MazeState.Step.BATTLE_PREPARE, "未完成战斗的存档回到本场准备")
	var service := SaveService.new()
	_expect(service.save_checkpoint(SAVE_PATH, {"schema_version": SaveService.SCHEMA_VERSION, "short_maze": interrupted}) == OK, "真实磁盘保存战前路径状态")
	var loaded := service.load_checkpoint(SAVE_PATH)
	var restored := MazeState.new()
	_expect(bool(loaded.get("success", false)) and restored.restore_state(loaded.checkpoint.short_maze), "真实JSON读回状态")
	_expect(restored.capture_state() == interrupted, "候选选择、日轮、保护和随机流完整恢复")
	_expect(restored.rng.randi() == maze.rng.randi(), "读取后的随机流继续点一致")
	_expect(restored.start_battle() and restored.settle_battle(true), "读档后可重试原场并结算")
	_expect(not restored.settle_battle(true) and restored.day == 1, "重复结算拒绝，展示统计前不进入新天")
	_expect(restored.continue_after_battle() and restored.day == 2, "点击继续才进入第二天")
	var before := restored.capture_state()
	var damaged := before.duplicate(true)
	damaged.day = 8
	_expect(not restored.restore_state(damaged) and restored.capture_state() == before, "篡改天数拒绝且保留原状态")
	damaged = before.duplicate(true)
	damaged.failure_protection = 0
	_expect(not restored.restore_state(damaged), "保护次数必须与真实胜败记录一致")
	damaged = before.duplicate(true)
	damaged.rng_state = "not_a_number"
	_expect(not restored.restore_state(damaged), "无效随机流拒绝")
	_expect(restored.commit_day_start(), "第二天日初")
	var duplicate_paths := _paths("shop")
	duplicate_paths[2].path_id = duplicate_paths[0].path_id
	_expect(not restored.set_paths(duplicate_paths), "同轮具体路径不能重复")
	_expect(not restored.set_paths(_paths("free_event")), "商店轮不能混入其他类型")
	_expect(restored.set_paths(_paths("shop")) and restored.select_path("test_a"), "选择第二天商店")
	_expect(restored.commit_start_packs(), "第二天礼包一次提交")
	var claimed := restored.capture_state()
	var gift_restore := MazeState.new()
	_expect(gift_restore.restore_state(JSON.parse_string(JSON.stringify(claimed))), "礼包提交中途可恢复")
	_expect(gift_restore.get_pending_start_packs().is_empty() and not gift_restore.commit_start_packs(), "读档不能重复发第二天礼包")
	var failed := MazeState.new()
	failed.initialize(20003)
	for expected_day: int in range(1, 4):
		_to_battle(failed)
		_expect(failed.settle_battle(false), "普通失败正常结算")
		_expect(failed.failure_protection == maxi(2 - expected_day, 0), "普通失败依次扣保护，不扣成负数")
		_expect(failed.continue_after_battle(), "普通失败统计后继续")
		if expected_day < 3:
			_expect(failed.step == MazeState.Step.DAY_START and failed.day == expected_day + 1, "前两次失败均可继续")
	_expect(failed.step == MazeState.Step.ENDED and failed.battle_results.back().ending == "ordinary_loss", "第三次普通失败结束本局")
	_expect(not failed.commit_day_start() and not failed.continue_after_battle(), "结束后不能继续推进")
	_expect(MazeState.new().restore_state(JSON.parse_string(JSON.stringify(failed.capture_state()))), "普通失败结局可JSON恢复")
	for boss_won: bool in [true, false]:
		var full := MazeState.new()
		full.initialize(80003)
		for expected_day: int in range(1, 9):
			_to_battle(full)
			_expect(full.is_boss_day() == (expected_day == 8), "只在第八天标记Boss")
			_expect(full.settle_battle(boss_won if expected_day == 8 else true), "八天路线逐日结算")
			_expect(full.continue_after_battle(), "结算后继续")
		_expect(full.step == MazeState.Step.ENDED and full.day == 8, "第八天Boss后结束短路线")
		_expect(full.battle_results.back().ending == ("cleared" if boss_won else "boss_loss"), "区分Boss通关与失败")
		_expect(full.failure_protection == (2 if boss_won else 0), "Boss失败失去全部保护")
		_expect(MazeState.new().restore_state(JSON.parse_string(JSON.stringify(full.capture_state()))), "Boss结局可JSON恢复")
	DirAccess.remove_absolute(SAVE_PATH)
	print("D2-8 short maze state: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
