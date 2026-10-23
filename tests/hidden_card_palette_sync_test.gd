extends "res://tests/d2_7_shop_presentation_test.gd"

## 真实Shader输出、交叠渐变与原PNG对比；颜色同步和图案独立分别检查。
var _gpu: SubViewport
var _sample: TextureRect

func _run() -> void:
	create_timer(50).timeout.connect(func(): push_error("暗卡品级颜色专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-hidden-palette-save.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	_gpu = SubViewport.new()
	_gpu.size = Vector2i(16, 16)
	_gpu.transparent_bg = true
	_gpu.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_gpu)
	_sample = TextureRect.new()
	_sample.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sample.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sample.size = Vector2(16, 16)
	_gpu.add_child(_sample)
	for kind: int in CardData.CardType.size():
		await _check_overlap(kind)
	await _check_construct_pixels()
	await _check_real_inspection()
	_gpu.queue_free()
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(main.run_save_path) if is_instance_valid(main) else DirAccess.remove_absolute("/private/tmp/project-card-hidden-palette-save.json")
	print("Hidden card palette sync: ", failures, " failures")
	quit(1 if failures else 0)

func _new_card(source: CardData, offer: Dictionary = {}, frame: int = 0) -> ShopCardView:
	var card := SHOP_CARD.instantiate() as ShopCardView
	card.configure_hidden(ShopCardView.public_definition(source, offer, frame), offer)
	main.add_child(card)
	card.position = Vector2(400, 50)
	card._carousel_timer.stop()
	card._identity_timer.stop()
	return card

func _check_overlap(kind: int) -> void:
	var definition := CardData.new()
	definition.id = &"secret_should_not_escape"
	definition.card_type = kind as CardData.CardType
	var card := _new_card(definition)
	var action_rect := card.action_icon.get_rect()
	var race_rect := card.race_icon.get_rect()
	card._advance_carousel()
	card._carousel_timer.stop()
	card._rarity_tween.pause()
	card._rarity_tween.custom_step(ShopCardView.CAROUSEL_FADE * 0.5)
	var frame_blend := float((card.card_frame.material as ShaderMaterial).get_shader_parameter("blend_amount"))
	check(is_equal_approx(frame_blend, 0.5) and is_equal_approx(float(card._identity_effect.get_shader_parameter("rarity_blend_amount")), frame_blend), "四类暗卡卡框与中央图标的品级颜色使用同一中间帧进度")
	var action_before := card.card_data.action_type
	card._advance_identity()
	card._identity_timer.stop()
	card._identity_tween.pause()
	card._identity_tween.custom_step(ShopCardView.CAROUSEL_FADE * 0.4)
	check(card.card_data.action_type == action_before and is_equal_approx(card._rarity_progress, 0.5) and is_equal_approx(float(card._identity_effect.get_shader_parameter("rarity_blend_amount")), frame_blend), "中央图案独立切换不重置卡框及颜色渐变")
	var clone := _new_card(card.card_data)
	clone.continue_carousel_from(card)
	clone._carousel_timer.stop()
	clone._identity_timer.stop()
	clone._rarity_tween.pause()
	clone._identity_tween.pause()
	var original := await _render_icon(card)
	var copied := await _render_icon(clone)
	check(original.get_data() == copied.get_data(), "检视继承时，图案和颜色两条进行中的渐变GPU像素完全一致")
	clone.queue_free()
	card._rarity_tween.custom_step(1.0)
	check(card.card_frame.material == null and is_equal_approx(float(card._identity_effect.get_shader_parameter("rarity_blend_amount")), 1.0), "卡框恢复新品级时图标颜色同时到达，不晚一拍")
	card._identity_tween.custom_step(1.0)
	var gpu_image := await _render_icon(card)
	var raw := card._get_identity_texture(card.card_data).get_image()
	raw.convert(Image.FORMAT_RGBA8)
	var expected := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	expected.blit_rect(raw, Rect2i(Vector2i.ZERO, raw.get_size()), (Vector2i(16, 16) - raw.get_size()) / 2)
	check(_same_pixels(gpu_image, expected), "四类暗卡中央图标的最终GPU颜色与当前品级的原始素材一致")
	check(card.action_icon.get_rect() == action_rect and card.race_icon.get_rect() == race_rect and card.card_data.id.is_empty(), "双重渐变仍固定图标位置并保留脱敏定义")
	card.queue_free()
	await process_frame

func _check_construct_pixels() -> void:
	var source := CardData.new()
	source.race_type = CardData.RaceType.CONSTRUCT
	for rarity: int in CardData.Rarity.size():
		var card := _new_card(source, {"hint": "race"}, rarity)
		var rendered := await _render_icon(card)
		var clean_lower_rows := true
		for y: int in range(13, 16):
			for x: int in 16:
				if rendered.get_pixel(x, y).a > 0: clean_lower_rows = false
		check(clean_lower_rows and rendered.get_used_rect().size == Vector2i(13, 11), "五个品级的造物图标只显示完整头部，无下方游离像素")
		var native := CARD.instantiate() as CardView
		var normal_data := CardData.new()
		normal_data.race_type = CardData.RaceType.CONSTRUCT
		normal_data.rarity = rarity as CardData.Rarity
		native.set_card_data(normal_data)
		main.add_child(native)
		check(native.race_icon.texture.get_image().get_size() == Vector2i(13, 11), "普通卡面也使用同一造物有效区域，不只修暗卡")
		native.queue_free()
		card.queue_free()
		await process_frame

func _check_real_inspection() -> void:
	main.run_reward_state.gold = 1000
	main._toggle_ordinary_shop()
	await create_timer(0.5).timeout
	main.ordinary_shop_service.offers.clear()
	main.ordinary_shop_service.offers.append({"kind": "single_card", "card_id": "musketeer", "hidden": true, "hint": "card_type", "price": 8, "instance_seed": "13", "offer_id": "palette_inspection"})
	main._refresh_ordinary_shop_panel()
	await create_timer(0.25).timeout
	main._preview_shop_offer(0)
	await create_timer(0.4).timeout
	var card: ShopCardView = main._inspection_card_view
	var rng: int = main.ordinary_shop_service.rng.state
	var synchronized := true
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var expected := 0.5 - 0.5 * cos(PI * card._rarity_progress)
		synchronized = synchronized and is_equal_approx(float(card._identity_effect.get_shader_parameter("rarity_blend_amount")), expected)
		if card.card_frame.material != null:
			synchronized = synchronized and is_equal_approx(float((card.card_frame.material as ShaderMaterial).get_shader_parameter("blend_amount")), expected)
	check(synchronized and card._identity_index > 1 and card.card_data.id.is_empty() and main.ordinary_shop_service.rng.state == rng, "真实4倍检视多次交叠切换始终同色，图案继续独立且不推进业务随机流")
	await capture("hidden-palette-synchronized")
	main._close_card_inspection(true)
	await process_frame
	check(not is_instance_valid(main._inspection_overlay), "修正后仍能正常关闭暗卡检视")

func _render_icon(card: ShopCardView) -> Image:
	_sample.texture = card.race_icon.texture
	_sample.material = card.race_icon.material
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return _gpu.get_texture().get_image()

func _same_pixels(actual: Image, expected: Image) -> bool:
	for y: int in expected.get_height():
		for x: int in expected.get_width():
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			if absf(a.a - b.a) > 0.01: return false
			if b.a > 0 and (absf(a.r - b.r) > 0.01 or absf(a.g - b.g) > 0.01 or absf(a.b - b.b) > 0.01): return false
	return true
