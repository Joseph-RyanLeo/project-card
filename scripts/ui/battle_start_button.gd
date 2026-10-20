extends Button

## 原生Button负责点击，独立显示层负责像素颤抖和压下，不移动鼠标命中范围。
const ART: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_start.png")
const PRESS_PIXELS: int = 3 # 按住时内部图案与文字向下压入的原生像素数
const PRESS_SECONDS: float = 0.06 # 按下到最深位置的时长
const RELEASE_SECONDS: float = 0.10 # 松开后回弹到原位置的时长
const SHAKE_PIXELS: float = 1.0 # 指向时显示层颤抖的最大原生像素幅度
const SHAKE_FREQUENCY: float = 38.0 # 指向时颤抖的角频率
const SHAKE_SECONDS: float = 0.24 # 每次鼠标进入只播放这一小段颤抖，结束后保持静止
const TEXT_LEFT: float = 26.0 # 双剑图标右侧的文字起点
const TEXT_RIGHT: float = 4.0 # 文字距右侧黑框的留白

var press_depth: float = 0.0:
	set(value):
		press_depth = clampf(value, 0.0, PRESS_PIXELS)
		if is_instance_valid(_face):
			var pixel_depth := roundi(press_depth)
			_face.texture = _frames[pixel_depth]
			_caption.position.y = pixel_depth

var _frames: Array[Texture2D] = []
var _visual: Control
var _face: TextureRect
var _caption: Label
var _hover_time: float = 0.0
var _press_tween: Tween


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var text_color := get_theme_color("font_color")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# 先去掉默认样式再设尺寸，否则Button会被主题的最小高度撑到31像素。
	size = ART.get_size()
	custom_minimum_size = size
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	_build_press_frames()
	_visual = Control.new()
	_visual.name = "ButtonVisual"
	_visual.size = ART.get_size()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)
	_face = TextureRect.new()
	_face.name = "ButtonArt"
	_face.texture = ART
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_face)
	_caption = Label.new()
	_caption.name = "ButtonCaption"
	_caption.text = text
	_caption.position = Vector2(TEXT_LEFT, 0)
	_caption.size = Vector2(size.x - TEXT_LEFT - TEXT_RIGHT, size.y)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", get_theme_font("font"))
	_caption.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	_caption.add_theme_color_override("font_color", text_color)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_caption)
	mouse_entered.connect(_on_hover_started)
	mouse_exited.connect(_reset_hover)
	button_down.connect(_animate_press.bind(float(PRESS_PIXELS), PRESS_SECONDS))
	button_up.connect(_animate_press.bind(0.0, RELEASE_SECONDS))
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func _build_press_frames() -> void:
	_frames.append(ART)
	var source := ART.get_image()
	for depth: int in range(1, PRESS_PIXELS + 1):
		var frame := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
		for y: int in source.get_height():
			for x: int in source.get_width():
				var original := source.get_pixel(x, y)
				if original == Color.BLACK and y > 0:
					frame.set_pixel(x, y, original) # 左右和底部黑框固定，挡住下沉图案
				elif original.a > 0.0 and y >= depth:
					var shifted := source.get_pixel(x, y - depth)
					if shifted != Color.BLACK or y == depth:
						frame.set_pixel(x, y, shifted)
		_frames.append(ImageTexture.create_from_image(frame))


func _on_hover_started() -> void:
	_hover_time = 0.0
	set_process(not disabled)


func _reset_hover() -> void:
	set_process(false)
	_hover_time = 0.0
	_visual.position = Vector2.ZERO


func _process(delta: float) -> void:
	if disabled or get_draw_mode() == BaseButton.DRAW_PRESSED:
		_reset_hover()
		return
	_hover_time += delta
	if _hover_time >= SHAKE_SECONDS:
		_reset_hover()
		return
	var amplitude := SHAKE_PIXELS * (1.0 - _hover_time / SHAKE_SECONDS)
	_visual.position = Vector2(
		roundf(sin(_hover_time * SHAKE_FREQUENCY) * amplitude),
		roundf(sin(_hover_time * SHAKE_FREQUENCY * 1.7) * amplitude)
	)


func _animate_press(target: float, duration: float) -> void:
	_reset_hover()
	if is_instance_valid(_press_tween):
		_press_tween.kill()
	_press_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(self, "press_depth", target, duration)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and is_instance_valid(_visual):
		_reset_hover()
		if is_instance_valid(_press_tween):
			_press_tween.kill()
		press_depth = 0.0
