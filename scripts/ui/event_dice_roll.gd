extends Control

## 只演出已提交的点数，动画不消费本局随机数。
signal finished

const Typography = preload("res://scripts/ui/ui_typography.gd")
const DiceModel = preload("res://scripts/ui/dice_model.gd")
const FLIGHT_SECONDS: float = 0.58 # 飞入到第一次碰桌的时长
const BOUNCE_SECONDS: float = 0.20 # 碰桌后弹起再落定的时长
const ROLL_SECONDS: float = FLIGHT_SECONDS + BOUNCE_SECONDS # 从飞入到落定的总时长
const RESULT_SECONDS: float = 0.48 # 停在真实点数上的阅读时间
const SLIDE_SECONDS: float = 0.36 # 落定后骰子平移到结果栏右侧的时长
const THROW_DISTANCE: float = 128.0 # 骰子飞入的横向距离
const THROW_HEIGHT: float = 34.0 # 掷出时的最高弧线
const BOUNCE_HEIGHT: float = 8.0 # 碰桌后弹起的最大高度
const BOUNCE_DISTANCE: float = 8.0 # 碰桌后向前挪动的距离
const IMPACT_TILT: float = 0.22 # 首次触桌时剩余的翻滚角度，单位为弧度
const DIE_SIZE: float = DiceModel.DESIGN_RADIUS # 骰体从中心到最远顶点的大小
const SPINS: float = 1.5 # 一次投掷的翻滚圈数
const CAPTION_FONT_SIZE: int = 15 # 投掷说明与结果字号
const CAPTION_BASELINE_OFFSET := 15.0 # 骰身区域下缘到结果文字基线的距离
const TABLE_Y := 114.0 # 区域内的落桌高度，放大骰身时保持固定
const TABLE_UP := Vector3(0, -0.6, 0.8) # 桌面法线，控制从上方看骰子的角度
const LANDING_TURN: float = -16.0 # 落定时骰面相对于桌面的转角
const TUMBLE_AXIS := Vector3(0.56, 0.8, 0.22) # 主翻滚轴，改变骰面切换方向
const SHADOW_COLOR := Color(0.19, 0.09, 0.10, 0.30) # 骰子贴桌时的阴影色及深度
const SHADOW_AIR_ALPHA := 0.52 # 抛到最高处时保留的阴影透明度比例

var _sides: int
var _result: int
var _flight: float
var _model := DiceModel.new()
var _landing_basis := Basis.IDENTITY
var _animation: Tween
var show_caption := true
var presentation_scale := 1.0 # 直接按倍率绘制骰体和点数
var motion_scale := 1.0 # 单独调整投掷的位移和弧线高度


func _ready() -> void:
	name = "EventDiceRoll"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func prepare(sides: int, result: int) -> void:
	if is_instance_valid(_animation): _animation.kill()
	_sides = sides
	_result = result
	_prepare_die()
	_update_flight(0.0)


func play(sides: int, result: int) -> void:
	prepare(sides, result)
	play_prepared()


