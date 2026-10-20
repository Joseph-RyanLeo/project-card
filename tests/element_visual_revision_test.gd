extends SceneTree

## 原生透明画布验证三层水波、连续木刺、前景炎尖及火焰边界，不替代战斗逻辑。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Sample = preload("res://scripts/battle/battle_element_sample_visual.gd")
const Fire = preload("res://scripts/battle/battle_fire_visual.gd")
var failures := 0
var view: SubViewport
var layer: Node2D


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func _frame(label: String) -> Image:
	await process_frame
	# macOS后台窗口可能停止自动重绘；主动绘制后读回，避免等待不到绘制信号。
	RenderingServer.force_draw(false)
	var result := view.get_texture().get_image()
	result.save_png("/private/tmp/project-card-element-revision-%s.png" % label)
	return result


func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	view = SubViewport.new()
	view.size = Vector2i(640, 480)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	layer = Node2D.new()
	view.add_child(layer)
	var water := Profiles.get_default_profile(&"water_spread")
	var wave := Renderer.play(layer, PackedVector2Array([Vector2(180, 240), Vector2(480, 240)]), water, Color("0095ff"), Color("0095ff"), Callable(), 1.0, 0)
	Renderer.set_flight_paused(wave, true)
	var animation := wave.get_meta("flight_tween") as Tween
	animation.custom_step(0.04)
	var mesh := wave.get_node("BeamMesh") as MeshInstance2D
	var material := mesh.material as ShaderMaterial
	var first_stretch := float(material.get_shader_parameter("wave_stretch"))
	await _frame("water-early")
	animation.custom_step(0.14)
	var water_image := await _frame("water-late")
	check(float(material.get_shader_parameter("wave_stretch")) > first_stretch, "水波两端随真实行进距离向后拉长")
	var colors := {}
	for y: int in range(480):
		for x: int in range(640):
			var pixel := water_image.get_pixel(x, y)
			if pixel.a > 0.01: colors[pixel.to_html()] = true
	check(colors.size() == 3, "实际透明画布中水波恰有三层纯色与固定透明度")
	var alphas := {}
	for color: String in colors: alphas[Color(color).a8] = true
	check(alphas.size() == 2, "水波只有后层半透明，前缘与主体保持不透明")
	await _check_water_tail(wave, material, water_image)
	wave.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("--record-water"):
		await _record_water(water)
	for variant: int in 3:
		var wood := Sample.new()
		layer.add_child(wood)
		wood.configure(&"wood_thorns", PackedVector2Array([Vector2(320, 400), Vector2(320, 80)]), Profiles.get_default_profile(&"wood_pierce"), variant)
		wood.update_visual(0.2, 1.5, 0.02, 0.1)
		var early := wood.sprite.global_position
		wood.update_visual(0.21, 1.5, 0.021, 0.1)
		check(early.is_equal_approx(wood.sprite.global_position), "木的完整原帧固定对齐两张卡牌，不再额外平移提取出的主刺")
		wood.update_visual(0.8, 1.5, 0.08, 0.1)
		await _frame("wood-%d" % variant)
		wood.queue_free()
		await process_frame
	var fire := Fire.new()
	layer.add_child(fire)
	fire.configure(Profiles.get_default_profile(&"fire_burn"))
	var card := Rect2(270, 210, 100, 136)
	fire.update_visual(card, 0.0)
	for time: float in [0.35, 0.7, 1.1]:
		await _check_fire_contact(fire, card, time)
	await _check_fire_shared_flow(fire, card)
	fire.foreground.hide()
	fire.flame.show()
	var cut_frames := 0
	for time: float in [0.3, 0.55, 0.9, 1.3, 1.8, 2.4]:
		fire.pulse(time, true)
		fire.update_visual(card, time, 1.5)
		var shape := await _frame("fire-shape-%.2f" % time)
		var rect := Rect2i(fire.flame.get_rect())
		var origin := Vector2i(fire.flame.position)
		for y: int in range(origin.y, origin.y + rect.size.y):
			if shape.get_pixel(origin.x, y).a > 0.01 or shape.get_pixel(origin.x + rect.size.x - 1, y).a > 0.01:
				cut_frames += 1
				break
	check(cut_frames == 0, "满强度与终结脉冲下火焰不触碰左右画布边界")
	fire.queue_free()
	await process_frame
	view.queue_free()
	await process_frame
	print("Element visual revision failures: ", failures)
	quit(1 if failures else 0)


