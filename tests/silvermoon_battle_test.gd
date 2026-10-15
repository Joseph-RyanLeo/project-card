extends SceneTree

## 使用正式资源和完整战斗执行器，验证银月规则与旧系统边界。
var failures := 0
var assertions := 0
var sequence := 0
var current: BattleController
var catalog: Array[CardData] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func owned(id: String, reveal: bool = false) -> OwnedCard:
	sequence += 1
	var card := OwnedCard.new()
	card.initialize(load("res://resources/cards/%s.tres" % id), StringName("silver:%d" % sequence), sequence)
	card.rune_revealed.fill(reveal)
	return card

func form(cards: Array[OwnedCard], side: int, back: Array[int] = []) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in cards.size():
		var row := ("player_" if side == 0 else "enemy_") + ("back" if index in back else "front")
		rows.append({"squad_data": SquadData.from_owned_card(cards[index]), "row_key": StringName(row), "formation_index": index})
	return rows

func battle(player: Array[OwnedCard], enemy: Array[OwnedCard], spells: Array[OwnedCard] = [], resources: Array[OwnedCard] = [], back: Array[int] = [], enemy_back: Array[int] = [], timed: bool = false, enemy_spells: Array[OwnedCard] = [], requested_id: StringName = &"") -> BattleController:
	if current != null:
		current.clear_battle()
		current.free()
	current = BattleController.new()
	root.add_child(current)
	current.use_projectile_timing = timed
	current.start_battle(form(player, 0, back), form(enemy, 1, enemy_back), 21010, false, requested_id if not requested_id.is_empty() else StringName("silverbattle:%d" % sequence), spells, enemy_spells, resources, [], catalog, player)
	while current._opening_spell_active: current.advance_time(BattleController.OPENING_SPELL_PRESENTATION_SECONDS)
	return current

func hit(source: BattleSquadState, target: BattleSquadState, amount: float, mode: CardData.ActionType = CardData.ActionType.MAGIC, primary: bool = true) -> BattleEffectEvent:
	var event := current.twisted_vein.make_event(source, target, amount, mode, true, "银月专项真实命中")
	event.is_base_action = primary
	current._apply_effect_event(event)
	return event

