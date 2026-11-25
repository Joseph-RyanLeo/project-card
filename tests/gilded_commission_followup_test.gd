extends SceneTree

var _fight: BattleController
var _checks := 0
var _failures := 0
var _sequence := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sargon()
	_test_damili_and_doorboard()
	_test_dialer()
	_test_spells()
	_test_harmony()
	_test_timers_and_movement()
	_test_equipment_and_copy()
	_test_helmet_settlement()
	_test_mission_battle_tracking()
	_fight.clear_battle()
	_fight.free()
	print("镀金委托人审续接：%d 项，%d 失败" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(value: bool, message: String) -> void:
	_checks += 1
	if value: return
	_failures += 1
	push_error(message)


func _owned(id: String, runes: Array[int] = []) -> OwnedCard:
	_sequence += 1
	var card := OwnedCard.new()
	card.initialize(load("res://resources/cards/%s.tres" % id), StringName("gilded_test_%d" % _sequence), _sequence)
	if not runes.is_empty():
		card.resolved_runes.assign(runes)
		card.rune_revealed.fill(true)
	return card


func _squad(id: String, runes: Array[int] = []) -> SquadData:
	return SquadData.from_owned_card(_owned(id, runes))


func _start(allies: Array[SquadData], foes: Array[SquadData], spells: Array[OwnedCard] = [], reserve: Array[OwnedCard] = []) -> void:
	if _fight != null:
		_fight.clear_battle()
		_fight.free()
	_fight = BattleController.new()
	root.add_child(_fight)
	_fight.start_battle(_formation(allies, &"player_front"), _formation(foes, &"enemy_front"), 829, false, &"gilded_followup", spells, [], [], [], [], reserve)
	if not spells.is_empty():
		_fight.advance_time(spells.size() * BattleController.OPENING_SPELL_PRESENTATION_SECONDS + 0.001)


func _formation(squads: Array[SquadData], row: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in squads.size():
		result.append({"squad_data": squads[index], "row_key": row, "formation_index": index})
	return result


func _test_sargon() -> void:
	var sargon := _owned("sargon_harmonizer")
	sargon.resolved_action_type = CardData.ActionType.MELEE
	var unit := SquadData.from_owned_card(sargon)
	_start([unit, _squad("militia")], [_squad("militia"), _squad("musketeer")])
	_check(unit.contains_stacking_forbidden_card(), "萨尔贡沿用无法堆叠关键词")
	var probe := RandomNumberGenerator.new()
	for value: int in range(1, 100):
		probe.seed = value
		var previous := probe.state
		if probe.randi_range(1, 6) >= 5:
			_fight._random.state = previous
			break
	var actor := _fight.player_states[0]
	_fight.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": actor})
	_fight.effect_runtime.process_due(0.0)
	var entries := _fight.permanent_growth_ledger.get_entries()
	_check(entries.size() == 6 and entries.filter(func(e: Dictionary) -> bool: return e.stat == &"base_value").size() == 3, "一次骰值同时给自身、近战友军和近战敌军两项成长")


func _kill(victim: BattleSquadState, source: BattleSquadState = null) -> void:
	_fight._death_wound_checked[victim.runtime_id] = true
	victim.pending_kill_source = source
	victim.current_health = 0.0
	_fight._finalize_batch()


func _test_damili_and_doorboard() -> void:
	_start([_squad("damili_bloodthorn"), _squad("militia")], [_squad("militia")])
	var damili := _fight.player_states[0]
	var target := _fight.enemy_states[0]
	for index: int in 5:
		if index > 0: _fight.revive_state_at_original_position(target, 2.0)
		_kill(target, damili)
	_check(_fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 4.0, "达米莉同一次生命内最多触发四次荣耀")
	_kill(damili)
	_check(_fight.revive_state_at_original_position(damili, 2.0) and _fight.revive_state_at_original_position(target, 2.0), "荣耀测试复活双方")
	_kill(target, damili)
	_check(_fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 5.0, "达米莉复活后重新获得荣耀次数")
	var door := _owned("doorboard")
	door.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 20.0)
	_start([_squad("militia"), SquadData.from_owned_card(door), _squad("militia")], [_squad("militia")])
	_kill(_fight.player_states[0])
	_check(_fight.permanent_growth_ledger.get_amount_for_owned_card(door.instance_id, &"max_health") == 1, "门板见相邻友军死亡获得一项永久成长")
	_kill(_fight.player_states[1])
	var recipient := _fight.player_states[2]
	_check(recipient.modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 26.0 and recipient.current_health == recipient.get_max_health(), "门板超过25基础生命后向相邻友军增加等量最大与当前生命")


func _test_dialer() -> void:
	var pair_squad := _squad("militia", [0, 0, 1])
	_start([_squad("dialer_beep"), pair_squad], [_squad("militia", [0, 0, 1])])
	var actor := _fight.player_states[1]
	var promoted := actor.get_rune_pattern_result()
	var groups := BattleElementResolver.get_element_groups(promoted)
	_check(promoted.pattern_type == RunePatternResult.PatternType.THREE_OF_A_KIND and promoted.participating_indices.size() == 2 and groups.size() == 1 and groups[0].count == 3, "哔哔升级三相的倍率和派生，仍只引用两枚实际符文")
	_check(_fight.enemy_states[0].get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.PAIR, "哔哔只影响同侧友军")
	_fight.player_states[0].grant_runtime_keyword(&"silenced", 891)
	_check(actor.get_rune_pattern_result().pattern_type == RunePatternResult.PatternType.PAIR, "哔哔被遮蔽后恢复真实双鸣")


func _test_spells() -> void:
	var militia := _squad("militia", [0, 3, 4])
	_start([militia, _squad("dialer_beep")], [_squad("militia")], [_owned("commoner_hero"), _owned("elemental_burst"), _owned("signal_jamming")])
	var actor := _fight.player_states[0]
	_check(actor.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 3.0 and actor.modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 5.0, "平民英雄正常释放给Ⅰ级队长+3/+5")
	_check(_fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 0.0, "平民英雄跳过IV级队长")
	_check(actor.current_health == militia.get_effective_max_health() + 6 and actor.get_active_rune_stat_bonus(&"base_armor") == 2 and actor.get_zeal_layers() == 2, "元素爆发同步生命、护甲和暗热诚")
	_check(actor.modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 4.0, "元素爆发只将火强化翻倍一次")
	var foe := _fight.enemy_states[0]
	_check(foe.get_zeal_layers() == -10 and _fight.gilded.next_delay(0.0) == 10.0, "干扰覆盖开场十秒")
	_fight.elapsed_seconds = 10.0
	_fight.gilded.process_due()
	_check(foe.get_zeal_layers() == 0 and is_inf(_fight.gilded.next_delay(10.0)), "干扰到时恢复热诚")


func _test_harmony() -> void:
	var left := _owned("militia", [0, 3, 4])
	var right := _owned("musketeer", [4, 1, 2])
	var straight := SquadData.from_cards([left.get_battlefield_card(), right.get_battlefield_card()])
	straight.bind_owned_card(left.get_battlefield_card(), left)
	straight.bind_owned_card(right.get_battlefield_card(), right)
	straight.bring_card_to_top(left.get_battlefield_card())
	_start([_squad("militia"), straight, _squad("militia")], [_squad("militia")], [_owned("ultimate_harmony")])
	var pattern := _fight.player_states[1].get_rune_pattern_result()
	_check(pattern.pattern_type == RunePatternResult.PatternType.STRAIGHT, "终极调和夹具识别连星")
	var a := _fight.player_states[0]
	var b := _fight.player_states[2]
	var action := a.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE)
	var health := a.modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH)
	_check(action >= 1.0 and action <= 6.0 and health >= 1.0 and health <= 10.0 and b.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == action and b.modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == health, "终极调和真实开场释放，左右邻居共用一组骰值")


