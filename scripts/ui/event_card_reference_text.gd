extends RichTextLabel

## 文案中的随从引用绑定卡牌实例；同名随从用各自的链接编号。
const KeywordMotion = preload("res://scripts/ui/keyword_text_effect.gd")
const LINK_INK := Color("17558e") # 浅色事件纸上的随从名字
const OPTION_LINK_INK := Color("9accff") # 深色选项条上的随从名字
var _parts: Array[Dictionary] = []


static func split_references(source: String, references: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var used := {}
	var start := 0
	while start < source.length():
		var nearest := source.length()
		var marker := ""
		for candidate: String in references:
			var at := source.find(candidate, start)
			if at >= 0 and (at < nearest or (at == nearest and candidate.length() > marker.length())):
				nearest = at
				marker = candidate
		if nearest > start: parts.append({"text": source.substr(start, nearest - start)})
		if marker.is_empty(): break
		var candidates: Array = references[marker]
		var index := int(used.get(marker, 0))
		parts.append(candidates[mini(index, candidates.size() - 1)])
		used[marker] = index + 1
		start = nearest + marker.length()
	return parts


static func plain_text(parts: Array[Dictionary]) -> String:
	var pieces: Array[String] = []
	for part: Dictionary in parts: pieces.append(part.text)
	return "".join(pieces)


func configure(parts: Array[Dictionary], font_size: int, ink: Color, in_option: bool, table: Control) -> void:
	_parts = parts
	bbcode_enabled = true
	fit_content = not in_option
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("normal_font_size", font_size)
	add_theme_color_override("default_color", ink)
	add_theme_constant_override("line_separation", 3) # 随从名字与普通事件段落使用相同的行距
	install_effect(KeywordMotion.new())
	var link_color := (OPTION_LINK_INK if in_option else LINK_INK).to_html(false)
	for index: int in parts.size():
		var part := parts[index]
		if part.get("card") == null:
			add_text(part.text)
		else:
			var escaped := String(part.text).replace("[", "[lb]")
			append_text("[url=%d][color=#%s][keyword]%s[/keyword][/color][/url]" % [index, link_color, escaped])
	meta_hover_started.connect(func(meta: Variant):
		var part := _parts[int(meta)]
		table.show_card_reference(self, part.card, part.get("owned")))
	meta_hover_ended.connect(func(_meta: Variant): table.hide_card_reference(self))
	mouse_exited.connect(func(): table.hide_card_reference(self))
