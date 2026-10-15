class_name MazeRewardService
extends RefCounted

## 生成已确认的迷宫奖励配方、给拥有随从添加事件伤势。
## 不修改金币、刮刀或英雄经验；Main的迷宫协调器在结算入口统一提交。
const CONFIG_PATH := "res://data/demo2/ioann_warden_config.json"
var config: Dictionary = {}


func load_config() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or not parsed.has("experience") or not parsed.has("battle_rewards") or not parsed.has("wound_event"):
		return false
	config = parsed
	return true


func build_battle_reward(floor_number: int, won: bool, source_rng: RandomNumberGenerator) -> Dictionary:
	if floor_number < 1 or source_rng == null or config.is_empty():
		return {"success": false}
	var next_rng := RandomNumberGenerator.new()
	next_rng.seed = source_rng.seed
	next_rng.state = source_rng.state
	var experience: Dictionary = config.experience
	var economy: Dictionary = config.battle_rewards
	var result := {"success": true, "gold": 0, "experience": 0, "drop": {}}
	if not won:
		result.gold = next_rng.randi_range(int(economy.defeat_gold_min), int(economy.defeat_gold_max))
		result.experience = floor_number * int(experience.defeat_per_floor)
	else:
		result.gold = int(economy.victory_gold)
		result.experience = int(experience.victory_base) + (floor_number - 1) * int(experience.victory_per_floor)
		var weights: Dictionary = economy.drop_weights
		var roll := next_rng.randi_range(1, int(weights.gold) + int(weights.scraper) + int(weights.emblem))
		if roll <= int(weights.gold):
			var amount := next_rng.randi_range(int(economy.drop_gold_min), int(economy.drop_gold_max))
			result.drop = {"kind": "gold", "amount": amount}
			result.gold += amount
		elif roll <= int(weights.gold) + int(weights.scraper):
			result.drop = {"kind": "scraper", "amount": 1}
		else:
			var pool := EmblemLibraryData.get_basic_emblem_ids()
			if pool.is_empty():
				return {"success": false}
			result.drop = {"kind": "emblem", "amount": 1, "emblem_id": String(pool[next_rng.randi_range(0, pool.size() - 1)])}
	source_rng.state = next_rng.state
	return result


func apply_random_event_wound(event_id: String, owned_cards: Array[OwnedCard], source_rng: RandomNumberGenerator) -> Dictionary:
	if event_id.is_empty() or source_rng == null or config.is_empty():
		return {"success": false}
	var candidates: Array[OwnedCard] = []
	var instance_id := "event_wound:%s" % event_id
	for owned: OwnedCard in owned_cards:
		if owned == null or owned.card_data == null or owned.card_data.card_type != CardData.CardType.MINION:
			continue
		var has_space := false
		for wound: Dictionary in owned.wound_slots:
			if String(wound.get("instance_id", "")) == instance_id:
				return {"success": false, "reason": "already_applied"}
			if wound.is_empty():
				has_space = true
		if has_space:
			candidates.append(owned)
	# 无目标不抽随机数、不增金币、不生成工具箱伤势。
	if candidates.is_empty():
		return {"success": true, "applied": false}
	var pool: Array = config.wound_event.wound_ids
	if pool.is_empty():
		return {"success": false}
	var target: OwnedCard = candidates[source_rng.randi_range(0, candidates.size() - 1)]
	var empty_slots: Array[int] = []
	for index: int in target.wound_slots.size():
		if target.wound_slots[index].is_empty():
			empty_slots.append(index)
	var index: int = empty_slots[source_rng.randi_range(0, empty_slots.size() - 1)]
	var wound_id := String(pool[source_rng.randi_range(0, pool.size() - 1)])
	target.set_wound_slot(index, {"wound_id": wound_id, "instance_id": instance_id, "level": 1, "temporary": false, "source": "maze_event"})
	return {"success": true, "applied": true, "owned_instance_id": String(target.instance_id), "slot_index": index, "wound_id": wound_id}
