extends Control

## 一次性着地烟团，可沿卡包滑行路线扩散；普通事件不设置路线，保持环状。
const LIFE_SECONDS: float = 1.16 # 扬尘、扩散和破碎消散的总时长
const EFFECT_SIZE := Vector2(326, 276) # 烟尘绘制范围，含卡牌四周的扩散空间
const PUFF_RADIUS := Vector2(88, 73) # 烟圈扩散前的基准半径，与烟尘着色器一致
const SPARK_COUNT: int = 28 # 落位后沿周边散开的细小亮点数量
const PUFF_SPACING: float = 105.0 # 沿途椭圆的采样间距，重叠处合并为同一个外轮廓
const MAX_PUFFS: int = 12 # 与着色器烟团数组容量一致
const SMOKE_SHADER = preload("res://shaders/event_landing_dust.gdshader")
static var _shader_warmed := false
var directional_spread := Vector2.ZERO # 从着地点到烟尘前沿的位移，包含整段滑行及停止点外的余量
var slide_seconds: float = 0.0 # 由入场动画传入实际滑行时长，最后一团烟尘停稳后才开始消散
var slide_power: float = 2.0 # 与卡包共用的减速指数，烟团按卡包到达对应路段的时刻出现
var elapsed: float = 0.0
var dust_color := Color(0.49, 0.44, 0.35, 0.60) # 默认沿用事件牌烟尘的颜色和浓度
var _smoke: ColorRect
var _puff_count: int = 1
var _puff_offsets := PackedVector2Array()
var _puff_births := PackedFloat32Array()
var _puff_ages := PackedFloat32Array()
var _visible_puffs := PackedVector4Array()

static func warm_shader(canvas: Control) -> void:
	if _shader_warmed or DisplayServer.get_name() == "headless": return
	_shader_warmed = true
	# 真正绘制一个透明的小色块，让兼容渲染器在首屏编译同一份材质程序。
	var probe := ColorRect.new()
	probe.size = Vector2(2, 2) # 预热只覆盖首屏两个像素宽高
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
	probe.material = material
	canvas.add_child(probe)
	RenderingServer.frame_post_draw.connect(probe.queue_free, CONNECT_ONE_SHOT)

func _ready() -> void:
	name = "EventLandingDust"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = EFFECT_SIZE
	if not directional_spread.is_zero_approx():
		_puff_count = clampi(ceili(directional_spread.length() / PUFF_SPACING) + 1, 2, MAX_PUFFS)
	_puff_ages.resize(_puff_count)
	_visible_puffs.resize(MAX_PUFFS)
	# 滑行反函数和各段偏移只算一次，亮点和烟尘共用。
	for index: int in _puff_count:
		var fraction := float(index) / maxi(1, _puff_count - 1)
		_puff_offsets.append(directional_spread * fraction)
		_puff_births.append(slide_seconds * (1.0 - pow(1.0 - fraction, 1.0 / slide_power)))
	_smoke = ColorRect.new()
	var before := Vector2(maxf(-directional_spread.x, 0.0), maxf(-directional_spread.y, 0.0))
	_smoke.position = -before
	_smoke.size = EFFECT_SIZE + directional_spread.abs()
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := ShaderMaterial.new()
	shader.shader = SMOKE_SHADER
	shader.set_shader_parameter("dust_color", dust_color)
	shader.set_shader_parameter("canvas_size", _smoke.size)
	shader.set_shader_parameter("canvas_origin", EFFECT_SIZE * 0.5 + before)
	_smoke.material = shader
	add_child(_smoke)

func _process(delta: float) -> void:
	elapsed += delta
	var active_count := 0
	for index: int in _puff_count:
		var age := (elapsed - _puff_births[index]) / LIFE_SECONDS
		_puff_ages[index] = age
		if age <= 0.0 or age >= 1.0: continue
		var center := _puff_offsets[index] - Vector2(0, age * 14.0)
		var opacity := smoothstep(0.0, 0.06, age) * pow(1.0 - age, 0.65)
		_visible_puffs[active_count] = Vector4(center.x, center.y, age, opacity)
		active_count += 1
	var shader := _smoke.material as ShaderMaterial
	shader.set_shader_parameter("puff_count", active_count)
	if active_count > 0: shader.set_shader_parameter("puffs", _visible_puffs)
	queue_redraw()
	if elapsed >= slide_seconds + LIFE_SECONDS: queue_free()

func _draw() -> void:
	for index: int in SPARK_COUNT:
		var puff := index % _puff_count
		var t := _puff_ages[puff]
		if t <= 0.0 or t >= 1.0: continue
		var angle := TAU * float(index) / SPARK_COUNT + sin(float(index) * 3.7) * 0.12
		var direction := Vector2(cos(angle), sin(angle))
		var distance := (1.0 - pow(1.0 - t, 2.0)) * (22.0 + fposmod(float(index) * 17.1, 31.0))
		var point := EFFECT_SIZE * 0.5 + direction * (Vector2(86, 72) + Vector2.ONE * distance) + Vector2(0, -t * 12)
		point += _puff_offsets[puff]
		var interior := false
		for other: int in _puff_count:
			if other == puff: continue
			var other_age := _puff_ages[other]
			if other_age <= 0.0 or other_age >= 1.0: continue
			var other_center := EFFECT_SIZE * 0.5 + _puff_offsets[other] - Vector2(0, other_age * 14.0)
			var radius := 0.95 + (1.0 - pow(1.0 - other_age, 3.0)) * 0.42
			if ((point - other_center) / PUFF_RADIUS).length() < radius - 0.1:
				interior = true
				break
		if interior: continue
		var alpha := sin(PI * minf(1.0, t * 2.0)) * (1.0 - t) if index % 3 == 0 else pow(1.0 - t, 1.5)
		draw_rect(Rect2(point.round(), Vector2.ONE), Color(0.88, 0.78, 0.48, alpha * 0.72))
