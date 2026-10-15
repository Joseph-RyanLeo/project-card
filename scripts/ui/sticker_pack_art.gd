extends Control

## 底板、整张贴纸、下封皮、上封皮在原生画布内合成；外层负责整体倾斜。
const FOIL_SHADER = preload("res://shaders/sticker_pack_foil.gdshader")
const BASE = preload("res://assets/card_ui/shop/sticker_pack_base.png")
const LOWER = preload("res://assets/card_ui/shop/sticker_pack_lower.png")
const UPPER = preload("res://assets/card_ui/shop/sticker_pack_seal.png")
const SHEETS = [
	preload("res://assets/card_ui/shop/sticker_sheet_anchor.png"),
	preload("res://assets/card_ui/shop/sticker_sheet_deer.png"),
	preload("res://assets/card_ui/shop/sticker_sheet_crown.png"),
	preload("res://assets/card_ui/shop/sticker_sheet_moon.png"),
]
const DOT_CENTERS = [
	[Vector2(47, 18), Vector2(47, 52), Vector2(17, 62), Vector2(77, 62), Vector2(47, 90)],
	[Vector2(19, 24), Vector2(75, 24), Vector2(32, 56), Vector2(62, 56), Vector2(47, 88)],
	[Vector2(47, 25), Vector2(17, 47), Vector2(77, 47), Vector2(33, 77), Vector2(61, 77)],
	[Vector2(46, 20), Vector2(17, 49), Vector2(61, 50), Vector2(31, 82), Vector2(74, 82)],
] # 四种底纸中五个白色圆点的原图像素中心
const UPPER_POSITION := Vector2(4, 1) # 上封皮与底板的对齐位置
const SHEET_POSITION := Vector2(2, 1) # 整张贴纸与底板的对齐位置
const FLIP_PADDING := Vector2(100, 150) # 完整翻起及左右偏转的封皮所需画布边距
const INSPECTION_RENDER_SCALE := 4.0 # 翻折斜边与金边高光按4倍显示精度绘制，素材仍按原图取色
const STICKER_ROTATION_LIMIT := 45.0 # 整张贴纸上每枚图案绕自身中心随机旋转的最大角度
const StatusStyle = preload("res://scripts/ui/status_indicator_style.gd")
const RuneStyle = preload("res://scripts/ui/rune_sticker_style.gd")
const SlotLayout = preload("res://scripts/data/card_slot_layout.gd")

var upper: TextureRect
var lower: TextureRect
var sheet: Control
var surface: InspectionCardSurface


func _init() -> void:
	name = "SealedStickerPack"
	size = BASE.get_size()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := _image(BASE)
	base.name = "PackBase"
	add_child(base)
	lower = _image(LOWER)
	lower.name = "PackLowerSeal"
	add_child(lower)
	upper = _image(UPPER)
	upper.name = "PackSeal"
	upper.position = UPPER_POSITION
	add_child(upper)
	for layer: TextureRect in [lower, upper]:
		var effect := ShaderMaterial.new()
		effect.shader = FOIL_SHADER
		effect.set_shader_parameter("use_foil", false)
		effect.set_shader_parameter("draw_padding", Vector2.ZERO)
		layer.material = effect
	set_process(false)


func configure_inspection(value: InspectionCardSurface) -> void:
	surface = value
	# 反光在两张封皮内部完成，关闭外层整面扫光，仍复用其透视倾斜。
	surface.effect.set_shader_parameter("use_flash", false)
	for layer: TextureRect in [lower, upper]:
		(layer.material as ShaderMaterial).set_shader_parameter("use_foil", true)
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(surface): return
	for layer: TextureRect in [lower, upper]:
		(layer.material as ShaderMaterial).set_shader_parameter("pointer_force", surface.force)


func set_peel_progress(value: float) -> void:
	(upper.material as ShaderMaterial).set_shader_parameter("peel_progress", value)


func configure_flip() -> void:
	(upper.material as ShaderMaterial).set_shader_parameter("draw_padding", FLIP_PADDING)


func set_peel_angle(value: float) -> void:
	(upper.material as ShaderMaterial).set_shader_parameter("peel_angle_degrees", value)


func create_sheet(stickers: Array, style_index: int) -> Control:
	var result := Control.new()
	result.name = "StickerSheet"
	result.size = SHEETS[style_index].get_size()
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.add_child(_image(SHEETS[style_index]))
	var cosmetic_rng := RandomNumberGenerator.new()
	cosmetic_rng.seed = hash(var_to_str(stickers) + str(style_index))
	for index: int in stickers.size():
		var sticker: Dictionary = stickers[index]
		var id := StringName(String(sticker.get("id", "")))
		var icon_texture: Texture2D = RuneStyle.get_texture_by_id(id) if sticker.get("target", "emblem") == "rune" else StatusStyle.get_texture(SlotLayout.Kind.EMBLEM, id)
		var icon := _image(icon_texture)
		icon.name = "Sticker_%d" % index
		icon.pivot_offset = icon.size * 0.5
		icon.position = (DOT_CENTERS[style_index][index] - icon.size * 0.5).round()
		icon.rotation_degrees = cosmetic_rng.randf_range(-STICKER_ROTATION_LIMIT, STICKER_ROTATION_LIMIT)
		icon.tooltip_text = id
		result.add_child(icon)
	return result


func show_contents(stickers: Array, style_index: int) -> void:
	sheet = create_sheet(stickers, style_index)
	sheet.position = SHEET_POSITION
	add_child(sheet)
	move_child(sheet, 1)


static func _image(image_texture: Texture2D) -> TextureRect:
	var result := TextureRect.new()
	result.texture = image_texture
	result.size = image_texture.get_size() if image_texture != null else Vector2.ZERO
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return result
