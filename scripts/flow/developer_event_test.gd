extends RefCounted

## 事件和任务都从独立快照运行，自动存档写入同目录的测试文件。
var _main: Control
var _original_path := ""
var _test_path := ""
var _original_view := 0
var event_id := ""
var task_id := ""
var forced_option := -1
var forced_roll := 0


func _init(main: Control) -> void:
	_main = main


func is_active() -> bool:
	return not _test_path.is_empty()


func can_retry() -> bool:
	return is_active() and FileAccess.file_exists(_test_path + ".retry")


func start(definition: Dictionary) -> String:
	if is_active(): return "请先退出当前测试。"
	var maze: ShortMazeController = _main.maze_controller
	if maze == null: return "请先开始一局迷宫。"
	var blocked := maze.developer_event_test_blocker(definition)
	if not blocked.is_empty(): return blocked
	var error := _begin()
	if not error.is_empty(): return error
	event_id = String(definition.path_id)
	if maze.deal_developer_event(definition) and _main.save_run_to_path(_test_path) == OK:
		return ""
	var restore_error := stop()
	return "无法准备测试事件。" if restore_error.is_empty() else restore_error


func _begin() -> String:
	_original_path = _main.run_save_path
	_original_view = _main.current_world_view
	_test_path = "%s.developer-test-%d-%d" % [_original_path, OS.get_process_id(), Time.get_ticks_usec()]
	if _main.save_run_to_path(_test_path + ".origin") != OK:
		discard()
		return "无法建立测试快照，请检查存档目录。"
	_main.run_save_path = _test_path
	return ""


func start_task(id: String) -> String:
	if is_active(): return "请先退出当前测试。"
	var maze: ShortMazeController = _main.maze_controller
	if maze == null or _main.current_phase == _main.GamePhase.BATTLE:
		return "请在迷宫备战或结算界面启动任务测试。"
	var trial := _create_task_profile(id)
	if trial == null: return "该任务暂不可重玩。"
	var error := _begin()
	if not error.is_empty(): return error
	task_id = id
	_main.profile_progress = trial
	maze.new_run(int(Time.get_ticks_msec()) % int(_main.BATTLE_SEED_MAX))
	if _main.save_run_to_path(_test_path) == OK:
		_main.profile_stage_changed.emit()
		return ""
	var restore_error := stop()
	return "无法保存任务测试局。" if restore_error.is_empty() else restore_error


func _create_task_profile(id: String) -> ProfileProgress:
	var task := TaskCatalog.get_task(id)
	if task.is_empty() or not task.implemented: return null
	var progress := ProfileProgress.new()
	var prerequisites: Array[String] = []
	var prerequisite := String(task.requires)
	while not prerequisite.is_empty():
		if prerequisite == id or prerequisites.has(prerequisite): return null
		var definition := TaskCatalog.get_task(prerequisite)
		if definition.is_empty(): return null
		prerequisites.push_front(prerequisite)
		prerequisite = String(definition.requires)
	for required_id: String in prerequisites:
		progress.profile.tasks[required_id] = {"purchased": true, "completed": false}
		if required_id == "tutorial": progress.complete_tutorial()
		else: progress.complete_task(required_id, TaskCatalog.rewards_for(required_id))
	progress.profile.tasks[id] = {"purchased": true, "completed": false}
	var is_main: bool = task.category == "main"
	if not progress.select_catalog_tasks(id if is_main else "", "" if is_main else id): return null
	return progress


func capture_retry_point() -> void:
	var maze: ShortMazeController = _main.maze_controller
	if not is_active() or event_id.is_empty() or can_retry() or maze.run.selected_path.get("path_id") != event_id: return
	var source := ProjectSettings.globalize_path(_test_path)
	if DirAccess.copy_absolute(source, source + ".retry") != OK:
		_main.play_area_label.text = "未能保存事件重试点。"


func retry() -> String:
	if not can_retry(): return "翻开指定事件牌后即可重试。"
	if not _main.load_run_from_path(_test_path + ".retry"):
		return "无法读回事件重试点。"
	if _main.save_run_to_path(_test_path) != OK:
		return "已恢复事件，测试文件保存失败。"
	return ""


func stop() -> String:
	if not is_active(): return ""
	if not _main.load_run_from_path(_test_path + ".origin"):
		return "无法读回测试前状态。原存档文件仍可从主菜单载入。"
	_main.run_save_path = _original_path
	_main.set_world_view(_original_view, false)
	discard()
	_main.profile_stage_changed.emit()
	return ""


func discard() -> void:
	if not is_active(): return
	for suffix: String in ["", ".bak", ".tmp", ".origin", ".origin.bak", ".origin.tmp", ".retry"]:
		var file := ProjectSettings.globalize_path(_test_path + suffix)
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	_test_path = ""
	_original_path = ""
	event_id = ""
	task_id = ""
	forced_option = -1
	forced_roll = 0


func roll_for(path_id: String, option_index: int) -> int:
	return forced_roll if path_id == event_id and option_index == forced_option else 0
