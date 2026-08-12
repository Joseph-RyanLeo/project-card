@tool
class_name CardView
extends Panel

signal card_clicked(card_data: CardData)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal hand_source_visibility_changing

const RUNE_FIRE_TEXTURE: Texture2D = preload("res://assets/runes/rune_fire.png")
const RUNE_WATER_TEXTURE: Texture2D = preload("res://assets/runes/rune_water.png")
const RUNE_WOOD_TEXTURE: Texture2D = preload("res://assets/runes/rune_wood.png")
const RUNE_LIGHT_TEXTURE: Texture2D = preload("res://assets/runes/rune_light.png")
const RUNE_DARK_TEXTURE: Texture2D = preload("res://assets/runes/rune_dark.png")
const RUNE_ACTIVE_FLOW_SHEET: Texture2D = preload(
	"res://assets/runes/rune_active_flow_sheet.png"
)
const ACTION_MELEE_TEXTURE: Texture2D = preload("res://assets/actions/action_melee.png")
const ACTION_RANGED_TEXTURE: Texture2D = preload("res://assets/actions/action_ranged.png")
const ACTION_MAGIC_TEXTURE: Texture2D = preload("res://assets/actions/action_magic.png")
const ACTION_HEAL_TEXTURE: Texture2D = preload("res://assets/actions/action_heal.png")
const ACTION_DEFENSE_TEXTURE: Texture2D = preload("res://assets/actions/action_defense.png")
const HEALTH_TEXTURE: Texture2D = preload("res://assets/stats/health.png")
const ARMOR_TEXTURE: Texture2D = preload("res://assets/stats/armor.png")
const DEFAULT_ART_BACKGROUND_TEXTURE: Texture2D = preload(
	"res://assets/card_backgrounds/card_background_placeholder.png"
)
const CARD_NAME_FRAME_TEXTURE: Texture2D = preload(
	"res://assets/card_ui/card_name_frame.png"
)
const LARGE_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_large.fnt")
const SMALL_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_small.fnt")
const LAYOUT_TWEEN_DURATION: float = 0.15 # 卡牌让位、归位和飞入目标位置的动画时长（秒）
const INTERACTION_TWEEN_DURATION: float = 0.10 # 悬停、按压缩放和阴影移动的动画时长（秒）
const PRESSED_SCALE_MULTIPLIER: float = 1.06 # 鼠标按住卡牌时的缩放倍率
const RESTING_SHADOW_OFFSET := Vector2(3.0, 4.0) # 悬停状态下阴影相对卡牌的偏移
const PRESSED_SHADOW_OFFSET := Vector2(6.0, 8.0) # 按住状态下阴影相对卡牌的偏移
const INTERACTION_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.28) # 悬停和按压阴影的颜色及透明度
const CARD_LAYER_Z_STEP: int = 100 # 小队相邻整卡之间的层级间隔，必须大于卡牌内部所有子图层与悬停增量
const ACTIVE_RUNE_FRAME_COUNT: int = 14 # 流光符文精灵表包含的动画帧数
const ACTIVE_RUNE_SHEET_COLUMN_STEP: int = 30 # 精灵表相邻元素符文起点的水平距离
const ACTIVE_RUNE_FRAME_SECONDS: Array[float] = [
	0.10, 0.08, 0.10, 0.10, 0.10, 0.10, 0.10,
	0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10,
] # 流光 GIF 原始 14 帧的逐帧停留时长（秒）
const PREVIEW_ACTIVE_RUNE_ALPHA: float = 0.62 # 假设牌型中流光符文相对真实结果的透明度
const ACTIVE_RUNE_CYCLE_SECONDS: float = 2.0 # 一轮完整流光动画的总时长（秒）
const ACTIVE_RUNE_START_PHASE_SECONDS: float = 1.4 # 新一轮真实流光首次出现时使用的精灵表时间相位（秒）
const RUNE_GLOW_SIZE := Vector2(33.0, 33.0) # 参与牌型的元素色光晕覆盖尺寸
const PREVIEW_RUNE_GLOW_ALPHA: float = 1.0 # 牌型预览常亮光晕的目标透明度
const PREVIEW_RUNE_GLOW_FADE_IN_SECONDS: float = 0.2 # 新预览高亮从透明到常亮的渐显时长（秒）
const PREVIEW_RUNE_GLOW_FADE_OUT_SECONDS: float = 0.5 # 取消、切换或确认预览时旧高亮残影的渐隐时长（秒）
@export_group("Card Pixel Layout")
@export var card_size: Vector2 = Vector2(99, 136) # 裸卡的基准像素尺寸
@export var title_area_position: Vector2 = Vector2(21, 4) # 卡牌名字文字区域的左上角坐标
@export var title_area_size: Vector2 = Vector2(61, 10) # 卡牌名字文字可使用的最大区域
@export var name_frame_position: Vector2 = Vector2(0, 4) # 卡牌名字框的左上角坐标
@export var art_area_position: Vector2 = Vector2(10, 5) # 立绘裁切窗口的左上角坐标
@export var art_area_size: Vector2 = Vector2(79, 95) # 立绘裁切窗口的像素尺寸
@export var bottom_area_position: Vector2 = Vector2(8, 108) # 符文或效果文字区域的左上角坐标
@export var bottom_area_size: Vector2 = Vector2(83, 23) # 符文或效果文字区域的像素尺寸
@export var health_badge_size: Vector2 = Vector2(20, 17) # 生命图标与数字共用区域的尺寸
@export var health_right_overhang: float = 5.0 # 生命区域超出裸卡右边缘的像素数
@export var health_bottom_gap: float = 32.0 # 生命区域底边距离裸卡底边的像素数
@export var armor_badge_size: Vector2 = Vector2(12, 12) # 护甲图标与数字共用区域的尺寸
@export var armor_right_overhang: float = 1.0 # 护甲区域超出裸卡右边缘的像素数
@export var armor_bottom_gap: float = 50.0 # 护甲区域底边距离裸卡底边的像素数
@export var action_top_overhang: float = 4.0 # 行动图标超出裸卡顶边缘的像素数
@export var race_center_pixel: Vector2i = Vector2i(49, 100) # 不同尺寸种族图标共用的中心像素坐标
@export var rune_slot_size: Vector2 = Vector2(23, 23) # 每个元素符文空腔的布局尺寸
@export var rune_icon_size: Vector2 = Vector2(23, 23) # 元素符文纹理的显示尺寸
@export var rune_spacing: int = 7 # 三个元素符文布局槽之间的水平间距

