extends Control

## 普通英雄台词与按钮二次确认共用；气泡可见期间才保留确认资格。
const BACKGROUND: Texture2D = preload("res://assets/ui/hero/speech_bubble.png")
const TextSettings = preload("res://scripts/ui/card_text_display_settings.gd")
const EventText = preload("res://scripts/ui/event_card_table.gd")
const DEFAULT_SECONDS: float = 5.0 # 默认台词停留秒数，超时后重新操作须再次提示
const TEXT_INSET := Vector2(12, 12) # 文字距气泡左右及顶部的留白
const TAIL_HEIGHT: float = 9.0 # 底部尾尖预留高度，文字不进入尾尖
const TAIL_TIP_X: float = 120.0 # 原图尾尖的横坐标，用于对齐英雄头部
const HEAD_INSET: float = 30.0 # 英雄180px透明画布顶端到头部的距离
const SPEAKER_GAP: float = 4.0 # 气泡尾尖与英雄头顶的间距
const SCREEN_INSET: float = 2.0 # 气泡与逻辑画布边缘的最小间距
const FONT_SIZE: int = 14 # 英雄台词黑体字号
const LINE_SPACING: int = 2 # 多行台词之间的额外间距
const FADE_SECONDS: float = 0.20 # 气泡出现与收起时整体淡入淡出的时长

var confirmation_button: BaseButton
var text_label: Label
var _speaker: Control
var speaker_head_inset: float = HEAD_INSET # 气泡尾端所指头部距控件顶边的距离
var _remaining_seconds: float = 0.0
var _background: NinePatchRect
var _text_reveal: Tween
var _fade: Tween
var _pinned: bool = false
var _visual: Control
var _display: Control
var _display_scale: float = 1.0


