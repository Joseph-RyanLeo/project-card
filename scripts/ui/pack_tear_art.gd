extends Control

## 包装仍使用原图；小画布保存完整包装，绘制时把顶部封条与主体分开。
const SEAL_HEIGHT: float = 11.0 # 顶部撕离封条的原生像素高度
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
var effects: Dictionary = Settings.get_values()
const STRIP_STEP: int = 2 # 封条分段宽度，保留阶梯状像素裂口
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var from_left := true
var seal_offset := Vector2.ZERO:
	set(value):
		seal_offset = value
		queue_redraw()
var source_viewport: SubViewport


func setup(art: Control) -> void:
	size = art.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	source_viewport = SubViewport.new()
	source_viewport.size = Vector2i(size)
	source_viewport.transparent_bg = true
	source_viewport.disable_3d = true
	source_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE # 固定包装图只合成一次，裂口由外层绘制
	add_child(source_viewport)
	art.reparent(source_viewport)
	art.position = Vector2.ZERO
	art.scale = Vector2.ONE
	queue_redraw()


func _draw() -> void:
	if source_viewport == null:
		return
	var source := source_viewport.get_texture()
	var body := Rect2(0, SEAL_HEIGHT, size.x, size.y - SEAL_HEIGHT)
	draw_texture_rect_region(source, body, body)
	for x: int in range(0, int(size.x), STRIP_STEP):
		var along := float(x) / size.x if from_left else 1.0 - float(x + STRIP_STEP) / size.x
		var lift: float = clampf((progress - along) * 2.0, 0.0, 1.0) * effects.peel_lift
		var region := Rect2(x, 0, minf(STRIP_STEP, size.x - x), SEAL_HEIGHT)
		var destination := region
		destination.position += Vector2(0, -lift) + seal_offset
		draw_texture_rect_region(source, destination, region)
	if progress > 0.0:
		var slit_x := 0.0 if from_left else size.x * (1.0 - progress)
		draw_rect(Rect2(slit_x, SEAL_HEIGHT - 1.0, size.x * progress, 2), Color("fff0b0"))
