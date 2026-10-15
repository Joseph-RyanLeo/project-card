extends EquipmentIndicator

## 哨位归属整排或法术板，复用装备指示物的拾起、阴影和原生拖动预览。
const Style = preload("res://scripts/ui/sentry_indicator_style.gd")
const Preview = preload("res://scripts/ui/celestial_drag_preview.gd")
var sentry_data: Dictionary = {}
var region: String = "stock"
var talent_description: String = ""

func get_indicator_size() -> Vector2:
	return Vector2(44, 49) # 哨位使用原生1倍像素尺寸与命中范围

func _ready() -> void:
	super()
	_indicator_visual.texture = Style.get_texture(int(sentry_data.visual_variant))
	_indicator_shadow.texture = _indicator_visual.texture
	_indicator_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_indicator_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _update_cursor_and_tooltip() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG if drag_enabled else Control.CURSOR_ARROW
	tooltip_text = "哨位：点击拿起再点击放下，或长按拖动。前排分担近战、后排分担远程、法术板分担法术伤害；放回指示物板回收。"
	if sentry_data.has("capacity"):
		tooltip_text += "\n容量%d" % int(sentry_data.capacity)
	if not talent_description.is_empty():
		tooltip_text += "\n当前英雄对哨位的增强：\n" + talent_description

func build_drag_data(at_position: Vector2) -> Dictionary:
	if not drag_enabled: return {}
	var image: Texture2D = Style.get_texture(int(sentry_data.visual_variant))
	var image_scale := get_indicator_size() / image.get_size()
	return {"kind": &"sentry_indicator", "instance_id": String(sentry_data.instance_id), "source_view": self,
		"texture": image, "grab": (at_position - _indicator_visual.position) / image_scale,
		"lifted_grab": (at_position + Vector2(0, HOVER_LIFT_OFFSET)) / image_scale,
		"scale": get_global_transform_with_canvas().get_scale() * image_scale}

func _get_drag_data(at_position: Vector2) -> Variant:
	var data := build_drag_data(at_position)
	if data.is_empty(): return null
	var preview := Preview.new()
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
	elif what == NOTIFICATION_DRAG_END and not is_queued_for_deletion():
		visible = true
		clear_pointer_hover_feedback()
