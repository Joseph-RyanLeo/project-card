class_name ShortMazeController
extends Node

## 一局迷宫的协调器：复用Main的收藏、商店、资源板与战斗，不复制这些系统。
const EncounterBuilder = preload("res://scripts/flow/enemy_encounter_builder.gd")
const RunState = preload("res://scripts/data/short_maze_run_state.gd")
const Progress = preload("res://scripts/data/hero_progress_state.gd")
const Rewards = preload("res://scripts/data/maze_reward_service.gd")
const Sentry = preload("res://scripts/data/sentry_indicator.gd")
const HeroRuntime = preload("res://scripts/battle/battle_hero_runtime.gd")
const SentryView = preload("res://scripts/ui/sentry_indicator_view.gd")
const EventTable = preload("res://scripts/ui/event_card_table.gd")
const StoryEvents = preload("res://scripts/data/maze_story_event_service.gd")
const CardServiceSlot = preload("res://scripts/ui/card_service_slot.gd")
const TEXT_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const SentryStyle = preload("res://scripts/ui/sentry_indicator_style.gd")
const SENTRY_MOVE_SECONDS: float = 0.30 # 哨位从鼠标落点移动到区域角落的时长
const PANEL_POSITION := Vector2(189, 0) # 普通事件与上半世界共用原稿顶边
const PANEL_SIZE := Vector2(902, 351) # 新事件棋盘原生尺寸
var run := RunState.new()
var hero := Progress.new()
var rewards := Rewards.new()
var story_events := StoryEvents.new()
var _event_table: Control
var _detail_body: VBoxContainer
var _last_dealt_key: String = ""
var _reveal_selected_event: bool = false
var content: Dictionary = {}
var stock: Array[Dictionary] = []
var deployed: Array[Dictionary] = []
var seen_events: Array[String] = []
var fortify_complete: bool = false
var last_reward: Dictionary = {}
var next_sentry_id: int = 1
var _main: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _status: Control
var _enhancement_slot: Control
var _enhancement_card_id: StringName = &""
var _enhancement_options: VBoxContainer
var _sentry_bar: Control
var _sentry_zones: Dictionary = {}
var _before_battle: Dictionary = {}
var _before_battle_gold: int = 0
var _sentry_views: Dictionary = {}


func initialize(main: Control) -> bool:
	_main = main
	if not rewards.load_config() or not story_events.load_config():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/short_maze_content.json"))
	if not parsed is Dictionary:
		return false
	content = parsed
	content.free_events.append_array(story_events.config.events.duplicate(true))
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	if not hero.initialize(thresholds, rewards.config.talent_choices):
		return false
	_build_ui()
	return true


func new_run(seed_value: int) -> void:
	_main._close_shop_card_services()
	_main._return_service_cards()
	_enhancement_card_id = &""
	run.initialize(seed_value)
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	hero.initialize(thresholds, rewards.config.talent_choices)
	stock.clear()
	deployed.clear()
	seen_events.clear()
	_last_dealt_key = ""
	fortify_complete = false
	last_reward.clear()
	next_sentry_id = 1
	_before_battle.clear()
	_main._cancel_click_carry()
	_main._close_card_inspection(true)
	_main.battle_controller.clear_battle()
	_main._record_run_diagnostic("new_run_battle_cleared", {}, true)
	_main._battle_snapshot = null
	_main._last_battle_settlement_result.clear()
	_main._resume_battle_instance_id = &""
	_main._next_battle_instance_sequence = 1
	_main.settlement_journal = RunSettlementJournal.new()
	_main.prepared_spell_instance_ids.clear()
	_main.recently_returned_cards.clear()
	_main.recently_returned_owned_cards.clear()
	_main.collection_bookmark_active = false
	_main.current_collection_page = 0
	_main.emblem_library.restore_inventory_state([])
	_main.scraper_count = int(_main.ordinary_shop_service.config.scraper.starting_count)
	_main.emblem_library.set_scraper_count(_main.scraper_count)
	_main.celestial_indicators.restore_state({})
	_main.ordinary_shop_service.initialize(seed_value)
	_main.ordinary_shop_open = false
	_main.ordinary_shop_panel.visible = false
	_main._last_chaos_reroll_day_token = &""
	_main.current_phase = _main.GamePhase.PREPARE
	_main.battle_result_panel.visible = false
	_main._clear_battle_log()
	_main.owned_card_collection = OwnedCardCollection.new()
	var registry: Dictionary = _main._build_card_definition_registry()
	for id: String in rewards.config.initial_card_ids:
		_main.owned_card_collection.create_card(registry[StringName(id)], run.rng)
	_main.run_reward_state = RunRewardState.new()
	_main.run_reward_state.gold = int(rewards.config.initial_gold)
	for row: BattlefieldRow in [_main.front_row, _main.back_row, _main.enemy_front_row, _main.enemy_back_row]:
		row.clear_squads()
	_main.start_new_resource_level(&"level_000001", run.rng)
	_main._sync_legacy_collection_cards()
	_main._build_collection_cards()
	_main._update_phase_label()
	_main.set_world_view(_main.WorldView.BATTLEFIELDS, false)
	refresh()


func _inventory_limit() -> int:
	return int(rewards.config.talents.sentry_alchemy.confirmed_rules.inventory_limit) if hero.has_talent("sentry_alchemy") else int(rewards.config.sentry.inventory_limit)


func _add_sentry() -> void:
	if stock.size() >= _inventory_limit():
		return
	var sentry := Sentry.new()
	sentry.initialize(StringName("sentry_%06d" % next_sentry_id), run.rng)
	next_sentry_id += 1
	stock.append(sentry.capture_state())


func _begin_day() -> void:
	if run.step != RunState.Step.DAY_START or not hero.pending_talent_levels.is_empty():
		return
	for index: int in int(rewards.config.sentry.daily_count):
		_add_sentry()
	_main.reroll_chaos_stickers_for_new_day(StringName("maze_day_%d" % run.day), run.rng)
	run.commit_day_start()
	_generate_paths()


func _generate_paths() -> void:
	if run.step != RunState.Step.CHOOSING or not run.paths.is_empty():
		return
	var candidates: Array[Dictionary] = []
	match run.get_round_kind():
		"shop": candidates.assign(content.shops.duplicate(true))
		"battle":
			for enemy: Dictionary in content.enemies:
				if run.day >= int(enemy.first_day) and run.day <= int(enemy.last_day):
					candidates.append(enemy.duplicate(true))
		_:
			var pool: Array = content.free_events if run.get_round_kind() == "free_event" else content.paid_events
			var unseen: Array[Dictionary] = []
			var visited: Array[Dictionary] = []
			for event: Dictionary in pool:
				if event.get("reward") == "story" and not story_events.can_appear(event, _main.run_reward_state.gold, int(content.get("floor", 1)), "ioann_warden"):
					continue
				(visited if String(event.path_id) in seen_events else unseen).append(event.duplicate(true))
			while candidates.size() < 3:
				var available: Array[Dictionary] = unseen if not unseen.is_empty() else visited
				var index := run.rng.randi_range(0, available.size() - 1)
				candidates.append(available.pop_at(index))
	# 所有路径（含商店／敌人）的显示次序使用本局随机源，选择后保存，不在刷新时重抽。
	var shuffled: Array[Dictionary] = []
	while not candidates.is_empty():
		shuffled.append(candidates.pop_at(run.rng.randi_range(0, candidates.size() - 1)))
	for path: Dictionary in shuffled:
		if path.kind == "battle":
			path["battle_seed"] = run.rng.randi_range(0, _main.BATTLE_SEED_MAX)
	run.set_paths(shuffled)


