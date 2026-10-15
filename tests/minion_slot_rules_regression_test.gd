extends SceneTree

## 使用正式卡牌、实例和磁盘存档验证统一槽位与旧规则迁移。
const SaveService = preload("res://scripts/data/run_save_service.gd")
const Layout = preload("res://scripts/data/card_slot_layout.gd")
const Builder = preload("res://scripts/flow/enemy_encounter_builder.gd")
const SAVE_PATH := "/private/tmp/project-card-minion-slot-migration.json"
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error(message)

func legacy_owned(definition: CardData, id: StringName, wounds: int, emblems: int, rune_count: int = 3) -> OwnedCard:
	var old := definition.duplicate(true) as CardData
	old.wound_slot_count = wounds
	old.emblem_slot_count = emblems
	old.runes.resize(rune_count)
	var owned := OwnedCard.new()
	owned.initialize(old, id, 0)
	return owned

func _run() -> void:
	var registry: Dictionary = {}
	var minion_count := 0
	for path: String in CardArtTuner.discover_card_resource_paths():
		var definition := load(path) as CardData
		registry[definition.id] = definition
		if definition.card_type != CardData.CardType.MINION: continue
		minion_count += 1
		var expected: int = [2, 2, 3, 4, 4][definition.rarity]
		check(definition.runes.size() == 3, "%s固定3符文槽" % definition.display_name)
		check(Layout.resolve_counts(definition) == Vector2i(expected, expected), "%s伤势／纹章按品级" % definition.display_name)
		var owned := OwnedCard.new()
		owned.initialize(definition, &"catalog_probe", 0)
		check(owned.wound_slots.size() == expected and owned.emblem_slots.size() == expected and Layout.is_valid_layout(definition, owned.slot_layout), "%s真实获得布局合法" % definition.display_name)
	print("检查%d张正式及开发随从资源" % minion_count)
	var ore: CardData = registry[&"ore_appraiser"]
	var twilight: CardData = registry[&"twilight_elemental"]
	var v := CardData.new()
	v.id = &"slot_v_probe"
	v.rarity = CardData.Rarity.V
	v.runes.assign([0, 1, 2])
	registry[v.id] = v
	var miner := legacy_owned(ore, &"legacy_miner", 3, 1, 2)
	miner.resolved_runes.assign([4, 1])
	miner.rune_revealed[0] = true
	miner.record_rune_scrape_pixels(1, [Vector2i(11, 11)])
	miner.rune_stickers[1] = {"emblem_id": "火元素", "element": 0, "instance_id": "old_element"}
	miner.wound_slots[2] = {"wound_id": &"中毒Ⅰ", "level": 1}
	miner.emblem_slots[0] = {"emblem_id": &"种子", "instance_id": &"old_seed"}
	miner.progress_by_source[&"old_seed"] = 2
	miner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 2)
	var old_mask := miner.rune_scrape_masks[1]
	var elemental := legacy_owned(twilight, &"legacy_elemental", 1, 2)
	elemental.wound_slots[0] = {"wound_id": &"中毒Ⅰ", "level": 1}
	var high := legacy_owned(v, &"legacy_v", 3, 5)
	for index: int in high.emblem_slots.size():
		high.emblem_slots[index] = {"emblem_id": &"种子", "instance_id": StringName("v_seed_%d" % index)}
		high.progress_by_source[StringName("v_seed_%d" % index)] = index
	var overcrowded := legacy_owned(ore, &"overflow_wounds", 3, 1, 2)
	for index: int in overcrowded.wound_slots.size():
		overcrowded.wound_slots[index] = {"wound_id": &"中毒Ⅰ", "level": 1}
	var enemy := legacy_owned(ore, &"legacy_enemy", 3, 1, 2)
	enemy.rune_revealed[0] = true
	var rows := {&"player_front": [SquadData.from_owned_card(miner)], &"enemy_front": [SquadData.from_owned_card(enemy)]}
	var service := SaveService.new()
	var state := {"cards": [miner.capture_state(), elemental.capture_state(), high.capture_state(), overcrowded.capture_state()], "next_instance_sequence": 10}
	var checkpoint := service.create_checkpoint(state, rows, 77, &"battle_slot_probe", 2, RunRewardState.new(), RunSettlementJournal.new(), 0)
	checkpoint.schema_version = 8
	checkpoint.status_slot_migration_version = 1
	var before := JSON.stringify(checkpoint)
	check(service.save_checkpoint(SAVE_PATH, checkpoint) == OK, "旧版真实JSON写入磁盘")
	var loaded := service.load_checkpoint(SAVE_PATH)
	check(loaded.success, "旧版真实JSON读回")
	var collection := OwnedCardCollection.new()
	var restored := service.restore_checkpoint(loaded.checkpoint, collection, RunRewardState.new(), RunSettlementJournal.new(), registry)
	check(restored.success, "旧版玩家与敌方存档一同恢复")
	if not restored.success: print(restored); quit(1); return
	var current := collection.get_by_instance_id(&"legacy_miner")
	check(current.wound_slots.size() == 2 and current.emblem_slots.size() == 2 and current.wound_slots[0].wound_id == &"中毒Ⅰ", "超出索引但未超容量的伤势保留并移入合法槽")
	check(current.emblem_slots[0].instance_id == &"old_seed" and current.progress_by_source[&"old_seed"] == 2 and current.get_permanent_growth(OwnedCard.STAT_BASE_VALUE) == 2, "原纹章进度和永久成长保留")
	check(current.resolved_runes.slice(0, 2) == [4, 1] and current.resolved_runes.size() == 3, "原符文保持，新槽只补一次")
	check(current.rune_revealed == [true, false, false] and current.rune_scrape_masks[1] == old_mask and current.rune_scrape_masks[2].is_empty(), "原揭晓与付费擦痕保留，新槽未揭晓")
	check(current.rune_stickers[1].instance_id == "old_element" and current.rune_stickers[2].is_empty(), "原元素贴纸保留")
	var current_elemental := collection.get_by_instance_id(&"legacy_elemental")
	check(current_elemental.wound_slots.size() == 2 and not current_elemental.wound_slots[0].is_empty() and current_elemental.wound_slots[1].is_empty(), "晨昏元素旧实例补齐第二伤势槽")
	var current_v := collection.get_by_instance_id(&"legacy_v")
	check(current_v.wound_slots.size() == 4 and current_v.emblem_slots.size() == 4 and current_v.progress_by_source.is_empty(), "V级调整到4／4，超额纹章按既有规则整卡返还")
	var returns: Array = restored.slot_migration_returns
	check(returns.size() == 8, "5枚超额纹章和3处超额伤势进入返还清单")
	check(returns[4].state.saved_progress == 4 and returns[4].state.instance_id == &"v_seed_4", "返还纹章保留身份和成长进度")
	var restored_enemy: OwnedCard = restored.rows[&"enemy_front"][0].get_action_source_instance()
	check(restored_enemy.rune_revealed == [true, false, false] and restored_enemy.wound_slots.size() == 2 and restored_enemy.emblem_slots.size() == 2, "敌方独立集合同步迁移")
	var repeated := OwnedCardCollection.new()
	check(service.restore_checkpoint(loaded.checkpoint, repeated, RunRewardState.new(), RunSettlementJournal.new(), registry).success and repeated.get_by_instance_id(&"legacy_miner").resolved_runes == current.resolved_runes, "重复载入新符文固定不重抽")
	check(JSON.stringify(checkpoint) == before, "迁移不修改输入快照")
	var updated := service.create_checkpoint(collection.capture_state(), restored.rows, 77, &"battle_slot_probe", 2, RunRewardState.new(), RunSettlementJournal.new(), 0)
	check(service.save_checkpoint(SAVE_PATH, updated) == OK, "迁移后保存新版磁盘文件")
	var current_disk := service.load_checkpoint(SAVE_PATH).checkpoint as Dictionary
	var reloaded := OwnedCardCollection.new()
	var reload_result := service.restore_checkpoint(current_disk, reloaded, RunRewardState.new(), RunSettlementJournal.new(), registry)
	var reloaded_state := reloaded.get_by_instance_id(&"legacy_miner").capture_state() if reload_result.success else {}
	# 磁盘保存可变数据，不保存OwnedCard自身的内存地址。
	check(reload_result.success and service._encode_collection_state({"cards": [reloaded_state]}) == service._encode_collection_state({"cards": [current.capture_state()]}), "新版磁盘再次载入完整保留实例状态")
	var legacy_encounter := {"collection": service._encode_collection_state({"cards": [enemy.capture_state()]}), "rows": service._encode_rows({&"enemy_front": [SquadData.from_owned_card(enemy)]}), "spell_ids": []}
	var encounter := Builder.new().restore(legacy_encounter, registry)
	check(not encounter.is_empty() and encounter.rows[&"enemy_front"][0].get_action_source_instance().resolved_runes.size() == 3, "路径内旧遭遇快照可以部署")
	check(Builder.new().restore(encounter.snapshot, registry).snapshot == encounter.snapshot, "遭遇迁移标记与状态保存后保持稳定")
	var invalid := updated.duplicate(true)
	invalid.collection.cards[0].resolved_runes.pop_back()
	check(not service.restore_checkpoint(invalid, OwnedCardCollection.new(), RunRewardState.new(), RunSettlementJournal.new(), registry).success, "新版长度损坏仍拒绝载入")
	invalid = loaded.checkpoint.duplicate(true)
	invalid.collection.cards[0].rune_stickers.pop_back()
	check(not service.restore_checkpoint(invalid, OwnedCardCollection.new(), RunRewardState.new(), RunSettlementJournal.new(), registry).success, "旧版不一致长度仍拒绝载入")
	print("随从槽位专项：%d项，%d失败" % [assertions, failures])
	quit(failures)
