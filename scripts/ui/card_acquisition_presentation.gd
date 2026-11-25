extends Control

## 演出只持有已提交的实例。收藏卡位仍由主场景生成，并在卡面落位时显示。
signal finished

const CARD_SCENE = preload("res://scenes/ui/CardView.tscn")
const ClickSpeed = preload("res://scripts/ui/animation_click_speed.gd")
const WHITE_SHADER = preload("res://shaders/emblem_fusion_white.gdshader")
const CARD_SCALE := 4.0 # 卡牌检视使用的原生卡面放大倍率
const BACKDROP := Color(0.015, 0.02, 0.025, 0.78) # 对齐检视暗幕的颜色与透明度
const ENLARGE_SECONDS := 0.32 # 卡牌放大和桌面渐暗的时长
const WHITEN_SECONDS := 0.23 # 暗牌逐渐变成白色剪影的时长
const REVEAL_SECONDS := 0.28 # 白色从真卡上褪去的时长
const READ_SECONDS := 0.42 # 揭晓后供玩家看清卡面的停留时间
const LIGHTEN_SECONDS := 0.25 # 收藏画面渐亮的时长
const FLIGHT_SECONDS := 0.44 # 卡面从检视位置缩小飞入收藏卡位的时长

var _main: Control
var _dim: ColorRect
var _card: Control
var _entries: Array[Dictionary] = []
var _animation: Tween
var _navigation: Tween
var _click_speed := ClickSpeed.new()
var _wait_for_release := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4000
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = BACKDROP
	_dim.modulate.a = 0.0
	add_child(_dim)


func begin(main_view: Control, entries: Array[Dictionary]) -> void:
	_main = main_view
	_entries.assign(entries)
	_play_next()


func holds(owned: OwnedCard) -> bool:
	return _entries.any(func(entry: Dictionary) -> bool: return entry.owned == owned)


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_wait_for_release = true
			_click_speed.register_click(_animation)
			_click_speed.apply_to(_navigation)
		else:
			_wait_for_release = false
			if _entries.is_empty(): _end.call_deferred()
	return event is InputEventMouse or event is InputEventKey or event is InputEventJoypadButton or event is InputEventScreenTouch


func _play_next() -> void:
	if _entries.is_empty():
		if not _wait_for_release: _end()
		return
	var entry := _entries[0]
	var owned := entry.owned as OwnedCard
	if _main.owned_card_collection.get_by_instance_id(owned.instance_id) != owned:
		_entries.pop_front()
		_play_next()
		return
	var inspection := entry.get("inspection") as InspectionCardSurface
	if is_instance_valid(inspection):
		var canvas_transform := inspection.get_global_transform_with_canvas()
		inspection.reparent(self, false)
		_main._set_control_transform_from_canvas(inspection, self, canvas_transform)
		inspection.set_process(false)
		inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inspection.z_index = 1
		_card = inspection
		_dim.modulate.a = 1.0
		_prepare_book.call_deferred()
		return
	var face := CARD_SCENE.instantiate() as CardView
	face.set_card_data(owned.card_data)
	face.set_owned_card(owned)
	var reward := make_visual(self, face)
	var preview := entry.get("preview") as CardView
	_card = make_visual(self, preview) if is_instance_valid(preview) else reward
	var shop_source := entry.get("shop_source") as ShopCardView
	if is_instance_valid(shop_source) and preview is ShopCardView:
		preview.continue_carousel_from(shop_source)
	reward.visible = _card == reward
	var default_source := Transform2D(0.0, get_viewport_rect().get_center())
	var source := get_global_transform_with_canvas().affine_inverse() * (entry.get("origin", default_source) as Transform2D)
	_card.position = source.origin
	_card.rotation = source.get_rotation()
	_card.scale = source.get_scale()
	if _card == reward: whiten(1.0, reward)
	var zoom := _new_tween().set_parallel(true)
	zoom.tween_property(_card, "position", size * 0.5, ENLARGE_SECONDS)
	zoom.tween_property(_card, "scale", Vector2.ONE * CARD_SCALE, ENLARGE_SECONDS)
	zoom.tween_property(_card, "rotation", 0.0, ENLARGE_SECONDS)
	zoom.tween_property(_dim, "modulate:a", 1.0, ENLARGE_SECONDS)
	if _card != reward:
		zoom.chain().tween_method(whiten.bind(_card), 0.0, 1.0, WHITEN_SECONDS)
		zoom.chain().tween_callback(_swap_face.bind(reward))
	zoom.chain().tween_method(whiten.bind(reward), 1.0, 0.0, REVEAL_SECONDS)
	zoom.chain().tween_interval(READ_SECONDS)
	zoom.chain().tween_callback(_prepare_book)


