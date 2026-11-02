class_name CardAppearance
extends RefCounted

## 卡面工艺与卡图表现分别抽取，独立于I～V品级和战斗数值。
enum Surface { PLAIN, SILVER, GOLD, RAINBOW, EMBOSSED, FRACTURED }
enum Art { PLAIN, HOLOGRAPHIC, OVERFRAME }
const SURFACE_WEIGHTS: Array[int] = [40, 25, 15, 10, 5, 5] # 普通、银闪、金闪、彩闪、法线闪、碎闪的百分比
const ART_WEIGHTS: Array[int] = [90, 5, 5] # 普通、全息、超框的百分比
const SURFACE_KEYS := ["plain", "silver", "gold", "rainbow", "embossed", "fractured"]
const ART_KEYS := ["plain", "holographic", "overframe"]
const SURFACE_LABELS := ["普通", "银闪", "金闪", "彩闪", "法线闪", "碎闪"]
const ART_LABELS := ["普通", "全息", "超框"]


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