func _test_timers_and_movement() -> void:
	var oak := _owned("mogris_old_oak")
	_start([SquadData.from_owned_card(oak), _squad("militia")], [_squad("militia")])
	_fight.elapsed_seconds = 45.0
	_fight.gilded.process_due()
	_check(oak.progress_by_source.get(&"mogris_survived", 0) == 1 and _fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0.0, "莫格里斯本场记录达标，奖励留到下一场")
	_start([SquadData.from_owned_card(oak), _squad("militia")], [_squad("militia")])
	_kill(_fight.player_states[0])
	_fight.elapsed_seconds = 45.0
	_fight.gilded.process_due()
	_check(_fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 5.0 and _fight.player_states[1].modifiers.get_additive(BattleModifier.Stat.MAX_HEALTH) == 10.0, "莫格里斯已触发的独立读秒在阵亡后照常发奖")
	var nyx := _owned("nyx_contract_demon")
	nyx.progress_by_source[OwnedCard.NYX_ROADS_PROGRESS] = 16
	_start([SquadData.from_owned_card(nyx), _squad("militia")], [_squad("militia")])
	_check(_fight.player_states[1].get_zeal_layers() == 6, "契约奈克斯达标后开场给友军热诚")
	var encore := _owned("starsinger_encore")
	_start([_squad("recruiter"), _squad("militia")], [_squad("militia")], [encore, _owned("nature_guard")])
	var before := _fight.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST, 0)
	_fight.gilded.on_movement(0)
	_fight.gilded.on_movement(0)
	_fight.effect_runtime.process_due(_fight.elapsed_seconds)
	_check(_fight.run_reward_ledger.get_total(BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST, 0) == before + 1, "安可曲在位移后重放一次完整突击")
	var probe := RandomNumberGenerator.new()
	for seed: int in range(1, 100):
		probe.seed = seed
		var saved := probe.state
		if probe.randi_range(1, 6) >= 5:
			_fight._random.state = saved
			break
	var friend := _fight.player_states[1]
	var health := friend.current_health
	friend.apply_damage_exact(1.0, null, null, true)
	_check(friend.current_health == health, "自然守护用同一伤害入口掷出成功时免伤")
	_fight.elapsed_seconds = 10.0
	friend.apply_damage_exact(1.0, null, null, true)
	_check(friend.current_health == health - 1.0, "自然守护的第10秒后恢复承伤")


