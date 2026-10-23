extends Button

## 原生Button负责点击；图集状态机负责按住、回弹和取消，抖动只移动视觉层。
signal refresh_requested

enum Motion { IDLE, PRESS, HOLD, RELEASE, CANCEL }
const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
const SHEET = preload("res://assets/ui/shop_event_20261020/refresh_press.png")
const FRAME_SIZE := Vector2(83, 33) # GIF单帧原生大小，同时作为固定点击范围
const FRAME_SECONDS: float = 0.05 # 保留GIF每帧50毫秒的播放节奏
const FRAME_COUNT: int = 11 # GIF完整按下与回弹的帧数
const HOLD_FRAME: int = 2 # 从零计数的第三帧；按住时停在这里
const CONTENT_Y: Array[int] = [0, 1, 2, 2, -1, -2, -1, 0, 0, 0, 0] # 原GIF按钮面逐帧位移；文字与金额同步下压和回弹
const SHAKE_DEGREES: float = 1.5 # 每次重新指向按钮时抖动的最大角度
const SHAKE_STEP_SECONDS: float = 0.045 # 指向抖动每次左右摆动的时长

var _motion := Motion.IDLE
var _frame := 0
var _elapsed := 0.0
var _held := false
var _cancelled := false
var _visual: TextureRect
var _caption: Label
var _cost: RuneNumber
var _atlas: AtlasTexture
var _shake: Tween

func _ready() -> void:
	size = FRAME_SIZE
	custom_minimum_size = FRAME_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_font_override("font", preload("res://assets/fonts/chill_7.ttf"))
	add_theme_font_size_override("font_size", 14) # 隐藏的原生Button文字也保持14像素，避免撑大点击区域
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_atlas = AtlasTexture.new()
	_atlas.atlas = SHEET
	_atlas.region = Rect2(Vector2.ZERO, FRAME_SIZE)
	_visual = TextureRect.new()
	_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visual.texture = _atlas
	_visual.size = FRAME_SIZE
	_visual.pivot_offset = FRAME_SIZE * 0.5
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)
	_caption = Label.new()
	_caption.position = Vector2(24, 0) # 文字避开左侧刷新图标，固定在按钮右侧
	_caption.size = Vector2(FRAME_SIZE.x - 24, FRAME_SIZE.y)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", preload("res://assets/fonts/chill_7.ttf"))
	_caption.add_theme_font_size_override("font_size", 14) # 刷新文字及费用的原生字号
	_caption.add_theme_color_override("font_color", Color("ead2ae"))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_caption)
	_cost = RuneNumber.new()
	_visual.add_child(_cost)
	set_caption(text)
	mouse_entered.connect(_hover)
	mouse_exited.connect(_exit_hover)
	pressed.connect(_activate)

func set_caption(value: String) -> void:
	text = value
	if not is_instance_valid(_caption): return
	_caption.text = "刷新"
	_cost.text = value.trim_prefix("刷新")
	var content_width := 28 + 3 + _cost.size.x
	_caption.position.x = roundf(24 + (FRAME_SIZE.x - 24 - content_width) * 0.5) # 刷新二字与金额整体居中在按钮图标右侧
	_caption.size.x = 28
	_cost.position.x = _caption.position.x + 31 # 大卢恩费用紧随刷新二字
	_set_frame(_frame)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not disabled:
		_held = true
		_cancelled = false
		_motion = Motion.PRESS
		_elapsed = 0.0
		_set_frame(0)

func _input(event: InputEvent) -> void:
	# 监听本次按压的松手，即使鼠标已经离开Button也能收尾，不消费其他界面的输入。
	if not _held or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	_held = false
	if not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		if not _cancelled: _cancel_press()
	elif not _cancelled and _motion == Motion.HOLD:
		_motion = Motion.RELEASE
		_elapsed = 0.0

func _activate() -> void:
	if _cancelled or disabled: return
	if _motion == Motion.IDLE:
		_motion = Motion.PRESS
		_elapsed = 0.0
	refresh_requested.emit()

func _hover() -> void:
	if disabled: return
	if is_instance_valid(_shake): _shake.kill()
	_visual.rotation = 0.0
	_shake = create_tween()
	for angle: float in [SHAKE_DEGREES, -SHAKE_DEGREES, SHAKE_DEGREES * 0.5, 0.0]:
		_shake.tween_property(_visual, "rotation", deg_to_rad(angle), SHAKE_STEP_SECONDS)

func _exit_hover() -> void:
	if _held and not _cancelled: _cancel_press()

func _cancel_press() -> void:
	_cancelled = true
	_motion = Motion.CANCEL
	_elapsed = 0.0
	_set_frame(HOLD_FRAME)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if disabled and _held and not _cancelled: _cancel_press()
	if _motion == Motion.IDLE or _motion == Motion.HOLD: return
	_elapsed += delta
	while _elapsed >= FRAME_SECONDS:
		_elapsed -= FRAME_SECONDS
		match _motion:
			Motion.PRESS:
				_set_frame(_frame + 1)
				if _frame == HOLD_FRAME:
					_motion = Motion.HOLD if _held else Motion.RELEASE
					if _held:
						_elapsed = 0.0
						break
			Motion.RELEASE:
				if _frame < FRAME_COUNT - 1: _set_frame(_frame + 1)
				else:
					_motion = Motion.IDLE
					_set_frame(0)
					break
			Motion.CANCEL:
				_set_frame(_frame - 1)
				if _frame == 0:
					_motion = Motion.IDLE
					break

func _set_frame(value: int) -> void:
	_frame = value
	_atlas.region = Rect2(Vector2(0, value * FRAME_SIZE.y), FRAME_SIZE)
	_caption.position.y = CONTENT_Y[value]
	_cost.position.y = 10 + CONTENT_Y[value] # 金额基准y10，保持原生14像素数字垂直居中

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_instance_valid(_visual) and not is_visible_in_tree():
		_held = false
		_cancelled = true
		_motion = Motion.IDLE
		_elapsed = 0.0
		_set_frame(0)
		if is_instance_valid(_shake): _shake.kill()
		_visual.rotation = 0.0
