class_name SpecialShopView
extends PanelContainer

## 特殊商店可复用视图：显示组合和代币，只发出采购／离开请求。
## 实际协调者负责事务与存档，视图不会自行发卡或扣本局金币。
signal purchase_requested(offer_id: String)
signal leave_requested

const PANEL_SIZE := Vector2(880, 370) # 模型面板的最小宽高
const CONTENT_GAP: int = 18 # 组合商品与说明之间的间距
const OFFER_WIDTH: int = 260 # 每组商品的最小宽度
var session: SpecialShopSession
var purchase_buttons: Dictionary = {}
var balance_label: Label


func bind_session(value: SpecialShopSession) -> void:
	session = value
	refresh()


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	purchase_buttons.clear()
	theme = Theme.new()
	theme.default_font = preload("res://assets/fonts/chill_7.ttf")
	custom_minimum_size = PANEL_SIZE
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(body)
	var title := Label.new()
	title.text = "特殊商店"
	body.add_child(title)
	balance_label = Label.new()
	if session == null:
		balance_label.text = "尚未进入"
		body.add_child(balance_label)
		return
	balance_label.text = "%s：%d　　离店时清空" % [session.currency_name, session.balance]
	body.add_child(balance_label)
	if session.total_purchase_limit > 0:
		var limit_label := Label.new()
		limit_label.text = "已采购%d／%d组" % [session.get_purchase_count(), session.total_purchase_limit]
		body.add_child(limit_label)
	var offers := HBoxContainer.new()
	offers.add_theme_constant_override("separation", CONTENT_GAP)
	body.add_child(offers)
	for offer: Dictionary in session.get_offers():
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = OFFER_WIDTH
		column.add_theme_constant_override("separation", CONTENT_GAP)
		offers.add_child(column)
		var name_label := Label.new()
		name_label.text = String(offer.name)
		column.add_child(name_label)
		for item: Dictionary in offer.items:
			var item_label := Label.new()
			item_label.text = "%s ×%d" % [String(item.name), int(item.amount)]
			column.add_child(item_label)
		var button := Button.new()
		var offer_id := String(offer.offer_id)
		button.text = "整组选取　%d %s" % [int(offer.price), session.currency_name]
		button.disabled = not session.can_purchase(offer_id)
		button.pressed.connect(_request_purchase.bind(offer_id))
		purchase_buttons[offer_id] = button
		column.add_child(button)
	var leave_button := Button.new()
	leave_button.text = "离开特殊商店"
	leave_button.disabled = session.phase != SpecialShopSession.Phase.OPEN
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	body.add_child(leave_button)


func _request_purchase(offer_id: String) -> void:
	if session != null and session.can_purchase(offer_id):
		purchase_requested.emit(offer_id)
