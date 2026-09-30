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
const RESOURCE_HEX_ATLAS: Texture2D = preload("res://assets/card_ui/resources/resource_hex_tile.png")
const RESOURCE_INDICATOR_STYLE = preload("res://scripts/ui/resource_indicator_style.gd")
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
const SPELL_PREPARATION_ICON_SIZE := Vector2(42.0, 42.0) # 法术准备栏原生图标尺寸
const SPELL_PREPARATION_TRANSITION_DURATION := 0.10 # 整卡与准备图标平滑切换的时长
const RESOURCE_PUZZLE_TRANSITION_DURATION := 0.10 # 整卡与六边形拼图交叉渐变的时长

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
var _spell_preparation_icon: TextureRect
var _spell_preparation_transition: Tween
var _spell_preparation_icon_mode: bool = false
var _resource_puzzle_mode := false
var _resource_puzzle_tiles: Array[TextureRect] = []
var _resource_puzzle_shape: Array[Vector2i] = []
var _resource_puzzle_rarity := -1
var _resource_puzzle_resource_type := -1
var _resource_puzzle_transition: Tween
var _resource_puzzle_icons: Array[TextureRect] = []
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


func set_resource_puzzle_mode(
	enabled: bool,
	shape: Array[Vector2i] = [],
	rarity: int = 0,
	grab_cell: Vector2i = Vector2i.ZERO,
	grab_pixel_offset: Vector2 = Vector2.ZERO,
	resource_type: int = -1
) -> void:
	if not enabled:
		if not _resource_puzzle_mode: return
		_resource_puzzle_mode = false
		_transition_resource_puzzle_visuals(false)
		return
	if shape.is_empty() or rarity < 0 or rarity >= RESOURCE_INDICATOR_STYLE.SOURCE_COLUMN_BY_RARITY.size(): return
	var shape_changed := _resource_puzzle_shape != shape or _resource_puzzle_rarity != rarity or _resource_puzzle_resource_type != resource_type
	if shape_changed: _rebuild_resource_puzzle_tiles(shape, rarity, resource_type)
	var entering := not _resource_puzzle_mode
	_resource_puzzle_mode = true
	_position_resource_puzzle_tiles(grab_cell, grab_pixel_offset)
	if entering: _transition_resource_puzzle_visuals(true)


func _rebuild_resource_puzzle_tiles(shape: Array[Vector2i], rarity: int, resource_type: int) -> void:
	for tile: TextureRect in _resource_puzzle_tiles: tile.queue_free()
	for icon: TextureRect in _resource_puzzle_icons: icon.queue_free()
	_resource_puzzle_tiles.clear()
	_resource_puzzle_icons.clear()
	_resource_puzzle_shape = shape.duplicate()
	_resource_puzzle_rarity = rarity
	_resource_puzzle_resource_type = resource_type
	var icon_texture := RESOURCE_INDICATOR_STYLE.get_icon_atlas_texture(rarity, resource_type)
	var icon_visible_rect: Rect2i = RESOURCE_INDICATOR_STYLE.get_icon_visible_rect(rarity, resource_type)
	for _cell in shape:
		var tile := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = RESOURCE_HEX_ATLAS
		atlas.region = Rect2(RESOURCE_INDICATOR_STYLE.get_source_x(rarity), 0, 35, 32)
		tile.texture = atlas
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.size = Vector2(35, 32)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.modulate.a = 0.0
		tile.visible = false
		add_child(tile)
		_resource_puzzle_tiles.append(tile)
		var icon := TextureRect.new()
		icon.name = "ResourcePuzzleKindIcon"
		var visible_texture := AtlasTexture.new()
		visible_texture.atlas = RESOURCE_INDICATOR_STYLE.ICON_ATLAS
		visible_texture.region = Rect2(
			icon_texture.region.position + Vector2(icon_visible_rect.position),
			Vector2(icon_visible_rect.size)
		)
		icon.texture = visible_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size = Vector2(icon_visible_rect.size)
		icon.position = -icon.size * 0.5
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.z_index = 2
		icon.modulate.a = 0.0
		add_child(icon)
		_resource_puzzle_icons.append(icon)


func _position_resource_puzzle_tiles(grab_cell: Vector2i, grab_pixel_offset: Vector2) -> void:
	for index in _resource_puzzle_tiles.size():
		var relative := _resource_puzzle_shape[index] - grab_cell
		var center := Vector2(27.0 * relative.x, 32.0 * relative.y - 16.0 * relative.x) - grab_pixel_offset
		_resource_puzzle_tiles[index].position = center - Vector2(17, 16)
		_resource_puzzle_icons[index].position = center - Vector2(_resource_puzzle_icons[index].size * 0.5)


