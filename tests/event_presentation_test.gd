extends "res://tests/event_cards_test.gd"

const PRESENTATION_SAVE := "/private/tmp/project-card-event-presentation-test.json"
const Table = preload("res://scripts/ui/event_card_table.gd")


func _run() -> void:
	create_timer(35.0).timeout.connect(func():
		push_error("事件演出测试超时")
		quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = PRESENTATION_SAVE
	root.add_child(shell)
	await process_frame
	maze = main.maze_controller
	await _test_deck_and_dice()
	await _test_reward("ioann_prayer", 0, "indicator")
	await _test_reward("strange_casino", 5, "sticker")
	await _test_reward("so_close", 0, "card")
	await _test_card_stack()
	await _test_reward("strange_casino", 5, "sticker", true)
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(PRESENTATION_SAVE)
	print("事件演出：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _test_deck_and_dice() -> void:
	_deal("fortuna_gift")
	var table: Control = maze._event_table
	main.set_world_view(main.WorldView.COLLECTION, true)
	main._view_tween.pause()
	main._view_tween.custom_step(main.VIEW_TWEEN_DURATION * 0.9)
	var park_button: TextureButton = main._tabletop_park_button
	check(maze._panel.get_global_rect().intersects(park_button.get_global_rect()) and park_button.z_index < maze._panel.z_index, "下移时事件板盖住与收板按钮重叠的部分")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	table._deck.mouse_entered.emit()
	var jump: Tween = table._deck_jump
	jump.pause()
	jump.custom_step(Table.DECK_CORNER_LIFT_SECONDS)
	var top: EventCardView = table._deck_top
	var projection: InspectionCardSurface = top._back_projection
	var top_right := Vector2(EventCardView.CARD_SIZE.x, 0)
	var bottom_right := EventCardView.CARD_SIZE
	var top_left := Vector2.ZERO
	var bottom_left := Vector2(0, EventCardView.CARD_SIZE.y)
	var deck_inverse: Transform2D = table._deck.get_global_transform_with_canvas().affine_inverse()
	var height := func(anchor: Vector2) -> float:
		var point := projection.card_canvas_point(anchor) if projection.visible else top.get_global_transform_with_canvas() * anchor
		return anchor.y - (deck_inverse * point).y
	check(projection.visible and height.call(top_right) > 6.0 and height.call(top_right) < 9.0 and height.call(bottom_right) < height.call(top_right) * 0.5 and table._deck.has_node("DeckNextCard"), "右上角轻抬，右下角只跟随少量位移")
	await _capture("deck-corner-lift")
	jump.custom_step(Table.DECK_LEVEL_SECONDS + Table.DECK_LEVEL_HOLD_SECONDS * 0.5)
	check(not projection.visible and [top_right, bottom_right, top_left, bottom_left].all(func(point: Vector2) -> bool: return is_equal_approx(height.call(point), Table.DECK_LEVEL_POSE.w)), "四角抬平后共同停在牌堆上方")
	await _capture("deck-level")
	jump.custom_step(Table.DECK_LEVEL_HOLD_SECONDS * 0.5 + Table.DECK_CORNER_LAND_SECONDS)
	check(absf(height.call(top_right)) < 0.25 and height.call(top_left) > 3.0 and height.call(bottom_right) > 1.5 and height.call(bottom_left) > 1.5, "右上角先触堆，其他角仍在空中")
	await _capture("deck-corner-land")
	jump.custom_step(Table.DECK_SETTLE_SECONDS + 0.01)
	check(top.position.is_zero_approx() and is_zero_approx(top.rotation) and not projection.visible, "顶牌落回原位和原始画面")
	table._deck.mouse_entered.emit()
	jump = table._deck_jump
	jump.pause()
	jump.custom_step(Table.DECK_CORNER_LIFT_SECONDS)
	var launched_tilt := top.back_tilt
	table._deck.pressed.emit()
	check(not launched_tilt.is_zero_approx() and table.cards[0]._back_projection == projection and table.cards[0].back_tilt.is_equal_approx(launched_tilt), "空中点击从顶牌当前透视继续发牌")
	await table.choices_ready
	check(table.cards[0].back_tilt.is_zero_approx() and not projection.visible, "首张牌飞入候选位置时回正")
	var candidate: EventCardView = table.cards[0]
	var origin := candidate.position
	candidate.mouse_entered.emit()
	await create_timer(0.20).timeout
	check(is_equal_approx(candidate._choice_lift, EventCardView.HOVER_LIFT) and candidate.position == origin, "三选一卡牌抬升，保留点击锚点")
	candidate.mouse_exited.emit()
	await create_timer(0.20).timeout
	check(is_zero_approx(candidate._choice_lift), "候选移出时落回")
	check(maze.select_path("fortuna_gift") and maze.choose_story_option(0), "点击掷骰选项后保存结果")
	var result: Dictionary = maze.run.selected_path.story_result
	var rolling: Control = maze._story_roll
	check(is_instance_valid(rolling) and not rolling.visible and not maze.complete_event(), "文字溶解期间保留旧页并阻止继续")
	await create_timer(Table.INK_SECONDS * 0.46).timeout
	await _capture("ink-dissolve")
	await create_timer(Table.INK_SECONDS * 0.54 + 0.12).timeout
	check(rolling.visible and not maze._event_table._paper.visible, "文字消失后才掷骰")
	var roll_origin: float = rolling.position.x
	await create_timer(rolling.ROLL_SECONDS + rolling.RESULT_SECONDS + 0.03).timeout
	check(rolling.position.x > roll_origin and not maze._event_table._paper.visible, "骰子停稳右移时左侧结果仍未出现")
	await rolling.finished
	var settled := maze._event_table.get_node_or_null("SettledEventDice") as Control
	check(settled != null and int(settled._result) == int(result.roll) and settled.position.x + settled.get_landing_center().x > maze._event_table._paper.position.x + maze._event_table._paper.size.x, "右侧保留已停骰子，结果栏在左")
	check(main.load_run_from_path(PRESENTATION_SAVE) and maze._event_table.has_node("SettledEventDice"), "读档直接还原停好的骰子")
	await _capture("settled-dice")


func _test_reward(event_id: String, option: int, kind: String, overflow: bool = false) -> void:
	if event_id == "ioann_prayer":
		maze.story_events.config.appearance[event_id] = {"floors": [1], "formal": true}
	_deal(event_id)
	if overflow:
		for index: int in main.emblem_library.get_inventory_capacity():
			maze._grant_emblem("面包", "event_test_fill:%d" % index)
	check(maze.select_path(event_id) and maze.choose_story_option(option), "事件成功发放" + kind)
	var ids := maze.event_reward_ids(kind)
	check(ids.size() == 1 and maze._event_reward_previews.has(String(ids[0])), "结算页预览实际实例 " + kind)
	if ids.is_empty(): return
	var id: StringName = ids[0]
	check(main.load_run_from_path(PRESENTATION_SAVE) and maze.event_reward_ids(kind) == ids, "存档可恢复未演出的奖励 " + kind)
	check(not _destination_visible(kind, id), "点击继续之前目的地隐藏该实例 " + kind)
	await process_frame
	if kind == "card":
		var preview: Control = maze._event_reward_previews[String(id)]
		var card := preview.get_child(0) as CardView
		check(card.scale == Vector2.ONE and preview.get_parent().name == "EventRewardCards", "奖励卡按原生尺寸放在独立右栏")
		check(preview.get_global_rect().position.x >= maze._event_table._paper.get_global_rect().end.x, "奖励叠牌让出事件正文与选项")
	await _capture("reward-" + kind)
	var button := maze._find_exit_button(maze.complete_event.bind(true))
	check(button != null, "实际结算页有继续旅程按钮")
	if button == null: return
	button.pressed.emit()
	var flight: Control = maze._event_reward_flight
	check(is_instance_valid(flight), "继续旅程触发飞入 " + kind)
	if not is_instance_valid(flight): return
	var toolbox_x: float = main.emblem_library.position.x
	var shook := false
	while is_instance_valid(maze._event_reward_flight):
		await process_frame
		if kind == "sticker" and is_instance_valid(maze._event_reward_flight):
			shook = shook or not is_equal_approx(main.emblem_library.position.x, toolbox_x)
	check(_destination_visible(kind, id) and maze.event_reward_ids(kind).is_empty(), "奖励飞入后显示原实例 " + kind)
	if kind == "sticker": check(shook, "纹章着陆触发工具箱震动")
	if overflow:
		check(is_instance_valid(main._toolbox_overlay) and maze.run.selected_path.path_id == event_id, "超额奖励飞进临时区域后打开工具箱，仍停留在结算页")


func _test_card_stack() -> void:
	_deal("so_close")
	check(maze.select_path("so_close") and maze.choose_story_option(0), "打开真实奖励结算页验证多卡叠放")
	var items: Array = maze.run.selected_path.reward_items
	for id: String in ["militia", "shieldwall_private"]:
		var card: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/%s.tres" % id))
		items.append({"kind": "card", "id": String(card.instance_id)})
	maze.refresh()
	var column: Control = maze._event_table.get_node("EventRewardCards")
	var first := column.get_child(0) as Control
	var second := column.get_child(1) as Control
	check(column.get_child_count() == 3 and first.get_rect().intersects(second.get_rect()) and first.position.x < second.position.x, "三张原尺寸奖励卡沿右侧依次重叠")
	var second_rest := second.z_index
	first.mouse_entered.emit()
	check(first.z_index > second.z_index, "悬停时被盖住的奖励卡置顶")
	first.mouse_exited.emit()
	check(first.z_index < second_rest, "移开时奖励卡恢复叠放顺序")
	await _capture("reward-card-stack")


func _destination_visible(kind: String, id: StringName) -> bool:
	match kind:
		"indicator":
			var view: Control = main.celestial_indicators._tray_views.get(id)
			return is_instance_valid(view) and view.visible
		"sticker":
			for entry: Control in main.emblem_library._entries:
				if StringName(entry.definition.returned_state.instance_id) == id: return entry.visible
		"card":
			var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(id)
			var slot: Control = main._find_collection_slot_for_owned_card(owned)
			return is_instance_valid(slot) and slot.visible
	return false
