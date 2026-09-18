extends SceneTree

## D2-5 第一小步：唯一收藏实例、战前快照/恢复与一次性结算身份基础。
## 使用真实数据对象和战斗账本，不使用 mock。

const BattlePermanentGrowthLedgerScript = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedgerScript = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattleOwnedCardChangeLedgerScript = preload("res://scripts/battle/battle_owned_card_change_ledger.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const BattlePreparationSnapshot = preload("res://scripts/data/battle_preparation_snapshot.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const BattleSettlementService = preload("res://scripts/data/battle_settlement_service.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_same_definition_has_independent_instances()
	_test_snapshot_restores_owned_state_and_formation_binding()
	_test_ledgers_record_instance_and_battle_identity()
	_test_settlement_journal_rejects_duplicate_commit()
	_test_atomic_settlement_restores_then_applies_once()
	_test_slot_progress_and_spell_durability_settle_once()
	await _test_main_battle_entry_uses_owned_snapshot()
	if failures == 0:
		print("D2-5 owned-card snapshot checks passed.")
	else:
		push_error("D2-5 owned-card snapshot checks failed: %d" % failures)
	quit(failures)


func _test_same_definition_has_independent_instances() -> void:
	var definition := _card_definition(&"shared_definition")
	var collection := OwnedCardCollection.new()
	var first := collection.create_card(definition)
	var second := collection.create_card(definition)
	first.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2.0)
	first.wound_slots[0] = {"wound_id": &"test_wound", "level": 1}
	first.emblem_slots[0] = {"emblem_id": &"test_emblem"}
	_expect(
		first.instance_id != second.instance_id
		and first.card_data == second.card_data
		and first.get_effective_base_value() == definition.base_value + 2
		and second.get_effective_base_value() == definition.base_value
		and second.wound_slots[0].is_empty()
		and second.emblem_slots[0].is_empty()
		and definition.base_value == 3,
		"同一CardData可生成两张唯一实例，成长、伤势和纹章不会互相污染或写回共享定义"
	)


func _test_snapshot_restores_owned_state_and_formation_binding() -> void:
	var definition := _card_definition(&"snapshot_definition")
	var collection := OwnedCardCollection.new()
	var owned_card := collection.create_card(definition)
	var other_card := collection.create_card(_card_definition(&"snapshot_other"))
	owned_card.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 1.0)
	owned_card.progress_by_source[&"seed_emblem"] = 2
	var squad := SquadData.from_owned_card(owned_card)
	var snapshot := BattlePreparationSnapshot.new()
	snapshot.initialize(
		&"run_battle_000001",
		24680,
		collection,
		{&"player_front": [squad]}
	)
	owned_card.apply_permanent_growth(OwnedCard.STAT_BASE_ARMOR, 5.0)
	owned_card.progress_by_source[&"seed_emblem"] = 99
	owned_card.wound_slots[0] = {"wound_id": &"should_rollback"}
	var post_snapshot_card := collection.create_card(_card_definition(&"post_snapshot"))
	squad.remove_card(definition)
	_expect(
		snapshot.restore_collection(collection),
		"战前快照可以恢复收藏实例状态"
	)
	var restored_squads := snapshot.get_row_squads(&"player_front")
	var restored_squad := restored_squads[0] if not restored_squads.is_empty() else null
	_expect(
		collection.size() == 2
		and collection.get_by_instance_id(post_snapshot_card.instance_id) == null
		and collection.get_by_instance_id(other_card.instance_id) == other_card
		and owned_card.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 1.0
		and int(owned_card.progress_by_source.get(&"seed_emblem", 0)) == 2
		and owned_card.wound_slots[0].is_empty()
		and restored_squad != null
		and restored_squad.get_vitals_source_instance() == owned_card
		and restored_squad.get_vitals_source_instance().instance_id == owned_card.instance_id
		and snapshot.battle_seed == 24680,
		"恢复会移除战后新增实例、回滚可变状态，并按同一OwnedCard身份重建阵容"
	)