@export_group("Card Font Sizes")
@export var title_font_size: int = 7 # 卡牌名字优先使用的字号
@export var title_font_min_size: int = 5 # 名字过长时允许缩小到的最小字号
@export var value_font_size: int = 12 # 行动数值使用的字号
@export var stats_font_size: int = 8 # 生命值和护甲值使用的字号
@export var effect_font_size: int = 7 # 卡牌效果文字使用的字号

@export var card_data: CardData:
	set(value):
		set_card_data(value)
	get:
		return _card_data

var _card_data: CardData
var showing_effect: bool = false
var _drag_enabled: bool = false
var _drag_source_type: StringName
var _drag_source_row: Node
var _drag_source_slot: Control
var _hand_source_hidden: bool = false
var _left_button_pressed: bool = false
var _active_drag_preview_offset: Vector2 = Vector2.ZERO
var _active_drag_visual: CardDragPreview
var _layout_tween: Tween
var _interaction_tween: Tween
var _shadow_tween: Tween
var _base_visual_scale: Vector2 = Vector2.ONE
var _layout_resting_position: Vector2 = Vector2.ZERO
var _mouse_hovered: bool = false
var _snapshot_mode: bool = false
var _interaction_shadow: Panel
var _external_lift: float = 0.0
var _resting_z_index: int = 0
var _highlighted_rune_indices: Array[int] = []
var _rune_highlight_is_preview: bool = false
var _active_rune_icons: Dictionary = {}
var _active_rune_join_cycles: Dictionary = {}
var _preview_rune_glows: Dictionary = {}
var _preview_glow_tweens: Dictionary = {}
var _active_rune_frame: int = -1

static var _active_rune_flow_epoch_msec: int = -1
static var _active_rune_flow_cached_process_frame: int = -1
static var _active_rune_flow_cached_elapsed_seconds: float = 0.0
static var _active_rune_flow_initial_process_frame: int = -1

@onready var name_clip: Control = %NameClip
@onready var name_label: Label = %NameLabel
@onready var action_icon: TextureRect = %ActionIcon
@onready var value_label: Label = %ValueLabel
@onready var top_row: Control = %TopRow
@onready var art_panel: Panel = %ArtPanel
@onready var art_content: Control = %ArtContent
@onready var art_background: TextureRect = %ArtBackground
@onready var art_texture: TextureRect = %ArtTexture
@onready var art_label: Label = %ArtLabel
@onready var card_frame: TextureRect = %CardFrame
@onready var card_name_frame: TextureRect = %CardNameFrame
@onready var race_icon: TextureRect = %RaceIcon
@onready var stats_row: Control = %StatsRow
@onready var health_icon: TextureRect = %HealthIcon
@onready var health_label: Label = %HealthLabel
@onready var armor_icon: TextureRect = %ArmorIcon
@onready var armor_label: Label = %ArmorLabel
@onready var priority_label: Label = %PriorityLabel
@onready var rune_glow_layer: Control = %RuneGlowLayer
@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var rune_row: HBoxContainer = %RuneRow
@onready var effect_text_label: Label = %EffectTextLabel


func _ready() -> void:
	_layout_resting_position = position
	_create_interaction_shadow()
	_apply_pixel_layout()
	_ignore_mouse_on_children(self)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	set_process(false)
	_refresh()


func _process(_delta: float) -> void:
	if _active_rune_icons.is_empty() or showing_effect:
		set_process(false)
		return
	_update_active_rune_frames()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_left_button_pressed = true
				if (
					_drag_enabled
					and is_instance_valid(_drag_source_slot)
					and _drag_source_slot.has_method("lock_drag_subject")
				):
					_drag_source_slot.lock_drag_subject(card_data)
				if _drag_enabled:
					_set_interaction_shadow_visible(true)
					_animate_shadow_offset(PRESSED_SHADOW_OFFSET)
					_animate_interaction_scale(
						PRESSED_SCALE_MULTIPLIER
					)
				card_clicked.emit(card_data)
			elif _left_button_pressed:
				_left_button_pressed = false
				if _drag_enabled and card_data != null:
					var pointer_global_position := (
						get_global_transform_with_canvas()
						* mouse_event.position
					)
					var drag_data := _build_drag_data(
						mouse_event.position
					)
					_reset_interaction_visual()
					_mouse_hovered = false
					click_carry_requested.emit(
						drag_data,
						pointer_global_position
					)
			accept_event()
		elif (
			mouse_event.button_index == MOUSE_BUTTON_RIGHT
			and mouse_event.pressed
		):
			showing_effect = not showing_effect
			_refresh_bottom_text()
			accept_event()


func _has_point(point: Vector2) -> bool:
	# 卡牌向上抽出后，命中区域仍覆盖抽出前的完整卡面；否则鼠标从
	# 下边缘进入时，卡牌上移会把鼠标瞬间甩出自身并打断 mouse_entered。
	return Rect2(
		Vector2.ZERO,
		Vector2(size.x, size.y + _external_lift)
	).has_point(point)


func _get_drag_data(at_position: Vector2) -> Variant:
	if not _drag_enabled or card_data == null:
		return null

	var drag_data := _build_drag_data(at_position)
	_active_drag_preview_offset = drag_data["preview_offset"] as Vector2
	var preview_root := create_drag_visual(drag_data)
	drag_data["drag_visual"] = preview_root
	_active_drag_visual = preview_root
	set_drag_preview(preview_root)
	return drag_data


func _build_drag_data(at_position: Vector2) -> Dictionary:
	var drag_source_scale := (
		_base_visual_scale if _drag_enabled else scale
	)
	var drag_data := {
		"kind": &"card",
		"card_data": card_data,
		"source_type": _drag_source_type,
		"source_row": _drag_source_row,
		"source_slot": _drag_source_slot,
		"grab_local_position": at_position,
		"preview_offset": at_position * drag_source_scale,
		"preview_scale": drag_source_scale,
		"showing_effect": showing_effect,
	}
	if (
		is_instance_valid(_drag_source_slot)
		and _drag_source_slot.has_method("enrich_drag_data")
	):
		return _drag_source_slot.enrich_drag_data(drag_data, card_data)
	return drag_data


