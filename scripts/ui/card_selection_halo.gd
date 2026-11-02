extends Control

## 高光在卡面本地坐标中绘制，进入检视合成画布后与整张卡一起透视。
const MARGIN := 5.0 # 金光与卡牌边缘的距离
const SPEED := 70.0 # 环绕光点每秒移动的逻辑像素距离
const TRAIL_LENGTH := 16 # 每束光的像素尾迹长度
var selected := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100 # 高光处于卡面、图标之上
	set_process(selected)

func set_selected(value: bool) -> void:
	selected = value
	set_process(selected)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _edge_point(distance: float, rect: Rect2) -> Vector2:
	var p := fposmod(distance, 2.0 * (rect.size.x + rect.size.y))
	if p < rect.size.x: return rect.position + Vector2(p, 0)
	p -= rect.size.x
	if p < rect.size.y: return rect.position + Vector2(rect.size.x, p)
	p -= rect.size.y
	if p < rect.size.x: return rect.end - Vector2(p, 0)
	return rect.position + Vector2(0, rect.size.y - (p - rect.size.x))

func _draw() -> void:
	if not selected: return
	var frame := Rect2(Vector2.ZERO, size).grow(MARGIN)
	draw_rect(frame, Color(1.0, 0.74, 0.3, 0.5), false, 1.0)
	var perimeter := 2.0 * (frame.size.x + frame.size.y)
	# 原卡与共享合成副本读同一时钟，悬停交接时尾迹不会跳到另一位置。
	var elapsed := Time.get_ticks_msec() / 1000.0
	for beam: int in 2:
		for step: int in TRAIL_LENGTH:
			var at := _edge_point(elapsed * SPEED + beam * perimeter * 0.5 - step * 2.0, frame).floor()
			draw_rect(Rect2(at - Vector2.ONE, Vector2(2, 2)), Color(1.0, 0.9, 0.55, 1.0 - float(step) / TRAIL_LENGTH))
