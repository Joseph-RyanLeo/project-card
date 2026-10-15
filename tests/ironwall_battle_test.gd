extends SceneTree

## 正式资源、真实战斗控制器和收藏存档的专项验收，不使用替身。
var failures := 0
var assertions := 0
var sequence := 0
var current: BattleController
var catalog: Array[CardData] = []

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func owned(id: String) -> OwnedCard:
	sequence += 1
	var result := OwnedCard.new()
	result.initialize(load("res://resources/cards/%s.tres" % id), StringName("iron:%d" % sequence), sequence)
	return result
func squad(ids: Array[String], item: String = "") -> SquadData:
	var result := SquadData.new()
	for id: String in ids:
		var card := owned(id)
		if result.horizontal_cards.has(card.get_battlefield_card()): card._battlefield_card = card.card_data.duplicate()
		result.horizontal_cards.append(card.get_battlefield_card())
		result.layer_cards.append(card.get_battlefield_card())
		result.bind_owned_card(card.get_battlefield_card(), card)
	if not item.is_empty(): check(result.equip_item(owned(item)), "合法装备：" + item)
	return result
func form(squads: Array[SquadData], side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in squads.size(): result.append({"squad_data": squads[index], "row_key": &"player_front" if side == 0 else &"enemy_front", "formation_index": index})
	return result
func battle(player: Array[SquadData], spells: Array[OwnedCard] = [], resources: Array[OwnedCard] = [], timed: bool = false) -> BattleController:
	if current != null:
		current.clear_battle()
		current.free()
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = timed
	current.start_battle(form(player, 0), form([squad(["ironhand_arno"])], 1), 1013, false, StringName("iron:%d" % sequence), spells, [], resources, [], catalog)
	while current._opening_spell_active: current.advance_time(BattleController.OPENING_SPELL_PRESENTATION_SECONDS)
	for state: BattleSquadState in current.get_all_states(): state.runtime_base_cooldown_override = 99; state.reset_action_cooldown()
	return current
func echo(state: BattleSquadState) -> void:
	current.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state, "action": {}})
	current.effect_runtime.process_due(current.elapsed_seconds)
func hit(source: BattleSquadState, target: BattleSquadState, amount: float, type: CardData.ActionType = CardData.ActionType.MAGIC, primary: bool = true) -> BattleEffectEvent:
	var event := current.twisted_vein.make_event(source, target, amount, type, true, "专项命中")
	event.is_base_action = primary
	event.is_attack_action_damage = primary
	current._apply_effect_event(event)
	return event
