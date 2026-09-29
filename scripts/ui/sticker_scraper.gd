extends TextureRect

const InspectionItemDrag = preload("res://scripts/ui/inspection_item_drag.gd")

signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

## 固定工具位；工具本身不被消耗，只有松手命中时才调用卡牌的移除操作。
var enabled := false
var blade_point := Vector2.ZERO # 刀头中心，按实际显示比例从素材命中定义换算
var blade_rect := Rect2() # 刀头可刮区域，排除刀柄
var _left_pressed := false
var _press_position := Vector2.ZERO
var _native_drag_started := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tooltip_text = "贴纸刮刀\n准备阶段松手时以刀头命中已贴纹章或符文贴纸即可移除；符文恢复底层符文，贴纸销毁且不返还工作包。"

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
		if enabled and not _native_drag_started:
			click_carry_requested.emit(
				_build_drag_data(mouse.position, false),
				get_global_transform_with_canvas() * mouse.position
			)
	accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if not enabled:
		return null
	_native_drag_started = true
	return _build_drag_data(_press_position if _left_pressed else at_position, true)


func _build_drag_data(grab_position: Vector2, install_preview: bool) -> Dictionary:
	var source_transform := get_global_transform_with_canvas()
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = texture
	preview.size = size
	preview.stretch_mode = stretch_mode
	preview.texture_filter = texture_filter
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var data := {
		"kind": &"sticker_scraper",
		"source_type": &"inspection_library",
		"tip_offset": source_transform.basis_xform(blade_point - grab_position),
		"hit_rect_offset": source_transform.basis_xform(blade_rect.position - grab_position),
		"hit_rect_size": source_transform.basis_xform(blade_rect.size),
		"preview_texture": texture,
	}
	return InspectionItemDrag.build(self, preview, grab_position, Vector2.ZERO, data, install_preview)
