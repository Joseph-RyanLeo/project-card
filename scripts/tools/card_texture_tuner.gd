extends Control

## 全局卡牌纹理编辑；草稿只影响预览，保存成功才通知全部正式卡面。
signal close_requested
const Settings = preload("res://scripts/ui/card_finish_settings.gd")
const Renderer = preload("res://scripts/ui/card_finish_preview.gd")
const Catalog = preload("res://scripts/tools/card_art_tuner.gd")
const CARD = preload("res://scenes/ui/CardView.tscn")
const Appearance = preload("res://scripts/data/card_appearance.gd")
const LEFT_WIDTH: float = 430.0 # 左侧全局参数面板宽度
const PREVIEW_SCALE: float = 2.0 # 卡牌以整数倍预览，保留素材像素边缘
const PREVIEW_STEP: float = 240.0 # 三张卡预览之间的横向间距
const INSPECTION_SCALE: float = 4.0 # 右键检视的整数放大倍率
const INSPECTION_DIM: float = 0.78 # 检视时周围界面的压暗程度
const STYLE_TABS := [0, 0, 0, 1, 2, 3, 4, 5] # 各预览风格对应的参数页；前三种共用闪纹
const TAB_STYLES := [0, 3, 4, 5, 6, 7] # 点击参数页时默认展示的风格
const STYLE_NAMES := ["银闪", "金闪", "彩闪", "全息", "法线", "碎闪", "磨砂闪", "指纹闪"]
var settings_path := Settings.PATH
var controls: Dictionary = {}
var sliders: Dictionary = {}
var previews: Array[InspectionCardSurface] = []
var draft: Resource
var baseline: Resource
var style_selector: OptionButton
var card_selector: OptionButton
var tabs: TabContainer
var status_label: Label
var save_button: Button
var reload_button: Button
var preview_area: Control
var _paths: Array[String] = []
var _inspection: CardInspectionOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui := Theme.new()
	ui.default_font = preload("res://scripts/ui/ui_typography.gd").font()
	ui.default_font_size = 16 # 调整器正文的可读字号
	theme = ui
	_build_interface()
	reload_settings()


func _button(parent: Node, title: String, callback: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("111923") # 调整器背景色
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14) # 页面边缘留白
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12) # 标题、内容、状态之间的间距
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := Label.new()
	title.text = "卡牌纹理调整器"
	title.add_theme_font_size_override("font_size", 24) # 页面标题字号
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var actions := HBoxContainer.new()
	page.add_child(actions)
	save_button = _button(actions, "保存并应用所有卡牌", save_settings, "SaveCardTextures")
	reload_button = _button(actions, "重新载入", reload_settings, "ReloadCardTextures")
	_button(actions, "恢复默认", reset_settings, "ResetCardTextures")
	_button(actions, "返回 · Esc", close_requested.emit, "CloseCardTextures")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16) # 参数区和预览区的间隔
	page.add_child(body)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.x = LEFT_WIDTH
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for group: String in ["闪纹", "全息", "法线", "碎闪", "磨砂闪", "指纹闪"]:
		var scroll := ScrollContainer.new()
		scroll.name = group
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 16) # 各参数组之间的纵向间距
		scroll.add_child(column)
		for field: Dictionary in Settings.FIELDS:
			if field.group != group: continue
			var label := Label.new()
			label.text = field.label
			label.tooltip_text = field.get("help", "")
			column.add_child(label)
			var row := HBoxContainer.new()
			column.add_child(row)
			var slider := HSlider.new()
			slider.min_value = field.min
			slider.max_value = field.max
			slider.step = field.step
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.tooltip_text = label.tooltip_text
			row.add_child(slider)
			var spin := SpinBox.new()
			spin.name = String(field.key)
			spin.min_value = field.min
			spin.max_value = field.max
			spin.step = field.step
			spin.custom_minimum_size.x = 104 # 数值输入框的宽度
			spin.tooltip_text = label.tooltip_text
			row.add_child(spin)
			controls[field.key] = spin
			sliders[field.key] = slider
			slider.value_changed.connect(_change.bind(field.key))
			spin.value_changed.connect(_change.bind(field.key))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var selectors := HBoxContainer.new()
	right.add_child(selectors)
	style_selector = OptionButton.new()
	style_selector.name = "TexturePreviewStyle"
	for title_text: String in STYLE_NAMES: style_selector.add_item(title_text)
	selectors.add_child(style_selector)
	card_selector = OptionButton.new()
	card_selector.name = "TexturePreviewCard"
	card_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paths = Catalog.discover_card_resource_paths()
	for path: String in _paths:
		var definition: CardData = load(path)
		card_selector.add_item(definition.display_name)
	selectors.add_child(card_selector)
	var help := Label.new()
	help.text = "指向卡牌预览光影，右键放大检视；三张卡共用纹理参数。\n草稿仅影响预览，保存后全卡牌、现有界面及下次启动统一生效。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(help)
	preview_area = Control.new()
	preview_area.name = "CardTexturePreviews"
	preview_area.custom_minimum_size = Vector2(720, 400) # 三张两倍卡牌的预览空间
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview_area)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status_label)
	style_selector.item_selected.connect(_select_style)
	card_selector.item_selected.connect(func(_index: int): _build_previews())
	tabs.tab_changed.connect(func(index: int):
		var wanted: int = TAB_STYLES[index]
		if STYLE_TABS[style_selector.selected] == index: return
		style_selector.select(wanted)
		_build_previews())


