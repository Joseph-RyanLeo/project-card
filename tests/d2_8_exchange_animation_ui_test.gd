extends "res://tests/d2_8_card_exchange_ui_test.gd"

## 复用正式鼠标输入工具，单独验证新增演出及服务卡悬停/单击携带。
func wait_stage(animation: Control, expected: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(animation) and animation.stage != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(animation) and animation.stage == expected, "演出到达阶段：" + String(expected))

func white_amount(visual: Control) -> float:
	var snapshot := visual.get_child(0) as CardSnapshotVisual
	var material := snapshot.get_texture_control().material as ShaderMaterial
	var value: Variant = material.get_shader_parameter("white_amount")
	# 尚未覆盖的参数由Shader默认值控制，直接读取渲染器中的真实默认值。
	if value == null:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), &"white_amount")
	return float(value)

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("置换动画专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-exchange-animation-save.json"
	root.add_child(shell)
	shell.apply_display_mode(0)
	await create_timer(0.3).timeout
	main.run_reward_state.gold = 200
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_exchange()
	main.ordinary_shop_service.rng.seed = 20261015 # 固定演出测试样本，避免随机抽到附送装备的卡改变库存断言
	var materials := add_materials(CardData.Rarity.I)
	select_materials(materials)
	await process_frame
	var original: CardView = main._shop_exchange_slots[0]._card_view
	await motion(original.get_global_rect().get_center())
	await create_timer(0.25).timeout
	check(not original._interaction_shadow.visible and is_zero_approx(original.rotation) and is_zero_approx(original._external_lift), "槽内悬停不生成偏移阴影、轻晃或残留抽出位移")
	var visible_originals := get_nodes_in_group("card_views").filter(func(view: CardView): return view.get_owned_card() == materials[0] and view.is_visible_in_tree() and not view.is_snapshot_mode())
	check(visible_originals.size() == 1, "槽内只有一张原卡面，不生成重影副本")
	await capture("animation-hover")
	await click(original.get_global_rect().get_center())
	check(main._click_carry_data.get("source_type") == &"card_service" and main._click_carry_preview != null, "真实单击抓取槽内卡，创建携带图像")
	var destination := Vector2(555, 430)
	await motion(destination)
	await create_timer(0.12).timeout
	print("鼠标携带跟随位置：", main._click_carry_preview.global_position, "，目标：", destination)
	check(main._click_carry_preview.global_position.distance_to(destination) <= 2.0, "服务槽单击预览持续跟随鼠标，允许原生鼠标坐标取整的2像素误差")
	check(is_equal_approx(original.modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA) and main._click_carry_preview.is_visible_in_tree(), "抓取后来源虚化且鼠标卡图可见")
	await capture("animation-carry")
	await button(destination, true, MOUSE_BUTTON_RIGHT)
	await button(destination, false, MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	check(main._click_carry_data.is_empty() and main._shop_exchange_slots[0]._card_view == original and original.modulate.a == 1.0, "右键取消恢复原槽与原卡")
	# 长按仍通过原生拖放归还，再用单击从收藏放回同一槽。
	var source := original.get_global_rect().get_center()
	await motion(source)
	await button(source, true)
	await motion(source + Vector2(35, 3), true)
	check(shell.internal_viewport.gui_is_dragging(), "悬停修正保留原生长按抓取")
	await motion(Vector2(1000, 620), true)
	await button(Vector2(1000, 620), false)
	await create_timer(0.2).timeout
	check(main._shop_exchange_ids[0].is_empty(), "长按拖回收藏清空原槽")
	show_page_for(materials[0])
	await process_frame
	var returned_slot: Control = main._find_collection_slot_for_owned_card(materials[0])
	await click((returned_slot.get_child(0) as CardView).get_global_rect().get_center())
	await click(main._shop_exchange_slots[0].get_global_rect().get_center())
	check(main._shop_exchange_slots[0]._card_view != null, "真实单击把卡牌放回槽内")
	var original_count: int = main.owned_card_collection.size()
	var original_rng: int = main.ordinary_shop_service.rng.state
	var save_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-missing-animation-parent/run.json"
	main._execute_shop_exchange()
	check(main._shop_exchange_animation == null and main.owned_card_collection.size() == original_count and main.ordinary_shop_service.rng.state == original_rng and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view != null), "保存失败保留材料与随机状态，不播放动画")
	main.run_save_path = save_path
	var book: Control = main.get_node("%BookPanel")
	var book_rest := book.position
	await click(main._shop_exchange_confirm.get_global_rect().get_center())
	var animation: Control = main._shop_exchange_animation
	check(animation != null and animation.stage == &"arrange" and animation._materials.size() == 3, "真实确认启动三张材料放大并居中并排")
	var awarded: OwnedCard = main.owned_card_collection.get_cards().back()
	var after_count: int = main.owned_card_collection.size()
	var after_rng: int = main.ordinary_shop_service.rng.state
	check(after_count == original_count - 2 and materials.all(func(card: OwnedCard): return main.owned_card_collection.get_by_instance_id(card.instance_id) == null) and awarded.card_data.rarity == CardData.Rarity.II, "演出开始前已完成材料消耗与新卡入库")
	check(FileAccess.file_exists(save_path) and main.run_reward_state.gold == 200, "演出开始前保存成功且置换仍免费")
	var distant_start: Vector2 = animation._materials[0].position
	var arranged_left: Vector2 = animation.size * 0.5 - Vector2(animation.CARD_SIZE.x * 2.0 + animation.MATERIAL_GAP, 0)
	await create_timer(0.15).timeout
	check(animation._materials[0].position.distance_to(arranged_left) < distant_start.distance_to(arranged_left), "材料实际从原槽移动至中央并排位置")
	main._execute_shop_exchange()
	check(main.owned_card_collection.size() == after_count and main.ordinary_shop_service.rng.state == after_rng, "演出中重复确认不生成卡牌或抽随机数")
	await wait_stage(animation, &"arranged")
	var center: Vector2 = animation.size * 0.5
	check(animation._materials.all(func(view: Control): return view.scale.is_equal_approx(Vector2.ONE * 2.0) and is_zero_approx(view.rotation) and is_equal_approx(view.position.y, center.y)) and animation._materials[1].position.is_equal_approx(center) and animation._materials[0].position.is_equal_approx(arranged_left) and is_equal_approx(animation._materials[2].position.x - center.x, center.x - arranged_left.x), "三张材料按原图2倍对称并排，中间卡位于屏幕中心")
	check(is_equal_approx(center.x - animation.CARD_SIZE.x - (animation._materials[0].position.x + animation.CARD_SIZE.x), 80.0) and animation._materials.all(func(view: Control): return is_zero_approx(white_amount(view))), "并排卡边缘间距从32扩大至80逻辑像素，材料仍保持原色")
	await capture("animation-arranged")
	await wait_stage(animation, &"pullback")
	await create_timer(0.05).timeout
	check(animation._materials.all(func(view: Control): return is_zero_approx(white_amount(view))) and animation._reward.modulate.a == 0.0 and animation.find_child("ExchangeFlash", true, false) == null, "回撤蓄力保持原色，不提前变白、显示新卡或绘制大片白光")
	check(animation._materials[0].position.x < arranged_left.x and animation._materials[2].position.x > 2.0 * center.x - arranged_left.x and animation._materials[1].position.is_equal_approx(center), "两侧卡保持原色向外回撤，中间卡保持固定")
	await capture("animation-pullback")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	check(not main._escape_pause_menu.is_menu_open(), "演出中Esc不穿透进入暂停菜单")
	await wait_stage(animation, &"collide")
	check(absf(arranged_left.x - animation._materials[0].position.x - 24.0) < 0.2 and absf(animation._materials[2].position.x - (2.0 * center.x - arranged_left.x) - 24.0) < 0.2, "两侧卡各回撤原图12像素，即2倍显示24逻辑像素，从回撤终点开始撞击")
	var collide_start: float = animation._materials[0].position.distance_to(center)
	await create_timer(0.08).timeout
	var first_distance: float = animation._materials[0].position.distance_to(center)
	await create_timer(0.08).timeout
	var second_distance: float = animation._materials[0].position.distance_to(center)
	check(first_distance < collide_start and first_distance - second_distance > collide_start - first_distance and animation._materials[1].position.is_equal_approx(center) and is_equal_approx(animation._materials[2].position.distance_to(center), second_distance), "两侧卡对称地从慢到快撞向中间卡，中间卡固定")
	check(animation._materials.all(func(view: Control): return is_zero_approx(white_amount(view))), "参照GIF，前冲前半程保留材料原色")
	await create_timer(0.10).timeout
	check(animation._materials.all(func(view: Control): return is_equal_approx(white_amount(view), 1.0) and view.scale.is_equal_approx(Vector2.ONE * 2.0)), "撞击期间材料保持2倍纯白剪影")
	await capture("animation-collide")
	await wait_stage(animation, &"fuse")
	check(animation._materials.all(func(view: Control): return view.position.is_equal_approx(center)) and animation._reward.modulate.a == 0.0, "三张白色剪影在原中间卡位置完全重合融合")
	await capture("animation-fuse")
	await wait_stage(animation, &"reveal")
	check(white_amount(animation._reward) > 0.8 and animation._sparks._progress < 0.2, "融合结果仍为白色剪影时十字闪点已立即出现，参照GIF重合时序")
	await create_timer(0.04).timeout
	check(animation._reward.scale.x > 2 and animation._reward.scale.x < 4 and animation._reward.modulate.a == 1.0 and white_amount(animation._reward) > 0.0 and white_amount(animation._reward) < 1.0 and animation._materials.all(func(view: Control): return not view.visible), "材料退场，新卡从白色恢复原色并由2倍放大至4倍")
	check(animation._sparks.is_visible_in_tree() and animation._sparks.z_index > animation._reward.z_index and animation._sparks._progress > 0.0 and animation._sparks._progress < 1.0, "融合揭晓时十字闪点在卡面上方绘制并向外消散")
	await capture("animation-reveal")
	await create_timer(0.08).timeout
	check(is_zero_approx(white_amount(animation._reward)) and animation._sparks._progress < 1.0, "参照GIF约100毫秒内恢复新卡原色，闪点继续飘散")
	await wait_stage(animation, &"display")
	check(animation._reward.scale.is_equal_approx(Vector2.ONE * 4) and is_zero_approx(white_amount(animation._reward)) and animation._materials.all(func(view: Control): return not view.visible), "新卡最终按原色4倍展示，材料已退场")
	check(is_equal_approx(animation._sparks._progress, 1.0), "新卡揭晓完成后十字闪点消散，不残留在飞入阶段")
	check(awarded.is_new and main.ordinary_shop_service.rng.state == after_rng, "只读演出不消除新卡绿点或再抽随机数")
	await capture("animation-display")
	await wait_stage(animation, &"fly")
	await create_timer(0.25).timeout
	check(animation._reward.scale.x < 4 and animation._reward.position.y > animation.size.y * 0.5 and animation._reward.modulate.a < 1, "新卡缩小、向下飞入收藏并淡出")
	await capture("animation-fly")
	await wait_stage(animation, &"shake")
	await create_timer(0.025).timeout
	check(not book.position.is_equal_approx(book_rest) and is_zero_approx(animation._reward.modulate.a), "卡牌消失后收藏书本整体抖动")
	await animation.finished
	await process_frame
	check(main._shop_exchange_animation == null and not is_instance_valid(animation) and book.position.is_equal_approx(book_rest), "结束后释放快照及动画并恢复书本位置")
	check(main.owned_card_collection.size() == after_count and main.ordinary_shop_service.rng.state == after_rng and main._shop_exchange_slots.all(func(slot: Control): return slot._card_view == null), "完整动画不再修改收藏或槽位数据")
	check(main.load_run_from_path(save_path) and main.owned_card_collection.get_by_instance_id(awarded.instance_id) != null and main.ordinary_shop_service.rng.state == after_rng, "演出后的存档读回保持同一结果，不重复置换")
	# 新一轮从普通速度开始，通过真实左键连续点击加速整条演出。
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._open_shop_exchange()
	materials = add_materials(CardData.Rarity.I)
	select_materials(materials)
	main._execute_shop_exchange()
	animation = main._shop_exchange_animation
	var accelerated_count: int = main.owned_card_collection.size()
	var accelerated_rng: int = main.ordinary_shop_service.rng.state
	var accelerated_start := Time.get_ticks_msec()
	await click(Vector2(70, 680))
	check(is_equal_approx(animation._click_speed.speed, 1.0), "单次点击不会立即加速，需连续点击")
	await click(Vector2(70, 680), MOUSE_BUTTON_RIGHT)
	check(is_equal_approx(animation._click_speed.speed, 1.0), "右键不会改变播放速度或取消已提交置换")
	await click(Vector2(70, 680))
	check(is_equal_approx(animation._click_speed.speed, 2.5), "连续左键使用纹章相同逻辑，将播放速度提至2.5倍")
	var elapsed_before: float = animation._tween.get_total_elapsed_time()
	var observed_start := Time.get_ticks_usec()
	await create_timer(0.05).timeout
	var observed_rate: float = (animation._tween.get_total_elapsed_time() - elapsed_before) / (float(Time.get_ticks_usec() - observed_start) / 1000000.0)
	check(observed_rate > 1.6 and observed_rate < 3.4, "实际Tween时间以约2.5倍推进，验证动画本身已经加速")
	for index: int in 4:
		await click(Vector2(70, 680))
	check(is_equal_approx(animation._click_speed.speed, 8.0), "持续连点加速至8倍上限")
	await animation.finished
	await process_frame
	check(Time.get_ticks_msec() - accelerated_start < 1500, "连点后整场演出在1.5秒内完成，短于原约2.69秒")
	check(main._shop_exchange_animation == null and book.position.is_equal_approx(book_rest) and main.owned_card_collection.size() == accelerated_count and main.ordinary_shop_service.rng.state == accelerated_rng, "加速演出完整归位并恢复书本，不重复置换或抽取随机数")
	# 程序化关闭/还原需收尾临时视觉；已提交的结果保留。
	main.ordinary_shop_open = true
	main.ordinary_shop_panel.visible = true
	main._open_shop_exchange()
	materials = add_materials(CardData.Rarity.I)
	select_materials(materials)
	main._execute_shop_exchange()
	check(main._shop_exchange_animation != null, "下一次置换可再次播放")
	check(is_equal_approx(main._shop_exchange_animation._click_speed.speed, 1.0), "新置换独立创建速度状态，从1倍开始")
	var committed_count: int = main.owned_card_collection.size()
	main._close_shop_card_services()
	await process_frame
	check(main._shop_exchange_animation == null and book.position.is_equal_approx(book_rest) and main.owned_card_collection.size() == committed_count, "关闭界面清理演出，保持已提交结果")
	# 战场来源仍保留信号绑定，原小队必须停止驱动服务槽里的原卡面。
	main._open_shop_exchange()
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var knight: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/heavy_knight.tres"))
	main.front_row.add_squad(SquadData.from_owned_card(knight), 0)
	var board_slot: BoardSlot = main.front_row.get_squads()[0]
	var board_card := board_slot.get_primary_card_view()
	board_slot._on_card_mouse_entered(board_card.card_data)
	main._select_exchange_card({"kind": &"card", "owned_card": knight}, 0)
	await motion(board_card.get_global_rect().get_center())
	await create_timer(0.3).timeout
	check(main._shop_exchange_slots[0]._card_view == board_card and is_zero_approx(board_card._external_lift) and not board_card._interaction_shadow.visible, "战场来源原卡在槽内悬停时不受旧小队抽出/阴影逻辑影响")
	await click(board_card.get_global_rect().get_center())
	await motion(destination)
	check(main._click_carry_data.get("source_type") == &"card_service" and main._click_carry_preview.global_position.distance_to(destination) <= 2.0, "战场来源原卡也可单击跟随鼠标")
	await button(destination, true, MOUSE_BUTTON_RIGHT)
	await button(destination, false, MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	main._close_shop_card_services()
	check(board_card.get_parent() == board_slot.card_visual_layer and not board_card.has_meta("card_service_slot"), "归还战场来源卡恢复原节点与原小队绑定")
	await capture("animation-finished")
	shell.queue_free()
	await process_frame
	print("置换交互与动画：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
