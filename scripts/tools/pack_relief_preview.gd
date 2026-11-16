extends Control

signal close_requested

## 两张包装共用鼠标姿态。右侧复用正式包装素材和光照，可分别调节袋身与印记。
const Surface = preload("res://scripts/ui/inspection_card_surface.gd")
const PACK = preload("res://assets/card_ui/shop/ash_ledger_large.png")
const RELIEF = preload("res://shaders/pack_relief_sample.gdshader")
const PackArt = preload("res://scripts/ui/pack_tear_art.gd")
const ActionArt = preload("res://scripts/ui/action_card_pack_art.gd")
const BODY = PackArt.BODY
const GOLD = PackArt.GOLD
const HEIGHT = PackArt.HEIGHT
const REGIONS = PackArt.REGIONS
const PACK_SAMPLES := [
	{"label": "灰烬证册 · 大包", "texture": PACK, "detail": "gold_strength"},
	{"label": "镀金委托 · 小包", "texture": PackArt.GILDED_WRAPPER, "detail": "center_height_strength"},
	{"label": "灰烬证册 · 小包", "texture": preload("res://assets/card_ui/shop/ash_ledger_small.png")},
	{"label": "铁壁铭刻 · 小包", "texture": preload("res://assets/card_ui/shop/ironwall_small.png")},
	{"label": "银月之章 · 小包", "texture": preload("res://assets/card_ui/shop/silvermoon_small.png")},
	{"label": "近战定向 · 小包", "texture": null},
]
const REFERENCE_ORIGIN := Vector2(174, 189) # 左侧大包基准位置，小包按相同中心对齐
const SAMPLE_ORIGIN := Vector2(870, 189) # 右侧大包基准位置，小包按相同中心对齐
const VIEW_NAMES := ["材质效果", "高度图 · 越亮越高", "法线 · 当前袋身强度", "素色光照 · 隐藏印刷", "凹凸位置 · 黄高度 / 青脊 / 紫沟"]
const CANVAS_SIZE := Vector2(1440, 960) # 样例的基准画布尺寸
const PACK_SCALE := 3.0 # 卡包原生像素放大倍率
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const DEFAULT_BODY := Settings.DEFAULT_RELIEF_BODY
const DEFAULT_GOLD := Settings.DEFAULT_RELIEF_GOLD
const DEFAULT_SEAL := Settings.DEFAULT_RELIEF_SEAL
const LIGHT_FIELDS := Settings.RELIEF_LIGHT_FIELDS
var original: InspectionCardSurface
var sample: InspectionCardSurface
var body_slider: HSlider
var gold_slider: HSlider
var status: Label
var view_selector: OptionButton
var pack_selector: OptionButton
var _detail_label: Label
var _save_feedback: Label
var _detail_parameter := ""
var _detail_strengths := {"gold_strength": DEFAULT_GOLD, "center_height_strength": DEFAULT_SEAL}
var lighting_controls: Dictionary = {}
var lighting_panel: PanelContainer
var lighting_mode_label: Label

