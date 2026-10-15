extends SceneTree

## 正式效果目录与控制器的五张卡重做验证，不替代战斗计算。
var assertions := 0
var failures := 0
var controller: BattleController

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func card(id: String) -> CardData:
	var value := load("res://resources/cards/%s.tres" % id).duplicate(true) as CardData
	value.runes.clear()
	value.cooldown_seconds = 99
	return value

func entry(value: CardData, index: int, row: StringName = &"player_front") -> Dictionary:
	return {"squad_data": SquadData.from_card(value), "row_key": row, "formation_index": index}

func start(players: Array[Dictionary]) -> void:
	if controller != null: controller.free()
	controller = BattleController.new()
	root.add_child(controller)
	var enemy := card("heavy_knight")
	enemy.effect_ids.clear()
	controller.start_battle(players, [entry(enemy, 0, &"enemy_front")], 1005, false, &"card_rework")

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("五卡专项超时"); quit(1))
	var catalog := BattleEffectCatalog.load_from_file("res://data/demo2/ash_ledger_effect_samples.json")
	check(catalog.is_valid(), "五张卡重做后正式效果目录严格校验通过")
	var equipped := OwnedCard.new()
	equipped.initialize(card("coarse_bandage"), &"engraver_equipment", 0)
	var engraver := card("rune_engraver")
	var host := SquadData.from_card(card("musketeer"))
	host.equip_item(equipped)
	start([entry(engraver, 0), {"squad_data": host, "row_key": &"player_front", "formation_index": 1}, entry(card("musketeer"), 2)])
	check(controller.player_states[1].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 3, "符文刻匠突击给装备友军3强化")
	check(controller.player_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0 and controller.player_states[2].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 0, "未装备物品的友军不获得刻匠强化")
	check(controller.player_states.all(func(state: BattleSquadState): return state.modifiers.get_additive(BattleModifier.Stat.ACTION_MULTIPLIER) == 0), "旧刻匠行动倍率光环已删除")
	start([entry(card("militia"), 0), entry(card("shieldwall_private"), 1), entry(card("militia"), 2)])
	var shield := controller.player_states[1]
	check(controller.has_effective_dazzling(shield), "盾墙列兵具有真实耀眼目标规则")
	var armor_before: float = shield.current_armor
	var armor_event := BattleEffectEvent.new()
	armor_event.source = shield
	armor_event.target = shield
	armor_event.effect_kind = BattleEffectEvent.EffectKind.ARMOR
	armor_event.action_type = CardData.ActionType.DEFENSE
	armor_event.exact_amount = 3
	armor_event.formula = BattleFormulaData.create("护甲", CardData.ActionType.DEFENSE, 3, 1, 1, shield, shield)
	controller._apply_effect_event(armor_event)
	controller.effect_runtime.process_due(0)
	check(shield.current_armor == armor_before + 4, "盾墙乡邻每次护甲额外1点且不递归")
	var fire := card("fireman")
	var fire_left := card("musketeer")
	fire_left.runes.assign([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
	var fire_right := fire_left.duplicate(true) as CardData
	start([entry(fire, 0), entry(fire_left, 1), entry(fire_right, 2)])
	check(controller.player_states[0].get_max_health() == fire.max_health + 12 and controller.player_states[0].current_health == fire.max_health + 12, "伙夫六枚有效火符文获得12生命，不受旧五枚上限限制")
	check(controller.has_effective_dazzling(controller.player_states[0]), "伙夫具有真实耀眼规则")
	var wounded := OwnedCard.new()
	var wounded_card := card("musketeer")
	wounded_card.wound_slot_count = 2
	wounded.initialize(wounded_card, &"medic_wounded", 0)
	wounded.set_wound_slot(0, {"wound_id": &"中毒Ⅰ", "level": 1})
	wounded.set_wound_slot(1, {"wound_id": &"中毒Ⅱ", "level": 2})
	start([entry(card("field_medic"), 0), {"squad_data": SquadData.from_owned_card(wounded), "row_key": &"player_front", "formation_index": 1}])
	var patient := controller.player_states[1]
	patient.apply_direct_health_damage_exact(2)
	heal(controller.player_states[0], patient)
	check(patient.get_unmasked_active_injuries().size() == 1, "真实治疗遮蔽一处生效伤势")
	controller.effect_runtime.process_due(6)
	check(patient.get_unmasked_active_injuries().size() == 1, "超过旧五秒后遮蔽仍生效")
	heal(controller.player_states[0], patient)
	check(patient.get_unmasked_active_injuries().is_empty(), "后续治疗遮蔽另一伤势而不重复选择已遮蔽槽")
	controller.effect_runtime.notify_battle_end()
	controller.effect_runtime.process_due(0)
	check(patient.get_unmasked_active_injuries().size() == 2 and wounded.wound_slots[0].wound_id == &"中毒Ⅰ", "战斗结束解除临时遮蔽，原伤势仍存在")
	var poet := card("elegy_poet")
	var players: Array[Dictionary] = [entry(card("musketeer"), 0), entry(poet, 1), entry(card("musketeer"), 2)]
	for index: int in 4: players.append(entry(card("musketeer"), index, &"player_back"))
	var derived := card("musketeer")
	derived.is_derived = true
	players.append(entry(derived, 4, &"player_back"))
	start(players)
	var poet_state := controller.player_states[1]
	var left := controller.player_states[0]
	var right := controller.player_states[2]
	for index: int in range(3, 7):
		controller.player_states[index].current_health = 0
		controller._finalize_batch()
	check(left.get_zeal_layers() == 4 and right.get_zeal_layers() == 4, "四次非衍生友军死亡均增强诗人左右友军，没有旧三次限制")
	check(poet_state.get_zeal_layers() == 0 and poet_state.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 0 and poet_state.modifiers.get_additive(BattleModifier.Stat.BASE_ARMOR) == 0, "诗人自身不获得旧数值护甲成长或新邻居热诚")
	controller.player_states[7].current_health = 0
	controller._finalize_batch()
	check(left.get_zeal_layers() == 4 and right.get_zeal_layers() == 4, "衍生物死亡不触发悲歌诗人")
	controller.free()
	await process_frame
	print("五卡重做：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func heal(medic: BattleSquadState, patient: BattleSquadState) -> void:
	var event := BattleEffectEvent.new()
	event.source = medic
	event.target = patient
	event.action_type = CardData.ActionType.HEAL
	event.effect_kind = BattleEffectEvent.EffectKind.HEALING
	event.exact_amount = 1
	event.is_base_action = true
	event.formula = BattleFormulaData.create("治疗", CardData.ActionType.HEAL, 1, 1, 1, medic, patient)
	controller._apply_effect_event(event)
