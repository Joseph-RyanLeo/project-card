extends CanvasLayer

## 一棵场景树只保留一个弹窗；直接绘制在根窗口，避开1倍游戏画布的二次放大。
const KeywordHelp = preload("res://scripts/data/card_keyword_help.gd")
const KeywordMotion = preload("res://scripts/ui/keyword_text_effect.gd")
const KEYWORD_WIDTH: float = 164.0 # 卡牌侧边关键词说明框的逻辑宽度
const KEYWORD_SIZE: int = 12 # 关键词解释小字的逻辑字号
const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const MIN_WIDTH := 200.0 # 短描述弹窗的最小逻辑宽度
const EDGE_MARGIN := 12.0 # 弹窗距窗口边缘的安全距离
const CARD_GAP := 8.0 # 弹窗与卡面上下边缘的距离
const INNER_MARGIN := 12.0 # 白色正文区四周的内距
const TITLE_SIZE := 18 # 弹窗标题逻辑字号
const BODY_SIZE := 16 # 弹窗正文逻辑字号
const LINE_SPACING := 3 # 正文各行之间的逻辑间距
const MAX_LINES := 3 # 效果正文最多三行，优先向两侧扩宽

var source: Control
var anchor: Control
var panel: Panel
var title: Label
var body_panel: Panel
var body: RichTextLabel
var keyword_panels: Array[PanelContainer] = []
var _bold_font: FontVariation
var _content_signature: Array = []
var _display: Control
var _context: StringName = &"card"


static func shared(tree: SceneTree) -> CanvasLayer:
	var existing := tree.get_first_node_in_group(&"card_effect_popup") as CanvasLayer
	if existing != null: return existing
	var popup := new()
	popup.name = "CardEffectPopup"
	tree.root.add_child(popup)
	return popup


static func interaction_blocked(tree: SceneTree) -> bool:
	for host: Node in tree.get_nodes_in_group(&"card_interaction_hosts"):
		if host._is_collection_drag_active(): return true
	return false


func _ready() -> void:
	add_to_group(&"card_effect_popup")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30 # 原生窗口文字层，盖在收藏悬停和检视说明之上
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	body_panel = Panel.new()
	body_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body_panel)
	title = _make_label(Color.WHITE)
	panel.add_child(title)
	_bold_font = KeywordMotion.bold_font(Settings.readable_font())
	body = RichTextLabel.new()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.bbcode_enabled = true
	body.scroll_active = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_override("normal_font", Settings.readable_font())
	body.add_theme_font_override("bold_font", _bold_font)
	body.add_theme_color_override("default_color", Color("263239"))
	body.install_effect(KeywordMotion.new())
	body.add_theme_constant_override("line_separation", LINE_SPACING)
	body_panel.add_child(body)
	hide_card()


func _make_label(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Settings.readable_font())
	label.add_theme_color_override("font_color", color)
	return label


func show_card(value: Control, anchor_control: Control = null, paused_battle: bool = false) -> void:
	if not value.can_show_effect_popup() or (not paused_battle and not value.prefers_effect_popup()): return
	_show(value, anchor_control if anchor_control != null else value, &"paused_battle" if paused_battle else &"card")


func show_sticker(surface: Control, gamepad: bool = false) -> void:
	_show(surface, surface, &"gamepad_sticker" if gamepad else &"sticker")


func show_gamepad_card(value: Control, anchor_control: Control) -> void:
	if value.can_show_effect_popup(): _show(value, anchor_control, &"gamepad")


func _show(value: Control, anchor_control: Control, context: StringName) -> void:
	if interaction_blocked(get_tree()) or _menu_open(): return
	if source == value and anchor == anchor_control and _context == context and panel.visible:
		if context == &"card": _update_popup()
		return
	source = value
	anchor = anchor_control
	_context = context
	_display = get_tree().get_first_node_in_group(&"game_display_shell") as Control
	_content_signature.clear()
	panel.show()
	set_process(true)
	_update_popup()


func hide_card(value: Control = null, context: StringName = &"") -> void:
	if value != null and value != source: return
	if not context.is_empty() and context != _context: return
	source = null
	anchor = null
	if is_instance_valid(panel): panel.hide()
	for help_panel: PanelContainer in keyword_panels: help_panel.hide()
	set_process(false)