func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/ironwall_manifest.json"))
	check(manifest.cards.size() == 38, "38张铁壁资源")
	var art_count := 0
	for entry: Dictionary in manifest.cards:
		var card := load("res://" + entry.resource) as CardData
		check(card != null and String(card.id) == entry.id and card.pack_id == &"ironwall_inscription", "身份：" + entry.name)
		check(card != null and card.is_available and card.deferred_effect_hooks.is_empty(), "可用：" + entry.name)
		if card != null: catalog.append(card)
		if entry.art != null:
			art_count += 1
			check(card.art_texture != null, "卡图：" + entry.name)
	check(art_count == 34, "34张原图")
	check((load("res://resources/cards/field_beer_machine.tres") as CardData).rarity == CardData.Rarity.I, "啤酒机I级")
	check(IronwallRuntime.BEER_CHARGE_SECONDS == 0.5, "啤酒机充能0.5秒")
	var directory := ResourceLoader.list_directory("res://resources/cards")
	for filename: String in directory:
		if filename.get_extension() == "tres":
			var card := load("res://resources/cards/" + filename) as CardData
			if card != null and card.pack_id in [&"ash_ledger", &"silvermoon_chapter"]: catalog.append(card)
	test_acquisition()
	test_stacking_and_shop()
	test_echo_and_periods()
	test_armor_and_zeal()
	test_protection()
	test_repairs()
	test_spells_and_growth()
	test_equipment_actions()
	test_mining_and_scrap()
	test_rush_and_death()
	test_transactions_and_timing()
	test_adjacency_and_targeting()
	test_balance_damage_and_death()
	if current != null: current.clear_battle(); current.free()
	print("铁壁铭刻：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func test_acquisition() -> void:
	var collection := OwnedCardCollection.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1013
	var arno := collection.create_card(load("res://resources/cards/augustus_ironwall.tres"), rng)
	check(collection.size() == 3, "奥古斯都取得两法术")
	for card: OwnedCard in collection.get_cards():
		if card != arno: check(card.companion_source_id == arno.instance_id and card.card_data.spell_durability_unlimited, "法术关联与无限耐久")
	var saved := collection.capture_state()
	collection.remove_by_instance_id(arno.instance_id)
	check(collection.size() == 0, "主卡永久移除删除配套法术")
	check(collection.restore_state(saved) and collection.size() == 3, "快照恢复专属关联")
	collection.remove_by_instance_id(arno.instance_id)
	collection.create_card(load("res://resources/cards/gunsmith_master.tres"), rng)
	check(collection.size() == 2, "枪械大师取得武器")
	var weapon := collection.get_cards()[1].card_data
	check(weapon.card_type == CardData.CardType.EQUIPMENT and weapon.equipment_type == CardData.EquipmentType.RANGED_WEAPON and weapon.rarity <= 1 and not weapon.is_derived and weapon.get_effective_faction() != CardFaction.Id.LABYRINTH, "枪械大师全局I-II合法池")

func test_stacking_and_shop() -> void:
	var s := squad(["formation_infantry", "formation_infantry"])
	check(s.get_effective_action_base_value() == 3 and s.get_effective_max_health() == 4, "列阵步兵被遮挡仍叠加")
	var badge := squad(["scout", "formation_infantry"], "officer_badge")
	check(badge.get_effective_action_base_value() == 5 and badge.get_effective_max_health() == 6, "徽章小队+2/+3并叠步兵")
	check(not squad(["scout"]).can_equip_item(owned("array_heavy_crossbow")), "重弩单兵禁装")
	check(squad(["scout", "formation_infantry"]).can_equip_item(owned("array_heavy_crossbow")), "重弩小队合法")
	for id: String in ["walking_fighter", "swordshield_master"]: check(squad([id]).contains_stacking_forbidden_card(), "禁止堆叠：" + id)
	var shop := OrdinaryShopService.new()
	shop.initialize(1013)
	var pool: Array[CardData] = shop._eligible_cards(catalog, [])
	for card: CardData in catalog:
		if card.pack_id != &"ironwall_inscription": continue
		check((card in pool) == not card.is_derived, "卡池衍生隔离：" + card.display_name)

func test_echo_and_periods() -> void:
	var c := battle([squad(["field_beer_machine"]), squad(["formation_infantry"]), squad(["scout"])])
	var dwarf := c.player_states[1]
	var before := dwarf.remaining_cooldown
	echo(c.player_states[0])
	check(is_equal_approx(dwarf.remaining_cooldown, before - 0.5), "啤酒机相邻矮人减0.5")
	check(c.player_states[2].remaining_cooldown == before, "非邻居不充能")
	c = battle([squad(["inscription_scholar"], "beer_mug"), squad(["formation_infantry"]), squad(["scout"], "ironheart_pendant")])
	echo(c.player_states[0])
	check(c.player_states[0].current_armor == 1 and c.player_states[2].current_armor == 5, "铭文学者加甲包含自身")
	check(c.player_states[1].current_armor == 2, "无装备目标跳过")
	c.elapsed_seconds = 3
	c.ironwall.process_due()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 2, "啤酒杯第3秒强化")
	c.elapsed_seconds = 9
	c.ironwall.process_due()
	check(c.player_states[2].get_protection_count() == 0, "吊坠第9秒无保护")
	c.elapsed_seconds = 10
	c.ironwall.process_due()
	check(c.player_states[2].get_protection_count() == 1, "吊坠第10秒保护")
	c = battle([squad(["formation_infantry", "scout"]), squad(["logistics_robot"]), squad(["formation_infantry", "scout"])])
	c.elapsed_seconds = 5
	c.ironwall.process_due()
	var a := c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	var b := c.player_states[2].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT)
	check(a >= 1 and a <= 4 and a == b, "后勤一次骰给两邻小队")

