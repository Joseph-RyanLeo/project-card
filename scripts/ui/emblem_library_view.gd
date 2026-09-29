class_name EmblemLibraryView
extends Panel

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

## 纹章库的唯一 UI 实例。
## 普通收藏界面和大卡牌检视只改变同一节点的位置、缩放与视口布局。

const EmblemLibraryEntryScript = preload("res://scripts/ui/emblem_library_entry.gd")
const EmblemLibraryGridScript = preload("res://scripts/ui/emblem_library_grid.gd")
const StickerInventoryScript = preload("res://scripts/data/emblem_sticker_inventory.gd")
const BOARD_TEXTURE: Texture2D = preload("res://assets/card_ui/emblems/source/sticker_board_horizontal.png")

const BOARD_SIZE := Vector2(195.0, 148.0) # 横放工具箱按原图像素尺寸显示
const NORMAL_ZOOM := 1.0 # 常规素材逻辑缩放
const INSPECT_ZOOM := 4.0 # 检视素材相对原生像素放大倍数

var _definitions: Array[Dictionary] = []
var _entries: Array[Variant] = []
var _title: Label
var _scroll: ScrollContainer
var _grid: Control
var _inspect_mode := false
var _drag_enabled := false
var _board: TextureRect
var _empty_panel_style: StyleBoxEmpty
var _scraper: TextureRect
var _sticker_inventory: Variant = StickerInventoryScript.new()


func return_sticker(state: Dictionary) -> bool:
	var instance_id := String(state.get("instance_id", ""))
	var candidate := state.duplicate(true)
	if instance_id.is_empty() or not _has_item_definition(candidate):
		return false
	if String(candidate.get("kind", "emblem")) == "wound":
		candidate["element_sticker"] = false
	else:
		candidate["kind"] = "emblem"
		candidate["element_sticker"] = _is_element_sticker_id(StringName(String(candidate.get("emblem_id", ""))))
	if not _sticker_inventory.add(candidate):
		return false
	if is_node_ready():
		_refresh_entries()
	return true


func consume_returned(state: Dictionary) -> bool:
	var removed: Dictionary = _sticker_inventory.remove(StringName(String(state.get("instance_id", ""))))
	if removed.is_empty():
		return false
	_refresh_entries()
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_controls()
	_refresh_entries()
	_set_display_layout()


func set_definitions(values: Array[Dictionary]) -> void:
	_definitions.assign(values)
	if is_node_ready():
		_refresh_entries()


func set_inspect_mode(value: bool) -> void:
	_inspect_mode = value
	if is_node_ready():
		_set_display_layout()
		_refresh_entries()


func set_drag_enabled(value: bool) -> void:
	_drag_enabled = value
	if is_instance_valid(_scraper):
		_scraper.enabled = value
	for entry: Variant in _entries:
		entry.set_drag_enabled(value)


func get_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_definitions)
	return result


func get_inventory_state() -> Array[Dictionary]:
	return _sticker_inventory.get_items()


func get_inventory_item(instance_id: StringName) -> Dictionary:
	return _sticker_inventory.get_item(instance_id)


func cell_for_local_position(point: Vector2) -> Vector2i:
	return _sticker_inventory.cell_for_local_position(point)


func get_inventory_capacity() -> int:
	return StickerInventoryScript.COLUMN_COUNT * StickerInventoryScript.ROW_COUNT


func restore_inventory_state(states: Array) -> bool:
	var normalized: Variant = _normalize_inventory_states(states)
	if normalized == null or not _sticker_inventory.restore(normalized as Array):
		return false
	if is_node_ready():
		_refresh_entries()
	return true


func can_restore_inventory_state(states: Array) -> bool:
	var normalized: Variant = _normalize_inventory_states(states)
	if normalized == null:
		return false
	var validation_inventory: Variant = StickerInventoryScript.new()
	return validation_inventory.restore(normalized as Array)


func _normalize_inventory_states(states: Array) -> Variant:
	var normalized: Array[Dictionary] = []
	for value: Variant in states:
		if not value is Dictionary:
			return null
		var item := (value as Dictionary).duplicate(true)
		if not _has_item_definition(item):
			return null
		if String(item.get("kind", "emblem")) == "wound":
			item["element_sticker"] = false
		else:
			item["kind"] = "emblem"
			item["element_sticker"] = _is_element_sticker_id(StringName(String(item.get("emblem_id", ""))))
		normalized.append(item)
	return normalized


func can_add_sticker(state: Dictionary) -> bool:
	var candidate := state.duplicate(true)
	if not _has_item_definition(candidate):
		return false
	if String(candidate.get("kind", "emblem")) == "wound":
		candidate["element_sticker"] = false
	else:
		candidate["element_sticker"] = _is_element_sticker_id(StringName(String(candidate.get("emblem_id", ""))))
	return _sticker_inventory.can_add(candidate)


func move_sticker(instance_id: StringName, target_cell: Vector2i) -> bool:
	if not _sticker_inventory.move(instance_id, target_cell):
		return false
	_refresh_entries()
	return true


func can_move_sticker(instance_id: StringName, target_cell: Vector2i) -> bool:
	return _sticker_inventory.can_move(instance_id, target_cell)


