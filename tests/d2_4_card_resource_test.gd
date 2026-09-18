extends SceneTree

## D2-4 第一小步：验证灰烬证册真实随从资源、效果绑定与实验室入口。
## 尚未实现的永久成长、复活、加卡、金币、伤势与开采只验证边界，不伪造结算。

const EFFECT_DATA_PATH := "res://data/demo2/ash_ledger_effect_samples.json"
const TIDE_ARCHER_PATH := "res://resources/cards/tide_archer.tres"
const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const BattleLabEffectLibrary = preload("res://scripts/tools/battle_lab_effect_library.gd")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data := _load_json()
	if data.is_empty():
		quit(1)
	_test_ash_ledger_resources(data)
	_test_real_battle_bindings()
	_test_battle_lab_real_effect_bundles(data)
	_test_tide_archer_deferred_hook()
	_test_positioning_cards_remain_available()
	_test_mudleg_brothers_forbid_stacking()
	if failures == 0:
		print("D2-4 card resource wiring checks passed.")
	else:
		push_error("D2-4 card resource wiring checks failed: %d" % failures)
	quit(failures)


func _load_json() -> Dictionary:
	var file := FileAccess.open(EFFECT_DATA_PATH, FileAccess.READ)
	_expect(file != null, "灰烬证册效果数据可读取")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "灰烬证册效果数据是合法 JSON 对象")
	return parsed as Dictionary if parsed is Dictionary else {}


func _test_ash_ledger_resources(data: Dictionary) -> void:
	var minions: Array[Dictionary] = []
	for raw_card: Variant in data.get("cards", []):
		if raw_card is Dictionary and String((raw_card as Dictionary).get("card_type", "")) == "随从":
			minions.append(raw_card as Dictionary)
	_expect(minions.size() == 21, "灰烬证册保留全部21张随从记录")
	var active_count := 0
	var active_effect_count := 0
	for card_record: Dictionary in minions:
		var path := String(card_record.get("resource_path", ""))
		var card := load(path) as CardData
		_expect(card != null, "真实随从资源可载入：%s" % path.get_file())
		if card == null:
			continue
		var expected_active := String(card_record.get("availability", "")) == "active"
		if expected_active:
			active_count += 1
			active_effect_count += (card_record.get("effects", []) as Array).size()
		_expect(card.id == StringName(card_record.get("card_id", "")), "%s 使用稳定卡牌ID" % card.display_name)
		_expect(card.display_name == String(card_record.get("display_name", "")), "%s 使用已确认显示名" % card.id)
		_expect(card.pack_id == &"ash_ledger", "%s 标记为灰烬证册资源" % card.id)
		_expect(card.is_available == expected_active, "%s 可用状态与数据源一致" % card.id)
		var expected_effect_ids: Array[StringName] = []
		for effect: Dictionary in card_record.get("effects", []):
			expected_effect_ids.append(StringName(effect.get("effect_id", "")))
		_expect(card.effect_ids == expected_effect_ids, "%s 精确绑定原子效果ID" % card.id)
		if expected_active:
			_test_confirmed_stats(card, card_record.get("source_fields", {}))
	_expect(active_count == 20, "20张启用随从进入当前卡池")
	_expect(active_effect_count == 26, "20张启用随从共绑定26条活动效果")
	var priest := load("res://resources/cards/town_priest.tres") as CardData
	_expect(priest != null and not priest.is_available and priest.effect_ids.is_empty(), "城镇牧师保留资源但停用且不补造效果")


