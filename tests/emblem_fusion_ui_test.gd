extends SceneTree

var failures := 0
var shell: Control
var main: Control
var pointer := Vector2.ZERO
var transform := Transform2D.IDENTITY
var capture_enabled := false
var _recording := false
var _motion_frames: Array[Image] = []
var _motion_times: Array[int] = []
var _motion_stages: Array[String] = []
const DISCOVERY_PATH := "/private/tmp/project-card-emblem-fusion-ui-discovery.json"

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: print("PASS: " + message)
	else:
		failures += 1
		push_error(message)

func motion(point: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = transform * point
	event.global_position = event.position
	event.relative = (point - pointer) * transform.get_scale()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = point
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func button(pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = transform * pointer
	event.global_position = event.position
	event.button_index = index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)
	await process_frame

func click(point: Vector2) -> void:
	await motion(point)
	await button(true)
	await button(false)

func wait_stage(overlay: Control, expected: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(overlay) and overlay.stage != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(overlay) and overlay.stage == expected, "动画阶段：" + String(expected))

func wait_finished() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(main._emblem_fusion_overlay) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(main._emblem_fusion_overlay), "动画结束释放操作锁")

func entry_for(id: StringName) -> Control:
	for entry: Control in main.emblem_library._entries:
		if StringName(String(entry.definition.returned_state.instance_id)) == id:
			return entry
	return null

func capture(name: String) -> void:
	if not capture_enabled: return
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	if image != null:
		image.save_png("/private/tmp/project-card-emblem-fusion-" + name + ".png")

func _record_frame() -> void:
	if not _recording:
		return
	var frame: Image = shell.internal_viewport.get_texture().get_image()
	if frame == null:
		return
	_motion_frames.append(frame)
	_motion_times.append(Time.get_ticks_msec())
	var animation: Control = main._emblem_fusion_overlay
	_motion_stages.append(String(animation.stage) if is_instance_valid(animation) else "finished")

