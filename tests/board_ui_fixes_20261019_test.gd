extends "res://tests/board_alignment_20261019_test.gd"

const FIXES_SAVE := "/private/tmp/project-card-board-ui-fixes-save.json"


func capture_alignment(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	if "--capture-ui-fixes" in OS.get_cmdline_user_args():
		image.save_png("/private/tmp/project-card-ui-fixes-%s.png" % label)
	return image


func verify_world_layout() -> void:
	var hud: Control = maze._status
	check(hud.get_parent() == main.world_content and hud.position == Vector2.ZERO, "层数天数保护金币固定在世界原位置")
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray._prepared_cards.is_empty(), "准备阶段持续显示敌方法术空框且不泄漏详情")
	var image := await capture_alignment("prepare")
	var frame: Control = main.world_content.get_node("BattlefieldWoodPad")
	var frame_image: Image = frame.texture.get_image()
	var trays: Array[Control] = [main.enemy_resource_tray, main.enemy_spell_preparation_tray, main.spell_preparation_tray, main.player_resource_tray]
	var positions: Array[Vector2] = [Vector2(6, 152), Vector2(1079, 38), Vector2(6, 367), Vector2(1075, 367)]
	var overlaps: Array[Vector2i] = [Vector2i(190, 250), Vector2i(1085, 150), Vector2i(190, 450), Vector2i(1085, 450)]
	for index: int in trays.size():
		check(trays[index].position == positions[index] and trays[index].z_index < frame.z_index, "四个侧栏保留原坐标并置于战场框之后")
		var point := overlaps[index]
		check(image.get_pixelv(point).is_equal_approx(frame_image.get_pixelv(point - Vector2i(frame.position))), "实际渲染时战场框遮住侧栏重叠边缘")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(main.world_content.position.y == -387 and hud.global_position.y == -387 and hud._gold.global_position.y == -381, "收藏视角上移3像素，顶部数值留在世界顶部而不钉住屏幕")
	var section: Control = main.get_node("%CollectionSection")
	check(section.position.y == 747 and hud._hero_panel.position.y == 747 and main.celestial_indicators._tray_board.position.y == 747, "收藏、英雄和指示物板世界位置同步上移3像素")
	check(main.emblem_library.global_position.y - main.world_content.position.y == 938, "工具包世界位置上移3像素")
	check(main.card_type_filter_tabs.global_position.y + main.card_type_filter_tabs.get_child(0).position.y == main.action_filter_tabs.global_position.y + main.action_filter_tabs.get_child(0).position.y, "种类标签下移3像素后常规顶边与行动标签相同")
	for index: int in 4:
		var tab: Control = main.card_type_filter_tabs.get_child(index)
		await _click(tab)
		await create_timer(0.3).timeout
		check(is_equal_approx(tab.global_position.y - main.world_content.position.y, 735), "四个种类标签实际点击后抽出顶边正确")
		await _click(tab)
		await create_timer(0.3).timeout
		check(is_equal_approx(tab.global_position.y - main.world_content.position.y, 743), "四个种类标签取消后常规顶边正确")
	var bookmark: Control = main.recent_bookmark_button
	check(bookmark.global_position.y - main.world_content.position.y == 722, "收藏书签相对板块下移3像素")
	await _click(bookmark)
	await create_timer(0.3).timeout
	check(bookmark.global_position.y - main.world_content.position.y == 714, "收藏书签下移后仍正确向上抽出")
	await _click(bookmark)
	await create_timer(0.3).timeout
	await verify_search_and_pixels()
	await verify_resource_drag()
	await capture_alignment("collection_after_drag")


func resolve_real_battle() -> void:
	var batches := 0
	while main.battle_controller.current_result == main.BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
		await process_frame
	if main.battle_controller.current_result == main.BattleController.Result.NONE:
		print("战斗未结束：", main.battle_controller.elapsed_seconds, " running=", main.battle_controller._running, " opening=", main.battle_controller._opening_spell_active)
	check(main.battle_controller.current_result == main.BattleController.Result.PLAYER_VICTORY, "实际战斗完成胜利结算")
	main._show_battle_result(main.battle_controller.current_result)
	await process_frame


