extends CanvasLayer

## 一棵场景树只保留一个弹窗；直接绘制在根窗口，避开1倍游戏画布的二次放大。
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
var body: Label
var _content_signature: Array = []
var _display: Control


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
	layer = 30 # 高于收藏动态卡面，暂停、检视打开时立即收起
	panel = Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	body_panel = Panel.new()
	body_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body_panel)
	title = _make_label(Color.WHITE)
	panel.add_child(title)
	body = _make_label(Color("263239"))
	body.add_theme_constant_override("line_spacing", LINE_SPACING)
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


func show_card(value: Control, anchor_control: Control = null) -> void:
	if interaction_blocked(get_tree()) or not value.prefers_effect_popup() or not value.can_show_effect_popup(): return
	source = value
	anchor = anchor_control if anchor_control != null else value
	_display = get_tree().get_first_node_in_group(&"game_display_shell") as Control
	_content_signature.clear()
	panel.show()
	set_process(true)
	_update_popup()


func hide_card(value: Control = null) -> void:
	if value != null and value != source: return
	source = null
	anchor = null
	if is_instance_valid(panel): panel.hide()
	set_process(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(source) or not is_instance_valid(anchor):
		hide_card()
		return
	if interaction_blocked(get_tree()) or not source.prefers_effect_popup() or get_tree().paused or not anchor.is_visible_in_tree() or not anchor.can_process() or anchor.get_viewport().gui_is_dragging():
		hide_card()
		return
	for menu: Node in get_tree().get_nodes_in_group(&"escape_pause_menus"):
		if menu.is_menu_open(): hide_card(); return
	_update_popup()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_card()


func _update_popup() -> void:
	var physical := anchor.get_global_transform_with_canvas()
	var display_scale := 1.0
	if is_instance_valid(_display):
		display_scale = _display.render_container.scale.x
		if anchor.get_viewport() == _display.internal_viewport:
			physical = _display.render_container.get_global_transform_with_canvas() * physical
	var bounds := physical * Rect2(Vector2.ZERO, anchor.size)
	var window_size := get_viewport().get_visible_rect().size
	var effect: String = source.get_effect_popup_text()
	var signature := [source.get_effect_popup_title(), effect, window_size, display_scale]
	if signature != _content_signature:
		_content_signature = signature
		_layout_content(String(signature[0]), effect, window_size, display_scale)
	var edge := EDGE_MARGIN * display_scale
	var gap := CARD_GAP * display_scale
	var point := Vector2(bounds.get_center().x - panel.size.x * 0.5, bounds.position.y - panel.size.y - gap)
	if point.y < edge: point.y = bounds.end.y + gap
	point.x = clampf(point.x, edge, maxf(edge, window_size.x - panel.size.x - edge))
	point.y = clampf(point.y, edge, maxf(edge, window_size.y - panel.size.y - edge))
	panel.position = point.round()


func _layout_content(card_name: String, text: String, window_size: Vector2, display_scale: float) -> void:
	var font := Settings.readable_font()
	var font_size := maxi(1, roundi(BODY_SIZE * display_scale))
	var title_size := maxi(1, roundi(TITLE_SIZE * display_scale))
	var inset := roundf(INNER_MARGIN * display_scale)
	var border := maxi(1, roundi(2.0 * display_scale)) # 面板浅色边框宽度
	var available := maxf(1.0, window_size.x - (EDGE_MARGIN * display_scale + inset + border) * 2.0)
	var minimum := minf(available, maxf(MIN_WIDTH * display_scale - inset * 2.0, font.get_string_size(card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x))
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	# 卡牌旧正文中的手动换行不应强迫新弹窗超过三行。
	text = text.replace("\r", "").replace("\n", " ").strip_edges()
	paragraph.add_string(text, font, font_size)
	paragraph.width = available
	# 极窄窗口才缩字；正常卡牌始终先扩宽，完整保留正文。
	while paragraph.get_line_count() > MAX_LINES and font_size > 1:
		font_size -= 1
		paragraph.clear()
		paragraph.add_string(text, font, font_size)
	var low := ceili(minimum)
	var high := ceili(available)
	while low < high:
		var middle := (low + high) / 2
		paragraph.width = middle
		if paragraph.get_line_count() <= MAX_LINES: high = middle
		else: low = middle + 1
	paragraph.width = low
	var lines := PackedStringArray()
	for index: int in paragraph.get_line_count():
		var span := paragraph.get_line_range(index)
		lines.append(text.substr(span.x, span.y - span.x).strip_edges())
	var width := float(low) + inset * 2.0
	var title_height := ceilf(font.get_height(title_size) + inset)
	var body_height := ceilf(font.get_height(font_size) * maxi(1, lines.size()) + LINE_SPACING * display_scale * maxi(0, lines.size() - 1) + inset * 2.0)
	panel.size = Vector2(width + border * 2.0, title_height + body_height + border * 2.0)
	panel.add_theme_stylebox_override("panel", _style(Color("252c35"), Color("ced8d5"), border))
	title.text = card_name
	title.add_theme_font_size_override("font_size", title_size)
	title.position = Vector2(border + inset, border)
	title.size = Vector2(width - inset * 2.0, title_height)
	body_panel.position = Vector2(border, border + title_height)
	body_panel.size = Vector2(width, body_height)
	body_panel.add_theme_stylebox_override("panel", _style(Color("f4f2e9"), Color.TRANSPARENT, 0))
	body.text = "\n".join(lines)
	body.add_theme_font_size_override("font_size", font_size)
	body.add_theme_constant_override("line_spacing", roundi(LINE_SPACING * display_scale))
	body.position = Vector2(inset, inset)
	body.size = Vector2(width - inset * 2.0, body_height - inset * 2.0)


func _style(background: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.set_border_width_all(border_width)
	return style
