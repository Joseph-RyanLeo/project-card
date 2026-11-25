extends RefCounted

## 将控件的轮廓映射到教学画布，保留旋转与缩放。挖空卡框只提取外轮廓。
static var _frame_masks: Dictionary = {}
static var _card_masks: Dictionary = {}


static func card_mask(card: Control) -> Dictionary:
	var inverse := card.get_global_transform().affine_inverse()
	var parts: Array[Dictionary] = []
	var key: Array = []
	var bounds := Rect2i()
	for layer: TextureRect in [card.card_frame, card.action_icon, card.health_icon, card.armor_icon, card.race_icon, card.cooldown_icon]:
		if not layer.visible or layer.texture == null: continue
		var rect := Rect2(Vector2.ZERO, layer.size)
		if layer.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var pixels := layer.texture.get_size()
			var fitted := pixels * minf(rect.size.x / pixels.x, rect.size.y / pixels.y)
			rect = Rect2((rect.size - fitted) * 0.5, fitted)
		rect = (inverse * layer.get_global_transform()) * rect
		var pixels_rect := Rect2i(rect.position.round(), rect.size.round())
		if not pixels_rect.has_area(): continue
		var texture := frame_mask(layer.texture) if layer == card.card_frame else layer.texture
		parts.append({"texture": texture, "rect": pixels_rect})
		key.append([texture.get_instance_id(), pixels_rect])
		bounds = bounds.merge(pixels_rect) if bounds.has_area() else pixels_rect
	if _card_masks.has(key): return _card_masks[key]
	if parts.is_empty(): return {}
	var image := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for part: Dictionary in parts:
		var pixels: Image = part.texture.get_image()
		if pixels == null or pixels.is_empty(): continue
		var destination: Rect2i = part.rect
		pixels.convert(Image.FORMAT_RGBA8)
		pixels.resize(destination.size.x, destination.size.y, Image.INTERPOLATE_NEAREST)
		image.blit_rect_mask(pixels, pixels, Rect2i(Vector2i.ZERO, destination.size), destination.position - bounds.position)
	var mask := {"texture": ImageTexture.create_from_image(image), "bounds": Rect2(bounds)}
	_card_masks[key] = mask
	return mask


static func set_transform(material: ShaderMaterial, target: Control) -> void:
	var inverse := target.get_global_transform_with_canvas().affine_inverse()
	material.set_shader_parameter("canvas_to_focus_axes", Vector4(inverse.x.x, inverse.y.x, inverse.x.y, inverse.y.y))
	material.set_shader_parameter("canvas_to_focus_origin", inverse.origin)
	material.set_shader_parameter("focus_sprite_size", target.size)


static func set_texture(material: ShaderMaterial, texture: Texture2D) -> void:
	var source := texture
	var region := Vector4(0.0, 0.0, 1.0, 1.0)
	if texture is AtlasTexture:
		source = texture.atlas
		var atlas_size := source.get_size()
		region = Vector4(texture.region.position.x / atlas_size.x, texture.region.position.y / atlas_size.y,
			texture.region.size.x / atlas_size.x, texture.region.size.y / atlas_size.y)
	material.set_shader_parameter("focus_texture", source)
	material.set_shader_parameter("focus_region", region)
	material.set_shader_parameter("focus_texture_pixel", Vector2.ONE / source.get_size())


static func frame_mask(texture: Texture2D) -> Texture2D:
	if texture == null: return null
	var id := texture.get_instance_id()
	if _frame_masks.has(id): return _frame_masks[id]
	var source := texture.get_image()
	if source == null or source.is_empty(): return texture
	var dimensions := source.get_size()
	var outside := PackedByteArray()
	outside.resize(dimensions.x * dimensions.y)
	var queue := PackedVector2Array()
	for x: int in dimensions.x:
		_visit(Vector2i(x, 0), source, outside, queue)
		_visit(Vector2i(x, dimensions.y - 1), source, outside, queue)
	for y: int in dimensions.y:
		_visit(Vector2i(0, y), source, outside, queue)
		_visit(Vector2i(dimensions.x - 1, y), source, outside, queue)
	var bounds := Rect2i(Vector2i.ZERO, dimensions)
	var cursor := 0
	while cursor < queue.size():
		var center := Vector2i(queue[cursor])
		cursor += 1
		for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var point := center + direction
			if bounds.has_point(point): _visit(point, source, outside, queue)
	var image := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	for y: int in dimensions.y:
		for x: int in dimensions.x:
			if outside[y * dimensions.x + x] == 0: image.set_pixel(x, y, Color.WHITE)
	var mask := ImageTexture.create_from_image(image)
	_frame_masks[id] = mask
	return mask


static func _visit(point: Vector2i, source: Image, outside: PackedByteArray, queue: PackedVector2Array) -> void:
	var index := point.y * source.get_width() + point.x
	if outside[index] != 0 or source.get_pixelv(point).a > 0.0: return
	outside[index] = 1
	queue.append(Vector2(point))
