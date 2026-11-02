extends "res://tests/pack_card_appearance_opening_test.gd"

## 正式陈列、实际购买、原生拖动和GPU像素，覆盖凹凸接入及双向回拉。
const SAVE := "/private/tmp/project-card-pack-relief-formal.json"
const PackArt = preload("res://scripts/ui/pack_tear_art.gd")

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("正式凹凸与回拉专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = SAVE
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if "2k" in OS.get_cmdline_user_args() else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main.run_reward_state.gold = 1000
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.5).timeout
	await verify_shop()
	for size_key: String in ["small", "large"]:
		var index := _find_generated_pack(size_key, false)
		check(index >= 0, "正式生成可购买的" + size_key)
		if index < 0: quit(1); return
		await create_timer(0.2).timeout
		# 小包从只读检视购买，大包从商品直接购买，覆盖两个接入点。
		if size_key == "small":
			await click(_tile(index).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
			await create_timer(0.45).timeout
			check(main._card_pack_opening.cards.is_empty() and main._card_pack_opening.tear_art.material.shader == PackArt.RELIEF, "未购买只读检视已使用同一凹凸材质")
			await click(main._inspection_overlay.get_node("InspectionPackPurchase").get_global_rect().get_center())
		else:
			await click(_tile(index).get_global_rect().get_center())
		await create_timer(0.55).timeout
		var sequence: CardPackOpening = main._card_pack_opening
		var package: InspectionCardSurface = sequence.surface
		check(package.render_scale == 4.0 and package.scale == Vector2(4, 4), "正式开包4倍光影采样不改变固定4倍显示")
		check(sequence.tear_art.material.shader == PackArt.RELIEF and not package.effect.get_shader_parameter("use_pack_foil") and not package.effect.get_shader_parameter("use_flash"), "开包内层凹凸与烫金、外层透视无重复扫光")
		sequence.tear_art.from_left = size_key == "small"
		sequence.tear_art.progress = 0.0
		await verify_seal_pixels(sequence)
		await reverse_drag(sequence, size_key == "small")
		await _finish_cards(sequence)
	# 单击、右键自动开包及卡包两端拉开另外沿用原有开包回归。
	shell.queue_free()
	await process_frame
	await process_frame
	for path: String in [SAVE, SAVE + ".diagnostics.jsonl", SAVE + ".diagnostics.jsonl.previous"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("正式卡包凹凸与回拉失败数：", failures)
	quit(1 if failures else 0)

func image_of(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return viewport.get_texture().get_image()

func verify_shop() -> void:
	var seen := {}
	for seed_value: int in range(1, 50):
		main.ordinary_shop_service.rng.seed = seed_value
		main._generate_ordinary_shop(false)
		await process_frame
		for index: int in main.ordinary_shop_service.offers.size():
			var offer: Dictionary = main.ordinary_shop_service.offers[index]
			if offer.kind != "card_pack" or offer.has("procurement_action"): continue
			var key := String(offer.pack_id) + ":" + String(offer.size)
			if seen.has(key): continue
			await verify_tile(_tile(index), key)
			seen[key] = true
		if seen.size() == 6: break
	check(seen.size() == 6, "正式生成器的三主题大小包全部验证凹凸材质")
	main._select_action_procurement(0)
	await process_frame
	for index: int in main.ordinary_shop_service.offers.size():
		var offer: Dictionary = main.ordinary_shop_service.offers[index]
		if offer.kind == "card_pack" and int(offer.get("procurement_action", -1)) == 0:
			await verify_tile(_tile(index), "melee-directed")
			break
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-pack-relief-formal-shop.png")
	main._select_action_procurement(-1)

func verify_tile(tile: ShopOfferView, tag: String) -> void:
	var surface := tile._hover_surface
	var art := surface.viewport.get_child(0) as PackArt
	check(art != null and surface.render_scale == 2.0, tag + "陈列使用2倍凹凸采样")
	if art == null: return
	check(Vector2(art.source_viewport.size) == art.size and surface.size == art.size, tag + "原图画布、陈列命中及占位尺寸不变")
	var effect := art.material as ShaderMaterial
	for entry: Array in [["light_angle_degrees", 60.0], ["light_front", 0.2], ["light_brightness", 0.95], ["light_mouse_influence", 0.8]]:
		check(is_equal_approx(float(RenderingServer.shader_get_parameter_default(effect.shader.get_rid(), entry[0])), entry[1]), tag + "固定光照参数" + entry[0])
	check(not surface.effect.get_shader_parameter("use_pack_foil") and not surface.effect.get_shader_parameter("use_flash"), tag + "外层没有重复扫光")
	tile.set_process(false)
	surface.set_pointer_force(Vector2(0.6, -0.3))
	var normal: Image = await image_of(surface.viewport)
	effect.set_shader_parameter("body_strength", 0.0)
	effect.set_shader_parameter("gold_strength", 0.0)
	var flat: Image = await image_of(surface.viewport)
	check(normal.get_data() != flat.get_data() and normal.get_used_rect().get_area() > 100, tag + "实际GPU有凹凸光照且包装非空白")
	effect.set_shader_parameter("body_strength", 0.65)
	effect.set_shader_parameter("gold_strength", 0.45)
	tile.set_process(true)

func verify_seal_pixels(sequence: CardPackOpening) -> void:
	var surface := sequence.surface
	surface.tilt_locked = true
	# tilt_locked会让倾斜逐渐回正；像素对照要先暂停这一插值，保持相同光源输入。
	surface.set_process(false)
	surface.set_pointer_force(Vector2(0.6, -0.3))
	var before: Image = await image_of(surface.viewport)
	sequence.tear_art.progress = 0.6
	var lifted: Image = await image_of(surface.viewport)
	var offset := Vector2i(surface.PADDING * 4)
	var body := Rect2i(offset + Vector2i(0, 14 * 4), Vector2i(sequence.tear_art.size.x * 4, (sequence.tear_art.size.y - 14) * 4))
	check(before.get_region(body).get_data() == lifted.get_region(body).get_data(), "封条撕动时袋身法线与印刷保持原位")
	var source_x := 8 if sequence.tear_art.from_left else int(sequence.tear_art.size.x) - 9
	var a := offset + Vector2i(source_x * 4 + 2, 4 * 4 + 2)
	var b := a - Vector2i(0, roundi(sequence.effects.peel_lift * 4))
	check(before.get_pixelv(a).a > 0.9 and before.get_pixelv(a).is_equal_approx(lifted.get_pixelv(b)), "封条颜色和法线按同一UV抬起，原像素光照一致")
	sequence.tear_art.progress = 0.0
	var restored: Image = await image_of(surface.viewport)
	check(before.get_data() == restored.get_data(), "回到零进度时封条与光照逐像素恢复")
	surface.set_pointer_force(Vector2.ZERO)
	await process_frame

func reverse_drag(sequence: CardPackOpening, left: bool) -> void:
	var surface := sequence.surface
	var width := sequence.tear_art.size.x
	var start_x := 9.0 if left else width - 9.0
	var sign_x := 1.0 if left else -1.0
	var gold: int = main.run_reward_state.gold
	var count: int = main.owned_card_collection.size()
	var rng: int = main.ordinary_shop_service.rng.state
	var start := _pointer_for_card_point(surface, Vector2(start_x, 7))
	await _button(start, true)
	await _held_motion(_pointer_for_card_point(surface, Vector2(start_x + sign_x * 35, 7)))
	var forward := sequence.tear_art.progress
	check(forward > 0.2 and forward < 1.0 and sequence.tear_art.from_left == left, "按住封口从指定一端向前撕开")
	await _held_motion(_pointer_for_card_point(surface, Vector2(start_x + sign_x * 15, 7)))
	check(sequence.tear_art.progress < forward and sequence.tear_art.progress > 0.0, "同次按住往回拉，裂口与封条进度下降")
	await _held_motion(start)
	await _button(start, false)
	check(is_zero_approx(sequence.tear_art.progress) and sequence.phase == CardPackOpening.Phase.TEARING and not sequence._auto_tearing, "拉回原点松手保持未开，不误触单击自动开包")
	await _button(start, true)
	var middle := _pointer_for_card_point(surface, Vector2(start_x + sign_x * 35, 7))
	await _held_motion(middle)
	await _button(middle, false)
	var retained := sequence.tear_art.progress
	await _button(middle, true)
	await _held_motion(_pointer_for_card_point(surface, Vector2(start_x + sign_x * 20, 7)))
	check(sequence.tear_art.progress < retained, "松手后重新抓取，也能从保留的裂口继续回拉")
	check(main.run_reward_state.gold == gold and main.owned_card_collection.size() == count and main.ordinary_shop_service.rng.state == rng, "往返拖动不重复购买、发卡或消耗玩法随机流")
	await RenderingServer.frame_post_draw
	shell.internal_viewport.get_texture().get_image().save_png("/private/tmp/project-card-pack-relief-formal-reverse-%s.png" % ("left" if left else "right"))
	await _held_motion(_pointer_for_card_point(surface, Vector2(width - 1 if left else 1.0, 7)))
	await _button(start, false)
	check(sequence.phase == CardPackOpening.Phase.BURST, "重新拉到底后照常退壳与揭卡")
	await create_timer(1.4).timeout
