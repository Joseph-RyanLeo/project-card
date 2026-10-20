extends "res://tests/d2_7_shop_presentation_test.gd"

const Inventory = preload("res://scripts/data/emblem_sticker_inventory.gd")
const Grid = preload("res://scripts/ui/emblem_library_grid.gd")

func move(point: Vector2) -> void:
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.move(point)

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("工具箱掉落验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-toolbox-overflow-save.json"
	var bag := main.emblem_library as EmblemLibraryView
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await process_frame
	check(main.find_child("ToolboxLauncher", true, false) == null, "普通上半战场不创建工具箱缩略入口")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await process_frame
	var original_position := bag.position
	var original_scale := bag.scale
	await click(bag.get_global_rect().get_center())
	check(is_instance_valid(main._toolbox_overlay), "收藏页可直接点击原工具箱独立展开")
	var opening := main._toolbox_tween as Tween
	check(is_instance_valid(opening) and bag.scale != Vector2(4, 4) and not bag._drag_enabled, "点击后从原倍率开始平滑展开，移动期间不启用贴纸拖拽")
	if is_instance_valid(opening):
		opening.pause()
		opening.custom_step(main.TOOLBOX_OPEN_SECONDS * 0.40)
		check(bag.scale.x > original_scale.x and bag.scale.x < 4.0 and bag.position != main.TOOLBOX_OPEN_POSITION, "真实Tween中途同时具有过渡位置与过渡缩放")
		await capture("toolbox-opening-middle")
	var expanded_scale := bag.scale
	await click(main._toolbox_overlay.get_node("CloseToolbox").get_global_rect().get_center())
	var closing := main._toolbox_tween as Tween
	check(is_instance_valid(closing) and main._toolbox_closing and is_instance_valid(main._toolbox_overlay) and not bag._drag_enabled, "收起按钮启动返回动画，不立即重挂或启用贴纸交互")
	if is_instance_valid(closing):
		closing.pause()
		closing.custom_step(main.TOOLBOX_OPEN_SECONDS * 0.40)
		check(bag.scale.x > original_scale.x and bag.scale.x < expanded_scale.x and bag.get_parent() == main._toolbox_overlay, "收起中途平滑缩小，工具箱仍留在演出层")
		await capture("toolbox-closing-middle")
		await key(KEY_ESCAPE)
		check(main._toolbox_tween == closing, "收起中再次按Esc不会重启动画")
		closing.custom_step(main.TOOLBOX_OPEN_SECONDS)
	await process_frame
	check(bag.position == original_position and bag.scale == original_scale and not is_instance_valid(main._toolbox_tween) and not is_instance_valid(main._toolbox_overlay), "收起动画结束后准确恢复原父节点、位置和倍率")
	await click(bag.get_global_rect().get_center())
	main._close_toolbox_inspection()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await create_timer(main.TOOLBOX_OPEN_SECONDS + 0.05).timeout
	check(not is_instance_valid(main._toolbox_overlay) and bag.position == original_position and bag.scale == original_scale, "收起期间切换界面立即清理补间，不会留下迟到位移或重复工具箱")
	main.set_world_view(main.WorldView.COLLECTION, false)
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	check(main.find_child("ToolboxLauncher", true, false) == null, "商店不再保留工具箱缩略入口")
	var scattered := _layout(true)
	check(bag.restore_inventory_state(scattered), "建立14个零散空位、无2×2空区的真实工具箱")
	_set_offer()
	check(_tile(0).get_meta("purchase_enabled"), "购买资格不读取隐藏内容的占格结果")
	var before_rng: int = main.ordinary_shop_service.rng.state
	var ids: Array[StringName] = main._buy_shop_sticker_pack(0, main.ordinary_shop_service.offers[0])
	check(ids.size() == 5 and main.run_reward_state.gold == 985, "零散空位仍可购买并获得完整五枚贴纸")
	check(not bag.has_dropped_stickers() and bag.get_inventory_item(ids[0]).grid_x == 0 and bag.get_inventory_item(ids[0]).grid_y == 0, "收到元素后自动整理，元素优先，并全部放入格内")
	check(main.ordinary_shop_service.rng.state == before_rng, "整理不重新抽取商品内容或消耗玩法随机流")
	check(bag.get_inventory_state().size() == scattered.size() + 5, "自动整理保留全部原有实例")
	# 满箱购买不得再提前拦截。
	check(bag.restore_inventory_state(_layout(false)), "建立28格全满的工具箱")
	_set_offer()
	var count_before := bag.get_inventory_state().size()
	await click(_tile(0).get_global_rect().get_center())
	await create_timer(0.35).timeout
	check(main.run_reward_state.gold == 970 and bag.get_inventory_state().size() == count_before + 5 and is_instance_valid(main._sticker_pack_opening), "满箱真实点击仍购买成功并启动开包，不丢失五枚奖励")
	var drops := bag.get_inventory_state().filter(func(item: Dictionary): return Inventory.is_dropped(item))
	check(drops.size() == 5, "无法加入的五枚全部进入临时区域")
	var sequence = main._sticker_pack_opening
	sequence._auto_advance = true
	sequence._click_speed.speed = 8.0
	sequence.auto_peel()
	for frame: int in 500:
		if not is_instance_valid(main._sticker_pack_opening): break
		await process_frame
	check(not is_instance_valid(main._sticker_pack_opening) and bag.has_dropped_stickers(), "开包演出完整飞向临时区域，结束后仍保留待整理实例")
	main._toggle_ordinary_shop()
	check(is_instance_valid(main._temporary_discard_dialog), "没有商店入口时，离店提示仍可返回整理")
	main._temporary_discard_dialog.canceled.emit()
	check(bag.scale.x < 4.0, "返回整理时同一工具箱从原布局平滑展开")
	await create_timer(main.TOOLBOX_OPEN_SECONDS + 0.05).timeout
	check(is_instance_valid(main._toolbox_overlay) and bag._drag_enabled and bag.scale == Vector2(4, 4), "独立工具箱在左侧4倍展开并启用拖拽")
	await capture("toolbox-overflow")
	await _check_dropped_feedback(bag)
	# 原生拖拽：格内 -> 临时区，允许与已有掉落重叠。
	var source := _entry(&"full_0_0")
	var start := source.get_global_rect().get_center()
	var end := bag._grid.get_global_transform_with_canvas() * (Grid.DROP_AREA.position + Vector2(20, 20))
	await _drag(start, end)
	check(Inventory.is_dropped(bag.get_inventory_item(&"full_0_0")), "原生拖拽可把格内纹章放入已有贴纸的临时区域")
	# 点击携带：临时普通贴纸 -> 刚空出的格位。
	var ordinary: Dictionary = drops[1]
	var drop_entry := _entry(StringName(String(ordinary.instance_id)))
	var carry := drop_entry._build_drag_data(drop_entry.size * 0.5, false)
	main._on_click_carry_requested(carry, drop_entry.get_global_rect().get_center())
	var cell_center := bag._grid.get_global_transform_with_canvas() * (Grid.GRID_ORIGIN + Grid.CELL_SIZE * 0.5)
	main._commit_click_carry(cell_center)
	check(not Inventory.is_dropped(bag.get_inventory_item(StringName(String(ordinary.instance_id)))) and bag.get_inventory_item(StringName(String(ordinary.instance_id))).grid_x == 0, "临时贴纸可通过点击携带放回工具箱，身份不变")
	var snapshot := bag.get_inventory_state()
	check(main.save_run_to_path(main.run_save_path) == OK, "格位、掉落身份和自由位置能共同保存")
	main._close_toolbox_inspection()
	await create_timer(main.TOOLBOX_OPEN_SECONDS + 0.05).timeout
	check(bag.get_parent() == main._emblem_library_parent and not bag._drag_enabled, "收起工具箱恢复原父节点与布局")
	check(main.load_run_from_path(main.run_save_path), "包含临时区域的存档可恢复")
	check(JSON.stringify(bag.get_inventory_state()) == JSON.stringify(snapshot), "读档保留手动格位与临时区域位置，不自动重排")
	# 保存失败还原整理和掉落，不扣款或改变已确定内容。
	_set_offer()
	var before := bag.get_inventory_state()
	var gold: int = main.run_reward_state.gold
	var instance_sequence: int = main._next_developer_emblem_instance
	main.run_save_path = "/private/tmp/project-card-missing-toolbox-directory/state.json"
	var failed: Array[StringName] = main._buy_shop_sticker_pack(0, main.ordinary_shop_service.offers[0])
	check(failed.is_empty() and bag.get_inventory_state() == before and main.run_reward_state.gold == gold and main._next_developer_emblem_instance == instance_sequence and not main.ordinary_shop_service.offers[0].get("sold", false), "保存失败回滚全部格位、临时贴纸、金币和实例序号")
	main.run_save_path = "/private/tmp/project-card-toolbox-overflow-save.json"
	main.ordinary_shop_open = true
	main._toggle_ordinary_shop()
	check(main.ordinary_shop_open and is_instance_valid(main._temporary_discard_dialog) and main._temporary_discard_dialog.dialog_text == "临时区域仍有纹章，是否确认丢弃", "离店有掉落时先提示，保持商店与贴纸")
	main._temporary_discard_dialog.canceled.emit()
	await process_frame
	check(main.ordinary_shop_open and bag.has_dropped_stickers() and is_instance_valid(main._toolbox_overlay), "取消丢弃后保留贴纸，并展开工具箱供整理")
	main._toggle_ordinary_shop()
	main._temporary_discard_dialog.confirmed.emit()
	await create_timer(0.3).timeout
	check(not main.ordinary_shop_open and not bag.has_dropped_stickers() and main.run_reward_state.gold == gold, "确认离店只销毁临时区域，金币不返还，格内贴纸保留")
	# 真实迷宫事件奖励：满箱领取停留，继续时才确认，读档不会重领。
	var maze := ShortMazeController.new()
	main.add_child(maze)
	main.maze_controller = maze
	check(maze.initialize(main), "初始化真实迷宫流程验证事件与结算退出")
	maze.run.initialize(43)
	maze.run.round_index = 1
	maze.run.step = ShortMazeRunState.Step.EVENT
	for event: Dictionary in maze.content.free_events:
		if event.reward == "emblem": maze.run.selected_path = event.duplicate(true); break
	bag.restore_inventory_state(_layout(false))
	check(maze.complete_event() and maze.run.step == ShortMazeRunState.Step.EVENT and maze.run.selected_path.get("reward_claimed", false) and bag.has_dropped_stickers(), "事件满箱奖励先保留在当前事件，不立即退出销毁")
	check(main.find_child("ToolboxLauncher", true, false) == null, "事件界面不保留工具箱缩略入口")
	check(not maze.complete_event() and is_instance_valid(main._temporary_discard_dialog), "已领取事件继续时弹出临时贴纸丢弃确认")
	main._temporary_discard_dialog.confirmed.emit()
	await process_frame
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and not bag.has_dropped_stickers() and bag.get_inventory_state().size() == 28, "确认结束事件不重复发奖，只丢弃临时贴纸")
	# 结算退出共用相同确认。
	bag.receive_stickers([{"instance_id": "result_drop", "emblem_id": "火把"}])
	maze.hero.pending_talent_levels.clear()
	main._last_battle_settlement_result = {"success": true}
	main.current_phase = main.GamePhase.RESULT
	maze.run.round_index = 3
	maze.run.step = ShortMazeRunState.Step.BATTLE_ACTIVE
	maze.run.settle_battle(true)
	check(main.find_child("ToolboxLauncher", true, false) == null, "战斗结算不保留工具箱缩略入口")
	check(not maze.continue_after_battle() and is_instance_valid(main._temporary_discard_dialog), "退出战斗结算同样先提示临时区域")
	if is_instance_valid(main._temporary_discard_dialog): main._temporary_discard_dialog.canceled.emit()
	await process_frame
	check(main.current_phase == main.GamePhase.RESULT and bag.has_dropped_stickers(), "取消结算退出后仍在结算，贴纸可继续整理")
	check(not maze.continue_after_battle() and is_instance_valid(main._temporary_discard_dialog), "再次继续结算仍需确认，不会因取消而放行")
	main._temporary_discard_dialog.confirmed.emit()
	await process_frame
	check(main.current_phase == main.GamePhase.PREPARE and not bag.has_dropped_stickers() and maze.run.day == 2, "确认结算退出销毁临时贴纸并正常进入下一天")
	main._close_toolbox_inspection(false)
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("Toolbox overflow failures: ", failures)
	quit(1 if failures else 0)

