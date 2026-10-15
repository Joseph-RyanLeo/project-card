class_name CardPackOpening
extends Node

## 只管理已经入库的卡牌的展示顺序；购买、实例生成与存档仍归主流程。
signal card_requested(owned: OwnedCard)
signal finished

enum Phase { ENLARGING, POSITIONING, SEALED, TEARING, BURST, REVEALING, INSPECTING, COLLECTING, FINISHED }
const TearArt = preload("res://scripts/ui/pack_tear_art.gd")
const Glow = preload("res://scripts/ui/pack_opening_glow.gd")
const CARD_SCENE = preload("res://scenes/ui/CardView.tscn")
const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const DRAG_FRACTION: float = 0.8 # 横向拖过包装宽度的此比例即完成撕开
const SEAL_HIT_HEIGHT: float = 28.0 # 顶部封口可点击区域的原生像素高度
const TEAR_DRAG_THRESHOLD: float = 6.0 # 鼠标移过此逻辑像素距离才算拖撕，否则松手视为单击

var effects: Dictionary = Settings.get_values()
var cards: Array[OwnedCard] = []
var current_index := 0
var phase := Phase.ENLARGING
var has_rare := false
var surface: InspectionCardSurface
var overlay: Control
var tear_art: TearArt
var glow: Glow
var animation: Tween
var _background_cards: Array[InspectionCardSurface] = []
var _drag_start := 0.0
var _drag_progress := 0.0
var _dragging := false
var _auto_tearing := false
var _host: Control
var _host_origin := Vector2.ZERO
var _shake_elapsed := -1.0
var _stack_origin := Vector2.ZERO
var _stack_scale := Vector2.ONE
var _stack_force := Vector2.ZERO
var _pack_surface: InspectionCardSurface
var _drag_pointer := Vector2.ZERO
var _press_pointer := Vector2.ZERO


func begin(acquired: Array[OwnedCard], host: Control, pack_surface: InspectionCardSurface) -> void:
	process_priority = 1 # 等前层卡更新鼠标倾斜后，再同步后层，避免卡叠落后一帧
	_host = host
	_host_origin = host.position
	surface = pack_surface
	overlay = surface.get_parent() as Control
	surface.z_index = 25
	var art := surface.viewport.get_child(0) as Control
	tear_art = TearArt.new()
	tear_art.effects = effects
	surface.viewport.add_child(tear_art)
	tear_art.setup(art)
	tear_art.position = surface.PADDING
	glow = _make_glow()
	accept_purchase(acquired)
	glow.rare = has_rare


static func tear_position_for(pack_surface: InspectionCardSurface, area_size: Vector2, pack_scale: Vector2) -> Vector2:
	var seal_center := pack_surface.PADDING + Vector2((pack_surface.size.x - pack_surface.PADDING.x * 2.0) * 0.5, TearArt.SEAL_HEIGHT * 0.5)
	return area_size * 0.5 - seal_center * pack_scale


func move_to_tearing_position() -> void:
	phase = Phase.POSITIONING
	surface.set_process(false)
	_set_help("正在将撕口移到画面中央…")
	animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(surface, "position", tear_position_for(surface, overlay.size, surface.scale), effects.pack_position_seconds)
	animation.tween_callback(allow_tearing)


func accept_purchase(acquired: Array[OwnedCard]) -> void:
	if acquired.is_empty():
		_dragging = false
		return
	cards = acquired.duplicate()
	for owned: OwnedCard in cards:
		has_rare = has_rare or owned.card_data.rarity == CardData.Rarity.IV


func _prepare_next_card() -> void:
	var owned := cards[_background_cards.size()]
	var view := CARD_SCENE.instantiate() as CardView
	view.set_card_data(owned.card_data)
	view.set_owned_card(owned)
	view.set_squad_attribute_preview_from_squad(SquadData.from_owned_card(owned))
	view.configure_drag_source(false)
	overlay.add_child(view)
	var back := InspectionCardSurface.new()
	back.visible = false
	overlay.add_child(back)
	back.setup(view, Callable(), Callable())
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.tilt_locked = true
	back.set_process(false)
	back.effect.set_shader_parameter("use_flash", false)
	_background_cards.append(back)
	if phase == Phase.SEALED and _background_cards.size() == cards.size():
		allow_tearing()


