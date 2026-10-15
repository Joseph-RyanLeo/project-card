extends SceneTree

const Controller = preload("res://scripts/battle/battle_controller.gd")
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _card(card_id: String) -> CardData:
	var card := load("res://resources/cards/%s.tres" % card_id).duplicate(true) as CardData
	card.runes.clear()
	return card


func _entry(card_id: String, row: StringName, index: int) -> Dictionary:
	return {"squad_data": SquadData.from_card(_card(card_id)), "row_key": row, "formation_index": index}


func _preview(players: Array[Dictionary]) -> BattleController:
	var controller := Controller.new() as BattleController
	root.add_child(controller)
	controller.prepare_battle_preview(players, [_entry("heavy_knight", &"enemy_front", 0)], 28103)
	return controller


func _recheck(controller: BattleController) -> void:
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(controller.elapsed_seconds)


func _bonus(state: BattleSquadState) -> float:
	return state.modifiers.get_additive(BattleModifier.Stat.HEALING_RECEIVED)


func _run() -> void:
	var definition := load("res://resources/cards/town_priest.tres") as CardData
	_expect(definition.is_available and definition.effect_ids == [&"town_priest.effect.01"], "重做城镇牧师已启用且绑定正式效果")
	var catalog := BattleEffectCatalog.load_from_file("res://data/demo2/ash_ledger_effect_samples.json")
	_expect(catalog.is_valid() and catalog.get_definition(&"town_priest.effect.01") != null, "完整正式效果数据严格解析通过")
	var controller := _preview([
		_entry("militia", &"player_front", 0), _entry("town_priest", &"player_front", 1),
		_entry("militia", &"player_front", 2), _entry("field_medic", &"player_front", 3),
		_entry("militia", &"player_back", 0),
	])
	var left := controller.player_states[0]
	var priest := controller.player_states[1]
	var right := controller.player_states[2]
	_expect(_bonus(left) == 1.0 and _bonus(priest) == 1.0 and _bonus(right) == 1.0, "乡邻成立后本卡及左右人类均获得恢复加成")
	_expect(_bonus(controller.player_states[3]) == 0.0 and _bonus(controller.player_states[4]) == 0.0, "不作用于非邻居或另一排")
	priest.current_health = 1.0
	_expect(priest.apply_healing_exact(2.0) == 3.0 and priest.current_health == 4.0, "恢复2实际变为3，未增加治疗者行动值")
	priest.current_health = 1.0
	var healing_event := BattleEffectEvent.new()
	healing_event.source = priest
	healing_event.target = priest
	healing_event.action_type = CardData.ActionType.HEAL
	healing_event.effect_kind = BattleEffectEvent.EffectKind.HEALING
	healing_event.formula = BattleFormulaData.create("治疗", CardData.ActionType.HEAL, 2.0, 1.0, 1.0, priest, priest)
	healing_event.exact_amount = 2.0
	controller._apply_effect_event(healing_event)
	_expect(healing_event.effective_amount == 3.0 and healing_event.formula.exact_result == 3.0 and priest.current_health == 4.0, "正式治疗事件及公式包含加成且不重复加生命")
	_expect(not healing_event.formula.final_flat_bonus_sources.is_empty() and BattleFormulaPresenter.format_popup(healing_event.formula, healing_event).contains("城镇牧师"), "公式来源可解释城镇牧师的恢复加成")
	_expect(priest.apply_healing_exact(0.0) == 0.0 and priest.current_health == 4.0, "零恢复不凭空生成生命")
	priest.current_health = float(priest.get_max_health()) - 0.5
	_expect(priest.apply_healing_exact(2.0) == 0.5, "恢复加成仍受最大生命约束")
	_recheck(controller)
	_expect(_bonus(priest) == 1.0, "重复乡邻检查不累加同一来源")
	right.alive = false
	_recheck(controller)
	_expect(_bonus(priest) == 0.0 and _bonus(left) == 0.0, "右侧乡邻死亡后实时撤销来源加成")
	priest.current_health = 1.0
	_expect(priest.apply_healing_exact(2.0) == 2.0, "乡邻失效后恢复原治疗量")
	right.alive = true
	_recheck(controller)
	_expect(_bonus(priest) == 1.0 and _bonus(left) == 1.0, "乡邻恢复后重新生效")
	priest.alive = false
	_recheck(controller)
	_expect(_bonus(left) == 0.0 and _bonus(right) == 0.0, "来源死亡撤销两侧加成")
	controller.free()
	controller = _preview([
		_entry("militia", &"player_front", 0), _entry("town_priest", &"player_front", 1),
		_entry("field_medic", &"player_front", 2),
	])
	_expect(_bonus(controller.player_states[1]) == 0.0, "一侧为精灵时沿用既有乡邻条件，不能启动")
	controller.free()
	controller = _preview([
		_entry("militia", &"player_front", 0), _entry("town_priest", &"player_front", 1),
		_entry("militia", &"player_front", 2), _entry("old_wolf_kaspar", &"player_back", 0),
	])
	_expect(_bonus(controller.player_states[1]) == 2.0, "老狼沿用正式乡邻额外触发，使恢复加成变为2")
	_recheck(controller)
	_expect(_bonus(controller.player_states[1]) == 2.0, "老狼额外触发不递归或重复累加")
	controller.free()
	controller = _preview([
		_entry("militia", &"player_front", 0), _entry("town_priest", &"player_front", 1),
		_entry("town_priest", &"player_front", 2), _entry("militia", &"player_front", 3),
	])
	_expect(_bonus(controller.player_states[1]) == 2.0 and _bonus(controller.player_states[2]) == 2.0, "不同牧师来源独立相加")
	controller.free()
	print("D2-8 town priest: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
