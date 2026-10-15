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
	{"group": "IV卡", "key": "flash_intensity", "label": "卡面金色反光强度", "default": 0.2, "min": 0.0, "max": 2.0, "step": 0.01, "unit": ""}, # 卡面金色反光强度
	{"group": "IV卡", "key": "stripe_spacing", "label": "卡面反光条纹密度", "default": 14.0, "min": 1.0, "max": 50.0, "step": 0.5, "unit": ""}, # 卡面反光条纹密度
	{"group": "IV卡", "key": "stripe_width", "label": "卡面反光条纹锐度", "default": 10.0, "min": 1.0, "max": 20.0, "step": 0.5, "unit": ""}, # 卡面反光条纹锐度
	{"group": "IV卡", "key": "flash_angle_degrees", "label": "卡面反光方向", "default": 50.0, "min": 0.0, "max": 360.0, "step": 1.0, "unit": "度"}, # 卡面反光方向
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
]
static var save_path: String = DEFAULT_SAVE_PATH
static var _values: Dictionary = {}
static var _loaded := false

static func defaults() -> Dictionary:
	var result := {}
	for field: Dictionary in FIELDS:
		result[field.key] = field.default
	return result

static func get_values() -> Dictionary:
	if not _loaded: reload()
	return _values

static func set_value(key: String, value: float) -> void:
	get_values()
	for field: Dictionary in FIELDS:
		if field.key == key:
			_values[key] = _normalize(field, value)
			return

static func reset_defaults() -> void:
	get_values().merge(defaults(), true)

static func reload() -> void:
	_loaded = true
	_values.merge(defaults(), true)
	var config := ConfigFile.new()
	if config.load(save_path) != OK: return
	for field: Dictionary in FIELDS:
		var value: Variant = config.get_value("opening", field.key, field.default)
		if value is float or value is int:
			_values[field.key] = _normalize(field, float(value))

static func save() -> Error:
	var config := ConfigFile.new()
	for field: Dictionary in FIELDS:
		config.set_value("opening", field.key, get_values()[field.key])
	return config.save(save_path)

static func _normalize(field: Dictionary, value: float) -> float:
	if not is_finite(value): return float(field.default)
	return clampf(snappedf(value, float(field.step)), float(field.min), float(field.max))
