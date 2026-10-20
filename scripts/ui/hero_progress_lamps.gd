extends Control

## 只显示英雄进度，不保存第二份经验或参与升级结算。
const EMPTY: Texture2D = preload("res://assets/ui/hero_progress_20261019/progress_empty.png")
const LEVEL_LIT: Texture2D = preload("res://assets/ui/hero_progress_20261019/level_lit.png")
const EXPERIENCE_LIT: Texture2D = preload("res://assets/ui/hero_progress_20261019/experience_lit.png")
const EXPERIENCE_UNUSED: Texture2D = preload("res://assets/ui/hero_progress_20261019/experience_unused.png")
const LEVEL_COUNT := 10 # 上排等级灯的总数
const EXPERIENCE_COUNT := 18 # 下排经验灯总数，匹配9级升10级所需18经验
const LEVEL_ORIGIN := Vector2(7, 0) # 第一盏等级亮灯相对空底槽的左上角
const LEVEL_STEP := 14.0 # 等级灯之间的像素步长
const EXPERIENCE_ORIGIN := Vector2(14, 18) # 经验条缩短14像素并居中后，第一盏灯相对等级底槽的位置
const EXPERIENCE_STEP := 7.0 # 经验灯之间的像素步长
const EXPERIENCE_TRACK_OFFSET := Vector2(7, 17) # 窄经验底槽相对完整素材的位置
const EXPERIENCE_TRACK_SIZE := Vector2(139, 8) # 18盏经验灯底槽的原生拼接尺寸
const EXPERIENCE_CAP_WIDTH := 7.0 # 保留右端圆角的原生像素宽度
var _level := 1
var _earned := 0
var _required := 0


func _init() -> void:
	size = Vector2(153, 25) # 两行灯底槽的原生尺寸
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


func sync(hero: HeroProgressState) -> void:
	_level = hero.level
	_earned = hero.get_current_level_experience()
	_required = hero.get_next_level_experience_required()
	tooltip_text = (
		"等级%d（满级）\n累计经验%d" % [_level, hero.experience]
		if _required == 0
		else "等级%d\n本级经验%d/%d\n累计经验%d" % [_level, _earned, _required, hero.experience]
	)
	queue_redraw()


func _draw() -> void:
	draw_texture_rect_region(EMPTY, Rect2(0, 0, 153, 15), Rect2(0, 0, 153, 15))
	# 删除最后两格，只拼接原图右端圆角，不缩放任一像素。
	var left_width := EXPERIENCE_TRACK_SIZE.x - EXPERIENCE_CAP_WIDTH
	draw_texture_rect_region(
		EMPTY, Rect2(EXPERIENCE_TRACK_OFFSET, Vector2(left_width, EXPERIENCE_TRACK_SIZE.y)),
		Rect2(0, 17, left_width, EXPERIENCE_TRACK_SIZE.y)
	)
	draw_texture_rect_region(
		EMPTY, Rect2(EXPERIENCE_TRACK_OFFSET + Vector2(left_width, 0), Vector2(EXPERIENCE_CAP_WIDTH, EXPERIENCE_TRACK_SIZE.y)),
		Rect2(153 - EXPERIENCE_CAP_WIDTH, 17, EXPERIENCE_CAP_WIDTH, EXPERIENCE_TRACK_SIZE.y)
	)
	for index: int in mini(_level, LEVEL_COUNT):
		draw_texture(LEVEL_LIT, LEVEL_ORIGIN + Vector2(index * LEVEL_STEP, 0))
	for index: int in EXPERIENCE_COUNT:
		var at := EXPERIENCE_ORIGIN + Vector2(index * EXPERIENCE_STEP, 0)
		if _required == 0 or index < _earned:
			draw_texture(EXPERIENCE_LIT, at)
		elif index >= _required:
			draw_texture(EXPERIENCE_UNUSED, at)
