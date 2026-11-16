extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func to_battle(state: ShortMazeRunState) -> void:
	check(state.commit_day_start(), "正式开始一天")
	for kind: String in ["free_event", "paid_event", "shop", "battle"]:
		check(state.get_round_kind() == kind, "日内轮次顺序：" + kind)
		var paths: Array[Dictionary] = []
		for index: int in 3: paths.append({"path_id": "unit_%s_%d" % [kind, index], "kind": kind, "hint": "状态单元测试路径"})
		check(state.set_paths(paths) and state.select_path(String(paths[0].path_id)), "选择合法路径")
		if kind != "battle": check(state.complete_event(), "D3未解锁日期礼包不会强制索取旧赠包")
	check(state.start_battle(), "状态机正式开战")

func _run() -> void:
	for terminal: int in [4, 8, 16]:
		var state := ShortMazeRunState.new()
		state.initialize(20261105)
		state.route_days = terminal
		state.daily_pack_rewards = false
		for day: int in terminal:
			to_battle(state)
			check(state.settle_battle(true), "状态机结算胜利输入")
			check(ShortMazeRunState.new().restore_state(JSON.parse_string(JSON.stringify(state.capture_state()))), "逐日结果可严格JSON恢复")
			if terminal == 16 and day == 7:
				check(state.is_boss_day() and state.battle_results.back().ending.is_empty(), "第一层Boss胜利仍保留第二层继续资格")
			check(state.continue_after_battle(), "正式推进下一天或结束")
		check(state.step == ShortMazeRunState.Step.ENDED and state.battle_results.back().ending == "cleared", "正确到达本局路线终点")
	# 两层路线第一层Boss失败直接结束，不能错误消费普通保护后继续第二层。
	var failed := ShortMazeRunState.new()
	failed.initialize(11)
	failed.route_days = 16
	failed.daily_pack_rewards = false
	for day: int in 8:
		to_battle(failed)
		failed.settle_battle(day != 7)
		failed.continue_after_battle()
	check(failed.step == ShortMazeRunState.Step.ENDED and failed.failure_protection == 0 and failed.battle_results.back().ending == "boss_loss", "两层路线第一层Boss败北立即结束")
	var old := ShortMazeRunState.new()
	old.initialize(12)
	var checkpoint := old.capture_state()
	checkpoint.erase("route_days")
	checkpoint.erase("daily_pack_rewards")
	check(old.restore_state(checkpoint) and old.route_days == 8 and old.daily_pack_rewards, "旧v2路线字段缺失时保留原八天与日期礼包")
	checkpoint = old.capture_state()
	checkpoint.route_days = 12
	check(not old.restore_state(checkpoint), "拒绝未定义路线天数")
	print("D3-4 routes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