func choose_talent(id: String) -> bool:
	var previous := _capture_transaction()
	if not hero.choose_talent(id):
		return false
	if id == "sentry_alchemy":
		for index: int in int(rewards.config.talents.sentry_alchemy.confirmed_rules.immediate_count):
			_add_sentry()
	_begin_day()
	return _commit_transaction(previous)


func select_path(id: String) -> bool:
	var previous := _capture_transaction()
	_enhancement_card_id = &""
	if not hero.pending_talent_levels.is_empty() or not run.select_path(id):
		return false
	if run.round_index == 0:
		for pack: Dictionary in run.get_pending_start_packs():
			if not _grant_pack(pack.size == "large"):
				_rollback_transaction(previous)
				return false
		if not run.get_pending_start_packs().is_empty():
			run.commit_start_packs()
	if run.get_round_kind() == "shop":
		_main.ordinary_shop_service.refresh_count = 0
		_main.ordinary_shop_service.initialize(run.rng.randi())
		if not _main._generate_ordinary_shop(false):
			_rollback_transaction(previous)
			return false
	elif run.get_round_kind() == "battle":
		if not _build_enemy():
			_rollback_transaction(previous)
			_main.play_area_label.text = "敌方遭遇配置无效或资源板没有合法空间，尚未选择路径。"
			return false
	else:
		if id not in seen_events:
			seen_events.append(id)
	if not _commit_transaction(previous):
		return false
	if run.get_round_kind() == "shop":
		enter_selected_shop()
	return true


func enter_selected_shop() -> void:
	if run.step == RunState.Step.EVENT and run.get_round_kind() == "shop" and not _main.ordinary_shop_open:
		_main._toggle_ordinary_shop()
		_main.ordinary_shop_status.text = shop_entry_message()


func _grant_pack(large: bool) -> bool:
	var candidates: Array[CardData] = _main.ordinary_shop_service._eligible_cards(_main._get_shop_card_definitions(), _main.owned_card_collection.get_cards())
	var result: Dictionary = _main.ordinary_shop_service.draw_card_pack(candidates, large, 5 if large else 3, run.rng, _main.owned_card_collection.get_cards())
	if not bool(result.get("success", false)):
		return false
	for card: CardData in result.cards:
		_main.owned_card_collection.create_card(card, run.rng, result.cards)
	return true


func _grant_emblem(id: String, receipt: String) -> void:
	var state := {"instance_id": receipt, "emblem_id": id, "temporary": false, "source": "maze_reward"}
	_main.emblem_library.receive_stickers([state])


func complete_event(take_reward: bool = true, discard_confirmed: bool = false) -> bool:
	if run.step != RunState.Step.EVENT or run.get_round_kind() == "shop" or (take_reward and run.selected_path.get("reward") in ["enhance_card", "story"] and not run.selected_path.has("story_result") and not run.selected_path.has("enhancement_result")):
		return false
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(complete_event.bind(take_reward, true)): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	var event: Dictionary = run.selected_path
	var cost := int(event.get("cost", 0))
	if take_reward and not bool(event.get("reward_claimed", false)):
		if _main.run_reward_state.gold < cost:
			_rollback_transaction(previous)
			return false
		_main.run_reward_state.gold -= cost
		var receipt := "maze_event:%d:%s" % [run.day, event.path_id]
		match String(event.reward):
			"gold": _main.run_reward_state.add_gold(int(event.amount))
			"emblem":
				var pool := EmblemLibraryData.get_basic_emblem_ids()
				_grant_emblem(String(pool[run.rng.randi_range(0, pool.size() - 1)]), receipt)
			"wound":
				if not bool(rewards.apply_random_event_wound(receipt, _main.owned_card_collection.get_cards(), run.rng).get("success", false)):
					_rollback_transaction(previous)
					return false
			"pack":
				if not _grant_pack(false):
					_rollback_transaction(previous)
					return false
			"minion":
				var pool: Array[CardData] = []
				for card: CardData in _main.ordinary_shop_service._eligible_cards(_main._get_shop_card_definitions(), _main.owned_card_collection.get_cards()):
					if card.rarity == CardData.Rarity.I and card.card_type == CardData.CardType.MINION:
						pool.append(card)
				if not pool.is_empty():
					_main.owned_card_collection.create_card(_main.ordinary_shop_service.draw_card_candidate(pool, run.rng, _main.ordinary_shop_service.count_owned_cards(_main.owned_card_collection.get_cards())), run.rng)
		if _main.emblem_library.has_dropped_stickers():
			run.selected_path["reward_claimed"] = true
			var committed := _commit_transaction(previous)
			if committed: _main._open_toolbox_inspection()
			return committed
	if not run.complete_event():
		_rollback_transaction(previous)
		return false
	_generate_paths()
	return _commit_transaction(previous)


func choose_story_option(index: int) -> bool:
	var event: Dictionary = run.selected_path
	if run.step != RunState.Step.EVENT or event.get("reward") != "story" or event.has("story_result") or index < 0 or index >= event.options.size():
		return false
	var option: Dictionary = event.options[index]
	if not story_events.blocked_reason(option, _main.run_reward_state.gold).is_empty():
		return false
	var previous := _capture_transaction()
	var result := story_events.draw_outcome(option, run.rng)
	if result.is_empty():
		_rollback_transaction(previous)
		return false
	result["option_index"] = index
	var outcome: Dictionary = option.outcomes[int(result.outcome_index)]
	_main.run_reward_state.gold -= int(option.cost)
	_main.run_reward_state.add_gold(int(outcome.get("gold", 0)))
	var receipt := "maze_story:%d:%s" % [run.day, event.path_id]
	if outcome.has("sticker"):
		_grant_emblem(String(outcome.sticker), receipt)
	if outcome.has("indicator"):
		var inventory: Dictionary = _main.celestial_indicators.capture_state()
		inventory.items.append({"instance_id": receipt, "kind": CelestialIndicator.Kind[String(outcome.indicator)], "star_transfer_count": 0})
		_main.celestial_indicators.restore_state(inventory)
	run.selected_path["story_result"] = result
	run.selected_path["reward_claimed"] = true
	var committed := _commit_transaction(previous)
	if committed and _main.emblem_library.has_dropped_stickers():
		_main._open_toolbox_inspection()
	return committed


