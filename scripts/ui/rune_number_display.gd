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
const ZEAL_SIGN_TEXTURE: Texture2D = preload("res://assets/fonts/rune_zeal_signs.png")

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
const SIGN_WIDTH: float = 7.0 # 热诚正负号的像素宽度，与冷却中号卢恩数字并排显示
const SIGN_HEIGHT: float = 10.0 # 用户提供的正负号原图画布高度，绘制时保留原始透明边距
const SIGN_TOP: float = 1.0 # 10px符号画布在12px中号数字旁的垂直居中偏移
const SIGN_PLUS_REGION := Rect2(0, 0, 7, 10) # 用户正号在原图中的7×10裁切区域
const SIGN_MINUS_REGION := Rect2(14, 0, 7, 10) # 用户负号在原图中的7×10裁切区域
const STAT_PLUS_MEDIUM = preload("res://assets/fonts/rune_stat_plus_medium.png")
const STAT_MINUS_MEDIUM = preload("res://assets/fonts/rune_stat_minus_medium.png")
const STAT_PLUS_LARGE = preload("res://assets/fonts/rune_stat_plus_large.png")
const STAT_MINUS_LARGE = preload("res://assets/fonts/rune_stat_minus_large.png")
const STAT_GAIN_COLOR := Color("#8dff4e") # 加成数字的白色像素替换色
const STAT_LOSS_COLOR := Color("#ff5b5b") # 减益数字的白色像素替换色
const STAT_SIGN_OVERLAP := 1.0 # 字形描边和符号相接时重叠的像素列数
const STAT_LEADING_ONE_SHIFT := 1.0 # 右侧首位为窄字形 1 时额外左移的像素数
const STAT_SIGN_TOP := 3.0 # 加减号相对于同组整数的顶部偏移
const STAT_WHITE_SHADER := preload("res://shaders/emblem_fusion_white.gdshader")
const STAT_WHITEN_END := 0.22 # 当前值完全变为白色剪影的进度
const STAT_SPLIT_START := 0.28 # 白色合影停顿结束、开始分离的进度
const STAT_SPLIT_END := 0.76 # 两侧数字抵达检视坐标、开始恢复原色的进度
const STAT_SIGN_APPEAR := 0.48 # 加减号开始在固定锚点浮现的进度
static var _infinity_texture: ImageTexture
static var _stat_palettes: Dictionary = {}

var _stat_color := Color.WHITE
var _stat_base_text := ""
var _stat_delta_text := ""
var _stat_positive := false
var _stat_single_offset := Vector2.ZERO
var _stat_split_progress := 1.0
var _stat_white_material: ShaderMaterial

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
		if text == value:
			return
		text = value
		_sync_size_and_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync_size_and_redraw()


func _draw() -> void:
	if text == "∞":
		_draw_infinity()
		return
	if _stat_delta_text.is_empty():
		_draw_number(text, Vector2.ZERO, _stat_color)
		return
	if _stat_split_progress >= 1.0:
		_draw_number(_stat_base_text, Vector2.ZERO, Color.WHITE)
		draw_texture(_get_stat_sign(), get_stat_sign_offset())
		_draw_number(_stat_delta_text, Vector2(_get_stat_delta_x(), 0.0), _stat_color)
		return
	if _stat_split_progress <= STAT_SPLIT_START:
		var single_color := Color.WHITE if number_style == NumberStyle.COOLDOWN else _stat_color
		_draw_number(text, _stat_single_offset, single_color)
		return
	var separation := _get_stat_separation()
	var single_center := _stat_single_offset + Vector2(_measure_number(text).x * 0.5, 0.0)
	var base_at_join := single_center - Vector2(_measure_number(_stat_base_text).x * 0.5, 0.0)
	var delta_at_join := single_center - Vector2(_measure_number(_stat_delta_text).x * 0.5, 0.0)
	var sign_alpha := smoothstep(STAT_SIGN_APPEAR, STAT_SPLIT_END, _stat_split_progress)
	_draw_number(_stat_base_text, base_at_join.lerp(Vector2.ZERO, separation).round(), Color.WHITE)
	if sign_alpha > 0.0:
		draw_texture(_get_stat_sign(), get_stat_sign_offset(), Color(1.0, 1.0, 1.0, sign_alpha))
	_draw_number(_stat_delta_text, delta_at_join.lerp(Vector2(_get_stat_delta_x(), 0.0), separation).round(), _stat_color)


func get_rendered_size() -> Vector2:
	if text == "∞": return Vector2(14, LARGE_HEIGHT)
	if not _stat_delta_text.is_empty():
		var delta_size := _measure_number(_stat_delta_text)
		return Vector2(_get_stat_delta_x() + delta_size.x, delta_size.y)
	return _measure_number(text)


