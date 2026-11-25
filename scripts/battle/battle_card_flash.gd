extends Node2D

## 灼烧和通用受击共用每张卡的瞬白轮廓与衰减手感。
const CARD_HEIGHT := 136.0 # 卡面原生高度，用于等比调整切角
const CORNER_PIXELS := 2.0 # 原生卡面瞬白剪影的切角


func show_pulse(cards: Array[Rect2], remaining: float, peak: float = 1.0) -> void:
	visible = remaining > 0.0 and not cards.is_empty()
	if not visible: return
	modulate.a = remaining * remaining * peak
	while get_child_count() < cards.size(): add_child(Polygon2D.new())
	for index: int in get_child_count():
		var surface := get_child(index) as Polygon2D
		surface.visible = index < cards.size()
		if not surface.visible: continue
		var rect := cards[index]
		if surface.position != rect.position: surface.position = rect.position
		if surface.get_meta(&"card_size", Vector2.ZERO) == rect.size: continue
		surface.set_meta(&"card_size", rect.size)
		var corner := CORNER_PIXELS * rect.size.y / CARD_HEIGHT
		var w := rect.size.x
		var h := rect.size.y
		surface.polygon = PackedVector2Array([
			Vector2(corner, 0), Vector2(w - corner, 0), Vector2(w, corner), Vector2(w, h - corner),
			Vector2(w - corner, h), Vector2(corner, h), Vector2(0, h - corner), Vector2(0, corner),
		])
