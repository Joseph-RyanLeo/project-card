extends "res://tests/shop_event_materials_20261020_test.gd"

## 使用真实2K显示壳和原生鼠标事件，验证层级、商品姿态和刷新按压生命周期。
func _motion(point: Vector2, held: bool = false) -> void:
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super._motion(point, held)

func _snapshot(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-" + file + ".png")

func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("商店事件指向动画验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-pointer-animation.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	maze = main.maze_controller
	_deal("ioann_prayer")
	await process_frame
	var table: Control = maze._event_table
	while is_instance_valid(table._deck_arrival): await process_frame
	await _click(table._deck)
	await create_timer(0.12).timeout
	check(table.cards.size() == 3 and table.cards[0].z_index > table.cards[1].z_index and table.cards[1].z_index > table.cards[2].z_index, "抽牌重叠时，先抽的牌始终盖住后抽的牌")
	await _snapshot("event-deal-layering")
	await create_timer(0.5).timeout
	await _check_event_hover(table)
	await _pad_button(JOY_BUTTON_A)
	check(table.cards[2].z_index > table.cards[0].z_index, "选中后层牌后翻牌演出独立置顶")
	await create_timer(1.2).timeout
	check(maze.run.selected_path.path_id == table._paths[2].path_id if is_instance_valid(table) else not maze.run.selected_path.is_empty(), "层级修正后仍能完成真实路径选择")
	shell.queue_free()
	await process_frame
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-pointer-animation.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	await _motion(Vector2(40, 450))
	var rng_before: int = main.ordinary_shop_service.rng.state
	var tiles: Array[Node] = main.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false)
	var initial := {}
	for tile: ShopOfferView in tiles:
		if tile._hover_surface != null: initial[tile] = tile._hover_surface.force
	await create_timer(0.5).timeout
	var moving := 0
	var different := {}
	for tile: ShopOfferView in initial:
		if tile._hover_surface.force.distance_to(initial[tile]) > 0.00001: moving += 1
		different[tile._hover_surface.force.snapped(Vector2.ONE * 0.0001)] = true
		check(tile._visual.rotation == 0.0 and absf(tile._hover_surface.force.x) <= tile.IDLE_FORCE_LIMIT and absf(tile._hover_surface.force.y) <= tile.IDLE_FORCE_LIMIT and tile._visual.position.y == 0.0, "商品未指向时轻微透视倾斜，保持原来高度")
	check(moving == initial.size() and moving > 1 and different.size() > 1, "各商品以独立随机透视方向持续缓慢变化")
	for stack: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
		var tile: ShopOfferView = stack._offers.back()
		var hit_rect := tile.get_global_rect()
		var price_rect := stack._description.get_global_rect()
		var surface := tile._hover_surface
		var point := tile.get_global_transform_with_canvas() * (surface.position + surface.size * Vector2(0.75, 0.7))
		await _motion(point)
		await create_timer(0.4).timeout
		check(tile._hovered and tile._visual.position.y == 0.0 and is_zero_approx(tile._visual.rotation), "卡包／纹章包指向后不再上移，陈列歪斜平滑回正")
		check(surface.force.x > 0.3 and surface.force.y > 0.2 and tile.get_global_rect() == hit_rect and stack._description.get_global_rect() == price_rect, "保留鼠标透视与原叠包命中，价格不跟随移动")
		await _motion(Vector2(40, 450))
	var stack := main.ordinary_shop_offer_list.find_child("ShopPackStack_*", true, false) as ShopPackStackView
	if stack != null: await _check_pack_gamepad_hover(stack)
	else: check(false, "商店提供真实手柄叠包测试目标")
	await _snapshot("shop-idle-tilt")
	check(main.ordinary_shop_service.rng.state == rng_before and main.run_reward_state.gold == 1000, "外观随机不消耗报价随机数或金币")
	await _check_refresh_button()
	await _check_full_shop_opening()
	await _check_single_offer()
	await _check_battle_trigger()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Shop/event pointer animation: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _pad_button(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

func _check_event_hover(table: Control) -> void:
	var first: EventCardView = table.cards[0]
	var last: EventCardView = table.cards[2]
	await _motion(last.get_global_rect().get_center())
	await create_timer(0.18).timeout
	check(is_equal_approx(last._choice_lift, last.HOVER_LIFT), "鼠标指向候选牌使用既有抬升")
	await _pad_button(JOY_BUTTON_DPAD_LEFT)
	await create_timer(0.18).timeout
	var pad: Node = shell._gamepad_pointer
	check(pad._focus_item == first and is_equal_approx(first._choice_lift, last.HOVER_LIFT) and is_zero_approx(last._choice_lift), "手柄接管后只抬起当前焦点牌，鼠标残留位置的牌落回")
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	await create_timer(0.18).timeout
	var raised_center: Vector2 = shell.render_container.get_global_transform_with_canvas() * (last.get_global_transform_with_canvas() * last.choice_visual_rect().get_center())
	check(pad._focus_item == last and is_equal_approx(last._choice_lift, last.HOVER_LIFT) and is_zero_approx(first._choice_lift), "手柄焦点切换共用事件牌上抬和落回动画")
	check(pad._marker.get_global_rect().get_center().is_equal_approx(raised_center), "呼吸光对齐抬起后的牌面")
	check(pad._marker.material.get_shader_parameter("use_silhouette") and pad._marker.material.get_shader_parameter("silhouette_texture") == (last.FRONT if last.face_up else last.BACK), "候选牌的呼吸高光按当前牌面轮廓绘制")

func _check_pack_gamepad_hover(stack: ShopPackStackView) -> void:
	var tile: ShopOfferView = stack._offers.front()
	var top: ShopOfferView = stack._offers.back()
	var surface := tile._hover_surface
	var mouse := top.get_global_transform_with_canvas() * (top._hover_surface.position + top._hover_surface.size * Vector2(0.82, 0.68))
	await _motion(mouse)
	await _pad_button(JOY_BUTTON_DPAD_RIGHT)
	var pad: Node = shell._gamepad_pointer
	pad._set_focus(main, {"item": tile, "area": &"shop", "point": tile.get_global_rect().get_center()})
	await create_timer(0.45).timeout
	check(stack._hover_offer == tile and tile.z_index == 0 and surface.force.length() < 0.025, "手柄指向叠包沿用横移让位，摇杆回中时不受残留鼠标坐标影响")
	_pad_axis(JOY_AXIS_RIGHT_X, -0.82)
	_pad_axis(JOY_AXIS_RIGHT_Y, 0.42)
	await create_timer(0.45).timeout
	check(surface.force.x < -0.60 and surface.force.y > 0.25, "右摇杆驱动同一个商品透视表面")
	check(pad._marker.material.get_shader_parameter("projected_shape") and pad._marker.material.get_shader_parameter("projection_force").distance_to(surface.force) < 0.02, "商品呼吸光同步采样摇杆倾斜后的轮廓")
	_pad_axis(JOY_AXIS_RIGHT_X, 0.12)
	_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await create_timer(0.45).timeout
	check(surface.force.length() < 0.025, "右摇杆返回死区时卡包回正")
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _motion(Vector2(40, 450))
	await _motion(mouse)
	await create_timer(0.45).timeout
	check(not pad._active and stack._hover_offer == top and top._hover_surface.force.x > 0.45, "切回鼠标后恢复鼠标透视和叠包选择")
	await _motion(Vector2(40, 450))

func _check_full_shop_opening() -> void:
	var service: OrdinaryShopService = main.ordinary_shop_service
	var weights: Dictionary = service.config.temporary_offer_weights
	var saved_weights := weights.duplicate(true)
	weights.card_pack_count = {"4": 1}
	weights.sticker_pack_count = {"2": 1}
	weights.single_card_count = {"1": 1}
	var definitions: Array[CardData] = main._get_shop_card_definitions()
	var generated := false
	for seed_value: int in range(1, 65):
		service.rng.seed = seed_value
		if not service.refresh(definitions, main.owned_card_collection.get_cards(), main._get_shop_sticker_definitions(), main._get_all_held_stickers()): continue
		var ordinary := service.offers.filter(func(offer: Dictionary): return not offer.has("procurement_action"))
		var large := ordinary.filter(func(offer: Dictionary): return offer.get("size") == "large")
		var small := ordinary.filter(func(offer: Dictionary): return offer.get("size") == "small")
		var stickers := ordinary.filter(func(offer: Dictionary): return offer.kind == "sticker_pack")
		var singles := ordinary.filter(func(offer: Dictionary): return offer.kind == "single_card")
		if large.size() == 2 and small.size() == 2 and stickers.size() == 2 and singles.size() == 1 and (large[0].pack_id == large[1].pack_id or small[0].pack_id == small[1].pack_id):
			generated = true
			break
	service.config.temporary_offer_weights = saved_weights
	check(generated, "正式生成两大包、两小包、两纹章包和单卡的满货夹具")
	if not generated: return
	main._refresh_ordinary_shop_panel()
	await create_timer(0.30).timeout
	var groups: Array[Control] = main._shop_board_view._offer_groups
	var services := main.ordinary_shop_offer_list.get_node("ShopServices") as Control
	var scraper := services.get_child(0) as ShopOfferView
	var fixed := scraper.get_global_rect()
	check(scraper._visual.get_child(0).size == Vector2(116, 112) and services.position == main._shop_board_view.SCRAPER_POSITION, "刮刀脱离商品流，固定在最右侧并显示四倍原图")
	var price := scraper.get_node("ShopPrice") as Control
	var written_price := price.get_global_rect()
	await _motion(fixed.get_center())
	await create_timer(0.06).timeout
	check(scraper._visual.position.y < -2.0 and scraper.get_global_rect() == fixed and price.get_global_rect() == written_price, "指向刮刀时刀图弹起，价格和购买热区仍在原位")
	await create_timer(0.28).timeout
	check(is_zero_approx(scraper._visual.position.y), "鼠标停在刮刀上只播放一次跳动")
	await _motion(Vector2(40, 450))
	var stack: ShopPackStackView
	for group: Control in groups:
		if group is ShopPackStackView and group._offers.size() > 1:
			stack = group
			break
	if stack == null: return
	var index := groups.find(stack)
	var positions: Array[float] = []
	for group: Control in groups: positions.append(group.get_global_rect().position.x)
	var selected: ShopOfferView = stack._offers.front()
	var selected_rect := selected.get_global_rect()
	await _motion(selected_rect.position + Vector2(5, 77))
	await create_timer(0.30).timeout
	check(stack._hover_offer == selected and selected.get_global_rect() == selected_rect and not selected_rect.intersects(stack._offers[1].get_global_rect()), "后层商品原地完整露出，堆内右包让位")
	for group_index: int in groups.size():
		var rect := groups[group_index].get_global_rect()
		check(rect.position.x > positions[group_index] if group_index > index else is_equal_approx(rect.position.x, positions[group_index]), "只向右滑动目标右方的整组货位")
		check(rect.end.x <= fixed.position.x, "满货让位仍未盖到最右侧刮刀")
	check(scraper.get_global_rect() == fixed, "滑动期间刮刀位置固定")
	await _snapshot("full-shop-reveal")
	await _motion(Vector2(40, 450))
	await create_timer(0.30).timeout
	for group_index: int in groups.size():
		check(is_equal_approx(groups[group_index].get_global_rect().position.x, positions[group_index]), "取消悬停后商品回到原位")

func _check_battle_trigger() -> void:
	main._toggle_ordinary_shop()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await create_timer(0.6).timeout
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"), main.ordinary_shop_service.rng)
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	var button: Button = main.start_battle_button
	check(main.can_gamepad_start_battle(), "真实备战入口允许 RT 蓄力")
	var presses: Array[int] = []
	button.pressed.connect(func(): presses.append(1))
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.95)
	await create_timer(0.4).timeout
	var shake_seen := false
	for frame: int in 10:
		shake_seen = shake_seen or not button._visual.position.is_zero_approx()
		await process_frame
	check(button._gamepad_charging and button._hover_time > button.SHAKE_SECONDS and shake_seen and presses.is_empty(), "RT 按住超过鼠标悬停动画时长后，按钮继续震动")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await create_timer(0.5).timeout
	check(not button._gamepad_charging and button._visual.position.is_zero_approx() and presses.is_empty(), "提前松开 RT 结束震动且不开战")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.95)
	await create_timer(1.5).timeout
	check(button._gamepad_charging and presses.is_empty(), "满两秒前持续蓄力，无按下动作")
	var peak_depth := 0.0
	var deadline := Time.get_ticks_msec() + 1500
	while presses.is_empty() and Time.get_ticks_msec() < deadline:
		peak_depth = maxf(peak_depth, button.press_depth)
		await process_frame
	await create_timer(0.3).timeout
	check(peak_depth >= button.PRESS_PIXELS - 0.1 and presses.size() == 1 and main.current_phase != main.GamePhase.PREPARE, "满两秒播放一次完整按压，通过原按钮信号开战，继续按住不重复")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)

