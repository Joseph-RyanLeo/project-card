extends SceneTree

## 正式显示壳、真实拖放输入与Tween逐帧检查；耗时数据只在测试中采集。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var assertions := 0
var failures := 0
var pointer := Vector2.ZERO
var stage := "startup"
var timings: Dictionary = {}
var frame_times: Dictionary = {}
var previous_usec := 0

func _initialize() -> void:
	process_frame.connect(record_frame)
	_run.call_deferred()

func record_frame() -> void:
	var now := Time.get_ticks_usec()
	if previous_usec > 0:
		if not frame_times.has(stage): frame_times[stage] = []
		frame_times[stage].append((now - previous_usec) / 1000.0)
	previous_usec = now

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func measure(label: String, action: Callable) -> void:
	var began := Time.get_ticks_usec()
	action.call()
	if not timings.has(label): timings[label] = []
	timings[label].append((Time.get_ticks_usec() - began) / 1000.0)

func move(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = outer
	Input.warp_mouse(outer)
	root.push_input(event, true)
	await process_frame

func button(point: Vector2, pressed: bool, index: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func click(point: Vector2, index: int = MOUSE_BUTTON_LEFT) -> void:
	await move(point)
	await button(point, true, index)
	await button(point, false, index)

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("服务动画专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	if "nested-profile" in OS.get_cmdline_user_args():
		main.set_script(preload("res://tests/performance/service_profiled_main.gd"))
		main.short_maze_enabled = true
	main.run_save_path = "/private/tmp/project-card-service-animation.json"
	root.add_child(shell)
	shell.apply_display_mode(0)
	await create_timer(0.3).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1707)
	maze.choose_talent("sentry_guard")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	maze.select_path(maze.run.paths[0].path_id)
	maze.complete_event(false)
	maze.select_path(maze.run.paths[0].path_id)
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(maze._enhancement_slot._empty_outline.visible and maze._enhancement_slot._empty_outline.size == Vector2(99, 136), "强化显示真实卡牌大小的空槽")
	await capture("empty-enhancement")
	var data := {"kind": &"card", "owned_card": owned}
	maze._enhancement_slot._drop_data(Vector2.ZERO, data)
	check(not maze._enhancement_slot._empty_outline.visible and maze._enhancement_slot._card_view.get_owned_card() == owned, "强化槽显示拖入的原实例")
	maze.apply_card_enhancement(0)
	maze.select_path(maze.run.paths[0].path_id)
	measure("open_services", main._open_shop_card_services)
	await process_frame
	check(main._shop_card_service_panel.is_visible_in_tree() and main._shop_service_slot._empty_outline.visible, "商店共用服务面板显示空槽且收藏可见")
	await capture("empty-services")
	check(main._shop_service_slot._can_drop_data(Vector2.ZERO, data), "商店槽原生拖放接收合法实例")
	main._shop_service_slot._drop_data(Vector2.ZERO, data)
	check(main._shop_service_card_id == owned.instance_id and not main._shop_service_slot._empty_outline.visible, "拖卡后商店选中正确实例")
	var collection_slot: Control = main._shop_service_slot._source.parent
	check(collection_slot.get_child_count() == 0, "原卡面移入服务槽后来源为空，不留下快照副本")
	await click(main._shop_service_slot._card_view.get_global_rect().get_center())
	await click(Vector2(1000, 620))
	check(main._shop_service_card_id.is_empty() and collection_slot.get_child_count() == 1, "服务槽中真实卡面可以抓取并归还收藏")
	var source_view: CardView = collection_slot.get_child(0)
	await click(source_view.get_global_rect().get_center())
	check(not main._click_carry_data.is_empty(), "收藏卡牌真实单击进入携带")
	await click(main._shop_service_slot.get_global_rect().get_center())
	check(main._click_carry_data.is_empty() and main._shop_service_slot._card_view == source_view and main._shop_service_card_id == owned.instance_id and main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned, "真实单击放入商店服务槽移动原卡面并保持拥有权")
	var sell := main._shop_card_service_actions.get_node("ServiceSellButton") as Button
	check(not sell.disabled and sell.text.contains("金币"), "拖入卡牌后显示出售收益")
	var count_before: int = main.owned_card_collection.size()
	sell.pressed.emit()
	var confirmation: ConfirmationDialog
	for child: Node in main.ordinary_shop_layer.get_children():
		if child is ConfirmationDialog and child.title == "确认出售卡牌": confirmation = child
	check(confirmation != null and main.owned_card_collection.size() == count_before, "服务先展示出售确认而不提前销毁")
	if confirmation != null: confirmation.canceled.emit()
	await process_frame
	main._close_shop_card_services()
	main.ordinary_shop_open = false
	main.ordinary_shop_panel.visible = false
	maze.leave_shop()
	main.set_world_view(main.WorldView.COLLECTION, false)
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.35).timeout
	var card: CardView = main._inspection_card_view
	var before: int = card.health_label.text.to_int()
	stage = "rolling_numbers"
	# 正式水符文增加2生命，实时重算仍走Main正式路径。
	owned.resolved_runes[0] = CardData.ElementType.WATER
	owned.rune_revealed[0] = true
	measure("reveal_refresh", func(): main._refresh_owned_card_status_visuals(owned))
	check(card.health_label.text.to_int() == before and card._squad_health_preview_target == before + 2, "揭晓后从旧数字开始滚动，目标已即时提交")
	await create_timer(0.24).timeout
	check(card.health_label.scale.x > 1.1 and card.health_label.text.to_int() > before and card.health_label.text.to_int() < before + 2, "放大期间数字同步滚动")
	var large_scale: float = card.health_label.scale.x
	var rolling_tween: Tween = card._battle_number_tweens.get(&"squad_preview_health")
	main._refresh_owned_card_status_visuals(owned)
	check(card._battle_number_tweens.get(&"squad_preview_health") == rolling_tween, "重复刷新同一目标不重启滚动或缩放")
	await create_timer(0.25).timeout
	check(card.health_label.scale.x > 1.0 and card.health_label.scale.x < CardView.STAT_PULSE_SCALE and card.health_label.scale.x < large_scale + 0.1, "滚动后半程数字逐渐缩小")
	await create_timer(0.22).timeout
	check(card.health_label.text.to_int() == before + 2 and card.health_label.scale.is_equal_approx(Vector2.ONE) and card._stat_pulse_tweens.is_empty(), "数字到终值时缩回正常尺寸并清理Tween")
	var old_health := card.health_label.text.to_int()
	owned.set_emblem_slot(0, {"instance_id": &"service_bread", "emblem_id": &"面包", "temporary": false})
	measure("sticker_refresh", func(): main._refresh_owned_card_status_visuals(owned))
	check(card.health_label.text.to_int() == old_health and not card._stat_pulse_tweens.is_empty(), "纹章同样从旧数字启动滚动与缩放")
	await create_timer(0.7).timeout
	check(card.health_label.text.to_int() > old_health and card.health_label.scale.is_equal_approx(Vector2.ONE), "纹章动画完成后数字和尺寸正确")
	main._close_card_inspection(true)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await create_timer(0.25).timeout
	var controller: CelestialIndicatorController = main.celestial_indicators
	# 测试主动新增日月星前，先把正式英雄已有哨位放到库存下部，避免图标重叠。
	maze._place_sentry_in_stock(String(maze.stock[0].instance_id), Vector2(150, 150))
	var inventory: Array[Dictionary] = []
	for kind: int in CelestialIndicator.Kind.values():
		var item := CelestialIndicator.new()
		item.kind = kind as CelestialIndicator.Kind
		item.instance_id = StringName("service_indicator_%d" % kind)
		inventory.append(item.capture_state())
	controller.restore_state({"items": inventory, "next_attachment_order": 1})
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var moon: CelestialIndicator = controller.items[0]
	var moon_view: Control = controller._tray_views[moon.instance_id]
	stage = "indicator_return"
	await test_return(moon_view, false, true, "库存月亮单击右键取消")
	await test_return(moon_view, true, false, "库存月亮长按非法放置")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var slot: BoardSlot = main.front_row.get_squads()[0]
	slot.get_squad_data().attach_indicator(moon, Vector2(49, 60), 1)
	slot.set_squad_data(slot.get_squad_data())
	controller._sync_tray()
	await create_timer(0.2).timeout
	moon_view = slot.get_celestial_indicator(moon.instance_id)
	await test_return(moon_view, false, false, "部署月亮单击非法放置")
	check(slot.get_squad_data().has_indicator(moon.kind) and not controller._tray_views.has(moon.instance_id), "非法放置不把部署月亮卸回库存")
	main.set_world_view(main.WorldView.COLLECTION, false)
	var sentry: Control
	for child: Node in maze._sentry_bar.get_children():
		if child.get_script() == preload("res://scripts/ui/sentry_indicator_view.gd"):
			sentry = child
			break
	await test_return(sentry, true, true, "哨位长按右键取消")
	check(maze.stock.size() == 1 and maze.deployed.is_empty(), "取消哨位不改变库存和部署")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var equipment: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/coarse_bandage.tres"))
	check(slot.get_squad_data().equip_item(equipment), "真实装备绑定到原随从")
	slot.set_squad_data(slot.get_squad_data())
	await create_timer(0.2).timeout
	await test_return(slot.get_equipment_indicator(), false, true, "装备指示物单击右键取消")
	await test_return(slot.get_equipment_indicator(), true, false, "装备指示物长按非法放置")
	check(slot.get_squad_data().get_equipped_item() == equipment, "非法放置装备保持原宿主，不卸回收藏")
	# 收藏增至72张、战场六队，检查稳定帧和交互CPU耗时。
	stage = "setup72"
	while main.owned_card_collection.size() < 72:
		main.owned_card_collection.create_card(owned.card_data)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	for index: int in 5:
		var extra: OwnedCard = main.owned_card_collection.get_cards()[main.owned_card_collection.size() - 1 - index]
		main.back_row.add_squad(SquadData.from_owned_card(extra), index)
	await create_timer(0.3).timeout
	stage = "idle72"
	for index: int in 60:
		measure("indicator_idle", func(): controller._process(0.0))
		await process_frame
	stage = "services72"
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._open_shop_card_services()
	for index: int in 12:
		measure("select_service72", func(): main._select_shop_service_card(data))
		await process_frame
	await capture("services")
	await test_service_transactions(owned, equipment)
	export_profile()
	shell.queue_free()
	await process_frame
	print("卡槽、数字与回位专项：%d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func test_service_transactions(owned: OwnedCard, equipment: OwnedCard) -> void:
	stage = "transactions"
	var selected: Array[Dictionary] = [owned.emblem_slots[0].duplicate(true)]
	var price: int = main.ordinary_shop_service.config.tear_service.prices_by_return_count["1"]
	main.run_reward_state.add_gold(30)
	var gold: int = main.run_reward_state.gold
	var saved_path: String = main.run_save_path
	var instance_id: StringName = owned.instance_id
	main.run_save_path = "/private/tmp/project-card-missing-service-parent/run.json"
	stage = "tear_failure72"
	measure("tear_save_failure72", func(): main._execute_shop_tear(instance_id, selected, price))
	await process_frame
	check(main.owned_card_collection.get_by_instance_id(instance_id) != null and main.run_reward_state.gold == gold and main.emblem_library.get_inventory_item(&"service_bread").is_empty(), "撕卡保存失败回退卡牌、金币和返还贴纸")
	check(main.front_row.get_squads()[0].get_squad_data().get_equipped_item().instance_id == equipment.instance_id, "撕卡失败恢复原装备归属")
	main.run_save_path = saved_path
	var retained_slot: Control = main.collection_card_row.get_child(4)
	var retained_owned: OwnedCard = retained_slot.get_meta("owned_card")
	if "nested-profile" in OS.get_cmdline_user_args(): main.service_profile.clear()
	stage = "tear_success72"
	measure("tear_commit72", func(): main._execute_shop_tear(instance_id, selected, price))
	if "nested-profile" in OS.get_cmdline_user_args(): print("TEAR_STEPS ", JSON.stringify(main.service_profile))
	await process_frame
	check(main.owned_card_collection.get_by_instance_id(instance_id) == null and main.run_reward_state.gold == gold - price and not main.emblem_library.get_inventory_item(&"service_bread").is_empty(), "正式撕卡扣费、返还选择贴纸并销毁宿主")
	check(main.owned_card_collection.get_by_instance_id(equipment.instance_id) != null and main.front_row.get_squads().is_empty(), "撕卡后装备留在收藏且场上宿主解除")
	check(main._find_collection_slot_for_owned_card(retained_owned) == retained_slot, "交易保留未改变的收藏卡面节点")
	var returned_slot: Control = main._find_collection_slot_for_owned_card(main.owned_card_collection.get_by_instance_id(equipment.instance_id))
	check(returned_slot != null and not returned_slot.get_meta("is_deployed_ghost", false), "退还装备更新为可交互卡面")
	await click(retained_slot.get_child(0).get_global_rect().get_center())
	check(not main._click_carry_data.is_empty() and main._click_carry_data.get("owned_card") == retained_owned, "交易后移动槽位仍能真实抓取正确实例")
	await click(Vector2(30, 350), MOUSE_BUTTON_RIGHT)
	check(main._shop_service_slot._empty_outline.visible, "已销毁服务卡恢复空槽")
	stage = "load72"
	check(main.load_run_from_path(saved_path) and main.owned_card_collection.get_by_instance_id(instance_id) == null and not main.emblem_library.get_inventory_item(&"service_bread").is_empty(), "撕卡结果磁盘读回不重复返还")
	await process_frame
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._open_shop_card_services()
	var sold: OwnedCard = main.owned_card_collection.get_by_instance_id(equipment.instance_id)
	var value: int = main._shop_card_sale_price(sold)
	main._select_shop_service_card({"kind": &"equipment_card", "owned_card": sold})
	gold = main.run_reward_state.gold
	if "nested-profile" in OS.get_cmdline_user_args(): main.service_profile.clear()
	stage = "sell_success72"
	measure("sell_commit72", func(): main._execute_shop_sale(sold.instance_id, value))
	if "nested-profile" in OS.get_cmdline_user_args(): print("SALE_STEPS ", JSON.stringify(main.service_profile))
	await process_frame
	check(main.owned_card_collection.get_by_instance_id(sold.instance_id) == null and main.run_reward_state.gold == gold + value and main._shop_service_slot._empty_outline.visible, "正式出售更新金币并清空服务槽")
	stage = "load72"
	check(main.load_run_from_path(saved_path) and main.owned_card_collection.get_by_instance_id(sold.instance_id) == null and main.run_reward_state.gold == gold + value, "出售结果立即保存并可读回")
	await process_frame

func test_return(view: Control, native: bool, cancel: bool, label: String) -> void:
	var source := view.get_global_rect().get_center()
	var destination := Vector2(30, 350)
	await move(source)
	await button(source, true)
	if native:
		await move(source + Vector2(35, 2), true)
		check(shell.internal_viewport.gui_is_dragging(), label + "进入真实原生拖拽")
	else:
		await button(source, false)
	await move(destination, native)
	if cancel:
		await button(destination, true, MOUSE_BUTTON_RIGHT)
		await button(destination, false, MOUSE_BUTTON_RIGHT)
		if native: await button(destination, false)
	else:
		await button(destination, not native)
		if not native: await button(destination, false)
	await process_frame
	check(view.visible and view._returning_to_source and view._indicator_visual.position.length() > 20, label + "从手持位置开始飞回")
	await create_timer(0.32).timeout
	check(view._indicator_visual.position.is_equal_approx(Vector2.ZERO) and not view._returning_to_source, label + "最终回到原位置")

func capture(label: String) -> void:
	if "capture" not in OS.get_cmdline_user_args(): return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("/private/tmp/project-card-service-%s.png" % label) == OK, "保存服务槽预览")

func export_profile() -> void:
	var result := {"cpu": {}, "frames": {}, "display": DisplayServer.get_name()}
	for group: Dictionary in [timings, frame_times]:
		var destination: Dictionary = result.cpu if group == timings else result.frames
		for key: String in group:
			var values: Array = group[key].duplicate()
			values.sort()
			var total := 0.0
			for value: float in values: total += value
			destination[key] = {"n": values.size(), "mean_ms": total / values.size(), "p95_ms": values[mini(floori(values.size() * 0.95), values.size() - 1)], "max_ms": values.back()}
	var suffix := "baseline" if "baseline" in OS.get_cmdline_user_args() else "final"
	var path := "/private/tmp/project-card-service-performance-%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("SERVICE_PERFORMANCE ", JSON.stringify(result))