func _select_style(index: int) -> void:
	tabs.current_tab = STYLE_TABS[index]
	_build_previews()


func _build_previews() -> void:
	_close_inspection()
	for surface: InspectionCardSurface in previews: surface.queue_free()
	previews.clear()
	if draft == null or _paths.is_empty(): return
	for index: int in mini(3, _paths.size()):
		var data: CardData = load(_paths[(card_selector.selected + index) % _paths.size()])
		var owned := OwnedCard.new()
		owned.initialize(data, StringName("texture_preview_%d" % index), 0)
		match style_selector.selected:
			0, 1, 2: owned.surface_finish = (Appearance.Surface.SILVER + style_selector.selected) as Appearance.Surface
			3: owned.art_finish = Appearance.Art.HOLOGRAPHIC
			4: owned.surface_finish = Appearance.Surface.EMBOSSED
			5: owned.surface_finish = Appearance.Surface.FRACTURED
			6: owned.surface_finish = Appearance.Surface.FROSTED
			7: owned.surface_finish = Appearance.Surface.FINGERPRINT
		var card: CardView = CARD.instantiate()
		card.set_card_data(data)
		card.set_owned_card(owned)
		add_child(card)
		var surface := InspectionCardSurface.new()
		surface.name = "TexturePreview%d" % index
		preview_area.add_child(surface)
		surface.setup(card, Callable(), Callable())
		surface.position = Vector2(index * PREVIEW_STEP, 48) # 卡面上方预留倾斜空间
		surface.scale = Vector2.ONE * PREVIEW_SCALE
		card._finish_controller.settings_source = draft
		card._finish_controller.refresh()
		surface.gui_input.connect(_on_preview_input.bind(surface))
		previews.append(surface)


func _on_preview_input(event: InputEvent, source: InspectionCardSurface) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		source.accept_event()
		_open_inspection.call_deferred(source)


