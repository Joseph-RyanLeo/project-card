extends Control

## 对照视频的一次性环状烟尘：程序烟团与细小亮点共用独立视觉时间。
const LIFE_SECONDS: float = 1.16 # 扬尘、扩散和破碎消散的总时长
const EFFECT_SIZE := Vector2(326, 276) # 烟尘绘制范围，含卡牌四周的扩散空间
const SPARK_COUNT: int = 28 # 落位后沿周边散开的细小亮点数量
var elapsed: float = 0.0
var _smoke: ColorRect

func _ready() -> void:
	name = "EventLandingDust"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = EFFECT_SIZE
	_smoke = ColorRect.new()
	_smoke.size = EFFECT_SIZE
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://shaders/event_landing_dust.gdshader")
	_smoke.material = shader
	add_child(_smoke)

func _process(delta: float) -> void:
	elapsed += delta
	(_smoke.material as ShaderMaterial).set_shader_parameter("progress", elapsed / LIFE_SECONDS)
	queue_redraw()
	if elapsed >= LIFE_SECONDS: queue_free()

func _draw() -> void:
	var t := clampf(elapsed / LIFE_SECONDS, 0.0, 1.0)
	for index: int in SPARK_COUNT:
		var angle := TAU * float(index) / SPARK_COUNT + sin(float(index) * 3.7) * 0.12
		var direction := Vector2(cos(angle), sin(angle))
		var distance := (1.0 - pow(1.0 - t, 2.0)) * (22.0 + fposmod(float(index) * 17.1, 31.0))
		var point := EFFECT_SIZE * 0.5 + direction * (Vector2(86, 72) + Vector2.ONE * distance) + Vector2(0, -t * 12)
		var alpha := sin(PI * minf(1.0, t * 2.0)) * (1.0 - t) if index % 3 == 0 else pow(1.0 - t, 1.5)
		draw_rect(Rect2(point.round(), Vector2.ONE), Color(0.88, 0.78, 0.48, alpha * 0.72))
