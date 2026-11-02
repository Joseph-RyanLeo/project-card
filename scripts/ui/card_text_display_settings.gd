extends RefCounted

## 显示偏好属于本机，独立于三个游戏存档；所有 CardView 共用同一个模式。
enum Mode { CARD, POPUP }

const SETTINGS_PATH := "user://card_text_display.cfg"
const NAME_FONT_SIZE := 9 # 未应用调试参数时的黑体名义字号，卡名区域仍固定9px高
const NAME_FONTS := [
	{"name": "Noto Sans SC · 当前黑体", "path": "res://assets/fonts/NotoSansSC-VF.ttf", "size": 9, "variable": true},
	{"name": "缝合像素 · 8px 黑体", "path": "res://assets/fonts/font_lab/fusion8/fusion-pixel-8px-monospaced-zh_hans.ttf", "size": 8, "variable": false},
	{"name": "缝合像素 · 10px 黑体", "path": "res://assets/fonts/font_lab/fusion10/fusion-pixel-10px-monospaced-zh_hans.ttf", "size": 10, "variable": false},
	{"name": "寒蝉点阵 · 原字体对照", "path": "res://assets/fonts/chill_7.ttf", "size": 8, "variable": false},
]
static var mode: Mode = Mode.CARD
static var _loaded := false
static var _font: FontVariation
static var _name_profile: Dictionary = {}
static var _applied_name_font: Font


static func is_popup_mode() -> bool:
	if not _loaded:
		load_settings()
	return mode == Mode.POPUP


static func load_settings(path: String = SETTINGS_PATH) -> void:
	_loaded = true
	mode = Mode.CARD
	_name_profile = {}
	_applied_name_font = null
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	mode = int(config.get_value("cards", "text_display", Mode.CARD)) as Mode
	if mode not in [Mode.CARD, Mode.POPUP]: mode = Mode.CARD
	var profile: Variant = config.get_value("cards", "name_font_profile", {})
	if profile is Dictionary: _name_profile = profile


static func get_name_profile() -> Dictionary:
	if not _loaded: load_settings()
	return _name_profile.duplicate()


static func card_name_font(default_font: Font) -> Font:
	if not get_name_profile().is_empty():
		if _applied_name_font == null: _applied_name_font = make_name_font(_name_profile)
		return _applied_name_font
	return readable_font() if is_popup_mode() else default_font


static func make_name_font(profile: Dictionary) -> Font:
	var index := clampi(int(profile.font), 0, NAME_FONTS.size() - 1)
	var base := (load(NAME_FONTS[index].path) as FontFile).duplicate() as FontFile
	base.antialiasing = int(profile.aa) as TextServer.FontAntialiasing
	base.hinting = int(profile.hint) as TextServer.Hinting
	base.subpixel_positioning = int(profile.subpixel) as TextServer.SubpixelPositioning
	base.oversampling = float(profile.oversampling)
	base.force_autohinter = bool(profile.auto_hint)
	base.allow_system_fallback = false
	if not NAME_FONTS[index].variable: return base
	var font := FontVariation.new()
	font.base_font = base
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): float(profile.weight)}
	return font


static func apply_name_profile(tree: SceneTree, profile: Dictionary, path: String = SETTINGS_PATH) -> Error:
	if not _loaded: load_settings()
	_name_profile = profile.duplicate()
	for key: String in ["text", "zoom", "grid"]: _name_profile.erase(key)
	_applied_name_font = make_name_font(_name_profile)
	for view: Node in tree.get_nodes_in_group(&"card_views"):
		view.apply_card_name_typography()
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("cards", "text_display", mode)
	config.set_value("cards", "name_font_profile", _name_profile)
	return config.save(path)


static func readable_font() -> Font:
	if _font == null:
		var base := load("res://assets/fonts/NotoSansSC-VF.ttf") as FontFile
		base.oversampling = 4.0 # 高清卡面合成时保留曲线字形细节
		_font = FontVariation.new()
		_font.base_font = base
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 500.0}
	return _font


static func set_mode(tree: SceneTree, value: Mode, persist := true, path: String = SETTINGS_PATH) -> Error:
	if not _loaded: load_settings()
	mode = value
	for view: Node in tree.get_nodes_in_group(&"card_views"):
		view.apply_text_display_mode()
	for menu: Node in tree.get_nodes_in_group(&"escape_pause_menus"):
		menu.sync_card_text_display_mode()
	for popup: Node in tree.get_nodes_in_group(&"card_effect_popup"):
		popup.hide_card()
	if not persist: return OK
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("cards", "text_display", mode)
	return config.save(path)