func _transition_resource_puzzle_visuals(show_puzzle: bool) -> void:
	if is_instance_valid(_resource_puzzle_transition): _resource_puzzle_transition.kill()
	_resource_puzzle_transition = create_tween()
	if show_puzzle:
		if is_instance_valid(_card_visual): _card_visual.visible = true
		if is_instance_valid(_shadow): _shadow.visible = true
		for tile: TextureRect in _resource_puzzle_tiles: tile.visible = true
		_resource_puzzle_transition.tween_property(_card_visual, "modulate:a", 0.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		_resource_puzzle_transition.parallel().tween_property(_shadow, "modulate:a", 0.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		for icon: TextureRect in _resource_puzzle_icons:
			icon.visible = true
			_resource_puzzle_transition.parallel().tween_property(icon, "modulate:a", 1.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		for tile: TextureRect in _resource_puzzle_tiles:
			_resource_puzzle_transition.parallel().tween_property(tile, "modulate:a", 1.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		_resource_puzzle_transition.tween_callback(_finish_resource_puzzle_enter)
	else:
		if is_instance_valid(_card_visual): _card_visual.visible = true
		if is_instance_valid(_shadow): _shadow.visible = true
		_resource_puzzle_transition.tween_property(_card_visual, "modulate:a", 1.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		_resource_puzzle_transition.parallel().tween_property(_shadow, "modulate:a", 1.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		for icon: TextureRect in _resource_puzzle_icons:
			_resource_puzzle_transition.parallel().tween_property(icon, "modulate:a", 0.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		for tile: TextureRect in _resource_puzzle_tiles:
			_resource_puzzle_transition.parallel().tween_property(tile, "modulate:a", 0.0, RESOURCE_PUZZLE_TRANSITION_DURATION)
		_resource_puzzle_transition.tween_callback(_finish_resource_puzzle_exit)


func _finish_resource_puzzle_enter() -> void:
	if not _resource_puzzle_mode: return
	if is_instance_valid(_card_visual): _card_visual.visible = false
	if is_instance_valid(_shadow): _shadow.visible = false


func _finish_resource_puzzle_exit() -> void:
	if _resource_puzzle_mode: return
	for tile: TextureRect in _resource_puzzle_tiles:
		tile.visible = false
	for icon: TextureRect in _resource_puzzle_icons: icon.visible = false


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


func configure_spell_preparation_icon(
	icon_texture: Texture2D,
	grab_local_position: Vector2,
	source_card_size: Vector2,
	starts_as_icon: bool
) -> void:
	_spell_preparation_icon = TextureRect.new()
	_spell_preparation_icon.name = "SpellPreparationDragIcon"
	_spell_preparation_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spell_preparation_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_spell_preparation_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spell_preparation_icon.texture = icon_texture
	_spell_preparation_icon.size = SPELL_PREPARATION_ICON_SIZE
	_spell_preparation_icon.scale = _preview_scale
	_spell_preparation_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spell_preparation_icon.z_index = 10
	var icon_grab_position := grab_local_position
	if not starts_as_icon:
		icon_grab_position *= SPELL_PREPARATION_ICON_SIZE / source_card_size
	_spell_preparation_icon.position = -icon_grab_position
	_spell_preparation_icon.modulate.a = 1.0 if starts_as_icon else 0.0
	_card_visual.modulate.a = 0.0 if starts_as_icon else 0.9
	_shadow.visible = not starts_as_icon
	_spell_preparation_icon_mode = starts_as_icon
	add_child(_spell_preparation_icon)


func set_spell_preparation_icon_mode(enabled: bool) -> void:
	if (
		not is_instance_valid(_spell_preparation_icon)
		or enabled == _spell_preparation_icon_mode
	):
		return
	_spell_preparation_icon_mode = enabled
	if is_instance_valid(_spell_preparation_transition) and _spell_preparation_transition.is_running():
		_spell_preparation_transition.kill()
	_shadow.visible = not enabled
	_spell_preparation_transition = create_tween().set_parallel(true)
	_spell_preparation_transition.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spell_preparation_transition.tween_property(
		_card_visual, "modulate:a", 0.0 if enabled else 0.9, SPELL_PREPARATION_TRANSITION_DURATION
	)
	_spell_preparation_transition.tween_property(
		_spell_preparation_icon,
		"modulate:a",
		1.0 if enabled else 0.0,
		SPELL_PREPARATION_TRANSITION_DURATION
	)


func prepare_spell_preparation_transition() -> void:
	# 一次性卡面快照在淡出期间冻结，避免为过渡动画持续重绘 SubViewport。
	if is_instance_valid(_snapshot_visual):
		var snapshot_viewport := _snapshot_visual.get_node_or_null("CardSnapshotViewport") as SubViewport
		if snapshot_viewport != null:
			snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(_shadow):
		_shadow.visible = false
	if is_instance_valid(_equipment_indicator_visual):
		_equipment_indicator_visual.visible = false
	set_process(false)


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
