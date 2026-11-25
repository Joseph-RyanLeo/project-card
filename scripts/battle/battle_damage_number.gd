extends Node2D

const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
const THRESHOLD := 10.0 # 实际扣减超过这个数才显示
const DISPLAY_SCALE := 4.0 # 卢恩大数字的正常展示倍率
const START_SCALE := 0.32 # 刚弹出时相对正常大小的比例
const PEAK_SCALE := 1.14 # 回落前相对正常大小的峰值倍率
const RISE := 34.0 # 从出现至淡出全程上移的像素数
const GROW_TIME := 0.10 # 从小到冲过正常大小的时间
const SETTLE_TIME := 0.11 # 回落到正常大小的时间
const HOLD_TIME := 0.06 # 正常大小维持的时间
const FADE_TIME := 0.22 # 向上移动并淡出的时间
const ARMOR_COLOR := Color("b9bec8") # 仅扣护甲时的灰色
const HEALTH_COLOR := Color("ff535a") # 扣到生命时的红色
const PUNCTUATION_WIDTH := 5.0 # 小数点和感叹号的原生字宽
var _parts: PackedStringArray
var _ink: Color


func play(armor: float, health: float) -> void:
	var total := armor + health
	var shown := snappedf(total, 0.1)
	if shown > THRESHOLD and is_equal_approx(shown, roundf(shown)):
		_parts = PackedStringArray([str(roundi(shown))])
	else:
		_parts = String.num(shown if shown > THRESHOLD else total, 5).split(".")
	_ink = HEALTH_COLOR if health > 0.0 else ARMOR_COLOR
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE * DISPLAY_SCALE * START_SCALE
	var animation := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	animation.tween_property(self, "position:y", position.y - RISE, GROW_TIME + SETTLE_TIME + HOLD_TIME + FADE_TIME)
	animation.parallel().tween_method(_animate_size, 0.0, GROW_TIME + SETTLE_TIME, GROW_TIME + SETTLE_TIME)
	animation.parallel().tween_property(self, "modulate:a", 0.0, FADE_TIME).set_delay(GROW_TIME + SETTLE_TIME + HOLD_TIME)
	animation.tween_callback(queue_free)
	queue_redraw()


func _animate_size(elapsed: float) -> void:
	var multiplier := (
		lerpf(START_SCALE, PEAK_SCALE, ease(elapsed / GROW_TIME, 0.38))
		if elapsed < GROW_TIME
		else lerpf(PEAK_SCALE, 1.0, smoothstep(GROW_TIME, GROW_TIME + SETTLE_TIME, elapsed))
	)
	scale = Vector2.ONE * DISPLAY_SCALE * multiplier


func _draw() -> void:
	if _parts.is_empty(): return
	var integer_width := RuneNumber.measure_large_digits(_parts[0]).x
	var fraction_width := 0.0 # 没有小数时感叹号直接靠在整数右侧
	if _parts.size() > 1: fraction_width = PUNCTUATION_WIDTH + RuneNumber.measure_large_digits(_parts[1]).x
	var at := -Vector2(integer_width + fraction_width + PUNCTUATION_WIDTH, RuneNumber.LARGE_HEIGHT) * 0.5
	RuneNumber.draw_large_digits(self, _parts[0], at, 0, _ink)
	if _parts.size() > 1:
		_draw_mark(Rect2(at + Vector2(integer_width + 1.0, 10.0), Vector2(2, 2)))
		RuneNumber.draw_large_digits(self, _parts[1], at + Vector2(integer_width + PUNCTUATION_WIDTH, 0), 0, _ink)
	var tail := at + Vector2(integer_width + fraction_width + 1.0, 0)
	_draw_mark(Rect2(tail + Vector2(0, 1), Vector2(3, 7)))
	_draw_mark(Rect2(tail + Vector2(0, 10), Vector2(3, 2)))


func _draw_mark(rect: Rect2) -> void:
	draw_rect(rect.grow(1.0), Color("090909"))
	draw_rect(rect, _ink)