func verify_spell_drag() -> OwnedCard:
	main.set_world_view(main.WorldView.COLLECTION, false)
	var spell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	await process_frame
	var slot: Control = main._find_collection_slot_for_owned_card(spell)
	check(is_instance_valid(slot), "实际收藏中新增测试法术")
	await move_pointer(slot.get_child(0).get_global_rect().get_center())
	await press_pointer(true)
	await move_pointer(pointer + Vector2(24, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "收藏法术触发原生拖拽")
	var tray: Control = main.spell_preparation_tray
	await move_pointer(tray.global_position + Vector2(35, 150), true)
	await press_pointer(false)
	check(main.prepared_spell_instance_ids.has(spell.instance_id), "层级下移后仍可真实拖入法术栏")
	return spell


func verify_battle_result_spells() -> void:
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "选择首日真实遭遇")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	check(main.start_battle(20261019, false), "启动首日实际战斗")
	await resolve_real_battle()
	check(main.spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray.is_visible_in_tree(), "首日结算界面双方空法术区持续显示")
	check(maze.continue_after_battle(), "真实结算进入第二天")
	finish_events()
	var path_id := ""
	for path: Dictionary in maze.run.paths:
		if not path.get("spells", []).is_empty(): path_id = path.path_id; break
	check(not path_id.is_empty() and maze.select_path(path_id), "选择第二天带实际法术的敌方遭遇")
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray._prepared_cards.is_empty(), "选择遭遇后敌方空框显示，详细法术仍保密")
	var spell := await verify_spell_drag()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	owned = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 200)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 3000)
	check(main.start_battle(20261019, false), "启动双方带法术的真实战斗")
	await process_frame
	var states: Array[Dictionary] = main.battle_controller.get_spell_display_states(BattleSquadState.Side.ENEMY)
	check(not states.is_empty() and main.enemy_spell_preparation_tray._prepared_cards.size() == states.size(), "开战后右栏展示实际敌方法术")
	await resolve_real_battle()
	check(main.current_phase == main.GamePhase.RESULT and main.battle_result_panel.visible, "进入真实战后结算界面")
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray._prepared_cards.size() == states.size(), "结算界面保留本场敌方法术队列")
	check(main.spell_preparation_tray.is_visible_in_tree() and main.spell_preparation_tray._prepared_cards.has(spell), "结算界面保留本场我方法术")
	for entry: Dictionary in main.battle_controller.get_spell_display_states(BattleSquadState.Side.ENEMY):
		var icon: Control = main.enemy_spell_preparation_tray._icons_by_instance_id[entry.spell.instance_id]
		check(is_equal_approx(icon.modulate.a, 0.45 if entry.spent else 1.0), "结算法术图标保持真实施放状态")
	await capture_alignment("result")
	main._set_result_battlefield_visible(true)
	await process_frame
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and not main.enemy_spell_preparation_tray._prepared_cards.is_empty(), "战后查看战场时法术队列继续显示")
	await capture_alignment("result_battlefield")
	main._set_result_battlefield_visible(false)
	check(maze.continue_after_battle(), "离开第二天结算")
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray._prepared_cards.is_empty(), "进入下一天保留空框并清除旧敌方详情")
	check(main.save_run_to_path(FIXES_SAVE) == OK and main.load_run_from_path(FIXES_SAVE), "更新后真实磁盘存档可恢复")
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and main.enemy_spell_preparation_tray._prepared_cards.is_empty(), "读档后保留空框且不泄漏上场敌方法术")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = FIXES_SAVE
	root.add_child(shell)
	if "--2k" in OS.get_cmdline_user_args(): shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.55).timeout
	await verify_world_layout()
	await verify_battle_result_spells()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(FIXES_SAVE)
	print("棋盘五项修复：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
