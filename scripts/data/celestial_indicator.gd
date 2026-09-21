class_name CelestialIndicator
extends Resource

## 独立指示物实例，不属于卡牌收藏或装备位。战前阵容只引用稳定实例身份。
enum Kind { MOON, STAR, SUN }

@export var instance_id: StringName = &""
@export var kind: Kind = Kind.MOON

const NAMES := ["月亮", "星星", "太阳"]
const MOON_ARMOR: int = 8 # 月亮提供的初始护甲
const SUN_HEALTH: int = 6 # 太阳提供的最大生命
const SUN_VALUE: int = 3 # 太阳提供的基础行动数值
const STAR_VALUE: int = 1 # 星星提供的基础行动数值
const MOON_RESTORE_SECONDS: float = 3.0 # 行动后重新获得影蔽的固定时间，不因期间再次行动刷新

func is_valid() -> bool:
	return not instance_id.is_empty() and kind in [Kind.MOON, Kind.STAR, Kind.SUN]

func capture_state() -> Dictionary:
	return {"instance_id": String(instance_id), "kind": int(kind)}

static func from_state(value: Dictionary) -> CelestialIndicator:
	var result := CelestialIndicator.new()
	result.instance_id = StringName(str(value.get("instance_id", "")))
	result.kind = int(value.get("kind", -1)) as Kind
	return result if result.is_valid() else null
