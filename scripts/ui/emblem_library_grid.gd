extends Control

## 纹章工作包的占格容器：以固定网格单元为基础，按条目顺序寻找完整连通空位。

const CELL_SIZE := Vector2(15.0, 15.0) # 每个工作包基础格的逻辑尺寸
const COLUMN_COUNT := 4 # 每排固定四个基础格，总内容宽60逻辑像素


func layout_entries(entries: Array[Variant]) -> void:
	var occupied: Array[Array] = []
	var used_rows := 0
	for entry: Variant in entries:
		var span := 2 if entry.is_element_sticker() else 1
		var cell := _find_open_region(occupied, span)
		var required_rows := cell.y + span
		while occupied.size() < required_rows:
			var row: Array[bool] = []
			row.resize(COLUMN_COUNT)
			row.fill(false)
			occupied.append(row)
		for row_index: int in range(cell.y, cell.y + span):
			for column_index: int in range(cell.x, cell.x + span):
				occupied[row_index][column_index] = true
		entry.position = Vector2(cell) * CELL_SIZE
		entry.size = Vector2(span, span) * CELL_SIZE
		entry.custom_minimum_size = entry.size
		entry.update_layout_visuals()
		used_rows = maxi(used_rows, required_rows)
	size = Vector2(COLUMN_COUNT * CELL_SIZE.x, used_rows * CELL_SIZE.y)
	custom_minimum_size = size


func _find_open_region(occupied: Array[Array], span: int) -> Vector2i:
	var search_rows := maxi(occupied.size(), 1)
	for row_index: int in range(search_rows):
		for column_index: int in range(COLUMN_COUNT - span + 1):
			var is_open := true
			for offset_y: int in span:
				for offset_x: int in span:
					var check_row := row_index + offset_y
					var check_column := column_index + offset_x
					if (
						check_row < occupied.size()
						and occupied[check_row][check_column]
					):
						is_open = false
			if is_open:
				return Vector2i(column_index, row_index)
	return Vector2i(0, search_rows)
