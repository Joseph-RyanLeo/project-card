extends "res://tests/d3_4_ui_test.gd"

## 使用隔离档、真实输入、渲染与战斗，覆盖本轮教程及卡牌交互调整。
const REVISION_DIR := "/private/tmp/project-card-feedback-revision"
const Effects = preload("res://scripts/ui/pack_opening_effect_settings.gd")
var main
var pointer_held := false
var last_pointer := Vector2.ZERO

func capture_revision(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(REVISION_DIR.path_join(label + ".png"))

func close_hint() -> void:
	var hint: Control = main.get_node_or_null("TaskHint")
	if hint != null:
		main.profile_progress.record_hint_read(hint.get_meta("hint_key"), hint.content, {"story": true, "teaching": true})
		hint.free()
	await frames()

func mark_other_hints() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tasks/tutorial_hints.json"))
	for id: String in source:
		if id in ["battle_intro", "attack_observed"]: continue
		main.profile_progress.record_hint_read("tutorial:step:" + id, source[id], {"story": true, "teaching": true})

func key_space() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await create_timer(0.6).timeout

func pointer(point: Vector2, pressed: int = -1) -> void:
	if pressed < 0:
		var event := InputEventMouseMotion.new()
		event.position = shell.render_container.get_global_transform_with_canvas() * point
		event.global_position = event.position
		event.relative = event.position - last_pointer
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pointer_held else 0
		last_pointer = event.position
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = shell.render_container.get_global_transform_with_canvas() * point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
		pointer_held = event.pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pointer_held else 0
		root.push_input(event, true)
	await process_frame

func verify_hero_disabled() -> void:
	var maze = main.maze_controller
	check(maze.hero.experience == 0 and maze.hero.selected_talents.is_empty() and maze.hero.pending_talent_levels.is_empty(), "教程不发经验、天赋或待选项")
	check(maze.stock.is_empty() and maze.deployed.is_empty() and maze.battle_context().is_empty(), "教程不产出哨位、不接入英雄战斗效果")
	check(not maze._status._hero_panel.visible and main.player_avatar_button.is_visible_in_tree(), "隐藏英雄信息板，保留伊奥恩头像")
	check(not main.player_resource_tray.visible and not main.enemy_resource_tray.visible and main._get_resource_definitions().is_empty(), "双方资源区隐藏且资源生成池为空")
	check(main.resource_board_state.get_level_resource_cards("player").is_empty() and main.resource_board_state.get_level_resource_cards("enemy").is_empty(), "本关双方均未生成自动资源")

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("教程反馈专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(REVISION_DIR)
	Effects.load_saved(REVISION_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = REVISION_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0), "创建隔离新档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "进入营救铁匠四关教程")
	main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if maze._initial_pack_drop.is_running(): await maze._initial_pack_drop.finished
	verify_hero_disabled()
	var origin: Vector2 = maze._initial_pack_button.position
	await create_timer(3.2).timeout
	check(main.get_node_or_null("TaskHint") == null and maze._initial_pack_button.position.y < origin.y, "落稳三秒后跳起摇摆，不弹点包框")
	await capture_revision("01_pack_nudge")
	await click_control(maze._initial_pack_button)
	await create_timer(5.2).timeout
	var opening: CardPackOpening = main._card_pack_opening
	check(is_instance_valid(opening) and opening.tear_art.seal_hint_seconds >= 0.0 and main.get_node_or_null("TaskHint") == null, "进入包装三秒后银色撕线来回扫光，五秒后无文字提示")
	await capture_revision("02_seal_breath")
	mark_other_hints()
	opening.auto_tear()
	await create_timer(1.0).timeout
	main._close_card_inspection(true)
	await frames()
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and maze.hero.pending_talent_levels.is_empty(), "收包后直接进入选路，无开局天赋页")
	var registry: Dictionary = main._build_card_definition_registry()
	var pool: Array[CardData] = main.ordinary_shop_service._eligible_cards(main._get_shop_card_definitions(), main.owned_card_collection.get_cards())
	check(pool.size() > 0 and pool.all(func(card: CardData): return not card.references_resource_rules()), "商店、卡包与事件共用候选不含资源及开采相关卡")
	for id: StringName in [&"armorsmith", &"baggage_muleteer", &"mining_pick", &"tide_archer"]:
		check(not pool.has(registry[id]) and main.owned_card_collection.create_card(registry[id]) == null, "拒绝资源相关卡获得：" + String(id))
	var table = maze._event_table
	check(table._deck.get_node("DeckTopCard").definition.path_id == maze.run.paths[0].path_id, "中央牌堆顶牌使用第一张待抽牌的定义")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await frames()
	var parked: bool = main._tabletop_panels_parked
	check(main._can_park_tabletop_panels(), "事件板允许收展")
	await key_space()
	check(main._tabletop_panels_parked != parked, "真实空格收起事件板")
	await key_space()
	check(main._tabletop_panels_parked == parked, "再次按空格展示事件板")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await click_control(table._deck)
	await create_timer(0.6).timeout
	check(not table.cards.is_empty() and table.cards[0].definition.path_id == table._deck.get_node("DeckTopCard").definition.path_id, "实际抽出的第一张牌与牌堆顶背一致")
	await click_control(table.cards[0])
	await create_timer(1.2).timeout
	check(maze.run.step == ShortMazeRunState.Step.EVENT and main.get_node_or_null("TaskHint") == null, "点选并翻开事件后不出现查看事件提示")
	check(maze.complete_event(false, true), "正式完成首个事件")
	await frames()
	# 装备与星星真实挂到同一卡牌，再用原生鼠标长按拖动。
	var gun: OwnedCard = main.owned_card_collection.find_first_by_definition(registry[&"musketeer"])
	gun.surface_finish = CardAppearance.Surface.FRACTURED
	var item: OwnedCard = main.owned_card_collection.create_card(registry[&"beer_mug"])
	var squad := SquadData.from_owned_card(gun)
	squad.equip_item(item)
	var star := CelestialIndicator.new()
	star.instance_id = &"revision_star"
	star.kind = CelestialIndicator.Kind.STAR
	squad.attach_indicator(star, Vector2(20, 40), 0)
	main.front_row.add_squad(squad, 0)
	main._refresh_drag_availability()
	main.set_world_view(main.WorldView.COLLECTION, false)
	main._park_tabletop_panels()
	await create_timer(0.6).timeout
	var slot: BoardSlot = main.front_row.get_squads()[0]
	var view := slot.get_card_view(gun.card_data)
	await pointer(Vector2(1200, 700))
	var force_before: Vector2 = view._finish_pointer_force
	await create_timer(0.4).timeout
	check(view._has_board_finish_motion() and view._finish_pointer_force.distance_to(force_before) > 0.01, "上场特殊卡面在鼠标外自动改变光照")
	check(is_equal_approx(view.BOARD_FINISH_ORBIT_SECONDS, 14.5), "自动光照一周为14.5秒")
	var equipment: Control = slot.get_equipment_indicator()
	var point: Vector2 = equipment.get_global_rect().get_center()
	await pointer(point)
	await pointer(point, 1)
	await create_timer(0.25).timeout
	await pointer(point + Vector2(26, 8))
	await frames()
	var star_view := slot.get_celestial_indicator(star.instance_id)
	check(shell.internal_viewport.gui_is_dragging() and not equipment.visible, "真实长按拖起装备块")
	check(is_instance_valid(star_view) and star_view.visible and squad.has_indicator(CelestialIndicator.Kind.STAR), "同卡星星在装备原生拖动期间保持显示与归属")
	await capture_revision("03_equipment_star_drag")
	shell.internal_viewport.gui_cancel_drag()
	await pointer(point, 0)
	await create_timer(0.5).timeout
	check(is_instance_valid(star_view) and star_view.visible and equipment.visible, "取消拖动后装备和星星都保留")
	main._open_card_inspection(gun.card_data, gun, view)
	await create_timer(0.6).timeout
	var effect_box: PanelContainer = main._inspection_overlay.get_node_or_null("InspectionEffectSideBox")
	check(effect_box != null and effect_box.get_theme_stylebox("panel").bg_color == Color("252c35"), "检视效果框复用指向说明的深色标题与浅色正文样式")
	await capture_revision("04_inspection_style")
	main._close_card_inspection(true)
	await frames()
	# 走真实事件与战斗，验证四关英雄与资源限制，以及首战暂停／末战非暂停对白。
	for day: int in range(1, 5):
		while maze.run.get_round_kind() != "battle":
			if maze.run.step == ShortMazeRunState.Step.CHOOSING: check(maze.select_path(String(maze.run.paths[0].path_id)), "选择第%d天事件" % day)
			if maze.run.get_round_kind() == "shop":
				await create_timer(0.5).timeout
				check(maze.leave_shop(true), "正式离店")
			else: check(maze.complete_event(false, true), "正式完成事件")
			await frames()
		check(maze.select_path(String(maze.run.paths[0].path_id)), "进入第%d关战斗准备" % day)
		mark_other_hints()
		await close_hint()
		for row: BattlefieldRow in [main.front_row, main.back_row]: row.clear_squads()
		for owned: OwnedCard in main.owned_card_collection.get_cards():
			if owned.card_data.card_type == CardData.CardType.MINION:
				var row: BattlefieldRow = main.back_row if owned.card_data.action_type in [CardData.ActionType.RANGED, CardData.ActionType.HEAL] else main.front_row
				row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())
		verify_hero_disabled()
		check(main.start_battle(12345, false), "第%d关正常开战" % day)
		await create_timer(0.8).timeout
		if day == 1:
			var hint: Control = main.get_node_or_null("TaskHint")
			check(hint != null and main._task_hint_pause_requested and hint.content.instruction.contains("行动冷却") and hint.content.instruction.contains("获胜") and hint.content.instruction.contains("失败"), "首次战斗暂停，首段介绍行动与胜负")
			await capture_revision("05_first_battle_intro")
			await close_hint()
		if day == 4:
			for batch: int in 20:
				if main.profile_progress.run.tasks.main.progress.get("tutorial_actions", {}).get("attack_observed", false): break
				main.battle_controller.resolve_next_batch()
			await create_timer(0.3).timeout
			var hint: Control = main.get_node_or_null("TaskHint")
			check(hint != null and hint.speech_only and not main._task_hint_pause_requested and not paused, "末战近战远程介绍仅用伊奥恩气泡，战斗保持运行")
			await capture_revision("06_melee_ranged_speech")
			await close_hint()
		for batch: int in 20000:
			if main.battle_controller.current_result != BattleController.Result.NONE: break
			main.battle_controller.resolve_next_batch()
		if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
		check(not maze.reward_summary().contains("经验") and maze.hero.experience == 0 and maze.hero.pending_talent_levels.is_empty(), "第%d关结算不发经验或弹天赋" % day)
		check(main.save_run_to_path(main.run_save_path) == OK, "正式保存本关状态")
		if day < 4:
			check(maze.continue_after_battle(true), "进入下一天")
			await frames()
			mark_other_hints()
			await close_hint()
	verify_hero_disabled()
	check(main.load_run_from_path(main.run_save_path), "正式读档恢复四关教程")
	await frames()
	verify_hero_disabled()
	shell.free()
	print("Tutorial feedback revision: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