func play_prepared(rest_position := Vector2.INF) -> void:
	_animation = create_tween()
	_animation.tween_method(_update_flight, 0.0, 1.0, ROLL_SECONDS)
	_animation.tween_interval(RESULT_SECONDS)
	if rest_position.is_finite():
		_animation.tween_property(self, "position", rest_position, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_animation.tween_callback(finished.emit)


func show_result(sides: int, result: int) -> void:
	prepare(sides, result)
	_update_flight(1.0)


func _prepare_die() -> void:
	_model.set_sides(_sides)
	if _model.vertices.is_empty(): return
	var landing_turn := Basis(TABLE_UP, deg_to_rad(LANDING_TURN))
	var result_index := clampi(_result - 1, 0, _sides - 1)
	if _sides == 4:
		# D4 以顶角读数，落在与该顶角相对的三角面上。
		_landing_basis = landing_turn * Basis(Quaternion(_model.vertices[result_index].normalized(), TABLE_UP))
	else:
		var table_axes := Basis(Vector3.RIGHT, TABLE_UP.cross(Vector3.RIGHT), TABLE_UP)
		var result_axes: Basis = _model.faces[result_index].axes
		_landing_basis = landing_turn * table_axes * result_axes.transposed()


func _update_flight(progress: float) -> void:
	_flight = progress
	queue_redraw()


func get_landing_rotation() -> Basis:
	return _landing_basis


func get_landing_center() -> Vector2:
	return _supported_center(_landing_contact(), _landing_basis)


func _landing_contact() -> Vector2:
	return Vector2(size.x * 0.5, TABLE_Y)


func _draw() -> void:
	if _sides <= 0: return
	var pose := _sample_motion(_flight * ROLL_SECONDS)
	var contact := _landing_contact() - Vector2(pose.x * motion_scale, 0)
	if _model.vertices.is_empty():
		_draw_generic_roll(contact - Vector2(0, pose.y * motion_scale))
	else:
		_draw_die(contact, pose.y, pose.z)

	if show_caption:
		var caption := "1d%d · 投掷中" % _sides
		if _flight >= 1.0: caption = "1d%d · 投掷结果 %d" % [_sides, _result]
		_draw_centered(caption, Vector2(size.x * 0.5, size.y + CAPTION_BASELINE_OFFSET), CAPTION_FONT_SIZE, DiceModel.INK)


func _sample_motion(seconds: float) -> Vector3:
	# 返回距落点的水平距离、离桌高度、相对落定姿势的翻滚角。
	if seconds < FLIGHT_SECONDS:
		var progress := seconds / FLIGHT_SECONDS
		var distance := BOUNCE_DISTANCE + (THROW_DISTANCE - BOUNCE_DISTANCE) * (1.0 - progress) * (1.0 - 0.6 * progress)
		var height := sin(PI * progress) * THROW_HEIGHT
		var turn := -IMPACT_TILT - (TAU * SPINS - IMPACT_TILT) * pow(1.0 - progress, 1.45)
		return Vector3(distance, height, turn)
	var rebound := clampf((seconds - FLIGHT_SECONDS) / BOUNCE_SECONDS, 0.0, 1.0)
	var remaining := pow(1.0 - rebound, 2.0)
	return Vector3(BOUNCE_DISTANCE * remaining, BOUNCE_HEIGHT * 4.0 * rebound * (1.0 - rebound), -IMPACT_TILT * remaining)


func _draw_die(contact: Vector2, height: float, turn: float) -> void:
	var rotation := Basis(TUMBLE_AXIS.normalized(), turn) * Basis(Vector3.RIGHT, turn * 0.44) * _landing_basis
	var radius := DIE_SIZE * presentation_scale
	var lift := height * motion_scale
	var shadow := _model.shadow_outline(rotation, TABLE_UP, radius, lift)
	for index: int in shadow.size():
		shadow[index] += contact
	var alpha := SHADOW_COLOR.a * lerpf(1.0, SHADOW_AIR_ALPHA, height / THROW_HEIGHT)
	draw_colored_polygon(shadow, Color(SHADOW_COLOR, alpha))
	var center := _supported_center(contact - Vector2(0, lift), rotation)
	_model.draw_on(self, center, rotation, radius, _result if _flight >= 1.0 else 0)


func _supported_center(contact: Vector2, rotation: Basis) -> Vector2:
	var bottom := _model.support_height(rotation, TABLE_UP) if not _model.vertices.is_empty() else 0.0
	# 把旋转后最低的顶点抬到桌面。落定时，整个底面会贴着桌面。
	return contact - Vector2(TABLE_UP.x, TABLE_UP.y) * (bottom * DIE_SIZE * presentation_scale)


func _draw_generic_roll(contact: Vector2) -> void:
	# 自定义面数仍能沿用事件结算与演出，用通用点数标记显示。
	var point := _result if _flight >= 1.0 else posmod(floori(_flight * 26.0) * 7 + _result, _sides) + 1
	var radius := DIE_SIZE * presentation_scale * 0.68 # 通用点数标记的半径
	var center := contact - Vector2(0, radius)
	draw_circle(center, radius, DiceModel.SHADE)
	draw_arc(center, radius, 0.0, TAU, 32, DiceModel.GOLD, 1.3, true)
	DiceModel.draw_number(self, str(point), Transform2D(0.0, center), DiceModel.POINT_MARK_HEIGHT * presentation_scale, radius)


func _draw_centered(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := Typography.font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, at - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
