extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-floor-exit-test"
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var source := RunSaveService.new().load_checkpoint("/private/tmp/project-card-d3-4-lantern-trial-test/project_card_run.json")
	check(source.get("success", false), "读取已实际完成八天的临时检查点，供层终点路由专项使用")
	var shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0), "创建层终点独立专项档")
	var p: ProfileProgress = shell.slot_progress
	# 本专项只验证不带主线的路由分支；获得积分的真实连续链另有专项覆盖。
	p.profile.unlocks.routes = ["eight_days", "second_floor"]
	check(await shell.start_new_slot_run(), "无主线自动开启当前最深两层路线")
	var main = shell.main_screen
	check(main.maze_controller.run.route_days == 16, "不新增路线选择器即可采用第二层")
	var checkpoint: Dictionary = source.checkpoint.short_maze.duplicate(true)
	checkpoint.run.route_days = 16
	checkpoint.run.step = ShortMazeRunState.Step.BATTLE_RESULT
	checkpoint.run.battle_results.back().ending = ""
	check(main.maze_controller.restore_state(checkpoint), "实际八天战斗历史构成合法第一层胜利检查点")
	main.current_phase = main.GamePhase.RESULT
	main.maze_controller.refresh()
	var exit_button = main.battle_result_panel.get_node("FinishFloorRunButton")
	check(exit_button.visible and main.continue_next_level_button.visible, "本层结算与继续第二层同时可选")
	check(Rect2(Vector2.ZERO, main.battle_result_panel.size).encloses(exit_button.get_rect()) and not exit_button.get_rect().intersects(main.continue_next_level_button.get_rect()), "两个按钮完整位于原面板内且不重叠")
	exit_button.pressed.emit()
	check(main.profile_progress.run.stage == "summary" and main.profile_progress.run.summary.outcome == "cleared", "点击本层结算按通关处理")
	check(main.profile_progress.run.summary.completed_days == 8 and main.profile_progress.run.summary.bosses == 1, "按实际一层八天及一个Boss计分")
	var restored := RunSaveService.new().load_checkpoint(main.run_save_path)
	var state := ShortMazeRunState.new()
	check(state.restore_state(restored.checkpoint.short_maze.run) and state.route_days == 8 and state.step == ShortMazeRunState.Step.ENDED, "主动层结算保持可严格恢复的终点历史")
	# 结算信号会延迟切换页面，先让回调结束，再释放测试场景。
	await process_frame
	await process_frame
	shell.free()
	await process_frame
	print("D3-4 floor exit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
