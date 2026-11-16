extends Control

## 只展示包装与轨迹，不创建本局卡牌；演出直接复用正式入场函数。
signal points_changed
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const Arrival = preload("res://scripts/ui/pack_arrival_animation.gd")
static var FONT: Font = preload("res://scripts/ui/ui_typography.gd").font()
const CANVAS_SIZE := Vector2(1280, 720) # 与正式游戏相同的坐标画布
const HANDLE_RADIUS: float = 16.0 # 路线点的鼠标拖动命中半径
const GRAPH := Rect2(870, 535, 360, 130) # 滑行速度曲线在预览右下角的区域
const POINT_COLORS := [Color("77bfff"), Color("ffd17d"), Color("8cdea1")] # 起点、着地点与停止点的标记颜色
var package: TextureButton
var motion: Tween
var texture: Texture2D
var _drag_point := ""
var _guides: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = CANVAS_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	package = TextureButton.new()
	package.name = "ArrivalPreviewPack"
	package.texture_normal = texture
	package.size = texture.get_size()
	package.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	package.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(package)
	_guides = Control.new()
	_guides.size = CANVAS_SIZE
	_guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guides.draw.connect(_draw_guides)
	add_child(_guides)
	refresh()


func refresh() -> void:
	queue_redraw()
	if is_instance_valid(_guides): _guides.queue_redraw()


func replay() -> void:
	stop()
	motion = Arrival.play(package, self, Settings.get_values())
	refresh()


func stop() -> void:
	if is_instance_valid(motion): motion.kill()
	for child: Node in get_children():
		if child.get_script() == preload("res://scripts/ui/event_landing_dust.gd"): child.queue_free()


func _handle_at(key: String) -> Vector2:
	return Arrival.point(Settings.get_values(), key).clamp(Vector2.ONE * HANDLE_RADIUS, CANVAS_SIZE - Vector2.ONE * HANDLE_RADIUS)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag_point = ""
			return
		for key: String in ["start", "contact", "end"]:
			if event.position.distance_to(_handle_at(key)) <= HANDLE_RADIUS * 1.5:
				_drag_point = key
				stop()
				accept_event()
				return
	elif event is InputEventMouseMotion and not _drag_point.is_empty():
		Settings.set_value("arrival_" + _drag_point + "_x", event.position.x)
		Settings.set_value("arrival_" + _drag_point + "_y", event.position.y)
		points_changed.emit()
		refresh()
		accept_event()


func _draw() -> void:
	var dim: float = Settings.get_values().arrival_dim
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color("4d586a").darkened(dim))
	for x: int in range(0, 1281, 80): draw_line(Vector2(x, 0), Vector2(x, 720), Color("637086").darkened(dim))
	for y: int in range(0, 721, 80): draw_line(Vector2(0, y), Vector2(1280, y), Color("637086").darkened(dim))


func _draw_guides() -> void:
	var values := Settings.get_values()
	var start := Arrival.point(values, "start")
	var contact := Arrival.point(values, "contact")
	var end := Arrival.point(values, "end")
	var previous := start
	for index: int in range(1, 65):
		var next := Arrival.flight_point(start, contact, float(index) / 64, values.arrival_arc_height)
		_guides.draw_line(previous, next, POINT_COLORS[0], 3.0)
		previous = next
	_guides.draw_line(contact, end, POINT_COLORS[2], 3.0)
	for index: int in 3:
		var key: String = ["start", "contact", "end"][index]
		var label: String = ["起点", "着地点", "停止点"][index]
		var at := _handle_at(key)
		_guides.draw_arc(at, HANDLE_RADIUS, 0, TAU, 24, POINT_COLORS[index], 3.0)
		_guides.draw_circle(at, 4.0, POINT_COLORS[index])
		_guides.draw_string(FONT, at + Vector2(22, -12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, POINT_COLORS[index])
	_draw_speed_graph(values)
	var seconds := Arrival.timing(values)
	_guides.draw_string(FONT, Vector2(24, 38), "拖动三个路线点，改数值后点「重播」；X向右，Y向下", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("eee0c5"))
	_guides.draw_string(FONT, Vector2(24, 690), "飞入约%.2f秒　滑行约%.2f秒　减速曲线：%.1f" % [seconds.x, seconds.y, values.arrival_slide_power], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("eee0c5"))


func _draw_speed_graph(values: Dictionary) -> void:
	_guides.draw_rect(GRAPH.grow(14), Color("141c25"))
	var previous := GRAPH.position
	for index: int in range(65):
		var time := float(index) / 64
		var speed := Arrival.speed_ratio(time, values.arrival_slide_power)
		var at := GRAPH.position + Vector2(time * GRAPH.size.x, (1.0 - speed) * GRAPH.size.y)
		if index > 0: _guides.draw_line(previous, at, Color("ffcf81"), 3.0)
		previous = at
	_guides.draw_string(FONT, GRAPH.position - Vector2(0, 24), "滑行速度：左=开始　右=停止", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffcf81"))
	_guides.draw_string(FONT, GRAPH.position + Vector2(8, 24), "%.0f px/s" % values.arrival_slide_speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b8c5d3"))
	_guides.draw_string(FONT, GRAPH.position + Vector2(0, GRAPH.size.y + 25), "2=匀减速；越大尾段越长", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b8c5d3"))