func allow_tearing() -> void:
	if phase in [Phase.ENLARGING, Phase.POSITIONING, Phase.SEALED]:
		phase = Phase.SEALED
		surface.set_process(true)
		_set_help("点击左侧购买按钮；右键退出检视" if cards.is_empty() else "左键单击包装自动开包；也可按住顶部封口横向撕开")
		if not cards.is_empty() and _background_cards.size() < cards.size():
			_set_help("正在准备卡面…")


func handle_input(event: InputEvent) -> bool:
	if cards.is_empty(): return false
	if phase == Phase.SEALED and _background_cards.size() < cards.size():
		return event is InputEventMouseButton or event is InputEventKey
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and phase in [Phase.ENLARGING, Phase.POSITIONING, Phase.BURST, Phase.REVEALING, Phase.COLLECTING]:
			return true
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if phase in [Phase.SEALED, Phase.TEARING] and not _auto_tearing:
				auto_tear()
			return true
		if mouse.button_index == MOUSE_BUTTON_LEFT and phase in [Phase.SEALED, Phase.TEARING] and not _auto_tearing:
			if mouse.pressed:
				var point := surface.card_point(surface.get_global_transform_with_canvas().affine_inverse() * mouse.position)
				if Rect2(0, -8, tear_art.size.x, SEAL_HIT_HEIGHT).has_point(point):
					phase = Phase.TEARING
					_dragging = true
					_drag_pointer = mouse.position
					_press_pointer = mouse.position
					_drag_start = point.x
					_drag_progress = tear_art.progress
					if is_zero_approx(tear_art.progress): tear_art.from_left = point.x < tear_art.size.x * 0.5
				elif Rect2(Vector2.ZERO, tear_art.size).has_point(point):
					auto_tear()
			else:
				var was_click := _dragging and _press_pointer.distance_to(mouse.position) <= TEAR_DRAG_THRESHOLD and is_equal_approx(tear_art.progress, _drag_progress)
				_dragging = false
				if was_click: auto_tear()
			return true
	elif event is InputEventMouseMotion and _dragging:
		_drag_pointer = event.position
		_advance_tear()
		return true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		return not cards.is_empty()
	return false


func _advance_tear() -> void:
	if _press_pointer.distance_to(_drag_pointer) <= TEAR_DRAG_THRESHOLD:
		return
	var point := surface.card_point(surface.get_global_transform_with_canvas().affine_inverse() * _drag_pointer)
	var distance: float = (point.x - _drag_start) * (1.0 if tear_art.from_left else -1.0)
	var remaining_distance: float = tear_art.size.x - _drag_start if tear_art.from_left else _drag_start
	tear_art.progress = maxf(tear_art.progress, _drag_progress + (1.0 - _drag_progress) * distance / maxf(1.0, remaining_distance * DRAG_FRACTION))
	if tear_art.progress >= 1.0: _burst()


func auto_tear() -> void:
	if cards.is_empty() or phase not in [Phase.SEALED, Phase.TEARING] or _auto_tearing or _background_cards.size() < cards.size():
		return
	phase = Phase.TEARING
	_dragging = false
	_auto_tearing = true
	animation = create_tween()
	animation.tween_property(tear_art, "progress", 1.0, effects.auto_tear_seconds)
	animation.tween_callback(_burst)


func _burst() -> void:
	if phase != Phase.TEARING:
		return
	phase = Phase.BURST
	_dragging = false
	surface.effect.set_shader_parameter("visual_offset", Vector2.ZERO)
	_pack_surface = surface
	_pack_surface.tilt_locked = true
	if has_rare: _shake_elapsed = 0.0
	card_requested.emit(cards[current_index])


func take_next_surface() -> InspectionCardSurface:
	if _background_cards.is_empty():
		return null
	# 换检视外壳前保留已经绘好的画布，下一张直接由后层提升到前层。
	if current_index == 0:
		for back: InspectionCardSurface in _background_cards:
			back.reparent(_host)
		if is_instance_valid(_pack_surface):
			_pack_surface.reparent(_host)
	return _background_cards.pop_front()