func test_armor_and_zeal() -> void:
	var c := battle([squad(["walking_fighter"]), squad(["thunderstorm_infantry"])])
	var walker := c.player_states[0]
	var before := walker.get_display_action_value()
	walker.apply_armor_exact(0.1)
	walker.apply_armor_exact(0.2)
	check(walker.get_display_action_value() == before + 2, "小数真实加甲各成长一次")
	var mode := walker.get_effective_action_type()
	echo(walker)
	check(walker.get_effective_action_type() != mode, "步行战斗机回响切换")
	var thunder := c.player_states[1]
	c.ironwall.add(thunder, BattleModifier.Stat.ZEAL, 23, &"test_aura")
	thunder.cooldown_progress = 0.25
	c.ironwall.sync_auras()
	check(thunder.get_zeal_layers() == 3 and thunder.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 20, "23热诚连续消费两次")
	check(thunder.cooldown_progress == 0.25, "转换保留冷却进度")
	for m: BattleModifier in thunder.modifiers.modifiers:
		if m.effect_id == &"test_aura": m.value = 18
	c.ironwall.sync_auras()
	check(thunder.get_zeal_layers() == -2, "源热诚减少仍保留负消费")
	thunder.grant_protection(&"test", 1)
	hit(c.enemy_states[0], thunder, 1)
	check(thunder.get_zeal_layers() == -2, "保护完全挡伤不加热诚")
	hit(c.enemy_states[0], thunder, 0.1, CardData.ActionType.MAGIC, false)
	check(thunder.get_zeal_layers() == -1, "独立或元素真实伤害也加热诚")

func test_protection() -> void:
	var c := battle([squad(["swordshield_master"]), squad(["scout"], "legion_aegis")])
	var sword := c.player_states[0]
	check(sword.get_protection_count() == 1 and sword.get_effective_action_type() == CardData.ActionType.DEFENSE, "剑盾初始防御与保护")
	check(c.player_states[1].get_protection_count() == 2, "圣盾只保护装备者")
	var before := c.enemy_states[0].current_health + c.enemy_states[0].current_armor
	hit(c.enemy_states[0], sword, 2)
	check(sword.get_effective_action_type() == CardData.ActionType.MELEE and sword.remaining_cooldown > 98, "保护耗尽立即近战并重置普通冷却")
	check(c.enemy_states[0].current_health + c.enemy_states[0].current_armor < before, "圣盾失去全保护独立报复")
	sword.grant_protection(&"again", 1)
	check(sword.get_effective_action_type() == CardData.ActionType.DEFENSE, "再次保护返回防御")

func test_repairs() -> void:
	var c := battle([squad(["ironhand_arno"]), squad(["sentry_machine"]), squad(["scout"])])
	var target := c.player_states[1]
	var center := target.logical_center
	var neighbor_center := c.player_states[2].logical_center
	target.current_health = 0
	c._finalize_batch()
	check(not target.alive and target.is_repairing and c.ironwall.repair_uses[0] == 1, "阿诺死亡后修复且共用额度")
	check(target.logical_center == center and c.player_states[2].logical_center == neighbor_center, "修复保留占位不移动")
	c.elapsed_seconds = 1
	c.ironwall.process_due()
	check(target.alive and not target.is_repairing and target.current_health == 1 and target.current_armor == 4, "延迟基础生命返回开战血甲")
	check(target.cooldown_progress == 0 and target.life_generation == 1, "修复重计冷却和生命代次")
	var binding_count := c.effect_runtime.bindings.size()
	for _i: int in 4:
		target.current_health = 0
		c._finalize_batch()
		c.elapsed_seconds += 1
		c.ironwall.process_due()
	check(c.ironwall.repair_uses[0] == 5 and c.effect_runtime.bindings.size() == binding_count, "5次上限与效果绑定不重复")
	target.current_health = 0
	c._finalize_batch()
	check(not target.is_repairing, "第6次死亡不修复")
	c = battle([squad(["ironhand_arno"]), squad(["booby_mine"])])
	target = c.player_states[1]
	target.current_health = 0
	c._finalize_batch()
	check(target.is_repairing, "衍生诡雷可修复")
	c.player_states[0].current_health = 0
	c._finalize_batch()
	check(not target.is_repairing and c.ironwall.repairs.is_empty(), "阿诺死亡中断修复")

