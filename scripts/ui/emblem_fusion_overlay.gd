extends Control

## 合成演出只保存视觉快照；确认时由Main重新验材料并提交库存。
signal finished
signal landed
const INSPECTION_ZOOM := 4.0 # 卡牌检视对原生纹章的显示倍率
const FORMULA_ZOOM := 2.0 # 公式相对4倍检视再放大的倍率
const ICON_SIZE := Vector2(14, 14) * INSPECTION_ZOOM * FORMULA_ZOOM # 公式纹章完整尺寸为112×112，即原图8倍
const FORMULA_GAP := 12.0 # 原纹章右侧公式各项之间的逻辑像素间距
const SYMBOL_SIZE := Vector2(32, 112) # 加号和等号的占位尺寸
const ANCHOR_Z_INDEX := 20 # 演出中的卡牌显示在工具箱上方，避免左移时被遮住
const EDGE_MARGIN := 10.0 # 公式后半段与画布右边缘的安全间距
const BUTTON_SIZE := Vector2(92, 30) # 下方确认和取消按钮尺寸
const BUTTON_GAP := 12.0 # 两个按钮的水平间隔
const BUTTON_OFFSET := 72.0 # 按钮顶部相对原纹章中心的下移距离
const APPEAR_SECONDS := 0.35 # 公式浮现、两枚纹章放大抬起及布局让位的时长（秒，越小越快）
const WHITE_SECONDS := 0.16 # 确认后两枚纹章变白并后退蓄力的时长（秒，越小越快）
const ATTRACT_SECONDS := 0.34 # 手中纹章从蓄力位置缓慢加速撞向固定目标的时长（秒，越小越快）
const PULLBACK_PIXELS := 2.0 # 撞击前手中纹章沿远离目标方向后退的距离，以原图1倍像素计
const RESULT_RECOIL_PIXELS := 2.0 # 生成的新纹章先向左移动再回弹的距离，以原图1倍像素计
const FUSION_HOLD_SECONDS := 0.07 # 两枚白色剪影在原槽融合后的短暂停留（秒）
const REVEAL_SECONDS := 0.28 # 新纹章恢复原色与十字闪点消散的时长（秒，越小越快）
const RESULT_RECOIL_OUT_SECONDS := 0.24 # 新纹章向左移动2个原图像素的时长（秒，越大越慢）
const RESULT_REBOUND_SECONDS := 0.14 # 新纹章弹回原槽的时长（秒，保持原先回弹用时）
const HOLD_SECONDS := 0.16 # 新纹章揭晓后停留的时长（秒）
const RETURN_SECONDS := 0.30 # 新纹章缩回、布局还原或取消材料飞回的时长（秒，越小越快）
const FLOAT_HEIGHT := 4.0 # 公式内手中材料和配方结果上下呼吸浮动的幅度
const FLOAT_SPEED := 2.5 # 呼吸浮动的角速度
const CARD_SHAKE_PIXELS := 2.0 # 新纹章落定后整张卡牌轻震的水平幅度
const CARD_SHAKE_STEP_SECONDS := 0.035 # 整张卡牌轻震每一步的时长
const WHITE_SHADER := preload("res://shaders/emblem_fusion_white.gdshader")
const SPARKS_SCRIPT := preload("res://scripts/ui/emblem_fusion_sparks.gd")
const CLICK_SPEED_SCRIPT := preload("res://scripts/ui/animation_click_speed.gd")
const FORMULA_BACKGROUND_BRIGHTNESS := 0.60 # 公式等待确认时的背景亮度；0全黑、1不额外压暗，调小更暗
const CONFIRM_BACKGROUND_BRIGHTNESS := 0.40 # 点击确认后的背景亮度；0全黑、1不额外压暗，调小更暗
const LABEL_FONT: Font = preload("res://assets/fonts/chill_7.ttf")

