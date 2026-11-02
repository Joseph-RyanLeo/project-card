extends "res://tests/service_origin_revision_20261021_test.gd"

const FOLLOWUP_SAVE := "/private/tmp/project-card-service-drag-followup.json"


func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("服务拖动后续回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = FOLLOWUP_SAVE
	root.add_child(shell)
	root.size = Vector2i(2560, 1440)
	await create_timer(0.4).timeout
	main.run_reward_state.gold = 1000
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var definition: CardData = load("res://resources/cards/field_beer_machine.tres")
	main.owned_card_collection.create_card(definition)
	var owned: OwnedCard = main.owned_card_collection.create_card(definition)
	owned.is_new = false
	owned.rune_revealed.assign([false, true, false])
	owned.resolved_runes.assign([CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WOOD])
	check(owned.get_battlefield_card() != owned.card_data, "同名实例使用独立战场引用，覆盖此前丢失绑定的条件")
	var original := owned.capture_state()
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await create_timer(0.3).timeout
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.4).timeout
	var sale: Control = main._shop_service_slot
	var exchange: Control = main._shop_exchange_slots[0]
	await verify_runes(sale, owned)
	await verify_service_hover(sale)
	await _drag(sale._card_view, exchange)
	await create_timer(0.4).timeout
	check(sale._selected_card == null and exchange._selected_card == owned and main._shop_service_card_id == &"" and main._shop_exchange_ids[0] == owned.instance_id, "原生拖动从出售槽直接移入置换槽，双方索引同步")
	if exchange._selected_card != owned:
		quit(1)
		return
	await verify_runes(exchange, owned)
	await verify_service_hover(exchange)
	await _click(exchange._card_view)
	check(not main._click_carry_data.is_empty(), "置换槽支持真实点击携带")
	await _motion(sale.get_global_rect().get_center())
	await _mouse(sale.get_global_rect().get_center(), true)
	await _mouse(sale.get_global_rect().get_center(), false)
	await create_timer(0.4).timeout
	check(sale._selected_card == owned and exchange._selected_card == null and main._shop_exchange_ids[0] == &"", "点击携带从置换槽直接移入出售槽")
	if sale._selected_card == owned:
		await verify_runes(sale, owned)
		var original_view: CardView = sale._card_view
		await _drag(original_view, main._shop_exchange_slots[1])
		await create_timer(0.4).timeout
		check(main._shop_exchange_slots[1]._card_view == original_view, "服务槽之间移交原卡面，不复制实例或重建来源")
		await _drag(main._shop_exchange_slots[1]._card_view, main._shop_exchange_slots[2])
		await create_timer(0.4).timeout
		check(main._shop_exchange_ids[1] == &"" and main._shop_exchange_ids[2] == owned.instance_id, "置换槽之间也可直接移动")
	check(owned.capture_state() == original, "全部拖动和悬停不揭晓符文，不修改实例永久状态")
	main._close_shop_card_services()
	await create_timer(0.4).timeout
	var restored := _show_owned(owned)
	check(restored != null and restored.get_owned_card() == owned and not restored._is_display_rune_known(0) and restored._is_display_rune_known(1), "离开服务后原实例与符文覆盖仍正确")
	shell.queue_free()
	await process_frame
	await verify_enhancement_rearrangement()
	print("Service drag followup: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)


func verify_runes(slot: Control, owned: OwnedCard) -> void:
	var view: CardView = slot._card_view
	check(view != null and view.get_owned_card() == owned, "服务卡面保留真实OwnedCard")
	var data: Dictionary = view._build_drag_data(Vector2(25, 65))
	var preview: CardDragPreview = CardView.create_drag_visual(data)
	main._click_carry_layer.add_child(preview)
	await process_frame
	var carried := preview._snapshot_visual.get_source_card_view() as CardView
	check(carried.get_owned_card() == owned, "拖拽预览仍绑定同名卡的正确实例")
	check(not carried._is_display_rune_known(0) and carried._is_display_rune_known(1) and not carried._is_display_rune_known(2), "拖拽预览保持未揭晓／已揭晓／未揭晓，不泄露定义符文")
	check(carried._get_display_rune_element(1) == CardData.ElementType.WATER, "已揭晓符文沿用该实例的固定元素")
	preview.queue_free()
	await process_frame


func verify_service_hover(slot: Control) -> void:
	var view: CardView = slot._card_view
	await _motion(Vector2(1200, 700))
	await _motion(view.get_global_rect().get_center())
	check(view._mouse_hovered and view._hover_punch_tween != null, "指向服务卡面复用战场轻晃反馈")
	await create_timer(view.hover_effect_delay_seconds + 0.3).timeout
	check(view._hover_effect_active and view.showing_effect, "持续指向服务卡面显示卡牌效果")
	await _motion(Vector2(1200, 700))
	await create_timer(0.25).timeout
	check(not view.showing_effect and not view._hover_effect_active, "移开恢复符文展示，清理持续指向状态")


func verify_enhancement_rearrangement() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = FOLLOWUP_SAVE
	root.add_child(shell)
	await create_timer(0.4).timeout
	maze = main.maze_controller
	_deal("loose_coins", 1000)
	check(maze.select_path("loose_coins") and maze.complete_event() and maze.select_path(maze.run.paths[0].path_id), "正式迷宫进入强化事件")
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var first: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	var second: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"))
	main.front_row.add_squad(SquadData.from_owned_card(first), 0)
	main.back_row.add_squad(SquadData.from_owned_card(second), 0)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._refresh_drag_availability()
	check(maze._enhancement_slot.is_visible_in_tree() and main.front_row._drop_enabled and main.back_row._drop_enabled, "强化槽可见且未收板时，前后排仍接受正常布阵")
	await create_timer(0.3).timeout
	var source: BoardSlot = main.front_row.get_squads()[0]
	await native_pick(source.get_card_views()[0])
	var move_point: Vector2 = main.back_row.placement_overlay.get_global_transform_with_canvas() * Vector2(100, 70)
	await _motion(move_point, true)
	await _mouse(move_point, false)
	await create_timer(0.4).timeout
	check(main.front_row.get_squad_count() == 0 and main.back_row.get_squad_count() == 2, "强化界面可用真实原生拖动跨排换位")
	var moved: BoardSlot
	var target: BoardSlot
	for slot: BoardSlot in main.back_row.get_squads():
		if slot.get_squad_data().get_action_source_instance() == first: moved = slot
		else: target = slot
	await native_pick(moved.get_card_views()[0])
	await create_timer(0.3).timeout
	var grab: Vector2 = main._native_carry_data.grab_local_position
	var target_rect: Rect2 = main.back_row._get_slot_visual_rect(target)
	var stack_point: Vector2 = main.back_row.placement_overlay.get_global_transform_with_canvas() * Vector2(target_rect.position.x - 99.0 + 45.0 + grab.x, target_rect.position.y + grab.y)
	await _motion(stack_point, true)
	await create_timer(0.3).timeout
	stack_point.x += 1.0
	await _motion(stack_point, true)
	await _mouse(stack_point, false)
	await create_timer(0.4).timeout
	check(main.back_row.get_squad_count() == 1 and main.back_row.get_squads()[0].get_squad_data().get_card_count() == 2, "强化界面可用真实原生拖动堆叠随从")
	check(maze._enhancement_slot._selected_card == null and not maze.run.selected_path.has("enhancement_result"), "布阵不误入强化槽，不提前强化或扣费")
	shell.queue_free()
	await process_frame
