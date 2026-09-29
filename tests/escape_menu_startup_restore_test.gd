extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const BattleController = preload("res://scripts/battle/battle_controller.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var snapshot: Dictionary = main._startup_runtime_snapshot
	_check(not snapshot.is_empty(), "Main 初始化完成后捕获一次启动快照")
	var initial_restore_button := _find_button(main._escape_pause_menu, "还原")
	_check(initial_restore_button != null and not initial_restore_button.disabled, "启动快照就绪后启用菜单还原")
	var startup_seed := int(snapshot.get("battle_seed", -1))
	var startup_speed := int(snapshot.get("battle_speed_index", -1))
	var startup_volume := float(snapshot.get("volume_percent", -1.0))
	var startup_phase := int(snapshot.get("phase", -1))
	var startup_gold := int((snapshot.get("reward_state", {}) as Dictionary).get("gold", -1))
	_check(
		not bool(snapshot.get("show_battle_target_priority", true))
		and not main._show_battle_target_priority,
		"显示受击优先级默认关闭并记录在启动还原基准中"
	)
	var priority_toggle := _find_node(main._escape_pause_menu, "ShowBattleTargetPriority") as CheckButton
	if priority_toggle != null:
		priority_toggle.toggled.emit(true)
	_check(
		priority_toggle != null
		and main._show_battle_target_priority
		and priority_toggle.button_pressed,
		"Esc菜单开关通过信号即时更新上场卡显示状态"
	)
	main.battle_seed_spin.value = (startup_seed + 123) % 999999999
	main.set_battle_speed(3)
	main.battle_volume_slider.value = 77.0
	main._capture_startup_runtime_snapshot()
	_check(
		int(main._startup_runtime_snapshot["battle_seed"]) == startup_seed,
		"反复开关 Esc 菜单不会重新捕获并覆盖启动基准"
	)

	var spell: OwnedCard
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type == CardData.CardType.SPELL:
			spell = owned
			break
	_check(spell != null, "启动收藏包含可验证耐久的真实法术实例")
	if spell != null:
		spell.spell_durability = 1
		main._startup_runtime_snapshot["prepared_spell_instance_ids"] = [spell.instance_id]
		var saved_collection := main._startup_runtime_snapshot["collection"] as Dictionary
		for card_state_value: Variant in saved_collection.get("cards", []) as Array:
			var card_state := card_state_value as Dictionary
			if card_state.get("instance_id", &"") == spell.instance_id:
				card_state["spell_durability"] = 1
		main.prepared_spell_instance_ids.assign([spell.instance_id])
		main._battle_snapshot = main._capture_battle_snapshot(&"startup_restore_spell", startup_seed)
		var empty_ledger: Array[Dictionary] = []
		var settlement: Dictionary = main.battle_settlement_service.settle(
			main._battle_snapshot,
			empty_ledger,
			empty_ledger,
			main.owned_card_collection,
			main.run_reward_state,
			main.settlement_journal
		)
		_check(
			bool(settlement.get("success", false))
			and int(settlement.get("spent_spells_removed", 0)) == 1
			and main.owned_card_collection.get_by_instance_id(spell.instance_id) == null,
			"正式结算事务扣尽法术耐久并从收藏移除实例"
		)
		main.run_reward_state.add_gold(9)
		main.prepared_spell_instance_ids.clear()
		for owned: OwnedCard in main.owned_card_collection.get_cards():
			if owned.card_data.card_type == CardData.CardType.MINION:
				main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
				break
		var battle_started: bool = main.start_battle(startup_seed, true)
		_check(
			battle_started and main.current_phase == main.GamePhase.BATTLE,
			"可在真实战斗运行中打开还原菜单"
		)
		main._on_escape_pause_menu_requested()
		var restore_button := _find_button(main._escape_pause_menu, "还原")
		if restore_button != null:
			restore_button.pressed.emit()
		var restored_spell: OwnedCard = main.owned_card_collection.get_by_instance_id(spell.instance_id)
		_check(
			restored_spell != null
			and restored_spell.spell_durability == 1
			and main.prepared_spell_instance_ids == [spell.instance_id],
			"Esc 还原找回已耗尽移除的法术实例、剩余耐久与准备顺序"
		)
		_check(
			main.get_tree().paused
			and main._escape_pause_menu.is_menu_open()
			and main.current_phase == startup_phase
			and not main._show_battle_target_priority
			and priority_toggle != null
			and not priority_toggle.button_pressed
			and not main._last_minion_inspection_library_expanded,
			"还原后继续停留在暂停菜单并恢复启动阶段"
		)
		_check(
			int(main.battle_seed_spin.value) == startup_seed
			and main.battle_speed_index == startup_speed
			and is_equal_approx(main.battle_volume_slider.value, startup_volume),
			"还原战斗种子、速度与音量"
		)
		_check(
			main.run_reward_state.gold == startup_gold
			and not main.settlement_journal.is_committed(&"startup_restore_spell"),
			"恢复启动奖励与结算账本，避免重置后遗留重复发奖凭证"
		)
		main.owned_card_collection.remove_by_instance_id(spell.instance_id)
		main.prepared_spell_instance_ids.clear()
		main.battle_seed_spin.value = 321
		if restore_button != null:
			restore_button.pressed.emit()
		var restored_again: OwnedCard = main.owned_card_collection.get_by_instance_id(spell.instance_id)
		_check(
			restored_again != null
			and restored_again.spell_durability == 1
			and main.prepared_spell_instance_ids == [spell.instance_id]
			and int(main.battle_seed_spin.value) == startup_seed,
			"连续还原结果一致且基准保持不变"
		)
	var return_button := _find_button(main._escape_pause_menu, "返回")
	if return_button != null:
		return_button.pressed.emit()
	_check(not main.get_tree().paused, "返回只释放 Esc 菜单持有的暂停")

	main.queue_free()
	await process_frame
	print("Escape startup restore failures: ", failures)
	quit(1 if failures else 0)


func _find_button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _find_node(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_node(child, node_name)
		if found != null:
			return found
	return null


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)
