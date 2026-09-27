extends TextureRect

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

## 固定工具位；工具本身不被消耗，只有松手命中时才调用卡牌的移除操作。
var enabled := false
var blade_point := Vector2.ZERO # 刀头中心，按实际显示比例从素材命中定义换算
var blade_rect := Rect2() # 刀头可刮区域，排除刀柄
var _left_pressed := false
var _press_position := Vector2.ZERO
var _native_drag_started := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tooltip_text = "状态刮刀\n松手时以刀头命中后贴纹章、伤势或符文贴纸即可移除；移除物销毁，不返还工作包。"

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_left_pressed = true
		_native_drag_started = false
		_press_position = mouse.position
	elif _left_pressed:
		_left_pressed = false
		if enabled and not _native_drag_started:
			click_carry_requested.emit(
				_build_drag_data(mouse.position, false),
				get_global_transform_with_canvas() * mouse.position
			)
	accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if not enabled:
		return null
	_native_drag_started = true
	return _build_drag_data(_press_position if _left_pressed else at_position, true)


func _build_drag_data(grab_position: Vector2, install_preview: bool) -> Dictionary:
	var source_transform := get_global_transform_with_canvas()
	var preview_scale := source_transform.get_scale()
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = texture
	preview.size = size
	preview.stretch_mode = stretch_mode
	preview.texture_filter = texture_filter
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.z_index = 4096
	preview.z_as_relative = false
	preview.scale = preview_scale
	var preview_offset := -source_transform.basis_xform(grab_position)
	preview.position = preview_offset
	if install_preview:
		var preview_root := Control.new()
		preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_root.add_child(preview)
		set_drag_preview(preview_root)
	return {
		"kind": &"sticker_scraper",
		"source_type": &"inspection_library",
		"tip_offset": source_transform.basis_xform(blade_point - grab_position),
		"hit_rect_offset": source_transform.basis_xform(blade_rect.position - grab_position),
		"hit_rect_size": source_transform.basis_xform(blade_rect.size),
		"preview_texture": texture,
		"preview_size": source_transform.basis_xform(size),
		"preview_offset": preview_offset,
		"drag_visual": preview,
	}
