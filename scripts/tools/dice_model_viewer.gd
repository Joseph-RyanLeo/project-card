extends Control

signal close_requested

enum PixelMode { NEAREST, SMOOTH, EDGE_AA }

const Style = preload("res://scripts/ui/menu_style.gd")
const DiceModel = preload("res://scripts/ui/dice_model.gd")
const EventDiceRoll = preload("res://scripts/ui/event_dice_roll.gd")
const PixelSmoothing = preload("res://shaders/dice_pixel_smoothing.gdshader")
const MODELS := {
	4: "正四面体",
	6: "立方体",
	8: "正八面体",
	10: "切角十面骰",
	12: "正十二面体",
	20: "正二十面体",
}
const DESIGN_SIZE := Vector2i(1280, 720) # 独立运行时使用与游戏相同的逻辑画幅
const DRAG_SPEED := 0.012 # 每拖动一个逻辑像素的旋转弧度
const ZOOM_STEP := 1.15 # 滚轮一格的缩放倍率
const MIN_ZOOM := 0.55 # 最小查看倍率
const MAX_ZOOM := 1.28 # 最大查看倍率，骰体仍留在视图内
const DEFAULT_ANGLES := Vector3(-0.46, 0.68, 0.14) # 默认观察角度，露出骰子的多块面
const DEFAULT_RADIUS := 156.0 # 查看器的默认骰体半径
const ROLL_SCALE := 2.35 # 将游戏演出的骰体和飞行距离一起放大到查看器里
const PIXEL_MAX := 12 # 滑块允许的最大像素块边长
const STAGE_COLOR := Color("1d2330") # 观察区的底色

