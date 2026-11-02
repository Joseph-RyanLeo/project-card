extends "res://tests/sticker_toolbox_overflow_test.gd"

## 真实离店按钮、英雄台词、超时、输入取消与存档事务；不修改玩家存档。
var assertions := 0


func check(condition: bool, message: String) -> void:
	assertions += 1
	super.check(condition, message)


func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	if DisplayServer.get_name() != "headless": Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.click(point, button)


func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("英雄说话验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-hero-speech-run.json"
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	var leave: Button = main._shop_leave_button
	var speech = main._hero_speech
	var bag := main.emblem_library as EmblemLibraryView
	check(not speech.visible, "英雄默认不显示空白气泡")
	check(bag.restore_inventory_state(_layout(false)), "工具箱28格填满")
	bag.receive_stickers([{"instance_id": "hero_speech_drop", "emblem_id": "火把"}])
	var inventory := bag.get_inventory_state()
	var gold: int = main.run_reward_state.gold
	var rng_state: int = main.ordinary_shop_service.rng.state
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and speech.is_confirming(leave), "首次真实点击离店触发英雄提示并保留商店")
	check(speech.text_label.text == "临时区域仍有纹章，是否真的要离开" and main.find_child("TemporaryStickerDiscardConfirmation", true, false) == null, "提示使用指定文案，不再弹出原生确认框")
	check(bag.get_inventory_state() == inventory and main.run_reward_state.gold == gold and main.ordinary_shop_service.rng.state == rng_state, "首次提示不改变库存、金币和商店随机流")
	check(speech.size.x == 178 and speech.size.y < 142 and speech.get_child(0).texture.resource_path == "res://assets/ui/hero/speech_bubble.png", "底板保留用户178px宽度，并按行数收紧高度")
	check(speech.mouse_filter == Control.MOUSE_FILTER_IGNORE and speech.text_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "气泡和文字都不阻挡原有操作")
	check(speech.get_rect().end.y < main.player_avatar_button.get_global_rect().position.y + speech.HEAD_INSET and Rect2(Vector2.ZERO, main.size).encloses(speech.get_rect()), "气泡默认朝上并保持在720p画布内")
	await capture("hero-speech-720p")
	for mode: int in [DisplayScript.DisplayMode.WINDOW_1080P, DisplayScript.DisplayMode.WINDOW_2K]:
		shell.apply_display_mode(mode)
		await process_frame
		check(speech.size.x == 178 and speech.size.y < 142 and Rect2(Vector2.ZERO, main.size).encloses(speech.get_rect()), "切换窗口尺寸仍保持原生气泡与英雄锚点")
	await capture("hero-speech-2k")
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_720P)
	await click(Vector2(480, 340))
	check(not speech.is_confirming(leave) and main.ordinary_shop_open and bag.get_inventory_state() == inventory, "点击其他位置立即取消确认，不丢弃贴纸")
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and speech.visible, "取消后再次离店先提示，不沿用上次确认")
	# 只缩短本次停留计时，用真实帧等待验证超时后的状态。
	speech._remaining_seconds = 0.08
	await create_timer(0.15).timeout
	check(not speech.is_confirming(leave) and main.ordinary_shop_open and bag.has_dropped_stickers(), "无操作超时收起台词，商店及临时贴纸仍保留")
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and speech.visible, "超时后第一次离店仍需重新提示")
	await key(KEY_ESCAPE)
	await process_frame
	check(not speech.is_confirming(leave) and main._escape_pause_menu.is_menu_open(), "Esc照常打开暂停菜单，同时取消离店确认")
	main._close_escape_pause_menu()
	await process_frame
	await click(leave.get_global_rect().get_center())
	bag.receive_stickers([{"instance_id": "hero_speech_new_drop", "emblem_id": "火把"}])
	check(not speech.is_confirming(leave) and bag.has_dropped_stickers(), "提示期间库存变化使旧确认失效")
	await click(leave.get_global_rect().get_center())
	main.hero_say("我会在这里等你。", 0.1)
	check(speech.text_label.text == "我会在这里等你。" and not speech.is_confirming(leave), "通用英雄台词替换旧话语并清除离店确认")
	await create_timer(0.1 + speech.FADE_SECONDS + 0.08).timeout
	check(not speech.visible, "通用台词同样按时渐隐收起")
	# 真实保存失败不得吞掉临时贴纸，失败后的下一次仍须重新提示。
	var before_failure := bag.get_inventory_state()
	main.run_save_path = "/private/tmp/project-card-hero-speech-no-directory/run.json"
	await click(leave.get_global_rect().get_center())
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and bag.get_inventory_state() == before_failure and not speech.is_confirming(leave), "二次离店保存失败恢复全部临时贴纸，并清除本次确认")
	main.run_save_path = "/private/tmp/project-card-hero-speech-run.json"
	await create_timer(0.5).timeout
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and speech.visible, "失败重试仍先提示")
	await click(leave.get_global_rect().get_center())
	await create_timer(0.4).timeout
	check(not main.ordinary_shop_open and not speech.is_confirming(leave) and not bag.has_dropped_stickers() and bag.get_inventory_state().size() == 28 and main.run_reward_state.gold == gold, "提示期间第二次真实点击离店成功，只销毁临时纹章并保留金币与格内库存")
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	await click(leave.get_global_rect().get_center())
	check(not main.ordinary_shop_open and not speech.is_confirming(leave), "没有临时纹章时一次点击正常离店")
	await create_timer(0.4).timeout
	await _check_maze_leave()
	shell.queue_free()
	await process_frame
	print("英雄说话与离店：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _check_maze_leave() -> void:
	var maze := ShortMazeController.new()
	main.add_child(maze)
	main.maze_controller = maze
	check(maze.initialize(main), "建立正式短迷宫流程")
	maze.run.initialize(45)
	maze.run.round_index = 2
	maze.run.step = ShortMazeRunState.Step.EVENT
	main.emblem_library.receive_stickers([{"instance_id": "maze_speech_drop", "emblem_id": "火把"}])
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	var leave: Button = main._shop_leave_button
	await click(leave.get_global_rect().get_center())
	check(main.ordinary_shop_open and main._hero_speech.visible and maze.run.step == ShortMazeRunState.Step.EVENT, "正式迷宫首次离店停留原商店事件")
	await click(leave.get_global_rect().get_center())
	await create_timer(0.4).timeout
	check(not main.ordinary_shop_open and not main.emblem_library.has_dropped_stickers() and maze.run.step == ShortMazeRunState.Step.CHOOSING, "正式迷宫二次离店沿用原事务销毁临时贴纸并推进路径")