func _test_ledgers_record_instance_and_battle_identity() -> void:
	var definition := _card_definition(&"ledger_definition")
	var collection := OwnedCardCollection.new()
	var first := collection.create_card(definition)
	var second := collection.create_card(definition)
	var state := BattleSquadState.new()
	state.initialize(
		SquadData.from_owned_card(second),
		BattleSquadState.Side.PLAYER,
		&"player_front",
		0
	)
	state.runtime_id = 17
	var growth_owner := BattleEffectOwnerRef.for_state(
		state,
		BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD
	)
	var growth_ledger := BattlePermanentGrowthLedgerScript.new()
	_expect(
		growth_ledger.record(
			growth_owner,
			BattlePermanentGrowthLedgerScript.STAT_BASE_VALUE,
			1.0,
			&"test_growth",
			17,
			100,
			&"run_battle_000007"
		),
		"永久成长账本接受带唯一实例的真实归属"
	)
	var growth_entry := growth_ledger.get_entries()[0]
	var reward_owner := BattleEffectOwnerRef.for_state(
		state,
		BattleEffectDefinition.OwnerKind.OWNING_PLAYER
	)
	var reward_ledger := BattleRunRewardLedgerScript.new()
	reward_ledger.record(
		reward_owner,
		BattleRunRewardLedgerScript.KIND_GOLD,
		2,
		&"test_reward",
		17,
		101,
		{},
		&"run_battle_000007"
	)
	var reward_entry := reward_ledger.get_entries()[0]
	_expect(
		growth_owner.owned_card == second
		and growth_owner.owned_card_instance_id == second.instance_id
		and growth_owner.owned_card_instance_id != first.instance_id
		and growth_entry.get("owned_card_instance_id") == second.instance_id
		and growth_entry.get("battle_instance_id") == &"run_battle_000007"
		and String(growth_entry.get("entry_id", &"")).ends_with(":growth:0")
		and reward_entry.get("battle_instance_id") == &"run_battle_000007"
		and String(reward_entry.get("entry_id", &"")).ends_with(":reward:0"),
		"成长与奖励记录同时携带卡牌实例ID、战斗实例ID和稳定条目ID"
	)


func _test_settlement_journal_rejects_duplicate_commit() -> void:
	var journal := RunSettlementJournal.new()
	_expect(
		not journal.is_committed(&"run_battle_000009")
		and journal.mark_committed(&"run_battle_000009")
		and journal.is_committed(&"run_battle_000009")
		and not journal.mark_committed(&"run_battle_000009"),
		"同一战斗实例只能登记一次正常战后提交"
	)


func _test_atomic_settlement_restores_then_applies_once() -> void:
	var action_definition := _card_definition(&"settlement_action")
	var armor_definition := _card_definition(&"settlement_armor")
	var collection := OwnedCardCollection.new()
	var action_card := collection.create_card(action_definition)
	var armor_card := collection.create_card(armor_definition)
	var squad := SquadData.from_cards([action_definition, armor_definition])
	squad.bind_owned_card(action_definition, action_card)
	squad.bind_owned_card(armor_definition, armor_card)
	var snapshot := BattlePreparationSnapshot.new()
	snapshot.initialize(
		&"run_battle_000020",
		25020,
		collection,
		{&"player_front": [squad]}
	)


	# 模拟战斗中即时预览曾改过实例；正式结算必须先恢复战前值，不能把差额重复算入。
	action_card.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 50.0)
	var growth_entries: Array[Dictionary] = [{
		"entry_id": &"run_battle_000020:growth:0",
		"battle_instance_id": &"run_battle_000020",
		"side": BattleSquadState.Side.PLAYER,
		"owned_card_instance_id": action_card.instance_id,
		"stat": BattlePermanentGrowthLedgerScript.STAT_BASE_VALUE,
		"amount": 1.0,
	}, {
		"entry_id": &"run_battle_000020:growth:1",
		"battle_instance_id": &"run_battle_000020",
		"side": BattleSquadState.Side.PLAYER,
		"owned_card_instance_id": armor_card.instance_id,
		"stat": BattlePermanentGrowthLedgerScript.STAT_BASE_ARMOR,
		"amount": 1.0,
	}]
	var reward_entries: Array[Dictionary] = [{
		"entry_id": &"run_battle_000020:reward:0",
		"battle_instance_id": &"run_battle_000020",
		"side": BattleSquadState.Side.PLAYER,
		"kind": BattleRunRewardLedgerScript.KIND_GOLD,
		"amount": 5,
	}, {
		"entry_id": &"run_battle_000020:reward:1",
		"battle_instance_id": &"run_battle_000020",
		"side": BattleSquadState.Side.PLAYER,
		"kind": BattleRunRewardLedgerScript.KIND_RANDOM_CARD_REQUEST,
		"amount": 1,
		"parameters": {"card_type": &"minion", "rarity_min": 0, "rarity_max": 3},
	}]
	var reward_state := RunRewardState.new()
	reward_state.gold = 4
	var journal := RunSettlementJournal.new()
	var service := BattleSettlementService.new()
	var first_result := service.settle(
		snapshot,
		growth_entries,
		reward_entries,
		collection,
		reward_state,
		journal
	)
	var restored_squad := snapshot.get_row_squads(&"player_front")[0]
	var next_battle_state := BattleSquadState.new()
	next_battle_state.initialize(
		restored_squad,
		BattleSquadState.Side.PLAYER,
		&"player_front",
		0
	)
	var second_result := service.settle(
		snapshot,
		growth_entries,
		reward_entries,
		collection,
		reward_state,
		journal
	)
	_expect(
		first_result.get("status") == BattleSettlementService.STATUS_COMMITTED
		and action_card.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 1.0
		and armor_card.get_permanent_growth(OwnedCard.STAT_BASE_ARMOR) == 1.0
		and next_battle_state.get_display_action_value() == action_definition.base_value + 1
		and next_battle_state.current_armor == armor_definition.armor + 1
		and reward_state.gold == 9
		and reward_state.get_pending_random_card_count() == 1
		and second_result.get("status") == BattleSettlementService.STATUS_ALREADY_COMMITTED
		and action_card.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 1.0
		and reward_state.gold == 9,
		"战后事务先恢复快照、再按实例应用成长与奖励，下一场读取新属性且重复提交不累加"
	)


