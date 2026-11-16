@tool
class_name CardFinishPreview
extends RefCounted

## 调整器、真实单卡与开包共用的卡面工艺；卡面与卡图独立组合。
const SETTINGS = preload("res://resources/ui/card_finish_settings.tres")
const Appearance = preload("res://scripts/data/card_appearance.gd")
enum Finish { PLAIN, FOIL, HOLOGRAPHIC, EMBOSSED, FRACTURED, OVERFRAME, FROSTED, FINGERPRINT }
const LABELS := ["普通卡", "闪卡", "全息闪卡", "法线闪卡", "碎闪", "超框卡", "磨砂闪", "指纹闪"]
const ART_SHADER := preload("res://shaders/card_art_finish.gdshader")
const BADGE_SHADER := preload("res://shaders/card_badge_relief.gdshader")
const REST_FLASH_SHADER := preload("res://shaders/card_rest_flash.gdshader")
const FRAME_FOIL_SHADER := preload("res://shaders/card_frame_foil.gdshader")
const BADGE_SHADOW_PADDING := 3.0 # 图标阴影所需的原生画布安全边
const BACKGROUND_DEPTH_RATIO := 2.4 # 背景距卡框的深度相对人物深度的比例；大于1使背景更远
const FLASH_DIRECTION_DEADZONE: float = 0.01 # 鼠标归一化方向小于此半径时保持上次光带方向，避免中心抖动
const DEPTH_DISTANCE_SCALE := 10.0 # 每档景深对应的原生空间距离；默认2.5使人物位于卡框后25px
const ART_OUTLINE_GAIN := 3.2 # 立绘线条反光倍率
const BACKGROUND_OUTLINE_GAIN := 1.0 # 背景线条反光倍率，让立绘仍是视觉主体
const NUMBER_OUTLINE_GAIN := 1.0 # 数字黑边反光倍率，保留字形对比

var surface_finish: Appearance.Surface = Appearance.Surface.GOLD
var art_finish: Appearance.Art = Appearance.Art.PLAIN
# 调整器入口映射到同一套双维度渲染；真实实例直接配置下面两个字段。
var finish: Finish = Finish.FOIL:
	set(value):
		finish = value
		surface_finish = Appearance.Surface.PLAIN
		art_finish = Appearance.Art.PLAIN
		match value:
			Finish.FOIL, Finish.OVERFRAME:
				var flash_type := int(_surface.get_shader_parameter("flash_type")) if _surface != null else 1
				surface_finish = (Appearance.Surface.SILVER + flash_type) as Appearance.Surface
				if value == Finish.OVERFRAME: art_finish = Appearance.Art.OVERFRAME
			Finish.HOLOGRAPHIC: art_finish = Appearance.Art.HOLOGRAPHIC
			Finish.EMBOSSED: surface_finish = Appearance.Surface.EMBOSSED
			Finish.FRACTURED: surface_finish = Appearance.Surface.FRACTURED
			Finish.FROSTED: surface_finish = Appearance.Surface.FROSTED
			Finish.FINGERPRINT: surface_finish = Appearance.Surface.FINGERPRINT
var settings_source: Resource = SETTINGS # 正式卡面使用全局资源；纹理工具指定独立草稿
var enabled := true
var _card: CardView
var _surface: ShaderMaterial
var _art_material: ShaderMaterial
var _background_material: ShaderMaterial
var _frame_material: ShaderMaterial
var _background_source: Texture2D
var _background_opaque: Texture2D
var _badge_materials: Dictionary[TextureRect, ShaderMaterial] = {}
var _detail_outlines: Dictionary[Control, ShaderMaterial] = {}
var _embossed_outline := false
var _rest_flash: TextureRect
var _surface_composited := true
var _flash_direction_force := Vector2.ZERO
static var _background_cache: Dictionary[Texture2D, Texture2D] = {}
static var _badge_asset_cache: Dictionary = {}
static var _rest_flash_mask_cache: Dictionary = {}