func hide_gamepad() -> void:
	if _context in [&"gamepad", &"gamepad_sticker"]: hide_card()


func _process(_delta: float) -> void:
	if not is_instance_valid(source) or not is_instance_valid(anchor):
		hide_card()
		return
	if interaction_blocked(get_tree()) or _menu_open() or not anchor.is_visible_in_tree() or anchor.get_viewport().gui_is_dragging():
		hide_card()
		return
	if _context == &"card" and (not source.prefers_effect_popup() or get_tree().paused or not anchor.can_process()):
		hide_card()
		return
	if _context == &"paused_battle" and not get_tree().paused:
		hide_card()
		return
	_update_popup()


func _menu_open() -> bool:
	for menu: Node in get_tree().get_nodes_in_group(&"escape_pause_menus"):
		if menu.blocks_gameplay(): return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_card()


func _update_popup() -> void:
	var bounds: Rect2
	var name_text: String
	var effect: String
	var keep_lines := _context in [&"sticker", &"gamepad_sticker"]
	if keep_lines:
		var help: Dictionary = source.get_hovered_sticker_help()
		if help.is_empty():
			hide_card()
			return
		bounds = help.rect
		var parts: PackedStringArray = String(help.text).split("\n", true, 1)
		name_text = parts[0]
		effect = parts[1] if parts.size() > 1 else ""
	else:
		name_text = source.get_effect_popup_title()
		effect = source.get_effect_popup_text()
		bounds = anchor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, anchor.size)
	var display_scale := 1.0
	if is_instance_valid(_display):
		display_scale = _display.render_container.scale.x
		if anchor.get_viewport() == _display.internal_viewport:
			bounds = _display.render_container.get_global_transform_with_canvas() * bounds
	var window_size := get_viewport().get_visible_rect().size
	var signature := [name_text, effect, window_size, display_scale, keep_lines]
	if signature != _content_signature:
		_content_signature = signature
		_layout_content(name_text, effect, window_size, display_scale, keep_lines)
	var edge := EDGE_MARGIN * display_scale
	var gap := CARD_GAP * display_scale
	var point := Vector2(bounds.get_center().x - panel.size.x * 0.5, bounds.position.y - panel.size.y - gap)
	if point.y < edge: point.y = bounds.end.y + gap
	point.x = clampf(point.x, edge, maxf(edge, window_size.x - panel.size.x - edge))
	point.y = clampf(point.y, edge, maxf(edge, window_size.y - panel.size.y - edge))
	panel.position = point.round()
	_layout_keyword_panels(bounds, window_size, display_scale)


