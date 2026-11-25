extends "res://tests/event_cards_test.gd"

const PRESENTATION_SAVE := "/private/tmp/project-card-event-presentation-test.json"
const Table = preload("res://scripts/ui/event_card_table.gd")
const DeveloperEventTest = preload("res://scripts/flow/developer_event_test.gd")


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
	await _test_random_gold_receipt()
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
	check(is_instance_valid(table._deck_arrival) and table._deck.disabled and table._deck.get_node("GatherCard0").position.x < 0 and table._deck.get_node("GatherCard1").position.x > 0, "牌堆出现即从左右来牌，聚拢期间不会提前发牌")
	var arriving_top: EventCardView = table._deck_top
	check(arriving_top.get_index() == table._deck.get_child_count() - 1 and arriving_top.tarot_back == table._choice_backs[0].texture, "最后飞入的正式顶牌已经位于最上层")
	await create_timer(0.12).timeout
	await _capture("deck-gather")
	while is_instance_valid(table._deck_arrival): await process_frame
	check(not table._deck.disabled and not table.has_node("EventChoiceOverlay") and table._deck_top.position.is_zero_approx(), "聚拢完成后等待玩家点击抽牌")
	check(table._deck_top == arriving_top and arriving_top.get_index() == table._deck.get_child_count() - 1, "合拢前后连续使用同一张顶牌")
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
	check(projection.visible and height.call(top_right) > 6.0 and height.call(top_right) < 9.0 and height.call(bottom_right) < height.call(top_right) * 0.5 and table._deck.has_node("DeckNextCard"), "右上角轻抬，右下角只跟随少量位移（实际 %.2f、%.2f，有透视 %s）" % [height.call(top_right), height.call(bottom_right), projection.visible])
	await _capture("deck-corner-lift")
	jump.custom_step(Table.DECK_LEVEL_SECONDS + 0.01)
	check(not projection.visible and [top_right, bottom_right, top_left, bottom_left].all(func(point: Vector2) -> bool: return is_equal_approx(height.call(point), Table.DECK_LEVEL_POSE.w)), "四角抬平后共同停在牌堆上方")
	await _capture("deck-level")
	await create_timer(0.22).timeout
	check(top.position.y == -Table.DECK_LEVEL_POSE.w and table._deck_shadow.modulate.a > 0.0, "留在牌堆上时顶牌保持悬空并投影")
	table._deck.mouse_exited.emit()
	jump = table._deck_jump
	jump.pause()
	jump.custom_step(Table.DECK_CORNER_LAND_SECONDS)
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
	var event_test: DeveloperEventTest = main._developer_event_test
	event_test.event_id = "fortuna_gift"
	event_test.forced_option = 0
	event_test.forced_roll = 7
	var before: int = main.run_reward_state.gold
	check(maze.select_path("fortuna_gift") and maze.choose_story_option(0), "点击掷骰选项后保存金币结果")
	event_test.event_id = ""
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
	var parked_rect := Rect2(rolling.position, rolling.size)
	var parked_scale := float(rolling.presentation_scale)
	await process_frame
	var settled := maze._event_table.get_node_or_null("SettledEventDice") as Control
	check(settled != null and int(settled._result) == int(result.roll) and settled.position.x + settled.get_landing_center().x > maze._event_table._paper.position.x + maze._event_table._paper.size.x, "右侧保留已停骰子，结果栏在左")
	check(settled != null and settled.get_rect().is_equal_approx(parked_rect) and is_equal_approx(settled.presentation_scale, parked_scale), "切到结果页时骰子的停靠位置和尺寸连续")
	check(maze._event_table.revealing_result and not is_instance_valid(maze._event_gold_flight), "骰子停好后先逐字显示结果")
	maze._event_table._text_reveal.custom_step(30.0)
	await process_frame
	var coins := int(result.get("gold_awarded", 0))
	var flight: Node = maze._event_gold_flight
	check(coins > 0 and is_instance_valid(flight) and flight._positions.size() == coins and maze._event_gold_label.get_parsed_text().contains("获得%d枚金币" % coins), "掷骰后显示实际奖励并逐枚生成金币")
	if is_instance_valid(flight):
		check(main.run_reward_state.gold == before + coins and maze.displayed_event_gold() == before, "保存一次真实金币，飞行动画从此前可见余额开始")
		check(coins == 15, "福尔图纳的馈赠发放15枚金币")
		if coins > 1:
			var first_gap: float = flight._emission_time(1) - flight._emission_time(0)
			var last_gap: float = flight._emission_time(coins - 1) - flight._emission_time(coins - 2)
			check(is_zero_approx(flight._emission_time(0)) and is_equal_approx(flight._emission_time(coins - 1), 2.1) and first_gap > last_gap and last_gap > 0.0, "15枚金币在2.1秒内由疏到密逐枚飞出")
		await create_timer(0.5).timeout
		check(flight._elapsed < 0.0 and flight._landed == 0 and maze.displayed_event_gold() == before, "结果文字先单独展示，半秒内金币尚未飞出")
		var header: Control = maze._event_table._tabletop_header
		var bumps: Array[bool] = []
		flight.coin_landed.connect(func(_remaining: int):
			var scale: Vector2 = header._gold_icon.scale
			var bump: bool = header._gold_icon.visible and header._gold_icon.position.y < header.GOLD_ICON_POSITION.y and scale.is_equal_approx(Vector2.ONE * header.GOLD_BUMP_SCALE)
			var flash: float = header._gold_flash.get_shader_parameter("white_amount")
			bumps.append(bump and is_equal_approx(flash, 1.0) and int(header._gold.text) == maze.displayed_event_gold()))
		var icon_center: Vector2 = header._gold_icon.get_global_transform_with_canvas() * (header._gold_icon.size * 0.5)
		check(maze._event_table.gold_target().is_equal_approx(icon_center), "飞行落点与右上角实际金币中心对齐")
		await flight.coin_landed
		check(maze.displayed_event_gold() >= before + 1, "第一枚抵达后可见余额增加")
		await _capture("coin-hud-bump")
		if maze._event_gold_flight == flight: await flight.finished
		check(maze.displayed_event_gold() == main.run_reward_state.gold, "金币全落袋后实际余额和显示余额一致")
		check(bumps.size() == coins and not bumps.has(false), "每枚实际落袋都同步更新余额并触发金币图标放大闪白")
		await create_timer(header.GOLD_BUMP_TIME + 0.04).timeout
		check(not header._gold_icon.visible and header._gold_icon.position == header.GOLD_ICON_POSITION and header._gold_icon.scale == Vector2.ONE and is_zero_approx(header._gold_flash.get_shader_parameter("white_amount")), "最后一枚落袋后图标的位置、大小和颜色复位")
	check(main.load_run_from_path(PRESENTATION_SAVE) and maze._event_table.has_node("SettledEventDice"), "读档直接还原停好的骰子")
	var restored := maze._event_table.get_node_or_null("SettledEventDice") as Control
	check(restored != null and restored.get_rect().is_equal_approx(parked_rect) and is_equal_approx(restored.presentation_scale, parked_scale), "读档后的骰子对齐投掷时的停靠位置和尺寸")
	check(not is_instance_valid(maze._event_gold_flight) and maze.displayed_event_gold() == main.run_reward_state.gold, "读档保留金币实得数，已领奖励不重复播放或入账")
	await _capture("settled-dice")
	if restored != null:
		var rotation: Basis = restored.get_landing_rotation()
		var resting_shadow: PackedVector2Array = restored._model.shadow_outline(rotation, restored.TABLE_UP, restored.DIE_SIZE, 0.0)
		var rotating := Basis(Vector3.RIGHT, 0.55) * rotation
		var turning_shadow: PackedVector2Array = restored._model.shadow_outline(rotating, restored.TABLE_UP, restored.DIE_SIZE, 17.0)
		check(resting_shadow.size() >= 3 and turning_shadow.size() >= 3 and not is_equal_approx(_polygon_area(resting_shadow), _polygon_area(turning_shadow)), "骰子翻滚时光线投影改变轮廓面积")
	await _test_board_slide()