func setup(card: CardView, surface: ShaderMaterial) -> void:
	_card = card
	_surface = surface
	SETTINGS.changed.connect(refresh)
	_art_material = ShaderMaterial.new()
	_art_material.shader = ART_SHADER
	_art_material.set_shader_parameter("pointer_force", Vector2.ZERO)
	_background_material = ShaderMaterial.new()
	_background_material.shader = ART_SHADER
	_background_material.set_shader_parameter("background_layer", true)
	_background_material.set_shader_parameter("outline_gain", BACKGROUND_OUTLINE_GAIN)
	_background_material.set_shader_parameter("outline_silhouette", 0.0)
	_frame_material = ShaderMaterial.new()
	_frame_material.shader = FRAME_FOIL_SHADER
	_card.art_texture.material = _art_material
	_card.art_background.material = _background_material
	_art_material.set_shader_parameter("outline_gain", ART_OUTLINE_GAIN)
	for number: Control in _number_layers():
		number.item_rect_changed.connect(_sync_outline_origin.bind(number))
	_card.rune_row.sort_children.connect(_sync_rune_outline_origins)
	for badge: TextureRect in [_card.action_icon, _card.health_icon, _card.armor_icon, _card.race_icon, _card.cooldown_icon]:
		var material := ShaderMaterial.new()
		material.shader = BADGE_SHADER
		material.set_shader_parameter("padding_pixels", BADGE_SHADOW_PADDING)
		badge.material = material
		_badge_materials[badge] = material
	refresh()


func bind_surface(surface: ShaderMaterial, composited: bool = true) -> void:
	_surface = surface
	_surface_composited = composited
	refresh()


