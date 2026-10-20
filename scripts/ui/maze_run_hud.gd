extends Control

## 顶栏只读取迷宫数据；滚轮动画不改变天数、轮次或奖励。
const DIR := "res://assets/ui/board_revision_20261019/"
const HERO_DIR := "res://assets/ui/hero_progress_20261019/"
const HeroProgressLampsScript = preload("res://scripts/ui/hero_progress_lamps.gd")
const FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const ROLL_SECONDS: float = 0.24 # 日内与跨天图标滚动切换的时长
const MARKER_SIZE := Vector2(13, 13) # 顶栏亮点的原生尺寸与滚轮窗口大小
const HERO_WORLD_POSITION := Vector2(1084, 749) # 英雄底板固定世界位置；视角移动只改变屏幕上的位置
const TALENT_POSITIONS: Array[Vector2] = [Vector2(47, 235), Vector2(103, 235), Vector2(47, 281), Vector2(103, 281)] # 四个天赋位按新版参考图对齐底板
const TALENT_COLORS: Array[Color] = [Color("2b7718"), Color("1e6bcd"), Color("7a25bb"), Color("e7bd55")] # 1／4／7／10级天赋选中后依次为绿、蓝、紫、金
const TALENT_EMPTY_COLOR := Color("8c8d8e") # 原稿未选择天赋的灰色
var _art: Dictionary = {}
var _slots: Array[Control] = []
var _fronts: Array[TextureRect] = []
var _backs: Array[TextureRect] = []
var _roll: Tween
var shown_day: int = -1
var shown_round: int = -1
var floor_number: int = 1
var protection: int = 2
var alive: bool = true
var _gold: Label
var _hero_label: Label
var _hero_panel: Control
var _hero_progress_lamps: HeroProgressLampsScript
var _talent_slots: Array[ColorRect] = []


func initialize(main: Control) -> void:
	name = "MazeRunHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2600 # 顶栏在事件面板和普通战场上方
	size = Vector2(1280, 34) # 世界顶部数值区范围，随WorldContent一起滚动
	for key: String in ["floor_track", "day_track", "floor_marker", "day_sun_red", "day_sun_gold", "day_moon", "floor_label", "day_label", "life_track", "gold_track", "life_shield", "life_heart", "gold_icon"]:
		_art[key] = load(DIR + key + ".png")
	for index: int in 8:
		var slot := Control.new()
		slot.name = "DaySlot%d" % (index + 1)
		slot.position = Vector2(402 + index * 14, 15) # 八天槽内亮点的左上角和间距
		slot.size = MARKER_SIZE
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)
		for views: Array[TextureRect] in [_fronts, _backs]:
			var marker := TextureRect.new()
			marker.size = MARKER_SIZE
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(marker)
			views.append(marker)
	_gold = Label.new()
	_gold.position = Vector2(918, 6) # 金币数位于底槽内，右侧留出钱币图标
	_gold.size = Vector2(58, 24) # 金币文字的显示宽高
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold.add_theme_font_override("font", FONT)
	_gold.add_theme_font_size_override("font_size", 14) # 顶栏金币字号
	_gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gold)
	var hero_panel := Control.new()
	hero_panel.name = "IoannInformationPanel"
	hero_panel.position = HERO_WORLD_POSITION
	hero_panel.size = Vector2(185, 357) # 新版变窄蓝色底板的原生尺寸
	hero_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_hero_panel = hero_panel
	main.world_content.add_child(hero_panel)
	for entry: Array in [[HERO_DIR + "hero_panel.png", Vector2.ZERO], [HERO_DIR + "ritual_outer.png", Vector2(32, 17)], [HERO_DIR + "ritual_inner.png", Vector2(41, 26)], [DIR + "hero_columns_gray.png", Vector2(5, 6)], [DIR + "hero_columns_white.png", Vector2(5, -10)]]:
		var image := TextureRect.new()
		image.texture = load(String(entry[0]))
		image.position = entry[1]
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero_panel.add_child(image)
	_hero_label = Label.new()
	_hero_label.position = Vector2(23, 145) # 新版姓名区域相对蓝板的位置
	_hero_label.size = Vector2(144, 42) # 保留实际姓名，等级经验改用下方灯条表达
	_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hero_label.add_theme_font_override("font", FONT)
	_hero_label.add_theme_font_size_override("font_size", 14) # 英雄姓名字号
	_hero_label.add_theme_color_override("font_color", Color("cda255"))
	_hero_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_panel.add_child(_hero_label)
	_hero_progress_lamps = HeroProgressLampsScript.new()
	_hero_progress_lamps.name = "HeroProgressLamps"
	_hero_progress_lamps.position = Vector2(16, 197) # 新参考图中灯槽相对蓝色底板的位置
	hero_panel.add_child(_hero_progress_lamps)
	for index: int in TALENT_POSITIONS.size():
		var slot := ColorRect.new()
		slot.name = "HeroTalent%d" % [1, 4, 7, 10][index]
		slot.position = TALENT_POSITIONS[index]
		slot.size = Vector2(36, 36) # 原稿天赋色块的原生尺寸
		slot.color = TALENT_EMPTY_COLOR
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		hero_panel.add_child(slot)
		_talent_slots.append(slot)


