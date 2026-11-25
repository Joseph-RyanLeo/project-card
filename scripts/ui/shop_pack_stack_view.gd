class_name ShopPackStackView
extends Control

## 同主题、同大小的卡包共用一处陈列，悬停时让右侧包滑开。
signal opening_changed(stack: ShopPackStackView, distance: float)
const CrtProjection = preload("res://scripts/ui/crt_projection.gd")
const PACK_STEP: float = 28.0 # 相邻卡包横向错开的距离，决定下层卡包露出宽度
const OPEN_GAP := 5.0 # 目标包完整露出后，与右侧包之间的留白
const OPEN_SECONDS := 0.19 # 右侧商品滑开或复位的时长

var _offers: Array[ShopOfferView] = []
var _hover_offer: ShopOfferView
var _gamepad_offer: ShopOfferView
var _pressed_offer: ShopOfferView
var _description: Control
var _offer_positions: Array[float] = []
var _opening: Tween


func configure(price: Control) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_price(price)
	set_process(false)


func _ready() -> void:
	set_process(is_instance_valid(_hover_offer))


func _process(_delta: float) -> void:
	# 悬停归属统一由叠包维护；检视暗幕接管GUI后立即让位，避免遗留选中状态。
	if is_instance_valid(_gamepad_offer): return
	var mouse_hovered := Input.mouse_mode != Input.MOUSE_MODE_HIDDEN and get_viewport().gui_get_hovered_control() == self
	_set_hover_offer(_pick_offer(CrtProjection.local_mouse(self)) if mouse_hovered else null)


func set_gamepad_offer(offer: ShopOfferView) -> void:
	_gamepad_offer = offer
	_set_hover_offer(offer)


func add_offer(offer: ShopOfferView) -> void:
	_offers.append(offer)
	add_child(offer)
	_layout_offers()


func remove_offer(offer: ShopOfferView) -> void:
	if _gamepad_offer == offer: _gamepad_offer = null
	if _hover_offer == offer:
		_set_hover_offer(null)
	if _pressed_offer == offer:
		_pressed_offer = null
	_offers.erase(offer)
	remove_child(offer)
	_layout_offers()


func _layout_offers() -> void:
	var pack_size := Vector2(99, ShopOfferView.ART_HEIGHT)
	for offer: ShopOfferView in _offers:
		pack_size.x = maxf(pack_size.x, offer._visual.size.x)
	var width := maxf(ShopOfferView.TILE_SIZE.x, pack_size.x + PACK_STEP * maxi(0, _offers.size() - 1))
	custom_minimum_size = Vector2(width, pack_size.y + ShopOfferView.TILE_SIZE.y - ShopOfferView.ART_HEIGHT)
	size = custom_minimum_size
	var left := (width - pack_size.x - PACK_STEP * maxi(0, _offers.size() - 1)) * 0.5
	_offer_positions.clear()
	for index: int in _offers.size():
		_offer_positions.append(left + index * PACK_STEP)
		_offers[index].position = Vector2(left + index * PACK_STEP, 0)
		_offers[index].z_index = index
	_description.position = Vector2(0, ShopOfferView.PRICE_TOP)
	_description.size = Vector2(width, 14) # 价格单独居中，所有包装共用固定纵坐标
	_update_opening()


func maximum_opening() -> float:
	var distance := 0.0
	for index: int in maxi(0, _offers.size() - 1):
		distance = maxf(distance, _offers[index].size.x - PACK_STEP + OPEN_GAP)
	return distance


func _update_opening() -> void:
	if is_instance_valid(_opening): _opening.kill()
	var selected := _offers.find(_hover_offer)
	var distance := maxf(0.0, _hover_offer.size.x - PACK_STEP + OPEN_GAP) if selected >= 0 and selected + 1 < _offers.size() else 0.0
	if is_inside_tree() and not _offers.is_empty():
		_opening = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for index: int in _offers.size():
			var destination := _offer_positions[index] + (distance if index > selected else 0.0)
			_opening.tween_property(_offers[index], "position:x", destination, OPEN_SECONDS)
	opening_changed.emit(self, distance)


func _has_point(point: Vector2) -> bool:
	return _pick_offer(point) != null


func _pick_offer(point: Vector2) -> ShopOfferView:
	# 滑开开始时保留悬停包，避免移动中的右包反复抢回指针。
	if is_instance_valid(_hover_offer) and Rect2(_hover_offer.position, _hover_offer.size).has_point(point):
		return _hover_offer
	for index: int in range(_offers.size() - 1, -1, -1):
		var offer := _offers[index]
		if Rect2(offer.position, offer.size).has_point(point):
			return offer
	if not _offers.is_empty() and Rect2(_description.position, _description.size).has_point(point):
		return _offers.back()
	return null


func _set_hover_offer(offer: ShopOfferView) -> void:
	if offer == _hover_offer:
		return
	if is_instance_valid(_hover_offer):
		_hover_offer.set_pointer_hover(false)
	_hover_offer = offer
	set_process(is_instance_valid(offer))
	if is_instance_valid(offer):
		offer.set_pointer_hover(true)
	_update_opening()


func _gui_input(event: InputEvent) -> void:
	if is_instance_valid(_gamepad_offer): return
	if event is InputEventMouseMotion:
		_set_hover_offer(_pick_offer((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		_set_hover_offer(_pick_offer(mouse.position))
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if is_instance_valid(_hover_offer) and _hover_offer.inspectable:
				_hover_offer.inspection_requested.emit()
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_pressed_offer = _hover_offer
			else:
				var target := _pressed_offer
				_pressed_offer = null
				if is_instance_valid(target) and target == _hover_offer and bool(target.get_meta("purchase_enabled", true)):
					target.purchase_requested.emit()
		accept_event()


func reorder_offers() -> void:
	_offers.sort_custom(func(a: ShopOfferView, b: ShopOfferView): return int(a.get_meta("shop_offer_index")) < int(b.get_meta("shop_offer_index")))
	_layout_offers()


func set_price(price: Control) -> void:
	if is_instance_valid(_description):
		remove_child(_description)
		_description.queue_free()
	_description = price
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_description)
	_layout_offers()