func leave_shop(discard_confirmed: bool = false) -> bool:
	if run.step != RunState.Step.EVENT or run.get_round_kind() != "shop":
		return false
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(_main._toggle_ordinary_shop.bind(true)): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	if not run.complete_event():
		_rollback_transaction(previous)
		return false
	_generate_paths()
	return _commit_transaction(previous)


func _enemy_revealed_count() -> int:
	var floor_key := str(int(content.get("floor", 1)))
	return clampi(int(content.get("enemy_rune_reveals_by_floor", {}).get(floor_key, 1)), 0, 3)


func _enemy_emblem_count() -> int:
	var counts: Array = content.get("enemy_emblems_by_day", [])
	return maxi(int(counts[clampi(run.day - 1, 0, counts.size() - 1)]), 0) if not counts.is_empty() else 0


func _build_enemy() -> bool:
	var registry: Dictionary = _main._build_card_definition_registry()
	var builder := EncounterBuilder.new()
	if not run.selected_path.has("encounter_state"):
		var generated := builder.build(run.selected_path, registry, _enemy_revealed_count(), _enemy_emblem_count())
		if generated.is_empty(): return false
		var rng := RandomNumberGenerator.new()
		rng.seed = int(run.selected_path.battle_seed) ^ 0x5EED
		for id: String in run.selected_path.get("resources", []):
			var definition: CardData = registry.get(StringName(id))
			if definition == null or definition.card_type != CardData.CardType.RESOURCE: return false
			var owned := OwnedCard.new()
			owned.initialize(definition, StringName("encounter_resource_%04d" % (_main.resource_board_state.level_resource_cards.enemy.size() + 1)), 0, rng)
			var placed := false
			for anchor: Vector2i in ResourceHexLayout.valid_cells():
				if _main.resource_board_state.deploy_level_resource("enemy", owned, anchor):
					placed = true
					break
			if not placed: return false
		run.selected_path["encounter_state"] = generated
	var encounter := builder.restore(run.selected_path.encounter_state, registry)
	if encounter.is_empty(): return false
	for pair: Array in [[_main.enemy_front_row, &"enemy_front"], [_main.enemy_back_row, &"enemy_back"]]:
		_main._restore_row_from_snapshot(pair[0], encounter.rows[pair[1]])
		pair[0].set_drag_enabled(false)
	_main._refresh_resource_preparation_trays()
	_main.battle_seed_spin.value = int(run.selected_path.battle_seed)
	return true


func get_enemy_prepared_spells() -> Array[OwnedCard]:
	if not run.selected_path.has("encounter_state"): return []
	var encounter := EncounterBuilder.new().restore(run.selected_path.encounter_state, _main._build_card_definition_registry())
	return encounter.get("spells", [])


func deploy_sentry(id: String, region: String) -> bool:
	if _main.current_phase != _main.GamePhase.PREPARE or run.step in [RunState.Step.BATTLE_RESULT, RunState.Step.ENDED] or region not in ["front", "back", "spells"]:
		return false
	for existing: Dictionary in deployed:
		if existing.region == region:
			return false
	for sentry: Dictionary in stock:
		if sentry.instance_id == id:
			var previous := _capture_transaction()
			stock.erase(sentry)
			var capacity := int(rewards.config.sentry.capacity_base) + hero.level * int(rewards.config.sentry.capacity_per_hero_level)
			capacity += int(rewards.config.talents.sentry_fortify.confirmed_rules.extra_capacity) if fortify_complete else 0
			capacity += int(rewards.config.talents.sentry_needle.confirmed_rules.extra_capacity) if hero.has_talent("sentry_needle") else 0
			var placement := sentry.duplicate(true)
			placement.merge({"region": region, "capacity": capacity, "remaining": capacity, "deployed_level": hero.level})
			deployed.append(placement)
			return _commit_transaction(previous)
	return false


func recall_sentry(region: String) -> bool:
	if _main.current_phase != _main.GamePhase.PREPARE or stock.size() >= _inventory_limit() or run.step in [RunState.Step.BATTLE_RESULT, RunState.Step.ENDED]:
		return false
	for sentry: Dictionary in deployed:
		if sentry.region == region:
			var previous := _capture_transaction()
			var inventory_state := {"instance_id": sentry.instance_id, "visual_variant": sentry.visual_variant}
			if sentry.has("stock_position"):
				inventory_state["stock_position"] = sentry.stock_position
			stock.append(inventory_state)
			deployed.erase(sentry)
			return _commit_transaction(previous)
	return false


func can_start_battle() -> bool:
	return run.step == RunState.Step.BATTLE_PREPARE and hero.pending_talent_levels.is_empty()


func begin_battle() -> bool:
	if not can_start_battle():
		return false
	_before_battle = capture_state()
	_before_battle_gold = _main.run_reward_state.gold
	run.start_battle()
	return true


func award_opening_gold() -> void:
	if hero.has_talent("sentry_alchemy"):
		_main.run_reward_state.add_gold(deployed.size() * int(rewards.config.talents.sentry_alchemy.confirmed_rules.gold_per_deployed_sentry))


func battle_context() -> Dictionary:
	return {"level": hero.level, "talents": hero.selected_talents.values(), "sentries": deployed.duplicate(true), "fortify_complete": fortify_complete, "rules": rewards.config}


func rollback_battle() -> void:
	if _before_battle.is_empty():
		return
	restore_state(_before_battle)
	_main.run_reward_state.gold = _before_battle_gold
	refresh()


func settle_battle(won: bool, battle_id: String, runtime: HeroRuntime) -> bool:
	if run.step == RunState.Step.BATTLE_RESULT:
		return true
	if run.step != RunState.Step.BATTLE_ACTIVE:
		return false
	last_reward = rewards.build_battle_reward(1, won, run.rng)
	if not bool(last_reward.get("success", false)):
		return false
	_main.run_reward_state.add_gold(int(last_reward.gold))
	var drop: Dictionary = last_reward.drop
	match String(drop.get("kind", "")):
		"scraper":
			_main.scraper_count += 1
			_main.emblem_library.set_scraper_count(_main.scraper_count)
		"emblem": _grant_emblem(String(drop.emblem_id), "maze_battle:%s" % battle_id)
	hero.grant_experience(battle_id, int(last_reward.experience))
	if runtime != null:
		last_reward["spell_cards"] = runtime.spell_awards.duplicate()
		var registry: Dictionary = _main._build_card_definition_registry()
		for card_id: String in runtime.spell_awards:
			_main.owned_card_collection.create_card(registry[StringName(card_id)], run.rng)
		if won and runtime.fortify_eligible:
			fortify_complete = true
			last_reward["fortify_completed"] = true
	deployed.clear() # 正常战后全数消费；未投入的库存保留。清理不触发锐。
	run.settle_battle(won)
	_main._sync_legacy_collection_cards()
	_main._build_collection_cards()
	refresh()
	return true


