extends "res://tests/tutorial_smith_layout_test.gd"

## 在真实铁匠检查点之后刮符文，验证第二战前解锁堆叠、检视并完成战斗。


func capture_pack(label: String) -> void:
	if DisplayServer.get_name() != "headless": await super.capture_pack(label)


func pointer_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)
	await process_frame


func _verify_toolbox() -> void:
	await super._verify_toolbox()
	var maze = main.maze_controller
	var owned: OwnedCard = main._inspection_owned_card
	var surface: InspectionCardSurface = main._inspection_surface
	surface.tilt_locked = true
	surface.set_pointer_force(Vector2.ZERO)
	var blade_offset: Vector2 = main._rune_scraper_drag_data.hit_rect_offset / surface.get_global_transform_with_canvas().get_scale()
	var blade_size: Vector2 = main._rune_scraper_drag_data.hit_rect_size / surface.get_global_transform_with_canvas().get_scale()
	var point: Vector2
	for index: int in 9:
		var offset := Vector2(4 + (index % 3) * 10, 4 + (index / 3) * 10)
		point = surface.card_canvas_point(main._inspection_card_view.rune_area_position + offset) - surface.get_global_transform_with_canvas().basis_xform(blade_offset + blade_size * 0.5)
		if index == 0: await pointer_button(point, true)
		var motion := InputEventMouseMotion.new()
		motion.position = shell.render_container.get_global_transform_with_canvas() * point
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	check(owned.rune_revealed[0] and main._rune_scraper_mode, "真实擦到70%揭晓首枚符文，按住期间不中断笔画")
	await pointer_button(point, false)
	await create_timer(0.4).timeout
	check(not main._rune_scraper_mode and owned.rune_revealed[0] and is_instance_valid(main._inspection_overlay), "松手后自动收好刮刀讲解，保留检视，无需Esc退出工具")
	var hint := await expected_hint("rune_basics")
	await frames()
	check(Rect2(0, 0, 1280, 720).encloses(hint.panel.get_rect()) and hint.instruction_label.get_minimum_size().y <= hint.instruction_label.size.y + 1, "五元素基础收益完整显示，正文没有越出画布或裁切")
	for term: String in ["强化+2", "生命+2", "护甲+3", "热诚+1", "受击优先级", "Esc → 玩法教学"]:
		check(hint.instruction_label.text.contains(term), "真实揭晓后教学包含：" + term)
	check(not hint.instruction_label.text.contains("×1.5"), "基础符文教学不重复牌型的具体规则")
	await capture_pack("25_basic_runes")
	await key_escape()
	check(main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:rune_basics"), "按提示收起检视后独立保存基础符文教学已阅")
	await right_click(maze._find_tutorial_card_view(&"anvil_margaret"))
	await create_timer(0.4).timeout
	check(main.get_node_or_null("TaskHint") == null, "同局再次检视不自动重弹已阅基础教学")
	await key_escape()
	# 跳过与本专项无关且此前已验收的前后排对白，仍实际走完事件和第二场战斗。
	check(main.save_profile_action(func():
		main.profile_progress.record_hint_read("tutorial:step:formation", TaskCatalog.tutorial_hint("formation"), {"story": true, "teaching": true})
		return true), "准备已阅布阵说明的隔离夹具")
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "正式选择第二天剩余事件")
		if maze.run.get_round_kind() == "shop":
			if is_instance_valid(main._shop_open_tween) and main._shop_open_tween.is_running(): await main._shop_open_tween.finished
			await click_control(main._shop_leave_button)
		else: check(maze.complete_event(false, true), "正式完成第二天事件")
	check(not maze.can_stack_cards(), "第二天活动期间仍未开放叠卡")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "进入第二战准备")

	hint = await expected_hint("squad_sources")
	await frames()
	check(maze.can_stack_cards(), "第二战准备显示叠卡说明时开放叠卡")
	check(hint.instruction_label.text.contains("最左卡") and hint.instruction_label.text.contains("最上层卡") and hint.instruction_label.text.contains("最右卡") and hint.instruction_label.text.contains("最多5枚"), "叠放前说明三处属性来源与实际显现符文")
	check(Rect2(0, 0, 1280, 720).encloses(hint.panel.get_rect()), "叠放属性说明完整位于左下角")
	await create_timer(0.25).timeout
	await capture_pack("26_squad_attribute_sources")
	var row: BattlefieldRow = main.front_row
	var source: BoardSlot = row.get_squads()[1]
	var member: CardData = source.get_squad_data().horizontal_cards[0]
	var drag := {"kind": &"card", "source_type": &"board", "source_row": row, "source_slot": source, "squad_data": source.get_squad_data(), "card_data": member, "owned_card": source.get_squad_data().get_owned_card(member), "preview_offset": -source.card_view.card_size * 0.5}
	var merged := false
	for x: int in range(0, 832, 5):
		var intent := row._build_drop_intent(Vector2(x, 65), drag)
		if intent.get("operation") != &"merge_card": continue
		drag["drop_intent"] = intent
		merged = main._transfer_drop_intent(drag, row)
		if merged: break
	check(merged, "通过正式落点解析与转移入口组成真实小队")
	await frames()
	var stacked: BoardSlot
	for slot: BoardSlot in row.get_squads():
		if slot.get_squad_data().get_card_count() > 1: stacked = slot
	var squad := stacked.get_squad_data()
	check(squad.get_action_source() == squad.horizontal_cards.front() and squad.get_vitals_source() == squad.horizontal_cards.back() and squad.get_effect_source() == squad.layer_cards.front(), "教学所述最左、最右和顶牌与真实小队模型一致")
	check(TaskCatalog.teaching_hint("tutorial:step:squad_patterns").is_empty(), "叠卡后不再出现一次性进阶大全")

	# 在实际堆叠槽位制造一组连续水符文，复用揭晓／贴纸变更后的场面刷新。
	var visible_slots := squad.get_visible_rune_slots()
	var owner: OwnedCard
	for index: int in visible_slots.size():
		var rune := visible_slots[index]
		owner = squad.get_owned_card(rune.card)
		owner.resolved_runes[rune.rune_index] = CardData.ElementType.WATER
		owner.rune_revealed[rune.rune_index] = index < 2
	main._refresh_owned_card_status_visuals(owner)
	await frames()
	var pair_key := "rune_pattern:pair"
	check(main.profile_progress.profile.tutorial.read_hints.has(pair_key), "已上场小队第一次达成双鸣后独立保存玩法教学")
	await right_click(stacked.card_view)
	check(is_instance_valid(main._inspection_overlay), "组成牌型后仍可正常检视小队")

	# 旧存档快照不会覆盖当前基础文案，也不会复活已撤下的旧教学。
	main.profile_progress.profile.tutorial.hint_texts["tutorial:step:rune_basics"] = "旧版基础教学快照"
	main.profile_progress.profile.tutorial.hint_texts["tutorial:step:squad_patterns"] = "旧版进阶教学快照"
	await key_escape()
	await key_escape()
	await click_control(main._escape_pause_menu.find_child("TutorialHelpButton", true, false))
	var page: Control = main._escape_pause_menu.find_child("TutorialHelpPage", true, false)
	var review: Label = page.find_child("TaskInfoText", true, false)
	var basics_button: Button = page.find_child("Teaching_tutorial_step_rune_basics", true, false)
	var index_scroll := basics_button.get_parent().get_parent() as ScrollContainer
	index_scroll.ensure_control_visible(basics_button)
	await frames()
	await click_control(basics_button)
	check(review.text.contains("火：强化+2") and not review.text.contains("旧版基础教学快照"), "玩法教学回看使用当前基础符文说明")
	check(page.find_child("Teaching_tutorial_step_squad_patterns", true, false) == null, "旧档快照不会把进阶大全重新加回目录")
	var pair_button: Button = page.find_child("Teaching_rune_pattern_pair", true, false)
	index_scroll.ensure_control_visible(pair_button)
	await frames()
	await click_control(pair_button)
	check(review.text.contains("两枚相同元素连续排列") and review.text.contains("×1.5") and page.find_child("TeachingElementTable", true, false).visible, "双鸣条目显示组成条件、倍率和共用元素表")
	await capture_pack("28_pattern_names_review")
	await key_escape()
	await key_escape()
	check(main.start_battle(-1, false), "真实阵容正式开始第二天战斗")
	var batches := 0
	while main.battle_controller.current_result == BattleController.Result.NONE and batches < 10000:
		main.battle_controller.resolve_next_batch()
		batches += 1
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "叠卡后的阵容完成第二场真实战斗")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	check(maze.continue_after_battle(true), "正式进入第三天")
