extends SceneTree

## 使用正式资源、战斗队列与真实主场景，验证文案上下文及均衡新效果。
const MAIN := preload("res://scenes/Main.tscn")
const IDS: Array[String] = ["twilight_knight", "twilight_guard", "twilight_elemental", "starmoon_leopard", "sunmoon_amulet"]
var checks := 0
var failures := 0
var sequence := 0
var current: BattleController

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("均衡回归超时"); quit(2))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func owned(id: String) -> OwnedCard:
	sequence += 1
	var card := OwnedCard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = sequence + 619
	card.initialize(load("res://resources/cards/%s.tres" % id), StringName("balance:%d" % sequence), sequence, rng)
	return card

func formation(cards: Array[OwnedCard], side: int, back: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in cards.size():
		result.append({"squad_data": SquadData.from_owned_card(cards[index]), "row_key": StringName(("player_" if side == 0 else "enemy_") + ("back" if index in back else "front")), "formation_index": index})
	return result

func battle(player: Array[OwnedCard], enemy: Array[OwnedCard], back: Array[int] = [], enemy_back: Array[int] = [], equipment: OwnedCard = null) -> BattleController:
	if current != null:
		current.clear_battle()
		current.free()
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = false
	var player_formation := formation(player, 0, back)
	if equipment != null: (player_formation[0].squad_data as SquadData).equip_item(equipment)
	var catalog: Array[CardData] = [load("res://resources/cards/fire_element_shard.tres")]
	current.start_battle(player_formation, formation(enemy, 1, enemy_back), 210101, false, StringName("balance_battle:%d" % sequence), [], [], [], [], catalog)
	return current

func hit(source: BattleSquadState, target: BattleSquadState, amount: float, primary: bool = true) -> BattleEffectEvent:
	var event := current.twisted_vein.make_event(source, target, amount, CardData.ActionType.MAGIC, false, "均衡实际命中")
	event.is_base_action = primary
	current._apply_effect_event(event)
	return event

func _run() -> void:
	_test_knight()
	_test_element_and_amulet()
	_test_guard()
	if current != null:
		current.clear_battle()
		current.free()
		current = null
	await _test_ui()
	print("均衡三场景与特效：%d 项，%d 失败" % [checks, failures])
	quit(failures)

func _test_knight() -> void:
	var knight := owned("twilight_knight")
	knight.set_emblem_slot(0, {"emblem_id": &"奶酪", "instance_id": &"balance_cheese"})
	knight.set_wound_slot(0, {"wound_id": &"brain_death", "instance_id": &"balance_brain"})
	var pouch := owned("crystal_shard_pouch")
	var c := battle([knight, owned("stargazer"), owned("baggage_muleteer")], [owned("baggage_muleteer"), owned("baggage_muleteer"), owned("baggage_muleteer"), owned("baggage_muleteer")], [1], [], pouch)
	var actor := c.player_states[0]
	var stunned := 0
	for enemy: BattleSquadState in c.enemy_states:
		if enemy.sleep_source_until.has(StringName("twilight_knight:%d" % actor.runtime_id)): stunned += 1
	check(stunned == 3, "开战前排突击随机3个不同目标")
	check(actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) >= 8, "正式脑死亡突击执行")
	check(is_equal_approx(actor.cooldown_progress, 0.5 / actor.get_action_interval()), "正式奶酪突击减少0.5秒冷却")
	var equipment_rewards := c._next_reward_instance_sequence
	var initial_progress := actor.cooldown_progress
	var rewards := c.run_reward_ledger.get_entries().size()
	var reinforcement := actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	check(c.silvermoon.swap(actor, c.player_states[2]), "同排换位合法")
	c.effect_runtime.process_due(c.elapsed_seconds)
	check(c._next_reward_instance_sequence == equipment_rewards and actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == reinforcement, "同排换位不重触装备与伤势突击")
	check(c.silvermoon.swap(actor, c.player_states[1]), "前排换入后排")
	c.effect_runtime.process_due(c.elapsed_seconds)
	var fatigued := 0
	for enemy: BattleSquadState in c.enemy_states:
		if enemy.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1: fatigued += 1
	check(fatigued == 3, "换后排对3个不同敌军疲劳1层")
	check(c._next_reward_instance_sequence == equipment_rewards + 1, "换排重触碎晶小包装备突击并获得1份碎晶收获")
	check(actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) >= reinforcement + 8, "换排重触脑死亡伤势突击")
	check(is_equal_approx(actor.cooldown_progress, initial_progress + 0.5 / actor.get_action_interval()), "换排重触奶酪纹章突击减少0.5秒")
	check(c.run_reward_ledger.get_entries().size() == rewards, "其他小队观星者不会被骑士换排广播重触")
	for enemy: BattleSquadState in c.enemy_states:
		check(not enemy.masking_forbidden and not enemy.priority_reduction_forbidden, "骑士旧限制光环已删除")
	c.elapsed_seconds = 0.75
	check(c.silvermoon.swap(actor, c.player_states[1]), "骑士返回前排")
	c.effect_runtime.process_due(c.elapsed_seconds)
	var refreshed := 0
	for enemy: BattleSquadState in c.enemy_states:
		var until := float(enemy.sleep_source_until.get(StringName("twilight_knight:%d" % actor.runtime_id), 0.0))
		if is_equal_approx(until, 1.75): refreshed += 1
	check(refreshed == 3, "每次换排再次触发眩晕并按当前时钟计1秒")
	actor.grant_runtime_keyword(&"silenced", 513)
	c.silvermoon.swap(actor, c.player_states[1])
	c.effect_runtime.process_due(c.elapsed_seconds)
	check(c._next_reward_instance_sequence == equipment_rewards + 2, "沉默骑士不重触换排突击")
	c = battle([owned("twilight_knight"), owned("baggage_muleteer")], [owned("baggage_muleteer"), owned("baggage_muleteer")], [1])
	actor = c.player_states[0]
	c.silvermoon.swap(actor, c.player_states[1])
	c.silvermoon.swap(actor, c.player_states[1])
	for enemy: BattleSquadState in c.enemy_states:
		check(enemy.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1 and enemy.is_sleeping(0.0), "同帧连续换排分别执行后排疲劳和前排眩晕")
	c = battle([owned("twilight_knight")], [owned("baggage_muleteer"), owned("baggage_muleteer")])
	for enemy: BattleSquadState in c.enemy_states: check(enemy.is_sleeping(0.0), "少于3名敌人时全部眩晕")
	c.advance_time(0.999)
	for enemy: BattleSquadState in c.enemy_states: check(enemy.is_sleeping(c.elapsed_seconds) and is_zero_approx(enemy.cooldown_progress), "眩晕期间暂停普通冷却")
	c.advance_time(0.001)
	for enemy: BattleSquadState in c.enemy_states: check(not enemy.is_sleeping(c.elapsed_seconds), "眩晕在第1秒准确结束")
	c = battle([owned("twilight_knight")], [owned("baggage_muleteer"), owned("baggage_muleteer")], [0])
	for enemy: BattleSquadState in c.enemy_states: check(enemy.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1, "后排开战突击疲劳且少于3名全选")
	var hp := c.enemy_states[0].current_health
	c.advance_time(1.0)
	check(is_equal_approx(c.enemy_states[0].current_health, hp - 1.0), "新增疲劳接入真实每秒环境伤害")

