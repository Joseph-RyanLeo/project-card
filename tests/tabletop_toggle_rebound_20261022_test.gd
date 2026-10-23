extends "res://tests/tabletop_layer_hidden_carousel_test.gd"

## 收起后的暗图仍接受真实鼠标点击；往返保留原节点、服务会话和遮挡层级。
func _run() -> void:
	create_timer(70).timeout.connect(func(): push_error("收板往返专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-tabletop-toggle.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	_deal("loose_coins")
	for row: BattlefieldRow in [main.front_row, main.back_row]:
		var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
		row.add_squad(SquadData.from_owned_card(owned), 0)
		_placed.append(row.get_squads().back().get_primary_card_view())
	await _check_toggle("事件", maze._panel)
	check(maze.select_path("loose_coins") and maze.complete_event(), "往返之后同一事件仍能正常完成")
	check(maze.select_path(maze.run.paths[0].path_id) and maze.complete_event(false), "进入商店轮")
	check(maze.select_path(maze.run.paths[0].path_id), "真实选择商店路径")
	await create_timer(0.4).timeout
	main._open_shop_card_services()
	var material: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	_show_owned(material)
	main._select_exchange_card({"kind": &"card", "owned_card": material}, 0)
	await create_timer(0.4).timeout
	var slot: Control = main._shop_exchange_slots[0]
	var view: CardView = slot._card_view
	check(main._shop_exchange_ids[0] == material.instance_id and is_instance_valid(view), "往返前材料已真实进入融合槽")
	var rng: int = main.ordinary_shop_service.rng.state
	var gold: int = main.run_reward_state.gold
	await _check_toggle("商店服务", main.ordinary_shop_panel)
	check(main._shop_exchange_ids[0] == material.instance_id and slot._card_view == view, "服务材料原实例与卡面节点在两次往返后不变")
	check(main.ordinary_shop_service.rng.state == rng and main.run_reward_state.gold == gold, "收起与移回不重新生成商品、不扣金币")
	# 返程尚未完成便切回上半视角，所有板仍准确落在常规锚点。
	await _click(main._tabletop_park_button)
	await create_timer(0.35).timeout
	await _click(main._tabletop_park_button)
	await create_timer(0.10).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main._shop_motion_root.position.is_equal_approx(Vector2.ZERO) and main.ordinary_shop_panel.global_position.is_equal_approx(Vector2(189, 0)), "返程中切上半视角也不会留下半途偏移")
	check(main._tabletop_park_button.disabled and not main._tabletop_panels_parked, "上半视角恢复原跟随并禁用按钮")
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	check(maze.select_path(maze.run.paths[0].path_id), "进入真实战斗准备")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	check(main._tabletop_park_button.disabled and maze._panel.global_position.y < -350, "战斗介绍自动留在上方时仍禁用，不能误移回来挡布阵")
	main._park_tabletop_panels()
	check(not main._tabletop_panels_parked, "禁用时程序入口也不误切换")
	maze._panel.hide()
	await process_frame
	check(main._tabletop_park_button.disabled, "没有板时保持禁用")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("收板往返：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func _check_toggle(label: String, panel: Control) -> void:
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var identity: int = panel.get_instance_id()
	for cycle: int in 2:
		check(not main._tabletop_park_button.disabled and main._tabletop_park_button.texture_normal != main._tabletop_park_button.texture_disabled, label + "覆盖战场时按钮亮且可点")
		await _click(main._tabletop_park_button)
		check(main._tabletop_panels_parked and main._tabletop_park_button.disabled, label + "收板动画期间阻止重复启动")
		await _sample_toggle_motion(label + "收起", panel)
		check(panel.global_position.is_equal_approx(Vector2(189, -364)), label + "收回上半世界锚点")
		check(not main._tabletop_park_button.disabled and main._tabletop_park_button.texture_normal == main._tabletop_park_button.texture_disabled, label + "收起后显示暗图但仍可点击")
		check(main.front_row._drop_enabled and main.back_row._drop_enabled, label + "收起后布阵落点可用")
		await _click(main._tabletop_park_button)
		check(not main._tabletop_panels_parked, label + "真实点击暗按钮启动移回")
		await _sample_toggle_motion(label + "移回", panel)
		check(panel.get_instance_id() == identity and panel.global_position.is_equal_approx(Vector2(189, 0)), label + "同一面板回到固定屏幕位置")
		check(not main._tabletop_park_button.disabled and main._tabletop_park_button.texture_normal != main._tabletop_park_button.texture_disabled, label + "移回后重新亮起并能再次收起")
	await capture("toggle-" + ("shop" if main.ordinary_shop_open else "event"))

func _sample_toggle_motion(label: String, panel: Control) -> void:
	main._tabletop_park_tween.pause()
	var covered := false
	for step: float in [0.07, 0.09, 0.12]:
		main._tabletop_park_tween.custom_step(step)
		await process_frame
		await RenderingServer.frame_post_draw
		var actual: Image = shell.internal_viewport.get_texture().get_image()
		main.front_row.hide()
		main.back_row.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var without_cards: Image = shell.internal_viewport.get_texture().get_image()
		for view: CardView in _placed:
			var area := panel.get_global_rect().grow(-6).intersection(view.get_global_rect()).grow(-2)
			if area.size.x <= 4 or area.size.y <= 4: continue
			covered = true
			check(actual.get_region(Rect2i(area)).get_data() == without_cards.get_region(Rect2i(area)).get_data(), label + "中间帧实际GPU板面盖住底下战场卡")
		main.front_row.show()
		main.back_row.show()
		await process_frame
	check(covered, label + "采样中确有真实卡牌与板重叠")
	main._tabletop_park_tween.custom_step(1.0)
	await process_frame
