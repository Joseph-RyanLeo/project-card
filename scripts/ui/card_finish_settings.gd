@tool
extends Resource

## 全局工艺风格参数；不属于卡牌属性或玩家存档。调整器保存后供真实卡面共用。
const PATH := "res://resources/ui/card_finish_settings.tres"
const KEYS: Array[StringName] = [&"holographic", &"embossed", &"fractured"]
const FLASH_FIELDS: Array[String] = ["stripe_spacing", "stripe_width", "flash_intensity", "flash_angle_degrees", "flash_offset"]
const FIELDS: Array[Dictionary] = [
	{"key": "stripe_spacing", "group": "闪纹", "label": "闪纹数量／密度", "min": 1.0, "max": 50.0, "step": 0.5, "help": "越大闪纹越密；银闪、金闪、彩闪共同使用。"},
	{"key": "flash_offset", "group": "闪纹", "label": "闪纹位置", "min": -1.0, "max": 1.0, "step": 0.01, "help": "平移整组闪纹；1为一个重复周期。"},
	{"key": "stripe_width", "group": "闪纹", "label": "闪纹锐度", "min": 1.0, "max": 20.0, "step": 0.5, "help": "越大光带越窄，越小越宽。"},
	{"key": "flash_intensity", "group": "闪纹", "label": "闪纹亮度", "min": 0.0, "max": 2.0, "step": 0.01},
	{"key": "flash_angle_degrees", "group": "闪纹", "label": "默认反光方向", "min": 0.0, "max": 360.0, "step": 1.0, "help": "未指向卡牌时的默认方向；指向后仍随鼠标转动。"},
	{"key": "foil_shade_strength", "group": "闪纹", "label": "随鼠标明暗强度", "min": 0.0, "max": 1.0, "step": 0.05, "help": "所有特殊卡面／卡图共用：居中较暗、边缘较亮，鼠标附近局部更亮。"},
	{"key": "holographic_strength", "group": "全息", "label": "反光强度", "min": 0.0, "max": 1.5, "step": 0.05},
	{"key": "holographic_depth", "group": "全息", "label": "前后景深", "min": 0.0, "max": 5.0, "step": 0.25},
	{"key": "holographic_density", "group": "全息", "label": "纹理密度", "min": 5.0, "max": 90.0, "step": 1.0},
	{"key": "embossed_strength", "group": "法线", "label": "反光强度", "min": 0.0, "max": 1.5, "step": 0.05},
	{"key": "embossed_density", "group": "法线", "label": "细纹密度", "min": 5.0, "max": 90.0, "step": 1.0},
	{"key": "fractured_strength", "group": "碎闪", "label": "反光强度", "min": 0.0, "max": 1.5, "step": 0.05},
	{"key": "fractured_brightness", "group": "碎闪", "label": "明度", "min": 0.0, "max": 1.0, "step": 0.01, "help": "同时调节碎片高光和背景、卡框的白色闪纹，1为原亮度。"},
	{"key": "fractured_saturation", "group": "碎闪", "label": "饱和度", "min": 0.0, "max": 1.0, "step": 0.01, "help": "越高，晶片反光混入的白色越少，颜色越浓。"},
	{"key": "fractured_hue_degrees", "group": "碎闪", "label": "色相（°）", "min": -180.0, "max": 180.0, "step": 1.0, "help": "沿色环旋转所有晶片的颜色。左右拖动可比较粉色偏红或偏紫的效果。"},
	{"key": "fractured_density", "group": "碎闪", "label": "晶片密度", "min": 5.0, "max": 90.0, "step": 1.0, "help": "越大晶片越细，越小显示更大块的镜碎。"},
	{"key": "frosted_strength", "group": "磨砂闪", "label": "膜层反光强度", "min": 0.0, "max": 1.5, "step": 0.05, "help": "新工艺的珠光膜反射，独立于停用的旧磨砂。"},
	{"key": "frosted_density", "group": "磨砂闪", "label": "细闪颗粒密度", "min": 40.0, "max": 240.0, "step": 2, "help": "越大颗粒越细；颗粒固定在卡面，不随时间跳动。"},
	{"key": "frosted_detail", "group": "磨砂闪", "label": "细闪颗粒强度", "min": 0.0, "max": 1.0, "step": 0.05, "help": "控制磨砂颗粒的整体反光强度，不改变形状和密度。"},
	{"key": "frosted_shadow_visibility", "group": "磨砂闪", "label": "暗处颗粒可见度", "min": 0.0, "max": 1.0, "step": 0.05, "help": "0＝暗处不显示颗粒，1＝暗处和亮处同样明显。只影响颗粒，不调暗卡图或光带。"},
	{"key": "fingerprint_strength", "group": "指纹闪", "label": "刻纹反光强度", "min": 0.0, "max": 1.5, "step": 0.05, "help": ""},
	{"key": "fingerprint_density", "group": "指纹闪", "label": "曲纹密度", "min": 20.0, "max": 180.0, "step": 2, "help": "越大曲纹越细密。"},
	{"key": "fingerprint_detail", "group": "指纹闪", "label": "曲纹弯曲程度", "min": 0.0, "max": 2.0, "step": 0.05, "help": "人物统一使用连续弧纹，背景使用独立的放射交织纹。"},
	{"key": "fingerprint_angle", "group": "指纹闪", "label": "刻纹整体方向", "min": -180.0, "max": 180.0, "step": 1, "help": "旋转固定刻纹，不改变鼠标检视方向。"},
	{"key": "fingerprint_iridescence", "group": "指纹闪", "label": "虹彩比例", "min": 0.0, "max": 1.0, "step": 0.05, "help": ""},
]
@export_range(1.0, 50.0, 0.5) var stripe_spacing := 14.0 # 全卡牌闪纹密度；越大光带越多
@export_range(-1.0, 1.0, 0.01) var flash_offset := 0.0 # 全卡牌闪纹平移相位；1为一个重复周期
@export_range(1.0, 20.0, 0.5) var stripe_width := 10.0 # 全卡牌光带锐度；越大越窄
@export_range(0.0, 2.0, 0.01) var flash_intensity := 0.2 # 全卡牌光带亮度
@export_range(0.0, 360.0, 1.0) var flash_angle_degrees := 50.0 # 静置默认光带方向
@export_range(0.0, 1.0, 0.05) var foil_matte_strength := 0.6 # 暂存旧磨砂强度；当前停用，不参与渲染
@export_range(0.25, 6.0, 0.25) var foil_matte_grain_size := 0.75 # 暂存旧颗粒大小；当前停用，不参与渲染
@export_range(0.0, 1.0, 0.05) var foil_matte_density := 0.75 # 暂存旧颗粒密度；当前停用，不参与渲染
@export_range(0.0, 1.0, 0.05) var foil_shade_strength := 0.45 # 所有特殊卡面与卡图共用的鼠标柔光幅度
@export_range(0.0, 1.5, 0.05) var holographic_strength := 0.75 # 全息虹彩与压纹的反光强度
@export_range(0.0, 5.0, 0.25) var holographic_depth := 2.5 # 全息人物和背景的前后层距
@export_range(5.0, 90.0, 1.0) var holographic_density := 32.0 # 全息压纹密度
@export_range(0.0, 1.5, 0.05) var embossed_strength := 0.75 # 法线浮雕的反光强度
@export_range(5.0, 90.0, 1.0) var embossed_density := 32.0 # 法线浮雕细纹密度
@export_range(0.0, 1.5, 0.05) var fractured_strength := 0.75 # 碎闪晶片的反光强度
@export_range(0.0, 1.0, 0.01) var fractured_brightness := 0.55 # 碎闪晶片高光与白色闪纹的明度倍率
@export_range(0.0, 1.0, 0.01) var fractured_saturation := 0.55 # 碎闪晶片彩色反光相对白光的比例
@export_range(-180.0, 180.0, 1.0) var fractured_hue_degrees := 0.0 # 碎闪晶片整体色相旋转角度
@export_range(5.0, 90.0, 1.0) var fractured_density := 15.0 # 碎闪晶片密度；15显示更大块镜碎

