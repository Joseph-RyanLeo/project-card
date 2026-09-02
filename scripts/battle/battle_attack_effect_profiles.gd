class_name BattleAttackEffectProfiles
extends RefCounted

## 正式战斗与攻击特效调试器共用的单一配置入口。
## 默认值随项目代码保存；开发者在调试器中保存的覆盖值写入 user://。

const SAVE_PATH := "user://battle_attack_effects.cfg"
const PROFILE_IDS: Array[StringName] = [
	&"melee_attack",
	&"ranged_attack",
	&"magic_attack",
	&"water_spread",
	&"dark_repeat",
	&"wood_pierce",
	&"light_reflect",
]
const PROFILE_NAMES := {
	&"melee_attack": "近战攻击",
	&"ranged_attack": "远程攻击",
	&"magic_attack": "法术攻击",
	&"water_spread": "水·扩散",
	&"dark_repeat": "暗·连击",
	&"wood_pierce": "木·穿刺",
	&"light_reflect": "光·折射",
}
const MASK_IDS: Array[StringName] = [&"energy", &"projectile"]
const MASK_NAMES := {&"energy": "宽能量尾迹", &"projectile": "尖头弹体尾迹"}

# 调试器按此顺序生成所有数值控件；min/max/step 同时负责保存前的安全钳制。
const NUMERIC_FIELDS: Array[Dictionary] = [
	{"key": &"duration", "label": "播放时间", "min": 0.10, "max": 2.00, "step": 0.01, "suffix": " 秒"},
	{"key": &"beam_height", "label": "尾迹高度", "min": 8.0, "max": 160.0, "step": 1.0, "suffix": " px"},
	{"key": &"end_padding", "label": "首尾延伸", "min": 0.0, "max": 64.0, "step": 1.0, "suffix": " px"},
	{"key": &"pixel_size", "label": "像素块大小", "min": 1.0, "max": 16.0, "step": 1.0, "suffix": " px"},
	{"key": &"trail_length", "label": "拖尾长度", "min": 0.05, "max": 1.00, "step": 0.01, "suffix": ""},
	{"key": &"trail_softness", "label": "头尾柔化", "min": 0.001, "max": 0.200, "step": 0.001, "suffix": ""},
	{"key": &"curve_segments", "label": "曲线分段", "min": 4.0, "max": 64.0, "step": 1.0, "suffix": ""},
	{"key": &"arc_height", "label": "整体弧度", "min": -160.0, "max": 160.0, "step": 1.0, "suffix": " px"},
	{"key": &"flow_speed", "label": "内部流速", "min": 0.0, "max": 8.0, "step": 0.05, "suffix": ""},
	{"key": &"flow_frequency", "label": "内部流动密度", "min": 1.0, "max": 24.0, "step": 0.1, "suffix": ""},
	{"key": &"flow_strength", "label": "内部流动强度", "min": 0.0, "max": 0.90, "step": 0.01, "suffix": ""},
	{"key": &"warp_speed", "label": "扭曲速度", "min": -8.0, "max": 8.0, "step": 0.05, "suffix": ""},
	{"key": &"warp_frequency", "label": "噪声平铺密度", "min": 0.1, "max": 24.0, "step": 0.1, "suffix": ""},
	{"key": &"twirl_frequency", "label": "旋扭频率", "min": 0.1, "max": 24.0, "step": 0.1, "suffix": ""},
	{"key": &"warp_strength", "label": "扭曲强度", "min": 0.0, "max": 0.45, "step": 0.005, "suffix": ""},
	{"key": &"mask_cutoff", "label": "黑底裁切", "min": 0.0, "max": 0.40, "step": 0.005, "suffix": ""},
	{"key": &"mask_power", "label": "遮罩对比", "min": 0.20, "max": 4.00, "step": 0.05, "suffix": ""},
	{"key": &"edge_threshold", "label": "边缘阈值", "min": 0.0, "max": 0.80, "step": 0.005, "suffix": ""},
	{"key": &"edge_softness", "label": "边缘柔化", "min": 0.001, "max": 0.25, "step": 0.001, "suffix": ""},
]

const _COMMON_DEFAULTS := {
	"duration": 0.58,
	"beam_height": 48.0,
	"end_padding": 16.0,
	"pixel_size": 1.0,
	"trail_length": 0.50,
	"trail_softness": 0.035,
	"curve_segments": 20.0,
	"flow_speed": 2.40,
	"flow_frequency": 6.0,
	"flow_strength": 0.48,
	"warp_speed": -1.0,
	"warp_frequency": 6.0,
	"twirl_frequency": 4.0,
	"warp_strength": 0.12,
	"mask_cutoff": 0.018,
	"mask_power": 1.0,
	"edge_threshold": 0.12,
	"edge_softness": 0.025,
}

static var _profiles: Dictionary = {}
static var _loaded: bool = false


static func get_profile(profile_id: StringName) -> Dictionary:
	_ensure_loaded()
	return (_profiles.get(profile_id, get_default_profile(profile_id)) as Dictionary).duplicate(true)


