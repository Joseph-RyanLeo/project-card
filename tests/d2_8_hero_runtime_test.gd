extends SceneTree
const Controller = preload("res://scripts/battle/battle_controller.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _card(id: String) -> CardData:
	var card := load("res://resources/cards/%s.tres" % id).duplicate(true) as CardData
	card.runes.clear()
	card.armor = 0 # 单元测试输入为无甲目标，正式民兵资源保持原值
	return card

func _entry(card: CardData, row: StringName, index: int) -> Dictionary:
	return {"squad_data": SquadData.from_card(card), "row_key": row, "formation_index": index}

func _sentry(region: String, capacity: float = 6.0) -> Dictionary:
	return {"instance_id": "test_" + region, "visual_variant": 0, "region": region, "capacity": capacity, "remaining": capacity}

func _controller(talents: Array[String], sentries: Array[Dictionary], level: int = 4, fortify: bool = false, seed_value: int = 91038, health: int = 99) -> Node:
	var controller := Controller.new()
	root.add_child(controller)
	var front := _card("militia")
	front.cooldown_seconds = 99.0
	front.max_health = health
	var back := _card("militia")
	back.cooldown_seconds = 99.0
	back.max_health = health
	var enemy := _card("militia")
	enemy.cooldown_seconds = 99.0
	enemy.max_health = 99
	var catalog: Array[CardData] = []
	var directory := DirAccess.open("res://resources/cards")
	for filename: String in directory.get_files():
		if filename.ends_with(".tres"):
			catalog.append(load("res://resources/cards/" + filename))
	controller.start_battle([_entry(front, &"player_front", 0), _entry(back, &"player_back", 0)], [_entry(enemy, &"enemy_front", 0)], seed_value, false, &"runtime_unit", [], [], [], [], catalog, [], {"level": level, "talents": talents, "sentries": sentries, "fortify_complete": fortify, "rules": JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/ioann_warden_config.json"))})
	return controller

func _hit(controller: Node, target: BattleSquadState, amount: float, type: CardData.ActionType, pierces: bool = false, multiplier: bool = false) -> BattleEffectEvent:
	var event := BattleEffectEvent.new()
	event.target = target
	event.source = controller.enemy_states[0]
	event.action_type = type
	event.exact_amount = amount
	event.uses_attack_type_multiplier = multiplier
	event.pierces_armor = pierces
	event.formula = BattleFormulaData.create("测试命中", type, amount, 1.0, 1.0, event.source, target)
	controller._apply_effect_event(event)
	return event

func _run() -> void:
	var c := _controller(["sentry_guard"], [_sentry("front"), _sentry("back"), _sentry("spells")])
	_expect(c.player_states[0].current_armor == 12.0 and c.player_states[1].current_armor == 0.0, "护：三枚哨位每枚给所有前排+4，后排不加")
	var event := _hit(c, c.player_states[1], 4.0, CardData.ActionType.MELEE)
	_expect(event.exact_amount == 3.0 and c.hero_runtime.sentries[0].remaining == 5.0, "前排哨位分担所有友军近战，不限目标所在排")
	event = _hit(c, c.player_states[0], 4.0, CardData.ActionType.RANGED)
	_expect(event.exact_amount == 3.0 and c.hero_runtime.sentries[1].remaining == 5.0, "后排哨位分担远程")
	event = _hit(c, c.player_states[1], 0.25, CardData.ActionType.MAGIC)
	_expect(event.exact_amount == 0.0 and c.hero_runtime.sentries[2].remaining == 5.75, "法术堆分担法术，保存小数容量")
	c.free()
	c = _controller([], [_sentry("front")])
	event = _hit(c, c.player_states[0], 4.0, CardData.ActionType.RANGED)
	_expect(event.exact_amount == 4.0 and c.hero_runtime.sentries[0].remaining == 6.0, "类型不匹配不分担")
	c.free()
	c = _controller(["sentry_break"], [_sentry("front"), _sentry("back")], 3)
	_expect(c._get_next_event_delay() == 4.0, "破进入统一时钟，第4秒前无哨位行动")
	_expect(c.resolve_next_batch() and c.elapsed_seconds == 4.0, "真实下一批到第4秒")
	_expect(is_equal_approx(c.enemy_states[0].current_health, 99.0 - 3.0 * 0.8 * 2), "破：每枚独立命中并使用远程无甲0.8倍率")
	_expect(c.hero_runtime.sentries[0].remaining == 6.0 and c._get_next_event_delay() == 4.0, "破不消费容量，下一次仍间隔4秒")
	c.free()
	c = _controller(["sentry_sharp"], [_sentry("front", 0.5)], 3, false, 91038, 20)
	var before_total_hp: float = c.player_states[0].get_max_health() + c.player_states[1].get_max_health()
	_hit(c, c.player_states[0], 2.0, CardData.ActionType.MELEE)
	_expect(c.hero_runtime.sentries.is_empty(), "容量耗尽立即销毁")

	_expect(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) + c.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1.5, "锐：3级行动值+1.5，内部不取整")
	_expect(c.player_states[0].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) + c.player_states[1].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 3.0, "锐：3级最大生命+3，只有一个存活友军受益")
	_expect(c.player_states[0].get_max_health() + c.player_states[1].get_max_health() == before_total_hp + 3.0, "锐：最大生命增加3")
	c.free()
	c = _controller(["sentry_sharp"], [_sentry("front", 0.5)], 3, false, 91038, 20)
	var peek := RandomNumberGenerator.new()
	peek.seed = c._random.seed
	peek.state = c._random.state
	var chosen: BattleSquadState = c.player_states[peek.randi_range(0, 1)]
	chosen.apply_damage_exact(0.75)
	_hit(c, chosen, 2.0, CardData.ActionType.MELEE)
	_expect(is_equal_approx(chosen.current_health, 20.75) and chosen.displayed_health == 21, "锐：整数生命提升保留0.75承伤累计，再受1.5伤害显示一致")
	c.free()
	c = _controller(["sentry_sharp"], [_sentry("front", 0.5)], 3, false, 91038, 20)
	peek.seed = c._random.seed
	peek.state = c._random.state
	chosen = c.player_states[peek.randi_range(0, 1)]
	chosen.current_health = 26.0
	chosen.displayed_health = 26
	_hit(c, chosen, 2.0, CardData.ActionType.MELEE)
	_expect(is_equal_approx(chosen.current_health, 24.5), "锐：既有超上限生命不会在增加上限时被截断")
	c.free()
	c = _controller(["sentry_needle"], [_sentry("front", 0.5)])
	c.enemy_states[0].current_armor = 2.0
	event = _hit(c, c.player_states[0], 4.0, CardData.ActionType.MELEE)
	_expect(event.exact_amount == 3.5 and c.enemy_states[0].current_armor == 1.5 and c.enemy_states[0].current_health == 99.0, "针刺按实际0.5分担量反伤，不再乘有甲近战0.7")
	c.free()
	c = _controller(["sentry_fortify"], [_sentry("front")], 4, true)
	event = _hit(c, c.player_states[0], 5.0, CardData.ActionType.MELEE)
	_expect(event.exact_amount == 2.0 and c.hero_runtime.sentries[0].remaining == 3.0, "坚固完成后最多分担3")
	c.free()
	c = _controller(["sentry_protection"], [_sentry("front", 6), _sentry("back", 2), _sentry("spells", 2)])
	c.player_states[0].current_health = 3.0
	event = _hit(c, c.player_states[0], 9.0, CardData.ActionType.MAGIC, true)
	_expect(event.missed and c.player_states[0].current_health == 8.0, "保护：法术先分担，再免疫整次剩余伤害、恢复5")
	_expect(c.hero_runtime.sentries.size() == 2 and c.hero_runtime.sentries[1].region == "back", "保护选择分担后容量最小的法术堆，保留后排")
	c.free()
	c = _controller(["sentry_protection"], [_sentry("front", 2), _sentry("back", 2)])
	c.player_states[0].current_health = 2.0
	event = _hit(c, c.player_states[0], 20.0, CardData.ActionType.MAGIC, true)
	_expect(c.hero_runtime.sentries.size() == 1 and c.hero_runtime.sentries[0].region == "back", "保护容量相同优先前排")
	c.free()
	c = _controller(["sentry_protection"], [_sentry("back")])
	c.player_states[0].current_health = 2.0
	var split: Dictionary = c.player_states[0].apply_damage_exact(20.0, c.enemy_states[0])
	_expect(split.total == 0.0 and c.player_states[0].current_health == 7.0 and c.hero_runtime.sentries.is_empty(), "卡牌效果直伤也受保护，不绕过英雄免死")
	c.free()
	for seed_index: int in 20:
		c = _controller(["sentry_spell"], [_sentry("front"), _sentry("back"), _sentry("spells")], 4, false, seed_index)
		_expect(c.hero_runtime.spell_awards.size() == 3 and c._prepared_spell_instances.is_empty(), "咒获得3张法术，不在本场直接施放")
		var awarded_iv: Array[String] = []
		for card_id: String in c.hero_runtime.spell_awards:
			var card := load("res://resources/cards/%s.tres" % card_id) as CardData
			_expect(card.is_available and card.card_type == CardData.CardType.SPELL and card.get_effective_faction() == CardFaction.Id.RADIANT_ALLIANCE, "咒使用正式已实现辉光法术")
			if card.rarity == CardData.Rarity.IV:
				_expect(card_id not in awarded_iv, "同场多哨位不重复授予同名IV")
				awarded_iv.append(card_id)
		c.free()
	c = _controller(["sentry_protection"], [_sentry("front")])
	var released_state: BattleSquadState = c.player_states[0]
	c.clear_battle()
	_expect(not released_state.direct_damage_guard.is_valid(), "清理战斗撤销英雄直伤检查，不使旧状态继续触发哨位")
	c.free()
	print("D2-8 哨位战斗：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
