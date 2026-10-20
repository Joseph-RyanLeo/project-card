extends SceneTree

## 三张正式卡牌的持续查询、回响、跨战斗事务和磁盘进度验收。
var failures := 0
var assertions := 0
var sequence := 0
var controller: BattleController
var collection := OwnedCardCollection.new()
var rewards := RunRewardState.new()
var journal := RunSettlementJournal.new()
var settlement := BattleSettlementService.new()
var snapshot: BattlePreparationSnapshot
var engraver: OwnedCard
const MAIN := preload("res://scenes/Main.tscn")
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error("FAIL: " + label)
func owned(id: String) -> OwnedCard:
	sequence += 1
	var card := OwnedCard.new()
	card.initialize(load("res://resources/cards/%s.tres" % id), StringName("three:%d" % sequence), sequence)
	return card
func form(cards: Array[OwnedCard], side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in cards.size(): result.append({"squad_data": SquadData.from_owned_card(cards[i]), "row_key": &"player_front" if side == 0 else &"enemy_front", "formation_index": i})
	return result
func battle(cards: Array[OwnedCard], enemies: Array[OwnedCard], context: Dictionary = {}) -> BattleController:
	if controller != null: controller.clear_battle(); controller.free()
	controller = BattleController.new()
	root.add_child(controller)
	controller.use_projectile_timing = false
	controller.start_battle(form(cards, 0), form(enemies, 1), 1013, false, StringName("three:%d" % sequence), [], [], [], [], [], cards, {}, context)
	return controller
func recheck() -> void:
	controller.effect_runtime.recheck_continuous_conditions()
	controller.effect_runtime.process_due(controller.elapsed_seconds)
func echo(state: BattleSquadState) -> void:
	controller.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state})
	controller.effect_runtime.process_due(controller.elapsed_seconds)
func test_commander() -> void:
	var c := battle([owned("militia_commander"), owned("ember_squire"), owned("ember_squire"), owned("ember_squire")], [owned("ember_squire")])
	for state: BattleSquadState in c.player_states:
		check(state.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 2 and state.modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 2, "两名Ⅰ级乡邻来源分别给全体同族+1/+1")
	check(c.enemy_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0, "敌方同族不受益")
	c.player_states[1].moon_shadowed = true
	recheck()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1, "Ⅰ级持有者效果影蔽后撤销该独立来源")
	c.player_states[1].moon_shadowed = false
	c.player_states[1].grant_runtime_keyword(&"silenced", -921)
	recheck()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 1, "Ⅰ级持有者沉默后停止乡邻")
	c.player_states[1].revoke_runtime_keyword(&"silenced", -921)
	recheck()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 2, "效果恢复重新计算，不重复累加")
	c.player_states[1].current_health = 0
	recheck()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0, "0生命但尚未正式退场的邻居不满足乡邻")
	c.player_states[1].current_health = 18
	recheck()
	var health := c.player_states[0].current_health
	c.player_states[0].grant_runtime_keyword(&"silenced", -922)
	recheck()
	check(c.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0 and c.player_states[0].current_health == health, "指挥官失效撤销加成，不倒扣当前生命")
	c = battle([owned("militia_commander"), owned("ember_squire"), owned("moonlight_treant"), owned("ember_squire")], [owned("ember_squire")])
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 0, "两侧种族不匹配时不满足乡邻")
	c = battle([owned("militia_commander"), owned("shadowstep_assassin"), owned("shadowstep_assassin"), owned("shadowstep_assassin"), owned("darkmoon_judge")], [owned("moon_hawk")])
	check(c.player_states[4].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 2 and c.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0, "精灵Ⅰ级乡邻也给高等级精灵加成，不给人类")
	c = battle([owned("militia_commander"), owned("ember_squire"), owned("ember_squire"), owned("ember_squire"), owned("old_wolf_kaspar")], [owned("ember_squire")])
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 6, "老狼为三个符合乡邻的Ⅰ级来源各额外执行一次")
func test_judge() -> void:
	var c := battle([owned("darkmoon_judge"), owned("ember_squire"), owned("ember_squire")], [owned("ember_squire"), owned("ember_squire"), owned("ember_squire")])
	var judge := c.player_states[0]
	judge.current_health = 5
	c.player_states[1].current_health = 4.9
	c.player_states[2].current_health = 5
	c.enemy_states[0].current_health = 4
	c.enemy_states[1].current_health = 6
	c.enemy_states[2].current_health = 1
	c.enemy_states[2].is_banished = true
	echo(judge)
	check(c.player_states[1].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1 and c.enemy_states[0].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1, "回响同时作用于较低当前生命的友敌")
	check(judge.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 0 and c.player_states[2].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 0 and c.enemy_states[1].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 0, "自身、相等和较高生命不获得疲劳")
	check(c.enemy_states[2].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 0, "放逐目标排除")
	check(c.twisted_vein.fatigue_next.has(c.player_states[1]), "疲劳进入已有确定性计时器")
	echo(judge)
	check(c.player_states[1].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 2, "多次回响逐次叠加")
	judge.current_health = 3
	echo(judge)
	check(c.player_states[1].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 2, "按回响时当前生命重新比较，不读生命上限")