func _ready() -> void:
	if get_parent() is Window:
		get_window().content_scale_size = Vector2i(CANVAS_SIZE)
		close_requested.connect(get_tree().quit)
	var ui_theme := Theme.new()
	ui_theme.default_font = preload("res://assets/fonts/chill_7.ttf")
	ui_theme.default_font_size = 20 # 样例说明的基础字号
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("111923") # 中性深色预览背景
	background.size = CANVAS_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_label("卡包凹凸调试", Vector2(48, 24), 30)
	var back := Button.new()
	back.name = "CloseReliefPreview"
	back.text = "返回 · Esc"
	back.position = Vector2(1238, 18)
	back.size = Vector2(150, 40) # 返回按钮尺寸
	back.pressed.connect(close_requested.emit)
	add_child(back)
	_label("两侧同步倾斜。右侧可试调袋身、独立印记和灯光。", Vector2(48, 69), 20)
	_label("现有烫金 · 对照", Vector2(214, 123), 24)
	_label("正式素材 · 凹凸样例", Vector2(866, 123), 24)
	_label("样包", Vector2(664, 24), 20)
	pack_selector = OptionButton.new()
	pack_selector.name = "PackSampleSelector"
	pack_selector.position = Vector2(732, 18) # 样包选择框位于标题栏右侧
	pack_selector.size = Vector2(462, 40) # 选择框留足主题和包型的文字宽度
	for entry: Dictionary in PACK_SAMPLES:
		pack_selector.add_item(entry.label)
	pack_selector.item_selected.connect(select_pack)
	add_child(pack_selector)
	view_selector = OptionButton.new()
	view_selector.position = Vector2(1018, 65)
	view_selector.size = Vector2(374, 38) # 计算图选择框的尺寸
	view_selector.add_theme_font_size_override("font_size", 16) # 计算图选项字号，避免长说明挤出窗口
	view_selector.fit_to_longest_item = false
	view_selector.clip_text = true
	for view_name: String in VIEW_NAMES:
		view_selector.add_item(view_name)
	view_selector.item_selected.connect(set_debug_view)
	add_child(view_selector)
	_build_lighting_panel()
	_label("袋身凹凸", Vector2(62, 799), 21)
	body_slider = _slider(Vector2(198, 806), DEFAULT_BODY, "body_strength")
	_detail_label = _label("金纹压纹", Vector2(754, 799), 21)
	gold_slider = _slider(Vector2(890, 806), DEFAULT_GOLD)
	gold_slider.value_changed.connect(_set_detail_strength)
	status = _label("", Vector2(48, 858), 20)
	var save := Button.new()
	save.name = "SaveReliefSettings"
	save.text = "保存"
	save.position = Vector2(1076, 851) # 保存与恢复默认并排
	save.size = Vector2(150, 44) # 保存按钮尺寸
	save.pressed.connect(save_settings)
	add_child(save)
	var reset := Button.new()
	reset.name = "ResetReliefDefaults"
	reset.text = "恢复默认"
	reset.position = Vector2(1238, 851)
	reset.size = Vector2(150, 44) # 恢复按钮尺寸
	reset.pressed.connect(reset_defaults)
	add_child(reset)
	_label("0 = 关闭该层凹凸 · 原图保留像素取样 · 法线只改变光影", Vector2(48, 914), 18)
	_save_feedback = _label("", Vector2(760, 914), 18)
	var saved := Settings.get_relief_values()
	_detail_strengths["gold_strength"] = saved.gold_strength
	_detail_strengths["center_height_strength"] = saved.center_height_strength
	body_slider.set_value_no_signal(saved.body_strength)
	for field: Dictionary in LIGHT_FIELDS:
		lighting_controls[field.key].slider.set_value_no_signal(saved[field.key])
	select_pack(0)