var stage: StringName = &"opening"
var _click_speed := CLICK_SPEED_SCRIPT.new()
var _tween: Tween
var _dim: ColorRect
var _formula: Control
var _buttons: Control
var _confirm: Button
var _cancel: Button
var _first: Control
var _second: Control
var _result: Control
var _result_icon: TextureRect
var _first_white: ShaderMaterial
var _second_white: ShaderMaterial
var _result_white: ShaderMaterial
var _sparks: Control
var _result_label: Label
var _first_origin := Vector2.ZERO
var _second_origin := Vector2.ZERO
var _first_scale := Vector2.ONE
var _second_scale := Vector2.ONE
var _first_rest := Vector2.ZERO
var _second_rest := Vector2.ZERO
var _result_rest := Vector2.ZERO
var _fusion_point := Vector2.ZERO
var _float_time := 0.0
var _commit: Callable
var _committed := false
var _result_id: StringName
var _anchor_card: Control
var _anchor_card_rest := Vector2.ZERO
var _anchor_card_z_index := 0
var _toolbox: Control
var _toolbox_rest := Vector2.ZERO
var _layout_shift := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 4095

func begin(first_id: StringName, second_id: StringName, result_id: StringName, known: bool, first_rect: Rect2, second_rect: Rect2, hand_rect: Rect2, commit: Callable, anchor_card: Control, toolbox: Control) -> void:
	_commit = commit
	_result_id = result_id
	_anchor_card = anchor_card
	_anchor_card_rest = anchor_card.position
	_anchor_card_z_index = anchor_card.z_index
	_toolbox = toolbox
	_toolbox_rest = toolbox.position
	anchor_card.z_index = maxi(anchor_card.z_index, ANCHOR_Z_INDEX)
	var inverse := get_global_transform_with_canvas().affine_inverse()
	_first_origin = inverse * first_rect.get_center()
	_second_origin = inverse * second_rect.get_center()
	_first_scale = first_rect.size / ICON_SIZE
	_second_scale = second_rect.size / ICON_SIZE
	_dim = ColorRect.new()
	_dim.color = Color.BLACK
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.modulate.a = 0.0
	add_child(_dim)
	_formula = Control.new()
	_formula.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_formula.modulate.a = 0.0
	add_child(_formula)
	# 右侧空间不足时，卡牌、公式和工具箱按相同位移一起左移，演出结束还原。
	var suffix_width := FORMULA_GAP * 4.0 + SYMBOL_SIZE.x * 2.0 + ICON_SIZE.x * 2.0
	var required_right := _first_origin.x + ICON_SIZE.x * 0.5 + suffix_width
	var shift_x := minf(0.0, size.x - EDGE_MARGIN - required_right)
	_layout_shift = Vector2(shift_x, 0)
	_formula.position = -_layout_shift
	_first_rest = _first_origin + _layout_shift
	var first_right := _first_rest.x + ICON_SIZE.x * 0.5
	var cursor := first_right + FORMULA_GAP
	_label(_formula, "+", Vector2(cursor, _first_rest.y - SYMBOL_SIZE.y * 0.5), SYMBOL_SIZE, 44)
	cursor += (SYMBOL_SIZE.x + FORMULA_GAP)
	_second_rest = Vector2(cursor + ICON_SIZE.x * 0.5, _first_rest.y + 4.0) # 手中材料略微错位
	cursor += (ICON_SIZE.x + FORMULA_GAP)
	_label(_formula, "=", Vector2(cursor, _first_rest.y - SYMBOL_SIZE.y * 0.5), SYMBOL_SIZE, 44)
	cursor += (SYMBOL_SIZE.x + FORMULA_GAP)
	_result_rest = Vector2(cursor + ICON_SIZE.x * 0.5, _first_rest.y)
	_fusion_point = _first_rest
	_first = _icon(first_id)
	_first.position = _first_origin
	_first.scale = _first_scale
	_second = _icon(second_id)
	_second.position = inverse * hand_rect.get_center()
	_second.scale = hand_rect.size / ICON_SIZE
	# 问号、结果纹章和名称共用同一个中心节点，浮动时只移动这个节点。
	_result = _icon(result_id)
	_result.position = _result_rest - _layout_shift
	_result_icon = _result.get_child(0) as TextureRect
	_result_icon.visible = known
	_result.modulate.a = 0.0
	_result_label = _label(_result, String(result_id) if known else "？", Vector2(-70, ICON_SIZE.y * 0.5 + 8), Vector2(140, 28), 18)
	if known:
		_result_label.position.x = clampf(_result_rest.x - 70, EDGE_MARGIN, size.x - EDGE_MARGIN - 140) - _result_rest.x
	else:
		_result_label.position = -ICON_SIZE * 0.5
		_result_label.size = ICON_SIZE
		_result_label.add_theme_font_size_override("font_size", 64)
	_buttons = Control.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.modulate.a = 0.0
	_buttons.position = -_layout_shift
	add_child(_buttons)
	var button_x := clampf(_first_rest.x - first_rect.size.x * 0.5, EDGE_MARGIN, size.x - EDGE_MARGIN - BUTTON_SIZE.x * 2.0 - BUTTON_GAP)
	var button_y := minf(_first_rest.y + BUTTON_OFFSET, size.y - BUTTON_SIZE.y - EDGE_MARGIN)
	_confirm = _button("确认", Vector2(button_x, button_y))
	_cancel = _button("取消", Vector2(button_x + BUTTON_SIZE.x + BUTTON_GAP, button_y))
	_confirm.disabled = true
	_cancel.disabled = true
	_first_white = _white_material(_first.get_child(0) as TextureRect)
	_second_white = _white_material(_second.get_child(0) as TextureRect)
	_result_white = _white_material(_result_icon)
	_sparks = SPARKS_SCRIPT.new()
	_sparks.position = _fusion_point
	add_child(_sparks)
	_tween = _new_tween()
	_tween.tween_property(_first, "position", _first_rest, APPEAR_SECONDS)
	_tween.parallel().tween_property(_anchor_card, "position", _anchor_card_rest + _layout_shift, APPEAR_SECONDS)
	_tween.parallel().tween_property(_toolbox, "position", _toolbox_rest + _layout_shift, APPEAR_SECONDS)
	_tween.parallel().tween_property(_formula, "position", Vector2.ZERO, APPEAR_SECONDS)
	_tween.parallel().tween_property(_buttons, "position", Vector2.ZERO, APPEAR_SECONDS)
	_tween.parallel().tween_property(_result, "position", _result_rest, APPEAR_SECONDS)
	_tween.parallel().tween_property(_first, "scale", Vector2.ONE, APPEAR_SECONDS)
	_tween.parallel().tween_property(_second, "position", _second_rest, APPEAR_SECONDS)
	_tween.parallel().tween_property(_second, "scale", Vector2.ONE, APPEAR_SECONDS)
	for item: Control in [_formula, _buttons]:
		_tween.parallel().tween_property(item, "modulate:a", 1.0, APPEAR_SECONDS)
	_tween.parallel().tween_property(_result, "modulate:a", 1.0, APPEAR_SECONDS)
	_tween.parallel().tween_property(_dim, "modulate:a", 1.0 - FORMULA_BACKGROUND_BRIGHTNESS, APPEAR_SECONDS)
	_tween.tween_callback(func():
		stage = &"awaiting"
		_confirm.disabled = false
		_cancel.disabled = false
	)

