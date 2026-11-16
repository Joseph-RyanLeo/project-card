extends SceneTree

## 直接渲染原组件，比较烟尘透明度分布；不载入或保存玩家配置。
const Dust = preload("res://scripts/ui/event_landing_dust.gd")
const Arrival = preload("res://scripts/ui/pack_arrival_animation.gd")
const Effects = preload("res://scripts/ui/pack_opening_effect_settings.gd")
var checks := 0
var failures := 0


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func make_sample(at: Vector2, spread: Vector2, seconds: float = 0.4872) -> Dictionary:
	var container := SubViewportContainer.new()
	container.position = at
	container.size = Vector2(800, 400)
	root.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 400)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var dust := Dust.new()
	dust.position = Vector2(64, 62)
	dust.directional_spread = spread
	if not spread.is_zero_approx(): dust.slide_seconds = 1.6
	viewport.add_child(dust)
	dust.set_process(false)
	dust.elapsed = seconds
	dust._process(0.0)
	return {"viewport": viewport, "dust": dust, "container": container}


func metrics(image: Image) -> Dictionary:
	var weight := 0.0
	var x_sum := 0.0
	var right := 0.0
	var right_edge := 0
	var beyond_stop := 0.0
	var left := 0.0
	var bounds := Rect2i()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha := image.get_pixel(x, y).a
			weight += alpha
			x_sum += x * alpha
			if x > 227: right += alpha
			if x > 640: beyond_stop += alpha
			if x < 330: left += alpha
			if alpha > 0.02: right_edge = maxi(right_edge, x)
			if alpha > 0.005:
				if bounds == Rect2i(): bounds = Rect2i(x, y, 1, 1)
				else: bounds = bounds.expand(Vector2i(x, y))
	return {"center": x_sum / maxf(weight, 0.001), "right": right, "edge": right_edge, "beyond_stop": beyond_stop, "left": left, "bounds": bounds, "weight": weight}


