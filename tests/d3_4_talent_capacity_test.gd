extends SceneTree

const SHELL = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-d3-4-capacity-test"
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if value: print("PASS: ", text)
	else: failures += 1; push_error("FAIL: " + text)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var shell = SHELL.instantiate()
	shell.run_slots.directory = DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	await process_frame
	check(await shell.start_slot(0) and await shell.start_new_slot_run(), "开启天赋容量专项临时档")
	var main = shell.main_screen
	var maze = main.maze_controller
	check(maze.hero.grant_experience("talent_fixture", 42), "7级经验边界夹具")
	check(maze.choose_talent("sentry_guard") and maze.choose_talent("sentry_needle") and maze.choose_talent("sentry_unbreakable"), "通过正式选择事务取得不坏身")
	check(maze.deploy_sentry(String(maze.stock[0].instance_id), "front"), "7级实际部署哨位")
	check(maze.deployed[0].capacity == (5 + 7 + 5) * 2 and maze.deployed[0].remaining == 34, "不坏身翻倍包含针刺额外容量")
	check(main.save_run_to_path(main.run_save_path) == OK, "7级及容量保存通过完整验证")
	check(main.load_run_from_path(main.run_save_path) and main.maze_controller.deployed[0].capacity == 34, "恢复后哨位容量不重算或丢失")
	shell.return_to_start_menu()
	await process_frame
	check(await shell.start_slot(1) and await shell.start_new_slot_run(), "建立三星印独立档")
	main = shell.main_screen
	maze = main.maze_controller
	maze.hero.grant_experience("marks_fixture", 42)
	check(maze.choose_talent("sentry_guard") and maze.choose_talent("sentry_needle") and not maze.choose_talent("firmament_blessing"), "至高天暂缓，不接受无商品天赋")
	check(maze.choose_talent("three_celestial_marks") and main.celestial_indicators.capture_state().items.size() == 3, "三星印各赠一枚现有太阳／月亮／星星")
	check(not maze.choose_talent("three_celestial_marks") and main.celestial_indicators.capture_state().items.size() == 3, "重复选择不重复赠指示物")
	shell.free()
	print("D3-4 talents: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
