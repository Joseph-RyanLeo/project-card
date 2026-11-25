extends RefCounted

## 本机偏好独立于三个游戏档；删除游戏档不删除偏好。
const CRT_DEFAULT_STRENGTH := 42.0 # 横纹与四角内弯的默认百分比

var path := "user://game_preferences.cfg"
var volume: float = 25.0 # 默认主音量百分比
var display_mode: int = 1 # 默认1080p窗口，沿用GameDisplay枚举
var pixel_edge_aa := false
var crt_enabled := false # CRT 为可选显示效果，默认关闭
var crt_strength := CRT_DEFAULT_STRENGTH


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	var saved_volume: Variant = config.get_value("settings", "volume", volume)
	var saved_display: Variant = config.get_value("settings", "display_mode", display_mode)
	var saved_pixel_edge_aa: Variant = config.get_value("settings", "pixel_edge_aa", false)
	var saved_crt: Variant = config.get_value("settings", "crt_enabled", false)
	var split_crt_strength := _read_crt_percent(config.get_value("settings", "crt_scanline_strength", CRT_DEFAULT_STRENGTH), CRT_DEFAULT_STRENGTH)
	if (saved_volume is int or saved_volume is float) and is_finite(float(saved_volume)):
		volume = clampf(float(saved_volume), 0, 100)
	if saved_display is int and saved_display >= 0 and saved_display <= 3: display_mode = saved_display
	pixel_edge_aa = saved_pixel_edge_aa is bool and saved_pixel_edge_aa
	crt_enabled = saved_crt is bool and saved_crt
	crt_strength = _read_crt_percent(config.get_value("settings", "crt_strength", split_crt_strength), split_crt_strength)


func _read_crt_percent(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), 0.0, 100.0)
	return fallback


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "display_mode", display_mode)
	config.set_value("settings", "pixel_edge_aa", pixel_edge_aa)
	config.set_value("settings", "crt_enabled", crt_enabled)
	config.set_value("settings", "crt_strength", crt_strength)
	return config.save(path)
