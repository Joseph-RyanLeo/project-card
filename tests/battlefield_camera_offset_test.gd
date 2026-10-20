extends "res://tests/board_ui_fixes_20261019_test.gd"

const CAMERA_SAVE := "/private/tmp/project-card-camera-offset-save.json"


func capture_camera(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	image.save_png("/private/tmp/project-card-camera-%s.png" % label)
	return image


func verify_world_and_screen() -> void:
	check(main.world_content.position == Vector2(0, -3), "战场视角下移3像素，整个世界上移3像素显示")
	var frame: Control = main.world_content.get_node("BattlefieldWoodPad")
	check(frame.position == Vector2(189, 0) and frame.global_position == Vector2(189, -3), "外框恢复源稿世界Y=0，屏幕仍为Y=-3")
	check(main.start_battle_button.global_position == Vector2(999, 671), "开战按钮随视角统一上移，世界仍为原稿Y=674")
	check(main.battle_time_bar.position == Vector2(191, 347) and main.battle_time_bar.global_position == Vector2(191, 344), "中线保留世界坐标并与外框一起显示")
	var source_y: Array[int] = [33, 188, 367, 522]
	for index: int in 4:
		var row: Control = main.world_content.get_node("BattlefieldBrocade%d" % index)
		check(row.position == Vector2(222, source_y[index]) and row.global_position == Vector2(222, source_y[index] - 3), "四排底板保留原稿坐标并统一受视角影响")
	var trays: Array[Control] = [main.enemy_resource_tray, main.enemy_spell_preparation_tray, main.spell_preparation_tray, main.player_resource_tray]
	var source: Array[Vector2] = [Vector2(6, 152), Vector2(1079, 38), Vector2(6, 367), Vector2(1075, 367)]
	for index: int in trays.size():
		check(trays[index].position == source[index] and trays[index].global_position == source[index] - Vector2(0, 3), "资源与法术托盘随同一战场视角移动")
	var hud: Control = maze._status
	check(hud.get_parent() == main.world_content and hud.global_position == Vector2(0, -3) and hud._gold.global_position.y == 3, "世界顶栏与金币数值使用同一视角，无独立补偿")
	check(main.battle_speed_bar.position == Vector2(558, 14) and main.battle_speed_bar.global_position == Vector2(558, 11), "倍速保留指定世界位置并随世界视角移动")
	var enemy: Control = main.get_node("%EnemyAvatar")
	check(enemy.global_position == enemy.position - Vector2(0, 3), "敌方人物与世界使用相同偏移")
	check(main.player_avatar_button.global_position == main.player_avatar_button.position + Vector2(208, 357), "我方人物按实际父区域统一移动")
	check(main.battle_result_panel.get_parent() == main, "屏幕结算面板不参与世界位移")
	var image := await capture_camera("battlefield")
	var original: Image = frame.texture.get_image()
	var errors := 0
	# 未被事件面板覆盖的左右金边及上角应仍显示源稿第3行以后的像素。
	for y: int in range(3, 33):
		for x: int in range(2, 10):
			var point := Vector2i(x, y)
			var color := original.get_pixelv(point)
			if color.a == 1 and not image.get_pixelv(Vector2i(189, -3) + point).is_equal_approx(color):
				errors += 1
	check(errors == 0, "外框顶部仍裁掉3像素，保留原金角像素")


func verify_collection_and_transition() -> void:
	main.set_world_view(main.WorldView.COLLECTION, true)
	await create_timer(0.4).timeout
	check(main.world_content.position == Vector2(1, -368), "下半视角保留已确认原稿(19,368)，不额外叠加3像素")
	var frame: Control = main.world_content.get_node("BattlefieldWoodPad")
	check(frame.global_position == Vector2(190, -368), "收藏视角中的外框也恢复真实原稿位置")
	check(main.get_node("%CollectionSection").position.y == 747 and maze._status._hero_panel.position.y == 747 and main.celestial_indicators._tray_board.position.y == 747, "另行确认的收藏、英雄、指示物上移3像素保持")
	check(main.emblem_library.global_position.y - main.world_content.position.y == 938, "另行确认的工具箱世界位置保持")
	var slot: Control = main._get_collection_card_slots()[0]
	check(slot.get_child(0).global_position == Vector2(250, 415), "收藏首卡仍精确对应图层9，不受上半视角更正影响")
	await capture_camera("collection")
	await verify_resource_drag()
	await verify_spell_drag()
	main.set_world_view(main.WorldView.BATTLEFIELDS, true)
	await create_timer(0.4).timeout
	check(main.world_content.position == Vector2(0, -3), "从下半视角返回正确新原点，无0或-6叠加残留")
	await verify_world_and_screen()


func verify_battle_and_restore() -> void:
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "真实遭遇进入准备")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	var rect: Rect2 = main.start_battle_button.get_global_rect()
	await move_pointer(rect.get_center())
	await press_pointer(true)
	await create_timer(0.1).timeout
	check(main.start_battle_button.press_depth == 3 and main.start_battle_button.get_global_rect() == rect, "新视角下原生鼠标按压与命中保持一致")
	await press_pointer(false)
	check(main.current_phase == main.GamePhase.BATTLE, "新位置实际点击正常开战")
	await create_timer(0.2).timeout
	check(main.world_content.position == Vector2(0, -3) and main.battle_time_bar.is_visible_in_tree(), "开战刷新不把视角还原为旧0")
	await resolve_real_battle()
	check(main.current_phase == main.GamePhase.RESULT and main.world_content.position == Vector2(0, -3), "实际结算保留战场视角")
	await _click(main.get_node("%ViewResultBattlefieldButton"))
	check(not main.battle_result_panel.visible, "新视角下可实际点击查看战场")
	await capture_camera("result_battlefield")
	check(maze.continue_after_battle(), "下一天真实流程正常")
	await create_timer(0.4).timeout
	check(main.save_run_to_path(CAMERA_SAVE) == OK and main.load_run_from_path(CAMERA_SAVE), "实际磁盘存读档正常")
	await create_timer(0.4).timeout
	check(main.world_content.position == Vector2(0, -3), "读档也使用战场新视角")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = CAMERA_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.4).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await verify_world_and_screen()
	await verify_collection_and_transition()
	await verify_battle_and_restore()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(CAMERA_SAVE)
	print("战场视角3像素更正：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
