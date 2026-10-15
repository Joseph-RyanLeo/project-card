extends Control

## 独立模型演示，商品只是用户示例，不是至高天正式卡池，也不写当前本局。
var shop := SpecialShopSession.new()
var view := SpecialShopView.new()
var result_label := Label.new()


func _ready() -> void:
	var body := VBoxContainer.new()
	body.position = Vector2(100, 90) # 模型内容在1280×720窗口中的起点
	body.add_theme_constant_override("separation", 24) # 面板与说明的间距
	add_child(body)
	var caption := Label.new()
	caption.text = "特殊商店模型演示（至高天内容待配置）"
	body.add_child(caption)
	var examples: Array[Dictionary] = [
		{"offer_id": "two_iii", "name": "双卡组合", "price": 1, "stock": 1, "purchased": 0,
			"items": [{"kind": "card", "name": "Ⅲ级卡牌", "amount": 2}]},
		{"offer_id": "one_iv", "name": "单卡组合", "price": 1, "stock": 1, "purchased": 0,
			"items": [{"kind": "card", "name": "Ⅳ级卡牌", "amount": 1}]},
		{"offer_id": "ii_and_pack", "name": "卡牌与卡包组合", "price": 1, "stock": 1, "purchased": 0,
			"items": [{"kind": "card", "name": "Ⅱ级卡牌", "amount": 3}, {"kind": "card_pack", "name": "小卡包", "amount": 1}]},
	]
	shop.enter("model_visit", "演示代币", 1, examples)
	view.purchase_requested.connect(_purchase)
	view.leave_requested.connect(_leave)
	body.add_child(view)
	view.bind_session(shop)
	result_label.text = "组合只能整组选取；演示入店获得1枚代币，三组均定价1。"
	body.add_child(result_label)
	var sentry_row := HBoxContainer.new()
	sentry_row.add_theme_constant_override("separation", 20) # 四款哨位预览的间距
	body.add_child(sentry_row)
	for index: int in 4:
		var indicator := SentryIndicator.new()
		indicator.visual_variant = index
		sentry_row.add_child(SentryIndicatorStyle.create_visual(indicator))


func _purchase(offer_id: String) -> void:
	var receipt := shop.purchase(offer_id)
	if not receipt.success:
		return
	var names: PackedStringArray = []
	for item: Dictionary in receipt.items:
		names.append("%s×%d" % [String(item.name), int(item.amount)])
	result_label.text = "模型选取结果：%s（未向当前本局发卡）" % "、".join(names)
	view.refresh()


func _leave() -> void:
	shop.leave()
	result_label.text = "已离店，演示代币清空。"
	view.refresh()
