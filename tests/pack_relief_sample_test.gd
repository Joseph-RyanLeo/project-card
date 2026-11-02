extends SceneTree

## 读取真实 GPU 图像，验证双层强度、遮罩、透明度与鼠标输入。
const SCENE = preload("res://scenes/tools/PackReliefPreview.tscn")
const OUTPUT := "res://docs/previews/pack_relief_20261027/"
var preview: Control
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()

func point(force: Vector2) -> void:
	for surface: InspectionCardSurface in [preview.original, preview.sample]:
		surface.force = force
		surface.effect.set_shader_parameter("pointer_force", force)

func changed(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.015

func is_gold(c: Color) -> bool:
	return c.is_equal_approx(Color("c09852")) or c.is_equal_approx(Color("937236")) or c.is_equal_approx(Color("ffd386"))

func side_mean(shot: Image, region: Rect2i, source: Image) -> float:
	var total := 0.0
	var count := 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var pixel := source.get_pixel(x, y)
			if pixel.a < 0.99 or is_gold(pixel): continue
			var color := shot.get_pixel(870 + x * 3 + 1, 189 + y * 3 + 1)
			total += (color.r + color.g + color.b) / 3.0
			count += 1
	return total / maxf(float(count), 1.0)

func max_body_step(a: Image, b: Image, source: Image) -> float:
	var peak := 0.0
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var source_pixel := source.get_pixel(x, y)
			if source_pixel.a < 0.99 or is_gold(source_pixel): continue
			var position := Vector2i(870 + x * 3 + 1, 189 + y * 3 + 1)
			var delta := a.get_pixelv(position) - b.get_pixelv(position)
			peak = maxf(peak, maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))))
	return peak

func verify_lighting(source: Image) -> void:
	var controls: Dictionary = preview.lighting_controls
	var sample_rect := Rect2i(870, 189, 375, 564) # 无透视时右侧卡包的实际像素范围
	var left_band := Rect2i(3, 44, 21, 100) # 用户高度图左侧完整坡面
	controls.light_mouse_influence.slider.value = 0.0
	controls.light_angle_degrees.slider.value = 0.0
	point(Vector2.ZERO)
	var light_right: Image = await capture()
	controls.light_angle_degrees.slider.value = 180.0
	var light_left: Image = await capture()
	check(side_mean(light_left, left_band, source) - side_mean(light_right, left_band, source) > 0.015, "方向滑块实际改变受光侧：固定左光照亮左侧")
	point(Vector2(-0.8, 0.4))
	var locked_a: Image = await capture()
	point(Vector2(0.8, -0.4))
	var locked_b: Image = await capture()
	check(locked_a.get_region(sample_rect).get_data() == locked_b.get_region(sample_rect).get_data(), "鼠标影响0%时，袋身与金纹照明都保持固定")
	controls.light_front.slider.value = 0.25
	var grazing_left: Image = await capture()
	controls.light_angle_degrees.slider.value = 0.0
	var grazing_right: Image = await capture()
	var grazing_contrast := side_mean(grazing_left, left_band, source) - side_mean(grazing_right, left_band, source)
	controls.light_front.slider.value = 4.0
	var frontal_right: Image = await capture()
	controls.light_angle_degrees.slider.value = 180.0
	var frontal_left: Image = await capture()
	var frontal_contrast := side_mean(frontal_left, left_band, source) - side_mean(frontal_right, left_band, source)
	check(grazing_contrast > frontal_contrast + 0.02, "正面程度越低，掠射光的坡面明暗对比越明显")
	controls.light_brightness.slider.value = 0.5
	var dimmed: Image = await capture()
	controls.light_brightness.slider.value = 1.5
	var brighter: Image = await capture()
	check(max_body_step(dimmed, brighter, source) > 0.2, "亮度滑块真实改变GPU输出")
	controls.light_brightness.slider.value = 0.0
	var off: Image = await capture()
	check(off.get_pixel(1057, 472).is_equal_approx(Color.BLACK), "亮度0时材质关灯")
	preview.set_debug_view(3)
	var clay_off: Image = await capture()
	check(clay_off.get_pixel(1057, 472).is_equal_approx(Color.BLACK), "素色光照视图也响应亮度")
	for view_index: int in [1, 2, 4]:
		preview.set_debug_view(view_index)
		controls.light_brightness.slider.value = 0.0
		var data_off: Image = await capture()
		controls.light_brightness.slider.value = 2.0
		var data_bright: Image = await capture()
		check(data_off.get_region(sample_rect).get_data() == data_bright.get_region(sample_rect).get_data(), "光照亮度不污染计算数据视图：%d" % view_index)
	preview.set_debug_view(0)
	preview.set_strengths(0.35, 0.9)
	controls.light_angle_degrees.slider.value = 90.0
	check(is_equal_approx(preview.body_slider.value, 0.35) and is_equal_approx(preview.gold_slider.value, 0.9), "光源控件不改变袋身和金纹滑块")
	preview.reset_defaults()
	for field: Dictionary in preview.LIGHT_FIELDS:
		var slider: HSlider = controls[field.key].slider
		check(is_equal_approx(slider.value, float(field.default)) and is_equal_approx(float(preview.sample.effect.get_shader_parameter(field.key)), float(field.default) * float(field.scale)), "恢复默认同步光源控件与材质：" + str(field.key))
	check(is_equal_approx(preview.body_slider.value, 0.65) and is_equal_approx(preview.gold_slider.value, 0.45), "恢复默认同时保留原凹凸默认值")
	print("LIGHTING: grazing contrast=", grazing_contrast, " frontal contrast=", frontal_contrast)
	await capture_lighting_examples()

