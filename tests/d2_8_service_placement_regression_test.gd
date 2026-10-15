extends "res://tests/d2_8_exchange_animation_ui_test.gd"

## 正式显示壳与真实拖放，验证服务期间落点、来源虚影和当前页产物归位。
func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("服务放置回归超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-service-placement-save.json"
	root.add_child(shell)
	shell.apply_display_mode(2 if "2k" in OS.get_cmdline_user_args() else 0)
	await create_timer(0.3).timeout
	var controller: CelestialIndicatorController = main.celestial_indicators
	var tray := controller.get_inventory_host()
	check(tray.get_parent() == main.world_content and controller._tray_board.get_parent() == main.world_content, "指示物和底板挂在同一个大世界坐标系")
	main.set_world_view(main.WorldView.COLLECTION, false)
	var collection_position := tray.get_global_transform_with_canvas().origin
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check(tray.position == Vector2(1080, 860) and tray.get_global_transform_with_canvas().origin - collection_position == Vector2(0, 360), "切换视角时指示物随世界平移，世界内位置不变")
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	for owned: OwnedCard in main.owned_card_collection.get_cards().duplicate():
		main.owned_card_collection.remove_by_instance_id(owned.instance_id)
	var materials := add_materials(CardData.Rarity.I)
	main.run_reward_state.gold = 200
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_exchange()
	await process_frame
	var data := {"kind": &"card", "owned_card": materials[0], "card_data": materials[0].card_data, "source_type": &"collection"}
	check(not main.front_row.can_receive_card_drag(data) and not main.back_row.can_receive_card_drag(data), "融合打开时前后排原生拖放均关闭")
	check(not main.player_resource_tray._enabled and not main.spell_preparation_tray._drop_enabled, "融合打开时资源和法术部署也关闭")
	var row_point: Vector2 = main.back_row.placement_overlay.get_global_transform_with_canvas() * (main.back_row.placement_overlay.size * 0.5)
	check(main._find_board_row_at(row_point) == null and not main._update_card_carry_target(row_point, data).get("accepted", false), "融合遮挡区域不产生点击携带战场目标或预留位")
	var original_slot: Control = main._find_collection_slot_for_owned_card(materials[0])
	var original: CardView = original_slot.get_child(0)
	var resting_position := original.position
	await click(original.get_global_rect().get_center())
	await click(row_point)
	await create_timer(0.25).timeout
	check(main.front_row.get_squads().is_empty() and main.back_row.get_squads().is_empty() and original.get_parent() == original_slot, "真实点击无效战场落点后回到收藏，没有部署")
	var native_source := original.get_global_rect().get_center()
	await motion(native_source)
	await button(native_source, true)
	await motion(native_source + Vector2(35, 3), true)
	await motion(row_point, true)
	check(shell.internal_viewport.gui_is_dragging() and not main.back_row.has_drop_reservation(), "真实长按拖到遮挡战场也不预留部署空间")
	await button(row_point, false)
	await create_timer(0.3).timeout
	check(main.back_row.get_squads().is_empty() and original.get_parent() == original_slot, "长按松手在遮挡战场不产生部署")
	await click(original.get_global_rect().get_center())
	await click(main._shop_exchange_slots[0].get_global_rect().get_center())
	var slot: Control = main._shop_exchange_slots[0]
	check(slot._card_view == original and original.is_layout_animating() and original.position.distance_to(slot.CARD_POSITION) > 1, "真实点击入槽时同一张卡从释放位置平滑移动")
	await create_timer(0.3).timeout
	check(original.position.is_equal_approx(slot.CARD_POSITION), "入槽动画最终落到固定轮廓位置")
	check(original_slot.get_child_count() == 1 and slot._source_ghost.get_parent() == original_slot and is_equal_approx(slot._source_ghost.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA) and slot._source_ghost.is_snapshot_mode() and slot._source_ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE, "收藏原位置保留只有展示用途的半透明虚影")
	main._build_collection_cards()
	await process_frame
	original_slot = main._find_collection_slot_for_owned_card(materials[0])
	check(slot._source_ghost.get_parent() == original_slot and slot._source_ghost.position == resting_position and slot._card_view == original, "重建收藏页保留正确位置的虚影和槽内真实卡")
	await capture("placement-ghost")
	var source := original.get_global_rect().get_center()
	await motion(source)
	await button(source, true)
	await motion(source + Vector2(35, 3), true)
	await motion(Vector2(1000, 620), true)
	await button(Vector2(1000, 620), false)
	await create_timer(0.3).timeout
	check(slot._card_view == null and original.get_parent() == original_slot and original_slot.get_child_count() == 1 and original.modulate.a == 1.0, "原生拖回收藏移除虚影并恢复原卡")
	source = original.get_global_rect().get_center()
	await motion(source)
	await button(source, true)
	await motion(source + Vector2(35, 3), true)
	await motion(slot.get_global_rect().get_center(), true)
	await button(slot.get_global_rect().get_center(), false)
	check(slot._card_view == original and original.is_layout_animating(), "原生长按拖入融合槽也播放平滑位移动画")
	check(is_equal_approx(original_slot.modulate.a, 1.0) and is_equal_approx(slot._source_ghost.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "原生拖入后来源容器恢复不透明，虚影只应用一次透明度")
	select_materials(materials)
	await create_timer(0.3).timeout
	main._execute_shop_exchange()
	var animation: Control = main._shop_exchange_animation
	var awarded: OwnedCard = main.owned_card_collection.get_cards().back()
	var reward_slot: Control = main._find_collection_slot_for_owned_card(awarded)
	check(reward_slot != null and not reward_slot.visible, "当前页产物卡位存在，飞回前隐藏实体")
	var reward_card: CardView = reward_slot.get_child(0)
	animation.landed.connect(func():
		var transform: Transform2D = animation.get_global_transform_with_canvas().affine_inverse() * reward_card.get_global_transform_with_canvas()
		check(animation._reward.position.distance_to(transform * (reward_card.card_size * 0.5)) < 0.1, "产物精确飞到当前页卡位中心")
	)
	var snapshot := animation._reward.get_child(0) as CardSnapshotVisual
	check(snapshot._viewport.size == Vector2i(snapshot.size) and snapshot._viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST and snapshot.get_texture_control().texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "融合内部按原生像素渲染并在两层使用最近邻采样")
	await wait_stage(animation, &"display")
	await capture("placement-pixel-display")
	await wait_stage(animation, &"fly")
	await create_timer(0.25).timeout
	check(animation._reward.modulate.a == 1.0 and animation._reward.scale.x > reward_card.scale.x, "当前页归位只缩放和平移，不提前淡出")
	await wait_stage(animation, &"shake")
	var target_transform: Transform2D = animation.get_global_transform_with_canvas().affine_inverse() * reward_card.get_global_transform_with_canvas()
	# 书本已开始抖动；检查归位大小和交接，而位置在landed瞬间检查。
	check(animation._reward.scale.is_equal_approx(target_transform.get_scale()) and reward_slot.visible and animation._reward.modulate.a == 0.0, "归位后恢复当前页实体卡的正常大小并交接显示")
	await animation.finished
	await process_frame
	check(reward_card.position == resting_position and reward_card.modulate.a == 1.0 and main.owned_card_collection.size() == 1, "动画结束只有正常卡位的一张产物，拥有权无重复")
	await capture("placement-returned")
	main._close_shop_card_services()
	check(main.front_row.can_receive_card_drag({"kind": &"card", "owned_card": awarded, "card_data": awarded.card_data, "source_type": &"collection"}), "关闭融合恢复战场拖放")
	shell.queue_free()
	await process_frame
	await test_enhancement()
	print("服务放置回归：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func test_enhancement() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-enhancement-placement-save.json"
	root.add_child(shell)
	shell.apply_display_mode(2 if "2k" in OS.get_cmdline_user_args() else 0)
	await create_timer(0.3).timeout
	var maze: ShortMazeController = main.maze_controller
	maze.new_run(1205)
	maze.choose_talent("sentry_guard")
	maze.select_path(maze.run.paths[0].path_id)
	maze.complete_event(false)
	maze.select_path(maze.run.paths[0].path_id)
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var data := {"kind": &"card", "owned_card": owned, "card_data": owned.card_data, "source_type": &"collection"}
	check(maze._enhancement_slot != null and not main.front_row.can_receive_card_drag(data) and not main.back_row.can_receive_card_drag(data), "事件强化开启时关闭前后排部署")
	var source_slot: Control = main._find_collection_slot_for_owned_card(owned)
	var source: CardView = source_slot.get_child(0)
	await click(source.get_global_rect().get_center())
	await click(maze._enhancement_slot.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(maze._enhancement_slot._card_view == source and source.position == maze._enhancement_slot.CARD_POSITION and source_slot.get_child_count() == 1 and is_equal_approx(maze._enhancement_slot._source_ghost.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "强化同样平滑入槽并在收藏保留虚影")
	maze.complete_event(false)
	await process_frame
	var returned_slot: Control = main._find_collection_slot_for_owned_card(owned)
	check(source.get_parent() == returned_slot and returned_slot.get_child_count() == 1 and source.modulate.a == 1.0 and main.front_row.can_receive_card_drag(data), "离开强化移除虚影、归还原卡并恢复部署")
	shell.queue_free()
	await process_frame
