extends Node2D

## 同一个检视浮层收集所有刀头碎屑，快速拖刮也只需要一个绘制节点。
const CHIPS_PER_CONTACT := 3 # 每次有效接触最多扬起的碎屑数
const MAX_CHIPS := 48 # 连续刮擦时同时存活的碎屑上限
const CHIP_LIFETIME := 0.29 # 碎屑弹散和淡出的秒数
const CHIP_GRAVITY := 115.0 # 碎屑下坠加速度
const CHIP_LIGHT := Color("fff0c7") # 刮落纸膜的受光面
const CHIP_SHADE := Color("654626") # 碎屑描边，确保浅色卡面也看得见
const CHIP_SIZES: Array[Vector2] = [Vector2(4, 3), Vector2(3, 3), Vector2(3, 2)] # 每次刮下的三片像素碎屑大小
var _rng := RandomNumberGenerator.new()
var _chips: Array[Dictionary] = []


func emit_at(canvas_point: Vector2) -> void:
	var origin := get_global_transform_with_canvas().affine_inverse() * canvas_point
	for index: int in mini(CHIPS_PER_CONTACT, MAX_CHIPS - _chips.size()):
		var velocity := Vector2(_rng.randf_range(-48.0, 48.0), _rng.randf_range(-38.0, -12.0)) # 刀头附近向两侧飞出的像素速度
		_chips.append({"origin": origin, "velocity": velocity, "age": 0.0, "size": CHIP_SIZES[index]})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for index: int in range(_chips.size() - 1, -1, -1):
		_chips[index].age += delta
		if _chips[index].age >= CHIP_LIFETIME: _chips.remove_at(index)
	set_process(not _chips.is_empty())
	queue_redraw()


func _draw() -> void:
	for chip: Dictionary in _chips:
		var age := float(chip.age)
		var point: Vector2 = chip.origin + (chip.velocity as Vector2) * age + Vector2.DOWN * CHIP_GRAVITY * age * age * 0.5
		var alpha := 1.0 - smoothstep(CHIP_LIFETIME * 0.35, CHIP_LIFETIME, age)
		var rect := Rect2(point.round(), chip.size)
		draw_rect(rect, Color(CHIP_SHADE, alpha))
		draw_rect(Rect2(rect.position, rect.size - Vector2.ONE), Color(CHIP_LIGHT, alpha))