func prepare_engraver_battle() -> void:
	sequence += 1
	var id := StringName("engraver:%d" % sequence)
	var row: Array[SquadData] = [SquadData.from_owned_card(engraver)]
	snapshot = BattlePreparationSnapshot.new()
	check(snapshot.initialize(id, 1013, collection, {&"player_front": row}), "建立真实战前快照")
	battle([engraver], [owned("ember_squire")])
	controller.battle_instance_id = id
func complete_victory() -> void:
	controller.enemy_states[0].current_health = 0
	controller._finalize_batch()
	controller._check_battle_result()
	check(controller.current_result == BattleController.Result.PLAYER_VICTORY, "正式胜负入口确认胜利")
func commit() -> Dictionary:
	return settlement.settle(snapshot, controller.permanent_growth_ledger.get_entries(), controller.run_reward_ledger.get_entries(), collection, rewards, journal, controller.owned_card_change_ledger.get_entries())
func test_engraver() -> void:
	engraver = collection.create_card(load("res://resources/cards/rune_engraver.tres"))
	check(engraver.get_effect_text_for_row(&"player_front").contains("还剩2次") and not engraver.card_data.effect_text.contains("突击"), "初始计数显示2并删除突击")
	for win: int in range(1, 5):
		prepare_engraver_battle()
		var before := int(engraver.progress_by_source.get(OwnedCard.RUNE_ENGRAVER_PROGRESS, 0))
		complete_victory()
		check(int(engraver.progress_by_source.get(OwnedCard.RUNE_ENGRAVER_PROGRESS, 0)) == before, "胜利结果在提交前不污染真实拥有实例")
		var earned := controller.run_reward_ledger.get_entries()
		check(earned.size() == (1 if win % 2 == 0 else 0), "每两场胜利奖励一张，无终身两次限制")
		controller._resolve_rune_engraver_progress()
		check(controller.run_reward_ledger.get_entries().size() == earned.size(), "同场重复检查不重复奖励")
		check(commit().success, "正常结算提交进度与奖励")
		check(engraver.get_effect_text_for_row(&"player_front").contains("还剩%d次" % (1 if win % 2 else 2)), "括号显示下次奖励所需胜利次数")
		var count := rewards.pending_emblem_instances.size()
		check(commit().status == &"already_committed" and rewards.pending_emblem_instances.size() == count, "重复事务不增发贴纸")
		if not earned.is_empty(): check(earned[0].parameters.element_sticker and rewards.pending_emblem_instances[-1].element_sticker, "元素类型穿过完整奖励事务保留")
	prepare_engraver_battle()
	controller.player_states[0].current_health = 0
	controller._finalize_batch()
	controller._check_battle_result()
	check(controller.owned_card_change_ledger.get_entries().filter(func(e: Dictionary) -> bool: return e.kind == BattleOwnedCardChangeLedger.KIND_SET_PROGRESS).is_empty(), "失败或阵亡不累计胜利")
	# 跨磁盘保存中途1场进度，并验证重新读回不会重置倒计数。
	engraver.progress_by_source[OwnedCard.RUNE_ENGRAVER_PROGRESS] = 1
	var saves := RunSaveService.new()
	var row: Array[SquadData] = [SquadData.from_owned_card(engraver)]
	var checkpoint := saves.create_checkpoint(collection.capture_state(), {&"player_front": row}, 1013, &"", 1, rewards, journal, 0)
	var path := "/private/tmp/project-card-three-balance-progress.json"
	check(saves.save_checkpoint(path, checkpoint) == OK, "进度可写入真实磁盘存档")
	var loaded := saves.load_checkpoint(path)
	var restored := OwnedCardCollection.new()
	check(saves.restore_checkpoint(loaded.checkpoint, restored, RunRewardState.new(), RunSettlementJournal.new(), {&"rune_engraver": engraver.card_data}).success, "进度可跨磁盘恢复")
	check(restored.get_by_instance_id(engraver.instance_id).get_effect_text_for_row(&"").contains("还剩1次"), "读档保留括号中的剩余次数")
func test_sticker_pool() -> void:
	var shop := OrdinaryShopService.new()
	shop.initialize(1013)
	var definitions: Array[Dictionary] = []
	for d: Dictionary in EmblemLibraryData.get_definitions():
		if d.get("target") == "rune": definitions.append(d)
	var candidates := shop._eligible_stickers(definitions, [], [])
	check(candidates.size() == 7, "奖励池含五普通、万能及混沌")
	check(int(shop.config.sticker_rarity_weights.II) == 13 and int(shop.config.sticker_rarity_weights.III) == 2, "直接复用纹章包II/III权重13比2")
	var held: Array[Dictionary] = [{"emblem_id": &"万能贴纸"}]
	check(shop._eligible_stickers(definitions, held, []).size() == 6, "已持有万能时排除它但保留混沌")
	var a := owned("rune_engraver")
	var b := owned("rune_engraver")
	a.progress_by_source[OwnedCard.RUNE_ENGRAVER_PROGRESS] = 1
	b.progress_by_source[OwnedCard.RUNE_ENGRAVER_PROGRESS] = 1
	battle([a, b], [owned("ember_squire")])
	controller._card_reward_picker.load_config()
	controller._card_reward_picker.config.sticker_rarity_weights = {"I": 0, "II": 0, "III": 1}
	complete_victory()
	var simultaneous := controller.run_reward_ledger.get_entries()
	check(simultaneous.size() == 2 and simultaneous.filter(func(e: Dictionary) -> bool: return e.parameters.emblem_id == &"万能贴纸").size() <= 1, "同场两名刻匠同时奖励也最多一张万能")
	prepare_engraver_battle()
	controller._card_reward_picker.load_config()
	controller._card_reward_picker.config.sticker_rarity_weights = {"I": 0, "II": 0, "III": 1}
	controller._held_reward_stickers.assign(held)
	complete_victory()
	var earned := controller.run_reward_ledger.get_entries()
	check(earned.size() == 1 and earned[0].parameters.emblem_id == &"混沌贴纸", "实际奖励遵守持有唯一，而非只校验候选池")

