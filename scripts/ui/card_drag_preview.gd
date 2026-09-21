class_name CardDragPreview
extends Control

## 鼠标正在携带的实体卡牌视觉。
##
## CardSnapshotVisual 把复杂卡面压成一个纹理，本节点只负责跟随、拖尾和阴影。
## BattlefieldRow 读取 get_card_global_corners() 作为拖动实体的几何边界；
## 因此视觉位置与堆叠判断使用同一份数据，不得用目标虚影的位置替代。

const CARD_SNAPSHOT_VISUAL_SCRIPT: Script = preload(
	"res://scripts/ui/card_snapshot_visual.gd"
)
const EquipmentIndicatorStyleScript = preload(
	"res://scripts/ui/equipment_indicator_style.gd"
)
const FOLLOW_SPEED: float = 18.0 # 拖拽卡牌追赶鼠标的速度；越大越快贴近鼠标
const LAG_RATIO: float = 0.42 # 鼠标移动时卡牌保留的滞后比例；越大拖尾感越强
const ROTATION_RESPONSE_SPEED: float = 14.0 # 卡牌倾斜追随移动方向及回正的速度
const ROTATION_PER_PIXEL: float = 0.65 # 水平移动量转换为倾斜角度的灵敏度
const MAX_ROTATION_DEGREES: float = 10.0 # 拖拽移动倾斜允许达到的最大绝对角度
const SHADOW_OFFSET := Vector2(6.0, 8.0) # 拖拽卡牌阴影相对卡牌的偏移
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.32) # 拖拽卡牌阴影的颜色及透明度
const DRAG_PREVIEW_Z_INDEX: int = 3000 # 拖拽整卡/整队始终高于战场真实小队和目标虚影的全局层级
const EQUIPMENT_INDICATOR_SIZE := EquipmentIndicatorStyleScript.DISPLAY_SIZE
const EQUIPMENT_TRANSITION_DURATION := 0.10 # 装备牌与指示物交叉渐变的时长
const EQUIPMENT_INDICATOR_START_SCALE := 2.0 # 装备牌变为指示物时的起始放大倍数
const EQUIPMENT_INDICATOR_DROP_LIFT := Vector2(0.0, 4.0) # 变成指示物时从上方短促落下的距离

var _card_visual: Control
var _shadow: Panel
var _snapshot_visual: Variant
var _card_size: Vector2 = Vector2.ZERO
var _rest_position: Vector2 = Vector2.ZERO
var _shadow_rest_position: Vector2 = Vector2.ZERO
var _visual_lag: Vector2 = Vector2.ZERO
var _previous_root_global_position: Vector2 = Vector2.ZERO
var _tracking_started: bool = false
var _equipment_indicator_visual: TextureRect
var _equipment_indicator_shadow: TextureRect
var _equipment_indicator_mode: bool = false
var _equipment_transition: Tween
var _preview_scale := Vector2.ONE
var _equipment_indicator_grab_local_position: Vector2 = EQUIPMENT_INDICATOR_SIZE * 0.5


