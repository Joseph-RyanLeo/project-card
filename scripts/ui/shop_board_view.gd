extends Control

## 原生棋盘只组织显示；购买、置换、提取与存档仍交给Main现有事务。
const Art = preload("res://scripts/ui/tabletop_art.gd")
const Header = preload("res://scripts/ui/tabletop_header.gd")
const Slot = preload("res://scripts/ui/card_service_slot.gd")
const StatusStyle = preload("res://scripts/ui/status_indicator_style.gd")
const RuneStyle = preload("res://scripts/ui/rune_sticker_style.gd")
const RuneNumber = preload("res://scripts/ui/rune_number_display.gd")
const STICKER_FLIGHT_SECONDS: float = 0.30 # 贴纸从卡面飞往环绕点的时长
const BEADS: Texture2D = preload("res://assets/ui/shop_event_20261020/rarity_beads.png")
const BEAD_X: Array[int] = [0, 16, 32, 47] # 用户原图I～IV级13×13玻璃珠的裁切起点
const EXCHANGE_CENTERS: Array[Vector2] = [Vector2(317, 87), Vector2(331, 87), Vector2(345, 87), Vector2(373, 87)] # 原图三个材料圆点及右侧产物圆点的中心
const Refresh = preload("res://scripts/ui/shop_refresh_button.gd")
const STICKER_CENTERS: Array[Vector2] = [Vector2(658, 121), Vector2(658, 157), Vector2(658, 192), Vector2(658, 226), Vector2(830, 121), Vector2(830, 157), Vector2(830, 192), Vector2(830, 226)] # 原稿八个点的中心位置，纹章与元素共用
var main: Control
var _background: TextureRect
var _refresh: Refresh
var _service_action: Button
var _amount: RuneNumber
var _rarity_dots: Array[TextureRect] = []
var _sticker_host: Control
var _exchange_mark: TextureRect
var _selection: Array[StringName] = []
var _shown_id: StringName = &""
var _shown_stickers: Array[Dictionary] = []

func initialize(owner_main: Control) -> void:
	main = owner_main
	size = Art.BOARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background = Art.art(self, "shop_board.png", Vector2.ZERO)
	var header := Header.new()
	header.main = main
	add_child(header)
	var tabs := Art.art(self, "shop_tabs.png", Vector2(14, 44))
	tabs.name = "ShopTabArtwork"
	for index: int in 2:
		var button := Button.new()
		button.name = "ShoppingTab" if index == 0 else "CardServicesTab"
		button.position = Vector2(14, 44 + index * 40) # 两个按钮分别覆盖原图上下各40像素
		button.size = Vector2(35, 40) # 两个页签的独立命中尺寸
		button.tooltip_text = "商品" if index == 0 else "卡牌服务"
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(main._close_shop_card_services if index == 0 else main._open_shop_card_services)
		add_child(button)
	main.ordinary_shop_offer_list = Control.new()
	main.ordinary_shop_offer_list.name = "OrdinaryShopOffers"
	main.ordinary_shop_offer_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main.ordinary_shop_offer_list)
	_refresh = Refresh.new()
	_refresh.name = "OrdinaryShopRefreshButton"
	_refresh.position = Vector2(680, 308) # 刷新与离店按钮顶边同高，商品价格保留完整一行
	_refresh.refresh_requested.connect(main._refresh_ordinary_shop)
	main.ordinary_shop_offer_list.add_child(_refresh)
	main._shop_procurement_button = Art.button(main.ordinary_shop_offer_list, "定向采购", Vector2(68, 43), load(Art.DIR + "service_button.png"), main._toggle_action_procurement)
	main._shop_card_service_panel = Control.new()
	main._shop_card_service_panel.name = "ShopCardServicePanel"
	main._shop_card_service_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main._shop_card_service_panel)
	main._shop_exchange_panel = Control.new()
	main._shop_exchange_panel.name = "ShopExchangePanel"
	main._shop_exchange_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._shop_card_service_panel.add_child(main._shop_exchange_panel)
	for index: int in 3:
		main._shop_exchange_ids.append(&"")
		var slot := Slot.new()
		slot.name = "ExchangeSlot_%d" % index
		slot.use_board_art = true
		slot.position = Vector2(136 + index * 145, 98) # 卡面在原稿三个117×152凹槽内居中，命中范围保留外侧余量
		slot.accepts_card = main._can_select_exchange_card.bind(index)
		slot.resolve_card_view = main._take_service_card_view
		slot.release_card_view = main._release_service_card_view
		slot.card_selected.connect(main._select_exchange_card.bind(index))
		slot.card_returned.connect(main._on_exchange_card_returned.bind(index))
		main._shop_exchange_panel.add_child(slot)
		main._shop_exchange_slots.append(slot)
	main._shop_exchange_confirm = Art.button(main._shop_exchange_panel, "融合", Vector2(304, 257), load(Art.DIR + "service_button.png"), main._execute_shop_exchange)
	main._shop_exchange_confirm.name = "ConfirmCardExchangeButton"
	main._shop_exchange_status = Label.new()
	main._shop_exchange_status.visible = false
	main._shop_exchange_panel.add_child(main._shop_exchange_status)
	_exchange_mark = TextureRect.new()
	_exchange_mark.position = Vector2(351, 79) # 固定17×17画布中心位于进度框中心间隙
	_exchange_mark.size = Vector2(17, 17) # 勾叉切换时不改变显示区域
	_exchange_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_exchange_mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_exchange_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._shop_exchange_panel.add_child(_exchange_mark)
	for center: Vector2 in EXCHANGE_CENTERS:
		var dot := TextureRect.new()
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.size = Vector2(13, 13) # 玻璃珠保持原生像素尺寸
		dot.position = center - Vector2(6, 6) # 对齐原稿点位中心
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main._shop_exchange_panel.add_child(dot)
		_rarity_dots.append(dot)
	main._shop_service_slot = Slot.new()
	main._shop_service_slot.name = "ShopCardServiceSlot"
	main._shop_service_slot.use_board_art = true
	main._shop_service_slot.position = Vector2(680, 98) # 真实卡面在右侧凹槽内居中
	main._shop_service_slot.accepts_card = main._can_select_shop_service_card
	main._shop_service_slot.resolve_card_view = main._take_service_card_view
	main._shop_service_slot.release_card_view = main._release_service_card_view
	main._shop_service_slot.card_selected.connect(main._select_shop_service_card)
	main._shop_service_slot.card_returned.connect(main._on_shop_service_card_returned)
	main._shop_card_service_panel.add_child(main._shop_service_slot)
	_sticker_host = Control.new()
	_sticker_host.name = "ServiceStickers"
	_sticker_host.z_index = CardView.CARD_LAYER_Z_STEP # 飞行与环绕贴纸高于服务卡的全部内部图层
	_sticker_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._shop_card_service_panel.add_child(_sticker_host)
	_service_action = Art.button(main._shop_card_service_panel, "出售", Vector2(702, 257), load(Art.DIR + "service_button.png"), _execute_service)
	_service_action.name = "SellOrExtractButton"
	Art.art(main._shop_card_service_panel, "price_coin.png", Vector2(780, 91))
	_amount = RuneNumber.new()
	_amount.name = "ServiceAmount"
	main._shop_card_service_panel.add_child(_amount)
	main._shop_card_service_panel.visible = false
	main._shop_exchange_panel.visible = false

