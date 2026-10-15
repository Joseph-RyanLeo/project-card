extends "res://tests/card_pack_opening_test.gd"

## 真实购买与原生输入：检视按钮购买、撕口居中、倾斜撕包、抽出与方向卡叠。
func _run() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("开包交互验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-pack-interaction-state.json"
	main.run_reward_state.gold = 1000
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.45).timeout
	var offer_index := _find_magic_fireman_pack()
	check(offer_index >= 0, "真实商品随机流提供后层包含魔法伙夫的卡包")
	if offer_index < 0: quit(1); return
	await create_timer(0.2).timeout
	var count_before: int = main.owned_card_collection.size()
	var gold_before: int = main.run_reward_state.gold
	var rng_before: int = main.ordinary_shop_service.rng.state
	await _inspect(offer_index)
	check(main._card_pack_opening.cards.is_empty(), "包装检视尚未购买或创建实际卡牌")
	var purchase := main._inspection_overlay.get_node("InspectionPackPurchase") as Button
	check(purchase.visible and not purchase.disabled, "合法包装检视弹出可点击购买按钮")
	await capture("pack-purchase-preview")
	await click(Vector2(640, 340), MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	check(not is_instance_valid(main._inspection_overlay) and main.run_reward_state.gold == gold_before, "未购买检视的右键只退出，不自动开包或扣款")
	main.run_reward_state.gold = 0
	await _inspect(offer_index)
	purchase = main._inspection_overlay.get_node("InspectionPackPurchase")
	await click(purchase.get_global_rect().get_center())
	check(purchase.disabled and main._card_pack_opening.cards.is_empty() and main.owned_card_collection.size() == count_before, "金币不足时购买按钮禁用，不发卡")
	await click(Vector2(640, 340), MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	main.run_reward_state.gold = gold_before
	await _inspect(offer_index)
	await _drag_seal(0.25, main._card_pack_opening.tear_art.size.x - 1)
	check(main._card_pack_opening.cards.is_empty() and main.run_reward_state.gold == gold_before and main._card_pack_opening.tear_art.progress == 0, "检视中拖动封口不会绕过购买按钮扣款或撕开")
	var good_path: String = main.run_save_path
	main.run_save_path = "/private/tmp/project-card-pack-missing-%d/state.json" % Time.get_ticks_msec()
	purchase = main._inspection_overlay.get_node("InspectionPackPurchase")
	await click(purchase.get_global_rect().get_center())
	check(main.run_reward_state.gold == gold_before and main.ordinary_shop_service.rng.state == rng_before and main.owned_card_collection.size() == count_before and main._card_pack_opening.cards.is_empty() and purchase.visible, "按钮购买存档失败完全回滚，保留检视和购买按钮")
	main.run_save_path = good_path
	var package: InspectionCardSurface = main._inspection_surface
	var preview_y := package.position.y
	await click(purchase.get_global_rect().get_center())
	var sequence: CardPackOpening = main._card_pack_opening
	var expected := sequence.cards.duplicate()
	var price: int = main.ordinary_shop_service.offers[offer_index].price
	check(not expected.is_empty() and main.run_reward_state.gold == gold_before - price and main.owned_card_collection.size() == count_before + expected.size() and FileAccess.file_exists(good_path), "按钮购买提交单次真实交易并保存，再播放位置过渡")
	check(sequence.phase == CardPackOpening.Phase.POSITIONING and not purchase.visible and main._inspection_surface == package, "成功购买沿用同一个包装画布，下移时不再显示购买按钮")
	await click(purchase.get_global_rect().get_center())
	await _move_pointer(Vector2(20, 690))
	await create_timer(0.45).timeout
	var seal := _pointer_for_card_point(package, Vector2(sequence.tear_art.size.x * 0.5, sequence.TearArt.SEAL_HEIGHT * 0.5))
	check(package.position.y > preview_y + 200 and seal.distance_to(main.size * 0.5) < 1 and sequence.phase == CardPackOpening.Phase.SEALED and package.scale == Vector2(4, 4), "购买后包装下移，原生4倍撕口准确停在屏幕中央")
	var all_hidden := true
	for back: InspectionCardSurface in sequence._background_cards:
		all_hidden = all_hidden and not back.visible
		if back.card.card_data.id == &"fireman": _check_fireman(back.card)
	check(all_hidden, "购买后预先绘好真实卡面，撕开前仍隐藏在包装内")
	var start := _pointer_for_card_point(package, Vector2(9, 7))
	await _move_pointer(start)
	await create_timer(0.35).timeout
	start = _pointer_for_card_point(package, Vector2(9, 7))
	var tilt_before := package.force
	await _button(start, true)
	check(sequence.phase == CardPackOpening.Phase.TEARING and not package.tilt_locked and package.force.length() > 0.2 and package.force.distance_to(tilt_before) < 0.1, "按住倾斜中的真实封口命中撕包，保持倾斜而不强制回正")
	await _held_motion(_pointer_for_card_point(package, Vector2(40, 7)))
	var first_jitter: Vector2 = package.effect.get_shader_parameter("visual_offset")
	var hit_origin := package.position
	await create_timer(0.05).timeout
	var jitter: Vector2 = package.effect.get_shader_parameter("visual_offset")
	check(not jitter.is_equal_approx(first_jitter) and (jitter * package.scale).length() <= sequence.effects.tear_shake_pixels * 1.42 and package.position == hit_origin and sequence.tear_art.position == package.PADDING, "按住撕包时按放大后像素轻颤，原生画布和命中位置不移动")
	var progress_before := sequence.tear_art.progress
	await _move_pointer(_pointer_for_card_point(package, Vector2(70, 7)))
	await create_timer(0.18).timeout
	await _held_motion(_pointer_for_card_point(package, Vector2(70, 7)))
	check(not package.tilt_locked and package.force.x > tilt_before.x + 0.2 and sequence.tear_art.progress > progress_before and sequence.tear_art.progress < 1, "按住撕包期间实际移动鼠标，包装持续倾斜且裂口向前推进")
	# 揭晓信号回调内检查真正的起点；等输入函数返回时Tween已推进了数帧。
	sequence.card_requested.connect(func(_owned: OwnedCard):
		if sequence.current_index == 0:
			var card_center := sequence.surface.position + sequence.surface.size * sequence.surface.scale * 0.5
			var pack_center := package.position + package.size * package.scale * 0.5
			check(card_center.is_equal_approx(pack_center), "抽出的4倍卡叠从包装内部中间位置开始")
	, CONNECT_ONE_SHOT)
	await _held_motion(_pointer_for_card_point(package, Vector2(sequence.tear_art.size.x - 1, 7)))
	await _button(start, false)
	check(sequence.phase == CardPackOpening.Phase.BURST and is_instance_valid(sequence._pack_surface) and sequence._background_cards.size() == expected.size() - 1, "包装尚在画面时真实卡叠已开始抽出，不等退壳后闪现")
	check(package.effect.get_shader_parameter("visual_offset") == Vector2.ZERO, "撕开完成清零包装视觉颤抖再抽卡退壳")
	var first_card_position := sequence.surface.position
	var first_pack_position := package.position
	await create_timer(0.22).timeout
	check(sequence.surface.position.y < first_card_position.y - 5 and package.position.y > first_pack_position.y + 5 and sequence.surface.modulate.a == 1, "同一段动画中卡叠向上抽出、外壳向下退出，卡面保持完整")
	await capture("pack-extract-mid")
	await create_timer(1.0).timeout
	check(not is_instance_valid(sequence._pack_surface) and sequence.phase == CardPackOpening.Phase.INSPECTING, "抽出完成释放外壳，才允许点击收卡")
	check((sequence.surface.position + sequence.surface.size * sequence.surface.scale * 0.5).distance_to(main.size * 0.5) < 1, "卡叠向上抽出后停在屏幕中央")
	var rng_after: int = main.ordinary_shop_service.rng.state
	await _move_pointer(Vector2(20, 690))
	await create_timer(0.5).timeout
	check(sequence.surface.force.length() < 0.01 and _backs_aligned(sequence), "鼠标离开时卡叠正面垂直重合，没有固定斜向排列")
	await capture("pack-stack-neutral")
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var point: Vector2 = sequence.surface.size * (Vector2.ONE * 0.5 + direction * 0.3)
		await _move_pointer(sequence.surface.get_global_transform_with_canvas() * point)
		await create_timer(0.4).timeout
		var offset: Vector2 = sequence._background_cards[0].position - sequence.surface.position
		check(sequence.surface.force.dot(direction) > 0.3 and offset.dot(direction) < -1, "鼠标%s时卡面同向倾斜，后层向反方向露边" % direction)
		check(sequence._background_cards[0].force.is_equal_approx(sequence.surface.force), "前后层使用相同倾斜，不被后层自己回正覆盖")
		await capture("pack-stack-%s" % ("left" if direction == Vector2.LEFT else "right" if direction == Vector2.RIGHT else "up" if direction == Vector2.UP else "down"))
	await _move_pointer(Vector2(20, 690))
	await create_timer(0.4).timeout
	for index: int in expected.size():
		while sequence.phase == CardPackOpening.Phase.REVEALING: await process_frame
		check(main._inspection_owned_card == expected[index], "第%d张保持抽取顺序与同一实际实例" % (index + 1))
		if expected[index].card_data.id == &"fireman": _check_fireman(main._inspection_card_view)
		await click(_pointer_for_card_point(main._inspection_surface, Vector2(48, 65)))
		await create_timer(1.05).timeout
	check(main.run_reward_state.gold == gold_before - price and main.ordinary_shop_service.rng.state == rng_after and not is_instance_valid(main._inspection_overlay), "整包演出结束只扣款一次，不重抽行动方式或消耗随机流")
	main._toggle_ordinary_shop()
	DirAccess.remove_absolute(good_path)
	shell.queue_free()
	await process_frame
	print("Card pack interaction failures: ", failures)
	quit(1 if failures else 0)


func _inspect(index: int) -> void:
	await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	main._inspection_surface.force = Vector2.ZERO


func _move_pointer(point: Vector2) -> void:
	# push_input 验证事件路由；卡面实时检视读取原生鼠标位置，还需实际移动窗口鼠标。
	root.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await move(point)


func _drag_seal(hold_seconds: float, end_x: float) -> void:
	var surface: InspectionCardSurface = main._inspection_surface
	var start := _pointer_for_card_point(surface, Vector2(9, 7))
	await _button(start, true)
	await create_timer(hold_seconds).timeout
	await _held_motion(_pointer_for_card_point(surface, Vector2(end_x, 7)))
	await _button(start, false)


func _backs_aligned(sequence: CardPackOpening) -> bool:
	for back: InspectionCardSurface in sequence._background_cards:
		if back.position.distance_to(sequence.surface.position) > 0.3: return false
	return true


func _check_fireman(view: CardView) -> void:
	var owned := view.get_owned_card()
	check(owned.resolved_action_type == CardData.ActionType.MAGIC, "伙夫在获得时已确定魔法行动，不在揭晓时重抽")
	check(view.action_icon.texture.get_image().get_data() == view._get_action_texture(CardData.ActionType.MAGIC).get_image().get_data() and view.action_icon.get_rect() == view._get_action_icon_rect(CardData.ActionType.MAGIC), "伙夫图标纹理与位置尺寸均按实例魔法结果显示")


func _find_magic_fireman_pack() -> int:
	var registry: Dictionary = main._build_card_definition_registry()
	for seed_value: int in range(1, 600):
		main.ordinary_shop_service.initialize(seed_value)
		main.ordinary_shop_service.refresh(main._get_shop_card_definitions(), main.owned_card_collection.get_cards(), main._get_shop_sticker_definitions(), main._get_all_held_stickers())
		for index: int in main.ordinary_shop_service.offers.size():
			var offer: Dictionary = main.ordinary_shop_service.offers[index]
			if offer.kind != "card_pack" or offer.get("pack_id", "") != "ash_ledger" or not offer.cards.slice(1).has("fireman"): continue
			# 用相同真实初始化函数预查种子；正式购买仍走原事务，不替换商品内容或实例结果。
			var trial_rng := RandomNumberGenerator.new()
			trial_rng.state = main.ordinary_shop_service.rng.state
			var trial_collection := OwnedCardCollection.new()
			var magic_fireman := false
			for id_value: String in offer.cards:
				var trial := trial_collection.create_card(registry[StringName(id_value)], trial_rng)
				magic_fireman = magic_fireman or (trial.card_data.id == &"fireman" and trial.resolved_action_type == CardData.ActionType.MAGIC)
			if magic_fireman:
				print("交互验收真实卡包：", offer.cards)
				main._refresh_ordinary_shop_panel()
				return index
	return -1
