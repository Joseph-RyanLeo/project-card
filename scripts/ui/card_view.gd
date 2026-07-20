class_name CardView
extends Panel

signal card_clicked(card_data: CardData)

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
@export_group("Card Pixel Layout")
@export var card_size: Vector2 = Vector2(99, 136)
@export var title_area_position: Vector2 = Vector2(8, 4)
@export var title_area_size: Vector2 = Vector2(83, 14)
@export var art_area_position: Vector2 = Vector2(10, 18)
@export var art_area_size: Vector2 = Vector2(79, 95)
@export var stats_area_position: Vector2 = Vector2(10, 101)
@export var stats_area_size: Vector2 = Vector2(79, 12)
@export var bottom_area_position: Vector2 = Vector2(10, 115)
@export var bottom_area_size: Vector2 = Vector2(79, 17)
@export var action_icon_size: Vector2 = Vector2(14, 14)
@export var rune_icon_size: Vector2 = Vector2(15, 18)
@export var rune_spacing: int = 4

@export_group("Card Font Sizes")
@export var title_font_size: int = 8
@export var value_font_size: int = 9
@export var stats_font_size: int = 7
@export var effect_font_size: int = 7

@export var card_data: CardData:
	set(value):
		set_card_data(value)
	get:
		return _card_data

var _card_data: CardData
var showing_effect: bool = false

@onready var name_label: Label = %NameLabel
@onready var action_icon: TextureRect = %ActionIcon
@onready var value_label: Label = %ValueLabel
@onready var top_row: HBoxContainer = %TopRow
@onready var art_panel: PanelContainer = %ArtPanel
@onready var stats_row: HBoxContainer = %StatsRow
@onready var health_label: Label = %HealthLabel
@onready var armor_label: Label = %ArmorLabel
@onready var priority_label: Label = %PriorityLabel
@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var rune_row: HBoxContainer = %RuneRow
@onready var effect_text_label: Label = %EffectTextLabel


func _ready() -> void:
	_apply_pixel_layout()
	_ignore_mouse_on_children(self)
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit(card_data)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			showing_effect = not showing_effect
			_refresh_bottom_text()
			accept_event()


func set_card_data(value: CardData) -> void:
	_card_data = value

	if is_node_ready():
		_refresh()


func _refresh() -> void:
	if card_data == null:
		_show_empty_card()
		return

	name_label.text = card_data.display_name
	action_icon.texture = _get_action_texture(card_data.action_type)
	value_label.text = str(card_data.base_value)
	health_label.text = "HP %d" % card_data.max_health
	armor_label.text = "AR %d" % card_data.armor
	priority_label.text = "P %d" % card_data.target_priority
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
	name_label.text = "空卡牌"
	action_icon.texture = null
	value_label.text = "-"
	health_label.text = "HP -"
	armor_label.text = "AR -"
	priority_label.text = "优先级 -"
	effect_text_label.visible = true
	effect_text_label.text = "没有绑定 CardData"
	rune_row.visible = false


func _refresh_runes() -> void:
	for child: Node in rune_row.get_children():
		child.queue_free()

	for rune: CardData.ElementType in card_data.runes:
		rune_row.add_child(_create_rune_chip(rune))


func _create_rune_chip(rune: CardData.ElementType) -> TextureRect:
	var chip := TextureRect.new()
	chip.custom_minimum_size = rune_icon_size
	chip.texture = _get_rune_texture(rune)
	chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = card_data.get_element_type_name(rune)
	return chip


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
	custom_minimum_size = card_size
	size = card_size

	_set_control_rect(top_row, title_area_position, title_area_size)
	_set_control_rect(art_panel, art_area_position, art_area_size)
	_set_control_rect(stats_row, stats_area_position, stats_area_size)
	_set_control_rect(bottom_panel, bottom_area_position, bottom_area_size)

	top_row.z_index = 10
	action_icon.custom_minimum_size = action_icon_size
	action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	action_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_label.add_theme_font_size_override("font_size", title_font_size)
	value_label.add_theme_font_size_override("font_size", value_font_size)
	health_label.add_theme_font_size_override("font_size", stats_font_size)
	armor_label.add_theme_font_size_override("font_size", stats_font_size)
	priority_label.add_theme_font_size_override("font_size", stats_font_size)
	effect_text_label.add_theme_font_size_override("font_size", effect_font_size)
	rune_row.add_theme_constant_override("separation", rune_spacing)


func _set_control_rect(control: Control, position_value: Vector2, size_value: Vector2) -> void:
	control.position = position_value
	control.size = size_value
	control.custom_minimum_size = size_value


func _ignore_mouse_on_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_ignore_mouse_on_children(child)
