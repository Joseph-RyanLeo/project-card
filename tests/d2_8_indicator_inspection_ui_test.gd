extends SceneTree

## 正式显示壳的指示物命中、暂停层级和悬停弹窗检视往返。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var assertions := 0
var failures := 0
var pointer := Vector2.ZERO
var opening_source: CardView
var opening_position := Vector2.ZERO
var opening_scale := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func move(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	pointer = outer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
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

func received_inspection(source: CardView, _data: CardData, _owned: OwnedCard) -> void:
	opening_source = source
	opening_position = main._inspection_surface.position
	opening_scale = main._inspection_surface.scale

func _test_sentries() -> void:
	var maze = main.maze_controller
	check(maze.choose_talent("sentry_guard"), "一级天赋初始化真实哨位")
	maze._add_sentry() # 两枚合法实例作为命中测试输入，不模拟放置或存档。
	for region: String in ["front", "back"]:
		check(maze.deploy_sentry(maze.stock[0].instance_id, region), "正式事务部署到" + region)
	await process_frame
	await process_frame
	for region: String in ["front", "back"]:
		var view: Control = maze._sentry_views[region]
		var row: Control = main.front_row if region == "front" else main.back_row
		check(view.size == view.get_indicator_size() and view.size == Vector2(30, 35), region + "根命中框保持图标大小")
		check(view.get_parent() == maze._sentry_zones[region] and view.position == Vector2(row.size.x - 30, 0), region + "自由布局宿主保留右上角位置")
		var empty := row.get_global_rect().get_center()
		await move(empty)
		check(shell.internal_viewport.gui_get_hovered_control() != view, region + "空白区域不触发哨位悬停")
		await click(empty)
		check(main.celestial_indicators._data.is_empty() and main._click_carry_data.is_empty(), region + "点击整排空白不会拿起哨位")
		await click(view.get_global_rect().get_center())
		check(main.celestial_indicators._data.get("instance_id") == maze.deployed[0 if region == "front" else 1].instance_id, region + "只点击图标可拿起正确实例")
		await button(empty, true, MOUSE_BUTTON_RIGHT)
		await button(empty, false, MOUSE_BUTTON_RIGHT)
		check(main.celestial_indicators._data.is_empty(), "取消后部署保持不变")
	check(maze.drop_sentry(maze.deployed[1].instance_id, "spells"), "后排哨位正式移动到法术区")
	await process_frame
	check(maze._sentry_views.spells.position == Vector2.ZERO and maze._sentry_views.spells.size == Vector2(30, 35), "法术区哨位保持左上角小命中框")
	check(main.load_run_from_path(main.run_save_path), "真实磁盘恢复部署")
	await process_frame
	await process_frame
	check(maze._sentry_views.front.size == Vector2(30, 35) and maze._sentry_views.spells.size == Vector2(30, 35), "读档后的容器布局不再撑大哨位")

func effective_z(node: CanvasItem) -> int:
	var value := node.z_index
	if node.z_as_relative:
		var parent := node.get_parent() as CanvasItem
		if parent != null: value += effective_z(parent)
	return value

func _test_layers(slot: Control) -> void:
	main._on_escape_pause_menu_requested()
	await process_frame
	check(main._escape_pause_menu.is_menu_open() and paused and slot.pattern_label.visible, "暂停菜单打开，牌型保留在底层桌面")
	for label: Control in [slot.pattern_label, slot.battle_status_label, slot.battle_action_label, slot.target_priority_badge]:
		check(effective_z(label) < effective_z(main._escape_pause_menu), "小队标签层低于暂停菜单：" + label.name)
	main._close_escape_pause_menu()
	await process_frame
	check(not paused, "关闭菜单恢复此前运行状态")

func resource_point(tray: Control) -> Vector2:
	for cell: Vector2i in tray._piece_by_cell:
		return tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + tray.Layout.center(cell))
	return Vector2.ZERO

func ensure_resource(side: String) -> Control:
	var tray: Control = main.player_resource_tray if side == "player" else main.enemy_resource_tray
	if tray._piece_by_cell.is_empty():
		var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/rainbow_gold_ore.tres"))
		var placed := false
		for y: int in range(5):
			for x: int in range(4):
				if main.resource_board_state.try_deploy(side, String(owned.instance_id), owned.resource_shape, Vector2i(x, y), Vector2i.ZERO, Vector2.ZERO):
					placed = true
					break
			if placed: break
		check(placed, side + "真实资源实例可按正式格网规则部署")
		var cards: Array[OwnedCard] = [owned]
		tray.set_owned_cards(cards)
	return tray