func _test_equipment_and_copy() -> void:
	var toy := _squad("doorboard")
	toy.equip_item(_owned("doorboard_toy"))
	_start([toy], [_squad("militia")])
	var bearer := _fight.player_states[0]
	bearer.current_health = 4.9
	_check(bearer.get_doorboard_toy_bonus() == 0 and bearer.get_zeal_layers() == -4, "玩具按当前生命舍去零头，旧代价换算为-4热诚")
	bearer.current_health = 25.0
	_check(bearer.get_doorboard_toy_bonus() == 5, "玩具无独立数值上限")
	var book := _owned("gravekeepers_notes")
	var notes := _squad("militia")
	notes.equip_item(book)
	_start([notes, _squad("musketeer")], [_squad("militia"), _squad("militia"), _squad("musketeer")])
	_kill(_fight.enemy_states[0])
	_kill(_fight.enemy_states[1])
	_check(book.progress_by_source.get(&"gravekeeper_seen:militia", 0) == 1 and book.progress_by_source.size() == 1, "笔记同名阵亡只记一个种类")
	var insect := _owned("insect_blade")
	insect.progress_by_source[&"insect_blade_summons"] = 9
	var summoner := _squad("kalis_summoner")
	summoner.equip_item(insect)
	var reserve := _owned("shieldwall_private")
	reserve.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 7)
	_start([summoner, _squad("militia")], [_squad("musketeer")], [], [reserve])
	_kill(_fight.player_states[1])
	var copied: BattleSquadState = _fight.player_states.back()
	var copy_owner: OwnedCard = copied.squad_data.get_effect_source_instance()
	_check(copied.battle_summoned and copied.formation_index == 1 and copy_owner.instance_id != reserve.instance_id and copy_owner.get_permanent_growth(OwnedCard.STAT_MAX_HEALTH) == 7, "喀利斯在腾空位置临时复制未部署实例")
	_check(insect.progress_by_source.get(&"insect_blade_summons", 0) == 10, "全队成功召唤使虫刃跨战进度达标")
	var enemy := _fight.enemy_states[0]
	enemy.current_health = 20.0
	enemy.current_armor = 0.0
	_fight.use_projectile_timing = false
	_fight.effect_runtime.emit_trigger(BattleEffectDefinition.Trigger.ECHO, {"actor": _fight.player_states[0]})
	_fight.effect_runtime.process_due(_fight.elapsed_seconds)
	_check(enemy.current_health == 16.0, "虫刃目标只有一个时两次固定伤害都命中")