func _run() -> void:
	create_timer(25).timeout.connect(func(): push_error("烟尘方向专项超时"); quit(1))
	root.size = Vector2i(1640, 430)
	var regular := make_sample(Vector2(12, 12), Vector2.ZERO)
	var drifting := make_sample(Vector2(824, 12), Vector2(450, 0), 1.8)
	check(regular.dust._smoke.size == Dust.EFFECT_SIZE and regular.dust._smoke.position == Vector2.ZERO, "普通事件默认不扩展或移动原画布")
	check(drifting.dust._smoke.size.x == Dust.EFFECT_SIZE.x + 450 and drifting.dust._smoke.position == Vector2.ZERO, "整段烟尘扩展画布，保留原着地中心")
	await process_frame
	await RenderingServer.frame_post_draw
	var base := metrics(regular.viewport.get_texture().get_image())
	var moved := metrics(drifting.viewport.get_texture().get_image())
	check(moved.center > base.center + 50, "实际像素烟尘明显铺向右侧：%.2f → %.2f" % [base.center, moved.center])
	check(moved.edge > 677, "烟尘实际覆盖停止后卡包右侧的区域")
	check(moved.right > base.right, "沿右滑方向的烟尘分布增加")
	check(moved.beyond_stop > 30.0, "停止点右侧存在可见烟团，而非仅有零星亮点：%.2f" % moved.beyond_stop)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/previews/d3_4_20261106"))
	root.get_texture().get_image().save_png("res://docs/previews/d3_4_20261106/11_dust_direction.png")
	var early := make_sample(Vector2.ZERO, Vector2(450, 0), 0.10)
	var middle := make_sample(Vector2.ZERO, Vector2(450, 0), 0.55)
	var last_puff := make_sample(Vector2.ZERO, Vector2(450, 0), 2.45)
	await process_frame
	await RenderingServer.frame_post_draw
	var first_pixels := metrics(early.viewport.get_texture().get_image())
	var middle_pixels := metrics(middle.viewport.get_texture().get_image())
	var last_pixels := metrics(last_puff.viewport.get_texture().get_image())
	check(first_pixels.beyond_stop < 0.01 and first_pixels.edge < 420, "滑行刚开始只在左侧扬尘，不提前铺满路线")
	check(middle_pixels.center > first_pixels.center + 45 and middle_pixels.beyond_stop < 1.0, "烟尘随滑行逐段向右生成，未到达的停止点保持干净")
	var middle_image: Image = middle.viewport.get_texture().get_image()
	middle_image.save_png("res://docs/previews/d3_4_20261106/12_dust_outline.png")
	var interior_alpha := 0.0
	var exterior_alpha := 0.0
	for x: int in range(280, 480):
		for y: int in range(180, 225): interior_alpha += middle_image.get_pixel(x, y).a
		for y: int in range(95, 140): exterior_alpha += middle_image.get_pixel(x, y).a
	check(interior_alpha < exterior_alpha * 0.12, "合并轮廓内部留空，不出现重叠小圆环：内部%.2f / 外缘%.2f" % [interior_alpha, exterior_alpha])

	check(moved.left < first_pixels.left * 0.1 and moved.beyond_stop > 30, "停稳后左侧先消散，右侧仍有烟团")
	check(last_pixels.beyond_stop > 10 and last_pixels.weight < moved.weight, "停稳一段时间后，右侧烟团仍在缓慢淡出")
	var ellipse: Vector2i = last_pixels.bounds.size
	check(ellipse.y > 120 and float(ellipse.x) / ellipse.y > 1.05 and float(ellipse.x) / ellipse.y < 1.8, "末端独立烟团保持椭圆，而非细长条：%s" % ellipse)
	var left := make_sample(Vector2(570, 12), Vector2(-36, 0))
	check(left.dust._smoke.position.x == -36 and left.dust._smoke.material.get_shader_parameter("canvas_origin").x == Dust.EFFECT_SIZE.x * 0.5 + 36, "反向滑动时扩展对应一侧，着地点不变")
	var host := Control.new()
	root.add_child(host)
	var button := TextureButton.new()
	button.size = Vector2(125, 186)
	host.add_child(button)
	var values := Effects.defaults()
	values.arrival_fall_speed = 2400.0
	values.arrival_slide_speed = 300.0
	var motion := Arrival.play(button, host, values)
	var spawned: Control = await host.child_entered_tree
	check(spawned.get_script() == Dust and spawned.directional_spread.x > 0 and spawned.directional_spread.y > 0, "实际卡包着地烟尘沿真实滑行方向扩散")
	var slide := Arrival.point(values, "end") - Arrival.point(values, "contact")
	var half_extent: float = button.size.dot(slide.normalized().abs()) * values.arrival_end_scale * 0.5
	check(is_equal_approx(spawned.directional_spread.length(), slide.length() + half_extent + values.arrival_dust_spread), "扩散覆盖整段路线并越过停止后卡包边缘，额外距离读取调整器")
	check(is_equal_approx(spawned.slide_seconds, Arrival.timing(values).y) and spawned.slide_power == values.arrival_slide_power, "实际烟尘继承卡包滑行时长和减速曲线")
	await create_timer(1.3).timeout
	check(is_instance_valid(spawned) and motion.is_running(), "慢速滑行超过原烟尘寿命，沿途烟团仍持续生成")
	var actual_fraction := (button.position + button.pivot_offset - Arrival.point(values, "contact")).length() / slide.length()
	var dust_fraction: float = 1.0 - pow(1.0 - spawned.elapsed / spawned.slide_seconds, spawned.slide_power)
	check(absf(actual_fraction - dust_fraction) < 0.05, "烟尘时间与真实卡包滑行位置保持同步")
	await motion.finished
	check((button.position + button.pivot_offset).distance_to(Arrival.point(values, "end")) < 0.01, "烟尘改动不影响原滑行终点")
	check(is_instance_valid(spawned) and spawned.elapsed < spawned.slide_seconds + spawned.LIFE_SECONDS, "卡包停稳时烟尘仍在，未按原固定总寿命提前消失")
	var zero_values := values.duplicate()
	zero_values.arrival_dust_spread = 0.0
	var zero_motion := Arrival.play(button, host, zero_values)
	var zero_dust: Control = await host.child_entered_tree
	check(zero_dust.directional_spread.is_zero_approx(), "扩散参数设为0可恢复原环状效果")
	await zero_motion.finished
	await create_timer(1.2).timeout
	check(not is_instance_valid(zero_dust), "普通环状烟尘仍在原寿命结束后释放")
	for child: Node in root.get_children(): child.queue_free()
	await process_frame
	print("Landing dust direction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
