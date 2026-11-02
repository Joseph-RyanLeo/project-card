extends SceneTree

## 使用正式图标和正式材质，在真实GPU上细步移动光源，检查阴影有无整像素闪跳。
const SCENE := preload("res://scenes/tools/CardArtTuner.tscn")
const STEPS := 64 # 横向扫过光源的细分步数，用来覆盖最近邻取样的跳变边界
const MAX_ALPHA_STEP := 0.025 # 单步阴影透明度变化上限；允许8位颜色量化误差

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var tuner := SCENE.instantiate() as CardArtTuner
	root.add_child(tuner)
	await process_frame
	await process_frame
	tuner.set_process(false)
	var source := tuner.preview_card.action_icon
	var probe := source.duplicate() as TextureRect
	var material := source.material.duplicate() as ShaderMaterial
	material.set_shader_parameter("light_strength", 0.0)
	probe.material = material
	probe.position = Vector2(24, 24)
	tuner.preview_viewport.add_child(probe)
	tuner.preview_card.hide()
	var previous: Image
	var maximum_jump := 0.0
	var region := Rect2i(80, 80, 144, 144) # 4倍画布中围住图标及投影的实际像素范围
	for step: int in range(STEPS + 1):
		material.set_shader_parameter("pointer_force", Vector2(-1.0 + 2.0 * step / STEPS, 0.0))
		await process_frame
		await RenderingServer.frame_post_draw
		var current := tuner.preview_viewport.get_texture().get_image().get_region(region)
		if previous != null:
			for y: int in current.get_height():
				for x: int in current.get_width():
					maximum_jump = maxf(maximum_jump, absf(current.get_pixel(x, y).a - previous.get_pixel(x, y).a))
		previous = current
	print("阴影连续移动GPU验收：%d步，最大单像素透明度跳变=%.6f（上限%.3f）" % [STEPS, maximum_jump, MAX_ALPHA_STEP])
	var failed := maximum_jump > MAX_ALPHA_STEP
	if failed: push_error("阴影在细步移动时出现整像素透明度跳变")
	tuner.queue_free()
	await process_frame
	quit(1 if failed else 0)
