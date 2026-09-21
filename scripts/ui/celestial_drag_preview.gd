class_name CelestialDragPreview
extends Control

## 只有指示物外观的拖动预览；原生长按与单击携带共用相同抓取位置。
var visual: TextureRect
var lifted_grab: Vector2
var texture_size: Vector2
var visual_scale: Vector2

func configure(data: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = CardDragPreview.DRAG_PREVIEW_Z_INDEX
	visual = TextureRect.new()
	visual.texture = CelestialIndicatorStyle.get_texture((data["indicator"] as CelestialIndicator).kind)
	texture_size = visual.texture.get_size()
	visual.size = texture_size
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual_scale = data["scale"]
	visual.scale = visual_scale
	visual.position = -(data["grab"] as Vector2) * visual_scale
	lifted_grab = data["lifted_grab"]
	add_child(visual)
	var shadow := TextureRect.new()
	shadow.texture = visual.texture
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate = EquipmentIndicatorStyle.SHADOW_COLOR
	shadow.position = EquipmentIndicatorStyle.LIFTED_SHADOW_OFFSET
	shadow.show_behind_parent = true
	visual.add_child(shadow)

func continue_pickup() -> void:
	create_tween().tween_property(visual, "position", -lifted_grab * visual_scale, EquipmentIndicator.HOVER_LIFT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func get_visual_center() -> Vector2:
	return visual.get_global_transform_with_canvas() * (texture_size * 0.5)
