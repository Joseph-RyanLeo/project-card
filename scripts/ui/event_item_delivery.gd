extends Panel

const FreeItemPlacement = preload("res://scripts/ui/free_item_placement.gd")
const WIDTH := 138.0 # 独立交付区与一张完整卡牌的宽度相适应
const COLUMN_GAP := 10.0 # 正文和交付区间距
const ITEM_SIZE := Vector2(14, 14) # 普通纹章按原图尺寸
const ITEM_SCALE := 2.0 # 交付区纹章按整像素倍数显示
const ITEM_INSET := 8.0 # 纹章与交付区边缘的留白
const TOOLBOX_BUTTON_HEIGHT := 24.0 # 工具箱按钮独立于交付区，放在纸面上方
const TOOLBOX_BUTTON_GAP := 5.0 # 打开按钮与交付区的间距

var accepts_item: Callable
var place_item: Callable
var open_button: Button
var card_slot: PanelContainer
var _board: Control
var _main: Control
var _board_position := Vector2.ZERO
var _item_layer: Control
var _entries := {}
var _rest_style: StyleBox
var _ready_style: StyleBox
var _previewing := false


func setup(board: Control, area: Rect2, slot_hint: String, main: Control) -> void:
	_board = board
	_main = main
	var toolbox_row := Vector2(0, TOOLBOX_BUTTON_HEIGHT + TOOLBOX_BUTTON_GAP)
	_board_position = area.position + toolbox_row
	name = "EventItemDelivery"
	position = _board_position
	size = area.size - toolbox_row
	tooltip_text = slot_hint
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rest_style = _style(Color("866246"), Color("614632"))
	_ready_style = _style(Color("788454"), Color("e0c589"))
	add_theme_stylebox_override("panel", _rest_style)
	board.add_child(self)
	_item_layer = Control.new()
	_item_layer.size = size
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_item_layer)
	mouse_exited.connect(_set_preview.bind(false))


func set_open_button(button: Button) -> void:
	open_button = button
	button.position = _board_position - Vector2(0, TOOLBOX_BUTTON_HEIGHT + TOOLBOX_BUTTON_GAP)
	button.size = Vector2(size.x, TOOLBOX_BUTTON_HEIGHT)


func set_toolbox_host(overlay: Control = null) -> void:
	var host := overlay if overlay != null else _board
	if get_parent() != host: reparent(host, overlay != null)
	if overlay == null: position = _board_position
	z_index = 2 if overlay != null else 0 # 展开时在暗幕上方，携带预览仍在最前
	if is_instance_valid(open_button): open_button.visible = overlay == null
	if is_instance_valid(card_slot):
		# 工具箱展开时让卡面下方的共用区域接收纹章拖放。
		card_slot.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if overlay != null else Control.MOUSE_BEHAVIOR_INHERITED


func set_card_visible(value: bool) -> void:
	if not is_instance_valid(card_slot): return
	card_slot.visible = value
	_item_layer.visible = not value


func contains(canvas_position: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(canvas_position)


func item_canvas_scale() -> Vector2:
	return get_global_transform_with_canvas().get_scale() * ITEM_SCALE


func item_entry(id: StringName) -> EmblemLibraryEntry:
	return _entries.get(id) as EmblemLibraryEntry


func sync_items(items: Array[Dictionary], positions: Dictionary, can_drag: bool) -> void:
	var current: Array[StringName] = []
	for definition: Dictionary in items:
		var id := StringName(definition.returned_state.instance_id)
		var entry := item_entry(id)
		if not is_instance_valid(entry): entry = _add_item_entry(id)
		if entry.definition != definition: entry.configure(definition, can_drag)
		entry.set_drag_enabled(can_drag)
		entry.position = positions[id]
		current.append(id)
	for id: StringName in _entries.keys():
		if id in current: continue
		var entry := item_entry(id)
		entry.hide()
		entry.queue_free()
		_entries.erase(id)


func _add_item_entry(id: StringName) -> EmblemLibraryEntry:
	var entry := EmblemLibraryEntry.new()
	entry.keep_carry_ghost = false
	entry.free_placement = true
	entry.drop_target = self
	entry.size = ITEM_SIZE
	entry.scale = Vector2.ONE * ITEM_SCALE
	entry.click_carry_requested.connect(_main._on_click_carry_requested)
	_item_layer.add_child(entry)
	_entries[id] = entry
	return entry


func preview_item(canvas_position: Vector2, data: Dictionary) -> void:
	_set_preview(_resolve_item_position(canvas_position, data).is_finite())


func drop_item(data: Dictionary, canvas_position: Vector2) -> bool:
	var point := _resolve_item_position(canvas_position, data)
	if not point.is_finite(): return false
	_set_preview(false)
	place_item.call(data, point)
	return true


func _resolve_item_position(canvas_position: Vector2, data: Dictionary) -> Vector2:
	if not contains(canvas_position) or not accepts_item.call(data): return Vector2.INF
	var transform := get_global_transform_with_canvas()
	var requested := InspectionItemDrag.placement_origin(transform, canvas_position, data, item_canvas_scale())
	var area := Rect2(Vector2.ZERO, size).grow(-ITEM_INSET)
	var footprint := ITEM_SIZE * ITEM_SCALE
	var occupied: Array[Rect2] = []
	for entry: EmblemLibraryEntry in _entries.values():
		if entry != data.get("source_entry"):
			occupied.append(Rect2(entry.position, footprint))
	return FreeItemPlacement.nearest_clear_origin(area, footprint, requested, occupied)


func _can_drop_data(point: Vector2, data: Variant) -> bool:
	if not data is Dictionary: return false
	var accepted := _resolve_item_position(get_global_transform_with_canvas() * point, data).is_finite()
	if not accepted and is_instance_valid(card_slot):
		accepted = card_slot._can_drop_data(Vector2.ZERO, data)
	_set_preview(accepted)
	return accepted


func _drop_data(point: Vector2, data: Variant) -> void:
	if not data is Dictionary: return
	if not drop_item(data, get_global_transform_with_canvas() * point) and is_instance_valid(card_slot):
		card_slot._drop_data(Vector2.ZERO, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: _set_preview(false)


func _set_preview(value: bool) -> void:
	if value == _previewing: return
	_previewing = value
	add_theme_stylebox_override("panel", _ready_style if value else _rest_style)


static func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	return style
