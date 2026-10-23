extends "res://tests/service_interaction_revision_20261020_test.gd"

## 真实2K显示壳、收板中间帧GPU遮挡与两轮暗卡轮播，不用模拟节点替代正式界面。
var _placed: Array[CardView] = []

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收板层级与暗卡轮播专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-tabletop-carousel.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	_deal("loose_coins")
	for row: BattlefieldRow in [main.front_row, main.back_row]:
		var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
		row.add_squad(SquadData.from_owned_card(owned), 0)
		_placed.append(row.get_squads().back().get_primary_card_view())
	await _check_panel("事件", maze._panel)
	check(maze.select_path("loose_coins") and maze.complete_event(), "事件正常推进强化轮")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "跳过强化进入商店轮")
	check(maze.select_path(maze.run.paths[0].path_id), "真实选择商店路径")
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await create_timer(0.5).timeout
	await _check_panel("商店服务", main.ordinary_shop_panel)
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	await _click(main._tabletop_park_button)
	await create_timer(0.35).timeout
	check(main._tabletop_park_button.disabled, "板已收起时按钮保持暗图且不能重复点击")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	check(maze.select_path(maze.run.paths[0].path_id), "真实选择战斗准备")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(maze._panel.global_position.y < -350 and main._tabletop_park_button.disabled, "战斗介绍留在上半世界、未遮挡我方战场时按钮不亮")
	main._park_tabletop_panels()
	check(not main._tabletop_panels_parked, "程序化调用也不能收起未覆盖战场的介绍板")
	maze._panel.hide()
	await process_frame
	check(main._tabletop_park_button.disabled, "下半视角没有事件／商店板时按钮保持禁用")
	shell.queue_free()
	await process_frame
	await _check_hidden_cards()
	DirAccess.remove_absolute("/private/tmp/project-card-tabletop-carousel.json")
	print("收板层级与暗卡轮播：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func _check_panel(label: String, panel: Control) -> void:
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(not main._tabletop_park_button.disabled, label + "实际覆盖我方战场时按钮可用")
	await _click(main._tabletop_park_button)
	main._tabletop_park_tween.pause()
	check(main._tabletop_park_button.disabled, label + "点击收板立即禁用按钮")
	for step: float in [0.02, 0.05, 0.07]:
		main._tabletop_park_tween.custom_step(step)
		await RenderingServer.frame_post_draw
		var actual: Image = shell.internal_viewport.get_texture().get_image()
		main.front_row.hide()
		main.back_row.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var without_cards: Image = shell.internal_viewport.get_texture().get_image()
		var covered := false
		for view: CardView in _placed:
			if not is_instance_valid(view): continue
			var area := panel.get_global_rect().grow(-6).intersection(view.get_global_rect()).grow(-2)
			if area.size.x <= 4 or area.size.y <= 4: continue
			covered = true
			check(actual.get_region(Rect2i(area)).get_data() == without_cards.get_region(Rect2i(area)).get_data(), label + "收板中间帧GPU像素仍完整盖住底下战场卡")
		check(covered, label + "采样帧确有板和真实卡牌重叠")
		main.front_row.show()
		main.back_row.show()
		await process_frame
	main._tabletop_park_tween.custom_step(1.0)
	await process_frame
	check(main._tabletop_panels_parked and panel.global_position == Vector2(189, -364), label + "最终仍准确收回上半世界")
	check(main.front_row._drop_enabled and main.back_row._drop_enabled, label + "收板后仍可正常布阵")
	await capture("layer-" + ("shop" if main.ordinary_shop_open else "event"))
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await process_frame
	check(not main._tabletop_panels_parked and main._tabletop_park_button.disabled, label + "回上半视角恢复跟随并禁用收板")

func _check_hidden_cards() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-tabletop-carousel.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main.ordinary_shop_service.offers.clear()
	main.ordinary_shop_service.offers.append({"kind": "single_card", "card_id": "musketeer", "hidden": true, "hint": "rarity", "price": 2, "instance_seed": "13", "offer_id": "hidden_stable"})
	main._refresh_ordinary_shop_panel()
	await create_timer(0.3).timeout
	main._preview_shop_offer(0)
	await create_timer(0.4).timeout
	var card: ShopCardView = main._inspection_card_view
	check(card != null and card._hidden_offer and card.card_data.id.is_empty() and card.card_data.display_name == "？", "实际暗卡4倍检视仍使用脱敏定义")
	if card == null: return
	main._inspection_surface.tilt_locked = true
	var action_bounds := card.action_icon.get_rect()
	var race_bounds := card.race_icon.get_rect()
	var rng: int = main.ordinary_shop_service.rng.state
	var always_visible := true
	var fixed_bounds := true
	var separate_action := false
	var separate_race := false
	var first_identity: int = card._identity_index
	var previous_action: int = card._carousel_index
	var previous_race: int = card._identity_index
	var previous_left: Texture2D = card.action_icon.texture
	var previous_middle: Texture2D = card.race_icon.texture
	var deadline := Time.get_ticks_msec() + 26000
	while card._identity_index - first_identity < 18 and Time.get_ticks_msec() < deadline:
		await process_frame
		always_visible = always_visible and card.action_icon.visible and card.race_icon.visible and card.action_icon.texture != null and card.race_icon.texture != null and card.card_data.race_type != CardData.RaceType.NONE
		fixed_bounds = fixed_bounds and card.action_icon.get_rect() == action_bounds and card.race_icon.get_rect() == race_bounds
		if card._carousel_index != previous_action and card._identity_index == previous_race:
			separate_action = separate_action or (card.race_icon.texture == previous_middle)
		if card._identity_index != previous_race and card._carousel_index == previous_action:
			separate_race = separate_race or (card.action_icon.texture == previous_left)
		previous_action = card._carousel_index
		previous_race = card._identity_index
		previous_left = card.action_icon.texture
		previous_middle = card.race_icon.texture
	check(card._identity_index - first_identity >= 18 and always_visible, "经过两轮完整种族循环，两个图标始终独立显示且不进入空种族")
	check(fixed_bounds and action_bounds == card.ACTION_CAROUSEL_RECT and race_bounds.size == Vector2(16, 16), "每个实际动画帧保持固定位置和尺寸，不因素材大小闪烁位移")
	check(separate_action and separate_race, "行动与种族按独立计时器切换，另一图标纹理不被重置")
	check(main.ordinary_shop_service.rng.state == rng and main.run_reward_state.gold == 1000, "暗卡轮播及只读检视不改变商品随机流和金币")
	await capture("hidden-two-cycles")
	var source: ShopCardView = main._shop_offer_art(0).card
	main._close_card_inspection(true)
	await process_frame
	check(source._identity_index == card._identity_index if is_instance_valid(card) else source._identity_index >= 18, "关闭检视后独立种族轮播继续回到原商品")
	await _check_gpu_icons(source)
	for kind: int in CardData.CardType.size():
		var definition := CardData.new()
		definition.card_type = kind as CardData.CardType
		for frame: int in 20:
			var public_card := ShopCardView.public_definition(definition, {}, frame)
			check(public_card.id.is_empty() and public_card.art_texture == null and public_card.race_type != CardData.RaceType.NONE, "四类暗单跨轮循环不泄露真实定义、不使用空种族")
	shell.queue_free()
	await process_frame

func _check_gpu_icons(card: ShopCardView) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 144)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for icon: TextureRect in [card.action_icon, card.race_icon]:
		var view := TextureRect.new()
		view.texture = icon.texture
		view.material = icon.material
		view.position = Vector2(24, 8)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.size = icon.size * 4
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(view)
		await process_frame
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().get_used_rect().size.x > 20, "GPU实际绘制暗卡循环图标，Shader不会输出空白")
		view.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