func _check_refresh_button() -> void:
	var button: Button = main._shop_board_view._refresh
	var leave: Button = main._shop_board_view.get_node("LeaveShopButton")
	check(button.global_position.y == leave.global_position.y, "刷新与离店按钮顶边同高")
	var sheet: Image = button.SHEET.get_image()
	for frame_index: int in button.FRAME_COUNT:
		button._set_frame(frame_index)
		var face_top := 0
		for row: int in int(button.FRAME_SIZE.y):
			if sheet.get_pixel(40, frame_index * int(button.FRAME_SIZE.y) + row).is_equal_approx(Color8(88, 74, 71)):
				face_top = row
				break
		check(button._caption.position.y == face_top - 7 and button._cost.position.y == face_top + 3, "第%d帧文字与金额跟随原GIF按钮面像素位置" % frame_index)
	button._set_frame(0)
	var point := button.get_global_rect().get_center()
	var rect := button.get_global_rect()
	await _motion(point)
	await create_timer(0.06).timeout
	check(absf(button._visual.rotation) > 0.0001 and button.get_global_rect() == rect, "首次指向刷新按钮播放抖动，点击范围固定")
	await create_timer(0.2).timeout
	check(is_zero_approx(button._visual.rotation), "指向抖动播放一次后回正")
	await _motion(Vector2(40, 450))
	var previous_shake: Tween = button._shake
	await _motion(point)
	var shake_seen := false
	var wait_for_shake := create_timer(0.18)
	while not shake_seen and wait_for_shake.time_left > 0.0:
		shake_seen = button._shake != previous_shake and not is_zero_approx(button._visual.rotation)
		await process_frame
	check(shake_seen, "移出再指向重播抖动")
	var gold_before: int = main.run_reward_state.gold
	var refresh_before: int = main.ordinary_shop_service.refresh_count
	await _mouse(point, true)
	await create_timer(0.18).timeout
	check(button._frame == 2 and button._held and button._caption.position.y == 2 and button._cost.position.y == 12 and main.run_reward_state.gold == gold_before, "按住刷新停在第三帧，未松手不扣费")
	await create_timer(0.25).timeout
	check(button._frame == 2, "持续按住仍保持第三帧")
	await _snapshot("refresh-held-third-frame")
	await _mouse(point, false)
	await create_timer(0.08).timeout
	check(button._frame > 2 and main.ordinary_shop_service.refresh_count == refresh_before + 1 and main.run_reward_state.gold == gold_before - 1, "范围内松手继续回弹，刷新且只扣一次费用")
	check(button.text == "刷新2" and button._caption.text == "刷新" and button._cost.text == "2", "扣费后按钮同步显示下一次刷新价格")
	await create_timer(0.5).timeout
	check(button._frame == 0 and button._caption.position.y == 0 and button._cost.position.y == 10, "完整回弹后按钮及文字一起恢复第一帧")
	gold_before = main.run_reward_state.gold
	refresh_before = main.ordinary_shop_service.refresh_count
	var rng_before: int = main.ordinary_shop_service.rng.state
	await _mouse(point, true)
	await create_timer(0.15).timeout
	await _motion(Vector2(40, 450), true)
	await create_timer(0.055).timeout
	check(button._frame == 1 and button._cancelled, "按住移出后第三帧倒放至第二帧")
	await create_timer(0.1).timeout
	check(button._frame == 0, "取消倒放回第一帧")
	await _motion(point, true)
	await _mouse(point, false)
	await create_timer(0.2).timeout
	check(main.run_reward_state.gold == gold_before and main.ordinary_shop_service.refresh_count == refresh_before and main.ordinary_shop_service.rng.state == rng_before, "按住移出再移回松手不会误刷新或消耗随机数")
	await _click(button)
	await create_timer(0.6).timeout
	check(main.run_reward_state.gold == gold_before - 2 and main.ordinary_shop_service.refresh_count == refresh_before + 1 and button._frame == 0, "取消之后仍能快速点击，完整播放并只提交一次")
	await _mouse(point, true)
	await create_timer(0.15).timeout
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	check(button._frame == 0 and not button._held, "切换页签清理未结束按压，不残留第三帧")
	await _click(main._shop_board_view.get_node("ShoppingTab"))
	await create_timer(0.3).timeout

