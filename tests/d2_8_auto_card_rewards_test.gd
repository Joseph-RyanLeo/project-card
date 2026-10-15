extends SceneTree

## 两本征兵册通过真实胜利与正式结算，自动发卡并验证重复提交／存档。
var main: Control
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("自动卡牌奖励专项超时"); quit(1))
	main = preload("res://scenes/Main.tscn").instantiate()
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-auto-card-rewards.json"
	root.add_child(main)
	await process_frame
	main.front_row.clear_squads()
	main.back_row.clear_squads()
	main.enemy_front_row.clear_squads()
	main.enemy_back_row.clear_squads()
	main.resource_board_state.clear_level_resources()
	var ledger_ids: Array[StringName] = []
	for index: int in 2:
		var host: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/musketeer.tres"))
		host.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 80)
		host.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 100)
		var ledger: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/recruitment_ledger.tres"))
		ledger_ids.append(ledger.instance_id)
		var squad := SquadData.from_owned_card(host)
		check(squad.equip_item(ledger), "真实征兵册装备到随从")
		main.front_row.add_squad(squad, index)
	var enemy := CardData.new()
	enemy.id = &"auto_reward_enemy"
	enemy.is_available = false
	enemy.display_name = "奖励验收敌人"
	enemy.max_health = 1
	enemy.base_value = 0
	enemy.cooldown_seconds = 99
	main.enemy_front_row.add_squad(SquadData.from_card(enemy), 0)
	var before: int = main.owned_card_collection.size()
	var rng_before: int = main.ordinary_shop_service.rng.state
	check(main.start_battle(51005, false), "正式开战")
	check(main.owned_card_collection.size() == before and main.run_reward_state.pending_random_card_requests.is_empty(), "战斗中不提前发卡或消耗征兵册")
	for index: int in 100:
		if main.battle_controller.current_result != BattleController.Result.NONE: break
		main.battle_controller.resolve_next_batch()
	check(main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY, "真实战斗获得胜利")
	if main.current_phase != main.GamePhase.RESULT: main._show_battle_result(main.battle_controller.current_result)
	check(main._last_battle_settlement_result.success and main._last_battle_settlement_result.get("random_card_names", []).size() == 4, "两本征兵册四张奖励在结算事务中解析")
	check(main.owned_card_collection.size() == before + 2 and main.run_reward_state.pending_random_card_requests.is_empty(), "销毁两本征兵册并自动加入四张卡，没有商店待领取奖励")
	check(ledger_ids.all(func(id: StringName): return main.owned_card_collection.get_by_instance_id(id) == null), "征兵册只在正常胜利结算消耗")
	check(main.ordinary_shop_service.rng.state != rng_before and main.battle_result_summary_label.text.contains("已加入收藏"), "发卡使用持久随机流并在结算显示卡名")
	var after: int = main.owned_card_collection.size()
	var after_rng: int = main.ordinary_shop_service.rng.state
	check(main.settle_current_battle().status == BattleSettlementService.STATUS_ALREADY_COMMITTED and main.owned_card_collection.size() == after and main.ordinary_shop_service.rng.state == after_rng, "重复结算不再次发卡或消耗随机数")
	check(main.load_run_from_path(main.run_save_path) and main.owned_card_collection.size() == after and main.run_reward_state.pending_random_card_requests.is_empty(), "磁盘读回保持已到账卡牌且不重复领取")
	# 原奖励筛选失败必须保持集合与随机流。
	main.run_reward_state.pending_next_level_from_id = &""
	check(main.run_reward_state.enqueue_random_card_request({"entry_id": &"missing_candidate_request", "battle_instance_id": &"no_candidate", "event_id": 51, "side": BattleSquadState.Side.PLAYER, "kind": BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST, "amount": 1, "parameters": {"pack_id": "missing_pack", "card_type": "minion"}}), "登记真实无候选请求")
	var unresolved: int = main.run_reward_state.pending_random_card_requests.size()
	after_rng = main.ordinary_shop_service.rng.state
	var invalid: Dictionary = main._resolve_pending_random_cards()
	check(not invalid.success and main.owned_card_collection.size() == after and main.ordinary_shop_service.rng.state == after_rng and main.run_reward_state.pending_random_card_requests.size() == unresolved, "无合法候选时奖励与随机流不丢失")
	check(main.start_battle(51006, false), "失败回退验收使用新的正式战前快照")
	var rejected: Dictionary = main.settle_current_battle()
	check(not rejected.success and not main.settlement_journal.is_committed(main._battle_snapshot.battle_instance_id) and main.owned_card_collection.size() == after and main.ordinary_shop_service.rng.state == after_rng and main.run_reward_state.pending_random_card_requests.size() == unresolved, "自动解析失败回退整个结算且不标记提交")
	main.queue_free()
	await process_frame
	print("自动卡牌奖励：%d断言，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
