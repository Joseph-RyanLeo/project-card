extends "res://tests/service_interaction_revision_20261020_test.gd"

## 真实工具箱、原生拖拽、点击携带、金币与磁盘存档验证纹章出售。
const SALE_SAVE := "/private/tmp/project-card-sticker-sale-20261025.json"
var stock: Array[Dictionary] = []
var action: Button
var slot: Control

func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("纹章出售专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SALE_SAVE
	root.add_child(shell)
	root.size = Vector2i(2560, 1440)
	await create_timer(0.5).timeout
	main.run_reward_state.gold = 1000
	main.emblem_library.restore_inventory_state([])
	var names: Array[String] = ["火把", "宝石", "天选之子", "盾牌Ⅱ", "水贴纸", "万能贴纸"]
	for index: int in names.size():
		stock.append({"instance_id": "sale_%d" % index, "emblem_id": names[index], "kind": "emblem", "element_sticker": index >= 4})
	stock.append({"instance_id": "sale_wound", "wound_id": "中毒Ⅰ", "kind": "wound", "element_sticker": false})
	check(main.emblem_library.receive_stickers(stock), "建立真实普通纹章、元素贴纸与伤势库存")
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main._open_shop_card_services()
	await create_timer(0.5).timeout
	action = main._shop_board_view._service_action
	slot = main._shop_service_slot
	var before: Image = await frame()
	var original: Vector2 = slot.global_position
	await _click(main.emblem_library)
	await create_timer(0.4).timeout
	check(main._shop_sticker_sale_available(), "真实点击单独打开工具箱后可出售纹章")
	check(main._shop_board_view._sale_root.get_parent() == main._toolbox_overlay and slot.global_position == original, "出售区域提到工具箱层并保留原屏幕位置")
	var opened: Image = await frame()
	check(opened.get_pixel(1040, 65).is_equal_approx(before.get_pixel(1040, 65)), "工具箱遮罩不压暗右侧出售区域")
	check(opened.get_pixel(1150, 350).r < before.get_pixel(1150, 350).r * 0.9, "其余背景仍正常压暗")
	check(can_accept(&"sale_0"), "出售槽接受库存真实纹章")
	check(not can_accept(&"sale_wound"), "伤势不能卖入纹章槽")
	check(main.ordinary_shop_service.sticker_sale_price({"rarity": CardData.Rarity.IV}) == -1, "未给出售价的IV级不擅自定价")
	await verify_snap_and_return()
	var prices: Array[int] = [1, 3, 6, 4, 3, 6]
	for index: int in names.size():
		var id := StringName("sale_%d" % index)
		var state: Dictionary = main.emblem_library.get_inventory_item(id)
		var gold: int = main.run_reward_state.gold
		var rng: int = main.ordinary_shop_service.rng.state
		await place(id, index % 2 == 0)
		check(main._shop_service_sticker_id == id and main._shop_service_card_id == &"" and main._shop_board_view._sale_sticker.visible, names[index] + "真实放入待售槽")
		check(main.run_reward_state.gold == gold and main.emblem_library.get_inventory_item(id) == state, "入槽不提前消耗纹章或增加金币")
		check(not entry(id).drag_enabled and is_equal_approx(entry(id).modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "库存原位保留不可重复抓取的虚影")
		check(action.text == "出售" and not action.disabled and main._shop_board_view._amount.text == "+%d" % prices[index], names[index] + "售价正确")
		if index == 4:
			await create_timer(0.4).timeout
			await capture("sticker-sale-water")
		await _click(action)
		check(main.emblem_library.get_inventory_item(id).is_empty() and main.run_reward_state.gold == gold + prices[index], "确认出售仅移除这一实例并增加对应金币")
		check(action.text == "撤销" and main._shop_board_view._amount.text == "-%d" % prices[index], "出售后复用单笔撤销及金币显示")
		check(main.ordinary_shop_service.rng.state == rng and main._shop_sticker_sale_available(), "交易不消耗报价随机数，工具箱保持打开")
		await _click(action)
		check(main.emblem_library.get_inventory_item(id) == state and main.run_reward_state.gold == gold, "撤销返还同一纹章实例及原格位，扣回本笔金币")
		main._clear_shop_service_sticker()
		main._refresh_shop_card_services()
	await verify_failures()
	await verify_close_and_reload()
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(SALE_SAVE)
	print("商店工具箱纹章出售：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func entry(id: StringName) -> Control:
	for item: Control in main.emblem_library._entries:
		if StringName(String(item.definition.returned_state.instance_id)) == id: return item
	return null

func frame() -> Image:
	await RenderingServer.frame_post_draw
	return shell.internal_viewport.get_texture().get_image()

func can_accept(id: StringName) -> bool:
	var data: Dictionary = entry(id)._build_drag_data(Vector2(7, 7), false)
	var accepted: bool = slot._can_drop_data(Vector2.ZERO, data)
	data.drag_visual.free()
	return accepted

func place(id: StringName, native: bool) -> void:
	var source := entry(id)
	var point: Vector2 = source._icon.get_global_rect().get_center()
	var target := slot.get_global_rect().get_center()
	await _motion(point)
	await _mouse(point, true)
	if native:
		await _motion(point + Vector2(38, 4), true)
		check(shell.internal_viewport.gui_is_dragging(), "纹章启动真实原生拖拽")
		await _motion(target, true)
		await _mouse(target, false)
	else:
		await _mouse(point, false)
		check(not main._click_carry_data.is_empty(), "纹章启动真实点击携带")
		await _motion(target)
		await _mouse(target, true)
		await _mouse(target, false)
	await process_frame

func verify_snap_and_return() -> void:
	var inventory: Array = main.emblem_library.get_inventory_state()
	var gold: int = main.run_reward_state.gold
	for native: bool in [true, false]:
		for id: StringName in [&"sale_0", &"sale_4"]:
			var source := entry(id)
			var start: Vector2 = source._icon.get_global_rect().get_center() + Vector2(8, -8)
			var release := slot.get_global_rect().get_center() + Vector2(42, 35)
			await _motion(start)
			await _mouse(start, true)
			if native:
				await _motion(start + Vector2(38, 4), true)
			else:
				await _mouse(start, false)
			check(source.visible and source._icon.visible and is_equal_approx(source.modulate.a * source._icon.self_modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "刚抓起时工具箱原位立即显示同透明度虚影")
			check(source.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.emblem_library.get_inventory_state() == inventory, "携带中的虚影不接收鼠标，库存格位保持不变")
			await _motion(release, native)
			if not native: await _mouse(release, true)
			await _mouse(release, false)
			check(main._shop_service_sticker_id == id, "偏离槽中心松手仍接受纹章")
			check(source.visible and source._icon.visible and is_equal_approx(source.modulate.a * source._icon.self_modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA), "放入出售槽后延续同一原位虚影，没有透明度突变")
			var sale: Control = main._shop_board_view._sale_sticker
			await verify_foreground_flight(sale)
			check(sale._icon.get_global_rect().get_center().distance_to(slot.get_global_rect().get_center()) < 0.5, "非中心抓取后纹章自动吸附出售槽中央")
			check(sale.drag_enabled and sale.mouse_filter == Control.MOUSE_FILTER_STOP, "槽内纹章有真实拖拽交互")
			var origin: Vector2 = entry(id)._icon.get_global_rect().get_center()
			var point: Vector2 = sale._icon.get_global_rect().get_center()
			await _motion(point)
			await _mouse(point, true)
			if native:
				await _motion(point + Vector2(38, 4), true)
				check(shell.internal_viewport.gui_is_dragging(), "槽内纹章可启动原生拖拽")
			else:
				await _mouse(point, false)
				check(not main._click_carry_data.is_empty(), "槽内纹章可启动点击携带")
			check(not sale.visible, "抓起槽内纹章后出售槽不保留第二个图案")
			await _motion(origin, native)
			if not native: await _mouse(origin, true)
			await _mouse(origin, false)
			await verify_foreground_flight(entry(id))
			check(main._shop_service_sticker_id == &"" and not sale.visible and entry(id).drag_enabled and entry(id).modulate.a == 1.0, "拖回工具箱释放待售状态并恢复原位交互")
			check(main.emblem_library.get_inventory_state() == inventory and main.run_reward_state.gold == gold, "往返吸附不改变实例、格位或金币")
			await place(id, native)
			await create_timer(0.4).timeout
			point = sale._icon.get_global_rect().get_center()
			var invalid := Vector2(1070, 190)
			await _motion(point)
			await _mouse(point, true)
			if native:
				await _motion(point + Vector2(38, 4), true)
			else:
				await _mouse(point, false)
			await _motion(invalid, native)
			if not native: await _mouse(invalid, true)
			await _mouse(invalid, false)
			await verify_foreground_flight(entry(id))
			check(main._shop_service_sticker_id == &"" and not sale.visible and entry(id).drag_enabled, "槽内纹章在非法位置松手归还工具箱虚影位置")
			check(entry(id)._icon.get_global_rect().get_center().distance_to(origin) < 0.5 and main.emblem_library.get_inventory_state() == inventory, "非法放置归位动画结束后保持原格和实例")
	await place(&"sale_4", true)
	await create_timer(0.4).timeout
	await place(&"sale_0", true)
	await create_timer(0.4).timeout
	check(main._shop_service_sticker_id == &"sale_0" and entry(&"sale_4").drag_enabled and entry(&"sale_4").modulate.a == 1.0, "已占用出售槽的纹章也将新拖拽转发给槽位，替换后释放旧虚影")
	await _click(main._shop_board_view._sale_sticker)
	await _motion(Vector2(1180, 500))
	var cancel := InputEventMouseButton.new()
	cancel.position = shell.render_container.get_global_transform_with_canvas() * Vector2(1180, 500)
	cancel.global_position = cancel.position
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	root.push_input(cancel, true)
	await create_timer(0.4).timeout
	check(main._click_carry_data.is_empty() and main._shop_service_sticker_id == &"" and entry(&"sale_0").drag_enabled, "右键取消槽内纹章携带也归还工具箱")
	await place(&"sale_0", false)
	await create_timer(0.4).timeout
	await _click(main._shop_board_view._sale_sticker)
	var grid: Control = main.emblem_library._grid
	var free_cell: Vector2 = grid.get_global_transform_with_canvas() * (grid.GRID_ORIGIN + Vector2(2, 6) * grid.CELL_STEP + Vector2(7, 7))
	await _motion(free_cell)
	await _mouse(free_cell, true)
	await _mouse(free_cell, false)
	await create_timer(0.4).timeout
	var moved: Dictionary = main.emblem_library.get_inventory_item(&"sale_0")
	check(main._shop_service_sticker_id == &"" and moved.grid_x == 2 and moved.grid_y == 6 and entry(&"sale_0").drag_enabled, "出售槽纹章也能拖回工具箱其他合法空格")
	var original: Dictionary = inventory[0]
	check(main.emblem_library.move_sticker(&"sale_0", Vector2i(original.grid_x, original.grid_y)), "恢复回归测试纹章原格位")
	check(main.emblem_library.get_inventory_state() == inventory and main.run_reward_state.gold == gold, "替换、取消和移动格位均不消耗库存或金币")

func verify_foreground_flight(item: Control) -> void:
	var visual: Polygon2D = item._return_visual
	check(is_instance_valid(visual), "松手后有独立前景贴纸飞行动画")
	if not is_instance_valid(visual): return
	check(visual.get_parent() == shell.internal_viewport and visual.z_index > effective_z(main._shop_board_view._sale_root) and item._icon.visible == item.keep_carry_ghost, "前景动画高于出售框，工具箱保留原位虚影，出售槽不留第二处图案")
	if item.keep_carry_ghost:
		check(is_equal_approx(item._icon.self_modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA) and item.mouse_filter == Control.MOUSE_FILTER_IGNORE, "归位动画开始时原位虚影持续显示且不可交互")
	# 手动推进真实Tween一小步，避免截图耗时／窗口帧率掩盖细粒度位移。
	item._return_tween.pause()
	var before: Vector2 = visual.polygon[0]
	var target: Vector2 = item._icon.get_global_transform_with_canvas().origin
	var travel := before.distance_to(target)
	item._return_tween.custom_step(0.0001)
	var fine_step := before.distance_to(visual.polygon[0])
	check((fine_step > 0.00001 and fine_step < 4.0) if travel > 0.01 else fine_step < 0.01, "非零路程连续插值，小步不受4倍像素限制；原位松手不漂移")
	item._return_tween.play()
	var texture: Image = visual.texture.get_image()
	var texel := Vector2i(texture.get_size() / 2)
	# 选取中心附近的实际不透明纹理像素，用渲染结果核对途中没有被框或其他贴纸覆盖。
	var nearest := INF
	for y: int in texture.get_height():
		for x: int in texture.get_width():
			if texture.get_pixel(x, y).a < 0.99: continue
			var distance := Vector2(x, y).distance_squared_to(Vector2(texture.get_size()) * 0.5)
			if distance < nearest:
				nearest = distance
				texel = Vector2i(x, y)
	var expected := texture.get_pixelv(texel)
	var unobscured := true
	var ghost_persisted := true
	var frames := 0
	while is_instance_valid(item._return_visual):
		var rendered: Image = await frame()
		if not is_instance_valid(item._return_visual): break
		var polygon: PackedVector2Array = visual.polygon
		if item.keep_carry_ghost:
			ghost_persisted = ghost_persisted and item._icon.visible and is_equal_approx(item._icon.self_modulate.a, CardView.COLLECTION_DRAG_GHOST_ALPHA)
		var uv := (Vector2(texel) + Vector2(0.5, 0.5)) / Vector2(texture.get_size())
		var point := polygon[0] + (polygon[1] - polygon[0]) * uv.x + (polygon[3] - polygon[0]) * uv.y
		if Rect2(Vector2.ZERO, Vector2(rendered.get_size())).has_point(point):
			var actual := rendered.get_pixelv(Vector2i(point))
			unobscured = unobscured and absf(actual.r - expected.r) < 0.03 and absf(actual.g - expected.g) < 0.03 and absf(actual.b - expected.b) < 0.03
		frames += 1
	check(unobscured and frames > 1, "逐帧截图中飞行贴纸的不透明像素始终位于出售框与其他贴纸上方")
	check(ghost_persisted, "归位途中每帧都保留原位虚影")
	await process_frame
	check(not is_instance_valid(item._return_visual) and item._icon.visible and item._icon.self_modulate.a == 1.0, "贴纸落回后才删除前景图案并恢复原位正常显示")

func verify_failures() -> void:
	var inventory: Array = main.emblem_library.get_inventory_state()
	var gold: int = main.run_reward_state.gold
	await place(&"sale_0", true)
	main.run_save_path = "/private/tmp/project-card-no-sticker-sale-directory/run.json"
	await _click(action)
	check(main.emblem_library.get_inventory_state() == inventory and main.run_reward_state.gold == gold and main._shop_service_sticker_id == &"sale_0", "出售写盘失败完整恢复库存／金币并保留重试入口")
	main.run_save_path = SALE_SAVE
	await _click(action)
	check(main.run_reward_state.gold == gold + 1 and main.emblem_library.get_inventory_item(&"sale_0").is_empty(), "修正存档路径后可以重试且仅成交一次")
	main.run_save_path = "/private/tmp/project-card-no-sticker-sale-directory/run.json"
	await _click(action)
	check(main.run_reward_state.gold == gold + 1 and main.emblem_library.get_inventory_item(&"sale_0").is_empty() and action.text == "撤销", "撤销写盘失败保留原成交和撤销机会")
	main.run_save_path = SALE_SAVE
	await _click(action)
	check(main.emblem_library.get_inventory_item(&"sale_0").instance_id == "sale_0" and main.run_reward_state.gold == gold, "撤销失败后重试仍恢复同一实例")

func verify_close_and_reload() -> void:
	var inventory: Array = main.emblem_library.get_inventory_state()
	var gold: int = main.run_reward_state.gold
	await _click(main._shop_board_view._sale_sticker)
	check(not main._click_carry_data.is_empty() and not is_instance_valid(main._shop_board_view._sale_sticker._return_visual), "重新拿起贴纸会清理旧吸附动画")
	await _motion(Vector2(1070, 190))
	main._cancel_click_carry()
	check(is_instance_valid(entry(&"sale_0")._return_visual), "取消后启动返回工具箱的真实前景动画")
	await _click(main._toolbox_overlay.get_node("CloseToolbox"))
	check(not is_instance_valid(entry(&"sale_0")._return_visual) and shell.internal_viewport.find_children("StickerReturnFlight", "Polygon2D", false, false).is_empty(), "关闭工具箱立即清理仍在飞行的前景贴纸")
	await create_timer(0.4).timeout
	check(not is_instance_valid(main._toolbox_overlay) and main._shop_service_sticker_id == &"" and main.emblem_library.get_inventory_state() == inventory and main.run_reward_state.gold == gold, "关闭工具箱取消待售预览，不丢纹章不改金币")
	check(main._shop_board_view._sale_root.get_parent() == main._shop_card_service_panel and not main._shop_board_view._sale_background.visible, "关闭后出售区恢复原父节点与原亮度关系")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main._open_toolbox_inspection()
	await create_timer(0.4).timeout
	check(not main._shop_sticker_sale_available() and not can_accept(&"sale_0"), "上半视角独立工具箱不开放纹章出售")
	main._close_toolbox_inspection(false)
	main.set_world_view(main.WorldView.COLLECTION, false)
	main._open_toolbox_inspection()
	await create_timer(0.4).timeout
	await place(&"sale_1", true)
	await _click(action)
	main._close_toolbox_inspection(false)
	check(main.load_run_from_path(SALE_SAVE), "真实出售存档能够读回")
	check(main.emblem_library.get_inventory_item(&"sale_1").is_empty() and main.run_reward_state.gold == gold + 3, "读档保留出售结果，不重复发钱或返还已售纹章")
	check(main._shop_service_undo.is_empty() and main._shop_service_sticker_id == &"", "读档不恢复临时待售或撤销界面状态")
