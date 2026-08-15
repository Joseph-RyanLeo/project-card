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
const FOLLOW_SPEED: float = 18.0 # 拖拽卡牌追赶鼠标的速度；越大越快贴近鼠标
const LAG_RATIO: float = 0.42 # 鼠标移动时卡牌保留的滞后比例；越大拖尾感越强
const SHADOW_OFFSET := Vector2(6.0, 8.0) # 拖拽卡牌阴影相对卡牌的偏移
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.32) # 拖拽卡牌阴影的颜色及透明度
const DRAG_PREVIEW_Z_INDEX: int = 3000 # 拖拽整卡/整队始终高于战场真实小队和目标虚影的全局层级

var _card_visual: Control
var _shadow: Panel
var _snapshot_visual: Variant
var _card_size: Vector2 = Vector2.ZERO
var _rest_position: Vector2 = Vector2.ZERO
var _shadow_rest_position: Vector2 = Vector2.ZERO
var _visual_lag: Vector2 = Vector2.ZERO
var _previous_root_global_position: Vector2 = Vector2.ZERO
var _tracking_started: bool = false


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
	_update_visual_transform()


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

	_update_visual_transform()

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


func _update_visual_transform() -> void:
	if not is_instance_valid(_card_visual):
		return

	_card_visual.position = _rest_position + _visual_lag
	# 活动卡保持水平，避免左上、右上越界属性随旋转半径产生明显位移。
	# 叠卡提示所需的旋转颤动由目标 SquadView 独立负责。
	_card_visual.rotation_degrees = 0.0
	if is_instance_valid(_shadow):
		_shadow.position = (
			_shadow_rest_position + _visual_lag + SHADOW_OFFSET
		)
		_shadow.rotation_degrees = 0.0
