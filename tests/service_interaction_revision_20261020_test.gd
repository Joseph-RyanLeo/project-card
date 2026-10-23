extends "res://tests/shop_event_materials_20261020_test.gd"

## 通过真实2K窗口及鼠标事件验证服务卡位、演出、透视和坐标。
func _motion(point: Vector2, held: bool = false) -> void:
	if DisplayServer.get_name() != "headless": Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super._motion(point, held)

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-revision-" + file + ".png")

func check_collection_ghost(owned: OwnedCard) -> void:
	_show_owned(owned)
	var slot: Control = main._find_collection_slot_for_owned_card(owned)
	check(is_instance_valid(slot) and slot.get_meta("is_deployed_ghost", false), "服务持卡保留收藏来源虚影")
	if not is_instance_valid(slot): return
	var ghost: CardView = slot.get_child(0)
	check(ghost.get_owned_card() == owned and ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE and not ghost._drag_enabled and is_equal_approx(ghost.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "虚影对应同一实例且不能交互")

func effective_z(item: CanvasItem) -> int:
	return item.z_index + (effective_z(item.get_parent() as CanvasItem) if item.z_as_relative and item.get_parent() is CanvasItem else 0)

func native_pick(view: CardView) -> void:
	var start := view.get_global_transform_with_canvas() * Vector2(25, 70)
	await _motion(start)
	await _mouse(start, true)
	await _motion(start + Vector2(38, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "原生长按启动真实卡牌拖拽")

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("服务交互修订验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-service-revision.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	check(main.ordinary_shop_panel.global_position == Vector2(189, 0), "商店原稿顶部完整位于屏幕内")
	check(main.enemy_resource_tray.position.x == 181 and main.enemy_spell_preparation_tray.position.x == 905, "敌方两个托盘向中央收起")
	check(main.enemy_resource_tray.visible and main.enemy_spell_preparation_tray.visible and not main.enemy_resource_tray.get_meta("expanded"), "收起保留两侧素材手柄")
	var tiles: Array[Node] = main.ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false)
	var initial := {}
	for tile: ShopOfferView in tiles:
		if is_instance_valid(tile._hover_surface): initial[tile] = tile._hover_surface.force
	await _motion(Vector2(40, 450))
	await create_timer(0.4).timeout
	var changing := 0
	for tile: ShopOfferView in initial:
		if tile._hover_surface.force != initial[tile]: changing += 1
		check(tile._visual.rotation == 0 and tile._hover_surface.force.length() < 0.4, "闲置使用检视透视force，不使用平面旋转")
	check(changing > 1, "各商品透视倾斜独立缓慢变化")
	for iteration: int in 3:
		await _click(main._shop_board_view._refresh)
		for frame: int in 3:
			await create_timer(0.04).timeout
			for stack: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
				check(stack._description.position.x == 0, "刷新报价原位出现，不从旧商品位置滑入")
	await capture("shop-top")
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	var a: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
	var b: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shieldwall_private.tres"), main.ordinary_shop_service.rng)
	var c: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
	for pair: Array in [[a, 0], [b, 1], [c, 2]]:
		_show_owned(pair[0])
		check(main._can_select_exchange_card({"kind": &"card", "owned_card": pair[0]}, pair[1]), "不同稀有度材料允许放入融合槽")
		main._select_exchange_card({"kind": &"card", "owned_card": pair[0]}, pair[1])
	await create_timer(0.3).timeout
	check(main._shop_exchange_confirm.disabled and main._shop_board_view._exchange_mark.texture.region == Rect2(0, 0, 11, 11), "混合品级仅显示叉号并禁用确认")
	check(main._shop_board_view._exchange_mark.size == Vector2(17, 17), "红叉和箭头共用固定尺寸，不产生拉伸")
	check(main._shop_board_view._rarity_dots[1].texture.atlas == main._shop_board_view.BEADS and main._shop_board_view._rarity_dots[1].texture.region == Rect2(16, 0, 13, 13), "融合使用用户原图铜色玻璃珠")
	check_collection_ghost(a)
	check_collection_ghost(b)
	check_collection_ghost(c)
	var expected_centers: Array[Vector2] = [Vector2(317.5, 87.5), Vector2(331.5, 87.5), Vector2(345.5, 87.5), Vector2(373.5, 87.5)]
	for index: int in 4:
		var dot: TextureRect = main._shop_board_view._rarity_dots[index]
		check(dot.get_rect().get_center() == expected_centers[index] and dot.size == Vector2(13, 13), "13×13珠子与原稿11×11槽位精确共心")
	check(main._shop_board_view._rarity_dots[0].get_rect().end.x + 1 == main._shop_board_view._rarity_dots[1].position.x and main._shop_board_view._rarity_dots[1].get_rect().end.x + 1 == main._shop_board_view._rarity_dots[2].position.x, "材料珠子之间各保留1原生像素间隙")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await capture("fusion-mixed")
	var slot: Control = main._shop_exchange_slots[0]
	var card: CardView = slot._card_view
	await _click(card)
	check(not main._click_carry_data.is_empty() and is_equal_approx(card.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "服务槽单击携带原位为虚影")
	main._cancel_click_carry()
	await create_timer(0.3).timeout
	await native_pick(card)
	check(is_equal_approx(card.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "服务槽原生长按拖拽原位也为同透明度虚影")
	await _motion(Vector2(650, 450), true)
	await _mouse(Vector2(650, 450), false)
	await create_timer(0.4).timeout
	check(main._shop_exchange_ids[0] == &"" and slot._card_view == null and not main._is_owned_card_deployed(a), "槽内卡随时取回收藏")
	main._close_shop_card_services()
	main._open_shop_card_services()
	var service_card := _service_card("revision")
	_show_owned(service_card)
	main._select_shop_service_card({"kind": &"card", "owned_card": service_card})
	await create_timer(0.24).timeout
	var flying: Control = main._shop_board_view._sticker_host.get_child(0)
	check_collection_ghost(service_card)
	check(effective_z(flying) > effective_z(main._shop_service_slot._card_view.stats_row) and effective_z(flying) > effective_z(main._shop_service_slot._card_view._status_slot_layer), "飞行贴纸层级高于卡面和属性图层")
	await capture("service-stickers-flight")
	check(flying.position.distance_to(main._shop_board_view.STICKER_CENTERS[0] - Vector2(16, 16)) > 1, "暂摘贴纸从真实卡面位置飞向目标点")
	await create_timer(0.35).timeout
	for index: int in main._shop_board_view._sticker_host.get_child_count():
		var button: Control = main._shop_board_view._sticker_host.get_child(index)
		var icon: TextureRect = button.get_node("StickerVisual")
		var used := icon.texture.get_image().get_used_rect()
		var actual := button.position + icon.position + Vector2(used.position) + Vector2(used.size) * 0.5
		check(actual.distance_to(main._shop_board_view.STICKER_CENTERS[index]) < 0.01, "纹章/元素贴纸实际像素中心对齐原稿点位")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await capture("service-stickers")
	main._close_shop_card_services()
	await create_timer(0.2).timeout
	check(not main._is_owned_card_in_service(service_card) and main.owned_card_collection.get_by_instance_id(service_card.instance_id) == service_card, "退出卡牌服务全部归收藏并保留实例")
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main.front_row.add_squad(SquadData.from_owned_card(a), 0)
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	main._select_shop_service_card({"kind": &"card", "owned_card": a})
	await create_timer(0.35).timeout
	check(main.front_row.get_squad_count() == 0 and is_instance_valid(main._shop_service_slot._card_view), "战场卡移入服务即解除部署且卡面仍存活")
	main._close_shop_card_services()
	await create_timer(0.2).timeout
	check(not main._is_owned_card_deployed(a), "退出服务不恢复旧战场位置")
	var bag: Control = main.emblem_library
	bag.receive_stickers([{"instance_id": "revision_return", "emblem_id": "火把", "kind": "emblem", "element_sticker": false}])
	main._close_shop_card_services()
	if main.ordinary_shop_open: main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_toolbox_inspection()
	await create_timer(0.4).timeout
	var entry: EmblemLibraryEntry
	for node: Node in bag.find_children("*", "Control", true, false):
		if node is EmblemLibraryEntry and String(node.definition.get("returned_state", {}).get("instance_id", "")) == "revision_return": entry = node
	check(is_instance_valid(entry), "定位真实工具箱内贴纸")
	if is_instance_valid(entry):
		var before_inventory: Array = bag.get_inventory_state().duplicate(true)
		var start := entry.get_global_rect().get_center()
		await _motion(start)
		await _mouse(start, true)
		await _motion(start + Vector2(38, 4), true)
		check(shell.internal_viewport.gui_is_dragging(), "工具箱内贴纸启动真实原生拖拽")
		await _motion(Vector2(1100, 300), true)
		await _mouse(Vector2(1100, 300), false)
		check(is_instance_valid(entry._lift_tween) and entry._lift_tween.is_running() and entry._icon.position != (entry.size - entry._icon.size) * 0.5, "非法放置后正在平滑飞回，不瞬移")
		await create_timer(0.35).timeout
		check(entry._icon.position.is_equal_approx((entry.size - entry._icon.size) * 0.5) and bag.get_inventory_state() == before_inventory, "回位完成且库存与布局没有变化")
	shell.queue_free()
	await process_frame
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-service-revision-event.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	_deal("loose_coins", 1000)
	maze.select_path("loose_coins")
	maze.complete_event()
	maze.select_path(maze.run.paths[0].path_id)
	await create_timer(0.2).timeout
	var table: Control = maze._event_table
	var tween: Tween = table._text_reveal
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/shieldwall_private.tres"))
	var second: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	_show_owned(owned)
	maze.select_enhancement_card({"kind": &"card", "owned_card": owned})
	check(maze._event_table == table and table._text_reveal == tween, "强化第一次入槽不重建文字和选项演出")
	await process_frame
	check_collection_ghost(owned)
	_show_owned(second)
	maze.select_enhancement_card({"kind": &"card", "owned_card": second})
	check(maze._event_table == table and maze._enhancement_slot._selected_card == second and table._text_reveal == tween, "换卡仅更新槽和选项可用性，不重播文字")
	check(table.detail_body.find_children("OptionTypewriter", "Label", true, false).is_empty(), "选项文字与选项条完整绑定，不逐字拆开")
	var paper: Control = table.get_node("EventDescription")
	await _mouse(paper.get_global_rect().get_center(), true)
	await _mouse(paper.get_global_rect().get_center(), false)
	check(table._reveal_speed > 1, "点击纸面加快正在进行的文字/选项演出")
	for click: int in 3:
		await _mouse(paper.get_global_rect().get_center(), true)
		await _mouse(paper.get_global_rect().get_center(), false)
	await create_timer(1.4).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await capture("enhancement-options")
	maze._enhancement_slot.return_card()
	await create_timer(0.25).timeout
	check(maze._enhancement_card_id == &"" and maze._event_table == table, "强化槽可以取下卡牌且不重播页面")
	_show_owned(second)
	maze.select_enhancement_card({"kind": &"card", "owned_card": second})
	await create_timer(0.2).timeout
	check(maze.apply_card_enhancement(0), "提交真实免费强化")
	await create_timer(0.3).timeout
	check(maze.run.selected_path.has("enhancement_result") and maze._enhancement_slot.allow_deployment, "强化后保留结果页及可重新部署的卡牌")
	check(not maze.apply_card_enhancement(0), "结果页不能重复强化/扣费")
	check(main.save_run_to_path("/private/tmp/project-card-enhancement-result-backup.json") == OK, "保存强化结果备份供离开与部署两条流程验收")
	var result_id := second.instance_id
	var result_gold: int = main.run_reward_state.gold
	check(maze.complete_event() and not main._is_owned_card_deployed(second), "直接离开强化结果页，卡牌回收藏且不恢复部署")
	check(main.load_run_from_path("/private/tmp/project-card-enhancement-result-backup.json"), "强化结果页真实存档可以读回")
	await create_timer(0.3).timeout
	second = main.owned_card_collection.get_by_instance_id(result_id)
	check(maze.run.selected_path.has("enhancement_result") and main.run_reward_state.gold == result_gold and not maze.apply_card_enhancement(0), "读档保留已付费结果并拒绝重复强化")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await native_pick(maze._enhancement_slot._card_view)
	var target := Vector2(650, main.front_row.global_position.y + 68)
	await _motion(target, true)
	await _mouse(target, false)
	await create_timer(0.4).timeout
	check(main._is_owned_card_deployed(second), "强化结果卡可用真实原生拖拽重新部署战场")
	for click: int in 4:
		await _mouse(Vector2(650, 260), true)
		await _mouse(Vector2(650, 260), false)
	await create_timer(0.5).timeout
	var result_buttons: Array[Node] = maze._event_table.detail_body.find_children("*", "Button", true, false)
	var result_tip: Label = maze._enhancement_options.get_child(0)
	check(result_buttons[0].get_global_rect().position.y >= result_tip.get_global_rect().end.y, "描述换行后选项条仍位于文字下方，不被动画旧坐标拉回")
	await capture("enhancement-result")
	check(maze.complete_event(), "结果页继续后推进旅程")
	await create_timer(0.2).timeout
	check(main._is_owned_card_deployed(second), "离开结果页保留玩家重新部署的阵容")
	DirAccess.remove_absolute("/private/tmp/project-card-enhancement-result-backup.json")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Service interaction revision: ", assertions, " checks, ", failures, " failures")
	quit(1 if failures else 0)
