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
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
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
		await click(main._inspection_library_toggle.get_global_rect().get_center())
		await create_timer(0.3).timeout
		check(main._inspection_library_expanded, "开包期间仍可临时展开工具箱")
		if remembered:
			await click(main._inspection_library_toggle.get_global_rect().get_center())
			await create_timer(0.3).timeout
			await _finish_cards(sequence)
		else:
			main._close_card_inspection(true)
			await process_frame
		check(main._last_minion_inspection_library_expanded == remembered, "整包完成或展开时取消均不保存开包工具箱状态")
		main._open_card_inspection(owned.card_data, owned)
		await create_timer(0.35).timeout
		check(main._inspection_library_expanded == remembered, "回到普通检视恢复之前的记忆")
		main._close_card_inspection(true)
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Pack toolbox scope failures: ", failures)
	quit(1 if failures else 0)