func continue_after_battle(discard_confirmed: bool = false) -> bool:
	_main._record_run_diagnostic("next_day_requested", {}, true)
	if run.step != RunState.Step.BATTLE_RESULT or not hero.pending_talent_levels.is_empty():
		return false
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(continue_after_battle.bind(true)): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	if not run.continue_after_battle():
		_rollback_transaction(previous)
		return false
	if run.step != RunState.Step.ENDED:
		if not _main.start_new_resource_level(StringName("level_%06d" % run.day), run.rng):
			_rollback_transaction(previous)
			return false
	_main.run_reward_state.pending_next_level_from_id = &""
	_main.battle_controller.clear_battle()
	_main._record_run_diagnostic("next_day_battle_cleared", {}, true)
	_main._battle_snapshot = null
	_main._last_battle_settlement_result.clear()
	_main._clear_battle_presentation_for_preparation()
	_main._clear_battle_log()
	_main.current_phase = _main.GamePhase.PREPARE
	_main.battle_result_panel.visible = false
	_begin_day()
	_main._update_phase_label()
	return _commit_transaction(previous)


func capture_state(before_battle: bool = false) -> Dictionary:
	if before_battle and not _before_battle.is_empty():
		return _before_battle.duplicate(true)
	return {"state_version": 1, "run": run.capture_state(), "hero": hero.capture_state(), "stock": stock.duplicate(true), "deployed": deployed.duplicate(true), "seen_events": seen_events.duplicate(), "fortify_complete": fortify_complete, "last_reward": last_reward.duplicate(true), "next_sentry_id": next_sentry_id}


func validate_state(snapshot: Dictionary) -> bool:
	var candidate_run := RunState.new()
	var candidate_hero := Progress.new()
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	candidate_hero.initialize(thresholds, rewards.config.talent_choices)
	if int(snapshot.get("state_version", 0)) != 1 or not snapshot.get("run") is Dictionary or not snapshot.get("hero") is Dictionary or not candidate_run.restore_state(snapshot.run) or not candidate_hero.restore_state(snapshot.hero) or candidate_hero.level > 4:
		return false
	if not snapshot.get("stock") is Array or not snapshot.get("deployed") is Array or not snapshot.get("seen_events") is Array or not snapshot.get("fortify_complete") is bool or not snapshot.get("last_reward") is Dictionary:
		return false
	var ids: Array[String] = []
	var regions: Array[String] = []
	var limit := int(rewards.config.talents.sentry_alchemy.confirmed_rules.inventory_limit) if candidate_hero.has_talent("sentry_alchemy") else int(rewards.config.sentry.inventory_limit)
	if snapshot.stock.size() > limit or snapshot.deployed.size() > 3:
		return false
	for sentry: Variant in snapshot.stock + snapshot.deployed:
		if not sentry is Dictionary or Sentry.from_state(sentry) == null or String(sentry.instance_id) in ids:
			return false
		if sentry.has("stock_position"):
			var position_value: Variant = sentry.stock_position
			if not position_value is Array or position_value.size() != 2:
				return false
			for component: Variant in position_value:
				if not (component is float or component is int) or not is_finite(float(component)) or float(component) < 0.0:
					return false
			if float(position_value[0]) > 151.0 or float(position_value[1]) > 146.0:
				return false
		ids.append(String(sentry.instance_id))
	for sentry: Dictionary in snapshot.deployed:
		if sentry.get("region") not in ["front", "back", "spells"] or sentry.region in regions:
			return false
		regions.append(sentry.region)
		if not sentry.get("capacity") is float and not sentry.get("capacity") is int:
			return false
		var minimum_capacity := int(rewards.config.sentry.capacity_base) + int(rewards.config.sentry.capacity_per_hero_level)
		if not run._whole_number(sentry.get("remaining")) or not run._whole_number(sentry.get("deployed_level")) or not run._whole_number(sentry.capacity):
			return false
		if float(sentry.capacity) < minimum_capacity or float(sentry.remaining) != float(sentry.capacity) or int(sentry.deployed_level) not in range(1, candidate_hero.level + 1):
			return false
	var known_events: Array[String] = []
	for event: Dictionary in content.free_events + content.paid_events:
		known_events.append(String(event.path_id))
	var seen: Array[String] = []
	for event: Variant in snapshot.seen_events:
		if not event is String or event not in known_events or event in seen:
			return false
		seen.append(event)
	if snapshot.fortify_complete and not candidate_hero.has_talent("sentry_fortify"):
		return false
	var sequence: Variant = snapshot.get("next_sentry_id")
	if not (sequence is int or sequence is float) or float(sequence) != floor(float(sequence)) or int(sequence) < 1:
		return false
	for id: String in ids:
		if not id.begins_with("sentry_") or not id.trim_prefix("sentry_").is_valid_int() or int(id.trim_prefix("sentry_")) < 1 or int(id.trim_prefix("sentry_")) >= int(sequence):
			return false
	# 路径快照必须来自当前内容池，不能靠损坏存档注入新卡或改变价格。
	var paths: Array = snapshot.run.paths.duplicate(true)
	if not snapshot.run.selected_path.is_empty():
		paths.append(snapshot.run.selected_path)
	var all_paths: Array = content.shops + content.free_events + content.paid_events + content.enemies
	for path: Dictionary in paths:
		var found := false
		for definition: Dictionary in all_paths:
			if definition.path_id != path.path_id:
				continue
			found = true
			for key: String in definition:
				if path.kind == "battle" and key in ["front", "back", "previous_formations", "hint", "spells", "resources"]: continue
				if path.get(key) != definition[key]:
					return false
			if path.kind == "battle":
				var formations: Array = [definition]
				formations.append_array(definition.get("previous_formations", []))
				var valid_formation := false
				for formation: Dictionary in formations:
					if path.get("front") == formation.front and path.get("back") == formation.back and path.get("hint") == formation.get("hint", definition.hint) and path.get("spells", []) == formation.get("spells", []) and path.get("resources", []) == formation.get("resources", []):
						valid_formation = true
				if not valid_formation: return false
			if path.kind == "battle" and (not run._whole_number(path.get("battle_seed")) or int(path.battle_seed) < 0 or int(path.battle_seed) > _main.BATTLE_SEED_MAX or int(snapshot.run.day) < int(definition.first_day) or int(snapshot.run.day) > int(definition.last_day)):
				return false
		if path.has("encounter_state"):
			if not path.encounter_state is Dictionary or EncounterBuilder.new().restore(path.encounter_state, _main._build_card_definition_registry()).is_empty(): return false
		if path.has("story_result") and (path.get("reward") != "story" or not path.story_result is Dictionary or not story_events.valid_result(path, path.story_result)):
			return false
		if not found:
			return false
	return true