@export_range(0.0, 1.5, 0.05) var frosted_strength := 0.8 # 磨砂闪：膜层反光强度
@export_range(40.0, 240.0, 2) var frosted_density := 140.0 # 磨砂闪：细闪颗粒密度
@export_range(0.0, 1.0, 0.05) var frosted_detail := 0.65 # 磨砂闪：细闪颗粒的整体强度
@export_range(0.0, 1.0, 0.05) var frosted_shadow_visibility := 0.20 # 磨砂闪：未受光处保留的颗粒强度比例
@export_range(0.0, 1.5, 0.05) var fingerprint_strength := 0.85 # 指纹闪：刻纹反光强度
@export_range(20.0, 180.0, 2) var fingerprint_density := 100.0 # 指纹闪：曲纹密度
@export_range(0.0, 2.0, 0.05) var fingerprint_detail := 0.85 # 指纹闪：曲纹弯曲程度
@export_range(-180.0, 180.0, 1) var fingerprint_angle := 0.0 # 指纹闪：刻纹整体方向
@export_range(0.0, 1.0, 0.05) var fingerprint_iridescence := 0.85 # 指纹闪：虹彩比例


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


func apply_flash(material: ShaderMaterial, brightness: float = 1.0) -> void:
	for key: String in FLASH_FIELDS:
		material.set_shader_parameter(key, flash_intensity * brightness if key == "flash_intensity" else get(key))


func apply_fractured_color(material: ShaderMaterial) -> void:
	material.set_shader_parameter("fractured_brightness", fractured_brightness)
	material.set_shader_parameter("fractured_saturation", fractured_saturation)
	material.set_shader_parameter("fractured_hue_degrees", fractured_hue_degrees)


func copy_values(source: Resource) -> void:
	for field: Dictionary in FIELDS: set(field.key, source.get(field.key))


func set_value(key: String, value: float) -> void:
	if not is_finite(value): return
	for field: Dictionary in FIELDS:
		if field.key == key:
			set(key, clampf(snappedf(value, float(field.step)), float(field.min), float(field.max)))
			return


func apply_film(material: ShaderMaterial, key: StringName) -> void:
	var kind := 1 if key == &"frosted" else (2 if key == &"fingerprint" else 0)
	material.set_shader_parameter("film_kind", kind)
	if kind == 0: return
	for suffix: String in ["strength", "density", "detail"]:
		material.set_shader_parameter("film_" + suffix, get(String(key) + "_" + suffix))
	material.set_shader_parameter("film_angle", fingerprint_angle if kind == 2 else 0.0)
	if kind == 1: material.set_shader_parameter("frosted_shadow_visibility", frosted_shadow_visibility)
	if kind == 2: material.set_shader_parameter("film_iridescence", fingerprint_iridescence)
