extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const SAVE_PATH := "/private/tmp/project-card-ironwall-integration-save.json"
var failures := 0
var assertions := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures += 1; push_error("FAIL: " + label)
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	main.run_save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	await process_frame
	var registry: Dictionary = main._build_card_definition_registry()
	var count := 0
	for card: CardData in registry.values():
		if card.pack_id == &"ironwall_inscription": count += 1
	check(count == 38, "主游戏注册38张")
	for size: String in ["large", "small"]: check(main._ordinary_shop_offer_icon({"kind": "card_pack", "pack_id": "ironwall_inscription", "size": size}).resource_path.ends_with("ironwall_%s.png" % size), "主游戏包装：" + size)
	main.ordinary_shop_service.initialize(1013)
	main.ordinary_shop_service.config.allowed_pack_ids = ["ironwall_inscription"]
	main.ordinary_shop_service.config.action_procurement.enabled = false
	main.ordinary_shop_service.config.temporary_offer_weights.sticker_pack_count = {"0": 1}
	var cards: Array[CardData] = []
	cards.assign(registry.values())
	var empty: Array[Dictionary] = []
	check(main.ordinary_shop_service.refresh(cards, main.owned_card_collection.get_cards(), empty, empty), "生成铁壁商品")
	if main.ordinary_shop_service.offers.is_empty(): main.queue_free(); quit(1); return
	main.run_reward_state.gold = 1000
	var offer: Dictionary = main.ordinary_shop_service.offers[0]
	var before: int = main.owned_card_collection.size()
	var added: Array[OwnedCard] = main._buy_shop_card_pack(0, offer)
	check(added.size() == offer.cards.size() and main.owned_card_collection.size() >= before + added.size(), "真实开包入收藏")
	check(main.run_reward_state.gold == 1000 - int(offer.price), "实际扣报价")
	for owned: OwnedCard in added: check(owned.card_data.pack_id == &"ironwall_inscription" and not owned.card_data.is_derived, "主题池与衍生隔离")
	var augustus: OwnedCard = main.owned_card_collection.create_card(registry[&"augustus_ironwall"])
	var companion_ids: Array[StringName] = []
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.companion_source_id == augustus.instance_id: companion_ids.append(owned.instance_id)
	check(companion_ids.size() == 2, "主游戏获得专属法术")
	main.prepared_spell_instance_ids.append(companion_ids[0])
	check(main.save_run_to_path(SAVE_PATH) == OK and main.load_run_from_path(SAVE_PATH), "磁盘保存并重载")
	for id: StringName in companion_ids: check(main.owned_card_collection.get_by_instance_id(id).companion_source_id == augustus.instance_id, "存档保留主卡关联")
	main.owned_card_collection.remove_by_instance_id(augustus.instance_id)
	check(not main.prepared_spell_instance_ids.has(companion_ids[0]), "主卡删除自动清理准备栏关联")
	for id: StringName in companion_ids: check(main.owned_card_collection.get_by_instance_id(id) == null, "专属法术同步移除")
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var arno: OwnedCard = main.owned_card_collection.create_card(registry[&"ironhand_arno"])
	var robot: OwnedCard = main.owned_card_collection.create_card(registry[&"sentry_machine"])
	var ally: OwnedCard = main.owned_card_collection.create_card(registry[&"scout"])
	var enemy: OwnedCard = main.owned_card_collection.create_card(registry[&"ironhand_arno"])
	main.front_row.add_squad(SquadData.from_owned_card(arno), 0)
	main.front_row.add_squad(SquadData.from_owned_card(robot), 1)
	main.front_row.add_squad(SquadData.from_owned_card(ally), 2)
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy), 0)
	check(main.start_battle(1013, false), "正式主场景开战")
	var c: BattleController = main.battle_controller
	c.use_projectile_timing = false
	var state := c.player_states[1]
	var slot: BoardSlot = main._battle_state_slots[state]
	state.current_health = 0
	c._finalize_batch()
	await process_frame
	check(state.is_repairing and slot.get_parent() == main.front_row.squad_row and main.front_row.get_squad_count() == 3, "修复卡面保留槽位")
	check(is_equal_approx(slot.modulate.a, 0.4), "修复卡面透明提示")
	c.elapsed_seconds += 1
	c.ironwall.process_due()
	await process_frame
	check(state.alive and slot.modulate.a == 1 and main._battle_state_slots[state] == slot, "修复恢复同一节点")
	check(main.save_run_to_path(SAVE_PATH) == OK, "战斗中保存战前安全状态")
	main.queue_free()
	await process_frame
	await process_frame
	print("铁壁主游戏集成：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
