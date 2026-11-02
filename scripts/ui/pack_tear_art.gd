extends Control

## 包装仍使用原图；小画布保存完整包装，绘制时把顶部封条与主体分开。
const SEAL_HEIGHT: float = 11.0 # 顶部撕离封条的原生像素高度
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const RELIEF = preload("res://shaders/pack_relief_art.gdshader")
const BODY = preload("res://assets/card_ui/shop/relief_sample/body_normal.png")
const GOLD = preload("res://assets/card_ui/shop/relief_sample/gold_normal.png")
const HEIGHT = preload("res://assets/card_ui/shop/relief_sample/body_height_input.png")
const REGIONS = preload("res://assets/card_ui/shop/relief_sample/body_regions.png")
const INSPECTION_RENDER_SCALE := 4.0 # 放大开包时光照与撕口按4倍精度绘制，原图尺寸不变
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
var surface: InspectionCardSurface


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
	var relief := ShaderMaterial.new()
	relief.shader = RELIEF
	relief.set_shader_parameter("body_normal", BODY)
	relief.set_shader_parameter("gold_normal", GOLD)
	relief.set_shader_parameter("body_height", HEIGHT)
	relief.set_shader_parameter("body_regions", REGIONS)
	material = relief
	set_process(false)
	queue_redraw()


func configure_inspection(value: InspectionCardSurface) -> void:
	surface = value
	# 凹凸和金纹在原图UV内着色，再让共用检视表面统一倾斜，避免双重扫光。
	surface.effect.set_shader_parameter("use_flash", false)
	surface.effect.set_shader_parameter("use_pack_foil", false)
	set_process(true)


func _process(_delta: float) -> void:
	if is_instance_valid(surface):
		(material as ShaderMaterial).set_shader_parameter("pointer_force", surface.force)


func _draw() -> void:
	if source_viewport == null:
		return
	var source := source_viewport.get_texture()
	var body := Rect2(0, SEAL_HEIGHT, size.x, size.y - SEAL_HEIGHT)
	draw_texture_rect_region(source, body, body)
	for x: int in range(0, int(size.x), STRIP_STEP):
		var strip_width := minf(STRIP_STEP, size.x - x)
		var along := float(x) / size.x if from_left else 1.0 - float(x + strip_width) / size.x
		var lift: float = clampf((progress - along) * 2.0, 0.0, 1.0) * effects.peel_lift
		var region := Rect2(x, 0, strip_width, SEAL_HEIGHT)
		var destination := region
		destination.position += Vector2(0, -lift) + seal_offset
		draw_texture_rect_region(source, destination, region)
	if progress > 0.0:
		var slit_x := 0.0 if from_left else size.x * (1.0 - progress)
		draw_rect(Rect2(slit_x, SEAL_HEIGHT - 1.0, size.x * progress, 2), Color("fff0b0"))