# 创建快照后，以抓取点为原点放置卡面和阴影。
func configure(
	card_visual: Control,
	grab_local_position: Vector2,
	preview_scale: Vector2,
	card_size: Vector2
) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = DRAG_PREVIEW_Z_INDEX
	# 先更新快照的追赶位置，再让战场行读取四角做反馈与吸附判定，
	# 避免同一帧仍使用上一帧的视觉位置。
	process_priority = -10
	_card_size = card_size
	_preview_scale = preview_scale
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
	_shadow.scale = preview_scale
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
	_card_visual.scale = preview_scale

	_equipment_indicator_visual = TextureRect.new()
	_equipment_indicator_visual.name = "EquipmentIndicatorVisual"
	_equipment_indicator_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equipment_indicator_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_equipment_indicator_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_equipment_indicator_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipment_indicator_visual.size = EQUIPMENT_INDICATOR_SIZE
	_equipment_indicator_visual.custom_minimum_size = EQUIPMENT_INDICATOR_SIZE
	_equipment_indicator_visual.pivot_offset = EQUIPMENT_INDICATOR_SIZE * 0.5
	_equipment_indicator_visual.scale = preview_scale
	_equipment_indicator_visual.position = _get_equipment_indicator_rest_position()
	_equipment_indicator_visual.visible = false
	add_child(_equipment_indicator_visual)
	_equipment_indicator_shadow = TextureRect.new()
	_equipment_indicator_shadow.name = "IndicatorShadow"
	_equipment_indicator_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equipment_indicator_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_equipment_indicator_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_equipment_indicator_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipment_indicator_shadow.size = EQUIPMENT_INDICATOR_SIZE
	# 鼠标正在携带指示物，相当于已经从卡面拿起，因此使用拉远的阴影。
	_equipment_indicator_shadow.position = EquipmentIndicatorStyleScript.LIFTED_SHADOW_OFFSET
	_equipment_indicator_shadow.modulate = EquipmentIndicatorStyleScript.SHADOW_COLOR
	_equipment_indicator_shadow.show_behind_parent = true
	_equipment_indicator_shadow.z_index = -1
	_equipment_indicator_visual.add_child(_equipment_indicator_shadow)
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

# 以下位置查询给战场判定使用，返回的是当前屏幕上真实看到的拖动卡牌。
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


func get_card_global_corners() -> PackedVector2Array:
	var corners := PackedVector2Array()
	if (
		not is_instance_valid(_card_visual)
		or not is_instance_valid(_snapshot_visual)
	):
		return corners
	var card_origin: Vector2 = _snapshot_visual.get_card_origin_in_texture()
	var visual_transform := _card_visual.get_global_transform_with_canvas()
	for local_corner: Vector2 in [
		card_origin,
		card_origin + Vector2(_card_size.x, 0.0),
		card_origin + _card_size,
		card_origin + Vector2(0.0, _card_size.y),
	]:
		corners.append(visual_transform * local_corner)
	return corners


func get_card_visual() -> Control:
	return _card_visual


func get_source_card_view() -> Variant:
	if is_instance_valid(_snapshot_visual):
		return _snapshot_visual.get_source_card_view()
	return null


func set_equipment_card_data(equipment_data: CardData) -> void:
	if is_instance_valid(_equipment_indicator_visual):
		_equipment_indicator_visual.texture = (
			EquipmentIndicatorStyleScript.get_texture(equipment_data)
		)
	if is_instance_valid(_equipment_indicator_shadow):
		_equipment_indicator_shadow.texture = _equipment_indicator_visual.texture


func set_equipment_indicator_grab_local_position(value: Vector2) -> void:
	_equipment_indicator_grab_local_position = value
	if _equipment_indicator_mode:
		_apply_equipment_mode_immediately(true)


func get_equipment_indicator_rest_global_center() -> Vector2:
	return get_global_transform_with_canvas() * (
		_get_equipment_indicator_rest_position()
		+ EQUIPMENT_INDICATOR_SIZE * 0.5
	)


func get_equipment_indicator_visual_global_center() -> Vector2:
	if not is_instance_valid(_equipment_indicator_visual):
		return get_equipment_indicator_rest_global_center()
	return (
		_equipment_indicator_visual.get_global_transform_with_canvas()
		* (EQUIPMENT_INDICATOR_SIZE * 0.5)
	)


