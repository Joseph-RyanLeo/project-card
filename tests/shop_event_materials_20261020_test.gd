extends "res://tests/event_cards_test.gd"

## 新棋盘的真实显示壳、鼠标输入、存档事务与落位演出验收。
const PREVIEW_DIR := "res://docs/previews/shop_event_20261020/"
var _pointer := Vector2.ZERO

func _motion(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - _pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_pointer = outer
	root.push_input(event, true)
	await process_frame

func _mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event, true)
	await process_frame

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	await _motion(point)
	await _mouse(point, true)
	await _mouse(point, false)

func _drag(view: CardView, target: Control) -> void:
	var start := view.get_global_transform_with_canvas() * (view.card_size * Vector2(0.25, 0.68))
	var end := target.get_global_rect().get_center() + Vector2(45, 0)
	await _motion(start)
	await _mouse(start, true)
	await _motion(start + Vector2(38, 4), true)
	check(shell.internal_viewport.gui_is_dragging(), "原生长按拖动真实卡面")
	await _motion(end, true)
	await _mouse(end, false)

func _frame(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png(PREVIEW_DIR + name_value + ".png")

func _show_owned(owned: OwnedCard) -> CardView:
	main._sync_legacy_collection_cards()
	for page: int in main.get_collection_spread_count():
		main.current_collection_page = page
		main._build_collection_cards()
		var slot: Control = main._find_collection_slot_for_owned_card(owned)
		if slot != null and slot.get_child_count() > 0: return slot.get_child(0) as CardView
	return null

func _service_card(suffix: String) -> OwnedCard:
	var definition: CardData
	for candidate: CardData in main._get_shop_card_definitions():
		if candidate.card_type == CardData.CardType.MINION and candidate.rarity == CardData.Rarity.IV and main.owned_card_collection.find_first_by_definition(candidate) == null:
			definition = candidate
			break
	if definition == null:
		for candidate: CardData in main._get_shop_card_definitions():
			if candidate.card_type == CardData.CardType.MINION and candidate.rarity == CardData.Rarity.IV:
				definition = candidate
				break
	var owned: OwnedCard = main.owned_card_collection.create_card(definition, main.ordinary_shop_service.rng)
	if owned == null: return null
	for index: int in 4:
		owned.set_emblem_slot(index, {"instance_id": "service_%s_emblem%d" % [suffix, index], "emblem_id": ["火把", "长剑", "面包", "盾牌Ⅰ"][index], "element_sticker": false})
	for index: int in 3:
		owned.set_rune_sticker(index, {"instance_id": "service_%s_rune%d" % [suffix, index], "emblem_id": ["火贴纸", "水贴纸", "光贴纸"][index], "element_sticker": true, "element": [0, 1, 3][index]})
	owned.wound_slots[0] = {"instance_id": "service_%s_wound" % suffix, "wound_id": "中毒Ⅰ"}
	return owned

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("新棋盘专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-shop-event-materials-save.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	var index := _deal("ioann_prayer")
	await process_frame
	check(index >= 0 and is_instance_valid(maze._event_table), "实际事件池生成候选，建立新棋盘")
	check(maze._event_table.cards.is_empty() and maze._event_table._deck.size == Vector2(166, 153), "初始只显示中央原生牌堆，不自动发牌")
	var fixed_position: Vector2 = maze._panel.global_position
	check(fixed_position == Vector2(189, -6) and maze._panel.size == Vector2(902, 351), "事件棋盘坐标与原生尺寸准确")
	main.set_world_view(main.WorldView.COLLECTION)
	main._view_tween.pause()
	for step: float in [0.12, 0.20, 0.12]:
		main._view_tween.custom_step(step)
		check(maze._panel.global_position == fixed_position and maze._panel.visible, "事件棋盘不继承视角的移动与回弹")
	check(main.world_content.position == Vector2(0, -367), "下半视角不再横移1像素")
	check(main.world_content.position + Vector2(189, 361) == fixed_position, "下半世界(189,361)与上半世界(189,-3)映射至同一屏幕点")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await _frame("event_deck")
	await _click(maze._event_table._deck)
	await _click(maze._event_table._deck)
	await create_timer(0.6).timeout
	check(maze._event_table.cards.size() == 3 and not maze._event_table.busy, "实际点击牌堆只发出三张候选，连击不重复发牌")
	for card: EventCardView in maze._event_table.cards:
		check(card.scale == Vector2(2, 2) and not card.face_up and card.tooltip_text.is_empty(), "候选按2倍显示，未选中前不泄漏详情")
	check(is_equal_approx(maze._event_table._dim.color.a, 0.7), "背景渐暗到目标透明度")
	check(maze._event_table.cards[1].get_global_rect().get_center().is_equal_approx(Vector2(640, 360)), "三张牌等距居中，中央牌精确位于画布中心")
	var paths := maze.run.paths.duplicate(true)
	var rng_state := maze.run.rng.state
	var table: Control = maze._event_table
	maze.refresh()
	check(table == maze._event_table and maze.run.paths == paths and maze.run.rng.state == rng_state, "刷新保留已展开牌桌，不重抽、不收起")
	await _frame("event_choices")
	var event_good_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-absent-event-choice-directory/test.json"
	await _click(maze._event_table.cards[index])
	check(table.busy and maze.run.step == ShortMazeRunState.Step.CHOOSING, "点击后锁定选择，动画不提前重复提交路径")
	await create_timer(1.05).timeout
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and maze.run.paths == paths and maze.run.rng.state == rng_state, "路径选择保存失败时恢复候选与游戏随机源")
	check(maze._event_table != table and is_instance_valid(maze._event_table._deck) and not maze._event_table.busy, "失败后清理退场的旧模态层，恢复可点击牌堆")
	main.run_save_path = event_good_path
	await _click(maze._event_table._deck)
	await create_timer(0.6).timeout
	await _click(maze._event_table.cards[index])
	if DisplayServer.get_name() != "headless":
		var times: Array[float] = []
		for frame: int in 42:
			await create_timer(1.0 / 30.0).timeout
			await _frame("transition_%03d" % frame)
			times.append(Time.get_ticks_usec() / 1000000.0)
		var timing := FileAccess.open(PREVIEW_DIR + "transition_times.json", FileAccess.WRITE)
		timing.store_string(JSON.stringify(times))
		timing.close()
	else:
		await create_timer(1.05).timeout
	check(maze.run.selected_path.get("path_id") == "ioann_prayer", "翻牌与落位完成后提交真实事件")
	check(maze._event_table.get_node("SelectedEventCard").position == Vector2(116, 108), "选中牌最终以原生大小落到图稿卡位")
	check(maze._event_table.get_node("EventDescription").position == Vector2(368, 70), "事件内容限制在纸面区域")
	await create_timer(0.5).timeout
	check(is_equal_approx(maze._event_table.detail_body.modulate.a, 1.0), "描述与选项逐渐浮现到正常亮度")
	var selected_table: Control = maze._event_table
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(maze._event_table == selected_table and maze._panel.global_position == fixed_position, "切换视角不重建描述页或中断其演出")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await _frame("event_description")
	check(maze.choose_story_option(0), "新纸面仍调用真实事件奖励服务")
	check(main.celestial_indicators.items.size() == 1 and not maze.choose_story_option(0), "奖励只领取一次")
	check(maze.complete_event(), "事件完成后正常推进强化轮")
	check(maze.select_path(maze.run.paths[0].path_id), "实际选择强化事件")
	main.set_world_view(main.WorldView.COLLECTION, false)
	var trainee: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var original := _show_owned(trainee)
	await process_frame
	await _drag(original, maze._enhancement_slot)
	await create_timer(0.35).timeout
	check(maze._enhancement_slot._card_view == original, "强化槽接收原卡并沿用平滑吸附")
	check(original.position == maze._enhancement_slot.CARD_POSITION, "强化槽吸附结束准确归位")
	check(maze.apply_card_enhancement(0), "强化仍写入原OwnedCard并推进商店轮")
	check(maze.select_path(maze.run.paths[0].path_id), "选择真实商店路径")
	maze.enter_selected_shop()
	await create_timer(0.5).timeout
	check(main.ordinary_shop_open and main.ordinary_shop_panel.position == Vector2(189, -6), "商店打开在固定棋盘坐标")
	check(main.ordinary_shop_offer_list.visible and not main._shop_card_service_panel.visible, "商店默认显示购物页")
	await _frame("shop_goods")
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	await create_timer(0.5).timeout
	check(main._shop_card_service_panel.visible and main._shop_exchange_panel.visible and not main.ordinary_shop_offer_list.visible, "下方页签同时展示三卡融合和单卡服务")
	check(main.world_content.position.x == 0.0 and main.ordinary_shop_panel.position == fixed_position, "商店切至下半视角时没有横移和回弹")
	var service_card := _service_card("sale")
	check(service_card != null and main._tearable_stickers(service_card).size() == 7, "IV卡真实4纹章加3元素，伤势排除")
	if service_card == null:
		quit(1)
		return
	var source := _show_owned(service_card)
	await process_frame
	await _motion(source.get_global_rect().get_center())
	var before := service_card.capture_state()
	var sale_price: int = main._shop_card_sale_price(service_card)
	await process_frame
	await _drag(source, main._shop_service_slot)
	await create_timer(0.35).timeout
	check(main._shop_service_slot._card_view == source and source.position == main._shop_service_slot.CARD_POSITION, "右侧单卡在槽位附近松手后平滑吸附")
	check(service_card.capture_state() == before and source._service_stickers_detached, "暂卸仅改变卡面显示，原卡所有槽位数据不变")
	check(main._shop_board_view._sticker_host.get_child_count() == 7 and main._shop_board_view._service_action.text == "出售", "最多7枚贴纸环绕显示，未选时为出售")
	check(main._shop_card_sale_price(service_card) == sale_price and main._shop_board_view._amount.text == "+%d" % sale_price, "暂卸后卖价保留全部贴纸加成与伤势扣减")
	await _frame("shop_services")
	await _click(main._shop_board_view.get_node("ShoppingTab"))
	check(service_card.capture_state() == before and not source._service_stickers_detached and not source.has_meta("card_service_slot"), "切购物页归还真实卡面及贴纸显示，不改变卡牌数据")
	await _click(main._shop_board_view.get_node("CardServicesTab"))
	main._select_shop_service_card({"kind": &"card", "owned_card": service_card})
	var sale_id := service_card.instance_id
	var gold_before: int = main.run_reward_state.gold
	await _click(main._shop_board_view._service_action)
	check(main.owned_card_collection.get_by_instance_id(sale_id) == null and main.run_reward_state.gold == gold_before + sale_price, "点击出售直接销毁卡牌与贴纸，获得所显示金币")
	check(main.ordinary_shop_layer.find_children("*", "ConfirmationDialog", true, false).is_empty(), "出售不再打开旧二次确认框")
	for count: int in [1, 2, 3]:
		var owned := _service_card("extract%d" % count)
		check(owned != null, "建立真实提取卡%d" % count)
		if owned == null: continue
		_show_owned(owned)
		main._select_shop_service_card({"kind": &"card", "owned_card": owned})
		var id := owned.instance_id
		var sticker_states: Array[Dictionary] = main._tearable_stickers(owned)
		for selected: int in count:
			await _click(main._shop_board_view._sticker_host.get_child(selected))
		check(main._shop_board_view._service_action.text == "提取" and main._shop_board_view._selection.size() == count, "选中%d枚后切换到提取" % count)
		var price: int = [2, 5, 10][count - 1]
		check(main._shop_board_view._amount.text == "−%d" % price, "按原阶梯价格显示提取费用")
		if count == 3:
			await _click(main._shop_board_view._sticker_host.get_child(3))
			check(main._shop_board_view._selection.size() == 3, "第4枚不能突破最多提取3枚")
			main.run_reward_state.gold = 0
			main._refresh_shop_card_services()
			check(main._shop_board_view._service_action.disabled, "金币不足时提取禁用")
			main.run_reward_state.gold = 100
			main._refresh_shop_card_services()
		var inventory_before: int = main.emblem_library.get_inventory_state().size()
		gold_before = main.run_reward_state.gold
		await _click(main._shop_board_view._service_action)
		check(main.owned_card_collection.get_by_instance_id(id) == null and main.run_reward_state.gold == gold_before - price, "提取%d枚只扣对应费用并销毁卡牌" % count)
		var inventory: Array = main.emblem_library.get_inventory_state()
		check(inventory.size() == inventory_before + count, "仅选中%d枚贴纸返还真实工具箱" % count)
		for selected: int in count:
			check(inventory.any(func(state: Dictionary): return String(state.instance_id) == String(sticker_states[selected].instance_id)), "返还原贴纸实例，保留身份")
	# 提取工具箱满时进入已有临时区域，不丢弃已付款的原贴纸。
	var original_inventory: Array = main.emblem_library.get_inventory_state().duplicate(true)
	var full: Array[Dictionary] = []
	for filled: int in 28:
		full.append({"instance_id": "full_service_%d" % filled, "emblem_id": "火把", "kind": "emblem", "element_sticker": false})
	check(main.emblem_library.receive_stickers(full), "填满真实工具箱，保持原有容量策略")
	var overflow := _service_card("overflow")
	_show_owned(overflow)
	main._select_shop_service_card({"kind": &"card", "owned_card": overflow})
	await _click(main._shop_board_view._sticker_host.get_child(4))
	await _click(main._shop_board_view._service_action)
	var overflow_inventory: Array = main.emblem_library.get_inventory_state()
	check(overflow_inventory.any(func(state: Dictionary): return String(state.instance_id) == "service_overflow_rune0" and EmblemStickerInventory.is_dropped(state)), "工具箱满时提取的元素贴纸进入真实临时区域")
	main.emblem_library.restore_inventory_state(original_inventory)
	# 从战场借用的装备宿主出售后，装备仍由原拥有实例保留。
	var host := _service_card("equipment")
	var item: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/coarse_bandage.tres"))
	if item == null: item = main.owned_card_collection.create_card(load("res://resources/cards/coarse_bandage.tres"), main.ordinary_shop_service.rng)
	var squad := SquadData.from_owned_card(host)
	check(item != null and squad.equip_item(item), "出售验收使用真实装备和宿主实例")
	var host_slot: BoardSlot = main.front_row.add_squad(squad, 0)
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	main._refresh_drag_availability()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await process_frame
	await _drag(host_slot.get_primary_card_view(), main._shop_service_slot)
	await create_timer(0.35).timeout
	check(main._shop_service_slot._card_view != null and main._shop_service_slot._card_view.get_owned_card() == host, "卡牌服务可从战场抓取真实单卡")
	var host_id := host.instance_id
	await _click(main._shop_board_view._service_action)
	check(main.owned_card_collection.get_by_instance_id(host_id) == null and main.owned_card_collection.get_by_instance_id(item.instance_id) == item and main._get_squad_for_owned_instance(item.instance_id) == null, "出售宿主销毁卡牌，装备原实例返还收藏")
	main.set_world_view(main.WorldView.COLLECTION, false)
	# 保存失败时验证完整事务回滚，随后切页验证未成交归还。
	var failed := _service_card("rollback")
	_show_owned(failed)
	main._select_shop_service_card({"kind": &"card", "owned_card": failed})
	await _click(main._shop_board_view._sticker_host.get_child(0))
	var failed_before := failed.capture_state()
	var failed_id := failed.instance_id
	var inventory_before: Array = main.emblem_library.get_inventory_state().duplicate(true)
	gold_before = main.run_reward_state.gold
	var good_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-absent-shop-event-directory/test.json"
	await _click(main._shop_board_view._service_action)
	check(main.owned_card_collection.get_by_instance_id(failed_id).capture_state() == failed_before and main.run_reward_state.gold == gold_before and main.emblem_library.get_inventory_state() == inventory_before, "提取保存失败恢复卡牌、七枚贴纸、金币与工具箱")
	main.run_save_path = good_path
	main._close_shop_card_services()
	main._open_shop_card_services()
	var materials: Array[OwnedCard] = []
	for material_index: int in 3:
		var material: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"), main.ordinary_shop_service.rng)
		materials.append(material)
		var material_view := _show_owned(material)
		await process_frame
		await _drag(material_view, main._shop_exchange_slots[material_index])
		await create_timer(0.35).timeout
		check(main._shop_exchange_slots[material_index]._card_view == material_view and material_view.position == main._shop_exchange_slots[material_index].CARD_POSITION, "融合槽%d附近松手后真实卡面平滑吸附归位" % material_index)
	check(not main._shop_exchange_confirm.disabled, "同页三卡槽接收三个真实同品级实例")
	var materials_count: int = main.owned_card_collection.get_cards().size()
	await _click(main._shop_exchange_confirm)
	check(main.owned_card_collection.get_cards().size() == materials_count - 2, "融合真实消耗3张、获得1张高一级卡")
	for material: OwnedCard in materials:
		check(main.owned_card_collection.get_by_instance_id(material.instance_id) == null, "融合材料从拥有集合移除")
	await create_timer(3.0).timeout
	check(not is_instance_valid(main._shop_exchange_animation), "现有融合演出完成并清理")
	check(main.save_run_to_path(good_path) == OK and main.load_run_from_path(good_path), "新界面交易后真实存档可读回")
	await process_frame
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._refresh_ordinary_shop_panel()
	await _frame("shop_restored")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(good_path)
	print("商店事件新素材：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