func _input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if stage == &"awaiting":
				var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
				if Rect2(_confirm.position, _confirm.size).has_point(point): confirm()
				elif Rect2(_cancel.position, _cancel.size).has_point(point): cancel()
			else:
				_click_speed.register_click(_tween)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
	# 演出节点统一消费输入，鼠标不会穿透到工具箱或检视背景。
	return event is InputEventMouse or event is InputEventKey or event is InputEventScreenTouch

func _process(delta: float) -> void:
	if stage != &"awaiting":
		return
	_float_time += delta
	# 卡上目标是固定合成点；只有手中材料与结果预览呼吸浮动。
	_first.position = _first_rest
	_second.position = _second_rest + Vector2(0, sin(_float_time * FLOAT_SPEED + 1.1) * FLOAT_HEIGHT)
	_result.position = _result_rest + Vector2(0, sin(_float_time * FLOAT_SPEED + 2.2) * FLOAT_HEIGHT)

func confirm() -> void:
	if stage != &"awaiting":
		return
	if not _commit.is_valid() or not bool(_commit.call()):
		cancel()
		return
	_committed = true
	stage = &"charging"
	_confirm.disabled = true
	_cancel.disabled = true
	_fusion_point = _first_rest
	_first.position = _fusion_point
	# 演出纹章是原图8倍，1倍像素先乘显示倍率，避免只退2个画布像素。
	var away := (_second.position - _fusion_point).normalized()
	_second_rest = _second.position + away * PULLBACK_PIXELS * INSPECTION_ZOOM * FORMULA_ZOOM
	_sparks.position = _fusion_point
	_result.hide()
	_tween = _new_tween()
	_tween.tween_property(_buttons, "modulate:a", 0.0, WHITE_SECONDS)
	_tween.parallel().tween_property(_formula, "modulate:a", 0.0, WHITE_SECONDS)
	_tween.parallel().tween_method(_whiten_materials, 0.0, 1.0, WHITE_SECONDS)
	_tween.parallel().tween_property(_dim, "modulate:a", 1.0 - CONFIRM_BACKGROUND_BRIGHTNESS, WHITE_SECONDS)
	_tween.parallel().tween_property(_second, "position", _second_rest, WHITE_SECONDS)
	_tween.tween_callback(func(): stage = &"attracting")
	# 线性时间输入由函数转换成三次曲线，越接近目标速度越快。
	_tween.tween_method(_attract_incoming, 0.0, 1.0, ATTRACT_SECONDS).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(func(): stage = &"flash")
	_tween.tween_interval(FUSION_HOLD_SECONDS)
	_tween.tween_callback(_begin_reveal)
	_tween.tween_method(_reveal_result, 0.0, 1.0, REVEAL_SECONDS)
	var recoil_seconds := RESULT_RECOIL_OUT_SECONDS + RESULT_REBOUND_SECONDS
	_tween.parallel().tween_method(_move_result_recoil, 0.0, recoil_seconds, recoil_seconds).set_trans(Tween.TRANS_LINEAR)
	_tween.parallel().tween_method(_sparks.set_progress, 0.0, 1.0, REVEAL_SECONDS)
	_tween.parallel().tween_property(_result_label, "modulate:a", 1.0, REVEAL_SECONDS)
	_tween.tween_callback(func(): stage = &"displaying")
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_callback(func(): stage = &"returning")
	# 合成点已是原卡槽，只缩回4倍槽内尺寸，不再把目标纹章挪到别处。
	_tween.tween_property(_result, "scale", _first_scale, RETURN_SECONDS)
	_tween.parallel().tween_property(_result_label, "modulate:a", 0.0, RETURN_SECONDS)
	_tween.tween_callback(_land_result)
	for offset: float in [1.0, -1.0, 0.6, -0.6, 0.0]:
		_tween.tween_property(_anchor_card, "position", _anchor_card_rest + _layout_shift + Vector2(offset * CARD_SHAKE_PIXELS, 0), CARD_SHAKE_STEP_SECONDS)
	_tween.tween_callback(func(): stage = &"restoring")
	_tween.tween_property(_anchor_card, "position", _anchor_card_rest, RETURN_SECONDS)
	_tween.parallel().tween_property(_toolbox, "position", _toolbox_rest, RETURN_SECONDS)
	_fade_shell(RETURN_SECONDS)
	_tween.tween_callback(_finish)

