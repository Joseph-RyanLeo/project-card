class_name BattleAttackTrailRenderer
extends RefCounted

## 根据统一配置生成曲线路径、带状网格和 ShaderMaterial。
## 正式战斗与调试器都调用 play()，避免预览效果与实战实现分叉。

const BATTLE_ENERGY_BEAM_SHADER: Shader = preload("res://shaders/battle_energy_beam.gdshader")
const BATTLE_TRAIL_ENERGY_TEXTURE: Texture2D = preload("res://assets/effects/battle_trail_energy.png")
const BATTLE_TRAIL_PROJECTILE_TEXTURE: Texture2D = preload("res://assets/effects/battle_trail_projectile.png")

const SampleVisual = preload("res://scripts/battle/battle_element_sample_visual.gd")

const BattleProjectileTiming = preload("res://scripts/battle/battle_projectile_timing.gd")
const TravelSpeedVariant = BattleProjectileTiming.TravelSpeedVariant
const TRAVEL_SPEED_VARIANT_COUNT: int = BattleProjectileTiming.TRAVEL_SPEED_VARIANT_COUNT
const WATER_DEPTH_RATIO := 0.48 # 刚发出时圆弧两端落后波心的距离，相对波面宽度
const WATER_MAX_STRETCH_RATIO := 0.60 # 两端随行进后拖的最大距离，相对波面宽度
const WATER_FRONT_PADDING_RATIO := 0.04 # 圆弧前端的透明留白，避免像素对齐裁掉波心


static func play(
	parent: CanvasItem,
	control_points: PackedVector2Array,
	profile: Dictionary,
	head_color: Color,
	tail_color: Color,
	impact_callback: Callable = Callable(),
	speed_scale: float = 1.0,
	speed_variant: int = -1,
	logical_impact_delay: float = -1.0,
	sequence_index: int = 0,
	card_height: float = 136.0
) -> Node2D:
	if not is_instance_valid(parent) or control_points.size() < 2:
		return null
	var mask_kind := profile["mask_kind"] as StringName
	var sample := is_sample_style(mask_kind)
	var path_points := PackedVector2Array([control_points[0], control_points[-1]]) if sample or mask_kind == &"water_flow" else sample_curve(control_points, profile)
	if not sample and polyline_length(path_points) < 1.0:
		return null
	var effect_root: Node2D = SampleVisual.new() if sample else Node2D.new()
	effect_root.name = "ElementEnergyBeam"
	effect_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(effect_root)
	var material: ShaderMaterial
	if sample:
		(effect_root as SampleVisual).configure(mask_kind, control_points, profile, sequence_index, card_height)
	else:
		material = _add_beam_mesh(effect_root, path_points, profile, head_color, tail_color)
	var resolved_speed_variant := (
		randi_range(0, TRAVEL_SPEED_VARIANT_COUNT - 1)
		if speed_variant < 0
		else clampi(speed_variant, 0, TRAVEL_SPEED_VARIANT_COUNT - 1)
	)
	var duration := float(profile["duration"])
	var impact_delay := logical_impact_delay
	if mask_kind == &"wood_thorns":
		if impact_delay < 0.0:
			impact_delay = BattleProjectileTiming.calculate_impact_delay(profile, resolved_speed_variant)
		# 只延长原画显示寿命，逻辑命中仍使用控制器给定的时刻。
		duration = maxf(duration, impact_delay + (16.0 - SampleVisual.WOOD_IMPACT_FRAME) * SampleVisual.WOOD_FRAME_SECONDS)
	effect_root.set_meta("visual_duration", duration)
	var terminal_progress := (
		1.0
		+ float(profile["trail_length"])
		+ float(profile["trail_softness"])
	)
	var impact_progress := 1.0 if sample else nearest_polyline_progress(path_points, control_points[-1])
	if material != null:
		material.set_shader_parameter("impact_progress", impact_progress)
	if impact_delay >= 0.0 and duration > 0.0:
		var logical_time_progress := clampf(
			impact_delay / duration,
			0.0,
			1.0
		)
		var remapped_at_impact := remap_travel_progress(
			logical_time_progress,
			resolved_speed_variant,
			float(profile.get("speed_variation_strength", 0.78))
		)
		if remapped_at_impact > 0.0:
			# 实际曲线会因卡位距离和首尾延伸改变目标点比例；
			# 调整播放终点，使可见弹头仍在控制器确定的逻辑时刻抵达。
			terminal_progress = impact_progress / remapped_at_impact
		effect_root.set_meta("travel_speed_variant", resolved_speed_variant)
	effect_root.set_meta("impact_emitted", false)
	var tween := effect_root.create_tween()
	tween.set_speed_scale(clampf(speed_scale, 0.01, 3.0))
	effect_root.set_meta("flight_tween", tween)
	tween.tween_method(
		_apply_travel_progress.bind(
			material,
			terminal_progress,
			resolved_speed_variant,
			float(profile.get("speed_variation_strength", 0.78)),
			effect_root,
			impact_progress,
			impact_callback,
			duration,
			control_points,
			impact_delay
		),
		0.0,
		1.0,
		duration
	)
	tween.tween_callback(_emit_impact_once.bind(effect_root, impact_callback))
	tween.tween_callback(effect_root.queue_free)
	return effect_root


