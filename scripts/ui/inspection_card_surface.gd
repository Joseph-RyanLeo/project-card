class_name InspectionCardSurface
extends TextureRect

## 整张卡先合成后倾斜；命中点使用与着色器相同的逆投影，避免贴纸错位。
const SHADER = preload("res://shaders/card_preview_3d.gdshader")
const PADDING := Vector2(18, 18) # 容纳卡面外角标和贴纸
const TILT := 10.0 # 检视鼠标倾斜最大角度
var card: CardView
var viewport: SubViewport
var effect: ShaderMaterial
const FOLLOW_SPEED := 12.0 # 检视倾斜跟随鼠标的平滑速度
var force := Vector2.ZERO
var drop_handler: Callable
var tooltip_handler: Callable
var _drop_preview: TextureRect

func setup(value: CardView, handler: Callable, tooltip: Callable) -> void:
	card = value
	drop_handler = handler
	tooltip_handler = tooltip
	_setup_content(card, card.card_size)
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

func setup_art(value: Control) -> void:
	_setup_content(value, value.size)

func _setup_content(value: Control, content_size: Vector2) -> void:
	size = content_size + PADDING * 2.0
	viewport = SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	value.reparent(viewport)
	value.position = PADDING
	value.scale = Vector2.ONE
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	force = force.lerp(target, 1.0 - exp(-FOLLOW_SPEED * delta))
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
	if not drop_handler.is_valid():
		return false
	var context := _drop_context(point, data)
	var legal := bool(drop_handler.call(&"can_drop", card, context.point, context.data))
	if legal:
		_update_drop_preview(context.point, context.data)
	else:
		clear_drop_preview()
	return legal

func _drop_data(point: Vector2, data: Variant) -> void:
	if not drop_handler.is_valid():
		return
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
	var adjusted_data: Dictionary = data.duplicate() if data is Dictionary else {}
	return {"point": card_point(point), "data": adjusted_data}

func _get_tooltip(point: Vector2) -> String:
	return tooltip_handler.call(card_point(point)) if tooltip_handler.is_valid() else ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_parent().close_requested.emit()
		accept_event()
