extends SceneTree

## 五件灰烬征册装备使用真实CardData、OwnedCard、小队与战斗效果运行时验证。

const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const BattlePreparationSnapshot = preload("res://scripts/data/battle_preparation_snapshot.gd")
const BattleSettlementService = preload("res://scripts/data/battle_settlement_service.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var failures: int = 0
var _serial: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_banner()
	_test_rally_horn()
	_test_shield()
	_test_equipment_armor_is_initial()
	_test_bandage()
	_test_recruitment_ledger()
	await _test_consumed_equipment_board_cleanup()
	if failures == 0:
		print("D2-6B formal equipment effect checks passed.")
	else:
		push_error("D2-6B formal equipment effect checks failed: %d" % failures)
	quit(failures)


func _test_banner() -> void:
	var players := _three_humans_with_middle_equipment(&"ash_war_banner")
	var controller := _start(players, 6101)
	var middle := controller.player_states[1]
	var all_get_one := true
	for state: BattleSquadState in controller.player_states:
		all_get_one = all_get_one and is_equal_approx(
			state.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE), 1.0
		)
	_expect(all_get_one and middle.has_runtime_keyword(&"dazzling"), "战旗乡邻成立时同排数值+1，装备者获得可撤销耀眼")
	controller.player_states[0].alive = false
	controller.player_states[0].current_health = 0
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
	_expect(not middle.has_runtime_keyword(&"dazzling") and is_zero_approx(middle.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)), "战旗乡邻失效后撤回本来源数值和耀眼")
	_dispose(controller)


func _test_rally_horn() -> void:
	var controller := _start(_three_humans_with_middle_equipment(&"rally_horn"), 6102)
	_expect(controller.player_states[0].get_zeal_layers() == 4 and controller.player_states[1].get_zeal_layers() == 0 and controller.player_states[2].get_zeal_layers() == 4, "集结号突击只给左右相邻友军本场热诚+4，不给装备者")
	_dispose(controller)


func _test_shield() -> void:
	var owner := _plain_minion(&"shield_owner")
	var squad := SquadData.from_card(owner)
	_expect(squad.equip_item(_owned_equipment(&"ash_war_shield")), "战盾装入小队")
	var controller := _start([_entry(squad, &"player_front", 0)], 6103)
	var defender := controller.player_states[0]
	var attacker := controller.enemy_states[0]
	var before_health := float(attacker.current_health)
	var hit := BattleEffectEvent.new()
	hit.source = attacker
	hit.target = defender
	hit.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	hit.exact_amount = 2.0
	hit.is_base_action = true
	hit.action_type = CardData.ActionType.MELEE
	controller._apply_effect_event(hit)
	_expect(is_equal_approx(float(defender.current_armor), 2.0) and is_equal_approx(before_health - float(attacker.current_health), 0.4), "战盾按基础行动命中后的当前护甲20%反伤，未使用攻击者护甲")
	_dispose(controller)


func _test_equipment_armor_is_initial() -> void:
	var squad := SquadData.from_card(_plain_minion(&"initial_armor_owner"))
	var no_base_armor := squad.get_effective_base_armor() == 0
	squad.equip_item(_owned_equipment(&"coarse_bandage"))
	var controller := _start([
		_entry(squad, &"player_front", 0),
		_entry(SquadData.from_card(_card(&"anvil_margaret")), &"player_front", 1),
	], 6106)
	var owner := controller.player_states[0]
	_expect(no_base_armor and is_equal_approx(float(owner.current_armor), 1.0) and owner.get_zeal_layers() == -4, "装备护甲是初始护甲，不触发玛格丽特获得护甲×2；有护甲仍触发热诚-4")
	_dispose(controller)


func _test_bandage() -> void:
	var minion := _plain_minion(&"bandage_owner")
	minion.wound_slot_count = 3
	var owned_minion := OwnedCard.new()
	owned_minion.initialize(minion, &"bandage_owner_instance", 0)
	owned_minion.set_wound_slot(0, {"wound_id": &"low", "level": 1})
	owned_minion.set_wound_slot(1, {"wound_id": &"high_a", "level": 3})
	owned_minion.set_wound_slot(2, {"wound_id": &"high_b", "level": 3})
	var squad := SquadData.from_owned_card(owned_minion)
	_expect(squad.equip_item(_owned_equipment(&"coarse_bandage")), "绷带装入小队")
	var controller := _start([_entry(squad, &"player_front", 0)], 6104)
	var state := controller.player_states[0]
	_expect(state.is_injury_masked(&"bandage_owner_instance:wound:1") and state.is_injury_masked(&"bandage_owner_instance:wound:2") and not state.is_injury_masked(&"bandage_owner_instance:wound:0"), "绷带从随从实例伤势槽读取等级，遮蔽最高的两处")
	_dispose(controller)


