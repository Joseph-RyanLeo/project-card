class_name EmblemLibraryEntry
extends Control

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

## 开发纹章库中的单个目录项。它代表定义，不代表一枚已拥有的纹章实例。

const StatusIndicatorStyle = preload("res://scripts/ui/status_indicator_style.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")
const InspectionItemDrag = preload("res://scripts/ui/inspection_item_drag.gd")
const EMBLEM_ICON_SIZE := Vector2(14.0, 14.0) # 普通纹章按一个可见格显示
const ELEMENT_STICKER_ICON_SIZE := Vector2(27.0, 27.0) # 元素贴纸原图居中显示，四边各留2像素
const WOUND_ICON_SIZE := Vector2(14.0, 14.0) # 伤势目录保持卡面原始状态图标尺寸

var definition: Dictionary = {}
var drag_enabled: bool = false
var _icon: TextureRect
var _missing_label: Label
var _left_pressed := false
var _press_position := Vector2.ZERO
var _native_drag_started := false


func configure(value: Dictionary, enabled: bool) -> void:
	definition = value.duplicate(true)
	drag_enabled = enabled
	var is_wound: bool = String(definition.get("status_kind", "emblem")) == "wound"
	tooltip_text = EmblemLibraryData.get_wound_tooltip(StringName(definition.get("id", ""))) if is_wound else EmblemLibraryData.get_tooltip(StringName(definition.get("id", "")))
	if definition.has("returned_state"):
		tooltip_text = "已返还 · " + tooltip_text
	if not is_node_ready():
		return
	_refresh_visual()


func set_drag_enabled(value: bool) -> void:
	drag_enabled = value


func is_element_sticker() -> bool:
	return definition.get("target", "emblem") == "rune"


func update_layout_visuals() -> void:
	if is_instance_valid(_icon):
		_icon.position = (size - _icon.size) * 0.5
	if is_instance_valid(_missing_label):
		_missing_label.position = (size - _missing_label.size) * 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_visual()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_left_pressed = true
		_native_drag_started = false
		_press_position = mouse.position
	elif _left_pressed:
		_left_pressed = false
		if drag_enabled and not definition.is_empty() and not _native_drag_started:
			click_carry_requested.emit(
				_build_drag_data(_press_position, false),
				get_global_transform_with_canvas() * mouse.position
			)
	accept_event()


func _refresh_visual() -> void:
	if _icon == null:
		_icon = TextureRect.new()
		_icon.name = "Icon"
		_icon.size = WOUND_ICON_SIZE
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_SCALE
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
	if _missing_label == null:
		_missing_label = Label.new()
		_missing_label.name = "MissingVisual"
		_missing_label.position = Vector2(1, 0)
		_missing_label.size = WOUND_ICON_SIZE
		_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_missing_label.add_theme_font_size_override("font_size", 9)
		_missing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_missing_label)
	var status_id := definition.get("id", &"") as StringName
	var is_wound: bool = String(definition.get("status_kind", "emblem")) == "wound"
	_icon.texture = StatusIndicatorStyle.get_texture(
		CardSlotLayout.Kind.WOUND if is_wound else CardSlotLayout.Kind.EMBLEM,
		status_id
	)
	if is_wound:
		_icon.size = WOUND_ICON_SIZE
	elif is_element_sticker():
		_icon.texture = RuneStickerStyle.get_texture_by_id(status_id)
		_icon.size = ELEMENT_STICKER_ICON_SIZE
	else:
		_icon.size = EMBLEM_ICON_SIZE
	update_layout_visuals()
	_icon.visible = _icon.texture != null
	_missing_label.visible = not _icon.visible
	_missing_label.text = "?"


func _get_drag_data(at_position: Vector2) -> Variant:
	if not drag_enabled or definition.is_empty():
		return null
	_native_drag_started = true
	return _build_drag_data(_press_position if _left_pressed else at_position, true)


func _build_drag_data(grab_position: Vector2, install_preview: bool) -> Dictionary:
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = _icon.texture
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size = _icon.size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preview.texture == null:
		var preview_label := Label.new()
		preview_label.text = "?"
		preview_label.size = _icon.size
		preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(preview_label)
	var data := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": definition.get("id", &"") if definition.get("status_kind", "emblem") != "wound" else &"",
		"wound_id": definition.get("id", &"") if definition.get("status_kind", "emblem") == "wound" else &"",
		"status_kind": definition.get("status_kind", "emblem"),
		"definition": definition.duplicate(true),
		"source_entry": self,
		"preview_texture": _icon.texture,
	}
	var placement_inset := Vector2(2.0, 2.0) if is_element_sticker() else Vector2.ZERO
	return InspectionItemDrag.build(
		self,
		preview,
		grab_position,
		_icon.position,
		data,
		install_preview,
		placement_inset
	)
