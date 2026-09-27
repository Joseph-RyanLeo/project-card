class_name RuneStickerStyle
extends RefCounted

## 七枚元素贴纸的独立美术目录。
## 图像保持用户素材的原生 27×27 像素；空白间隔不进入单枚贴纸。

const CardDataScript = preload("res://scripts/data/card_data.gd")
const RUNE_COUNT: int = 7
const FRAME_COUNT: int = 14
const FRAME_DURATION_SECONDS: float = 0.1 # GIF 原始每帧100毫秒，闪耀时沿用这个节拍
const SOURCE_CELL_SIZE: int = 30 # 原图每枚图标占用30像素步长，实际图案为27×27

const RUNE_IDS: Array[StringName] = [
	&"暗贴纸",
	&"火贴纸",
	&"水贴纸",
	&"光贴纸",
	&"木贴纸",
	&"万能贴纸",
	&"混沌贴纸",
]

const RUNE_NAMES: Array[String] = [
	"暗贴纸",
	"火贴纸",
	"水贴纸",
	"光贴纸",
	"木贴纸",
	"万能贴纸",
	"混沌贴纸",
]

# 前五枚对应 CardData 的五种普通元素；后两枚是特殊元素贴纸。
const RUNE_ELEMENTS: Array[int] = [
	CardDataScript.ElementType.DARK,
	CardDataScript.ElementType.FIRE,
	CardDataScript.ElementType.WATER,
	CardDataScript.ElementType.LIGHT,
	CardDataScript.ElementType.WOOD,
	-2, # 万能：可按规则替代普通元素
	-1, # 混沌：不直接等同于某一种普通元素
]

const RUNE_TEXTURE_ROOT: String = "res://assets/card_ui/stickers/runes/"
const RUNE_FRAME_ROOT: String = "res://assets/card_ui/stickers/runes/frames/"
const SCRAPER_TEXTURE: Texture2D = preload("res://assets/card_ui/stickers/scraper.png")

# 刮刀素材画布保持原生59×59；只有左上方刀头区域参与命中，不把刀柄误算为贴纸目标。
const SCRAPER_HIT_POINT: Vector2 = Vector2(16, 17)
const SCRAPER_HIT_RECT: Rect2 = Rect2(14, 15, 16, 16)

static var _textures: Dictionary = {}
static var _animations: Dictionary = {}


static func get_texture(element: int) -> Texture2D:
	if element < 0 or element >= RUNE_COUNT:
		return null
	if not _textures.has(element):
		_textures[element] = load(RUNE_TEXTURE_ROOT + "rune_%d.png" % element) as Texture2D
	return _textures[element] as Texture2D


static func get_texture_by_id(rune_id: StringName) -> Texture2D:
	return get_texture(RUNE_IDS.find(rune_id))


static func get_animation(element: int) -> Array[Dictionary]:
	if element < 0 or element >= RUNE_COUNT:
		return []
	if _animations.has(element):
		return (_animations[element] as Array).duplicate()
	var frames: Array[Dictionary] = []
	for frame_index: int in FRAME_COUNT:
		var frame_path := RUNE_FRAME_ROOT + "rune_%d_%02d_%dms.png" % [element, frame_index, int(FRAME_DURATION_SECONDS * 1000.0)]
		var texture := load(frame_path) as Texture2D
		if texture == null:
			continue
		frames.append({"texture": texture, "duration": FRAME_DURATION_SECONDS})
	_animations[element] = frames
	return frames.duplicate()


static func get_frame_by_id(rune_id: StringName, normalized_progress: float) -> Texture2D:
	var element := RUNE_IDS.find(rune_id)
	if element < 0:
		return null
	var frames := get_animation(element)
	if frames.is_empty():
		return get_texture(element)
	var frame_index := mini(int(floor(fposmod(normalized_progress, 1.0) * frames.size())), frames.size() - 1)
	return frames[frame_index].get("texture") as Texture2D


static func get_emblem_id(element: int) -> StringName:
	if element < 0 or element >= RUNE_COUNT:
		return &""
	return RUNE_IDS[element]


static func get_display_id_for_element(element_type: CardDataScript.ElementType) -> StringName:
	match element_type:
		CardDataScript.ElementType.FIRE:
			return &"火贴纸"
		CardDataScript.ElementType.WATER:
			return &"水贴纸"
		CardDataScript.ElementType.WOOD:
			return &"木贴纸"
		CardDataScript.ElementType.LIGHT:
			return &"光贴纸"
		CardDataScript.ElementType.DARK:
			return &"暗贴纸"
	return &""


static func get_display_name(element: int) -> String:
	if element < 0 or element >= RUNE_COUNT:
		return "未知贴纸"
	return RUNE_NAMES[element]


static func get_element_type(element: int) -> int:
	if element < 0 or element >= RUNE_COUNT:
		return -1
	return RUNE_ELEMENTS[element]


static func is_special(element: int) -> bool:
	return element == 5 or element == 6


static func get_scraper_texture() -> Texture2D:
	return SCRAPER_TEXTURE


static func get_scraper_hit_point() -> Vector2:
	return SCRAPER_HIT_POINT


static func get_scraper_hit_rect() -> Rect2:
	return SCRAPER_HIT_RECT