func _swap_face(reward: Control) -> void:
	whiten(1.0, reward)
	reward.position = _card.position
	reward.scale = _card.scale
	_card.hide()
	_card.queue_free()
	_card = reward
	_card.show()


func _prepare_book() -> void:
	var light := _new_tween()
	light.tween_property(_dim, "modulate:a", 0.0, LIGHTEN_SECONDS)
	if _card is InspectionCardSurface:
		var inspection := _card as InspectionCardSurface
		light.parallel().tween_method(inspection.set_pointer_force, inspection.force, Vector2.ZERO, LIGHTEN_SECONDS)
		inspection.card.animate_inspection_stats(false, LIGHTEN_SECONDS)
	var owned := _entries[0].owned as OwnedCard
	navigate(_main, owned, _watch_navigation, _fly)


func _watch_navigation(tween: Tween) -> void:
	_navigation = tween
	_click_speed.apply_to(tween)


func _fly() -> void:
	var owned := _entries[0].owned as OwnedCard
	var slot: Control = _main._find_collection_slot_for_owned_card(owned)
	# 同页落位可能早于淡幕结束，把剩余的淡幕接到飞行动画一起加速。
	if is_instance_valid(_animation) and _animation.is_running(): _animation.kill()
	var tween := _new_tween().set_parallel(true)
	animate_into_slot(tween, _card, slot)
	if _dim.modulate.a > 0.0:
		tween.parallel().tween_property(_dim, "modulate:a", 0.0, LIGHTEN_SECONDS)
	tween.chain().tween_callback(_land.bind(slot))


func _land(slot: Control) -> void:
	_entries.pop_front()
	if is_instance_valid(slot): slot.show()
	_card.hide()
	_card.queue_free()
	_play_next.call_deferred()


func _end() -> void:
	if is_queued_for_deletion(): return
	hide()
	queue_free()
	finished.emit()


func _new_tween() -> Tween:
	_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_click_speed.apply_to(_animation)
	return _animation


static func make_visual(parent: Control, face: CardView) -> Control:
	var center := Control.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var snapshot := CardSnapshotVisual.new()
	center.add_child(snapshot)
	snapshot.configure(face, face.card_size, CanvasItem.TEXTURE_FILTER_NEAREST, 1)
	snapshot.position = -face.card_size * 0.5 - snapshot.get_card_origin_in_texture()
	var white := ShaderMaterial.new()
	white.shader = WHITE_SHADER
	white.set_shader_parameter("jelly_pivot", snapshot.get_card_origin_in_texture() + face.card_size * 0.5)
	snapshot.get_texture_control().material = white
	return center


static func white_material(visual: Control) -> ShaderMaterial:
	return (visual.get_child(0) as CardSnapshotVisual).get_texture_control().material as ShaderMaterial


static func whiten(amount: float, visual: Control) -> void:
	white_material(visual).set_shader_parameter("white_amount", amount)


static func navigate(main_view: Control, owned: OwnedCard, watch: Callable, on_ready: Callable) -> void:
	var turn_page := func():
		if not on_ready.is_valid(): return
		if main_view._turn_collection_to_acquired_card(owned):
			_wait_for_navigation(main_view._page_tween, watch, on_ready)
		else:
			on_ready.call()
	main_view.set_world_view(main_view.WorldView.COLLECTION)
	_wait_for_navigation(main_view._view_tween, watch, turn_page)


static func _wait_for_navigation(tween: Tween, watch: Callable, next: Callable) -> void:
	if is_instance_valid(tween) and tween.is_running():
		watch.call(tween)
		tween.finished.connect(next, CONNECT_ONE_SHOT)
	else:
		next.call()


static func animate_into_slot(tween: Tween, visual: Control, slot: Control) -> void:
	if not is_instance_valid(slot):
		tween.tween_property(visual, "modulate:a", 0.0, FLIGHT_SECONDS)
		return
	var face := slot.get_child(0) as CardView
	var parent := visual.get_parent() as Control
	var target := parent.get_global_transform_with_canvas().affine_inverse() * face.get_global_transform_with_canvas()
	# 检视表面从带透明边距的左上角定位，普通卡面快照以裸卡中心定位。
	var offset: Vector2 = -visual.content_padding if visual is InspectionCardSurface else face.card_size * 0.5
	tween.tween_property(visual, "position", target * offset, FLIGHT_SECONDS)
	tween.parallel().tween_property(visual, "scale", target.get_scale(), FLIGHT_SECONDS)