func _test_element_and_amulet() -> void:
	var c := battle([owned("twilight_elemental"), owned("starmoon_leopard")], [owned("moon_hawk")])
	var element := c.player_states[0]
	for state: BattleSquadState in c.get_all_states(): state.apply_sleep(&"timing_fixture", 100.0)
	element.cooldown_progress = 0.4
	element.refresh_cooldown_after_modifier_change()
	check(element.get_zeal_layers() == 10 and element.get_display_action_value() == 2, "元素改热诚10且撤除旧数值5")
	check(is_equal_approx(element.remaining_cooldown, 2.0), "热诚10按现有速度规则缩短冷却")
	c.advance_time(9.999)
	check(element.get_zeal_layers() == 10, "第10秒前保持热诚10")
	c.advance_time(0.001)
	check(element.get_zeal_layers() == 0, "第10秒准确撤回热诚")
	check(is_equal_approx(element.cooldown_progress, 0.4) and is_equal_approx(element.remaining_cooldown, 3.0), "到期保留冷却进度并重新换算剩余秒数")
	c = battle([owned("twilight_elemental"), owned("starmoon_leopard")], [owned("moon_hawk")])
	element = c.player_states[0]
	var leopard := c.player_states[1]
	check(leopard.get_zeal_layers() == 4, "豹前排热诚4")
	leopard.row_key = &"player_back"
	c.recalculate_logical_layout()
	c.silvermoon.swap(element, leopard)
	check(element.get_zeal_layers() == 0 and is_equal_approx(c.silvermoon.fatigue_multiplier(element), 0.5), "元素后排撤回热诚并减半疲劳")
	c.silvermoon.swap(element, leopard)
	check(element.get_zeal_layers() == 10, "10秒内回到前排恢复热诚")
	check(leopard.get_zeal_layers() == 0 and leopard.get_display_action_value() == 3, "豹后排数值1")
	var hp := element.current_health
	c.silvermoon.swap(element, leopard)
	var fatigue := element.add_buff_stacks(BattleRules.FATIGUE_BUFF_ID, 1)
	c.twisted_vein.fatigue_next[element] = {"next_time": 1.0, "paused_at": -1.0}
	c.advance_time(1.0)
	check(fatigue == 1 and is_equal_approx(element.current_health, hp - 0.5), "后排元素疲劳减益精确扣0.5生命")
	c.elapsed_seconds = 30.0
	var storms := c._prepare_fatigue_events(c.get_all_states())
	for event: BattleEffectEvent in storms:
		if event.target == element: check(is_equal_approx(event.exact_amount, 0.5), "后排元素疲劳风暴也减半")
	var item := owned("sunmoon_amulet")
	c = battle([owned("baggage_muleteer"), owned("baggage_muleteer")], [owned("moon_hawk")], [1], [], item)
	var carrier := c.player_states[0]
	check(carrier.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1 and carrier.get_zeal_layers() == 0, "护符前排数值1")
	c.silvermoon.swap(carrier, c.player_states[1])
	check(carrier.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0 and carrier.get_zeal_layers() == 2, "护符后排热诚2且撤回前排加成")
	c.silvermoon.swap(carrier, c.player_states[1])
	check(carrier.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1 and carrier.get_zeal_layers() == 0, "反复换排不叠加护符光环")

