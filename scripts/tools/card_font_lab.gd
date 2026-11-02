extends Control

signal close_requested

## 字体只在61×9原生像素里绘制一次，1×、4×和放大镜共用同一张纹理。
const Settings = preload("res://scripts/ui/card_text_display_settings.gd")
const CANVAS_SIZE := Vector2(1280, 720) # 调试器沿用游戏逻辑画布
const NAME_SIZE := Vector2i(61, 9) # 卡名可用宽高，所有候选固定不变
const FULL_HEIGHT := 19 # 完整行盒对照的采样高度，显示9px区域外的字形
const FULL_INSET := 5 # 完整行盒中9px区域的上边界
const PAPER := Color("edd6b4") # 正式名字牌接近的浅纸底色
const INK := Color("35251c") # 正式卡名使用的深棕字色
const FONTS := Settings.NAME_FONTS
const AA_NAMES := ["关闭抗锯齿", "灰度抗锯齿", "LCD 子像素"]
const DEFAULTS := {"font": 0, "aa": 1, "size": 9, "weight": 500, "hint": 1, "oversampling": 4, "subpixel": 1, "offset": 0, "auto_hint": false, "fit": true, "zoom": 8, "grid": false, "text": "重返战场"}

var profile_path := "user://card_font_lab.cfg"
var card_settings_path := Settings.SETTINGS_PATH
var controls: Dictionary = {}
var comparisons: Array[Dictionary] = []
var selected: Dictionary
var full_sample: Dictionary
var metrics: Label
var status: Label
var magnified: TextureRect
var full_magnified: TextureRect
var pixel_grid: Control
var _refresh_queued := false
var _font_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui_theme := Theme.new()
	ui_theme.default_font = Settings.readable_font()
	ui_theme.default_font_size = 15 # 调试控件字体不参与卡名小字实验
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("17212d") # 调试画布底色
	background.size = CANVAS_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_label("卡名字体调试 · 固定 61×9px", Vector2(20, 14), Vector2(900, 32), 24)
	_button("返回 · Esc", Vector2(940, 14), Vector2(130, 34), close_requested.emit).name = "CloseCardFontLab"
	_label("右侧每格：1×原图 + 4×像素放大；点击任意格选用该字体与抗锯齿。", Vector2(348, 60), Vector2(912, 24), 15)
	_build_controls()
	for aa: int in 3:
		_label(AA_NAMES[aa], Vector2(348 + aa * 304, 91), Vector2(290, 22), 16)
		for font_index: int in FONTS.size():
			_build_comparison(font_index, aa)
	_build_selected_preview()
	load_profile()
	_refresh_previews()


func _label(text: String, point: Vector2, extent: Vector2, font_size := 15) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	add_child(label)
	return label


