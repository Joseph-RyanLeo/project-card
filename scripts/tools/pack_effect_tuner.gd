extends Control

## 原生滑块编辑共享特效参数；右侧复用真实免费商店，交易只写临时存档。
signal close_requested
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const SHOP_SCENE = preload("res://scenes/tools/RareShopLab.tscn")
const CONTROL_WIDTH: float = 482.0 # 左侧参数面板宽度
const LABEL_WIDTH: float = 206.0 # 参数名称占用的宽度
const SPIN_WIDTH: float = 106.0 # 数值输入框宽度
const PREVIEW_SIZE := Vector2(1280, 720) # 预览使用和正式游戏相同的逻辑画布
const MARGIN: int = 14 # 调整器四周留白

var controls: Dictionary = {}
var preview_shop: Control
var preview_viewport: SubViewport
var preview_container: SubViewportContainer
var preview_holder: Control
var status_label: Label
var _auto_open := false
var _last_pack := 1
var _diagnostic_dialog: FileDialog

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui_theme := Theme.new()
	ui_theme.default_font = preload("res://assets/fonts/chill_7.ttf")
	ui_theme.default_font_size = 14 # 调整器基础字号
	theme = ui_theme
	_build_interface()
	_load_controls()
	preview_shop = SHOP_SCENE.instantiate()
	preview_shop.diagnostic_context = _capture_diagnostic_context
	preview_shop.diagnostic_feedback = _on_diagnostic_feedback
	preview_viewport.add_child(preview_shop)
	preview_shop._escape_pause_menu.set_process_input(false)
	preview_shop._escape_pause_menu.hide()
	preview_shop.close_requested.connect(return_to_shop, CONNECT_DEFERRED)
	preview_holder.resized.connect(_layout_preview)
	_layout_preview.call_deferred()
	status_label.text = "外观实时更新；时长在下次播放生效。未保存的调整在退出时丢弃。"

func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("10161d") # 调整器背景颜色
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10) # 标题、内容和状态之间的间距
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "开包特效调整器"
	title.add_theme_font_size_override("font_size", 22) # 调整器标题字号
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header, "保存", save_settings, "SaveEffects")
	_button(header, "重新载入", reload_settings, "ReloadEffects")
	_button(header, "恢复默认", reset_settings, "ResetEffects")
	_button(header, "导出诊断日志", export_diagnostics, "ExportPackDiagnostics")
	_button(header, "返回 · Esc", close_requested.emit, "CloseEffects")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14) # 参数面板和预览之间的间距
	layout.add_child(body)
	var tabs := TabContainer.new()
	tabs.name = "ParameterTabs"
	tabs.custom_minimum_size.x = CONTROL_WIDTH
	body.add_child(tabs)
	var groups := {}
	for field: Dictionary in Settings.FIELDS:
		if not groups.has(field.group):
			var scroll := ScrollContainer.new()
			scroll.name = field.group
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			tabs.add_child(scroll)
			var rows := VBoxContainer.new()
			rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.add_theme_constant_override("separation", 10) # 参数行垂直间距
			scroll.add_child(rows)
			groups[field.group] = rows
		_add_slider(groups[field.group], field)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var preview_title := Label.new()
	preview_title.text = "免费测试商店 · 可直接购买、检视、撕包和连点收卡"
	right.add_child(preview_title)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	_button(actions, "普通开包", play_pack.bind(0), "PreviewNormal")
	_button(actions, "传奇开包", play_pack.bind(1), "PreviewRare")
	_button(actions, "重播", replay, "ReplayEffects")
	_button(actions, "IV光环", show_rare_card, "PreviewHalo")
	_button(actions, "回商店", return_to_shop, "PreviewShop")
	preview_holder = Control.new()
	preview_holder.name = "PreviewHolder"
	preview_holder.clip_contents = true
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview_holder)
	preview_container = SubViewportContainer.new()
	preview_container.size = PREVIEW_SIZE
	preview_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_holder.add_child(preview_container)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(PREVIEW_SIZE)
	preview_viewport.disable_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview_viewport)
	var help := Label.new()
	help.text = "包装颤抖按4×检视画面像素计算；此缩小预览也可操作。\n普通：4张I＋1张II　传奇：4张I＋1张IV；测试收藏与本局独立。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(help)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)

