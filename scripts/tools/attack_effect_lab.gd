class_name AttackEffectLab
extends Control

## 所有攻击尾迹配置的可视化开发页面。
## 控件编辑的是本地草稿；实时预览直接消费草稿，点击保存后正式战斗读取同一份配置。

signal close_requested

const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleAttackTrailRenderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const UI_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const PREVIEW_MARGIN_X: float = 92.0 # 预览起终点距离面板左右边缘的留白
const PREVIEW_REPLAY_GAP: float = 0.16 # 一次尾迹完全结束到下一次自动播放的间隔（秒）
const CONTROL_LABEL_WIDTH: float = 118.0 # 参数中文名称占用的固定宽度
const CONTROL_SPIN_WIDTH: float = 102.0 # 数值输入框的固定宽度

const PREVIEW_COLOR_NAMES: Array[String] = ["无元素·白", "光·黄", "暗·紫", "火·红", "水·蓝", "木·绿"]
const PREVIEW_COLORS: Array[Color] = [
	Color("ffffff"),
	Color("ffd84a"),
	Color("963cff"),
	Color("ff3b30"),
	Color("2f9bff"),
	Color("35d04f"),
]

var _drafts: Dictionary = {}
var _current_profile_id: StringName = &"melee_attack"
var _numeric_controls: Dictionary = {}
var _loading_controls: bool = false
var _auto_play: bool = true
var _replay_seconds: float = 0.0
var _preview_start := Vector2.ZERO
var _preview_end := Vector2.ZERO

var profile_option: OptionButton
var mask_option: OptionButton
var head_color_option: OptionButton
var tail_color_option: OptionButton
var auto_play_button: Button
var status_label: Label
var preview_canvas: Control
var effect_layer: Control
var source_marker: PanelContainer
var target_marker: PanelContainer


func _ready() -> void:
	var lab_theme := Theme.new()
	lab_theme.default_font = UI_FONT
	lab_theme.default_font_size = 14
	theme = lab_theme
	_load_drafts()
	_build_interface()
	_load_profile_into_controls(_current_profile_id)
	preview_canvas.resized.connect(_layout_preview)
	call_deferred("_layout_preview")
	set_process(true)


func _process(delta: float) -> void:
	if not _auto_play or not is_instance_valid(effect_layer):
		return
	_replay_seconds -= delta
	if _replay_seconds <= 0.0:
		_play_preview(false)


func _load_drafts() -> void:
	_drafts.clear()
	for profile_id: StringName in BattleAttackEffectProfiles.PROFILE_IDS:
		_drafts[profile_id] = BattleAttackEffectProfiles.get_profile(profile_id)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("10161d")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root_layout := VBoxContainer.new()
	root_layout.add_theme_constant_override("separation", 9)
	margin.add_child(root_layout)
	root_layout.add_child(_build_top_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body.add_child(_build_settings_panel())
	body.add_child(_build_preview_panel())
	root_layout.add_child(body)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 40.0
	bar.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "← 返回主界面"
	back.custom_minimum_size.x = 132.0
	back.pressed.connect(func() -> void: close_requested.emit())
	bar.add_child(back)
	var title := Label.new()
	title.text = "攻击特效调试器"
	title.add_theme_font_size_override("font_size", 22)
	title.custom_minimum_size.x = 172.0
	bar.add_child(title)
	profile_option = OptionButton.new()
	profile_option.custom_minimum_size.x = 148.0
	for profile_id: StringName in BattleAttackEffectProfiles.PROFILE_IDS:
		profile_option.add_item(BattleAttackEffectProfiles.PROFILE_NAMES[profile_id])
	profile_option.item_selected.connect(_on_profile_selected)
	bar.add_child(profile_option)
	var save := Button.new()
	save.text = "保存全部配置"
	save.pressed.connect(_save_all_profiles)
	bar.add_child(save)
	var reset := Button.new()
	reset.text = "当前恢复默认"
	reset.pressed.connect(_reset_current_profile)
	bar.add_child(reset)
	var reload := Button.new()
	reload.text = "重新载入已保存"
	reload.pressed.connect(_reload_saved_profiles)
	bar.add_child(reload)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	status_label = Label.new()
	status_label.text = "修改任意参数会立即重播"
	status_label.add_theme_color_override("font_color", Color("9fd6ac"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(status_label)
	return bar


func _build_settings_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 430.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("19232d"), Color("425466")))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)
	var mask_title := Label.new()
	mask_title.text = "尾迹遮罩"
	mask_title.add_theme_font_size_override("font_size", 17)
	layout.add_child(mask_title)
	mask_option = OptionButton.new()
	for mask_id: StringName in BattleAttackEffectProfiles.MASK_IDS:
		mask_option.add_item(BattleAttackEffectProfiles.MASK_NAMES[mask_id])
	mask_option.item_selected.connect(_on_mask_selected)
	layout.add_child(mask_option)
	var separator := HSeparator.new()
	layout.add_child(separator)
	var numeric_title := Label.new()
	numeric_title.text = "路径、拖尾、流动与扭曲参数"
	numeric_title.add_theme_font_size_override("font_size", 17)
	layout.add_child(numeric_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 4)
	scroll.add_child(fields)
	for field: Dictionary in BattleAttackEffectProfiles.NUMERIC_FIELDS:
		fields.add_child(_build_numeric_row(field))
	return panel