func sync(maze: Node, animate: bool = true) -> void:
	floor_number = int(maze.content.get("floor", 1))
	protection = maze.run.failure_protection
	alive = maze.run.battle_results.is_empty() or String(maze.run.battle_results.back().ending) not in ["ordinary_loss", "boss_loss"]
	_gold.text = str(maze._main.run_reward_state.gold)
	_hero_label.text = "伊奥恩·沃登"
	_hero_progress_lamps.sync(maze.hero)
	_hero_panel.tooltip_text = maze.hero_description()
	maze._main.player_avatar_button.tooltip_text = maze.hero_description() + "\n左键切换视角；右键查看详情"
	for index: int in _talent_slots.size():
		var level: int = [1, 4, 7, 10][index]
		var id: String = maze.hero.selected_talents.get(str(level), "")
		var slot := _talent_slots[index]
		slot.color = TALENT_EMPTY_COLOR if id.is_empty() else TALENT_COLORS[index]
		if id.is_empty():
			slot.tooltip_text = "%d级天赋：尚未选择" % level
		else:
			var talent: Dictionary = maze.rewards.config.talents[id]
			slot.tooltip_text = "%d级 · %s\n%s" % [level, talent.display_name, talent.source_text]
	set_day_marker(maze.run.day, maze.run.round_index, animate)
	queue_redraw()


func set_day_marker(day: int, round_index: int, animate: bool = true) -> void:
	if day == shown_day and round_index == shown_round:
		return
	if is_instance_valid(_roll):
		_roll.kill()
	for index: int in 8:
		_fronts[index].texture = _marker(shown_round) if index + 1 == shown_day else null
		_fronts[index].position = Vector2.ZERO
		_backs[index].texture = null
		_backs[index].position = Vector2.ZERO
	var previous_day := shown_day
	shown_day = day
	shown_round = round_index
	if not animate or previous_day < 1:
		_finish_roll()
		return
	_roll = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for index: int in 8:
		if _fronts[index].texture != null:
			_roll.tween_property(_fronts[index], "position:y", -MARKER_SIZE.y, ROLL_SECONDS)
		if index + 1 == day:
			_backs[index].texture = _marker(round_index)
			_backs[index].position.y = MARKER_SIZE.y
			_roll.tween_property(_backs[index], "position:y", 0.0, ROLL_SECONDS)
	_roll.chain().tween_callback(_finish_roll)


func _marker(round_index: int) -> Texture2D:
	return _art[["day_sun_red", "day_sun_gold", "day_sun_red", "day_moon"][clampi(round_index, 0, 3)]]


func _finish_roll() -> void:
	for index: int in 8:
		_fronts[index].texture = _marker(shown_round) if index + 1 == shown_day else null
		_fronts[index].position = Vector2.ZERO
		_backs[index].texture = null


func _draw() -> void:
	if _art.is_empty(): return
	for entry: Array in [["floor_label", Vector2(238, 16)], ["floor_track", Vector2(287, 14)], ["day_label", Vector2(363, 16)], ["day_track", Vector2(395, 14)], ["life_track", Vector2(840, 5)], ["gold_track", Vector2(912, 5)]]:
		draw_texture(_art[entry[0]], entry[1])
	_draw_mirrored_icon(_art.gold_icon, Vector2(977, 4))
	draw_texture(_art.floor_marker, Vector2(294 + 14 * clampi(floor_number - 1, 0, 2), 15))
	for index: int in clampi(protection, 0, 2):
		_draw_mirrored_icon(_art.life_shield, Vector2(851 + 18 * index, 11))
	if alive:
		_draw_mirrored_icon(_art.life_heart, Vector2(889, 7))


func _draw_mirrored_icon(texture: Texture2D, at: Vector2) -> void:
	# 向右平移一个图宽再反向绘制，保持图标占位不动并统一阴影方向。
	draw_set_transform(at + Vector2(texture.get_width(), 0), 0.0, Vector2(-1, 1))
	draw_texture(texture, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO)
