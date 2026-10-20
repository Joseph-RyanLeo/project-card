extends Control

const FULL: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_time_bar.png")
const EMPTY: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_time_empty.png")
const EYE: Texture2D = preload("res://assets/ui/board_revision_20261019/battle_time_eye.png")
const BLUE_LEFT := Rect2(37, 5, 383, 6) # 左侧完整槽内范围，右端固定在中央装饰旁
const BLUE_RIGHT := Rect2(478, 5, 383, 6) # 右侧完整槽内范围，左端固定在中央装饰旁
const BLUE_SAMPLE := Rect2(67, 7, 1, 1) # 从原图纯蓝区域取色，铺满槽位而非沿用原图未满示例
var remaining_ratio: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = FULL.get_size()


func update_time(elapsed: float, fatigue_start: float) -> void:
	remaining_ratio = clampf((fatigue_start - elapsed) / fatigue_start, 0.0, 1.0) if fatigue_start > 0.0 else 0.0
	tooltip_text = "距疲劳风暴 %.1f秒" % maxf(fatigue_start - elapsed, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_texture(EMPTY, Vector2.ZERO)
	var width := floorf(BLUE_LEFT.size.x * remaining_ratio)
	if width > 0.0:
		for row: int in int(BLUE_LEFT.size.y):
			var corner := 1.0 if row == 0 or row == int(BLUE_LEFT.size.y) - 1 else 0.0
			var row_width := width - corner
			if row_width <= 0.0:
				continue
			var left := Rect2(BLUE_LEFT.end.x - row_width, BLUE_LEFT.position.y + row, row_width, 1)
			var right := Rect2(BLUE_RIGHT.position + Vector2(0, row), Vector2(row_width, 1))
			draw_texture_rect_region(FULL, left, BLUE_SAMPLE)
			draw_texture_rect_region(FULL, right, BLUE_SAMPLE)
	draw_texture(EYE, Vector2(441, 3)) # 中线眼睛按原稿位置显示，不随剩余时间消失