func restore_state(snapshot: Dictionary) -> bool:
	if not validate_state(snapshot):
		return false
	run.restore_state(snapshot.run)
	_enhancement_card_id = StringName(run.selected_path.get("enhancement_result", {}).get("instance_id", ""))
	# 路径内还有一份固定遭遇快照；同步迁移并保存它，避免下次部署恢复旧槽数。
	var saved_paths: Array = run.paths.duplicate()
	if not run.selected_path.is_empty(): saved_paths.append(run.selected_path)
	for path: Dictionary in saved_paths:
		if path.has("encounter_state"):
			var encounter := EncounterBuilder.new().restore(path.encounter_state, _main._build_card_definition_registry())
			path["encounter_state"] = encounter.snapshot
	hero.restore_state(snapshot.hero)
	stock.assign((snapshot.stock as Array).duplicate(true))
	deployed.assign((snapshot.deployed as Array).duplicate(true))
	for sentry: Dictionary in stock + deployed:
		sentry["visual_variant"] = int(sentry["visual_variant"]) # JSON数字读回后恢复外观编号的整数类型，不修改输入快照
	seen_events.assign(snapshot.seen_events)
	fortify_complete = snapshot.fortify_complete
	last_reward = snapshot.last_reward.duplicate(true)
	next_sentry_id = int(snapshot.next_sentry_id)
	if is_instance_valid(_status):
		_status.sync(self, false)
	return true


func restore_ui() -> void:
	if run.step == RunState.Step.BATTLE_RESULT:
		_main.current_phase = _main.GamePhase.RESULT
		_main._last_battle_settlement_result = {"success": true}
		_main.battle_result_label.text = "战斗胜利" if run.battle_results.back().won else "战斗失败"
		_main.battle_result_summary_label.text = reward_summary()
	elif run.step == RunState.Step.BATTLE_PREPARE:
		_build_enemy()
	_main._update_phase_label()
	_main.set_world_view(_main.WorldView.BATTLEFIELDS, false)
	refresh()
	if run.step == RunState.Step.EVENT and run.get_round_kind() == "shop":
		enter_selected_shop()


func reward_summary() -> String:
	var drop: Dictionary = last_reward.get("drop", {})
	var extra := ""
	if drop.get("kind") == "scraper": extra = "\n刮刀+1"
	if drop.get("kind") == "emblem": extra = "\n纹章：%s" % drop.emblem_id
	var registry: Dictionary = _main._build_card_definition_registry()
	for card_id: String in last_reward.get("spell_cards", []):
		extra += "\n咒获得：%s" % (registry[StringName(card_id)] as CardData).display_name
	if bool(last_reward.get("fortify_completed", false)):
		extra += "\n坚固任务已完成"
	return "本场金币+%d\n经验+%d\n等级%d（总经验%d）\n失败保护剩余%d%s" % [int(last_reward.get("gold", 0)), int(last_reward.get("experience", 0)), hero.level, hero.experience, run.failure_protection, extra]


func _capture_transaction() -> Dictionary:
	return {"maze": capture_state(), "cards": _main.owned_card_collection.capture_state(), "reward": _main.run_reward_state.capture_state(), "inventory": _main.emblem_library.get_inventory_state(), "shop": _main.ordinary_shop_service.capture_state(), "resources": _main.resource_board_state.capture_state(), "rows": _main._current_rows_for_save(), "phase": _main.current_phase, "chaos_day": _main._last_chaos_reroll_day_token, "journal": _main.settlement_journal.capture_state(), "celestial": _main.celestial_indicators.capture_state(), "scrapers": _main.scraper_count, "battle_sequence": _main._next_battle_instance_sequence, "settlement": _main._last_battle_settlement_result.duplicate(true), "battle_snapshot": _main._battle_snapshot, "prepared_spells": _main.prepared_spell_instance_ids.duplicate()}


func _rollback_transaction(previous: Dictionary) -> void:
	_main._return_service_cards()
	restore_state(previous.maze)
	_main.owned_card_collection.restore_state(previous.cards)
	_main.run_reward_state.restore_state(previous.reward)
	_main.emblem_library.restore_inventory_state(previous.inventory)
	_main.ordinary_shop_service.initialize(0, previous.shop)
	_main.resource_board_state.restore_state(previous.resources, _main._build_card_definition_registry())
	for pair: Array in [[_main.front_row, &"player_front"], [_main.back_row, &"player_back"], [_main.enemy_front_row, &"enemy_front"], [_main.enemy_back_row, &"enemy_back"]]:
		_main._restore_row_from_snapshot(pair[0], previous.rows[pair[1]])
	_main.current_phase = previous.phase
	_main._last_chaos_reroll_day_token = previous.chaos_day
	_main.settlement_journal.restore_state(previous.journal)
	_main.celestial_indicators.restore_state(previous.celestial)
	_main.scraper_count = previous.scrapers
	_main.emblem_library.set_scraper_count(_main.scraper_count)
	_main._next_battle_instance_sequence = previous.battle_sequence
	_main._last_battle_settlement_result = previous.settlement
	_main._battle_snapshot = previous.battle_snapshot
	_main.prepared_spell_instance_ids.assign(previous.prepared_spells)
	_main.battle_result_panel.visible = _main.current_phase == _main.GamePhase.RESULT
	_refresh_collection()
	refresh()


func _commit_transaction(previous: Dictionary) -> bool:
	_refresh_collection()
	if _main.save_run_to_path(_main.run_save_path) != OK:
		_rollback_transaction(previous)
		_main.play_area_label.text = "保存失败，本次选择与奖励已回退，请重试。"
		return false
	refresh()
	return true


func _refresh_collection() -> void:
	_main._sync_legacy_collection_cards()
	_main._build_collection_cards()
	_main._receive_pending_ground_stickers()
	_main._refresh_preparation_effect_preview.call_deferred()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MazeFlowPanel"
	_panel.theme = Theme.new()
	_panel.theme.default_font = TEXT_FONT
	_panel.position = PANEL_POSITION
	_panel.size = PANEL_SIZE
	_panel.z_index = 2400 # 流程面板覆盖战场图标，位于商店弹层下方
	_panel.z_as_relative = false
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_main.add_child(_panel)
	var panel_host := Control.new()
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(panel_host)
	_body = VBoxContainer.new()
	_body.size = PANEL_SIZE
	_body.add_theme_constant_override("separation", 8) # 天赋或结局说明的垂直间距
	panel_host.add_child(_body)
	_status = preload("res://scripts/ui/maze_run_hud.gd").new()
	_main.world_content.add_child(_status)
	_status.initialize(_main)

	_sentry_bar = Control.new()
	_sentry_bar.theme = _panel.theme
	_sentry_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.celestial_indicators.get_inventory_host().add_child(_sentry_bar)
	_sentry_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for region: String in ["stock", "front", "back", "spells"]:
		# 区域节点只提供边界和图标父节点；输入统一交给指示物控制器。
		var zone := Control.new()
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone.z_index = 400 # 哨位图标显示在区域内卡牌上方
		var host: Control = {"stock": _sentry_bar, "front": _main.front_row, "back": _main.back_row, "spells": _main.spell_preparation_tray}[region]
		host.add_child(zone)
		zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_sentry_zones[region] = zone


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14) # 事件纸面正文按原生像素使用紧凑字号
	label.add_theme_color_override("font_color", Color("513124"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_detail_body if is_instance_valid(_detail_body) else _body).add_child(label)


func _button(text: String, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 13) # 纸面选项使用紧凑字号，长句在可用宽度内换行
	button.tooltip_text = text
	button.pressed.connect(callback)
	(parent if parent != null else (_detail_body if is_instance_valid(_detail_body) else _body)).add_child(button)
	return button


func _input(event: InputEvent) -> void:
	# 天赋确认后立即换成路径按钮；双击的第二次按压不能误选下一屏。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click and is_instance_valid(_panel) and _panel.is_visible_in_tree():
		var local: Vector2 = _panel.get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, _panel.size).has_point(local):
			get_viewport().set_input_as_handled()