func sync_page() -> void:
	var serving: bool = main._shop_card_service_panel.visible
	_background.texture = load(Art.DIR + ("service_board.png" if serving else "shop_board.png"))
	_refresh.set_caption("刷新%d" % main.ordinary_shop_service.refresh_price())
	main.ordinary_shop_status.tooltip_text = main.ordinary_shop_status.text

func _bead(rarity: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = BEADS
	atlas.region = Rect2(BEAD_X[rarity], 0, 13, 13)
	return atlas

func sync_exchange() -> void:
	for index: int in 3:
		var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(main._shop_exchange_ids[index])
		_rarity_dots[index].visible = owned != null
		if owned != null: _rarity_dots[index].texture = _bead(int(owned.card_data.rarity))
	_rarity_dots[3].visible = not main._shop_exchange_confirm.disabled
	if _rarity_dots[3].visible:
		var material: OwnedCard = main.owned_card_collection.get_by_instance_id(main._shop_exchange_ids[0])
		_rarity_dots[3].texture = _bead(int(material.card_data.rarity) + 1)
	_exchange_mark.texture = Art.atlas("exchange_state.png", Rect2(0, 17 if not main._shop_exchange_confirm.disabled else 0, 11, 11))
	main._shop_exchange_confirm.tooltip_text = main._shop_exchange_status.text
	_exchange_mark.tooltip_text = main._shop_exchange_status.text

func sync_service(owned: OwnedCard) -> void:
	var id := owned.instance_id if owned != null else &""
	var stickers: Array[Dictionary] = main._tearable_stickers(owned)
	if id != _shown_id or stickers != _shown_stickers:
		_selection.clear()
		_shown_id = id
		_shown_stickers = stickers
		for child: Node in _sticker_host.get_children():
			_sticker_host.remove_child(child)
			child.queue_free()
		for index: int in stickers.size():
			var state: Dictionary = stickers[index]
			var sticker_id := StringName(state.get("emblem_id", ""))
			var texture := RuneStyle.get_texture_by_id(sticker_id)
			if texture == null: texture = StatusStyle.get_texture(CardSlotLayout.Kind.EMBLEM, sticker_id)
			var button := Button.new()
			button.name = "ServiceSticker%d" % index
			button.position = STICKER_CENTERS[index] - Vector2(16, 16) # 每点提供32像素命中范围，容纳27像素元素贴纸
			button.size = Vector2(32, 32) # 环绕贴纸的固定点击尺寸
			button.toggle_mode = true
			for state_name: String in ["normal", "focus", "disabled"]:
				button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(1.0, 0.85, 0.45, 0.08) # 环绕贴纸的悬停及选中底色强度
			selected_style.border_color = Color("e8be5a")
			selected_style.set_border_width_all(1) # 用1像素边线提示选中的贴纸
			for state_name: String in ["hover", "pressed", "hover_pressed"]:
				button.add_theme_stylebox_override(state_name, selected_style)
			var icon := TextureRect.new()
			icon.name = "StickerVisual"
			icon.texture = texture
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if texture != null:
				var used := texture.get_image().get_used_rect()
				icon.position = Vector2(16, 16) - Vector2(used.position) - Vector2(used.size) * 0.5
			button.add_child(icon)
			button.modulate.a = 0.0
			button.tooltip_text = EmblemLibraryData.get_tooltip(sticker_id)
			button.pressed.connect(_toggle_sticker.bind(StringName(state.instance_id)))
			_sticker_host.add_child(button)
		_fly_service_stickers.call_deferred(owned, id)
	_update_service_action()

func _fly_service_stickers(owned: OwnedCard, id: StringName) -> void:
	if owned == null or not is_inside_tree() or id != _shown_id: return
	var card: CardView = main._shop_service_slot._card_view
	await get_tree().create_timer(CardView.LAYOUT_TWEEN_DURATION + 0.04).timeout
	if id != _shown_id or not is_instance_valid(card) or card != main._shop_service_slot._card_view: return
	var definitions := CardSlotLayout.get_slot_definitions(owned.card_data, owned)
	for index: int in _shown_stickers.size():
		var state: Dictionary = _shown_stickers[index]
		var center := card.card_size * 0.5
		for rune_index: int in owned.rune_stickers.size():
			if owned.rune_stickers[rune_index].get("instance_id") == state.get("instance_id"):
				center = card.rune_area_position + Vector2(rune_index * (card.rune_slot_size.x + card.rune_spacing), 0) + card.rune_slot_size * 0.5
		for definition: Dictionary in definitions:
			if int(definition.kind) != CardSlotLayout.Kind.EMBLEM: continue
			if owned.emblem_slots[int(definition.storage_index)].get("instance_id") == state.get("instance_id"):
				center = definition.position + Vector2(7, 7)
		var button := _sticker_host.get_child(index) as Button
		var rest := button.position
		button.position = _sticker_host.get_global_transform_with_canvas().affine_inverse() * (card.get_global_transform_with_canvas() * center) - button.size * 0.5
		button.modulate.a = 1.0
		var flight := button.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		flight.tween_property(button, "position", rest, STICKER_FLIGHT_SECONDS)
	card.set_service_stickers_detached(true)

func _toggle_sticker(id: StringName) -> void:
	if id in _selection: _selection.erase(id)
	elif _selection.size() < 3: _selection.append(id)
	_update_service_action()

func _update_service_action() -> void:
	if not main._shop_service_undo.is_empty():
		var delta := int(main._shop_service_undo.gold_delta)
		_service_action.text = "撤销"
		_service_action.disabled = main.run_reward_state.gold < delta
		_service_action.tooltip_text = "返还原卡与全部贴纸，%s%d金币；离页、放入新卡或使用提取贴纸后失效" % ["扣回" if delta > 0 else "退还", absi(delta)]
		_amount.text = ("-" if delta > 0 else "+") + str(absi(delta))
		_amount.position = Vector2(776 - _amount.size.x, 88)
		return
	var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(_shown_id)
	var extracting := not _selection.is_empty()
	var price: int = int(main.ordinary_shop_service.config.tear_service.prices_by_return_count.get(str(_selection.size()), 0)) if extracting else main._shop_card_sale_price(owned)
	_service_action.text = "提取" if extracting else "出售"
	_amount.text = ("-" if extracting else "+") + str(price) if owned != null else ""
	_amount.position = Vector2(776 - _amount.size.x, 88) # 金额右对齐金币左边，原生14像素高
	_service_action.disabled = owned == null or (extracting and main.run_reward_state.gold < price)
	for index: int in _sticker_host.get_child_count():
		var button := _sticker_host.get_child(index) as Button
		var selected: bool = StringName(_shown_stickers[index].instance_id) in _selection
		button.set_pressed_no_signal(selected)
		button.self_modulate = Color("ffe092") if selected else Color.WHITE
	_service_action.tooltip_text = "消耗%d金币，提取所选%d枚贴纸；卡牌和未选贴纸销毁" % [price, _selection.size()] if extracting else "出售卡牌及全部贴纸，获得%d金币；装备返还收藏" % price

func _execute_service() -> void:
	if _service_action.disabled: return
	if not main._shop_service_undo.is_empty():
		main._undo_shop_card_service()
		return
	var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(_shown_id)
	if owned == null: return
	if _selection.is_empty():
		main._execute_shop_sale(_shown_id, main._shop_card_sale_price(owned))
	else:
		var selected: Array[Dictionary] = []
		for state: Dictionary in main._tearable_stickers(owned):
			if StringName(state.instance_id) in _selection: selected.append(state)
		if selected.size() != _selection.size(): return
		var price: int = int(main.ordinary_shop_service.config.tear_service.prices_by_return_count[str(selected.size())])
		main._execute_shop_tear(_shown_id, selected, price)