static func create_drag_visual(drag_data: Dictionary) -> CardDragPreview:
	var preview_root := CardDragPreview.new()
	var card_view_scene := load("res://scenes/ui/CardView.tscn") as PackedScene
	if drag_data.get("kind") == &"squad":
		var squad_visual := Control.new()
		var squad_size: Vector2 = drag_data.get("squad_size", Vector2(99, 136))
		squad_visual.size = squad_size
		squad_visual.custom_minimum_size = squad_size
		var cards: Array = drag_data.get("squad_cards", [])
		var x_positions: Array = drag_data.get("squad_x_positions", [])
		var layers: Array = drag_data.get("squad_layer_cards", [])
		for index: int in cards.size():
			var squad_card := card_view_scene.instantiate() as CardView
			squad_card.position = Vector2(float(x_positions[index]), 0.0)
			# CardView 会在 _ready() 记录静止位置，因此整队快照也要先放好 X 再入树。
			squad_visual.add_child(squad_card)
			squad_card.set_card_data(cards[index] as CardData)
			squad_card.configure_drag_source(false)
			squad_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			squad_card.set_resting_z_index(
				(cards.size() - layers.find(cards[index]))
				* CARD_LAYER_Z_STEP
			)
		preview_root.configure(
			squad_visual,
			drag_data.get("grab_local_position", Vector2.ZERO),
			drag_data.get("preview_scale", Vector2.ONE),
			squad_size
		)
		return preview_root
	var preview_card := card_view_scene.instantiate() as CardView
	preview_card.modulate.a = 0.9
	preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_card.showing_effect = bool(drag_data.get("showing_effect", false))
	preview_card.set_card_data(drag_data["card_data"] as CardData)
	preview_card.configure_drag_source(false)
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	var grab_local_position: Vector2 = drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	preview_root.configure(
		preview_card,
		grab_local_position,
		preview_scale,
		preview_card.card_size
	)
	return preview_root


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		if (
			_drag_enabled
			and drag_data is Dictionary
			and (drag_data as Dictionary).get("source_slot") == _drag_source_slot
		):
			_left_button_pressed = false
			_mouse_hovered = false
			_reset_interaction_visual()
		if (
			_drag_enabled
			and _drag_source_type == &"hand"
			and is_instance_valid(_drag_source_slot)
			and drag_data is Dictionary
			and (drag_data as Dictionary).get("source_slot") == _drag_source_slot
		):
			hand_source_visibility_changing.emit()
			_drag_source_slot.visible = false
			_hand_source_hidden = true
	elif what == NOTIFICATION_DRAG_END and _hand_source_hidden:
		var should_animate_back := (
			not get_viewport().gui_is_drag_successful()
		)
		var return_global_position := (
			_active_drag_visual.get_card_global_position()
			if is_instance_valid(_active_drag_visual)
			else (
				get_viewport().get_mouse_position()
				- _active_drag_preview_offset
			)
		)
		hand_source_visibility_changing.emit()
		if is_instance_valid(_drag_source_slot):
			_drag_source_slot.visible = true
		_hand_source_hidden = false
		if should_animate_back:
			_animate_cancelled_drag_return.call_deferred(
				return_global_position
				)
		_active_drag_preview_offset = Vector2.ZERO
		_active_drag_visual = null