func capture_lighting_examples() -> void:
	var cases := [
		["方向：右侧光", 0.0, 1.4, 1.0, 0.0], ["方向：左侧光", 180.0, 1.4, 1.0, 0.0],
		["正面程度：0.25", 225.0, 0.25, 1.0, 0.0], ["正面程度：4.00", 225.0, 4.0, 1.0, 0.0],
		["亮度：0.40倍", 225.0, 1.4, 0.4, 0.0], ["亮度：1.50倍", 225.0, 1.4, 1.5, 0.0],
		["鼠标影响：0%", 0.0, 1.4, 1.0, 0.0], ["鼠标影响：100%", 0.0, 1.4, 1.0, 100.0],
	]
	var caption: Label
	for child: Node in preview.get_children():
		if child is Label and child.text == "袋身 + 金纹 · 法线样例": caption = child
	var grid := Image.create(1760, 1306, false, Image.FORMAT_RGBA8)
	point(Vector2(0.8, 0.0))
	for index: int in range(cases.size()):
		var settings: Array = cases[index]
		caption.text = settings[0]
		for field_index: int in range(preview.LIGHT_FIELDS.size()):
			var field: Dictionary = preview.LIGHT_FIELDS[field_index]
			preview.lighting_controls[field.key].slider.value = settings[field_index + 1]
		var shot: Image = await capture()
		grid.blit_rect(shot, Rect2i(845, 119, 440, 653), Vector2i((index % 4) * 440, floori(float(index) / 4.0) * 653))
	caption.text = "袋身 + 金纹 · 法线样例"
	check(grid.save_png(OUTPUT + "lighting-effects.png") == OK, "导出四项光照的实际效果对照")
	preview.reset_defaults()

