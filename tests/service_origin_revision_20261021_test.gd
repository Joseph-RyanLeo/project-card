extends "res://tests/service_interaction_revision_20261020_test.gd"

## 原生输入验证借用卡牌、原位指示物、独立属性和失败回位。
const SAVE := "/private/tmp/project-card-service-origin-revision.json"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("服务原位回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	main.run_reward_state.gold = 1000
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var owned := _service_card("origin")
	owned.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 7)
	owned.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 11)
	for index: int in owned.rune_revealed.size(): owned.rune_revealed[index] = true
	var pure := SquadData.from_owned_card(owned)
	var squad := SquadData.from_owned_card(owned)
	var equipment: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/tower_shield.tres"))
	if equipment == null: equipment = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/tower_shield.tres"))
	check(squad.equip_item(equipment), "真实单卡装备物品")
	var sun := CelestialIndicator.new()
	sun.instance_id = &"origin_sun"
	sun.kind = CelestialIndicator.Kind.SUN
	check(squad.attach_indicator(sun, Vector2(65, 50), 0), "真实单卡附带独立太阳指示物")
	main.front_row.add_squad(squad, 0)
	main._build_collection_cards()
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await create_timer(0.5).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var original: BoardSlot = main.front_row.get_squads()[0]
	var original_rect := original.get_card_views()[0].get_global_rect()
	var source_state: Dictionary = owned.capture_state()
	await _drag(original.get_card_views()[0], main._shop_service_slot)
	await create_timer(0.45).timeout
	var service: Control = main._shop_service_slot
	check(service._selected_card == owned and original.get_squad_data() == squad, "服务仅借用原实例，原队伍及部署保留")
	if service._selected_card == null: quit(1); return
	check(original.get_card_views()[0].get_global_rect().position.distance_to(original_rect.position) < 1.0 and is_equal_approx(original.get_card_views()[0].modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA) and not original.get_card_views()[0]._drag_enabled, "原卡位保留不可拖动虚影且不让其他卡补位")
	check(squad.get_equipped_item() == equipment and squad.indicator_attachments[0].indicator == sun and original.get_equipment_indicator().visible and original.get_celestial_indicator(sun.instance_id).visible, "装备及指示物保留在原虚影处")
	await verify_pure(service, pure, owned, source_state)
	await capture("origin-service-pure")
	await _click(service._card_view)
	check(service._card_view.modulate.a == 0 and not main._click_carry_data.is_empty(), "单击携带时服务槽完全隐藏卡牌，不留槽内虚影")
	await _motion(Vector2(1130, 290))
	await _mouse(Vector2(1130, 290), true)
	await _mouse(Vector2(1130, 290), false)
	await create_timer(0.4).timeout
	check(service._selected_card == null and main._shop_service_card_id == &"" and original.get_card_views()[0].modulate.a == 1.0, "单击携带非法落点归还原战场位置并清空服务槽")
	check(squad.get_equipped_item() == equipment and squad.capture_indicators()[0].instance_id == String(sun.instance_id), "归位后仍是原装备和原指示物")
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.4).timeout
	await native_pick(service._card_view)
	check(service._card_view.modulate.a == 0, "原生拖拽时服务槽也不显示虚影")
	await _motion(Vector2(1130, 290), true)
	await _mouse(Vector2(1130, 290), false)
	await process_frame
	check(original.get_card_views()[0].is_layout_animating(), "原生非法放置从最后可见位置平滑回到来源虚影")
	await create_timer(0.4).timeout
	check(service._selected_card == null and main._is_owned_card_deployed(owned) and original.get_card_views()[0].modulate.a == 1, "上半区非法原生落点同样归还原位")
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.4).timeout
	main._close_shop_card_services()
	await create_timer(0.4).timeout
	check(original.get_squad_data() == squad and not original.has_service_ghosts() and squad.get_equipped_item() == equipment, "退出服务恢复原位实体及完整关联")
	var member: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	check(squad.insert_card(member.get_battlefield_card(), 1, SquadData.TwoCardLayout.COMPACT), "建立真实双卡小队")
	squad.bind_owned_card(member.get_battlefield_card(), member)
	original.set_squad_data(squad)
	main._open_shop_card_services()
	await create_timer(0.4).timeout
	main._select_shop_service_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.4).timeout
	check(squad.get_card_count() == 2 and squad.get_equipped_item() == equipment and service._card_view.get_owned_card() == owned, "双卡借出成员保留层级与原小队装备")
	await verify_pure(service, pure, owned, source_state)
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.4).timeout
	check(main._inspection_card_view._squad_health_preview_target == pure.get_effective_max_health(), "服务卡右键检视也排除原小队／外部加成")
	main._close_card_inspection(true)
	check(not main._shop_board_view._service_action.disabled, "借用小队成员后出售／提取按钮仍可用")
	await _click(main._shop_board_view._service_action)
	await create_timer(0.3).timeout
	check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == null and original.get_squad_data().get_card_count() == 1, "确认出售才移除真实成员和原位虚影")
	await _click(main._shop_board_view._service_action)
	await create_timer(0.4).timeout
	check(main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned and service._selected_card == owned, "出售撤销仍完整返还原实例到服务槽")
	main._close_shop_card_services()
	main._open_shop_card_services()
	await create_timer(0.4).timeout
	var other: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
	_show_owned(other)
	main._select_exchange_card({"kind": &"card", "owned_card": other}, 0)
	await create_timer(0.4).timeout
	var exchange: Control = main._shop_exchange_slots[0]
	await native_pick(exchange._card_view)
	check(exchange._card_view.modulate.a == 0, "融合材料槽原生拖起同样不显示虚影")
	await _motion(Vector2(1130, 290), true)
	await _mouse(Vector2(1130, 290), false)
	await create_timer(0.4).timeout
	var collection_slot: Control = main._find_collection_slot_for_owned_card(other)
	check(exchange._selected_card == null and not collection_slot.get_meta("is_deployed_ghost", true), "收藏来源的融合卡非法落点归还收藏虚影位置")
	main._close_shop_card_services()
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(main._tabletop_park_button.texture_disabled.resource_path.ends_with("tabletop_park_dark.png") and main._tabletop_park_button.disabled and main._tabletop_park_button.size == Vector2(82, 21), "上半视角使用用户暗按钮及82×21原生尺寸")
	main.set_world_view(main.WorldView.COLLECTION, false)
	check(not main._tabletop_park_button.disabled and main._tabletop_park_button.texture_normal.resource_path.ends_with("tabletop_park_bright.png") and main._tabletop_park_button.global_position == Vector2(599, 349), "下半视角使用亮按钮且世界坐标保持599,713")
	await capture("origin-button-bright")
	shell.queue_free()
	await process_frame
	await verify_enhancement()
	DirAccess.remove_absolute(SAVE)
	print("服务原位与按钮素材：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func verify_pure(service: Control, pure: SquadData, owned: OwnedCard, source_state: Dictionary) -> void:
	await create_timer(0.3).timeout
	var view: CardView = service._card_view
	check(view._squad_action_preview_target == pure.get_effective_action_base_value() and view._squad_health_preview_target == pure.get_effective_max_health() and view._squad_armor_preview_target == pure.get_effective_base_armor(), "服务属性计算自身伤势、纹章、已揭晓符文与永久成长")
	var data: Dictionary = view._build_drag_data(Vector2(20, 60))
	var carried: SquadData = data.squad_data
	check(carried.get_equipped_item() == null and carried.indicator_attachments.is_empty() and not data.has("attached_equipment_data") and view.find_children("*", "CelestialIndicatorView", true, false).is_empty(), "服务卡及拖拽预览均不携带装备或独立指示物数据")
	check(owned.capture_state() == source_state and view.get_owned_card() == owned, "借用不修改本卡永久数据或复制OwnedCard")

func verify_enhancement() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	maze = main.maze_controller
	_deal("loose_coins", 1000)
	check(maze.select_path("loose_coins") and maze.complete_event() and maze.select_path(maze.run.paths[0].path_id), "真实流程进入强化事件")
	var owned := _service_card("enhance")
	var squad := SquadData.from_owned_card(owned)
	main.back_row.add_squad(squad, 0)
	main._build_collection_cards()
	main.set_world_view(main.WorldView.COLLECTION, false)
	await create_timer(0.3).timeout
	var slot: BoardSlot = main.back_row.get_squads()[0]
	maze.select_enhancement_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.4).timeout
	check(slot.has_service_ghosts() and maze._enhancement_slot._selected_card == owned, "强化保留来源战场虚影")
	await native_pick(maze._enhancement_slot._card_view)
	check(maze._enhancement_slot._card_view.modulate.a == 0, "强化槽拖起完全隐藏")
	await _motion(Vector2(1130, 290), true)
	await _mouse(Vector2(1130, 290), false)
	await create_timer(0.4).timeout
	check(maze._enhancement_card_id == &"" and slot.get_squad_data() == squad and not slot.has_service_ghosts(), "强化非法落点归还原位置并保留小队关系")
	maze.select_enhancement_card({"kind": &"card", "owned_card": owned})
	await create_timer(0.3).timeout
	check(maze.apply_card_enhancement(0), "新流程可正常提交强化")
	await create_timer(0.4).timeout
	check(maze._enhancement_slot.allow_deployment, "强化结果仍支持重新部署")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await _drag(maze._enhancement_slot._card_view, main.front_row)
	await create_timer(0.5).timeout
	check(main.front_row.get_squad_count() == 1 and main.back_row.get_squad_count() == 0 and main._is_owned_card_deployed(owned), "结果重新部署移动原实例，不留下第二份真实部署")
	shell.queue_free()
	await process_frame
