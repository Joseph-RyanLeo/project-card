extends SceneTree

## 使用真实包装、离屏画布和正式着色器验证4倍显示时的颤抖像素，而非只检查变量。
var canvas: SubViewport
var package: InspectionCardSurface
var tear_art: Control
var failures := 0
var baseline_position := Vector2.ZERO
var baseline_pixels := PackedByteArray()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func rendered() -> Image:
	# 嵌套画布在实际渲染后采样，避免测到尚未绘制的空纹理。
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	return canvas.get_texture().get_image()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("颤抖像素验收需要真实窗口渲染器")
		quit(1)
		return
	create_timer(30).timeout.connect(func(): push_error("颤抖像素验收超时"); quit(1))
	canvas = SubViewport.new()
	canvas.size = Vector2i(900, 1000) # 完整容纳原生包装的4倍表面与透明边距
	canvas.transparent_bg = true
	canvas.disable_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var art := TextureRect.new()
	art.texture = load("res://assets/card_ui/shop/ash_ledger_small.png")
	art.size = art.texture.get_size()
	canvas.add_child(art)
	package = InspectionCardSurface.new()
	canvas.add_child(package)
	package.setup_art(art)
	package.set_process(false)
	package.scale = Vector2(4, 4) # 采用游戏检视的实际包装倍率
	package.position = Vector2(60, 60) # 为负向颤抖留出画布空间
	package.effect.set_shader_parameter("use_flash", false)
	tear_art = CardPackOpening.TearArt.new()
	package.viewport.add_child(tear_art)
	tear_art.setup(art)
	tear_art.position = package.PADDING
	var neutral: Image = await rendered()
	baseline_position = Vector2(neutral.get_used_rect().position)
	baseline_pixels = package.viewport.get_texture().get_image().get_data()
	var hit_origin := package.position
	var hit_point := package.card_point(package.PADDING + Vector2(9, 7))
	for amplitude: float in [0.5, 0.6, 1.5]:
		var min_x := 1000
		var max_x := -1000
		# 正弦一般不到精确峰值；0.5×0.99复现旧实现低于半个原生像素的情况。
		for wave: float in [0.0, 0.99, -0.99]:
			package.effect.set_shader_parameter("visual_offset", Vector2(amplitude * wave, 0) / package.scale)
			var image_value: Image = await rendered()
			var moved := image_value.get_used_rect().position.x - int(baseline_position.x)
			min_x = mini(min_x, moved)
			max_x = maxi(max_x, moved)
			check(absf(moved - amplitude * wave) <= 1.0, "幅度%.1f在4倍画面位移%d像素，仅受最终像素取整影响" % [amplitude, moved])
			check(package.viewport.get_texture().get_image().get_data() == baseline_pixels, "颤抖不重新栅格化1倍包装纹理")
			check(package.position == hit_origin and package.card_point(package.PADDING + Vector2(9, 7)).is_equal_approx(hit_point), "视觉颤抖不移动封口命中位置")
		print("幅度 ", amplitude, " 的实际4倍显示横向范围：", min_x, " 至 ", max_x)
		if amplitude == 0.6:
			check(min_x < 0 and max_x > 0 and max_x - min_x <= 2, "0.6仍可轻颤，但不会放大成正负4像素跳动")
	package.effect.set_shader_parameter("visual_offset", Vector2.ZERO)
	var restored: Image = await rendered()
	check(restored.get_data() == neutral.get_data(), "清零视觉位移后像素画面完整归位")
	canvas.queue_free()
	await process_frame
	print("Card pack shake pixel failures: ", failures)
	quit(1 if failures else 0)