func continue_equipment_pickup(lifted_grab_local_position: Vector2) -> void:
	# 保留场上图像当前的抬起位置，再完成剩余抬起；鼠标不重新对齐图标中心。
	_equipment_indicator_grab_local_position = lifted_grab_local_position
	if is_instance_valid(_equipment_transition):
		_equipment_transition.kill()
	_equipment_transition = create_tween()
	_equipment_transition.tween_property(
		_equipment_indicator_visual, "position",
		_get_equipment_indicator_rest_position(), EQUIPMENT_TRANSITION_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_equipment_indicator_mode(enabled: bool, animated: bool = true) -> void:
	# 原生长按拖拽期间，鼠标移动会连续上报同一个目标形态。目标没有变化时
	# 不能重启 Tween，否则“指示物 -> 卡牌”的渐显每帧都从透明重新开始，
	# 屏幕上便只剩卡牌阴影，看起来像一块持续存在的黑色虚影。
	if _equipment_indicator_mode == enabled:
		if not animated:
			_apply_equipment_mode_immediately(enabled)
		return
	_equipment_indicator_mode = enabled
	if is_instance_valid(_equipment_transition):
		_equipment_transition.kill()
	if not animated or not is_inside_tree():
		_apply_equipment_mode_immediately(enabled)
		return

	_snapshot_visual.visible = true
	_shadow.visible = not enabled
	_equipment_indicator_visual.visible = true
	_equipment_transition = create_tween().set_parallel(true)
	if enabled:
		_equipment_indicator_visual.modulate.a = 0.0
		_equipment_indicator_visual.scale = (
			_preview_scale * EQUIPMENT_INDICATOR_START_SCALE
		)
		_equipment_indicator_visual.position = (
			_get_equipment_indicator_rest_position()
			- EQUIPMENT_INDICATOR_DROP_LIFT * _preview_scale
		)
		_equipment_transition.tween_property(
			_snapshot_visual, "modulate:a", 0.0, EQUIPMENT_TRANSITION_DURATION
		)
		_equipment_transition.tween_property(
			_equipment_indicator_visual, "modulate:a", 1.0, EQUIPMENT_TRANSITION_DURATION
		)
		_equipment_transition.tween_property(
			_equipment_indicator_visual, "scale", _preview_scale, EQUIPMENT_TRANSITION_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_equipment_transition.tween_property(
			_equipment_indicator_visual,
			"position",
			_get_equipment_indicator_rest_position(),
			EQUIPMENT_TRANSITION_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_snapshot_visual.modulate.a = 0.0
		_equipment_transition.tween_property(
			_snapshot_visual, "modulate:a", 1.0, EQUIPMENT_TRANSITION_DURATION
		)
		_equipment_transition.tween_property(
			_equipment_indicator_visual, "modulate:a", 0.0, EQUIPMENT_TRANSITION_DURATION
		)
	_equipment_transition.chain().tween_callback(
		_finalize_equipment_transition.bind(enabled)
	)


func _apply_equipment_mode_immediately(enabled: bool) -> void:
	if is_instance_valid(_snapshot_visual):
		_snapshot_visual.visible = not enabled
		_snapshot_visual.modulate.a = 1.0
	if is_instance_valid(_shadow):
		_shadow.visible = not enabled
	if is_instance_valid(_equipment_indicator_visual):
		_equipment_indicator_visual.visible = enabled
		_equipment_indicator_visual.modulate.a = 1.0
		_equipment_indicator_visual.scale = _preview_scale
		_equipment_indicator_visual.position = _get_equipment_indicator_rest_position()


func _finalize_equipment_transition(enabled: bool) -> void:
	if enabled != _equipment_indicator_mode:
		return
	_apply_equipment_mode_immediately(enabled)


func _get_equipment_indicator_rest_position() -> Vector2:
	var center := EQUIPMENT_INDICATOR_SIZE * 0.5
	return -_equipment_indicator_grab_local_position * _preview_scale + center * (_preview_scale - Vector2.ONE)


func is_equipment_indicator_mode() -> bool:
	return _equipment_indicator_mode


func set_preview_rune_highlights(rune_indices: Array[int]) -> void:
	var source_card := get_source_card_view() as CardView
	if source_card == null:
		return
	if (
		source_card.is_rune_highlight_preview()
		and source_card.get_highlighted_rune_indices() == rune_indices
	):
		return
	# 手中卡使用假设牌型的参与槽位与时间轴，但本身不是半透明目标虚影。
	source_card.set_rune_pattern_highlights(rune_indices, true, false)


func _update_visual_transform(rotation_degrees_value: float = NAN) -> void:
	if not is_instance_valid(_card_visual):
		return
	if is_nan(rotation_degrees_value):
		rotation_degrees_value = _card_visual.rotation_degrees

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