func set_stat_format(color: Color, base_text: String = "", delta_text: String = "", positive: bool = false) -> void:
	if _stat_color == color and _stat_base_text == base_text and _stat_delta_text == delta_text and _stat_positive == positive:
		return
	_stat_color = color
	_stat_base_text = base_text
	_stat_delta_text = delta_text
	_stat_positive = positive
	_sync_stat_silhouette()
	_sync_size_and_redraw()


func set_stat_single_offset(offset: Vector2) -> void:
	if _stat_single_offset == offset: return
	_stat_single_offset = offset
	if has_stat_breakdown() and _stat_split_progress < 1.0: queue_redraw()


func set_stat_split_progress(progress: float) -> void:
	if _stat_split_progress == progress: return
	_stat_split_progress = progress
	_sync_stat_silhouette()
	queue_redraw()


func _get_stat_separation() -> float:
	var travel := clampf(inverse_lerp(STAT_SPLIT_START, STAT_SPLIT_END, _stat_split_progress), 0.0, 1.0)
	return 1.0 - pow(1.0 - travel, 3.0)


func _sync_stat_silhouette() -> void:
	var whiten := 0.0
	if has_stat_breakdown() and _stat_split_progress > 0.0 and _stat_split_progress < 1.0:
		whiten = smoothstep(0.0, STAT_WHITEN_END, _stat_split_progress) * (1.0 - smoothstep(STAT_SPLIT_END, 1.0, _stat_split_progress))
	if is_zero_approx(whiten):
		if _stat_white_material != null and material == _stat_white_material: material = null
		return
	if _stat_white_material == null:
		_stat_white_material = ShaderMaterial.new()
		_stat_white_material.shader = STAT_WHITE_SHADER
	if material != _stat_white_material: material = _stat_white_material
	_stat_white_material.set_shader_parameter("white_amount", whiten)


func has_stat_breakdown() -> bool:
	return not _stat_delta_text.is_empty()


func get_stat_sign_offset() -> Vector2:
	return Vector2(_measure_number(_stat_base_text).x - STAT_SIGN_OVERLAP, STAT_SIGN_TOP)


func _get_stat_sign() -> Texture2D:
	if number_style == NumberStyle.LARGE:
		return STAT_PLUS_LARGE if _stat_positive else STAT_MINUS_LARGE
	return STAT_PLUS_MEDIUM if _stat_positive else STAT_MINUS_MEDIUM


func _get_stat_delta_x() -> float:
	var tight_shift := STAT_LEADING_ONE_SHIFT if _stat_delta_text.begins_with("1") else 0.0
	return get_stat_sign_offset().x + _get_stat_sign().get_width() - STAT_SIGN_OVERLAP - tight_shift


func _draw_number(value: String, origin: Vector2, color: Color) -> void:
	match number_style:
		NumberStyle.LARGE:
			_draw_digit_run(self, value, _get_stat_palette(LARGE_TEXTURE, color), LARGE_GLYPH_RECTS, origin, character_spacing)
		NumberStyle.MEDIUM:
			_draw_digit_run(self, value, _get_stat_palette(MEDIUM_TEXTURE, color), MEDIUM_GLYPH_RECTS, origin, character_spacing)
		NumberStyle.COOLDOWN:
			_draw_cooldown(value, origin, color)


func _measure_number(value: String) -> Vector2:
	match number_style:
		NumberStyle.LARGE:
			return measure_large_digits(value, character_spacing)
		NumberStyle.MEDIUM:
			return Vector2(_measure_digit_run(value, MEDIUM_GLYPH_RECTS, character_spacing), MEDIUM_HEIGHT)
		NumberStyle.COOLDOWN:
			return _measure_cooldown(value)
	return Vector2.ZERO


static func draw_large_digits(canvas: CanvasItem, value: String, origin: Vector2, spacing: int = 0, color: Color = Color.WHITE) -> void:
	_draw_digit_run(canvas, value, _get_stat_palette(LARGE_TEXTURE, color), LARGE_GLYPH_RECTS, origin, spacing)


static func measure_large_digits(value: String, spacing: int = 0) -> Vector2:
	return Vector2(_measure_digit_run(value, LARGE_GLYPH_RECTS, spacing), LARGE_HEIGHT)