func _build_numeric_row(field: Dictionary) -> Control:
	var key := StringName(field["key"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = String(field["label"])
	label.custom_minimum_size.x = CONTROL_LABEL_WIDTH
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = float(field["min"])
	slider.max_value = float(field["max"])
	slider.step = float(field["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = slider.min_value
	spin.max_value = slider.max_value
	spin.step = slider.step
	spin.custom_minimum_size.x = CONTROL_SPIN_WIDTH
	spin.suffix = String(field["suffix"])
	spin.allow_greater = false
	spin.allow_lesser = false
	row.add_child(spin)
	_numeric_controls[key] = {"slider": slider, "spin": spin}
	slider.value_changed.connect(_on_slider_changed.bind(key, spin))
	spin.value_changed.connect(_on_spin_changed.bind(key, slider))
	return row


func _build_preview_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("121b24"), Color("765f35")))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 7)
	panel.add_child(layout)
	var preview_bar := HBoxContainer.new()
	preview_bar.add_theme_constant_override("separation", 7)
	var preview_title := Label.new()
	preview_title.text = "实时循环预览"
	preview_title.add_theme_font_size_override("font_size", 18)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_bar.add_child(preview_title)
	head_color_option = _make_color_option(4)
	tail_color_option = _make_color_option(2)
	head_color_option.item_selected.connect(func(_index: int) -> void: _restart_preview())
	tail_color_option.item_selected.connect(func(_index: int) -> void: _restart_preview())
	preview_bar.add_child(_labeled_preview_control("头部", head_color_option))
	preview_bar.add_child(_labeled_preview_control("尾部", tail_color_option))
	var play_once := Button.new()
	play_once.text = "播放一次"
	play_once.pressed.connect(func() -> void: _play_preview(true))
	preview_bar.add_child(play_once)
	auto_play_button = Button.new()
	auto_play_button.text = "循环：开"
	auto_play_button.pressed.connect(_toggle_auto_play)
	preview_bar.add_child(auto_play_button)
	layout.add_child(preview_bar)
	preview_canvas = Control.new()
	preview_canvas.name = "PreviewCanvas"
	preview_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_canvas.clip_contents = true
	layout.add_child(preview_canvas)
	var preview_background := ColorRect.new()
	preview_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_background.color = Color("293e58")
	preview_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_canvas.add_child(preview_background)
	var center_guide := ColorRect.new()
	center_guide.name = "CenterGuide"
	center_guide.color = Color(0.83, 0.72, 0.43, 0.22)
	center_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_canvas.add_child(center_guide)
	effect_layer = Control.new()
	effect_layer.name = "EffectLayer"
	effect_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_layer.z_index = 10
	preview_canvas.add_child(effect_layer)
	source_marker = _make_marker("攻击方")
	target_marker = _make_marker("目标")
	preview_canvas.add_child(source_marker)
	preview_canvas.add_child(target_marker)
	var help := Label.new()
	help.text = "边缘阈值越大，外围灰雾裁得越多；边缘柔化越小，边界越锐利。教程扭曲四参数也可独立调整，保存后正式战斗立即读取。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("a9bac8"))
	layout.add_child(help)
	return panel


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10.0)
	return style


func _make_color_option(selected_index: int) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.x = 100.0
	for color_name: String in PREVIEW_COLOR_NAMES:
		option.add_item(color_name)
	option.select(selected_index)
	return option


