class_name SentryIndicator
extends Resource

## 四种外观属于同一种哨位。创建时抽取，移动和读档不重抽。
@export var instance_id: StringName = &""
@export var visual_variant: int = 0 # 素材左上、右上、左下、右下四种外观索引


func initialize(id: StringName, source_rng: RandomNumberGenerator) -> bool:
	if id.is_empty() or source_rng == null:
		return false
	instance_id = id
	visual_variant = source_rng.randi_range(0, 3)
	return true


func capture_state() -> Dictionary:
	return {"instance_id": String(instance_id), "visual_variant": visual_variant}


static func from_state(snapshot: Dictionary) -> SentryIndicator:
	var id: Variant = snapshot.get("instance_id")
	var variant: Variant = snapshot.get("visual_variant")
	if not id is String or id.is_empty() or not (variant is int or variant is float):
		return null
	if not is_finite(float(variant)) or float(variant) != floor(float(variant)) or int(variant) < 0 or int(variant) > 3:
		return null
	var result := SentryIndicator.new()
	result.instance_id = StringName(id)
	result.visual_variant = int(variant)
	return result
