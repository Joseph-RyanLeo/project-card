extends "res://tests/service_interaction_revision_20261020_test.gd"

## 正式窗口中的收藏、服务卡归还与战场整队回位；检查动画中途的原位虚影。
const RETURN_SAVE := "/private/tmp/project-card-return-origin-ghost.json"
var _captured: Dictionary = {}

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("归位虚影专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = RETURN_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var owned := _service_card("return_origin")
	owned.is_new = false
	var state := owned.capture_state()
	main.set_world_view(main.WorldView.COLLECTION, false)
	for native: bool in [true, false]:
		var view := _show_owned(owned)
		await carry_and_release(view, native, Vector2(1210, 340))
		await verify_card_return(view, "收藏非法落点")
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_card_services()
	await create_timer(0.4).timeout
	for native: bool in [true, false]:
		main._select_shop_service_card({"kind": &"card", "owned_card": owned})
		await create_timer(0.3).timeout
		await carry_and_release(main._shop_service_slot._card_view, native, Vector2(1180, 350))
		var view: CardView
		for index: int in 5:
			var source: Control = main._find_collection_slot_for_owned_card(owned)
			if is_instance_valid(source) and source.get_child_count() > 0:
				view = source.get_child(0) as CardView
				if is_instance_valid(view._return_ghost): break
			await process_frame
		await verify_card_return(view, "服务卡归还收藏")
	main._close_shop_card_services()
	main._toggle_ordinary_shop()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var member: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var squad := SquadData.from_owned_card(owned)
	check(squad.insert_card(member.get_battlefield_card(), 1, SquadData.TwoCardLayout.COMPACT), "建立真实双卡小队")
	squad.bind_owned_card(member.get_battlefield_card(), member)
	main.front_row.add_squad(squad, 0)
	main.front_row.set_prefer_minion(false)
	await create_timer(0.3).timeout
	for native: bool in [true, false]:
		var source: BoardSlot = main.front_row.get_squads()[0]
		await carry_and_release(source.get_card_views()[-1], native, Vector2(1210, 340))
		for index: int in 5:
			if is_instance_valid(source.get_card_views()[0]._return_ghost): break
			await process_frame
		var cards := source.get_card_views()
		check(cards.size() == 2 and is_instance_valid(cards[0]._return_ghost) and is_instance_valid(cards[1]._return_ghost), "整队归位时每张成员卡都保留原位虚影")
		await verify_card_return(cards[0], "整队归位", source)
		check(not is_instance_valid(cards[1]._return_ghost), "整队落回后同时清理其他成员虚影")
	check(owned.capture_state() == state and squad.get_card_count() == 2, "所有回位与虚影均未修改OwnedCard或真实小队成员")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(RETURN_SAVE)
	print("Return origin ghost: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func carry_and_release(view: CardView, native: bool, invalid: Vector2) -> void:
	var start := view.get_global_transform_with_canvas() * Vector2(22, 70)
	await _motion(start)
	await _mouse(start, true)
	if native:
		await _motion(start + Vector2(38, 4), true)
		check(shell.internal_viewport.gui_is_dragging(), "启动真实原生卡牌拖拽")
	else:
		await _mouse(start, false)
		check(not main._click_carry_data.is_empty(), "启动真实卡牌点击携带")
	await _motion(invalid, native)
	if not native: await _mouse(invalid, true)
	await _mouse(invalid, false)

func verify_card_return(view: CardView, label: String, squad: BoardSlot = null) -> void:
	check(is_instance_valid(view) and is_instance_valid(view._return_ghost), label + "动画开始时原位虚影仍存在")
	if not is_instance_valid(view) or not is_instance_valid(view._return_ghost): return
	var ghost: CardView = view._return_ghost
	check(ghost.get_owned_card() == view.get_owned_card() and ghost.is_snapshot_mode() and not ghost._drag_enabled and ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + "虚影引用同一实例，仅显示且不可交互")
	check(is_equal_approx(ghost.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), label + "虚影使用统一透明度")
	var position := ghost.position
	var origin_parent := ghost.get_parent() as CanvasItem
	var stable := true
	var frames := 0
	while is_instance_valid(view._return_ghost):
		stable = stable and ghost.position.distance_to(position) < 0.1
		if not _captured.has(label):
			await RenderingServer.frame_post_draw
			shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-return-ghost-%d.png" % _captured.size())
			_captured[label] = true
		else:
			await process_frame
		frames += 1
		if frames > 60: break
	check(stable and frames > 0 and frames <= 60, label + "移动中的卡牌不带走原位虚影")
	await process_frame
	check(not is_instance_valid(view._return_ghost) and view.modulate.a == 1.0, label + "落回后才恢复实体且删除虚影")
	var landed := view.get_global_transform_with_canvas().origin
	var target := origin_parent.get_global_transform_with_canvas() * position
	check(landed.distance_to(target) < 0.1, label + "实体最终落回虚影所在位置 %s → %s" % [target, landed])
	if squad != null: check(not squad.is_layout_animating(), label + "清理时整队归位动画已经结束")
