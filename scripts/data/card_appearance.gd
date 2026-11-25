class_name CardAppearance
extends RefCounted

## 卡面按已抽出的品级选权重，卡图独立抽取。外观不参与品级或战斗数值的结算。
enum Surface { PLAIN, SILVER, GOLD, RAINBOW, EMBOSSED, FRACTURED, FROSTED, FINGERPRINT }
enum Art { PLAIN, HOLOGRAPHIC, OVERFRAME }
# 以下每行依次为普通、银闪、金闪、彩闪、法线闪、碎闪、磨砂闪、指纹闪。
const SURFACE_WEIGHTS_I: Array[int] = [75, 10, 5, 4, 2, 2, 2, 0] # Ⅰ级卡面概率（%）
const SURFACE_WEIGHTS_II: Array[int] = [62, 15, 8, 6, 3, 3, 3, 0] # Ⅱ级卡面概率（%）
const SURFACE_WEIGHTS_III: Array[int] = [50, 20, 10, 8, 4, 4, 4, 0] # Ⅲ级卡面概率（%）
const SURFACE_WEIGHTS_IV_V: Array[int] = [40, 20, 15, 10, 5, 5, 5, 0] # Ⅳ／Ⅴ级共用卡面概率（%）
const ART_WEIGHTS: Array[int] = [90, 5, 5] # 普通、全息、超框的百分比
const SURFACE_KEYS := ["plain", "silver", "gold", "rainbow", "embossed", "fractured", "frosted", "fingerprint"]
const ART_KEYS := ["plain", "holographic", "overframe"]
const SURFACE_LABELS := ["普通", "银闪", "金闪", "彩闪", "法线闪", "碎闪", "磨砂闪", "指纹闪"]
const ART_LABELS := ["普通", "全息", "超框"]


static func get_surface_weights(rarity: CardData.Rarity) -> Array[int]:
	match rarity:
		CardData.Rarity.I: return SURFACE_WEIGHTS_I
		CardData.Rarity.II: return SURFACE_WEIGHTS_II
		CardData.Rarity.III: return SURFACE_WEIGHTS_III
		_: return SURFACE_WEIGHTS_IV_V


static func pick_ticket(weights: Array[int], ticket: int) -> int:
	if ticket < 1: return -1
	for index: int in weights.size():
		ticket -= weights[index]
		if ticket <= 0: return index
	return -1


static func offset_key(surface: int, art: int) -> StringName:
	if art != Art.PLAIN: return StringName(ART_KEYS[art])
	if surface in [Surface.SILVER, Surface.GOLD, Surface.RAINBOW]: return &"foil"
	return StringName(SURFACE_KEYS[surface])


static func is_valid(surface: Variant, art: Variant) -> bool:
	return (surface is int or surface is float) and (art is int or art is float) \
		and is_finite(float(surface)) and is_finite(float(art)) \
		and float(surface) == floor(float(surface)) and float(art) == floor(float(art)) \
		and surface >= 0 and surface < SURFACE_KEYS.size() and art >= 0 and art < ART_KEYS.size()