static func is_sample_style(mask_kind: StringName) -> bool:
	return mask_kind in [&"wood_thorns", &"dark_slash"]


static func _add_beam_mesh(effect_root: Node2D, path_points: PackedVector2Array, profile: Dictionary, head_color: Color, tail_color: Color) -> ShaderMaterial:
	var mask_kind := profile["mask_kind"] as StringName
	var water := mask_kind == &"water_flow"
	var beam_mesh := MeshInstance2D.new()
	beam_mesh.name = "BeamMesh"
	var height := float(profile["beam_height"])
	beam_mesh.mesh = build_ribbon(PackedVector2Array([Vector2(-height * WATER_DEPTH_RATIO, 0), Vector2(height * WATER_FRONT_PADDING_RATIO, 0)]), height) if water else build_ribbon(path_points, height)
	if water:
		effect_root.position = path_points[0]
		effect_root.rotation = (path_points[-1] - path_points[0]).angle()
	var material := ShaderMaterial.new()
	material.shader = BATTLE_ENERGY_BEAM_SHADER
	material.set_shader_parameter("soul_ribbon", mask_kind == &"soul_ribbon")
	material.set_shader_parameter("water_flow", mask_kind == &"water_flow")
	if water:
		material.set_shader_parameter("wave_width", height)
		material.set_shader_parameter("wave_depth", height * WATER_DEPTH_RATIO)
	material.set_shader_parameter("soul_taper", float(profile.get("soul_taper", 0.75)))
	material.set_shader_parameter("soul_core_width", float(profile.get("soul_core_width", 0.30)))
	material.set_shader_parameter("trail_mask", get_mask_texture(mask_kind))
	# 宽能量原图的头在左侧；沿攻击路径绘制时翻转采样，让素材头部朝向目标。
	material.set_shader_parameter("flip_mask_x", mask_kind == &"energy")
	material.set_shader_parameter("head_color", head_color)
	material.set_shader_parameter("tail_color", tail_color)
	material.set_shader_parameter("noise_seed", float(Time.get_ticks_msec() % 997) * 0.013)
	for parameter_name: StringName in [
		&"pixel_size",
		&"trail_length",
		&"trail_softness",
		&"flow_speed",
		&"flow_frequency",
		&"flow_strength",
		&"warp_speed",
		&"warp_frequency",
		&"twirl_frequency",
		&"warp_strength",
		&"mask_cutoff",
		&"mask_power",
		&"edge_threshold",
		&"edge_softness",
	]:
		material.set_shader_parameter(parameter_name, float(profile[String(parameter_name)]))
	material.set_shader_parameter("travel_progress", 0.0)
	beam_mesh.material = material
	effect_root.add_child(beam_mesh)
	return material


