extends RefCounted

const ITEM_GAP := 2.0 # 指示物和交付区物件边界之间的最小留白


static func clamp_origin(area: Rect2, item_size: Vector2, requested: Vector2) -> Vector2:
	if item_size.x > area.size.x or item_size.y > area.size.y: return Vector2.INF
	return requested.clamp(area.position, area.end - item_size)


static func nearest_clear_origin(area: Rect2, item_size: Vector2, requested: Vector2, occupied: Array[Rect2]) -> Vector2:
	var wanted := clamp_origin(area, item_size, requested)
	if not wanted.is_finite(): return wanted
	var obstacles: Array[Rect2] = []
	for bounds: Rect2 in occupied: obstacles.append(bounds.grow(ITEM_GAP))
	if _is_clear(Rect2(wanted, item_size), obstacles): return wanted

	# 在障碍和底板的边界上找最近的合法位置，沿用指示物区的避让规则。
	var minimum := area.position
	var maximum := area.end - item_size
	var xs: Array[float] = [wanted.x, minimum.x, maximum.x]
	var ys: Array[float] = [wanted.y, minimum.y, maximum.y]
	for bounds: Rect2 in obstacles:
		xs.append(clampf(bounds.position.x - item_size.x, minimum.x, maximum.x))
		xs.append(clampf(bounds.end.x, minimum.x, maximum.x))
		ys.append(clampf(bounds.position.y - item_size.y, minimum.y, maximum.y))
		ys.append(clampf(bounds.end.y, minimum.y, maximum.y))
	var best := Vector2.INF
	var distance := INF
	for x: float in xs:
		for y: float in ys:
			var point := Vector2(x, y)
			var candidate_distance := wanted.distance_squared_to(point)
			if candidate_distance < distance and _is_clear(Rect2(point, item_size), obstacles):
				best = point
				distance = candidate_distance
	return best


static func _is_clear(candidate: Rect2, obstacles: Array[Rect2]) -> bool:
	for bounds: Rect2 in obstacles:
		if candidate.intersects(bounds): return false
	return true
