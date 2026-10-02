extends HBoxContainer

## 商店金额独立绘制，不把25像素图片混入正文的字体度量。
const COIN: Texture2D = preload("res://assets/ui/currency/gold_coin.png")
const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
const NUMBER_SCALE := 2.0 # 大号14像素卢恩数字以整数2倍显示，接近25像素金币高度
const GAP := 5 # 金币、数字及文字之间的像素间距
const TEXT_SIZE := 20 # 商店金额旁的简短说明字号

func configure(values: Array[int], caption: String = "") -> void:
	name = "ShopPrice"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", GAP)
	if not caption.is_empty():
		var label := Label.new()
		label.text = caption
		label.add_theme_font_size_override("font_size", TEXT_SIZE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	var coin := TextureRect.new()
	coin.name = "Coin"
	coin.texture = COIN
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	coin.custom_minimum_size = COIN.get_size()
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin)
	for index: int in values.size():
		if index > 0:
			var slash := Label.new()
			slash.text = "/"
			slash.add_theme_font_size_override("font_size", TEXT_SIZE)
			slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(slash)
		var number := RuneNumber.new()
		number.text = str(values[index])
		number.scale = Vector2.ONE * NUMBER_SCALE
		var frame := Control.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.custom_minimum_size = number.get_rendered_size() * NUMBER_SCALE
		frame.add_child(number)
		add_child(frame)
