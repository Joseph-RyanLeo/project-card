extends "res://tests/event_cards_test.gd"

const Layout = preload("res://scripts/data/resource_hex_layout.gd")
const Board = preload("res://scripts/data/resource_board_state.gd")
const SAVE := "/private/tmp/project-card-board-revision-save.json"
var pointer := Vector2.ZERO


func move_pointer(point: Vector2, held: bool = false) -> void:
	var transform: Transform2D = shell.render_container.get_global_transform_with_canvas()
	var event := InputEventMouseMotion.new()
	event.position = transform * point
	event.global_position = event.position
	event.relative = (point - pointer) * transform.get_scale()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = point
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame


func press_pointer(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * pointer
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func verify_resource_drag() -> void:
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/stone_of_greed.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	await process_frame
	var slot: Control = main._find_collection_slot_for_owned_card(owned)
	check(is_instance_valid(slot), "真实收藏页显示手动资源")
	if not is_instance_valid(slot): return
	var board: ResourceBoardState = main.resource_board_state
	var occupied: Dictionary = {}
	for placement: Dictionary in board.deployments.player.values():
		for pair: Array in placement.shape:
			occupied[Vector2i(placement.anchor[0] + pair[0], placement.anchor[1] + pair[1])] = true
	var disabled: Dictionary = {}
	for cell: Vector2i in board.disabled_by_side.player: disabled[cell] = true
	var anchor := Vector2i(-99, -99)
	for cell: Vector2i in Layout.valid_cells():
		if Layout.can_place(owned.resource_shape, cell, occupied, disabled):
			anchor = cell
			break
	check(anchor != Vector2i(-99, -99), "19格内有合法真实资源落点")
	await move_pointer(slot.get_child(0).get_global_rect().get_center())
	await press_pointer(true)
	await move_pointer(pointer + Vector2(24, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "新布局收藏资源触发原生拖拽")
	var tray: Control = main.player_resource_tray
	await move_pointer(tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + Layout.center(anchor)), true)
	await create_timer(0.15).timeout
	await capture_revision("resource_drag")
	await press_pointer(false)
	check(board.deployments.player.has(String(owned.instance_id)), "真实鼠标拖放部署到19格资源区")
	main._refresh_resource_preparation_trays()


func capture_revision(label: String) -> void:
	if "--capture-board-revision" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-board-revision-%s.png" % label)


func verify_geometry_and_migration() -> void:
	check(Layout.valid_cells().size() == 19 and Layout.valid_cells(1).size() == 27, "新布局19格，旧布局仅用于迁移")
	check(Layout.center(Vector2i(0, 0)) == Vector2(17, 48) and Layout.center(Vector2i(2, 0)) == Vector2(71, 16), "19格中心与新稿一致")
	for cell: Vector2i in Layout.valid_cells():
		var center := Layout.center(cell)
		check(Rect2(0, 0, 143, 160).has_point(center), "所有合法格心位于新网格图片内")
	var legacy := {"level_id": "old", "disabled_by_side": {"player": [[5, 6]], "enemy": []}, "deployments": {"player": {"old_resource": {"anchor": [5, 2], "shape": [[0, 0]], "grab_anchor": [0, 0], "grab_pixel_offset": [0, 0]}}, "enemy": []}, "level_resource_cards": {"player": [], "enemy": []}, "resources_generated": true}
	legacy.deployments.enemy = {}
	var original := JSON.stringify(legacy)
	var board := Board.new()
	check(board.restore_state(legacy), "旧27格资源和禁用格可迁移到19格")
	var state := board.capture_state()
	var anchor: Array = state.deployments.player.old_resource.anchor
	check(int(state.layout_version) == Layout.VERSION and Layout.is_valid_cell(Vector2i(int(anchor[0]), int(anchor[1]))), "迁移后保存新版本及合法锚点")
	check(JSON.stringify(legacy) == original, "迁移不修改传入旧存档数据")
	var other := Board.new()
	check(other.restore_state(legacy) and JSON.stringify(other.capture_state()) == JSON.stringify(state), "迁移确定性，无随机重抽")
	check(other.restore_state(JSON.parse_string(JSON.stringify(state))), "新布局JSON往返可恢复")
	var oversized: Dictionary = legacy.duplicate(true)
	oversized.disabled_by_side.player = []
	oversized.deployments.player = {}
	for index: int in 20:
		var cell := Layout.valid_cells(1)[index]
		oversized.deployments.player["old_%02d" % index] = {"anchor": [cell.x, cell.y], "shape": [[0, 0]], "grab_anchor": [0, 0], "grab_pixel_offset": [0, 0]}
	check(not board.restore_state(oversized) and JSON.stringify(board.capture_state()) == JSON.stringify(state), "旧存档确实超出19格时拒绝读取，不丢资源或污染当前状态")
	var definitions: Array[CardData] = [load("res://resources/cards/fire_element_shard.tres"), load("res://resources/cards/stone_of_greed.tres"), load("res://resources/cards/rainbow_gold_ore.tres")]
	for seed_value: int in 100:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var generated := Board.new()
		check(generated.initialize_level(&"revision_generation", rng) and generated.generate_level_resources(definitions, rng).success, "19格资源与随机禁用格实际生成")


func finish_events() -> void:
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实随机事件")
	if maze.run.selected_path.get("reward") == "story":
		maze.choose_story_option(maze.run.selected_path.options.size() - 1)
	check(maze.complete_event(false), "完成随机事件")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "完成强化事件")
	check(maze.select_path(maze.run.paths[0].path_id), "选中商店")
	maze.enter_selected_shop()
	main._toggle_ordinary_shop()
	check(maze.run.get_round_kind() == "battle", "每日事件后进入战斗轮")


