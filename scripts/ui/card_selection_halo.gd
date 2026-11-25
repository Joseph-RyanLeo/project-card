extends Control

## 高光在卡面本地坐标中绘制，进入检视合成画布后与整张卡一起透视。
const FocusOutline = preload("res://scripts/ui/focus_outline.gd")
const SPEED := 70.0 # 环绕光点每秒移动的逻辑像素距离
const TRAIL_LENGTH := 16 # 每束光的像素尾迹长度
var selected := false
var _mask: Texture2D
var _curves: Array[Curve2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100 # 高光处于卡面、图标之上
	set_process(selected)

func set_selected(value: bool) -> void:
	if value == selected: return
	selected = value
	_mask = null
	set_process(selected)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _refresh_contours() -> void:
	var shape := FocusOutline.card_mask(get_parent() as Control)
	if shape.is_empty() or shape.texture == _mask: return
	_mask = shape.texture
	_curves.clear()
	var image := _mask.get_image()
	var bits := BitMap.new()
	bits.create_from_image_alpha(image)
	var bounds: Rect2 = shape.bounds
	for points: PackedVector2Array in bits.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 0.3):
		var curve := Curve2D.new()
		curve.bake_interval = 1.0 # 按原生像素走角标轮廓，拐角不抄近路
		for point: Vector2 in points: curve.add_point(point + bounds.position)
		curve.add_point(curve.get_point_position(0))
		_curves.append(curve)

func _draw() -> void:
	if not selected: return
	if _mask == null: _refresh_contours()
	# 原卡与共享合成副本读同一时钟，悬停交接时尾迹不会跳到另一位置。
	var elapsed := Time.get_ticks_msec() / 1000.0
	for curve: Curve2D in _curves:
		draw_polyline(curve.get_baked_points(), Color(1.0, 0.74, 0.3, 0.5), 1.0)
		var length := curve.get_baked_length()
		if length <= 0.0: continue
		for beam: int in (2 if length > 80.0 else 1):
			for step: int in mini(TRAIL_LENGTH, ceili(length * 0.25)):
				var along := fposmod(elapsed * SPEED + beam * length * 0.5 - step * 2.0, length)
				var at := curve.sample_baked(along).floor()
				draw_rect(Rect2(at - Vector2.ONE, Vector2(2, 2)), Color(1.0, 0.9, 0.55, 1.0 - float(step) / TRAIL_LENGTH))