func _layout_content(card_name: String, text: String, window_size: Vector2, display_scale: float, keep_lines: bool = false) -> void:
	var font := Settings.readable_font()
	var font_size := maxi(1, roundi(BODY_SIZE * display_scale))
	var title_size := maxi(1, roundi(TITLE_SIZE * display_scale))
	var inset := roundf(INNER_MARGIN * display_scale)
	var border := maxi(1, roundi(2.0 * display_scale)) # 面板浅色边框宽度
	var available := maxf(1.0, window_size.x - (EDGE_MARGIN * display_scale + inset + border) * 2.0)
	var minimum := minf(available, maxf(MIN_WIDTH * display_scale - inset * 2.0, font.get_string_size(card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x))
	text = text.replace("\r", "").strip_edges()
	if not keep_lines: text = text.replace("\n", " ")
	body.text = "[center]" + KeywordMotion.format_text(text, display_scale) + "[/center]"
	body.add_theme_constant_override("line_separation", roundi(LINE_SPACING * display_scale))
	body.add_theme_font_size_override("normal_font_size", font_size)
	body.add_theme_font_size_override("bold_font_size", font_size)
	body.size = Vector2(available, 1)
	# 直接测量真实富文本，包含粗体字宽与行高；不再用普通Label的度量估算。
	var max_lines := maxi(MAX_LINES, text.get_slice_count("\n"))
	while body.get_line_count() > max_lines and font_size > 1:
		font_size -= 1
		body.add_theme_font_size_override("normal_font_size", font_size)
		body.add_theme_font_size_override("bold_font_size", font_size)
	var low := ceili(minimum)
	var high := ceili(available)
	while low < high:
		var middle := (low + high) / 2
		body.size.x = middle
		if body.get_line_count() <= max_lines: high = middle
		else: low = middle + 1
	body.size.x = low
	var width := float(low) + inset * 2.0
	var title_height := ceilf(font.get_height(title_size) + inset)
	var body_height := ceilf(body.get_content_height() + inset * 2.0)
	panel.size = Vector2(width + border * 2.0, title_height + body_height + border * 2.0)
	panel.add_theme_stylebox_override("panel", _style(Color("252c35"), Color("ced8d5"), border))
	title.text = card_name
	title.add_theme_font_size_override("font_size", title_size)
	title.position = Vector2(border + inset, border)
	title.size = Vector2(width - inset * 2.0, title_height)
	body_panel.position = Vector2(border, border + title_height)
	body_panel.size = Vector2(width, body_height)
	body_panel.add_theme_stylebox_override("panel", _style(Color("f4f2e9"), Color.TRANSPARENT, 0))
	body.position = Vector2(inset, inset)
	body.size = Vector2(width - inset * 2.0, body_height - inset * 2.0)
	_build_keyword_panels(KeywordHelp.in_text(text), display_scale)


func _build_keyword_panels(words: Array[String], display_scale: float) -> void:
	for help_panel: PanelContainer in keyword_panels: help_panel.queue_free()
	keyword_panels.clear()
	for word: String in words:
		var help_panel := PanelContainer.new()
		help_panel.name = "KeywordHelp_" + word
		help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		help_panel.add_theme_stylebox_override("panel", _style(Color("f4f2e9"), Color("9caaa7"), maxi(1, roundi(display_scale))))
		add_child(help_panel)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, roundi(8 * display_scale))
		help_panel.add_child(margin)
		var label := RichTextLabel.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.text = "[b]%s：[/b]%s" % [word, KeywordHelp.DEFINITIONS[word]]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = (KEYWORD_WIDTH - 16) * display_scale
		label.add_theme_font_override("normal_font", Settings.readable_font())
		label.add_theme_font_override("bold_font", _bold_font)
		label.add_theme_color_override("default_color", Color("263239"))
		label.add_theme_font_size_override("normal_font_size", roundi(KEYWORD_SIZE * display_scale))
		label.add_theme_font_size_override("bold_font_size", roundi(KEYWORD_SIZE * display_scale))
		margin.add_child(label)
		keyword_panels.append(help_panel)


func _layout_keyword_panels(bounds: Rect2, window_size: Vector2, display_scale: float) -> void:
	var edge := EDGE_MARGIN * display_scale
	var gap := CARD_GAP * display_scale
	var width := KEYWORD_WIDTH * display_scale
	var right := bounds.end.x + gap
	var left := bounds.position.x - width - gap
	var tops := [bounds.position.y, bounds.position.y]
	for index: int in keyword_panels.size():
		var help_panel := keyword_panels[index]
		help_panel.size = help_panel.get_combined_minimum_size()
		var side := index % 2
		if left < edge: side = 0
		elif right + width > window_size.x - edge: side = 1
		var point := Vector2(right if side == 0 else left, tops[side])
		point = point.clamp(Vector2.ONE * edge, (window_size - Vector2.ONE * edge - help_panel.size).max(Vector2.ONE * edge))
		help_panel.position = point.round()
		tops[side] = point.y + help_panel.size.y + gap
		help_panel.show()