func _button(parent: Control, text: String, action: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 36 # 按钮高度
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _add_slider(parent: VBoxContainer, field: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = field.label
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = field.key
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.custom_minimum_size.x = SPIN_WIDTH
	spin.suffix = field.unit
	row.add_child(spin)
	for control: Range in [slider, spin]:
		control.min_value = field.min
		control.max_value = field.max
		control.step = field.step
		control.tooltip_text = "%s\n默认：%s %s" % [field.key, field.default, field.unit]
		control.value_changed.connect(_on_value_changed.bind(String(field.key)))
	controls[field.key] = {"slider": slider, "spin": spin}

func _on_value_changed(value: float, key: String) -> void:
	Settings.set_value(key, value)
	var normalized: float = Settings.get_values()[key]
	controls[key].slider.set_value_no_signal(normalized)
	controls[key].spin.set_value_no_signal(normalized)
	status_label.text = "已调整 %s：%s；点击保存后用于正式开包，重播可查看新的动画时长。" % [key, normalized]

func _load_controls() -> void:
	for key: String in controls:
		controls[key].slider.set_value_no_signal(Settings.get_values()[key])
		controls[key].spin.set_value_no_signal(Settings.get_values()[key])

func save_settings() -> void:
	var error := Settings.save()
	status_label.text = "已保存；正式开包与下次启动使用这些参数。" if error == OK else "保存失败：%s；当前预览调整仍保留。" % error_string(error)

func reload_settings() -> void:
	Settings.reload()
	_load_controls()
	status_label.text = "已恢复上次保存的参数。"

func reset_settings() -> void:
	Settings.reset_defaults()
	_load_controls()
	status_label.text = "已恢复默认；点击保存才会覆盖已保存的参数。"

func _capture_diagnostic_context() -> Dictionary:
	var hovered := preview_viewport.gui_get_hovered_control() if is_instance_valid(preview_viewport) else null
	return {
		"effects": Settings.get_values().duplicate(true), "auto_open_pending": _auto_open, "last_pack": _last_pack,
		"preview_scale": preview_container.scale, "preview_position": preview_container.position,
		"preview_mouse": preview_viewport.get_mouse_position(), "preview_hovered": String(hovered.get_path()) if is_instance_valid(hovered) else "",
		"window_size": get_window().size, "viewport_size": get_viewport_rect().size,
		"tree_paused": get_tree().paused, "preview_can_process": preview_shop.can_process(),
	}

func export_diagnostics() -> void:
	if not is_instance_valid(_diagnostic_dialog):
		_diagnostic_dialog = FileDialog.new()
		_diagnostic_dialog.name = "PackDiagnosticSaveDialog"
		_diagnostic_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		_diagnostic_dialog.title = "导出开包诊断日志"
		_diagnostic_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_diagnostic_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_diagnostic_dialog.filters = PackedStringArray(["*.json ; JSON 开包诊断日志"])
		_diagnostic_dialog.file_selected.connect(_save_diagnostics)
		add_child(_diagnostic_dialog)
		var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if DirAccess.dir_exists_absolute(documents): _diagnostic_dialog.current_dir = documents
	_diagnostic_dialog.current_file = "project-card-pack-diagnostics-%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	_diagnostic_dialog.popup_centered_ratio(0.72)

func _save_diagnostics(path: String) -> void:
	# 沿用正式导出的只读流程及防止覆盖交易存档的校验，导出当前预览Main。
	if is_instance_valid(_diagnostic_dialog): _diagnostic_dialog.hide()
	preview_shop._save_run_diagnostic_file(path)

func _on_diagnostic_feedback(message: String) -> void:
	status_label.text = message.replace("\n", " ")

func _layout_preview() -> void:
	var ratio := minf(preview_holder.size.x / PREVIEW_SIZE.x, preview_holder.size.y / PREVIEW_SIZE.y)
	preview_container.scale = Vector2.ONE * ratio
	preview_container.position = (preview_holder.size - PREVIEW_SIZE * ratio) * 0.5

func return_to_shop() -> void:
	_auto_open = false
	preview_shop._close_card_inspection(true)

func play_pack(index: int) -> void:
	return_to_shop()
	_last_pack = index
	# 只刷新实验室独立服务；沿用真实商品购买事务和动画。
	var empty_stickers: Array[Dictionary] = []
	preview_shop.ordinary_shop_service.refresh(preview_shop._get_shop_card_definitions(), [], empty_stickers, empty_stickers)
	preview_shop._refresh_ordinary_shop_panel()
	preview_shop._on_ordinary_shop_offer_pressed(index)
	_auto_open = true

func replay() -> void:
	play_pack(_last_pack)

func show_rare_card() -> void:
	var sequence: CardPackOpening = preview_shop._card_pack_opening
	if not is_instance_valid(sequence) or sequence.phase != CardPackOpening.Phase.INSPECTING or not sequence.has_rare:
		status_label.text = "先播放传奇开包；抽出卡牌后，点击IV光环跳到IV卡。"
		return
	while sequence.current_index < sequence.cards.size() - 1:
		sequence.collect_current()
	if is_instance_valid(sequence.animation): sequence.animation.kill()
	sequence._reveal_card(false)

func _process(_delta: float) -> void:
	if not _auto_open: return
	var sequence: CardPackOpening = preview_shop._card_pack_opening
	if is_instance_valid(sequence) and sequence.phase == CardPackOpening.Phase.SEALED and sequence._background_cards.size() == sequence.cards.size():
		_auto_open = false
		sequence.auto_tear()

func _input(event: InputEvent) -> void:
	if is_instance_valid(_diagnostic_dialog) and _diagnostic_dialog.visible: return
	if event is InputEventMouseButton and event.pressed:
		preview_shop._record_run_diagnostic("pack_tuner_pointer", {"button": event.button_index, "position": event.position, "preview_rect": Rect2(preview_container.global_position, PREVIEW_SIZE * preview_container.scale)}, true)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()

func prepare_close() -> void:
	if is_instance_valid(preview_shop): preview_shop._close_card_inspection(true)

func _exit_tree() -> void:
	Settings.reload() # 丢弃未保存草稿；已经保存的配置继续用于正式开包。
