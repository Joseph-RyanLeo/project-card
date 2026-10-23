extends RefCounted

## 商店与事件共用原生素材、图集按钮；AtlasTexture只引用区域，不改写源图。
const DIR := "res://assets/ui/shop_event_20261020/"
const BOARD_SIZE := Vector2(902, 351) # 商店与事件棋盘的原生尺寸
const SCREEN_POSITION := Vector2(189, 0) # 原稿顶边完整显示，不再叠加世界视角和素材的上移补偿

static func atlas(file: String, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load(DIR + file)
	texture.region = region
	return texture

static func art(parent: Node, file: String, origin: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = load(DIR + file)
	view.position = origin
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view

static func button(parent: Node, title: String, origin: Vector2, texture: Texture2D, callback: Callable) -> Button:
	var view := Button.new()
	view.text = title
	view.position = origin
	view.size = texture.get_size()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxTexture.new()
		style.texture = texture
		view.add_theme_stylebox_override(state, style)
	view.add_theme_font_override("font", preload("res://assets/fonts/chill_7.ttf"))
	view.add_theme_font_size_override("font_size", 14) # 新棋盘小按钮文字字号
	view.add_theme_color_override("font_color", Color("ead2ae"))
	view.add_theme_color_override("font_hover_color", Color("fff1ca"))
	view.add_theme_color_override("font_disabled_color", Color("827162"))
	view.pressed.connect(callback)
	parent.add_child(view)
	return view