func _animate_cancelled_drag_return(
	return_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if is_inside_tree() and is_visible_in_tree():
		animate_from_global_position(return_global_position)


func configure_drag_source(
	enabled: bool,
	source_type: StringName = &"",
	source_row: Node = null,
	source_slot: Control = null
) -> void:
	var was_drag_enabled := _drag_enabled
	_drag_enabled = enabled
	_drag_source_type = source_type
	_drag_source_row = source_row
	_drag_source_slot = source_slot
	if _drag_enabled and not was_drag_enabled:
		_base_visual_scale = scale
		pivot_offset = card_size * 0.5
		_animate_interaction_scale(1.0, true)
	elif not _drag_enabled and was_drag_enabled:
		_reset_interaction_visual()
	mouse_default_cursor_shape = (
		Control.CURSOR_DRAG if _drag_enabled else Control.CURSOR_ARROW
	)


func set_snapshot_mode(value: bool) -> void:
	_snapshot_mode = value
	if _snapshot_mode:
		_reset_interaction_visual()
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mouse_entered() -> void:
	show_pointer_hover_feedback()


func show_pointer_hover_feedback() -> void:
	_mouse_hovered = true
	if _drag_enabled and not _left_button_pressed and not _snapshot_mode:
		z_index = _resting_z_index + 20
		_set_interaction_shadow_visible(true)
		_animate_shadow_offset(RESTING_SHADOW_OFFSET)


func _on_mouse_exited() -> void:
	_mouse_hovered = false
	if _drag_enabled and not _left_button_pressed:
		z_index = _resting_z_index
		_set_interaction_shadow_visible(false)


func clear_pointer_hover_feedback() -> void:
	# Godot 开始另一次拖拽或点击携带时不一定会补发旧卡的 mouse_exited。
	# 这里提供显式兜底，避免旧卡继续保留悬停阴影。
	_mouse_hovered = false
	if not _left_button_pressed:
		_reset_interaction_visual()


func _animate_interaction_scale(
	multiplier: float,
	immediate: bool = false
) -> void:
	if _interaction_tween != null and _interaction_tween.is_valid():
		_interaction_tween.kill()

	var target_scale := _base_visual_scale * multiplier
	z_index = _resting_z_index + 20 if multiplier > 1.0 else _resting_z_index
	if immediate:
		scale = target_scale
		return

	_interaction_tween = create_tween()
	_interaction_tween.set_trans(Tween.TRANS_QUAD)
	_interaction_tween.set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(
		self,
		"scale",
		target_scale,
		INTERACTION_TWEEN_DURATION
	)


func _reset_interaction_visual() -> void:
	_animate_interaction_scale(1.0, true)
	_set_interaction_shadow_visible(false)


func _create_interaction_shadow() -> void:
	_interaction_shadow = Panel.new()
	_interaction_shadow.name = "InteractionShadow"
	_interaction_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_shadow.z_index = -10
	_interaction_shadow.show_behind_parent = true
	_interaction_shadow.position = RESTING_SHADOW_OFFSET
	_interaction_shadow.size = card_size
	_interaction_shadow.custom_minimum_size = card_size
	_interaction_shadow.visible = false
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = INTERACTION_SHADOW_COLOR
	shadow_style.corner_radius_top_left = 3
	shadow_style.corner_radius_top_right = 3
	shadow_style.corner_radius_bottom_left = 3
	shadow_style.corner_radius_bottom_right = 3
	_interaction_shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(_interaction_shadow)
	move_child(_interaction_shadow, 0)


func _set_interaction_shadow_visible(value: bool) -> void:
	if not is_instance_valid(_interaction_shadow):
		return
	_interaction_shadow.visible = value and not _snapshot_mode


func _animate_shadow_offset(target_offset: Vector2) -> void:
	if not is_instance_valid(_interaction_shadow):
		return
	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = create_tween()
	_shadow_tween.set_trans(Tween.TRANS_QUAD)
	_shadow_tween.set_ease(Tween.EASE_OUT)
	_shadow_tween.tween_property(
		_interaction_shadow,
		"position",
		target_offset,
		INTERACTION_TWEEN_DURATION
	)


func animate_from_global_position(previous_global_position: Vector2) -> void:
	if not visible:
		return

	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()

	# 新动画可能在旧动画尚未完成时开始。必须先回到固定静止坐标，
	# 不能把 Tween 中途的临时 position 当成下一轮目标，否则偏移会累加。
	position = _layout_resting_position
	var resting_global_position := global_position
	position += previous_global_position - resting_global_position
	_layout_tween = create_tween()
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	_layout_tween.set_ease(Tween.EASE_OUT)
	_layout_tween.tween_property(
		self,
		"position",
		_layout_resting_position + Vector2(0.0, -_external_lift),
		LAYOUT_TWEEN_DURATION
	)


func set_external_lift(pixels: float) -> void:
	_external_lift = maxf(pixels, 0.0)
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	position = _layout_resting_position + Vector2(0.0, -_external_lift)


func set_layout_position(value: Vector2) -> void:
	# 小队水平顺序变化时只更新长期存在的 CardView 静止坐标，
	# 不销毁节点；这样原生 mouse_entered / mouse_exited 状态不会中断。
	_layout_resting_position = value
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	position = _layout_resting_position + Vector2(0.0, -_external_lift)


func set_resting_z_index(value: int) -> void:
	_resting_z_index = value
	z_index = _resting_z_index


func set_attribute_source_state(
	action_active: bool,
	vitals_active: bool,
	effect_active: bool,
	inactive_alpha: float
) -> void:
	var action_alpha := 1.0 if action_active else inactive_alpha
	var vitals_alpha := 1.0 if vitals_active else inactive_alpha
	action_icon.modulate.a = action_alpha
	value_label.modulate.a = action_alpha
	health_icon.modulate.a = vitals_alpha
	health_label.modulate.a = vitals_alpha
	armor_icon.modulate.a = vitals_alpha
	armor_label.modulate.a = vitals_alpha
	effect_text_label.modulate.a = 1.0 if effect_active else inactive_alpha


func is_layout_animating() -> bool:
	return (
		_layout_tween != null
		and _layout_tween.is_valid()
		and _layout_tween.is_running()
	)


func set_card_data(value: CardData) -> void:
	_card_data = value

	if is_node_ready():
		_refresh()


func set_rune_pattern_highlights(
	rune_indices: Array[int], is_preview_highlight: bool = false
) -> void:
	if not is_preview_highlight and not rune_indices.is_empty():
		_start_active_rune_flow_if_needed()
	if (
		_highlighted_rune_indices == rune_indices
		and _rune_highlight_is_preview == is_preview_highlight
	):
		return
	_highlighted_rune_indices.assign(rune_indices)
	_rune_highlight_is_preview = is_preview_highlight
	if is_node_ready() and not showing_effect:
		_refresh_runes()


func get_highlighted_rune_indices() -> Array[int]:
	return _highlighted_rune_indices.duplicate()


func is_rune_highlight_preview() -> bool:
	return _rune_highlight_is_preview


func get_active_rune_animation_count() -> int:
	return _active_rune_icons.size()


func get_rune_glow_count() -> int:
	return rune_glow_layer.get_child_count() if is_node_ready() else 0


func get_preview_glow_state() -> Dictionary:
	var state: Dictionary = {}
	if not is_node_ready():
		return state
	for child: Node in rune_glow_layer.get_children():
		var glow := child as Control
		if glow == null or not glow.has_meta(&"rune_slot_index"):
			continue
		var slot_index := int(glow.get_meta(&"rune_slot_index"))
		state[slot_index] = maxf(
			float(state.get(slot_index, 0.0)),
			glow.modulate.a
		)
	return state


func apply_preview_glow_transition(previous_state: Dictionary = {}) -> void:
	if not _rune_highlight_is_preview or card_data == null:
		return
	for slot_value: Variant in _preview_rune_glows.keys():
		var slot_index := int(slot_value)
		var glow := _preview_rune_glows[slot_index] as Control
		if glow == null:
			continue
		glow.modulate.a = float(previous_state.get(slot_index, 0.0))
		_start_preview_glow_tween(
			glow,
			PREVIEW_RUNE_GLOW_ALPHA,
			PREVIEW_RUNE_GLOW_FADE_IN_SECONDS
		)
	for slot_value: Variant in previous_state.keys():
		var slot_index := int(slot_value)
		if _preview_rune_glows.has(slot_index):
			continue
		if slot_index < 0 or slot_index >= card_data.runes.size():
			continue
		var old_glow := _create_rune_glow(
			card_data.runes[slot_index],
			slot_index
		)
		old_glow.name = "PreviewRuneGlowFade_%d" % slot_index
		rune_glow_layer.add_child(old_glow)
		old_glow.visible = true
		old_glow.modulate.a = float(previous_state[slot_index])
		_start_preview_glow_tween(
			old_glow,
			0.0,
			PREVIEW_RUNE_GLOW_FADE_OUT_SECONDS,
			true
		)


func fade_preview_glow_state(previous_state: Dictionary) -> void:
	if not is_node_ready() or card_data == null or previous_state.is_empty():
		return
	_clear_preview_glow_tweens()
	_preview_rune_glows.clear()
	for child: Node in rune_glow_layer.get_children():
		rune_glow_layer.remove_child(child)
		child.queue_free()
	for slot_value: Variant in previous_state.keys():
		var slot_index := int(slot_value)
		if slot_index < 0 or slot_index >= card_data.runes.size():
			continue
		var glow := _create_rune_glow(card_data.runes[slot_index], slot_index)
		glow.name = "PreviewRuneGlowFade_%d" % slot_index
		rune_glow_layer.add_child(glow)
		glow.modulate.a = float(previous_state[slot_index])
		_start_preview_glow_tween(
			glow,
			0.0,
			PREVIEW_RUNE_GLOW_FADE_OUT_SECONDS,
			true
		)


func get_active_rune_animation_frame() -> int:
	return _active_rune_frame


static func has_active_rune_flow_started() -> bool:
	return _active_rune_flow_epoch_msec >= 0


static func reset_active_rune_flow() -> void:
	_active_rune_flow_epoch_msec = -1
	_active_rune_flow_cached_process_frame = -1
	_active_rune_flow_cached_elapsed_seconds = 0.0
	_active_rune_flow_initial_process_frame = -1


func is_rune_using_active_animation(slot_index: int) -> bool:
	if not _active_rune_icons.has(slot_index):
		return false
	var rune_icon := _active_rune_icons[slot_index] as TextureRect
	return rune_icon != null and rune_icon.texture is AtlasTexture


func is_rune_scheduled_for_active_animation(slot_index: int) -> bool:
	return _active_rune_icons.has(slot_index)


func is_rune_waiting_for_next_flow(slot_index: int) -> bool:
	if not _active_rune_join_cycles.has(slot_index):
		return false
	return (
		_get_global_flow_cycle()
		< int(_active_rune_join_cycles[slot_index])
	)


func _refresh() -> void:
	if card_data == null:
		_show_empty_card()
		return

	_set_card_name(card_data.display_name)
	action_icon.texture = _get_action_texture(card_data.action_type)
	_apply_action_layout(card_data.action_type)
	value_label.text = str(card_data.base_value)
	health_label.text = str(card_data.max_health)
	armor_label.text = str(card_data.armor)
	priority_label.text = str(card_data.target_priority)
	card_name_frame.visible = true
	_refresh_card_frame()
	_refresh_art()
	_refresh_race_icon()
	_refresh_bottom_text()


func _refresh_bottom_text() -> void:
	if card_data == null:
		return

	if showing_effect:
		rune_row.visible = false
		rune_glow_layer.visible = false
		set_process(false)
		effect_text_label.visible = true
		effect_text_label.text = card_data.effect_text
	else:
		effect_text_label.visible = false
		rune_row.visible = true
		rune_glow_layer.visible = true
		_refresh_runes()


func _show_empty_card() -> void:
	_clear_preview_glow_tweens()
	_active_rune_icons.clear()
	_active_rune_join_cycles.clear()
	_preview_rune_glows.clear()
	set_process(false)
	_set_card_name("空卡牌")
	action_icon.texture = null
	card_name_frame.visible = false
	card_frame.texture = null
	card_frame.visible = false
	art_background.texture = null
	art_background.visible = false
	art_texture.texture = null
	art_texture.visible = false
	art_label.visible = true
	race_icon.texture = null
	race_icon.visible = false
	value_label.text = "-"
	health_label.text = "-"
	armor_label.text = "-"
	priority_label.text = "-"
	effect_text_label.visible = true
	effect_text_label.text = "没有绑定 CardData"
	rune_row.visible = false
	rune_glow_layer.visible = false


func _refresh_art() -> void:
	art_background.texture = (
		card_data.background_texture
		if card_data.background_texture != null
		else DEFAULT_ART_BACKGROUND_TEXTURE
	)
	art_background.visible = art_background.texture != null
	art_texture.texture = card_data.art_texture
	art_texture.visible = card_data.art_texture != null
	_apply_art_offset()
	art_label.visible = (
		card_data.art_texture == null
		and art_background.texture == null
	)


func _set_card_name(display_name: String) -> void:
	name_label.text = display_name
	var name_font := name_label.get_theme_font("font")
	var fitted_size := title_font_size
	while fitted_size > title_font_min_size:
		var text_size := name_font.get_string_size(
			display_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			fitted_size
		)
		if (
			text_size.x <= title_area_size.x
			and name_font.get_height(fitted_size) <= title_area_size.y
		):
			break
		fitted_size -= 1
	name_label.add_theme_font_size_override("font_size", fitted_size)
	_layout_name_label()


func _layout_name_label() -> void:
	var label_height := maxf(
		title_area_size.y,
		name_label.get_combined_minimum_size().y
	)
	_set_control_rect(
		name_label,
		Vector2(0, floorf((title_area_size.y - label_height) * 0.5)),
		Vector2(title_area_size.x, label_height)
	)


func _apply_art_offset() -> void:
	if art_texture.texture == null:
		return

	var texture_size := art_texture.texture.get_size()
	var centered_position := Vector2(
		floori((art_area_size.x - texture_size.x) * 0.5),
		floori((art_area_size.y - texture_size.y) * 0.5)
	)
	_set_control_rect(
		art_texture,
		centered_position + Vector2(card_data.art_offset),
		texture_size
	)


func _refresh_card_frame() -> void:
	var rarity_key := card_data.get_rarity_asset_key()
	var texture_path := (
		"res://assets/card_frames/card_frame_%s.png" % rarity_key
	)
	card_frame.texture = load(texture_path) as Texture2D
	card_frame.visible = card_frame.texture != null


func _refresh_race_icon() -> void:
	if card_data.card_type != CardData.CardType.MINION:
		race_icon.texture = null
		race_icon.visible = false
		return

	var race_key := card_data.get_race_asset_key()
	var rarity_key := card_data.get_rarity_asset_key()
	var texture_path := (
		"res://assets/races/%s/race_%s_%s.png"
		% [race_key, race_key, rarity_key]
	)
	var texture := load(texture_path) as Texture2D
	race_icon.texture = texture
	race_icon.visible = texture != null
	if texture == null:
		return

	var icon_size := texture.get_size()
	var icon_position := Vector2(
		race_center_pixel.x - floori(icon_size.x * 0.5),
		race_center_pixel.y - floori(icon_size.y * 0.5)
	)
	_set_control_rect(race_icon, icon_position, icon_size)
	race_icon.tooltip_text = "%s · 稀有度 %s" % [
		card_data.get_race_name(),
		card_data.get_rarity_name(),
	]


func _refresh_runes() -> void:
	var previous_join_cycles := _active_rune_join_cycles.duplicate()
	_clear_preview_glow_tweens()
	_active_rune_icons.clear()
	_active_rune_join_cycles.clear()
	_preview_rune_glows.clear()
	_active_rune_frame = -1
	for child: Node in rune_row.get_children():
		rune_row.remove_child(child)
		child.queue_free()
	for child: Node in rune_glow_layer.get_children():
		rune_glow_layer.remove_child(child)
		child.queue_free()

	var current_cycle := _get_global_flow_cycle()
	var joins_initial_cycle := (
		has_active_rune_flow_started()
		and Engine.get_process_frames() == _active_rune_flow_initial_process_frame
	)
	for slot_index: int in 3:
		var rune_slot := _create_rune_slot()
		rune_row.add_child(rune_slot)
		if slot_index < card_data.runes.size():
			var rune := card_data.runes[slot_index]
			var is_active := _highlighted_rune_indices.has(slot_index)
			var join_cycle: int = -1
			if is_active:
				join_cycle = (
					current_cycle
					if _rune_highlight_is_preview or joins_initial_cycle
					else int(previous_join_cycles.get(
						slot_index,
						current_cycle + 1
					))
				)
				_active_rune_join_cycles[slot_index] = join_cycle
			if is_active and _rune_highlight_is_preview:
				var rune_glow := _create_rune_glow(rune, slot_index)
				rune_glow.name = "RuneGlow_%d" % slot_index
				rune_glow_layer.add_child(rune_glow)
				_preview_rune_glows[slot_index] = rune_glow
			var show_active_frame := is_active and current_cycle >= join_cycle
			var rune_icon := _create_rune_icon(rune, show_active_frame)
			rune_slot.add_child(rune_icon)
			if is_active:
				_active_rune_icons[slot_index] = rune_icon
	_update_active_rune_frames()
	if _rune_highlight_is_preview:
		apply_preview_glow_transition()
	set_process(not _active_rune_icons.is_empty())


func _create_rune_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = rune_slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _create_rune_icon(
	rune: CardData.ElementType, use_active_animation: bool = false
) -> TextureRect:
	var icon := TextureRect.new()
	icon.position = (rune_slot_size - rune_icon_size) * 0.5
	icon.custom_minimum_size = rune_icon_size
	icon.size = rune_icon_size
	icon.texture = (
		_create_active_rune_atlas(rune)
		if use_active_animation
		else _get_rune_texture(rune)
	)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate.a = (
		PREVIEW_ACTIVE_RUNE_ALPHA
		if use_active_animation and _rune_highlight_is_preview
		else 1.0
	)
	icon.tooltip_text = card_data.get_element_type_name(rune)
	return icon


func _create_rune_glow(
	rune: CardData.ElementType, slot_index: int
) -> Control:
	var glow := Control.new()
	glow.position = _get_rune_glow_position(slot_index)
	glow.custom_minimum_size = RUNE_GLOW_SIZE
	glow.size = RUNE_GLOW_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_color := _get_rune_glow_color(rune)
	var outer_diameter := minf(RUNE_GLOW_SIZE.x, RUNE_GLOW_SIZE.y)
	_add_rune_glow_disc(glow, glow_color, outer_diameter, 0.10)
	_add_rune_glow_disc(glow, glow_color, maxf(outer_diameter - 4.0, 1.0), 0.16)
	_add_rune_glow_disc(glow, glow_color, maxf(outer_diameter - 8.0, 1.0), 0.22)
	glow.set_meta(&"rune_slot_index", slot_index)
	glow.modulate.a = 0.0
	glow.visible = true
	return glow


func _get_rune_glow_position(slot_index: int) -> Vector2:
	var row_width := rune_slot_size.x * 3.0 + float(rune_spacing * 2)
	var centered_row_x := (bottom_area_size.x - row_width) * 0.5
	var slot_position := Vector2(
		centered_row_x + float(slot_index) * (rune_slot_size.x + rune_spacing),
		(bottom_area_size.y - rune_slot_size.y) * 0.5
	)
	return slot_position + (rune_slot_size - RUNE_GLOW_SIZE) * 0.5


func _add_rune_glow_disc(
	glow: Control, glow_color: Color, diameter: float, alpha: float
) -> void:
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.position = (RUNE_GLOW_SIZE - Vector2(diameter, diameter)) * 0.5
	disc.size = Vector2(diameter, diameter)
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(
		glow_color.r,
		glow_color.g,
		glow_color.b,
		alpha
	)
	var radius := roundi(diameter * 0.5)
	disc_style.corner_radius_top_left = radius
	disc_style.corner_radius_top_right = radius
	disc_style.corner_radius_bottom_left = radius
	disc_style.corner_radius_bottom_right = radius
	disc.add_theme_stylebox_override("panel", disc_style)
	glow.add_child(disc)


func _get_rune_glow_color(rune: CardData.ElementType) -> Color:
	match rune:
		CardData.ElementType.FIRE:
			return Color(1.0, 0.18, 0.06, 1.0)
		CardData.ElementType.WATER:
			return Color(0.0, 0.65, 1.0, 1.0)
		CardData.ElementType.WOOD:
			return Color(0.2, 1.0, 0.3, 1.0)
		CardData.ElementType.LIGHT:
			return Color(1.0, 0.86, 0.12, 1.0)
		CardData.ElementType.DARK:
			return Color(0.64, 0.2, 1.0, 1.0)
		_:
			return Color.WHITE


func _create_active_rune_atlas(
	rune: CardData.ElementType
) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = RUNE_ACTIVE_FLOW_SHEET
	atlas_texture.region = Rect2(
		_get_active_rune_sheet_x(rune),
		0.0,
		rune_icon_size.x,
		rune_icon_size.y
	)
	return atlas_texture


func _get_active_rune_sheet_x(rune: CardData.ElementType) -> float:
	match rune:
		CardData.ElementType.DARK:
			return 0.0
		CardData.ElementType.FIRE:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP)
		CardData.ElementType.WATER:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 2)
		CardData.ElementType.LIGHT:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 3)
		CardData.ElementType.WOOD:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 4)
		_:
			return 0.0


