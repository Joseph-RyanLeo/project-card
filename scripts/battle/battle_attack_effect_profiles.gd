class_name BattleAttackEffectProfiles
extends RefCounted

## 正式战斗与攻击特效调试器共用的单一配置入口。
## 默认值随项目代码保存；开发者在调试器中保存的覆盖值写入 user://。

const SAVE_PATH := "user://battle_attack_effects.cfg"
const FILE_FORMAT := "project_card_attack_effects"
const FILE_VERSION: int = 2
const PROFILE_IDS: Array[StringName] = [
	&"melee_attack",
	&"ranged_attack",
	&"magic_attack",
	&"heal_action",
	&"defense_action",
	&"water_spread",
	&"dark_repeat",
	&"wood_pierce",
	&"light_reflect",
	&"fire_burn",
]
const PROFILE_NAMES := {
	&"melee_attack": "近战攻击",
	&"ranged_attack": "远程攻击",
	&"magic_attack": "法术攻击",
	&"heal_action": "治疗行动",
	&"defense_action": "防御行动",
	&"water_spread": "水·扩散",
	&"dark_repeat": "暗·连击",
	&"wood_pierce": "木·穿刺",
	&"light_reflect": "光·折射",
	&"fire_burn": "火·灼烧",
}
const MASK_IDS: Array[StringName] = [&"energy", &"projectile", &"soul_ribbon", &"water_flow", &"wood_thorns", &"dark_slash"]
const MASK_NAMES := {&"energy": "宽能量尾迹", &"projectile": "尖头弹体尾迹", &"soul_ribbon": "灵魂光带", &"water_flow": "像素水流", &"wood_thorns": "手绘木穿刺", &"dark_slash": "手绘暗斩击"}

# 只替换外观参数，保留当前行动的播放时间与变速强度，沿用既有命中时序。
const SOUL_RIBBON_PRESET := {
	"mask_kind": &"soul_ribbon",
	"beam_height": 28.0, # 光带最宽处的厚度（像素）
	"end_padding": 0.0, # 光带停在目标中心，不向目标后方延伸
	"pixel_size": 3.0, # 光带轮廓的像素块大小
	"curve_segments": 40.0, # 贝塞尔路径的采样段数
	"arc_height": -150.0, # 从攻击方上方弯出，再落向目标
	"flow_speed": 1.5, # 带内亮纹的流动速度
	"flow_frequency": 4.0, # 带内亮纹的重复密度
	"flow_strength": 0.18, # 带内亮纹对透明度的影响强度
	"warp_strength": 0.015, # 光带边缘的轻微摆动幅度
	"mask_cutoff": 0.0, # 不裁掉程序生成的光带主体
	"mask_power": 1.0, # 光带透明度对比
	"edge_threshold": 0.08, # 光带外围裁切阈值
	"edge_softness": 0.015, # 光带外围裁切的柔化范围
	"soul_taper": 0.75, # 越大，细尾向宽头过渡越集中在头部
	"soul_core_width": 0.30, # 白色亮芯占光带宽度的比例
}