func echo(state: BattleSquadState, target: BattleSquadState = null) -> void:
	current.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": state, "action": {"target": target}})
	current.effect_runtime.process_due(current.elapsed_seconds)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/silvermoon_manifest.json"))
	check(manifest.cards.size() == 37, "37张银月正式卡")
	for entry: Dictionary in manifest.cards:
		var card := load("res://" + entry.resource) as CardData
		check(card != null and String(card.id) == entry.id and card.pack_id == &"silvermoon_chapter", "资源身份：" + entry.name)
		check(card != null and card.is_available and card.deferred_effect_hooks.is_empty(), "全部可用且无待实现钩子：" + entry.name)
		if card != null: catalog.append(card)
	catalog.append(load("res://resources/cards/baggage_muleteer.tres"))
	check((load("res://resources/cards/moon_hawk.tres") as CardData).max_health == 4 and (load("res://resources/cards/moon_hawk.tres") as CardData).armor == 0, "月鹰明确更正4/0")
	check((load("res://resources/cards/moonshadow_stoneguard.tres") as CardData).max_health == 1, "石卫生命1")
	check((load("res://resources/cards/moonblade_scimitar.tres") as CardData).equipment_action_delta == 4, "弯刀保留原数值4")
	check((load("res://resources/cards/moonshadow_seed.tres") as CardData).equipment_health_delta == -2, "树种生命-2")
	check((load("res://resources/cards/starfire.tres") as CardData).spell_durability_unlimited, "星火术无限耐久")
	for id: String in ["moondew", "victory_prophecy", "failure_prophecy"]: check((load("res://resources/cards/%s.tres" % id) as CardData).is_derived, "衍生池隔离：" + id)
	test_rush()
	test_rows_and_movement()
	test_hits()
	test_spells()
	test_links_and_seed()
	test_resources()
	test_shop()
	test_equipment_and_timing()
	test_settlement_and_save()
	if current != null:
		current.clear_battle()
		current.free()
	print("银月之章：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func test_rush() -> void:
	var apprentice := owned("silvermoon_apprentice", true)
	apprentice.resolved_runes.assign([CardData.ElementType.DARK, CardData.ElementType.DARK, CardData.ElementType.LIGHT])
	var c := battle([apprentice], [owned("moon_hawk")])
	check(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 4, "学徒两暗强化4，应用人工强化2")
	check(c.permanent_growth_ledger.get_amount_for_owned_card(apprentice.instance_id, &"max_health") == 1, "学徒一光永久生命1")
	c = battle([owned("stargazer")], [owned("moon_hawk")])
	check(c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 0) == 2, "观星者两张预言进入奖励账本")
	check(c._get_all_prepared_spell_instances().is_empty(), "生成预言不自动准备或释放")
	var il := owned("il_ancient_speaker")
	var light := owned("baggage_muleteer", true)
	light.resolved_runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.DARK])
	var dark := owned("moon_hawk", true)
	dark.resolved_runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.DARK, CardData.ElementType.DARK])
	c = battle([il, light], [dark])
	check(c.permanent_growth_ledger.get_amount_for_owned_card(light.instance_id, &"max_health") == 2, "伊尔2光1暗净光1永久生命2")
	check(c.permanent_growth_ledger.get_amount_for_owned_card(dark.instance_id, &"base_value") == 1, "伊尔1光2暗净暗1永久数值1，包含敌军")
	check(c.permanent_growth_ledger.get_amount_for_owned_card(il.instance_id, &"max_health") == 0, "未揭晓符文不参与伊尔比较")
	check(c.enemy_states[0].runtime_permanent_action_growth == 1, "净暗数值立即进入本场基础层")
	var equal := owned("baggage_muleteer", true)
	equal.resolved_runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.DARK, CardData.ElementType.WOOD])
	c = battle([owned("il_ancient_speaker"), equal, owned("starlight_weaver")], [owned("moon_hawk")])
	check(c.permanent_growth_ledger.get_amount_for_owned_card(equal.instance_id, &"max_health") == 0 and c.permanent_growth_ledger.get_amount_for_owned_card(equal.instance_id, &"base_value") == 0, "光暗相等不提供成长")
	check(c.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_OWNED_CARD_AWARD, 0) == 1, "编者突击获得1张月露入奖励账本")
	check(c.silvermoon.links.is_empty(), "祭祀未启咒时不生成链接")

func test_rows_and_movement() -> void:
	var c := battle([owned("moon_dancer"), owned("twilight_knight"), owned("starmoon_leopard")], [owned("moon_hawk"), owned("moonshadow_stoneguard")], [], [], [1])
	var dancer := c.player_states[0]
	var knight := c.player_states[1]
	var leopard := c.player_states[2]
	check(knight.get_effective_action_type() == CardData.ActionType.MAGIC, "骑士后排法术")
	check(c.enemy_states[0].is_sleeping(0) and c.enemy_states[1].is_sleeping(0), "月鹰30秒与石卫10秒入场休眠")
	check(leopard.get_zeal_layers() == 4, "星月豹前排热诚4")
	var progress := leopard.cooldown_progress
	check(c.silvermoon.swap(knight, leopard), "合法跨排换位")
	check(knight.get_effective_action_type() == CardData.ActionType.MELEE, "骑士换排切近战")
	check(not c.enemy_states[0].masking_forbidden and not c.enemy_states[0].priority_reduction_forbidden, "新版骑士撤除禁止遮蔽及降低优先级的旧光环")
	c.enemy_states[0].moon_shadowed = true
	check(c.choose_base_target(knight, [c.enemy_states[0]], CardData.ActionType.MELEE) == null, "新版骑士仍遵守影蔽目标不可选规则")
	check(leopard.get_zeal_layers() == 0 and leopard.get_display_action_value() == 3, "豹后排切普通值+1")
	check(is_equal_approx(leopard.cooldown_progress, progress), "换排速度变化保留冷却进度")
	check(dancer.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1, "一次换位对舞者计一次")
	c.silvermoon.swap(knight, leopard)
	check(dancer.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1, "同一时刻内部冷却不重复")
	c.elapsed_seconds = 0.1
	c.silvermoon.swap(knight, leopard)
	check(dancer.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 2, "0.1秒后再次监听")
	var tree := owned("moonlight_treant", true)
	tree.resolved_runes.assign([CardData.ElementType.WOOD, CardData.ElementType.LIGHT, CardData.ElementType.WATER])
	c = battle([tree], [owned("moon_hawk", true)])
	var state := c.enemy_states[0]
	state.squad_data.get_effect_source_instance().resolved_runes.assign([CardData.ElementType.WOOD, CardData.ElementType.WOOD, CardData.ElementType.WOOD])
	c.silvermoon.sync_auras()
	check(c.player_states[0].get_effective_action_type() == CardData.ActionType.MELEE, "月华树人改为近战")
	check(c.player_states[0].get_active_runes() == [CardData.ElementType.DARK, CardData.ElementType.LIGHT, CardData.ElementType.WATER], "树人突击仅改最左端符文为暗")
	check(tree.resolved_runes[0] == CardData.ElementType.WOOD, "树人不写回拥有卡原符文")
	check(is_equal_approx(c.player_states[0].remaining_cooldown, c.player_states[0].get_action_interval()), "暗符文转换后立即刷新冷却秒数")
	check(state.get_active_rune_stat_bonus(&"zeal") == 0 and state.get_active_rune_stat_bonus(&"base_armor") == 9, "撤除木符文额外暗收益光环")