func refresh() -> void:
	if not is_instance_valid(_card): return
	var face := int(surface_finish) if enabled else Appearance.Surface.PLAIN
	var art := int(art_finish) if enabled else Appearance.Art.PLAIN
	_embossed_outline = face == Appearance.Surface.EMBOSSED
	var overframe := art == Appearance.Art.OVERFRAME
	_card._refresh_card_frame(overframe)
	_card.card_frame.material = null if overframe else _frame_material
	var face_key: StringName = &"fractured" if face == Appearance.Surface.FRACTURED else (&"embossed" if face == Appearance.Surface.EMBOSSED else &"plain")
	var face_parameters: Vector3 = settings_source.parameters(face_key)
	var art_parameters: Vector3 = settings_source.parameters(&"holographic")
	var texture_parameters := face_parameters if face == Appearance.Surface.EMBOSSED else art_parameters
	var active := int(Finish.HOLOGRAPHIC) if art == Appearance.Art.HOLOGRAPHIC else -1
	var foil := face in [Appearance.Surface.SILVER, Appearance.Surface.GOLD, Appearance.Surface.RAINBOW]
	var flash := foil or face in [Appearance.Surface.FRACTURED, Appearance.Surface.EMBOSSED]
	var flash_type := face - Appearance.Surface.SILVER if foil else 0
	var brightness: float = settings_source.fractured_brightness if face == Appearance.Surface.FRACTURED else 1.0
	settings_source.apply_flash(_surface, brightness)
	settings_source.apply_fractured_color(_surface)
	var film_key := StringName(Appearance.SURFACE_KEYS[face])
	for material: ShaderMaterial in [_art_material, _background_material, _frame_material]:
		settings_source.apply_flash(material, brightness)
		settings_source.apply_film(material, film_key)
		material.set_shader_parameter("card_size", _card.card_size)
		material.set_shader_parameter("foil_padding", InspectionCardSurface.PADDING)
	var special := face != Appearance.Surface.PLAIN or art != Appearance.Art.PLAIN
	_surface.set_shader_parameter("use_flash", flash)
	_surface.set_shader_parameter("flash_in_layers", flash)
	for material: ShaderMaterial in [_frame_material, _background_material]:
		material.set_shader_parameter("foil_enabled", flash)
		material.set_shader_parameter("pointer_light_enabled", special)
		material.set_shader_parameter("flash_type", flash_type)
		material.set_shader_parameter("foil_shade_strength", settings_source.foil_shade_strength)
	_art_material.set_shader_parameter("pointer_light_enabled", special)
	_art_material.set_shader_parameter("outline_highlight_enabled", _embossed_outline)
	_background_material.set_shader_parameter("outline_highlight_enabled", _embossed_outline)
	_frame_material.set_shader_parameter("outline_highlight_enabled", _embossed_outline)
	_frame_material.set_shader_parameter("layer_origin", _card.card_frame.position)
	_art_material.set_shader_parameter("foil_shade_strength", settings_source.foil_shade_strength)
	if flash:
		_surface.set_shader_parameter("flash_type", flash_type)
	_surface.set_shader_parameter("use_fractured", face == Appearance.Surface.FRACTURED)
	_surface.set_shader_parameter("finish_strength", face_parameters.x)
	_surface.set_shader_parameter("finish_density", face_parameters.z)
	_surface.set_shader_parameter("mask_origin_px", _card.position)
	_surface.set_shader_parameter("mask_size_px", _card.card_size)
	_art_material.set_shader_parameter("embossed", face == Appearance.Surface.EMBOSSED)
	for material: ShaderMaterial in [_art_material, _background_material]:
		material.set_shader_parameter("effect_strength", texture_parameters.x)
		material.set_shader_parameter("texture_density", texture_parameters.z)
		material.set_shader_parameter("card_finish", active)
		material.set_shader_parameter("use_3d", _surface.get_shader_parameter("use_3d"))
		material.set_shader_parameter("max_tilt_degrees", _surface.get_shader_parameter("max_tilt_degrees"))
		material.set_shader_parameter("fov", _surface.get_shader_parameter("fov"))
		material.set_shader_parameter("projection_size", _surface.get_shader_parameter("card_texture_size_px"))
		material.set_shader_parameter("card_origin", _card.position)
	_art_material.set_shader_parameter("layer_size", _card.art_texture.size)
	_background_material.set_shader_parameter("layer_size", _card.art_background.size)
	var art_depth := -art_parameters.y * DEPTH_DISTANCE_SCALE if active == Finish.HOLOGRAPHIC else 0.0
	_art_material.set_shader_parameter("layer_depth", art_depth)
	_background_material.set_shader_parameter("layer_depth", art_depth * BACKGROUND_DEPTH_RATIO)
	_art_material.set_shader_parameter("layer_origin", _card.art_panel.position + _card.art_texture.position)
	_background_material.set_shader_parameter("layer_origin", _card.art_panel.position + _card.art_background.position)
	var definition := _card.card_data
	var background_source := definition.get_background_texture() if definition != null else CardView.DEFAULT_ART_BACKGROUND_TEXTURE
	if active == Finish.HOLOGRAPHIC:
		if background_source != _background_source:
			_background_source = background_source
			_background_opaque = _fill_background_transparency(background_source)
		_card.art_background.texture = _background_opaque
	else:
		_card.art_background.texture = background_source
	var normal_texture: Texture2D = definition.art_normal_texture if definition != null else null
	_art_material.set_shader_parameter("has_normal_texture", normal_texture != null)
	_art_material.set_shader_parameter("surface_normal", normal_texture)
	# 新法线工艺在人物层处理，避免外层再重复照亮一次。
	_surface.set_shader_parameter("use_normal_texture", false)
	_refresh_badges()
	refresh_detail_outlines()
	_refresh_rest_flash(face, face_parameters)


func _number_layers() -> Array[Control]:
	return [_card.value_label, _card.health_label, _card.armor_label, _card.cooldown_label]


