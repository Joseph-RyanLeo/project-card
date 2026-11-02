extends SceneTree

const START_SCENE = preload("res://scenes/StartMenu.tscn")
const TEST_DIRECTORY := "/private/tmp/project-card-start-menu-quit-test"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIRECTORY)
	var shell = START_SCENE.instantiate()
	shell.run_slots.directory = TEST_DIRECTORY
	root.add_child(shell)
	await process_frame
	if "window-close" in OS.get_cmdline_user_args():
		shell.run_slots.delete_slot(0)
		if not await shell.start_slot(0) or not await shell.start_new_slot_run():
			quit(1)
			return
		shell.main_screen.run_reward_state.gold = 135
		await process_frame
		root.close_requested.emit()
		var result := RunSaveService.new().load_checkpoint(shell.run_slots.get_slot_path(0))
		if not result.get("success", false) or result.checkpoint.reward_state.gold != 135:
			quit(1)
			return
		print("PASS: 关闭窗口先保存当前档位的最新金币")
	else:
		shell.start_menu.find_child("QuitButton", true, false).pressed.emit()
		await process_frame
		print("PASS: 主菜单退出按钮已发出退出请求")
	await create_timer(2.0).timeout
	push_error("退出请求未结束游戏")
	quit(1)
