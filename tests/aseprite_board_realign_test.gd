extends "res://tests/board_ui_fixes_20261019_test.gd"

const REALIGN_SAVE := "/private/tmp/project-card-aseprite-realign-save.json"


func capture_alignment(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var result: Image = shell.internal_viewport.get_texture().get_image()
	if "--capture-realign" in OS.get_cmdline_user_args():
		result.save_png("/private/tmp/project-card-realign-%s.png" % label)
	return result


func verify_source_positions() -> void:
	var source_y: Array[int] = [33, 188, 367, 522]
	for index: int in 4:
		var board: Control = main.world_content.get_node("BattlefieldBrocade%d" % index)
		check(board.position == Vector2(242 - 20, source_y[index]) and board.size == Vector2(836, 155), "四排底板位置和原生尺寸与Aseprite一致")
	for index: int in 7:
		main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(main.world_content.position == Vector2(1, -368), "下半视角准确对应原稿左上角(19,368)")
	var source_x: Array[int] = [269, 406, 543, 678, 815, 952]
	var slots: Array = main._get_collection_card_slots()
	check(slots.size() == 12, "实际两页收藏排满12张卡")
	for index: int in slots.size():
		var card: Control = slots[index].get_child(0)
		var page_side := index / 6
		var side_index := index % 6
		var source := Vector2(source_x[page_side * 3 + side_index % 3], 783 + (side_index / 3) * 153)
		check(card.global_position.is_equal_approx(source - Vector2(19, 368)), "真实裸卡对应图层9的12个卡框位置")
		check(card.size == Vector2(99, 136), "保留当前裸卡尺寸")
	await capture_alignment("collection")
	main.set_world_view(main.WorldView.BATTLEFIELDS, true)
	await create_timer(0.4).timeout
	check(main.world_content.position.is_equal_approx(Vector2.ZERO), "返回战场时恢复原X和Y，无横向偏移残留")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	check(main.front_row.position.y + main.get_node("WorldContent/PlayerBoardSection").position.y + main.BATTLEFIELD_ROW_CONTENT_INSET_Y == 377, "战场卡位继续位于原稿我方前排底板内")
	await capture_alignment("battlefields")


func verify_symmetric_bar() -> void:
	var bar: Control = main.battle_time_bar
	check(bar.is_visible_in_tree(), "准备阶段中线进度条持续显示")
	var full: Image = bar.FULL.get_image()
	var empty: Image = bar.EMPTY.get_image()
	for elapsed: float in [0.0, 7.5, 15.0, 22.5, 30.0]:
		bar.update_time(elapsed, 30.0)
		var rendered := await capture_alignment("bar_%d" % elapsed)
		var left_count := 0
		var right_count := 0
		for x: int in range(65, 833):
			if full.get_pixel(x, 7) == empty.get_pixel(x, 7): continue
			var color := rendered.get_pixelv(Vector2i(bar.global_position) + Vector2i(x, 7))
			if color.is_equal_approx(full.get_pixel(x, 7)):
				if x < 420: left_count += 1
				else: right_count += 1
		var expected := floori(355 * (1.0 - elapsed / 30.0))
		check(left_count == expected and right_count == expected, "真实渲染时左右蓝条等长且同时向中央收拢")
		check(rendered.get_pixelv(Vector2i(bar.global_position) + Vector2i(65, 7)).is_equal_approx(full.get_pixel(65, 7) if elapsed == 0.0 else empty.get_pixel(65, 7)), "左侧外端随时间移动，不再固定不动")
	bar.update_time(20.0, 16.0)
	check(bar.remaining_ratio == 0, "提前进入疲劳后蓝条保持空槽")
	main._update_battle_timer()
	check(bar.remaining_ratio == 1, "准备阶段恢复满条")


func verify_real_battle_bar() -> void:
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实遭遇")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	check(main.start_battle(20261019, false), "按实际战前快照开战")
	main.battle_controller.resolve_next_batch()
	main._update_battle_timer()
	var expected: float = clampf(1.0 - main.battle_controller.elapsed_seconds / main.battle_controller.fatigue_start_seconds, 0, 1)
	check(main.battle_time_bar.is_visible_in_tree() and is_equal_approx(main.battle_time_bar.remaining_ratio, expected), "战斗中直接读取实际疲劳起点和战斗时间")
	await resolve_real_battle()
	check(main.current_phase == main.GamePhase.RESULT and main.battle_time_bar.is_visible_in_tree(), "真实战斗结算后中线仍显示")
	await capture_alignment("result")
	check(maze.continue_after_battle(), "实际进入下一天")
	check(main.battle_time_bar.is_visible_in_tree() and main.battle_time_bar.remaining_ratio == 1, "下一天准备阶段仍显示满条")
	check(main.save_run_to_path(REALIGN_SAVE) == OK and main.load_run_from_path(REALIGN_SAVE), "实际磁盘读档仍可恢复")
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(main.world_content.position == Vector2(1, -368), "读档后下半视角保持原稿(19,368)")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = REALIGN_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.4).timeout
	await verify_source_positions()
	await verify_symmetric_bar()
	await verify_real_battle_bar()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(REALIGN_SAVE)
	print("Aseprite重新对齐：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
