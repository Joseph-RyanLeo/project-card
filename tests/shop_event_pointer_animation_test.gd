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
	await _click(table._deck)
	await create_timer(0.12).timeout
	check(table.cards.size() == 3 and table.cards[0].z_index > table.cards[1].z_index and table.cards[1].z_index > table.cards[2].z_index, "抽牌重叠时，先抽的牌始终盖住后抽的牌")
	await _snapshot("event-deal-layering")
	await create_timer(0.5).timeout
	await _click(table.cards[2])
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
	await _snapshot("shop-idle-tilt")
	check(main.ordinary_shop_service.rng.state == rng_before and main.run_reward_state.gold == 1000, "外观随机不消耗报价随机数或金币")
	await _check_refresh_button()
	await _check_single_offer()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Shop/event pointer animation: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)

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
	await _motion(point)
	await create_timer(0.06).timeout
	check(absf(button._visual.rotation) > 0.0001, "移出再指向重播抖动")
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
