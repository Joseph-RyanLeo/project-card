class_name EmblemLibraryView
extends Panel

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

## 纹章库的唯一 UI 实例。
## 普通收藏界面和大卡牌检视只改变同一节点的位置、缩放与滚动布局。

const EmblemLibraryEntryScript = preload("res://scripts/ui/emblem_library_entry.gd")
const EmblemLibraryGridScript = preload("res://scripts/ui/emblem_library_grid.gd")

const NORMAL_SIZE := Vector2(124, 248) # 常规工作包不越过左侧收藏书本边界
const INSPECT_LOGICAL_SIZE := Vector2(86, 120) # 两列贴纸加滚动条的窄栏，不遮挡居中卡牌
const NORMAL_ZOOM := 1.0 # 常规素材逻辑缩放
const INSPECT_ZOOM := 4.0 # 检视素材相对原生像素放大倍数

var _definitions: Array[Dictionary] = []
var _entries: Array[Variant] = []
var _title: Label
var _scroll: ScrollContainer
var _grid: Control
var _inspect_mode := false
var _drag_enabled := false
var _scraper: TextureRect
var _returned: Array[Dictionary] = []
var _item_kind := "emblem"


func set_item_kind(value: String) -> void:
	_item_kind = value
	if is_instance_valid(_scraper):
		_scraper.visible = _item_kind != "wound"


func return_sticker(state: Dictionary) -> void:
	var instance_id := String(state.get("instance_id", ""))
	if not instance_id.is_empty():
		for existing: Dictionary in _returned:
			if String(existing.get("instance_id", "")) == instance_id:
				return
	_returned.append(state.duplicate(true))
	_refresh_entries()
	_scroll.scroll_vertical = 0


func consume_returned(state: Dictionary) -> void:
	for index: int in _returned.size():
		if _returned[index].get("instance_id") == state.get("instance_id"):
			_returned.remove_at(index)
			_refresh_entries()
			return


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


func get_scroll_position() -> int:
	return _scroll.scroll_vertical if is_instance_valid(_scroll) else 0


func set_scroll_position(value: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = maxi(value, 0)


func _build_controls() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.07, 0.075, 0.96)
	style.border_color = Color("d1aa58")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_color_override("font_color", Color("f5df9b"))
	_title.add_theme_font_size_override("font_size", 9)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)
	_grid = EmblemLibraryGridScript.new()
	_grid.name = "Grid"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid)
	_scraper = preload("res://scripts/ui/sticker_scraper.gd").new()
	_scraper.name = "Scraper"
	_scraper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scraper.texture = RuneStickerStyle.get_scraper_texture()
	_scraper.size = Vector2(28, 28)
	var scraper_scale := 28.0 / 59.0
	_scraper.blade_point = RuneStickerStyle.get_scraper_hit_point() * scraper_scale
	var source_blade_rect: Rect2 = RuneStickerStyle.get_scraper_hit_rect()
	_scraper.blade_rect = Rect2(
		source_blade_rect.position * scraper_scale,
		source_blade_rect.size * scraper_scale
	)
	_scraper.enabled = _drag_enabled
	_scraper.visible = _item_kind != "wound"
	_scraper.click_carry_requested.connect(_on_item_click_carry_requested)
	add_child(_scraper)


func _set_display_layout() -> void:
	if not is_instance_valid(_title) or not is_instance_valid(_scroll):
		return
	var zoom := INSPECT_ZOOM if _inspect_mode else NORMAL_ZOOM
	scale = Vector2(zoom, zoom)
	custom_minimum_size = INSPECT_LOGICAL_SIZE if _inspect_mode else NORMAL_SIZE
	size = custom_minimum_size
	_title.position = Vector2(4, 1)
	_title.size = Vector2(size.x - 8, 16)
	_title.text = ("伤势工作区" if _item_kind == "wound" else "纹章工作包") if _inspect_mode else ("伤势工作区（测试）" if _item_kind == "wound" else "纹章库（开发）")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scraper.position = Vector2(size.x - 31, 1)
	_scroll.position = Vector2(3, 31)
	_scroll.size = Vector2(size.x - 6, size.y - 34)


func _refresh_entries() -> void:
	if not is_instance_valid(_grid):
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_entries.clear()
	var display_definitions: Array[Dictionary] = []
	for state: Dictionary in _returned:
		if String(state.get("kind", "emblem")) != _item_kind:
			continue
		for definition: Dictionary in _definitions:
			var state_id: Variant = state.get("wound_id", "") if _item_kind == "wound" else state.get("emblem_id", "")
			if String(definition.id) == String(state_id):
				var returned_definition := definition.duplicate(true)
				returned_definition["returned_state"] = state
				display_definitions.append(returned_definition)
	display_definitions.append_array(_definitions)
	for definition: Dictionary in display_definitions:
		var entry: Variant = EmblemLibraryEntryScript.new()
		entry.configure(definition, _drag_enabled)
		entry.click_carry_requested.connect(_on_item_click_carry_requested)
		_grid.add_child(entry)
		_entries.append(entry)
	_grid.layout_entries(_entries)


func _on_item_click_carry_requested(data: Dictionary, pointer_global_position: Vector2) -> void:
	click_carry_requested.emit(data, pointer_global_position)
