extends SceneTree

## 对真实GPU光带测量亮度梯度，验证与鼠标连线垂直，而非仅检查画面变化。
const CARD = preload("res://scenes/ui/CardView.tscn")
const Appearance = preload("res://scripts/data/card_appearance.gd")
const PIXELS := Vector2(135, 172)
const SCALE: int = 4
var checks := 0
var failures := 0


func _initialize() -> void: run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)


func shot(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func energy(color: Color) -> float:
	return color.r + color.g + color.b


func level(frame: Image, reference: Image, x: int, y: int) -> float:
	return energy(frame.get_pixel(x, y)) / maxf(energy(reference.get_pixel(x, y)), 0.01)


func tangent_error(frame: Image, reference: Image, normal: Vector2) -> float:
	var tangent := normal.orthogonal()
	var total := 0.0
	var cross_energy := 0.0
	for y: int in range(48, frame.get_height() - 48, 3):
		for x: int in range(48, frame.get_width() - 48, 3):
			# 彩闪本身有固定彩虹色，先除去同材质无光带时的颜色；跨6像素测量避免8位图像量化噪声。
			var gradient := Vector2(level(frame, reference, x + 6, y) - level(frame, reference, x - 6, y), level(frame, reference, x, y + 6) - level(frame, reference, x, y - 6))
			total += gradient.length_squared()
			cross_energy += pow(gradient.dot(tangent), 2)
	return cross_energy / maxf(total, 0.000001)


func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("闪卡方向专项超时"); quit(1))
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 720)
	var image := Image.create(135, 172, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	image.fill_rect(Rect2i(0, 0, 8, 172), Color.TRANSPARENT)
	var source := ImageTexture.create_from_image(image)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PIXELS * SCALE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect := TextureRect.new()
	rect.texture = source
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Vector2(viewport.size)
	viewport.add_child(rect)
	var grid := Image.create(viewport.size.x * 4, viewport.size.y * 3, false, Image.FORMAT_RGBA8)
	var directions: Array[Vector2] = [Vector2(0.8, 0), Vector2(0, 0.8), Vector2(0.7, 0.4), Vector2(-0.6, 0.5)]
	for path: String in ["res://shaders/card_preview_3d.gdshader", "res://shaders/card_rest_flash.gdshader"]:
		var material := ShaderMaterial.new()
		material.shader = load(path)
		material.set_shader_parameter("use_flash", true)
		material.set_shader_parameter("stripe_spacing", 14.0)
		material.set_shader_parameter("stripe_width", 10.0)
		material.set_shader_parameter("flash_intensity", 0.2)
		material.set_shader_parameter("card_texture_size_px", PIXELS)
		material.set_shader_parameter("texture_size_px", PIXELS)
		rect.material = material
		for kind: int in 3:
			material.set_shader_parameter("flash_type", kind)
			for index: int in directions.size():
				var force := directions[index]
				material.set_shader_parameter("pointer_force", force)
				material.set_shader_parameter("flash_direction_force", force)
				material.set_shader_parameter("stripe_width", 0.0)
				var reference := await shot(viewport)
				material.set_shader_parameter("stripe_width", 10.0)
				var frame := await shot(viewport)
				var error := tangent_error(frame, reference, (force * PIXELS).normalized())
				print("FLASH_DIRECTION: ", path.get_file(), " type=", kind, " force=", force, " tangent_error=", error)
				check(error < 0.004, "GPU光带垂直于真实像素鼠标连线：%s/%d/%d" % [path.get_file(), kind, index])
				check(frame.get_pixel(4, 300).a < 0.001, "透明留白不被光带照亮")
				if path.ends_with("card_preview_3d.gdshader"): grid.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(index * frame.get_width(), kind * frame.get_height()))
	grid.save_png("/private/tmp/project-card-flash-direction-grid.png")
	viewport.queue_free()
	# 真实卡牌接线与中心稳定性：复用检视的鼠标跟随，不另建平滑参数。
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"foil_direction", 0)
	owned.surface_finish = Appearance.Surface.GOLD
	var card: CardView = CARD.instantiate()
	card.set_card_data(owned.card_data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.position = Vector2(800, 80)
	surface.scale = Vector2.ONE * 3
	var force := Vector2(0.6, -0.4)
	var motion := InputEventMouseMotion.new()
	motion.position = surface.get_global_transform_with_canvas() * (surface.size * (Vector2.ONE + force) * 0.5)
	motion.global_position = motion.position
	root.grab_focus()
	Input.warp_mouse(motion.position)
	root.push_input(motion, true)
	await create_timer(0.5).timeout
	print("FLASH_MOUSE: wanted=", force, " actual=", surface.force, " direction=", surface.effect.get_shader_parameter("flash_direction_force"))
	check(surface.force.distance_to(force) < 0.025 and Vector2(surface.effect.get_shader_parameter("flash_direction_force")).distance_to(force) < 0.025, "实际鼠标事件经原检视平滑传入反光方向")
	surface.set_process(false)
	surface.set_pointer_force(force)
	surface.set_pointer_force(Vector2.ZERO)
	check(surface.effect.get_shader_parameter("flash_direction_force") == force, "鼠标到中心保留上一次方向，不跳回固定斜率")
	surface.set_pointer_force(Vector2(0.001, -0.001))
	check(surface.effect.get_shader_parameter("flash_direction_force") == force, "中心微动不引起方向抖动")
	surface.set_pointer_force(Vector2(-0.5, 0.8))
	check(surface.effect.get_shader_parameter("flash_direction_force") == Vector2(-0.5, 0.8), "离开中心后继续更新方向")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-flash-direction-card.png")
	surface.queue_free()
	await process_frame
	print("Flash direction GPU: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
