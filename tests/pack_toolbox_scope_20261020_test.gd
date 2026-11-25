extends "res://tests/card_pack_opening_test.gd"

## 真实普通检视记忆、商店购买、整包完成及中途取消，不替换任何业务对象。
func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.click(point, button)

func _run() -> void:
	create_timer(75).timeout.connect(func(): push_error("开包工具箱验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-pack-toolbox-scope.json"
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	main.run_reward_state.gold = 1000
	CardView.TextDisplaySettings.set_mode(self, CardView.TextDisplaySettings.Mode.POPUP, false)
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var effect_box_seen := false
	for remembered: bool in [true, false, false]:
		main._open_card_inspection(owned.card_data, owned)
		await create_timer(0.35).timeout
		if main._inspection_library_expanded != remembered:
			await click(main._inspection_library_toggle.get_global_rect().get_center())
			await create_timer(0.3).timeout
		main._close_card_inspection(true)
		check(main._last_minion_inspection_library_expanded == remembered, "普通检视保存实际展开或收起状态")
		if not main.ordinary_shop_open: main._toggle_ordinary_shop()
		await create_timer(0.5).timeout
		var index := _find_generated_pack("small", false)
		check(index >= 0, "真实商店生成可购买小包")
		if index < 0: quit(1); return
		await process_frame
		await click(_tile(index).get_global_rect().get_center())
		await create_timer(0.6).timeout
		await click(Vector2(640, 340), MOUSE_BUTTON_RIGHT)
		var sequence: CardPackOpening = main._card_pack_opening
		if not is_instance_valid(sequence): push_error("未打开真实卡包"); quit(1); return
		while sequence.phase != CardPackOpening.Phase.INSPECTING: await process_frame
		check(not main._inspection_library_expanded and main.emblem_library.position.is_equal_approx(main._inspection_library_position(false)), "新卡包默认收起工具箱，不沿用普通检视记忆")
		check(main._last_minion_inspection_library_expanded == remembered, "开包没有覆盖普通检视记忆")
		await capture("pack-toolbox-closed")
		var effect_box := main._inspection_overlay.get_node_or_null("InspectionEffectSideBox") as Control
		var original_x := effect_box.position.x if effect_box != null else 0.0
		await click(main._inspection_library_toggle.get_global_rect().get_center())
		await create_timer(0.3).timeout
		check(main._inspection_library_expanded, "开包期间仍可临时展开工具箱")
		if effect_box != null:
			effect_box_seen = true
			check(effect_box.position.x >= main._inspection_overlay.size.x, "开包检视原说明同样滑出右侧")
		if remembered:
			var inspected: OwnedCard = main._inspection_owned_card
			main._open_gameplay_teaching("tutorial:step:wounds")
			check(main._escape_pause_menu.is_teaching_book_open(), "开包检视也可打开独立教程书")
			main._on_escape_pause_menu_requested()
			check(main._card_pack_opening == sequence and main._inspection_owned_card == inspected and main._inspection_library_expanded, "关闭教程后保留开包进度、原卡和工具箱")
			await click(main._inspection_library_toggle.get_global_rect().get_center())
			await create_timer(0.3).timeout
			if effect_box != null: check(is_equal_approx(effect_box.position.x, original_x), "开包检视收回时原说明滑回")
			await _finish_cards(sequence)
		else:
			main._close_card_inspection(true)
			await process_frame
		check(main._last_minion_inspection_library_expanded == remembered, "整包完成或展开时取消均不保存开包工具箱状态")
		main._open_card_inspection(owned.card_data, owned)
		await create_timer(0.35).timeout
		check(main._inspection_library_expanded == remembered, "回到普通检视恢复之前的记忆")
		main._close_card_inspection(true)
	check(effect_box_seen, "真实开包遇到带侧边特效说明的卡")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Pack toolbox scope failures: ", failures)
	quit(1 if failures else 0)
