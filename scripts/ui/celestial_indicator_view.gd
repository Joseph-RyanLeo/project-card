class_name CelestialIndicatorView
extends EquipmentIndicator

## 复用装备指示物的阴影、悬停和落地反馈；实例身份与拖动数据保持独立。
var indicator_data: CelestialIndicator

func get_indicator_size() -> Vector2:
	return CelestialIndicatorStyle.get_texture(indicator_data.kind).get_size() if indicator_data != null else Vector2(30, 30)

func _ready() -> void:
	super()
	_indicator_visual.texture = CelestialIndicatorStyle.get_texture(indicator_data.kind)
	_indicator_shadow.texture = _indicator_visual.texture
	_update_cursor_and_tooltip()

func build_drag_data(at_position: Vector2) -> Dictionary:
	if not drag_enabled or indicator_data == null:
		return {}
	return {
		"kind": &"celestial_indicator", "indicator": indicator_data,
		"source_slot": source_slot, "source_view": self,
		"grab": at_position - _indicator_visual.position,
		"lifted_grab": at_position + Vector2(0, HOVER_LIFT_OFFSET),
		"scale": get_global_transform_with_canvas().get_scale(),
	}

func _get_drag_data(at_position: Vector2) -> Variant:
	var data := build_drag_data(at_position)
	if data.is_empty():
		return null
	var preview := CelestialDragPreview.new()
	preview.configure(data)
	data["preview"] = preview
	set_drag_preview(preview)
	preview.continue_pickup()
	return data

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("source_view") == self:
			_left_button_pressed = false
			visible = false
	elif what == NOTIFICATION_DRAG_END:
		if not is_queued_for_deletion():
			visible = true
			clear_pointer_hover_feedback()

func _update_cursor_and_tooltip() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if drag_enabled else Control.CURSOR_ARROW
	if indicator_data != null:
		tooltip_text = CelestialIndicator.NAMES[indicator_data.kind] + "\n" + [
			"基础护甲+8、影蔽；行动时失去影蔽，3秒后恢复，期间再次行动不刷新。",
			"数值+1、耀眼；遗愿转移给随机友军，并使其本场数值额外+1。",
			"生命+6、数值+3、耀眼；除太阳携带者外，双方其他耀眼失效。",
		][indicator_data.kind]
