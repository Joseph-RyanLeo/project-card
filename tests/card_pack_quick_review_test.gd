extends "res://tests/card_pack_opening_continuity_test.gd"

## 真实交易和原生鼠标输入：单击撕包、固定鼠标快速收卡、稀有卡和强制退出。
func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("快速开包验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-quick-review-state.json"
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	var index := _find_mixed_pack()
	check(index >= 0, "真实卡池生成法术、物品和随从混合大包")
	if index < 0: quit(1); return
	await create_timer(0.2).timeout
	await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(not main._inspection_surface.is_processing(), "拿起包装过程中不同时执行鼠标倾斜")
	await create_timer(0.3).timeout
	var package: InspectionCardSurface = main._inspection_surface
	check(package.is_processing(), "包装到位恢复检视倾斜")
	await click(_pointer_for_card_point(package, Vector2(40, 70)))
	check(main._card_pack_opening.cards.is_empty(), "未购买的检视包装单击不会擅自购买或撕开")
	await click(Vector2(20, 600), MOUSE_BUTTON_RIGHT)
	check(not package.is_processing(), "放回商店时不同时执行鼠标倾斜")
	await create_timer(0.3).timeout
	var retained_slot: Control = null
	for slot: Control in main._get_collection_card_slots():
		if slot.has_meta("owned_card"): retained_slot = slot; break
	await click(_tile(index).get_global_rect().get_center())
	await create_timer(0.3).timeout
	if retained_slot != null:
		check(is_instance_valid(retained_slot) and retained_slot.get_parent() == main.collection_card_row, "购买卡包复用未变化的收藏槽")
	var sequence: CardPackOpening = main._card_pack_opening
	package = main._inspection_surface
	await click(_pointer_for_card_point(package, Vector2(9, 7)))
	check(sequence.phase == CardPackOpening.Phase.TEARING and sequence._auto_tearing, "左键单击封口自动开包")
	await create_timer(1.2).timeout
	check(sequence.phase == CardPackOpening.Phase.INSPECTING, "抽出卡叠后立即接受收卡输入")
	await _quick_collect(sequence)
	index = _find_generated_pack("large", true)
	check(index >= 0, "真实卡池生成含IV卡的五张大包")
	if index < 0: quit(1); return
	await create_timer(0.2).timeout
	await click(_tile(index).get_global_rect().get_center())
	await create_timer(0.3).timeout
	sequence = main._card_pack_opening
	await click(_pointer_for_card_point(main._inspection_surface, Vector2(40, 70)))
	check(sequence._auto_tearing, "左键单击包装主体同样自动开包")
	await create_timer(1.2).timeout
	await _quick_collect(sequence)
	index = _find_generated_pack("large", false)
	await create_timer(0.2).timeout
	await click(_tile(index).get_global_rect().get_center())
	await create_timer(0.3).timeout
	sequence = main._card_pack_opening
	sequence.auto_tear()
	await create_timer(1.2).timeout
	await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
	main._close_card_inspection(true)
	await create_timer(0.5).timeout
	check(not is_instance_valid(main._inspection_overlay) and not is_instance_valid(sequence), "重叠收卡动画中强制退出会统一释放界面与控制器")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Card pack quick review failures: ", failures)
	quit(1 if failures else 0)


func _quick_collect(sequence: CardPackOpening) -> void:
	var expected := sequence.cards.duplicate()
	var gold: int = main.run_reward_state.gold
	var rng: int = main.ordinary_shop_service.rng.state
	var count: int = main.owned_card_collection.size()
	var overlay: Control = main._inspection_overlay
	var original_stack: Array[InspectionCardSurface] = [sequence.surface]
	original_stack.append_array(sequence._background_cards)
	var original_layers: Array[int] = []
	for card_surface: InspectionCardSurface in original_stack:
		original_layers.append(card_surface.z_index)
	var library_transform: Transform2D = main.emblem_library.get_global_transform_with_canvas()
	var point := _pointer_for_card_point(main._inspection_surface, Vector2(72, 65))
	root.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await move(point)
	await create_timer(0.4).timeout
	check(main._inspection_surface.force.length() > 0.1, "固定鼠标的收卡测试开始于实际倾斜状态")
	var began := Time.get_ticks_msec()
	for card_index: int in expected.size():
		check(main._inspection_owned_card == expected[card_index], "快速阅览第%d张保留抽取顺序与原实例" % (card_index + 1))
		if expected[card_index].card_data.rarity == CardData.Rarity.IV:
			check(sequence.glow.rare and sequence.phase == CardPackOpening.Phase.INSPECTING, "IV聚光展示期间仍允许立即收卡")
		var previous_force: Vector2 = main._inspection_surface.force
		var next: InspectionCardSurface = sequence._background_cards[0] if not sequence._background_cards.is_empty() else null
		var next_texture: Texture2D = next.texture if next != null else null
		await click(point)
		check(sequence.current_index == card_index + 1, "每次点击立即推进一张，无需等待离场动画")
		var layers_preserved := true
		for stack_index: int in original_stack.size():
			if is_instance_valid(original_stack[stack_index]):
				layers_preserved = layers_preserved and original_stack[stack_index].z_index == original_layers[stack_index]
		check(layers_preserved, "收起与后层提升均保持初始层级，后点击的卡始终在先点击的卡下面")
		if next != null:
			check(main._inspection_overlay == overlay and main._inspection_surface == next and next.texture == next_texture, "提升已绘制卡面，复用检视外壳和纹理")
			check(main._inspection_surface.force.distance_to(previous_force) < 0.1 and not main._inspection_surface.tilt_locked, "换卡沿用倾斜角度，不先回正")
			check(main.emblem_library.get_global_transform_with_canvas().is_equal_approx(library_transform), "快速轮换时工具箱位置不变")
			check(main.emblem_library._drag_enabled == (expected[card_index + 1].card_data.card_type == CardData.CardType.MINION), "工具资格跟随当前前层卡大类")
	check(Time.get_ticks_msec() - began < 300, "五张卡可在一段收起动画内连点阅览完毕")
	await create_timer(0.6).timeout
	check(not is_instance_valid(main._inspection_overlay) and main.ordinary_shop_open, "最后一张动画完成后返回商店")
	check(main.run_reward_state.gold == gold and main.ordinary_shop_service.rng.state == rng and main.owned_card_collection.size() == count, "快速连点不重复入库、扣款或消耗随机流")