func _polygon_area(outline: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index: int in outline.size():
		twice_area += outline[index].cross(outline[(index + 1) % outline.size()])
	return absf(twice_area) * 0.5


func _test_random_gold_receipt() -> void:
	_deal("so_close")
	var before: int = main.run_reward_state.gold
	var event_test: DeveloperEventTest = main._developer_event_test
	event_test.event_id = "so_close"
	event_test.forced_option = 1
	event_test.forced_roll = 5
	check(maze.select_path("so_close") and maze.choose_story_option(1), "一步之遥通过正式选项结算随机金币")
	event_test.event_id = ""
	if not is_instance_valid(maze._story_roll): return
	await maze._story_roll.finished
	maze._event_table._text_reveal.custom_step(30.0)
	await process_frame
	var amount := int(maze.run.selected_path.story_result.gold_awarded)
	var flight: Node = maze._event_gold_flight
	check(amount >= 1 and amount <= 10 and main.run_reward_state.gold == before + amount and maze._event_gold_label.get_parsed_text() == "获得%d枚金币" % amount, "一步之遥的纸面、奖励金额和真实余额精确相符")
	if not is_instance_valid(flight): return
	var label: RichTextLabel = maze._event_gold_label
	check(label.text.contains("[color=#ae751b][b][keyword]") and label.get_global_rect().has_point(flight._origin), "金色金额复用粗体关键词动效，金币从文字位置爆开")
	var near_amount := true
	for point: Vector2 in flight._positions:
		near_amount = near_amount and point.x >= flight._origin.x + 44.0 and point.x <= flight._origin.x + 134.0
	check(near_amount and flight.SPREAD.x > 34.0 and flight.SPREAD.y > 13.0, "散落范围加宽，金币仍留在金额旁边")
	check(flight.COIN.get_size() == Vector2(25, 27) and flight.COIN == maze._event_table._tabletop_header.GOLD_ICON, "爆出的金币与余额金币共用原始像素素材")
	var edge_time: float = 0.25 / flight.TURN_SPEEDS.x
	check(flight.COIN_EDGE.get_size() == Vector2(5, 27) and edge_time < flight.SCATTER_TIME and flight._coin_face_width(0, edge_time) <= flight.COIN_EDGE.get_width(), "从金额飞出时已开始旋转，并在散落阶段显示原始厚度侧图")
	check(is_equal_approx(flight._shadow_width_scale(flight._coin_face_width(0, 0.0)), 1.0) and is_equal_approx(flight._shadow_width_scale(flight._coin_face_width(0, edge_time)), 0.2), "侧面金币的投影宽度缩到正面的五分之一")
	var airborne: Vector2 = flight._hover_position(0, flight.HOVER_END)
	var destination: Vector2 = maze._event_table.gold_target()
	var apex: Vector2 = flight._flight_position(airborne, destination, 0.5)
	check(airborne.y < flight._positions[0].y - 16.0 and apex.y < airborne.lerp(destination, 0.5).y - 40.0 and flight._flight_position(airborne, destination, 1.0).is_equal_approx(destination), "金币先浮空，随后沿上扬弧线准确落袋")
	if "--capture-events" in OS.get_cmdline_user_args():
		var elapsed: float = flight._elapsed
		flight.set_process(false)
		flight._elapsed = 0.075
		flight.queue_redraw()
		await _capture("coin-burst")
		flight._elapsed = edge_time
		flight.queue_redraw()
		await _capture("coin-edge-early")
		flight._elapsed = flight._launches[0] + flight.FLIGHT_TIME * 0.72
		flight.queue_redraw()
		await _capture("coin-flip-trail")
		flight._elapsed = elapsed
		flight.set_process(true)
	await create_timer(flight.REWARD_PAUSE + flight.SCATTER_TIME + 0.03).timeout
	await _capture("coins-scattered")
	check(flight._elapsed >= flight.SCATTER_TIME and flight._landed == 0 and flight._positions.size() == amount, "第一枚金币先离开文字并在桌面浮空，然后才开始落袋")
	check(main.load_run_from_path(PRESENTATION_SAVE) and not is_instance_valid(maze._event_gold_flight) and maze.displayed_event_gold() == before + amount, "金币飞行中读档恢复最终余额，保留奖励记录且不重播")


func _test_board_slide() -> void:
	var button := maze._find_exit_button(maze.complete_event.bind(true))
	check(is_instance_valid(button), "掷骰结果有继续旅程按钮")
	if not is_instance_valid(button): return
	main.run_save_path = PRESENTATION_SAVE.path_join("cannot-save.json")
	button.pressed.emit()
	main.run_save_path = PRESENTATION_SAVE
	check(maze.run.step == ShortMazeRunState.Step.EVENT and not maze._event_presentation_busy(), "保存失败留在事件结果页")
	var table: Control = maze._event_table
	var art: Control = table._board
	var card := table.get_node("SelectedEventCard") as Control
	var paper: Control = table._paper
	var dice := table.get_node("SettledEventDice") as Control
	var pieces: Array[Control] = [art, card, paper, dice]
	var origins: Array[Vector2] = []
	for piece: Control in pieces: origins.append(piece.global_position)
	button = maze._find_exit_button(maze.complete_event.bind(true))
	button.pressed.emit()
	var retract: Tween = maze._event_board_slide
	check(is_instance_valid(retract) and maze._event_table == table and table.busy, "成功继续后暂留旧板并锁定操作")
	if not is_instance_valid(retract): return
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PRESENTATION_SAVE))
	check(int(checkpoint.short_maze.run.step) == ShortMazeRunState.Step.CHOOSING, "滑出前已将抽牌状态写入存档")
	retract.pause()
	retract.custom_step(Table.BOARD_SECONDS * 0.8)
	var displacement := art.global_position - origins[0]
	check(displacement.y < 0.0 and art.get_global_rect().end.y > 0.0 and maze._event_table == table, "旧板向上移动且未提前换页")
	for index: int in range(1, pieces.size()):
		check((pieces[index].global_position - origins[index]).is_equal_approx(displacement), "事件牌、纸面和骰子与木板等距移动")
	await _capture("board-retract")
	retract.custom_step(Table.BOARD_SECONDS * 0.21)
	var arrive: Tween = maze._event_board_slide
	var next: Control = maze._event_table
	check(is_instance_valid(arrive) and next != table and next.get_global_rect().end.y < 0.0, "旧板退完后下一叠牌从屏外开始滑入")
	if not is_instance_valid(arrive): return
	arrive.pause()
	arrive.custom_step(Table.BOARD_SECONDS * 0.45)
	next._deck.pressed.emit()
	check(next.busy and next.cards.is_empty() and next.get_global_rect().position.y < 0.0, "滑入期间牌堆尚不可抽取")
	await _capture("board-arrive")
	arrive.custom_step(Table.BOARD_SECONDS * 0.56)
	check(not maze._event_presentation_busy() and not is_instance_valid(maze._board_input_blocker) and next.get_global_rect().position == origins[0], "新板落准原位并恢复交互")
	while is_instance_valid(next._deck_arrival): await process_frame
	next._deck.pressed.emit()
	check(not next.cards.is_empty(), "落稳后可以抽下一叠事件牌")
	if not next.cards.is_empty(): await next.choices_ready


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
	var flight: Control = main._card_acquisition if kind == "card" else maze._event_reward_flight
	check(is_instance_valid(flight), "继续旅程触发飞入 " + kind)
	if not is_instance_valid(flight): return
	var toolbox_x: float = main.emblem_library.position.x
	var shook := false
	while is_instance_valid(flight):
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
