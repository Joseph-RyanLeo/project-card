extends SceneTree

var checks := 0
var failures := 0
func check(value: bool, title: String) -> void:
	checks += 1
	if value: print("PASS: ", title)
	else:
		failures += 1
		push_error(title)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var collection := OwnedCardCollection.new()
	var bottom := collection.create_card(load("res://resources/cards/musketeer.tres"))
	var top := collection.create_card(load("res://resources/cards/militia.tres"))
	var ally := collection.create_card(load("res://resources/cards/town_priest.tres"))
	var spell := collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	var enemy := OwnedCard.new()
	enemy.initialize(load("res://resources/cards/musketeer.tres"), &"enemy", 0)
	enemy.apply_permanent_growth(&"max_health", 1000)
	var squad := SquadData.from_cards([top.card_data, bottom.card_data])
	squad.bind_owned_card(bottom.card_data, bottom)
	squad.bind_owned_card(top.card_data, top)
	check(squad.get_effect_source_instance() == top, "实际堆叠最上层为队长")
	spell.spell_durability = 1
	var snapshot := BattlePreparationSnapshot.new()
	check(snapshot.initialize(&"statistics_test", 882, collection, {&"player_front": [squad]}, [spell.instance_id]), "建立真实战前快照与法术准备记录")
	var progress := ProfileProgress.new()
	progress.start_run()
	collection.card_removing.connect(progress.remember_exhausted_spell)
	var controller := BattleController.new()
	root.add_child(controller)
	var player_formation: Array[Dictionary] = [{"squad_data": squad, "row_key": &"player_front", "formation_index": 0}, {"squad_data": SquadData.from_owned_card(ally), "row_key": &"player_back", "formation_index": 0}]
	var enemy_formation: Array[Dictionary] = [{"squad_data": SquadData.from_owned_card(enemy), "row_key": &"enemy_front", "formation_index": 0}]
	var prepared: Array[OwnedCard] = [spell]
	controller.start_battle(player_formation, enemy_formation, 882, false, &"statistics_test", prepared)
	var actor := controller.player_states[0]
	var target := controller.enemy_states[0]
	var event := BattleEffectEvent.new()
	event.source = actor
	target.apply_damage_exact(3.5, actor, event, true)
	actor.apply_damage_exact(2, target, event, true)
	actor.apply_healing_exact(20, actor, event)
	actor.apply_armor_exact(1.5, actor, event)
	var stats := controller.get_owned_card_statistics()
	var id := String(top.instance_id)
	check(stats[id].damage_dealt == 3.5 and stats[id].damage_taken == 2, "实际伤害和承伤全部归队长")
	check(stats[id].healing_done == 2 and stats[id].armor_granted == 1.5, "实际生效治疗与护甲，过量不累计")
	check(not stats.has(String(bottom.instance_id)), "其余堆叠成员不重复累计")
	var spell_event := BattleEffectEvent.new()
	spell_event.source_owned_card_instance_id = spell.instance_id
	target.apply_damage_exact(4, null, spell_event, true)
	stats = controller.get_owned_card_statistics()
	check(stats[String(spell.instance_id)].damage_dealt == 4 and stats[id].damage_dealt == 3.5, "法术直接伤害独立归法术实例")
	var summoned := controller.summon_content_minion(actor, load("res://resources/cards/booby_mine.tres"))
	var summon_event := BattleEffectEvent.new()
	summon_event.source = summoned
	target.apply_damage_exact(2, summoned, summon_event, true)
	check(controller.get_owned_card_statistics()[id].damage_dealt == 5.5, "召唤物伤害归召唤源卡")
	actor.apply_damage_exact(9999, target, event, true)
	controller._finalize_batch()
	check(controller.revive_state_at_original_position(actor, 3, false), "实际复活同一战斗单位")
	actor.apply_damage_exact(9999, target, event, true)
	controller._finalize_batch()
	stats = controller.get_owned_card_statistics()
	check(stats[id].battles == 1 and stats[id].deaths == 1, "首次阵亡计1，复活和再次阵亡不追加")
	target.apply_damage_exact(99999, null, spell_event, true)
	controller._finalize_batch()
	check(controller.get_owned_card_statistics()[String(spell.instance_id)].kills == 1, "法术击杀即使没有随从source也归法术")
	check(top.lifetime_stats.is_empty() and spell.lifetime_stats.is_empty(), "战斗中暂存统计，不提前写永久单卡")
	var journal := RunSettlementJournal.new()
	var reward := RunRewardState.new()
	var service := BattleSettlementService.new()
	var final_spell_stats: Dictionary = controller.get_owned_card_statistics()[String(spell.instance_id)].duplicate(true)
	var settlement := service.settle(snapshot, [], [], collection, reward, journal, [], {}, null, Callable(), controller.get_owned_card_statistics())
	check(settlement.get("success", false), "真实结算服务提交单卡累计战绩")
	check(collection.get_by_instance_id(spell.instance_id) == null and progress.run.exhausted_spells.has(String(spell.instance_id)), "正常耗尽法术由移除回调保存候选")
	var archived: Dictionary = progress.run.exhausted_spells[String(spell.instance_id)].lifetime_stats
	check(archived.damage_dealt == final_spell_stats.damage_dealt and archived.kills == final_spell_stats.kills and archived.battles == final_spell_stats.battles, "耗尽前已累计本场伤害与击杀，候选保留完整战绩")
	var submitted: Dictionary = top.lifetime_stats.duplicate(true)
	check(service.settle(snapshot, [], [], collection, reward, journal, [], {}, null, Callable(), controller.get_owned_card_statistics()).get("success", false) and top.lifetime_stats == submitted, "同场重复提交不重复累计单卡战绩")
	controller.clear_battle()
	controller.free()
	await process_frame
	print("D3-2 statistics checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
