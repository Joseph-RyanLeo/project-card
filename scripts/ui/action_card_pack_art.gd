extends Control

## 行动方式定向小包：像素包装轮廓和原行动图标组合，不另生成位图素材。
const PACK_SIZE := Vector2(115, 174) # 定向小包与普通小包共用完整1倍包装尺寸
const ACTION_ICON_SCALE: float = 3.0 # 行动图标按原素材3倍显示
const ACTION_TEXTURES: Array[Texture2D] = [
	preload("res://assets/actions/action_melee.png"),
	preload("res://assets/actions/action_ranged.png"),
	preload("res://assets/actions/action_magic.png"),
	preload("res://assets/actions/action_heal.png"),
	preload("res://assets/actions/action_defense.png"),
]
const BODY_COLOR := Color("2678c9") # 包装主体蓝色
const SEAL_COLOR := Color("68c1f5") # 包装封口浅蓝色
const EDGE_COLOR := Color("152033") # 包装像素轮廓颜色

func configure(action_type: int) -> void:
	size = PACK_SIZE
	custom_minimum_size = PACK_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "ActionIcon"
	icon.texture = ACTION_TEXTURES[action_type]
	icon.size = icon.texture.get_size() * ACTION_ICON_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = ((PACK_SIZE - icon.size) * 0.5).floor()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(4, 0, size.x - 8, size.y), EDGE_COLOR)
	draw_rect(Rect2(6, 2, size.x - 12, size.y - 4), BODY_COLOR)
	for y: int in [3, 7, int(size.y) - 9, int(size.y) - 5]:
		draw_rect(Rect2(6, y, size.x - 12, 2), SEAL_COLOR)
	for x: int in range(9, int(size.x) - 8, 8):
		draw_rect(Rect2(x, 0, 4, 2), BODY_COLOR)
		draw_rect(Rect2(x, size.y - 2, 4, 2), BODY_COLOR)
	draw_line(Vector2(8, 14), Vector2(8, size.y - 14), SEAL_COLOR, 2.0)
	draw_line(Vector2(size.x - 8, 14), Vector2(size.x - 8, size.y - 14), SEAL_COLOR, 2.0)
	for y: int in [13, int(size.y) - 13]:
		draw_line(Vector2(7, y), Vector2(18, y + (9 if y == 13 else -9)), SEAL_COLOR, 2.0)
		draw_line(Vector2(size.x - 8, y), Vector2(size.x - 19, y + (9 if y == 13 else -9)), SEAL_COLOR, 2.0)
