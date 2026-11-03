@tool
extends Resource

## 全局工艺风格参数；不属于卡牌属性或玩家存档。调整器保存后供真实卡面共用。
const PATH := "res://resources/ui/card_finish_settings.tres"
const KEYS: Array[StringName] = [&"holographic", &"embossed", &"fractured"]
@export_range(0.0, 1.5, 0.05) var holographic_strength := 0.75 # 全息虹彩与压纹的反光强度
@export_range(0.0, 5.0, 0.25) var holographic_depth := 2.5 # 全息人物和背景的前后层距
@export_range(5.0, 90.0, 1.0) var holographic_density := 32.0 # 全息压纹密度
@export_range(0.0, 1.5, 0.05) var embossed_strength := 0.75 # 法线浮雕的反光强度
@export_range(5.0, 90.0, 1.0) var embossed_density := 32.0 # 法线浮雕细纹密度
@export_range(0.0, 1.5, 0.05) var fractured_strength := 0.75 # 碎闪晶片的反光强度
@export_range(5.0, 90.0, 1.0) var fractured_density := 15.0 # 碎闪晶片密度；15显示更大块镜碎

func parameters(key: StringName) -> Vector3:
	match key:
		&"holographic": return Vector3(holographic_strength, holographic_depth, holographic_density)
		&"embossed": return Vector3(embossed_strength, 2.5, embossed_density)
		&"fractured": return Vector3(fractured_strength, 2.5, fractured_density)
	return Vector3(0.75, 2.5, 32.0)

func set_parameters(key: StringName, value: Vector3) -> void:
	if not value.is_finite(): return
	var strength := clampf(snappedf(value.x, 0.05), 0.0, 1.5)
	var depth := clampf(snappedf(value.y, 0.25), 0.0, 5.0)
	var density := clampf(roundf(value.z), 5.0, 90.0)
	match key:
		&"holographic":
			holographic_strength = strength
			holographic_depth = depth
			holographic_density = density
		&"embossed":
			embossed_strength = strength
			embossed_density = density
		&"fractured":
			fractured_strength = strength
			fractured_density = density