func _check_single_offer() -> void:
	var definition: CardData = load("res://resources/cards/musketeer.tres")
	main.ordinary_shop_service.offers.clear()
	main.ordinary_shop_service.offers.append({"kind": "single_card", "card_id": String(definition.id), "hidden": false, "hint": "card_type", "price": 4, "instance_seed": "13", "offer_id": "pointer_single"})
	for hidden: bool in [false, true]:
		main.ordinary_shop_service.offers[0].hidden = hidden
		main._refresh_ordinary_shop_panel()
		await create_timer(0.25).timeout
		var tile: ShopOfferView = main.ordinary_shop_offer_list.find_child("ShopOffer_0", true, false)
		var surface := tile._hover_surface
		var origin := surface.position + surface.content_padding
		var point := tile.get_global_transform_with_canvas() * (origin + surface.card.card_size * Vector2(0.75, 0.7))
		var price: Control = tile.get_node("ShopPrice")
		var price_rect := price.get_global_rect()
		await _motion(point)
		await create_timer(0.4).timeout
		check(tile._hovered and tile._visual.position.y == 0.0 and tile._visual.rotation == 0.0 and surface.force.x > 0.3, "明暗单卡保留鼠标倾斜，取消指向上移")
		await _motion(Vector2(40, 450))
		var force: Vector2 = tile._hover_surface.force
		await create_timer(0.5).timeout
		check(not tile._hover_surface.force.is_equal_approx(force) and price.get_global_rect() == price_rect, "明暗单卡移出后恢复随机轻微透视，价格固定")