func _update_active_rune_frames() -> void:
	if _active_rune_icons.is_empty():
		return
	var elapsed_seconds := _get_global_flow_elapsed_seconds()
	var current_cycle := floori(
		elapsed_seconds / ACTIVE_RUNE_CYCLE_SECONDS
	)
	var effect_elapsed_seconds := (
		elapsed_seconds + _get_active_rune_start_phase_seconds()
	)
	var cycle_time := fposmod(
		effect_elapsed_seconds,
		ACTIVE_RUNE_CYCLE_SECONDS
	)
	var current_frame := _get_flow_frame_at_time(cycle_time)
	_active_rune_frame = current_frame
	var frame_y := float(current_frame) * rune_icon_size.y
	for slot_value: Variant in _active_rune_icons.keys():
		var slot_index := int(slot_value)
		var rune_icon := _active_rune_icons[slot_index] as TextureRect
		var join_cycle := int(_active_rune_join_cycles[slot_index])
		if current_cycle < join_cycle:
			if rune_icon.texture is AtlasTexture:
				rune_icon.texture = _get_rune_texture(
					card_data.runes[slot_index]
				)
			continue
		if not rune_icon.texture is AtlasTexture:
			rune_icon.texture = _create_active_rune_atlas(
				card_data.runes[slot_index]
			)
		var atlas_texture := rune_icon.texture as AtlasTexture
		var region := atlas_texture.region
		region.position.y = frame_y
		atlas_texture.region = region


