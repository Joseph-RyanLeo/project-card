extends Control

## 确定性的2D像素光束；不读取游戏随机源，也不需要3D或额外位图。
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
var effects: Dictionary = Settings.get_values()
var origin := Vector2.ZERO
var strength := 0.0
var elapsed := 0.0
var rare := false
var card_reveal := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	if strength <= 0.0:
		return
	var pixel: float = effects.pixel
	var gold := Color(effects.gold_r / 255.0, effects.gold_g / 255.0, effects.gold_b / 255.0)
	var core := Color(effects.core_r / 255.0, effects.core_g / 255.0, effects.core_b / 255.0)
	var center := origin.snapped(Vector2.ONE * pixel)
	if card_reveal:
		var radius: float = effects.halo_radius * (1.0 - strength * (1.0 - effects.halo_start_ratio))
		for index: int in int(effects.halo_count):
			var angle := TAU * float(index) / maxf(1.0, effects.halo_count)
			var point := (center + Vector2.from_angle(angle) * radius).snapped(Vector2.ONE * pixel)
			draw_rect(Rect2(point - Vector2.ONE * pixel * effects.halo_point_scale * 0.5, Vector2.ONE * pixel * effects.halo_point_scale), Color(gold, strength))
	else:
		var height: float = effects.beam_height if rare else effects.beam_height * effects.normal_height_ratio
		var width: float = effects.beam_width if rare else effects.beam_width * effects.normal_width_ratio
		if width > 0.0 and height > 0.0:
			for layer: int in range(int(effects.beam_layers), 0, -1):
				var half: float = width * float(layer) / effects.beam_layers
				var top := maxf(0.0, center.y - height)
				var points := PackedVector2Array([center + Vector2(-half * effects.beam_taper, 0), Vector2(center.x - half, top), Vector2(center.x + half, top), center + Vector2(half * effects.beam_taper, 0)])
				if is_zero_approx(effects.beam_taper): points.remove_at(3) # 零底宽绘为三角形，避免重复底部顶点
				draw_colored_polygon(points, Color(gold.lerp(core, 1.0 - float(layer) / effects.beam_layers), strength * (effects.beam_outer_alpha if layer > 1 else effects.beam_core_alpha)))
		for index: int in int(effects.particle_count):
			var phase := fmod(elapsed * effects.particle_speed + float(index) * effects.particle_spacing, 1.0)
			var x := sin(float(index) * effects.particle_spread) * width
			var point := (center + Vector2(x * phase, -phase * height)).snapped(Vector2.ONE * pixel)
			draw_rect(Rect2(point, Vector2.ONE * pixel), Color(core, strength * (1.0 - phase)))
	var flare: float = (effects.rare_flare_width if rare else effects.normal_flare_width) * strength
	draw_rect(Rect2(center - Vector2(flare, pixel), Vector2(flare * 2.0, pixel * 2.0)), Color(core, strength))
