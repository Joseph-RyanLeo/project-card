class_name EmblemLibraryEntry
extends Control

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal front_requested(instance_id: StringName)

## 同一贴纸实例在格内／临时区域中的表现，身份保存在returned_state。

const StatusIndicatorStyle = preload("res://scripts/ui/status_indicator_style.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")
const InspectionItemDrag = preload("res://scripts/ui/inspection_item_drag.gd")
const EMBLEM_ICON_SIZE := Vector2(14.0, 14.0) # 普通纹章按一个可见格显示
const ELEMENT_STICKER_ICON_SIZE := Vector2(27.0, 27.0) # 元素贴纸原图居中显示，四边各留2像素
const WOUND_ICON_SIZE := Vector2(14.0, 14.0) # 伤势目录保持卡面原始状态图标尺寸
const DROP_HOVER_LIFT := 1.0 # 临时贴纸指向时仅抬升一个原生像素，检视4倍时为4个逻辑像素
const DROP_LIFTED_SHADOW_OFFSET := Vector2(1.5, 2.5) # 临时贴纸轻微离开工具箱时的阴影偏移

var definition: Dictionary = {}
var drag_enabled: bool = false
var _icon: TextureRect
var _missing_label: Label
var _left_pressed := false
var _press_position := Vector2.ZERO
var _native_drag_started := false
var _shadow: TextureRect
var _lift_tween: Tween


func configure(value: Dictionary, enabled: bool) -> void:
	definition = value.duplicate(true)
	drag_enabled = enabled
	var is_wound: bool = String(definition.get("status_kind", "emblem")) == "wound"
	tooltip_text = EmblemLibraryData.get_wound_tooltip(StringName(definition.get("id", ""))) if is_wound else EmblemLibraryData.get_tooltip(StringName(definition.get("id", "")))
	if definition.has("returned_state"):
		tooltip_text = ("临时掉落 · " if EmblemStickerInventory.is_dropped(definition.returned_state) else "工具箱 · ") + tooltip_text
	if not is_node_ready():
		return
	_refresh_visual()


func set_drag_enabled(value: bool) -> void:
	drag_enabled = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW


func is_element_sticker() -> bool:
	return definition.get("target", "emblem") == "rune"


func update_layout_visuals() -> void:
	if is_instance_valid(_icon):
		_icon.position = (size - _icon.size) * 0.5
	if is_instance_valid(_shadow):
		_shadow.position = (size - _icon.size) * 0.5 + EquipmentIndicatorStyle.SHADOW_OFFSET
	if is_instance_valid(_missing_label):
		_missing_label.position = (size - _missing_label.size) * 0.5


func _ready() -> void:
	set_drag_enabled(drag_enabled)
	_refresh_visual()
	if EmblemStickerInventory.is_dropped(definition.get("returned_state", {})):
		_shadow = _icon.duplicate() as TextureRect
		_shadow.modulate = EquipmentIndicatorStyle.SHADOW_COLOR
		_shadow.position += EquipmentIndicatorStyle.SHADOW_OFFSET
		_shadow.z_index = -1
		add_child(_shadow)
		mouse_entered.connect(_lift.bind(true))
		mouse_exited.connect(_lift.bind(false))


func _gui_input(event: InputEvent) -> void:
	if not drag_enabled: return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_request_front()
		_left_pressed = true
		_native_drag_started = false
		_press_position = mouse.position
	elif _left_pressed:
		_left_pressed = false
		if drag_enabled and not definition.is_empty() and not _native_drag_started:
			click_carry_requested.emit(
				_build_drag_data(_press_position, false),
				get_global_transform_with_canvas() * mouse.position
			)
	accept_event()


