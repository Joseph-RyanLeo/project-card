class_name ShopOfferView
extends Control

## 商品图面独立倾斜，价格与原始点击区域保持固定。
signal purchase_requested
signal inspection_requested

const TILE_SIZE := Vector2(112, 212) # 单行商品仅预留图片与独立价格的高度
const REFLOW_SECONDS: float = 0.24 # 售出商品后剩余图片和价格横向补位的秒数
const ART_HEIGHT: float = 188.0 # 锦缎从棋盘y79至y267，商品在此固定高度内上下居中
const PRICE_TOP: float = 198.0 # 价格左上角位于锦缎底边下方10像素
const IDLE_FORCE_LIMIT: float = 0.22 # 闲置透视倾斜强度，为检视最大倾斜的22%
const IDLE_SECONDS_MIN: float = 1.8 # 一次随机倾斜变化的最短秒数
const IDLE_SECONDS_MAX: float = 3.4 # 一次随机倾斜变化的最长秒数
const PACK_RENDER_SCALE: float = 2.0 # 商店贴纸封皮按2倍精度计算高光，适配2K窗口

var _reflow_tween: Tween
var _reflow_offset := 0.0
var _visual: Control
var _hovered := false
var _left_pressed := false
var _hover_surface: InspectionCardSurface
var _idle_rng := RandomNumberGenerator.new()
var _idle_from := Vector2.ZERO
var _idle_target := Vector2.ZERO
var _idle_elapsed := 0.0
var _idle_duration := 1.0
var inspectable := false


func configure(art: Control, price: Control, is_inspectable: bool, enabled: bool, stacked: bool = false, service_name: String = "") -> void:
	var compact := not service_name.is_empty()
	if compact: art.size = Vector2(32, 32) # 棋盘下沿服务图标缩至32像素，点击与价格保持独立
	var art_height := ART_HEIGHT
	var footprint := Vector2(148, 48) if compact else (Vector2(art.size.x, art_height) if stacked else Vector2(maxf(TILE_SIZE.x, art.size.x), art_height + TILE_SIZE.y - ART_HEIGHT))
	custom_minimum_size = footprint
	size = footprint
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN # 高包装只扩大所在行，不拉高旁边单卡的实际命中范围
	mouse_filter = Control.MOUSE_FILTER_IGNORE if stacked else Control.MOUSE_FILTER_STOP
	inspectable = is_inspectable
	_visual = Control.new()
	_visual.size = Vector2(40, footprint.y) if compact else Vector2(footprint.x, art_height)
	_visual.pivot_offset = _visual.size * 0.5
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
		price.position = Vector2(40, 22) if compact else Vector2(0, PRICE_TOP)
		price.size = Vector2(footprint.x - 40, 28) if compact else Vector2(footprint.x, 14)
		add_child(price)
		if compact:
			var caption := Label.new()
			caption.text = service_name
			caption.position = Vector2(40, 0)
			caption.size = Vector2(footprint.x - 40, 26)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", 14) # 独立服务区的名称字号
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
		# 外观使用独立随机源，不能推进报价、开包或战斗的随机序列。
		_idle_rng.randomize()
		_next_idle_tilt()
	set_process(_hover_surface != null)


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
	if not entered and _hover_surface != null:
		_next_idle_tilt()


func _next_idle_tilt() -> void:
	_idle_from = _hover_surface.force
	_idle_target = Vector2(_idle_rng.randf_range(-IDLE_FORCE_LIMIT, IDLE_FORCE_LIMIT), _idle_rng.randf_range(-IDLE_FORCE_LIMIT, IDLE_FORCE_LIMIT))
	_idle_elapsed = 0.0
	_idle_duration = _idle_rng.randf_range(IDLE_SECONDS_MIN, IDLE_SECONDS_MAX)


func _process(delta: float) -> void:
	var target := Vector2.ZERO
	if _hovered:
		# 从固定商品区域取鼠标坐标，视觉倾斜不能反过来移动命中区域。
		var pointer := get_local_mouse_position() - Vector2(_visual.position.x, 0.0) - _hover_surface.position - _hover_surface.content_padding
		var art_size := _hover_surface.size - _hover_surface.content_padding * 2.0
		target = ((pointer / art_size - Vector2.ONE * 0.5) * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
	else:
		_idle_elapsed = minf(_idle_elapsed + delta, _idle_duration)
		target = _idle_from.lerp(_idle_target, smoothstep(0.0, _idle_duration, _idle_elapsed))
		if _idle_elapsed >= _idle_duration:
			_next_idle_tilt()
	_hover_surface.update_pointer_force(target, delta)


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
	# 所有直系可视子节点一起补位；图面的独立旋转不干扰价格。
	for child: Node in get_children():
		if child is Control:
			child.position.x += value - _reflow_offset
	_reflow_offset = value