func _test_guard() -> void:
	var c := battle([owned("twilight_guard")], [owned("baggage_muleteer")])
	var guard := c.player_states[0]
	var attacker := c.enemy_states[0]
	check(c.has_effective_dazzling(guard), "守卫前排耀眼生效")
	var hp := attacker.current_health
	hit(attacker, guard, 0.1)
	check(is_equal_approx(attacker.current_health, hp - 2.0), "守卫主攻击反伤固定2，无类型倍率")
	hp = attacker.current_health
	hit(attacker, guard, 0.1, false)
	check(is_equal_approx(attacker.current_health, hp), "独立效果伤害不产生攻击反伤")
	hit(attacker, guard, 100.0)
	check(is_equal_approx(attacker.current_health, hp - 2.0), "致死攻击仍触发守卫反伤")
	c = battle([owned("twilight_guard")], [owned("baggage_muleteer")])
	c.use_projectile_timing = true
	guard = c.player_states[0]
	attacker = c.enemy_states[0]
	attacker.current_health = 2.0
	hit(attacker, guard, 100.0)
	c._finalize_batch()
	check(c.current_result == BattleController.Result.NONE and c._pending_projectile_contexts.size() == 1, "致死反伤真实弹道到达前不提前宣布败北")
	c.advance_time(2.0)
	check(c.current_result == BattleController.Result.DRAW and attacker.current_health <= 0.0, "真实致死反伤弹道完成后按双方阵亡结算")
	c = battle([owned("twilight_guard"), owned("baggage_muleteer")], [owned("baggage_muleteer")], [0, 1])
	guard = c.player_states[0]
	var target := c.player_states[1]
	attacker = c.enemy_states[0]
	check(not c.has_effective_dazzling(guard), "守卫后排无前排耀眼")
	var misses := 0
	for index: int in 80:
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = c._random.state
		var expected := expected_rng.randi_range(1, 10) == 10
		var event := hit(attacker, target, 0.001)
		check(event.missed == expected, "实际1d10仅掷出10无效攻击：%d" % index)
		if event.missed:
			misses += 1
			check(not event.can_trigger_element_chain, "无效攻击同时停止元素追加")
	check(misses > 0 and misses < 80, "固定种子包含保护成功与失败")
	var rng_state := c._random.state
	hit(attacker, target, 0.01, false)
	check(c._random.state == rng_state, "后排保护不对独立伤害掷骰")
	var event := c.twisted_vein.make_event(attacker, target, 0.01, CardData.ActionType.HEAL, false, "治疗")
	event.is_base_action = true
	event.effect_kind = BattleEffectEvent.EffectKind.HEALING
	c._apply_effect_event(event)
	check(c._random.state == rng_state, "后排保护不对治疗行动掷骰")
	target.squad_data.get_effect_source_instance().set_emblem_slot(0, {"emblem_id": &"天选之子", "instance_id": &"balance_advantage"})
	c._register_formation_emblems()
	for index: int in 20:
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = c._random.state
		var a := expected_rng.randi_range(1, 10)
		var b := expected_rng.randi_range(1, 10)
		var protected := maxi(a, b) == 10
		var guarded_event := hit(attacker, target, 0.001)
		check(guarded_event.missed == protected, "后排保护沿用真实优势骰取较高结果：%d" % index)
	guard.row_key = &"player_front"
	c.recalculate_logical_layout()
	rng_state = c._random.state
	hit(attacker, target, 0.01)
	check(c._random.state == rng_state, "守卫离开后排即撤回后排保护")

func _test_ui() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-balance-row-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	for id: String in IDS:
		var card := owned(id)
		var view := preload("res://scenes/ui/CardView.tscn").instantiate() as CardView
		view.set_owned_card(card)
		view.set_card_data(card.card_data)
		root.add_child(view)
		check(view._get_instance_effect_text() == card.card_data.effect_text, "收藏／商店通用文案：" + id)
		main._open_card_inspection(card.card_data, card, view, true)
		check(main._inspection_card_view._get_instance_effect_text() == card.card_data.effect_text, "非场上检视通用文案：" + id)
		main._close_card_inspection(true)
		view.free()
		if id == "sunmoon_amulet": continue
		main.front_row.add_squad(SquadData.from_owned_card(card), main.front_row.get_squad_count())
		var slot: BoardSlot = main.front_row.get_squads().back()
		var live := slot.get_card_views()[0]
		check(live._get_instance_effect_text() == card.card_data.front_effect_text, "准备前排文案：" + id)
		main._open_card_inspection(card.card_data, card, live, true)
		check(main._inspection_card_view._get_instance_effect_text() == card.card_data.front_effect_text, "前排检视同步上下文：" + id)
		var box: Node = main._inspection_overlay.get_node_or_null("InspectionEffectSideBox")
		if box != null: check((box.get_child(0) as Label).text == card.card_data.front_effect_text, "完整侧栏使用前排文本：" + id)
		main._close_card_inspection(true)
		main.back_row.add_squad(SquadData.from_owned_card(owned(id)), main.back_row.get_squad_count())
		var back_slot: BoardSlot = main.back_row.get_squads().back()
		check(back_slot.get_card_views()[0]._get_instance_effect_text() == card.card_data.back_effect_text, "准备后排文案：" + id)
	var carrier_slot: BoardSlot = main.front_row.get_squads()[1]
	var item := owned("sunmoon_amulet")
	carrier_slot.get_squad_data().equip_item(item)
	carrier_slot._refresh()
	var indicator := carrier_slot._equipment_indicator as EquipmentIndicator
	indicator._on_mouse_entered()
	check(indicator._hover_card._get_instance_effect_text() == item.card_data.front_effect_text, "装备悬停使用承载小队前排文本")
	main._open_card_inspection(item.card_data, item, indicator._hover_card, true)
	check(main._inspection_card_view._get_instance_effect_text() == item.card_data.front_effect_text, "装备检视继承承载排")
	main._close_card_inspection(true)
	var enemy := owned("moon_hawk")
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy), 0)
	check(main.start_battle(210101, false), "正式主场景开始均衡战斗")
	main.battle_controller.set_process(false)
	var front_state: BattleSquadState
	var back_state: BattleSquadState
	for state: BattleSquadState in main.battle_controller.player_states:
		if state.squad_data == carrier_slot.get_squad_data(): front_state = state
		elif state.row_key == &"player_back" and state.get_effect_source().id == &"twilight_guard": back_state = state
	main.battle_controller.silvermoon.swap(front_state, back_state)
	await process_frame
	await process_frame
	var live := carrier_slot.get_card_views()[0]
	check(live._get_instance_effect_text() == live.card_data.back_effect_text and live.effect_text_label.text == live.card_data.back_effect_text, "战斗换排立即更新卡面文本")
	indicator._clear_hover_card(true)
	indicator._on_mouse_entered()
	check(indicator._hover_card._get_instance_effect_text() == item.card_data.back_effect_text, "战斗换排装备弹窗使用新排而非旧拖拽配置")
	if "--snapshot" in OS.get_cmdline_user_args():
		var knight_slot: BoardSlot = main.front_row.get_squads()[0]
		var knight_view := knight_slot.get_card_views()[0]
		main._open_card_inspection(knight_view.card_data, knight_slot.get_squad_data().get_effect_source_instance(), knight_view, true)
		main._toggle_inspection_display_mode()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-balance-front.png") == OK, "原生前排检视截图")
		main._close_card_inspection(true)
		indicator._clear_hover_card(true)
		indicator._on_mouse_entered()
		main._open_card_inspection(item.card_data, item, indicator._hover_card, true)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-balance-equipment-back.png") == OK, "原生后排装备检视截图")
		main._close_card_inspection(true)
	main.battle_controller.clear_battle()
	main.queue_free()
	await process_frame
	await process_frame