func _test_confirmed_stats(card: CardData, source_fields: Dictionary) -> void:
	_expect(card.base_value == int(source_fields.get("建议基础数值", -1)), "%s 使用建议基础数值" % card.id)
	_expect(card.max_health == int(source_fields.get("建议基础生命值", -1)), "%s 使用建议基础生命" % card.id)
	_expect(card.armor == int(source_fields.get("建议基础护甲", -1)), "%s 使用建议基础护甲" % card.id)
	var cooldown_text := String(source_fields.get("建议行动冷却", "0s"))
	_expect(is_equal_approx(card.cooldown_seconds, cooldown_text.trim_suffix("s").to_float()), "%s 使用建议行动冷却" % card.id)
	_expect(card.rarity == _rarity_from_text(String(source_fields.get("品级", "Ⅰ"))), "%s 使用确认品级" % card.id)
	_expect(card.race_type == _race_from_text(String(source_fields.get("子类型/种族", "人类"))), "%s 使用确认种族" % card.id)
	_expect(card.wound_slot_count == int(source_fields.get("伤势槽位", 0)), "%s 保存伤势槽位数据" % card.id)
	_expect(card.emblem_slot_count == int(source_fields.get("徽章槽位", 0)), "%s 保存纹章槽位数据" % card.id)
	var actions: Array = source_fields.get("行动方式", [])
	if actions.size() == 1:
		_expect(card.action_type == _action_from_text(String(actions[0])), "%s 使用确认行动方式" % card.id)


func _test_real_battle_bindings() -> void:
	var controller := BattleControllerScript.new() as BattleController
	root.add_child(controller)
	var anvil := load("res://resources/cards/anvil_margaret.tres") as CardData
	var knight := load("res://resources/cards/heavy_knight.tres") as CardData
	controller.start_battle(
		[_entry(anvil, &"player_front")],
		[_entry(knight, &"enemy_front")],
		24001,
		false
	)
	_expect(controller.effect_runtime.bindings.size() == 3, "正式战斗按真实卡牌ID自动登记三条效果")
	_expect(controller.player_states[0].get_zeal_layers() == -4, "正式战斗开场执行玛格丽特的真实持续热诚效果")
	_expect(
		controller.enemy_states[0].modifiers.get_additive(BattleModifier.Stat.REINFORCEMENT) == 8.0,
		"正式战斗开场执行重装骑士的真实突击"
	)
	controller.queue_free()


func _test_battle_lab_real_effect_bundles(data: Dictionary) -> void:
	var real_option_count := 0
	var real_effect_count := 0
	for raw_card: Variant in data.get("cards", []):
		if not raw_card is Dictionary:
			continue
		var card_record := raw_card as Dictionary
		if String(card_record.get("card_type", "")) != "随从" or String(card_record.get("availability", "")) != "active":
			continue
		var card_id := StringName(card_record.get("card_id", ""))
		var definitions := BattleLabEffectLibrary.create_definitions(card_id)
		real_option_count += 1
		real_effect_count += definitions.size()
		_expect(BattleLabEffectLibrary.get_option_index(card_id) > 0, "战斗实验室提供真实卡选项：%s" % card_id)
	_expect(real_option_count == 20 and real_effect_count == 26, "战斗实验室可选择20张真实随从的26条效果")
	_expect(BattleLabEffectLibrary.get_option_index(&"town_priest") == 0, "战斗实验室不提供停用城镇牧师")


func _test_tide_archer_deferred_hook() -> void:
	var tide_archer := load(TIDE_ARCHER_PATH) as CardData
	var hook: Dictionary = tide_archer.deferred_effect_hooks.get("mining_succeeded", {})
	_expect(tide_archer.pack_id == &"development_test", "潮汐射手明确位于灰烬证册之外")
	_expect(tide_archer.keywords == [&"mining"], "潮汐射手只记录开采关键词")
	_expect(tide_archer.effect_ids.is_empty(), "D2-4不把潮汐射手强化挂到其他战斗触发")
	_expect(
		String(hook.get("operation", "")) == "add_reinforcement"
		and int(hook.get("amount", 0)) == 1
		and String(hook.get("implementation_stage", "")) == "D2-6C",
		"+1强化只关联未来 mining_succeeded 钩子"
	)


func _test_positioning_cards_remain_available() -> void:
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	var main := main_scene.instantiate()
	var cards_by_id: Dictionary = {}
	for card: CardData in main.collection_cards:
		cards_by_id[card.id] = card
	for card_id: StringName in [&"town_priest", &"tide_archer", &"ember_squire", &"spark_mage"]:
		_expect(cards_by_id.has(card_id), "%s 继续保留在收藏站位资源中" % card_id)
	_expect((cards_by_id[&"town_priest"] as CardData).effect_text.is_empty(), "城镇牧师特效栏留空")
	_expect((cards_by_id[&"ember_squire"] as CardData).effect_text.is_empty(), "余烬侍从特效栏留空")
	_expect((cards_by_id[&"spark_mage"] as CardData).effect_text.is_empty(), "星火法师特效栏留空")
	_expect((cards_by_id[&"tide_archer"] as CardData).effect_text == "开采：+1强化", "潮汐射手显示暂不生效的开采特效")
	main.free()