func refresh_detail_outlines() -> void:
	if not _embossed_outline:
		for layer: Control in _detail_outlines:
			if is_instance_valid(layer): layer.material = null
		_detail_outlines.clear()
		return
	_detail_outlines.clear()
	var numbers := _number_layers()
	var layers := numbers.duplicate()
	layers.append(_card.card_name_frame)
	if is_instance_valid(_card._overframe_outline): layers.append(_card._overframe_outline)
	for slot: Node in _card.rune_row.get_children():
		for icon: TextureRect in slot.get_children():
			layers.append(icon)
	for icon: TextureRect in _card._status_slot_layer.get_children():
		layers.append(icon)
	for layer: Control in layers:
		var material := layer.material as ShaderMaterial
		# 符文刮层使用自己的遮罩材质，避免照亮或露出未揭示的符文。
		if layer.material != null and (material == null or material.shader != FRAME_FOIL_SHADER): continue
		if material == null:
			material = ShaderMaterial.new()
			material.shader = FRAME_FOIL_SHADER
			layer.material = material
			if layer in numbers:
				material.set_shader_parameter("outline_gain", NUMBER_OUTLINE_GAIN)
				material.set_shader_parameter("outline_silhouette", 0.0)
		_detail_outlines[layer] = material
		_configure_outline(material)
		_sync_outline_origin(layer)


func _configure_outline(material: ShaderMaterial) -> void:
	settings_source.apply_flash(material)
	material.set_shader_parameter("outline_highlight_enabled", true)
	material.set_shader_parameter("card_size", _card.card_size)
	material.set_shader_parameter("foil_padding", InspectionCardSurface.PADDING)
	_apply_pointer(material, _art_material.get_shader_parameter("pointer_force"))


func _get_card_local_origin(layer: Control) -> Vector2:
	return _card.get_global_transform().affine_inverse() * layer.get_global_transform().origin


func _sync_outline_origin(layer: Control) -> void:
	var material: ShaderMaterial = _detail_outlines.get(layer)
	if material != null: material.set_shader_parameter("layer_origin", _get_card_local_origin(layer))


func _sync_rune_outline_origins() -> void:
	if not _embossed_outline: return
	for slot: Node in _card.rune_row.get_children():
		for icon: TextureRect in slot.get_children():
			_sync_outline_origin(icon)


func _refresh_rest_flash(face: int, parameters: Vector3) -> void:
	var visible := not _surface_composited and _card.card_data != null and face == Appearance.Surface.FRACTURED
	if not visible:
		if is_instance_valid(_rest_flash): _rest_flash.visible = false
		return
	if not is_instance_valid(_rest_flash):
		_rest_flash = TextureRect.new()
		_rest_flash.name = "RestFlash"
		_rest_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rest_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rest_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_rest_flash.z_index = 80 # 亮纹覆盖完整卡面，保留新卡绿点在上层
		var light := ShaderMaterial.new()
		light.shader = REST_FLASH_SHADER
		_rest_flash.material = light
		_card.add_child(_rest_flash)
	var padding := InspectionCardSurface.PADDING
	_rest_flash.position = -padding
	_rest_flash.size = _card.card_size + padding * 2.0
	_rest_flash.texture = _get_rest_flash_mask(padding)
	var material := _rest_flash.material as ShaderMaterial
	settings_source.apply_flash(material, settings_source.fractured_brightness)
	settings_source.apply_fractured_color(material)
	material.set_shader_parameter("flash_type", face - Appearance.Surface.SILVER)
	material.set_shader_parameter("use_fractured", face == Appearance.Surface.FRACTURED)
	material.set_shader_parameter("finish_strength", parameters.x)
	material.set_shader_parameter("finish_density", parameters.z)
	material.set_shader_parameter("mask_origin_px", padding)
	material.set_shader_parameter("mask_size_px", _card.card_size)
	material.set_shader_parameter("texture_size_px", _rest_flash.size)
	_rest_flash.visible = true


