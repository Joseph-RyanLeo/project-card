class_name BattleAttackTrailRenderer
extends RefCounted

## 根据统一配置生成曲线路径、带状网格和 ShaderMaterial。
## 正式战斗与调试器都调用 play()，避免预览效果与实战实现分叉。

const BATTLE_ENERGY_BEAM_SHADER: Shader = preload("res://shaders/battle_energy_beam.gdshader")
const BATTLE_TRAIL_ENERGY_TEXTURE: Texture2D = preload("res://assets/effects/battle_trail_energy.png")
const BATTLE_TRAIL_PROJECTILE_TEXTURE: Texture2D = preload("res://assets/effects/battle_trail_projectile.png")

enum TravelSpeedVariant {
	FAST_THEN_SLOW,
	ACCELERATE_THEN_SLOW,
	SLOW_THEN_FAST,
}

const TRAVEL_SPEED_VARIANT_COUNT: int = 3


static func play(
	parent: CanvasItem,
	control_points: PackedVector2Array,
	profile: Dictionary,
	head_color: Color,
	tail_color: Color
) -> Node2D:
	if not is_instance_valid(parent) or control_points.size() < 2:
		return null
	var path_points := sample_curve(control_points, profile)
	if polyline_length(path_points) < 1.0:
		return null
	var effect_root := Node2D.new()
	effect_root.name = "ElementEnergyBeam"
	parent.add_child(effect_root)
	var beam_mesh := MeshInstance2D.new()
	beam_mesh.name = "BeamMesh"
	beam_mesh.mesh = build_ribbon(path_points, float(profile["beam_height"]))
	var material := ShaderMaterial.new()
	material.shader = BATTLE_ENERGY_BEAM_SHADER
	var mask_kind := profile["mask_kind"] as StringName
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
	var speed_variant := randi_range(0, TRAVEL_SPEED_VARIANT_COUNT - 1)
	var terminal_progress := (
		1.0
		+ float(profile["trail_length"])
		+ float(profile["trail_softness"])
	)
	effect_root.set_meta("travel_speed_variant", speed_variant)
	var tween := effect_root.create_tween()
	tween.tween_method(
		_apply_travel_progress.bind(
			material,
			terminal_progress,
			speed_variant,
			float(profile.get("speed_variation_strength", 0.78))
		),
		0.0,
		1.0,
		float(profile["duration"])
	)
	tween.tween_callback(effect_root.queue_free)
	return effect_root


static func remap_travel_progress(
	time_progress: float,
	speed_variant: int,
	variation_strength: float
) -> float:
	## 三条曲线都是速度函数积分后的累计位移：首尾固定为 0/1，
	## 因此改变的是飞行过程中的瞬时速度，而不是配置的总播放时间。
	var t := clampf(time_progress, 0.0, 1.0)
	var shaped_progress := t
	match speed_variant:
		TravelSpeedVariant.FAST_THEN_SLOW:
			# 速度峰值靠前：12t(1-t)^2 的积分。
			shaped_progress = 6.0 * t * t - 8.0 * pow(t, 3.0) + 3.0 * pow(t, 4.0)
		TravelSpeedVariant.ACCELERATE_THEN_SLOW:
			# 速度峰值在中间：30t^2(1-t)^2 的积分。
			shaped_progress = 10.0 * pow(t, 3.0) - 15.0 * pow(t, 4.0) + 6.0 * pow(t, 5.0)
		TravelSpeedVariant.SLOW_THEN_FAST:
			# 速度峰值靠后：12t^2(1-t) 的积分。
			shaped_progress = 4.0 * pow(t, 3.0) - 3.0 * pow(t, 4.0)
		_:
			shaped_progress = t
	return lerpf(t, shaped_progress, clampf(variation_strength, 0.0, 1.0))


static func _apply_travel_progress(
	time_progress: float,
	material: ShaderMaterial,
	terminal_progress: float,
	speed_variant: int,
	variation_strength: float
) -> void:
	if not is_instance_valid(material):
		return
	material.set_shader_parameter(
		"travel_progress",
		remap_travel_progress(time_progress, speed_variant, variation_strength)
		* terminal_progress
	)


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
	var end_padding := float(profile["end_padding"])
	start -= direction * end_padding
	finish += direction * end_padding
	var control := (start + finish) * 0.5
	if control_points.size() >= 3:
		control = control_points[1]
	else:
		var normal := Vector2(-direction.y, direction.x)
		var maximum_arc := direct_delta.length() * 0.32
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
