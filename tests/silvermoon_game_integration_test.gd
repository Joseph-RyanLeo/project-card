extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := MAIN.instantiate()
	main.run_save_path = "/private/tmp/project-card-silvermoon-integration-save.json"
	root.add_child(main)
	await process_frame
	await process_frame
	var registry: Dictionary = main._build_card_definition_registry()
	var silver_count := 0
	for card: CardData in registry.values():
		if card.pack_id == &"silvermoon_chapter": silver_count += 1
	check(silver_count == 37, "主游戏自动注册全部37张")
	check(main._ordinary_shop_offer_icon({"kind": "card_pack", "pack_id": "silvermoon_chapter", "size": "large"}).resource_path.ends_with("silvermoon_large.png"), "银月大包使用包装立绘")
	check(main._ordinary_shop_offer_icon({"kind": "card_pack", "pack_id": "silvermoon_chapter", "size": "small"}).resource_path.ends_with("silvermoon_small.png"), "银月小包使用包装立绘")
	main.ordinary_shop_service.initialize(9010)
	main.ordinary_shop_service.config.allowed_pack_ids = ["silvermoon_chapter"]
	main.ordinary_shop_service.config.temporary_offer_weights.sticker_pack_count = {"0": 1}
	main.ordinary_shop_service.config.action_procurement.enabled = false
	var cards: Array[CardData] = []
	for card: CardData in registry.values(): cards.append(card)
	var no_stickers: Array[Dictionary] = []
	check(main.ordinary_shop_service.refresh(cards, main.owned_card_collection.get_cards(), no_stickers, no_stickers), "主游戏生成银月商品")
	main.run_reward_state.gold = 1000
	var offer: Dictionary = main.ordinary_shop_service.offers[0]
	var previous_count: int = main.owned_card_collection.get_cards().size()
	main._buy_shop_card_pack(0, offer)
	check(main.owned_card_collection.get_cards().size() == previous_count + offer.cards.size(), "实际购买开包添加真实收藏实例")
	check(main.run_reward_state.gold == 1000 - int(offer.price), "开包沿用现有实际报价")
	var recent: Array = main.owned_card_collection.get_cards().slice(previous_count)
	check(recent.all(func(card: OwnedCard) -> bool: return card.card_data.pack_id == &"silvermoon_chapter" and not card.card_data.is_derived), "开包结果全部银月且排除衍生")
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	var dancer: OwnedCard = main.owned_card_collection.create_card(registry[&"moon_dancer"])
	var knight: OwnedCard = main.owned_card_collection.create_card(registry[&"twilight_knight"])
	var enemy: OwnedCard = main.owned_card_collection.create_card(registry[&"baggage_muleteer"])
	main.front_row.add_squad(SquadData.from_owned_card(dancer), 0)
	main.back_row.add_squad(SquadData.from_owned_card(knight), 0)
	main.enemy_front_row.add_squad(SquadData.from_owned_card(enemy), 0)
	check(main.start_battle(9010, false), "主游戏真实银月阵容开始战斗")
	var controller: BattleController = main.battle_controller
	var first: BattleSquadState = controller.player_states[0]
	var second: BattleSquadState = controller.player_states[1]
	check(controller.silvermoon.swap(first, second), "主游戏换位成功")
	await process_frame
	var first_slot: BoardSlot = main._battle_state_slots[first]
	var second_slot: BoardSlot = main._battle_state_slots[second]
	check(first_slot.get_parent() == main.back_row.squad_row and second_slot.get_parent() == main.front_row.squad_row, "真实卡面节点随逻辑跨排换位")
	check(main.save_run_to_path(main.run_save_path) == OK, "银月战斗可保存安全战前状态")
	main.queue_free()
	await process_frame
	await process_frame
	print("银月主游戏集成：%d条断言，%d失败" % [assertions, failures])
	quit(1 if failures > 0 else 0)