func _run() -> void:
	root.size = Vector2i(1440, 960)
	preview = SCENE.instantiate()
	root.add_child(preview)
	await process_frame
	preview.set_process(false)
	var preset := {"light_angle_degrees": 60.0, "light_front": 0.2, "light_brightness": 0.95, "light_mouse_influence": 80.0}
	for key: String in preset:
		var field: Dictionary = preview.LIGHT_FIELDS.filter(func(item: Dictionary): return item.key == key)[0]
		check(is_equal_approx(preview.lighting_controls[key].slider.value, preset[key]) and is_equal_approx(float(preview.sample.effect.get_shader_parameter(key)), preset[key] * float(field.scale)), "用户固定预设同时用于控件和材质：" + key)
		check(is_equal_approx(float(RenderingServer.shader_get_parameter_default(preview.sample.effect.shader.get_rid(), key)), preset[key] * float(field.scale)), "独立shader默认值与用户预设一致：" + key)
	# 既有四向鼠标照明验收明确切换至跟随模式；独立光源参数另行检查。
	preview.lighting_controls.light_mouse_influence.slider.value = 100.0
	# 既有烫金对照在相同曝光和正面分量下核对，默认预设已在上面单独验证。
	preview.lighting_controls.light_front.slider.value = 1.4
	preview.lighting_controls.light_brightness.slider.value = 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	point(Vector2.ZERO)
	preview.original.effect.set_shader_parameter("use_3d", false)
	preview.sample.effect.set_shader_parameter("use_3d", false)
	preview.set_strengths(0.0, 0.0)
	var flat: Image = await capture()
	preview.set_strengths(1.0, 0.0)
	var body: Image = await capture()
	preview.set_strengths(0.0, 1.0)
	var gold: Image = await capture()
	var source: Image = preview.PACK.get_image()
	var imported_normal: Image = preview.BODY.get_image()
	imported_normal.convert(Image.FORMAT_RGBA8)
	var raw_normal := Image.load_from_file(ProjectSettings.globalize_path("res://assets/card_ui/shop/relief_sample/body_normal.png"))
	var stale_normal_pixels := 0
	for y: int in range(raw_normal.get_height()):
		for x: int in range(raw_normal.get_width()):
			if raw_normal.get_pixel(x, y).a > 0.99 and imported_normal.get_pixel(x, y) != raw_normal.get_pixel(x, y):
				stale_normal_pixels += 1
	check(stale_normal_pixels == 0, "GPU 使用的导入法线与最新 PNG 一致，未读旧缓存")
	var body_changes := 0
	var gold_changes := 0
	var gold_leaks := 0
	var flat_errors := 0
	var transparent_changes := 0
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var point_sample := Vector2i(870 + x * 3 + 1, 189 + y * 3 + 1)
			var point_original := Vector2i(174 + x * 3 + 1, 189 + y * 3 + 1)
			var a := flat.get_pixelv(point_sample)
			var b := body.get_pixelv(point_sample)
			var c := gold.get_pixelv(point_sample)
			var pixel := source.get_pixel(x, y)
			if changed(a, flat.get_pixelv(point_original)): flat_errors += 1
			if changed(a, b) and pixel.a > 0.5 and not is_gold(pixel): body_changes += 1
			if changed(a, c):
				if is_gold(pixel): gold_changes += 1
				else: gold_leaks += 1
			if pixel.a < 0.01 and (changed(a, b) or changed(a, c)): transparent_changes += 1
	check(flat_errors == 0, "两层关闭时与现有烫金精确一致：%d" % flat_errors)
	check(body_changes > 100, "袋身凹凸确实影响非金色包装：%d" % body_changes)
	check(gold_changes > 100, "金纹凹凸确实影响金色区域：%d" % gold_changes)
	check(gold_leaks == 0, "金纹凹凸不泄漏到袋身、白字或银饰：%d" % gold_leaks)
	check(transparent_changes == 0, "凹凸不改变透明区")
	point(Vector2(0.6, -0.35))
	preview.set_strengths(0.0, 0.45)
	var uncreased: Image = await capture()
	preview.set_strengths(0.65, 0.45)
	var reflection_default := float(RenderingServer.shader_get_parameter_default(preview.sample.effect.shader.get_rid(), "body_reflection_strength"))
	preview.sample.effect.set_shader_parameter("body_reflection_strength", 0.0)
	var creased: Image = await capture()
	preview.sample.effect.set_shader_parameter("body_reflection_strength", reflection_default)
	var reflected: Image = await capture()
	var visible_crease_pixels := 0
	var reflection_pixels := 0
	var reflection_gold_leaks := 0
	var reflection_transparent_leaks := 0
	var crease_peak := 0.0
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var location := Vector2i(870 + x * 3 + 1, 189 + y * 3 + 1)
			var pixel := source.get_pixel(x, y)
			var without_fold := uncreased.get_pixelv(location)
			var fold := creased.get_pixelv(location)
			var shiny := reflected.get_pixelv(location)
			# 在封边附近的蓝色袋身检查可见幅度，避免只证明“画面有几个像素变化”。
			if pixel.a > 0.5 and pixel.b > pixel.r and ((y >= 12 and y <= 48) or (y >= 140 and y <= 176)):
				var delta := maxf(absf(fold.r - without_fold.r), maxf(absf(fold.g - without_fold.g), absf(fold.b - without_fold.b)))
				crease_peak = maxf(crease_peak, delta)
				if delta > 0.025: visible_crease_pixels += 1
			if changed(fold, shiny):
				if is_gold(pixel): reflection_gold_leaks += 1
				elif pixel.a < 0.01: reflection_transparent_leaks += 1
				else: reflection_pixels += 1
	check(visible_crease_pixels > 150, "默认强度下封边蓝色折痕有足够可见幅度：%d" % visible_crease_pixels)
	check(reflection_pixels > 1000, "柔和反射在袋身形成宽亮区：%d" % reflection_pixels)
	check(reflection_gold_leaks == 0, "袋身反射不改变独立金纹效果")
	check(reflection_transparent_leaks == 0, "袋身反射不填充透明区")
	# 对比同一彩色包装上关闭／开启肩部增强，验证最终素材上的可见幅度。
	var shadow_default := float(RenderingServer.shader_get_parameter_default(preview.sample.effect.shader.get_rid(), "support_shadow_strength"))
	var highlight_default := float(RenderingServer.shader_get_parameter_default(preview.sample.effect.shader.get_rid(), "support_highlight_strength"))
	preview.sample.effect.set_shader_parameter("support_shadow_strength", 0.0)
	preview.sample.effect.set_shader_parameter("support_highlight_strength", 0.0)
	var without_shoulders: Image = await capture()
	preview.sample.effect.set_shader_parameter("support_shadow_strength", shadow_default)
	preview.sample.effect.set_shader_parameter("support_highlight_strength", highlight_default)
	var with_shoulders: Image = await capture()
	var region_map: Image = preview.REGIONS.get_image()
	var enhanced_shoulder_pixels := 0
	var shoulder_leaks := 0
	var positive_shoulder_peak := 0.0
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var location := Vector2i(870 + x * 3 + 1, 189 + y * 3 + 1)
			if not changed(without_shoulders.get_pixelv(location), with_shoulders.get_pixelv(location)): continue
			var feature := region_map.get_pixel(x, y)
			if feature.g + feature.b > 0.0:
				enhanced_shoulder_pixels += 1
				var delta := with_shoulders.get_pixelv(location) - without_shoulders.get_pixelv(location)
				positive_shoulder_peak = maxf(positive_shoulder_peak, maxf(delta.r, maxf(delta.g, delta.b)))
			else: shoulder_leaks += 1
	check(enhanced_shoulder_pixels > 800, "彩色原图上四周肩部明暗与高光足够可见：%d" % enhanced_shoulder_pixels)
	check(shoulder_leaks == 0, "局部增强不泄漏到高度图的平坦区域：%d" % shoulder_leaks)
	check(positive_shoulder_peak < 0.14, "肩部提亮保持克制，避免发光边：%.3f" % positive_shoulder_peak)
	var directional: Array[Image] = []
	var direction_forces := [Vector2(-0.8, 0.0), Vector2(0.8, 0.0), Vector2(0.0, -0.8), Vector2(0.0, 0.8)]
	var direction_titles := ["鼠标左 · 左暗右亮", "鼠标右 · 右暗左亮", "鼠标上 · 上暗下亮", "鼠标下 · 下暗上亮"]
	var direction_grid := Image.create(1760, 653, false, Image.FORMAT_RGBA8)
	var direction_caption: Label
	for child: Node in preview.get_children():
		if child is Label and child.text == "袋身 + 金纹 · 法线样例": direction_caption = child
	for index: int in range(direction_forces.size()):
		point(direction_forces[index])
		direction_caption.text = direction_titles[index]
		var shot: Image = await capture()
		directional.append(shot)
		direction_grid.blit_rect(shot, Rect2i(845, 119, 440, 653), Vector2i(index * 440, 0))
	direction_caption.text = "袋身 + 金纹 · 法线样例"
	direction_grid.save_png(OUTPUT + "directions.png")
	# 用户新高度图的侧面坡道位于更外侧；覆盖完整坡道，不能只抽取凸边内侧的回落面。
	var left_delta := side_mean(directional[1], Rect2i(3, 44, 21, 100), source) - side_mean(directional[0], Rect2i(3, 44, 21, 100), source)
	var right_delta := side_mean(directional[0], Rect2i(101, 44, 21, 100), source) - side_mean(directional[1], Rect2i(101, 44, 21, 100), source)
	# 新图上下窄凸边分别靠近24和163行，采样须包含凸边外侧完整下降坡面。
	var top_delta := side_mean(directional[3], Rect2i(30, 18, 65, 13), source) - side_mean(directional[2], Rect2i(30, 18, 65, 13), source)
	var bottom_delta := side_mean(directional[2], Rect2i(30, 158, 65, 13), source) - side_mean(directional[3], Rect2i(30, 158, 65, 13), source)
	check(left_delta > 0.015, "鼠标在左时左侧较暗，移到右时左侧变亮：%.3f" % left_delta)
	check(right_delta > 0.015, "鼠标在右时右侧较暗，移到左时右侧变亮：%.3f" % right_delta)
	check(top_delta > 0.015, "鼠标在上时上侧较暗，移到下时上侧变亮：%.3f" % top_delta)
	check(bottom_delta > 0.015, "鼠标在下时下侧较暗，移到上时下侧变亮：%.3f" % bottom_delta)
	var continuity_peaks: Array[float] = []
	for path: Array in [[Vector2(-0.04, 0), Vector2(-0.02, 0), Vector2.ZERO, Vector2(0.02, 0), Vector2(0.04, 0)], [Vector2(0.42, 0.565), Vector2(0.44, 0.565), Vector2(0.46, 0.565), Vector2(0.48, 0.565)]]:
		var previous: Image
		var peak := 0.0
		for force: Vector2 in path:
			point(force)
			var shot: Image = await capture()
			if previous != null: peak = maxf(peak, max_body_step(previous, shot, source))
			previous = shot
		continuity_peaks.append(peak)
		check(peak < 0.03, "鼠标小步穿越中心或旧翻转位置时袋身明暗连续：%.3f" % peak)
	point(Vector2(0.6, -0.35))
	# 去掉印刷后单独验证卡叠的四周肩部，不能让封口折痕替中央鼓起通过验收。
	preview.set_debug_view(3)
	preview.set_strengths(0.0, 0.45)
	var flat_clay: Image = await capture()
	preview.set_strengths(0.65, 0.45)
	var raised_clay: Image = await capture()
	var shoulder_pixels := 0
	for y: int in range(20, 168):
		for x: int in range(8, 117):
			var on_sides := (x <= 24 or x >= 100) and y >= 40 and y <= 148
			var on_ends := (y <= 36 or y >= 152) and x >= 30 and x <= 96
			if not on_sides and not on_ends: continue
			var location := Vector2i(870 + x * 3 + 1, 189 + y * 3 + 1)
			if changed(flat_clay.get_pixelv(location), raised_clay.get_pixelv(location)):
				shoulder_pixels += 1
	check(shoulder_pixels > 800, "素色光照中卡叠四周形成可见肩部：%d" % shoulder_pixels)
	var height_map: Image = preview.HEIGHT.get_image()
	check(height_map.get_pixel(62, 94).r - height_map.get_pixel(7, 94).r > 0.25, "中央卡叠平台高于两侧松弛包装")
	check(height_map.get_pixel(62, 94).is_equal_approx(Color8(143, 143, 143, 255)), "保留用户输入的中央灰度143，没有叠加预设鼓起")
	check(height_map.get_pixel(115, 94).r > height_map.get_pixel(62, 94).r, "保留用户图中高于中央的亮凸边")
	var flat_center_regions := region_map.get_pixel(62, 94)
	check(flat_center_regions.g == 0.0 and flat_center_regions.b == 0.0, "用户平坦中央不生成额外凸脊或凹沟")
	var diagnostics := Image.create(1760, 653, false, Image.FORMAT_RGBA8)
	var caption: Label
	for child: Node in preview.get_children():
		if child is Label and child.text == "袋身 + 金纹 · 法线样例": caption = child
	var diagnostic_titles := ["用户高度 · 亮高暗低", "重算法线 · 当前强度", "素色光照 · 隐藏印刷", "位置 · 黄高度 / 青脊 / 紫沟"]
	for view_index: int in range(1, 5):
		preview.set_debug_view(view_index)
		caption.text = diagnostic_titles[view_index - 1]
		var diagnostic: Image = await capture()
		diagnostics.blit_rect(diagnostic, Rect2i(845, 119, 440, 653), Vector2i((view_index - 1) * 440, 0))
		check(int(preview.sample.effect.get_shader_parameter("debug_view")) == view_index, "计算视图切换已接入：%d" % view_index)
	check(diagnostics.save_png(OUTPUT + "diagnostics.png") == OK, "输出实际 GPU 高度、法线、素色与凹凸位置图")
	caption.text = "袋身 + 金纹 · 法线样例"
	preview.set_debug_view(0)
	var states := [[0.0, 0.0, "关闭凹凸"], [1.0, 0.0, "仅袋身"], [0.0, 1.0, "仅金纹"], [0.65, 0.45, "默认叠加"]]
	var grid := Image.create(1440, 960, false, Image.FORMAT_RGBA8)
	for index: int in range(states.size()):
		preview.set_strengths(states[index][0], states[index][1])
		preview.status.text = states[index][2] + " · 袋身 %.2f / 金纹 %.2f" % [states[index][0], states[index][1]]
		var shot: Image = await capture()
		# 直接拼合实际渲染截图，标题取自真实状态标签。
		var card := shot.get_region(Rect2i(810, 150, 510, 630))
		card.resize(340, 420, Image.INTERPOLATE_NEAREST)
		var origin := Vector2i((index % 2) * 720, (index / 2) * 480)
		grid.fill_rect(Rect2i(origin, Vector2i(720, 480)), Color("111923"))
		grid.blit_rect(card, card.get_used_rect(), origin + Vector2i(190, 0))
		grid.blit_rect(shot, Rect2i(48, 858, 650, 32), origin + Vector2i(30, 440))
	check(grid.save_png(OUTPUT + "layers.png") == OK, "导出四组实际 GPU 对照图")
	await verify_lighting(source)
	preview.original.effect.set_shader_parameter("use_3d", true)
	preview.sample.effect.set_shader_parameter("use_3d", true)
	preview.set_strengths(0.65, 0.45)
	point(Vector2(-0.65, -0.3))
	var left: Image = await capture()
	left.save_png(OUTPUT + "tilt-left.png")
	point(Vector2(0.65, 0.3))
	var right: Image = await capture()
	right.save_png(OUTPUT + "tilt-right.png")
	check(left.get_data() != right.get_data(), "两侧倾斜有实际画面变化")
	point(Vector2(-0.65, -0.3))
	var restored: Image = await capture()
	check(left.get_data() == restored.get_data(), "回到相同角度光影完全恢复")
	preview.set_process(true)
	root.warp_mouse(Vector2i(1170, 300))
	await create_timer(0.5).timeout
	check(preview.sample.force.x > 0.3 and preview.sample.force.y < -0.3, "真实鼠标驱动右上倾斜")
	check(preview.sample.force.is_equal_approx(preview.original.force), "两侧共用鼠标姿态")
	preview.body_slider.value = 0.35
	preview.gold_slider.value = 1.2
	check(is_equal_approx(float(preview.sample.effect.get_shader_parameter("body_strength")), 0.35), "袋身滑块实际传入材质")
	check(is_equal_approx(float(preview.sample.effect.get_shader_parameter("gold_strength")), 1.2), "金纹滑块实际传入材质")
	preview.set_strengths(0.65, 0.45)
	await capture()
	preview.set_process(false)
	point(Vector2(0.55, -0.35))
	var final_shot: Image = await capture()
	final_shot.save_png(OUTPUT + "preview.png")
	# 连续帧同样来自 GPU，只记录卡包对照区，供离线拼成循环演示。
	DirAccess.make_dir_recursive_absolute("/private/tmp/project-card-pack-relief-frames")
	for frame: int in range(36):
		var angle := float(frame) / 36.0 * TAU
		point(Vector2(sin(angle) * 0.7, cos(angle) * 0.45))
		var shot: Image = await capture()
		shot.get_region(Rect2i(100, 120, 1240, 670)).save_png("/private/tmp/project-card-pack-relief-frames/%02d.png" % frame)
	# 可选地把此次修改前保存的真实 shader 与法线放在左侧，输出同角度前后对照。
	if "--compare-previous" in OS.get_cmdline_user_args():
		var old_shader := Shader.new()
		old_shader.code = FileAccess.get_file_as_string("/private/tmp/project-card-pack-relief-before/pack_relief_sample.gdshader")
		preview.original.effect.shader = old_shader
		preview.original.effect.set_shader_parameter("body_normal", ImageTexture.create_from_image(Image.load_from_file("/private/tmp/project-card-pack-relief-before/body_normal.png")))
		preview.original.effect.set_shader_parameter("gold_normal", preview.GOLD)
		preview.original.effect.set_shader_parameter("body_regions", ImageTexture.create_from_image(Image.load_from_file("/private/tmp/project-card-pack-relief-before/body_regions.png")))
		preview.original.effect.set_shader_parameter("body_height", ImageTexture.create_from_image(Image.load_from_file("/private/tmp/project-card-pack-relief-before/body_height_input.png")))
		preview.original.effect.set_shader_parameter("body_strength", 0.65)
		preview.original.effect.set_shader_parameter("gold_strength", 0.45)
		for child: Node in preview.get_children():
			if child is Label and child.text == "现有烫金 · 对照": child.text = "上一版 · 预设高度"
		point(Vector2(0.55, -0.35))
		var comparison: Image = await capture()
		comparison.save_png(OUTPUT + "before-after.png")
	print("PACK RELIEF: %d checks, %d failures; body=%d gold=%d leaks=%d" % [checks, failures, body_changes, gold_changes, gold_leaks])
	print("BODY VISIBILITY: crease pixels=%d peak=%.3f reflection pixels=%d" % [visible_crease_pixels, crease_peak, reflection_pixels])
	print("CARD SUPPORT: shoulder pixels=%d" % shoulder_pixels)
	print("COLOR SUPPORT: enhanced shoulder pixels=%d leaks=%d" % [enhanced_shoulder_pixels, shoulder_leaks])
	print("DIRECTION deltas: ", [left_delta, right_delta, top_delta, bottom_delta], " CONTINUITY peaks: ", continuity_peaks, " HIGHLIGHT peak: ", positive_shoulder_peak)
	quit(1 if failures > 0 else 0)
