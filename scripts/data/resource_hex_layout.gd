class_name ResourceHexLayout
extends RefCounted

## 图4固定栏位的轴向六边格纯数据几何，保持形状平移不变。

const BOARD_SIZE := Vector2i(170, 160) # 图4固定栏位尺寸
const COLUMN_COUNT := 6 # 原图固定列数
const COLUMN_STEP := 27 # 相邻列格心横向距离（像素）
const ROW_STEP := 32 # 同列格心纵向距离（像素）
const HEX_ORIGIN := Vector2i(17, 32) # 轴向坐标(0,0)格心（像素）
const AXIAL_NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

static func valid_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for q in COLUMN_COUNT:
		var first_r := floori(float(q) / 2.0)
		var count := 5 if q % 2 == 1 else 4
		for row in count:
			cells.append(Vector2i(q, first_r + row))
	return cells

static func center(cell: Vector2i) -> Vector2:
	return Vector2(HEX_ORIGIN.x + 27 * cell.x, HEX_ORIGIN.y + 32 * cell.y - 16 * cell.x)

static func is_valid_cell(cell: Vector2i) -> bool:
	return valid_cells().has(cell)

static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in AXIAL_NEIGHBORS:
		result.append(cell + offset)
	return result

static func create_migration_shape(size: int) -> Array[Vector2i]:
	if size < 1 or size > 5:
		return []
	var shape: Array[Vector2i] = []
	for index in size:
		shape.append(Vector2i(0, index))
	return shape

static func create_random_shape(size: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	if size < 1 or size > 5 or rng == null:
		return []
	var starts := valid_cells()
	while not starts.is_empty():
		var shape: Array[Vector2i] = [starts.pop_at(rng.randi_range(0, starts.size() - 1))]
		while shape.size() < size:
			var frontier: Array[Vector2i] = []
			for cell in shape:
				for adjacent in neighbors(cell):
					if not shape.has(adjacent) and not frontier.has(adjacent):
						frontier.append(adjacent)
			var viable: Array[Vector2i] = []
			for candidate in frontier:
				var trial := shape.duplicate()
				trial.append(candidate)
				if find_any_placement(normalize_shape(trial)):
					viable.append(candidate)
			if viable.is_empty():
				break
			shape.append(viable[rng.randi_range(0, viable.size() - 1)])
		if shape.size() == size:
			return normalize_shape(shape)
	return []

static func normalize_shape(shape: Array[Vector2i]) -> Array[Vector2i]:
	if shape.is_empty():
		return []
	var min_q := shape[0].x
	var min_r := shape[0].y
	for cell in shape:
		min_q = mini(min_q, cell.x)
		min_r = mini(min_r, cell.y)
	var result: Array[Vector2i] = []
	for cell in shape:
		result.append(cell - Vector2i(min_q, min_r))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func is_connected_shape(shape: Array[Vector2i]) -> bool:
	if shape.is_empty() or shape.size() > 5:
		return false
	var unique: Dictionary = {}
	for cell in shape:
		if unique.has(cell): return false
		unique[cell] = true
	var reached: Dictionary = {shape[0]: true}
	var pending: Array[Vector2i] = [shape[0]]
	while not pending.is_empty():
		for adjacent in neighbors(pending.pop_front()):
			if unique.has(adjacent) and not reached.has(adjacent):
				reached[adjacent] = true
				pending.append(adjacent)
	return reached.size() == shape.size()

static func can_place(shape: Array[Vector2i], anchor: Vector2i, occupied: Dictionary, disabled: Dictionary) -> bool:
	if not is_connected_shape(shape): return false
	var seen: Dictionary = {}
	for offset in shape:
		var cell := anchor + offset
		if not is_valid_cell(cell) or seen.has(cell) or occupied.has(cell) or disabled.has(cell): return false
		seen[cell] = true
	return true

static func find_any_placement(shape: Array[Vector2i], occupied: Dictionary = {}, disabled: Dictionary = {}) -> bool:
	if not is_connected_shape(shape):
		return false
	for board_cell in valid_cells():
		for shape_cell in shape:
			var anchor := board_cell - shape_cell
			if can_place(shape, anchor, occupied, disabled):
				return true
	return false