func _whiten_materials(progress: float) -> void:
	_first_white.set_shader_parameter("white_amount", progress)
	_second_white.set_shader_parameter("white_amount", progress)

func _attract_incoming(progress: float) -> void:
	var travel := progress * progress * progress
	_second.position = _second_rest.lerp(_fusion_point, travel)

func _begin_reveal() -> void:
	stage = &"revealing"
	_first.hide()
	_second.hide()
	_result.position = _fusion_point
	_result.scale = Vector2.ONE
	_result.modulate.a = 1.0
	_result.show()
	_result_icon.show()
	_result_white.set_shader_parameter("white_amount", 1.0)
	_result_label.text = String(_result_id)
	_result_label.position = Vector2(clampf(_fusion_point.x - 70, EDGE_MARGIN, size.x - EDGE_MARGIN - 140) - _fusion_point.x, ICON_SIZE.y * 0.5 + 8)
	_result_label.size = Vector2(140, 28)
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.modulate.a = 0.0
	_sparks.set_progress(0.0)

func _reveal_result(progress: float) -> void:
	_result_white.set_shader_parameter("white_amount", 1.0 - progress)

func _move_result_recoil(elapsed: float) -> void:
	# 左移与回弹各自计时；两段余弦缓动都在端点减速，转向时位置连续。
	var progress := clampf(elapsed / RESULT_RECOIL_OUT_SECONDS, 0.0, 1.0)
	var weight := (1.0 - cos(progress * PI)) * 0.5
	if elapsed > RESULT_RECOIL_OUT_SECONDS:
		progress = clampf((elapsed - RESULT_RECOIL_OUT_SECONDS) / RESULT_REBOUND_SECONDS, 0.0, 1.0)
		weight = (1.0 + cos(progress * PI)) * 0.5
	var recoil := weight * RESULT_RECOIL_PIXELS * INSPECTION_ZOOM * FORMULA_ZOOM
	_result.position = _fusion_point + Vector2(-recoil, 0)

