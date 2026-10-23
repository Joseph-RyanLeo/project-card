extends "res://tests/shop_event_materials_20261020_test.gd"

## 真实显示壳、报价生成和输入覆盖连续刷新、摆放、融合提示及分阶段托盘。
func _motion(point: Vector2, held: bool = false) -> void:
	if DisplayServer.get_name() != "headless": Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super._motion(point, held)

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-followup-" + file + ".png")

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("界面追加验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-ui-followup.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	check(main.enemy_resource_tray.visible and main.enemy_resource_tray.position == main.ENEMY_RESOURCE_TRAY_POSITION and not bool(main.enemy_spell_preparation_tray.get_meta("expanded", false)), "独立准备阶段仅展开敌方资源区")
	main.run_reward_state.gold = 1499999
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.7).timeout
	check(not bool(main.enemy_resource_tray.get_meta("expanded", false)) and not bool(main.enemy_spell_preparation_tray.get_meta("expanded", false)), "进入商店收起双方敌方托盘")
	var button: Button = main._shop_board_view._refresh
	var point := button.get_global_rect().get_center()
	await _motion(point)
	for index: int in 8:
		var gold: int = main.run_reward_state.gold
		await _mouse(point, true)
		await _mouse(point, false)
		await create_timer(0.6).timeout
		check(main.ordinary_shop_service.refresh_count == index + 1 and main.run_reward_state.gold == gold - index - 1, "不移开鼠标连续刷新第%d次，按1、2、3递增扣费" % (index + 1))
		check(main.ordinary_shop_service.refresh_price() == index + 2, "下一次费用继续加1")
	var origin: Vector2 = main.ordinary_shop_offer_list.global_position
	for stack: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
		check(is_equal_approx(stack._description.global_position.y - origin.y, 277), "叠包价格顶部位于锦缎下方10px")
		check(is_equal_approx(stack._description.get_global_rect().get_center().x, stack.get_global_rect().get_center().x), "叠包报价左右居中")
		for tile: ShopOfferView in stack._offers:
			check(is_equal_approx((tile._visual.get_global_transform_with_canvas() * (tile._visual.size * 0.5)).y - origin.y, 173), "不同大小包装沿锦缎中线垂直居中")
	await capture("goods")
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	var cards: Array[OwnedCard] = []
	for index: int in 3:
		cards.append(main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"), main.ordinary_shop_service.rng))
		_show_owned(cards[index])
		main._select_exchange_card({"kind": &"card", "owned_card": cards[index]}, index)
		await create_timer(0.35).timeout
		check(main._shop_board_view._rarity_dots[index].visible, "每个材料槽实时点亮对应稀有度圆点")
	check(not main._shop_exchange_confirm.disabled and main._shop_board_view._rarity_dots[3].visible, "三张合法材料点亮高一级产物圆点")
	var mark: TextureRect = main._shop_board_view._exchange_mark
	check(mark.get_rect().get_center().is_equal_approx(Vector2(359.5, 87.5)), "融合勾叉在三个点和一个点之间，纵向居中")
	check(button._cost is RuneNumberDisplay and button._cost.text == "9", "刷新费用同样使用大卢恩数字")
	await create_timer(0.35).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await capture("fusion-ready")
	main._shop_exchange_ids[0] = &""
	main._refresh_shop_exchange()
	check(not main._shop_board_view._rarity_dots[0].visible and not main._shop_board_view._rarity_dots[3].visible and main._shop_exchange_confirm.disabled, "移出材料立即恢复空点和红叉")
	main._select_shop_service_card({"kind": &"card", "owned_card": cards[0]})
	check(main._shop_board_view._amount is RuneNumberDisplay and main._shop_board_view._amount.number_style == RuneNumberDisplay.NumberStyle.LARGE, "出售提取金额复用大卢恩数字")
	await capture("services")
	main._toggle_ordinary_shop()
	await create_timer(0.7).timeout
	check(main.enemy_resource_tray.visible and not bool(main.enemy_spell_preparation_tray.get_meta("expanded", false)), "返回准备仅滑出资源区")
	main.current_phase = main.GamePhase.BATTLE
	main._refresh_enemy_side_trays()
	await create_timer(0.12).timeout
	check(main.enemy_spell_preparation_tray.visible and main.enemy_spell_preparation_tray.position.x < main.ENEMY_SPELL_TRAY_POSITION.x and main.enemy_spell_preparation_tray.position.x > 905, "开战时法术区正在从右侧滑入")
	await create_timer(0.3).timeout
	check(main.enemy_spell_preparation_tray.position == main.ENEMY_SPELL_TRAY_POSITION, "法术区完成滑入")
	main.current_phase = main.GamePhase.PREPARE
	main._refresh_enemy_side_trays()
	await create_timer(0.4).timeout
	check(not bool(main.enemy_spell_preparation_tray.get_meta("expanded", false)), "回准备收起敌方法术区")
	shell.queue_free()
	await process_frame
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-ui-followup.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	maze = main.maze_controller
	var index := _deal("ioann_prayer", 1499999)
	check(index >= 0 and maze.select_path(maze.run.paths[index].path_id), "进入真实事件描述页")
	await create_timer(0.25).timeout
	check(not bool(main.enemy_resource_tray.get_meta("expanded", false)) and not bool(main.enemy_spell_preparation_tray.get_meta("expanded", false)), "随机事件阶段敌方两侧全部收起")
	var labels: Array[Node] = maze._event_table.detail_body.find_children("*", "Label", true, false)
	check(not labels.is_empty() and labels[0].visible_characters > 0 and labels[0].visible_characters < (labels[0] as Label).get_total_character_count(), "事件描述按字出现，开始时没有直接全部显示")
	var before: int = labels[0].visible_characters
	await create_timer(0.1).timeout
	check(labels[0].visible_characters > before and labels[0].visible_characters - before <= 3, "逐字速度约每0.045秒一字")
	await capture("typing")
	var total := 0
	for label: Label in labels: total += label.get_total_character_count()
	await create_timer(total * 0.045 + labels.size() * 0.16 + maze._event_table.detail_body.find_children("*", "Button", true, false).size() * 0.28 + 0.3).timeout
	for label: Label in labels: check(label.visible_characters >= label.get_total_character_count(), "描述与所有选项最终完整显示")
	var option: Button = maze._event_table.detail_body.find_children("*", "Button", true, false)[0]
	check(option.mouse_filter == Control.MOUSE_FILTER_STOP and not option.disabled, "文字显示后保留真实选项操作资格")
	await capture("event")
	var hud: Control = maze._status
	check(hud._gold is RuneNumberDisplay and hud._gold.text == "1499999", "大世界顶栏金币使用大卢恩数字")
	var header: Control = maze._event_table._board.get_child(1)
	check(header._gold is RuneNumberDisplay and header._gold.text == "1499999", "事件和商店共用顶栏使用大卢恩数字")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Shop UI followup: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