var _model := DiceModel.new()
var _rotation := Basis.IDENTITY
var _zoom := 1.0
var _dragging := false
var _canvas: Control
var _model_title: Label
var _buttons: Dictionary = {}
var _viewport: SubViewport
var _texture: TextureRect
var _surface: Control
var _roll: EventDiceRoll
var _roll_button: Button
var _result_label: Label
var _pixel_label: Label
var _pixel_size := 1 # 默认以原分辨率显示
var _pixel_enabled := true
var _pixel_mode := PixelMode.NEAREST
var _smoothing_material := ShaderMaterial.new()
var _result := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if get_tree().current_scene == self:
		get_window().content_scale_size = DESIGN_SIZE
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	theme = Style.make_theme()
	Style.add_background(self)
	_add_label(self, "骰子模型查看器", Vector2(52, 42), 34)
	_add_label(self, "按住鼠标左键拖动旋转，滚轮缩放", Vector2(54, 88), 18)
	_add_button(self, "返回", "CloseDiceViewer", Vector2(1080, 52), Vector2(146, 46), _close)

	var menu := Panel.new()
	menu.position = Vector2(52, 136) # 骰种列表在左侧
	menu.size = Vector2(254, 530) # 容纳六种骰子和重置操作
	menu.add_theme_stylebox_override("panel", Style.panel(Color("18202b"), Color("6a594b")))
	add_child(menu)
	_add_label(menu, "选择骰子", Vector2(18, 16), 20)
	var group := ButtonGroup.new()
	var y := 58.0 # 第一个骰种按钮的纵坐标
	for sides: int in MODELS:
		var button := _add_button(menu, "D%d  %s" % [sides, MODELS[sides]], "ChooseD%d" % sides, Vector2(16, y), Vector2(222, 52), _select_model.bind(sides))
		button.toggle_mode = true
		button.button_group = group
		_buttons[sides] = button
		y += 61.0 # 骰种按钮高度与间距之和
	_add_button(menu, "重置视角", "ResetDiceView", Vector2(16, 454), Vector2(222, 54), _reset_view)

	var stage := Panel.new()
	stage.position = Vector2(330, 136) # 模型视图在右侧
	stage.size = Vector2(898, 530) # 放大后仍能完整显示骰体
	stage.add_theme_stylebox_override("panel", Style.panel(STAGE_COLOR, Color("6a594b")))
	add_child(stage)
	_build_canvas(stage)
	_model_title = _add_label(stage, "", Vector2(24, 18), 26)
	_model_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label = _add_label(stage, "", Vector2(520, 25), 20)
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_button = _add_button(stage, "掷骰", "RollDiceButton", Vector2(722, 16), Vector2(150, 46), _play_roll)
	var pixel_toggle := CheckButton.new()
	pixel_toggle.name = "DicePixelFilter"
	pixel_toggle.text = "像素滤镜"
	pixel_toggle.button_pressed = _pixel_enabled
	pixel_toggle.position = Vector2(26, 479) # 像素滤镜开关放在滑块左侧
	pixel_toggle.add_theme_font_size_override("font_size", 18) # 像素开关字号
	pixel_toggle.toggled.connect(func(enabled: bool):
		_pixel_enabled = enabled
		_sync_pixel_viewport())
	stage.add_child(pixel_toggle)
	_pixel_label = _add_label(stage, "1 px", Vector2(440, 483), 18)
	var slider := HSlider.new()
	slider.name = "DicePixelSize"
	slider.min_value = 1
	slider.max_value = PIXEL_MAX
	slider.step = 1
	slider.value = _pixel_size
	slider.position = Vector2(186, 483) # 像素滑块放在视图区下沿
	slider.size = Vector2(224, 26) # 像素滑块的操作范围
	slider.value_changed.connect(_set_pixel_size)
	stage.add_child(slider)
	var modes := HBoxContainer.new()
	modes.name = "DicePixelMode"
	modes.position = Vector2(508, 479) # 三档并排，点击即可在同一姿态下对比
	modes.add_theme_constant_override("separation", 6) # 像素档位按钮之间的横向间距
	stage.add_child(modes)
	var mode_group := ButtonGroup.new()
	var mode_labels := ["像素最近邻", "像素平滑", "像素边缘抗锯齿"]
	for index: int in mode_labels.size():
		var button := Button.new()
		button.text = mode_labels[index]
		button.toggle_mode = true
		button.button_group = mode_group
		button.set_pressed_no_signal(index == _pixel_mode)
		button.custom_minimum_size.y = 30 # 与同排像素滤镜开关等高
		button.add_theme_font_size_override("font_size", 16) # 三档名称在视图区下沿完整显示
		button.pressed.connect(_set_pixel_mode.bind(index as PixelMode))
		modes.add_child(button)
	_select_model(10)


func _build_canvas(stage: Control) -> void:
	_canvas = Control.new()
	_canvas.name = "DiceViewport"
	stage.add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_canvas.gui_input.connect(_on_model_input)

	# 沿用字体调试器的低分辨率视口与最近邻放大，只处理骰子视图区。
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_canvas.add_child(_viewport)
	_surface = Control.new()
	_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_surface.draw.connect(_draw_model)
	_viewport.add_child(_surface)
	_texture = TextureRect.new()
	_texture.texture = _viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_smoothing_material.shader = PixelSmoothing
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_texture)
	_canvas.resized.connect(_sync_pixel_viewport)
	_sync_pixel_viewport()


func _set_pixel_size(value: float) -> void:
	_pixel_size = int(value)
	_pixel_label.text = "%d px" % _pixel_size
	_sync_pixel_viewport()


func _set_pixel_mode(mode: PixelMode) -> void:
	_pixel_mode = mode
	_sync_pixel_viewport()


