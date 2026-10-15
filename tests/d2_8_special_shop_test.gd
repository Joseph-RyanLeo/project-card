extends SceneTree

const Session = preload("res://scripts/data/special_shop_session.gd")
const View = preload("res://scripts/ui/special_shop_view.gd")
const Lab = preload("res://scenes/tools/SpecialShopLab.tscn")
const SaveService = preload("res://scripts/data/run_save_service.gd")
const SAVE_PATH := "/private/tmp/project-card-d2-8-special-shop.json"
var assertions := 0
var failures := 0
var requests: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _examples() -> Array[Dictionary]:
	# 仅用于模型验证的明确商品规格，不是至高天正式配置。
	return [
		{"offer_id": "two_cards", "name": "双卡", "price": 2, "stock": 1, "purchased": 0,
			"items": [{"kind": "card", "name": "Ⅲ级卡", "amount": 2}]},
		{"offer_id": "cards_pack", "name": "卡与包", "price": 1, "stock": 2, "purchased": 0,
			"items": [{"kind": "card", "name": "Ⅱ级卡", "amount": 3}, {"kind": "card_pack", "name": "小包", "amount": 1}]},
	]


func _run() -> void:
	_test_default_stock_and_total_limit()
	var shop := Session.new()
	_expect(shop.restore_state(shop.capture_state()), "未入店状态可往返")
	var offers := _examples()
	_expect(shop.enter("visit_a", "祝福凭证", 3, offers), "入店发放指定独立货币")
	offers[0].items[0].amount = 9
	_expect(int(shop.get_offers()[0].items[0].amount) == 2, "外部配置修改不污染店内商品组合")
	_expect(not shop.enter("visit_a", "祝福凭证", 3, _examples()) and shop.balance == 3, "重复入店不补币也不重置商品")
	var gold := RunRewardState.new()
	gold.gold = 999
	var receipt := shop.purchase("two_cards")
	_expect(receipt.success and shop.balance == 1 and gold.gold == 999, "采购仅消耗特殊货币，本局金币不变")
	_expect(receipt.items.size() == 1 and int(receipt.items[0].amount) == 2, "绑定两张卡一次采购完整交付清单")
	_expect(not shop.purchase("two_cards").success and shop.balance == 1, "库存售罄不能重复采购")
	var second := shop.purchase("cards_pack")
	_expect(second.success and second.items.size() == 2 and int(second.items[0].amount) == 3 and int(second.items[1].amount) == 1, "卡牌加卡包组成一个不可拆买的商品")
	_expect(second.purchase_id != receipt.purchase_id, "每笔采购有稳定的唯一凭证")
	_expect(shop.balance == 0 and not shop.purchase("cards_pack").success and gold.gold == 999, "特殊货币不足即使金币充足也无法购买")
	receipt.items[0].amount = 20
	_expect(int(shop.get_offers()[0].items[0].amount) == 2, "发货清单是副本，不修改保存的商品")
	var save := SaveService.new()
	var before := shop.capture_state()
	_expect(save.save_checkpoint(SAVE_PATH, {"schema_version": SaveService.SCHEMA_VERSION, "special_shop": before}) == OK, "保存模型真实JSON文件")
	var loaded := save.load_checkpoint(SAVE_PATH)
	var restored := Session.new()
	_expect(loaded.success and restored.restore_state(loaded.checkpoint.special_shop), "读档恢复特殊商店")
	_expect(restored.capture_state() == before and not restored.enter("visit_a", "祝福凭证", 3, _examples()), "读档不重发货币、不重置售出状态")
	var bad := before.duplicate(true)
	bad.balance = 1
	_expect(not restored.restore_state(bad) and restored.capture_state() == before, "余额与实际采购不符拒绝恢复且保留原状态")
	bad = before.duplicate(true)
	bad.offers[0].items = []
	_expect(not restored.restore_state(bad), "不完整商品组合不能载入")
	bad = before.duplicate(true)
	bad.offers[0].purchased = 0.5
	_expect(not restored.restore_state(bad), "小数采购次数不能载入")
	bad = before.duplicate(true)
	bad.offers[1].offer_id = "two_cards"
	_expect(not restored.restore_state(bad), "重复商品身份不能载入")
	bad = before.duplicate(true)
	bad.offers[0].items[0].resource = load("res://resources/cards/musketeer.tres")
	_expect(not restored.restore_state(bad), "商品不可携带无法序列化的Resource引用")
	var unspent := Session.new()
	unspent.enter("visit_b", "另一货币", 8, _examples())
	_expect(unspent.leave() and unspent.balance == 0, "未花完的余额离店清空")
	_expect(not unspent.purchase("two_cards").success and not unspent.leave(), "离店后不能继续交易或重复离店")
	_expect(not unspent.enter("visit_b", "另一货币", 8, _examples()), "同一次访问离店后不能再次入店领奖")
	var closed := Session.new()
	_expect(closed.restore_state(JSON.parse_string(JSON.stringify(unspent.capture_state()))) and closed.balance == 0 and closed.phase == Session.Phase.CLOSED, "离店状态JSON往返不恢复剩余代币")
	var malformed := _examples()
	malformed[0].items[0].amount = 0
	var invalid := Session.new()
	_expect(not invalid.enter("bad", "币", 1, malformed) and invalid.phase == Session.Phase.UNOPENED, "非法规格拒绝入店且不领取货币")
	var view_shop := Session.new()
	view_shop.enter("view_visit", "测试币", 3, _examples())
	var view := View.new()
	root.add_child(view)
	view.bind_session(view_shop)
	view.purchase_requested.connect(func(id: String) -> void: requests.append(id))
	(view.purchase_buttons.two_cards as Button).pressed.emit()
	_expect(requests == ["two_cards"] and view_shop.balance == 3, "实际视图按钮发出采购请求，由协调者提交事务")
	view_shop.purchase(requests[0])
	view.refresh()
	_expect((view.purchase_buttons.two_cards as Button).disabled and view.balance_label.text.contains("1"), "正式模型变化刷新售罄按钮与余额")
	view.free()
	var lab := Lab.instantiate()
	root.add_child(lab)
	await process_frame
	_expect(lab.shop.balance == 1 and lab.view.purchase_buttons.size() == 3, "模型场景加载三种示例组合和独立货币")
	(lab.view.purchase_buttons.ii_and_pack as Button).pressed.emit()
	_expect(lab.shop.balance == 0 and lab.result_label.text.contains("Ⅱ级卡牌×3") and lab.result_label.text.contains("小卡包×1"), "实际演示按钮整组采购并展示结果")
	lab._leave()
	_expect(lab.shop.phase == Session.Phase.CLOSED and lab.shop.balance == 0, "演示离店入口清空货币")
	lab.free()
	await process_frame
	DirAccess.remove_absolute(SAVE_PATH)
	print("D2-8 special shop: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _test_default_stock_and_total_limit() -> void:
	var offers := _examples()
	offers[0].erase("stock")
	var default_shop := Session.new()
	_expect(default_shop.enter("defaults", "试验币", 10, offers), "未指定每组库存时采用已确认默认值")
	_expect(int(default_shop.get_offers()[0].stock) == 1 and default_shop.total_purchase_limit == 0, "默认每组一次，无额外总组数上限")
	_expect(default_shop.purchase("two_cards").success and not default_shop.purchase("two_cards").success and default_shop.balance == 8, "余额充足时默认限购仍生效")
	_expect(default_shop.purchase("cards_pack").success and default_shop.purchase("cards_pack").success, "具体店铺可显式覆盖每组库存")
	var limited := Session.new()
	_expect(limited.enter("limited", "试验币", 10, _examples(), 1), "具体店铺可配置总采购组数上限")
	_expect(limited.purchase("cards_pack").success and not limited.can_purchase("two_cards") and limited.balance == 9, "达到总上限后其他组合也不可采购")
	var before := limited.capture_state()
	var restored := Session.new()
	_expect(restored.restore_state(JSON.parse_string(JSON.stringify(before))) and restored.get_purchase_count() == 1 and not restored.can_purchase("two_cards"), "读档保留总上限和已采购次数")
	var bad := before.duplicate(true)
	bad.total_purchase_limit = 0.5
	_expect(not restored.restore_state(bad) and restored.capture_state() == before, "小数总上限拒绝载入且原状态不变")
	bad = default_shop.capture_state()
	bad.total_purchase_limit = 1
	_expect(not restored.restore_state(bad), "已采购次数超过存档总上限时拒绝恢复")
