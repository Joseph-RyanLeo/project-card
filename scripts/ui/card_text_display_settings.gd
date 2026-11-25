extends RefCounted

## 显示偏好属于本机，独立于三个游戏存档；所有 CardView 共用同一个模式。
enum Mode { CARD, POPUP }

const SETTINGS_PATH := "user://card_text_display.cfg"
const FONT_LAB_SETTINGS_PATH := "user://card_font_lab.cfg"
const NAME_FONT_SIZE := 9 # 未应用调试参数时的黑体名义字号，卡名区域仍固定9px高
const NAME_FONTS := [
	{"name": "Noto Sans SC · 当前黑体", "path": "res://assets/fonts/NotoSansSC-VF.ttf", "size": 9, "variable": true},
	{"name": "缝合像素 · 8px 黑体", "path": "res://assets/fonts/font_lab/fusion8/fusion-pixel-8px-monospaced-zh_hans.ttf", "size": 8, "variable": false},
	{"name": "缝合像素 · 10px 黑体", "path": "res://assets/fonts/font_lab/fusion10/fusion-pixel-10px-monospaced-zh_hans.ttf", "size": 10, "variable": false},
	{"name": "寒蝉点阵 · 原字体对照", "path": "res://assets/fonts/chill_7.ttf", "size": 8, "variable": false},
]
const NAME_PRESETS := [
	{"label": "随文字显示模式", "profile": {}},
	{"label": "黑体 9 px · 平滑", "profile": {"font": 0, "size": 9, "aa": 1, "hint": 1, "subpixel": 1, "oversampling": 4.0, "auto_hint": false, "weight": 500.0, "offset": 0.0, "fit": true}},
	{"label": "黑体 9 px · 关闭抗锯齿", "profile": {"font": 0, "size": 9, "aa": 0, "hint": 1, "subpixel": 1, "oversampling": 4.0, "auto_hint": false, "weight": 500.0, "offset": 0.0, "fit": true}},
	{"label": "缝合像素 8 px · 锐利", "profile": {"font": 1, "size": 8, "aa": 0, "hint": 1, "subpixel": 0, "oversampling": 4.0, "auto_hint": false, "weight": 500.0, "offset": 0.0, "fit": true}},
	{"label": "缝合像素 10 px · 锐利", "profile": {"font": 2, "size": 10, "aa": 0, "hint": 1, "subpixel": 0, "oversampling": 4.0, "auto_hint": false, "weight": 500.0, "offset": 0.0, "fit": false}},
]
const NAME_PROFILE_FIELDS := ["font", "size", "aa", "hint", "subpixel", "oversampling", "auto_hint", "weight", "offset", "fit"]
static var mode: Mode = Mode.CARD
static var _loaded := false
static var _font: FontVariation
static var _name_profile: Dictionary = {}
static var _custom_name_profile: Dictionary = {}
static var _using_custom_name_font := false
static var _applied_name_font: Font


static func is_popup_mode() -> bool:
	if not _loaded:
		load_settings()
	return mode == Mode.POPUP


static func load_settings(path: String = SETTINGS_PATH, lab_path: String = FONT_LAB_SETTINGS_PATH) -> void:
	_loaded = true
	mode = Mode.CARD
	_name_profile = {}
	_custom_name_profile = {}
	_using_custom_name_font = false
	_applied_name_font = null
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	mode = int(config.get_value("cards", "text_display", Mode.CARD)) as Mode
	if mode not in [Mode.CARD, Mode.POPUP]: mode = Mode.CARD
	_name_profile = _read_name_profile(config.get_value("cards", "name_font_profile", {}))
	_using_custom_name_font = not _name_profile.is_empty() and bool(config.get_value("cards", "use_custom_name_font", _matching_name_preset(_name_profile) < 0))
	if _using_custom_name_font:
		_custom_name_profile = _name_profile.duplicate()
	elif config.has_section_key("cards", "custom_name_font_profile"):
		_custom_name_profile = _read_name_profile(config.get_value("cards", "custom_name_font_profile"))
	elif config.has_section_key("cards", "name_font_profile"):
		# 旧版选预设时会覆盖应用项。此时尝试找回调试器最近保存的参数。
		var lab := ConfigFile.new()
		if lab.load(lab_path) == OK:
			_custom_name_profile = _read_name_profile(lab.get_value("font_lab", "profile", {}))


static func get_name_profile() -> Dictionary:
	if not _loaded: load_settings()
	return _name_profile.duplicate()


static func has_custom_name_font() -> bool:
	if not _loaded: load_settings()
	return not _custom_name_profile.is_empty()


static func name_font_selection() -> int:
	if not _loaded: load_settings()
	return custom_name_font_index() if _using_custom_name_font else maxi(_matching_name_preset(_name_profile), 0)


static func custom_name_font_index() -> int:
	return NAME_PRESETS.size()


static func _matching_name_preset(profile: Dictionary) -> int:
	for index: int in NAME_PRESETS.size():
		if profile == NAME_PRESETS[index].profile: return index
	return -1


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
	if not _loaded: load_settings(path)
	var custom := _read_name_profile(profile)
	if custom.is_empty() and not profile.is_empty(): return ERR_INVALID_DATA
	if not custom.is_empty(): _custom_name_profile = custom
	return _apply_name_font(tree, custom, not custom.is_empty(), path)


static func select_name_font(tree: SceneTree, index: int, path: String = SETTINGS_PATH) -> Error:
	if not _loaded: load_settings(path)
	if index == custom_name_font_index() and has_custom_name_font():
		return _apply_name_font(tree, _custom_name_profile, true, path)
	if index < 0 or index >= NAME_PRESETS.size(): return ERR_INVALID_PARAMETER
	return _apply_name_font(tree, NAME_PRESETS[index].profile, false, path)


static func _read_name_profile(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has_all(NAME_PROFILE_FIELDS): return {}
	var profile := {}
	for key: String in NAME_PROFILE_FIELDS: profile[key] = value[key]
	return profile


static func _apply_name_font(tree: SceneTree, profile: Dictionary, custom: bool, path: String) -> Error:
	_name_profile = profile.duplicate()
	_using_custom_name_font = custom
	_applied_name_font = make_name_font(_name_profile) if not _name_profile.is_empty() else null
	for view: Node in tree.get_nodes_in_group(&"card_views"):
		view.apply_card_name_typography()
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("cards", "text_display", mode)
	config.set_value("cards", "name_font_profile", _name_profile)
	config.set_value("cards", "custom_name_font_profile", _custom_name_profile)
	config.set_value("cards", "use_custom_name_font", _using_custom_name_font)
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