func _check_water_tail(wave: Node2D, material: ShaderMaterial, original: Image) -> void:
	var bands := [0, 0, 0]
	for x: int in view.size.x:
		var pixel := original.get_pixel(x, 240)
		if pixel.a < 0.01: continue
		if pixel.a < 0.8: bands[2] += 1
		elif pixel.r > 0.5: bands[0] += 1
		else: bands[1] += 1
	check(bands[0] >= 6 and bands[1] >= 10, "112像素默认波面中，亮前缘至少6像素、正蓝中层至少10像素")
	check(bands[2] > bands[1], "半透明尾波在波心比正蓝中层更宽")
	material.set_shader_parameter("effect_time", 0.56)
	var changed := await _frame("water-tail-moving")
	var opaque_changes := 0
	var rear_changes := 0
	for y: int in view.size.y:
		for x: int in view.size.x:
			var before := original.get_pixel(x, y)
			var after := changed.get_pixel(x, y)
			if before == after: continue
			if before.a > 0.8 or after.a > 0.8: opaque_changes += 1
			else: rear_changes += 1
	check(opaque_changes == 0 and rear_changes > 20, "固定水波位置时，仅半透明尾缘随噪声运动，前两层轮廓与颜色不变")
	var frozen := await _frame("water-tail-frozen")
	check(changed.get_data() == frozen.get_data(), "水波时钟不推进时，真实尾缘像素完全冻结")
	var clipped := 0
	var mesh := wave.get_node("BeamMesh") as MeshInstance2D
	var vertices: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rear_x := ceili((mesh.global_transform * vertices[0]).x)
	for index: int in 12:
		material.set_shader_parameter("effect_time", float(index) * 0.13)
		var frame := await _frame("water-tail-bounds-%02d" % index)
		for y: int in view.size.y:
			if frame.get_pixel(rear_x + 2, y).a > 0.01: clipped += 1
	check(clipped == 0, "多个噪声时刻下水波尾缘与绘制后边界保持留白")


func _record_water(profile: Dictionary) -> void:
	var waves: Array[Node2D] = []
	for index: int in 2:
		var wave := Renderer.play(layer, PackedVector2Array([Vector2(180, 240), Vector2(480, 240)]), profile, Color("0095ff"), Color("0095ff"), Callable(), 1.0, 0)
		Renderer.set_flight_paused(wave, true)
		(wave.get_meta("flight_tween") as Tween).custom_step(0.04 if index == 0 else 0.18)
		wave.position = Vector2(220 + index * 240, 240)
		(wave.get_node("BeamMesh").material as ShaderMaterial).set_shader_parameter("wave_opacity", 1.0)
		waves.append(wave)
	for index: int in 24:
		for wave: Node2D in waves:
			(wave.get_node("BeamMesh").material as ShaderMaterial).set_shader_parameter("effect_time", float(index) * 0.06)
		await _frame("water-motion-%02d" % index)
	for wave: Node2D in waves: wave.queue_free()
	await process_frame


