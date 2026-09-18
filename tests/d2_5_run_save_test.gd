extends SceneTree

## D2-5 第四小步：用真实 Main 场景和磁盘 JSON 验证战斗中退出、结算后读档、
## 同名实例隔离、战斗身份复用与一次性提交凭证。

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const BattleOwnedCardChangeLedger = preload("res://scripts/battle/battle_owned_card_change_ledger.gd")
const BattleSettlementService = preload("res://scripts/data/battle_settlement_service.gd")

const SAVE_PATH: String = "/private/tmp/project-card-d2-5-run-save.json"
const CORRUPT_SAVE_PATH: String = "/private/tmp/project-card-d2-5-run-save-corrupt.json"

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(CORRUPT_SAVE_PATH):
		DirAccess.remove_absolute(CORRUPT_SAVE_PATH)
	root.size = Vector2i(1280, 720)
	var first_main = await _new_main()
	var heavy_definition := load("res://resources/cards/heavy_knight.tres") as CardData
	var spell_definition := load("res://resources/cards/damage_fireball.tres") as CardData
	var first_heavy: OwnedCard = first_main.owned_card_collection.create_card(heavy_definition)
	var second_heavy: OwnedCard = first_main.owned_card_collection.create_card(heavy_definition)
	var prepared_spell: OwnedCard = first_main.owned_card_collection.create_card(spell_definition)
	first_main._sync_legacy_collection_cards()
	first_heavy.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2.0)
	first_heavy.wound_slots[0] = {"wound_id": &"scar", "level": 1}
	first_heavy.emblem_slots[0] = {
		"instance_id": &"seed_save_instance",
		"emblem_id": &"seed",
		"temporary": false,
	}
	first_heavy.progress_by_source[&"seed_save_instance"] = 2
	second_heavy.wound_slots[0] = {"wound_id": &"bruise", "level": 2}
	first_main.front_row.add_squad(SquadData.from_owned_card(first_heavy), 0)
	var first_id := first_heavy.instance_id
	var second_id := second_heavy.instance_id
	var spell_id := prepared_spell.instance_id
	_expect(first_main.start_battle(424242, false), "主流程建立可持久化的战前快照")
	var interrupted_battle_id: StringName = first_main.get("_battle_snapshot").battle_instance_id
	# 这些值模拟未完成战斗中的临时污染；磁盘存档必须保存战前快照而不是它们。
	first_heavy.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 50.0)
	first_heavy.wound_slots[0] = {"wound_id": &"unfinished_battle_wound", "level": 9}
	second_heavy.wound_slots[0] = {"wound_id": &"wrong_second_wound", "level": 9}
	prepared_spell.spell_durability = 99
	_expect(first_main.save_run_to_path(SAVE_PATH) == OK, "战斗中退出可把安全战前状态写入JSON存档")
	first_main.queue_free()
	await process_frame

	var resumed_main = await _new_main()
	_expect(resumed_main.load_run_from_path(SAVE_PATH), "新主场景可从磁盘恢复本局")
	var restored_first: OwnedCard = resumed_main.owned_card_collection.get_by_instance_id(first_id)
	var restored_second: OwnedCard = resumed_main.owned_card_collection.get_by_instance_id(second_id)
	var restored_spell: OwnedCard = resumed_main.owned_card_collection.get_by_instance_id(spell_id)
	var restored_front_squads: Array[BoardSlot] = resumed_main.front_row.get_squads()
	var restored_front_squad: SquadData = (
		restored_front_squads[0].get_squad_data()
		if not restored_front_squads.is_empty()
		else null
	)
	_expect(
		resumed_main.current_phase == resumed_main.GamePhase.PREPARE
		and roundi(resumed_main.battle_seed_spin.value) == 424242
		and restored_first != null
		and restored_first.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 2.0
		and restored_first.wound_slots[0].get("wound_id") == &"scar"
		and int(restored_first.progress_by_source.get(&"seed_save_instance", 0)) == 2
		and restored_second != null
		and restored_second.wound_slots[0].get("wound_id") == &"bruise"
		and restored_spell != null
		and restored_spell.spell_durability == 2
		and restored_front_squad != null
		and restored_front_squad.get_action_source_instance() == restored_first,
		"战斗中读档回到准备阶段，回滚未完成变化并保持同名实例与阵容绑定"
	)
	_expect(resumed_main.start_battle(-1, false), "读档后的准备状态可以重新开战")
	_expect(
		resumed_main.battle_controller.battle_instance_id == interrupted_battle_id,
		"战斗中退出后复用原战斗实例ID和固定种子"
	)
	var state: BattleSquadState = resumed_main.battle_controller.player_states[0]
	var card_owner := BattleEffectOwnerRef.for_state(
		state,
		BattleEffectDefinition.OwnerKind.ACTION_PROVIDER_CARD
	)
	var player_owner := BattleEffectOwnerRef.for_state(
		state,
		BattleEffectDefinition.OwnerKind.OWNING_PLAYER
	)
	resumed_main.battle_controller.record_pending_permanent_growth(
		card_owner,
		BattlePermanentGrowthLedger.STAT_BASE_VALUE,
		1.0,
		&"save_regression_growth",
		state.runtime_id,
		10
	)
	resumed_main.battle_controller.record_pending_owned_card_slot_change(
		card_owner,
		BattleOwnedCardChangeLedger.KIND_SET_WOUND_SLOT,
		1,
		{"wound_id": &"settled_wound", "level": 1},
		&"save_regression_wound",
		state.runtime_id,
		20
	)
	resumed_main.battle_controller.record_pending_run_reward(
		player_owner,
		BattleRunRewardLedger.KIND_GOLD,
		3,
		&"save_regression_gold",
		state.runtime_id,
		30
	)
	var settlement_result: Dictionary = resumed_main.settle_current_battle()
	_expect(
		settlement_result.get("status") == BattleSettlementService.STATUS_COMMITTED,
		"恢复后的同一战斗可以正常提交一次"
	)
	_expect(resumed_main.restart_battle(), "已提交战斗返回准备阶段时保留结算结果")
	_expect(resumed_main.save_run_to_path(SAVE_PATH) == OK, "正常结算后的本局状态可以覆盖保存")
	resumed_main.queue_free()
	await process_frame

	var settled_main = await _new_main()
	_expect(settled_main.load_run_from_path(SAVE_PATH), "结算后的存档可以在新进程状态中恢复")
	var settled_first: OwnedCard = settled_main.owned_card_collection.get_by_instance_id(first_id)
	var settled_second: OwnedCard = settled_main.owned_card_collection.get_by_instance_id(second_id)
	var settled_spell: OwnedCard = settled_main.owned_card_collection.get_by_instance_id(spell_id)
	var no_entries: Array[Dictionary] = []
	var duplicate_result: Dictionary = settled_main.battle_settlement_service.settle(
		settled_main._capture_battle_snapshot(interrupted_battle_id, 424242),
		no_entries,
		no_entries,
		settled_main.owned_card_collection,
		settled_main.run_reward_state,
		settled_main.settlement_journal,
		no_entries
	)
	var next_card: OwnedCard = settled_main.owned_card_collection.create_card(heavy_definition)
	_expect(
		settled_first != null
		and settled_first.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 3.0
		and settled_first.wound_slots[0].get("wound_id") == &"scar"
		and settled_first.wound_slots[1].get("wound_id") == &"settled_wound"
		and settled_second != null
		and settled_second.wound_slots[0].get("wound_id") == &"bruise"
		and settled_spell != null
		and settled_spell.spell_durability == 2
		and settled_main.run_reward_state.gold == 3
		and settled_main.settlement_journal.is_committed(interrupted_battle_id)
		and duplicate_result.get("status") == BattleSettlementService.STATUS_ALREADY_COMMITTED
		and next_card.instance_id not in [first_id, second_id, spell_id],
		"结算后读档保留永久状态、奖励、实例序列和提交凭证，重复结算不再发放"
	)
	var loaded_checkpoint_result: Dictionary = settled_main.run_save_service.load_checkpoint(SAVE_PATH)
	var corrupt_checkpoint := (
		loaded_checkpoint_result.get("checkpoint", {}) as Dictionary
	).duplicate(true)
	var corrupt_rows := corrupt_checkpoint.get("rows", {}) as Dictionary
	var corrupt_front := corrupt_rows.get("player_front", []) as Array
	var corrupt_squad := corrupt_front[0] as Dictionary
	var corrupt_horizontal := corrupt_squad.get("horizontal_cards", []) as Array
	(corrupt_horizontal[0] as Dictionary)["owned_card_instance_id"] = "missing_owned_card"
	settled_main.run_save_service.save_checkpoint(CORRUPT_SAVE_PATH, corrupt_checkpoint)
	_expect(
		not settled_main.load_run_from_path(CORRUPT_SAVE_PATH)
		and settled_first.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 3.0
		and settled_main.run_reward_state.gold == 3,
		"损坏的阵容实例引用会被拒绝，且不会部分覆盖当前本局状态"
	)
	settled_main.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(CORRUPT_SAVE_PATH):
		DirAccess.remove_absolute(CORRUPT_SAVE_PATH)
	if failures == 0:
		print("D2-5 run save regression checks passed.")
	else:
		push_error("D2-5 run save regression checks failed: %d" % failures)
	quit(failures)


func _new_main():
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	return main


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)
