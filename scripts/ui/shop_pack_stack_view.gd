class_name ShopPackStackView
extends Control

## 同主题、同大小的卡包共用一处陈列，按固定露出区域挑选，不用动画中的位置判定。
const PACK_STEP: float = 28.0 # 相邻卡包横向错开的距离，决定下层卡包露出宽度
const HOVER_Z: int = 100 # 目标卡包在本堆内提升的绘制层，不跨过检视与资源详情

var _offers: Array[ShopOfferView] = []
var _hover_offer: ShopOfferView
var _pressed_offer: ShopOfferView
var _price_reflow: Tween
var _description: Control


func configure(price: Control) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_price(price)
	mouse_exited.connect(_set_hover_offer.bind(null))


func add_offer(offer: ShopOfferView) -> void:
	_offers.append(offer)
	add_child(offer)
	_layout_offers()


func remove_offer(offer: ShopOfferView) -> void:
	if _hover_offer == offer:
		_set_hover_offer(null)
	if _pressed_offer == offer:
		_pressed_offer = null
	_offers.erase(offer)
	remove_child(offer)
	_layout_offers()


func _layout_offers() -> void:
	var width := maxf(ShopOfferView.TILE_SIZE.x, 99.0 + PACK_STEP * (_offers.size() - 1))
	custom_minimum_size = Vector2(width, ShopOfferView.TILE_SIZE.y)
	size = custom_minimum_size
	var left := (width - 99.0 - PACK_STEP * (_offers.size() - 1)) * 0.5
	for index: int in _offers.size():
		_offers[index].position = Vector2(left + index * PACK_STEP, 0)
		_offers[index].z_index = HOVER_Z if _offers[index] == _hover_offer else index
	_description.position = Vector2(2, ShopOfferView.ART_HEIGHT + 2)
	_description.size = Vector2(width - 4, ShopOfferView.TILE_SIZE.y - ShopOfferView.ART_HEIGHT - 2)


func _pick_offer(point: Vector2) -> ShopOfferView:
	# 提到前面的包已经真实遮住邻包；先命中当前前层包，不能点到其背后的原始矩形。
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
		_hover_offer.z_index = _offers.find(_hover_offer)
	_hover_offer = offer
	if is_instance_valid(offer):
		offer.z_index = HOVER_Z
		offer.set_pointer_hover(true)


func _gui_input(event: InputEvent) -> void:
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


func animate_price_reflow_from(previous_canvas_origin: Vector2) -> void:
	if is_instance_valid(_price_reflow):
		_price_reflow.kill()
	var delta := get_global_transform_with_canvas().basis_xform_inv(previous_canvas_origin - _description.get_global_transform_with_canvas().origin)
	_description.position.x += delta.x
	_price_reflow = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_price_reflow.tween_property(_description, "position:x", 2.0, ShopOfferView.REFLOW_SECONDS)


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