func _draw_cooldown(value: String, origin: Vector2, color: Color) -> void:
	var parts := value.split(".", false, 1)
	var medium := _get_stat_palette(MEDIUM_TEXTURE, color)
	if parts.size() != 2:
		# 10秒及以上只显示紧贴的中号整数，不再要求必须存在小数点。
		_draw_digit_run(self, value, medium, MEDIUM_GLYPH_RECTS, origin, character_spacing)
		return
	var integer_text := parts[0]
	var fraction_text := parts[1]
	var integer_width := _measure_digit_run(integer_text, MEDIUM_GLYPH_RECTS, character_spacing)
	_draw_digit_run(self, integer_text, medium, MEDIUM_GLYPH_RECTS, origin, character_spacing)
	_draw_digit_run(
		self,
		fraction_text,
		_get_stat_palette(SMALL_TEXTURE, color),
		SMALL_GLYPH_RECTS,
		origin + Vector2(integer_width + 1.0, COOLDOWN_FRACTION_TOP),
		character_spacing
	)
	# 最后绘制小数点，使其左右黑边覆盖整数、小数各自边缘的 1px。
	draw_texture_rect(
		_get_stat_palette(DECIMAL_POINT_TEXTURE, color),
		Rect2(
			origin + Vector2(integer_width - COOLDOWN_JOIN_OVERLAP, COOLDOWN_POINT_TOP),
			DECIMAL_POINT_TEXTURE.get_size()
		),
		false
	)


func _measure_cooldown(value: String) -> Vector2:
	var parts := value.split(".", false, 1)
	if parts.size() != 2:
		return Vector2(_measure_digit_run(value, MEDIUM_GLYPH_RECTS, character_spacing), MEDIUM_HEIGHT)
	var integer_width := _measure_digit_run(parts[0], MEDIUM_GLYPH_RECTS, character_spacing)
	var fraction_width := _measure_digit_run(parts[1], SMALL_GLYPH_RECTS, character_spacing)
	return Vector2(integer_width + 1.0 + fraction_width, MEDIUM_HEIGHT)


static func _get_stat_palette(atlas: Texture2D, color: Color) -> Texture2D:
	if color == Color.WHITE:
		return atlas
	var key := [atlas, color]
	if not _stat_palettes.has(key):
		var image := atlas.get_image()
		for row: int in image.get_height():
			for column: int in image.get_width():
				if image.get_pixel(column, row) == Color.WHITE:
					image.set_pixel(column, row, color)
		_stat_palettes[key] = ImageTexture.create_from_image(image)
	return _stat_palettes[key]


static func _draw_digit_run(
	canvas: CanvasItem,
	value: String,
	atlas: Texture2D,
	glyph_rects: Dictionary,
	start_position: Vector2,
	spacing: int
) -> void:
	var cursor_x := start_position.x
	for index: int in value.length():
		var digit := value.substr(index, 1)
		if digit == "+" or digit == "-":
			_draw_zeal_sign(canvas, Vector2(cursor_x, start_position.y), digit == "+")
			cursor_x += SIGN_WIDTH + float(spacing)
			continue
		if not glyph_rects.has(digit):
			continue
		var glyph_rect := glyph_rects[digit] as Rect2
		canvas.draw_texture_rect_region(
			atlas,
			Rect2(Vector2(cursor_x, start_position.y), glyph_rect.size),
			glyph_rect
		)
		cursor_x += glyph_rect.size.x + float(spacing)


static func _measure_digit_run(value: String, glyph_rects: Dictionary, spacing: int) -> float:
	var width := 0.0
	var glyph_count := 0
	for index: int in value.length():
		var digit := value.substr(index, 1)
		if digit == "+" or digit == "-":
			width += SIGN_WIDTH
			glyph_count += 1
			continue
		if not glyph_rects.has(digit):
			continue
		width += (glyph_rects[digit] as Rect2).size.x
		glyph_count += 1
	return width + float(maxi(glyph_count - 1, 0) * spacing)


static func _draw_zeal_sign(canvas: CanvasItem, origin: Vector2, positive: bool) -> void:
	canvas.draw_texture_rect_region(
		ZEAL_SIGN_TEXTURE,
		Rect2(origin + Vector2(0.0, SIGN_TOP), Vector2(SIGN_WIDTH, SIGN_HEIGHT)),
		SIGN_PLUS_REGION if positive else SIGN_MINUS_REGION
	)


func _sync_size_and_redraw() -> void:
	var rendered_size := get_rendered_size()
	custom_minimum_size = rendered_size
	size = rendered_size
	queue_redraw()


func _draw_infinity() -> void:
	# 生成一张共享像素纹理，让无限符号的黑边也能像图集数字一样反光。
	if _infinity_texture == null:
		var rows := ["011100001110", "110110011011", "100011110001", "100001100001", "100011110001", "110110011011", "011100001110"]
		var image := Image.create_empty(14, int(LARGE_HEIGHT), false, Image.FORMAT_RGBA8)
		var pixels: Array[Vector2i] = []
		for y: int in rows.size():
			for x: int in rows[y].length():
				if rows[y][x] == "1": pixels.append(Vector2i(x + 1, y + 3))
		for pixel: Vector2i in pixels: image.fill_rect(Rect2i(pixel - Vector2i.ONE, Vector2i(3, 3)), Color.BLACK)
		for pixel: Vector2i in pixels: image.set_pixelv(pixel, Color.WHITE)
		_infinity_texture = ImageTexture.create_from_image(image)
	draw_texture(_infinity_texture, Vector2.ZERO)