func test_npc_reward() -> void:
	var npc := owned("rune_engraver")
	npc.progress_by_source[OwnedCard.RUNE_ENGRAVER_PROGRESS] = 1
	var c := battle([owned("ember_squire")], [npc])
	c.player_states[0].current_health = 0
	c._finalize_batch()
	c._check_battle_result()
	var actual := c.enemy_states[0].squad_data.get_effect_source_instance()
	check(c.current_result == BattleController.Result.PLAYER_DEFEAT and int(actual.progress_by_source[OwnedCard.RUNE_ENGRAVER_PROGRESS]) == 0, "NPC胜利完成自身跨战计数")
	check(actual.rune_stickers.filter(func(item: Dictionary) -> bool: return not item.is_empty()).size() == 1 and c.run_reward_ledger.get_entries().is_empty(), "NPC元素奖励贴入自身一方符文槽，不转给玩家")

func test_main_rewards() -> void:
	var main = MAIN.instantiate()
	main.run_save_path = "/private/tmp/project-card-three-balance-main.json"
	root.add_child(main)
	await process_frame
	main._battle_snapshot = snapshot
	main.run_reward_state.pending_emblem_instances.assign(rewards.pending_emblem_instances.duplicate(true))
	for entry: Dictionary in main.run_reward_state.pending_emblem_instances: entry.battle_instance_id = snapshot.battle_instance_id
	main._add_settled_emblem_rewards_to_library()
	var items: Array = main.emblem_library.get_inventory_state()
	check(items.size() == 2 and items.all(func(item: Dictionary) -> bool: return item.element_sticker), "真实主场景把奖励作为元素贴纸入包")
	var full: Array[Dictionary] = []
	for i: int in 28: full.append({"instance_id": "full_%d" % i, "emblem_id": "面包", "temporary": false})
	check(main.emblem_library.restore_inventory_state(full), "建立真实满工具箱")
	main.run_reward_state.pending_emblem_instances.assign(rewards.pending_emblem_instances.duplicate(true))
	for entry: Dictionary in main.run_reward_state.pending_emblem_instances: entry.battle_instance_id = snapshot.battle_instance_id
	main._add_settled_emblem_rewards_to_library()
	var dropped: Array = main.emblem_library.get_inventory_state().filter(func(item: Dictionary) -> bool: return EmblemStickerInventory.is_dropped(item))
	check(dropped.size() == 2 and dropped[0].element_sticker and main.run_reward_state.pending_ground_items.is_empty(), "满包元素奖励进入同一工具箱临时区域，保留类型")
	var retained: Array[Dictionary] = []
	retained.assign(dropped)
	main.emblem_library.restore_inventory_state(retained)
	var first_id := StringName(String(dropped[0].instance_id))
	check(main.emblem_library.move_sticker(first_id, Vector2i(0, 0)) and not EmblemStickerInventory.is_dropped(main.emblem_library.get_inventory_item(first_id)), "临时元素贴纸回包保持2×2类别与原实例")
	main.front_row.clear_squads()
	var deploy: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/rune_engraver.tres"))
	main.front_row.add_squad(SquadData.from_owned_card(deploy), 0)
	main._open_card_inspection(deploy.card_data, deploy)
	var second_id := StringName(String(dropped[1].instance_id))
	var drag_data := {}
	for entry: EmblemLibraryEntry in main.emblem_library._entries:
		if StringName(String(entry.definition.returned_state.instance_id)) == second_id:
			drag_data = entry._build_drag_data(Vector2.ZERO, false)
	var rune_point: Vector2 = main._inspection_card_view.rune_area_position + main._inspection_card_view.rune_slot_size * 0.5
	check(main._drop_emblem_on_inspection_card(main._inspection_card_view, rune_point, drag_data) and deploy.rune_stickers.any(func(item: Dictionary) -> bool: return not item.is_empty()), "临时元素奖励通过真实检视贴入符文槽，并从临时区域移除")
	(drag_data.drag_visual as Control).free()
	main._close_card_inspection(true)
	main.queue_free()
	await process_frame
func _run() -> void:
	test_commander()
	test_judge()
	test_engraver()
	test_sticker_pool()
	test_npc_reward()
	await test_main_rewards()
	if controller != null: controller.clear_battle(); controller.free()
	print("三卡平衡：%d项，%d失败" % [assertions, failures])
	quit(failures)
