class_name ShopOfferView
extends Control

## 商品图片与说明共用一个点击区域；视觉抬起不改变原始命中范围。
signal purchase_requested
signal inspection_requested

const TILE_SIZE := Vector2(112, 174) # 单行商品仅预留图片与独立价格的高度
const REFLOW_SECONDS: float = 0.24 # 售出商品后剩余图片和价格横向补位的秒数
const ART_HEIGHT: float = 140.0 # 商品图片区域高度
const HOVER_LIFT: float = 5.0 # 指向商品时向上抬起的距离
const HOVER_DURATION: float = 0.15 # 商品抬起和回落的秒数
const PACK_RENDER_SCALE: float = 2.0 # 商店贴纸封皮按2倍精度计算高光，适配2K窗口

var _reflow_tween: Tween
var _reflow_offset := 0.0
var _visual: Control
var _hovered := false
var _left_pressed := false
var _hover_tween: Tween
var _hover_surface: InspectionCardSurface
var inspectable := false


func configure(art: Control, price: Control, is_inspectable: bool, enabled: bool, stacked: bool = false, service_name: String = "") -> void:
	var compact := not service_name.is_empty()
	var art_height := maxf(ART_HEIGHT, art.size.y)
	var footprint := Vector2(224, 70) if compact else (Vector2(art.size.x, art_height) if stacked else Vector2(maxf(TILE_SIZE.x, art.size.x), art_height + TILE_SIZE.y - ART_HEIGHT))
	custom_minimum_size = footprint
	size = footprint
	mouse_filter = Control.MOUSE_FILTER_IGNORE if stacked else Control.MOUSE_FILTER_STOP
	inspectable = is_inspectable
	_visual = Control.new()
	_visual.size = Vector2(76, footprint.y) if compact else Vector2(footprint.x, art_height)
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)
	art.position = ((_visual.size - art.size) * 0.5).round()
	_visual.add_child(art)
	if is_inspectable:
		_hover_surface = InspectionCardSurface.new()
		_hover_surface.name = "ShopHoverSurface"
		_visual.add_child(_hover_surface)
	if stacked:
		price.free()
	else:
		price.position = Vector2(76, 30) if compact else Vector2(0, art_height + 4)
		price.size = Vector2(footprint.x - 76, 28) if compact else Vector2(footprint.x, 28)
		add_child(price)
		if compact:
			var caption := Label.new()
			caption.text = service_name
			caption.position = Vector2(76, 0)
			caption.size = Vector2(footprint.x - 76, 26)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", 20) # 独立服务区的名称字号
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(caption)
	_set_mouse_ignore_recursive(art)
	set_purchase_enabled(enabled)
	if not stacked and not compact:
		mouse_entered.connect(set_pointer_hover.bind(true))
		mouse_exited.connect(set_pointer_hover.bind(false))
	set_process(false)


func _ready() -> void:
	if _hover_surface != null:
		var art := _visual.get_child(0) as Control
		var art_position := art.position
		var padding := InspectionCardSurface.PADDING if art is CardView else Vector2.ZERO
		# 单卡留边容纳数值角标；向外扩展画布，不改变原商品占位和价格。
		_hover_surface.card = art as CardView
		_hover_surface.setup_art(art, padding, PACK_RENDER_SCALE if art.has_method("configure_inspection") else 1.0)
		_hover_surface.position = art_position - padding
		_hover_surface.effect.set_shader_parameter("use_flash", false)
		if art.has_method("configure_inspection"):
			art.configure_inspection(_hover_surface)
		elif not art is CardView:
			_hover_surface.effect.set_shader_parameter("use_pack_foil", true)
		_hover_surface.set_process(false)
		_set_mouse_ignore_recursive(_hover_surface)
	# _process会在入树时自动启用，因此在_ready阶段关闭未悬停商品的处理。
	set_process(_hovered)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
		if inspectable:
			inspection_requested.emit()
		accept_event()
	elif mouse.button_index == MOUSE_BUTTON_LEFT:
		if mouse.pressed:
			_left_pressed = true
		elif _left_pressed:
			_left_pressed = false
			if Rect2(Vector2.ZERO, size).has_point(mouse.position) and bool(get_meta("purchase_enabled", true)):
				purchase_requested.emit()
		accept_event()


func set_pointer_hover(entered: bool) -> void:
	if _hovered == entered:
		return
	_hovered = entered
	_left_pressed = false
	if is_instance_valid(_hover_tween):
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_visual, "position:y", -HOVER_LIFT if entered else 0.0, HOVER_DURATION)
	set_process(_hover_surface != null)


func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if _hovered:
		# 忽略抬起后的y偏移，避免视觉变形反过来影响鼠标归一化与叠包命中。
		var pointer := get_local_mouse_position() - Vector2(_visual.position.x, 0.0) - _hover_surface.position - _hover_surface.content_padding
		var art_size := _hover_surface.size - _hover_surface.content_padding * 2.0
		target = ((pointer / art_size - Vector2.ONE * 0.5) * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
	_hover_surface.update_pointer_force(target, delta)
	if not _hovered and _hover_surface.force.length() < 0.001:
		_hover_surface.update_pointer_force(Vector2.ZERO, 1.0)
		set_process(false)


func _set_mouse_ignore_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_ignore_recursive(child)


func set_purchase_enabled(enabled: bool) -> void:
	set_meta("purchase_enabled", enabled)
	modulate.a = 1.0 if enabled else 0.5


func animate_reflow_from(previous_canvas_origin: Vector2) -> void:
	if is_instance_valid(_reflow_tween):
		_reflow_tween.kill()
	var delta := get_global_transform_with_canvas().basis_xform_inv(previous_canvas_origin - _visual.get_global_transform_with_canvas().origin)
	_set_reflow_offset(_reflow_offset + delta.x)
	_reflow_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reflow_tween.tween_method(_set_reflow_offset, _reflow_offset, 0.0, REFLOW_SECONDS)


func _set_reflow_offset(value: float) -> void:
	# 所有直系可视子节点一起补位，悬停只修改图片的y，不干扰静态价格。
	for child: Node in get_children():
		if child is Control:
			child.position.x += value - _reflow_offset
	_reflow_offset = value
