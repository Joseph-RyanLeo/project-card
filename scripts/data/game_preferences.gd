extends RefCounted

## 本机偏好独立于三个游戏档；删除游戏档不删除偏好。
var path := "user://game_preferences.cfg"
var volume: float = 25.0 # 默认主音量百分比
var display_mode: int = 1 # 默认1080p窗口，沿用GameDisplay枚举


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	var saved_volume: Variant = config.get_value("settings", "volume", volume)
	var saved_display: Variant = config.get_value("settings", "display_mode", display_mode)
	if (saved_volume is int or saved_volume is float) and is_finite(float(saved_volume)):
		volume = clampf(float(saved_volume), 0, 100)
	if saved_display is int and saved_display >= 0 and saved_display <= 3: display_mode = saved_display


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "display_mode", display_mode)
	return config.save(path)