func _check_fire_contact(fire: Fire, card: Rect2, time: float) -> void:
	fire.update_visual(card, time)
	fire.flame.hide()
	fire.foreground.show()
	var front := await _frame("fire-foreground-%.2f" % time)
	fire.flame.show()
	fire.foreground.hide()
	var back := await _frame("fire-background-%.2f" % time)
	var inner_pixels := 0
	var center_pixels := 0
	var disconnected := 0
	var color_mismatch := 0
	var shades := {}
	var opacity_mismatch := 0
	var tip_pixels := 0
	var top_pixels := 0
	for y: int in range(int(card.position.y), int(card.end.y)):
		for x: int in range(int(card.position.x), int(card.end.x)):
			var point := Vector2i(x, y)
			if front.get_pixelv(point).a <= 0.01: continue
			var left := x - int(card.position.x)
			var right := int(card.end.x) - 1 - x
			var bottom := int(card.end.y) - 1 - y
			var edge := mini(mini(left, right), bottom)
			if edge >= 2: inner_pixels += 1
			if edge > Fire.FOREGROUND_DEPTH + Fire.FOREGROUND_TIP_DEPTH: center_pixels += 1
			if edge > Fire.FOREGROUND_DEPTH: tip_pixels += 1
			if y < card.position.y + 10: top_pixels += 1
			var outside := point
			if left <= right and left <= bottom: outside.x = int(card.position.x) - 1
			elif right <= bottom: outside.x = int(card.end.x)
			else: outside.y = int(card.end.y)
			var rooted := back.get_pixelv(outside).a > 0.01
			# 侧边焰尖从下方卡外火团向上生长，根部可以位于当前像素下方。
			if not rooted and outside.y == y:
				for below: int in range(1, ceili(Fire.FOREGROUND_TIP_DEPTH * 2.4) + 3):
					if back.get_pixel(outside.x, mini(outside.y + below, view.size.y - 1)).a > 0.01:
						rooted = true
						break
			if not rooted: disconnected += 1
			var front_color := front.get_pixelv(point)
			var shade := _fire_shade(front_color)
			if shade < 0: color_mismatch += 1
			else: shades[shade] = true
			var expected_alpha := float(fire.effect.get_shader_parameter("opacity")) * Fire.FOREGROUND_OPACITY
			if absf(front_color.a - expected_alpha) > 0.008: opacity_mismatch += 1
	check(inner_pixels > 30 and center_pixels == 0, "%.2f秒：外侧火团少量延伸入卡边，中央透明" % time)
	check(disconnected == 0 and top_pixels == 0, "%.2f秒：内层火舌在当前位置或下方卡外火团扎根，顶部无独立火苗" % time)
	check(color_mismatch == 0 and shades.size() == 3 and opacity_mismatch == 0, "%.2f秒：内层恰有外层色板的暗边／主体／亮区三色，半透明比例保持不变" % time)
	check(tip_pixels > 0, "%.2f秒：内侧有超出主体内缘的细小炎尖" % time)
	var ordered_bands := false
	var max_depth := ceili(Fire.FOREGROUND_DEPTH + Fire.FOREGROUND_TIP_DEPTH)
	for x: int in range(int(card.position.x) + max_depth, int(card.end.x) - max_depth):
		var sequence: Array[int] = []
		for distance: int in max_depth:
			var pixel := front.get_pixel(x, int(card.end.y) - 1 - distance)
			if pixel.a <= 0.01: break
			var shade := _fire_shade(pixel)
			if sequence.is_empty() or sequence[-1] != shade: sequence.append(shade)
		if sequence == [2, 1, 0]: ordered_bands = true
	check(ordered_bands, "%.2f秒：焰尖内部沿向内方向依次经过亮区／主体／暗边后结束" % time)


func _check_fire_shared_flow(fire: Fire, card: Rect2) -> void:
	fire.flame.hide()
	fire.foreground.show()
	var front := fire.foreground.material as ShaderMaterial
	var speed := float(fire.effect.get_shader_parameter("flow_speed"))
	# 连续火焰不会整根刚性平移；直接检查真实画面随流速冻结／恢复，且两层共享时钟。
	for material: ShaderMaterial in [fire.effect, front]: material.set_shader_parameter("flow_speed", 0.0)
	fire.update_visual(card, 1.3)
	var frozen_a := await _frame("fire-flow-frozen-a")
	fire.update_visual(card, 1.44)
	var frozen_b := await _frame("fire-flow-frozen-b")
	check(frozen_a.get_data() == frozen_b.get_data(), "内外流速归零后，实际侧焰画面完全冻结，无独立循环火舌")
	for material: ShaderMaterial in [fire.effect, front]: material.set_shader_parameter("flow_speed", speed)
	fire.update_visual(card, 1.3)
	var moving_a := await _frame("fire-flow-moving-a")
	fire.update_visual(card, 1.44)
	var moving_b := await _frame("fire-flow-moving-b")
	check(moving_a.get_data() != moving_b.get_data() and front.get_shader_parameter("effect_time") == fire.effect.get_shader_parameter("effect_time") and front.get_shader_parameter("flow_speed") == fire.effect.get_shader_parameter("flow_speed"), "恢复流速后原生侧焰连续变形，内外使用相同时间与流速")


func _fire_shade(color: Color) -> int:
	if color.a <= 0.01: return -1
	# 透明画布的RGB已经乘过Alpha；还原后核对与外层共用的原始色板。
	var rgb := Vector3(color.r, color.g, color.b) / color.a
	var palette: Array[Color] = [Color("6d4239"), Color("a75f49"), Color("d49c6b")]
	for index: int in palette.size():
		var expected := palette[index]
		var difference := (rgb - Vector3(expected.r, expected.g, expected.b)).abs()
		if maxf(maxf(difference.x, difference.y), difference.z) <= 0.012: return index
	return -1
