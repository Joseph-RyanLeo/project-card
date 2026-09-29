extends TextureButton

## 单个准备法术图标：只保存同一个 OwnedCard 引用，不复制法术实例。

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal inspection_requested(card_data: CardData, owned_card: OwnedCard)

const CARD_VIEW_SCRIPT: Script = preload("res://scripts/ui/card_view.gd")
const SpellPreparationIconStyle = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const ICON_SIZE := Vector2(42.0, 42.0) # 与准备图标底座原始尺寸一致
var owned_card: OwnedCard
var tray: Control
var _drag_enabled: bool = true
var _left_button_pressed: bool = false


func _ready() -> void:
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = ICON_SIZE


func configure(card: OwnedCard, host: Control) -> void:
	owned_card = card
	tray = host
	if owned_card == null or owned_card.card_data == null:
		texture_normal = null
		tooltip_text = ""
		return
	var trigger_kind := owned_card.card_data.spell_trigger_kind
	var source_column: int = SpellPreparationIconStyle.source_column_for_trigger(trigger_kind)
	texture_normal = SpellPreparationIconStyle.get_texture(source_column, owned_card.card_data.rarity)
	tooltip_text = ""


func set_drag_enabled(enabled: bool) -> void:
	_drag_enabled = enabled
	mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		if owned_card != null and owned_card.card_data != null:
			inspection_requested.emit(owned_card.card_data, owned_card)
		accept_event()
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		_left_button_pressed = true
		return
	if not _left_button_pressed:
		return
	_left_button_pressed = false
	if not _drag_enabled:
		return
	var drag_data := _build_drag_data(mouse_event.position)
	click_carry_requested.emit(
		drag_data,
		get_global_transform_with_canvas() * mouse_event.position
	)
	accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if not _drag_enabled:
		return null
	var drag_data := _build_drag_data(at_position)
	var preview: CardDragPreview = CARD_VIEW_SCRIPT.create_drag_visual(drag_data)
	drag_data["drag_visual"] = preview
	set_drag_preview(preview)
	return drag_data


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and (data as Dictionary).get("source_slot") == self:
			modulate.a = 0.0
			_left_button_pressed = false
	elif what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0
		_left_button_pressed = false


func _build_drag_data(at_position: Vector2) -> Dictionary:
	var trigger_kind := owned_card.card_data.spell_trigger_kind
	var icon_texture := SpellPreparationIconStyle.get_texture(
		SpellPreparationIconStyle.source_column_for_trigger(trigger_kind),
		owned_card.card_data.rarity
	)
	return {
		"kind": &"card",
		"card_data": owned_card.card_data,
		"owned_card": owned_card,
		"source_type": &"spell_preparation",
		"source_slot": self,
		"grab_local_position": at_position,
		"preview_offset": at_position,
		"preview_scale": Vector2.ONE,
		"drag_visual_scale": Vector2.ONE,
		"spell_icon_texture": icon_texture,
		"showing_effect": false,
	}