func show_card(card_surface: InspectionCardSurface, toolbox_expanded: bool = false) -> void:
	var previous_force := _stack_force
	surface = card_surface
	overlay = surface.get_parent() as Control
	surface.z_index = 25 - current_index # 按原抽取顺序逐层降低，提升为当前卡也不越过先收起的卡
	surface.visible = true
	surface.tilt_locked = false
	if current_index > 0:
		surface.position = _stack_origin
		surface.scale = _stack_scale
		surface.force = previous_force
		surface.effect.set_shader_parameter("pointer_force", previous_force)
	for back: InspectionCardSurface in _background_cards:
		back.reparent(overlay)
		back.visible = true
	_stack_origin = surface.position
	_stack_scale = surface.scale
	_stack_force = surface.force
	_update_stack_layout()
	if not is_instance_valid(glow) or glow.get_parent() != overlay:
		glow = _make_glow()
	var label := overlay.get_node_or_null("PackCardProgress") as Label
	if label == null:
		label = Label.new()
		label.name = "PackCardProgress"
		label.position = Vector2(590, 660) # 揭卡进度在画面下方居中
		label.size = Vector2(100, 30) # 揭卡进度文字的显示范围
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", preload("res://assets/fonts/chill_7.ttf"))
		label.add_theme_font_size_override("font_size", 16) # 揭卡进度字号
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 30
		overlay.add_child(label)
	label.text = "%d / %d" % [current_index + 1, cards.size()]
	if current_index == 0 and is_instance_valid(_pack_surface):
		_extract_stack(toolbox_expanded)
	else:
		_reveal_card(toolbox_expanded)


