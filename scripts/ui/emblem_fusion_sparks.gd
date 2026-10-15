extends Control

## 融合揭晓时的两枚像素十字闪点，不使用覆盖卡面的大片白光。
const START_DISTANCE := 64.0 # 闪点开始时距合成中心的水平距离
const SPREAD_DISTANCE := 26.0 # 闪点消散时向两侧飘出的距离
const START_HEIGHT := 48.0 # 闪点开始时在合成中心上方的高度
const RISE_DISTANCE := 18.0 # 闪点消散时继续上浮的距离
const CROSS_LENGTH := 8.0 # 十字闪点两条笔画的长度
const CROSS_WIDTH := 2.0 # 十字闪点笔画的宽度
var _progress := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_progress(value: float) -> void:
	_progress = value
	queue_redraw()

func _draw() -> void:
	if _progress >= 1.0:
		return
	var color := Color(1, 1, 1, 1.0 - _progress)
	for direction: float in [-1.0, 1.0]:
		var center := Vector2(direction * (START_DISTANCE + SPREAD_DISTANCE * _progress), -START_HEIGHT - RISE_DISTANCE * _progress).round()
		draw_rect(Rect2(center - Vector2(CROSS_LENGTH, CROSS_WIDTH) * 0.5, Vector2(CROSS_LENGTH, CROSS_WIDTH)), color)
		draw_rect(Rect2(center - Vector2(CROSS_WIDTH, CROSS_LENGTH) * 0.5, Vector2(CROSS_WIDTH, CROSS_LENGTH)), color)
