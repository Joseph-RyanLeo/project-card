class_name SpecialShopSession
extends RefCounted

## 一次特殊商店访问的商品组合、独立货币和采购凭证。
## 本类不操作本局金币或收藏；协调者须将采购、发货和存档作为同一事务提交。
enum Phase { UNOPENED, OPEN, CLOSED }
const DEFAULT_STOCK: int = 1 # 每组默认限购一次；具体店铺可显式覆盖stock

var phase: Phase = Phase.UNOPENED
var visit_id: String = ""
var currency_name: String = ""
var initial_currency: int = 0
var balance: int = 0
var total_purchase_limit: int = 0 # 0不额外限制总组数，仅受余额与各组库存限制
var _offers: Array[Dictionary] = []


func enter(id: String, currency: String, amount: int, offers: Array[Dictionary], purchase_limit: int = 0) -> bool:
	if phase != Phase.UNOPENED or id.is_empty() or currency.is_empty() or amount < 0 or purchase_limit < 0:
		return false
	var seen: Array[String] = []
	for offer: Dictionary in offers:
		if not _valid_offer(offer) or int(offer.purchased) != 0 or String(offer.offer_id) in seen:
			return false
		seen.append(String(offer.offer_id))
	visit_id = id
	currency_name = currency
	initial_currency = amount
	balance = amount
	total_purchase_limit = purchase_limit
	for offer: Dictionary in offers:
		_offers.append(_normalized_offer(offer))
	phase = Phase.OPEN
	return true


func get_offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_offers.duplicate(true))
	return result


func can_purchase(offer_id: String) -> bool:
	if phase != Phase.OPEN:
		return false
	if total_purchase_limit > 0 and get_purchase_count() >= total_purchase_limit:
		return false
	for offer: Dictionary in _offers:
		if String(offer.offer_id) == offer_id:
			return int(offer.purchased) < int(offer.stock) and balance >= int(offer.price)
	return false


func get_purchase_count() -> int:
	var count := 0
	for offer: Dictionary in _offers:
		count += int(offer.purchased)
	return count


func purchase(offer_id: String) -> Dictionary:
	if not can_purchase(offer_id):
		return {"success": false}
	for offer: Dictionary in _offers:
		if String(offer.offer_id) != offer_id:
			continue
		# 商品组合不可拆买：一次扣费，返回完整发货清单。
		balance -= int(offer.price)
		offer.purchased = int(offer.purchased) + 1
		return {
			"success": true,
			"purchase_id": "%s:%s:%d" % [visit_id, offer_id, int(offer.purchased)],
			"items": (offer.items as Array).duplicate(true),
			"paid": int(offer.price),
		}
	return {"success": false}


func leave() -> bool:
	if phase != Phase.OPEN:
		return false
	balance = 0
	phase = Phase.CLOSED
	return true


func capture_state() -> Dictionary:
	return {
		"state_version": 1, "phase": int(phase), "visit_id": visit_id,
		"currency_name": currency_name, "initial_currency": initial_currency,
		"balance": balance, "offers": get_offers(), "total_purchase_limit": total_purchase_limit,
	}


func restore_state(snapshot: Dictionary) -> bool:
	if snapshot.get("state_version") != 1:
		return false
	for key: String in ["phase", "initial_currency", "balance"]:
		if not _whole_nonnegative(snapshot.get(key)):
			return false
	var saved_phase := int(snapshot.phase)
	var saved_id: Variant = snapshot.get("visit_id")
	var saved_currency: Variant = snapshot.get("currency_name")
	var saved_offers: Variant = snapshot.get("offers")
	var saved_limit: Variant = snapshot.get("total_purchase_limit", 0)
	if not _whole_nonnegative(saved_limit):
		return false
	if saved_phase not in [Phase.UNOPENED, Phase.OPEN, Phase.CLOSED] or not saved_id is String or not saved_currency is String or not saved_offers is Array:
		return false
	var spent := 0
	var purchase_count := 0
	var seen: Array[String] = []
	var checked: Array[Dictionary] = []
	for value: Variant in saved_offers:
		if not value is Dictionary or not _valid_offer(value) or String(value.offer_id) in seen:
			return false
		seen.append(String(value.offer_id))
		spent += int(value.price) * int(value.purchased)
		purchase_count += int(value.purchased)
		checked.append(_normalized_offer(value))
	if spent > int(snapshot.initial_currency):
		return false
	if int(saved_limit) > 0 and purchase_count > int(saved_limit):
		return false
	if saved_phase == Phase.UNOPENED:
		if not saved_id.is_empty() or not saved_currency.is_empty() or not checked.is_empty() or int(snapshot.initial_currency) != 0 or int(snapshot.balance) != 0 or int(saved_limit) != 0:
			return false
	else:
		if saved_id.is_empty() or saved_currency.is_empty():
			return false
		var expected_balance := int(snapshot.initial_currency) - spent if saved_phase == Phase.OPEN else 0
		if int(snapshot.balance) != expected_balance:
			return false
	# 先校验再替换，拒绝篡改余额和不完整组合时保留原状态。
	phase = saved_phase as Phase
	visit_id = saved_id
	currency_name = saved_currency
	initial_currency = int(snapshot.initial_currency)
	balance = int(snapshot.balance)
	total_purchase_limit = int(saved_limit)
	_offers = checked
	return true


func _valid_offer(offer: Dictionary) -> bool:
	if not _plain_value(offer):
		return false
	if not offer.get("offer_id") is String or String(offer.offer_id).is_empty() or not offer.get("name") is String or String(offer.name).is_empty():
		return false
	for key: String in ["price", "purchased"]:
		if not _whole_nonnegative(offer.get(key)):
			return false
	var stock: Variant = offer.get("stock", DEFAULT_STOCK)
	if not _whole_nonnegative(stock) or int(stock) == 0 or int(offer.purchased) > int(stock):
		return false
	var items: Variant = offer.get("items")
	if not items is Array or items.is_empty():
		return false
	for item: Variant in items:
		if not item is Dictionary or not item.get("kind") is String or String(item.kind) not in ["card", "card_pack", "emblem", "scraper"]:
			return false
		if not _whole_nonnegative(item.get("amount")) or int(item.amount) == 0:
			return false
		if not item.get("name") is String or String(item.name).is_empty():
			return false
	return true


func _whole_nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value))


func _normalized_offer(offer: Dictionary) -> Dictionary:
	var result := offer.duplicate(true)
	# JSON读出的数字是float，验证通过后还原采购所需的整数类型。
	result.stock = int(result.get("stock", DEFAULT_STOCK))
	for key: String in ["price", "purchased"]:
		result[key] = int(result[key])
	for item: Dictionary in result.items:
		item.amount = int(item.amount)
	return result


func _plain_value(value: Variant) -> bool:
	# 商品保存稳定ID和普通数据，不能把Resource／节点引用写进JSON。
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain_value(value[key]):
				return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain_value(item):
				return false
		return true
	return value == null or value is String or value is bool or value is int or (value is float and is_finite(value))
