class_name RunRewardState
extends RefCounted

## 已经写入本局、但不属于某张卡牌的奖励状态。
## 随机随从请求先原样进入待解析队列；D2-7 拥有正式卡池与唯一性规则后再决定结果，
## 不能在当前阶段用一个临时随机 CardData 冒充真实奖励。

var gold: int = 0
var pending_random_card_requests: Array[Dictionary] = []
var pending_emblem_instances: Array[Dictionary] = []
var pending_ground_items: Array[Dictionary] = []
var pending_next_level_from_id: StringName = &"" # 战斗已提交但关卡尚未推进；读档后仍先处理本场奖励


func add_gold(amount: int) -> bool:
	if amount <= 0:
		return false
	gold += amount
	return true


func apply_gold_delta(amount: int) -> int:
	var previous := gold
	gold = maxi(gold + amount, 0)
	return gold - previous


func add_ground_item(item: Dictionary) -> bool:
	var item_id := StringName(String(item.get("ground_id", "")))
	if item_id.is_empty() or String(item.get("item_id", "")).is_empty():
		return false
	for existing: Dictionary in pending_ground_items:
		if StringName(String(existing.get("ground_id", ""))) == item_id:
			return false
	pending_ground_items.append(item.duplicate(true))
	return true


func remove_ground_item(item_id: StringName) -> Dictionary:
	for index: int in pending_ground_items.size():
		if StringName(String(pending_ground_items[index].get("ground_id", ""))) == item_id:
			return pending_ground_items.pop_at(index)
	return {}


func enqueue_random_card_request(entry: Dictionary) -> bool:
	var entry_id := entry.get("entry_id", &"") as StringName
	var amount := int(entry.get("amount", 0))
	if entry_id.is_empty() or amount <= 0:
		return false
	for queued: Dictionary in pending_random_card_requests:
		if queued.get("entry_id") == entry_id:
			return false
	pending_random_card_requests.append({
		"entry_id": entry_id,
		"battle_instance_id": entry.get("battle_instance_id", &""),
		"amount": amount,
		"effect_id": entry.get("effect_id", &""),
		"parameters": (entry.get("parameters", {}) as Dictionary).duplicate(true),
	})
	return true


func get_pending_random_card_count() -> int:
	var result := 0
	for request: Dictionary in pending_random_card_requests:
		result += int(request.get("amount", 0))
	return result


func enqueue_emblem_instance(entry: Dictionary) -> bool:
	var entry_id := entry.get("entry_id", &"") as StringName
	var parameters := entry.get("parameters", {}) as Dictionary
	var instance_id := parameters.get("emblem_instance_id", &"") as StringName
	var emblem_id := parameters.get("emblem_id", &"") as StringName
	if entry_id.is_empty() or instance_id.is_empty() or emblem_id.is_empty():
		return false
	for queued: Dictionary in pending_emblem_instances:
		if queued.get("entry_id") == entry_id or queued.get("emblem_instance_id") == instance_id:
			return false
	pending_emblem_instances.append({
		"entry_id": entry_id,
		"battle_instance_id": entry.get("battle_instance_id", &""),
		"emblem_instance_id": instance_id,
		"emblem_id": emblem_id,
		"source": parameters.get("source", ""),
	})
	return true


func drain_emblem_instances_for_battle(battle_instance_id: StringName) -> Array[Dictionary]:
	var result := get_emblem_instances_for_battle(battle_instance_id)
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in pending_emblem_instances:
		if entry.get("battle_instance_id", &"") != battle_instance_id:
			remaining.append(entry)
	pending_emblem_instances = remaining
	return result


func get_emblem_instances_for_battle(battle_instance_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in pending_emblem_instances:
		if entry.get("battle_instance_id", &"") == battle_instance_id:
			result.append(entry.duplicate(true))
	return result


func capture_state() -> Dictionary:
	return {
		"gold": gold,
		"pending_random_card_requests": pending_random_card_requests.duplicate(true),
		"pending_emblem_instances": pending_emblem_instances.duplicate(true),
		"pending_ground_items": pending_ground_items.duplicate(true),
		"pending_next_level_from_id": pending_next_level_from_id,
	}


func restore_state(snapshot: Dictionary) -> void:
	gold = int(snapshot.get("gold", 0))
	pending_random_card_requests.assign(
		(snapshot.get("pending_random_card_requests", []) as Array).duplicate(true)
	)
	pending_emblem_instances.assign(
		(snapshot.get("pending_emblem_instances", []) as Array).duplicate(true)
	)
	pending_ground_items.assign((snapshot.get("pending_ground_items", []) as Array).duplicate(true))
	pending_next_level_from_id = StringName(String(snapshot.get("pending_next_level_from_id", "")))