# 调试器按此顺序生成所有数值控件；min/max/step 同时负责保存前的安全钳制。
const NUMERIC_FIELDS: Array[Dictionary] = [
	{"key": &"duration", "label": "播放时间", "min": 0.10, "max": 2.00, "step": 0.01, "suffix": " 秒"},
	{"key": &"speed_variation_strength", "label": "变速强度", "min": 0.0, "max": 1.0, "step": 0.01, "suffix": ""},
	{"key": &"beam_height", "label": "尾迹高度", "min": 8.0, "max": 160.0, "step": 1.0, "suffix": " px"},
	{"key": &"end_padding", "label": "首尾延伸", "min": 0.0, "max": 64.0, "step": 1.0, "suffix": " px"},
	{"key": &"pixel_size", "label": "像素块大小", "min": 1.0, "max": 16.0, "step": 1.0, "suffix": " px"},
	{"key": &"trail_length", "label": "拖尾长度", "min": 0.05, "max": 1.00, "step": 0.01, "suffix": ""},
	{"key": &"trail_softness", "label": "头尾柔化", "min": 0.001, "max": 0.200, "step": 0.001, "suffix": ""},
	{"key": &"soul_taper", "label": "光带收尾指数", "min": 0.20, "max": 3.00, "step": 0.05, "suffix": "", "hint": "仅用于灵魂光带。越大，尾巴越细，宽度越集中在头部。"},
	{"key": &"soul_core_width", "label": "光带亮芯宽度", "min": 0.0, "max": 0.80, "step": 0.01, "suffix": "", "hint": "仅用于灵魂光带。调整白色亮芯所占比例；设为0关闭亮芯。"},
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
	"speed_variation_strength": 0.78, # 三种随机速度曲线相对匀速的变化强度
	"beam_height": 48.0,
	"end_padding": 16.0,
	"pixel_size": 1.0,
	"trail_length": 0.50,
	"trail_softness": 0.035,
	"soul_taper": 0.75, # 灵魂光带由细尾向宽头过渡的指数
	"soul_core_width": 0.30, # 灵魂光带白色亮芯的宽度比例
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
			profile.merge({"mask_kind": &"water_flow", "beam_height": 112.0, "pixel_size": 2.0, "arc_height": 0.0, "end_padding": 0.0, "flow_speed": 2.04, "flow_frequency": 5.1, "flow_strength": 0.55, "warp_speed": -0.80, "warp_frequency": 4.0, "twirl_frequency": 3.0, "warp_strength": 0.14}, true)
		&"fire_burn":
			profile.merge({"mask_kind": &"energy", "duration": 1.8, "beam_height": 160.0, "pixel_size": 2.0, "flow_speed": 1.6, "flow_frequency": 5.0, "warp_strength": 0.10}, true)
		&"dark_repeat":
			profile.merge({"mask_kind": &"dark_slash", "beam_height": 144.0, "arc_height": 0.0}, true) # 暗斩整体宽度为144逻辑像素
		&"wood_pierce":
			profile.merge({"mask_kind": &"wood_thorns", "beam_height": 70.0, "arc_height": 0.0}, true) # 70为木原图的横向比例参考值；默认不压缩原画像素
		&"light_reflect":
			profile.merge({"mask_kind": &"projectile", "arc_height": -60.0, "flow_speed": 3.24, "flow_frequency": 9.6, "flow_strength": 0.360, "warp_speed": -1.50, "warp_frequency": 8.0, "twirl_frequency": 8.0, "warp_strength": 0.06}, true)
		&"melee_attack":
			profile.merge({"mask_kind": &"energy", "arc_height": 60.0, "warp_frequency": 4.0, "twirl_frequency": 3.0, "warp_strength": 0.12}, true)
		&"ranged_attack":
			profile.merge({"mask_kind": &"projectile", "arc_height": -30.0, "flow_speed": 3.36, "flow_frequency": 7.2, "flow_strength": 0.360, "warp_speed": -1.40, "warp_frequency": 6.0, "twirl_frequency": 5.0, "warp_strength": 0.05}, true)
		&"magic_attack":
			profile.merge({"mask_kind": &"energy", "arc_height": 78.0, "flow_speed": 2.16, "flow_frequency": 6.9, "flow_strength": 0.528, "warp_speed": -0.80, "warp_frequency": 5.0, "twirl_frequency": 4.0, "warp_strength": 0.18}, true)
		&"heal_action":
			profile.merge({"mask_kind": &"energy", "arc_height": 44.0, "flow_speed": 1.80, "flow_frequency": 5.2, "flow_strength": 0.36, "warp_speed": -0.55, "warp_frequency": 4.0, "twirl_frequency": 3.0, "warp_strength": 0.08}, true)
		&"defense_action":
			profile.merge({"mask_kind": &"energy", "arc_height": -38.0, "flow_speed": 1.65, "flow_frequency": 4.8, "flow_strength": 0.32, "warp_speed": -0.45, "warp_frequency": 3.5, "twirl_frequency": 2.5, "warp_strength": 0.07}, true)
		_:
			profile.merge({"mask_kind": &"energy", "arc_height": 24.0}, true)
	return _clamp_profile(profile)


static func normalize_profile(profile_id: StringName, source: Dictionary) -> Dictionary:
	var result := get_default_profile(profile_id)
	result.merge(source, true)
	return _clamp_profile(result)


static func make_soul_ribbon_profile(profile_id: StringName, source: Dictionary) -> Dictionary:
	var result := normalize_profile(profile_id, source)
	result.merge(SOUL_RIBBON_PRESET, true)
	return _clamp_profile(result)


static func make_element_sample_profile(profile_id: StringName, source: Dictionary) -> Dictionary:
	var result := normalize_profile(profile_id, source)
	var defaults := get_default_profile(profile_id)
	for key: String in ["mask_kind", "beam_height"]:
		result[key] = defaults[key]
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
	if profile_id not in PROFILE_IDS: return ERR_INVALID_PARAMETER
	return save_profiles({profile_id: profile})


static func save_profiles(profiles: Dictionary, path: String = SAVE_PATH) -> Error:
	_ensure_loaded()
	var candidate := _profiles.duplicate(true)
	for profile_id: StringName in PROFILE_IDS:
		if profiles.has(profile_id):
			candidate[profile_id] = normalize_profile(profile_id, profiles[profile_id] as Dictionary)
	var error := _write_all_profiles(path, candidate)
	if error == OK: _profiles = candidate
	return error


static func reset_profile(profile_id: StringName) -> Error:
	return save_profile(profile_id, get_default_profile(profile_id))


static func reload_profiles(use_saved_file: bool = true) -> void:
	_loaded = false
	_profiles.clear()
	_ensure_loaded(use_saved_file)


static func save_snapshot(path: String) -> Error:
	_ensure_loaded()
	return _write_all_profiles(path)


static func get_profiles() -> Dictionary:
	_ensure_loaded()
	return _profiles.duplicate(true)


static func export_profiles(path: String, profiles: Dictionary) -> Error:
	var validated := _validate_file_profiles(profiles)
	if not validated.success: return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": FILE_FORMAT, "version": FILE_VERSION, "profiles": validated.profiles}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	return error


static func read_profile_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"success": false, "error": "无法打开配置文件：" + error_string(FileAccess.get_open_error())}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK: return {"success": false, "error": "JSON格式错误（第%d行）" % parser.get_error_line()}
	var document: Variant = parser.data
	if not document is Dictionary or document.get("format") != FILE_FORMAT or (document.get("version") != 1 and document.get("version") != FILE_VERSION):
		return {"success": false, "error": "文件类型或配置版本不受支持"}
	return _validate_file_profiles(document.get("profiles"), int(document.version) == 1)