func _get_global_flow_elapsed_seconds() -> float:
	if _active_rune_flow_epoch_msec < 0:
		return 0.0
	var process_frame := Engine.get_process_frames()
	if process_frame != _active_rune_flow_cached_process_frame:
		_active_rune_flow_cached_process_frame = process_frame
		_active_rune_flow_cached_elapsed_seconds = float(
			Time.get_ticks_msec() - _active_rune_flow_epoch_msec
		) / 1000.0
	return _active_rune_flow_cached_elapsed_seconds


static func _start_active_rune_flow_if_needed() -> void:
	if _active_rune_flow_epoch_msec >= 0:
		return
	_active_rune_flow_epoch_msec = Time.get_ticks_msec()
	_active_rune_flow_cached_process_frame = -1
	_active_rune_flow_cached_elapsed_seconds = 0.0
	_active_rune_flow_initial_process_frame = Engine.get_process_frames()


func _get_global_flow_cycle() -> int:
	return floori(
		_get_global_flow_elapsed_seconds() / ACTIVE_RUNE_CYCLE_SECONDS
	)


func _get_active_rune_start_phase_seconds() -> float:
	return fposmod(
		ACTIVE_RUNE_START_PHASE_SECONDS,
		ACTIVE_RUNE_CYCLE_SECONDS
	)


