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
const HOVER_SCALE_MULTIPLIER: float = 1.035 # 鼠标悬停卡牌时的缩放倍率
const PRESSED_SCALE_MULTIPLIER: float = 1.06 # 鼠标按住卡牌时的缩放倍率
const HOVER_PUNCH_ANGLE: float = 5.0 # 鼠标进入卡牌左/右半边时，同方向轻晃的最大角度
const HOVER_PUNCH_DURATION: float = 0.16 # 悬停单方向轻晃并复位的总时长（秒）
const RESTING_SHADOW_OFFSET := Vector2(3.0, 4.0) # 悬停状态下阴影相对卡牌的偏移
const PRESSED_SHADOW_OFFSET := Vector2(6.0, 8.0) # 按住状态下阴影相对卡牌的偏移
const INTERACTION_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.28) # 悬停和按压阴影的颜色及透明度
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
var _hover_punch_tween: Tween
var _shadow_tween: Tween
var _base_visual_scale: Vector2 = Vector2.ONE
var _layout_resting_position: Vector2 = Vector2.ZERO
var _mouse_hovered: bool = false
var _snapshot_mode: bool = false
var _interaction_shadow: Panel

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
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_left_button_pressed = true
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
	return {
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


static func create_drag_visual(drag_data: Dictionary) -> CardDragPreview:
	var preview_root := CardDragPreview.new()
	var card_view_scene := load("res://scenes/ui/CardView.tscn") as PackedScene
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
		_animate_interaction_scale(
			HOVER_SCALE_MULTIPLIER if _mouse_hovered else 1.0,
			true
		)
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
	_mouse_hovered = true
	if _drag_enabled and not _left_button_pressed and not _snapshot_mode:
		_set_interaction_shadow_visible(true)
		_animate_shadow_offset(RESTING_SHADOW_OFFSET)
		_animate_interaction_scale(HOVER_SCALE_MULTIPLIER)
		_play_hover_rotation_punch()


func _on_mouse_exited() -> void:
	_mouse_hovered = false
	if _drag_enabled and not _left_button_pressed:
		_animate_interaction_scale(1.0)
		_set_interaction_shadow_visible(false)


func _animate_interaction_scale(
	multiplier: float,
	immediate: bool = false
) -> void:
	if _interaction_tween != null and _interaction_tween.is_valid():
		_interaction_tween.kill()

	var target_scale := _base_visual_scale * multiplier
	z_index = 20 if multiplier > 1.0 else 0
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
	if _hover_punch_tween != null and _hover_punch_tween.is_valid():
		_hover_punch_tween.kill()
	rotation_degrees = 0.0
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


func _play_hover_rotation_punch() -> void:
	if _snapshot_mode:
		return
	if _hover_punch_tween != null and _hover_punch_tween.is_valid():
		_hover_punch_tween.kill()
	rotation_degrees = 0.0
	var punch_direction := _get_hover_punch_direction(
		get_local_mouse_position().x
	)
	_hover_punch_tween = create_tween()
	_hover_punch_tween.set_trans(Tween.TRANS_SINE)
	_hover_punch_tween.set_ease(Tween.EASE_OUT)
	_hover_punch_tween.tween_property(
		self,
		"rotation_degrees",
		HOVER_PUNCH_ANGLE * punch_direction,
		HOVER_PUNCH_DURATION * 0.45
	)
	_hover_punch_tween.tween_property(
		self,
		"rotation_degrees",
		0.0,
		HOVER_PUNCH_DURATION * 0.55
	)


func _get_hover_punch_direction(pointer_local_x: float) -> float:
	return -1.0 if pointer_local_x < card_size.x * 0.5 else 1.0


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
		_layout_resting_position,
		LAYOUT_TWEEN_DURATION
	)


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
		effect_text_label.visible = true
		effect_text_label.text = card_data.effect_text
	else:
		effect_text_label.visible = false
		rune_row.visible = true
		_refresh_runes()


func _show_empty_card() -> void:
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
	for child: Node in rune_row.get_children():
		child.queue_free()

	for slot_index: int in 3:
		var rune_slot := _create_rune_slot()
		rune_row.add_child(rune_slot)
		if slot_index < card_data.runes.size():
			var rune := card_data.runes[slot_index]
			var rune_icon := _create_rune_icon(rune)
			rune_slot.add_child(rune_icon)


func _create_rune_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = rune_slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _create_rune_icon(rune: CardData.ElementType) -> TextureRect:
	var icon := TextureRect.new()
	icon.position = (rune_slot_size - rune_icon_size) * 0.5
	icon.custom_minimum_size = rune_icon_size
	icon.size = rune_icon_size
	icon.texture = _get_rune_texture(rune)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = card_data.get_element_type_name(rune)
	return icon


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
	_set_control_rect(bottom_panel, bottom_area_position, bottom_area_size)
	bottom_panel.clip_contents = true

	art_panel.z_index = 0
	card_frame.z_index = 5
	card_name_frame.z_index = 8
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