static func _style(background: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.set_border_width_all(border_width)
	return style


static func inspection_content(card_name: String, text: String, display_scale: float = 1.0) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var title_label := Label.new()
	title_label.text = card_name
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", Settings.readable_font())
	title_label.add_theme_font_size_override("font_size", maxi(1, roundi(TITLE_SIZE * display_scale)))
	title_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(title_label)
	var words := KeywordHelp.in_text(text)
	var sections: Array[String] = ["[center]" + KeywordMotion.format_text(text, display_scale) + "[/center]"]
	for word: String in words:
		sections.append("[b]%s：[/b]%s" % [word, KeywordHelp.DEFINITIONS[word]])
	for index: int in sections.size():
		var section := PanelContainer.new()
		section.mouse_filter = Control.MOUSE_FILTER_IGNORE
		section.add_theme_stylebox_override("panel", _style(Color("f4f2e9"), Color("9caaa7"), 0 if index == 0 else maxi(1, roundi(display_scale))))
		content.add_child(section)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, roundi((INNER_MARGIN if index == 0 else 8.0) * display_scale))
		section.add_child(margin)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = sections[index]
		label.add_theme_font_override("normal_font", Settings.readable_font())
		label.add_theme_font_override("bold_font", KeywordMotion.bold_font(Settings.readable_font()))
		var font_size := maxi(1, roundi((BODY_SIZE if index == 0 else KEYWORD_SIZE) * display_scale))
		label.add_theme_font_size_override("normal_font_size", font_size)
		label.add_theme_font_size_override("bold_font_size", font_size)
		label.add_theme_color_override("default_color", Color("263239"))
		label.add_theme_constant_override("line_separation", roundi(LINE_SPACING * display_scale))
		label.install_effect(KeywordMotion.new())
		margin.add_child(label)
	return content


class InspectionPanel extends PanelContainer:
	## 逻辑节点跟随检视层定位，正文直接在实际窗口尺寸上绘制。
	var card_title: String
	var effect_text: String
	var build_content: Callable
	var build_style: Callable
	var _display: Control
	var _visual: PanelContainer
	var _visual_clip: Control
	var _content: VBoxContainer
	var _display_scale := 0.0
	var _logical_width := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logical_width = size.x
		_display = get_tree().get_first_node_in_group(&"game_display_shell") as Control
		if is_instance_valid(_display) and get_viewport() == _display.internal_viewport:
			self_modulate.a = 0.0
			var window_layer := CanvasLayer.new()
			window_layer.name = "InspectionEffectWindowLayer"
			window_layer.layer = 28 # 高于游戏合成画布，低于英雄对白和换场黑幕
			window_layer.custom_viewport = get_tree().root
			add_child(window_layer)
			_visual_clip = Control.new()
			_visual_clip.clip_contents = true
			_visual_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			window_layer.add_child(_visual_clip)
			_visual = PanelContainer.new()
			_visual.name = "InspectionEffectWindowVisual"
			_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_visual_clip.add_child(_visual)
		else:
			_visual = self
		_process(0.0)

	func _process(_delta: float) -> void:
		var window_transform := get_global_transform_with_canvas()
		if _visual != self:
			var display_transform: Transform2D = _display.render_container.get_global_transform_with_canvas()
			window_transform = display_transform * window_transform
			_visual_clip.position = display_transform.origin.round()
			_visual_clip.size = _display.render_container.size * display_transform.get_scale()
		var display_scale := window_transform.get_scale().x
		if not is_equal_approx(display_scale, _display_scale):
			_display_scale = display_scale
			_rebuild_text()
		if _visual == self: return
		_visual.position = window_transform.origin.round() - _visual_clip.position
		_visual.modulate.a = modulate.a
		var menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
		_visual.visible = is_visible_in_tree() and not (menu != null and menu.blocks_gameplay()) and not _display.screen_transition.busy
		size.y = _visual.size.y / display_scale

	func _rebuild_text() -> void:
		if is_instance_valid(_content):
			_visual.remove_child(_content)
			_content.queue_free()
		var width := roundf(_logical_width * _display_scale)
		var border := maxi(1, roundi(2.0 * _display_scale))
		_visual.add_theme_stylebox_override("panel", build_style.call(Color("252c35"), Color("ced8d5"), border))
		_content = build_content.call(card_title, effect_text, _display_scale)
		_content.custom_minimum_size.x = width - border * 2.0
		_visual.add_child(_content)
		_visual.size = Vector2(width, 0.0)
		# 富文本先按真实宽度换行，再更新外框高度，避免沿用窄列的初始行数。
		_content.minimum_size_changed.connect(_fit_text_height)
		_fit_text_height.call_deferred()

	func _fit_text_height() -> void:
		if not is_instance_valid(_content): return
		_visual.size.y = _visual.get_combined_minimum_size().y