func _start_preview_glow_tween(
	glow: Control,
	target_alpha: float,
	duration: float,
	free_after: bool = false
) -> void:
	_stop_preview_glow_tween(glow)
	var tween := create_tween()
	_preview_glow_tweens[glow] = tween
	tween.tween_property(glow, "modulate:a", target_alpha, duration)
	tween.finished.connect(
		_on_preview_glow_tween_finished.bind(glow, free_after),
		CONNECT_ONE_SHOT
	)


func _stop_preview_glow_tween(glow: Control) -> void:
	var tween := _preview_glow_tweens.get(glow) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	_preview_glow_tweens.erase(glow)


func _clear_preview_glow_tweens() -> void:
	for tween_value: Variant in _preview_glow_tweens.values():
		var tween := tween_value as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	_preview_glow_tweens.clear()


func _on_preview_glow_tween_finished(
	glow: Control,
	free_after: bool
) -> void:
	_preview_glow_tweens.erase(glow)
	if free_after and is_instance_valid(glow):
		glow.queue_free()


func _get_flow_frame_at_time(cycle_time: float) -> int:
	var source_cycle_seconds: float = 0.0
	for frame_seconds: float in ACTIVE_RUNE_FRAME_SECONDS:
		source_cycle_seconds += frame_seconds
	var normalized_progress := (
		fposmod(cycle_time, ACTIVE_RUNE_CYCLE_SECONDS)
		/ ACTIVE_RUNE_CYCLE_SECONDS
	)
	var source_cycle_time := normalized_progress * source_cycle_seconds
	var accumulated_seconds: float = 0.0
	for frame_index: int in ACTIVE_RUNE_FRAME_COUNT:
		accumulated_seconds += ACTIVE_RUNE_FRAME_SECONDS[frame_index]
		if source_cycle_time < accumulated_seconds:
			return frame_index
	return ACTIVE_RUNE_FRAME_COUNT - 1


func _get_rune_texture(rune: CardData.ElementType) -> Texture2D:
	match rune:
		CardData.ElementType.FIRE:
			return RUNE_FIRE_TEXTURE
		CardData.ElementType.WATER:
			return RUNE_WATER_TEXTURE
		CardData.ElementType.WOOD:
			return RUNE_WOOD_TEXTURE
		CardData.ElementType.LIGHT:
			return RUNE_LIGHT_TEXTURE
		CardData.ElementType.DARK:
			return RUNE_DARK_TEXTURE
		_:
			return RUNE_FIRE_TEXTURE


