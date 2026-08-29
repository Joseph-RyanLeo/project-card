@tool
class_name RuneNumberDisplay
extends Control

## 使用美术提供的非等宽卢恩数字图集绘制卡面数值。
##
## 数字 1 比其余数字窄，因此不能再交给等宽 BitmapFont。普通模式逐个
## 使用真实字形宽度绘制；冷却模式把中号整数、3×3 小数点和小号小数
## 组合在同一个节点里，避免三个节点各自维护位置。

enum NumberStyle {
	LARGE,
	MEDIUM,
	COOLDOWN,
}

const LARGE_TEXTURE: Texture2D = preload("res://assets/fonts/rune_numbers_large.png")
const MEDIUM_TEXTURE: Texture2D = preload("res://assets/fonts/rune_numbers_medium.png")
const SMALL_TEXTURE: Texture2D = preload("res://assets/fonts/rune_numbers_small.png")
const DECIMAL_POINT_TEXTURE: Texture2D = preload("res://assets/fonts/rune_decimal_point.png")

const LARGE_GLYPH_RECTS: Dictionary = {
	"1": Rect2(0, 0, 7, 14),
	"2": Rect2(10, 0, 10, 14),
	"3": Rect2(23, 0, 10, 14),
	"4": Rect2(35, 0, 10, 14),
	"5": Rect2(47, 0, 10, 14),
	"6": Rect2(59, 0, 10, 14),
	"7": Rect2(71, 0, 10, 14),
	"8": Rect2(84, 0, 10, 14),
	"9": Rect2(96, 0, 10, 14),
	"0": Rect2(109, 0, 10, 14),
}
const MEDIUM_GLYPH_RECTS: Dictionary = {
	"1": Rect2(0, 0, 6, 12),
	"2": Rect2(8, 0, 8, 12),
	"3": Rect2(19, 0, 8, 12),
	"4": Rect2(29, 0, 8, 12),
	"5": Rect2(39, 0, 8, 12),
	"6": Rect2(49, 0, 8, 12),
	"7": Rect2(59, 0, 8, 12),
	"8": Rect2(69, 0, 8, 12),
	"9": Rect2(79, 0, 8, 12),
	"0": Rect2(89, 0, 8, 12),
}
const SMALL_GLYPH_RECTS: Dictionary = {
	"1": Rect2(0, 0, 5, 8),
	"2": Rect2(7, 0, 6, 8),
	"3": Rect2(15, 0, 6, 8),
	"4": Rect2(23, 0, 6, 8),
	"5": Rect2(31, 0, 6, 8),
	"6": Rect2(39, 0, 6, 8),
	"7": Rect2(47, 0, 6, 8),
	"8": Rect2(55, 0, 6, 8),
	"9": Rect2(63, 0, 6, 8),
	"0": Rect2(71, 0, 6, 8),
}

const LARGE_HEIGHT: float = 14.0
const MEDIUM_HEIGHT: float = 12.0
const SMALL_HEIGHT: float = 8.0
const COOLDOWN_FRACTION_TOP: float = 4.0 # 卡面 y=24 起算，小号数字绝对顶部为 y=28
const COOLDOWN_POINT_TOP: float = 9.0 # 卡面 y=24 起算，小数点绝对顶部为 y=33
const COOLDOWN_JOIN_OVERLAP: float = 1.0 # 小数点左右黑边各与相邻数字重合 1px

@export var number_style: NumberStyle = NumberStyle.LARGE:
	set(value):
		number_style = value
		_sync_size_and_redraw()
@export var character_spacing: int = 0: # 多位卢恩数字相邻字形之间的空隙（像素）
	set(value):
		character_spacing = value
		_sync_size_and_redraw()
@export var text: String = "":
	set(value):
		text = value
		_sync_size_and_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync_size_and_redraw()


func _draw() -> void:
	match number_style:
		NumberStyle.LARGE:
			_draw_digit_run(text, LARGE_TEXTURE, LARGE_GLYPH_RECTS, Vector2.ZERO)
		NumberStyle.MEDIUM:
			_draw_digit_run(text, MEDIUM_TEXTURE, MEDIUM_GLYPH_RECTS, Vector2.ZERO)
		NumberStyle.COOLDOWN:
			_draw_cooldown()


func get_rendered_size() -> Vector2:
	match number_style:
		NumberStyle.LARGE:
			return Vector2(_measure_digit_run(text, LARGE_GLYPH_RECTS), LARGE_HEIGHT)
		NumberStyle.MEDIUM:
			return Vector2(_measure_digit_run(text, MEDIUM_GLYPH_RECTS), MEDIUM_HEIGHT)
		NumberStyle.COOLDOWN:
			return _measure_cooldown()
	return Vector2.ZERO


func _draw_cooldown() -> void:
	var parts := text.split(".", false, 1)
	if parts.size() != 2:
		return
	var integer_text := parts[0]
	var fraction_text := parts[1]
	var integer_width := _measure_digit_run(integer_text, MEDIUM_GLYPH_RECTS)
	_draw_digit_run(integer_text, MEDIUM_TEXTURE, MEDIUM_GLYPH_RECTS, Vector2.ZERO)
	_draw_digit_run(
		fraction_text,
		SMALL_TEXTURE,
		SMALL_GLYPH_RECTS,
		Vector2(integer_width + 1.0, COOLDOWN_FRACTION_TOP)
	)
	# 最后绘制小数点，使其左右黑边覆盖整数、小数各自边缘的 1px。
	draw_texture_rect(
		DECIMAL_POINT_TEXTURE,
		Rect2(
			Vector2(integer_width - COOLDOWN_JOIN_OVERLAP, COOLDOWN_POINT_TOP),
			DECIMAL_POINT_TEXTURE.get_size()
		),
		false
	)


func _measure_cooldown() -> Vector2:
	var parts := text.split(".", false, 1)
	if parts.size() != 2:
		return Vector2.ZERO
	var integer_width := _measure_digit_run(parts[0], MEDIUM_GLYPH_RECTS)
	var fraction_width := _measure_digit_run(parts[1], SMALL_GLYPH_RECTS)
	return Vector2(integer_width + 1.0 + fraction_width, MEDIUM_HEIGHT)


func _draw_digit_run(
	value: String,
	atlas: Texture2D,
	glyph_rects: Dictionary,
	start_position: Vector2
) -> void:
	var cursor_x := start_position.x
	for index: int in value.length():
		var digit := value.substr(index, 1)
		if not glyph_rects.has(digit):
			continue
		var glyph_rect := glyph_rects[digit] as Rect2
		draw_texture_rect_region(
			atlas,
			Rect2(Vector2(cursor_x, start_position.y), glyph_rect.size),
			glyph_rect
		)
		cursor_x += glyph_rect.size.x + float(character_spacing)


func _measure_digit_run(value: String, glyph_rects: Dictionary) -> float:
	var width := 0.0
	var glyph_count := 0
	for index: int in value.length():
		var digit := value.substr(index, 1)
		if not glyph_rects.has(digit):
			continue
		width += (glyph_rects[digit] as Rect2).size.x
		glyph_count += 1
	return width + float(maxi(glyph_count - 1, 0) * character_spacing)


func _sync_size_and_redraw() -> void:
	var rendered_size := get_rendered_size()
	custom_minimum_size = rendered_size
	size = rendered_size
	queue_redraw()