func test_spells_and_growth() -> void:
	var c := battle([squad(["augustus_ironwall"]), squad(["scout"])], [owned("skirmish_formation")])
	for s: BattleSquadState in c.player_states: check(s.get_zeal_layers() == 4 and s.get_protection_count() == 2, "散兵热诚与在场监听")
	c = battle([squad(["augustus_ironwall", "formation_infantry"])], [owned("rally_formation")])
	check(c.player_states[0].current_armor == 6 and c.player_states[0].get_protection_count() == 2, "集结每小队一次加甲与保护")
	c = battle([squad(["scout", "augustus_ironwall"])], [owned("rally_formation")])
	check(c.player_states[0].get_protection_count() == 0, "奥古斯都被覆盖不能监听")
	c = battle([squad(["scout"]), squad(["formation_infantry"], "anvilbone_ledger")], [owned("ancestral_blessing")])
	c.player_states[0].current_health = 0
	c._finalize_batch()
	c.ironwall.finish(BattleController.Result.PLAYER_VICTORY)
	var growth := c.permanent_growth_ledger.get_entries()
	check(growth.size() == 4, "铁册存活与先祖阵亡各两属性成长")
	for entry: Dictionary in growth: check(entry.owner_kind != BattleEffectDefinition.OwnerKind.EQUIPMENT_INSTANCE, "成长归属性来源卡")

func test_equipment_actions() -> void:
	var c := battle([squad(["gunsmith_master"], "sentry_pistol")])
	var state := c.player_states[0]
	for index: int in 4:
		var action := c._build_action(state, c.get_all_states(), CardData.ActionType.RANGED)
		check(is_zero_approx(float(action.action_value_delta)), "枪械大师不再提供行动1d4加值")
		c._consume_reinforcement_for_action(state, action)
	c = battle([squad(["scout"], "standard_quiver")])
	state = c.player_states[0]
	for index: int in 4:
		var action := c._build_action(state, c.get_all_states(), CardData.ActionType.RANGED)
		check(state.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == (2 if index < 3 else 0), "箭袋仅前三次快照前强化")
		c._consume_reinforcement_for_action(state, action)
	c = battle([squad(["scout"], "repeater_gun")])
	state = c.player_states[0]
	c.execute_immediate_action(state, CardData.ActionType.RANGED)
	check(c.ironwall.repeats.size() == 2, "连珠铳排定两次")
	c.ironwall.process_due()
	check(c.ironwall.repeats.is_empty(), "追加不递归本装备")
	c = battle([squad(["inscription_scholar"], "blackiron_staff")])
	state = c.player_states[0]
	c.execute_immediate_action(state, CardData.ActionType.MAGIC)
	check(c.ironwall.repeats.size() == 1, "黑铁追加一次")
	c.ironwall.process_due()
	check(c.ironwall.repeats.is_empty(), "法杖追加不递归")
	c = battle([squad(["scout", "formation_infantry"], "array_heavy_crossbow")])
	var event := hit(c.player_states[0], c.enemy_states[0], 1, CardData.ActionType.RANGED, false)
	check(event.pierces_armor and event.attack_type_multiplier == 1.3 and event.armor_amount == 0, "重弩独立远程穿甲仍读甲倍率")
	c = battle([squad(["scout"], "tower_shield")])
	event = hit(c.enemy_states[0], c.player_states[0], 2)
	check(is_equal_approx(event.effective_amount, 1.2), "塔盾非疲劳伤害减半")
	c = battle([squad(["logistics_robot"], "runic_anvil")])
	state = c.player_states[0]
	state.current_health = 0.5
	var heal := c.twisted_vein.make_event(state, state, 0.1, CardData.ActionType.HEAL, false, "铁砧治疗")
	heal.effect_kind = BattleEffectEvent.EffectKind.HEALING
	heal.is_base_action = true
	c._apply_effect_event(heal)
	check(state.current_armor == 10 and state.is_sleeping(c.elapsed_seconds), "符文铁砧治疗主目标也眩晕加甲")

