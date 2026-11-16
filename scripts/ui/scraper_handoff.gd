extends Control

## 刮刀交接只负责表现；协调器负责节点记录与实际工具库存。
signal finished
const Style = preload("res://scripts/ui/rune_sticker_style.gd")
const LIFT_SECONDS: float = 0.38 # 刮刀从玛格丽特身上向左上方飞出的时长
const FLIGHT_SECONDS: float = 0.95 # 镜头下移时飞到工具栏的时长
const LIFT_OFFSET := Vector2(-40, -80) # 先离开卡面的抛出方向
const ARC_OFFSET := Vector2(-220, -100) # 飞向工具栏时弧线控制点的偏移
const START_SCALE: float = 1.35 # 从卡牌飞出时的刮刀大小
const FADE_SECONDS: float = 0.18 # 起飞与落入工具位的淡入淡出时长
var source: Control
var target: Control
var move_view: Callable
var icon: TextureRect
var _motion: Tween
var _retry := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4095 # 交接期间位于普通卡牌之上，Esc暂停仍由更高的菜单处理
	icon = TextureRect.new()
	icon.texture = Style.get_scraper_texture()
	icon.size = icon.texture.get_size()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.pivot_offset = icon.size * 0.5
	add_child(icon)
	var origin := _center(source)
	var lifted := origin + LIFT_OFFSET
	icon.position = origin - icon.size * 0.5
	icon.scale = Vector2.ONE * START_SCALE
	icon.rotation_degrees = -25.0 # 刮刀起飞时略微侧转
	icon.modulate.a = 0.0
	target.hide()
	tree_exiting.connect(func():
		if is_instance_valid(target): target.show())
	_motion = create_tween()
	_motion.tween_property(icon, "modulate:a", 1.0, FADE_SECONDS)
	_motion.parallel().tween_property(icon, "position", lifted - icon.size * 0.5, LIFT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_callback(move_view)
	_motion.tween_method(func(progress: float):
		var center := lifted.bezier_interpolate(lifted + ARC_OFFSET, _center(target) + Vector2(80, -40), _center(target), progress)
		icon.position = center - icon.size * 0.5
		icon.scale = Vector2.ONE * lerpf(START_SCALE, target.get_global_transform_with_canvas().get_scale().x, progress)
		icon.rotation_degrees = lerpf(-25.0, 0.0, progress), 0.0, 1.0, FLIGHT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_callback(func(): target.show())
	_motion.tween_property(icon, "modulate:a", 0.0, FADE_SECONDS)
	_motion.tween_callback(func(): finished.emit())


func _center(control: Control) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas() * (control.size * 0.5)


func show_save_failure() -> void:
	if _retry: return
	_retry = true
	var message := Label.new()
	message.text = "保存失败，点击重试。"
	message.position = Vector2(24, 620) # 保存异常时在工具栏上方显示重试说明
	message.add_theme_font_size_override("font_size", 18)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(message)


func _gui_input(event: InputEvent) -> void:
	if _retry and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finished.emit()
