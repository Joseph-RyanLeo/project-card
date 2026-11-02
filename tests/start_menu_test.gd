extends SceneTree

## 四层菜单以真实显示壳、控件输入与临时存档验证。空档先到大厅，手动开启本局。
const SCENE = preload("res://scenes/StartMenu.tscn")
const DIR := "/private/tmp/project-card-four-menu-test"
const PREVIEWS := "res://docs/previews/d3_1_menu_20261102"
var failures := 0
var checks := 0
var shell: Control


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var slots := RunSlotService.new()
	slots.directory = DIR
	for index: int in 3: slots.delete_slot(index)
	for filename: String in ["run_slots.cfg", "game_preferences.cfg", "card_text_display.cfg"]:
		if FileAccess.file_exists(DIR.path_join(filename)): DirAccess.remove_absolute(DIR.path_join(filename))
	root.size = Vector2i(1280, 720)
	shell = SCENE.instantiate()
	shell.run_slots.directory = DIR
	root.add_child(shell)
	await frames()
	check(shell.main_screen == null and shell.slot_progress == null and shell.start_menu.visible, "启动只显示主菜单，不预建本局")
	check(button(shell.start_menu, "StartButton").text == "开始游戏" and button(shell.start_menu, "GalleryButton") == null and button(shell.start_menu, "MazeShopButton") == null, "主菜单只保留开始/继续、存档、设置、退出")
	await capture("01_start")
	await click(button(shell.start_menu, "SlotsButton"))
	await click(shell.start_menu._slot_buttons[2])
	check(not slots.has_slot(2) and shell.main_screen == null, "点选空档不创建本局或存档，等待进入")
	await capture("02_slots")
	await click(button(shell.start_menu, "BackButton"))
	await click(button(shell.start_menu, "StartButton"))
	check(shell.slot_progress != null and shell.slot_progress.run.stage == "hub" and shell.main_screen == null and shell.run_slots.selected_slot == 0, "无档开始自动创建第一档并进入轻量大厅")
	var path: String = shell.run_slots.get_slot_path(0)
	var service := RunSaveService.new()
	var fresh: Dictionary = service.load_checkpoint(path).checkpoint
	check(not fresh.has("collection") and fresh.profile_progress.profile.discoveries.cards.is_empty() and fresh.profile_progress.profile.points == 0, "大厅新档没有提前赠卡、发现或积分")
	check(button(shell._slot_progress_panel, "GalleryButton").disabled and button(shell._slot_progress_panel, "MazeShopButton").disabled, "展览馆和迷宫商店只在档内展示并禁用")
	await capture("03_hub")
	await click(button(shell._slot_progress_panel, "HubSettingsButton"))
	shell._settings_panel.volume_slider.value = 42
	check(FileAccess.file_exists(DIR.path_join("game_preferences.cfg")) and shell._preferences.volume == 42, "大厅设置音量实际生效并保存本机偏好")
	shell._settings_panel.text_option.select(1)
	shell._settings_panel.text_option.item_selected.emit(1)
	check(FileAccess.file_exists(DIR.path_join("card_text_display.cfg")), "卡牌文字设置保存到独立本机偏好")
	shell._settings_panel.display_option.select(0)
	shell._settings_panel.display_option.item_selected.emit(0)
	await frames()
	check(shell.current_display_mode == 0 and shell._preferences.display_mode == 0, "设置页切换实际窗口模式并保存偏好")
	await capture("04_settings")
	await escape()
	check(not shell._settings_panel.visible and shell._slot_progress_panel.visible and not shell.start_menu.visible, "设置页Esc只返回来源大厅")
	await click(button(shell._slot_progress_panel, "HubReturnButton"))
	check(shell.start_menu.visible and button(shell.start_menu, "StartButton").text == "继续游戏", "返回主菜单后主入口切换为继续")
	await click(button(shell.start_menu, "SlotsButton"))
	await click(shell.start_menu._slot_buttons[2])
	await click(button(shell.start_menu, "EnterSlotButton"))
	check(shell.slot_progress.run.stage == "hub" and shell.main_screen == null and shell.run_slots.selected_slot == 2, "显式进入第三空档，同样先到大厅")
	var other_path: String = shell.run_slots.get_slot_path(2)
	var other_bytes := FileAccess.get_file_as_string(other_path)
	await click(button(shell._slot_progress_panel, "HubReturnButton"))
	await click(button(shell.start_menu, "SlotsButton"))
	await click(shell.start_menu._slot_buttons[0])
	await click(button(shell.start_menu, "BackButton"))
	check(shell.start_menu._selection_label.text == "继续：存档 3", "主菜单摘要明确显示继续目标，不与选中位置混淆")
	await click(button(shell.start_menu, "StartButton"))
	check(shell.run_slots.selected_slot == 2, "仅点选另一档不改变继续游戏的上次使用档")
	await click(button(shell._slot_progress_panel, "HubReturnButton"))
	other_bytes = FileAccess.get_file_as_string(other_path)
	await click(button(shell.start_menu, "SlotsButton"))
	await click(shell.start_menu._slot_buttons[0])
	await click(button(shell.start_menu, "EnterSlotButton"))
	await click(button(shell._slot_progress_panel, "NewRunButton"))
	var main = shell.main_screen
	check(main != null and main.visible and main.owned_card_collection.size() == 5 and shell.slot_progress.run.stage == "active", "手动开始后才创建本局并发原有5张卡")
	check(main.profile_progress.profile.discoveries.cards.size() == 5, "开局初始发现只提交一次")
	var run_id: String = main.profile_progress.run.id
	main.run_reward_state.gold = 87
	await escape()
	check(paused and main._escape_pause_menu.is_menu_open() and button(main._escape_pause_menu, "ContinueGameButton").is_visible_in_tree(), "对局Esc打开精简首页并沿用暂停机制")
	await capture("05_pause")
	await click(button(main._escape_pause_menu, "PauseSettingsButton"))
	check(paused and main._escape_pause_menu._settings.visible and not main._escape_pause_menu._home.visible, "对局设置为暂停子页")
	check(main.battle_volume_slider.value == 42 and main._escape_pause_menu._settings.text_option.selected == 1, "主菜单/大厅/对局共用音量与卡牌文字偏好")
	main.battle_volume_slider.value = 55
	await escape()
	check(paused and main._escape_pause_menu._home.visible and not main._escape_pause_menu._settings.visible, "设置页Esc回暂停首页，战斗保持暂停")
	await click(button(main._escape_pause_menu, "DeveloperToolsButton"))
	check(main._escape_pause_menu._tools.visible and button(main._escape_pause_menu, "CardFontLabButton").is_visible_in_tree(), "原调试工具保留在独立子页")
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(main._escape_pause_menu._tools.get_global_rect()), "调试子页面板完整位于720p逻辑画布内")
	await escape()
	await click(button(main._escape_pause_menu, "ContinueGameButton"))
	check(not paused and not main._escape_pause_menu.is_menu_open(), "继续游戏正确释放暂停")
	await escape()
	await click(button(main._escape_pause_menu, "ReturnToMainMenuButton"))
	check(shell.main_screen == null and shell.slot_progress == null and not paused and shell.start_menu.visible, "对局保存返回只到主菜单，不进入局外大厅")
	await click(button(shell.start_menu, "StartButton"))
	main = shell.main_screen
	check(main != null and main.run_reward_state.gold == 87 and main.profile_progress.run.id == run_id, "继续游戏优先恢复原本局与金币，不新开局")
	check(main.begin_run_collection(), "真实本局保存待完成收藏阶段")
	await frames()
	check(not main.visible and not main._escape_pause_menu.is_processing_input() and button(shell._slot_progress_panel, "NewRunButton") == null, "待收藏阶段屏蔽本局Esc与新一局入口")
	await click(button(shell._slot_progress_panel, "CollectionPreviewButton"))
	check(shell.slot_progress.run.stage == "preview", "集合按钮保存预览阶段")
	await click(button(shell._slot_progress_panel, "HubReturnButton"))
	await click(button(shell.start_menu, "StartButton"))
	check(shell.main_screen == null and shell.slot_progress.run.stage == "preview" and shell.slot_progress.run.id == run_id, "待完成集合由轻量界面直接恢复，不预建另一局")
	await click(button(shell._slot_progress_panel, "CollectionBackButton"))
	check(shell.slot_progress.run.stage == "selection", "集合可返回选卡并保存")
	await click(button(shell._slot_progress_panel, "CollectionPreviewButton"))
	await click(button(shell._slot_progress_panel, "CollectionConfirmButton"))
	check(shell.slot_progress.run.stage == "hub" and shell.main_screen == null, "零张最终确认回存档内大厅")
	var before_failure := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	await click(button(shell._slot_progress_panel, "NewRunButton"))
	check(shell.main_screen == null and shell.slot_progress.run.stage == "hub" and shell._persistence_dialog.visible, "新局保存失败回大厅，保留原局外状态")
	check(FileAccess.get_file_as_string(path) == before_failure, "失败的新局初始化不覆盖有效原档")
	DirAccess.remove_absolute(path + ".tmp")
	shell._persistence_dialog.hide()
	await click(button(shell._slot_progress_panel, "NewRunButton"))
	check(shell.main_screen != null and shell.slot_progress.run.id != run_id and shell.main_screen.owned_card_collection.size() == 5, "保存失败后可正常重试新一局")
	await escape()
	# 保存返回失败必须留在原对局和暂停页。
	DirAccess.make_dir_absolute(path + ".tmp")
	await click(button(shell.main_screen._escape_pause_menu, "ReturnToMainMenuButton"))
	check(shell.main_screen != null and paused and shell._persistence_dialog.visible, "对局保存失败保留游戏及暂停状态")
	DirAccess.remove_absolute(path + ".tmp")
	shell._persistence_dialog.hide()
	await click(button(shell.main_screen._escape_pause_menu, "ReturnToMainMenuButton"))
	check(FileAccess.get_file_as_string(other_path) == other_bytes, "所有切换/重开不修改另一档进度")
	await click(button(shell.start_menu, "SlotsButton"))
	await click(shell.start_menu._slot_buttons[0])
	await click(button(shell.start_menu, "DeleteSlotButton"))
	check(shell.start_menu._delete_dialog.visible, "删除仍需明确确认")
	shell.start_menu._delete_dialog.confirmed.emit()
	shell.start_menu._delete_dialog.hide()
	check(not shell.run_slots.has_slot(0) and shell.run_slots.has_slot(2), "删除只清所选档，保留其他档")
	await click(button(shell.start_menu, "BackButton"))
	await click(button(shell.start_menu, "SettingsButton"))
	check(shell._settings_panel.volume_slider.value == 55, "对局修改的音量同步回主菜单设置")
	await escape()
	var restarted = SCENE.instantiate()
	restarted.run_slots.directory = DIR
	root.add_child(restarted)
	await frames()
	check(restarted._preferences.volume == 55 and restarted._preferences.display_mode == 0 and restarted.run_slots.get_continue_slot() == 2, "重建显示壳恢复本机设置与剩余可继续档位")
	restarted.queue_free()
	await frames()
	for index: int in 3: shell.run_slots.delete_slot(index)
	shell.queue_free()
	await frames()
	print("Four menu checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)


func button(parent: Node, node_name: String) -> Button:
	return parent.find_child(node_name, true, false) as Button if parent != null else null


func frames() -> void:
	await process_frame
	await process_frame


func click(target: Button) -> void:
	if target == null:
		check(false, "目标按钮存在")
		return
	await frames()
	var at: Vector2 = shell.render_container.get_global_transform_with_canvas() * target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()
	if shell.screen_transition.busy: await shell.screen_transition.finished
	await frames()


func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await frames()


func capture(filename: String) -> void:
	if not OS.get_cmdline_user_args().has("screenshots"): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEWS))
	shell.internal_viewport.get_texture().get_image().save_png(PREVIEWS.path_join(filename + ".png"))
