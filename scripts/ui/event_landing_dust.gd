extends Control

## 一次性着地烟团，可沿卡包滑行路线扩散；普通事件不设置路线，保持环状。
const LIFE_SECONDS: float = 1.16 # 扬尘、扩散和破碎消散的总时长
const EFFECT_SIZE := Vector2(326, 276) # 烟尘绘制范围，含卡牌四周的扩散空间
const SPARK_COUNT: int = 28 # 落位后沿周边散开的细小亮点数量
const PUFF_SPACING: float = 105.0 # 沿途椭圆的采样间距，重叠处合并为同一个外轮廓
var directional_spread := Vector2.ZERO # 从着地点到烟尘前沿的位移，包含整段滑行及停止点外的余量
var slide_seconds: float = 0.0 # 由入场动画传入实际滑行时长，最后一团烟尘停稳后才开始消散
var slide_power: float = 2.0 # 与卡包共用的减速指数，烟团按卡包到达对应路段的时刻出现
var elapsed: float = 0.0
var _smoke: ColorRect
var _puff_count: int = 1

func _ready() -> void:
	name = "EventLandingDust"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = EFFECT_SIZE
	if not directional_spread.is_zero_approx():
		_puff_count = clampi(ceili(directional_spread.length() / PUFF_SPACING) + 1, 2, 12)
	_smoke = ColorRect.new()
	var before := Vector2(maxf(-directional_spread.x, 0.0), maxf(-directional_spread.y, 0.0))
	_smoke.position = -before
	_smoke.size = EFFECT_SIZE + directional_spread.abs()
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://shaders/event_landing_dust.gdshader")
	shader.set_shader_parameter("canvas_size", _smoke.size)
	shader.set_shader_parameter("canvas_origin", EFFECT_SIZE * 0.5 + before)
	shader.set_shader_parameter("directional_spread", directional_spread)
	shader.set_shader_parameter("slide_seconds", slide_seconds)
	shader.set_shader_parameter("slide_power", slide_power)
	shader.set_shader_parameter("puff_count", _puff_count)
	shader.set_shader_parameter("puff_life_seconds", LIFE_SECONDS)
	_smoke.material = shader
	add_child(_smoke)

func _process(delta: float) -> void:
	elapsed += delta
	(_smoke.material as ShaderMaterial).set_shader_parameter("progress", clampf(elapsed / LIFE_SECONDS, 0.0, 1.0))
	(_smoke.material as ShaderMaterial).set_shader_parameter("elapsed_seconds", elapsed)
	queue_redraw()
	if elapsed >= slide_seconds + LIFE_SECONDS: queue_free()

func _draw() -> void:
	for index: int in SPARK_COUNT:
		var fraction := float(index % _puff_count) / maxf(1.0, _puff_count - 1.0)
		var birth := slide_seconds * (1.0 - pow(1.0 - fraction, 1.0 / slide_power))
		var age := elapsed - birth
		if age <= 0.0 or age >= LIFE_SECONDS: continue
		var t := age / LIFE_SECONDS
		var angle := TAU * float(index) / SPARK_COUNT + sin(float(index) * 3.7) * 0.12
		var direction := Vector2(cos(angle), sin(angle))
		var distance := (1.0 - pow(1.0 - t, 2.0)) * (22.0 + fposmod(float(index) * 17.1, 31.0))
		var point := EFFECT_SIZE * 0.5 + direction * (Vector2(86, 72) + Vector2.ONE * distance) + Vector2(0, -t * 12)
		point += directional_spread * fraction
		var interior := false
		for other: int in _puff_count:
			if other == index % _puff_count: continue
			var other_fraction := float(other) / maxf(1.0, _puff_count - 1.0)
			var other_age := (elapsed - slide_seconds * (1.0 - pow(1.0 - other_fraction, 1.0 / slide_power))) / LIFE_SECONDS
			if other_age <= 0.0 or other_age >= 1.0: continue
			var other_center := EFFECT_SIZE * 0.5 + directional_spread * other_fraction - Vector2(0, other_age * 14.0)
			var radius := 0.95 + (1.0 - pow(1.0 - other_age, 3.0)) * 0.42
			if ((point - other_center) / Vector2(88, 73)).length() < radius - 0.1:
				interior = true
				break
		if interior: continue
		var alpha := sin(PI * minf(1.0, t * 2.0)) * (1.0 - t) if index % 3 == 0 else pow(1.0 - t, 1.5)
		draw_rect(Rect2(point.round(), Vector2.ONE), Color(0.88, 0.78, 0.48, alpha * 0.72))