func _get_rest_flash_mask(padding: Vector2) -> Texture2D:
	# 遮罩只由卡框轮廓和外伸图标决定，可跨同布局卡牌共享；不捕获整卡、不新增Viewport。
	var key: Array = [_card.card_frame.texture, _card.card_size]
	var badges: Array[Dictionary] = []
	for badge: TextureRect in _badge_materials:
		if not badge.visible or badge.texture == null: continue
		var material := _badge_materials[badge]
		var texture := material.get_shader_parameter("badge_texture") as Texture2D
		var origin: Vector2 = _card.get_global_transform().affine_inverse() * badge.get_global_transform() * Vector2(material.get_shader_parameter("draw_origin"))
		var draw_size: Vector2 = material.get_shader_parameter("draw_size")
		key.append_array([texture, origin, draw_size])
		badges.append({"texture": texture, "origin": origin, "size": draw_size})
	if _rest_flash_mask_cache.has(key): return _rest_flash_mask_cache[key]
	var mask := Image.create(int(_rest_flash.size.x), int(_rest_flash.size.y), false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	var frame := _card.card_frame.texture.get_image()
	# 每行填满卡框左右边之间的窗口；圆角外的透明像素仍保留。
	for y: int in frame.get_height():
		var left := -1
		var right := -1
		for x: int in frame.get_width():
			if frame.get_pixel(x, y).a > 0.0:
				if left < 0: left = x
				right = x
		if left >= 0: mask.fill_rect(Rect2i(Vector2i(padding + _card.card_frame.position) + Vector2i(left, y), Vector2i(right - left + 1, 1)), Color.WHITE)
	for badge: Dictionary in badges:
		var icon: Image = badge.texture.get_image()
		icon.convert(Image.FORMAT_RGBA8)
		icon.resize(int(badge.size.x), int(badge.size.y), Image.INTERPOLATE_NEAREST)
		mask.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i((padding + badge.origin).round()))
	var texture := ImageTexture.create_from_image(mask)
	_rest_flash_mask_cache[key] = texture
	return texture


func _fill_background_transparency(texture: Texture2D) -> Texture2D:
	if _background_cache.has(texture): return _background_cache[texture]
	# 只处理全息显示副本；透明圆角沿用最近的不透明颜色，避免边缘延展把空角拉成黑块。
	var image := texture.get_image()
	if image == null or image.is_empty(): return texture
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var frontier: Array[Vector2i] = []
	for y: int in height:
		for x: int in width:
			if image.get_pixel(x, y).a >= 0.99:
				visited[y * width + x] = 1
				frontier.append(Vector2i(x, y))
	if frontier.is_empty() or frontier.size() == width * height: return texture
	var neighbors: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var cursor := 0
	# 多源队列由不透明边界向外逐层扩散，每个像素最多处理一次，不在鼠标移动时重做。
	while cursor < frontier.size():
		var pixel := frontier[cursor]
		cursor += 1
		var color := image.get_pixelv(pixel)
		for direction: Vector2i in neighbors:
			var adjacent := pixel + direction
			if adjacent.x < 0 or adjacent.x >= width or adjacent.y < 0 or adjacent.y >= height: continue
			var index := adjacent.y * width + adjacent.x
			if visited[index] != 0: continue
			image.set_pixelv(adjacent, color)
			visited[index] = 1
			frontier.append(adjacent)
	var filled := ImageTexture.create_from_image(image)
	_background_cache[texture] = filled
	return filled


func _refresh_badges() -> void:
	for badge: TextureRect in _badge_materials:
		var material := _badge_materials[badge]
		material.set_shader_parameter("relief_enabled", enabled and (surface_finish in [Appearance.Surface.EMBOSSED, Appearance.Surface.FRACTURED] or art_finish == Appearance.Art.HOLOGRAPHIC))
		if _embossed_outline:
			_configure_outline(material)
		else:
			material.set_shader_parameter("outline_highlight_enabled", false)
		refresh_badge_texture(badge)


