class_name CelestialIndicator
extends Resource

## 独立指示物实例，不属于卡牌收藏或装备位。战前阵容只引用稳定实例身份。
enum Kind { MOON, STAR, SUN }

@export var instance_id: StringName = &""
@export var kind: Kind = Kind.MOON
@export var star_transfer_count: int = 0 # 同一枚星星本场已传播次数；战前实例保持0，不写回定义

const NAMES := ["月亮", "星星", "太阳"]
const MOON_ARMOR: int = 8 # 月亮提供的初始护甲
const SUN_HEALTH: int = 6 # 太阳提供的最大生命
const SUN_VALUE: int = 3 # 太阳提供的基础行动数值
const STAR_VALUE: int = 1 # 星星提供的基础行动数值
const MOON_RESTORE_SECONDS: float = 3.0 # 行动后重新获得影蔽的固定时间，不因期间再次行动刷新

func is_valid() -> bool:
	return not instance_id.is_empty() and kind in [Kind.MOON, Kind.STAR, Kind.SUN] and star_transfer_count >= 0

func get_action_value() -> int:
	return STAR_VALUE + star_transfer_count if kind == Kind.STAR else 0

func duplicate_instance() -> CelestialIndicator:
	var copy := CelestialIndicator.new()
	copy.instance_id = instance_id
	copy.kind = kind
	copy.star_transfer_count = star_transfer_count
	return copy

func capture_state() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"kind": int(kind),
		"star_transfer_count": star_transfer_count,
	}

static func from_state(value: Dictionary) -> CelestialIndicator:
	var result := CelestialIndicator.new()
	result.instance_id = StringName(str(value.get("instance_id", "")))
	result.kind = int(value.get("kind", -1)) as Kind
	result.star_transfer_count = maxi(int(value.get("star_transfer_count", 0)), 0)
	return result if result.is_valid() else null
