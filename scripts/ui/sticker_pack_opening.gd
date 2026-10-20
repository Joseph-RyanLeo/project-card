extends Node

## 只播放已提交交易的五枚贴纸；演出不抽取、不扣款、不再次入库。
signal surface_changed(value: InspectionCardSurface)
signal finished

const Art = preload("res://scripts/ui/sticker_pack_art.gd")
const ClickSpeed = preload("res://scripts/ui/animation_click_speed.gd")
const Grid = preload("res://scripts/ui/emblem_library_grid.gd")
const PEEL_SECONDS := 0.55 # 单击自动揭开上封皮的时长
const PULL_SECONDS := 0.45 # 整张贴纸抽出、包装下落的时长
const SETTLE_SECONDS := 0.22 # 抽出的贴纸回到屏幕中心的时长
const COLLECT_SECONDS := 0.24 # 确认后整张贴纸向下收起的时长
const PULL_LIFT := 35.0 # 抽出时高于最终位置的原生像素距离
const SHELL_DROP := 155.0 # 包装退场的原生像素距离
const DRAG_FRACTION := 0.8 # 向上拖过上封皮高度的此比例完成揭开
const CLICK_THRESHOLD := 6.0 # 按下后移动小于此逻辑像素距离仍视为单击
const MAX_PEEL_ANGLE := 25.0 # 上半封皮相对向上揭开的左右最大偏转角度
const ANGLE_FOLLOW_SPEED := 14.0 # 翻皮角度平滑跟随鼠标的速度
const FOCUS_SECONDS := 0.18 # 收平底纸并压暗背景的过渡时长
const BACKDROP_ALPHA := 0.62 # 剥离时除五枚贴纸与工具箱外额外压暗的透明度
const STICKER_LIFT := 26.0 # 单枚贴纸先向上剥离的逻辑像素距离
const STICKER_LIFT_ANGLE := 18.0 # 剥离时在原随机角度上附加的旋转角度
const STICKER_LIFT_SECONDS := 0.14 # 单枚贴纸揭起的时长
const ARRANGE_SECONDS := 0.30 # 单枚贴纸从底纸移动到中央队列的时长
const STICKER_ROW_STEP := 112.0 # 五枚贴纸并排时的中心间距，兼容27像素元素贴纸
const STICKER_ROW_Y := 0.44 # 贴纸队列在画面高度中的位置比例
const TOOLBOX_SECONDS := 0.36 # 工具箱半展开、收回及底纸让位的时长
const TOOLBOX_MARGIN := 20.0 # 露出的纹章槽左缘距屏幕左边的距离
const CONTENT_SHIFT := 100.0 # 工具箱展开时队列与底纸共同向右让位的距离
const STORE_SECONDS := 0.32 # 单枚贴纸飞入其真实工具箱槽位的时长
const TOOLBOX_SHAKE := 5.0 # 每枚贴纸入槽后工具箱的最大水平震动位移
const SHAKE_SECONDS := 0.04 # 工具箱震动每一步的时长
enum Phase { ENLARGING, SEALED, PEELING, EXTRACTING, REVEALED, DETACHING, TOOLBOX_ENTERING, STORING, TOOLBOX_RETURNING, EMPTY_REVEALED, COLLECTING, FINISHED }

var phase := Phase.ENLARGING
var art: Art
var surface: InspectionCardSurface
var overlay: Control
var animation: Tween
var progress := 0.0
var style_index := 0
var peel_angle := 0.0
var _target_angle := 0.0
var _dragging := false
var _auto_peeling := false
var _press_pointer := Vector2.ZERO
var _drag_pointer := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _start_progress := 0.0
var _click_speed := ClickSpeed.new()
var _auto_advance := false
var _library: EmblemLibraryView
var _sticker_ids: Array[StringName] = []
var _flying: Array[TextureRect] = []
var _dim: ColorRect
var _library_parent: Node
var _library_layout := {}
var _library_rest := Vector2.ZERO
var _sheet_center := Vector2.ZERO
var stored_count := 0


func begin(pack_art: Art, pack_surface: InspectionCardSurface, host: Control, offer: Dictionary, library: EmblemLibraryView, sticker_ids: Array[StringName]) -> void:
	art = pack_art
	surface = pack_surface
	overlay = host
	_library = library
	_sticker_ids.assign(sticker_ids)
	# 用已确定商品内容的哈希选择外观，不消耗玩法随机流，也不按稀有度选图。
	style_index = int(hash(var_to_str(offer))) % Art.SHEETS.size()
	art.show_contents(offer.get("stickers", []) as Array, style_index)
	art.configure_flip()


