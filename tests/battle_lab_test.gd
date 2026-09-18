extends SceneTree

## 战斗实验室回归：验证配置不是另一套规则，而是能构造正式阵容并驱动 BattleController。

const LAB_SCENE: PackedScene = preload("res://scenes/tools/BattleLab.tscn")
const BattleLabScenario = preload("res://scripts/tools/battle_lab_scenario.gd")
const BattleLabEffectLibrary = preload("res://scripts/tools/battle_lab_effect_library.gd")

var failures: int = 0
var test_root: Node


func _initialize() -> void:
	var visual_root := Control.new()
	visual_root.size = Vector2(1280, 720)
	test_root = visual_root
	get_root().add_child(test_root)
	_run.call_deferred()


func _run() -> void:
	_test_effect_test_card_library()
	_test_scenario_round_trip_and_formation()
	await _test_visual_lab_flow()
	if failures == 0:
		print("Battle lab checks passed.")
	else:
		push_error("Battle lab checks failed: %d" % failures)
	quit(failures)


func _test_effect_test_card_library() -> void:
	var valid_count := 0
	var triggers: Dictionary = {}
	for preset: Dictionary in BattleLabEffectLibrary.PRESETS:
		var preset_id := StringName(preset["id"])
		if preset_id == BattleLabEffectLibrary.NONE:
			continue
		var definitions := BattleLabEffectLibrary.create_definitions(preset_id)
		if not definitions.is_empty() and definitions.all(
			func(definition: BattleEffectDefinition) -> bool: return definition != null
		):
			valid_count += 1
			for definition: BattleEffectDefinition in definitions:
				triggers[definition.trigger] = true
	_expect(valid_count == BattleLabEffectLibrary.PRESETS.size() - 1, "合成测试卡与灰烬真实卡全部生成严格效果定义")
	_expect(
		triggers.has(BattleEffectDefinition.Trigger.RUSH)
		and triggers.has(BattleEffectDefinition.Trigger.CONTINUOUS)
		and triggers.has(BattleEffectDefinition.Trigger.ELAPSED_BATTLE_TIME)
		and triggers.has(BattleEffectDefinition.Trigger.OTHER_ALLY_ACTION_AFTER),
		"测试卡覆盖突击、持续、定时与友军行动后触发器"
	)


func _test_scenario_round_trip_and_formation() -> void:
	var scenario: BattleLabScenario = BattleLabScenario.create_preset(&"light_water")
	scenario.player_squads[0]["effect_card"] = String(BattleLabEffectLibrary.RANDOM_BANNER)
	scenario.player_squads[0]["cooldown"] = 42.0
	scenario.player_squads[0]["race"] = CardData.RaceType.ELF
	_expect(scenario.validate().is_empty(), "内置实验预设可直接运行")
	var player_formation := scenario.build_player_formation()
	var enemy_formation := scenario.build_enemy_formation()
	var squad := player_formation[0]["squad_data"] as SquadData
	_expect(
		player_formation.size() == 1
		and enemy_formation.size() == 3
		and is_equal_approx(float(player_formation[0]["base_cooldown_override"]), 42.0),
		"实验场景生成敌我正式 formation 输入，并允许测试最长99秒行动间隔"
	)
	_expect(squad.get_visible_runes() == [CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.WATER], "五个编辑槽生成完全相同顺序的合法可见符文堆叠")
	_expect(
		BattleLabScenario.SIDE_SLOT_COUNT == 6
		and scenario.player_squads.size() == 6
		and squad.get_effect_source().race_type == CardData.RaceType.ELF,
		"实验室每方可配置六个小队，且种族字段进入正式CardData"
	)
	_expect(squad.get_effect_source().effect_text.contains("随机一名友军"), "测试效果说明进入正式CardData卡面")
	var restored: BattleLabScenario = BattleLabScenario.from_dictionary(scenario.to_dictionary())
	_expect(restored.to_dictionary() == scenario.to_dictionary(), "场景名称、阵容、种子与断言可以无损保存载入")


