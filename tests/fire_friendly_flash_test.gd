extends "res://tests/d2_7_shop_presentation_test.gd"

## 用真实战斗验证火的三种行动模式；原生画面检查卡面瞬白，不伪造结算事件。
const Fire = preload("res://scripts/battle/battle_fire_visual.gd")
var events: Array[BattleEffectEvent] = []


func _run() -> void:
	create_timer(55).timeout.connect(func(): quit(1))
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	await process_frame
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-fire-friendly-test-save.json"
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main.set_process(false)
	main.set_battle_speed(1)
	for mode: int in [CardData.ActionType.MELEE, CardData.ActionType.HEAL, CardData.ActionType.DEFENSE]:
		await _test_mode(mode)
	main.set_process(true)
	await _test_lab()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("Fire friendly/flash failures: ", failures)
	quit(1 if failures else 0)


func _test_mode(mode: int) -> void:
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	main.resource_board_state = ResourceBoardState.new()
	main.resource_board_state.initialize_level(&"fire_flash_test", RandomNumberGenerator.new())
	var actor := _card(mode, 0.5, 2000)
	actor.base_value = 10
	var owned: OwnedCard = main.owned_card_collection.create_card(actor)
	owned.resolved_runes.assign([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
	owned.rune_revealed.assign([true, true, true])
	main.back_row.add_squad(SquadData.from_owned_card(owned), 0)
	main.front_row.add_squad(SquadData.from_cards([_card(CardData.ActionType.MELEE, 99, 2000), _card(CardData.ActionType.MELEE, 99, 2000)]), 0)
	main.enemy_front_row.add_squad(SquadData.from_card(_card(CardData.ActionType.MELEE, 99, 2000)), 0)
	check(main.start_battle(4201, false), "%s：正式战斗启动" % mode)
	var controller: BattleController = main.battle_controller
	controller.set_process(false)
	# 等待真实战场让位动画结束，再冻结时间并读取卡面像素。
	await create_timer(0.4).timeout
	events.clear()
	controller.effect_resolved.connect(_collect)
	for state: BattleSquadState in controller.get_all_states():
		if state.side == BattleSquadState.Side.PLAYER and state.row_key == &"player_front": state.current_health = 100
	for index: int in 100:
		if not controller.active_continuous_effects.is_empty(): break
		controller.advance_time(0.025)
	main._sync_fire_burn_visuals()
	check(not controller.active_continuous_effects.is_empty(), "%s：真实行动生成持续状态" % mode)
	if controller.active_continuous_effects.is_empty(): return
	var status: Dictionary = controller.active_continuous_effects[0]
	var target: BattleSquadState = status.target
	(status.source as BattleSquadState).runtime_base_cooldown_override = 99
	(status.source as BattleSquadState).reset_action_cooldown()
	check(target.side == (BattleSquadState.Side.ENEMY if mode == CardData.ActionType.MELEE else BattleSquadState.Side.PLAYER), "%s：持续效果仍选择正确阵营" % mode)
	var visual := main._fire_burn_visuals.get(target) as Fire
	check(is_instance_valid(visual) and not visual.white_flash.visible, "%s：施加时显示火焰，尚未跳结算不瞬白" % mode)
	if not is_instance_valid(visual): return
	controller.advance_time(float(status.next_time) - controller.elapsed_seconds)
	main._sync_fire_burn_visuals()
	var slot: BoardSlot = main._battle_state_slots[target]
	check(events.size() == 1 and events[0].effective_amount > 0.0, "%s：第一跳真实改变伤害／治疗／护甲数值" % mode)
	check(visual.white_flash.visible and visual.white_flash.get_child_count() == slot.squad_data.get_card_count() and is_equal_approx(visual.white_flash.modulate.a, 1.0), "%s：同一跳立即使每张目标卡面瞬白" % mode)
	var point := Vector2i(slot.get_global_rect().get_center())
	await process_frame
	RenderingServer.force_draw(false)
	var white := main.get_viewport().get_texture().get_image()
	white.save_png("/private/tmp/project-card-fire-white-%d.png" % mode)
	var pixel := white.get_pixelv(point)
	check(minf(minf(pixel.r, pixel.g), pixel.b) > 0.95, "%s：原生画面中目标卡面中心实际变白" % mode)
	var before := visual.white_flash.modulate.a
	await create_timer(0.08).timeout
	main._sync_fire_burn_visuals()
	check(visual.white_flash.modulate.a == before, "%s：战斗时钟停止时瞬白保持冻结" % mode)
	controller.set_battle_speed_multiplier(3.0)
	controller._process(0.02)
	main._sync_fire_burn_visuals()
	check(visual.white_flash.visible and absf(visual.white_flash.modulate.a - 0.25) < 0.001, "%s：三倍速推进0.06战斗秒，瞬白同步衰减" % mode)
	controller.advance_time(0.07)
	main._sync_fire_burn_visuals()
	check(not visual.white_flash.visible, "%s：0.12战斗秒后恢复卡面" % mode)
	await process_frame
	RenderingServer.force_draw(false)
	var restored := main.get_viewport().get_texture().get_image().get_pixelv(point)
	check(restored != pixel, "%s：原生画面恢复卡面原色" % mode)
	# 三火的下一跳及最终一跳均应再次瞬白。
	for index: int in 2:
		var next: Dictionary = controller.active_continuous_effects[0]
		controller.advance_time(float(next.next_time) - controller.elapsed_seconds)
		main._sync_fire_burn_visuals()
		check(visual.white_flash.visible and is_equal_approx(visual.white_flash.modulate.a, 1.0), "%s：第%d跳重新触发瞬白" % [mode, index + 2])
	controller.advance_time(0.3)
	main._sync_fire_burn_visuals()
	check(main._fire_burn_visuals.is_empty(), "%s：状态结束后火焰与瞬白一起清理" % mode)
	controller.effect_resolved.disconnect(_collect)
	main._clear_battle_presentation_for_preparation()
	controller.clear_battle()
	main.current_phase = main.GamePhase.PREPARE
	await process_frame


func _card(mode: int, cooldown: float, health: int) -> CardData:
	var result: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
	result.action_type = mode
	result.acquisition_action_types.clear()
	result.cooldown_seconds = cooldown
	result.max_health = health
	result.base_value = 0
	result.armor = 0
	return result


func _collect(event: BattleEffectEvent) -> void:
	if event.visual_kind in [&"fire_tick", &"fire_finish"]: events.append(event)


func _test_lab() -> void:
	var lab := preload("res://scenes/tools/BattleLab.tscn").instantiate() as BattleLab
	root.add_child(lab)
	lab.set_process(false)
	for preset: StringName in [&"fire_heal", &"fire_armor"]:
		lab.scenario = BattleLabScenario.create_preset(&"fire_heal")
		if preset == &"fire_armor": lab.scenario.player_squads[0]["action"] = CardData.ActionType.DEFENSE
		lab._load_scenario_into_controls()
		lab._start_battle()
		for index: int in 200:
			if not lab.battle_controller.active_continuous_effects.is_empty(): break
			lab.battle_controller.advance_time(0.05)
		lab._sync_fire_burn_visuals()
		check(not lab._fire_burn_visuals.is_empty(), "%s：战斗实验室也使用同一火焰表现" % preset)
		if not lab._fire_burn_visuals.is_empty():
			var status: Dictionary = lab.battle_controller.active_continuous_effects[0]
			var expected_mode := CardData.ActionType.HEAL if preset == &"fire_heal" else CardData.ActionType.DEFENSE
			check(status.action_type == expected_mode and (status.target as BattleSquadState).side == BattleSquadState.Side.PLAYER, "%s：实验室实际结算正确的友军行动模式" % preset)
			var finish_time := float(status.next_time) + float(status.ticks_remaining - 1) * float(status.interval)
			for state: BattleSquadState in lab.battle_controller.get_all_states():
				state.runtime_base_cooldown_override = 99
				state.reset_action_cooldown()
			events.clear()
			lab.battle_controller.effect_resolved.connect(_collect)
			lab.battle_controller.advance_time(float(status.next_time) - lab.battle_controller.elapsed_seconds)
			var visual := lab._fire_burn_visuals.get(status.target) as Fire
			check(is_instance_valid(visual) and visual.white_flash.visible, "%s：实验室真实结算也触发瞬白" % preset)
			lab.battle_controller.advance_time(finish_time - lab.battle_controller.elapsed_seconds)
			check(events.any(func(event: BattleEffectEvent) -> bool: return event.visual_kind == &"fire_finish") and visual.white_flash.visible and visual._finisher, "%s：五火终结追加同样触发瞬白与增强" % preset)
			lab.battle_controller.effect_resolved.disconnect(_collect)
		lab._return_to_configuration_preview()
		check(lab._fire_burn_visuals.is_empty(), "%s：退出实验室战斗后清理" % preset)
	lab.queue_free()
	await process_frame