func _extract_stack(toolbox_expanded: bool) -> void:
	phase = Phase.BURST
	_pack_surface.reparent(overlay)
	_pack_surface.z_index = 26
	var target_origin := _stack_origin
	_stack_origin = _pack_surface.position + (_pack_surface.size - surface.size) * _stack_scale * 0.5
	surface.force = _pack_surface.force
	_stack_force = surface.force
	surface.effect.set_shader_parameter("pointer_force", surface.force)
	surface.position = _stack_origin
	surface.scale = _stack_scale
	_update_stack_layout()
	glow.rare = has_rare
	glow.strength = effects.burst_strength
	_set_help("正在从包装中抽出卡牌…")
	animation = create_tween().set_parallel(true)
	animation.tween_property(tear_art, "seal_offset", Vector2(effects.seal_fly_x, effects.seal_fly_y), effects.burst_seconds * 0.45)
	animation.tween_property(_pack_surface, "position:y", _pack_surface.position.y + effects.shell_drop, effects.burst_seconds * 0.7).set_delay(effects.burst_seconds * 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	animation.tween_property(self, "_stack_origin", target_origin, effects.burst_seconds * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(glow, "strength", 0.0, effects.burst_seconds)
	animation.chain().tween_callback(func():
		_pack_surface.queue_free()
		_pack_surface = null
		surface.position = target_origin
		_update_stack_layout()
		_reveal_card(toolbox_expanded)
	)


func _reveal_card(toolbox_expanded: bool) -> void:
	phase = Phase.INSPECTING
	glow.card_reveal = true
	var rare: bool = cards[current_index].card_data.rarity == CardData.Rarity.IV
	glow.rare = rare
	glow.strength = 1.0 if rare else 0.0
	surface.effect.set_shader_parameter("use_flash", rare)
	if rare:
		animation = create_tween()
		animation.tween_property(glow, "strength", 0.0, effects.rare_reveal_seconds)
	update_inspection_help(toolbox_expanded)


func update_inspection_help(toolbox_expanded: bool) -> void:
	if phase == Phase.INSPECTING:
		var tools_help := "左侧工具包可处理当前卡；" if cards[current_index].card_data.card_type == CardData.CardType.MINION else "当前卡无法使用工具；"
		_set_help("鼠标移动检视；" + tools_help + ("先收起工具箱，再点击卡面显示下一张" if toolbox_expanded else "点击卡面收起并显示下一张"))


func collect_current() -> void:
	if phase != Phase.INSPECTING:
		return
	if is_instance_valid(animation): animation.kill()
	_stack_origin = surface.position
	_stack_scale = surface.scale
	_stack_force = surface.force
	var outgoing := surface
	outgoing.set_process(false)
	outgoing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tween 绑定离场卡本身，多张收卡动画可以重叠；强制关闭会随卡节点一起停止。
	var collect := outgoing.create_tween().set_parallel(true)
	collect.tween_property(outgoing, "position", outgoing.position + Vector2(0, effects.collect_drop), effects.collect_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	collect.tween_property(outgoing, "scale", outgoing.scale * effects.collect_scale, effects.collect_seconds)
	collect.tween_property(outgoing, "modulate:a", 0.0, effects.collect_seconds)
	current_index += 1
	if current_index < cards.size():
		collect.chain().tween_callback(outgoing.queue_free)
		card_requested.emit(cards[current_index])
	else:
		phase = Phase.COLLECTING
		_set_help("收进收藏…")
		collect.chain().tween_callback(func():
			phase = Phase.FINISHED
			finished.emit()
		)


func _make_glow() -> Glow:
	var light := Glow.new()
	light.effects = effects
	light.name = "PackOpeningGlow"
	light.z_index = 18
	overlay.add_child(light)
	light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return light


func _set_help(value: String) -> void:
	var label := overlay.get_node_or_null("InspectionHelp") as Label
	if label != null: label.text = value


func _process(delta: float) -> void:
	# 包装放大时每帧准备一张真实卡面，避免一次创建五张把购买帧堵住。
	if phase in [Phase.ENLARGING, Phase.POSITIONING, Phase.SEALED] and _background_cards.size() < cards.size():
		_prepare_next_card()
	if _shake_elapsed >= 0.0:
		_shake_elapsed += delta
		var remaining := maxf(0.0, 1.0 - _shake_elapsed / effects.shake_seconds)
		_host.position = _host_origin + Vector2(sin(_shake_elapsed * effects.shake_frequency_x), sin(_shake_elapsed * effects.shake_frequency_y)) * effects.shake_pixels * remaining
		if remaining <= 0.0:
			_host.position = _host_origin
			_shake_elapsed = -1.0
	if not is_instance_valid(surface): return
	if phase == Phase.INSPECTING and has_rare:
		for key: String in ["flash_intensity", "stripe_spacing", "stripe_width", "flash_angle_degrees"]:
			surface.effect.set_shader_parameter(key, effects[key])
	if phase == Phase.TEARING and _dragging:
		_advance_tear()
	if phase in [Phase.SEALED, Phase.TEARING] and is_instance_valid(glow):
		if phase == Phase.TEARING and (_dragging or _auto_tearing):
			var elapsed := Time.get_ticks_msec() * 0.001
			var shake: Vector2 = Vector2(sin(elapsed * effects.tear_frequency_x), sin(elapsed * effects.tear_frequency_y)) * effects.tear_shake_pixels
			# 顶点位移发生在合成后；除以包装倍率，显示时得到指定的逻辑像素幅度。
			surface.effect.set_shader_parameter("visual_offset", shake / surface.scale)
		else:
			surface.effect.set_shader_parameter("visual_offset", Vector2.ZERO)
		glow.origin = surface.position + (surface.PADDING + Vector2(tear_art.size.x * 0.5, TearArt.SEAL_HEIGHT)) * surface.scale
		glow.strength = tear_art.progress * (effects.rare_seal_strength if has_rare else effects.normal_seal_strength)
	if phase == Phase.BURST and is_instance_valid(_pack_surface):
		_stack_force = surface.force
		surface.position = _stack_origin
		surface.scale = _stack_scale
		glow.origin = _pack_surface.position + (_pack_surface.PADDING + Vector2(tear_art.size.x * 0.5, TearArt.SEAL_HEIGHT)) * _pack_surface.scale
		_update_stack_layout()
	if phase in [Phase.REVEALING, Phase.INSPECTING, Phase.COLLECTING]:
		glow.origin = surface.position + surface.size * surface.scale * 0.5
		if phase != Phase.COLLECTING:
			_stack_origin = surface.position
			_stack_scale = surface.scale
			_stack_force = surface.force
		_update_stack_layout()


func _update_stack_layout() -> void:
	for index: int in _background_cards.size():
		var back := _background_cards[index]
		back.z_index = surface.z_index - 1 - index
		back.position = _stack_origin - _stack_force * Vector2(effects.stack_parallax_x, effects.stack_parallax_y) * float(index + 1)
		back.scale = _stack_scale
		back.force = _stack_force
		back.effect.set_shader_parameter("pointer_force", _stack_force)


func cancel() -> void:
	phase = Phase.FINISHED
	if is_instance_valid(animation): animation.kill()
	if is_instance_valid(_host): _host.position = _host_origin
	set_process(false)


func _exit_tree() -> void:
	cancel()
