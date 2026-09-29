class_name InspectionItemDrag
extends RefCounted

## 纹章、伤势和刮刀共用的拖拽显示数据；来源只补充物件身份与专用命中形状。


static func build(
	source: Control,
	preview: Control,
	grab_position: Vector2,
	preview_origin: Vector2,
	data: Dictionary,
	install_native_preview: bool,
	placement_inset := Vector2.ZERO
) -> Dictionary:
	var source_transform := source.get_global_transform_with_canvas()
	var preview_scale := source_transform.get_scale()
	var preview_offset := source_transform.basis_xform(preview_origin - grab_position)
	var placement_offset := source_transform.basis_xform(
		preview_origin - grab_position - placement_inset
	)
	preview.scale = preview_scale
	preview.position = preview_offset
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	data["preview_size"] = preview.size
	data["preview_scale"] = preview_scale
	data["preview_offset"] = preview_offset
	data["placement_offset"] = placement_offset
	data["drag_visual"] = preview
	if install_native_preview:
		preview.z_index = 4096
		preview.z_as_relative = false
		var preview_root := Control.new()
		preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_root.add_child(preview)
		source.set_drag_preview(preview_root)
	return data
