extends SceneTree

const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const PanelScript = preload("res://scripts/ui/game_settings_panel.gd")
const Card = preload("res://scenes/ui/CardView.tscn")
const PREFS := "/private/tmp/project-card-name-font-settings.cfg"
const LAB := "/private/tmp/project-card-name-font-legacy-lab.cfg"

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var legacy := Settings.NAME_PRESETS[2].profile.duplicate() as Dictionary
	legacy.offset = 2.0
	var fixture := ConfigFile.new()
	fixture.set_value("font_lab", "profile", legacy.merged({"text": "调试样本", "zoom": 8, "grid": true}))
	_check(fixture.save(LAB) == OK, "准备独立的旧版字体调试偏好")
	fixture.clear()
	fixture.set_value("cards", "name_font_profile", Settings.NAME_PRESETS[3].profile)
	fixture.set_value("cards", "text_display", Settings.Mode.POPUP)
	_check(fixture.save(PREFS) == OK, "准备旧版预设覆盖后的字体设置")
	Settings.load_settings(PREFS, LAB)
	var panel := PanelScript.new()
	panel.text_settings_path = PREFS
	root.add_child(panel)
	var view := Card.instantiate() as CardView
	view.set_card_data(load("res://resources/cards/militia.tres"))
	root.add_child(view)
	_check(panel.name_font_option.selected == 3 and _has_custom_option(panel), "旧版预设启动仍使用预设，自定义可从旧调试参数找回")
	await _pick(panel, Settings.custom_name_font_index())
	_check(Settings.get_name_profile() == legacy and Settings.is_popup_mode() and view.name_label.get_theme_font_size("font_size") == 9, "恢复旧自定义，现有卡牌刷新并保留文字显示模式")
	await _pick(panel, 4)
	_check(Settings.get_name_profile() == Settings.NAME_PRESETS[4].profile and _has_custom_option(panel) and view.name_label.get_theme_font_size("font_size") == 10, "切预设后现有卡名更新，自定义入口仍可选择")
	Settings.load_settings(PREFS, "/private/tmp/project-card-missing-name-font-lab.cfg")
	panel.sync_text_mode()
	_check(panel.name_font_option.selected == 4 and _has_custom_option(panel), "重启后恢复活动预设并保留独立自定义")
	await _pick(panel, Settings.custom_name_font_index())
	_check(Settings.get_name_profile() == legacy and panel.name_font_option.selected == Settings.custom_name_font_index(), "重启后能切回同一份自定义")
	Settings.load_settings(PREFS)
	_check(Settings.name_font_selection() == Settings.custom_name_font_index(), "重启后仍选中自定义")
	var same_as_preset: Dictionary = Settings.NAME_PRESETS[1].profile.duplicate()
	_check(Settings.apply_name_profile(self, same_as_preset, PREFS) == OK, "允许从调试器保存与预设参数相同的自定义")
	Settings.load_settings(PREFS)
	panel.sync_text_mode()
	_check(panel.name_font_option.selected == Settings.custom_name_font_index(), "参数一致时仍区分用户选择的自定义和预设")
	await _pick(panel, 1)
	_check(panel.name_font_option.selected == 1 and _has_custom_option(panel), "也能明确选用相同字形的预设")
	await _pick(panel, 0)
	_check(Settings.get_name_profile().is_empty() and _has_custom_option(panel), "恢复随显示模式时仍保留自定义")
	panel.free()
	view.free()
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(LAB)
	print("卡名字体切换：%d 项，%d 失败" % [checks, failures])
	quit(1 if failures else 0)


func _pick(panel: Control, index: int) -> void:
	panel.name_font_option.select(index)
	panel.name_font_option.item_selected.emit(index)
	await process_frame


func _has_custom_option(panel: Control) -> bool:
	var option: OptionButton = panel.name_font_option
	var index := Settings.custom_name_font_index()
	return option.item_count > index and not option.is_item_disabled(index)


func _check(passed: bool, message: String) -> void:
	checks += 1
	if passed:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
