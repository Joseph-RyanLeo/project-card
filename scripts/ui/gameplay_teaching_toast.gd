extends Control

## 非必要教学通知：不暂停游戏；只把条目编号交给Esc菜单，不负责存档。
signal entry_requested(key: String)

const Style = preload("res://scripts/ui/menu_style.gd")
const TOAST_SIZE := Vector2(420, 64) # 长条通知的整体尺寸
const TOAST_POSITION := Vector2(28, 82) # 避开左上角Esc按钮和左下角对白头像
const ICON_SIDE: float = 64.0 # 感叹号与四边倒计时的正方形边长
const DEFAULT_SECONDS: float = 8.0 # 一条非必要教学通知的默认停留时长
const PROGRESS_WIDTH: float = 3.0 # 正方形周长进度条粗细
const EDGE_INSET: float = 3.0 # 进度线距图标边缘的距离
const APPEAR_SECONDS: float = 0.12 # 入场放大到峰值并渐显的时长
const PEAK_HOLD_SECONDS: float = 0.04 # 入场和退场在峰值尺寸停顿的时长
const SETTLE_SECONDS: float = 0.08 # 入场从峰值回到正常大小的时长
const EXIT_GROW_SECONDS: float = 0.07 # 退场前从正常大小放大到峰值的时长
const DISAPPEAR_SECONDS: float = 0.13 # 退场从峰值缩小并渐隐的时长
const RESTING_SCALE: float = 0.78 # 入场起点和退场终点的缩放比例
const PEAK_SCALE: float = 1.12 # 超过正常大小时的峰值缩放比例
const HOVER_SCALE: float = 1.05 # 鼠标指向提示条时的缩放比例
const HOVER_SECONDS: float = 0.09 # 悬停尺寸与正常尺寸之间完整过渡的时长

var progress: float = 0.0
var current_key: String = ""
var _button: Button
var title_label: Label
var _remaining: float
var _duration: float
var _queue: Array[Dictionary] = []
var _motion: Tween
var _run_while_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = TOAST_POSITION
	size = TOAST_SIZE
	pivot_offset = Vector2(ICON_SIDE * 0.5, size.y * 0.5)
	theme = Style.make_theme()
	var background := Panel.new()
	background.size = size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", Style.panel(Color("17232fee"), Color("8a7453")))
	add_child(background)
	_button = Button.new()
	_button.name = "TeachingToastButton"
	_button.size = size
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_button.pressed.connect(_activate)
	_button.draw.connect(_draw_progress)
	add_child(_button)
	var icon := Label.new()
	icon.size = Vector2.ONE * ICON_SIDE
	icon.text = "!"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 36) # 感叹号字号
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(icon)
	var category := Label.new()
	category.position = Vector2(80, 7)
	category.text = "玩法教学"
	category.add_theme_font_size_override("font_size", 13) # 通知类别的小字号
	category.add_theme_color_override("font_color", Color("b0a28c"))
	category.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(category)
	title_label = Label.new()
	title_label.position = Vector2(80, 25)
	title_label.size = Vector2(324, 32)
	title_label.add_theme_font_size_override("font_size", 20) # 教学标题字号
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(title_label)
	hide()


func notify(key: String, title: String, seconds: float = DEFAULT_SECONDS, run_while_paused: bool = false) -> void:
	if key.is_empty() or key == current_key: return
	for entry: Dictionary in _queue:
		if entry.key == key: return
	_queue.append({"key": key, "title": title, "seconds": maxf(seconds, 0.1), "run_while_paused": run_while_paused})
	if current_key.is_empty(): _next()


func _next() -> void:
	if _motion != null and _motion.is_valid(): _motion.kill()
	if _queue.is_empty():
		current_key = ""
		hide()
		return
	var entry: Dictionary = _queue.pop_front()
	current_key = entry.key
	_run_while_paused = entry.run_while_paused
	title_label.text = entry.title
	_button.tooltip_text = "打开玩法教学：%s" % entry.title
	_button.disabled = false
	_duration = entry.seconds
	_remaining = _duration
	progress = 0.0
	_button.queue_redraw()
	scale = Vector2.ONE * RESTING_SCALE
	modulate.a = 0.0
	show()
	_motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_motion.tween_property(self, "scale", Vector2.ONE * PEAK_SCALE, APPEAR_SECONDS).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "modulate:a", 1.0, APPEAR_SECONDS)
	_motion.chain().tween_interval(PEAK_HOLD_SECONDS)
	_motion.chain().tween_property(self, "scale", Vector2.ONE, SETTLE_SECONDS).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if current_key.is_empty(): return
	var menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	var menu_open: bool = menu != null and menu.is_menu_open()
	visible = not menu_open
	var suspended := (get_tree().paused and not _run_while_paused) or not is_visible_in_tree()
	if _motion != null and _motion.is_valid():
		_motion.set_speed_scale(0.0 if suspended else 1.0)
		return
	if suspended or _remaining <= 0.0: return
	_remaining = maxf(0.0, _remaining - delta)
	progress = 1.0 - _remaining / _duration
	_button.queue_redraw()
	if _remaining <= 0.0:
		_button.disabled = true
		_motion = create_tween().set_trans(Tween.TRANS_SINE)
		_motion.tween_property(self, "scale", Vector2.ONE * PEAK_SCALE, EXIT_GROW_SECONDS).set_ease(Tween.EASE_OUT)
		_motion.tween_interval(PEAK_HOLD_SECONDS)
		_motion.tween_property(self, "scale", Vector2.ONE * RESTING_SCALE, DISAPPEAR_SECONDS).set_ease(Tween.EASE_IN)
		_motion.parallel().tween_property(self, "modulate:a", 0.0, DISAPPEAR_SECONDS)
		_motion.finished.connect(_next)
		return
	# 只在计时阶段更新悬停尺寸，入退场动画独占缩放，退场从当前尺寸接续。
	var target_scale := HOVER_SCALE if _button.is_hovered() else 1.0
	var hover_scale := move_toward(scale.x, target_scale, (HOVER_SCALE - 1.0) * delta / HOVER_SECONDS)
	scale = Vector2.ONE * hover_scale


func _draw_progress() -> void:
	# 沿左上→右上→右下→左下→左上走过四条边；小数部分绘制当前边。
	var edge := ICON_SIDE - EDGE_INSET * 2.0
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(edge, 0), Vector2(edge, edge), Vector2(0, edge), Vector2.ZERO])
	var steps := progress * 4.0
	for index: int in 4:
		var start := corners[index] + Vector2.ONE * EDGE_INSET
		var end := corners[index + 1] + Vector2.ONE * EDGE_INSET
		_button.draw_line(start, end, Color("5e5649"), PROGRESS_WIDTH)
		if steps > index:
			_button.draw_line(start, start.lerp(end, minf(1.0, steps - index)), Style.GOLD, PROGRESS_WIDTH)


func _activate() -> void:
	if current_key.is_empty() or _remaining <= 0.0: return
	var key := current_key
	_next()
	entry_requested.emit(key)