func _labeled_preview_control(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	row.add_child(control)
	return row


func _make_marker(label_text: String) -> PanelContainer:
	var marker := PanelContainer.new()
	marker.custom_minimum_size = Vector2(86.0, 126.0)
	marker.add_theme_stylebox_override("panel", _panel_style(Color("27323e"), Color("d2b55e")))
	marker.z_index = 20
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_child(label)
	return marker


func _layout_preview() -> void:
	if not is_instance_valid(preview_canvas):
		return
	var canvas_size := preview_canvas.size
	_preview_start = Vector2(PREVIEW_MARGIN_X, canvas_size.y * 0.56)
	_preview_end = Vector2(canvas_size.x - PREVIEW_MARGIN_X, canvas_size.y * 0.44)
	source_marker.position = _preview_start - source_marker.custom_minimum_size * 0.5
	target_marker.position = _preview_end - target_marker.custom_minimum_size * 0.5
	var center_guide := preview_canvas.get_node("CenterGuide") as ColorRect
	center_guide.position = Vector2(0.0, canvas_size.y * 0.5 - 1.0)
	center_guide.size = Vector2(canvas_size.x, 2.0)
	_restart_preview()


func _on_profile_selected(index: int) -> void:
	_current_profile_id = BattleAttackEffectProfiles.PROFILE_IDS[index]
	_load_profile_into_controls(_current_profile_id)


func _load_profile_into_controls(profile_id: StringName) -> void:
	_loading_controls = true
	var profile := _drafts[profile_id] as Dictionary
	mask_option.select(BattleAttackEffectProfiles.MASK_IDS.find(profile["mask_kind"] as StringName))
	for field: Dictionary in BattleAttackEffectProfiles.NUMERIC_FIELDS:
		var key := StringName(field["key"])
		var controls := _numeric_controls[key] as Dictionary
		(controls["slider"] as HSlider).value = float(profile[String(key)])
		(controls["spin"] as SpinBox).value = float(profile[String(key)])
	_loading_controls = false
	_restart_preview()


func _on_mask_selected(index: int) -> void:
	if _loading_controls:
		return
	var profile := _drafts[_current_profile_id] as Dictionary
	profile["mask_kind"] = BattleAttackEffectProfiles.MASK_IDS[index]
	_restart_preview()


func _on_slider_changed(value: float, key: StringName, spin: SpinBox) -> void:
	if _loading_controls:
		return
	_loading_controls = true
	spin.value = value
	_loading_controls = false
	_update_numeric_value(key, value)


func _on_spin_changed(value: float, key: StringName, slider: HSlider) -> void:
	if _loading_controls:
		return
	_loading_controls = true
	slider.value = value
	_loading_controls = false
	_update_numeric_value(key, value)


func _update_numeric_value(key: StringName, value: float) -> void:
	var profile := _drafts[_current_profile_id] as Dictionary
	profile[String(key)] = value
	_restart_preview()


func _restart_preview() -> void:
	_replay_seconds = 0.0
	if is_instance_valid(effect_layer):
		_play_preview(true)


func _play_preview(clear_previous: bool) -> void:
	if not is_instance_valid(effect_layer) or _preview_end.distance_to(_preview_start) < 20.0:
		return
	if clear_previous:
		for child: Node in effect_layer.get_children():
			child.queue_free()
	var profile := BattleAttackEffectProfiles.normalize_profile(
		_current_profile_id,
		_drafts[_current_profile_id] as Dictionary
	)
	BattleAttackTrailRenderer.play(
		effect_layer,
		PackedVector2Array([_preview_start, _preview_end]),
		profile,
		PREVIEW_COLORS[head_color_option.selected],
		PREVIEW_COLORS[tail_color_option.selected]
	)
	_replay_seconds = float(profile["duration"]) + PREVIEW_REPLAY_GAP


func _toggle_auto_play() -> void:
	_auto_play = not _auto_play
	auto_play_button.text = "循环：开" if _auto_play else "循环：关"
	if _auto_play:
		_restart_preview()


func _save_all_profiles() -> void:
	var error := BattleAttackEffectProfiles.save_profiles(_drafts)
	if error == OK:
		status_label.text = "已保存：%s" % BattleAttackEffectProfiles.SAVE_PATH
		status_label.add_theme_color_override("font_color", Color("9fd6ac"))
	else:
		status_label.text = "保存失败：%s" % error_string(error)
		status_label.add_theme_color_override("font_color", Color("ff8c82"))


func _reset_current_profile() -> void:
	_drafts[_current_profile_id] = BattleAttackEffectProfiles.get_default_profile(_current_profile_id)
	_load_profile_into_controls(_current_profile_id)
	status_label.text = "当前类型已恢复默认；点击保存才会写入文件"


func _reload_saved_profiles() -> void:
	BattleAttackEffectProfiles.reload(true)
	_load_drafts()
	_load_profile_into_controls(_current_profile_id)
	status_label.text = "已重新载入保存配置"
