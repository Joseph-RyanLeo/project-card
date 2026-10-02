extends TextureRect

const InspectionItemDrag = preload("res://scripts/ui/inspection_item_drag.gd")

signal action_mode_requested

## 固定工具位；由正式库存数量控制拖拽，成功移除后Main扣减库存。
var enabled := false
var blade_point := Vector2.ZERO # 刀头中心，按实际显示比例从素材命中定义换算
var blade_rect := Rect2() # 刀头可刮区域，排除刀柄
var _left_pressed := false
var _press_position := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tooltip_text = "符文刮刀\n点击进入刮擦模式；左键点击或按住移动以刮开符文。右键或 Esc 退出。"

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_left_pressed = true
		_press_position = mouse.position
	elif _left_pressed:
		_left_pressed = false
		if enabled and mouse.position.distance_to(_press_position) < 6.0:
			action_mode_requested.emit()
	accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	# 刮刀使用独立的点击行动模式；返回 null 可阻止工具盒启动原生拖拽。
	return null


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
