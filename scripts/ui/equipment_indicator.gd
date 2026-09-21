class_name EquipmentIndicator
extends TextureRect

## 小队装备位的场上表现。它不拥有第二份物品数据，只保存并拖动同一个OwnedCard引用。

const CardViewScript = preload("res://scripts/ui/card_view.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const EquipmentIndicatorStyleScript = preload(
	"res://scripts/ui/equipment_indicator_style.gd"
)
const INDICATOR_SIZE := EquipmentIndicatorStyleScript.DISPLAY_SIZE
const FULL_CARD_CENTER := Vector2(49.5, 68.0) # 指示物离开卡面变回完整装备牌时，让鼠标位于卡牌中心
const HOVER_LIFT_OFFSET := 6.0 # 鼠标指向装备指示物时，图标向上跳起的距离
const HOVER_LIFT_DURATION := 0.10 # 指示物向上跳起的动画时长（秒）
const DROP_DURATION := 0.14 # 鼠标离开后，指示物向下落回卡面的动画时长（秒）

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

var owned_item: OwnedCard
var source_row: Node
var source_slot: Control
var drag_enabled: bool = false
var _left_button_pressed: bool = false
var _indicator_visual: TextureRect
var _indicator_shadow: TextureRect
var _lift_tween: Tween
var _hover_requires_reentry: bool = false


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = get_indicator_size()
	size = get_indicator_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = EquipmentIndicatorStyleScript.INDICATOR_Z_INDEX
	# 根节点只保留固定命中框，实际图像放在子节点中移动；否则图标上跳后
	# 命中框也会离开鼠标，mouse_entered / mouse_exited 会来回触发而抖动。
	texture = null
	_indicator_visual = TextureRect.new()
	_indicator_visual.name = "IndicatorVisual"
	_indicator_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_indicator_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_indicator_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_indicator_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_visual.size = get_indicator_size()
	add_child(_indicator_visual)
	_indicator_shadow = TextureRect.new()
	_indicator_shadow.name = "IndicatorShadow"
	_indicator_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_indicator_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_indicator_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_indicator_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_shadow.size = get_indicator_size()
	_indicator_shadow.position = EquipmentIndicatorStyleScript.SHADOW_OFFSET
	_indicator_shadow.modulate = EquipmentIndicatorStyleScript.SHADOW_COLOR
	_indicator_shadow.show_behind_parent = true
	_indicator_shadow.z_index = -1
	add_child(_indicator_shadow)
	move_child(_indicator_shadow, 0)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	_update_cursor_and_tooltip()


func get_indicator_size() -> Vector2:
	return INDICATOR_SIZE


func configure(
	item: OwnedCard,
	row: Node,
	slot: Control,
	can_drag: bool
) -> void:
	owned_item = item
	source_row = row
	source_slot = slot
	drag_enabled = can_drag
	var indicator_texture: Texture2D = (
		EquipmentIndicatorStyleScript.get_texture(item.card_data)
		if item != null
		else null
	)
	if is_instance_valid(_indicator_visual):
		_indicator_visual.texture = indicator_texture
	if is_instance_valid(_indicator_shadow):
		_indicator_shadow.texture = indicator_texture
	_update_cursor_and_tooltip()


func show_pointer_hover_feedback() -> void:
	if not drag_enabled or _left_button_pressed or _hover_requires_reentry:
		return
	_animate_lift(true)


func clear_pointer_hover_feedback() -> void:
	_animate_lift(false)