func _test_animation(owner: Control, point: Vector2, label: String, close_on_origin: bool = false) -> void:
	await move(point)
	var popup: CardView = owner._hover_card
	check(is_instance_valid(popup), label + "鼠标指向显示完整卡牌弹窗")
	if not is_instance_valid(popup): return
	var expected: Transform2D = popup.get_global_transform_with_canvas()
	var owned: OwnedCard = popup.get_owned_card()
	opening_source = null
	await click(point, MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(main._inspection_overlay) and main._inspection_owned_card == owned, label + "右键检视同一OwnedCard实例")
	if not is_instance_valid(main._inspection_overlay): return
	var start: Transform2D = main._inspection_overlay.get_global_transform_with_canvas().affine_inverse() * expected
	check(opening_source == popup and main._inspection_source_view == popup and not popup.is_queued_for_deletion(), label + "来源弹窗保留到收回动画")
	check(opening_scale.is_equal_approx(start.get_scale()) and opening_position.is_equal_approx(start.origin - start.basis_xform(main._inspection_surface.PADDING)), label + "放大动画第一帧与原弹窗重合")
	check(not popup.visible and paused and not main._inspection_has_library_toolbox, label + "放大时隐藏原弹窗并保持战斗只读暂停")
	# 遮罩接管鼠标后，源节点会收到退出事件，仍须保留来源。
	owner._on_mouse_exited()
	if owner.has_method("_refresh_hover_card"): owner._refresh_hover_card()
	check(is_instance_valid(popup) and not popup.is_queued_for_deletion(), label + "悬停退出或刷新不会释放正在检视的来源")
	await create_timer(0.08).timeout
	check(main._inspection_surface.scale.x > start.get_scale().x and main._inspection_surface.scale.x < 4.0, label + "真实Tween逐步放大")
	await create_timer(0.22).timeout
	check(main._inspection_surface.scale.is_equal_approx(Vector2(4, 4)), label + "放大结束达到原生4倍")
	var close_point: Vector2 = point if close_on_origin else main._inspection_surface.get_global_rect().get_center()
	await click(close_point, MOUSE_BUTTON_RIGHT)
	check(main._inspection_closing and is_instance_valid(main._inspection_overlay) and paused, label + "右键关闭启动收回，结束前不恢复战斗")
	await create_timer(0.06).timeout
	check(main._inspection_surface.scale.x < 4.0 and main._inspection_surface.scale.x > start.get_scale().x, label + "收回动画逐步缩小")
	await create_timer(0.2).timeout
	await process_frame
	check(not is_instance_valid(main._inspection_overlay) and not paused, label + "收回结束销毁检视层并恢复战斗")
	if close_on_origin:
		check(is_instance_valid(popup) and owner._hover_card == popup and popup.visible, label + "鼠标仍在指示物上时恢复原弹窗")
	else:
		check(not is_instance_valid(owner._hover_card), label + "鼠标离开原指示物时不残留弹窗")

func _run() -> void:
	root.size = Vector2i(2560, 1440) if "2k" in OS.get_cmdline_user_args() else Vector2i(1280, 720)
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-indicator-inspection-ui.json"
	root.add_child(shell)
	await process_frame
	await process_frame
	main.maze_controller.new_run(1707)
	await _test_sentries()
	var unit: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var item: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/coarse_bandage.tres"))
	var squad := SquadData.from_owned_card(unit)
	check(squad.equip_item(item), "真实随从装备粗麻绷带")
	var slot: Control = main.front_row.add_squad(squad, 0)
	await process_frame
	await process_frame
	await _test_layers(slot)
	var equipment: Control = slot.get_equipment_indicator()
	equipment.inspection_requested.connect(received_inspection)
	var player := ensure_resource("player")
	var enemy := ensure_resource("enemy")
	player.inspection_requested.connect(received_inspection)
	enemy.inspection_requested.connect(received_inspection)
	# UI单元测试输入：真实OwnedCard与场景，切入战斗只读状态，不伪造胜负或奖励。
	main.current_phase = main.GamePhase.BATTLE
	main._update_phase_label()
	await create_timer(main.VIEW_TWEEN_DURATION + 0.05).timeout
	await _test_animation(equipment, equipment.get_global_rect().get_center(), "装备", true)
	await _test_animation(player, resource_point(player), "我方资源")
	await _test_animation(enemy, resource_point(enemy), "敌方资源")
	# 暂停时没有鼠标悬停回调，检视入口也应生成正确来源并恢复原暂停状态。
	main._on_battle_pause_button_pressed()
	check(paused, "手动暂停基准")
	await click(resource_point(player), MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(main._inspection_source_view) and main._inspection_owned_card.card_data.card_type == CardData.CardType.RESOURCE, "暂停时右键资源也有动画来源")
	await create_timer(0.04).timeout
	main._close_card_inspection()
	await create_timer(0.25).timeout
	check(not is_instance_valid(main._inspection_overlay) and paused, "提前取消检视仍收回并保持原手动暂停")
	main._on_battle_pause_button_pressed()
	await process_frame
	check(not paused, "手动继续可恢复")
	print("指示物命中／检视动画专项：", assertions, "项断言，失败", failures)
	main._close_card_inspection(true)
	shell.queue_free()
	await process_frame
	quit(1 if failures else 0)
