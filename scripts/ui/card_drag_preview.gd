class_name CardDragPreview
extends Control

const CARD_SNAPSHOT_VISUAL_SCRIPT: Script = preload(
	"res://scripts/ui/card_snapshot_visual.gd"
)
const FOLLOW_SPEED: float = 18.0 # 拖拽卡牌追赶鼠标的速度；越大越快贴近鼠标
const LAG_RATIO: float = 0.42 # 鼠标移动时卡牌保留的滞后比例；越大拖尾感越强
const ROTATION_RESPONSE_SPEED: float = 14.0 # 卡牌倾斜追随移动方向及回正的速度
const ROTATION_PER_PIXEL: float = 0.65 # 水平移动量转换为倾斜角度的灵敏度
const MAX_ROTATION_DEGREES: float = 10.0 # 拖拽移动倾斜允许达到的最大绝对角度
const DRAG_SCALE_MULTIPLIER: float = 1.06 # 拿起卡牌后相对来源显示比例的额外放大倍率
const SHADOW_OFFSET := Vector2(6.0, 8.0) # 拖拽卡牌阴影相对卡牌的偏移
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.32) # 拖拽卡牌阴影的颜色及透明度

var _card_visual: Control
var _shadow: Panel
var _snapshot_visual: Variant
var _rest_position: Vector2 = Vector2.ZERO
var _shadow_rest_position: Vector2 = Vector2.ZERO
var _visual_lag: Vector2 = Vector2.ZERO
var _previous_root_global_position: Vector2 = Vector2.ZERO
var _tracking_started: bool = false


func configure(
	card_visual: Control,
	grab_local_position: Vector2,
	preview_scale: Vector2,
	card_size: Vector2
) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_snapshot_visual = CARD_SNAPSHOT_VISUAL_SCRIPT.new()
	_snapshot_visual.name = "CardSnapshotVisual"
	_snapshot_visual.configure(card_visual, card_size)
	add_child(_snapshot_visual)
	_card_visual = _snapshot_visual.get_texture_control()
	var card_origin: Vector2 = (
		_snapshot_visual.get_card_origin_in_texture()
	)
	_rest_position = -grab_local_position - card_origin
	_shadow_rest_position = -grab_local_position

	_shadow = Panel.new()
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.z_index = -1
	_shadow.size = card_size
	_shadow.custom_minimum_size = card_size
	_shadow.pivot_offset = grab_local_position
	_shadow.scale = preview_scale * DRAG_SCALE_MULTIPLIER
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = SHADOW_COLOR
	shadow_style.corner_radius_top_left = 3
	shadow_style.corner_radius_top_right = 3
	shadow_style.corner_radius_bottom_left = 3
	shadow_style.corner_radius_bottom_right = 3
	_shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(_shadow)

	_card_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_visual.position = _rest_position
	_card_visual.pivot_offset = grab_local_position + card_origin
	_card_visual.scale = preview_scale * DRAG_SCALE_MULTIPLIER
	_update_visual_transform(0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(_card_visual):
		return

	if not _tracking_started:
		_previous_root_global_position = global_position
		_tracking_started = true
		return

	var root_movement := global_position - _previous_root_global_position
	_previous_root_global_position = global_position
	_visual_lag -= root_movement * LAG_RATIO
	var follow_weight := 1.0 - exp(-FOLLOW_SPEED * delta)
	_visual_lag = _visual_lag.lerp(Vector2.ZERO, follow_weight)

	var desired_rotation := clampf(
		root_movement.x * ROTATION_PER_PIXEL,
		-MAX_ROTATION_DEGREES,
		MAX_ROTATION_DEGREES
	)
	var rotation_weight := 1.0 - exp(-ROTATION_RESPONSE_SPEED * delta)
	var next_rotation := lerpf(
		_card_visual.rotation_degrees,
		desired_rotation,
		rotation_weight
	)
	_update_visual_transform(next_rotation)


func get_card_global_position() -> Vector2:
	if (
		is_instance_valid(_card_visual)
		and is_instance_valid(_snapshot_visual)
	):
		return (
			_card_visual.get_global_transform_with_canvas()
			* _snapshot_visual.get_card_origin_in_texture()
		)
	return global_position


func get_card_visual() -> Control:
	return _card_visual


func get_source_card_view() -> Variant:
	if is_instance_valid(_snapshot_visual):
		return _snapshot_visual.get_source_card_view()
	return null


func _update_visual_transform(rotation_degrees_value: float) -> void:
	if not is_instance_valid(_card_visual):
		return

	_card_visual.position = _rest_position + _visual_lag
	_card_visual.rotation_degrees = rotation_degrees_value
	if is_instance_valid(_shadow):
		var shadow_offset := SHADOW_OFFSET.rotated(
			deg_to_rad(rotation_degrees_value)
		)
		_shadow.position = (
			_shadow_rest_position + _visual_lag + shadow_offset
		)
		_shadow.rotation_degrees = rotation_degrees_value