func _set_offer() -> void:
	main.ordinary_shop_service.offers.clear()
	main.ordinary_shop_service.offers.append({"kind": "sticker_pack", "price": 15, "offer_id": "overflow_%d" % Time.get_ticks_usec(), "stickers": [{"id": "光贴纸", "target": "rune"}, {"id": "火把"}, {"id": "长剑"}, {"id": "面包"}, {"id": "火把"}]})
	main._refresh_ordinary_shop_panel()

func _layout(scattered: bool) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for y: int in 7:
		for x: int in 4:
			if scattered and (x + y) % 2 == 0: continue
			items.append({"instance_id": "full_%d_%d" % [x, y], "emblem_id": "火把", "grid_x": x, "grid_y": y})
	return items

func _entry(id: StringName) -> EmblemLibraryEntry:
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if StringName(String(entry.definition.returned_state.instance_id)) == id: return entry
	return null

func _check_dropped_feedback(bag: EmblemLibraryView) -> void:
	var original := bag.get_inventory_state()
	check(bag.restore_inventory_state([
		{"instance_id": "overlap_a", "emblem_id": "火把", "storage": "drop", "drop_position": [14, 10]},
		{"instance_id": "overlap_b", "emblem_id": "长剑", "storage": "drop", "drop_position": [21, 10]},
	]), "建立两枚部分重叠的真实临时贴纸")
	var grid_transform := bag._grid.get_global_transform_with_canvas()
	var drop_origin: Vector2 = Grid.DROP_AREA.position
	var first := _entry(&"overlap_a")
	var second := _entry(&"overlap_b")
	check(first.get_index() < second.get_index(), "初始重叠显示顺序可供真实鼠标检验")
	var exposed := grid_transform * (drop_origin + Vector2(17, 17))
	await move(exposed)
	await create_timer(EquipmentIndicator.HOVER_LIFT_DURATION + 0.05).timeout
	var rest := (first.size - first._icon.size) * 0.5
	check(is_equal_approx(rest.y - first._icon.position.y, first.DROP_HOVER_LIFT) and first.DROP_HOVER_LIFT == 1.0, "临时贴纸悬停只抬升一个原生像素")
	await click(exposed)
	check(main._click_carry_data.get("source_entry") == first and first.get_index() > second.get_index(), "点击下层贴纸露出的部分后，它立即移到叠放最上方")
	check(is_instance_valid(main._click_carry_preview) and main._click_carry_preview.get_parent() == main._click_carry_layer and main._click_carry_layer.z_index > main._toolbox_overlay.z_index, "点击携带的贴纸预览高于工具箱和全部临时贴纸")
	await key(KEY_ESCAPE)
	check(first.visible and main._click_carry_data.is_empty(), "取消携带后贴纸恢复显示并保留置顶顺序")
	var overlap := grid_transform * (drop_origin + Vector2(24, 17))
	await click(overlap)
	check(main._click_carry_data.get("source_entry") == first, "重叠处再次点击命中最近操作的贴纸")
	await key(KEY_ESCAPE)
	# 另一枚从右侧露出的部分拖动到交叠区，落下后仍应在最前面。
	await _drag(grid_transform * (drop_origin + Vector2(33, 17)), grid_transform * (drop_origin + Vector2(20, 18)), true)
	first = _entry(&"overlap_a")
	second = _entry(&"overlap_b")
	check(Inventory.is_dropped(bag.get_inventory_item(&"overlap_b")) and second.get_index() > first.get_index(), "原生拖拽放下并重建目录后，刚拖动的贴纸仍在最上层")
	bag.set_scraper_count(main.scraper_count)
	bag._refresh_entries()
	check(_entry(&"overlap_b").get_index() > _entry(&"overlap_a").get_index(), "普通界面刷新不会恢复成旧的获得顺序")
	await capture("toolbox-overlap-front")
	check(bag.restore_inventory_state(original), "交互验证结束恢复原库存与格位")


func _drag(from: Vector2, to: Vector2, verify_preview: bool = false) -> void:
	await move(from)
	var down := InputEventMouseButton.new()
	down.position = shell.render_container.get_global_transform_with_canvas() * from
	down.global_position = down.position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	for step: int in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = shell.render_container.get_global_transform_with_canvas() * from.lerp(to, float(step) / 8.0)
		motion.relative = shell.render_container.get_global_transform_with_canvas().basis_xform((to - from) / 8.0)
		motion.global_position = motion.position
		Input.warp_mouse(motion.position)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	if verify_preview:
		var data: Variant = main.get_viewport().gui_get_drag_data()
		var preview: Control = data.get("drag_visual") if data is Dictionary else null
		check(is_instance_valid(preview) and not preview.z_as_relative and preview.z_index == 4096, "原生拖拽时的贴纸预览独立绘制在全部临时贴纸上方")
	var up := InputEventMouseButton.new()
	up.position = shell.render_container.get_global_transform_with_canvas() * to
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	root.push_input(up, true)
	await process_frame
