extends Button

## 事件选项沿用 Godot 的悬停提示，只替换提示内容和纸条外观。
const PAPER: Texture2D = preload("res://assets/ui/shop_event_20261020/event_outcome_paper.png")
const Typography = preload("res://scripts/ui/ui_typography.gd")
const KeywordMotion = preload("res://scripts/ui/keyword_text_effect.gd")
const CORNER_WIDTH := 17.0 # 保留纸条两端的折角和缺口
const CORNER_HEIGHT := 6.0 # 保留上下边缘的锯齿与缺口高度
const TEXT_INSET := Vector2(8, 6) # 文字离纸条边缘的最小距离
const MAX_TEXT_WIDTH := 360.0 # 过宽的说明在纸条内部按此宽度折行
const FONT_SIZE := 14 # 事件概率与结果的字号
const INK := Color("392619") # 浅纸条上的深色正文
static var _tooltip_theme: Theme
var _lines: Array[Dictionary] = []
var _reference_caption: RichTextLabel


func _ready() -> void:
	if _tooltip_theme == null:
		_tooltip_theme = Theme.new()
		# Godot 会在自定义内容外再套一个提示面板，留空才能露出纸条的缺角。
		_tooltip_theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	theme = _tooltip_theme


func set_reference_caption(label: RichTextLabel) -> void:
	_reference_caption = label
	label.name = "StoryOptionCaption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_outcome_lines(lines: Array[Dictionary]) -> void:
	if is_instance_valid(_reference_caption):
		_reference_caption.modulate.a = 0.5 if disabled else 1.0
	_lines = lines
	var plain: Array[String] = []
	for line: Dictionary in lines:
		plain.append(String(line.prefix) + String(line.text))
	tooltip_text = "\n".join(plain)


func _make_custom_tooltip(_for_text: String) -> Control:
	var style := StyleBoxTexture.new()
	style.texture = PAPER
	for side: Side in [SIDE_LEFT, SIDE_RIGHT]:
		style.set_texture_margin(side, CORNER_WIDTH)
		style.set_content_margin(side, TEXT_INSET.x)
	for side: Side in [SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, CORNER_HEIGHT)
		style.set_content_margin(side, TEXT_INSET.y)
	var paper := PanelContainer.new()
	paper.name = "EventOutcomePaper"
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	paper.custom_minimum_size = PAPER.get_size()
	paper.add_theme_stylebox_override("panel", style)
	var label := RichTextLabel.new()
	label.name = "OutcomeText"
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.bbcode_enabled = true
	label.install_effect(KeywordMotion.new())
	var font := Typography.font()
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_override("bold_font", KeywordMotion.bold_font(font))
	for kind: String in ["normal_font_size", "bold_font_size"]:
		label.add_theme_font_size_override(kind, FONT_SIZE)
	label.add_theme_color_override("default_color", INK)
	var width := PAPER.get_width() - 2.0 * TEXT_INSET.x
	for index: int in _lines.size():
		var line := _lines[index]
		var text := String(line.prefix) + String(line.text)
		for part: String in text.split("\n"):
			width = maxf(width, ceilf(font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) + 2.0)
		if index > 0: label.newline()
		label.add_text(line.prefix)
		if line.get("unknown", false):
			label.append_text("[b][keyword]？[/keyword][/b]")
		else:
			label.add_text(line.text)
	label.custom_minimum_size.x = minf(width, MAX_TEXT_WIDTH)
	paper.add_child(label)
	return paper
