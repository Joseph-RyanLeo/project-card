extends SceneTree

## 正式显示壳、真实输入验证商店层级、实际卡面暂存和Esc还原。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
var shell: Control
var main: Control
var assertions := 0
var failures := 0
var pointer := Vector2.ZERO

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func motion(point: Vector2, held: bool = false) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var event := InputEventMouseMotion.new()
	event.position = outer
	event.global_position = outer
	event.relative = outer - pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = outer
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

func click(point: Vector2) -> void:
	await motion(point)
	await button(point, true)
	await button(point, false)

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-followup-%s.png" % label)

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("商店追加专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-followup-ui-save.json"
	root.add_child(shell)
	shell.apply_display_mode(0)
	await create_timer(0.3).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1205)
	maze.choose_talent("sentry_guard")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	main.set_world_view(main.WorldView.COLLECTION, false)
	var original_slot: Control = main._find_collection_slot_for_owned_card(owned)
	var original: CardView = original_slot.get_child(0)
	check(original._new_card_dot.visible, "新收藏卡显示绿点")
	await motion(original.get_global_rect().get_center())
	check(not owned.is_new and not original._new_card_dot.visible, "指向收藏卡清除该实例绿点")
	var resources: Array = main.resource_board_state.get_level_resource_cards("player")
	if resources.is_empty(): resources = main.resource_board_state.get_level_resource_cards("enemy")
	check(not resources.is_empty(), "测试使用真实生成的场上资源")
	if not resources.is_empty():
		var resource: OwnedCard = resources[0]
		var tray: Control = main.player_resource_tray if main.resource_board_state.is_level_resource("player", String(resource.instance_id)) else main.enemy_resource_tray
		tray._hover_instance_id = resource.instance_id
		tray._refresh_hover_card()
		check(tray._hover_card != null and not tray._hover_card._new_card_dot.visible, "敌我资源板详情不显示收藏绿点")
		tray._hover_card._on_mouse_entered()
		check(resource.is_new, "指向非收藏详情不会修改新卡标识数据")
		tray._clear_hover_card()
	maze.select_path(maze.run.paths[0].path_id)
	maze.complete_event(false)
	maze.select_path(maze.run.paths[0].path_id)
	main.set_world_view(main.WorldView.COLLECTION, false)
	original_slot = main._find_collection_slot_for_owned_card(owned)
	original = original_slot.get_child(0)
	var target: Control = maze._enhancement_slot
	await click(original.get_global_rect().get_center())
	await click(target.get_global_rect().get_center())
	target = maze._enhancement_slot
	check(target._card_view == original and not original.is_snapshot_mode() and original_slot.get_child_count() == 0, "强化实际移动同一卡面，来源不再重复显示")
	await click(original.get_global_rect().get_center())
	check(main._click_carry_data.get("source_type") == &"card_service", "强化槽内卡可以真实抓取")
	await click(Vector2(1000, 620))
	await create_timer(0.1).timeout
	check(main._click_carry_data.is_empty() and maze._enhancement_card_id.is_empty() and original.get_parent() == original_slot, "强化卡放回收藏，清空选择并归还原节点")
	maze.select_enhancement_card({"kind": &"card", "owned_card": owned})
	maze.complete_event(false)
	check(not original.has_meta("card_service_slot") and main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned, "离开强化归还卡牌，不丢失拥有实例")
	maze.select_path(maze.run.paths[0].path_id)
	await create_timer(0.4).timeout
	check(main.ordinary_shop_open and maze._sentry_bar.is_visible_in_tree(), "商店事件显示哨位库存")
	check(main.celestial_indicators.get_inventory_host().get_global_rect().end.y <= 720, "指示物板在商店战场视图内保持屏幕可见")
	check(maze._sentry_bar.get_children().all(func(node: Node): return not node is Label), "哨位库存仅显示图标，没有数量标签")
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	var equipment: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/coarse_bandage.tres"))
	board_slot.get_squad_data().equip_item(equipment)
	board_slot.set_squad_data(board_slot.get_squad_data())
	check(main.ordinary_shop_layer.z_index > board_slot.pattern_label.z_index and main.ordinary_shop_layer.z_index > board_slot.get_equipment_indicator().z_index, "商店覆盖牌型与装备图标")
	check(main.ordinary_shop_layer.get_node_or_null("ClaimRandomCardRequestsButton") == null, "商店不再出现随机卡领取按钮")
	await screenshot("shop")
	main._open_shop_card_services()
	var source_view: CardView = board_slot.get_primary_card_view()
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	check(main._shop_service_slot._card_view == source_view and source_view.get_parent() != board_slot.card_visual_layer, "商店暂存实际战场卡面")
	await click(source_view.get_global_rect().get_center())
	await motion(Vector2(1000, 620))
	await button(Vector2(1000, 620), true, MOUSE_BUTTON_RIGHT)
	await button(Vector2(1000, 620), false, MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	check(main._shop_service_slot._card_view == source_view and source_view.modulate.a == 1, "取消槽内抓取返回服务槽，不丢失选择")
	# 原生拖动从服务槽归还收藏，仍恢复原战场绑定。
	var source := source_view.get_global_rect().get_center()
	await motion(source)
	await button(source, true)
	await motion(source + Vector2(35, 3), true)
	check(shell.internal_viewport.gui_is_dragging(), "槽内卡支持原生长按拖动")
	await motion(Vector2(1000, 620), true)
	await button(Vector2(1000, 620), false)
	await create_timer(0.15).timeout
	check(main._shop_service_card_id.is_empty() and source_view.get_parent() == board_slot.card_visual_layer and board_slot.get_squad_data().get_owned_card(source_view.card_data) == owned, "原生归还恢复原卡面及战场归属")
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	main._close_shop_card_services()
	check(source_view.get_parent() == board_slot.card_visual_layer and not source_view.has_meta("card_service_slot"), "退出卡牌服务自动归还")
	main._open_shop_card_services()
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	var save_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-missing-followup-parent/run.json"
	main._execute_shop_sale(owned.instance_id, main._shop_card_sale_price(owned))
	check(main.owned_card_collection.get_by_instance_id(owned.instance_id) != null and main._shop_service_slot._card_view != null, "实际卡面出售保存失败后恢复卡牌、部署和槽内选择")
	main.run_save_path = save_path
	var restored: OwnedCard = main.owned_card_collection.get_by_instance_id(owned.instance_id)
	main._execute_shop_sale(restored.instance_id, main._shop_card_sale_price(restored))
	check(main.owned_card_collection.get_by_instance_id(restored.instance_id) == null and main._shop_service_slot._card_view == null and main._shop_service_card_id.is_empty() and main.front_row.get_squads().is_empty(), "实际卡面出售成功清空槽位和宿主，不留下第二份卡面")
	main._close_shop_card_services()
	# 正式暂停入口与正式还原按钮。
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	check(main._escape_pause_menu.is_menu_open(), "Esc打开正式暂停菜单")
	main._escape_pause_menu.restore_requested.emit()
	await create_timer(0.2).timeout
	check(not main.ordinary_shop_open and not main.ordinary_shop_panel.visible and main.maze_controller.run.step != ShortMazeRunState.Step.EVENT, "商店还原后关闭旧空面板并恢复启动流程")
	check(main._shop_service_slot._card_view == null, "还原释放暂存卡槽")
	main._escape_pause_menu.close_menu()
	await screenshot("restored")
	shell.queue_free()
	await process_frame
	print("商店追加界面：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
