class_name EmblemStickerInventory
extends RefCounted

## 单枚贴纸的固定容量背包；显示节点不负责判定实例是否仍被拥有。

const COLUMN_COUNT := 4
const ROW_COUNT := 7
const CELL_VISIBLE_SIZE := Vector2(14.0, 14.0) # 单格可见贴纸尺寸
const CELL_GAP := 3.0 # 相邻格之间的可见间隔
const CELL_STEP := CELL_VISIBLE_SIZE + Vector2.ONE * CELL_GAP # 命中与占格共用的格距

var _items: Array[Dictionary] = []


func get_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _items:
		result.append(item.duplicate(true))
	return result


func get_item(instance_id: StringName) -> Dictionary:
	for item: Dictionary in _items:
		if StringName(String(item.get("instance_id", ""))) == instance_id:
			return item.duplicate(true)
	return {}


func can_add(state: Dictionary, target: Vector2i = Vector2i(-1, -1)) -> bool:
	if not _is_valid_identity(state) or _contains_instance(state.get("instance_id", "")):
		return false
	var cell := target if _is_cell(target) else _find_open_cell(_items, _span_for(state))
	return _can_place(_items, state, cell, &"")


func add(state: Dictionary) -> bool:
	if not _is_valid_identity(state) or _contains_instance(state.get("instance_id", "")):
		return false
	var candidate := state.duplicate(true)
	var span := _span_for(candidate)
	var requested := Vector2i(int(candidate.get("grid_x", -1)), int(candidate.get("grid_y", -1)))
	var has_saved_cell := candidate.has("grid_x") or candidate.has("grid_y")
	if has_saved_cell:
		if not candidate.has("grid_x") or not candidate.has("grid_y") or not _can_place(_items, candidate, requested, &""):
			return false
	else:
		requested = _find_open_cell(_items, span)
	if not _can_place(_items, candidate, requested, &""):
		return false
	candidate["grid_x"] = requested.x
	candidate["grid_y"] = requested.y
	candidate["grid_span"] = span
	_items.append(candidate)
	return true


func restore(states: Array) -> bool:
	var restored := EmblemStickerInventory.new()
	for value: Variant in states:
		if not value is Dictionary or not restored.add(value as Dictionary):
			return false
	_items = restored._items
	return true


func remove(instance_id: StringName) -> Dictionary:
	for index: int in _items.size():
		if StringName(String(_items[index].get("instance_id", ""))) != instance_id:
			continue
		return _items.pop_at(index)
	return {}


func move(instance_id: StringName, target: Vector2i) -> bool:
	for index: int in _items.size():
		var item := _items[index]
		if StringName(String(item.get("instance_id", ""))) != instance_id:
			continue
		if not _can_place(_items, item, target, instance_id):
			return false
		_items[index]["grid_x"] = target.x
		_items[index]["grid_y"] = target.y
		return true
	return false


func can_move(instance_id: StringName, target: Vector2i) -> bool:
	for item: Dictionary in _items:
		if StringName(String(item.get("instance_id", ""))) == instance_id:
			return _can_place(_items, item, target, instance_id)
	return false


func cell_for_local_position(point: Vector2) -> Vector2i:
	var cell := Vector2i(roundi(point.x / CELL_STEP.x), roundi(point.y / CELL_STEP.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= COLUMN_COUNT or cell.y >= ROW_COUNT:
		return Vector2i(-1, -1)
	return cell


func _contains_instance(raw_id: Variant) -> bool:
	var instance_id := String(raw_id)
	for item: Dictionary in _items:
		if String(item.get("instance_id", "")) == instance_id:
			return true
	return false


func _is_valid_identity(state: Dictionary) -> bool:
	var kind := String(state.get("kind", "emblem"))
	var item_id: String = String(state.get("wound_id", "") if kind == "wound" else state.get("emblem_id", ""))
	return String(state.get("instance_id", "")).strip_edges() != "" and not item_id.strip_edges().is_empty() and kind in ["emblem", "wound"]


func _span_for(state: Dictionary) -> int:
	return 2 if bool(state.get("element_sticker", false)) else 1


func _find_open_cell(items: Array[Dictionary], span: int) -> Vector2i:
	for row: int in range(ROW_COUNT - span + 1):
		for column: int in range(COLUMN_COUNT - span + 1):
			var candidate := Vector2i(column, row)
			if _can_place(items, {"element_sticker": span == 2}, candidate, &""):
				return candidate
	return Vector2i(-1, -1)


func _can_place(
	items: Array[Dictionary],
	state: Dictionary,
	target: Vector2i,
	ignored_instance_id: StringName
) -> bool:
	var span := _span_for(state)
	if target.x < 0 or target.y < 0 or target.x + span > COLUMN_COUNT or target.y + span > ROW_COUNT:
		return false
	for existing: Dictionary in items:
		if StringName(String(existing.get("instance_id", ""))) == ignored_instance_id:
			continue
		var other_span := _span_for(existing)
		var other := Vector2i(int(existing.get("grid_x", -1)), int(existing.get("grid_y", -1)))
		if (
			target.x < other.x + other_span
			and target.x + span > other.x
			and target.y < other.y + other_span
			and target.y + span > other.y
		):
			return false
	return true


func _is_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLUMN_COUNT and cell.y < ROW_COUNT
