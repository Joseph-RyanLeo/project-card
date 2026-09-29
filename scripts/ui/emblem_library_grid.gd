extends Control

## 背包网格绘制4×7格子；占用判定由贴纸库存模型负责。

const InventoryScript = preload("res://scripts/data/emblem_sticker_inventory.gd")
const CELL_SIZE := InventoryScript.CELL_VISIBLE_SIZE
const CELL_GAP := InventoryScript.CELL_GAP
const CELL_STEP := InventoryScript.CELL_STEP
const COLUMN_COUNT := InventoryScript.COLUMN_COUNT
const ROW_COUNT := InventoryScript.ROW_COUNT
const GRID_ORIGIN := Vector2(114.0, 16.0) # 旋转底图右侧4×7格网的首格坐标

var inventory_view: EmblemLibraryView
var _cell_layer: Control
var _drop_preview: ColorRect
var _preview_cell := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cell_layer = Control.new()
	_cell_layer.name = "GridCells"
	_cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cell_layer)
	for row: int in ROW_COUNT:
		for column: int in COLUMN_COUNT:
			var cell := ColorRect.new()
			cell.name = "Cell_%d_%d" % [column, row]
			cell.position = GRID_ORIGIN + Vector2(column, row) * CELL_STEP
			cell.size = CELL_SIZE
			cell.color = Color("2b1b20")
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cell_layer.add_child(cell)
	_drop_preview = ColorRect.new()
	_drop_preview.name = "DropPreview"
	_drop_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_preview.color = Color(0.4, 1.0, 0.5, 0.32) # 合法落点的半透明预览色
	_drop_preview.visible = false
	_drop_preview.z_index = 1
	add_child(_drop_preview)


func layout_entries(entries: Array[Variant]) -> void:
	_cell_layer.visible = true
	size = inventory_view.get_board_size()
	custom_minimum_size = size
	for entry: Variant in entries:
		var state: Dictionary = entry.definition.get("returned_state", {})
		var span := 2 if entry.is_element_sticker() else 1
		var cell := Vector2i(int(state.get("grid_x", 0)), int(state.get("grid_y", 0)))
		entry.position = GRID_ORIGIN + Vector2(cell) * CELL_STEP
		entry.size = Vector2(span, span) * CELL_SIZE + Vector2.ONE * CELL_GAP * (span - 1)
		entry.custom_minimum_size = entry.size
		entry.update_layout_visuals()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if inventory_view == null or not data is Dictionary:
		_hide_drop_preview()
		return false
	var drag_data := data as Dictionary
	var state := drag_data.get("definition", {}).get("returned_state", {}) as Dictionary
	var instance_id := StringName(String(state.get("instance_id", "")))
	var cell := _cell_for_drag(drag_data, get_global_transform_with_canvas() * at_position)
	var accepted: bool = (
		drag_data.get("kind") == &"emblem_library"
		and not instance_id.is_empty()
		and inventory_view.can_move_sticker(instance_id, cell)
	)
	_show_drop_preview(cell, 2 if bool(state.get("element_sticker", false)) else 1, accepted)
	return accepted


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if inventory_view == null or not data is Dictionary:
		return
	var state := (data as Dictionary).get("definition", {}).get("returned_state", {}) as Dictionary
	var instance_id := StringName(String(state.get("instance_id", "")))
	var cell := _cell_for_drag(data as Dictionary, get_global_transform_with_canvas() * at_position)
	if not instance_id.is_empty():
		inventory_view.move_sticker(instance_id, cell)
	_hide_drop_preview()


func cell_for_drag(data: Dictionary, global_pointer_position: Vector2) -> Vector2i:
	return _cell_for_drag(data, global_pointer_position)


func show_move_preview(instance_id: StringName, cell: Vector2i) -> bool:
	var item := inventory_view.get_inventory_item(instance_id) if inventory_view != null else {}
	if item.is_empty():
		_hide_drop_preview()
		return false
	var accepted := inventory_view.can_move_sticker(instance_id, cell)
	_show_drop_preview(cell, 2 if bool(item.get("element_sticker", false)) else 1, accepted)
	return accepted


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hide_drop_preview()


func _show_drop_preview(cell: Vector2i, span: int, accepted: bool) -> void:
	if cell.x < 0 or cell.y < 0:
		_hide_drop_preview()
		return
	var preview_size := Vector2(span, span) * CELL_SIZE + Vector2.ONE * CELL_GAP * (span - 1)
	if _preview_cell != cell or _drop_preview.size != preview_size:
		_drop_preview.position = GRID_ORIGIN + Vector2(cell) * CELL_STEP
		_drop_preview.size = preview_size
	_preview_cell = cell
	_drop_preview.color = Color(0.4, 1.0, 0.5, 0.32) if accepted else Color(1.0, 0.2, 0.2, 0.35)
	_drop_preview.visible = true


func _hide_drop_preview() -> void:
	if is_instance_valid(_drop_preview):
		_drop_preview.visible = false
	_preview_cell = Vector2i(-1, -1)


func clear_move_preview() -> void:
	_hide_drop_preview()


func _cell_for_drag(data: Dictionary, global_pointer_position: Vector2) -> Vector2i:
	var placement_offset := data.get("placement_offset", Vector2.ZERO) as Vector2
	var item_origin_local := get_global_transform_with_canvas().affine_inverse() * (
		global_pointer_position + placement_offset
	)
	return inventory_view.cell_for_local_position(item_origin_local - GRID_ORIGIN)