func _open_inspection(source: InspectionCardSurface) -> void:
	if is_instance_valid(_inspection) or not is_instance_valid(source): return
	_inspection = CardInspectionOverlay.new()
	_inspection.name = "TextureInspection"
	_inspection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspection.offset_left = preview_area.get_global_rect().position.x - global_position.x # 检视只覆盖右侧预览区，左侧参数保持可操作
	_inspection.z_index = 200 # 大卡与蒙版覆盖右侧预览
	_inspection.close_requested.connect(_close_inspection)
	add_child(_inspection)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, INSPECTION_DIM)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_inspection())
	_inspection.add_child(dim)
	var card: CardView = CARD.instantiate()
	card.set_card_data(source.card.card_data)
	card.set_owned_card(source.card.get_owned_card())
	_inspection.add_child(card)
	var surface := InspectionCardSurface.new()
	surface.name = "TextureInspectionSurface"
	_inspection.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.scale = Vector2.ONE * INSPECTION_SCALE
	surface.position = ((_inspection.size - surface.size * INSPECTION_SCALE) * 0.5).round()
	card._finish_controller.settings_source = draft
	card._finish_controller.refresh()
	var hint := Label.new()
	hint.text = "左侧调整实时生效 · 右键／Esc／点击背景返回"
	hint.position = Vector2(24, size.y - 36) # 底部说明避开大卡实体
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection.add_child(hint)
	var close := _button(_inspection, "关闭检视 · Esc", _close_inspection, "CloseTextureInspection")
	close.position = Vector2(_inspection.size.x - 200, 64) # 右上角关闭按钮避开显示模式入口
	close.size = Vector2(176, 40) # 检视关闭按钮的点击范围


func _close_inspection() -> void:
	if not is_instance_valid(_inspection): return
	_inspection.hide()
	_inspection.set_process_input(false)
	_inspection.queue_free()
	_inspection = null


func _change(value: float, key: String) -> void:
	if draft == null: return
	draft.set_value(key, value)
	controls[key].set_value_no_signal(draft.get(key))
	sliders[key].set_value_no_signal(draft.get(key))
	for surface: InspectionCardSurface in previews: surface.card._finish_controller.refresh()
	if is_instance_valid(_inspection):
		var large: InspectionCardSurface = _inspection.get_node("TextureInspectionSurface")
		large.card._finish_controller.refresh()
	_update_status()


func has_changes() -> bool:
	if draft == null or baseline == null: return false
	for field: Dictionary in Settings.FIELDS:
		if not is_equal_approx(float(draft.get(field.key)), float(baseline.get(field.key))): return true
	return false


func _update_status() -> void:
	save_button.disabled = not has_changes()
	status_label.text = "有未保存的全局纹理修改 · 当前仅预览。" if has_changes() else "当前显示已保存的全局纹理。"


func _load_controls() -> void:
	for field: Dictionary in Settings.FIELDS:
		controls[field.key].set_value_no_signal(draft.get(field.key))
		sliders[field.key].set_value_no_signal(draft.get(field.key))
	_build_previews()
	_update_status()


func reload_settings() -> void:
	var latest := ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if latest == null:
		status_label.text = "无法读取纹理配置，原有草稿保留。"
		return
	baseline = latest
	draft = latest.duplicate(true)
	_load_controls()


func reset_settings() -> void:
	draft = Settings.new()
	_load_controls()


func save_settings() -> bool:
	var latest := ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if latest == null:
		status_label.text = "无法读取纹理配置，尚未保存，草稿保留。"
		return false
	for field: Dictionary in Settings.FIELDS:
		if not is_equal_approx(float(draft.get(field.key)), float(baseline.get(field.key))): latest.set_value(field.key, draft.get(field.key))
	var error := ResourceSaver.save(latest, settings_path)
	if error != OK:
		status_label.text = "纹理保存失败，草稿保留，请重试。"
		return false
	Renderer.SETTINGS.copy_values(latest)
	Renderer.SETTINGS.emit_changed()
	baseline = latest
	draft = latest.duplicate(true)
	_load_controls()
	status_label.text = "已保存，全体卡牌的纹理已更新；下次启动继续使用。"
	return true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if is_instance_valid(_inspection): _close_inspection()
		else: close_requested.emit()