func play_drop_feedback(release_global_center: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(_indicator_visual) or not is_instance_valid(_indicator_shadow):
		return
	_hover_requires_reentry = true
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_indicator_visual.position = (
		get_global_transform_with_canvas().affine_inverse() * release_global_center
		- get_indicator_size() * 0.5
		if release_global_center.is_finite()
		else Vector2(0.0, -HOVER_LIFT_OFFSET)
	)
	_indicator_shadow.position = EquipmentIndicatorStyleScript.LIFTED_SHADOW_OFFSET
	_animate_lift(false)


func _on_mouse_entered() -> void:
	show_pointer_hover_feedback()


func _on_mouse_exited() -> void:
	_try_finish_hover_reentry(get_viewport().get_mouse_position())
	if not _left_button_pressed:
		clear_pointer_hover_feedback()


func _input(event: InputEvent) -> void:
	if _hover_requires_reentry and event is InputEventMouseMotion:
		_try_finish_hover_reentry((event as InputEventMouseMotion).position)


func _try_finish_hover_reentry(pointer_viewport_position: Vector2) -> void:
	var local_position := (
		get_global_transform_with_canvas().affine_inverse()
		* pointer_viewport_position
	)
	if not Rect2(Vector2.ZERO, size).has_point(local_position):
		_hover_requires_reentry = false


func _animate_lift(lifted: bool) -> void:
	if not is_instance_valid(_indicator_visual) or not is_instance_valid(_indicator_shadow):
		return
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	var duration := HOVER_LIFT_DURATION if lifted else DROP_DURATION
	_lift_tween = create_tween().set_parallel(true)
	_lift_tween.set_trans(Tween.TRANS_QUAD)
	_lift_tween.set_ease(Tween.EASE_OUT if lifted else Tween.EASE_IN)
	_lift_tween.tween_property(
		_indicator_visual,
		"position",
		Vector2(0.0, -HOVER_LIFT_OFFSET if lifted else 0.0),
		duration
	)
	_lift_tween.tween_property(
		_indicator_shadow,
		"position",
		(
			EquipmentIndicatorStyleScript.LIFTED_SHADOW_OFFSET
			if lifted
			else EquipmentIndicatorStyleScript.SHADOW_OFFSET
		),
		duration
	)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		_left_button_pressed = true
		_animate_lift(true)
	elif _left_button_pressed:
		_left_button_pressed = false
		var drag_data := build_drag_data(mouse_event.position)
		if not drag_data.is_empty():
			click_carry_requested.emit(
				drag_data,
				get_global_transform_with_canvas() * mouse_event.position
			)
	accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	var drag_data := build_drag_data(at_position)
	if drag_data.is_empty():
		return null
	# 同一拖拽预览可在指示物和完整物品卡之间切换，始终携带原物品实例。
	var preview := CardViewScript.create_drag_visual(drag_data)
	# 拖拽刚开始时鼠标仍在原随从卡牌上，所以先保持指示物形态；
	# BattlefieldRow 会在离开/进入可装备卡面时实时切换完整卡牌与指示物。
	preview.set_equipment_indicator_mode(true, false)
	drag_data["drag_visual"] = preview
	set_drag_preview(preview)
	preview.continue_equipment_pickup(drag_data["indicator_lifted_grab_local_position"])
	return drag_data


func build_drag_data(at_position: Vector2) -> Dictionary:
	if (
		not drag_enabled
		or owned_item == null
		or not owned_item.is_valid()
		or owned_item.card_data.card_type != CardData.CardType.EQUIPMENT
	):
		return {}
	var visual_scale := get_global_transform_with_canvas().get_scale()
	return {
		"kind": &"equipment_indicator",
		"card_data": owned_item.card_data,
		"owned_card": owned_item,
		"source_type": &"board",
		"source_row": source_row,
		"source_slot": source_slot,
		"grab_local_position": FULL_CARD_CENTER,
		"indicator_grab_local_position": at_position - _indicator_visual.position,
		"indicator_lifted_grab_local_position": at_position + Vector2(0.0, HOVER_LIFT_OFFSET),
		"preview_offset": FULL_CARD_CENTER * visual_scale,
		"drag_visual_scale": visual_scale,
		"showing_effect": false,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_left_button_pressed = false
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		if (
			drag_data is Dictionary
			and (drag_data as Dictionary).get("source_slot") == source_slot
			and (drag_data as Dictionary).get("kind") == &"equipment_indicator"
		):
			visible = false
	elif what == NOTIFICATION_DRAG_END:
		visible = true
		clear_pointer_hover_feedback()


func _update_cursor_and_tooltip() -> void:
	mouse_default_cursor_shape = (
		Control.CURSOR_DRAG if drag_enabled else Control.CURSOR_ARROW
	)
	tooltip_text = (
		"%s\n拖回收藏可卸下" % owned_item.card_data.display_name
		if owned_item != null and owned_item.card_data != null
		else "装备指示物"
	)
