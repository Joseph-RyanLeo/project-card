extends SceneTree

## 正式Main结算：成功只刷新一次，失败恢复快照，重复提交不回滚已得奖励。
const MAIN := preload("res://scenes/Main.tscn")
const PROFILE := preload("res://tests/performance/battle_result_profiled_main.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("结算刷新专项超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for success: bool in [true, false]: await _test_result(success)
	print("结算刷新专项：%d项，%d失败" % [checks, failures])
	quit(failures)

func _test_result(success: bool) -> void:
	var main := MAIN.instantiate()
	main.set_script(PROFILE)
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-result-refresh-regression.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var rng := RandomNumberGenerator.new()
	rng.seed = 251027
	var first: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"), rng)
	var second: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/moon_dancer.tres"), rng)
	second.rune_revealed.fill(false)
	var unknown_before := second.rune_revealed.duplicate()
	var item: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/tower_shield.tres"), rng)
	var squad := SquadData.from_owned_card(first)
	check(squad.equip_item(item), "真实装备绑定")
	main.front_row.add_squad(squad, 0)
	main.back_row.add_squad(SquadData.from_owned_card(second), 0)
	main.enemy_front_row.add_squad(SquadData.from_card(load("res://resources/cards/heavy_knight.tres")), 0)
	var spell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"), rng)
	spell.spell_durability = 2
	main.prepared_spell_instance_ids.assign([spell.instance_id])
	check(main.start_battle(251027, false), "真实阵容及法术开战")
	var battle: BattleController = main.battle_controller
	battle.set_process(false)
	var actor: BattleSquadState = battle.player_states[0]
	var growing: BattleSquadState = battle.player_states[1]
	check(battle.silvermoon.swap(actor, growing), "真实跨排换位")
	actor.record_damage_dealt(CardData.ActionType.MELEE, 17)
	var owner := BattleEffectOwnerRef.for_owned_card_in_state(growing, second)
	check(battle.record_pending_permanent_growth(owner, BattlePermanentGrowthLedger.STAT_BASE_VALUE, 2.0, &"refresh_growth", growing.runtime_id, 0), "记录真实永久成长")
	check(battle.record_pending_run_reward(BattleEffectOwnerRef.for_state(growing, BattleEffectDefinition.OwnerKind.OWNING_PLAYER), BattleRunRewardLedger.KIND_GOLD, 3, &"refresh_gold", growing.runtime_id, 0), "记录真实金币奖励")
	check(battle.record_pending_equipment_consumption(BattleEffectOwnerRef.for_state(actor, BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE), &"refresh_consume", actor.runtime_id, 0), "记录真实装备消耗")
	check(battle.owned_card_change_ledger.record_content_change(BattleEffectOwnerRef.for_owned_card_in_state(actor, first), BattleOwnedCardChangeLedger.KIND_DESTROY_CARD, {}, battle.battle_instance_id), "记录真实永久销毁")
	if not success: battle.permanent_growth_ledger._entries[0]["battle_instance_id"] = &"invalid_other_battle"
	var previous_gold: int = main.run_reward_state.gold
	second.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 9.0)
	battle.current_result = BattleController.Result.PLAYER_VICTORY
	main.result_profile.clear()
	main._show_battle_result(BattleController.Result.PLAYER_VICTORY)
	var result: Dictionary = main._last_battle_settlement_result
	check(bool(result.success) == success, "合法事务提交，非法账本拒绝")
	check(main.result_profile.get("收藏刷新", {}).get("calls", 0) == 1, "结果入口收藏只刷新一次")
	check(main.result_profile.get("阵容恢复", {}).get("calls", 0) == 4, "结果入口四排各恢复一次")
	check(main.result_profile.get("快照恢复", {}).get("calls", 0) == (0 if success else 1), "成功不重复回滚，失败仍恢复准备快照")
	check(second.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == (2.0 if success else 0.0), "只应用账本成长，不遗留战斗中临时写入")
	check(main.run_reward_state.gold == previous_gold + (3 if success else 0), "金币只按事务提交一次")
	check(spell.spell_durability == (1 if success else 2), "法术耐久只消耗一次，失败不消耗")
	check(main.prepared_spell_instance_ids.is_empty() if success else main.prepared_spell_instance_ids == [spell.instance_id], "成功清空准备法术，失败恢复原队列")
	check(main.owned_card_collection.get_by_instance_id(item.instance_id) == (null if success else item), "装备消耗遵循事务")
	check(main.owned_card_collection.get_by_instance_id(first.instance_id) == (null if success else first), "永久销毁只影响权威收藏")
	check(main.front_row.get_squads()[0].get_squad_data().get_effect_source_instance() == first, "永久销毁的原成员仍保留结算原位统计")
	check(main.front_row.get_squads()[0].get_squad_data().get_equipped_item() == (null if success else item), "结算卡面移除已消耗装备")
	check(main.back_row.get_squads()[0].get_squad_data().get_effect_source_instance() == second, "未销毁成员恢复战前排位与同一实例")
	check(main.front_row.get_squads()[0].get_battle_result_statistics().damage_dealt == 17, "销毁及换位不使统计错位")
	check(second.rune_revealed == unknown_before, "隐藏符文不会被刷新揭晓")
	await process_frame
	await process_frame
	check(main.front_row.get_squads()[0].get_battle_result_statistics().damage_dealt == 17, "延迟显示同步不覆盖结算统计")
	if success:
		main._show_battle_result(BattleController.Result.PLAYER_VICTORY)
		check(main._last_battle_settlement_result.status == BattleSettlementService.STATUS_ALREADY_COMMITTED, "重复结果只读取已提交状态")
		check(second.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 2 and main.run_reward_state.gold == previous_gold + 3 and spell.spell_durability == 1, "重复结果不回滚或重复发奖")
		check(main.owned_card_collection.get_by_instance_id(first.instance_id) == null, "重复结果不复活已销毁成员")
	battle.clear_battle()
	main.queue_free()
	await process_frame
	await process_frame