func _test_recruitment_ledger() -> void:
	var collection := OwnedCardCollection.new()
	var minion := collection.create_card(_plain_minion(&"ledger_owner"))
	var item := collection.create_card(_card(&"recruitment_ledger"))
	var squad := SquadData.from_owned_card(minion)
	_expect(squad.equip_item(item), "征兵册装入小队")
	var snapshot := BattlePreparationSnapshot.new()
	var rows := {&"player_front": [squad.duplicate_squad()]}
	_expect(snapshot.initialize(&"d2_6b_ledger_battle", 6105, collection, rows), "征兵册战前快照已建立")
	var controller := _start([_entry(squad, &"player_front", 0)], 6105)
	controller.battle_instance_id = snapshot.battle_instance_id
	controller.enemy_states[0].alive = false
	controller.enemy_states[0].current_health = 0
	controller._check_battle_result()
	var reward_entries := controller.run_reward_ledger.get_entries()
	var change_entries := controller.owned_card_change_ledger.get_entries()
	_expect(reward_entries.size() == 1 and int(reward_entries[0].get("amount", 0)) == 2 and change_entries.size() == 1 and change_entries[0].get("owned_card_instance_id") == item.instance_id, "征兵册胜利时记录两张随机随从请求与本装备消耗")
	var settlement := BattleSettlementService.new()
	var rewards := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var settled := settlement.settle(snapshot, [], reward_entries, collection, rewards, journal, change_entries)
	_expect(bool(settled.get("success", false)) and int(settled.get("equipment_consumed", 0)) == 1 and rewards.get_pending_random_card_count() == 2 and collection.get_by_instance_id(item.instance_id) == null, "正式战后事务先排队两张随从奖励再消耗征兵册，同一实例从收藏移除")
	var repeated := settlement.settle(snapshot, [], reward_entries, collection, rewards, journal, change_entries)
	_expect(repeated.get("status") == BattleSettlementService.STATUS_ALREADY_COMMITTED and rewards.get_pending_random_card_count() == 2, "重复进入结算不会再次发放征兵册奖励或消耗其他装备")
	_dispose(controller)


func _test_consumed_equipment_board_cleanup() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	var minion: OwnedCard = main.owned_card_collection.create_card(_plain_minion(&"cleanup_owner"))
	var item: OwnedCard = main.owned_card_collection.create_card(_card(&"recruitment_ledger"))
	var squad := SquadData.from_owned_card(minion)
	_expect(squad.equip_item(item), "消耗清理测试装备绑定成功")
	var stale_snapshot := squad.duplicate_squad()
	var slot: BoardSlot = main.front_row.add_squad(squad, 0)
	_expect(slot != null and slot.get_equipment_indicator() != null, "征兵册在战场上有真实指示物")
	main.owned_card_collection.remove_by_instance_id(item.instance_id)
	main._remove_missing_equipment_from_board()
	_expect(slot.get_squad_data().get_equipped_item() == null and slot.get_equipment_indicator() == null, "结算后已消耗装备从战场小队和指示物同步移除")
	main._restore_row_from_snapshot(main.front_row, [stale_snapshot])
	var restored_slot: BoardSlot = main.front_row.get_squads()[0]
	_expect(restored_slot.get_squad_data().get_equipped_item() == null and restored_slot.get_equipment_indicator() == null, "旧快照恢复时不复活已消耗装备")
	main.queue_free()
	await process_frame


func _three_humans_with_middle_equipment(item_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in 3:
		var squad := SquadData.from_card(_plain_minion(StringName("ally_%d" % index)))
		if index == 1:
			squad.equip_item(_owned_equipment(item_id))
		result.append(_entry(squad, &"player_front", index))
	return result


func _owned_equipment(item_id: StringName) -> OwnedCard:
	_serial += 1
	var item := OwnedCard.new()
	item.initialize(_card(item_id), StringName("%s_test_%d" % [item_id, _serial]), _serial)
	return item


func _plain_minion(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.race_type = CardData.RaceType.HUMAN
	card.base_value = 2
	card.cooldown_seconds = 9.0
	card.max_health = 20
	return card


func _card(card_id: StringName) -> CardData:
	return load("res://resources/cards/%s.tres" % card_id) as CardData


func _entry(squad: SquadData, row_key: StringName, index: int) -> Dictionary:
	return {"squad_data": squad, "row_key": row_key, "formation_index": index}


func _start(players: Array[Dictionary], seed: int) -> BattleController:
	var controller := BattleController.new()
	root.add_child(controller)
	var enemy := _plain_minion(&"effect_test_enemy")
	enemy.max_health = 100
	controller.start_battle(players, [_entry(SquadData.from_card(enemy), &"enemy_front", 0)], seed, false)
	return controller


func _dispose(controller: BattleController) -> void:
	controller.clear_battle()
	controller.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
