extends SceneTree

## 用正式CardView和开包检视表面在GPU上验证六种卡面×三种卡图。
const Appearance = preload("res://scripts/data/card_appearance.gd")
const CARD := preload("res://scenes/ui/CardView.tscn")
const TILE := Rect2i(20, 0, 470, 640) # 每个组合截取同一大小的实际画面
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()

func difference(a: Image, b: Image) -> int:
	var changed := 0
	for y: int in range(60, 570):
		for x: int in range(55, 435):
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) + absf(delta.a) > 0.025: changed += 1
	return changed

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color("11141b")
	backdrop.size = Vector2(1280, 720)
	root.add_child(backdrop)
	var caption := Label.new()
	caption.position = Vector2(35, 4)
	caption.size = Vector2(450, 32)
	caption.add_theme_font_size_override("font_size", 20)
	root.add_child(caption)
	var source := load("res://resources/cards/militia.tres") as CardData
	var original_bytes := FileAccess.get_file_as_bytes(source.resource_path)
	var grid := Image.create(TILE.size.x * 6, TILE.size.y * 3, false, Image.FORMAT_RGBA8)
	for art: int in Appearance.ART_KEYS.size():
		var reference: Image
		for face: int in Appearance.SURFACE_KEYS.size():
			var owned := OwnedCard.new()
			owned.initialize(source, StringName("visual_%d_%d" % [face, art]), 0)
			owned.surface_finish = face as Appearance.Surface
			owned.art_finish = art as Appearance.Art
			var card := CARD.instantiate() as CardView
			card.set_card_data(source)
			card.set_owned_card(owned)
			card.configure_drag_source(false)
			root.add_child(card)
			var surface := InspectionCardSurface.new()
			root.add_child(surface)
			surface.setup(card, Callable(), Callable())
			surface.tilt_locked = true
			surface.set_process(false)
			surface.position = Vector2(50, 48)
			surface.scale = Vector2(3, 3)
			surface.set_pointer_force(Vector2(0.7, -0.45))
			caption.text = "%s卡面 / %s卡图" % [Appearance.SURFACE_LABELS[face], Appearance.ART_LABELS[art]]
			var shot := await capture()
			var renderer = card._finish_controller
			var foil := face in [Appearance.Surface.SILVER, Appearance.Surface.GOLD, Appearance.Surface.RAINBOW]
			check(bool(surface.effect.get_shader_parameter("use_flash")) == foil, "真实检视按卡面维度启用扫光：" + caption.text)
			if foil: check(int(surface.effect.get_shader_parameter("flash_type")) == face - Appearance.Surface.SILVER, "银／金／彩闪的颜色正确")
			check(bool(surface.effect.get_shader_parameter("use_fractured")) == (face == Appearance.Surface.FRACTURED), "碎闪可与卡图组合")
			check(bool(renderer._art_material.get_shader_parameter("embossed")) == (face == Appearance.Surface.EMBOSSED), "法线可与卡图组合")
			check(renderer._overframe_clip.visible == (art == Appearance.Art.OVERFRAME), "超框由卡图维度控制")
			check((float(renderer._art_material.get_shader_parameter("layer_depth")) < 0.0) == (art == Appearance.Art.HOLOGRAPHIC), "全息由卡图维度控制")
			check(renderer._art_material.get_shader_parameter("pointer_force") == surface.force, "人物与整卡共用平滑方向")
			var centered := Vector2(floorf((card.art_area_size.x - card.art_texture.size.x) * 0.5), floorf((card.art_area_size.y - card.art_texture.size.y) * 0.5))
			check(card.art_texture.position == centered + Vector2(source.get_art_offset_for_finish(owned.get_art_finish_key())), "真实实例沿用各工艺已保存的取景")
			if face == 0: reference = shot
			else: check(difference(reference, shot) > 50, "GPU实际画面能区分卡面工艺：" + caption.text)
			grid.blit_rect(shot, TILE, Vector2i(face * TILE.size.x, art * TILE.size.y))
			if face == Appearance.Surface.GOLD and art == Appearance.Art.HOLOGRAPHIC: shot.save_png("/private/tmp/project-card-gold-holographic.png")
			if owned.has_special_appearance():
				surface.set_pointer_force(Vector2(-0.7, 0.45))
				var reversed := await capture()
				check(difference(shot, reversed) > 100, "移动鼠标能观察组合效果")
			check(owned.surface_finish == face and owned.art_finish == art, "展示不会重新抽外观")
			surface.queue_free()
			await process_frame
	check(grid.save_png("/private/tmp/project-card-pack-appearance-18.png") == OK, "输出18种组合实拍")
	check(FileAccess.get_file_as_bytes(source.resource_path) == original_bytes, "外观组合与取景不修改共享资源")
	print("开包罕贵度GPU验收：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
