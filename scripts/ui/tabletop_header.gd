extends Control

## 新棋盘顶栏读取真实迷宫状态，不维护另一份金币、天数或失败保护。
const Art = preload("res://scripts/ui/tabletop_art.gd")
const HUD_DIR := "res://assets/ui/board_revision_20261019/"
const FONT: Font = preload("res://assets/fonts/chill_7.ttf")
var main: Control
var _signature: Array = []
var _header: Texture2D
var _marker: Texture2D
var _day_marker: Texture2D
var _shield: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(902, 39) # 顶栏只占用棋盘顶部，不遮挡内容输入
	_header = Art.atlas("event_reference.png", Rect2(0, 0, 902, 39))
	_marker = load(HUD_DIR + "floor_marker.png")
	_shield = load(HUD_DIR + "life_shield.png")

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or main == null or main.maze_controller == null: return
	var maze: Node = main.maze_controller
	var signature: Array = [maze.run.day, maze.run.round_index, int(maze.content.get("floor", 1)), main.run_reward_state.gold, maze.run.failure_protection]
	if signature == _signature: return
	_signature = signature
	_day_marker = load(HUD_DIR + ["day_sun_red", "day_sun_gold", "day_sun_red", "day_moon"][clampi(maze.run.round_index, 0, 3)] + ".png")
	queue_redraw()

func _draw() -> void:
	if _header == null: return
	draw_texture(_header, Vector2.ZERO)
	if _signature.is_empty(): return
	draw_texture(_marker, Vector2(105 + 14 * clampi(int(_signature[2]) - 1, 0, 2), 18))
	if int(_signature[0]) in range(1, 9):
		draw_texture(_day_marker, Vector2(213 + 14 * (int(_signature[0]) - 1), 18))
	for index: int in clampi(int(_signature[4]), 0, 2):
		draw_texture_rect(_shield, Rect2(663 + index * 17, 14, 14, 14), false)
	draw_string(FONT, Vector2(731, 27), str(_signature[3]), HORIZONTAL_ALIGNMENT_CENTER, 56, 15, Color("ead2ae"))
