class_name BattleSettlementService
extends RefCounted

## 正常战后唯一写回入口。
## 顺序固定为：检查重复与记录合法性 → 恢复战前收藏 → 应用全部变化 →
## 登记整场已提交。任一步失败都会回滚本次事务，不能留下半份奖励。

const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const BattlePreparationSnapshot = preload("res://scripts/data/battle_preparation_snapshot.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleOwnedCardChangeLedger = preload("res://scripts/battle/battle_owned_card_change_ledger.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")

const STATUS_COMMITTED: StringName = &"committed"
const STATUS_ALREADY_COMMITTED: StringName = &"already_committed"
const STATUS_FAILED: StringName = &"failed"


func settle(
	snapshot: BattlePreparationSnapshot,
	growth_entries: Array[Dictionary],
	reward_entries: Array[Dictionary],
	owned_collection: OwnedCardCollection,
	reward_state: RunRewardState,
	journal: RunSettlementJournal,
	owned_change_entries: Array[Dictionary] = []
) -> Dictionary:
	if (
		snapshot == null
		or snapshot.is_empty()
		or owned_collection == null
		or reward_state == null
		or journal == null
	):
		return _failure("missing_settlement_context")
	var battle_id := snapshot.battle_instance_id
	if journal.is_committed(battle_id):
		return {
			"success": true,
			"status": STATUS_ALREADY_COMMITTED,
			"battle_instance_id": battle_id,
			"growth_applied": 0,
			"owned_changes_applied": 0,
			"emblem_progress_added": 0,
			"temporary_progress_skipped": 0,
			"spell_durability_spent": 0,
			"spent_spells_removed": 0,
			"gold_added": 0,
			"random_card_requests_queued": 0,
		}
	var validation := _validate_entries(
		battle_id,
		growth_entries,
		reward_entries,
		owned_change_entries,
		owned_collection
	)
	if not bool(validation.get("success", false)):
		return validation
	if not snapshot.restore_collection(owned_collection):
		return _failure("snapshot_restore_failed", battle_id)

	var rollback_collection := owned_collection.capture_state()
	var rollback_rewards := reward_state.capture_state()
	var growth_applied := 0
	var owned_changes_applied := 0
	var equipment_consumed := 0
	var emblem_progress_added := 0
	var temporary_progress_skipped := 0
	var spell_durability_spent := 0
	var spent_spells_removed := 0
	var gold_added := 0
	var random_requests_queued := 0
	for entry: Dictionary in growth_entries:
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		var instance_id := entry.get("owned_card_instance_id", &"") as StringName
		if instance_id.is_empty():
			# 战斗召唤物没有收藏实例，设计上战后消失；其“永久”成长不能凭空进入收藏。
			continue
		var owned_card := owned_collection.get_by_instance_id(instance_id)
		if owned_card == null or not owned_card.apply_permanent_growth(
			_map_growth_stat(entry.get("stat", &"") as StringName),
			float(entry.get("amount", 0.0))
		):
			_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
			return _failure("growth_apply_failed", battle_id)
		growth_applied += 1
	for entry: Dictionary in owned_change_entries:
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		if entry.get("kind") == BattleOwnedCardChangeLedger.KIND_CONSUME_EQUIPMENT:
			continue
		var change_result := _apply_owned_change(entry, owned_collection)
		if not bool(change_result.get("success", false)):
			_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
			return _failure("owned_change_apply_failed", battle_id)
		owned_changes_applied += int(change_result.get("applied", 0))
		emblem_progress_added += int(change_result.get("progress_added", 0))
		temporary_progress_skipped += int(change_result.get("temporary_progress_skipped", 0))
	for spell_instance_id: StringName in snapshot.get_prepared_spell_instance_ids():
		var owned_spell := owned_collection.get_by_instance_id(spell_instance_id)
		if (
			owned_spell == null
			or owned_spell.card_data.card_type != CardData.CardType.SPELL
			or owned_spell.spell_durability <= 0
		):
			_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
			return _failure("spell_durability_apply_failed", battle_id)
		owned_spell.spell_durability -= 1
		spell_durability_spent += 1
		if owned_spell.spell_durability == 0:
			owned_collection.remove_by_instance_id(spell_instance_id)
			spent_spells_removed += 1
	for entry: Dictionary in reward_entries:
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		var kind := entry.get("kind", &"") as StringName
		var amount := int(entry.get("amount", 0))
		match kind:
			BattleRunRewardLedger.KIND_GOLD:
				if not reward_state.add_gold(amount):
					_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
					return _failure("gold_apply_failed", battle_id)
				gold_added += amount
			BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST:
				if not reward_state.enqueue_random_card_request(entry):
					_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
					return _failure("random_request_apply_failed", battle_id)
				random_requests_queued += amount
	# 征兵册先生成随机随从请求，再移除源装备；即使合法奖励池为空也照常消耗。
	for entry: Dictionary in owned_change_entries:
		if (
			int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER
			or entry.get("kind") != BattleOwnedCardChangeLedger.KIND_CONSUME_EQUIPMENT
		):
			continue
		if owned_collection.remove_by_instance_id(
			entry.get("owned_card_instance_id", &"") as StringName
		) == null:
			_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
			return _failure("equipment_consumption_failed", battle_id)
		equipment_consumed += 1
	if not journal.mark_committed(battle_id):
		_restore_transaction(owned_collection, rollback_collection, reward_state, rollback_rewards)
		return _failure("commit_guard_failed", battle_id)
	return {
		"success": true,
		"status": STATUS_COMMITTED,
		"battle_instance_id": battle_id,
		"growth_applied": growth_applied,
		"owned_changes_applied": owned_changes_applied,
		"equipment_consumed": equipment_consumed,
		"emblem_progress_added": emblem_progress_added,
		"temporary_progress_skipped": temporary_progress_skipped,
		"spell_durability_spent": spell_durability_spent,
		"spent_spells_removed": spent_spells_removed,
		"gold_added": gold_added,
		"random_card_requests_queued": random_requests_queued,
	}


func _validate_entries(
	battle_id: StringName,
	growth_entries: Array[Dictionary],
	reward_entries: Array[Dictionary],
	owned_change_entries: Array[Dictionary],
	owned_collection: OwnedCardCollection
) -> Dictionary:
	var seen_entry_ids: Dictionary = {}
	for entry: Dictionary in growth_entries:
		if not _validate_common_entry(entry, battle_id, seen_entry_ids):
			return _failure("invalid_growth_entry_identity", battle_id)
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		var stat := entry.get("stat", &"") as StringName
		if _map_growth_stat(stat).is_empty() or is_zero_approx(float(entry.get("amount", 0.0))):
			return _failure("invalid_growth_entry_value", battle_id)
		var instance_id := entry.get("owned_card_instance_id", &"") as StringName
		if not instance_id.is_empty() and owned_collection.get_by_instance_id(instance_id) == null:
			return _failure("missing_growth_owner", battle_id)
	var occupied_slot_changes: Dictionary = {}
	var consumed_equipment_ids: Dictionary = {}
	for entry: Dictionary in owned_change_entries:
		if not _validate_common_entry(entry, battle_id, seen_entry_ids):
			return _failure("invalid_owned_change_entry_identity", battle_id)
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		var instance_id := entry.get("owned_card_instance_id", &"") as StringName
		var owned_card := owned_collection.get_by_instance_id(instance_id)
		if owned_card == null:
			return _failure("missing_owned_change_target", battle_id)
		var kind := entry.get("kind", &"") as StringName
		var parameters := entry.get("parameters", {}) as Dictionary
		match kind:
			BattleOwnedCardChangeLedger.KIND_CONSUME_EQUIPMENT:
				if (
					owned_card.card_data.card_type != CardData.CardType.EQUIPMENT
					or consumed_equipment_ids.has(instance_id)
				):
					return _failure("invalid_equipment_consumption", battle_id)
				consumed_equipment_ids[instance_id] = true
			BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT, BattleOwnedCardChangeLedger.KIND_SET_EMBLEM_SLOT:
				var slot_index := int(parameters.get("slot_index", -1))
				var slot_count := (
					owned_card.wound_slots.size()
					if kind == BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT
					else owned_card.emblem_slots.size()
				)
				var slot_key := "%s:%s:%d" % [instance_id, kind, slot_index]
				if slot_index < 0 or slot_index >= slot_count or occupied_slot_changes.has(slot_key):
					return _failure("invalid_owned_change_slot", battle_id)
				occupied_slot_changes[slot_key] = true
				var slot_state := parameters.get("slot_state", {}) as Dictionary
				if not _is_valid_slot_state(kind, slot_state):
					return _failure("invalid_owned_change_slot_state", battle_id)
			BattleOwnedCardChangeLedger.KIND_ADD_EMBLEM_PROGRESS:
				if (
					(parameters.get("emblem_instance_id", &"") as StringName).is_empty()
					or int(parameters.get("amount", 0)) <= 0
				):
					return _failure("invalid_emblem_progress", battle_id)
			_:
				return _failure("invalid_owned_change_kind", battle_id)
	for entry: Dictionary in reward_entries:
		if not _validate_common_entry(entry, battle_id, seen_entry_ids):
			return _failure("invalid_reward_entry_identity", battle_id)
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		if (
			entry.get("kind", &"") not in [
				BattleRunRewardLedger.KIND_GOLD,
				BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST,
			]
			or int(entry.get("amount", 0)) <= 0
		):
			return _failure("invalid_reward_entry_value", battle_id)
	return {"success": true}


func _is_valid_slot_state(kind: StringName, slot_state: Dictionary) -> bool:
	if slot_state.is_empty():
		return true
	if kind == BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT:
		return (
			not (slot_state.get("wound_id", &"") as StringName).is_empty()
			and int(slot_state.get("level", 0)) > 0
		)
	return (
		not (slot_state.get("emblem_id", &"") as StringName).is_empty()
		and not (slot_state.get("instance_id", &"") as StringName).is_empty()
	)


func _apply_owned_change(
	entry: Dictionary,
	owned_collection: OwnedCardCollection
) -> Dictionary:
	var owned_card := owned_collection.get_by_instance_id(
		entry.get("owned_card_instance_id", &"") as StringName
	)
	if owned_card == null:
		return {"success": false}
	var kind := entry.get("kind", &"") as StringName
	var parameters := entry.get("parameters", {}) as Dictionary
	match kind:
		BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT:
			return {
				"success": owned_card.set_wound_slot(
					int(parameters.get("slot_index", -1)),
					parameters.get("slot_state", {}) as Dictionary
				),
				"applied": 1,
			}
		BattleOwnedCardChangeLedger.KIND_SET_EMBLEM_SLOT:
			return {
				"success": owned_card.set_emblem_slot(
					int(parameters.get("slot_index", -1)),
					parameters.get("slot_state", {}) as Dictionary
				),
				"applied": 1,
			}
		BattleOwnedCardChangeLedger.KIND_ADD_EMBLEM_PROGRESS:
			var progress_result := owned_card.add_emblem_progress(
				parameters.get("emblem_instance_id", &"") as StringName,
				int(parameters.get("amount", 0))
			)
			return {
				"success": progress_result >= 0,
				"applied": 1 if progress_result > 0 else 0,
				"progress_added": int(parameters.get("amount", 0)) if progress_result > 0 else 0,
				"temporary_progress_skipped": 1 if progress_result == 0 else 0,
			}
	return {"success": false}


func _validate_common_entry(
	entry: Dictionary,
	battle_id: StringName,
	seen_entry_ids: Dictionary
) -> bool:
	var entry_id := entry.get("entry_id", &"") as StringName
	if (
		entry_id.is_empty()
		or entry.get("battle_instance_id", &"") != battle_id
		or seen_entry_ids.has(entry_id)
	):
		return false
	seen_entry_ids[entry_id] = true
	return true


func _map_growth_stat(stat: StringName) -> StringName:
	match stat:
		BattlePermanentGrowthLedger.STAT_BASE_VALUE:
			return OwnedCard.STAT_BASE_VALUE
		BattlePermanentGrowthLedger.STAT_BASE_ARMOR:
			return OwnedCard.STAT_BASE_ARMOR
		_:
			return &""


func _restore_transaction(
	owned_collection: OwnedCardCollection,
	collection_state: Dictionary,
	reward_state: RunRewardState,
	reward_snapshot: Dictionary
) -> void:
	owned_collection.restore_state(collection_state)
	reward_state.restore_state(reward_snapshot)


func _failure(reason: String, battle_id: StringName = &"") -> Dictionary:
	return {
		"success": false,
		"status": STATUS_FAILED,
		"battle_instance_id": battle_id,
		"reason": reason,
	}