func _test_visual_lab_flow() -> void:
	var lab := LAB_SCENE.instantiate() as BattleLab
	test_root.add_child(lab)
	await process_frame
	_expect(lab.scenario != null and lab.battle_controller != null and lab._side_controls.size() == 2, "实验室建立双方编辑器与正式战斗控制器")
	_expect(
		is_equal_approx(((lab._side_controls["player"] as Dictionary)["cooldown"] as SpinBox).max_value, 99.0),
		"实验室冷却编辑器使用最新版99秒测试上限"
	)
	_expect(
		((lab._side_controls["player"] as Dictionary)["slot"] as OptionButton).item_count == 6
		and ((lab._side_controls["player"] as Dictionary)["race"] as OptionButton).item_count == CardData.RaceType.size(),
		"双方编辑器提供六个小队槽与完整种族选择"
	)
	_expect(
		not lab.player_drawer.visible
		and not lab.enemy_drawer.visible
		and not lab.output_drawer.visible
		and lab.output_drawer_button.get_global_rect().end.x <= lab.get_global_rect().end.x - 12.0,
		"配置与日志默认收纳为左右、底部弹出抽屉"
	)
	var player_preview_row := lab.state_rows["player_back"] as HBoxContainer
	var enemy_preview_row := lab.state_rows["enemy_front"] as HBoxContainer
	var player_wrapper := player_preview_row.get_child(0) as Control
	var enemy_wrapper := enemy_preview_row.get_child(0) as Control
	_expect(player_preview_row.get_child_count() == 1 and enemy_preview_row.get_child_count() == 3, "未开始战斗时已经实时显示当前敌我配置卡堆")
	_expect(
		int(player_wrapper.get_meta("unscaled_squad_width")) == 159
		and int(enemy_wrapper.get_meta("unscaled_squad_width")) == 99
		and player_wrapper.custom_minimum_size.x >= 159.0
		and player_wrapper.custom_minimum_size.y >= 150.0
		and player_wrapper.custom_minimum_size.x > enemy_wrapper.custom_minimum_size.x,
		"单卡与展开双卡按正式100%尺寸和99/159比例显示"
	)
	var player_effect_option := (lab._side_controls["player"] as Dictionary)["effect"] as OptionButton
	lab._set_drawer_open("player", true)
	await process_frame
	_expect(
		player_preview_row.size.y >= player_wrapper.custom_minimum_size.y
		and lab.player_drawer.visible
		and lab.player_drawer.size.x >= 282.0
		and lab.player_drawer_button.button_pressed
		and player_effect_option.size.x >= 100.0,
		"100%卡面完整容纳在战场行内，左侧配置抽屉可展开使用"
	)
	lab._set_drawer_open("player", false)
	lab._set_drawer_open("output", true)
	await process_frame
	_expect(
		lab.output_drawer.visible
		and lab.output_drawer.size.y >= 245.0
		and lab.output_drawer_button.button_pressed,
		"底部日志与轨迹抽屉可独立展开"
	)
	lab._set_drawer_open("output", false)
	var player_cooldown_spin := (lab._side_controls["player"] as Dictionary)["cooldown"] as SpinBox
	player_cooldown_spin.value = 20.0
	lab._on_editor_changed("player")
	await process_frame
	await process_frame
	player_wrapper = (lab.state_rows["player_back"] as HBoxContainer).get_child(0) as Control
	var preview_slot := player_wrapper.get_node("VirtualSquad") as BoardSlot
	_expect(preview_slot.get_squad_data().get_card_count() == 2 and preview_slot.get_primary_card_view().card_data.art_texture != null, "实时预览复用正式卡堆与卡面美术")
	var preview_action_view := preview_slot.get_card_view(preview_slot.get_squad_data().get_action_source())
	_expect(
		preview_action_view.cooldown_label.text == "20"
		and preview_action_view.cooldown_label.get_rendered_size() == Vector2(16, 12),
		"大于9.9秒的实验室冷却显示无小数、两位整数紧贴"
	)
	player_cooldown_spin.value = 2.0
	lab._on_editor_changed("player")
	var player_runes := (lab._side_controls["player"] as Dictionary)["runes"] as Array[OptionButton]
	player_runes[4].select(0)
	lab._on_editor_changed("player")
	player_wrapper = (lab.state_rows["player_back"] as HBoxContainer).get_child(0) as Control
	_expect(int(player_wrapper.get_meta("unscaled_squad_width")) == 129, "编辑第五枚符文后立即从展开双卡刷新为紧密双卡")
	player_runes[4].select(CardData.ElementType.WATER + 1)
	lab._on_editor_changed("player")

	var aura_scenario := BattleLabScenario.create_default()
	for spec: Dictionary in aura_scenario.player_squads:
		spec["enabled"] = false
	for index: int in 3:
		var spec := aura_scenario.player_squads[index]
		spec["enabled"] = true
		spec["row"] = "front"
		spec["position"] = index
		spec["name"] = "人类%d" % (index + 1)
		spec["health"] = 6
		spec["race"] = CardData.RaceType.HUMAN
	aura_scenario.player_squads[0]["name"] = "民兵指挥官"
	aura_scenario.player_squads[0]["effect_card"] = "militia_commander"
	lab.scenario = aura_scenario
	lab._load_scenario_into_controls()
	await process_frame
	await process_frame
	var aura_healths: Array[int] = []
	for state: BattleSquadState in lab.battle_controller.player_states:
		aura_healths.append(state.displayed_health)
	_expect(
		aura_healths == [8, 10, 8]
		and not lab.battle_controller.is_running()
		and lab.battle_controller.run_reward_ledger.get_entries().is_empty(),
		"配置预览只结算持续光环：三个相邻人类立即显示8/10/8生命，不触发突击奖励"
	)
	var middle_slot := lab._battle_state_slots[lab.battle_controller.player_states[1]] as BoardSlot
	_expect(middle_slot.get_primary_card_view().health_label.text == "10", "民兵指挥官生命光环直接显示在战场卡面")

	((lab._side_controls["player"] as Dictionary)["slot"] as OptionButton).select(2)
	lab._on_slot_selected(2, "player")
	var player_race_option := (lab._side_controls["player"] as Dictionary)["race"] as OptionButton
	player_race_option.select(CardData.RaceType.ELF)
	lab._on_editor_changed("player")
	await process_frame
	await process_frame
	aura_healths.clear()
	for state: BattleSquadState in lab.battle_controller.player_states:
		aura_healths.append(state.displayed_health)
	_expect(aura_healths == [8, 8, 6], "把第三张牌改为精灵后，种族邻接光环立即移除旧加成并重新计算")

	lab.scenario = BattleLabScenario.create_default()
	lab._load_scenario_into_controls()
	player_effect_option = (lab._side_controls["player"] as Dictionary)["effect"] as OptionButton
	player_effect_option.select(BattleLabEffectLibrary.get_option_index(BattleLabEffectLibrary.ACTION_REINFORCEMENT))
	lab._on_editor_changed("player")
	lab._start_battle()
	_expect(
		lab.battle_controller.effect_runtime.bindings.size() == 1
		and is_equal_approx(
			lab.battle_controller.player_states[0].modifiers.get_additive(
				BattleModifier.Stat.REINFORCEMENT
			),
			3.0
		)
		and lab.trace_text.text.contains("[效果]"),
		"实验室测试卡绑定正式D2-3运行时并显示效果轨迹"
	)
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.03).timeout
	var player_state := lab.battle_controller.player_states[0] as BattleSquadState
	var player_slot := lab._battle_state_slots[player_state] as BoardSlot
	var player_action_view := player_slot.get_card_view(player_state.get_action_source())
	_expect(player_action_view.value_label.text == "13", "单次强化立即反映为卡面10→13")
	lab._step_batch()
	_expect(lab.battle_controller.batch_count == 1 and not lab._log_entries.is_empty(), "单步批次推进正式分层结算并生成结构化日志")
	_expect(lab.trace_text.text.contains("[层0") and lab.trace_text.text.contains("[层1"), "分层轨迹显示基础层与元素层")
	_expect(lab.battle_effect_layer.get_child_count() > 0, "实验室复用正式战斗弹道与命中特效层")
	lab._paused = false
	await create_timer(CardView.BATTLE_NUMBER_TWEEN_DURATION + 0.25).timeout
	lab._paused = true
	var all_card_values_match := player_action_view.value_label.text == "10"
	for state: BattleSquadState in lab.battle_controller.get_all_states():
		var slot := lab._battle_state_slots[state] as BoardSlot
		var vitals_view := slot.get_card_view(state.get_vitals_source())
		all_card_values_match = (
			all_card_values_match
			and vitals_view.health_label.text == str(state.displayed_health)
			and vitals_view.armor_label.text == str(state.displayed_armor)
		)
	_expect(
		all_card_values_match,
		"连续播放逐帧刷新时，强化消费、受伤与护甲变化仍会实时完成卡面跳数"
	)
	var first_entry := lab._log_entries[0] as BattleLogEntry
	lab._on_log_meta_hover_started("formula:%d:0" % first_entry.group_id)
	_expect(lab.formula_popup.visible and lab.formula_popup_text.text.contains("牌型倍率"), "实验室日志整段结果可悬停查看公式")
	lab._on_log_meta_hover_ended("")
	lab._run_assertion()
	_expect(lab.report_text.text.contains("PASS"), "单场自动断言检查预期结果与状态边界")
	lab._run_combination_matrix()
	_expect(lab.report_text.text.contains("100 / 100 通过"), "批量矩阵覆盖五种行动、五种元素和二至五枚档位")
	lab.battle_controller.clear_battle()
	test_root.remove_child(lab)
	lab.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