func test_hits() -> void:
	var defender := owned("moonshadow_stoneguard")
	defender.set_emblem_slot(0, {"emblem_id": "盔甲", "instance_id": &"silver_test_armor"})
	var c := battle([owned("darkmoon_judge"), owned("star_chant_apprentice")], [defender, owned("moon_hawk")])
	var judge := c.player_states[0]
	var target := c.enemy_states[0]
	echo(judge, target)
	check(target.masked_emblem_sources.is_empty() and target.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1, "审判者回响改为低生命疲劳，不再遮蔽")
	hit(judge, target, 1)
	check(target.masked_emblem_sources.is_empty(), "审判者实际命中不再触发旧纹章遮蔽")
	var neighbor_before := c.enemy_states[1].current_health
	hit(c.player_states[1], target, 0.1)
	check(c.enemy_states[1].current_health < neighbor_before, "星咏实际命中对目标邻居1法伤")
	c = battle([owned("theran_shadowmoon")], [owned("moon_hawk")])
	var action := c._build_action(c.player_states[0], c.get_all_states(), CardData.ActionType.RANGED)
	var event: BattleEffectEvent = action.base_event
	c._apply_effect_event(event)
	check(event.dual_melee_ranged and event.attack_type_multiplier == 1.5, "瑟兰无甲取近战1.5而非双倍率")
	c = battle([owned("darkmoon_archer")], [owned("baggage_muleteer")])
	c.enemy_states[0].current_health = float(c.enemy_states[0].get_max_health()) * 0.4
	event = hit(c.player_states[0], c.enemy_states[0], 2, CardData.ActionType.RANGED)
	check(is_equal_approx(event.exact_amount, 4.6), "弓手类型倍率后再加3")
	c = battle([owned("shadowstep_assassin")], [owned("moon_hawk"), owned("baggage_muleteer")])
	hit(c.player_states[0], c.enemy_states[0], 30)
	c._finalize_batch()
	check(c.player_states[0].protection_charges_by_source.get(&"shadowstep_assassin", 0) == 1, "刺客荣耀真实击杀给予保护")

func test_spells() -> void:
	var star := owned("starfire")
	var c := battle([owned("moon_hawk")], [owned("baggage_muleteer")], [star])
	var enemy := c.enemy_states[0]
	var hp := enemy.current_health
	c.elapsed_seconds = 2.999
	c._resolve_due_prepared_spells()
	c.silvermoon.process_due()
	check(enemy.current_health == hp, "星火首次周期严格3秒")
	c.elapsed_seconds = 3.0
	c._resolve_due_prepared_spells()
	c.silvermoon.process_due()
	check(is_equal_approx(enemy.current_health, hp - 1.2), "星火一法伤实际1.2")
	c.elapsed_seconds = 6.0
	c._resolve_due_prepared_spells()
	c.silvermoon.process_due()
	check(c.silvermoon.spell_counts[star.instance_id] == 2, "星火每次实际释放一份启咒")
	var eclipse_target := owned("moon_hawk", true)
	eclipse_target.resolved_runes.fill(CardData.ElementType.LIGHT)
	c = battle([eclipse_target], [owned("baggage_muleteer")], [owned("solar_eclipse")])
	check(c.player_states[0].get_active_runes().all(func(element: int) -> bool: return element == CardData.ElementType.DARK), "日蚀临时转换全部光")
	check(eclipse_target.resolved_runes.all(func(element: int) -> bool: return element == CardData.ElementType.LIGHT), "日蚀不改收藏原符文")
	var veil := owned("twilight_veil")
	c = battle([owned("moon_hawk")], [owned("baggage_muleteer")], [veil])
	var target := c.player_states[0]
	target.current_armor = 0
	var cooldown := target.remaining_cooldown
	var event := hit(c.enemy_states[0], target, 100)
	check(target.is_banished and event.missed and target.current_health == 4, "面纱伤害写入前放逐并取消致命伤害")
	check(not c.execute_immediate_action(target, CardData.ActionType.MAGIC), "放逐期间立即行动入口也拒绝执行")
	check(c.choose_weighted_target([target]) == null, "放逐单位不能成为治疗、防御加权目标")
	check(c.get_living_states(0).is_empty() and c.get_living_states(0, true).size() == 1, "放逐不可选但仍算存活与占位")
	c._check_battle_result()
	check(c.current_result == BattleController.Result.NONE, "全侧放逐不误判失败")
	c._decrease_living_cooldowns(2.0)
	check(target.remaining_cooldown == cooldown, "放逐冷却暂停")
	c.elapsed_seconds = 3.0
	c._resolve_due_prepared_spells()
	c.silvermoon.process_due()
	check(not target.is_banished, "3秒返回")
	c = battle([owned("baggage_muleteer")], [owned("moon_hawk")], [owned("silvermoon_breath")])
	target = c.player_states[0]
	target.current_health = 1
	c.silvermoon.check_health_spells()
	check(target.current_health == 5, "整体生命条件治疗4")
	var used := c.silvermoon.used_spells.size()
	c.silvermoon.check_health_spells()
	check(c.silvermoon.used_spells.size() == used and target.current_health == 5, "条件法术不重复释放")
	c = battle([owned("moon_hawk")], [owned("baggage_muleteer")], [owned("nightfall")])
	c.elapsed_seconds = 10
	c._resolve_due_prepared_spells()
	c.silvermoon.process_due()
	check(c.fatigue_start_seconds == 20 and c._next_fatigue_damage_seconds == 20, "黑夜准备10秒后使风暴在第20秒启动")
	c.elapsed_seconds = 20
	var fatigue := c._prepare_fatigue_events(c.get_all_states())
	check(fatigue.size() == 2 and fatigue[0].exact_amount == 1, "提前风暴第一跳仍为1")
	c = battle([owned("twilight_elemental")], [owned("baggage_muleteer")], [], [], [0])
	c.elapsed_seconds = 30
	fatigue = c._prepare_fatigue_events(c.get_all_states())
	check(fatigue[0].exact_amount == 0.5, "后排晨昏元素疲劳保留0.5精度")

func test_links_and_seed() -> void:
	var c := battle([owned("silvermoon_priest"), owned("moon_hawk")], [owned("baggage_muleteer"), owned("moonshadow_stoneguard")], [owned("victory_prophecy")])
	check(c.silvermoon.links.size() == 1, "准备法术实际释放触发祭祀")
	var healing := c._build_action(c.enemy_states[0], c.enemy_states, CardData.ActionType.HEAL)
	c.silvermoon.on_action_launched(healing)
	check(c.silvermoon.links.size() == 1, "治疗行动不复制也不消耗攻击链接")
	var defense := c._build_action(c.enemy_states[0], c.enemy_states, CardData.ActionType.DEFENSE)
	c.silvermoon.on_action_launched(defense)
	check(c.silvermoon.links.size() == 1, "防御行动不复制也不消耗攻击链接")
	var actor := c.player_states[1]
	var action := c._build_action(actor, c.get_all_states(), CardData.ActionType.MAGIC)
	action.target = c.enemy_states[0]
	(action.base_event as BattleEffectEvent).target = c.enemy_states[0]
	var armor_before := c.enemy_states[1].current_armor
	c.silvermoon.on_action_launched(action)
	check(c.silvermoon.links.is_empty() and c.enemy_states[1].current_armor < armor_before, "下一攻击行动复制另一目标并消费链接")
	var bearer := owned("baggage_muleteer")
	var squad := SquadData.from_owned_card(bearer)
	squad.equip_item(owned("moonshadow_seed"))
	c = battle([bearer], [owned("baggage_muleteer")])
	actor = c.player_states[0]
	actor.squad_data.equip_item(owned("moonshadow_seed"))
	c.elapsed_seconds = 30
	c.execute_immediate_action(actor, CardData.ActionType.MAGIC)
	check(c.silvermoon.extra_actions.size() == 1, "树种原行动完成后排一个追加")
	c.silvermoon.process_due()
	check(c.silvermoon.extra_actions.is_empty(), "追加为独立行动且不递归")
	c = battle([owned("baggage_muleteer")], [owned("baggage_muleteer")], [owned("moonshadow")])
	actor = c.player_states[0]
	c.twisted_vein.add_modifier(actor, BattleModifier.Stat.ACTION_VALUE, 50, &"test_temporary")
	c.twisted_vein.add_modifier(actor, BattleModifier.Stat.REINFORCEMENT, 40, &"test_reinforcement")
	c.twisted_vein.add_modifier(actor, BattleModifier.Stat.ACTION_MULTIPLIER, 1, &"test_multiplier")
	var launches: Array[BattleEffectEvent] = []
	c.projectile_launched.connect(func(event: BattleEffectEvent) -> void: launches.append(event))
	hit(c.enemy_states[0], actor, 1000)
	check(launches.size() == 1 and is_equal_approx(launches[0].formula.exact_result, actor.get_action_source().base_value), "月影仅原生永久值追加，不含临时强化")
	hit(c.enemy_states[0], actor, 1000)
	check(launches.size() == 1, "月影同目标本场只一次")

func test_resources() -> void:
	var c := battle([owned("moondew_collector"), owned("baggage_muleteer")], [owned("baggage_muleteer")], [], [owned("moondew")])
	var actor := c.player_states[0]
	var action := c._build_action(actor, c.get_all_states(), actor.get_effective_action_type())
	check(action.is_mining, "采集者无限开采替换行动")
	var other := c.player_states[1]
	var cooldown := other.remaining_cooldown
	c.twisted_vein.add_modifier(other, BattleModifier.Stat.REINFORCEMENT, 10, &"charge_selection")
	c._apply_effect_event(action.base_event)
	check(is_equal_approx(other.remaining_cooldown, cooldown - 0.5), "成功采矿充能最高有效值友军0.5秒")
	check(c.twisted_vein.mining_totals[0] == 1, "原矿脉成功采矿计数兼容")
	c = battle([owned("moon_hawk")], [owned("moon_hawk")], [], [owned("moondew")])
	var player := c.player_states[0]
	var enemy := c.enemy_states[0]
	var before := [player.get_max_health(), player.get_display_action_value(), player.get_zeal_layers()]
	var event := c.make_mining_event(enemy, c.player_resource_states[0])
	c._apply_effect_event(event)
	var after := [player.get_max_health(), player.get_display_action_value(), player.get_zeal_layers()]
	check(before != after, "敌方采我方月露，奖励归资源板我方")
	check(enemy.get_max_health() == 4 and enemy.get_display_action_value() == 2 and enemy.get_zeal_layers() == 0, "敌方击碎者不抢资源所属奖励")
	c = battle([owned("baggage_muleteer")], [owned("moon_hawk")], [owned("moon_tears")])
	c.player_states[0].current_health = 1
	c.silvermoon.check_health_spells()
	check(not c.player_resource_states.is_empty(), "月泪填合法空资源格")
	check(c.player_resource_states.all(func(resource: RefCounted) -> bool: return resource.owned_card.card_data.id == &"moondew"), "月泪只召唤月露")

func test_shop() -> void:
	var service := OrdinaryShopService.new()
	service.initialize(1010)
	check(service.config.allowed_pack_ids.has("silvermoon_chapter"), "银月正式开放卡池")
	var definitions: Array[CardData] = catalog.duplicate()
	var folder := DirAccess.open("res://resources/cards")
	for file: String in folder.get_files():
		if file.ends_with(".tres"):
			var card := load("res://resources/cards/" + file) as CardData
			if card != null and card.pack_id == &"ash_ledger": definitions.append(card)
	var stickers := EmblemLibraryData.get_definitions()
	var saw_silver := false
	for index: int in 20:
		check(service.refresh(definitions, [], stickers, []), "开放银月后商店正常生成")
		for offer: Dictionary in service.offers:
			if offer.kind != "card_pack" or offer.has("procurement_action"): continue
			if offer.pack_id == "silvermoon_chapter": saw_silver = true
			for id: String in offer.cards:
				var definition := load("res://resources/cards/%s.tres" % id) as CardData
				check(String(definition.pack_id) == offer.pack_id and not definition.is_derived, "卡包不混主题且不含衍生卡")
	check(saw_silver, "可获得银月大／小包")

func test_equipment_and_timing() -> void:
	var c := battle([owned("moon_singer"), owned("baggage_muleteer")], [owned("baggage_muleteer"), owned("moon_hawk")], [], [], [1], [1])
	var target := c.enemy_states[0]
	echo(c.player_states[0], target)
	check(target.row_key == &"enemy_back", "歌者回响交换实际目标与其另一排友軍")
	var bearer := c.player_states[0]
	bearer.squad_data.equip_item(owned("dancer_handbell"))
	c._register_card_effects(bearer, bearer.squad_data.get_equipped_item().card_data, true)
	echo(bearer)
	check(bearer.row_key == &"player_back", "手铃回响交换自己与另一排友军")
	c = battle([owned("moon_hawk")], [owned("baggage_muleteer")])
	bearer = c.player_states[0]
	bearer.squad_data.equip_item(owned("sunmoon_amulet"))
	c.silvermoon.sync_auras()
	check(bearer.get_display_action_value() == 3, "护符前排普通值+1")
	bearer.row_key = &"player_back"
	c.silvermoon.sync_auras()
	check(bearer.get_display_action_value() == 2 and bearer.get_zeal_layers() == 2, "护符后排切热诚2")
	c = battle([owned("moon_hawk")], [owned("twilight_guard")])
	var actor := c.player_states[0]
	var before := actor.current_health
	hit(actor, c.enemy_states[0], 1)
	check(actor.current_health == before - 2, "守卫前排反射2无类型伤害")
	before = actor.current_health
	hit(actor, c.enemy_states[0], 1, CardData.ActionType.MAGIC, false)
	check(actor.current_health == before, "效果伤害不触发守卫反射")
	c = battle([owned("moon_hawk")], [owned("baggage_muleteer")])
	target = c.enemy_states[0]
	target.squad_data.equip_item(owned("night_cloak"))
	target.current_health = 500
	var misses := 0
	var hits := 0
	for index: int in 30:
		var event := hit(c.player_states[0], target, 0.1, CardData.ActionType.RANGED)
		if event.missed: misses += 1
		else: hits += 1
	check(misses > 0 and hits > 0, "披风逐次掷骰，既有命中也有落空")
	var event := c.twisted_vein.make_event(c.player_states[0], target, 1, CardData.ActionType.RANGED, true, "双标签披风")
	event.is_base_action = true
	event.dual_melee_ranged = true
	c._apply_effect_event(event)
	check(not event.missed, "披风不闪避双标签")
	c = battle([owned("darkmoon_judge")], [owned("baggage_muleteer"), owned("moon_hawk")], [], [], [], [], true)
	target = c.enemy_states[0]
	var unit := target.squad_data.get_effect_source_instance()
	unit.set_emblem_slot(0, {"emblem_id": &"苹果", "instance_id": &"timed_apple"})
	c._register_formation_emblems()
	c.execute_immediate_action(c.player_states[0], CardData.ActionType.MAGIC)
	check(target.masked_emblem_sources.is_empty(), "新审判者不再排定纹章遮蔽")
	var projectiles: Array = c._pending_projectile_contexts.keys()
	if not projectiles.is_empty():
		var main_event: BattleEffectEvent = projectiles[0]
		c.elapsed_seconds = main_event.impact_time
		c._resolve_due_projectile_impacts()
		check(not main_event.missed and main_event.target.masked_emblem_sources.is_empty() and c.enemy_states[1].get_buff_stacks(BattleRules.FATIGUE_BUFF_ID) == 1, "真实弹道完成回响对低生命随从施加疲劳")
	c = battle([owned("moon_hawk")], [owned("moon_hawk")], [owned("twilight_veil")])
	target = c.player_states[0]
	var direct := target.apply_direct_health_damage_exact(100)
	check(direct == 0 and target.is_banished, "无事件效果直伤也经过面纱免死")

func test_settlement_and_save() -> void:
	var collection := OwnedCardCollection.new()
	var apprentice := collection.create_card(load("res://resources/cards/silvermoon_apprentice.tres"))
	apprentice.rune_revealed.fill(true)
	apprentice.resolved_runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.LIGHT, CardData.ElementType.DARK])
	var star := collection.create_card(load("res://resources/cards/starfire.tres"))
	var victory := collection.create_card(load("res://resources/cards/victory_prophecy.tres"))
	var failure := collection.create_card(load("res://resources/cards/failure_prophecy.tres"))
	var registry: Dictionary = {}
	for card: CardData in catalog: registry[card.id] = card
	var rewards := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var service := BattleSettlementService.new()
	for index: int in 2:
		var prepared: Array[StringName] = [star.instance_id]
		var spells: Array[OwnedCard] = [star]
		if index == 0:
			prepared.append(victory.instance_id)
			prepared.append(failure.instance_id)
			spells.append(victory)
			spells.append(failure)
		var snapshot := BattlePreparationSnapshot.new()
		var id := StringName("silver_settle:%d" % index)
		check(snapshot.initialize(id, index, collection, {&"player_front": [SquadData.from_owned_card(apprentice)]}, prepared), "银月战前快照")
		var c := battle([apprentice], [owned("baggage_muleteer")], spells, [], [], [], false, [], id)
		c.silvermoon.finish(BattleController.Result.PLAYER_VICTORY)
		var result := service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, journal, c.get_owned_card_change_entries_for_settlement(), registry)
		check(result.get("success", false), "银月永久事务提交：" + str(result.get("reason", "")))
		check(star.spell_durability == 3 and collection.get_by_instance_id(star.instance_id) != null, "连续战后无限星火耐久不扣")
		check(apprentice.get_permanent_growth(&"max_health") == 2 * (index + 1), "永久生命按实例逐战提交")
		var again := service.settle(snapshot, c.permanent_growth_ledger.get_entries(), c.run_reward_ledger.get_entries(), collection, rewards, journal, c.get_owned_card_change_entries_for_settlement(), registry)
		check(again.status == BattleSettlementService.STATUS_ALREADY_COMMITTED, "重复结算不会再发奖励")
	check(rewards.gold == 3, "胜利预言金币一次提交，失败预言不混发")
	check(collection.get_by_instance_id(victory.instance_id) == null and collection.get_by_instance_id(failure.instance_id) == null, "一级预言正常扣耐久一次")
	var save := RunSaveService.new()
	var decoded := save._decode_collection_state(save._encode_collection_state(collection.capture_state()), registry)
	check(not decoded.is_empty(), "银月实例与无限耐久可序列化解码")
	var shop := OrdinaryShopService.new()
	shop.initialize(103)
	shop.config.temporary_offer_weights.sticker_pack_count = {"0": 1}
	shop.config.action_procurement.enabled = false
	check(shop.refresh(catalog, [], [], []), "单银月目录生成主题包")
	var capture := shop.capture_state()
	var definitions: Array[String] = []
	for card: CardData in catalog: definitions.append(String(card.id))
	check(shop.validate_saved_state(capture, definitions, [], catalog), "主题归属随商品存档验证")
	var restored := OrdinaryShopService.new()
	restored.config = shop.config.duplicate(true)
	check(restored.initialize(1, JSON.parse_string(JSON.stringify(capture))), "商店JSON往返恢复")
	var a := shop.refresh(catalog, [], [], [])
	var b := restored.refresh(catalog, [], [], [])
	check(a and b and JSON.stringify(shop.offers) == JSON.stringify(restored.offers), "读档继续抽包完全确定")
	var damaged := capture.duplicate(true)
	for offer: Dictionary in damaged.offers:
		if offer.kind == "card_pack": offer.pack_id = "ash_ledger"
	check(not shop.validate_saved_state(damaged, definitions, [], catalog), "拒绝篡改卡包主题")