func _save_motion_preview() -> void:
	_recording = false
	var entries: Array[Dictionary] = []
	for index: int in _motion_frames.size():
		var path := "/private/tmp/project-card-fusion-motion-%03d.png" % index
		_motion_frames[index].save_png(path)
		entries.append({"path": path, "time_ms": _motion_times[index], "stage": _motion_stages[index]})
	var file := FileAccess.open("/private/tmp/project-card-fusion-motion.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(entries))
	file.close()
	_motion_frames.clear()

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("纹章合成专项测试超时"); quit(1))
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	DirAccess.remove_absolute(DISCOVERY_PATH)
	root.size = Vector2i(2560, 1440)
	shell = load("res://scenes/GameDisplay.tscn").instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-emblem-fusion-ui-run.json"
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.apply_display_mode(GameDisplay.DisplayMode.WINDOW_2K)
	await create_timer(0.25).timeout
	shell.internal_viewport.notify_mouse_entered()
	transform = shell.render_container.get_global_transform_with_canvas()
	check(transform.get_scale().is_equal_approx(Vector2(2, 2)), "2K窗口真实交互采用2倍显示壳")
	main._emblem_recipe_discovery.save_path = DISCOVERY_PATH
	main._emblem_recipe_discovery.discovered.clear()
	main._emblem_recipe_discovery.encountered.clear()
	main.emblem_library.restore_inventory_state([])
	main.emblem_library.return_sticker({"instance_id": &"sword", "emblem_id": &"长剑", "grid_x": 0, "grid_y": 0})
	main.emblem_library.return_sticker({"instance_id": &"torch", "emblem_id": &"火把", "grid_x": 1, "grid_y": 0})
	main.emblem_library.return_sticker({"instance_id": &"bread", "emblem_id": &"面包", "grid_x": 2, "grid_y": 0})
	var source_card: CardView
	for slot: Control in main._get_collection_card_slots():
		var owned: OwnedCard = slot.get_meta("owned_card", null)
		if owned != null and owned.card_data.card_type == CardData.CardType.MINION:
			source_card = slot.get_child(0)
			break
	var toolbox_normal_position: Vector2 = main.emblem_library.position
	main._open_card_inspection(source_card.card_data, source_card.get_owned_card(), source_card)
	await create_timer(0.35).timeout
	main._toggle_inspection_library()
	await create_timer(0.35).timeout
	var owned := source_card.get_owned_card()
	var slots: Array[Dictionary] = CardSlotLayout.get_slot_definitions(owned.card_data, owned).filter(func(slot: Dictionary): return int(slot.kind) == CardSlotLayout.Kind.EMBLEM)
	var left_slot: Dictionary = slots.filter(func(slot: Dictionary): return (slot.position as Vector2).x < 50)[0]
	var right_slot: Dictionary = slots.filter(func(slot: Dictionary): return (slot.position as Vector2).x > 50)[0]
	var target_index := int(left_slot.storage_index)
	owned.set_emblem_slot(target_index, {"instance_id": &"card_torch", "emblem_id": &"火把"})
	owned.set_emblem_slot(int(right_slot.storage_index), {"instance_id": &"card_apple", "emblem_id": &"苹果"})
	main._refresh_owned_card_status_visuals(owned)
	var before: Array = main.emblem_library.get_inventory_state()
	var slots_before := owned.emblem_slots.duplicate(true)
	var scraper_before: int = main.scraper_count
	var gold_before: int = main.run_reward_state.gold
	var drag_data: Dictionary = entry_for(&"sword")._build_drag_data(Vector2(7, 7), false)
	var grid: Control = main.emblem_library._grid
	var toolkit_point: Vector2 = entry_for(&"torch").get_global_rect().get_center()
	check(not grid._can_drop_data(grid.get_global_transform_with_canvas().affine_inverse() * toolkit_point, drag_data), "工具箱中的可配对纹章格仍拒绝合成")
	drag_data.drag_visual.free()
	await click(entry_for(&"sword").get_global_rect().get_center())
	check(not main._click_carry_data.is_empty() and main._inspection_surface._fusion_rects.size() == 1 and main._inspection_surface._fusion_rects[0] == main._get_emblem_slot_rect(target_index), "拖动时仅卡牌可合成纹章显示紫色呼吸光")
	await capture("card-highlight")
	await click(toolkit_point)
	check(main._emblem_fusion_overlay == null and main.emblem_library.get_inventory_state() == before, "真实点击工具箱另一材料不打开公式、不消耗材料")
	await click(entry_for(&"sword").get_global_rect().get_center())
	var target_local: Vector2 = left_slot.position + Vector2(7, 7)
	await click(main._inspection_surface.card_canvas_point(target_local))
	var overlay: Control = main._emblem_fusion_overlay
	check(overlay != null and main._click_carry_data.is_empty() and main.emblem_library.fusion_busy, "工具箱材料落到卡上纹章开启公式并锁住操作")
	if overlay == null: quit(1); return
	await wait_stage(overlay, &"awaiting")
	check(overlay._first_rest.is_equal_approx(overlay._first_origin) and overlay._second_rest.x > overlay._first_origin.x and overlay._result_rest.x > overlay._second_rest.x, "第一枚锚定卡上原位，第二枚与结果依次在右侧")
	var surface: Control = main._inspection_surface
	var projected: Vector2 = surface.card_canvas_point(target_local)
	var restored: Vector2 = surface.card_point(surface.get_global_transform_with_canvas().affine_inverse() * projected)
	check(restored.distance_to(target_local) < 0.001 and overlay._first_origin.distance_to(surface.card_canvas_rect(main._get_emblem_slot_rect(target_index)).get_center()) < 0.01, "倾斜卡面正逆投影一致，公式定位当前目标纹章")
	check(is_equal_approx(overlay._dim.modulate.a, 1.0 - overlay.FORMULA_BACKGROUND_BRIGHTNESS) and overlay._result_label.text == "？" and not overlay._result_icon.visible and owned.emblem_slots == slots_before, "公式预览按可调亮度压暗，首次配方仍显示问号")
	check((overlay._first.get_child(0).size * overlay._first.scale).is_equal_approx(Vector2(112, 112)) and (overlay._second.get_child(0).size * overlay._second.scale).is_equal_approx(Vector2(112, 112)) and overlay._result_icon.size == Vector2(112, 112), "公式三枚纹章均按4倍检视再2倍，完整尺寸112×112")
	var old_question_position: Vector2 = overlay._result_label.get_global_transform_with_canvas().origin
	var old_first: Vector2 = overlay._first.position
	var old_second: Vector2 = overlay._second.position
	await create_timer(0.15).timeout
	check(overlay._first.position.is_equal_approx(old_first) and not overlay._second.position.is_equal_approx(old_second), "卡上目标固定不动，只有手中材料呼吸浮动")
	check(overlay._result_label.get_global_transform_with_canvas().origin != old_question_position, "首次结果问号实际上下浮动")
	await capture("card-unknown")
	await click(overlay._cancel.position + overlay._cancel.size * 0.5)
	await wait_finished()
	check(main.emblem_library.get_inventory_state() == before and owned.emblem_slots == slots_before and not FileAccess.file_exists(DISCOVERY_PATH), "取消返还手中材料，卡上原纹章和进度不变")
	# 用真实原生拖放走同一卡牌入口。
	var sword_point := entry_for(&"sword").get_global_rect().get_center()
	await motion(sword_point)
	await button(true)
	await motion(sword_point + Vector2(32, 5), true)
	check(shell.internal_viewport.gui_is_dragging() and surface._fusion_rects.size() == 1, "原生长按拖动也提示卡上的合成目标")
	await motion(surface.card_canvas_point(target_local), true)
	await button(false)
	overlay = main._emblem_fusion_overlay
	check(overlay != null, "原生松手命中卡牌纹章开启合成")
	if overlay == null: quit(1); return
	await click(Vector2(100, 660))
	await click(Vector2(100, 660))
	check(overlay._click_speed.speed > 1.0, "共用连点逻辑加速公式浮现")
	await wait_stage(overlay, &"awaiting")
	check(overlay._result_label.text == "火焰剑" and overlay._result_icon.visible and owned.emblem_slots == slots_before, "再次遇见显示结果但仍等待确认")
	var old_result_icon_position: Vector2 = overlay._result_icon.get_global_transform_with_canvas().origin
	var old_result_name_position: Vector2 = overlay._result_label.get_global_transform_with_canvas().origin
	await create_timer(0.15).timeout
	var result_icon_delta: Vector2 = overlay._result_icon.get_global_transform_with_canvas().origin - old_result_icon_position
	var result_name_delta: Vector2 = overlay._result_label.get_global_transform_with_canvas().origin - old_result_name_position
	check(absf(result_icon_delta.y) > 0.001 and result_icon_delta.distance_to(result_name_delta) < 0.01, "已知结果纹章和名称共用上下浮动，图文不会分离")
	await capture("card-known")
	check(not main.start_battle(1, false), "公式期间拒绝开始战斗")
	if capture_enabled:
		RenderingServer.frame_post_draw.connect(_record_frame)
		_recording = true
	var incoming_before_confirm: Vector2 = overlay._second.position
	await click(overlay._confirm.position + overlay._confirm.size * 0.5)
	check(overlay.stage == &"charging" and main.emblem_library.get_inventory_state().size() == before.size() - 1, "确认只消耗工具箱手中材料")
	var fixed_target: Vector2 = overlay._first_rest
	var fixed_card: Vector2 = surface.position
	check(overlay._fusion_point.is_equal_approx(fixed_target) and overlay._fusion_point.distance_to(overlay._result_rest) > 40, "合成点固定在卡牌目标纹章原槽，取代材料正中间")
	var result: Dictionary = owned.emblem_slots[target_index]
	check(result.emblem_id == &"火焰剑" and result.instance_id != &"card_torch" and not result.has("grid_x") and main.emblem_library.get_inventory_item(&"torch").emblem_id == &"火把", "新纹章替换卡上原槽，工具箱另一纹章保持不变")
	check(main._inspection_card_view._fusion_hidden_emblem_slot == target_index, "贴回前隐藏卡上新纹章，避免双影")
	# 蓄力可能被连点加速缩至几帧，逐帧观察实际后退，不在固定延迟后才取样。
	var furthest_pullback_x: float = overlay._second.position.x
	while overlay.stage == &"charging":
		furthest_pullback_x = maxf(furthest_pullback_x, overlay._second.position.x)
		await process_frame
	furthest_pullback_x = maxf(furthest_pullback_x, overlay._second.position.x)
	check(overlay._dim.modulate.a > 1.0 - overlay.FORMULA_BACKGROUND_BRIGHTNESS and overlay.CONFIRM_BACKGROUND_BRIGHTNESS < overlay.FORMULA_BACKGROUND_BRIGHTNESS, "确认后按独立亮度参数继续逐渐变暗")
	overlay.confirm()
	check(main.emblem_library.get_inventory_state().size() == before.size() - 1 and main.scraper_count == scraper_before and main.run_reward_state.gold == gold_before, "重复确认无效且不消耗刮刀或金币")
	await wait_stage(overlay, &"attracting")
	var native_zoom: float = overlay.INSPECTION_ZOOM * overlay.FORMULA_ZOOM
	check(is_equal_approx(overlay.PULLBACK_PIXELS, 2.0) and absf(overlay._second_rest.x - incoming_before_confirm.x - 2.0 * native_zoom) < 0.1 and furthest_pullback_x > incoming_before_confirm.x + 1.8 * native_zoom, "手中材料实际先后退原图2像素，即8倍演出16逻辑像素，再开始撞击")
	var attract_start_distance: float = overlay._second.position.distance_to(fixed_target)
	await create_timer(0.025).timeout
	check(overlay._first.position.is_equal_approx(fixed_target) and surface.position.is_equal_approx(fixed_card) and overlay._second.position.distance_to(fixed_target) < attract_start_distance, "吸附期间目标纹章和卡牌固定，手中纹章实际飞向目标")
	check(is_equal_approx(float(overlay._first_white.get_shader_parameter("white_amount")), 1.0) and is_equal_approx(float(overlay._second_white.get_shader_parameter("white_amount")), 1.0), "吸附时两枚纹章均为白色剪影")
	await wait_stage(overlay, &"flash")
	check(overlay._first.position.distance_to(fixed_target) < 0.01 and overlay._second.position.distance_to(fixed_target) < 0.01 and overlay._sparks.position.distance_to(fixed_target) < 0.01, "白色剪影在固定目标原槽重合融合")
	await capture("card-white")
	await wait_stage(overlay, &"revealing")
	check(overlay._result_icon.visible and not overlay._first.visible and not overlay._second.visible, "材料融合为原槽的新纹章，并开始恢复原色")
	var max_recoil := 0.0
	var recoil_within_bounds := true
	var saw_rebound := false
	var previous_recoil := 0.0
	while overlay.stage == &"revealing":
		var recoil: Vector2 = fixed_target - overlay._result.position
		max_recoil = maxf(max_recoil, recoil.x)
		recoil_within_bounds = recoil_within_bounds and absf(recoil.y) < 0.01 and recoil.x >= -0.01 and recoil.x <= 2.0 * native_zoom + 0.01
		saw_rebound = saw_rebound or recoil.x < previous_recoil - 0.01
		previous_recoil = recoil.x
		await process_frame
	check(is_equal_approx(overlay.RESULT_RECOIL_PIXELS, 2.0) and recoil_within_bounds and max_recoil > 1.5 * native_zoom and saw_rebound and overlay._result.position.distance_to(fixed_target) < 0.01, "新纹章向左受撞击后回弹到原槽，原图2像素换算为最多16逻辑像素")
	await capture("card-reveal")
	await wait_stage(overlay, &"displaying")
	var revealed_result_start: Vector2 = overlay._result.position
	await create_timer(0.025).timeout
	check(overlay._result.position.is_equal_approx(revealed_result_start) and overlay._result.scale == Vector2.ONE and is_zero_approx(float(overlay._result_white.get_shader_parameter("white_amount"))), "恢复原色后的8倍结果保持目标位置，等待缩小落定")
	await click(Vector2(100, 660))
	await click(Vector2(100, 660))
	await wait_stage(overlay, &"shaking")
	check(not overlay._result.visible and main._inspection_card_view._fusion_hidden_emblem_slot == -1, "落定后先显示卡牌真实新纹章，再轻震整张卡牌")
	var saw_card_shake := false
	var shake_within_bounds := true
	while is_instance_valid(overlay) and overlay.stage == &"shaking":
		var shake_offset: Vector2 = surface.position - fixed_card
		saw_card_shake = saw_card_shake or shake_offset.length() > 0.01
		shake_within_bounds = shake_within_bounds and shake_offset.length() <= overlay.CARD_SHAKE_PIXELS + 0.01
		await process_frame
	check(saw_card_shake and shake_within_bounds, "新纹章落定后整张卡牌实际轻震，且不超过指定幅度")
	await wait_finished()
	check(main._inspection_card_view._fusion_hidden_emblem_slot == -1 and main.emblem_library._drag_enabled, "结果贴回原卡槽后恢复静态纹章与拖动")
	if capture_enabled:
		await process_frame
		_save_motion_preview()
	var loaded := EmblemRecipeDiscovery.new()
	loaded.save_path = DISCOVERY_PATH
	loaded.load_discoveries()
	check(loaded.is_known("flame_sword"), "成功合成永久保存配方发现")
	await capture("card-landed")
	check(main.save_run_to_path(main.run_save_path) == OK, "卡上结果进入现有本局存档")
	var file := FileAccess.open(main.run_save_path, FileAccess.READ)
	var checkpoint: Dictionary = JSON.parse_string(file.get_as_text())
	var saved_card: Dictionary = (checkpoint.collection.cards as Array).filter(func(state: Dictionary): return String(state.instance_id) == String(owned.instance_id))[0]
	check(saved_card.emblem_slots[target_index].emblem_id == "火焰剑" and not (checkpoint.developer_sticker_bag.items as Array).any(func(state: Dictionary): return String(state.instance_id) == String(result.instance_id)), "存档结果位于OwnedCard纹章槽，未放入工具箱")
	# 右侧原槽也必须保持自身锚点，不能回到固定画面中心。
	main.emblem_library.return_sticker({"instance_id": &"second_coin", "emblem_id": &"金币"})
	await click(entry_for(&"second_coin").get_global_rect().get_center())
	var right_local: Vector2 = right_slot.position + Vector2(7, 7)
	await click(surface.card_canvas_point(right_local))
	overlay = main._emblem_fusion_overlay
	check(overlay != null, "右侧槽开启独立锚点公式")
	if overlay != null:
		var toolbox_rest: Vector2 = overlay._toolbox_rest
		await create_timer(0.15).timeout
		var card_delta: Vector2 = surface.position - overlay._anchor_card_rest
		var toolbox_delta: Vector2 = main.emblem_library.position - toolbox_rest
		var formula_delta: Vector2 = overlay._formula.position + overlay._layout_shift
		check(card_delta.x < 0 and card_delta.distance_to(toolbox_delta) < 0.01 and card_delta.distance_to(formula_delta) < 0.01, "滑动中间帧卡牌、公式、工具箱位移完全一致")
		await wait_stage(overlay, &"awaiting")
		check((main.emblem_library.position - toolbox_rest).is_equal_approx(overlay._layout_shift), "工具箱和卡牌同步左移到同一终点")
		check(overlay._first_rest.distance_to(surface.card_canvas_rect(main._get_emblem_slot_rect(int(right_slot.storage_index))).get_center()) < 0.01 and overlay._second_rest.x > overlay._first_rest.x and overlay._result_rest.x + overlay.ICON_SIZE.x * 0.5 <= 1270.1, "右侧纹章和卡牌一起左移，完整公式仍跟随原槽并留在画布内")
		var card_rest: Vector2 = overlay._anchor_card_rest
		var card_rest_z: int = overlay._anchor_card_z_index
		check(surface.z_index > main.emblem_library.z_index, "左移卡牌显示在工具箱前方，不被工具箱遮住")
		await capture("card-right")
		await button(true, MOUSE_BUTTON_RIGHT)
		await button(false, MOUSE_BUTTON_RIGHT)
		await wait_finished()
		check(surface.position.is_equal_approx(card_rest) and surface.z_index == card_rest_z and main.emblem_library.position.is_equal_approx(toolbox_rest), "取消后卡牌、工具箱还原位置，卡牌层级恢复")
	# 滑动途中强制关闭检视，旧演出的销毁不能再覆盖普通工具箱的位置。
	await click(entry_for(&"second_coin").get_global_rect().get_center())
	await click(surface.card_canvas_point(right_local))
	main._close_card_inspection(true)
	await process_frame
	await process_frame
	check(main.emblem_library.position.is_equal_approx(toolbox_normal_position) and not main.emblem_library.fusion_busy, "滑动中关闭检视后工具箱保持普通布局，不被延迟清理覆盖")
	main._open_card_inspection(source_card.card_data, owned, source_card)
	await create_timer(0.35).timeout
	if not main._inspection_library_expanded:
		main._toggle_inspection_library()
		await create_timer(0.3).timeout
	surface = main._inspection_surface
	await click(entry_for(&"second_coin").get_global_rect().get_center())
	await click(surface.card_canvas_point(right_local))
	overlay = main._emblem_fusion_overlay
	if overlay == null:
		check(false, "重新检视后仍可合成")
		quit(1)
		return
	await wait_stage(overlay, &"awaiting")
	var confirm_card_rest: Vector2 = overlay._anchor_card_rest
	var confirm_toolbox_rest: Vector2 = overlay._toolbox_rest
	await click(overlay._confirm.position + overlay._confirm.size * 0.5)
	await click(Vector2(100, 660))
	await click(Vector2(100, 660))
	await wait_finished()
	check(surface.position.is_equal_approx(confirm_card_rest) and main.emblem_library.position.is_equal_approx(confirm_toolbox_rest) and owned.emblem_slots[int(right_slot.storage_index)].emblem_id == &"金苹果", "确认合成结束后卡牌和工具箱同步还原，结果保留原槽")
	main._close_card_inspection(true)
	await process_frame
	check(owned.emblem_slots[target_index].emblem_id == &"火焰剑", "关闭检视保留卡上合成结果")
	DirAccess.remove_absolute(DISCOVERY_PATH)
	main.queue_free()
	await process_frame
	print("Emblem fusion UI failures: ", failures)
	quit(1 if failures else 0)