static func remap_travel_progress(
	time_progress: float,
	speed_variant: int,
	variation_strength: float
) -> float:
	return BattleProjectileTiming.remap_travel_progress(
		time_progress,
		speed_variant,
		variation_strength
	)


static func _apply_travel_progress(
	time_progress: float,
	material: ShaderMaterial,
	terminal_progress: float,
	speed_variant: int,
	variation_strength: float,
	effect_root: Node2D,
	impact_progress: float,
	impact_callback: Callable,
	effect_duration: float,
	control_points: PackedVector2Array,
	impact_delay: float
) -> void:
	if not is_instance_valid(effect_root):
		return
	var visual_progress := (
		remap_travel_progress(time_progress, speed_variant, variation_strength)
		* terminal_progress
	)
	if effect_root is SampleVisual:
		(effect_root as SampleVisual).update_visual(visual_progress, terminal_progress, time_progress * effect_duration, impact_delay)
	elif is_instance_valid(material):
		material.set_shader_parameter("travel_progress", visual_progress)
		material.set_shader_parameter("effect_time", time_progress * effect_duration)
		if bool(material.get_shader_parameter("water_flow")):
			# 波心按真实弹道前进；只把两端向后拉长，命中后保持形状消散。
			effect_root.position = control_points[0].lerp(control_points[-1], clampf(visual_progress / maxf(impact_progress, 0.001), 0.0, 1.0))
			var width := float(material.get_shader_parameter("wave_width"))
			var distance := effect_root.position.distance_to(control_points[0])
			var stretch := minf(distance * float(material.get_shader_parameter("flow_strength")), width * WATER_MAX_STRETCH_RATIO)
			var depth := width * WATER_DEPTH_RATIO + stretch
			var mesh := effect_root.get_node("BeamMesh") as MeshInstance2D
			mesh.scale.x = (depth + width * WATER_FRONT_PADDING_RATIO) / (width * (WATER_DEPTH_RATIO + WATER_FRONT_PADDING_RATIO))
			mesh.position.x = width * WATER_FRONT_PADDING_RATIO * (1.0 - mesh.scale.x)
			material.set_shader_parameter("wave_depth", depth)
			material.set_shader_parameter("wave_stretch", stretch)
			var dissolve := smoothstep(impact_progress, maxf(terminal_progress, impact_progress + 0.001), visual_progress)
			material.set_shader_parameter("wave_opacity", clampf(time_progress / 0.08, 0.0, 1.0) * (1.0 - dissolve))
	if visual_progress + 0.0001 >= impact_progress:
		_emit_impact_once(effect_root, impact_callback)


static func _emit_impact_once(effect_root: Node2D, impact_callback: Callable) -> void:
	if not is_instance_valid(effect_root) or bool(effect_root.get_meta("impact_emitted", false)):
		return
	effect_root.set_meta("impact_emitted", true)
	if impact_callback.is_valid():
		impact_callback.call()


static func set_flight_speed(effect_root: Node, speed_scale: float) -> void:
	if not is_flight_root(effect_root):
		return
	var tween := effect_root.get_meta("flight_tween", null) as Tween
	if tween != null and tween.is_valid():
		tween.set_speed_scale(clampf(speed_scale, 0.01, 3.0))


static func set_flight_paused(effect_root: Node, paused: bool) -> void:
	if not is_flight_root(effect_root):
		return
	var tween := effect_root.get_meta("flight_tween", null) as Tween
	if tween == null or not tween.is_valid():
		return
	if paused:
		tween.pause()
	else:
		tween.play()


static func is_flight_root(effect_root: Node) -> bool:
	return is_instance_valid(effect_root) and effect_root.has_meta("flight_tween")