func test_mining_and_scrap() -> void:
	var c := battle([squad(["scout"], "sapper_shovel")], [], [owned("gear_scrap")])
	var action := c._build_action(c.player_states[0], c.get_all_states(), CardData.ActionType.RANGED)
	check(action.is_mining and int(c.mining_actions_remaining_by_runtime_id[c.player_states[0].runtime_id]) == 0, "工兵铲仅一次发射扣开采")
	c._apply_effect_event(action.base_event)
	check(c.player_states.size() == 2 and c.player_states[1].get_effect_source().id == &"booby_mine", "成功开采后召唤诡雷")
	check(c.player_states[0].squad_data.get_equipped_item().card_data.id == &"sapper_shovel", "废料不覆盖已有装备")
	c = battle([squad(["scout"])], [], [owned("gear_scrap")])
	var mining := c.make_mining_event(c.player_states[0], c.player_resource_states[0])
	c._apply_effect_event(mining)
	check(c.player_states[0].squad_data.get_equipped_item() != null and c.ironwall.temporary_items.size() == 1, "废料临时装备真实击碎者")
	c.ironwall.restore_temporary()
	check(c.player_states[0].squad_data.get_equipped_item() == null, "战后临时装备移除")
	c = battle([squad(["ore_appraiser"])], [], [owned("gear_scrap")])
	action = c._build_action(c.player_states[0], c.get_all_states(), CardData.ActionType.MAGIC)
	check(action.is_mining, "鉴定师无限开采")
	c._apply_effect_event(action.base_event)
	check(c.run_reward_ledger.get_entries().any(func(e: Dictionary) -> bool: return e.effect_id == &"ore_appraiser"), "成功开采额外1金币账本")

func test_rush_and_death() -> void:
	var c := battle([squad(["formation_commander"]), squad(["formation_infantry", "scout"])])
	check(c.player_states[1].get_protection_count() == 1, "军阵突击只相邻小队")
	c = battle([squad(["mobilization_machine"]), squad(["scout"])])
	check(c.ironwall.temporary_emblems.size() == 1, "动员每邻居临时纹章")
	var recipient := c.ironwall.temporary_emblems[0].owned as OwnedCard
	c.ironwall.restore_temporary()
	check(recipient.emblem_slots.all(func(s: Dictionary) -> bool: return s.is_empty()), "临时纹章战后恢复")
	c = battle([squad(["recycling_robot"]), squad(["sentry_machine"])])
	var recycler := c.player_states[0]
	c.player_states[1].current_health = 0
	c._finalize_batch()
	check(recycler.get_display_action_value() == 2 and recycler.current_armor == 4, "回收不再增加自身数值或护甲")
	check(c.player_resource_states.size() + c.enemy_resource_states.size() == 0, "警戒不再生成废料")
	c = battle([squad(["booby_mine"])])
	var target := c.player_states[0]
	var before := c.enemy_states[0].current_health + c.enemy_states[0].current_armor
	hit(c.enemy_states[0], target, 100)
	c._finalize_batch()
	check(c.enemy_states[0].current_health + c.enemy_states[0].current_armor < before, "诡雷对击杀来源无类型遗愿")

