class_name EventCardView
extends Button

## 路径牌只负责牌面显示；选择与奖励仍由迷宫协调器提交。
const FRONT: Texture2D = preload("res://assets/ui/shop_event_20261020/event_front.png")
const BACK: Texture2D = preload("res://assets/ui/shop_event_20261020/event_back.png")
const BACK_MARK: Texture2D = preload("res://assets/events/card_back.png")
const FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const CARD_SIZE := Vector2(166, 136) # 事件牌原生尺寸；三选一通过节点scale统一放大2倍
const TITLE_FONT_SIZE: int = 13 # 牌面底部名称字号
var definition: Dictionary = {}
var face_up: bool = false:
	set(value):
		face_up = value
		queue_redraw()
var artwork: Texture2D


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	artwork = load(_art_path()) as Texture2D
	queue_redraw()


func _art_path() -> String:
	if definition.has("art"):
		return String(definition.art)
	match String(definition.get("reward", definition.get("kind", ""))):
		"gold": return "res://assets/ui/currency/gold_coin.png"
		"emblem": return "res://assets/card_ui/status/emblems/宝石.png"
		"wound": return "res://assets/stats/health.png"
		"pack": return "res://assets/card_ui/shop/sticker_pack_base.png"
		"enhance_card": return "res://assets/stats/armor.png"
		"shop": return "res://assets/card_ui/status/emblems/金币袋.png"
		"battle": return "res://assets/card_ui/status/emblems/长剑.png"
	return "res://assets/card_ui/status/emblems/盾牌Ⅰ.png"


func _draw() -> void:
	draw_texture_rect(FRONT, Rect2(Vector2.ZERO, CARD_SIZE), false)
	if face_up:
		if artwork != null:
			var factor := minf(144.0 / artwork.get_width(), 100.0 / artwork.get_height()) # 图片区等比缩放，保留原图像素
			var art_size := artwork.get_size() * factor
			draw_texture_rect(artwork, Rect2(Vector2(83, 55) - art_size * 0.5, art_size), false)
		var title := String(definition.get("name", "迷宫商人" if definition.get("kind") == "shop" else "战斗遭遇"))
		draw_string(FONT, Vector2(8, 129), title, HORIZONTAL_ALIGNMENT_CENTER, 150, TITLE_FONT_SIZE, Color(0.98, 0.91, 0.73))
	else:
		draw_texture_rect(BACK, Rect2(Vector2.ZERO, CARD_SIZE), false)
		draw_texture_rect(BACK_MARK, Rect2(35, 8, 96, 96), false)
	if is_hovered() and not disabled:
		draw_rect(Rect2(Vector2(1, 1), CARD_SIZE - Vector2(2, 2)), Color("f6d99a"), false, 2.0)
