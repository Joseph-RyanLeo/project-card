@tool
extends McpTestSuite

## Godot AI 编辑器内回归：验证战斗实验室的配置预览只重算持续光环。

const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const BattleLabScenarioScript = preload("res://scripts/tools/battle_lab_scenario.gd")
const SquadViewScript = preload("res://scripts/ui/squad_view.gd")


func suite_name() -> String:
	return "battle_lab_preview"


func test_scenario_has_six_slots_and_persists_race() -> void:
	var scenario := BattleLabScenarioScript.create_default()
	scenario.player_squads[0]["race"] = CardData.RaceType.ELF
	var restored := BattleLabScenarioScript.from_dictionary(scenario.to_dictionary())
	var formation := restored.build_player_formation()
	var squad := formation[0]["squad_data"] as SquadData
	assert_eq(restored.player_squads.size(), 6, "每方应提供六个可配置小队槽")
	assert_eq(squad.get_effect_source().race_type, CardData.RaceType.ELF, "种族应写入实验卡牌")


func test_preview_applies_and_recalculates_militia_commander_aura() -> void:
	var controller := track(BattleControllerScript.new()) as BattleController
	var commander := _card("militia_commander")
	var middle := _card("ember_squire")
	var right := _card("militia")
	controller.prepare_battle_preview(
		[
			_entry(commander, 0),
			_entry(middle, 1),
			_entry(right, 2),
		],
		[_entry(_plain_enemy(), 0)],
		24106
	)
	assert_false(controller.is_running(), "配置预览不能推进自动战斗")
	assert_eq(controller.player_states[0].displayed_health, 8, "左侧人类应获得一名相邻人类的生命")
	assert_eq(controller.player_states[1].displayed_health, 22, "中间人类应获得两名相邻人类的生命")
	assert_eq(controller.player_states[2].displayed_health, 4, "右侧人类应获得一名相邻人类的生命")

	var elf_right := right.duplicate(true) as CardData
	elf_right.race_type = CardData.RaceType.ELF
	controller.prepare_battle_preview(
		[
			_entry(commander, 0),
			_entry(middle, 1),
			_entry(elf_right, 2),
		],
		[_entry(_plain_enemy(), 0)],
		24106
	)
	assert_eq(controller.player_states[0].displayed_health, 8, "指挥官仍与中间人类相邻")
	assert_eq(controller.player_states[1].displayed_health, 20, "精灵不再计入中间目标的人类邻接数")
	assert_eq(controller.player_states[2].displayed_health, 2, "精灵不应成为民兵指挥官的光环目标")


func test_preview_does_not_trigger_gold_rush() -> void:
	var controller := track(BattleControllerScript.new()) as BattleController
	controller.prepare_battle_preview(
		[_entry(_card("baggage_muleteer"), 0)],
		[_entry(_plain_enemy(), 0)],
		114514
	)
	assert_true(
		controller.run_reward_ledger.get_entries().is_empty(),
		"配置预览不能把突击金币写入待结算账本"
	)


func test_gold_rush_records_once_and_reads_do_not_reapply() -> void:
	var controller := track(BattleControllerScript.new()) as BattleController
	var players: Array[Dictionary] = [_entry(_card("baggage_muleteer"), 0)]
	var enemies: Array[Dictionary] = [_entry(_plain_enemy(), 0)]
	controller.start_battle(players, enemies, 114514, false)
	var first_read := controller.run_reward_ledger.get_entries()
	var second_read := controller.run_reward_ledger.get_entries()
	assert_eq(first_read.size(), 1, "辎重驮夫的基础突击应只生成一条金币记录")
	assert_eq(second_read, first_read, "结算界面式的重复读取不能生成新奖励")
	controller.start_battle(players, enemies, 114514, false)
	assert_eq(
		controller.run_reward_ledger.get_entries().size(),
		1,
		"同种子重开会先清空旧账本，再生成本场的一条记录"
	)


func test_damage_statistics_are_split_by_action_type() -> void:
	var controller := track(BattleControllerScript.new()) as BattleController
	controller.start_battle(
		[_entry(_plain_enemy(), 0)],
		[_entry(_plain_enemy(), 0)],
		4242,
		false
	)
	var source := controller.player_states[0]
	var target := controller.enemy_states[0]
	var ranged := BattleEffectEvent.new()
	ranged.source = source
	ranged.target = target
	ranged.action_type = CardData.ActionType.RANGED
	ranged.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	ranged.effective_amount = 7.0
	controller._record_battle_statistics(ranged)
	var melee := BattleEffectEvent.new()
	melee.source = source
	melee.target = target
	melee.action_type = CardData.ActionType.MELEE
	melee.effect_kind = BattleEffectEvent.EffectKind.DAMAGE
	melee.effective_amount = 10.0
	controller._record_battle_statistics(melee)
	var statistics := source.get_battle_statistics()
	var split := statistics.get("damage_dealt_by_action", {}) as Dictionary
	assert_eq(statistics["damage_dealt"], 17.0, "总伤害仍应保留")
	assert_eq(split[CardData.ActionType.RANGED], 7.0, "远程伤害应独立统计")
	assert_eq(split[CardData.ActionType.MELEE], 10.0, "近战伤害应独立统计")

	var view := track(SquadViewScript.new()) as SquadView
	view._battle_result_statistics = statistics
	view._battle_result_action_type = CardData.ActionType.MELEE
	var entries := view._get_visible_battle_result_entries()
	assert_eq(entries.size(), 2, "结算卡面应生成两条攻击方式统计")
	assert_eq(entries[0]["value"], 10.0, "近战统计按固定顺序显示")
	assert_eq(entries[1]["value"], 7.0, "远程统计与近战分开显示")


func test_fractional_survivor_never_displays_zero_health() -> void:
	var card := _plain_enemy()
	card.max_health = 1
	var state := BattleSquadState.new()
	state.initialize(SquadData.from_card(card), BattleSquadState.Side.PLAYER, &"player_front", 0)
	state.apply_direct_health_damage_exact(0.6)
	state.finalize_batch_survival()
	assert_true(state.current_health > 0.0, "精确生命仍应大于零")
	assert_eq(state.displayed_health, 1, "存活角色的卡面生命至少显示一")
	state.apply_direct_health_damage_exact(0.4)
	state.finalize_batch_survival()
	assert_true(state.current_health <= 0.0, "补足伤害后精确生命应归零")
	assert_eq(state.displayed_health, 0, "真正归零时才显示零生命")


func _entry(card: CardData, position: int) -> Dictionary:
	return {
		"squad_data": SquadData.from_card(card),
		"row_key": &"player_front" if not card.id.begins_with("preview_enemy") else &"enemy_front",
		"formation_index": position,
	}


func _card(card_id: String) -> CardData:
	return load("res://resources/cards/%s.tres" % card_id) as CardData


func _plain_enemy() -> CardData:
	var card := CardData.new()
	card.id = &"preview_enemy"
	card.display_name = "预览敌人"
	card.base_value = 0
	card.max_health = 100
	return card
