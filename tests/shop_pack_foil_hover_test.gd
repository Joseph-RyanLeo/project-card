extends "res://tests/d2_7_shop_presentation_test.gd"

const FOIL = preload("res://shaders/card_preview_3d.gdshader")
const GOLD_PALETTE: Array[Color] = [Color("c09852"), Color("937236"), Color("ffd386")]

func move(point: Vector2) -> void:
	Input.warp_mouse(shell.render_container.get_global_transform_with_canvas() * point)
	await super.move(point)

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("商店烫金悬停验收超时"); quit(1))
	await _check_gold_pixels()
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-shop-foil-save.json"
	main.run_reward_state.gold = 1000
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	main._toggle_ordinary_shop()
	await create_timer(0.6).timeout
	var rng_before: int = main.ordinary_shop_service.rng.state
	var seen := {}
	for stack: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
		var tile: ShopOfferView = stack._offers.back()
		var surface := main._shop_offer_art(int(tile.get_meta("shop_offer_index"))) as InspectionCardSurface
		check(surface != null, "包装商品复用检视表面")
		if surface == null: continue
		var price_position := stack._description.get_global_rect()
		var hit_rect := tile.get_global_rect()
		var original := surface.viewport.get_child(0) as Control
		check(surface.size == original.size and surface.scale == Vector2.ONE, "包装表面保持原生商品尺寸")
		var bottom_right := tile.get_global_transform_with_canvas() * (surface.position + surface.size * Vector2(0.75, 0.7))
		await move(bottom_right)
		await create_timer(0.4).timeout
		for other: ShopPackStackView in main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false):
			if other == stack: continue
			for other_tile: ShopOfferView in other._offers:
				check(other_tile._hover_surface.force.length() < 0.02 and not other_tile._hovered, "切换商品或退出检视后，其余包装恢复平面")
		check(surface.force.x > 0.35 and surface.force.y > 0.25 and is_zero_approx(tile._visual.rotation), "真实鼠标向右下倾斜，取消原来自动轻晃")
		check(stack._hover_offer == tile and tile.get_global_rect() == hit_rect and stack._description.get_global_rect() == price_position, "倾斜抬起不改变叠包命中和价格位置")
		var kind: String = tile.get_meta("offer").kind
		seen[kind] = true
		if kind == "sticker_pack":
			check(not surface.effect.get_shader_parameter("use_flash") and original.upper.material.get_shader_parameter("use_foil"), "商店贴纸包使用原来的封皮限定金色反光")
		else:
			check(not surface.effect.get_shader_parameter("use_flash") and surface.effect.get_shader_parameter("use_pack_foil"), "商店主题包装只开启中央烫金反光")
		await capture("shop-foil-" + kind + ("-2k" if OS.get_cmdline_user_args().has("2k") else "-720p"))
		# 先离开再进入另一侧，避免当前包提升后遮住邻包的固定优先级影响选择。
		await move(Vector2(40, 450))
		await create_timer(0.5).timeout
		check(surface.force.length() < 0.01 and absf(tile._visual.position.y) < 0.1, "离开商品后倾斜和抬起平滑归位")
		var top_left := tile.get_global_transform_with_canvas() * (surface.position + surface.size * Vector2(0.3, 0.2))
		await move(top_left)
		await create_timer(0.4).timeout
		check(surface.force.x < -0.25 and surface.force.y < -0.4, "真实鼠标向左上倾斜")
		await click(tile.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		await create_timer(0.4).timeout
		check(is_instance_valid(main._inspection_surface) and main._inspection_surface.scale == Vector2(4, 4) and not main._inspection_surface.effect.get_shader_parameter("use_flash"), "右键仍能进入4倍包装检视，保持限定区域反光")
		await key(KEY_ESCAPE)
		await create_timer(0.3).timeout
	check(seen.has("card_pack") and seen.has("sticker_pack"), "实际商店覆盖卡包与贴纸包")
	await _check_single_card_hover()
	check(main.ordinary_shop_service.rng.state == rng_before and main.run_reward_state.gold == 1000, "悬停及只读检视不消耗金币或随机数")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Shop pack foil hover failures: ", failures)
	quit(1 if failures else 0)

func _check_single_card_hover() -> void:
	var definition: CardData
	for candidate: CardData in main._get_shop_card_definitions():
		if candidate.card_type == CardData.CardType.MINION:
			definition = candidate
			break
	check(definition != null, "真实卡池提供单卡倾斜验收目标")
	if definition == null: return
	main.ordinary_shop_service.offers.clear()
	var offer := {"kind": "single_card", "card_id": String(definition.id), "hidden": false, "hint": "card_type", "price": 4, "instance_seed": "13", "offer_id": "single_hover"}
	main.ordinary_shop_service.offers.append(offer)
	for hidden: bool in [false, true]:
		offer.hidden = hidden
		main._refresh_ordinary_shop_panel()
		await create_timer(0.25).timeout
		var tile := _tile(0) as ShopOfferView
		var surface := tile._hover_surface
		check(surface.card is ShopCardView and tile.size == Vector2(112, 174), "明暗单卡共用检视表面，保留原商品占位")
		check(surface.content_padding == InspectionCardSurface.PADDING and not surface.effect.get_shader_parameter("use_pack_foil") and not surface.effect.get_shader_parameter("use_flash"), "单卡保留数值角标留边，不应用包装金色材质")
		var price := tile.get_node("ShopPrice") as Control
		var price_rect := price.get_global_rect()
		var art_origin := surface.position + surface.content_padding
		var art_size := surface.card.card_size
		await move(tile.get_global_transform_with_canvas() * (art_origin + art_size * Vector2(0.75, 0.7)))
		await create_timer(0.4).timeout
		check(surface.force.x > 0.35 and surface.force.y > 0.25 and tile._visual.rotation == 0.0, "明暗单卡指向右下时跟随倾斜，没有自动轻晃")
		var settled := surface.force
		await create_timer(0.35).timeout
		check(surface.force.distance_to(settled) < 0.02 and price.get_global_rect() == price_rect, "鼠标不动时单卡姿态稳定，报价不随图面移动")
		await capture("single-card-hover-" + ("hidden" if hidden else "visible"))
		await move(tile.get_global_transform_with_canvas() * (art_origin + art_size * Vector2(0.25, 0.2)))
		await create_timer(0.4).timeout
		check(surface.force.x < -0.35 and surface.force.y < -0.4, "明暗单卡也能随鼠标向左上倾斜")
		main._preview_shop_single_card(0)
		var original_position: Vector2 = main._inspection_overlay.get_global_transform_with_canvas().affine_inverse() * surface.get_global_transform_with_canvas().origin
		check(main._inspection_source_view == surface and main._inspection_surface.position.is_equal_approx(original_position), "单卡从原商品画布位置开始检视，没有透明留边偏移")
		if hidden:
			check(main._inspection_card_view._carousel_index == surface.card._carousel_index and main._inspection_card_view.card_data.display_name == "？", "暗单放大延续原轮播且不泄露真实身份")
		await create_timer(0.3).timeout
		await key(KEY_ESCAPE)
		await create_timer(0.3).timeout
		check(surface.visible and not is_instance_valid(main._inspection_overlay), "明暗单卡检视关闭后回到同一商品表面")
		await move(Vector2(40, 450))
		await create_timer(0.5).timeout
		check(surface.force.length() < 0.01 and absf(tile._visual.position.y) < 0.1, "离开单卡后倾斜与上抬都恢复原位")

func _check_gold_pixels() -> void:
	for theme: String in ["ash_ledger", "ironwall", "silvermoon"]:
		for pack_size: String in ["small", "large"]:
			var source := load("res://assets/card_ui/shop/%s_%s.png" % [theme, pack_size]) as Texture2D
			var original := source.get_image()
			var viewport := SubViewport.new()
			viewport.size = Vector2i(source.get_size() * 4.0)
			viewport.transparent_bg = true
			viewport.disable_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var art := TextureRect.new()
			art.texture = source
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.size = source.get_size() * 4.0
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var effect := ShaderMaterial.new()
			effect.shader = FOIL
			effect.set_shader_parameter("use_pack_foil", true)
			art.material = effect
			viewport.add_child(art)
			var frames: Array[Image] = []
			for force: Vector2 in [Vector2(-0.75, -0.5), Vector2(0.65, 0.3)]:
				effect.set_shader_parameter("pointer_force", force)
				await process_frame
				await RenderingServer.frame_post_draw
				frames.append(viewport.get_texture().get_image())
			var gold_changed := 0
			var outside_changed := 0
			var gold_interior_gradient := false
			for y: int in original.get_height():
				for x: int in original.get_width():
					var expected := original.get_pixel(x, y)
					var a := frames[0].get_pixel(x * 4 + 1, y * 4 + 1)
					var b := frames[1].get_pixel(x * 4 + 1, y * 4 + 1)
					var gold := GOLD_PALETTE.has(expected) and expected.a > 0.5
					if gold:
						if _different(a, b): gold_changed += 1
						if _different(a, frames[0].get_pixel(x * 4 + 3, y * 4 + 3)): gold_interior_gradient = true
					elif _different(a, b) or (expected.a > 0.5 and _different(a, expected)):
						outside_changed += 1
					if absf(a.a - expected.a) > 0.01: outside_changed += 1
			check(gold_changed > 200 and outside_changed == 0, theme + " " + pack_size + "真实GPU仅改变中央三档金色，保留描边、文字、蓝底和透明度")
			check(gold_interior_gradient, theme + " " + pack_size + "4倍光带在单个原图像素内仍有细腻渐变")
			effect.set_shader_parameter("pack_foil_strength", 0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var flat := viewport.get_texture().get_image()
			var unified := true
			for y: int in original.get_height():
				for x: int in original.get_width():
					if GOLD_PALETTE.has(original.get_pixel(x, y)) and _different(flat.get_pixel(x * 4 + 1, y * 4 + 1), Color("c09852") * Color(0.77, 0.77, 0.77, 1.0)): unified = false
			check(unified, theme + " " + pack_size + "画死的亮暗金统一为纹章封皮底色")
			viewport.queue_free()
			await process_frame

func _different(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) > 0.012 or absf(a.g - b.g) > 0.012 or absf(a.b - b.b) > 0.012 or absf(a.a - b.a) > 0.012