func refresh() -> void:
	if not is_instance_valid(_panel):
		return
	_main._sync_tabletop_panel_anchors()
	_update_status()
	_main._refresh_enemy_side_trays()
	var choice_key := "%d:%d:%s" % [run.day, run.round_index, JSON.stringify(run.paths)] if run.step == RunState.Step.CHOOSING else ""
	if is_instance_valid(_event_table) and not choice_key.is_empty() and choice_key == _last_dealt_key and hero.pending_talent_levels.is_empty():
		_panel.visible = not _main.ordinary_shop_open
		_status.visible = not _panel.visible and not _main.ordinary_shop_open
		return
	var preparing: bool = _main.current_phase == _main.GamePhase.PREPARE
	var choosing_talent := not hero.pending_talent_levels.is_empty()
	# 战后先完成升级选择；中央结算页不能同时遮住天赋按钮。
	# 选择提交、保存回退和读档都会经过refresh，统一在此恢复正确界面。
	if _main.current_phase == _main.GamePhase.RESULT:
		_main.battle_result_panel.visible = not choosing_talent and not _main._viewing_result_battlefield
	_main.start_battle_button.visible = preparing and can_start_battle()
	_main.ordinary_shop_entry_button.visible = preparing and run.step == RunState.Step.EVENT and run.get_round_kind() == "shop" and not _main.ordinary_shop_open
	_main.battle_seed_panel.visible = false
	_main.battle_seed_random_button.disabled = true
	_main.battle_seed_spin.get_line_edit().editable = false
	if is_instance_valid(_main.debug_new_shop_button):
		_main.debug_new_shop_button.visible = false
	_main.continue_next_level_button.visible = run.step == RunState.Step.BATTLE_RESULT and not choosing_talent
	_main.continue_next_level_button.text = "结束本局" if not run.battle_results.is_empty() and not String(run.battle_results.back().ending).is_empty() else "进入下一天"
	_main.restart_battle_button.visible = false
	if is_instance_valid(_enhancement_slot): _enhancement_slot.return_card(false)
	_enhancement_slot = null
	_clear_children(_body)
	_body.position = Vector2.ZERO
	_body.size = PANEL_SIZE
	_detail_body = null
	_event_table = null
	var show_panel := false
	if choosing_talent:
		show_panel = true
		_build_plain_event_board()
		_label("选择%d级天赋（本局生效）" % hero.pending_talent_levels[0])
		for id: String in hero.get_pending_choices():
			var definition: Dictionary = rewards.config.talents[id]
			_button("%s　%s" % [definition.display_name, definition.source_text], choose_talent.bind(id))
	elif run.step == RunState.Step.CHOOSING:
		show_panel = true
		_event_table = EventTable.new()
		_event_table.main = _main
		_body.add_child(_event_table)
		_event_table.path_chosen.connect(_on_event_path_chosen)
		_event_table.show_choices(run.paths, choice_key != _last_dealt_key)
		_last_dealt_key = choice_key
	elif run.step in [RunState.Step.EVENT, RunState.Step.BATTLE_PREPARE]:
		show_panel = run.get_round_kind() != "shop"
		if show_panel: _build_selected_event()
	elif run.step == RunState.Step.ENDED:
		show_panel = true
		_build_plain_event_board()
		var wins := 0
		for result: Dictionary in run.battle_results:
			if result.won: wins += 1
		var ending: String = run.battle_results.back().ending
		_label({"cleared": "第一层通关", "boss_loss": "Boss战失败", "ordinary_loss": "失败保护耗尽，本局结束"}[ending])
		_label("到达第%d天　胜利%d场／失败%d场\n剩余金币%d　总经验%d　英雄等级%d" % [run.day, wins, run.battle_results.size() - wins, _main.run_reward_state.gold, hero.experience, hero.level])
		_button("新一局", _restart_run)
	_panel.visible = show_panel and not _main._viewing_result_battlefield and not _main.ordinary_shop_open
	_status.visible = not _panel.visible and not _main.ordinary_shop_open
	# 父节点隐藏会连带隐藏全部敌方卡面；每次阶段变化都重新设置，不能只在准备阶段隐藏。
	_main.get_node("WorldContent/EnemyBoardSection").visible = _main.current_phase in [_main.GamePhase.BATTLE, _main.GamePhase.RESULT] and not choosing_talent and not _main.ordinary_shop_open
	for child: Node in _sentry_bar.get_children():
		if child == _sentry_zones.stock:
			continue
		_sentry_bar.remove_child(child)
		child.queue_free()
	for view: Control in _sentry_views.values():
		view.get_parent().remove_child(view)
		view.queue_free()
	_sentry_views.clear()
	var sentries_visible: bool = (preparing or _main.current_phase == _main.GamePhase.BATTLE) and run.step not in [RunState.Step.ENDED, RunState.Step.BATTLE_RESULT] and hero.pending_talent_levels.is_empty()
	_sentry_bar.visible = preparing and sentries_visible
	for sentry: Dictionary in stock:
		var stock_view := _create_sentry_view(sentry, "stock", _sentry_bar, preparing)
		var saved_position: Array = sentry.get("stock_position", [])
		stock_view.position = Vector2(float(saved_position[0]), float(saved_position[1])) if saved_position.size() == 2 else _main.celestial_indicators.get_inventory_slot_position(stock.find(sentry), StringName(sentry.instance_id))
	for sentry: Dictionary in deployed:
		var region: String = sentry.region
		# 排容器会撑大直接子节点；复用自由布局的投放区承载固定大小图标。
		var host: Control = _sentry_zones[region]
		var view := _create_sentry_view(sentry, region, host, preparing)
		view.position = Vector2.ZERO if region == "spells" else Vector2(host.size.x - view.size.x, 0) # 法术哨位在左上角，前后排哨位在右上角
		view.visible = sentries_visible
		_sentry_views[region] = view
	_main._refresh_drag_availability()
	update_battle_display()


func _build_plain_event_board() -> void:
	var board := EventTable.new()
	board.main = _main
	_body.add_child(board)
	board.show_selected({"name": "旅程", "kind": "battle"})
	_detail_body = board.detail_body


func _on_event_path_chosen(id: String) -> void:
	_reveal_selected_event = true
	var committed := select_path(id)
	_reveal_selected_event = false
	if not committed:
		# 选择存档失败后重建可点击牌堆，不能保留已经退场的旧模态层。
		_last_dealt_key = ""
		refresh()


func _build_selected_event() -> void:
	_event_table = EventTable.new()
	_event_table.main = _main
	_body.add_child(_event_table)
	_event_table.show_selected(run.selected_path, _reveal_selected_event)
	_detail_body = _event_table.detail_body
	var event: Dictionary = run.selected_path
	match run.get_round_kind():
		"battle":
			_label("Boss战" if run.is_boss_day() else "战斗遭遇")
			_label(String(event.hint) + "\n可以先调整我方阵容，准备后点击右下方开始战斗。")
		_:
			if event.get("reward") == "enhance_card":
				_build_enhancement_interface()
			elif event.get("reward") == "story":
				_build_story_choices(event)
			else:
				_label(String(event.name))
				var reward_text: String = {"gold": "获得3金币", "emblem": "获得1枚随机I级纹章", "minion": "获得1张随机灰烬证册I级随从", "pack": "获得1个灰烬证册小卡包（立即打开）", "wound": "随机拥有且有空槽的随从新增1处I级伤势；无目标不执行"}[event.reward]
				_label(reward_text)
				var cost := int(event.cost)
				var take := _button("继续" if bool(event.get("reward_claimed", false)) else ("花费%d金币" % cost if cost > 0 else "领取并继续"), complete_event.bind(true))
				take.disabled = not bool(event.get("reward_claimed", false)) and _main.run_reward_state.gold < cost
				if cost > 0 and not bool(event.get("reward_claimed", false)):
					_button("放弃，不花金币", complete_event.bind(false))


func _build_story_choices(event: Dictionary) -> void:
	_label(String(event.name))
	if event.has("story_result"):
		var result: Dictionary = event.story_result
		var outcome: Dictionary = event.options[int(result.option_index)].outcomes[int(result.outcome_index)]
		_label(("骰子点数：%d\n" % int(result.roll) if result.has("roll") else "") + String(outcome.text))
		_label(String(outcome.effect_text))
		_button("继续旅程", complete_event.bind(true))
		return
	_label(String(event.description))
	for index: int in event.options.size():
		var option: Dictionary = event.options[index]
		var blocked := story_events.blocked_reason(option, _main.run_reward_state.gold)
		var button := _button(String(option.label), choose_story_option.bind(index))
		button.text = String(option.label)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not blocked.is_empty()
		var explanation := "条件：%s" % String(option.condition)
		for outcome: Dictionary in option.outcomes:
			explanation += "\n%s：%s" % [str(outcome.source_probability), String(outcome.effect_text)]
		button.tooltip_text = explanation + ("\n" + blocked if not blocked.is_empty() else "")
		if not blocked.is_empty():
			_label(blocked)


func update_battle_display() -> void:
	if _main.current_phase != _main.GamePhase.BATTLE or _main.battle_controller.hero_runtime == null:
		return
	_update_status()
	var runtime: HeroRuntime = _main.battle_controller.hero_runtime
	for region: String in _sentry_views:
		var view: Control = _sentry_views[region]
		var active: Dictionary = {}
		for sentry: Dictionary in runtime.sentries:
			if sentry.region == region:
				active = sentry
		view.visible = not active.is_empty()
		if not active.is_empty():
			view.tooltip_text = "哨位容量 %.1f/%d；战斗中不可调整\n当前英雄对哨位的增强：\n%s" % [float(active.remaining), int(active.capacity), selected_talent_description()]


func _create_sentry_view(sentry: Dictionary, region: String, host: Control, preparing: bool) -> Control:
	var view := SentryView.new()
	view.sentry_data = sentry
	view.region = region
	view.talent_description = selected_talent_description()
	view.drag_enabled = preparing and _sentry_bar.visible
	host.add_child(view)
	view.click_carry_requested.connect(_main._on_click_carry_requested)
	return view


func can_drop_sentry(id: String, region: String) -> bool:
	if _main.current_phase != _main.GamePhase.PREPARE or run.step in [RunState.Step.BATTLE_RESULT, RunState.Step.ENDED] or not hero.pending_talent_levels.is_empty() or _main.ordinary_shop_open:
		return false
	var source_region := ""
	for sentry: Dictionary in stock:
		if sentry.instance_id == id: source_region = "stock"
	for sentry: Dictionary in deployed:
		if sentry.instance_id == id: source_region = String(sentry.region)
	if source_region.is_empty():
		return false
	if source_region == region:
		return region == "stock"
	if region == "stock":
		return stock.size() < _inventory_limit()
	if region not in ["front", "back", "spells"]:
		return false
	for sentry: Dictionary in deployed:
		if sentry.region == region: return false
	return true


func drop_sentry(id: String, region: String) -> bool:
	if not can_drop_sentry(id, region): return false
	for sentry: Dictionary in deployed:
		if sentry.instance_id != id: continue
		if region == "stock": return recall_sentry(String(sentry.region))
		var previous := _capture_transaction()
		sentry.region = region
		return _commit_transaction(previous)
	return deploy_sentry(id, region)


func resolve_sentry_drop(id: String, pointer: Vector2) -> Dictionary:
	for region: String in _sentry_zones:
		var zone: Control = _sentry_zones[region]
		var local := zone.get_global_transform_with_canvas().affine_inverse() * pointer
		if zone.is_visible_in_tree() and Rect2(Vector2.ZERO, zone.size).has_point(local):
			return {"region": region, "local": local} if can_drop_sentry(id, region) else {}
	return {}


func drop_sentry_at(id: String, pointer: Vector2) -> bool:
	var target := resolve_sentry_drop(id, pointer)
	if target.is_empty():
		return false
	var region := String(target.region)
	var local: Vector2 = target.local
	if region == "stock":
		return _place_sentry_in_stock(id, local)
	if not drop_sentry(id, region):
		return false
	var view: Control = _sentry_views.get(region)
	if is_instance_valid(view):
		var destination := view.position
		view.position = local - view.size * 0.5
		view.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(view, "position", destination, SENTRY_MOVE_SECONDS)
	return true


