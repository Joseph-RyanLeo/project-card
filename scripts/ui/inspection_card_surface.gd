class_name InspectionCardSurface
extends TextureRect

## 整张卡先合成后倾斜；命中点使用与着色器相同的逆投影，避免贴纸错位。
const SHADER = preload("res://shaders/card_preview_3d.gdshader")
const PADDING := Vector2(18, 18) # 容纳卡面外角标和贴纸
const TILT := 10.0 # 检视鼠标倾斜最大角度
var card: CardView
var viewport: SubViewport
var effect: ShaderMaterial
var force := Vector2.ZERO
var drop_handler: Callable
var tooltip_handler: Callable
var _drop_preview: TextureRect

func setup(value: CardView, handler: Callable, tooltip: Callable) -> void:
	card = value
	drop_handler = handler
	tooltip_handler = tooltip
	size = card.card_size + PADDING * 2.0
	viewport = SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	card.get_parent().remove_child(card)
	viewport.add_child(card)
	card.position = PADDING
	card.scale = Vector2.ONE
	_drop_preview = TextureRect.new()
	_drop_preview.name = "InspectionStickerPreview"
	_drop_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drop_preview.stretch_mode = TextureRect.STRETCH_KEEP
	_drop_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drop_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_preview.modulate = Color(1.0, 1.0, 1.0, 0.45)
	_drop_preview.z_index = 100
	_drop_preview.visible = false
	card.add_child(_drop_preview)
	texture = viewport.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect = ShaderMaterial.new()
	effect.shader = SHADER
	effect.set_shader_parameter("use_3d", true)
	effect.set_shader_parameter("use_flash", true)
	effect.set_shader_parameter("max_tilt_degrees", TILT)
	effect.set_shader_parameter("inset", 0.0)
	effect.set_shader_parameter("stripe_spacing", 14.0)
	effect.set_shader_parameter("stripe_width", 10.0)
	effect.set_shader_parameter("flash_intensity", 0.2)
	effect.set_shader_parameter("flash_type", 1)
	effect.set_shader_parameter("card_texture_size_px", size)
	material = effect
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	var pointer := get_local_mouse_position()
	var target := Vector2.ZERO
	if Rect2(Vector2.ZERO, size).has_point(pointer):
		target = (pointer / size - Vector2(0.5, 0.5)) * 2.0
	force = force.lerp(target, 1.0 - exp(-12.0 * delta))
	effect.set_shader_parameter("pointer_force", force)

func card_point(point: Vector2) -> Vector2:
	var perspective := tan(deg_to_rad(72.0) * 0.5)
	var uv := (point / size - Vector2(0.5, 0.5)) / (1.0 + perspective) + Vector2(0.5, 0.5)
	var y := deg_to_rad(force.x * TILT)
	var x := deg_to_rad(-force.y * TILT)
	var rotation := Basis(Vector3(cos(y), 0, -sin(y)), Vector3(sin(y)*sin(x), cos(x), cos(y)*sin(x)), Vector3(sin(y)*cos(x), -sin(x), cos(y)*cos(x)))
	var projected := rotation * Vector3(uv.x - 0.5, uv.y - 0.5, 0.5 / perspective)
	var distance := 0.5 / perspective + 0.5
	var sample_uv := Vector2(projected.x, projected.y) * distance * rotation.z.z / projected.z - Vector2(rotation.z.x, rotation.z.y) * distance + Vector2(0.5, 0.5)
	return sample_uv * size - PADDING

func _can_drop_data(point: Vector2, data: Variant) -> bool:
	var context := _drop_context(point, data)
	var legal := bool(drop_handler.call(&"can_drop", card, context.point, context.data))
	if legal:
		_update_drop_preview(context.point, context.data)
	else:
		clear_drop_preview()
	return legal

func _drop_data(point: Vector2, data: Variant) -> void:
	var context := _drop_context(point, data)
	clear_drop_preview()
	drop_handler.call(&"animate_drop", card, context.point, context.data)

func can_drop_global(pointer_global: Vector2, data: Dictionary) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse() * pointer_global
	return _can_drop_data(point, data)

func drop_global(pointer_global: Vector2, data: Dictionary) -> bool:
	var point := get_global_transform_with_canvas().affine_inverse() * pointer_global
	if not _can_drop_data(point, data):
		clear_drop_preview()
		return false
	var context := _drop_context(point, data)
	clear_drop_preview()
	return bool(drop_handler.call(&"animate_drop", card, context.point, context.data))

func clear_drop_preview() -> void:
	if is_instance_valid(_drop_preview):
		_drop_preview.visible = false
		_drop_preview.texture = null

func _update_drop_preview(point: Vector2, data: Dictionary) -> void:
	if not is_instance_valid(_drop_preview):
		return
	var preview := drop_handler.call(&"get_preview", card, point, data) as Dictionary
	if preview.is_empty():
		clear_drop_preview()
		return
	_drop_preview.texture = preview.get("texture") as Texture2D
	_drop_preview.position = preview.get("position", Vector2.ZERO) as Vector2
	_drop_preview.size = preview.get("size", Vector2.ZERO) as Vector2
	_drop_preview.visible = _drop_preview.texture != null

func _drop_context(point: Vector2, data: Variant) -> Dictionary:
	var adjusted_point := _tool_point(point, data)
	var adjusted_data: Dictionary = data.duplicate() if data is Dictionary else {}
	if data is Dictionary and data.get("kind") == &"sticker_scraper":
		var surface_scale := get_global_transform_with_canvas().get_scale()
		var offset := (data.get("hit_rect_offset", Vector2.ZERO) as Vector2) / surface_scale
		var hit_size := (data.get("hit_rect_size", Vector2.ZERO) as Vector2) / surface_scale
		var corners := [
			card_point(point + offset),
			card_point(point + offset + Vector2(hit_size.x, 0)),
			card_point(point + offset + hit_size),
			card_point(point + offset + Vector2(0, hit_size.y)),
		]
		var min_point := corners[0] as Vector2
		var max_point := min_point
		for corner_value: Variant in corners:
			var corner := corner_value as Vector2
			min_point = min_point.min(corner)
			max_point = max_point.max(corner)
		adjusted_data["_inspection_hit_rect"] = Rect2(min_point, max_point - min_point)
	return {"point": card_point(adjusted_point), "data": adjusted_data}

func _tool_point(point: Vector2, data: Variant) -> Vector2:
	if data is Dictionary and data.get("kind") == &"sticker_scraper":
		return point + (data.get("tip_offset", Vector2.ZERO) as Vector2) / get_global_transform_with_canvas().get_scale()
	return point

func _get_tooltip(point: Vector2) -> String:
	return tooltip_handler.call(card_point(point)) if tooltip_handler.is_valid() else ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_parent().close_requested.emit()
		accept_event()