func refresh_badge_texture(badge: TextureRect) -> void:
	if badge.texture == null: return
	var material := _badge_materials[badge]
	if _embossed_outline:
		material.set_shader_parameter("layer_origin", _get_card_local_origin(badge))
	# 图标/图集小图与补边阴影只生成一次；刷新材质时复用，避免悬停重绑反复读回纹理。
	var key: Variant = badge.texture
	if badge.texture is AtlasTexture:
		key = [badge.texture.atlas, badge.texture.region, badge.texture.margin]
	var assets: Dictionary = _badge_asset_cache.get(key, {})
	if assets.is_empty():
		var image := badge.texture.get_image()
		if image == null or image.is_empty(): return
		image.convert(Image.FORMAT_RGBA8)
		var shadow_mask := Image.create(image.get_width() + 2, image.get_height() + 2, false, Image.FORMAT_RGBA8)
		shadow_mask.fill(Color.TRANSPARENT)
		shadow_mask.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ONE)
		assets = {"badge": ImageTexture.create_from_image(image), "shadow": ImageTexture.create_from_image(shadow_mask), "size": Vector2(image.get_size())}
		_badge_asset_cache[key] = assets
	material.set_shader_parameter("badge_texture", assets.badge)
	material.set_shader_parameter("shadow_texture", assets.shadow)
	material.set_shader_parameter("source_size", assets.size)
	var draw_size := badge.size
	var draw_origin := Vector2.ZERO
	if badge.stretch_mode == TextureRect.STRETCH_KEEP:
		draw_size = badge.texture.get_size()
	elif badge.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		var texture_size := badge.texture.get_size()
		draw_size = texture_size * minf(badge.size.x / texture_size.x, badge.size.y / texture_size.y)
		draw_origin = (badge.size - draw_size) * 0.5
	material.set_shader_parameter("draw_size", draw_size)
	material.set_shader_parameter("draw_origin", draw_origin)


func update_pointer(force: Vector2, reset_direction: bool = false) -> void:
	if reset_direction: _flash_direction_force = Vector2.ZERO
	elif force.length_squared() > FLASH_DIRECTION_DEADZONE * FLASH_DIRECTION_DEADZONE: _flash_direction_force = force
	_surface.set_shader_parameter("flash_direction_force", _flash_direction_force)
	for material: ShaderMaterial in [_art_material, _background_material, _frame_material]:
		_apply_pointer(material, force)
	if is_instance_valid(_rest_flash):
		_apply_pointer(_rest_flash.material, force)
	for material: ShaderMaterial in _badge_materials.values():
		material.set_shader_parameter("pointer_force", force)
		if _embossed_outline: material.set_shader_parameter("flash_direction_force", _flash_direction_force)
	for material: ShaderMaterial in _detail_outlines.values():
		_apply_pointer(material, force)


func _apply_pointer(material: ShaderMaterial, force: Vector2) -> void:
	material.set_shader_parameter("pointer_force", force)
	material.set_shader_parameter("flash_direction_force", _flash_direction_force)


func get_description() -> String:
	if not enabled: return "材质已关闭；当前显示原画。"
	match finish:
		Finish.PLAIN: return "普通卡：保留原画与图标，不添加法线、投影或闪面材质。"
		Finish.HOLOGRAPHIC: return "全息：从前到后为卡框、人物、背景；同角度倾斜，景深控制卡内层次。"
		Finish.EMBOSSED:
			return "法线：使用专用法线贴图。" if _card.card_data != null and _card.card_data.art_normal_texture != null else "法线：当前为轮廓／亮度生成的自动浮雕，可换专用法线贴图。"
		Finish.FRACTURED: return "碎闪：固定晶片反光叠加背景与外框白色闪纹，移动鼠标观察。"
		Finish.FROSTED: return "磨砂闪（实验）：固定细闪膜层随鼠标反光，人物保留原画明暗，背景与外框带白色细闪。"
		Finish.FINGERPRINT: return "指纹闪（实验）：人物统一连续弧纹、背景独立放射交织纹，共用鼠标反光。"
		Finish.OVERFRAME: return "超框：立绘扩至半透明细框，隐藏卡名与随从种族图标。"
		Finish.FOIL: return "闪卡：背景与外框反光，人物参与鼠标柔光；鼠标控制光带方向。"
	return ""