func allow_peeling() -> void:
	if phase != Phase.ENLARGING: return
	phase = Phase.SEALED
	surface.set_process(true)
	_set_help("按住上半封皮向上揭开，可有限左右偏转；单击包装或右键自动揭开")
	if _auto_advance: auto_peel()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and (phase not in [Phase.SEALED, Phase.PEELING] or _auto_peeling):
		_register_click()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if phase == Phase.REVEALED: collect()
		elif phase == Phase.EMPTY_REVEALED: _fly_sheet_away()
		return true
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if phase in [Phase.REVEALED, Phase.EMPTY_REVEALED]:
			if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: collect()
			return true
		if phase not in [Phase.SEALED, Phase.PEELING] or _auto_peeling: return true
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			auto_peel()
			return true
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				var point := _pack_point(mouse.position)
				if Rect2(Art.UPPER_POSITION, art.upper.size).has_point(point):
					_dragging = true
					_press_pointer = mouse.position
					_drag_pointer = mouse.position
					_drag_start = point
					_start_progress = progress
				elif Rect2(Vector2.ZERO, art.size).has_point(point):
					_register_click()
					auto_peel()
			else:
				var was_click := _dragging and _press_pointer.distance_to(mouse.position) <= CLICK_THRESHOLD
				_dragging = false
				if was_click:
					_register_click()
					auto_peel()
			return true
	elif event is InputEventMouseMotion and _dragging:
		_drag_pointer = event.position
		_advance_peel()
		return true
	return false


func _process(delta: float) -> void:
	if _dragging: _advance_peel()
	if phase in [Phase.SEALED, Phase.PEELING]:
		peel_angle = lerpf(peel_angle, _target_angle, 1.0 - exp(-ANGLE_FOLLOW_SPEED * delta))
		art.set_peel_angle(peel_angle)


func _pack_point(pointer: Vector2) -> Vector2:
	# 先撤销窗口/画布缩放，再撤销检视shader的透视；结果是包装1倍原图坐标。
	return surface.card_point(surface.get_global_transform_with_canvas().affine_inverse() * pointer)


func _advance_peel() -> void:
	if _press_pointer.distance_to(_drag_pointer) <= CLICK_THRESHOLD: return
	phase = Phase.PEELING
	var displacement := _pack_point(_drag_pointer) - _drag_start
	var upward := maxf(0.0, -displacement.y)
	# 横向移动只控制偏转；向上位移决定揭开程度，避免侧向拖动直接开包。
	_target_angle = clampf(rad_to_deg(atan2(displacement.x, maxf(upward, 1.0))), -MAX_PEEL_ANGLE, MAX_PEEL_ANGLE)
	_set_progress(maxf(progress, _start_progress + upward / (art.upper.size.y * DRAG_FRACTION)))
	if progress >= 1.0: _extract_sheet()


func _set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	art.set_peel_progress(progress)


func auto_peel() -> void:
	if phase not in [Phase.SEALED, Phase.PEELING] or _auto_peeling: return
	phase = Phase.PEELING
	_dragging = false
	_auto_peeling = true
	_start_animation()
	animation.tween_method(_set_progress, progress, 1.0, PEEL_SECONDS * (1.0 - progress))
	animation.tween_callback(_extract_sheet)


func _extract_sheet() -> void:
	if phase != Phase.PEELING: return
	phase = Phase.EXTRACTING
	_dragging = false
	var pack_surface := surface
	pack_surface.tilt_locked = true
	var sheet := art.sheet
	sheet.reparent(overlay)
	surface = InspectionCardSurface.new()
	surface.name = "InspectionStickerSheet"
	overlay.add_child(surface)
	surface.setup_art(sheet, InspectionCardSurface.PADDING, Art.INSPECTION_RENDER_SCALE)
	surface.effect.set_shader_parameter("use_flash", false)
	surface.scale = pack_surface.scale
	surface.position = pack_surface.position + (pack_surface.content_padding + Art.SHEET_POSITION - surface.content_padding) * surface.scale
	surface.force = pack_surface.force
	surface.tilt_locked = true
	surface.z_index = pack_surface.z_index + 1
	surface_changed.emit(surface)
	var center := (overlay.size - surface.size * surface.scale) * 0.5
	_set_help("正在抽出整张贴纸…")
	_start_animation().set_parallel(true)
	animation.tween_property(surface, "position", center - Vector2(0, PULL_LIFT * surface.scale.y), PULL_SECONDS)
	animation.tween_property(pack_surface, "position:y", pack_surface.position.y + SHELL_DROP * pack_surface.scale.y, PULL_SECONDS + SETTLE_SECONDS)
	animation.chain().tween_property(surface, "position", center, SETTLE_SECONDS)
	animation.chain().tween_callback(func():
		pack_surface.queue_free()
		surface.tilt_locked = false
		phase = Phase.REVEALED
		_set_help("移动鼠标检视整张贴纸；点击剥离并收入工具箱，连点加速连续播放")
		if _auto_advance: collect()
	)


