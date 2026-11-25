extends "res://tests/event_cards_test.gd"

const COPY_SAVE := "/private/tmp/project-card-event-card-references-save.json"
const References = preload("res://scripts/ui/event_card_reference_text.gd")


func _run() -> void:
	create_timer(35.0).timeout.connect(func(): push_error("事件人名与结果文字专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = COPY_SAVE
	root.add_child(shell)
	await process_frame
	await process_frame
	maze = main.maze_controller
	maze.new_run(1729)
	check(maze.choose_talent("sentry_guard"), "通过天赋选择进入本局事件轮")
	await _test_spoils_copy()
	await _test_named_minion()
	await _test_dice_and_gold()
	shell.queue_free()
	await process_frame
	print("事件人名与结果文字：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)


func _open_event(id: String) -> bool:
	for definition: Dictionary in maze.developer_event_catalog():
		if definition.path_id != id: continue
		return maze.deal_developer_event(definition) and maze.select_path(id)
	return false


func _option(index: int) -> Button:
	for button: Button in maze._detail_body.find_children("*", "Button", true, false):
		if button.get_meta("story_option", -1) == index: return button
	return null


func _test_spoils_copy() -> void:
	var definition: CardData = load("res://resources/cards/musketeer.tres")
	var first: OwnedCard = main.owned_card_collection.create_card(definition)
	var second: OwnedCard = main.owned_card_collection.create_card(definition)
	first.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 3)
	second.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 7)
	main.front_row.add_squad(SquadData.from_owned_card(first), 0)
	main.back_row.add_squad(SquadData.from_owned_card(second), 0)
	check(_open_event("spoils_dispute"), "从正式事件池打开分赃不均")
	if maze.run.selected_path.get("path_id") != "spoils_dispute": return
	await process_frame
	var table: Control = maze._event_table
	table._text_reveal.custom_step(30.0)
	await process_frame
	var chosen_a := maze._story_locked_target(0)
	var chosen_b := maze._story_locked_target(1)
	check(chosen_a != chosen_b and chosen_a.card_data == chosen_b.card_data, "事件锁定两张同名的不同随从")
	var body: RichTextLabel
	for node: Control in table.detail_body.get_children():
		if node is References: body = node
	check(is_instance_valid(body) and not body.get_parsed_text().contains("*"), "正文用真实名字替换占位符")
	if is_instance_valid(body):
		await _hover_first_reference(body)
		_check_preview(table, chosen_a, "正文中的人名也可悬停查看对应卡牌")
	var option_a := _option(1)
	var option_b := _option(2)
	if not is_instance_valid(option_a) or not is_instance_valid(option_b):
		check(false, "两项支持选项均可用")
		return
	check(option_a.text == "支持" + chosen_a.card_data.display_name and option_b.text == option_a.text, "支持选项使用实际名字")
	await _move(option_a.get_global_rect().get_center())
	_check_preview(table, chosen_a, "指向第一个支持选项的名字显示第一张同名随从")
	await _capture("spoils-card-reference")
	await _move(option_b.get_global_rect().get_center())
	_check_preview(table, chosen_b, "指向另一个同名随从显示其实际卡牌实例")
	await _move(Vector2(32, 32))
	check(not is_instance_valid(table._reference_card), "移开名字收起预览")
	await _move(option_a.get_global_rect().get_center())
	await _click(option_a)
	check(maze.run.selected_path.get("story_result", {}).get("option_index") == 1, "点击选项里的带链接人名仍然选择该选项")
	var text := ""
	for line: Control in maze._event_table.result_lines:
		text += line.get_parsed_text() if line is RichTextLabel else line.text
	check(not text.contains("*") and not text.contains("随从A") and not text.contains("B随从"), "结果正文和奖励均替换人名占位符")
	check(main.load_run_from_path(COPY_SAVE) and maze._story_locked_target(0).instance_id == chosen_a.instance_id, "读档后结果仍引用原来锁定的随从")


func _check_preview(table: Control, expected: OwnedCard, message: String) -> void:
	var preview: Control = table._reference_card
	check(is_instance_valid(preview) and preview.get_child(0).get_owned_card() == expected, message)


func _test_named_minion() -> void:
	check(_open_event("silvermoon_guide"), "打开含具名随从的银月引路事件")
	if maze.run.selected_path.get("path_id") != "silvermoon_guide": return
	await process_frame
	var table: Control = maze._event_table
	table._text_reveal.custom_step(30.0)
	await process_frame
	var line: RichTextLabel = table.detail_body.get_child(1)
	await _hover_first_reference(line)
	var preview: Control = table._reference_card
	check(is_instance_valid(preview) and preview.get_child(0).card_data.id == &"silvermoon_priest", "其他事件里的具名随从也显示对应卡面")
	await _move(Vector2(32, 32))


func _test_dice_and_gold() -> void:
	check(_open_event("fortuna_gift"), "打开福尔图纳的馈赠")
	if maze.run.selected_path.get("path_id") != "fortuna_gift": return
	main._developer_event_test.event_id = "fortuna_gift"
	main._developer_event_test.forced_option = 0
	main._developer_event_test.forced_roll = 7
	var gold_before: int = main.run_reward_state.gold
	check(maze.choose_story_option(0), "实际掷骰并提交金币奖励")
	main._developer_event_test.event_id = ""
	if not is_instance_valid(maze._story_roll): return
	await maze._story_roll.finished
	var table: Control = maze._event_table
	var line: Control = table.result_lines.front()
	var amount: RichTextLabel = maze._event_gold_label
	check(table.revealing_result and table.has_node("SettledEventDice") and amount.visible_characters == 0, "骰子停好后金额等待逐字显示")
	await create_timer(0.25).timeout
	check(line.visible_characters > 0 and line.visible_ratio < 1.0 and not is_instance_valid(maze._event_gold_flight), "正文逐字显现期间金币未启动")
	table._text_reveal.pause()
	table._text_reveal.custom_step(
		(line.get_total_character_count() - line.visible_characters) * table.CHARACTER_SECONDS + table.TEXT_LINE_PAUSE + 0.11
	)
	check(amount.visible_characters > 0 and amount.visible_ratio < 1.0 and not is_instance_valid(maze._event_gold_flight), "金额显示一半时仍未启动金币")
	var button := maze._find_exit_button(maze.complete_event.bind(true))
	await _move(button.get_global_rect().get_center())
	await _click(button)
	check(maze._event_table == table and not table.revealing_result and amount.visible_ratio == 1.0, "第一次点击继续只补全文字")
	await process_frame
	var flight: Node = maze._event_gold_flight
	var award := int(maze.run.selected_path.story_result.gold_awarded)
	check(is_instance_valid(flight) and flight._elapsed < 0.0 and flight._landed == 0, "金额完整显示后才开始原有金币停顿")
	check(main.run_reward_state.gold == gold_before + award and maze.displayed_event_gold() == gold_before, "当前只入账一次，画面余额等待金币落袋")
	if not is_instance_valid(flight): return
	await flight.finished
	await _click(button)
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and main.run_reward_state.gold == gold_before + award, "再次点击进入下一轮且奖励只发一次")


func _hover_first_reference(label: RichTextLabel) -> void:
	var font := label.get_theme_font("normal_font")
	var font_size := label.get_theme_font_size("normal_font_size")
	var x := 0.0
	for part: Dictionary in label._parts:
		var width := font.get_string_size(part.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if part.has("card"):
			await _move(label.get_global_rect().position + Vector2(x + width * 0.5, font_size * 0.5))
			return
		x += width


func _move(logical_point: Vector2) -> void:
	var point: Vector2 = shell.render_container.get_global_transform_with_canvas() * logical_point
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame
