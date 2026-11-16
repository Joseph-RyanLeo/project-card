extends RichTextEffect

## 两种频率叠加，逐字产生不规则的轻微上下浮动，不改变文字排版或命中范围。
var bbcode := "keyword"
const Help = preload("res://scripts/data/card_keyword_help.gd")
const AMPLITUDE: float = 0.80 # 每个关键词字符最多约1逻辑像素的纵向位移
const SPEED: float = 2.7 # 主要浮动频率，避免整段文字快速抖动

static func format_text(text: String, scale: float = 1.0) -> String:
	for word: String in Help.in_text(text):
		text = text.replace(word, "[b][keyword scale=%s]%s[/keyword][/b]" % [scale, word])
	return text


static func bold_font(font: Font) -> FontVariation:
	var bold := FontVariation.new()
	bold.base_font = font.base_font if font is FontVariation else font
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 800.0}
	return bold


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var phase := float(char_fx.relative_index) * 2.399
	var time := char_fx.elapsed_time
	var scale := float(char_fx.env.get("scale", 1.0))
	char_fx.offset.y += (sin(time * SPEED + phase) * 0.7 + sin(time * 4.13 + phase * 0.63) * 0.3) * AMPLITUDE * scale
	return true