func collect() -> void:
	if phase == Phase.EMPTY_REVEALED:
		_fly_sheet_away()
		return
	if phase != Phase.REVEALED: return
	phase = Phase.DETACHING
	surface.tilt_locked = true
	surface.set_process(false)
	_sheet_center = (overlay.size - surface.size * surface.scale) * 0.5
	_set_help("正在依次剥离五枚贴纸；连点可加速并自动继续")
	_start_animation()
	animation.tween_method(func(value: Vector2):
		surface.force = value
		surface.effect.set_shader_parameter("pointer_force", value)
	, surface.force, Vector2.ZERO, FOCUS_SECONDS)
	animation.tween_callback(_detach_stickers)


func _detach_stickers() -> void:
	var sheet := surface.viewport.get_node("StickerSheet") as Control
	# 先收平再把原图标移出离屏画布；保持中心、缩放和随机角度，避免复制或跳位。
	for index: int in _sticker_ids.size():
		var icon := sheet.get_node("Sticker_%d" % index) as TextureRect
		var canvas_center := surface.card_canvas_point(icon.position + icon.pivot_offset)
		var center := overlay.get_global_transform_with_canvas().affine_inverse() * canvas_center
		icon.reparent(overlay)
		icon.position = center - icon.pivot_offset
		icon.scale = surface.scale
		icon.z_index = 50
		_flying.append(icon)
	_dim = ColorRect.new()
	_dim.name = "StickerPeelBackdrop"
	_dim.size = overlay.size
	_dim.color = Color(0, 0, 0, BACKDROP_ALPHA)
	_dim.modulate.a = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = 30
	overlay.add_child(_dim)
	_start_animation()
	animation.tween_property(_dim, "modulate:a", 1.0, FOCUS_SECONDS)
	for index: int in _flying.size():
		var icon := _flying[index]
		var angle := icon.rotation_degrees + STICKER_LIFT_ANGLE * (-1.0 if index % 2 == 0 else 1.0)
		animation.tween_property(icon, "position:y", icon.position.y - STICKER_LIFT, STICKER_LIFT_SECONDS)
		animation.parallel().tween_property(icon, "rotation_degrees", angle, STICKER_LIFT_SECONDS)
		var center := overlay.size * Vector2(0.5, STICKER_ROW_Y) + Vector2((index - 2) * STICKER_ROW_STEP, 0)
		animation.tween_property(icon, "position", center - icon.pivot_offset, ARRANGE_SECONDS)
		animation.parallel().tween_property(icon, "rotation", 0.0, ARRANGE_SECONDS)
	animation.tween_callback(_open_toolbox)


func _open_toolbox() -> void:
	phase = Phase.TOOLBOX_ENTERING
	_library_parent = _library.get_parent()
	_library_layout = {"position": _library.position, "scale": _library.scale, "rotation": _library.rotation, "z_index": _library.z_index, "visible": _library.visible, "drag_enabled": _library._drag_enabled, "index": _library.get_index()}
	_library.reparent(overlay)
	_library.set_drag_enabled(false)
	_library.set_hidden_item_ids(_sticker_ids)
	_library.scale = surface.scale
	_library.rotation = 0.0
	_library.z_index = 40
	_library.show()
	var zoom := _library.scale.x
	_library.position = Vector2(-_library.size.x * zoom, (overlay.size.y - _library.size.y * zoom) * 0.5)
	var has_drop := _sticker_ids.any(func(id: StringName): return EmblemStickerInventory.is_dropped(_library.get_inventory_item(id)))
	_library_rest = Vector2(TOOLBOX_MARGIN if has_drop else TOOLBOX_MARGIN - Grid.GRID_ORIGIN.x * zoom, _library.position.y)
	_start_animation().set_parallel(true)
	animation.tween_property(_library, "position", _library_rest, TOOLBOX_SECONDS)
	animation.tween_property(surface, "position", _sheet_center + Vector2(CONTENT_SHIFT, 0), TOOLBOX_SECONDS)
	for icon: TextureRect in _flying:
		animation.tween_property(icon, "position:x", icon.position.x + CONTENT_SHIFT, TOOLBOX_SECONDS)
	animation.chain().tween_callback(_store_next)


