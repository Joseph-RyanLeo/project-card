extends RefCounted

## 正式入场和调整器使用同一个演出函数，只接收包装、画布和参数，不接触任务或发卡。
const Dust = preload("res://scripts/ui/event_landing_dust.gd")
const ARC_SAMPLES: int = 64 # 估算弧线长度的分段数，用于把平均速度换算成时间
const MIN_SECONDS: float = 0.02 # 重合端点时仍保留一个有效动画步骤


static func point(values: Dictionary, key: String) -> Vector2:
	return Vector2(values["arrival_" + key + "_x"], values["arrival_" + key + "_y"])


static func flight_point(start: Vector2, contact: Vector2, progress: float, height: float) -> Vector2:
	return start.lerp(contact, progress) - Vector2(0, sin(PI * progress) * height)


static func timing(values: Dictionary) -> Vector2:
	var start := point(values, "start")
	var contact := point(values, "contact")
	var length := 0.0
	var previous := start
	for index: int in range(1, ARC_SAMPLES + 1):
		var next := flight_point(start, contact, float(index) / ARC_SAMPLES, values.arrival_arc_height)
		length += previous.distance_to(next)
		previous = next
	var slide_distance := contact.distance_to(point(values, "end"))
	return Vector2(maxf(MIN_SECONDS, length / values.arrival_fall_speed), maxf(MIN_SECONDS, slide_distance * values.arrival_slide_power / values.arrival_slide_speed))


static func speed_ratio(progress: float, power: float) -> float:
	return pow(maxf(0.0, 1.0 - progress), power - 1.0)


static func play(button: TextureButton, host: Control, values: Dictionary) -> Tween:
	var start := point(values, "start")
	var contact := point(values, "contact")
	var end := point(values, "end")
	var seconds := timing(values)
	var start_angle := deg_to_rad(values.arrival_start_angle)
	var contact_angle := deg_to_rad(values.arrival_contact_angle)
	var start_scale: float = values.arrival_start_scale
	var end_scale: float = values.arrival_end_scale
	var fall_power: float = values.arrival_fall_power
	var slide_power: float = values.arrival_slide_power
	var height: float = values.arrival_arc_height
	var dust_spread: float = values.arrival_dust_spread
	var slide := end - contact
	var slide_direction := slide.normalized()
	var pack_half_extent := button.size.dot(slide_direction.abs()) * end_scale * 0.5
	for child: Node in host.get_children():
		if child.get_script() == Dust: child.queue_free()
	button.disabled = true
	button.material = null
	button.pivot_offset = button.size * 0.5
	button.position = start - button.pivot_offset
	button.scale = Vector2.ONE * start_scale
	button.rotation = start_angle
	var motion := host.create_tween()
	motion.tween_method(func(time: float):
		var progress := pow(time, fall_power)
		button.position = flight_point(start, contact, progress, height) - button.pivot_offset
		button.scale = Vector2.ONE * lerpf(start_scale, end_scale, progress)
		button.rotation = lerpf(start_angle, contact_angle, progress), 0.0, 1.0, seconds.x)
	motion.tween_callback(func():
		var dust := Dust.new()
		if dust_spread > 0.0 and not slide.is_zero_approx():
			dust.directional_spread = slide + slide_direction * (pack_half_extent + dust_spread)
			dust.slide_seconds = seconds.y
			dust.slide_power = slide_power
		dust.position = contact - Dust.EFFECT_SIZE * 0.5
		dust.z_index = 1 # 沿用事件牌烟尘与亮点，绘制在包装之上
		host.add_child(dust))
	motion.tween_method(func(time: float):
		var progress := 1.0 - pow(1.0 - time, slide_power)
		button.position = contact.lerp(end, progress) - button.pivot_offset
		button.rotation = lerpf(contact_angle, 0.0, progress), 0.0, 1.0, seconds.y)
	motion.tween_callback(func():
		button.position = end - button.pivot_offset
		button.scale = Vector2.ONE * end_scale
		button.rotation = 0.0
		button.disabled = false)
	return motion