func try_move_sticker_global(instance_id: StringName, global_position: Vector2, drag_data: Dictionary) -> bool:
	if not _drag_enabled or not is_instance_valid(_grid):
		return false
	return move_sticker(instance_id, _grid.cell_for_drag(drag_data, global_position))


func preview_sticker_move_global(instance_id: StringName, global_position: Vector2, drag_data: Dictionary) -> bool:
	if not is_instance_valid(_grid):
		return false
	var cell: Vector2i = _grid.cell_for_drag(drag_data, global_position)
	return _grid.show_move_preview(instance_id, cell)


func clear_sticker_move_preview() -> void:
	if is_instance_valid(_grid):
		_grid.clear_move_preview()


func _is_element_sticker_id(emblem_id: StringName) -> bool:
	for definition: Dictionary in _definitions:
		if StringName(String(definition.get("id", ""))) == emblem_id:
			return definition.get("target", "emblem") == "rune"
	return false


func _has_item_definition(state: Dictionary) -> bool:
	var is_wound := String(state.get("kind", "emblem")) == "wound"
	var item_id := StringName(String(state.get("wound_id", "") if is_wound else state.get("emblem_id", "")))
	if item_id.is_empty():
		return false
	for definition: Dictionary in _definitions:
		if StringName(String(definition.get("id", ""))) == item_id:
			return String(definition.get("status_kind", "emblem")) == ("wound" if is_wound else "emblem")
	return false


func get_scroll_position() -> int:
	return _scroll.scroll_vertical if is_instance_valid(_scroll) else 0


func set_scroll_position(value: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = maxi(value, 0)


func get_board_size() -> Vector2:
	return BOARD_SIZE


func get_display_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size)


func _build_controls() -> void:
	_empty_panel_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", _empty_panel_style)
	_board = TextureRect.new()
	_board.name = "Board"
	_board.texture = BOARD_TEXTURE
	_board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board.stretch_mode = TextureRect.STRETCH_KEEP
	_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.z_index = -1
	_board.size = BOARD_SIZE
	add_child(_board)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_color_override("font_color", Color("f5df9b"))
	_title.add_theme_font_size_override("font_size", 9)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_grid = EmblemLibraryGridScript.new()
	_grid.name = "Grid"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid)
	_grid.inventory_view = self
	_scraper = preload("res://scripts/ui/sticker_scraper.gd").new()
	_scraper.name = "Scraper"
	_scraper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scraper.texture = RuneStickerStyle.get_scraper_texture()
	_scraper.size = Vector2(28, 28) # 刮刀图标在工作包中的显示尺寸
	var scraper_scale := 28.0 / 59.0 # 刮刀素材换算到图标尺寸的命中比例
	_scraper.blade_point = RuneStickerStyle.get_scraper_hit_point() * scraper_scale
	var source_blade_rect: Rect2 = RuneStickerStyle.get_scraper_hit_rect()
	_scraper.blade_rect = Rect2(
		source_blade_rect.position * scraper_scale,
		source_blade_rect.size * scraper_scale
	)
	_scraper.enabled = _drag_enabled
	_scraper.position = Vector2(34.0, 62.0)
	_scraper.click_carry_requested.connect(_on_item_click_carry_requested)
	add_child(_scraper)


func _set_display_layout() -> void:
	if not is_instance_valid(_title) or not is_instance_valid(_scroll):
		return
	var zoom := INSPECT_ZOOM if _inspect_mode else NORMAL_ZOOM
	scale = Vector2(zoom, zoom)
	custom_minimum_size = BOARD_SIZE
	size = custom_minimum_size
	var board_size := get_board_size()
	_title.position = Vector2(4.0, 4.0) # 标题放在底图左侧工具区内
	_title.size = Vector2(87.0, 16.0) # 标题限制在底图左侧工具区
	_update_title()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scroll.position = Vector2.ZERO
	_scroll.size = board_size


func _refresh_entries() -> void:
	if not is_instance_valid(_grid):
		return
	for entry: Variant in _entries:
		if is_instance_valid(entry):
			_grid.remove_child(entry)
			entry.queue_free()
	_entries.clear()
	var display_definitions: Array[Dictionary] = []
	for state: Dictionary in _sticker_inventory.get_items():
		var item_id := String(state.get("wound_id", "") if String(state.get("kind", "emblem")) == "wound" else state.get("emblem_id", ""))
		for definition: Dictionary in _definitions:
			if String(definition.id) == item_id:
				var inventory_definition := definition.duplicate(true)
				inventory_definition["returned_state"] = state
				display_definitions.append(inventory_definition)
	for definition: Dictionary in display_definitions:
		var entry: Variant = EmblemLibraryEntryScript.new()
		entry.configure(definition, _drag_enabled)
		entry.click_carry_requested.connect(_on_item_click_carry_requested)
		_grid.add_child(entry)
		_entries.append(entry)
	_grid.layout_entries(_entries)
	_update_title()


func _update_title() -> void:
	if not is_instance_valid(_title):
		return
	_title.text = "工具箱 %d/%d" % [
		_sticker_inventory.get_items().size(),
		get_inventory_capacity(),
	]


func _on_item_click_carry_requested(data: Dictionary, pointer_global_position: Vector2) -> void:
	click_carry_requested.emit(data, pointer_global_position)