func _store_next() -> void:
	if stored_count == _flying.size():
		_return_toolbox()
		return
	phase = Phase.STORING
	var icon := _flying[stored_count]
	var slot := _library.get_item_canvas_rect(_sticker_ids[stored_count])
	var target := overlay.get_global_transform_with_canvas().affine_inverse() * slot.get_center()
	var dropped := EmblemStickerInventory.is_dropped(_library.get_inventory_item(_sticker_ids[stored_count]))
	_set_help(("正在放入临时区域 %d / %d；离开前请整理" if dropped else "正在收入工具箱 %d / %d；连点加速") % [stored_count + 1, _flying.size()])
	_start_animation()
	animation.tween_property(icon, "position", target - icon.pivot_offset, STORE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	animation.parallel().tween_property(icon, "rotation", 0.0, STORE_SECONDS)
	animation.tween_callback(func():
		icon.hide()
		stored_count += 1
		var remaining: Array[StringName] = []
		remaining.assign(_sticker_ids.slice(stored_count))
		_library.set_hidden_item_ids(remaining)
	)
	animation.tween_property(_library, "position:x", _library_rest.x - TOOLBOX_SHAKE, SHAKE_SECONDS)
	animation.tween_property(_library, "position:x", _library_rest.x + TOOLBOX_SHAKE, SHAKE_SECONDS)
	animation.tween_property(_library, "position:x", _library_rest.x, SHAKE_SECONDS)
	animation.tween_callback(_store_next)


func _return_toolbox() -> void:
	phase = Phase.TOOLBOX_RETURNING
	_start_animation().set_parallel(true)
	animation.tween_property(_library, "position:x", -_library.size.x * _library.scale.x, TOOLBOX_SECONDS)
	animation.tween_property(surface, "position", _sheet_center, TOOLBOX_SECONDS)
	animation.tween_property(_dim, "modulate:a", 0.0, TOOLBOX_SECONDS)
	animation.chain().tween_callback(func():
		_restore_library()
		_dim.queue_free()
		for icon: TextureRect in _flying: icon.queue_free()
		_flying.clear()
		surface.tilt_locked = false
		surface.set_process(true)
		phase = Phase.EMPTY_REVEALED
		_set_help("贴纸已收入工具箱；移动鼠标检视空底纸，点击让它飞走")
		if _auto_advance: _fly_sheet_away()
	)


func _fly_sheet_away() -> void:
	if phase != Phase.EMPTY_REVEALED: return
	phase = Phase.COLLECTING
	surface.tilt_locked = true
	_start_animation().set_parallel(true).set_ease(Tween.EASE_IN)
	animation.tween_property(surface, "position:y", overlay.size.y, COLLECT_SECONDS)
	animation.tween_property(surface, "modulate:a", 0.0, COLLECT_SECONDS)
	animation.chain().tween_callback(func(): phase = Phase.FINISHED; finished.emit())


func _start_animation() -> Tween:
	animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_click_speed.apply_to(animation)
	return animation


func _register_click() -> void:
	_click_speed.register_click(animation)
	if _click_speed.speed > 1.0: _auto_advance = true


func _restore_library() -> void:
	if _library_layout.is_empty(): return
	_library.set_hidden_item_ids([])
	_library.reparent(_library_parent)
	_library_parent.move_child(_library, int(_library_layout.index))
	_library.position = _library_layout.position
	_library.scale = _library_layout.scale
	_library.rotation = _library_layout.rotation
	_library.z_index = int(_library_layout.z_index)
	_library.visible = bool(_library_layout.visible)
	_library.set_drag_enabled(bool(_library_layout.drag_enabled))
	_library_layout.clear()


func _set_help(value: String) -> void:
	var label := overlay.get_node_or_null("InspectionHelp") as Label
	if label != null: label.text = value


func cancel() -> void:
	_dragging = false
	phase = Phase.FINISHED
	if is_instance_valid(animation): animation.kill()
	_restore_library()
	set_process(false)


func _exit_tree() -> void:
	cancel()
