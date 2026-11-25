extends "res://tests/service_interaction_revision_20261020_test.gd"

const DELIVERY_SAVE := "/private/tmp/project-card-event-food-delivery.json"
const FAILED_SAVE := "/private/tmp/project-card-no-event-food-save-directory/run.json"


func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("事件食物交付专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = DELIVERY_SAVE
	root.add_child(shell)
	await process_frame
	await process_frame
	maze = main.maze_controller
	maze.new_run(1731)
	check(maze.choose_talent("sentry_guard"), "进入正式事件轮")
	var stock: Array[Dictionary] = []
	for index: int in 4:
		stock.append({"instance_id": "bread_%d" % index, "emblem_id": "面包"})
	stock.append({"instance_id": "apple", "emblem_id": "苹果"})
	stock.append({"instance_id": "torch", "emblem_id": "火把"})
	check(main.emblem_library.receive_stickers(stock), "准备四枚同名食物、苹果和非食物纹章")
	for event: Dictionary in maze.developer_event_catalog():
		if event.path_id == "lone_druid":
			check(maze.deal_developer_event(event) and maze.select_path(event.path_id), "打开独行德鲁伊")
			break
	var delivery: Control = maze._event_item_delivery
	if is_instance_valid(delivery):
		await _verify_delivery(delivery)
		await _verify_mixed_delivery()
	else:
		check(false, "事件右侧出现交付栏")
	shell.queue_free()
	await process_frame
	print("事件食物交付：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _verify_delivery(delivery: Control) -> void:
	var submit := _option(0)
	check(submit.disabled and maze._detail_body.is_ancestor_of(submit), "未放入食物时，交付选项留在左侧列表并禁用")
	check(maze._event_table._paper.get_global_rect().end.x < delivery.get_global_rect().position.x, "事件右侧只有独立放置区")
	check(submit.tooltip_text.begins_with("必定 · "), "确定事件结果显示必定")
	var original_entry := _stock_entry(&"bread_0")
	await _click(delivery.open_button)
	await create_timer(0.85).timeout
	check(main.current_world_view == main.WorldView.COLLECTION and delivery.get_parent() == main._toolbox_overlay, "工具箱和交付区在下半视角同时可用")
	check(_stock_entry(&"bread_0") == original_entry, "工具箱展开沿用同一个库存图标节点")
	await _verify_overlapping_shadow()
	for native: bool in [true, false]:
		await _verify_resize(delivery, native)
	var before: Array = main.emblem_library.get_inventory_state()
	var target := delivery.get_global_rect().get_center()
	await _drop(_stock_entry(&"torch"), target, true)
	check(maze._story_food_ids.is_empty(), "非食物纹章无法进入交付区")
	await _drop(_stock_entry(&"bread_0"), target, true)
	await _drop(_stock_entry(&"bread_1"), target, false)
	check(maze._story_food_ids == [&"bread_0", &"bread_1"] and submit.disabled, "未满三份仍禁用")
	var first := delivery.item_entry(&"bread_0") as EmblemLibraryEntry
	var second := delivery.item_entry(&"bread_1") as EmblemLibraryEntry
	var footprint := first.size * first.scale
	check(not Rect2(first.position, footprint).grow(2).intersects(Rect2(second.position, footprint)), "同位置放入会避让，保留两像素间距")
	var new_point := delivery.get_global_rect().position + Vector2(105, 136)
	await _drop(first, new_point, false)
	check(first.get_global_rect().get_center().distance_to(new_point) <= 3 and maze._story_food_ids == [&"bread_0", &"bread_1"], "可以自由重摆，保留原交付先后顺序")
	check(main.emblem_library.get_inventory_state() == before and not _stock_entry(&"bread_0").drag_enabled, "放入不更改库存，原位虚影不能重复拿取")
	await _drop(delivery.item_entry(&"bread_1"), _stock_entry(&"bread_1").get_global_rect().get_center(), true)
	check(maze._story_food_ids == [&"bread_0"] and _stock_entry(&"bread_1").drag_enabled, "可以从交付区拖回原格")
	for id: StringName in [&"bread_2", &"bread_1", &"bread_3"]:
		await _drop(_stock_entry(id), target, id != &"bread_3")
	check(not submit.disabled and maze._story_food_ids == [&"bread_0", &"bread_2", &"bread_1", &"bread_3"], "可按放置顺序暂放四份，原列表中的交付选项启用")
	await capture("event-food-delivery")
	var selected: Array = maze._story_food_ids.duplicate()
	var positions: Dictionary = maze._event_food_positions.duplicate()
	original_entry = _stock_entry(&"bread_0")
	await _click(main._toolbox_overlay.get_node("CloseToolbox"))
	await create_timer(0.35).timeout
	check(maze._story_food_ids == selected and delivery.get_parent() == maze._event_table, "收回工具箱时保留交付排列和可用选项")
	check(maze._event_food_positions == positions, "收起工具箱保留自由摆放位置")
	check(_stock_entry(&"bread_0") == original_entry, "工具箱收起也不重建库存图标")
	await capture("event-food-delivery-options")
	await _verify_commit(selected)


func _verify_commit(selected: Array) -> void:
	var inventory: Array = main.emblem_library.get_inventory_state()
	var positions: Dictionary = maze._event_food_positions.duplicate()
	var rng: int = maze.run.rng.state
	main.run_save_path = FAILED_SAVE
	await _click(_option(0))
	check(maze._story_food_ids == selected and main.emblem_library.get_inventory_state() == inventory and maze.run.rng.state == rng, "写盘失败恢复原纹章、格位、随机状态和放置顺序")
	check(maze._event_food_positions == positions, "写盘失败恢复交付区内的具体摆放位置")
	check(not _option(0).disabled and not maze.run.selected_path.has("story_result"), "失败后原列表可直接重试")
	main.run_save_path = DELIVERY_SAVE
	await _click(_option(0))
	check(maze.run.selected_path.get("story_result", {}).get("option_index") == 0 and maze._story_food_ids.is_empty(), "成功提交并清空交付区")
	var seeds := 0
	for item: Dictionary in main.emblem_library.get_inventory_state():
		if item.emblem_id == "种子": seeds += 1
	check(seeds == 3 and selected.slice(0, 3).all(func(id: StringName) -> bool: return _stock_entry(id) == null), "按放置顺序消耗前三枚并发放三枚种子")
	check(is_instance_valid(_stock_entry(&"bread_3")) and is_instance_valid(_stock_entry(&"apple")) and is_instance_valid(_stock_entry(&"torch")), "第四枚与未放入的纹章仍在原库存")
	var committed: Array = main.emblem_library.get_inventory_state()
	check(main.load_run_from_path(DELIVERY_SAVE) and main.emblem_library.get_inventory_state() == committed and not maze.choose_story_option(0), "磁盘读档恢复已交付状态且无法重复领取")


func _verify_mixed_delivery() -> void:
	# 在测试副本给同一事件加一个卡牌条件，检查共用区域，不更动正式事件配置。
	maze.new_run(1732)
	check(maze.choose_talent("sentry_guard"), "另开测试局验证混合交付")
	var index: int = maze.content.free_events.find_custom(func(event: Dictionary) -> bool: return event.path_id == "lone_druid")
	var mixed: Dictionary = maze.content.free_events[index].duplicate(true)
	var card_option: Dictionary = mixed.options.back().duplicate(true)
	card_option.label = "提供一张随从"
	card_option["target"] = "minion"
	mixed.options.append(card_option)
	var card_index: int = mixed.options.size() - 1
	maze.content.free_events[index] = mixed
	main.emblem_library.receive_stickers([
		{"instance_id": "mixed_bread_2", "emblem_id": "面包"},
		{"instance_id": "mixed_bread_0", "emblem_id": "面包"},
		{"instance_id": "mixed_bread_1", "emblem_id": "面包"},
	])
	check(maze.deal_developer_event(mixed) and maze.select_path(mixed.path_id), "用临时事件配置同时打开卡牌和食物条件")
	var delivery: Control = maze._event_item_delivery
	if not is_instance_valid(delivery) or not is_instance_valid(delivery.card_slot): return
	check(_option(0).disabled and _option(card_index).disabled, "混合事件的两个选项均需放入材料")
	await _click(delivery.open_button)
	await create_timer(0.85).timeout
	var target := delivery.get_global_rect().get_center()
	for id: StringName in [&"mixed_bread_0", &"mixed_bread_1", &"mixed_bread_2"]:
		await _drop(_stock_entry(id), target, true)
	check(not _option(0).disabled and _option(card_index).disabled, "放食物只启用食物选项")
	var stock: Array = main.emblem_library.get_inventory_state()
	await _click(main._toolbox_overlay.get_node("CloseToolbox"))
	await create_timer(0.35).timeout
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var card := _show_owned(owned)
	await _drag(card, delivery)
	await create_timer(0.35).timeout
	check(_option(0).disabled and not _option(card_index).disabled and delivery.card_slot._selected_card == owned, "放入真实卡牌后启用卡牌选项")
	check(maze._story_food_ids.is_empty() and main.emblem_library.get_inventory_state() == stock, "放入卡牌时原放置纹章回到原库存位置")
	await _click(delivery.open_button)
	await create_timer(0.35).timeout
	await _drop(_stock_entry(&"mixed_bread_0"), target, true)
	check(maze._story_food_ids == [&"mixed_bread_0"] and _option(card_index).disabled and delivery.card_slot._selected_card == null, "放回纹章可将暂存卡牌归还原位")


func _option(index: int) -> Button:
	for button: Button in maze._detail_body.find_children("*", "Button", true, false):
		if button.get_meta("story_option", -1) == index: return button
	return null


func _stock_entry(id: StringName) -> EmblemLibraryEntry:
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if StringName(entry.definition.returned_state.instance_id) == id: return entry
	return null


func _verify_overlapping_shadow() -> void:
	var library: EmblemLibraryView = main.emblem_library
	var original := library.get_inventory_state()
	var fixture := original.duplicate(true)
	fixture.append({"instance_id": "shadow_lower", "emblem_id": "面包", "storage": "drop", "drop_position": [16, 15]})
	fixture.append({"instance_id": "shadow_upper", "emblem_id": "面包", "storage": "drop", "drop_position": [15, 13]})
	if library.restore_inventory_state(fixture):
		await _motion(Vector2(870, 325))
		var lower := _stock_entry(&"shadow_lower")
		var upper := _stock_entry(&"shadow_upper")
		upper._shadow.hide()
		var unlit := await _shadow_frame()
		upper._shadow.show()
		var shaded := await _shadow_frame()
		var footprint := Rect2i(lower._icon.get_global_rect())
		var inverse := lower._icon.get_global_transform_with_canvas().affine_inverse()
		var texture := lower._icon.texture.get_image()
		var darkened := false
		for y: int in range(footprint.position.y, footprint.end.y):
			for x: int in range(footprint.position.x, footprint.end.x):
				var point := Vector2i(x, y)
				var original_color := texture.get_pixelv(Vector2i(inverse * (Vector2(point) + Vector2.ONE * 0.5)))
				if original_color.a >= 0.99 and unlit.get_pixelv(point).is_equal_approx(original_color) and shaded.get_pixelv(point).v < original_color.v - 0.05:
					darkened = true
					break
			if darkened: break
		check(darkened, "上层纹章阴影能实际压暗下层纹章的不透明像素")
		library.restore_inventory_state(original)
	else:
		check(false, "建立两枚重叠临时纹章来验证阴影")


func _shadow_frame() -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	return shell.internal_viewport.get_texture().get_image()


func _verify_resize(delivery: Control, native: bool) -> void:
	var stock := _stock_entry(&"apple")
	var stock_target := stock._icon.get_global_rect().get_center()
	var event_target := delivery.get_global_rect().get_center()
	var outside_event := Vector2(delivery.get_global_rect().position.x - 4, event_target.y)
	var preview := await _begin_carry(stock, native, Vector2(4, 6)) as InspectionItemDrag.StickerPreview
	if not is_instance_valid(preview):
		check(false, "工具箱纹章生成缩放预览")
		return
	await _motion(outside_event, native)
	check(preview.scale.is_equal_approx(Vector2(4, 4)), "交付区外保留工具箱倍率")
	await _verify_scale_transition(preview, event_target, 4, 2, native)
	await _release(event_target, native)
	var staged := delivery.item_entry(&"apple") as EmblemLibraryEntry
	if not is_instance_valid(staged):
		check(false, "缩放后仍能放入交付区")
		return
	preview = await _begin_carry(staged, native, Vector2(-3, 4)) as InspectionItemDrag.StickerPreview
	if not is_instance_valid(preview):
		check(false, "交付区纹章生成缩放预览")
		return
	await _verify_scale_transition(preview, stock_target, 2, 4, native)
	await _release(stock_target, native)
	check(maze._story_food_ids.is_empty() and _stock_entry(&"apple").drag_enabled, "放大后按同一抓取点归还工具箱原格")


func _verify_scale_transition(preview: InspectionItemDrag.StickerPreview, point: Vector2, start_scale: float, end_scale: float, native: bool) -> void:
	check(is_equal_approx(preview.scale.x, start_scale), "穿过边界前使用来源倍率")
	await _motion(point, native)
	var tween := preview._scale_tween
	check(is_instance_valid(tween), "进入目标区域启动缩放补间")
	if is_instance_valid(tween):
		tween.pause()
		tween.custom_step(0.06)
		check(preview.scale.x > minf(start_scale, end_scale) and preview.scale.x < maxf(start_scale, end_scale), "跨区后经过中间大小")
		check((preview.get_global_transform_with_canvas() * preview.pivot_offset).distance_to(point) <= 2, "缩放过程中图案抓取点跟住鼠标")
		tween.custom_step(0.15)
	check(preview.scale.is_equal_approx(Vector2.ONE * end_scale), "补间结束后匹配目标区域倍率")


func _drop(source: EmblemLibraryEntry, target: Vector2, native: bool) -> void:
	await _begin_carry(source, native)
	await _motion(target, native)
	await _release(target, native)


func _begin_carry(source: EmblemLibraryEntry, native: bool, offset := Vector2.ZERO) -> Control:
	var start := source._icon.get_global_rect().get_center() + offset
	var id: String = source.definition.returned_state.instance_id
	await _motion(start)
	var hover: Control = shell.internal_viewport.gui_get_hovered_control()
	var hover_name := String(hover.name) if is_instance_valid(hover) else "无"
	var drag_status := "%s（指向 %s，允许拖动 %s）" % [id, hover_name, source.drag_enabled]
	await _mouse(start, true)
	if native:
		await _motion(start + Vector2(38, 4), true)
		check(shell.internal_viewport.gui_is_dragging(), "启动原生纹章拖拽 " + drag_status)
		var data: Variant = shell.internal_viewport.gui_get_drag_data()
		return data.get("drag_visual") as Control if data is Dictionary else null
	await _mouse(start, false)
	check(not main._click_carry_data.is_empty(), "启动点击携带 " + drag_status)
	return main._click_carry_preview


func _release(target: Vector2, native: bool) -> void:
	if not native: await _mouse(target, true)
	await _mouse(target, false)
	await create_timer(0.3).timeout
