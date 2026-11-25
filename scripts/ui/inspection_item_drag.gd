class_name InspectionItemDrag
extends RefCounted

## 纹章、伤势和刮刀共用的拖拽显示数据；来源只补充物件身份与专用命中形状。

const STICKER_RESIZE_SECONDS := 0.15 # 纹章跨放置区时切换到目标倍率的时长


class StickerPreview extends TextureRect:
	var _target_scale: Vector2
	var _scale_tween: Tween

	func animate_scale(value: Vector2) -> void:
		if value.is_equal_approx(_target_scale): return
		_target_scale = value
		if is_instance_valid(_scale_tween): _scale_tween.kill()
		if scale.is_equal_approx(value): return
		_scale_tween = create_tween()
		_scale_tween.tween_property(self, "scale", value, STICKER_RESIZE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	if preview is StickerPreview:
		# 控件的缩放中心就是抓取点，倍率变化时手持图案会继续贴住鼠标。
		preview.pivot_offset = -preview_offset / preview_scale
		preview.position = -preview.pivot_offset
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


static func placement_origin(target_to_canvas: Transform2D, pointer: Vector2, data: Dictionary, target_item_scale := Vector2.ZERO) -> Vector2:
	var offset := data.get("placement_offset", Vector2.ZERO) as Vector2
	if target_item_scale != Vector2.ZERO:
		# 从工具箱的四倍图缩到交付区的两倍图时，保留抓取点在物件里的比例。
		offset *= target_item_scale / (data.get("preview_scale", Vector2.ONE) as Vector2)
	return target_to_canvas.affine_inverse() * (pointer + offset)