static func sample_curve(
	control_points: PackedVector2Array,
	profile: Dictionary
) -> PackedVector2Array:
	var start := control_points[0]
	var finish := control_points[-1]
	var direct_delta := finish - start
	if direct_delta.length() < 1.0:
		return PackedVector2Array([start, finish])
	var direction := direct_delta.normalized()
	# 灵魂光带的尾迹被终点吸收，路径必须精确结束在目标中心。
	var end_padding := 0.0 if profile["mask_kind"] == &"soul_ribbon" else float(profile["end_padding"])
	start -= direction * end_padding
	finish += direction * end_padding
	var control := (start + finish) * 0.5
	if control_points.size() >= 3:
		control = control_points[1]
	else:
		var normal := Vector2(-direction.y, direction.x)
		var is_soul: bool = profile["mask_kind"] == &"soul_ribbon"
		# 光带把控制点靠近发射端，形成先弯出、再向目标拉长的轮廓。
		if is_soul:
			control = start.lerp(finish, 0.20)
		var maximum_arc := direct_delta.length() * (0.65 if is_soul else 0.32)
		control += normal * clampf(float(profile["arc_height"]), -maximum_arc, maximum_arc)
	var segment_count := maxi(roundi(float(profile["curve_segments"])), 4)
	var sampled := PackedVector2Array()
	for sample_index: int in range(segment_count + 1):
		var t := float(sample_index) / float(segment_count)
		var inverse_t := 1.0 - t
		sampled.append(
			inverse_t * inverse_t * start
			+ 2.0 * inverse_t * t * control
			+ t * t * finish
		)
	return sampled


static func polyline_length(points: PackedVector2Array) -> float:
	var result := 0.0
	for point_index: int in range(1, points.size()):
		result += points[point_index - 1].distance_to(points[point_index])
	return result


static func nearest_polyline_progress(points: PackedVector2Array, target: Vector2) -> float:
	## 返回目标点在实际采样路径上的累计长度比例，使数值命中与可见弹头重合。
	var total := polyline_length(points)
	if points.size() < 2 or total <= 0.0:
		return 1.0
	var traversed := 0.0
	var best_distance := INF
	var best_length := total
	for index: int in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var delta := finish - start
		var segment_length := delta.length()
		if segment_length <= 0.0:
			continue
		var t := clampf((target - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
		var projected := start + delta * t
		var distance := projected.distance_squared_to(target)
		if distance < best_distance:
			best_distance = distance
			best_length = traversed + segment_length * t
		traversed += segment_length
	return clampf(best_length / total, 0.0, 1.0)


static func build_ribbon(path_points: PackedVector2Array, ribbon_height: float) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var texture_uvs := PackedVector2Array()
	var distances: Array[float] = [0.0]
	for point_index: int in range(1, path_points.size()):
		distances.append(distances[-1] + path_points[point_index - 1].distance_to(path_points[point_index]))
	var total_length := maxf(distances[-1], 1.0)
	for point_index: int in path_points.size():
		var previous := path_points[maxi(point_index - 1, 0)]
		var following := path_points[mini(point_index + 1, path_points.size() - 1)]
		var tangent := (following - previous).normalized()
		if tangent.is_zero_approx():
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x)
		var half_width := normal * ribbon_height * 0.5
		var uv_x := distances[point_index] / total_length
		vertices.append(path_points[point_index] - half_width)
		vertices.append(path_points[point_index] + half_width)
		texture_uvs.append(Vector2(uv_x, 0.0))
		texture_uvs.append(Vector2(uv_x, 1.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return ribbon


static func get_mask_texture(mask_kind: StringName) -> Texture2D:
	return BATTLE_TRAIL_PROJECTILE_TEXTURE if mask_kind == &"projectile" else BATTLE_TRAIL_ENERGY_TEXTURE