func _test_slot_progress_and_spell_durability_settle_once() -> void:
	var collection := OwnedCardCollection.new()
	var carrier := collection.create_card(_card_definition(&"persistent_change_carrier"))
	carrier.emblem_slots[0] = {
		"instance_id": &"seed_instance",
		"emblem_id": &"seed",
		"temporary": false,
	}
	carrier.emblem_slots[1] = {
		"instance_id": &"temporary_seed_instance",
		"emblem_id": &"seed",
		"temporary": true,
	}
	var last_use_spell := collection.create_card(_spell_definition(&"last_use_spell", CardData.Rarity.I))
	var reusable_spell := collection.create_card(_spell_definition(&"reusable_spell", CardData.Rarity.II))
	var prepared_spell_ids: Array[StringName] = [
		last_use_spell.instance_id,
		reusable_spell.instance_id,
	]
	var duplicate_spell_ids: Array[StringName] = [
		last_use_spell.instance_id,
		last_use_spell.instance_id,
	]
	var rejected_snapshot := BattlePreparationSnapshot.new()
	_expect(
		not rejected_snapshot.initialize(
			&"run_battle_invalid_spells",
			25029,
			collection,
			{},
			duplicate_spell_ids
		)
		and rejected_snapshot.is_empty(),
		"非法或重复的法术实例不能留下半份可结算快照"
	)
	var snapshot := BattlePreparationSnapshot.new()
	_expect(
		snapshot.initialize(
			&"run_battle_000030",
			25030,
			collection,
			{&"player_front": [SquadData.from_owned_card(carrier)]},
			prepared_spell_ids
		),
		"战前快照验证并记录本场实际准备的法术实例"
	)
	var state := BattleSquadState.new()
	state.initialize(
		SquadData.from_owned_card(carrier),
		BattleSquadState.Side.PLAYER,
		&"player_front",
		0
	)
	var owner := BattleEffectOwnerRef.for_state(
		state,
		BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD
	)
	var ledger := BattleOwnedCardChangeLedgerScript.new()
	ledger.record_slot_change(
		owner,
		BattleOwnedCardChangeLedgerScript.KIND_SET_WOUND_SLOT,
		0,
		{"wound_id": &"test_wound", "level": 1},
		&"test_wound_gain",
		state.runtime_id,
		10,
		&"run_battle_000030"
	)
	ledger.record_emblem_progress(owner, &"seed_instance", 1, &"test_seed_survival", state.runtime_id, 20, &"run_battle_000030")
	ledger.record_emblem_progress(owner, &"temporary_seed_instance", 1, &"test_temporary_seed_survival", state.runtime_id, 21, &"run_battle_000030")
	ledger.record_slot_change(
		owner,
		BattleOwnedCardChangeLedgerScript.KIND_SET_EMBLEM_SLOT,
		0,
		{"instance_id": &"seed_instance", "emblem_id": &"tree", "temporary": false},
		&"test_seed_evolution",
		state.runtime_id,
		30,
		&"run_battle_000030"
	)
	ledger.record_slot_change(
		owner,
		BattleOwnedCardChangeLedgerScript.KIND_SET_EMBLEM_SLOT,
		1,
		{"instance_id": &"earned_emblem", "emblem_id": &"test_emblem", "temporary": false},
		&"test_emblem_gain",
		state.runtime_id,
		31,
		&"run_battle_000030"
	)
	# 模拟战斗内预览污染；正常结算必须先恢复战前值，再消费账本与准备法术列表。
	carrier.wound_slots[0] = {"wound_id": &"wrong_preview", "level": 9}
	carrier.progress_by_source[&"seed_instance"] = 99
	last_use_spell.spell_durability = 99
	var service := BattleSettlementService.new()
	var reward_state := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var first_result := service.settle(snapshot, [], [], collection, reward_state, journal, ledger.get_entries())
	var second_result := service.settle(snapshot, [], [], collection, reward_state, journal, ledger.get_entries())
	_expect(
		first_result.get("status") == BattleSettlementService.STATUS_COMMITTED
		and carrier.wound_slots[0].get("wound_id") == &"test_wound"
		and carrier.emblem_slots[0].get("emblem_id") == &"tree"
		and carrier.emblem_slots[1].get("instance_id") == &"earned_emblem"
		and int(carrier.progress_by_source.get(&"seed_instance", 0)) == 1
		and not carrier.progress_by_source.has(&"temporary_seed_instance")
		and collection.get_by_instance_id(last_use_spell.instance_id) == null
		and collection.get_by_instance_id(reusable_spell.instance_id) == reusable_spell
		and reusable_spell.spell_durability == 1
		and int(first_result.get("temporary_progress_skipped", 0)) == 1
		and int(first_result.get("spell_durability_spent", 0)) == 2
		and int(first_result.get("spent_spells_removed", 0)) == 1
		and second_result.get("status") == BattleSettlementService.STATUS_ALREADY_COMMITTED
		and reusable_spell.spell_durability == 1,
		"伤势、永久纹章、种子进度与法术耐久按实例原子写回，临时进度跳过且重复结算不再消费"
	)