func _button(text: String, point: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = point
	button.size = extent
	button.pressed.connect(action)
	add_child(button)
	return button


func _option(key: String, caption: String, row: int, options: Array) -> OptionButton:
	_label(caption, Vector2(20, 119 + row * 35), Vector2(96, 28))
	var option := OptionButton.new()
	option.name = key.capitalize() + "Option"
	option.position = Vector2(119, 119 + row * 35)
	option.size = Vector2(207, 29)
	option.fit_to_longest_item = false
	for text: String in options: option.add_item(text)
	option.item_selected.connect(func(_index: int): _queue_refresh())
	add_child(option)
	controls[key] = option
	return option


func _spin(key: String, caption: String, row: int, minimum: float, maximum: float, step := 1.0) -> SpinBox:
	_label(caption, Vector2(20, 119 + row * 35), Vector2(96, 28))
	var spin := SpinBox.new()
	spin.name = key.capitalize() + "SpinBox"
	spin.position = Vector2(119, 119 + row * 35)
	spin.size = Vector2(207, 29)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value_changed.connect(func(_value: float): _queue_refresh())
	add_child(spin)
	controls[key] = spin
	return spin


func _check(key: String, caption: String, point: Vector2) -> CheckBox:
	var check := CheckBox.new()
	check.name = key.capitalize() + "Check"
	check.text = caption
	check.position = point
	check.size = Vector2(304, 28)
	check.toggled.connect(func(_enabled: bool): _queue_refresh())
	add_child(check)
	controls[key] = check
	return check


func _build_controls() -> void:
	_label("测试卡名（可以直接输入）", Vector2(20, 60), Vector2(306, 22))
	var edit := LineEdit.new()
	edit.name = "SampleTextEdit"
	edit.position = Vector2(20, 86)
	edit.size = Vector2(190, 29)
	edit.text_changed.connect(func(_text: String): _queue_refresh())
	add_child(edit)
	controls.text = edit
	var names := OptionButton.new()
	names.name = "CardNameSamples"
	names.position = Vector2(218, 86)
	names.size = Vector2(108, 29)
	names.fit_to_longest_item = false
	for text: String in ["重返战场", "阵型步兵", "月之歌者", "碎甲啤酒机", "影步刺客", "余烬秘渊"]: names.add_item(text)
	names.item_selected.connect(func(index: int): edit.text = names.get_item_text(index); _queue_refresh())
	add_child(names)
	_option("font", "字体", 0, FONTS.map(func(font: Dictionary): return font.name)).item_selected.connect(_on_font_selected)
	_option("aa", "抗锯齿", 1, AA_NAMES)
	_spin("size", "名义字号", 2, 6, 12)
	_spin("weight", "矢量字重", 3, 300, 700, 50)
	_option("hint", "像素对齐", 4, ["无 Hinting", "轻度 Hinting", "完整 Hinting"])
	_option("subpixel", "字形定位", 5, ["整数像素", "自动子像素", "半像素", "四分之一像素"])
	_spin("oversampling", "字体采样", 6, 1, 4)
	_spin("offset", "上下微调", 7, -4, 4)
	_spin("zoom", "放大倍数", 8, 2, 10)
	_check("auto_hint", "启用自动 Hinting", Vector2(20, 435))
	_check("fit", "长名字按61px宽度缩字", Vector2(20, 465))
	_check("grid", "放大镜显示像素网格", Vector2(20, 495))
	_label("字号 ≠ 字形高度，裁切区域始终是9px。\n采样只改字体参数，游戏画布保持原方案。\nLCD 经合成后可能接近灰度，按实图判断。", Vector2(20, 532), Vector2(308, 74), 14)
	_button("应用到卡牌", Vector2(20, 610), Vector2(306, 32), apply_to_cards).name = "ApplyFontToCards"
	_button("保存参数", Vector2(20, 648), Vector2(146, 29), save_profile).name = "SaveFontProfile"
	_button("恢复初始", Vector2(180, 648), Vector2(146, 29), func(): apply_profile(DEFAULTS)).name = "ResetFontProfile"
	status = _label("", Vector2(20, 680), Vector2(306, 38), 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.clip_text = false


func _build_comparison(font_index: int, aa: int) -> void:
	var origin := Vector2(348 + aa * 304, 119 + font_index * 94)
	var button := _button("", origin, Vector2(292, 88), choose_comparison.bind(font_index, aa))
	button.name = "FontComparison_%d_%d" % [font_index, aa]
	_label("%s · %d号" % [FONTS[font_index].name, FONTS[font_index].size], origin + Vector2(10, 3), Vector2(274, 22), 14)
	var sample := _make_sample(NAME_SIZE, 0)
	sample.font_index = font_index
	sample.aa = aa
	sample.actual = _texture(sample.viewport, origin + Vector2(12, 28), Vector2(NAME_SIZE))
	sample.enlarged = _texture(sample.viewport, origin + Vector2(12, 46), Vector2(NAME_SIZE) * 4.0)
	comparisons.append(sample)


func _build_selected_preview() -> void:
	_label("当前设置 · 原始9px纹理的放大镜", Vector2(348, 505), Vector2(560, 25), 18)
	metrics = _label("", Vector2(348, 533), Vector2(900, 24), 14)
	selected = _make_sample(NAME_SIZE, 0)
	magnified = _texture(selected.viewport, Vector2(360, 570), Vector2(NAME_SIZE) * 8.0)
	full_sample = _make_sample(Vector2i(NAME_SIZE.x, FULL_HEIGHT), FULL_INSET)
	_label("完整行盒 4× · 红线间是9px", Vector2(990, 560), Vector2(270, 22), 14)
	full_magnified = _texture(full_sample.viewport, Vector2(990, 592), Vector2(NAME_SIZE.x, FULL_HEIGHT) * 4.0)
	var guide := Control.new()
	guide.position = full_magnified.position
	guide.size = full_magnified.size
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.draw.connect(func():
		for y: int in [FULL_INSET * 4, (FULL_INSET + NAME_SIZE.y) * 4]:
			guide.draw_line(Vector2(0, y), Vector2(guide.size.x, y), Color(0.8, 0.15, 0.12, 0.8))
	)
	add_child(guide)
	pixel_grid = Control.new()
	pixel_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel_grid.draw.connect(_draw_grid)
	add_child(pixel_grid)


func _make_sample(extent: Vector2i, inset: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "NativeFontSample"
	viewport.size = extent
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var paper := ColorRect.new()
	paper.color = PAPER
	paper.size = Vector2(extent)
	viewport.add_child(paper)
	var label := Label.new()
	label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	viewport.add_child(label)
	return {"viewport": viewport, "label": label, "inset": inset}


func _texture(viewport: SubViewport, point: Vector2, extent: Vector2) -> TextureRect:
	var texture := TextureRect.new()
	texture.texture = viewport.get_texture()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.position = point
	texture.size = extent
	add_child(texture)
	return texture


func get_profile() -> Dictionary:
	var result := {}
	for key: String in DEFAULTS:
		var control: Control = controls[key]
		if control is OptionButton: result[key] = control.selected
		elif control is SpinBox: result[key] = control.value
		elif control is CheckBox: result[key] = control.button_pressed
		else: result[key] = control.text
	return result


func apply_profile(profile: Dictionary) -> void:
	for key: String in DEFAULTS:
		var value: Variant = profile.get(key, DEFAULTS[key])
		var control: Control = controls[key]
		if control is OptionButton: control.select(clampi(int(value), 0, control.item_count - 1))
		elif control is SpinBox: control.set_value_no_signal(clampf(float(value), control.min_value, control.max_value))
		elif control is CheckBox: control.set_pressed_no_signal(bool(value))
		else: control.text = String(value)
	_queue_refresh()


func load_profile() -> void:
	var config := ConfigFile.new()
	var error := config.load(profile_path)
	apply_profile(config.get_value("font_lab", "profile", DEFAULTS) if error == OK else DEFAULTS)


func save_profile() -> Error:
	var config := ConfigFile.new()
	config.set_value("font_lab", "profile", get_profile())
	var error := config.save(profile_path)
	status.text = "已保存，下次打开继续当前参数。" if error == OK else "保存失败：%d" % error
	return error


func apply_to_cards() -> void:
	var preview_error := save_profile()
	var error := Settings.apply_name_profile(get_tree(), get_profile(), card_settings_path)
	if error == OK and preview_error == OK:
		close_requested.emit()
	else:
		status.text = "本次已应用；参数保存失败（%d／%d），可按Esc查看。" % [error, preview_error]


func choose_comparison(font_index: int, aa: int) -> void:
	controls.font.select(font_index)
	controls.aa.select(aa)
	controls["size"].set_value_no_signal(FONTS[font_index].size)
	_queue_refresh()


func _on_font_selected(index: int) -> void:
	controls["size"].set_value_no_signal(FONTS[index].size)
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	_refresh_previews.call_deferred()


func _make_font(index: int, aa: int, profile: Dictionary) -> Font:
	var key := [index, aa, profile.weight, profile.hint, profile.subpixel, profile.oversampling, profile.auto_hint]
	if _font_cache.has(key): return _font_cache[key]
	var parameters := profile.duplicate()
	parameters.font = index
	parameters.aa = aa
	var font := Settings.make_name_font(parameters)
	_font_cache[key] = font
	return font


func _update_sample(sample: Dictionary, font: Font, font_size: int, profile: Dictionary) -> int:
	var text: String = profile.text
	while bool(profile.fit) and font_size > 5 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > NAME_SIZE.x:
		font_size -= 1
	var label: Label = sample.label
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	var line_height := maxf(NAME_SIZE.y, font.get_height(font_size))
	label.position = Vector2(0, sample.inset + floorf((NAME_SIZE.y - line_height) * 0.5) + float(profile.offset))
	label.size = Vector2(NAME_SIZE.x, line_height)
	sample.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return font_size


func _refresh_previews() -> void:
	_refresh_queued = false
	if not is_instance_valid(metrics): return
	var profile := get_profile()
	# 修改Hinting等设置后释放旧参数的字体缓存，避免反复调试累积图集。
	_font_cache.clear()
	for sample: Dictionary in comparisons:
		_update_sample(sample, _make_font(sample.font_index, sample.aa, profile), FONTS[sample.font_index].size, profile)
	var font := _make_font(int(profile.font), int(profile.aa), profile)
	var fitted := _update_sample(selected, font, int(profile["size"]), profile)
	_update_sample(full_sample, font, int(profile["size"]), profile)
	var missing := ""
	for character: String in String(profile.text):
		if not font.has_char(character.unicode_at(0)) and not missing.contains(character): missing += character
	metrics.text = "固定61×9px｜实际字号 %d｜字体行高 %.0fpx｜上下偏移 %+dpx%s" % [fitted, font.get_height(fitted), int(profile.offset), "｜缺字：" + missing if not missing.is_empty() else ""]
	controls.weight.editable = bool(FONTS[int(profile.font)].variable)
	magnified.size = Vector2(NAME_SIZE) * float(profile.zoom)
	pixel_grid.position = magnified.position
	pixel_grid.size = magnified.size
	pixel_grid.visible = bool(profile.grid)
	pixel_grid.queue_redraw()


func _draw_grid() -> void:
	var zoom := float(controls.zoom.value)
	var color := Color(0.2, 0.35, 0.45, 0.35) # 像素网格线的颜色与透明度
	for x: int in NAME_SIZE.x + 1: pixel_grid.draw_line(Vector2(x * zoom, 0), Vector2(x * zoom, NAME_SIZE.y * zoom), color)
	for y: int in NAME_SIZE.y + 1: pixel_grid.draw_line(Vector2(0, y * zoom), Vector2(NAME_SIZE.x * zoom, y * zoom), color)


func prepare_close() -> void:
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_viewport().is_input_handled(): return
	for option: Node in find_children("*", "OptionButton", true, false):
		if option.get_popup().visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()