func _run() -> void:
	verify_geometry_and_migration()
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE
	root.add_child(shell)
	if "--2k" in OS.get_cmdline_user_args():
		shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.55).timeout
	if "--2k" in OS.get_cmdline_user_args():
		check(shell.render_container.get_global_transform_with_canvas().get_scale().is_equal_approx(Vector2(2, 2)), "2K窗口仍用1280逻辑画布与2倍输入映射")
	var hud: Control = maze._status
	check(hud._slots.size() == 8, "顶栏8天槽")
	hud.set_day_marker(1, 0, false)
	hud.set_day_marker(1, 1)
	check(is_instance_valid(hud._roll) and hud._roll.is_running(), "日内切换启动滚轮动画")
	hud._roll.pause()
	hud._roll.custom_step(0.12)
	check(hud._fronts[0].position.y < 0 and hud._backs[0].position.y > 0, "日内滚轮同槽上下衔接")
	hud._roll.custom_step(0.2)
	hud.set_day_marker(2, 0)
	await create_timer(0.3).timeout
	for index: int in 8:
		check((hud._fronts[index].texture != null) == (index == 1), "跨天后只有当天亮，过去和未来为空")
	hud.sync(maze, false)
	for tray: Control in [main.player_resource_tray, main.enemy_resource_tray]:
		check(tray.size == Vector2(199, 208), "资源托盘原生尺寸")
		for cell: Vector2i in Layout.valid_cells():
			check(tray._nearest_axial_cell(Layout.center(cell)) == cell and tray._contains_hex_point(Layout.center(cell), Layout.center(cell)), "19格中心命中与绘制一致")
	check(not main.enemy_spell_preparation_tray.visible, "准备阶段隐藏敌方法术详情")
	await capture_revision("prepare")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var rest: Vector2 = main.recent_bookmark_button.position
	await _click(main.recent_bookmark_button)
	await create_timer(0.3).timeout
	check(main.collection_bookmark_active and main.recent_bookmark_button.position.x == rest.x and main.recent_bookmark_button.position.y < rest.y, "真实点击最近使用书签向上抽出")
	await capture_revision("collection")
	main.toggle_recent_bookmark()
	await verify_resource_drag()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	finish_events()
	check(maze.select_path(maze.run.paths[0].path_id), "选择首日真实遭遇")
	await capture_revision("battle_prepare")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 20)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 300)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await _click(main.start_battle_button)
	check(main.current_phase == main.GamePhase.BATTLE, "真实点击素材开始按钮可开战")
	main.battle_time_bar.update_time(15, 30)
	check(is_equal_approx(main.battle_time_bar.remaining_ratio, 0.5), "蓝条按距疲劳剩余时间计算")
	main.battle_time_bar.update_time(30, 26)
	check(main.battle_time_bar.remaining_ratio == 0.0, "提前疲劳后保持空条")
	var batches := 0
	while main.battle_controller.current_result == main.BattleController.Result.NONE and batches < 1200:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result == main.BattleController.Result.PLAYER_VICTORY, "真实战斗与资源结算可完成")
	main._show_battle_result(main.battle_controller.current_result)
	check(maze.continue_after_battle(), "进入第二天")
	finish_events()
	var path_id := ""
	for path: Dictionary in maze.run.paths:
		if not path.get("spells", []).is_empty(): path_id = path.path_id; break
	check(not path_id.is_empty() and maze.select_path(path_id), "选择带真实敌方法术的第二天遭遇")
	check(not main.enemy_spell_preparation_tray.visible, "选定敌方后准备阶段仍无侦察信息泄漏")
	check(main.start_battle(-1, false), "第二天实际开战")
	await process_frame
	main._update_battle_timer()
	var spell_states: Array[Dictionary] = main.battle_controller.get_spell_display_states(BattleSquadState.Side.ENEMY)
	check(main.enemy_spell_preparation_tray.is_visible_in_tree() and not spell_states.is_empty(), "开战后敌方真实法术可见")
	check(main.enemy_spell_preparation_tray._prepared_cards.size() == spell_states.size() and not main.enemy_spell_preparation_tray._drop_enabled, "右侧只读队列对应实际敌方法术")
	check(not main.battle_log_panel.visible, "日志默认收起，不盖住法术托盘")
	await _click(main.battle_log_button)
	check(main.battle_log_panel.visible, "真实点击顶栏可打开日志")
	await _click(main.battle_log_button)
	check(not main.battle_log_panel.visible, "再次点击收起日志")
	await capture_revision("battle")
	check(main.save_run_to_path(SAVE) == OK and main.load_run_from_path(SAVE), "19格战前状态可真实磁盘恢复")
	check(not main.enemy_spell_preparation_tray.visible and main.resource_board_state.capture_state().layout_version == Layout.VERSION, "读档恢复准备并隐藏敌方法术")
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(SAVE)
	print("棋盘修订：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
