extends SceneTree

## 真实卡面GPU对照：先隔离工艺光影，再检查4倍合成是否保留原图像素块。
const CARD = preload("res://scenes/ui/CardView.tscn")
const Appearance = preload("res://scripts/data/card_appearance.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func capture(surface: InspectionCardSurface) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return surface.viewport.get_texture().get_image()

func mixed_blocks(shot: Image, factor: int) -> int:
	# 位于插画内部，避开字体、数值、图标阴影等独立绘制内容。
	var mixed := 0
	for y: int in range(53, 108):
		for x: int in range(43, 93):
			var base := shot.get_pixel(x * factor, y * factor)
			var different := false
			for dy: int in factor:
				for dx: int in factor:
					if shot.get_pixel(x * factor + dx, y * factor + dy) != base: different = true
			if different: mixed += 1
	return mixed

func run() -> void:
	root.size = Vector2i(1280, 720)
	for card_id: String in ["shadowstep_assassin", "moonlight_treant"]:
		var definition := load("res://resources/cards/" + card_id + ".tres") as CardData
		var owned := OwnedCard.new()
		owned.initialize(definition, StringName("sampling_" + card_id), 0)
		owned.surface_finish = Appearance.Surface.GOLD
		var card := CARD.instantiate() as CardView
		card.set_card_data(definition)
		card.set_owned_card(owned)
		root.add_child(card)
		var surface := InspectionCardSurface.new()
		root.add_child(surface)
		surface.setup(card, Callable(), Callable())
		surface.set_process(false)
		surface.position = Vector2(20, 20)
		surface.scale = Vector2(4, 4)
		surface.set_pointer_force(Vector2.ZERO)
		surface.effect.set_shader_parameter("use_3d", false)
		card._finish_controller.enabled = false
		card._finish_controller.refresh()
		# 背景会按插画窗口缩放，原像素不一定占恰好4格；只对1:1立绘检查4×4同色块。
		card.art_background.visible = false
		var actual := await capture(surface)
		var actual_mixed := mixed_blocks(actual, 4)
		print(card_id, " 默认内层过滤：", surface.viewport.canvas_item_default_texture_filter, "；原图像素内混色块：", actual_mixed)
		check(surface.render_scale == 4.0 and actual.get_size() == Vector2i(surface.size * 4), "特殊卡保留4倍动态效果画布")
		check(surface.viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, "内层合成明确使用最近邻")
		check(actual_mixed == 0, "关闭光效后每个立绘像素的4×4块保持同色：" + card_id)
		# 在同一实际材质上切换过滤作GPU反例，证明检查确实能识别被平滑的原图。
		surface.viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		var linear := await capture(surface)
		check(mixed_blocks(linear, 4) > 500, "同卡线性过滤确实产生大量像素内混色")
		surface.viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		var nearest := await capture(surface)
		check(mixed_blocks(nearest, 4) == 0, "最近邻恢复硬像素边界")
		card.art_background.visible = true
		surface.viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		linear = await capture(surface)
		surface.viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		nearest = await capture(surface)
		var grid := Image.create(actual.get_width() * 2, actual.get_height(), false, Image.FORMAT_RGBA8)
		grid.blit_rect(linear, Rect2i(Vector2i.ZERO, linear.get_size()), Vector2i.ZERO)
		grid.blit_rect(nearest, Rect2i(Vector2i.ZERO, nearest.get_size()), Vector2i(nearest.get_width(), 0))
		grid.save_png("/private/tmp/project-card-sampling-" + card_id + ".png")
		card._finish_controller.enabled = true
		card._finish_controller.refresh()
		var lit := await capture(surface)
		check(lit.get_data() != nearest.get_data() and surface.effect.get_shader_parameter("use_flash"), "恢复工艺后金闪和图标光影继续生效")
		surface.queue_free()
		await process_frame
	print("卡面像素采样：%d项，%d失败" % [checks, failures])
	quit(1 if failures else 0)