func _place_sentry_in_stock(id: String, local: Vector2) -> bool:
	if not can_drop_sentry(id, "stock"):
		return false
	var placement: Vector2 = _main.celestial_indicators.find_inventory_position(Vector2(44, 49), local - Vector2(22, 24.5), StringName(id))
	if not placement.is_finite(): return false
	var previous := _capture_transaction()
	for sentry: Dictionary in deployed:
		if sentry.instance_id == id:
			var entry := {"instance_id": sentry.instance_id, "visual_variant": sentry.visual_variant}
			stock.append(entry)
			deployed.erase(sentry)
			break
	for sentry: Dictionary in stock:
		if sentry.instance_id == id:
			sentry["stock_position"] = [placement.x, placement.y]
			return _commit_transaction(previous)
	return false


func _restart_run() -> void:
	var previous := _capture_transaction()
	new_run(Time.get_ticks_usec())
	_commit_transaction(previous)


func _update_status() -> void:
	_status.visible = not _panel.visible and not _main.ordinary_shop_open
	_status.sync(self)


func shop_entry_message() -> String:
	if run.day == 2 and 2 in run.claimed_pack_days:
		return "今日礼包大包×1已打开，5张卡已入收藏并保存。"
	if run.day == 3 and 3 in run.claimed_pack_days:
		return "今日礼包大包×1、小包×1已打开，8张卡已入收藏并保存。"
	return "可购买商品，也可直接离开商店。"


func selected_talent_description() -> String:
	var lines: Array[String] = []
	for id: String in hero.selected_talents.values():
		var talent: Dictionary = rewards.config.talents[id]
		lines.append("%s：%s" % [talent.display_name, talent.source_text])
	return "\n".join(lines) if not lines.is_empty() else "尚未选择强化"


func hero_description() -> String:
	return "伊奥恩·沃登\n当前等级：%d\n累计经验：%d\n已选择的强化：\n%s" % [hero.level, hero.experience, selected_talent_description()]


func can_select_enhancement_card(data: Dictionary) -> bool:
	if run.step != RunState.Step.EVENT or run.selected_path.get("reward") != "enhance_card" or run.selected_path.has("enhancement_result") or _main.current_phase != _main.GamePhase.PREPARE:
		return false
	var owned := data.get("owned_card") as OwnedCard
	return data.get("kind") == &"card" and owned != null and owned.card_data.card_type == CardData.CardType.MINION and _main.owned_card_collection.get_by_instance_id(owned.instance_id) == owned


func select_enhancement_card(data: Dictionary) -> bool:
	if not can_select_enhancement_card(data):
		return false
	var entry_position := CardServiceSlot.get_entry_position(data)
	_enhancement_card_id = (data.owned_card as OwnedCard).instance_id
	_refresh_enhancement_card()
	_enhancement_slot.animate_entry_from_global_position(entry_position)
	return true


func is_enhancement_drop_at(pointer: Vector2) -> bool:
	return is_instance_valid(_enhancement_slot) and _enhancement_slot.is_visible_in_tree() and _enhancement_slot.get_global_rect().has_point(pointer)

func _on_enhancement_card_returned() -> void:
	_enhancement_card_id = &""
	_refresh_enhancement_card.call_deferred()


func _enhancement_option_text(option: Dictionary) -> String:
	var values: Array[String] = []
	for pair: Array in [["max_health", "生命"], ["base_armor", "护甲"], ["base_value", "数值"]]:
		if option.has(pair[0]):
			values.append("+%d%s" % [int(option[pair[0]]), pair[1]])
	return "%s：%s" % ["免费" if int(option.cost) == 0 else "%d金币" % int(option.cost), "、".join(values)]


func _refresh_enhancement_card() -> void:
	if not is_instance_valid(_enhancement_slot): return
	var owned: OwnedCard = _main.owned_card_collection.get_by_instance_id(_enhancement_card_id)
	_enhancement_slot.show_card(owned)
	if is_instance_valid(_enhancement_options):
		for button: Node in _enhancement_options.find_children("*", "Button", true, false):
			if button is Button and button.has_meta("enhancement_option"):
				var option: Dictionary = run.selected_path.options[int(button.get_meta("enhancement_option"))]
				button.disabled = owned == null or _main.run_reward_state.gold < int(option.cost)
	_main._refresh_drag_availability()


func _build_enhancement_interface() -> void:
	var finished := run.selected_path.has("enhancement_result")
	_label(String(run.selected_path.name) + (" · 强化完成" if finished else " · 本局永久强化"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24) # 强化选项和右侧卡槽的间距
	(_detail_body if is_instance_valid(_detail_body) else _body).add_child(row)
	_enhancement_options = VBoxContainer.new()
	_enhancement_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_enhancement_options)
	var tip := Label.new()
	tip.text = "卡牌已强化，可拖回战场，或继续旅程后回收藏。" if finished else "把一张随从拖到右侧，再选择一次强化。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enhancement_options.add_child(tip)
	if finished:
		_button("继续旅程", complete_event.bind(true), _enhancement_options)
	else:
		for index: int in run.selected_path.options.size():
			var option: Dictionary = run.selected_path.options[index]
			var button := _button(_enhancement_option_text(option), apply_card_enhancement.bind(index), _enhancement_options)
			button.set_meta("enhancement_option", index)
		_button("放弃强化并继续", complete_event.bind(false), _enhancement_options)
	var slot := CardServiceSlot.new()
	slot.allow_deployment = finished
	slot.accepts_card = can_select_enhancement_card
	slot.resolve_card_view = _main._take_service_card_view
	slot.release_card_view = _main._release_service_card_view
	slot.card_selected.connect(select_enhancement_card)
	slot.card_returned.connect(_on_enhancement_card_returned)
	slot.name = "EnhancementCardSlot"
	slot.custom_minimum_size = Vector2(130, 155) # 右侧强化卡槽尺寸
	row.add_child(slot)
	_enhancement_slot = slot
	_refresh_enhancement_card()


func apply_card_enhancement(option_index: int, discard_confirmed: bool = false) -> bool:
	if run.step != RunState.Step.EVENT or run.selected_path.get("reward") != "enhance_card" or run.selected_path.has("enhancement_result") or option_index < 0 or option_index >= run.selected_path.options.size():
		return false
	var owned: OwnedCard = _main.owned_card_collection.get_by_instance_id(_enhancement_card_id)
	var option: Dictionary = run.selected_path.options[option_index]
	if owned == null or owned.card_data.card_type != CardData.CardType.MINION or _main.run_reward_state.gold < int(option.cost):
		return false
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(apply_card_enhancement.bind(option_index, true)): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	_main.run_reward_state.gold -= int(option.cost)
	for stat: StringName in [OwnedCard.STAT_MAX_HEALTH, OwnedCard.STAT_BASE_ARMOR, OwnedCard.STAT_BASE_VALUE]:
		if option.has(String(stat)):
			owned.apply_permanent_growth(stat, float(option[String(stat)]))
	run.selected_path["enhancement_result"] = {"instance_id": String(owned.instance_id), "option_index": option_index}
	run.selected_path["reward_claimed"] = true
	return _commit_transaction(previous)
