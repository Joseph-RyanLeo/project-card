extends RefCounted

## 开包动画的唯一参数入口；共享字典让正在播放的外观参数立即更新。
const DEFAULT_SAVE_PATH := "user://pack_opening_effects.cfg"
const FIELDS := [
	{"group": "流程", "key": "inspect_seconds", "label": "拿起／购买放大时长", "default": 0.25, "min": 0.05, "max": 2.0, "step": 0.01, "unit": "秒"}, # 拿起／购买放大时长
	{"group": "流程", "key": "return_seconds", "label": "放回商店时长", "default": 0.2, "min": 0.05, "max": 2.0, "step": 0.01, "unit": "秒"}, # 放回商店时长
	{"group": "流程", "key": "pack_position_seconds", "label": "购买后移到撕口时长", "default": 0.3, "min": 0.05, "max": 2.0, "step": 0.01, "unit": "秒"}, # 购买后移到撕口时长
	{"group": "流程", "key": "auto_tear_seconds", "label": "自动撕开时长", "default": 0.35, "min": 0.05, "max": 3.0, "step": 0.01, "unit": "秒"}, # 自动撕开时长
	{"group": "流程", "key": "burst_seconds", "label": "退壳与金光时长", "default": 0.72, "min": 0.05, "max": 4.0, "step": 0.01, "unit": "秒"}, # 退壳与金光时长
	{"group": "流程", "key": "shell_drop", "label": "包装下落距离", "default": 760.0, "min": 0.0, "max": 1800.0, "step": 1.0, "unit": "px"}, # 包装下落距离
	{"group": "流程", "key": "seal_fly_x", "label": "封条飞出横向距离", "default": 35.0, "min": -300.0, "max": 300.0, "step": 1.0, "unit": "px"}, # 封条飞出横向距离
	{"group": "流程", "key": "seal_fly_y", "label": "封条飞出纵向距离", "default": -45.0, "min": -400.0, "max": 200.0, "step": 1.0, "unit": "px"}, # 封条飞出纵向距离
	{"group": "流程", "key": "peel_lift", "label": "撕开封条抬起距离", "default": 15.0, "min": 0.0, "max": 45.0, "step": 0.5, "unit": "原生px"}, # 撕开封条抬起距离
	{"group": "震动", "key": "tear_shake_pixels", "label": "包装颤抖幅度（4×画面）", "default": 1.0, "min": 0.0, "max": 12.0, "step": 0.05, "unit": "px"}, # 包装颤抖幅度（4×画面）
	{"group": "震动", "key": "tear_frequency_x", "label": "包装横向颤抖频率", "default": 73.0, "min": 0.0, "max": 180.0, "step": 1.0, "unit": "rad/s"}, # 包装横向颤抖频率
	{"group": "震动", "key": "tear_frequency_y", "label": "包装纵向颤抖频率", "default": 91.0, "min": 0.0, "max": 180.0, "step": 1.0, "unit": "rad/s"}, # 包装纵向颤抖频率
	{"group": "震动", "key": "shake_pixels", "label": "稀有包画面震动幅度", "default": 3.0, "min": 0.0, "max": 30.0, "step": 0.1, "unit": "px"}, # 稀有包画面震动幅度
	{"group": "震动", "key": "shake_seconds", "label": "画面震动时长", "default": 0.38, "min": 0.05, "max": 2.0, "step": 0.01, "unit": "秒"}, # 画面震动时长
	{"group": "震动", "key": "shake_frequency_x", "label": "画面横向震动频率", "default": 83.0, "min": 0.0, "max": 180.0, "step": 1.0, "unit": "rad/s"}, # 画面横向震动频率
	{"group": "震动", "key": "shake_frequency_y", "label": "画面纵向震动频率", "default": 107.0, "min": 0.0, "max": 180.0, "step": 1.0, "unit": "rad/s"}, # 画面纵向震动频率
	{"group": "金光", "key": "beam_height", "label": "稀有包光束高度", "default": 640.0, "min": 0.0, "max": 1400.0, "step": 1.0, "unit": "px"}, # 稀有包光束高度
	{"group": "金光", "key": "beam_width", "label": "稀有包光束半宽", "default": 180.0, "min": 0.0, "max": 600.0, "step": 1.0, "unit": "px"}, # 稀有包光束半宽
	{"group": "金光", "key": "normal_height_ratio", "label": "普通包光束高度比例", "default": 0.28, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 普通包光束高度比例
	{"group": "金光", "key": "normal_width_ratio", "label": "普通包光束宽度比例", "default": 0.45, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 普通包光束宽度比例
	{"group": "金光", "key": "beam_layers", "label": "光束渐变层数", "default": 4.0, "min": 1.0, "max": 12.0, "step": 1.0, "unit": "层"}, # 光束渐变层数
	{"group": "金光", "key": "beam_taper", "label": "光束底部宽度比例", "default": 0.32, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 光束底部宽度比例
	{"group": "金光", "key": "beam_outer_alpha", "label": "光束外围透明度", "default": 0.2, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 光束外围透明度
	{"group": "金光", "key": "beam_core_alpha", "label": "光束核心透明度", "default": 0.9, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 光束核心透明度
	{"group": "金光", "key": "burst_strength", "label": "撕开瞬间亮度", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 撕开瞬间亮度
	{"group": "金光", "key": "rare_seal_strength", "label": "稀有包撕口亮度", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 稀有包撕口亮度
	{"group": "金光", "key": "normal_seal_strength", "label": "普通包撕口亮度", "default": 0.18, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 普通包撕口亮度
	{"group": "金光", "key": "rare_flare_width", "label": "稀有包横向闪光半宽", "default": 100.0, "min": 0.0, "max": 400.0, "step": 1.0, "unit": "px"}, # 稀有包横向闪光半宽
	{"group": "金光", "key": "normal_flare_width", "label": "普通包横向闪光半宽", "default": 45.0, "min": 0.0, "max": 200.0, "step": 1.0, "unit": "px"}, # 普通包横向闪光半宽
	{"group": "光点", "key": "pixel", "label": "像素光点尺寸／对齐步长", "default": 4.0, "min": 1.0, "max": 16.0, "step": 1.0, "unit": "px"}, # 像素光点尺寸／对齐步长
	{"group": "光点", "key": "particle_count", "label": "上升光点数量", "default": 18.0, "min": 0.0, "max": 100.0, "step": 1.0, "unit": "个"}, # 上升光点数量
	{"group": "光点", "key": "particle_speed", "label": "上升光点速度", "default": 0.65, "min": 0.0, "max": 4.0, "step": 0.01, "unit": "轮/秒"}, # 上升光点速度
	{"group": "光点", "key": "particle_spacing", "label": "光点相位间距", "default": 0.173, "min": 0.0, "max": 1.0, "step": 0.001, "unit": ""}, # 光点相位间距
	{"group": "光点", "key": "particle_spread", "label": "光点横向分布角度", "default": 2.37, "min": 0.0, "max": 6.28, "step": 0.01, "unit": "rad"}, # 光点横向分布角度
	{"group": "IV卡", "key": "rare_reveal_seconds", "label": "IV卡光环持续时长", "default": 0.65, "min": 0.05, "max": 4.0, "step": 0.01, "unit": "秒"}, # IV卡光环持续时长
	{"group": "IV卡", "key": "halo_radius", "label": "光环最终半径", "default": 290.0, "min": 0.0, "max": 650.0, "step": 1.0, "unit": "px"}, # 光环最终半径
	{"group": "IV卡", "key": "halo_start_ratio", "label": "光环初始半径比例", "default": 0.3, "min": 0.0, "max": 1.0, "step": 0.01, "unit": ""}, # 光环初始半径比例
	{"group": "IV卡", "key": "halo_count", "label": "光环点数", "default": 24.0, "min": 0.0, "max": 100.0, "step": 1.0, "unit": "个"}, # 光环点数
	{"group": "IV卡", "key": "halo_point_scale", "label": "光环光点尺寸倍率", "default": 2.0, "min": 0.25, "max": 6.0, "step": 0.05, "unit": ""}, # 光环光点尺寸倍率
	{"group": "收卡", "key": "collect_seconds", "label": "收起卡牌时长", "default": 0.3, "min": 0.05, "max": 2.0, "step": 0.01, "unit": "秒"}, # 收起卡牌时长
	{"group": "收卡", "key": "collect_drop", "label": "收起卡牌下落距离", "default": 520.0, "min": 0.0, "max": 1500.0, "step": 1.0, "unit": "px"}, # 收起卡牌下落距离
	{"group": "收卡", "key": "collect_scale", "label": "收起卡牌最终倍率", "default": 0.4, "min": 0.05, "max": 1.0, "step": 0.01, "unit": ""}, # 收起卡牌最终倍率
	{"group": "收卡", "key": "stack_parallax_x", "label": "卡叠横向错位幅度", "default": 24.0, "min": 0.0, "max": 80.0, "step": 0.5, "unit": "px"}, # 卡叠横向错位幅度
	{"group": "收卡", "key": "stack_parallax_y", "label": "卡叠纵向错位幅度", "default": 15.0, "min": 0.0, "max": 80.0, "step": 0.5, "unit": "px"}, # 卡叠纵向错位幅度
	{"group": "颜色", "key": "gold_r", "label": "金光外围 · 红", "default": 255.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 金光外围 · 红
	{"group": "颜色", "key": "gold_g", "label": "金光外围 · 绿", "default": 189.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 金光外围 · 绿
	{"group": "颜色", "key": "gold_b", "label": "金光外围 · 蓝", "default": 53.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 金光外围 · 蓝
	{"group": "颜色", "key": "core_r", "label": "光束核心 · 红", "default": 255.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 光束核心 · 红
	{"group": "颜色", "key": "core_g", "label": "光束核心 · 绿", "default": 244.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 光束核心 · 绿
	{"group": "颜色", "key": "core_b", "label": "光束核心 · 蓝", "default": 186.0, "min": 0.0, "max": 255.0, "step": 1.0, "unit": ""}, # 光束核心 · 蓝
	{"group": "入场", "key": "arrival_start_x", "label": "起点 X", "default": -20.0, "min": -800.0, "max": 2080.0, "step": 1.0, "unit": "px"}, # 起点中心横坐标
	{"group": "入场", "key": "arrival_start_y", "label": "起点 Y", "default": 250.0, "min": -600.0, "max": 1320.0, "step": 1.0, "unit": "px"}, # 起点中心纵坐标
	{"group": "入场", "key": "arrival_contact_x", "label": "着地点 X", "default": 270.0, "min": 0.0, "max": 1280.0, "step": 1.0, "unit": "px"}, # 首次着地中心横坐标
	{"group": "入场", "key": "arrival_contact_y", "label": "着地点 Y", "default": 305.0, "min": 0.0, "max": 720.0, "step": 1.0, "unit": "px"}, # 首次着地中心纵坐标
	{"group": "入场", "key": "arrival_end_x", "label": "停止位置 X", "default": 640.0, "min": 0.0, "max": 1280.0, "step": 1.0, "unit": "px"}, # 最终停止中心横坐标
	{"group": "入场", "key": "arrival_end_y", "label": "停止位置 Y", "default": 360.0, "min": 0.0, "max": 720.0, "step": 1.0, "unit": "px"}, # 最终停止中心纵坐标
	{"group": "入场", "key": "arrival_fall_speed", "label": "飞入平均速度", "default": 484.0, "min": 50.0, "max": 2400.0, "step": 1.0, "unit": "px/s"}, # 沿飞入弧线的平均速度
	{"group": "入场", "key": "arrival_fall_power", "label": "飞入加速曲线", "default": 3.0, "min": 1.0, "max": 5.0, "step": 0.1, "unit": ""}, # 1为匀速，数值越大越偏向后段加速
	{"group": "入场", "key": "arrival_arc_height", "label": "飞入弧线高度", "default": 50.0, "min": -240.0, "max": 360.0, "step": 1.0, "unit": "px"}, # 正值向上拱起，负值向下弯曲
	{"group": "入场", "key": "arrival_start_scale", "label": "出现时大小", "default": 3.5, "min": 0.25, "max": 6.0, "step": 0.05, "unit": "倍"}, # 刚出现时相对原图的大小
	{"group": "入场", "key": "arrival_end_scale", "label": "落地后大小", "default": 1.0, "min": 0.25, "max": 3.0, "step": 0.05, "unit": "倍"}, # 着地和滑行阶段保持的大小
	{"group": "入场", "key": "arrival_start_angle", "label": "出现时平面角度", "default": -48.0, "min": -180.0, "max": 180.0, "step": 1.0, "unit": "度"}, # 起点包装的平面旋转角度
	{"group": "入场", "key": "arrival_contact_angle", "label": "着地时平面角度", "default": -26.0, "min": -180.0, "max": 180.0, "step": 1.0, "unit": "度"}, # 着地后从此角度滑行回正
	{"group": "入场", "key": "arrival_slide_speed", "label": "滑行初速度", "default": 1467.0, "min": 30.0, "max": 3000.0, "step": 1.0, "unit": "px/s"}, # 刚着地时沿滑行方向的速度
	{"group": "入场", "key": "arrival_slide_power", "label": "滑行减速曲线", "default": 2.0, "min": 1.1, "max": 5.0, "step": 0.1, "unit": ""}, # 2为匀减速，越大越早减速且尾段更长
	{"group": "入场", "key": "arrival_dust_spread", "label": "烟尘越过停止点", "default": 36.0, "min": 0.0, "max": 200.0, "step": 1.0, "unit": "px"}, # 烟尘沿整段滑行铺开，再越过停止后卡包边缘的距离；0保留原环状
	{"group": "入场", "key": "arrival_dim", "label": "背景压暗程度", "default": 0.48, "min": 0.0, "max": 0.9, "step": 0.01, "unit": ""}, # 初始包出现时背景暗幕透明度
]
const DEFAULT_RELIEF_BODY := 0.15 # 全部卡牌包的袋身凹凸默认强度
const DEFAULT_RELIEF_GOLD := 0.45 # 灰烬大包中央金纹的默认浅压纹强度
const DEFAULT_RELIEF_SEAL := 0.15 # 镀金委托中心火漆的默认浮雕强度
const RELIEF_MAX_STRENGTH := 2.0 # 调试器浮雕滑块的强度上限
const RELIEF_STRENGTH_STEP := 0.05 # 调试器浮雕滑块的调整步长
const RELIEF_LIGHT_FIELDS := [
	{"key": "light_angle_degrees", "label": "光源方向", "min": 0.0, "max": 360.0, "step": 1.0, "default": 60.0, "scale": 1.0, "format": "%.0f°", "tip": "光源所在侧：0°右、90°下、180°左、270°上；降低鼠标影响可使用固定方向"}, # 固定光源方位角
	{"key": "light_front", "label": "正面程度", "min": 0.2, "max": 4.0, "step": 0.05, "default": 0.2, "scale": 1.0, "format": "%.2f", "tip": "越小越贴近表面照射、凹凸对比越强；越大越接近正面照明"}, # 光源正向分量
	{"key": "light_brightness", "label": "亮度", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.95, "scale": 1.0, "format": "%.2f×", "tip": "0关灯，1保持原亮度；不影响高度、法线和凹凸位置数据视图"}, # 材质整体亮度倍率
	{"key": "light_mouse_influence", "label": "鼠标影响", "min": 0.0, "max": 100.0, "step": 1.0, "default": 80.0, "scale": 0.01, "format": "%.0f%%", "tip": "0%使用固定光源方向；100%由鼠标反侧决定方向；中间值平滑混合"}, # 默认80%鼠标反侧、20%固定方向的混合光源
]
const RELIEF_FIELDS := [
	{"key": "body_strength", "default": DEFAULT_RELIEF_BODY, "min": 0.0, "max": RELIEF_MAX_STRENGTH, "step": RELIEF_STRENGTH_STEP},
	{"key": "gold_strength", "default": DEFAULT_RELIEF_GOLD, "min": 0.0, "max": RELIEF_MAX_STRENGTH, "step": RELIEF_STRENGTH_STEP},
	{"key": "center_height_strength", "default": DEFAULT_RELIEF_SEAL, "min": 0.0, "max": RELIEF_MAX_STRENGTH, "step": RELIEF_STRENGTH_STEP},
] + RELIEF_LIGHT_FIELDS
static var save_path: String = DEFAULT_SAVE_PATH
static var _values: Dictionary = {}
static var _relief_values: Dictionary = {}
static var _loaded := false

static func defaults() -> Dictionary:
	var result := {}
	for field: Dictionary in FIELDS:
		result[field.key] = field.default
	return result

static func get_values() -> Dictionary:
	if not _loaded: load_saved()
	return _values

static func get_relief_values() -> Dictionary:
	if not _loaded: load_saved()
	return _relief_values

static func set_value(key: String, value: float) -> void:
	get_values()
	for field: Dictionary in FIELDS:
		if field.key == key:
			_values[key] = _normalize(field, value)
			return

static func reset_defaults() -> void:
	get_values().merge(defaults(), true)

static func load_saved(path: String = "") -> void:
	# 避开GDScript资源自带的reload(bool)，防止外部调用重载脚本并重置配置路径。
	if not path.is_empty(): save_path = path
	_loaded = true
	_values.merge(defaults(), true)
	var config := ConfigFile.new()
	var error := config.load(save_path)
	_relief_values = {}
	for field: Dictionary in RELIEF_FIELDS:
		var value: Variant = config.get_value("relief", field.key, field.default) if error == OK else field.default
		_relief_values[field.key] = _read_number(field, value)
	if error != OK: return
	for field: Dictionary in FIELDS:
		var value: Variant = config.get_value("opening", field.key, field.default)
		if value is float or value is int:
			_values[field.key] = _normalize(field, float(value))

static func save() -> Error:
	var config := ConfigFile.new()
	config.load(save_path)
	for field: Dictionary in FIELDS:
		config.set_value("opening", field.key, get_values()[field.key])
	return config.save(save_path)

static func save_relief(values: Dictionary) -> Error:
	get_relief_values()
	var config := ConfigFile.new()
	var load_error := config.load(save_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND: return load_error
	var saved := {}
	for field: Dictionary in RELIEF_FIELDS:
		saved[field.key] = _read_number(field, values.get(field.key, _relief_values[field.key]))
		config.set_value("relief", field.key, saved[field.key])
	var error := config.save(save_path)
	if error == OK: _relief_values = saved
	return error

static func _read_number(field: Dictionary, value: Variant) -> float:
	if value is float or value is int:
		return _normalize(field, float(value))
	return float(field.default)

static func _normalize(field: Dictionary, value: float) -> float:
	if not is_finite(value): return float(field.default)
	return clampf(snappedf(value, float(field.step)), float(field.min), float(field.max))