func _refresh_visual() -> void:
	if _icon == null:
		_icon = TextureRect.new()
		_icon.name = "Icon"
		_icon.size = WOUND_ICON_SIZE
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
	if _missing_label == null:
		_missing_label = Label.new()
		_missing_label.name = "MissingVisual"
		_missing_label.position = Vector2(1, 0)
		_missing_label.size = WOUND_ICON_SIZE
		_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_missing_label.add_theme_font_size_override("font_size", 9)
		_missing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_missing_label)
	var status_id := definition.get("id", &"") as StringName
	var is_wound: bool = String(definition.get("status_kind", "emblem")) == "wound"
	_icon.texture = StatusIndicatorStyle.get_texture(
		CardSlotLayout.Kind.WOUND if is_wound else CardSlotLayout.Kind.EMBLEM,
		status_id
	)
	if is_wound:
		_icon.size = WOUND_ICON_SIZE
	elif is_element_sticker():
		_icon.texture = RuneStickerStyle.get_texture_by_id(status_id)
		_icon.size = ELEMENT_STICKER_ICON_SIZE
	else:
		_icon.size = EMBLEM_ICON_SIZE
	update_layout_visuals()
	_icon.visible = _icon.texture != null
	_missing_label.visible = not _icon.visible
	_missing_label.text = "?"


func _get_drag_data(at_position: Vector2) -> Variant:
	if not drag_enabled or definition.is_empty():
		return null
	_native_drag_started = true
	return _build_drag_data(_press_position if _left_pressed else at_position, true)


func _build_drag_data(grab_position: Vector2, install_preview: bool) -> Dictionary:
	_request_front()
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = _icon.texture
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size = _icon.size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if EmblemStickerInventory.is_dropped(definition.get("returned_state", {})):
		var shadow := TextureRect.new()
		shadow.texture = preview.texture
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.size = preview.size
		shadow.position = DROP_LIFTED_SHADOW_OFFSET
		shadow.modulate = EquipmentIndicatorStyle.SHADOW_COLOR
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.z_index = -1
		preview.add_child(shadow)
	if preview.texture == null:
		var preview_label := Label.new()
		preview_label.text = "?"
		preview_label.size = _icon.size
		preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(preview_label)
	var data := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": definition.get("id", &"") if definition.get("status_kind", "emblem") != "wound" else &"",
		"wound_id": definition.get("id", &"") if definition.get("status_kind", "emblem") == "wound" else &"",
		"status_kind": definition.get("status_kind", "emblem"),
		"definition": definition.duplicate(true),
		"source_entry": self,
		"preview_texture": _icon.texture,
	}
	var placement_inset := Vector2(2.0, 2.0) if is_element_sticker() else Vector2.ZERO
	return InspectionItemDrag.build(
		self,
		preview,
		grab_position,
		_icon.position,
		data,
		install_preview,
		placement_inset
	)


func _request_front() -> void:
	if EmblemStickerInventory.is_dropped(definition.get("returned_state", {})):
		front_requested.emit(StringName(String(definition.returned_state.instance_id)))


func _lift(lifted: bool, duration_override: float = -1.0) -> void:
	if not is_instance_valid(_shadow) or (lifted and not drag_enabled): return
	if is_instance_valid(_lift_tween): _lift_tween.kill()
	var rest := (size - _icon.size) * 0.5
	_lift_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD)
	_lift_tween.set_ease(Tween.EASE_OUT if lifted else Tween.EASE_IN)
	var duration := duration_override if duration_override > 0 else (EquipmentIndicator.HOVER_LIFT_DURATION if lifted else EquipmentIndicator.DROP_DURATION)
	_lift_tween.tween_property(_icon, "position", rest + Vector2(0, -DROP_HOVER_LIFT if lifted else 0), duration)
	_lift_tween.tween_property(_shadow, "position", rest + (DROP_LIFTED_SHADOW_OFFSET if lifted else EquipmentIndicatorStyle.SHADOW_OFFSET), duration)


func play_return_feedback(global_center: Vector2 = Vector2.INF) -> void:
	if is_instance_valid(_shadow) and global_center.is_finite():
		_icon.position = get_global_transform_with_canvas().affine_inverse() * global_center - _icon.size * 0.5
	_lift(false, EquipmentIndicator.RETURN_DURATION)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("source_entry") == self:
			_left_pressed = false
			visible = false
	elif what == NOTIFICATION_DRAG_END:
		visible = true
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("source_entry") == self and not get_viewport().gui_is_drag_successful():
			var preview := data.get("drag_visual") as Control
			play_return_feedback(preview.get_global_transform_with_canvas() * (preview.size * 0.5) if is_instance_valid(preview) else Vector2.INF)
		else:
			_lift(false)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return get_parent()._can_drop_data(position + at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	get_parent()._drop_data(position + at_position, data)