func _sync_pixel_viewport() -> void:
	var block := _pixel_size if _pixel_enabled else 1
	var raster_size := Vector2i((_canvas.size / block).ceil()).max(Vector2i(2, 2))
	var supersample := _pixel_mode != PixelMode.NEAREST
	var sampling := 2 if supersample else 1 # 两个抗锯齿档每格均渲染 2×2 个样本
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if supersample else CanvasItem.TEXTURE_FILTER_NEAREST
	_smoothing_material.set_shader_parameter("edge_only", _pixel_mode == PixelMode.EDGE_AA)
	_texture.material = _smoothing_material if supersample else null
	_viewport.size = raster_size * sampling
	_texture.size = Vector2(raster_size) * block
	_surface.scale = Vector2.ONE * float(sampling) / block
	_surface.queue_redraw()


func _select_model(sides: int) -> void:
	_model.set_sides(sides)
	_model_title.text = "D%d · %s" % [sides, MODELS[sides]]
	_buttons[sides].set_pressed_no_signal(true)
	_reset_view()


func _reset_view() -> void:
	_clear_roll()
	_dragging = false
	_result = 0
	_result_label.text = ""
	_rotation = Basis.from_euler(DEFAULT_ANGLES)
	_zoom = 1.0
	_surface.queue_redraw()


func _play_roll() -> void:
	_clear_roll()
	_dragging = false
	_result = _rng.randi_range(1, _model.sides)
	_roll_button.disabled = true
	_result_label.text = "1d%d · 投掷中" % _model.sides
	_roll = EventDiceRoll.new()
	_roll.show_caption = false
	_roll.presentation_scale = ROLL_SCALE
	_roll.motion_scale = ROLL_SCALE
	_surface.add_child(_roll)
	_roll.size.x = _canvas.size.x
	_roll.finished.connect(_finish_roll)
	_roll.play(_model.sides, _result)
	_roll.position = _preview_center() - _roll.get_landing_center()
	_surface.queue_redraw()


func _finish_roll() -> void:
	_rotation = _roll.get_landing_rotation()
	_zoom = ROLL_SCALE * EventDiceRoll.DIE_SIZE / DEFAULT_RADIUS
	_result_label.text = "1d%d · 结果 %d" % [_model.sides, _result]
	# 停住时保留最后一帧，实际旋转或缩放才切回可拖动视图。
	_roll_button.disabled = false


func _clear_roll() -> void:
	if is_instance_valid(_roll):
		_surface.remove_child(_roll)
		_roll.queue_free()
		_roll = null
	_roll_button.disabled = false


func _on_model_input(event: InputEvent) -> void:
	if _roll_button.disabled: return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not event.pressed: return
				var step := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
				_zoom = clampf(_zoom * step, MIN_ZOOM, MAX_ZOOM)
				_clear_roll()
				_surface.queue_redraw()
			_:
				return
		_canvas.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		# 把水平和竖直拖动转成沿屏幕两条轴的旋转，任意方向都能连续翻转。
		var turn := Basis(Vector3.UP, event.relative.x * DRAG_SPEED)
		turn = Basis(Vector3.RIGHT, -event.relative.y * DRAG_SPEED) * turn
		_rotation = (turn * _rotation).orthonormalized()
		_clear_roll()
		_surface.queue_redraw()
		_canvas.accept_event()


func _draw_model() -> void:
	var center := _preview_center()
	_surface.draw_rect(Rect2(Vector2.ZERO, _texture.size), STAGE_COLOR)
	_surface.draw_arc(center, 200.0, 0.0, TAU, 96, Color("303747"), 1.0, true) # 辅助圆标出模型观察区
	if not is_instance_valid(_roll):
		_model.draw_on(_surface, center, _rotation, DEFAULT_RADIUS * _zoom, _result)


func _preview_center() -> Vector2:
	return _canvas.size * Vector2(0.5, 0.47) # 模型中心稍往上，为下方滑块留空间


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if get_tree().current_scene == self:
		get_tree().quit()
	else:
		close_requested.emit()


func _add_label(parent: Control, value: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _add_button(parent: Control, value: String, node_name: String, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Style.button(parent, value, node_name, action)
	button.custom_minimum_size = dimensions
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 20) # 查看器按钮字号
	return button
