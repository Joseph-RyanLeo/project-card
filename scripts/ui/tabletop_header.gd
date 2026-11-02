extends Control

## 新棋盘顶栏读取真实迷宫状态，不维护另一份金币、天数或失败保护。
const Art = preload("res://scripts/ui/tabletop_art.gd")
const HUD_DIR := "res://assets/ui/board_revision_20261019/"
const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
var main: Control
var _signature: Array = []
var _header: Texture2D
var _marker: Texture2D
var _day_rolling := false
var _shield: Texture2D
var _gold: RuneNumber

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(902, 39) # 顶栏只占用棋盘顶部，不遮挡内容输入
	_header = Art.atlas("event_reference.png", Rect2(0, 0, 902, 39))
	_marker = load(HUD_DIR + "floor_marker.png")
	_shield = load(HUD_DIR + "life_shield.png")
	_gold = RuneNumber.new()
	_gold.name = "GoldAmount"
	_gold.character_spacing = -1 # 相邻数字仅重合黑色描边，七位余额仍能完整放进金币槽
	add_child(_gold)

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or main == null: return
	_gold.text = str(main.run_reward_state.gold)
	_gold.position = Vector2(roundf(755 - _gold.size.x * 0.5), 15) # 大卢恩金额按实际字形宽度居中
	if main.maze_controller == null: return
	var maze: Node = main.maze_controller
	var signature: Array = [maze.run.day, maze.run.round_index, int(maze.content.get("floor", 1)), main.run_reward_state.gold, maze.run.failure_protection]
	var hud: Control = maze._status
	var rolling: bool = is_instance_valid(hud._roll) and hud._roll.is_running()
	if rolling or _day_rolling: queue_redraw()
	_day_rolling = rolling
	if signature == _signature: return
	_signature = signature
	queue_redraw()

func _draw() -> void:
	if _header == null: return
	draw_texture(_header, Vector2.ZERO)
	if _signature.is_empty(): return
	draw_texture(_marker, Vector2(105 + 14 * clampi(int(_signature[2]) - 1, 0, 2), 18))
	# 复用世界顶栏同一份滚轮进度；棋盘重建也不会重启或跳过日内切换。
	var hud: Control = main.maze_controller._status
	for index: int in hud._slots.size():
		for marker: TextureRect in [hud._fronts[index], hud._backs[index]]:
			if marker.texture == null: continue
			var offset := Vector2(0, roundf(marker.position.y))
			var clipped := Rect2(offset, hud.MARKER_SIZE).intersection(Rect2(Vector2.ZERO, hud.MARKER_SIZE))
			if clipped.has_area():
				draw_texture_rect_region(marker.texture, Rect2(Vector2(213 + 14 * index, 18) + clipped.position, clipped.size), Rect2(clipped.position - offset, clipped.size))
	for index: int in clampi(int(_signature[4]), 0, 2):
		draw_texture_rect(_shield, Rect2(663 + index * 17, 14, 14, 14), false)