func _build_lighting_panel() -> void:
	var panel := PanelContainer.new()
	lighting_panel = panel
	panel.name = "LightingPanel"
	panel.position = Vector2(594, 190) # 光照面板位于双卡之间，避免遮挡右侧效果
	panel.custom_minimum_size = Vector2(242, 470) # 光照面板的最小宽高
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182430") # 光照面板底色
	style.set_content_margin_all(14) # 面板内容与边缘的间距
	style.set_corner_radius_all(6) # 面板圆角半径
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8) # 各组光照控件的间距
	panel.add_child(layout)
	var title := Label.new()
	title.text = "光照 · 实时调整"
	title.add_theme_font_size_override("font_size", 20) # 光照面板标题字号
	layout.add_child(title)
	lighting_mode_label = Label.new()
	lighting_mode_label.add_theme_font_size_override("font_size", 16) # 当前光照模式说明字号
	layout.add_child(lighting_mode_label)
	var hints := {
		"light_angle_degrees": "看右侧亮面沿四周移动",
		"light_front": "小：反差强 / 大：柔和",
		"light_brightness": "让右侧卡包变暗／变亮",
		"light_mouse_influence": "0%固定 / 100%鼠标反侧",
	}
	for field: Dictionary in LIGHT_FIELDS:
		var row := VBoxContainer.new()
		layout.add_child(row)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 18) # 参数名称和值的字号
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = "Lighting_" + str(field.key)
		slider.custom_minimum_size = Vector2(214, 28) # 光照滑块宽高
		slider.min_value = field.min
		slider.max_value = field.max
		slider.step = field.step
		slider.value = field.default
		slider.tooltip_text = field.tip
		row.add_child(slider)
		var hint := Label.new()
		hint.text = hints[field.key]
		hint.add_theme_font_size_override("font_size", 15) # 参数直接作用的提示字号
		row.add_child(hint)
		lighting_controls[field.key] = {"slider": slider, "label": label, "hint": hint}
		slider.value_changed.connect(func(_value: float): _update_lighting())
	var help := Label.new()
	help.text = "0°右 / 90°下\n180°左 / 270°上\n调灯时保留检视姿态"
	help.add_theme_font_size_override("font_size", 16) # 光源方向与鼠标混合说明字号
	layout.add_child(help)

func _update_lighting() -> void:
	_save_feedback.text = ""
	for field: Dictionary in LIGHT_FIELDS:
		var slider: HSlider = lighting_controls[field.key].slider
		var label: Label = lighting_controls[field.key].label
		label.text = "%s  %s" % [field.label, str(field.format) % slider.value]
		sample.effect.set_shader_parameter(field.key, slider.value * float(field.scale))
	var mouse_percent: float = lighting_controls.light_mouse_influence.slider.value
	var direction: Dictionary = lighting_controls.light_angle_degrees
	direction.slider.editable = mouse_percent < 100.0
	direction.label.modulate = Color.WHITE if mouse_percent < 100.0 else Color("82909e")
	if mouse_percent >= 100.0:
		direction.label.text = "方向由鼠标接管"
		direction.hint.text = "降低鼠标影响后可调方向"
	else:
		direction.hint.text = "看右侧亮面沿四周移动"
	lighting_mode_label.text = "当前：固定灯光" if is_zero_approx(mouse_percent) else ("当前：鼠标反侧受光" if mouse_percent >= 100.0 else "当前：混合光照 %.0f%%" % mouse_percent)

func reset_lighting() -> void:
	for field: Dictionary in LIGHT_FIELDS:
		var slider: HSlider = lighting_controls[field.key].slider
		slider.set_value_no_signal(field.default)
	_update_lighting()

func reset_defaults() -> void:
	_detail_strengths["gold_strength"] = DEFAULT_GOLD
	_detail_strengths["center_height_strength"] = DEFAULT_SEAL
	set_strengths(DEFAULT_BODY, float(_detail_strengths.get(_detail_parameter, 0.0)))
	reset_lighting()

func save_settings() -> void:
	var values := _detail_strengths.duplicate()
	values["body_strength"] = body_slider.value
	for field: Dictionary in LIGHT_FIELDS:
		values[field.key] = lighting_controls[field.key].slider.value
	var error := Settings.save_relief(values)
	_save_feedback.text = "已保存 · 正式卡包已应用" if error == OK else "保存失败（%d）· 可重试" % error

func select_pack(index: int) -> void:
	pack_selector.select(index)
	var force := sample.force if is_instance_valid(sample) else Vector2.ZERO
	for surface: InspectionCardSurface in [original, sample]:
		if is_instance_valid(surface):
			remove_child(surface)
			surface.queue_free()
	var entry: Dictionary = PACK_SAMPLES[index]
	var wrapper := entry.texture as Texture2D
	original = _pack(REFERENCE_ORIGIN, wrapper)
	original.effect.set_shader_parameter("use_flash", false)
	original.effect.set_shader_parameter("use_pack_foil", true)
	sample = _pack(SAMPLE_ORIGIN, wrapper)
	sample.effect = PackArt.create_relief(sample.size, wrapper, RELIEF)
	sample.material = sample.effect
	original.set_pointer_force(force)
	sample.set_pointer_force(force)
	_detail_parameter = String(entry.get("detail", ""))
	gold_slider.editable = not _detail_parameter.is_empty()
	_detail_label.text = "火漆浮雕" if _detail_parameter == "center_height_strength" else ("金纹压纹" if gold_slider.editable else "袋身单层")
	set_strengths(body_slider.value, float(_detail_strengths.get(_detail_parameter, 0.0)))
	set_debug_view(view_selector.selected)
	_update_lighting()

