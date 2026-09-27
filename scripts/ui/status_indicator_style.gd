class_name StatusIndicatorStyle
extends RefCounted

## 纹章与伤势使用用户提供的 14×14 原生像素贴纸，不重绘、不放大。

const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")

const DISPLAY_SIZE := Vector2(14, 14) # 实际纹章与伤势贴纸保持用户素材的14×14逻辑尺寸
const EMBLEM_DIR := "res://assets/card_ui/status/emblems/"
const WOUND_DIR := "res://assets/card_ui/status/wounds/"

const ALIASES := {
	&"torch": "火把", &"long_sword": "长剑", &"bread": "面包", &"modify": "改造",
	&"light_sticker": "光贴纸", &"dark_sticker": "暗贴纸", &"water_sticker": "水贴纸",
	&"fire_sticker": "火贴纸", &"wood_sticker": "木贴纸", &"chaos_sticker": "混沌贴纸",
	&"wildcard_sticker": "万能贴纸", &"poison_1": "中毒Ⅰ", &"poison_2": "中毒Ⅱ",
	&"天选之子": "天选之人",
	&"poison_3": "中毒Ⅲ", &"concussion": "脑震荡", &"blind_1": "致盲Ⅰ",
	&"blind_2": "致盲Ⅱ", &"fracture_1": "骨折Ⅰ", &"fracture_2": "骨折Ⅱ",
	&"light_blood": "光血", &"internal_1": "内伤Ⅰ", &"internal_2": "内伤Ⅱ",
	&"internal_3": "内伤Ⅲ", &"tear_1": "撕裂Ⅰ", &"tear_2": "撕裂Ⅱ",
	&"tear_3": "撕裂Ⅲ", &"frozen": "冻僵", &"feather_1": "羽毛Ⅰ",
	&"feather_2": "羽毛Ⅱ", &"crystallization": "晶体化", &"dark_erosion": "暗蚀",
	&"confusion": "混乱", &"burn_1": "烧伤Ⅰ", &"burn_2": "烧伤Ⅱ",
	&"brain_death": "脑死亡", &"poisoned": "尸毒Ⅰ", &"greed": "贪婪",
	&"fracture": "骨折Ⅰ", &"magic_mark_1": "魔痕Ⅰ", &"magic_mark_2": "魔痕Ⅱ",
	&"magic_mark_3": "魔痕Ⅲ",
}

static var _texture_cache: Dictionary = {}


static func get_texture(kind: int, status_id: StringName) -> Texture2D:
	if status_id.is_empty():
		return null
	var category := "emblem" if kind == CardSlotLayout.Kind.EMBLEM else "wound"
	var cache_key := "%s:%s" % [category, String(status_id)]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var filename := String(ALIASES.get(status_id, String(status_id)))
	var path := (
		EMBLEM_DIR if category == "emblem" else WOUND_DIR
	) + filename + ".png"
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		_texture_cache[cache_key] = texture
	return texture


static func create_visual(kind: int, status_id: StringName) -> TextureRect:
	var visual := TextureRect.new()
	visual.texture = get_texture(kind, status_id)
	visual.position = Vector2.ZERO
	visual.size = DISPLAY_SIZE
	visual.custom_minimum_size = DISPLAY_SIZE
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.stretch_mode = TextureRect.STRETCH_KEEP
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return visual