func _ready() -> void:
	name = "HeroSpeechBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2700 # 高于商店棋盘，低于卡牌检视及暂停菜单
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = BACKGROUND.get_size()
	_display = get_tree().get_first_node_in_group(&"game_display_shell") as Control
	var layer := CanvasLayer.new()
	layer.name = "SpeechWindowLayer"
	layer.custom_viewport = get_tree().root
	layer.layer = 29 # 直接在根窗口绘字，位于卡牌效果悬浮框下方
	add_child(layer)
	_visual = Control.new()
	_visual.name = "SpeechWindowVisual"
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_visual)
	_background = NinePatchRect.new()
	_background.texture = BACKGROUND
	_background.patch_margin_left = 8 # 保留原图左右边框
	_background.patch_margin_right = 8 # 保留原图左右边框
	_background.patch_margin_top = 8 # 保留原图顶端圆角
	_background.patch_margin_bottom = 16 # 保留原图底边、圆角和尾尖，只伸缩中间纯色区域
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual.add_child(_background)
	text_label = Label.new()
	text_label.name = "SpeechText"
	text_label.position = TEXT_INSET
	text_label.size = size - TEXT_INSET * 2.0 - Vector2(0, TAIL_HEIGHT)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("font", TextSettings.readable_font())
	text_label.add_theme_font_size_override("font_size", FONT_SIZE)
	text_label.add_theme_constant_override("line_spacing", LINE_SPACING)
	text_label.add_theme_color_override("font_color", Color("35251c"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 用完整台词确定换行和居中位置，逐字显示只遮住后面的字。
	text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.add_child(text_label)
	visibility_changed.connect(_sync_visual_visibility)
	dismiss(true)


func say(message: String, speaker: Control, seconds: float = DEFAULT_SECONDS, confirm_button: BaseButton = null, pinned: bool = false) -> void:
	if message.is_empty() or not is_instance_valid(speaker):
		dismiss()
		return
	_speaker = speaker
	_pinned = pinned
	confirmation_button = confirm_button
	if is_instance_valid(_fade): _fade.kill()
	if is_instance_valid(_text_reveal): _text_reveal.kill()
	modulate.a = 1.0
	_visual.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(_visual, "modulate:a", 1.0, FADE_SECONDS)
	_display_scale = _window_transform().get_scale().x
	text_label.text = message
	_layout_message(message)
	_reveal_message(message)
	_remaining_seconds = maxf(seconds, 0.0)
	show()
	_update_position()
	set_process(true)
	set_process_input(true)


func dismiss(immediate: bool = false) -> void:
	_speaker = null
	_pinned = false
	confirmation_button = null
	_remaining_seconds = 0.0
	set_process(false)
	set_process_input(false)
	if is_instance_valid(_text_reveal): _text_reveal.kill()
	if immediate or not visible:
		if is_instance_valid(_fade): _fade.kill()
		hide()
		return
	if is_instance_valid(_fade): _fade.kill()
	_fade = create_tween()
	_fade.tween_property(_visual, "modulate:a", 0.0, FADE_SECONDS)
	_fade.tween_callback(hide)


func _layout_message(message: String) -> void:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.width = (BACKGROUND.get_width() - TEXT_INSET.x * 2.0) * _display_scale
	var physical_font_size := maxi(1, roundi(FONT_SIZE * _display_scale))
	var physical_spacing := roundi(LINE_SPACING * _display_scale)
	text_label.add_theme_font_size_override("font_size", physical_font_size)
	text_label.add_theme_constant_override("line_spacing", physical_spacing)
	paragraph.add_string(message, text_label.get_theme_font("font"), physical_font_size)
	var text_height := ceilf((paragraph.get_size().y + physical_spacing * maxi(0, paragraph.get_line_count() - 1)) / _display_scale)
	size = Vector2(BACKGROUND.get_width(), text_height + TEXT_INSET.y * 2.0 + TAIL_HEIGHT)
	_background.size = size
	_background.scale = Vector2.ONE * _display_scale
	text_label.position = (TEXT_INSET * _display_scale).round()
	text_label.size.x = paragraph.width
	# 改字号与宽度后，Label需先重算换行；随后再设置高度，避免沿用窄版正文的旧最小高度。
	text_label.set_deferred("size", Vector2(paragraph.width, text_height * _display_scale).ceil())


func _reveal_message(message: String) -> void:
	text_label.visible_characters = 0
	_text_reveal = create_tween()
	var start := 0
	for index: int in message.length():
		if message[index] not in "，。！？；、,.!?;\n" and index != message.length() - 1: continue
		_text_reveal.tween_property(text_label, "visible_characters", index + 1, (index + 1 - start) * EventText.CHARACTER_SECONDS)
		_text_reveal.tween_interval(EventText.TEXT_LINE_PAUSE)
		start = index + 1


func finish_reveal() -> bool:
	if not is_instance_valid(_text_reveal) or not _text_reveal.is_running():
		return false
	var incomplete := text_label.visible_ratio < 1.0
	_text_reveal.kill()
	text_label.visible_characters = -1
	return incomplete


func is_confirming(button: BaseButton) -> bool:
	return is_instance_valid(button) and is_visible_in_tree() and _remaining_seconds > 0.0 and confirmation_button == button and not get_tree().paused


func _process(delta: float) -> void:
	var menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	if menu != null and menu.blocks_gameplay():
		_sync_visual_visibility()
		if _pinned: return
	_remaining_seconds -= delta
	if (not _pinned and (_remaining_seconds <= 0.0 or get_tree().paused)) or not is_visible_in_tree() or not is_instance_valid(_speaker) or not _speaker.is_visible_in_tree():
		dismiss()
		return
	if is_instance_valid(confirmation_button) and not confirmation_button.is_visible_in_tree():
		dismiss()
		return
	_update_position()


func _update_position() -> void:
	var display_scale := _window_transform().get_scale().x
	if not is_equal_approx(display_scale, _display_scale):
		_display_scale = display_scale
		_layout_message(text_label.text)
	var host := get_parent() as Control
	var speaker_transform := host.get_global_transform_with_canvas().affine_inverse() * _speaker.get_global_transform_with_canvas()
	var head := speaker_transform * Vector2(_speaker.size.x * 0.5, speaker_head_inset)
	position = (head - Vector2(TAIL_TIP_X, size.y + SPEAKER_GAP)).round()
	position.x = clampf(position.x, SCREEN_INSET, maxf(SCREEN_INSET, host.size.x - size.x - SCREEN_INSET))
	position.y = clampf(position.y, SCREEN_INSET, maxf(SCREEN_INSET, host.size.y - size.y - SCREEN_INSET))
	_visual.position = _window_transform().origin.round()
	_visual.size = size * _display_scale
	_sync_visual_visibility()


func _window_transform() -> Transform2D:
	var result := get_global_transform_with_canvas()
	if is_instance_valid(_display) and get_viewport() == _display.internal_viewport:
		result = _display.render_container.get_global_transform_with_canvas() * result
	return result


func _sync_visual_visibility() -> void:
	if not is_instance_valid(_visual): return
	var visible_here := is_visible_in_tree()
	if is_instance_valid(_display) and is_instance_valid(_display.screen_transition) and _display.screen_transition.busy: visible_here = false
	var menu := get_tree().get_first_node_in_group(&"escape_pause_menus") if is_inside_tree() else null
	if menu != null and menu.blocks_gameplay(): visible_here = false
	_visual.visible = visible_here


func _input(event: InputEvent) -> void:
	if _pinned: return
	var menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	if menu != null and menu.blocks_gameplay(): return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(confirmation_button):
			var point: Vector2 = confirmation_button.get_global_transform_with_canvas().affine_inverse() * event.position
			if Rect2(Vector2.ZERO, confirmation_button.size).has_point(point): return
		dismiss()
	elif event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(confirmation_button) and confirmation_button.has_focus() and event.is_action_pressed("ui_accept"): return
		dismiss()