func _pack(origin: Vector2, wrapper: Texture2D) -> InspectionCardSurface:
	var art: Control
	if wrapper == null:
		art = ActionArt.new()
		art.configure(CardData.ActionType.MELEE)
	else:
		var image := TextureRect.new()
		image.texture = wrapper
		image.size = wrapper.get_size()
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art = image
	add_child(art)
	var surface := Surface.new()
	add_child(surface)
	surface.setup_art(art, Vector2.ZERO)
	surface.position = origin + (Vector2(PACK.get_size()) - surface.size) * PACK_SCALE * 0.5
	surface.scale = Vector2.ONE * PACK_SCALE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_process(false)
	return surface

func _label(text: String, origin: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = origin
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label

func _slider(origin: Vector2, initial: float, parameter: String = "") -> HSlider:
	var slider := HSlider.new()
	slider.position = origin
	slider.size = Vector2(480, 30) # 每个凹凸滑块的可拖动宽高
	slider.min_value = 0.0
	slider.max_value = Settings.RELIEF_MAX_STRENGTH
	slider.step = Settings.RELIEF_STRENGTH_STEP
	slider.value = initial
	if not parameter.is_empty():
		slider.value_changed.connect(func(value: float):
			sample.effect.set_shader_parameter(parameter, value)
			_update_status())
	add_child(slider)
	return slider

func set_strengths(body: float, gold: float) -> void:
	body_slider.set_value_no_signal(body)
	gold_slider.set_value_no_signal(gold)
	sample.effect.set_shader_parameter("body_strength", body_slider.value)
	_set_detail_strength(gold_slider.value)

func _set_detail_strength(value: float) -> void:
	if not _detail_parameter.is_empty():
		_detail_strengths[_detail_parameter] = value
		sample.effect.set_shader_parameter(_detail_parameter, value)
	_update_status()

func _update_status() -> void:
	if is_instance_valid(status):
		_save_feedback.text = ""
		var detail := "    %s %.2f" % [_detail_label.text, gold_slider.value] if gold_slider.editable else ""
		status.text = "袋身 %.2f%s    ｜    %s" % [body_slider.value, detail, VIEW_NAMES[view_selector.selected]]

func set_debug_view(index: int) -> void:
	view_selector.select(index)
	sample.effect.set_shader_parameter("debug_view", index)
	_update_status()

func fit_to_host(host_size: Vector2) -> void:
	# 缩放整个调试画布，鼠标继续使用节点本地坐标，不改变游戏窗口的显示倍率。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = CANVAS_SIZE
	scale = Vector2.ONE * minf(host_size.x / CANVAS_SIZE.x, host_size.y / CANVAS_SIZE.y)
	position = (host_size - CANVAS_SIZE * scale) * 0.5

func prepare_close() -> void:
	set_process(false)

func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled() or view_selector.get_popup().visible or pack_selector.get_popup().visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_requested.emit()

func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if lighting_panel.get_rect().has_point(get_local_mouse_position()):
		target = sample.force
	for surface: InspectionCardSurface in [original, sample]:
		var pointer := surface.get_local_mouse_position()
		if Rect2(Vector2.ZERO, surface.size).has_point(pointer):
			target = (pointer / surface.size - Vector2(0.5, 0.5)) * 2.0
	original.update_pointer_force(target, delta)
	sample.update_pointer_force(target, delta)
