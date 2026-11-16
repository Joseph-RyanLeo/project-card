extends Control

signal closed
signal volume_changed(value: float)
signal display_changed(value: int)
signal pixel_edge_aa_changed(enabled: bool)
signal tool_requested(tool: StringName)

const Style = preload("res://scripts/ui/menu_style.gd")
const TextSettings = preload("res://scripts/ui/card_text_display_settings.gd")
const PANEL_RECT := Rect2(350, 134, 580, 452) # 共用设置面板位置与尺寸，为画面选项预留一行
const TOOLS_RECT := Rect2(350, 56, 580, 608) # 开发工具子页完整位于720p画布内
var text_settings_path := TextSettings.SETTINGS_PATH
var volume_slider: HSlider
var display_option: OptionButton
var pixel_edge_aa_option: CheckButton
var text_option: OptionButton
var status: Label
var developer_tools_enabled := false
var _settings_body: PanelContainer
var _tools: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72) # 设置页的背景压暗程度
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	_settings_body = panel
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16) # 设置行垂直间距
	panel.add_child(body)
	var title := Label.new()
	title.text = "设置"
	body.add_child(title)
	display_option = OptionButton.new()
	display_option.name = "SettingsDisplayMode"
	for text: String in ["720p 窗口", "1080p 窗口", "2K 窗口", "自适应全屏"]: display_option.add_item(text)
	display_option.item_selected.connect(display_changed.emit)
	body.add_child(display_option)
	pixel_edge_aa_option = CheckButton.new()
	pixel_edge_aa_option.name = "SettingsPixelEdgeAA"
	pixel_edge_aa_option.text = "像素边缘抗锯齿（非整数倍率）"
	pixel_edge_aa_option.tooltip_text = "在 1080p 等非整数倍率下，只在像素边界混色。"
	pixel_edge_aa_option.toggled.connect(pixel_edge_aa_changed.emit)
	body.add_child(pixel_edge_aa_option)
	var audio := HBoxContainer.new()
	body.add_child(audio)
	var audio_label := Label.new()
	audio_label.text = "音量"
	audio.add_child(audio_label)
	volume_slider = HSlider.new()
	volume_slider.name = "BattleVolumeSlider"
	volume_slider.unique_name_in_owner = true
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = 25 # 首次创建时的默认音量百分比
	volume_slider.value_changed.connect(volume_changed.emit)
	audio.add_child(volume_slider)
	text_option = OptionButton.new()
	text_option.name = "CardTextDisplayMode"
	text_option.add_item("卡牌文字：卡牌显示", TextSettings.Mode.CARD)
	text_option.add_item("卡牌文字：弹窗显示", TextSettings.Mode.POPUP)
	text_option.item_selected.connect(_set_text_mode)
	body.add_child(text_option)
	status = Label.new()
	status.name = "SettingsStatus"
	status.add_theme_font_size_override("font_size", 16) # 保存状态提示字号
	status.text = "设置会自动保存"
	body.add_child(status)
	var developer_button := Style.button(body, "开发工具", "SettingsDeveloperToolsButton", open_tools)
	developer_button.visible = developer_tools_enabled
	Style.button(body, "返回", "SettingsBackButton", closed.emit)
	_build_tools()
	sync_text_mode()


func _build_tools() -> void:
	_tools = PanelContainer.new()
	_tools.name = "SettingsDeveloperTools"
	_tools.position = TOOLS_RECT.position
	_tools.size = TOOLS_RECT.size
	add_child(_tools)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10) # 工具按钮之间的纵向间距
	_tools.add_child(body)
	var title := Label.new()
	title.text = "开发工具"
	body.add_child(title)
	for entry: Array in preload("res://scripts/ui/developer_tool_catalog.gd").ENTRIES:
		Style.button(body, entry[0], entry[1], tool_requested.emit.bind(entry[2]))
	Style.button(body, "返回设置", "DeveloperToolsBackButton", close_subpage)
	_tools.hide()


func open_tools() -> void:
	_settings_body.hide()
	_tools.show()


func close_subpage() -> bool:
	if not _tools.visible: return false
	_tools.hide()
	_settings_body.show()
	return true


func sync_values(volume: float, mode: int, pixel_edge_aa: bool, display_available: bool = true) -> void:
	volume_slider.set_value_no_signal(volume)
	display_option.select(mode)
	display_option.disabled = not display_available or Engine.is_embedded_in_editor()
	pixel_edge_aa_option.set_pressed_no_signal(pixel_edge_aa)
	pixel_edge_aa_option.disabled = not display_available
	sync_text_mode()


func sync_text_mode() -> void:
	if text_option != null: text_option.select(1 if TextSettings.is_popup_mode() else 0)


func show_save_result(error: Error) -> void:
	status.text = "设置已保存" if error == OK else "本次已生效，偏好保存失败（%d）" % error


func _set_text_mode(index: int) -> void:
	show_save_result(TextSettings.set_mode(get_tree(), index as TextSettings.Mode, true, text_settings_path))
