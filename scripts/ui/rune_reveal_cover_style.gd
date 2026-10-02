class_name RuneRevealCoverStyle
extends RefCounted

const SIZE: int = 23 # 用户提供的每个品级符文覆盖素材边长
const SCRAPE_COMPLETE_RATIO: float = 0.70 # 擦除素材实际不透明覆盖像素达到该比例后揭晓
const SCRAPE_SAMPLE_SPACING: float = 1.0 # 鼠标路径插值的最大画布像素间距，防止快速移动漏刮
const COVER_SHADER = preload("res://shaders/rune_reveal_cover.gdshader")
const COVER_TEXTURE_PATHS: Array[String] = [
	"res://assets/card_ui/rune_covers/rarity_i.png",
	"res://assets/card_ui/rune_covers/rarity_ii.png",
	"res://assets/card_ui/rune_covers/rarity_iii.png",
	"res://assets/card_ui/rune_covers/rarity_iv.png",
	"res://assets/card_ui/rune_covers/rarity_v.png",
]

static var _cover_textures: Dictionary = {}
static var _opaque_pixel_count: int = -1
static var _cover_alpha_initialized: bool = false
static var _empty_mask_texture: ImageTexture
static var _empty_mask_materials: Dictionary = {}
static var _cover_alpha: PackedByteArray = PackedByteArray()


static func get_cover_texture(rarity: int) -> Texture2D:
	if rarity < 0 or rarity >= COVER_TEXTURE_PATHS.size():
		return null
	if not _cover_textures.has(rarity):
		_cover_textures[rarity] = load(COVER_TEXTURE_PATHS[rarity]) as Texture2D
	return _cover_textures[rarity] as Texture2D


static func get_opaque_pixel_count() -> int:
	_initialize_cover_alpha()
	return _opaque_pixel_count


static func is_cover_pixel(pixel: Vector2i) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= SIZE or pixel.y >= SIZE:
		return false
	_initialize_cover_alpha()
	return not _cover_alpha.is_empty() and _cover_alpha[pixel.y * SIZE + pixel.x] != 0


static func _initialize_cover_alpha() -> void:
	if _cover_alpha_initialized:
		return
	_cover_alpha_initialized = true
	_opaque_pixel_count = 0
	# 导出包保存的是导入纹理；从 ResourceLoader 取得纹理像素，不能读磁盘原始 PNG。
	var texture := get_cover_texture(0)
	var image := texture.get_image() if texture != null else null
	if image != null and image.is_compressed():
		if image.decompress() != OK:
			push_error("符文覆盖纹理无法解压")
			return
	if image == null or image.get_size() != Vector2i(SIZE, SIZE):
		push_error("符文覆盖纹理必须提供23×23像素数据")
		return
	_cover_alpha.resize(SIZE * SIZE)
	for y: int in SIZE:
		for x: int in SIZE:
			var opaque := image.get_pixel(x, y).a > 0.0
			_cover_alpha[y * SIZE + x] = 1 if opaque else 0
			if opaque:
				_opaque_pixel_count += 1


static func is_complete(scraped_pixel_count: int) -> bool:
	var count := get_opaque_pixel_count()
	return count > 0 and float(scraped_pixel_count) / float(count) >= SCRAPE_COMPLETE_RATIO


static func create_mask_image(scraped_bits: PackedByteArray) -> Image:
	_initialize_cover_alpha()
	var pixels := PackedByteArray()
	pixels.resize(SIZE * SIZE)
	# 位图按字节展开；未刮状态全为零，不需要逐像素查询圆形区域。
	for byte_index: int in mini(scraped_bits.size(), ceili(float(SIZE * SIZE) / 8.0)):
		var bits := int(scraped_bits[byte_index])
		if bits == 0:
			continue
		for bit: int in 8:
			var index := byte_index * 8 + bit
			if index < pixels.size() and not _cover_alpha.is_empty() and _cover_alpha[index] != 0 and (bits & (1 << bit)) != 0:
				pixels[index] = 255
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, pixels)


static func get_empty_mask_texture() -> ImageTexture:
	if _empty_mask_texture == null:
		_empty_mask_texture = ImageTexture.create_from_image(create_mask_image(PackedByteArray()))
	return _empty_mask_texture


static func create_mask_texture(scraped_bits: PackedByteArray) -> ImageTexture:
	for byte: int in scraped_bits:
		if byte != 0:
			return ImageTexture.create_from_image(create_mask_image(scraped_bits))
	return get_empty_mask_texture()


static func create_material(mask_texture: Texture2D, reveal_only: bool = false) -> ShaderMaterial:
	var is_empty_mask := mask_texture == get_empty_mask_texture()
	if is_empty_mask and _empty_mask_materials.has(reveal_only):
		return _empty_mask_materials[reveal_only] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = COVER_SHADER
	material.set_shader_parameter("scrape_mask", mask_texture)
	material.set_shader_parameter("reveal_only", reveal_only)
	if is_empty_mask:
		_empty_mask_materials[reveal_only] = material
	return material