func _land_result() -> void:
	stage = &"shaking"
	_result.hide()
	landed.emit() # 先交回卡面真实纹章，再震动整张合成卡面，纹章也会跟着震动

func _white_material(icon: TextureRect) -> ShaderMaterial:
	var white := ShaderMaterial.new()
	white.shader = WHITE_SHADER
	icon.material = white
	return white

func cancel() -> void:
	if _committed or stage in [&"cancelling", &"finished"]:
		return
	if is_instance_valid(_tween): _tween.kill()
	stage = &"cancelling"
	_confirm.disabled = true
	_cancel.disabled = true
	_tween = _new_tween()
	_tween.tween_property(_second, "position", _second_origin, RETURN_SECONDS)
	_tween.parallel().tween_property(_second, "scale", _second_scale, RETURN_SECONDS)
	_tween.parallel().tween_property(_first, "position", _first_origin, RETURN_SECONDS)
	_tween.parallel().tween_property(_first, "scale", _first_scale, RETURN_SECONDS)
	_tween.parallel().tween_property(_result, "modulate:a", 0.0, RETURN_SECONDS)
	_tween.parallel().tween_property(_anchor_card, "position", _anchor_card_rest, RETURN_SECONDS)
	_tween.parallel().tween_property(_toolbox, "position", _toolbox_rest, RETURN_SECONDS)
	_fade_shell(RETURN_SECONDS)
	_tween.tween_callback(_finish)

func finish_immediately() -> void:
	if is_instance_valid(_tween): _tween.kill()
	_finish()

func _fade_shell(seconds: float) -> void:
	_tween.parallel().tween_property(_formula, "position", -_layout_shift, seconds)
	_tween.parallel().tween_property(_buttons, "position", -_layout_shift, seconds)
	for item: Control in [_dim, _formula, _buttons]:
		_tween.parallel().tween_property(item, "modulate:a", 0.0, seconds)

func _new_tween() -> Tween:
	var tween := create_tween()
	_click_speed.apply_to(tween)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

func _icon(id: StringName) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var icon := TextureRect.new()
	icon.texture = StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.EMBLEM, id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size = ICON_SIZE
	icon.position = -ICON_SIZE * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return holder

func _label(parent: Control, text: String, position_value: Vector2, size_value: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.size = size_value
	label.add_theme_font_override("font", LABEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f4e6ff"))
	label.add_theme_color_override("font_outline_color", Color("19121f"))
	label.add_theme_constant_override("outline_size", 2) # 公式在卡面上方显示时的文字描边宽度
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(text: String, position_value: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position_value
	button.size = BUTTON_SIZE
	button.add_theme_font_override("font", LABEL_FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_child(button)
	return button

func _finish() -> void:
	if stage == &"finished": return
	stage = &"finished"
	_restore_layout()
	finished.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(_tween): _tween.kill()
	if stage != &"finished": _restore_layout()

func _restore_layout() -> void:
	if is_instance_valid(_toolbox): _toolbox.position = _toolbox_rest
	if is_instance_valid(_anchor_card):
		_anchor_card.position = _anchor_card_rest
		_anchor_card.z_index = _anchor_card_z_index