func test_transactions_and_timing() -> void:
	# 在真实战前快照上执行军械突击，随后由正式结算器恢复快照并提交。
	for seed_value: int in range(1, 21):
		var collection := OwnedCardCollection.new()
		var apprentice := collection.create_card(load("res://resources/cards/armament_apprentice.tres"))
		var equipment := collection.create_card(load("res://resources/cards/standard_quiver.tres"))
		var s := SquadData.from_owned_card(apprentice)
		s.equip_item(equipment)
		if current != null: current.clear_battle(); current.free()
		current = BattleController.new()
		root.add_child(current)
		current.use_projectile_timing = false
		var battle_id := StringName("iron_transaction:%d" % seed_value)
		var snapshot := BattlePreparationSnapshot.new()
		var row: Array[SquadData] = [s]
		check(snapshot.initialize(battle_id, seed_value, collection, {&"player_front": row}), "真实事务快照")
		current.start_battle(form([s], 0), form([squad(["ironhand_arno"])], 1), seed_value, false, battle_id)
		var destroyed := current.player_states[0].squad_data.get_equipped_item() == null
		var service := BattleSettlementService.new()
		var reward := RunRewardState.new()
		var journal := RunSettlementJournal.new()
		var result := service.settle(snapshot, current.permanent_growth_ledger.get_entries(), [], collection, reward, journal, current.owned_card_change_ledger.get_entries())
		check(result.success, "军械装备成长或摧毁正式结算")
		var remaining := collection.get_by_instance_id(equipment.instance_id)
		check((remaining == null) == destroyed, "摧毁从拥有集合移除")
		if not destroyed: check(remaining.get_permanent_growth(&"base_value") == 1, "无数值装备从0永久成长1")
		var again := service.settle(snapshot, current.permanent_growth_ledger.get_entries(), [], collection, reward, journal, current.owned_card_change_ledger.get_entries())
		check(again.success and again.status == &"already_committed", "重复结算不重复成长")
	var c := battle([squad(["scout"], "repeater_gun")], [], [], true)
	var state := c.player_states[0]
	var launched: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(e: BattleEffectEvent) -> void: launched.append(e))
	check(c.execute_immediate_action(state, CardData.ActionType.RANGED), "真实弹道连珠主行动")
	c.ironwall.process_due()
	check(launched.size() == 3 and launched[1].is_equipment_repeat and launched[2].is_equipment_repeat, "两次真实追加弹道")
	check(is_equal_approx(launched[1].exact_amount, launched[0].exact_amount * 0.4), "追加40%效能")
	check(c.ironwall.repeats.is_empty(), "真实弹道不递归")
	c = battle([squad(["scout"])])
	var target := c.enemy_states[0]
	c.ironwall.vengeance[target] = [{"left": 3, "groups": {}}]
	target.current_health = 999
	target.current_armor = 0
	var actor := c.player_states[0]
	var event := hit(actor, target, 1)
	check(is_equal_approx(event.effective_amount, 2.4), "铁册行动伤害翻倍")
	var followup := c.twisted_vein.make_event(actor, target, 1, CardData.ActionType.MAGIC, true, "同一行动元素")
	followup.group_id = event.group_id
	followup.is_attack_action_damage = true
	c._apply_effect_event(followup)
	check(c.ironwall.vengeance[target][0].left == 2 and is_equal_approx(followup.effective_amount, 2.4), "同一完整行动元素共用额度")
	var independent := hit(actor, target, 1, CardData.ActionType.MAGIC, false)
	check(is_equal_approx(independent.effective_amount, 1.2) and c.ironwall.vengeance[target][0].left == 2, "独立伤害不享受不消费")
	c = battle([squad(["scout"], "tower_shield")], [], [owned("gear_scrap")])
	for _i: int in 4:
		c.mining_actions_remaining_by_runtime_id[c.player_states[0].runtime_id] = 1
		var action := c._build_action(c.player_states[0], c.get_all_states(), CardData.ActionType.RANGED)
		check(not action.is_empty() and action.is_mining, "塔盾开采不投失败骰")
	var saw_failure := false
	var saw_success := false
	c = battle([squad(["scout"], "tower_shield")])
	for _i: int in 20:
		var action := c._build_action(c.player_states[0], c.get_all_states(), CardData.ActionType.RANGED)
		saw_failure = saw_failure or action.is_empty()
		saw_success = saw_success or not action.is_empty()
	check(saw_failure and saw_success, "塔盾普通行动实际1d6成功失败")

func test_adjacency_and_targeting() -> void:
	var c := battle([squad(["phalanx_officer", "formation_infantry"]), squad(["formation_infantry", "scout"]), squad(["phalanx_officer", "scout"])])
	for _i: int in 4:
		var action := c._build_action(c.player_states[1], c.get_all_states(), CardData.ActionType.MELEE)
		check(action.action_value_delta >= 2 and action.action_value_delta <= 8 and action.action_value_source.sources.size() == 2, "两方阵各投1d4且保留来源")
	var passive: float = c.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)
	check(passive == 0, "方阵骰不留本场常驻加值")
	c = battle([squad(["scout"]), squad(["thunderstorm_infantry"])])
	var actor := c.player_states[1]
	var enemy_low := squad(["logistics_robot"])
	var enemy_high := squad(["walking_fighter"])
	c.enemy_states.assign(c._create_states(form([enemy_high, enemy_low], 1), 1))
	c.recalculate_logical_layout()
	c.enemy_states[0].grant_runtime_keyword(&"dazzling", -109)
	var action := c._build_action(actor, c.get_all_states(), CardData.ActionType.RANGED)
	check(action.target == c.enemy_states[0], "侦查员不再覆盖普通耀眼选敌规则")
	echo(c.player_states[0])
	check(actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 1, "侦查员回响强化相邻远程友军")
	c = battle([squad(["ironhand_arno"]), squad(["sentry_machine"]), squad(["formation_infantry"])])
	c.player_states[1].current_health = 0
	c._finalize_batch()
	check(not c._get_adjacent_allies(c.player_states[0]).has(c.player_states[2]), "修复保留位置阻隔跨卡相邻")
	c = battle([squad(["bomb_apprentice"])])
	c.player_states[0].current_health = 0
	c._finalize_batch()
	check(c.player_states.size() == 2 and c.player_states[1].get_effect_source().id == &"booby_mine", "爆弹遗愿正式召唤")
	c = battle([squad(["scout"], "sentry_pistol")])
	var enemy := c.enemy_states[0]
	var first_before := enemy.current_health + enemy.current_armor
	echo(c.player_states[0]); echo(c.player_states[0])
	var after := enemy.current_health + enemy.current_armor
	check(after < first_before, "短铳前两回响独立伤害")
	echo(c.player_states[0])
	check(enemy.current_health + enemy.current_armor == after, "短铳第三回响无弹")

func test_balance_damage_and_death() -> void:
	var c := battle([squad(["scout"]), squad(["sentry_machine"]), squad(["formation_infantry"])])
	var guard := c.player_states[1]
	c.player_states[2].row_key = &"player_back"
	check(guard.is_sleeping(0), "警戒初始休眠")
	guard.grant_protection(&"test", 1)
	hit(c.enemy_states[0], guard, 0.1)
	check(guard.is_sleeping(0) and c.player_states[0].get_protection_count() == 0, "警戒保护挡伤不唤醒")
	guard.apply_damage_exact(0.1)
	check(not guard.is_sleeping(0) and c.player_states[0].get_protection_count() == 1 and guard.get_protection_count() == 1, "实际护甲伤害唤醒并保护同排含自身")
	check(c.player_states[2].get_protection_count() == 0, "不同排不发保护")
	guard.protection_charges_by_source.clear()
	guard.apply_damage_exact(0.1)
	check(c.player_states[0].get_protection_count() == 1, "醒后再受伤不重复发保护")
	c = battle([squad(["sentry_machine"]), squad(["scout"])])
	guard = c.player_states[0]
	check(guard.is_sleeping(29.9) and not guard.is_sleeping(30), "第30秒自然唤醒")
	c.elapsed_seconds = 30
	guard.apply_damage_exact(0.1)
	check(c.player_states[1].get_protection_count() == 0, "自然醒后受伤不发保护")
	c = battle([squad(["thunderstorm_infantry"])])
	var thunder := c.player_states[0]
	c.ironwall.add(thunder, BattleModifier.Stat.ZEAL, 9, &"test")
	thunder.apply_damage_exact(0.1)
	check(thunder.get_zeal_layers() == 0 and thunder.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 10, "无事件的持续直伤也触发10热诚转换")
	thunder.apply_damage_exact(0)
	check(thunder.get_zeal_layers() == 0, "零伤害不触发")
	c = battle([squad(["formation_infantry", "scout"]), squad(["formation_commander"]), squad(["formation_infantry", "scout"])])
	c.player_states[1].current_health = 0
	c._finalize_batch()
	check(c.player_states[0].get_protection_count() == 2 and c.player_states[2].get_protection_count() == 2, "军阵遗愿沿用死亡前左右邻居，各再发保护1")
	c = battle([squad(["scout"]), squad(["recycling_robot"]), squad(["formation_infantry"]), squad(["sentry_machine"])])
	c.player_states[3].current_health = 0
	c._finalize_batch()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 2 and c.player_states[2].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 2, "友方造物死亡强化回收左右两侧")
	var enemy := c.enemy_states[0]
	enemy.squad_data = squad(["sentry_machine"])
	enemy.current_health = 0
	c._finalize_batch()
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 4, "敌方造物死亡也触发回收")

	c = battle([squad(["recycling_robot"]), squad(["sentry_machine"]), squad(["booby_mine"]), squad(["scout"])])
	c.player_states[1].current_health = 0
	c.player_states[2].current_health = 0
	c._finalize_batch()
	check(c._get_adjacent_allies(c.player_states[0]).has(c.player_states[3]) and c.player_states[3].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 4, "同批两造物先腾位，再对回收当前邻居各给强化2")
