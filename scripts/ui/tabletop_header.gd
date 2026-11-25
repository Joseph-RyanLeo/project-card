extends Control

## 新棋盘顶栏读取真实迷宫状态，不维护另一份金币、天数或失败保护。
const Art = preload("res://scripts/ui/tabletop_art.gd")
const HUD_DIR := "res://assets/ui/board_revision_20261019/"
const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
const GOLD_ICON: Texture2D = preload("res://assets/ui/board_revision_20261019/gold_icon.png")
const GOLD_TRACK: Texture2D = preload("res://assets/ui/board_revision_20261019/gold_track.png")
const GOLD_FLASH_SHADER = preload("res://shaders/emblem_fusion_white.gdshader")
const GOLD_ICON_POSITION := Vector2(788, 7) # 棋盘原图上金币的左上角，与镜像金币素材像素对齐
const GOLD_TRACK_POSITION := Vector2(723, 8) # 底板原图中金额槽的左上角
const HEADER_WOOD := Color("824d3a") # 取自顶栏金币右侧的木板底色
const GOLD_BUMP_HEIGHT := 3.0 # 落袋时金币图标向上弹起的整数像素数
const GOLD_BUMP_SCALE := 1.16 # 落袋时金币图标保持比例放大的峰值
const GOLD_BUMP_TIME := 0.15 # 金币图标从轻弹到回位的秒数
const GOLD_FLASH_TIME := 0.075 # 白色闪光消退的秒数，比轻弹短
var main: Control
var _signature: Array = []
var _header: Texture2D
var _marker: Texture2D
var _day_rolling := false
var _shield: Texture2D
var _gold: RuneNumber
var _gold_icon: TextureRect
var _gold_flash := ShaderMaterial.new()
var _gold_bump: Tween

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
	_gold_icon = TextureRect.new()
	_gold_icon.name = "GoldLandingIcon"
	_gold_icon.texture = GOLD_ICON
	_gold_icon.flip_h = true
	_gold_icon.position = GOLD_ICON_POSITION
	_gold_icon.size = GOLD_ICON.get_size()
	_gold_icon.pivot_offset = _gold_icon.size * 0.5
	_gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_flash.shader = GOLD_FLASH_SHADER
	_gold_icon.material = _gold_flash
	_gold_icon.hide()
	add_child(_gold_icon)

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or main == null: return
	_update_gold_amount()
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

func gold_target() -> Vector2:
	return get_global_transform_with_canvas() * (GOLD_ICON_POSITION + GOLD_ICON.get_size() * 0.5)

func _update_gold_amount() -> void:
	_gold.text = str(main.maze_controller.displayed_event_gold() if main.maze_controller != null else main.run_reward_state.gold)
	_gold.position = Vector2(roundf(755 - _gold.size.x * 0.5), 15) # 大卢恩金额按实际字形宽度居中

func bump_gold_icon() -> void:
	_update_gold_amount()
	if is_instance_valid(_gold_bump): _gold_bump.kill()
	_gold_icon.show()
	_set_gold_icon_impact(0.0)
	_gold_bump = create_tween()
	_gold_bump.tween_method(_set_gold_icon_impact, 0.0, GOLD_BUMP_TIME, GOLD_BUMP_TIME)
	_gold_bump.tween_callback(_gold_icon.hide)

func _set_gold_icon_impact(elapsed: float) -> void:
	var bump := 1.0 - elapsed / GOLD_BUMP_TIME
	var flash := maxf(0.0, 1.0 - elapsed / GOLD_FLASH_TIME)
	_gold_icon.position.y = GOLD_ICON_POSITION.y - roundf(GOLD_BUMP_HEIGHT * bump * bump)
	_gold_icon.scale = Vector2.ONE * lerpf(1.0, GOLD_BUMP_SCALE, bump * bump)
	_gold_flash.set_shader_parameter("white_amount", flash * flash)
	queue_redraw()

func _draw() -> void:
	if _header == null: return
	draw_texture(_header, Vector2.ZERO)
	if _gold_icon.visible:
		# 补出原金币下面的木纹和金额槽，再绘制独立的弹起图标。
		var base := Rect2(GOLD_ICON_POSITION, GOLD_ICON.get_size())
		draw_rect(base, HEADER_WOOD)
		var exposed_track := base.intersection(Rect2(GOLD_TRACK_POSITION, GOLD_TRACK.get_size()))
		draw_texture_rect_region(GOLD_TRACK, exposed_track, Rect2(exposed_track.position - GOLD_TRACK_POSITION, exposed_track.size))
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