func _test_mudleg_brothers_forbid_stacking() -> void:
	var mudleg := load("res://resources/cards/mudleg_brothers.tres") as CardData
	var militia := load("res://resources/cards/militia.tres") as CardData
	var ember := load("res://resources/cards/ember_squire.tres") as CardData
	_expect(mudleg.has_keyword(&"forbid_stacking"), "泥腿三兄弟保存无法堆叠固有关键词")
	_expect(SquadData.from_card(mudleg).is_valid(), "泥腿三兄弟独立组成单卡小队时合法")
	_expect(
		not SquadData.from_cards([mudleg, militia]).is_valid(),
		"批量工厂也不能伪造包含泥腿三兄弟的多卡小队"
	)
	var ordinary_squad := SquadData.from_card(militia)
	_expect(not ordinary_squad.insert_card(mudleg, 1), "泥腿三兄弟不能堆到普通小队")
	var mudleg_squad := SquadData.from_card(mudleg)
	_expect(not mudleg_squad.insert_card(militia, 1), "普通卡不能堆到泥腿三兄弟所在小队")
	var moved_mudleg := mudleg_squad.duplicate_squad()
	moved_mudleg.remove_card(mudleg)
	_expect(moved_mudleg.insert_card(mudleg, 0), "泥腿三兄弟从原小队抽出后仍可放回空小队")
	var compact_pair := SquadData.from_cards(
		[militia, ember],
		SquadData.TwoCardLayout.COMPACT
	)
	_expect(
		compact_pair.merge_compact_double_with_single(mudleg_squad, false) == null,
		"紧密双卡整队也不能与泥腿三兄弟合并"
	)
	var controller := BattleControllerScript.new() as BattleController
	root.add_child(controller)
	controller.start_battle(
		[_entry(mudleg, &"player_front")],
		[_entry(militia, &"enemy_front")],
		24002,
		false
	)
	var forbid_instance_found := false
	for instance: BattleEffectInstance in controller.effect_runtime.active_instances:
		if instance.definition.effect_id == &"mudleg_brothers.effect.01" and instance.active:
			forbid_instance_found = true
	_expect(forbid_instance_found, "正式战斗登记泥腿三兄弟的无法堆叠持续实例")
	controller.queue_free()


func _entry(card: CardData, row_key: StringName) -> Dictionary:
	return {
		"squad_data": SquadData.from_card(card),
		"row_key": row_key,
		"formation_index": 0,
	}


func _action_from_text(value: String) -> CardData.ActionType:
	return {
		"近战": CardData.ActionType.MELEE,
		"远程": CardData.ActionType.RANGED,
		"魔法": CardData.ActionType.MAGIC,
		"治疗": CardData.ActionType.HEAL,
		"防御": CardData.ActionType.DEFENSE,
	}.get(value, CardData.ActionType.MELEE) as CardData.ActionType


func _race_from_text(value: String) -> CardData.RaceType:
	return {
		"人类": CardData.RaceType.HUMAN,
		"精灵": CardData.RaceType.ELF,
		"矮人": CardData.RaceType.DWARF,
		"元素": CardData.RaceType.ELEMENTAL,
	}.get(value, CardData.RaceType.HUMAN) as CardData.RaceType


func _rarity_from_text(value: String) -> CardData.Rarity:
	return {
		"Ⅰ": CardData.Rarity.I,
		"Ⅱ": CardData.Rarity.II,
		"Ⅲ": CardData.Rarity.III,
		"Ⅳ": CardData.Rarity.IV,
		"Ⅴ": CardData.Rarity.V,
	}.get(value, CardData.Rarity.I) as CardData.Rarity


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
