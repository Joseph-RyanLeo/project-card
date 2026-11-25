class_name EventCardView
extends Button

## 路径牌只负责牌面显示；选择与奖励仍由迷宫协调器提交。
const FRONT: Texture2D = preload("res://assets/ui/shop_event_20261020/event_front.png")
const BACK: Texture2D = preload("res://assets/ui/shop_event_20261020/event_back.png")
const BACK_MARK: Texture2D = preload("res://assets/events/card_back.png")
static var FONT: Font = preload("res://scripts/ui/ui_typography.gd").font()
const CARD_SIZE := Vector2(166, 136) # 事件牌原生尺寸；三选一通过节点scale统一放大2倍
const TITLE_FONT_SIZE: int = 14 # 牌面底部名称字号
const TAROT_FILL_RECT := Rect2(6, 7, 154, 122) # 覆盖金色内框的区域，避开底板外沿
const TAROT_FILL_COLOR := Color("824d3a") # 取自底板原有的棕色
const TAROT_ORIGIN := Vector2(-44, -23) # 全部塔罗图案共用的原生像素偏移，有效区域落在底板内
var definition: Dictionary = {}
var face_up: bool = false:
	set(value):
		face_up = value
		queue_redraw()
var artwork: Texture2D
var back_artwork: Texture2D
var tarot_back: Texture2D
var tarot_reversed := false
var _back_projection: InspectionCardSurface
var back_tilt := Vector2.ZERO:
	set(value):
		back_tilt = value
		if not is_instance_valid(_back_projection): return
		var projected := not value.is_zero_approx()
		if _back_projection.visible != projected:
			_back_projection.visible = projected
			queue_redraw()
		if projected: _back_projection.set_pointer_force(value)
const HOVER_LIFT := 7.0 # 三选一悬停抬升的原生像素数，与备战随从相同
const HOVER_SECONDS := 0.14 # 悬停抬起与落回的时长
var _choice_hover_enabled := false
var _choice_gamepad_hovered := false
var _choice_hovered := false
var _choice_lift := 0.0
var _choice_hover_tween: Tween


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(_update_choice_hover.bind(true))
	mouse_exited.connect(_update_choice_hover.bind(false))
	artwork = load(_art_path()) as Texture2D
	back_artwork = load(String(definition.back_art)) as Texture2D if definition.has("back_art") else BACK
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


func prepare_back_projection() -> void:
	var art := Control.new()
	art.size = CARD_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.draw.connect(_draw_back.bind(art))
	add_child(art)
	_back_projection = InspectionCardSurface.new()
	_back_projection.name = "DeckBackProjection"
	add_child(_back_projection)
	# 底板、塔罗和逆位变换先合成一次，再用检视卡的着色器投影整张牌。
	_back_projection.setup_art(art, Vector2.ZERO)
	_back_projection.effect.set_shader_parameter("use_flash", false)
	_back_projection.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_back_projection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_projection.set_process(false)
	_back_projection.hide()


func transfer_back_projection_to(target: EventCardView) -> void:
	if back_tilt.is_zero_approx(): return
	var surface := _back_projection
	_back_projection = null
	surface.reparent(target, false)
	target._back_projection = surface
	target.back_tilt = back_tilt
	target.queue_redraw()
	back_tilt = Vector2.ZERO
	queue_redraw()


func set_choice_hover_enabled(value: bool) -> void:
	_choice_hover_enabled = value
	if value:
		_update_choice_hover(is_hovered())
	else:
		_choice_gamepad_hovered = false
		_choice_hovered = false
		if is_instance_valid(_choice_hover_tween): _choice_hover_tween.kill()
		_set_choice_lift(0.0)


func set_gamepad_hover(hovered: bool) -> void:
	_choice_gamepad_hovered = hovered and _choice_hover_enabled and not disabled
	_update_choice_hover(is_hovered())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: _update_choice_hover(true)


func _update_choice_hover(mouse_hovered: bool) -> void:
	var hovered := _choice_gamepad_hovered or (mouse_hovered and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN)
	if not _choice_hover_enabled or disabled or hovered == _choice_hovered: return
	_choice_hovered = hovered
	if is_instance_valid(_choice_hover_tween): _choice_hover_tween.kill()
	_choice_hover_tween = create_tween()
	_choice_hover_tween.tween_method(_set_choice_lift, _choice_lift, HOVER_LIFT if hovered else 0.0, HOVER_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_choice_lift(value: float) -> void:
	_choice_lift = value
	queue_redraw()


func choice_visual_rect() -> Rect2:
	return Rect2(Vector2(0.0, -_choice_lift), size)


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2(0, -_choice_lift), size + Vector2(0, _choice_lift)).has_point(point)


func _draw() -> void:
	if _choice_lift > 0.0:
		draw_rect(Rect2(Vector2(2, 3), CARD_SIZE - Vector2(4, 3)), Color(0.10, 0.04, 0.03, 0.56))
	draw_set_transform(Vector2(0, -_choice_lift))
	if face_up:
		draw_texture_rect(FRONT, Rect2(Vector2.ZERO, CARD_SIZE), false)
		if artwork != null:
			var factor := minf(144.0 / artwork.get_width(), 100.0 / artwork.get_height()) # 图片区等比缩放，保留原图像素
			var art_size := artwork.get_size() * factor
			draw_texture_rect(artwork, Rect2(Vector2(83, 55) - art_size * 0.5, art_size), false)
		var title := String(definition.get("name", "迷宫商人" if definition.get("kind") == "shop" else "战斗遭遇"))
		draw_string(FONT, Vector2(8, 129), title, HORIZONTAL_ALIGNMENT_CENTER, 150, TITLE_FONT_SIZE, Color(0.98, 0.91, 0.73))
	elif not is_instance_valid(_back_projection) or not _back_projection.visible:
		_draw_back(self, Vector2(0, -_choice_lift))


func _draw_back(canvas: CanvasItem, offset := Vector2.ZERO) -> void:
	canvas.draw_set_transform(offset)
	if tarot_back != null:
		canvas.draw_texture_rect(BACK, Rect2(Vector2.ZERO, CARD_SIZE), false)
		canvas.draw_rect(TAROT_FILL_RECT, TAROT_FILL_COLOR)
		# 两个坐标轴精确取反，逆位仍落在同一整数像素格。
		if tarot_reversed: canvas.draw_set_transform_matrix(Transform2D(Vector2.LEFT, Vector2.UP, CARD_SIZE + offset))
		canvas.draw_texture(tarot_back, TAROT_ORIGIN)
		if tarot_reversed: canvas.draw_set_transform(offset)
	else:
		canvas.draw_texture_rect(back_artwork, Rect2(Vector2.ZERO, CARD_SIZE), false)
		if not definition.has("back_art"):
			canvas.draw_texture_rect(BACK_MARK, Rect2(35, 8, 96, 96), false)
