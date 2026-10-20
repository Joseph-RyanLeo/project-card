extends SceneTree

## 直接比较原生绘制与透明原图集，防止木刺再次被提取、重排、压缩或改色。
const Sample = preload("res://scripts/battle/battle_element_sample_visual.gd")
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Timing = preload("res://scripts/battle/battle_projectile_timing.gd")
var failures := 0
var view: SubViewport
var hits := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func _draw() -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	return view.get_texture().get_image()


func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	view = SubViewport.new()
	view.size = Vector2i(640, 640)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var atlas := Sample.WOOD_ATLAS.get_image()
	atlas.convert(Image.FORMAT_RGBA8)
	# 导入器会向透明像素扩散边色；预乘Alpha只清空这些不可见RGB，不改变任何可见像素。
	atlas.premultiply_alpha()
	var visual := Sample.new()
	view.add_child(visual)
	var profile := Profiles.get_default_profile(&"wood_pierce")
	visual.configure(&"wood_thorns", PackedVector2Array([Vector2(320, 490), Vector2(320, 330)]), profile, 0)
	var rect := visual.sprite.get_rect()
	var top_left := Vector2i((visual.sprite.get_global_transform() * rect.position).round())
	for angle: int in 3:
		var wrong_frames := 0
		for frame: int in 16:
			visual.sprite.frame = angle * 16 + frame
			var image := await _draw()
			var drawn := image.get_region(Rect2i(top_left, Vector2i(160, 450)))
			drawn.convert(Image.FORMAT_RGBA8)
			var expected := atlas.get_region(Rect2i(frame * 160, angle * 450, 160, 450))
			if drawn.get_data() != expected.get_data(): wrong_frames += 1
			if frame == 4: drawn.save_png("/private/tmp/project-card-wood-original-angle-%d.png" % angle)
		check(wrong_frames == 0, "角度%d的16张完整原帧在原比例下逐像素一致，包括分段残影与碎屑" % angle)
	visual.queue_free()
	await process_frame
	visual = Sample.new()
	view.add_child(visual)
	visual.configure(&"wood_thorns", PackedVector2Array([Vector2(320, 490), Vector2(320, 230)]), profile, 0)
	top_left = Vector2i((visual.sprite.get_global_transform() * visual.sprite.get_rect().position).round())
	var wrong_card_regions := 0
	for frame: int in 16:
		visual.sprite.frame = frame
		var image := await _draw()
		for span: Vector2i in [Vector2i(114, 250), Vector2i(274, 410)]:
			var y := span.x if span.x == 114 else span.x + 100
			var drawn := image.get_region(Rect2i(top_left + Vector2i(0, y), Vector2i(160, 136)))
			drawn.convert(Image.FORMAT_RGBA8)
			var expected := atlas.get_region(Rect2i(frame * 160, span.x, 160, 136))
			if drawn.get_data() != expected.get_data(): wrong_card_regions += 1
	check(wrong_card_regions == 0, "两排中心距增加100像素后，两段各136像素的卡牌长度仍逐像素保持原样")
	var material := visual.sprite.material as ShaderMaterial
	check(is_equal_approx(float(material.get_shader_parameter("row_gap")), 124.0), "只把原24像素排间距适配为实际124像素，不再整体压缩450像素原图")
	visual.queue_free()
	await process_frame
	var layer := Node2D.new()
	view.add_child(layer)
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		hits = 0
		var delay := Timing.calculate_impact_delay(profile, variant)
		var flight := Renderer.play(layer, PackedVector2Array([Vector2(320, 490), Vector2(320, 304)]), profile, Color.WHITE, Color.WHITE, func(): hits += 1, 1.0, variant, delay) as Sample
		Renderer.set_flight_paused(flight, true)
		var tween := flight.get_meta("flight_tween") as Tween
		tween.custom_step(delay - 0.001)
		check(hits == 0, "速度%d：延长原帧显示寿命不会提前结算伤害" % variant)
		tween.custom_step(0.002)
		check(hits == 1 and flight.sprite.frame % 16 == 2, "速度%d：仍在原有命中时刻进入上方卡牌的露出帧" % variant)
		var complete_sequence := true
		for frame: int in range(2, 16):
			if flight.sprite.frame % 16 != frame: complete_sequence = false
			tween.custom_step(0.05)
		check(complete_sequence and hits == 1, "速度%d：命中后的2—15帧每帧保持50毫秒，完整长刺与残影没有跳帧" % variant)
		await process_frame
	view.queue_free()
	await process_frame
	print("Wood reference fidelity failures: ", failures)
	quit(1 if failures else 0)
