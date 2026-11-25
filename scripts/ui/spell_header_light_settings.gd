class_name SpellHeaderLightSettings
extends RefCounted

signal changed

const SAVE_PATH := "user://spell_header_light.cfg"
const SECTION := "spell_header_light"
const FIELDS: Array[Dictionary] = [
	{"key": "brightness", "label": "令牌提亮幅度", "min": 0.0, "max": 80.0, "step": 0.01, "default": 18.75, "unit": "%"}, # 首枚令牌的亮度增幅
	{"key": "saturation", "label": "令牌增饱和幅度", "min": 0.0, "max": 80.0, "step": 0.01, "default": 15.0, "unit": "%"}, # 首枚令牌的饱和度增幅
	{"key": "release_strength", "label": "释放边缘光强度", "min": 0.0, "max": 200.0, "step": 1.0, "default": 100.0, "unit": "%"}, # 释放时金色边缘光峰值倍率
	{"key": "fade_seconds", "label": "边缘光淡出时间", "min": 0.0, "max": 2.0, "step": 0.01, "default": 0.20, "unit": "秒"}, # 到达峰值后淡出所需时间
]

var _values: Dictionary[String, float] = {}


func _init() -> void:
	reset_defaults()


func get_value(key: String) -> float:
	return _values[key]


func set_value(value: float, key: String) -> void:
	if _values[key] == value:
		return
	_values[key] = value
	changed.emit()


func reset_defaults() -> void:
	for field: Dictionary in FIELDS:
		_values[field.key] = field.default
	changed.emit()


func load_saved(path: String = SAVE_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for field: Dictionary in FIELDS:
		var value: Variant = config.get_value(SECTION, field.key, field.default)
		if (value is float or value is int) and is_finite(float(value)):
			_values[field.key] = clampf(float(value), field.min, field.max)
	changed.emit()


func save(path: String = SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	for key: String in _values:
		config.set_value(SECTION, key, _values[key])
	return config.save(path)