func _get_action_texture(action_type: CardData.ActionType) -> Texture2D:
	match action_type:
		CardData.ActionType.MELEE:
			return ACTION_MELEE_TEXTURE
		CardData.ActionType.RANGED:
			return ACTION_RANGED_TEXTURE
		CardData.ActionType.MAGIC:
			return ACTION_MAGIC_TEXTURE
		CardData.ActionType.HEAL:
			return ACTION_HEAL_TEXTURE
		CardData.ActionType.DEFENSE:
			return ACTION_DEFENSE_TEXTURE
		_:
			return ACTION_MELEE_TEXTURE


func _apply_pixel_layout() -> void:
	# 行动、生命和护甲图标会越过 99×136 裸卡边界，根节点不能裁切。
	# 效果文字只由 BottomPanel 自己裁切，避免再次出现黑色长条。
	clip_contents = false
	custom_minimum_size = card_size
	size = card_size

	_set_control_rect(top_row, Vector2.ZERO, card_size)
	_set_control_rect(name_clip, title_area_position, title_area_size)
	name_clip.clip_contents = true
	_set_control_rect(art_panel, art_area_position, art_area_size)
	# 人物原图大于 79×95px 插画窗口时保持 1:1 像素，不再二次缩放；
	# 超出窗口的部分交给 ArtPanel 裁切，保证人物与卡牌框像素同尺度。
	art_panel.clip_contents = true
	_set_control_rect(art_content, Vector2.ZERO, art_area_size)
	_set_control_rect(art_background, Vector2.ZERO, art_area_size)
	_set_control_rect(art_label, Vector2.ZERO, art_area_size)
	art_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_background.stretch_mode = TextureRect.STRETCH_SCALE
	art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_texture.stretch_mode = TextureRect.STRETCH_KEEP
	_set_control_rect(card_frame, Vector2.ZERO, card_size)
	card_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_frame.stretch_mode = TextureRect.STRETCH_SCALE
	card_name_frame.texture = CARD_NAME_FRAME_TEXTURE
	_set_control_rect(
		card_name_frame,
		name_frame_position,
		CARD_NAME_FRAME_TEXTURE.get_size()
	)
	card_name_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_name_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_set_control_rect(stats_row, Vector2.ZERO, card_size)
	var health_right := card_size.x + health_right_overhang
	var health_bottom := card_size.y - health_bottom_gap
	_set_control_rect(
		health_icon,
		Vector2(
			health_right - health_badge_size.x,
			health_bottom - health_badge_size.y
		),
		health_badge_size
	)
	_set_control_rect(
		health_label,
		Vector2(
			health_right - health_badge_size.x,
			health_bottom - health_badge_size.y
		),
		health_badge_size
	)
	var armor_right := card_size.x + armor_right_overhang
	var armor_bottom := card_size.y - armor_bottom_gap
	_set_control_rect(
		armor_icon,
		Vector2(
			armor_right - armor_badge_size.x,
			armor_bottom - armor_badge_size.y
		),
		armor_badge_size
	)
	_set_control_rect(
		armor_label,
		Vector2(
			armor_right - armor_badge_size.x,
			armor_bottom - armor_badge_size.y
		),
		armor_badge_size
	)
	priority_label.visible = false
	_set_control_rect(rune_glow_layer, bottom_area_position, bottom_area_size)
	rune_glow_layer.clip_contents = false
	_set_control_rect(bottom_panel, bottom_area_position, bottom_area_size)
	bottom_panel.clip_contents = true

	art_panel.z_index = 0
	card_frame.z_index = 5
	card_name_frame.z_index = 8
	rune_glow_layer.z_index = 9
	top_row.z_index = 10
	bottom_panel.z_index = 10
	stats_row.z_index = 20
	action_icon.z_index = 10
	value_label.z_index = 11
	action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	action_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	health_icon.texture = HEALTH_TEXTURE
	health_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	health_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	armor_icon.texture = ARMOR_TEXTURE
	armor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	armor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_apply_action_layout(CardData.ActionType.MELEE)
	name_label.add_theme_font_size_override("font_size", title_font_size)
	name_label.add_theme_color_override(
		"font_color",
		Color("35251c")
	)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_layout_name_label()
	value_label.add_theme_font_override("font", LARGE_NUMBER_FONT)
	value_label.add_theme_font_size_override("font_size", value_font_size)
	health_label.add_theme_font_override("font", SMALL_NUMBER_FONT)
	health_label.add_theme_font_size_override("font_size", stats_font_size)
	armor_label.add_theme_font_override("font", SMALL_NUMBER_FONT)
	armor_label.add_theme_font_size_override("font_size", stats_font_size)
	priority_label.add_theme_font_size_override("font_size", stats_font_size)
	effect_text_label.add_theme_font_size_override("font_size", effect_font_size)
	rune_row.add_theme_constant_override("separation", rune_spacing)


func _apply_action_layout(action_type: CardData.ActionType) -> void:
	var icon_size := Vector2(25, 25)
	var left_overhang: float = 4.0
	match action_type:
		CardData.ActionType.MAGIC:
			icon_size = Vector2(25, 25)
			left_overhang = 7.0
		CardData.ActionType.DEFENSE:
			icon_size = Vector2(24, 25)
			left_overhang = 6.0
		CardData.ActionType.RANGED, CardData.ActionType.MELEE:
			icon_size = Vector2(25, 25)
			left_overhang = 4.0
		CardData.ActionType.HEAL:
			icon_size = Vector2(25, 28)
			left_overhang = 8.0

	var icon_position := Vector2(-left_overhang, -action_top_overhang)
	_set_control_rect(action_icon, icon_position, icon_size)
	_set_control_rect(
		value_label,
		icon_position + Vector2(-1.0, icon_size.y - 12.0),
		Vector2(18, 12)
	)


func _set_control_rect(control: Control, position_value: Vector2, size_value: Vector2) -> void:
	control.position = position_value
	control.custom_minimum_size = Vector2.ZERO
	control.size = size_value
	control.custom_minimum_size = size_value


func _ignore_mouse_on_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_ignore_mouse_on_children(child)