static func _validate_file_profiles(source: Variant, legacy: bool = false) -> Dictionary:
	if not source is Dictionary or source.size() != PROFILE_IDS.size() - (1 if legacy else 0):
		return {"success": false, "error": "配置必须包含全部攻击特效类型"}
	var profiles: Dictionary = {}
	for id: StringName in PROFILE_IDS:
		if legacy and id == &"fire_burn":
			profiles[id] = get_default_profile(id)
			continue
		var profile: Variant = source.get(id)
		if not profile is Dictionary:
			return {"success": false, "error": "缺少特效类型：" + PROFILE_NAMES[id]}
		var mask: Variant = profile.get("mask_kind")
		if not (mask is String or mask is StringName) or StringName(mask) not in MASK_IDS:
			return {"success": false, "error": PROFILE_NAMES[id] + "的特效样式无效"}
		for field: Dictionary in NUMERIC_FIELDS:
			var value: Variant = profile.get(field.key)
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < float(field.min) or float(value) > float(field.max):
				return {"success": false, "error": "%s的%s缺失或超出范围" % [PROFILE_NAMES[id], field.label]}
			if field.key == &"curve_segments" and float(value) != floor(float(value)):
				return {"success": false, "error": "曲线分段必须是整数"}
		profiles[id] = normalize_profile(id, profile)
	return {"success": true, "profiles": profiles}


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


static func _write_all_profiles(path: String, source: Dictionary = {}) -> Error:
	var config := ConfigFile.new()
	var profiles := _profiles if source.is_empty() else source
	for profile_id: StringName in PROFILE_IDS:
		var section := String(profile_id)
		var profile := profiles[profile_id] as Dictionary
		config.set_value(section, "mask_kind", String(profile["mask_kind"]))
		for field: Dictionary in NUMERIC_FIELDS:
			var key := String(field["key"])
			config.set_value(section, key, profile[key])
	return config.save(path)