static func get_default_profile(profile_id: StringName) -> Dictionary:
	var profile := _COMMON_DEFAULTS.duplicate(true)
	match profile_id:
		&"water_spread":
			profile.merge({"mask_kind": &"energy", "arc_height": 54.0, "flow_speed": 2.04, "flow_frequency": 5.1, "flow_strength": 0.408, "warp_speed": -0.80, "warp_frequency": 4.0, "twirl_frequency": 3.0, "warp_strength": 0.10}, true)
		&"dark_repeat":
			profile.merge({"mask_kind": &"energy", "arc_height": 42.0, "flow_speed": 2.88, "flow_frequency": 8.4, "flow_strength": 0.528, "warp_speed": -1.20, "warp_frequency": 6.0, "twirl_frequency": 7.0, "warp_strength": 0.20}, true)
		&"wood_pierce":
			profile.merge({"mask_kind": &"projectile", "arc_height": 12.0, "flow_speed": 1.80, "flow_frequency": 3.9, "flow_strength": 0.384, "warp_speed": -0.60, "warp_frequency": 3.0, "twirl_frequency": 2.2, "warp_strength": 0.08}, true)
		&"light_reflect":
			profile.merge({"mask_kind": &"projectile", "arc_height": -60.0, "flow_speed": 3.24, "flow_frequency": 9.6, "flow_strength": 0.360, "warp_speed": -1.50, "warp_frequency": 8.0, "twirl_frequency": 8.0, "warp_strength": 0.06}, true)
		&"melee_attack":
			profile.merge({"mask_kind": &"energy", "arc_height": 60.0, "warp_frequency": 4.0, "twirl_frequency": 3.0, "warp_strength": 0.12}, true)
		&"ranged_attack":
			profile.merge({"mask_kind": &"projectile", "arc_height": -30.0, "flow_speed": 3.36, "flow_frequency": 7.2, "flow_strength": 0.360, "warp_speed": -1.40, "warp_frequency": 6.0, "twirl_frequency": 5.0, "warp_strength": 0.05}, true)
		&"magic_attack":
			profile.merge({"mask_kind": &"energy", "arc_height": 78.0, "flow_speed": 2.16, "flow_frequency": 6.9, "flow_strength": 0.528, "warp_speed": -0.80, "warp_frequency": 5.0, "twirl_frequency": 4.0, "warp_strength": 0.18}, true)
		_:
			profile.merge({"mask_kind": &"energy", "arc_height": 24.0}, true)
	return _clamp_profile(profile)


static func normalize_profile(profile_id: StringName, source: Dictionary) -> Dictionary:
	var result := get_default_profile(profile_id)
	result.merge(source, true)
	return _clamp_profile(result)


static func _clamp_profile(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var mask_kind := StringName(source.get("mask_kind", result.get("mask_kind", &"energy")))
	result["mask_kind"] = mask_kind if mask_kind in MASK_IDS else &"energy"
	for field: Dictionary in NUMERIC_FIELDS:
		var key := String(field["key"])
		var value := float(source.get(key, result.get(key, 0.0)))
		result[key] = clampf(value, float(field["min"]), float(field["max"]))
	result["curve_segments"] = float(roundi(float(result["curve_segments"])))
	return result


static func save_profile(profile_id: StringName, profile: Dictionary) -> Error:
	_ensure_loaded()
	_profiles[profile_id] = normalize_profile(profile_id, profile)
	return _write_all_profiles(SAVE_PATH)


static func save_profiles(profiles: Dictionary) -> Error:
	_ensure_loaded()
	for profile_id: StringName in PROFILE_IDS:
		if profiles.has(profile_id):
			_profiles[profile_id] = normalize_profile(profile_id, profiles[profile_id] as Dictionary)
	return _write_all_profiles(SAVE_PATH)


static func reset_profile(profile_id: StringName) -> Error:
	_ensure_loaded()
	_profiles[profile_id] = get_default_profile(profile_id)
	return _write_all_profiles(SAVE_PATH)


static func reload(use_saved_file: bool = true) -> void:
	_loaded = false
	_profiles.clear()
	_ensure_loaded(use_saved_file)


static func save_snapshot(path: String) -> Error:
	_ensure_loaded()
	return _write_all_profiles(path)


static func _ensure_loaded(use_saved_file: bool = true) -> void:
	if _loaded:
		return
	_loaded = true
	for profile_id: StringName in PROFILE_IDS:
		_profiles[profile_id] = get_default_profile(profile_id)
	if not use_saved_file or not FileAccess.file_exists(SAVE_PATH):
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for profile_id: StringName in PROFILE_IDS:
		var section := String(profile_id)
		var loaded_profile := (_profiles[profile_id] as Dictionary).duplicate(true)
		loaded_profile["mask_kind"] = StringName(config.get_value(section, "mask_kind", loaded_profile["mask_kind"]))
		for field: Dictionary in NUMERIC_FIELDS:
			var key := String(field["key"])
			loaded_profile[key] = config.get_value(section, key, loaded_profile[key])
		_profiles[profile_id] = normalize_profile(profile_id, loaded_profile)


static func _write_all_profiles(path: String) -> Error:
	var config := ConfigFile.new()
	for profile_id: StringName in PROFILE_IDS:
		var section := String(profile_id)
		var profile := _profiles[profile_id] as Dictionary
		config.set_value(section, "mask_kind", String(profile["mask_kind"]))
		for field: Dictionary in NUMERIC_FIELDS:
			var key := String(field["key"])
			config.set_value(section, key, profile[key])
	return config.save(path)
