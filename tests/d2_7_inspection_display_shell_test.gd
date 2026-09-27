extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var display := load("res://scenes/GameDisplay.tscn").instantiate() as GameDisplay
	root.add_child(display)
	await process_frame
	await process_frame
	var main = display.main_screen
	var shell := display.render_container
	var viewport := display.internal_viewport
	check(shell.process_mode == Node.PROCESS_MODE_ALWAYS, "正式显示壳在树暂停时仍转发根窗口输入")
	check(main.process_mode == Node.PROCESS_MODE_PAUSABLE, "正式 Main 显式作为战斗暂停边界")
	check(viewport.process_mode == Node.PROCESS_MODE_INHERIT, "内部视口继承显示容器暂停模式")

	var owned: OwnedCard
	for slot: Control in main._get_collection_card_slots():
		if slot.get_child_count() == 0:
			continue
		var candidate := slot.get_child(0) as CardView
		if candidate != null and candidate.get_owned_card() != null:
			owned = candidate.get_owned_card()
			break
	check(owned != null, "初始收藏提供真实 OwnedCard 战斗单位")
	if owned != null and not main._is_owned_card_deployed(owned):
		main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
		await process_frame
	for slot: Control in main._get_collection_card_slots():
		if main.front_row.get_squad_count() >= 6:
			break
		var card := slot.get_meta("owned_card", null) as OwnedCard
		if card != null and card.card_data.card_type == CardData.CardType.MINION and not main._is_owned_card_deployed(card):
			main.front_row.add_squad(SquadData.from_owned_card(card), main.front_row.get_squad_count())
	if owned != null and main.enemy_front_row.get_squads().is_empty():
		main.enemy_front_row.add_squad(SquadData.from_card(owned.card_data), 0)
		await process_frame
	var started: bool = main.start_battle(2026, true)
	check(started, "正式 GameDisplay 入口启动真实 2026 种子战斗")
	check(main.battle_controller.current_result == BattleController.Result.NONE, "战斗夹具包含双方小队且未立即结算")
	await create_timer(0.5).timeout
	check(main.battle_pause_button.visible and main.battle_pause_button.text == "⏸️", "战斗速度档左侧显示暂停按钮")
	var running_time: float = main.battle_controller.elapsed_seconds
	await _click_pause_button(display, main)
	check(main.get_tree().paused and main.battle_pause_button.text == "▶️", "根窗口点击暂停按钮暂停战斗并显示继续图标")
	await _check_frozen(main, "手动暂停按钮")
	await _click_pause_button(display, main)
	check(not main.get_tree().paused and main.battle_pause_button.text == "⏸️", "暂停期间根窗口仍可点击按钮继续战斗")
	await create_timer(0.1).timeout
	check(main.battle_controller.elapsed_seconds > running_time, "手动继续后战斗逻辑时间恢复推进")
	var source_card: CardView
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_back_row, main.enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			if slot.card_view != null and slot.card_view.is_visible_in_tree() and slot.card_view.get_global_rect().intersects(Rect2(0, 0, 1280, 720)):
				source_card = slot.card_view
				break
		if source_card != null:
			break
	if source_card == null:
		for slot: Control in main._get_collection_card_slots():
			if slot.get_child_count() == 0:
				continue
			var candidate := slot.get_child(0) as CardView
			if candidate != null and candidate.is_visible_in_tree() and candidate.get_global_rect().intersects(Rect2(0, 0, 1280, 720)):
				source_card = candidate
				break
	check(source_card != null, "真实战斗卡面可用于根窗口命中")
	if source_card != null:
		await _open_from_root(display, source_card)
		check(is_instance_valid(main._inspection_overlay), "根窗口右键经 SubViewportContainer 打开检视")
		if is_instance_valid(main._inspection_overlay):
			await _check_frozen(main, "运行中右键开启")
			var frozen_at_close: float = main.battle_controller.elapsed_seconds
			await _send_key(KEY_ESCAPE)
			await create_timer(0.25, true).timeout
			check(main._inspection_overlay == null and not main.get_tree().paused, "根窗口 Escape 关闭并恢复战斗")
			await create_timer(0.1).timeout
			check(main.battle_controller.elapsed_seconds > frozen_at_close, "Escape 关闭后战斗逻辑时间继续推进")

		await _close_path(display, main, source_card, "卡面右键", MOUSE_BUTTON_RIGHT, Vector2(640, 360))
		await _close_path(display, main, source_card, "暗幕左键", MOUSE_BUTTON_LEFT, Vector2(640, 700))

		await _open_from_root(display, source_card)
		await process_frame
		var close_button := main._inspection_overlay.get_node("CloseInspectionButton") as Control if is_instance_valid(main._inspection_overlay) else null
		if close_button != null:
			var button_position := close_button.get_global_transform_with_canvas() * (close_button.size * 0.5)
			await _send_mouse(display, MOUSE_BUTTON_LEFT, button_position)
			await create_timer(0.25, true).timeout
			check(main._inspection_overlay == null and not main.get_tree().paused, "根窗口真实点击关闭按钮关闭并恢复战斗")
		else:
			check(false, "检视层创建关闭按钮")

		await _open_from_root(display, source_card)
		await _send_key(KEY_ESCAPE)
		await create_timer(0.25, true).timeout
		await _open_from_root(display, source_card)
		await _send_key(KEY_ESCAPE)
		await create_timer(0.25, true).timeout
		check(main._inspection_overlay == null and not main.get_tree().paused, "连续两次开关检视均恢复战斗")

		# 从真实暂停按钮进入暂停，再通过根窗口右键打开卡面检视。
		await _click_pause_button(display, main)
		await _open_from_root(display, source_card)
		check(
			is_instance_valid(main._inspection_overlay) and main.get_tree().paused,
			"手动暂停后可经根窗口右键打开检视层"
		)
		if is_instance_valid(main._inspection_overlay):
			await _send_key(KEY_ESCAPE)
			await create_timer(0.25, true).timeout
			check(main._inspection_overlay == null and main.get_tree().paused, "Esc 关闭后保留原手动暂停状态")
		await _click_pause_button(display, main)
		check(not main.get_tree().paused, "关闭检视后仍可通过暂停按钮继续战斗")

	display.queue_free()
	await process_frame
	print("Display shell inspection failures: ", failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _root_position(display: GameDisplay, internal_position: Vector2) -> Vector2:
	return display.render_container.get_global_transform_with_canvas() * internal_position


func _send_mouse(display: GameDisplay, button: MouseButton, internal_position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = _root_position(display, internal_position)
	root.push_input(event, true)
	await process_frame
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event, true)
	await process_frame


func _click_pause_button(display: GameDisplay, main: Control) -> void:
	var button := main.battle_pause_button as Control
	var internal_position := button.get_global_transform_with_canvas() * (button.size * 0.5)
	await _send_mouse(display, MOUSE_BUTTON_LEFT, internal_position)


func _open_from_root(display: GameDisplay, card: CardView) -> void:
	var internal_position := card.get_global_transform_with_canvas() * (card.size * 0.5)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = _root_position(display, internal_position)
	root.push_input(event, true)
	await process_frame
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _check_frozen(main: Control, label: String) -> void:
	var controller := main.battle_controller as BattleController
	var before_time: float = controller.elapsed_seconds
	var cooldowns: Array[float] = []
	for state: BattleSquadState in controller.player_states + controller.enemy_states:
		cooldowns.append(state.remaining_cooldown)
	var projectile_count: int = controller._pending_projectile_contexts.size()
	await create_timer(0.2, true).timeout
	var cooldowns_after: Array[float] = []
	for state: BattleSquadState in controller.player_states + controller.enemy_states:
		cooldowns_after.append(state.remaining_cooldown)
	check(
		main.get_tree().paused
		and is_equal_approx(controller.elapsed_seconds, before_time)
		and cooldowns_after == cooldowns
		and controller._pending_projectile_contexts.size() == projectile_count,
		label + "期间逻辑时间、冷却和弹道队列冻结"
	)


func _close_path(
	display: GameDisplay,
	main: Control,
	card: CardView,
	label: String,
	button: MouseButton,
	internal_position: Vector2
) -> void:
	await _open_from_root(display, card)
	await process_frame
	check(is_instance_valid(main._inspection_overlay), label + "测试通过根窗口打开检视")
	if not is_instance_valid(main._inspection_overlay):
		return
	await _check_frozen(main, label)
	var click_position := internal_position
	if label == "暗幕左键":
		click_position = _find_exposed_dim_point(main._inspection_dim)
	await _send_mouse(display, button, click_position)
	await create_timer(0.25, true).timeout
	check(main._inspection_overlay == null and not main.get_tree().paused, label + "关闭后恢复战斗")


func _find_exposed_dim_point(dim: Control) -> Vector2:
	var overlay := dim.get_parent() as Control
	for y in range(710, 0, -10):
		for x in range(1270, 0, -10):
			var point := Vector2(x, y)
			if dim.get_global_rect().has_point(point) and not _covered_by_interactive_control(overlay, dim, point):
				return point
	return Vector2(640, 700)


func _covered_by_interactive_control(parent: Control, dim: Control, point: Vector2) -> bool:
	for child: Node in parent.get_children():
		if child == dim:
			continue
		if child is Control:
			var control := child as Control
			if (
				control.is_visible_in_tree()
				and control.mouse_filter == Control.MOUSE_FILTER_STOP
				and control.get_global_rect().has_point(point)
			):
				return true
			if _covered_by_interactive_control(control, dim, point):
				return true
	return false
