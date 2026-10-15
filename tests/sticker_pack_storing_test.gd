extends "res://tests/d2_7_shop_presentation_test.gd"

const Opening = preload("res://scripts/ui/sticker_pack_opening.gd")
const Art = preload("res://scripts/ui/sticker_pack_art.gd")
var _offer: Dictionary
var _ids: Array[StringName] = []
var _inventory: Array[Dictionary] = []
var _library_parent: Node
var _library_position := Vector2.ZERO
var _library_scale := Vector2.ONE
var _saved_gold := 0
var _saved_rng := 0

func _run() -> void:
	var no_cards: Array[OwnedCard] = []
	create_timer(90.0).timeout.connect(func(): push_error("贴纸入箱验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-sticker-storing-save.json"
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	var index := -1
	for i: int in main.ordinary_shop_service.offers.size():
		if main.ordinary_shop_service.offers[i].kind == "sticker_pack": index = i; break
	check(index >= 0, "实际商店提供贴纸包")
	if index < 0: quit(1); return
	_offer = main.ordinary_shop_service.offers[index]
	# 用包含同名实例和2×2元素贴纸的合法商品数据，执行真实购买、占格和存档。
	_offer.stickers = [{"id": "火把"}, {"id": "火把"}, {"id": "面包"}, {"id": "光贴纸", "target": "rune"}, {"id": "木贴纸", "target": "rune"}]
	main._refresh_ordinary_shop_panel()
	_library_parent = main.emblem_library.get_parent()
	_library_position = main.emblem_library.position
	_library_scale = main.emblem_library.scale
	var before := main.emblem_library.get_inventory_state() as Array[Dictionary]
	await click(_tile(index).get_global_rect().get_center())
	await create_timer(0.35).timeout
	var sequence: Opening = main._sticker_pack_opening
	check(sequence != null and sequence._sticker_ids.size() == 5, "购买传递五个已提交真实实例ID给演出")
	if sequence == null: quit(1); return
	_ids.assign(sequence._sticker_ids)
	_inventory.assign(main.emblem_library.get_inventory_state())
	_saved_gold = main.run_reward_state.gold
	_saved_rng = main.ordinary_shop_service.rng.state
	check(_inventory.size() == before.size() + 5 and _saved_gold == 985 and FileAccess.file_exists(main.run_save_path), "动画前五枚贴纸已入库且完整保存，只扣一次金币")
	check(_ids[0] != _ids[1] and main.emblem_library.get_inventory_item(_ids[0]).emblem_id == main.emblem_library.get_inventory_item(_ids[1]).emblem_id, "同名贴纸仍各自绑定独立实例")
	await click(sequence.surface.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await _wait_phase(sequence, Opening.Phase.REVEALED)
	var sheet := sequence.surface.viewport.get_node("StickerSheet") as Control
	var angles: Array[float] = []
	for i: int in 5:
		var icon := sheet.get_node("Sticker_%d" % i) as TextureRect
		angles.append(icon.rotation_degrees)
		check(absf(icon.rotation_degrees) <= 45.0 and icon.pivot_offset == icon.size * 0.5, "第%d枚围绕中心随机旋转且不超过45度" % i)
	var distinct := false
	for angle: float in angles: distinct = distinct or absf(angle - angles[0]) > 10.0
	check(distinct and sequence.surface.render_scale == 4.0, "五枚角度不规则，整张底纸按4倍精度绘制旋转边缘")
	await capture("sticker-random-angles")
	await click(sequence.surface.get_global_rect().get_center())
	await create_timer(0.45).timeout
	check(sequence.phase == Opening.Phase.DETACHING and sequence._flying.size() == 5 and sequence._dim.modulate.a > 0.9, "点击后五枚图标在暗幕上方，其余底纸和背景变暗")
	check(sheet.get_child_count() == 1, "原五枚图标移出底纸，没有复制新奖励")
	await _wait_phase(sequence, Opening.Phase.TOOLBOX_ENTERING)
	for i: int in 5:
		var center := sequence._flying[i].position + sequence._flying[i].pivot_offset
		var target := main.size * Vector2(0.5, sequence.STICKER_ROW_Y) + Vector2((i - 2) * sequence.STICKER_ROW_STEP, 0)
		check(center.distance_to(target) < 2.0 and absf(sequence._flying[i].rotation) < 0.01, "第%d枚依次剥离、旋转转正后在中央并排" % i)
	await capture("sticker-five-arranged")
	await _wait_phase(sequence, Opening.Phase.STORING)
	check(main.emblem_library.get_parent() == main._inspection_overlay and main.emblem_library.position.is_equal_approx(sequence._library_rest), "原工具箱从左侧半展开到位")
	var grid_left: float = main.emblem_library.position.x + sequence.Grid.GRID_ORIGIN.x * main.emblem_library.scale.x
	check(is_equal_approx(grid_left, sequence.TOOLBOX_MARGIN) and main.emblem_library.position.x < 0.0, "仅右半工具箱的四列七行纹章槽完整露出")
	check(sequence.surface.position.is_equal_approx(sequence._sheet_center + Vector2(sequence.CONTENT_SHIFT, 0)), "底纸和五枚贴纸一同向右让位")
	await capture("sticker-toolbox-open")
	var previous_count := 0
	var shake_seen := false
	while sequence.phase == Opening.Phase.STORING:
		shake_seen = shake_seen or absf(main.emblem_library.position.x - sequence._library_rest.x) > 1.0
		if sequence.stored_count > previous_count:
			check(sequence.stored_count == previous_count + 1 and not sequence._flying[previous_count].visible, "从左到右逐枚放置，每次只落下一枚")
			var slot: Rect2 = main.emblem_library.get_item_canvas_rect(_ids[previous_count])
			var icon := sequence._flying[previous_count]
			var actual := icon.get_global_transform_with_canvas() * icon.pivot_offset
			check(actual.distance_to(slot.get_center()) < sequence.TOOLBOX_SHAKE + 1.0, "普通纹章或2×2元素贴纸准确落入已保存的真实槽位")
			check(_ids[previous_count] not in main.emblem_library._hidden_item_ids and main.emblem_library._hidden_item_ids.size() == 5 - sequence.stored_count, "只在落槽时显示对应工具箱图标")
			previous_count = sequence.stored_count
		await process_frame
	check(sequence.stored_count == 5 and shake_seen, "五枚全部入箱，工具箱有轻微震动")
	await _wait_phase(sequence, Opening.Phase.EMPTY_REVEALED)
	check(sequence.surface.position.is_equal_approx(sequence._sheet_center) and not sequence.surface.tilt_locked and sequence._flying.is_empty(), "工具箱收回、屏幕回亮、空底纸居中恢复检视")
	_check_library_restored()
	_check_transaction()
	await capture("sticker-empty-sheet")
	await click(sequence.surface.get_global_rect().get_center())
	await create_timer(0.35).timeout
	check(main._sticker_pack_opening == null and not is_instance_valid(main._inspection_overlay), "再次点击空底纸后飞走回商店")
	# 重播同一份已拥有内容，仅验证加速与清理，不再次执行购买。
	main._open_shop_pack_inspection(_offer, null, true, no_cards, -1, _ids)
	sequence = main._sticker_pack_opening
	await click(Vector2(640, 360))
	await create_timer(0.07).timeout
	await click(Vector2(640, 360))
	check(sequence._auto_advance and sequence._click_speed.speed > 1.0, "放大阶段连点即启用持续加速与自动跨过停留点")
	check(sequence.animation == main._inspection_tween, "初始包装放大也交由同一连点控制器加速")
	var start := Time.get_ticks_msec()
	var accelerated_in_store := false
	while is_instance_valid(main._inspection_overlay) and Time.get_ticks_msec() - start < 8000:
		if sequence.phase == Opening.Phase.STORING and not accelerated_in_store:
			var previous_speed: float = sequence._click_speed.speed
			await click(Vector2(640, 360))
			await create_timer(0.06).timeout
			await click(Vector2(640, 360))
			accelerated_in_store = true
			check(sequence._click_speed.speed > previous_speed, "入箱阶段继续连点也立即提高播放倍率")
		await process_frame
	check(not is_instance_valid(main._inspection_overlay) and accelerated_in_store, "连点后无需阶段确认，自动揭封、抽纸、剥离、入箱和飞走")
	check(Time.get_ticks_msec() - start < 4800, "实际加速后完整后续演出少于4.8秒，明显快于正常约7秒流程")
	_check_library_restored()
	_check_transaction()
	for cancel_phase: int in [Opening.Phase.DETACHING, Opening.Phase.STORING]:
		main._open_shop_pack_inspection(_offer, null, true, no_cards, -1, _ids)
		sequence = main._sticker_pack_opening
		await create_timer(0.35).timeout
		await click(Vector2(640, 360), MOUSE_BUTTON_RIGHT)
		await _wait_phase(sequence, Opening.Phase.REVEALED)
		await click(Vector2(640, 360))
		await _wait_phase(sequence, cancel_phase)
		if cancel_phase == Opening.Phase.DETACHING:
			await create_timer(0.4).timeout
			check(sequence._flying.size() == 5 and is_instance_valid(sequence._dim), "在五枚图标已移出且暗幕存在时验证强制关闭")
		main._close_card_inspection(true)
		await create_timer(0.2).timeout
		_check_library_restored()
		_check_transaction()
		check(not is_instance_valid(main._inspection_overlay), "剥离或入箱途中强制关闭后没有临时图标和暗幕残留")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Sticker pack storing failures: ", failures)
	quit(1 if failures else 0)

func _wait_phase(sequence: Opening, target: int) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(sequence) and sequence.phase != target and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(sequence) and sequence.phase == target, "自动衔接至阶段 " + Opening.Phase.keys()[target])

func _check_library_restored() -> void:
	check(main.emblem_library.get_parent() == _library_parent and main.emblem_library.position.is_equal_approx(_library_position) and main.emblem_library.scale == _library_scale and main.emblem_library._hidden_item_ids.is_empty(), "工具箱原父节点、位置、倍率及所有图标完整恢复")

func _check_transaction() -> void:
	check(main.emblem_library.get_inventory_state() == _inventory and main.run_reward_state.gold == _saved_gold and main.ordinary_shop_service.rng.state == _saved_rng, "演出、加速和取消均不改变库存格位、金币或玩法随机数")