func _test_main_battle_entry_uses_owned_snapshot() -> void:
	root.size = Vector2i(1280, 720)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var definition: CardData = main.collection_cards[0]
	var owned_card: OwnedCard = main.owned_card_collection.find_first_by_definition(definition)
	_expect(
		main._transfer_card({
			"source_type": &"collection",
			"kind": &"card",
			"card_data": definition,
		}, &"board", main.front_row, 0),
		"主场景可把收藏实例对应的卡牌部署到战场"
	)
	_expect(main.start_battle(25001, false), "主场景用固定种子建立战前实例快照")
	var state: BattleSquadState = main.battle_controller.player_states[0]
	var snapshot_id: StringName = main.get("_battle_snapshot").battle_instance_id
	owned_card.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 9.0)
	main.battle_seed_spin.value = 99999
	_expect(
		state.squad_data.get_action_source_instance() == owned_card
		and not snapshot_id.is_empty()
		and main.battle_controller.battle_instance_id == snapshot_id,
		"正式战斗状态携带真实OwnedCard，控制器与战前快照共享同一战斗实例ID"
	)
	_expect(main.restart_battle(), "未完成战斗可恢复战前准备状态")
	var restored_squad := main.front_row.get_squads()[0].get_squad_data() as SquadData
	_expect(
		owned_card.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 0.0
		and roundi(main.battle_seed_spin.value) == 25001
		and restored_squad.get_action_source_instance() == owned_card,
		"中途重试回滚实例变化与固定种子，并保持阵容仍指向同一收藏实例"
	)
	_expect(main.start_battle(25002, false), "主场景可从已恢复的准备状态再次开战")
	var settled_state: BattleSquadState = main.battle_controller.player_states[0]
	var growth_owner := BattleEffectOwnerRef.for_state(
		settled_state,
		BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD
	)
	var reward_owner := BattleEffectOwnerRef.for_state(
		settled_state,
		BattleEffectDefinition.OwnerKind.OWNING_PLAYER
	)
	main.battle_controller.record_pending_permanent_growth(
		growth_owner,
		BattlePermanentGrowthLedgerScript.STAT_BASE_VALUE,
		1.0,
		&"main_settlement_growth",
		settled_state.runtime_id,
		0
	)
	main.battle_controller.record_pending_run_reward(
		reward_owner,
		BattleRunRewardLedgerScript.KIND_GOLD,
		3,
		&"main_settlement_gold",
		settled_state.runtime_id,
		0
	)
	var settlement_result: Dictionary = main.settle_current_battle()
	_expect(main.restart_battle(), "主场景已结算战斗仍可返回当前开发版准备界面")
	_expect(
		settlement_result.get("status") == BattleSettlementService.STATUS_COMMITTED
		and owned_card.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 1.0
		and main.run_reward_state.gold == 3,
		"主场景正常结算写入永久成长与金币，随后返回准备界面不会被旧快照回滚"
	)
	main.queue_free()
	await process_frame


func _card_definition(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.base_value = 3
	card.max_health = 8
	card.armor = 2
	card.wound_slot_count = 2
	card.emblem_slot_count = 2
	card.runes.assign([
		CardData.ElementType.FIRE,
		CardData.ElementType.WATER,
		CardData.ElementType.WOOD,
	])
	return card


func _spell_definition(card_id: StringName, rarity: CardData.Rarity) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.card_type = CardData.CardType.SPELL
	card.rarity = rarity
	return card


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)
