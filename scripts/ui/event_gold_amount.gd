extends RichTextLabel

## 金额单独成行，排版锚点固定，只有字形沿用卡牌关键词的浮动。
const KeywordMotion = preload("res://scripts/ui/keyword_text_effect.gd")
const FONT_SIZE := 16 # 与事件结果正文使用同一字号
const PREFIX := "获得"
const GOLD_INK := Color("ae751b") # 浅纸面上的深金色金额
var _amount_center := Vector2.ZERO


func set_amount(amount: int, font: Font) -> void:
	var bold := KeywordMotion.bold_font(font)
	var text_amount := "%d枚金币" % amount
	var prefix_width := font.get_string_size(PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var amount_width := bold.get_string_size(text_amount, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_amount_center = Vector2(prefix_width + amount_width * 0.5, font.get_height(FONT_SIZE) * 0.5)
	name = "EventGoldAmount"
	fit_content = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbcode_enabled = true
	install_effect(KeywordMotion.new())
	add_theme_font_override("normal_font", font)
	add_theme_font_override("bold_font", bold)
	add_theme_font_size_override("normal_font_size", FONT_SIZE)
	add_theme_font_size_override("bold_font_size", FONT_SIZE)
	add_theme_color_override("default_color", Color("513124"))
	text = "%s[color=#%s][b][keyword]%s[/keyword][/b][/color]" % [PREFIX, GOLD_INK.to_html(false), text_amount]


func amount_canvas_origin() -> Vector2:
	return get_global_transform_with_canvas() * _amount_center