func _test_helmet_settlement() -> void:
	var collection := OwnedCardCollection.new()
	var carrier := _owned("militia")
	var team := SquadData.from_owned_card(carrier)
	var helmet := _owned("balin_helmet")
	var item := _owned("nyx_dice")
	var base_armor := team.get_effective_base_armor()
	item.equipment_durability = 3
	item.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 4)
	_check(team.equip_item(item) and team.equip_item(helmet, Vector2(18, 30)) and team.get_equipped_items().size() == 2, "巴林头盔与普通装备独立佩戴")
	_check(team.get_effective_base_armor() == base_armor + 2 and team.get_equipment_zeal_delta() == item.card_data.equipment_zeal_delta - 2, "头盔护甲与热诚计入小队")
	for owned: OwnedCard in [carrier, item, helmet]: collection.add_existing(owned)
	var snapshot := BattlePreparationSnapshot.new()
	snapshot.initialize(&"gilded_followup", 829, collection, {&"player_front": [team]})
	_start([team], [_squad("musketeer")], [], collection.get_cards())
	var entries := _fight.run_reward_ledger.get_entries()
	_check(entries.size() == 1 and entries[0].effect_id == &"balin_helmet", "开场头盔只记录一次复制奖励")
	var service := BattleSettlementService.new()
	var reward := RunRewardState.new()
	var journal := RunSettlementJournal.new()
	var registry := {item.card_data.id: item.card_data}
	var settled := service.settle(snapshot, [], entries, collection, reward, journal, [], registry)
	var copies := collection.get_cards().filter(func(card: OwnedCard) -> bool: return card.is_temporary_equipment())
	_check(settled.success and copies.size() == 1 and copies[0].equipment_durability == 3 and copies[0].get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 4, "正式结算将装备独立复制到收藏，并保留成长与剩余耐久")
	if copies.is_empty(): return
	var copy_id: StringName = copies[0].instance_id
	var duplicate := service.settle(snapshot, [], entries, collection, reward, journal, [], registry)
	_check(duplicate.status == BattleSettlementService.STATUS_ALREADY_COMMITTED and collection.size() == 4, "战后重入不再发放复制品")
	snapshot.initialize(&"gilded_followup_next", 830, collection, {&"player_front": [team]})
	_check(service.settle(snapshot, [], [], collection, reward, journal).success and collection.get_by_instance_id(copy_id) == null and collection.get_by_instance_id(item.instance_id) == item, "下场正式结算时未装备的复制品也消失，原装备仍在")


func _test_mission_battle_tracking() -> void:
	var carrier := _squad("militia")
	var kill_task := _owned("secret_mission")
	kill_task.progress_by_source[OwnedCard.MISSION_GOAL] = OwnedCard.MissionGoal.KILLS
	carrier.equip_item(kill_task)
	var spell_task := _owned("secret_mission")
	spell_task.progress_by_source[OwnedCard.MISSION_GOAL] = OwnedCard.MissionGoal.SPELLS
	var spell := _owned("commoner_hero")
	_start([carrier, _squad("militia")], [_squad("musketeer"), _squad("militia")], [spell], [kill_task, spell_task])
	_kill(_fight.enemy_states[0], _fight.player_states[1])
	_check(int(kill_task.progress_by_source.get(OwnedCard.MISSION_PROGRESS, 0)) == 0, "其他小队的击杀不计入隐秘任务")
	_kill(_fight.enemy_states[1], _fight.player_states[0])
	_check(kill_task.progress_by_source.get(OwnedCard.MISSION_PROGRESS, 0) == 1, "击杀按实际来源累计")
	_check(spell_task.progress_by_source.get(OwnedCard.MISSION_PROGRESS, 0) == 1, "未佩戴的隐秘任务也记录实际释放的友方法术")
	_check(_fight.owned_card_change_ledger.get_entries().any(func(entry: Dictionary) -> bool: return entry.owned_card_instance_id == spell_task.instance_id and entry.parameters.get("counter_key") == OwnedCard.MISSION_PROGRESS), "未佩戴的法术进度进入正式战斗账本")
