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
const Arrival = preload("res://scripts/ui/pack_arrival_animation.gd")
const ArrivalSettings = preload("res://scripts/ui/pack_opening_effect_settings.gd")
const StoryEvents = preload("res://scripts/data/maze_story_event_service.gd")
const PotionRules = preload("res://scripts/data/event_potion_rules.gd")
const MiningEvents = preload("res://scripts/flow/twisted_vein_event_runtime.gd")
const DiceRoll = preload("res://scripts/ui/event_dice_roll.gd")
const EventRewards = preload("res://scripts/ui/event_reward_presentation.gd")
const BATTLE_INTRO_STEPS := ["battle_intro", "battle_retreat", "battle_wounds", "battle_protection", "battle_playback"]
const CardServiceSlot = preload("res://scripts/ui/card_service_slot.gd")
static var TEXT_FONT: Font = preload("res://scripts/ui/ui_typography.gd").font()
const SentryStyle = preload("res://scripts/ui/sentry_indicator_style.gd")
const SENTRY_MOVE_SECONDS: float = 0.30 # 哨位从鼠标落点移动到区域角落的时长
const PANEL_POSITION := Vector2(189, 0) # 普通事件与上半世界共用原稿顶边
const PANEL_SIZE := Vector2(902, 351) # 新事件棋盘原生尺寸
const BATTLE_BOARD_EXIT_SECONDS := 0.34 # 上半视角的战斗准备板滑出屏幕所需时间
const INITIAL_PACK_HINT_DELAY: float = 3.0 # 卡包落稳后空闲多久开始摇摆跳动
const INITIAL_PACK_NUDGE_SECONDS: float = 0.4 # 单次摇摆跳动的时长
const INITIAL_PACK_NUDGE_HEIGHT: float = 18.0 # 卡包提示跳起的逻辑像素高度
const INITIAL_PACK_NUDGE_ANGLE: float = 8.0 # 卡包提示左右摇摆的最大角度
const INITIAL_PACK_SHADOW_RATIO := Vector2(0.84, 0.08) # 跳动时地面投影相对包装显示尺寸的宽高
const INITIAL_PACK_SHADOW_ALPHA: float = 0.20 # 跳动地面投影的最大透明度
const INITIAL_PACK_SHADOW_SPREAD: float = 0.12 # 跳起到最高点时投影额外变宽的比例
const INITIAL_PACK_SHADOW_Y_RATIO: float = 0.44 # 投影距包装中心的纵向偏移，占包装显示高度的比例
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
var story_buffs: Array[Dictionary] = []
var story_participants: Array[String] = []
var story_score: int = 0
var story_shop_discount: bool = false
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
var _story_battle_deployed: Array[String] = []
var _before_battle_gold: int = 0
var _sentry_views: Dictionary = {}
var _initial_pack_prompt: Control
var _initial_pack_button: TextureButton
var _initial_pack_shadow: Panel
var _initial_pack_opening: CardPackOpening
var _initial_pack_idle_seconds := 0.0
var _initial_pack_drop: Tween
var _initial_pack_presenting := false
var _queued_tutorial_stories: Array[String] = []
var _scraper_handoff: Control
var _rune_lesson_waiting_for_release := false
var _story_roll: Control
var _event_reward_previews: Dictionary = {}
var _event_reward_in_flight: Array[Dictionary] = []
var _event_reward_flight: Control
var _battle_board_exit: Tween
var _battle_board_input_blocker: Control
var _story_food_picker: ItemList
var _camp_donation_picker: OptionButton
var _story_material_pickers: Dictionary = {}


func _process(delta: float) -> void:
	if not is_instance_valid(_main) or not _main.is_visible_in_tree() or _main.profile_progress.run.stage != "active": return
	if _initial_pack_presenting and not is_instance_valid(_main._inspection_overlay):
		_initial_pack_presenting = false
		refresh()
	if _main._escape_menu_pause_requested: return
	# 真正揭晓的信号先等待松手，再收好刮刀讲解，不中断当前笔画。
	if _rune_lesson_waiting_for_release and not _main._rune_scrape_button_held:
		_rune_lesson_waiting_for_release = false
		_main._finish_rune_scraper_mode()
		show_task_hint.call_deferred()
	if is_instance_valid(_scraper_handoff): return
	if _smith_handoff_pending() and not is_instance_valid(_main._inspection_overlay):
		_start_smith_handoff()
		return
	var hint := _main.get_node_or_null("TaskHint")
	if is_instance_valid(hint):
		if _teaching_action_completed(String(hint.get_meta("hint_key", "")), hint): hint.complete_teaching()
		if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial":
			var next_id := _tutorial_hint_id()
			var next_key := "tutorial:step:" + next_id
			if next_key != hint.get_meta("hint_key", "") and not _queued_tutorial_stories.has(next_id) and _main.profile_progress.hint_pending(next_key, TaskCatalog.tutorial_hint(next_id)).story:
				_queued_tutorial_stories.append(next_id)
		return
	var display := get_tree().get_first_node_in_group(&"game_display_shell")
	if display != null and is_instance_valid(display.screen_transition) and display.screen_transition.busy: return
	if not is_instance_valid(_initial_pack_prompt) or not _initial_pack_prompt.visible or _initial_pack_button.disabled:
		_initial_pack_idle_seconds = 0.0
		return
	_initial_pack_idle_seconds += delta
	if _initial_pack_idle_seconds >= INITIAL_PACK_HINT_DELAY:
		_nudge_initial_pack()
		_initial_pack_idle_seconds = 0.0


func initialize(main: Control) -> bool:
	_main = main
	if not rewards.load_config() or not story_events.load_config():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/short_maze_content.json"))
	if not parsed is Dictionary:
		return false
	content = parsed
	var tutorial: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tasks/tutorial_enemies.json"))
	content.enemies.append_array(tutorial.enemies)
	var floor_two: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tasks/second_floor_enemies.json"))
	content.enemies.append_array(floor_two.enemies)
	for event: Dictionary in story_events.config.events:
		var pool: Array = content.free_events if event.kind == "free_event" else content.paid_events
		pool.append(event.duplicate(true))
	var tutorial_events: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tasks/tutorial_events.json"))
	# 两版福尔图纳共用文案和奖励表，正式版解除教程的点数上限。
	var fortuna: Dictionary = tutorial_events.fortuna.duplicate(true)
	fortuna.path_id = "fortuna_gift"
	for key: String in ["tutorial", "first_day", "last_day"]:
		fortuna.erase(key)
	fortuna.options[0].erase("roll_max")
	content.free_events.append(fortuna)
	# 三张候选指向同一事件；独立路径编号沿用原有选择及存档校验。
	for event: Dictionary in tutorial_events.values():
		for index: int in 3:
			var path := event.duplicate(true)
			path.path_id = "%s_%d" % [event.path_id, index]
			content.free_events.append(path)
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	if not hero.initialize(thresholds, rewards.config.talent_choices):
		return false
	_build_ui()
	return true


func new_run(seed_value: int) -> void:
	if _main.profile_progress.run.stage in ["selection", "preview"]: return
	_cancel_event_presentations()
	if is_instance_valid(_scraper_handoff): _scraper_handoff.free()
	_rune_lesson_waiting_for_release = false
	_queued_tutorial_stories.clear()
	_initial_pack_idle_seconds = 0.0
	_initial_pack_presenting = false
	if is_instance_valid(_initial_pack_drop): _initial_pack_drop.kill()
	_initial_pack_prompt.visible = false
	# D3-1保留Demo2的开局流程，仅重置本局部分，局外数据持续保留。
	_main.profile_progress.run.stage = "hub"
	_main.profile_progress.start_run()
	_main._profile_before_battle.clear()
	_main._close_shop_card_services()
	_main._return_service_cards()
	_enhancement_card_id = &""
	run.initialize(seed_value)
	run.route_days = 4 if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial" or not _main.profile_progress.enabled("routes", "eight_days") else (16 if _main.profile_progress.enabled("routes", "second_floor") else 8)
	if TaskCatalog.selected(_main.profile_progress, "main") == "deep_survey": run.route_days = 8
	run.daily_pack_rewards = false
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	hero.initialize(thresholds, rewards.config.talent_choices, not _main.is_smith_tutorial())
	stock.clear()
	deployed.clear()
	seen_events.clear()
	story_buffs.clear()
	story_participants.clear()
	story_score = 0
	story_shop_discount = false
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
	_main._bind_profile_collection()
	var registry: Dictionary = _main._build_card_definition_registry()
	var no_reserved_cards: Array[CardData] = []
	for id: String in ([] if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial" else rewards.config.initial_card_ids):
		_main.owned_card_collection.create_card(registry[StringName(id)], run.rng, no_reserved_cards, false, {"kind": "starting_supplies"})
	_main.run_reward_state = RunRewardState.new()
	_main.run_reward_state.gold = int(rewards.config.initial_gold)
	for row: BattlefieldRow in [_main.front_row, _main.back_row, _main.enemy_front_row, _main.enemy_back_row]:
		row.clear_squads()
	_main.apply_run_unlocks()
	_prepare_task_supplies(registry)
	if _main.is_smith_tutorial(): _begin_day()
	_main.start_new_resource_level(&"level_000001", run.rng)
	_main._sync_legacy_collection_cards()
	_main._build_collection_cards()
	_main._update_phase_label()
	_main.set_world_view(_main.WorldView.BATTLEFIELDS, false)
	_main._collect_progress_discoveries(_main.profile_progress, _main.owned_card_collection.capture_state())
	_main.profile_progress.commit_discoveries()
	refresh()


func floor_number() -> int:
	return (run.day - 1) / RunState.DAYS + 1


func _inventory_limit() -> int:
	return int(rewards.config.talents.sentry_alchemy.confirmed_rules.inventory_limit) if hero.has_talent("sentry_alchemy") else int(rewards.config.sentry.inventory_limit)


func _add_sentry() -> void:
	if _main.is_smith_tutorial(): return
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
				if bool(enemy.get("tutorial", false)) != (TaskCatalog.selected(_main.profile_progress, "main") == "tutorial"): continue
				if run.day >= int(enemy.first_day) and run.day <= int(enemy.last_day):
					candidates.append(enemy.duplicate(true))
		_:
			var pool: Array = content.free_events if run.get_round_kind() == "free_event" else content.paid_events
			if _main.is_smith_tutorial():
				if run.round_index == 0:
					candidates.assign(pool.filter(func(event: Dictionary): return event.get("tutorial", false) and int(event.first_day) == run.day))
			else:
				pool = content.free_events + content.paid_events
				var fixed := _fixed_story_path(pool)
				if not fixed.is_empty():
					for index: int in 3:
						candidates.append(fixed.duplicate(true))
			_fill_event_paths(candidates, pool)
	# 所有路径（含商店／敌人）的显示次序使用本局随机源，选择后保存，不在刷新时重抽。
	var shuffled: Array[Dictionary] = []
	while not candidates.is_empty():
		shuffled.append(candidates.pop_at(run.rng.randi_range(0, candidates.size() - 1)))
	for path: Dictionary in shuffled:
		if path.kind == "battle":
			path["battle_seed"] = run.rng.randi_range(0, _main.BATTLE_SEED_MAX)
	run.set_paths(shuffled)


func _fixed_story_path(pool: Array) -> Dictionary:
	var fixed: Dictionary = {}
	var postponed: Dictionary = {}
	for event: Dictionary in pool:
		if int(event.get("fixed_day", 0)) != run.day or event.path_id in seen_events: continue
		if int(event.get("fixed_round", -1)) == run.round_index:
			if event.path_id == "so_close": postponed = event
			else: fixed = event
		elif event.path_id == "so_close" and run.round_index == int(event.fixed_round) + 1:
			postponed = event
	if fixed.is_empty(): fixed = postponed
	if fixed.is_empty(): return {}
	var path := fixed.duplicate(true)
	path.kind = run.get_round_kind()
	_prepare_story_path(path)
	return path


func _fill_event_paths(candidates: Array[Dictionary], pool: Array) -> void:
	if candidates.size() >= 3: return
	var groups := [[], [], [], []]
	for event: Dictionary in pool:
		if event.get("tutorial", false) or event.has("fixed_day"): continue
		if event.get("reward") == "emblem" and not _main.run_pack_enabled("emblem_pack"): continue
		if event.get("reward") == "story" and not story_events.can_appear(event, _main.run_reward_state.gold, floor_number(), String(_main.profile_progress.run.hero)):
			continue
		var pack := story_events.required_pack(event)
		if not pack.is_empty() and not _main.run_pack_enabled(pack): continue
		if not MiningEvents.can_appear(self, event.path_id): continue
		if event.path_id == "bounty_hunter" and _story_minions().is_empty(): continue
		if event.path_id == "spoils_dispute" and _story_deployed().size() < 2: continue
		# 先抽未见正式事件，再由同类旧事件补位。未见池用尽后才回用已见事件。
		var index := 2 if String(event.path_id) in seen_events else 0
		if not story_events.is_formal_event(event): index += 1
		groups[index].append(event)
	var ordered_groups := [groups[0], groups[2]] if not groups[0].is_empty() or not groups[2].is_empty() else [groups[1], groups[3]]
	for group: Array in ordered_groups:
		while candidates.size() < 3 and not group.is_empty():
			var event: Dictionary = group.pop_at(run.rng.randi_range(0, group.size() - 1))
			var path := event.duplicate(true)
			path.kind = run.get_round_kind()
			_prepare_story_path(path)
			candidates.append(path)
	if not candidates.is_empty():
		var distinct_count := candidates.size()
		while candidates.size() < 3:
			candidates.append(candidates[run.rng.randi_range(0, distinct_count - 1)].duplicate(true))


func _prepare_story_path(path: Dictionary) -> void:
	if path.path_id == "bounty_hunter":
		var pool := _story_minions()
		var target := pool[run.rng.randi_range(0, pool.size() - 1)]
		path["story_targets"] = [String(target.instance_id)]
	elif path.path_id == "spoils_dispute":
		var pool := _story_deployed()
		path["story_targets"] = []
		for index: int in 2:
			var target: OwnedCard = pool.pop_at(run.rng.randi_range(0, pool.size() - 1))
			path.story_targets.append(String(target.instance_id))


func choose_talent(id: String) -> bool:
	if _main.is_smith_tutorial(): return false
	if id == "firmament_blessing": return false
	var previous := _capture_transaction()
	if not hero.choose_talent(id):
		return false
	if id == "sentry_alchemy":
		for index: int in int(rewards.config.talents.sentry_alchemy.confirmed_rules.immediate_count):
			_add_sentry()
	if id == "three_celestial_marks":
		var state: Dictionary = _main.celestial_indicators.capture_state()
		for kind: int in CelestialIndicator.ASTRAL_KINDS:
			state.items.append({"instance_id": "hero_three_marks_%d" % kind, "kind": kind, "star_transfer_count": 0})
		_main.celestial_indicators.restore_state(state)
	_begin_day()
	return _commit_transaction(previous)


func select_path(id: String, index: int = -1) -> bool:
	var previous := _capture_transaction()
	_enhancement_card_id = &""
	if index < 0: index = run.paths.find_custom(func(path: Dictionary) -> bool: return path.path_id == id)
	var designated := _nyx_designated_road()
	if index < 0 or index >= run.paths.size() or run.paths[index].path_id != id: return false
	if not _main.profile_progress.run.get("supplies", []).is_empty() or not hero.pending_talent_levels.is_empty() or not run.select_path(id, index):
		return false
	if index == designated:
		var nyx := _story_owned("nyx_contract_demon")[0] as OwnedCard
		nyx.progress_by_source[OwnedCard.NYX_ROADS_PROGRESS] = int(nyx.progress_by_source.get(OwnedCard.NYX_ROADS_PROGRESS, 0)) + 1
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
		if run.selected_path.get("reward") == "tutorial_smith":
			if not _grant_tutorial_smith():
				_rollback_transaction(previous)
				return false
			run.selected_path["reward_claimed"] = true
		if id not in seen_events:
			seen_events.append(id)
	if not _commit_transaction(previous):
		return false
	if run.get_round_kind() == "shop":
		enter_selected_shop()
	return true


func _nyx_designated_road() -> int:
	if run.paths.is_empty(): return -1
	var cards := _story_owned("nyx_contract_demon")
	if cards.is_empty() or int(cards[0].progress_by_source.get(OwnedCard.NYX_ROADS_PROGRESS, 0)) >= OwnedCard.NYX_ROADS_REQUIRED: return -1
	# 标记由本局种子和轮次确定，翻牌、刷新界面和读档不额外推进随机流。
	return posmod(hash("nyx:%d:%d:%d" % [run.rng.seed, run.day, run.round_index]), run.paths.size())


func enter_selected_shop() -> void:
	if run.step == RunState.Step.EVENT and run.get_round_kind() == "shop" and not _main.ordinary_shop_open:
		_main._toggle_ordinary_shop()
		_main.ordinary_shop_status.text = shop_entry_message()


func _prepare_task_supplies(registry: Dictionary) -> void:
	var no_reserved: Array[CardData] = []
	var task_id := TaskCatalog.selected(_main.profile_progress, "main")
	if task_id == "tutorial":
		_main.profile_progress.run.supplies.append({"kind": "card_pack", "name": "灰烬证册 · 初始包", "pack_id": "ash_ledger", "size": "large", "cards": rewards.config.initial_card_ids.duplicate()})
	elif task_id == "supply_first":
		var robot: OwnedCard = _main.owned_card_collection.create_card(registry[&"logistics_robot"], run.rng, no_reserved, false, {"kind": "task", "name": "补给先行"})
		_main.front_row.add_squad(SquadData.from_owned_card(robot), 0)
		var service := OrdinaryShopService.new()
		service.load_config()
		service.config.sticker_unlocks = _main.ordinary_shop_service.config.sticker_unlocks.duplicate(true)
		var candidates: Array[Dictionary] = service._eligible_stickers(_main._get_shop_sticker_definitions(), [], [])
		var stickers: Array[Dictionary] = []
		for index: int in int(service.config.sticker_pack.sticker_count):
			var sticker := service._draw_sticker(candidates, run.rng)
			sticker.id = String(sticker.id)
			stickers.append(sticker)
		_main.profile_progress.run.supplies.append({"kind": "sticker_pack", "name": "纹章包", "stickers": stickers})

	if task_id == "deep_survey":
		_main.owned_card_collection.create_card(registry[&"extinguished_lantern"], run.rng, no_reserved, false, {"kind": "task", "name": "深层勘探"})
	if task_id in ["ironwall_support", "temple_boon"]:
		if task_id == "temple_boon":
			var il: OwnedCard = _main.owned_card_collection.create_card(registry[&"il_ancient_speaker"], run.rng, no_reserved, false, {"kind": "task", "name": "神殿增益"})
			_main.front_row.add_squad(SquadData.from_owned_card(il), 0)
		_queue_task_packs("ironwall_inscription" if task_id == "ironwall_support" else "silvermoon_chapter", 1)
	if TaskCatalog.selected(_main.profile_progress, "side") == "witch_cauldron":
		var states: Array[Dictionary] = []
		for id: String in ["长剑", "盾牌Ⅰ", "奶酪", "面包"]:
			states.append({"instance_id": "witch_cauldron:" + id, "emblem_id": id, "temporary": false, "source": "task"})
		_main.emblem_library.receive_stickers(states)
	if TaskCatalog.selected(_main.profile_progress, "side") == "portable_runes":
		var states: Array[Dictionary] = []
		for id: String in ["光贴纸", "暗贴纸", "水贴纸", "火贴纸", "木贴纸"]:
			states.append({"instance_id": "portable_runes:" + id, "emblem_id": id, "element_sticker": true, "temporary": false, "source": "task"})
		_main.emblem_library.receive_stickers(states)


func _queue_task_packs(pack_id: String, count: int) -> bool:
	var service := OrdinaryShopService.new()
	service.load_config()
	service.config.allowed_pack_ids = [pack_id]
	service.config.excluded_pack_ids = []
	var held: Array = _main.owned_card_collection.get_cards()
	# Pending gift packs count as held for item／IV uniqueness across the whole batch.
	var registry: Dictionary = _main._build_card_definition_registry()
	for queued: Dictionary in _main.profile_progress.run.supplies:
		for id: String in queued.get("cards", []):
			var reserved := OwnedCard.new()
			reserved.card_data = registry[StringName(id)]
			held.append(reserved)
	for index: int in count:
		var drawn := service.draw_card_pack(_main._get_shop_card_definitions(), true, int(service.config.card_pack_sizes.large), run.rng, held)
		if not drawn.success: return false
		var ids: Array[String] = []
		for card: CardData in drawn.cards:
			ids.append(String(card.id))
			var reserved := OwnedCard.new()
			reserved.card_data = card
			held.append(reserved)
		_main.profile_progress.run.supplies.append({"kind": "card_pack", "name": CardPackRegistry.get_display_name(StringName(pack_id)) + " · 任务大包", "pack_id": pack_id, "size": "large", "cards": ids})
	return true


func open_task_supply() -> bool:
	if _main.current_phase != _main.GamePhase.PREPARE or _main.profile_progress.run.get("supplies", []).is_empty() or is_instance_valid(_main._inspection_overlay): return false
	var previous := _capture_transaction()
	var supply: Dictionary = _main.profile_progress.run.supplies[0]
	var mission_owners: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	var cards: Array[OwnedCard] = []
	var sticker_ids: Array[StringName] = []
	var registry: Dictionary = _main._build_card_definition_registry()
	var reserved: Array[CardData] = []
	for queued: Dictionary in _main.profile_progress.run.supplies:
		for id: String in queued.get("cards", []): reserved.append(registry[StringName(id)])
	if supply.kind == "card_pack":
		for id: String in supply.cards:
			var owned: OwnedCard = _main.owned_card_collection.create_card(registry[StringName(id)], run.rng, reserved, true, {"kind": "task_pack", "name": supply.name})
			if owned == null:
				_rollback_transaction(previous)
				return false
			cards.append(owned)
	else:
		var states: Array[Dictionary] = []
		for index: int in supply.stickers.size():
			var sticker: Dictionary = supply.stickers[index]
			var id := StringName("task_supply:%s:%d" % [_main.profile_progress.run.id, index])
			states.append({"instance_id": id, "emblem_id": sticker.id, "temporary": false, "source": "task_pack", "element_sticker": sticker.get("target", "emblem") == "rune"})
			sticker_ids.append(id)
		if not _main.emblem_library.receive_stickers(states):
			_rollback_transaction(previous)
			return false
	if supply.kind == "card_pack": _main.record_secret_mission_progress(OwnedCard.MissionGoal.PACKS, mission_owners)
	var initial: bool = TaskCatalog.selected(_main.profile_progress, "main") == "tutorial"
	_main.profile_progress.run.supplies.pop_front()
	_initial_pack_presenting = initial
	if not _commit_transaction(previous, true):
		_initial_pack_presenting = false
		return false
	_main._open_shop_pack_inspection(supply, _initial_pack_button if initial else null, true, cards, -1, sticker_ids)
	if initial:
		_initial_pack_idle_seconds = 0.0
		_initial_pack_opening = _main._card_pack_opening
		_initial_pack_opening.wrapper_opened.connect(func():
			_main.save_profile_action(func():
				note_tutorial_action("initial_pack_torn")
				return true), CONNECT_ONE_SHOT)
	return true


func _grant_tutorial_smith() -> bool:
	var progress: Dictionary = _main.profile_progress.run.tasks.main.progress
	if progress.get("smith_received", false): return true
	var row: BattlefieldRow = _main.front_row if _main.front_row.has_capacity_for_single_card() else _main.back_row
	if not row.has_capacity_for_single_card(): return false
	var no_reserved: Array[CardData] = []
	var margaret: OwnedCard = _main.owned_card_collection.create_card(load("res://resources/cards/anvil_margaret.tres"), run.rng, no_reserved, false, {"kind": "task", "name": "营救铁匠"})
	if margaret == null or row.add_squad(SquadData.from_owned_card(margaret), 0) == null: return false
	progress["smith_received"] = true
	_main.scraper_count = maxi(_main.scraper_count, 1)
	_main.emblem_library.set_scraper_count(_main.scraper_count)
	_main.apply_run_unlocks()
	return true


func _smith_handoff_pending() -> bool:
	return is_instance_valid(_main) and TaskCatalog.selected(_main.profile_progress, "main") == "tutorial" and run.day == 2 and _main.current_phase == _main.GamePhase.PREPARE and _main.profile_progress.run.read_story_nodes.has("tutorial:step:smith") and not _main.profile_progress.run.tasks.main.progress.get("tutorial_actions", {}).get("smith_scraper_delivered", false)


func _start_smith_handoff() -> void:
	var source := _find_tutorial_card_view(&"anvil_margaret")
	if not is_instance_valid(source): return
	var display := get_tree().get_first_node_in_group(&"game_display_shell")
	if display != null and display.screen_transition.busy: return
	if not Rect2(0, 0, 1280, 720).intersects(_hint_control_rect(source)): _main.set_world_view(_main.WorldView.BATTLEFIELDS, false)
	var flight := preload("res://scripts/ui/scraper_handoff.gd").new()
	flight.name = "SmithScraperHandoff"
	flight.source = source
	flight.target = _main.emblem_library._scraper
	flight.move_view = _main.set_world_view.bind(_main.WorldView.COLLECTION, true)
	_scraper_handoff = flight
	flight.finished.connect(func():
		if _main.save_profile_action(func():
			note_tutorial_action("smith_scraper_delivered")
			return true): flight.queue_free()
		else: flight.show_save_failure())
	flight.tree_exited.connect(func():
		_scraper_handoff = null
		show_task_hint.call_deferred(), CONNECT_ONE_SHOT)
	_main.add_child(flight)


func _tutorial_speaker(name_text: String) -> Control:
	if name_text.begins_with("伊奥恩") or name_text == "主角": return _main.player_avatar_button
	var definition: CardData = _main.character_definition(name_text)
	if definition != null:
		if is_instance_valid(_main._inspection_surface) and _main._inspection_owned_card != null and _main._inspection_owned_card.card_data.id == definition.id: return _main._inspection_surface
		return _find_tutorial_card_view(definition.id)
	return null


func _find_tutorial_card_view(id: StringName) -> CardView:
	# 优先真实上场卡，避免同一实例在收藏中的灰色占位抢走气泡锚点。
	for row: BattlefieldRow in [_main.front_row, _main.back_row]:
		for slot: BoardSlot in row.get_squads():
			for card: CardView in slot.get_card_views():
				if card.card_data.id == id: return card
	for card: Node in get_tree().get_nodes_in_group(&"card_views"):
		if card is CardView and card.is_visible_in_tree() and card.card_data != null and card.card_data.id == id and card.get_owned_card() != null: return card
	return null


func show_task_hint() -> void:
	if _event_presentation_busy(): return
	if is_instance_valid(_scraper_handoff) or _smith_handoff_pending(): return
	if not is_instance_valid(_main) or not _main.is_inside_tree(): return
	if _main.profile_progress.run.stage != "active" or is_instance_valid(_main.get_node_or_null("TaskHint")) or _main._escape_menu_pause_requested or _main._rune_scraper_mode or _main._inspection_closing: return
	for animation: Tween in [_main._shop_open_tween, _main._view_tween, _main._inspection_tween]:
		if is_instance_valid(animation) and animation.is_running():
			if not animation.finished.is_connected(show_task_hint): animation.finished.connect(show_task_hint, CONNECT_ONE_SHOT)
			return
	if is_instance_valid(_event_table) and _event_table.busy:
		if not _event_table.choices_ready.is_connected(show_task_hint): _event_table.choices_ready.connect(show_task_hint, CONNECT_ONE_SHOT)
		return
	var key := ""
	var title := "任务剧情"
	var presentation: Dictionary = {}
	var battle_intro_step := _battle_intro_step()
	if not battle_intro_step.is_empty():
		key = "tutorial:step:" + battle_intro_step
		presentation = TaskCatalog.tutorial_hint(battle_intro_step)
		title = presentation.title
	while presentation.is_empty() and not _queued_tutorial_stories.is_empty() and TaskCatalog.selected(_main.profile_progress, "main") == "tutorial":
		var id := _queued_tutorial_stories[0]
		if is_instance_valid(_main._inspection_overlay) and id not in ["supplies", "scraper_inspection", "rune_basics", "smith_tools", "militia_inspect", "militia_keywords"]: return
		_queued_tutorial_stories.pop_front()
		var queued := TaskCatalog.tutorial_hint(id)
		if not _main.profile_progress.hint_pending("tutorial:step:" + id, queued).story: continue
		if id != _tutorial_hint_id(): queued.instruction = ""
		key = "tutorial:step:" + id
		presentation = queued
		title = queued.title
		break
	for category: String in ["main", "side"]:
		if not presentation.is_empty(): break
		var selected := TaskCatalog.selected(_main.profile_progress, category)
		if selected.is_empty(): continue
		if selected == "tutorial":
			var hint_id := _tutorial_hint_id()
			var hint := TaskCatalog.tutorial_hint(hint_id)
			if hint_id == "supplies":
				hint.anchor = "inspection"
			if hint.is_empty() or not _tutorial_node_pending(hint_id): continue
			if is_instance_valid(_main._inspection_overlay) and hint_id not in ["supplies", "scraper_inspection", "rune_basics", "smith_tools", "militia_inspect", "militia_keywords"]: continue
			key = "tutorial:step:" + hint_id
			presentation = hint
			title = hint.title
			break
		if is_instance_valid(_main._inspection_overlay): continue
		var chapter := "supplies" if not _main.profile_progress.run.get("supplies", []).is_empty() else "day"
		if selected == "deep_survey":
			for card: OwnedCard in _main.owned_card_collection.get_cards():
				if card.card_data.id in [&"extinguished_lantern", &"flickering_lantern", &"blazing_lantern"]: chapter = String(card.card_data.id)
			if run.day == 8 and run.step == RunState.Step.BATTLE_RESULT: chapter = "ending"
		var candidate_key := TaskCatalog.story_key(selected, run.day, chapter)
		var candidate_text := _hint_text(selected)
		if candidate_text.is_empty(): continue
		key = candidate_key
		presentation = TaskCatalog.teaching_hint(candidate_key) if candidate_key == "supply_first:emblems" else TaskCatalog.story_hint(candidate_text)
		var pending: Dictionary = _main.profile_progress.hint_pending(key, presentation)
		if not pending.story and not pending.teaching:
			presentation = {}
			continue
		break
	if presentation.is_empty(): return
	var parts: Dictionary = _main.profile_progress.hint_pending(key, presentation)
	if not parts.story and not parts.teaching: return
	var shown := presentation.duplicate(true)
	var waiting_for_inspection := battle_intro_step == "battle_wounds" and not is_instance_valid(_main._inspection_overlay)
	if waiting_for_inspection: shown = TaskCatalog.tutorial_hint("battle_retreat")
	if battle_intro_step in ["battle_retreat", "battle_wounds"] and shown.anchor == "battle_card":
		var target := _battle_intro_card()
		if target != null:
			shown.instruction = String(shown.instruction).replace("高亮的敌方随从", "高亮的「%s」" % target.card_data.display_name)
	if not parts.story:
		shown["dialogue"] = []
		shown["story_text"] = ""
	if not parts.teaching: shown["instruction"] = ""
	var dialog := preload("res://scripts/ui/task_hint_overlay.gd").new()
	dialog.name = "TaskHint"
	dialog.title = String(shown.get("title", title))
	dialog.content = shown
	dialog.focus_rect = _hint_focus(String(shown.get("anchor", "event")))
	dialog.speaker = _main.player_avatar_button
	dialog.speaker_resolver = _tutorial_speaker
	dialog.portrait_resolver = _main.character_portrait
	dialog.complete_on_click = battle_intro_step in ["battle_intro", "battle_protection"]
	if presentation.get("anchor", "") == "militia": dialog.follow_target = _find_tutorial_card_view(&"militia")
	if shown.get("anchor", "") in ["hero", "collection"] and dialog.focus_rect == _hint_control_rect(_main.player_avatar_button):
		dialog.follow_target = _main.player_avatar_button
		dialog.silhouette_target = _main.player_avatar_button
	dialog.set_meta("hint_key", key)
	dialog.set_meta("start_day", run.day)
	dialog.set_meta("start_round", run.round_index)
	dialog.set_meta("formation", _formation_signature())
	dialog.set_meta("inspection", _main._inspection_owned_card)
	if key == "supply_first:emblems": dialog.set_meta("emblem_inventory", _main.emblem_library.get_inventory_state().duplicate(true))
	_main._hero_speech.dismiss()
	# 开包检视会在_input中先消费鼠标；提示期间交给上层按钮，关闭后再恢复。
	if dialog.action_rect.has_area() and is_instance_valid(_main._inspection_overlay): _main._inspection_overlay.set_process_input(false)
	dialog.inspection_dim = _main._inspection_dim
	_main.add_child(dialog)
	if battle_intro_step == "battle_wounds" and not waiting_for_inspection:
		_main.show_gameplay_teaching("tutorial:step:wounds", _main.GameplayTeachingToast.DEFAULT_SECONDS, true)
	if key == "tutorial:step:squad_sources" and run.day == 2 and run.step == RunState.Step.BATTLE_PREPARE:
		note_tutorial_action("stacking_unlocked")
	# 操作提示允许正常点击与拖拽。首战引导逐段保持暂停，最后由播放条继续。
	_main._task_hint_pause_requested = _main.current_phase == _main.GamePhase.BATTLE and not presentation.get("nonblocking", false)
	_main._sync_battle_pause_owners()
	dialog.tree_exited.connect(func():
		_main._task_hint_pause_requested = _battle_intro_pending()
		if is_instance_valid(_main._inspection_overlay): _main._inspection_overlay.set_process_input(true)
		if _main.is_inside_tree(): _main._sync_battle_pause_owners())
	var mark_read := func():
		if dialog._closing: return true
		var read_parts := {"story": parts.story and dialog._hero_done and dialog._narrative_done, "teaching": parts.teaching and dialog._teaching_done}
		if not read_parts.story and not read_parts.teaching: return true
		var previous_battle_profile: Dictionary = _main._profile_before_battle.duplicate(true)
		var saved: bool = _main.save_profile_action(func():
			_main.profile_progress.record_hint_read(key, presentation, read_parts)
			# 教学已阅属于界面记录；战中存盘仍保存战前阵容和任务挑战进度。
			if not _main._profile_before_battle.is_empty():
				_main._profile_before_battle.profile.tutorial = _main.profile_progress.profile.tutorial.duplicate(true)
				_main._profile_before_battle.run.read_story_nodes = _main.profile_progress.run.read_story_nodes.duplicate()
			return true)
		if not saved:
			_main._profile_before_battle = previous_battle_profile
			dialog.show_save_failure()
			return false
		if read_parts.teaching: parts.teaching = false
		if read_parts.story: parts.story = false
		dialog.save_recovered()
		if not parts.story and not parts.teaching:
			dialog.tree_exited.connect(show_task_hint, CONNECT_ONE_SHOT)
			dialog.dismiss()
		return true
	dialog.confirmed.connect(mark_read)
	dialog.teaching_completed.connect(mark_read)
	dialog.story_completed.connect(mark_read)


func _battle_intro_pending() -> bool:
	return not _battle_intro_step().is_empty()


func _battle_intro_step() -> String:
	if not _main.is_smith_tutorial() or run.day != 1 or run.step != RunState.Step.BATTLE_ACTIVE:
		return ""
	for id: String in BATTLE_INTRO_STEPS:
		if _tutorial_node_pending(id): return id
	return ""


func _battle_intro_card() -> CardView:
	var fallback: CardView
	for row: BattlefieldRow in [_main.enemy_front_row, _main.enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			for view: CardView in slot.get_card_views():
				if not view.is_visible_in_tree(): continue
				if view.card_data.id == &"mine_wailer": return view
				if fallback == null: fallback = view
	return fallback


func open_intro_card_at(point: Vector2) -> bool:
	var step := _battle_intro_step()
	if step not in ["battle_retreat", "battle_wounds"] or _main._escape_menu_pause_requested: return false
	var hint := _main.get_node_or_null("TaskHint")
	if not is_instance_valid(hint) or hint._closing or not hint.focus_rect.has_point(point): return false
	var target := _battle_intro_card()
	if not is_instance_valid(target) or not _hint_control_rect(target).has_point(point): return false
	_main._on_card_inspection_requested(target, target.card_data, target.get_owned_card())
	if not is_instance_valid(_main._inspection_overlay): return false
	if step == "battle_retreat":
		hint.complete_teaching()
	else:
		# 若提前关过检视或从战前档恢复，重新打开后接着看伤势说明。
		hint.tree_exited.connect(show_task_hint, CONNECT_ONE_SHOT)
		hint.dismiss()
	return true


func on_intro_inspection_closed() -> void:
	if _battle_intro_step() != "battle_wounds": return
	var hint := _main.get_node_or_null("TaskHint")
	if is_instance_valid(hint) and hint.get_meta("hint_key", "") == "tutorial:step:battle_wounds" and hint.content.anchor == "none":
		hint.complete_teaching()


func handle_intro_playback(slot: int) -> bool:
	var step := _battle_intro_step()
	if step.is_empty(): return false
	var hint := _main.get_node_or_null("TaskHint")
	if step == "battle_playback" and slot in [0, 1] and is_instance_valid(hint) and hint.get_meta("hint_key", "") == "tutorial:step:battle_playback":
		if slot == 1: _main.set_battle_speed(0)
		hint.complete_teaching()
	return true


func on_battle_started() -> void:
	if TaskCatalog.selected(_main.profile_progress, "main") != "tutorial" or run.day not in [1, 2]: return
	var hint := _main.get_node_or_null("TaskHint")
	if is_instance_valid(hint) and not hint._closing and not hint._teaching_done:
		var key := String(hint.get_meta("hint_key", ""))
		if _teaching_action_completed(key, hint): hint.complete_teaching()
		else:
			# 玩家提前开战可以收起未完成的练习，但不能把它误记为已完成。
			var id := key.trim_prefix("tutorial:step:")
			if _main.profile_progress.hint_pending(key, TaskCatalog.tutorial_hint(id)).story and not _queued_tutorial_stories.has(id): _queued_tutorial_stories.push_front(id)
			hint.tree_exited.connect(show_task_hint, CONNECT_ONE_SHOT)
			hint.dismiss()
	if not _battle_intro_pending(): return
	# 战斗时间轴先暂停，视角Tween仍可完成，随后显示战斗说明。
	if is_instance_valid(_main._view_tween): _main._view_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_main._task_hint_pause_requested = true
	_main._sync_battle_pause_owners()
	show_task_hint.call_deferred()


func _inspecting_militia() -> bool:
	return is_instance_valid(_main._inspection_overlay) and not _main._inspection_closing and _main._inspection_owned_card != null and _main._inspection_owned_card.card_data.id == &"militia"


func _militia_neighbor_active() -> bool:
	# 备战预览复用正式效果系统；检查实际生效实例，不另写一套乡邻种族／位置条件。
	for instance: BattleEffectInstance in _main.battle_controller.effect_runtime.active_instances:
		if instance.active and instance.definition.effect_id == &"militia.effect.01" and instance.source.state == instance.target: return true
	return false


func _formation_signature() -> Array:
	var rows: Array = []
	for row: BattlefieldRow in [_main.front_row, _main.back_row]:
		var squads: Array = []
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			squads.append([squad.horizontal_cards.map(func(card: CardData): return card.get_instance_id()), squad.layer_cards.map(func(card: CardData): return card.get_instance_id()), squad.two_card_layout])
		rows.append(squads)
	return rows


func _teaching_action_completed(key: String, hint: Control) -> bool:
	if hint._teaching_done or hint._closing: return false
	if key == "supply_first:emblems":
		return _main.emblem_library.get_inventory_state() != hint.get_meta("emblem_inventory")
	var previous_inspection: OwnedCard = hint.get_meta("inspection") if hint.has_meta("inspection") else null
	var id := key.trim_prefix("tutorial:step:")
	var advanced: bool = run.day != hint.get_meta("start_day") or run.round_index != hint.get_meta("start_round")
	match id:
		"shop_route": return advanced or run.step != RunState.Step.CHOOSING or (is_instance_valid(_event_table) and not _event_table.cards.is_empty())
		"shop_entered": return not _main.ordinary_shop_open or _main.ordinary_shop_service.offers.any(func(offer: Dictionary): return offer.get("sold", false))
		"deploy_view": return _main.current_world_view == _main.WorldView.COLLECTION
		"deploy": return _main.front_row.get_squad_count() + _main.back_row.get_squad_count() > 0
		"militia_inspect": return _inspecting_militia()
		"militia_keywords":
			if _inspecting_militia(): hint.set_meta("militia_inspection_seen", true)
			return hint.get_meta("militia_inspection_seen", false) and not _inspecting_militia()
		"militia_neighbor": return _militia_neighbor_active()
		"battle_ready": return run.step != RunState.Step.BATTLE_PREPARE
		"first_victory": return advanced or run.step != RunState.Step.BATTLE_RESULT
		"smith_tools": return is_instance_valid(_main._inspection_overlay) and _main._inspection_owned_card != null and _main._inspection_owned_card.card_data.card_type == CardData.CardType.MINION
		"scraper_inspection": return _main._rune_scraper_mode
		"rune_basics": return not is_instance_valid(_main._inspection_overlay) or _main._rune_scraper_mode or _main._inspection_owned_card != previous_inspection
		"formation": return run.step != RunState.Step.BATTLE_PREPARE or _formation_signature() != hint.get_meta("formation")
		"squad_sources":
			return advanced or (_has_stacked_squad() and (is_instance_valid(_main._inspection_overlay) or _formation_signature() != hint.get_meta("formation")))

	return false


func _hint_focus(anchor: String) -> Rect2:
	var target: Control = _panel
	match anchor:
		"initial_pack": target = _initial_pack_button
		"pack_seal":
			if is_instance_valid(_initial_pack_opening):
				var surface := _initial_pack_opening.surface
				return surface.get_global_transform_with_canvas() * Rect2(surface.content_padding, Vector2(_initial_pack_opening.tear_art.size.x, CardPackOpening.SEAL_HIT_HEIGHT))
		"event":
			if is_instance_valid(_event_table): target = _event_table.get_node_or_null("EventDescription")
			elif is_instance_valid(_detail_body): target = _detail_body
		"choices":
			if is_instance_valid(_event_table) and not _event_table.cards.is_empty():
				var area := Rect2()
				for card: Control in _event_table.cards:
					var rect := _hint_control_rect(card)
					area = rect if not area.has_area() else area.merge(rect)
				return area
		"shop": target = _main.ordinary_shop_panel
		"none": return Rect2()
		"battle_card":
			var card := _battle_intro_card()
			return _hint_control_rect(card).grow(4.0) if is_instance_valid(card) else Rect2()
		"battle_protection": return _status.life_track_rect()
		"battle_playback": return _hint_control_rect(_main.battle_speed_bar).grow(3.0)
		"formation": return _hint_control_rect(_main.front_row).merge(_hint_control_rect(_main.back_row))
		"collection": target = _main.collection_viewport if _main.current_world_view == _main.WorldView.COLLECTION else _main.player_avatar_button
		"militia": target = _find_tutorial_card_view(&"militia")
		"hero": target = _main.player_avatar_button
		"start_battle": target = _main.start_battle_button
		"result": target = _main.battle_result_panel
		"toolbox": target = _main._inspection_library_toggle
		"inspection": target = _main._inspection_surface
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		target = _main.battle_result_panel if _main.current_phase == _main.GamePhase.RESULT else _main.front_row
	return _hint_control_rect(target)


func _hint_control_rect(target: Control) -> Rect2:
	return target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)


func note_tutorial_action(action: String) -> void:
	if TaskCatalog.selected(_main.profile_progress, "main") != "tutorial": return
	if action == "rune_revealed" and _tutorial_node_pending("rune_basics"): _rune_lesson_waiting_for_release = true
	var progress: Dictionary = _main.profile_progress.run.tasks.main.progress
	if not progress.has("tutorial_actions"): progress["tutorial_actions"] = {}
	if progress.tutorial_actions.get(action, false): return
	progress.tutorial_actions[action] = true
	show_task_hint.call_deferred()


func _tutorial_node_pending(id: String) -> bool:
	var parts: Dictionary = _main.profile_progress.hint_pending("tutorial:step:" + id, TaskCatalog.tutorial_hint(id))
	return parts.story or parts.teaching


func can_stack_cards() -> bool:
	if not _main.is_smith_tutorial() or run.day >= 3: return true
	if run.day != 2: return false
	var actions: Dictionary = _main.profile_progress.run.tasks.main.progress.get("tutorial_actions", {})
	return actions.get("stacking_unlocked", false) or (run.step == RunState.Step.BATTLE_PREPARE and not _tutorial_node_pending("squad_sources"))


func _has_stacked_squad() -> bool:
	for row: BattlefieldRow in [_main.front_row, _main.back_row]:
		for slot: BoardSlot in row.get_squads():
			if slot.get_squad_data().get_card_count() > 1: return true
	return false


func _tutorial_hint_id() -> String:
	var progress: Dictionary = _main.profile_progress.run.tasks.main.progress
	var actions: Dictionary = progress.get("tutorial_actions", {})
	if not _main.profile_progress.run.get("supplies", []).is_empty():
		return ""
	if is_instance_valid(_initial_pack_opening) and _initial_pack_opening.phase in [CardPackOpening.Phase.ENLARGING, CardPackOpening.Phase.POSITIONING, CardPackOpening.Phase.SEALED, CardPackOpening.Phase.TEARING]:
		return ""
	if actions.get("initial_pack_torn", false) and _main.profile_progress.hint_pending("tutorial:step:supplies", TaskCatalog.tutorial_hint("supplies")).story: return "supplies"
	if not hero.pending_talent_levels.is_empty(): return ""
	if _main.current_phase == _main.GamePhase.PREPARE and actions.get("rune_revealed", false) and _tutorial_node_pending("rune_basics") and is_instance_valid(_main._inspection_overlay): return "rune_basics"
	match run.day:
		1:
			if run.step == RunState.Step.BATTLE_RESULT: return "first_victory" if run.battle_results.back().won else ""
			if run.step == RunState.Step.BATTLE_PREPARE:
				if _main.current_world_view != _main.WorldView.COLLECTION and _tutorial_node_pending("deploy_view"): return "deploy_view"
				if _main.front_row.get_squad_count() + _main.back_row.get_squad_count() == 0: return "deploy"
				if _main.owned_card_collection.find_first_by_definition(load("res://resources/cards/militia.tres")) != null:
					for id: String in ["militia_inspect", "militia_keywords", "militia_neighbor"]:
						if _tutorial_node_pending(id): return id
				return "battle_ready"
			if actions.get("event_reward", false) and _tutorial_node_pending("event_reward"): return "event_reward"
			if run.get_round_kind() == "shop":
				if _main.ordinary_shop_open:
					return "shop_entered"
				if run.step == RunState.Step.CHOOSING: return "shop_route"
		2:
			if run.step == RunState.Step.BATTLE_PREPARE:
				if _tutorial_node_pending("squad_sources"): return "squad_sources"
				return "formation"
			if progress.get("smith_received", false):
				if _tutorial_node_pending("smith"): return "smith"
				if not actions.get("smith_scraper_delivered", false): return ""
				if _tutorial_node_pending("smith_tools"): return "smith_tools"
				if actions.get("rune_revealed", false) and _tutorial_node_pending("rune_basics"): return "rune_basics"
				if is_instance_valid(_main._inspection_overlay) and not _main._inspection_read_only and _main._inspection_owned_card != null and _main._inspection_owned_card.card_data.card_type == CardData.CardType.MINION: return "scraper_inspection"
		3:
			if run.step not in [RunState.Step.BATTLE_ACTIVE, RunState.Step.BATTLE_RESULT] and _tutorial_node_pending("squad_sources"):
				if _has_stacked_squad() or run.round_index == 0: return "squad_sources"
		4:
			if run.step == RunState.Step.BATTLE_ACTIVE and actions.get("attack_observed", false): return "attack_observed"
	return ""


func _hint_text(task_id: String) -> String:
	var source := TaskCatalog.progress_text(task_id)
	if task_id in ["witch_cauldron", "portable_runes"]:
		return source.split("完成任务：")[0].trim_prefix("1-0\n").strip_edges() if run.day == 1 and run.round_index == 0 else ""
	if task_id == "deep_survey":
		var has_blazing: bool = _main.owned_card_collection.get_cards().any(func(card: OwnedCard): return card.card_data.id == &"blazing_lantern")
		var has_flickering: bool = _main.owned_card_collection.get_cards().any(func(card: OwnedCard): return card.card_data.id == &"flickering_lantern")
		if run.day == 8 and run.step == RunState.Step.BATTLE_RESULT and run.battle_results.back().won:
			return source.split("如果拥有炽烈青灯：")[1].split("如果未拥有炽烈青灯：")[0] + source.split("任务完成：")[1] if has_blazing else source.split("如果未拥有炽烈青灯：")[1].split("任务完成：")[0]
		var text := ""
		if has_blazing: text = source.split("获得炽烈青灯后")[1].split("1-8战斗胜利后")[0]
		elif has_flickering: text = source.split("获得摇曳青灯后")[1].split("获得炽烈青灯后")[0]
		elif run.day == 1 and run.round_index == 0: text = source.split("获得摇曳青灯后")[0].split("\n", false, 1)[1].strip_edges()
		return text
	if task_id in ["ironwall_support", "temple_boon"]:
		if run.round_index == 0 and run.day in [1, 9]:
			var chapters := source.split("任务完成：")[0].split("2-0")
			return chapters[0].replace("1-0", "").strip_edges() if run.day == 1 else chapters[1].strip_edges()
		return ""
	if task_id == "supply_first":
		if run.day == 1 and run.round_index == 0:
			if _main.profile_progress.run.get("supplies", []).is_empty(): return "纹章已收入工具箱。右键检视随从，展开工具箱后，把纹章拖到可用的纹章槽上。"
			return "后勤机器人：“哔……哔……铁壁关的先行补给已送达，后续的增员已经在路上。”\n伊奥恩：“铁壁关那帮人总算没全忘了这儿。”\n\n后勤机器人已加入收藏并上场，打开补给中的纹章包领取试用纹章。"
		return ""
	return ""


func _grant_pack(large: bool, themed: bool = false, count_mission: bool = true) -> bool:
	var owned: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var candidates := shop._eligible_cards(_main._get_shop_card_definitions(), owned)
	var result := (shop.draw_reward_card_pack(candidates, "large" if large else "small", run.rng, owned)
		if themed else shop.draw_card_pack(candidates, large, 5 if large else 3, run.rng, owned))
	if not bool(result.get("success", false)):
		return false
	for card: CardData in result.cards:
		_main.owned_card_collection.create_card(card, run.rng, result.cards, true)
	if count_mission: _main.record_secret_mission_progress(OwnedCard.MissionGoal.PACKS, owned)
	return true


func _grant_emblem(id: String, receipt: String) -> bool:
	var state := {"instance_id": receipt, "emblem_id": id, "temporary": false, "source": "maze_reward"}
	return _main.emblem_library.receive_stickers([state])


func complete_event(take_reward: bool = true, discard_confirmed: bool = false, source_button: BaseButton = null) -> bool:
	if _event_presentation_busy(): return false
	if run.step != RunState.Step.EVENT or run.get_round_kind() == "shop" or run.selected_path.has("mining_progress") or (take_reward and run.selected_path.get("reward") in ["enhance_card", "story"] and not run.selected_path.has("story_result") and not run.selected_path.has("enhancement_result")):
		return false
	var event: Dictionary = run.selected_path
	var from_button := is_instance_valid(source_button)
	var awards: Array[Dictionary] = []
	awards.assign(event.get("reward_items", []))
	# 刚领到的超额贴纸先飞到临时区，玩家整理后再沿原有流程确认离开。
	var show_overflow := from_button and awards.any(func(item: Dictionary) -> bool:
		return item.kind == "sticker" and EmblemStickerInventory.is_dropped(_main.emblem_library.get_inventory_item(StringName(item.id))))
	if not from_button: source_button = _find_exit_button(complete_event.bind(take_reward))
	if not show_overflow and not discard_confirmed and not _main.confirm_temporary_sticker_discard(source_button): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	if not show_overflow: _main.emblem_library.discard_dropped_stickers()
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
		if run.day == 1 and run.get_round_kind() == "free_event" and event.reward in ["gold", "pack", "minion", "emblem"]:
			note_tutorial_action("event_reward")
		var awarded := EventRewards.collect(_main, previous)
		if not awarded.is_empty():
			event["reward_claimed"] = true
			event["reward_items"] = awarded
			return _commit_transaction(previous)
	if String(event.path_id).begins_with("tutorial_fortuna_") and event.has("story_result"):
		note_tutorial_action("event_reward")
	var animate_awards := from_button and not awards.is_empty()
	var origins := _event_reward_origins(awards, source_button) if animate_awards else {}
	if show_overflow:
		event.erase("reward_items")
	elif not run.complete_event():
		_rollback_transaction(previous)
		return false
	else:
		_generate_paths()
	if animate_awards: _event_reward_in_flight.assign(awards)
	if not _commit_transaction(previous, not show_overflow, not animate_awards): return false
	if animate_awards: _play_event_reward_flight(origins, show_overflow)
	return true


func choose_story_option(index: int) -> bool:
	if _event_presentation_busy(): return false
	var event: Dictionary = run.selected_path
	if run.step != RunState.Step.EVENT or event.get("reward") != "story" or event.has("story_result") or index < 0 or index >= event.options.size():
		return false
	var option := story_events.runtime_option(event, index)
	var target: OwnedCard = _main.owned_card_collection.get_by_instance_id(_enhancement_card_id)
	if not _story_blocked_reason(option, target).is_empty():
		return false
	var previous := _capture_transaction()
	var result := {"outcome_index": 0, "roll": 4, "guaranteed": true} if option.get("mine_prayer", false) and not _story_owned("ember_empty_bottle").is_empty() else story_events.draw_outcome(option, run.rng, 0 if _story_owned("nyx_dice").is_empty() else 2)
	if result.is_empty():
		_rollback_transaction(previous)
		return false
	result["option_index"] = index
	var outcome: Dictionary = option.outcomes[int(result.outcome_index)]
	_main.run_reward_state.gold -= int(outcome.get("cost", _story_option_cost(option)))
	_main.run_reward_state.add_gold(int(outcome.get("gold", 0)))
	var gilded_cards: Array[OwnedCard] = []
	if not _apply_story_effects(event, option, outcome, target, result, gilded_cards):
		_rollback_transaction(previous)
		return false
	var skipped_packs: Array[String] = []
	for pack: String in outcome.get("packs", []):
		if not _grant_pack(pack == "large", true):
			if int(option.cost) > 0:
				_rollback_transaction(previous)
				return false
			skipped_packs.append("大卡包" if pack == "large" else "小卡包")
	if not skipped_packs.is_empty():
		result["skipped_packs"] = skipped_packs
	var receipt := "maze_story:%d:%s:%d" % [run.day, event.path_id, run.round_index]
	if outcome.has("sticker"):
		_grant_emblem(String(outcome.sticker), receipt)
	if outcome.has("indicator"):
		var inventory: Dictionary = _main.celestial_indicators.capture_state()
		inventory.items.append({"instance_id": receipt, "kind": CelestialIndicator.Kind[String(outcome.indicator)], "star_transfer_count": 0})
		_main.celestial_indicators.restore_state(inventory)
	if not result.get("mining_continues", false):
		run.selected_path["story_result"] = result
		run.selected_path["reward_claimed"] = true
		var awarded := EventRewards.collect(_main, previous, gilded_cards)
		if not awarded.is_empty(): event["reward_items"] = awarded
	var animate_roll: bool = result.has("roll") and not result.get("guaranteed", false) and is_instance_valid(_event_table)
	if not _commit_transaction(previous, false, not animate_roll):
		return false
	var show_reward_pack := _present_story_gilded_pack.bind(gilded_cards) if not gilded_cards.is_empty() else Callable()
	if animate_roll:
		_play_story_roll(int(option.roll_sides), int(result.roll), show_reward_pack)
	elif show_reward_pack.is_valid():
		show_reward_pack.call()
	return true


func _present_story_gilded_pack(cards: Array[OwnedCard]) -> void:
	# 奖励已经存档，开包界面只展示刚获得的三个实例。
	_main._open_shop_pack_inspection({"kind": "card_pack", "pack_id": "gilded_commission", "size": "small"}, null, true, cards)


func _story_blocked_reason(option: Dictionary, target: OwnedCard, ignore_gold: bool = false) -> String:
	var blocked := story_events.blocked_reason(option, 2147483647 if ignore_gold else int(_main.run_reward_state.gold))
	if not blocked.is_empty(): return blocked
	blocked = MiningEvents.blocked_reason(self, option)
	if not blocked.is_empty(): return blocked
	if option.has("bounty_target"):
		if _story_locked_target(0) == null: return "悬赏目标已离开收藏"
		if _main.run_reward_state.gold < _story_option_cost(option): return "金币不足，需要%d金币" % _story_option_cost(option)
	if option.has("dispute_targets") and (_story_locked_target(0) == null or _story_locked_target(1) == null):
		return "参与争执的随从已离开收藏"
	if option.has("target") and not _matches_story_target(option, target): return "请把符合条件的随从拖入右侧卡槽"
	if option.has("requires_hero") and option.requires_hero != _main.profile_progress.run.hero: return "需要使用伊奥恩"
	if option.get("requires_faction") == "hansa" and _main.profile_progress.run.hero == ProfileProgress.INITIAL_HERO: return "需要汉萨联邦英雄"
	if option.has("requires_card") and _story_owned(String(option.requires_card)).is_empty(): return "缺少指定卡牌"
	if option.has("requires_race") and not _story_minions().any(func(card: OwnedCard) -> bool: return int(card.card_data.race_type) == int(option.requires_race)): return "需要拥有符合种族的随从"
	if option.has("food_choices") and _selected_story_food(option).size() != 3: return "请选择三枚未装备的食物纹章"
	for key: String in ["sticker_cost", "requires_sticker"]:
		if option.has(key) and _story_stickers(String(option[key])).is_empty(): return "需要纹章「%s」" % option[key]
	for outcome: Dictionary in option.outcomes:
		if int(option.cost) > 0:
			for pack: String in outcome.get("packs", []):
				if not _can_draw_story_pack(pack): return "当前无法发放普通卡包"
		for effect: Dictionary in outcome.get("effects", []):
			match String(effect.kind):
				"card", "wounded_card":
					if _story_card(String(effect.card), String(effect.get("unlocked_by", ""))) == null: return "指定卡牌当前不可获得"
				"random_cards":
					if int(option.cost) > 0 and _story_card_pool(effect).is_empty(): return "当前没有合格卡牌"
				"slave_card":
					if _story_card_pool(effect).is_empty(): return "当前没有合格随从"
				"scrapers":
					if not _main.run_item_enabled("scraper"): return "尚未开放符文刮刀"
				"emblem_pack":
					if not _main.run_pack_enabled("emblem_pack"): return "尚未开放纹章包"
				"send_muleteer":
					if _story_owned("baggage_muleteer").is_empty(): return "需要辎重驮夫"
				"whole_pack":
					if _story_whole_pack(String(effect.pack)).is_empty(): return "指定卡包当前无法完整发放"
				"nature":
					if _story_stickers("树").size() + _story_stickers("木贴纸").size() < 2: return "需要合计两枚树纹章或木贴纸"
				"event_battle":
					if story_events.event_encounter(run.selected_path.path_id, floor_number(), bool(effect.get("enemy_first", false))).is_empty(): return "战斗阵容待补充"
					if run.selected_path.path_id == "bounty_hunter" and not effect.get("enemy_first", false) and _story_deployed().is_empty(): return "备战场需要至少一名随从"
				"casino_cheat":
					if _story_owned("nyx_dice").is_empty(): return "需要持有奈克斯的骰子"
				"gilded_pack":
					if _gilded_pack_pool().size() < 3: return "当前没有三张可获得的镀金委托卡"
				"random_pack":
					if not _can_draw_story_pack(String(effect.size)): return "当前无法发放普通卡包"
				"trade_potion":
					if _selected_story_materials(effect.rarities).size() != effect.rarities.size(): return "请选择各品级的随从材料"
					for variant: int in 3:
						if _story_card("event_forbidden_%s_%d" % [effect.tier, variant], "event") == null: return "有候选禁药已持有或不可获得"
	return ""


func _can_draw_story_pack(size: String) -> bool:
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var owned: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	var probe := RandomNumberGenerator.new()
	probe.state = run.rng.state
	return shop.draw_reward_card_pack(shop._eligible_cards(_main._get_shop_card_definitions(), owned), size, probe, owned).success


func _story_option_cost(option: Dictionary) -> int:
	if not option.get("bounty_bribe", false): return int(option.cost)
	var target := _story_locked_target(0)
	return _main._shop_card_sale_price(target) + 5 if target != null else 0


func _story_locked_target(index: int) -> OwnedCard:
	var ids: Array = run.selected_path.get("story_targets", [])
	return _main.owned_card_collection.get_by_instance_id(StringName(ids[index])) if index < ids.size() else null


func _story_minions() -> Array[OwnedCard]:
	var cards: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	return cards.filter(func(card: OwnedCard) -> bool: return card.card_data.card_type == CardData.CardType.MINION)


func _story_whole_pack(pack: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	if not _main.run_pack_enabled(pack): return cards
	for card: CardData in _main._get_shop_card_definitions():
		if card.is_available and not card.is_derived and String(card.pack_id) == pack:
			if card.is_unique_while_owned() and not _story_owned(String(card.id)).is_empty():
				cards.clear()
				return cards
			cards.append(card)
	return cards


func _matches_story_target(option: Dictionary, card: OwnedCard) -> bool:
	return card != null and card.card_data.card_type == CardData.CardType.MINION \
		and int(option.get("target_rarity", card.card_data.rarity)) == card.card_data.rarity \
		and int(option.get("target_race", card.card_data.race_type)) == card.card_data.race_type


func _story_owned(id: String) -> Array[OwnedCard]:
	var cards: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	return cards.filter(func(card: OwnedCard) -> bool: return String(card.card_data.id) == id)


func _story_stickers(id: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for item: Dictionary in _main.emblem_library.get_inventory_state():
		if item.get("emblem_id") == id: candidates.append({"item": item})
	for owned: OwnedCard in _main.owned_card_collection.get_cards():
		for item: Dictionary in owned.emblem_slots + owned.rune_stickers:
			if item.get("emblem_id") == id: candidates.append({"item": item, "owner": owned})
	return candidates


func _consume_story_sticker(id: String) -> bool:
	var choices := _story_stickers(id)
	if choices.is_empty(): return false
	var choice: Dictionary = choices[run.rng.randi_range(0, choices.size() - 1)]
	if choice.has("owner"):
		return not _main._remove_owned_sticker_instance(choice.owner, StringName(choice.item.instance_id)).is_empty()
	return _main.emblem_library.consume_returned(choice.item)


func _selected_story_food(option: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_story_food_picker): return result
	for index: int in _story_food_picker.get_selected_items():
		var id := StringName(_story_food_picker.get_item_metadata(index))
		var current: Dictionary = _main.emblem_library.get_inventory_item(id)
		if String(current.get("emblem_id", "")) in option.food_choices: result.append(current)
	return result


func _selected_story_materials(rarities: Array) -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	for value: Variant in rarities:
		var rarity := int(value)
		var picker := _story_material_pickers.get(rarity) as OptionButton
		if not is_instance_valid(picker) or picker.selected < 1: continue
		var id := StringName(picker.get_item_metadata(picker.selected))
		var owned: OwnedCard = _main.owned_card_collection.get_by_instance_id(id)
		if owned != null and owned.card_data.card_type == CardData.CardType.MINION and int(owned.card_data.rarity) == rarity: result.append(owned)
	return result


func _story_card(id: String, unlocked_by: String = "") -> CardData:
	var card: CardData = _main._build_card_definition_registry().get(StringName(id))
	if card == null or not card.is_available: return null
	if unlocked_by != "event" and card.pack_id != &"event_relics" and not _main.run_pack_enabled(String(card.pack_id) if unlocked_by.is_empty() else unlocked_by): return null
	if card.is_unique_while_owned() and not _story_owned(id).is_empty(): return null
	return card


func _gilded_pack_pool() -> Array[CardData]:
	var cards: Array[CardData] = []
	if not _main.run_pack_enabled("gilded_commission"): return cards
	for definition: CardData in _main._get_shop_card_definitions():
		if definition.pack_id == &"gilded_commission" and definition.rarity == CardData.Rarity.IV and definition.is_available and not definition.is_derived and _story_owned(String(definition.id)).is_empty():
			cards.append(definition)
	return cards


func _story_card_pool(effect: Dictionary) -> Array[CardData]:
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var definitions: Array[CardData] = _main._get_shop_card_definitions()
	var owned: Array[OwnedCard] = _main.owned_card_collection.get_cards()
	var pool := shop._eligible_cards(definitions, owned)
	if effect.get("other_faction", false):
		# 雾中人额外接纳已永久解锁、当局未启用的阵营包。
		var exception := OrdinaryShopService.new()
		exception.config = shop.config.duplicate(true)
		for pack: String in _main.profile_progress.profile.unlocks.packs:
			if pack not in exception.config.allowed_pack_ids: exception.config.allowed_pack_ids.append(pack)
		pool = exception._eligible_cards(definitions, owned)
	return pool.filter(func(card: CardData) -> bool:
		if effect.has("rarity") and card.rarity != int(effect.rarity): return false
		if effect.has("race") and card.race_type != int(effect.race): return false
		if effect.get("other_faction", false) and card.get_effective_faction() == CardFaction.Id.RADIANT_ALLIANCE: return false
		match String(effect.get("card_type", "")):
			"minion": return card.card_type == CardData.CardType.MINION
			"equipment": return card.card_type == CardData.CardType.EQUIPMENT
			"mineral": return card.card_type == CardData.CardType.RESOURCE and card.resource_type == CardData.ResourceType.MINERAL
		return true
	)


func _story_deployed() -> Array[OwnedCard]:
	var cards: Array[OwnedCard] = []
	for row: BattlefieldRow in [_main.front_row, _main.back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			for card: CardData in squad.horizontal_cards:
				var owned := squad.get_owned_card(card)
				if owned != null and owned not in cards: cards.append(owned)
	return cards


func _story_targets(effect: Dictionary, target: OwnedCard) -> Array[OwnedCard]:
	var cards: Array[OwnedCard] = []
	match String(effect.get("target", "selected")):
		"selected":
			if target != null: cards.append(target)
		"deployed", "strongest_melee": cards = _story_deployed()
		"dispute":
			for index: int in effect.get("indices", [0, 1]):
				var card := _story_locked_target(index)
				if card != null: cards.append(card)
		"all", "last_battle":
			cards = _main.owned_card_collection.get_cards()
			cards = cards.filter(func(card: OwnedCard) -> bool:
				return card.card_data.card_type == CardData.CardType.MINION and (effect.target == "all" or String(card.instance_id) in story_participants))
	if effect.get("target") == "strongest_melee":
		cards = cards.filter(func(card: OwnedCard) -> bool: return card.resolved_action_type == CardData.ActionType.MELEE)
		var highest := -1
		for card: OwnedCard in cards: highest = maxi(highest, card.get_effective_base_value())
		cards = cards.filter(func(card: OwnedCard) -> bool: return card.get_effective_base_value() == highest)
	return cards


func _apply_story_effects(event: Dictionary, option: Dictionary, outcome: Dictionary, target: OwnedCard, result: Dictionary, gilded_cards: Array[OwnedCard]) -> bool:
	var receipt := "story:%d:%s:%d" % [run.day, event.path_id, run.round_index]
	var source := {"kind": "event", "event_id": event.path_id, "name": event.name}
	var no_reserved: Array[CardData] = []
	if option.has("sticker_cost") and not _consume_story_sticker(String(option.sticker_cost)): return false
	if option.has("food_choices"):
		for food: Dictionary in _selected_story_food(option):
			if not _main.emblem_library.consume_returned(food): return false
	for index: int in outcome.get("effects", []).size():
		var effect: Dictionary = outcome.effects[index]
		var effect_receipt := "%s:%d" % [receipt, index]
		match String(effect.kind):
			"casino_cheat":
				if effect.get("caught", false):
					var balance: int = _main.run_reward_state.gold
					_main.run_reward_state.gold -= floori(float(balance) * 2.0 / 3.0)
				else: _main.run_reward_state.add_gold(60)
			"gold":
				_main.run_reward_state.add_gold(int(effect.amount))
			"random_pack":
				if not _grant_pack(effect.size == "large", true): return false
			"gilded_pack":
				var owned: Array[OwnedCard] = _main.owned_card_collection.get_cards()
				var shop: OrdinaryShopService = _main.ordinary_shop_service
				var drawn := shop.draw_card_pack(_gilded_pack_pool(), false, 3, run.rng, owned, &"gilded_commission")
				if not drawn.success: return false
				for definition: CardData in drawn.cards:
					var acquired: OwnedCard = _main.owned_card_collection.create_card(definition, run.rng, drawn.cards, true, source)
					if acquired == null: return false
					gilded_cards.append(acquired)
				_main.record_secret_mission_progress(OwnedCard.MissionGoal.PACKS, owned)
			"trade_potion":
				var materials := _selected_story_materials(effect.rarities)
				if materials.size() != effect.rarities.size(): return false
				var reward := _story_card("event_forbidden_%s_%d" % [effect.tier, run.rng.randi_range(0, 2)], "event")
				if reward == null: return false
				for material: OwnedCard in materials:
					_main._remove_owned_instance_from_rows(material.instance_id)
					if _main.owned_card_collection.remove_by_instance_id(material.instance_id) == null: return false
				if _main.owned_card_collection.create_card(reward, run.rng, no_reserved, false, source) == null: return false
				result["effect_text"] = "交换完成，获得%s。" % reward.display_name
			"event_battle":
				event.erase("mining_progress")
				var encounter := story_events.event_encounter(event.path_id, floor_number(), bool(effect.get("enemy_first", false)))
				if encounter.is_empty(): return false
				encounter["battle_seed"] = run.rng.randi_range(0, _main.BATTLE_SEED_MAX)
				if not run.prepare_event_battle(encounter) or not _build_enemy(): return false
			"battle_buff":
				_queue_story_buff(effect, target)
			"shrine_blessing":
				var kinds := [["zeal", 3], ["action_value", 1], ["base_armor", 4], ["max_health", 3]]
				var rolled: Array = kinds[run.rng.randi_range(0, kinds.size() - 1)]
				_queue_story_buff({"stat": rolled[0], "value": rolled[1]}, null)
			"growth":
				var cards := _story_targets(effect, target)
				var count := mini(int(effect.get("count", cards.size())), cards.size())
				for _index: int in count:
					var card: OwnedCard = cards.pop_at(run.rng.randi_range(0, cards.size() - 1)) if effect.has("count") else cards.pop_front()
					for stat: StringName in [OwnedCard.STAT_BASE_VALUE, OwnedCard.STAT_MAX_HEALTH, OwnedCard.STAT_BASE_ARMOR]:
						var amount := int(effect.get(String(stat), 0))
						if stat == OwnedCard.STAT_MAX_HEALTH and amount < 0:
							amount = maxi(amount, 1 - int(card.get_base_stat_with_permanent_growth(stat)))
						card.apply_permanent_growth(stat, amount)
			"dispute_emblem":
				for index_value: int in effect.get("indices", [0, 1]):
					var card := _story_locked_target(index_value)
					if card != null: _attach_story_emblem(card, "%s:%d" % [effect_receipt, index_value])
			"dispute_zeal":
				_queue_story_buff({"stat": "zeal", "value": -5, "target": "selected"}, _story_locked_target(int(effect.index)))
			"nature":
				if not _story_stickers("树").is_empty():
					if not _consume_story_sticker("树"): return false
				elif not _consume_story_sticker("木贴纸") or not _consume_story_sticker("木贴纸"):
					return false
			"bounty_handover":
				var surrendered := _story_locked_target(0)
				_main._remove_owned_instance_from_rows(surrendered.instance_id)
				_main.owned_card_collection.remove_by_instance_id(surrendered.instance_id)
				story_shop_discount = true
			"whole_pack":
				var cards := _story_whole_pack(String(effect.pack))
				if cards.is_empty(): return false
				for card: CardData in cards:
					if _main.owned_card_collection.create_card(card, run.rng, cards, false, source) == null: return false
			"heal", "wound":
				_apply_story_wounds(effect, _story_targets(effect, target), effect_receipt)
			"hellfire_wound":
				var leaders: Array = last_reward.get("damage_leaders", [])
				result["effect_text"] = "业火未能附着。"
				if not leaders.is_empty():
					var chosen: OwnedCard = _main.owned_card_collection.get_by_instance_id(StringName(leaders[run.rng.randi_range(0, leaders.size() - 1)]))
					var targets: Array[OwnedCard] = []
					if chosen != null: targets.append(chosen)
					_apply_story_wounds({"kind": "wound", "wound": "业火"}, targets, effect_receipt)
					if chosen != null and chosen.wound_slots.any(func(wound: Dictionary) -> bool: return wound.get("instance_id") == effect_receipt):
						result["effect_text"] = "%s获得业火伤势。" % chosen.card_data.display_name
			"small_potion":
				var mask := 1 << run.rng.randi_range(0, 3)
				var growth := PotionRules.growth(mask, target)
				for stat: StringName in growth:
					target.apply_permanent_growth(stat, growth[stat])
				if mask & PotionRules.SWIFT:
					target.progress_by_source[PotionRules.PERMANENT_ZEAL] = int(target.progress_by_source.get(PotionRules.PERMANENT_ZEAL, 0)) + 1
			"small_forbidden_potion":
				PotionRules.add_locked_wound(target, rewards.config.wound_event.wound_ids, run.rng, effect_receipt)
				match int(effect.variant):
					0:
						target.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 1)
						target.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 2)
					1: target.progress_by_source[PotionRules.PERMANENT_ZEAL] = int(target.progress_by_source.get(PotionRules.PERMANENT_ZEAL, 0)) + 5
					2: _queue_story_buff({"stat": "protection", "value": 1, "target": "selected", "battles": -1}, target)
			"remove_selected", "remove_reserve", "send_muleteer", "sell_slave":
				var candidates: Array[OwnedCard] = []
				if effect.kind in ["remove_selected", "sell_slave"] and target != null: candidates.append(target)
				elif effect.kind == "send_muleteer": candidates = _story_owned("baggage_muleteer")
				elif effect.kind == "remove_reserve":
					var deployed_cards := _story_deployed()
					candidates = _main.owned_card_collection.get_cards().filter(func(card: OwnedCard) -> bool:
						return card.card_data.card_type == CardData.CardType.MINION and card not in deployed_cards)
				if not candidates.is_empty():
					var removed := candidates[run.rng.randi_range(0, candidates.size() - 1)]
					_main._remove_owned_instance_from_rows(removed.instance_id)
					_main.owned_card_collection.remove_by_instance_id(removed.instance_id)
					if effect.kind == "send_muleteer": story_score += 1000
					if effect.kind == "sell_slave": _main.run_reward_state.add_gold(3 * (int(removed.card_data.rarity) + 1))
			"consume_sticker":
				if not _consume_story_sticker(String(effect.sticker)): return false
			"stickers", "emblem_pack":
				if not _grant_story_stickers(effect, effect_receipt): return false
			"scrapers":
				_main.scraper_count += int(effect.count)
				_main.emblem_library.set_scraper_count(_main.scraper_count)
			"random_gold": _main.run_reward_state.add_gold(run.rng.randi_range(int(effect.low), int(effect.high)))
			"random_cards", "slave_card":
				for _draw: int in int(effect.get("count", 1)):
					var pool := _story_card_pool(effect)
					if pool.is_empty():
						if int(option.cost) > 0: return false
						break
					var shop: OrdinaryShopService = _main.ordinary_shop_service
					var card := shop.draw_card_candidate(pool, run.rng, shop.count_owned_cards(_main.owned_card_collection.get_cards()))
					var received: OwnedCard = _main.owned_card_collection.create_card(card, run.rng, no_reserved, false, source)
					if received == null: return false
					if effect.kind == "slave_card":
						var slot := received.emblem_slots.find({})
						if slot < 0 or not received.set_emblem_slot(slot, {"emblem_id": "奴隶镣铐", "instance_id": effect_receipt, "temporary": false, "source": "maze_event"}): return false
			"card", "wounded_card":
				var owned: OwnedCard = _main.owned_card_collection.create_card(_story_card(String(effect.card), String(effect.get("unlocked_by", ""))), run.rng, no_reserved, false, source)
				if owned == null: return false
				if effect.kind == "wounded_card":
					for wound_index: int in int(effect.count):
						var targets: Array[OwnedCard] = [owned]
						if not rewards.apply_random_event_wound("%s:%d" % [effect_receipt, wound_index], targets, run.rng).success: return false
			"hero_experience": hero.grant_experience(effect_receipt, hero.level)
			"task_scroll":
				var inventory: Dictionary = _main.celestial_indicators.capture_state()
				inventory.items.append({"instance_id": effect_receipt, "kind": CelestialIndicator.Kind[String(effect.scroll)], "task_progress": 0})
				_main.celestial_indicators.restore_state(inventory)
			_:
				if not MiningEvents.apply(self, event, effect, target, result, effect_receipt, source): return false
	return true


func _grant_story_stickers(effect: Dictionary, receipt: String) -> bool:
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var names: Array = effect.get("names", [])
	var count := int(shop.config.sticker_pack.sticker_count) if effect.kind == "emblem_pack" else int(effect.count)
	var picks: Array[Dictionary] = []
	for index: int in count:
		var id: String
		if names.is_empty():
			var candidates := shop._eligible_stickers(_main._get_shop_sticker_definitions(), _main._get_all_held_stickers(), picks)
			if effect.kind != "emblem_pack":
				candidates = candidates.filter(func(item: Dictionary) -> bool: return item.get("target", "emblem") != "rune")
			var picked := shop._draw_sticker(candidates, run.rng)
			if picked.is_empty(): return false
			id = String(picked.id)
			picks.append(picked)
		else: id = String(names[run.rng.randi_range(0, names.size() - 1)])
		if not _grant_emblem(id, "%s:%d" % [receipt, index]): return false
	return true


func _attach_story_emblem(card: OwnedCard, receipt: String) -> void:
	var slot := card.emblem_slots.find({})
	if slot < 0: return
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var pool := shop._eligible_stickers(_main._get_shop_sticker_definitions(), _main._get_all_held_stickers(), [])
	pool = pool.filter(func(item: Dictionary) -> bool: return item.get("target", "emblem") != "rune")
	var picked := shop._draw_sticker(pool, run.rng)
	if not picked.is_empty():
		card.set_emblem_slot(slot, {"emblem_id": picked.id, "instance_id": receipt, "temporary": false, "source": "maze_event"})


func _apply_story_wounds(effect: Dictionary, cards: Array[OwnedCard], receipt: String) -> void:
	var empty := String(effect.kind) == "wound"
	cards = cards.filter(func(card: OwnedCard) -> bool:
		return card.wound_slots.any(func(slot: Dictionary) -> bool: return slot.is_empty() == empty and not slot.get("locked", false)))
	if cards.is_empty(): return
	var target := cards[run.rng.randi_range(0, cards.size() - 1)]
	var slots: Array[int] = []
	for index: int in target.wound_slots.size():
		if target.wound_slots[index].is_empty() == empty and not target.wound_slots[index].get("locked", false): slots.append(index)
	if empty:
		var slot := slots[run.rng.randi_range(0, slots.size() - 1)]
		target.set_wound_slot(slot, {"wound_id": effect.wound, "instance_id": receipt, "level": 1, "temporary": false, "source": "maze_event"})
	elif int(effect.count) < 0:
		for index: int in slots: target.set_wound_slot(index, {})
	else:
		target.set_wound_slot(slots[run.rng.randi_range(0, slots.size() - 1)], {})


func _queue_story_buff(effect: Dictionary, target: OwnedCard) -> void:
	var buff := effect.duplicate(true)
	buff["battles"] = int(effect.get("battles", 1))
	if effect.get("scope") == "floor": buff["floor"] = floor_number()
	if target != null and effect.get("target") == "selected": buff["instance_id"] = String(target.instance_id)
	story_buffs.append(buff)


func leave_shop(discard_confirmed: bool = false) -> bool:
	if run.step != RunState.Step.EVENT or run.get_round_kind() != "shop":
		return false
	if not discard_confirmed and not _main.confirm_shop_leave(): return false
	var previous := _capture_transaction()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	story_shop_discount = false
	if not run.complete_event():
		_rollback_transaction(previous)
		return false
	_generate_paths()
	return _commit_transaction(previous, true)


func _enemy_revealed_count() -> int:
	if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial": return 0
	var floor_key := str(floor_number())
	return clampi(int(content.get("enemy_rune_reveals_by_floor", {}).get(floor_key, 1)), 0, 3)


func _enemy_emblem_count() -> int:
	if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial": return 0
	var counts: Array = content.get("enemy_emblems_by_day", [])
	return maxi(int(counts[clampi(run.day - 1, 0, counts.size() - 1)]), 0) if not counts.is_empty() else 0


func _build_enemy() -> bool:
	var path := run.battle_path()
	var registry: Dictionary = _main._build_card_definition_registry()
	var builder := EncounterBuilder.new()
	if not path.has("encounter_state"):
		var generated := builder.build(path, registry, _enemy_revealed_count(), _enemy_emblem_count())
		if generated.is_empty(): return false
		var rng := RandomNumberGenerator.new()
		rng.seed = int(path.battle_seed) ^ 0x5EED
		for id: String in ([] if _main.is_smith_tutorial() else path.get("resources", [])):
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
		path["encounter_state"] = generated
	var encounter := builder.restore(path.encounter_state, registry)
	if encounter.is_empty(): return false
	for pair: Array in [[_main.enemy_front_row, &"enemy_front"], [_main.enemy_back_row, &"enemy_back"]]:
		_main._restore_row_from_snapshot(pair[0], encounter.rows[pair[1]])
		pair[0].set_drag_enabled(false)
	_main._refresh_resource_preparation_trays()
	_main.battle_seed_spin.value = int(path.battle_seed)
	return true


func get_enemy_prepared_spells() -> Array[OwnedCard]:
	var path := run.battle_path()
	if not path.has("encounter_state"): return []
	var encounter := EncounterBuilder.new().restore(path.encounter_state, _main._build_card_definition_registry())
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
			if hero.has_talent("sentry_unbreakable"): capacity *= int(rewards.config.talents.sentry_unbreakable.confirmed_rules.capacity_multiplier)
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


func can_finish_floor() -> bool:
	return TaskCatalog.selected(_main.profile_progress, "main").is_empty() and not run.is_event_battle() and run.step == RunState.Step.BATTLE_RESULT and run.day % RunState.DAYS == 0 and not run.battle_results.is_empty() and run.battle_results.back().won


func can_start_battle() -> bool:
	return run.step == RunState.Step.BATTLE_PREPARE and hero.pending_talent_levels.is_empty() and not _event_presentation_busy()


func slide_battle_board(start: Callable) -> void:
	if not can_start_battle(): return
	if _main.current_world_view != _main.WorldView.BATTLEFIELDS or not _panel.is_visible_in_tree() or not _panel.get_global_rect().intersects(_main.get_viewport_rect()):
		start.call()
		return
	_main._cancel_click_carry()
	_battle_board_input_blocker = Control.new()
	_battle_board_input_blocker.name = "BattleBoardTransitionInput"
	_battle_board_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_battle_board_input_blocker.z_index = 3900 # 阻挡重复部署和点击，Esc菜单在独立上层
	_main.add_child(_battle_board_input_blocker)
	_battle_board_input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_board_exit = _panel.create_tween()
	_battle_board_exit.tween_property(_panel, "position:y", _panel.position.y - _panel.get_global_rect().end.y, BATTLE_BOARD_EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_battle_board_exit.tween_callback(func():
		_clear_battle_board_exit()
		start.call())


func _clear_battle_board_exit() -> void:
	if not is_instance_valid(_battle_board_exit): return
	_battle_board_exit.kill()
	_battle_board_exit = null
	if is_instance_valid(_panel): _panel.position = PANEL_POSITION
	if is_instance_valid(_battle_board_input_blocker):
		_battle_board_input_blocker.hide()
		_battle_board_input_blocker.queue_free()
		_battle_board_input_blocker = null


func begin_battle() -> bool:
	if not can_start_battle():
		return false
	_before_battle = capture_state()
	_before_battle_gold = _main.run_reward_state.gold
	_story_battle_deployed.clear()
	for card: OwnedCard in _story_deployed():
		_story_battle_deployed.append(String(card.instance_id))
	run.start_battle()
	return true


func award_opening_gold() -> void:
	if hero.has_talent("sentry_alchemy"):
		_main.run_reward_state.add_gold(deployed.size() * int(rewards.config.talents.sentry_alchemy.confirmed_rules.gold_per_deployed_sentry))


func battle_context() -> Dictionary:
	if _main.is_smith_tutorial(): return {}
	return {"level": hero.level, "talents": hero.selected_talents.values(), "sentries": deployed.duplicate(true), "fortify_complete": fortify_complete, "rules": rewards.config, "story_buffs": story_buffs.duplicate(true), "floor": floor_number(), "enemy_first": run.battle_path().get("enemy_first", false)}


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
	last_reward = rewards.build_battle_reward(floor_number(), won, run.rng, _main.run_item_enabled("scraper"), _main.run_pack_enabled("emblem_pack"))
	if not bool(last_reward.get("success", false)):
		return false
	last_reward["damage_leaders"] = _battle_damage_leaders()
	_main.run_reward_state.add_gold(int(last_reward.gold))
	var drop: Dictionary = last_reward.drop
	match String(drop.get("kind", "")):
		"scraper":
			_main.scraper_count += 1
			_main.emblem_library.set_scraper_count(_main.scraper_count)
		"emblem": _grant_emblem(String(drop.emblem_id), "maze_battle:%s" % battle_id)
	if _main.is_smith_tutorial(): last_reward.experience = 0
	else: hero.grant_experience(battle_id, int(last_reward.experience))
	if runtime != null:
		last_reward["spell_cards"] = runtime.spell_awards.duplicate()
		var registry: Dictionary = _main._build_card_definition_registry()
		for card_id: String in runtime.spell_awards:
			_main.owned_card_collection.create_card(registry[StringName(card_id)], run.rng)
		if won and runtime.fortify_eligible:
			fortify_complete = true
			last_reward["fortify_completed"] = true
	if _main.battle_controller.current_result == BattleController.Result.PLAYER_VICTORY and run.is_event_battle() and run.selected_path.path_id == "high_risk_mining":
		var count := MiningEvents.grant_full_mining_reward(self)
		last_reward["mining_cards"] = count
	_settle_task_scrolls(battle_id)
	resolve_secret_missions()
	deployed.clear() # 正常战后全数消费；未投入的库存保留。清理不触发锐。
	story_participants.assign(_story_battle_deployed)
	for index: int in story_buffs.size():
		var buff := story_buffs[index]
		if buff.stat == "fragile_protection":
			buff.value = int(buff.value) - int(_main.battle_controller.story_fragile_spent.get(index, 0))
		if int(buff.battles) > 0 and (not buff.has("instance_id") or buff.instance_id in story_participants or buff.get("expire_without_participation", false)):
			buff.battles = int(buff.battles) - 1
	story_buffs = story_buffs.filter(func(buff: Dictionary) -> bool:
		return int(buff.battles) != 0 and int(buff.get("floor", floor_number())) >= floor_number() and (buff.stat != "fragile_protection" or int(buff.value) > 0))
	run.settle_battle(won)
	return true


func _battle_damage_leaders() -> Array[String]:
	var leaders: Array[String] = []
	var highest := -INF
	var statistics: Dictionary = _main.battle_controller.get_owned_card_statistics()
	# 开战时锁定的随从身份包含后来阵亡或移除的实例，判定时不换目标。
	for id: String in _story_battle_deployed:
		var stats: Dictionary = statistics.get(id, {})
		if int(stats.get("battles", 0)) == 0: continue
		var damage := float(stats.get("damage_dealt", 0))
		if damage > highest:
			leaders.clear()
			highest = damage
		if damage == highest: leaders.append(id)
	return leaders


func _settle_task_scrolls(battle_id: String) -> void:
	var tray: CelestialIndicatorController = _main.celestial_indicators
	var battle: BattleController = _main.battle_controller
	var survival := {}
	for state: BattleSquadState in battle.player_states:
		if not state.battle_participated or state.battle_summoned or not state.alive or state.current_health <= 0.0 or state.battle_ever_defeated: continue
		for attachment: Dictionary in state.squad_data.indicator_attachments:
			var item: CelestialIndicator = attachment.indicator
			if item.kind == CelestialIndicator.Kind.MERCENARY: survival[item.instance_id] = 1
	var completed: Array[String] = []
	var registry: Dictionary = _main._build_card_definition_registry() if not battle.task_scroll_supplies.is_empty() else {}
	for item: CelestialIndicator in tray.items.duplicate():
		if not CelestialIndicator.TASK_TARGETS.has(item.kind): continue
		match item.kind:
			CelestialIndicator.Kind.CLEANUP: item.task_progress += int(battle.task_scroll_buffs.get(item.instance_id, 0))
			CelestialIndicator.Kind.MERCENARY: item.task_progress += int(survival.get(item.instance_id, 0))
			CelestialIndicator.Kind.SUPPLIES:
				for supply: Dictionary in battle.task_scroll_supplies.get(item.instance_id, []):
					if supply.has("emblem_id"):
						item.task_progress += maxi(0, _main._shop_sticker_sale_price(supply))
					elif supply.has("owned"):
						item.task_progress += maxi(0, _main._shop_card_sale_price(supply.owned))
					else:
						var definition: CardData = registry.get(StringName(supply.get("card_id", "")))
						if definition == null: continue
						var prices: Dictionary = _main.ordinary_shop_service.config.card_sale.base_prices
						item.task_progress += maxi(0, int(prices.get(["I", "II", "III", "IV", "V"][definition.rarity], 1)))
		if item.task_progress < int(CelestialIndicator.TASK_TARGETS[item.kind]): continue
		tray.items.erase(item)
		completed.append(CelestialIndicator.NAMES[item.kind])
		_grant_task_scroll_reward(item.kind, "%s:%s" % [battle_id, item.instance_id])
	if not completed.is_empty(): last_reward["task_scrolls"] = completed
	tray.sync_task_attachments()


func resolve_secret_missions(expired_rewards: Dictionary = {}) -> void:
	for id: String in expired_rewards:
		_grant_secret_mission_reward(int(expired_rewards[id]), "secret_mission:%s" % id)
	for item: OwnedCard in _main.owned_card_collection.get_cards():
		if not item.mission_complete(): continue
		var reward := int(item.progress_by_source.get(OwnedCard.MISSION_REWARD, -1))
		item.progress_by_source[OwnedCard.MISSION_DONE] = 1
		_grant_secret_mission_reward(reward, "secret_mission:%s" % item.instance_id, item)
		if reward not in [3, 5]:
			_main._remove_owned_instance_from_rows(item.instance_id)
			_main.owned_card_collection.remove_by_instance_id(item.instance_id)
		else:
			_main._refresh_owned_card_status_visuals(item)


func _grant_secret_mission_reward(reward: int, receipt: String, item: OwnedCard = null) -> void:
	match reward:
		0: _main.run_reward_state.add_gold(50)
		1: _grant_mission_stickers(10, false, [], receipt)
		2:
			for _pack: int in 2: _grant_pack(true, true, false)
		3:
			if item != null:
				item.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 6)
				item.apply_permanent_growth(OwnedCard.STAT_MAX_HEALTH, 10)
		4: _grant_mission_cards(CardData.CardType.EQUIPMENT, 5)
		5:
			if item != null:
				item.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, -3)
				item.progress_by_source[OwnedCard.MISSION_ZEAL] = 10
		6:
			_grant_mission_cards(CardData.CardType.RESOURCE, 10)
			var pick := _story_card("ghost_pick")
			if pick != null: _main.owned_card_collection.create_card(pick, run.rng)
		7: _grant_mission_stickers(4, true, [], receipt)
		8: _grant_mission_stickers(2, true, ["万能贴纸", "混沌贴纸"], receipt)
		9:
			_main.profile_progress.run["secret_mission_unlimited_scraper"] = true
			_main.scraper_count = maxi(_main.scraper_count, 1)
			_main.emblem_library.set_scraper_count(_main.scraper_count)


func _grant_mission_cards(type: int, count: int) -> void:
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var definitions: Array[CardData] = _main._get_shop_card_definitions()
	var no_reserved: Array[CardData] = []
	for _index: int in count:
		var owned: Array[OwnedCard] = _main.owned_card_collection.get_cards()
		var pool := shop._eligible_cards(definitions, owned)
		pool = pool.filter(func(card: CardData) -> bool:
			return card.card_type == type and (type != CardData.CardType.RESOURCE or card.resource_type == CardData.ResourceType.MINERAL))
		var drawn := shop.draw_card_candidate(pool, run.rng, shop.count_owned_cards(owned))
		if drawn == null: break
		_main.owned_card_collection.create_card(drawn, run.rng, no_reserved, false, {"kind": "mission", "name": "隐秘任务"})


func _grant_mission_stickers(count: int, rune: bool, names: Array, receipt: String) -> void:
	if not _main.run_pack_enabled("emblem_pack") and not rune: return
	var shop: OrdinaryShopService = _main.ordinary_shop_service
	var definitions: Array[Dictionary] = _main._get_shop_sticker_definitions()
	var no_picks: Array[Dictionary] = []
	for index: int in count:
		var candidates := shop._eligible_stickers(definitions, _main._get_all_held_stickers(), no_picks)
		candidates = candidates.filter(func(sticker: Dictionary) -> bool:
			return (sticker.get("target", "emblem") == "rune") == rune and (names.is_empty() or String(sticker.id) == names[index]))
		var drawn := shop._draw_sticker(candidates, run.rng)
		if drawn.is_empty(): continue
		_main.emblem_library.receive_stickers([{"instance_id": "%s:%d" % [receipt, index], "emblem_id": drawn.id, "temporary": false, "source": "secret_mission", "element_sticker": rune}])


func _grant_task_scroll_reward(kind: int, receipt: String) -> void:
	if kind == CelestialIndicator.Kind.SUPPLIES:
		var shop: OrdinaryShopService = _main.ordinary_shop_service
		var no_reserved: Array[CardData] = []
		for type: int in [CardData.CardType.EQUIPMENT, CardData.CardType.SPELL]:
			for _index: int in 2:
				var cards: Array[CardData] = shop._eligible_cards(_main._get_shop_card_definitions(), _main.owned_card_collection.get_cards())
				cards = cards.filter(func(card: CardData) -> bool: return card.card_type == type)
				var card := shop.draw_card_candidate(cards, run.rng, shop.count_owned_cards(_main.owned_card_collection.get_cards()))
				if card == null: break
				_main.owned_card_collection.create_card(card, run.rng, no_reserved, false, {"kind": "event", "name": "任务卷轴：丰衣足食"})
	else:
		_main.run_reward_state.add_gold(5)
		_grant_pack(kind == CelestialIndicator.Kind.CLEANUP, true)
	if _main.run_pack_enabled("emblem_pack"):
		_grant_story_stickers({"kind": "emblem_pack"}, "task_scroll:" + receipt)


func apply_task_completions(progress: ProfileProgress) -> bool:
	_main.commit_pending_side_task(progress)
	if run.battle_results.is_empty() or run.is_event_battle(): return false
	var task_id := TaskCatalog.selected(progress, "main")
	if progress.run.tasks.has("main"): progress.run.tasks.main.progress["completed_days"] = run.day
	if not run.battle_results.back().won or run.day != run.route_days: return false
	if task_id == "tutorial": progress.complete_tutorial()
	elif task_id in ["supply_first", "ironwall_support", "temple_boon"]: progress.complete_task(task_id, TaskCatalog.rewards_for(task_id))
	elif task_id == "deep_survey" and _main.owned_card_collection.get_cards().any(func(card: OwnedCard): return card.card_data.id == &"blazing_lantern"):
		return progress.complete_task(task_id, TaskCatalog.rewards_for(task_id))
	return false



func continue_after_battle(discard_confirmed: bool = false) -> bool:
	_main._record_run_diagnostic("next_day_requested", {}, true)
	if run.step in [RunState.Step.BATTLE_RESULT, RunState.Step.ENDED] and not run.battle_results.is_empty() and not String(run.battle_results.back().ending).is_empty():
		return _main.finish_maze_run()
	if run.step != RunState.Step.BATTLE_RESULT or not hero.pending_talent_levels.is_empty():
		return false
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(_main.continue_next_level_button): return false
	var previous := _capture_transaction()
	var was_event_battle := run.is_event_battle()
	_main._close_toolbox_inspection(false)
	_main.emblem_library.discard_dropped_stickers()
	if not run.continue_after_battle():
		_rollback_transaction(previous)
		return false
	if not was_event_battle and run.step != RunState.Step.ENDED:
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
	if not was_event_battle and run.day == 9:
		var task_id := TaskCatalog.selected(_main.profile_progress, "main")
		if task_id in ["ironwall_support", "temple_boon"]:
			if not _queue_task_packs("ironwall_inscription" if task_id == "ironwall_support" else "silvermoon_chapter", 2):
				_rollback_transaction(previous)
				return false
	if was_event_battle: _generate_paths()
	else: _begin_day()
	_main._update_phase_label()
	return _commit_transaction(previous)


func capture_state(before_battle: bool = false) -> Dictionary:
	if before_battle and not _before_battle.is_empty():
		return _before_battle.duplicate(true)
	return {"state_version": 1, "run": run.capture_state(), "hero": hero.capture_state(), "stock": stock.duplicate(true), "deployed": deployed.duplicate(true), "seen_events": seen_events.duplicate(), "fortify_complete": fortify_complete, "last_reward": last_reward.duplicate(true), "next_sentry_id": next_sentry_id, "story_buffs": story_buffs.duplicate(true), "story_participants": story_participants.duplicate(), "story_score": story_score, "story_shop_discount": story_shop_discount}


func validate_state(snapshot: Dictionary) -> bool:
	var candidate_run := RunState.new()
	var candidate_hero := Progress.new()
	var thresholds: Array[int] = []
	thresholds.assign(rewards.config.experience.level_thresholds)
	candidate_hero.initialize(thresholds, rewards.config.talent_choices)
	if int(snapshot.get("state_version", 0)) != 1 or not snapshot.get("run") is Dictionary or not snapshot.get("hero") is Dictionary or not candidate_run.restore_state(snapshot.run) or not candidate_hero.restore_state(snapshot.hero):
		return false
	if not snapshot.get("stock") is Array or not snapshot.get("deployed") is Array or not snapshot.get("seen_events") is Array or not snapshot.get("fortify_complete") is bool or not snapshot.get("last_reward") is Dictionary:
		return false
	if not snapshot.get("story_buffs", []) is Array or not snapshot.get("story_participants", []) is Array or not run._whole_number(snapshot.get("story_score", 0)) or int(snapshot.get("story_score", 0)) < 0: return false
	if not snapshot.get("story_shop_discount", false) is bool: return false
	for buff: Variant in snapshot.get("story_buffs", []):
		if not buff is Dictionary or not run._json_value(buff) or not buff.get("stat") is String or not run._whole_number(buff.get("battles")): return false
	for id: Variant in snapshot.get("story_participants", []):
		if not id is String: return false
	var leaders: Variant = snapshot.last_reward.get("damage_leaders", [])
	if not leaders is Array or not leaders.all(func(id: Variant) -> bool: return id is String and not id.is_empty()): return false
	if not _main.is_smith_tutorial() and not candidate_hero.progression_enabled: return false
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
		if path.path_id in ["bounty_hunter", "spoils_dispute"]:
			var ids_value: Variant = path.get("story_targets")
			if not ids_value is Array or ids_value.size() != (1 if path.path_id == "bounty_hunter" else 2): return false
			if not ids_value.all(func(id: Variant) -> bool: return id is String and not id.is_empty()): return false
			if ids_value.size() == 2 and ids_value[0] == ids_value[1]: return false
		if path.kind == "free_event" and path.get("tutorial", false) and (int(snapshot.run.day) != int(path.get("first_day", 0)) or int(snapshot.run.round_index) != 0): return false
		var found := false
		for definition: Dictionary in all_paths:
			if definition.path_id != path.path_id:
				continue
			found = true
			for key: String in definition:
				if path.kind == "battle" and key in ["front", "back", "previous_formations", "hint", "spells", "resources"]: continue
				if key == "kind" and not definition.get("tutorial", false) and path.kind in ["free_event", "paid_event"] and definition.kind in ["free_event", "paid_event"]: continue
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
		if path.has("reward_items") and (path != snapshot.run.selected_path or not path.get("reward_claimed", false) or not EventRewards.valid_items(path.reward_items)): return false
		if path.has("mining_progress") and (path != snapshot.run.selected_path or path.path_id != "high_risk_mining" or not MiningEvents.valid_progress(self, path)): return false
		if path.has("event_battle") and not _valid_event_battle(path, int(snapshot.run.day)): return false
	return true


func _valid_event_battle(path: Dictionary, day_number: int) -> bool:
	if not path.get("story_result") is Dictionary or not path.event_battle is Dictionary: return false
	if path.get("reward") != "story" or not path.get("options") is Array or not story_events.valid_result(path, path.story_result): return false
	var result: Dictionary = path.story_result
	var option := story_events.runtime_option(path, int(result.option_index))
	var effects: Array = option.outcomes[int(result.outcome_index)].get("effects", [])
	var battle_effects := effects.filter(func(effect: Dictionary) -> bool: return effect.kind == "event_battle")
	if battle_effects.size() != 1: return false
	var expected := story_events.event_encounter(path.path_id, (day_number - 1) / RunState.DAYS + 1, bool(battle_effects[0].get("enemy_first", false)))
	if expected.is_empty(): return false
	var encounter: Dictionary = path.event_battle
	for key: String in expected:
		if encounter.get(key) != expected[key]: return false
	if not run._whole_number(encounter.get("battle_seed")) or int(encounter.battle_seed) < 0 or int(encounter.battle_seed) > _main.BATTLE_SEED_MAX: return false
	return encounter.get("encounter_state") is Dictionary and not EncounterBuilder.new().restore(encounter.encounter_state, _main._build_card_definition_registry()).is_empty()


func restore_state(snapshot: Dictionary) -> bool:
	if not validate_state(snapshot):
		return false
	_cancel_event_presentations()
	if is_instance_valid(_scraper_handoff): _scraper_handoff.free()
	_rune_lesson_waiting_for_release = false
	_queued_tutorial_stories.clear()
	run.restore_state(snapshot.run)
	_enhancement_card_id = StringName(run.selected_path.get("enhancement_result", {}).get("instance_id", ""))
	# 路径内还有一份固定遭遇快照；同步迁移并保存它，避免下次部署恢复旧槽数。
	var saved_paths: Array = run.paths.duplicate()
	if not run.selected_path.is_empty(): saved_paths.append(run.selected_path)
	for path: Dictionary in saved_paths:
		path = path.get("event_battle", path)
		if path.has("encounter_state"):
			var encounter := EncounterBuilder.new().restore(path.encounter_state, _main._build_card_definition_registry())
			path["encounter_state"] = encounter.snapshot
	hero.restore_state(snapshot.hero)
	stock.assign((snapshot.stock as Array).duplicate(true))
	deployed.assign((snapshot.deployed as Array).duplicate(true))
	for sentry: Dictionary in stock + deployed:
		sentry["visual_variant"] = int(sentry["visual_variant"]) # JSON数字读回后恢复外观编号的整数类型，不修改输入快照
	seen_events.assign(snapshot.seen_events)
	story_buffs.assign(snapshot.get("story_buffs", []).duplicate(true))
	story_participants.assign(snapshot.get("story_participants", []))
	story_score = int(snapshot.get("story_score", 0))
	story_shop_discount = snapshot.get("story_shop_discount", false)
	fortify_complete = snapshot.fortify_complete
	last_reward = snapshot.last_reward.duplicate(true)
	next_sentry_id = int(snapshot.next_sentry_id)
	if _main.is_smith_tutorial():
		var thresholds: Array[int] = []
		thresholds.assign(rewards.config.experience.level_thresholds)
		hero.initialize(thresholds, rewards.config.talent_choices, false)
		stock.clear()
		deployed.clear()
		fortify_complete = false
		if run.step == RunState.Step.DAY_START: _begin_day()
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
	var old_hint := _main.get_node_or_null("TaskHint") as Control
	if is_instance_valid(old_hint):
		if not old_hint.tree_exited.is_connected(show_task_hint): old_hint.tree_exited.connect(show_task_hint, CONNECT_ONE_SHOT)
		old_hint.dismiss()
	else:
		show_task_hint.call_deferred()


func reward_summary() -> String:
	var drop: Dictionary = last_reward.get("drop", {})
	var extra := ""
	if drop.get("kind") == "scraper": extra = "\n刮刀+1"
	if drop.get("kind") == "emblem": extra = "\n纹章：%s" % drop.emblem_id
	if last_reward.has("mining_cards"): extra += "\n矿物卡+%d" % int(last_reward.mining_cards)
	var registry: Dictionary = _main._build_card_definition_registry()
	for card_id: String in last_reward.get("spell_cards", []):
		extra += "\n咒获得：%s" % (registry[StringName(card_id)] as CardData).display_name
	if bool(last_reward.get("fortify_completed", false)):
		extra += "\n坚固任务已完成"
	for title: String in last_reward.get("task_scrolls", []):
		extra += "\n%s已完成" % title
	if _main.is_smith_tutorial(): return "本场金币+%d\n失败保护剩余%d%s" % [int(last_reward.get("gold", 0)), run.failure_protection, extra]
	return "本场金币+%d\n经验+%d\n等级%d（总经验%d）\n失败保护剩余%d%s" % [int(last_reward.get("gold", 0)), int(last_reward.get("experience", 0)), hero.level, hero.experience, run.failure_protection, extra]


func _capture_transaction() -> Dictionary:
	return {"profile": _main.profile_progress.capture_state(), "maze": capture_state(), "cards": _main.owned_card_collection.capture_state(), "reward": _main.run_reward_state.capture_state(), "inventory": _main.emblem_library.get_inventory_state(), "shop": _main.ordinary_shop_service.capture_state(), "resources": _main.resource_board_state.capture_state(), "rows": _main._current_rows_for_save(), "phase": _main.current_phase, "chaos_day": _main._last_chaos_reroll_day_token, "journal": _main.settlement_journal.capture_state(), "celestial": _main.celestial_indicators.capture_state(), "scrapers": _main.scraper_count, "battle_sequence": _main._next_battle_instance_sequence, "settlement": _main._last_battle_settlement_result.duplicate(true), "battle_snapshot": _main._battle_snapshot, "prepared_spells": _main.prepared_spell_instance_ids.duplicate()}


func _rollback_transaction(previous: Dictionary) -> void:
	_main._return_service_cards()
	_main.profile_progress.restore_state(previous.profile)
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


func _commit_transaction(previous: Dictionary, commit_discoveries: bool = false, refresh_interface: bool = true) -> bool:
	resolve_secret_missions()
	_refresh_collection()
	if _main.save_run_to_path(_main.run_save_path, commit_discoveries) != OK:
		_rollback_transaction(previous)
		_main.play_area_label.text = "保存失败，本次选择与奖励已回退，请重试。"
		return false
	if refresh_interface:
		refresh()
		show_task_hint.call_deferred()
	return true


func _refresh_collection() -> void:
	_sync_event_reward_visibility()
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
	_initial_pack_prompt = Control.new()
	_initial_pack_prompt.name = "InitialTaskPack"
	_initial_pack_prompt.size = Vector2(1280, 720) # 暗幕覆盖整个游戏逻辑画布
	_initial_pack_prompt.z_index = 2500 # 高于路径事件，低于现有开包检视
	_initial_pack_prompt.visible = false
	_main.add_child(_initial_pack_prompt)
	var dim := ColorRect.new()
	dim.name = "ArrivalDim"
	dim.size = _initial_pack_prompt.size
	dim.color = Color(0, 0, 0, ArrivalSettings.get_values().arrival_dim)
	_initial_pack_prompt.add_child(dim)
	_initial_pack_shadow = Panel.new()
	_initial_pack_shadow.name = "InitialPackGroundShadow"
	_initial_pack_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial_pack_shadow.visible = false
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color.BLACK
	shadow_style.set_corner_radius_all(8) # 地面投影两端的圆角半径
	shadow_style.shadow_color = Color(0, 0, 0, 0.35) # 投影外沿柔化的相对透明度
	shadow_style.shadow_size = 6 # 地面投影外沿的柔化范围
	_initial_pack_shadow.add_theme_stylebox_override("panel", shadow_style)
	_initial_pack_prompt.add_child(_initial_pack_shadow)
	_initial_pack_button = TextureButton.new()
	_initial_pack_button.name = "InitialPackButton"
	_initial_pack_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_initial_pack_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_initial_pack_button.pressed.connect(open_task_supply)
	_initial_pack_prompt.add_child(_initial_pack_button)
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
	label.add_theme_font_size_override("font_size", 16) # 事件纸面正文使用清晰的黑体字号
	label.add_theme_constant_override("line_spacing", 3) # 多行事件描述的行间留白
	label.add_theme_color_override("font_color", Color("513124"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_detail_body if is_instance_valid(_detail_body) else _body).add_child(label)


func _button(text: String, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 15) # 纸面选项字号，长句在可用宽度内换行
	button.tooltip_text = text
	if callback.is_valid(): button.pressed.connect(callback)
	(parent if parent != null else (_detail_body if is_instance_valid(_detail_body) else _body)).add_child(button)
	return button


func _exit_button(text: String, callback: Callable, parent: Node = null) -> Button:
	var button := _button(text, Callable(), parent)
	button.set_meta("exit_action", callback)
	# 连续bind会反向追加参数；显式保留原动作参数，再附加确认状态与原按钮。
	var arguments := callback.get_bound_arguments()
	arguments.append_array([false, button])
	button.pressed.connect(Callable(callback.get_object(), callback.get_method()).bindv(arguments))
	return button


func _find_exit_button(action: Callable) -> BaseButton:
	for button: Button in _panel.find_children("*", "Button", true, false):
		if button.get_meta("exit_action", Callable()) == action: return button
	return null


func _input(event: InputEvent) -> void:
	# 天赋确认后立即换成路径按钮；双击的第二次按压不能误选下一屏。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click and is_instance_valid(_panel) and _panel.is_visible_in_tree():
		var local: Vector2 = _panel.get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, _panel.size).has_point(local):
			get_viewport().set_input_as_handled()


func refresh() -> void:
	_main._bind_profile_collection()
	if not is_instance_valid(_panel) or _event_presentation_busy():
		return
	_sync_event_reward_visibility()
	_main._sync_tabletop_panel_anchors()
	_update_status()
	_main._refresh_enemy_side_trays()
	var choice_key := "%d:%d:%s" % [run.day, run.round_index, JSON.stringify(run.paths)] if run.step == RunState.Step.CHOOSING else ""
	if not _initial_pack_presenting and is_instance_valid(_event_table) and not choice_key.is_empty() and choice_key == _last_dealt_key and hero.pending_talent_levels.is_empty():
		_panel.visible = not _main.ordinary_shop_open
		_status.visible = not _panel.visible and not _main.ordinary_shop_open
		_refresh_sentry_views(_main.current_phase == _main.GamePhase.PREPARE)
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
	var floor_exit := _main.battle_result_panel.get_node_or_null("FinishFloorRunButton") as Button
	if floor_exit == null:
		floor_exit = _main._make_button("FinishFloorRunButton", "本层通关结算", Vector2(52, 394), Vector2(120, 27), false)
		floor_exit.pressed.connect(_main.finish_maze_run.bind("cleared"))
		_main.battle_result_panel.add_child(floor_exit)
	floor_exit.visible = can_finish_floor() and run.day < run.route_days and not choosing_talent
	_main.continue_next_level_button.position = Vector2(188 if floor_exit.visible else 120, 394) # 分层结算与继续并排显示，保持在原结算面板内
	_main.continue_next_level_button.text = "结束本局" if not run.battle_results.is_empty() and not String(run.battle_results.back().ending).is_empty() else ("继续当天" if run.is_event_battle() else "进入下一天")
	_main.restart_battle_button.visible = false
	if is_instance_valid(_enhancement_slot): _enhancement_slot.return_card(false)
	_enhancement_slot = null
	_clear_children(_body)
	_body.position = Vector2.ZERO
	_body.size = PANEL_SIZE
	_detail_body = null
	_event_table = null
	_event_reward_previews.clear()
	var show_panel := false
	var initial_pack_was_visible := _initial_pack_prompt.visible
	_initial_pack_prompt.visible = false
	if not _main.profile_progress.run.get("supplies", []).is_empty():
		var supply: Dictionary = _main.profile_progress.run.supplies[0]
		if TaskCatalog.selected(_main.profile_progress, "main") == "tutorial":
			_initial_pack_prompt.visible = true
			_initial_pack_button.texture_normal = _main._ordinary_shop_offer_icon(supply)
			_initial_pack_button.size = _initial_pack_button.texture_normal.get_size()
			_initial_pack_button.material = CardPackOpening.TearArt.create_relief(_initial_pack_button.size, _initial_pack_button.texture_normal) if supply.kind == "card_pack" and supply.get("size") == "small" else null
			_initial_pack_button.pivot_offset = _initial_pack_button.size * 0.5
			var arrival := ArrivalSettings.get_values()
			_initial_pack_prompt.get_node("ArrivalDim").color.a = arrival.arrival_dim
			if not initial_pack_was_visible: _drop_initial_pack()
			elif not is_instance_valid(_initial_pack_drop) or not _initial_pack_drop.is_valid():
				_initial_pack_button.position = Arrival.point(arrival, "end") - _initial_pack_button.size * 0.5
				_initial_pack_button.scale = Vector2.ONE * arrival.arrival_end_scale
				_initial_pack_button.rotation = 0.0
		else:
			show_panel = true
			_build_plain_event_board()
			_label("出发补给 · %s" % supply.get("name", "任务卡包"))
			_label("点击打开卡包，获得本局试用物资后继续。")
			_button("打开补给包", open_task_supply)
	elif _initial_pack_presenting:
		show_panel = false
	elif choosing_talent:
		show_panel = true
		_build_plain_event_board()
		_label("选择%d级天赋（本局生效）" % hero.pending_talent_levels[0])
		for id: String in hero.get_pending_choices():
			var definition: Dictionary = rewards.config.talents[id]
			var talent_button := _button("%s　%s" % [definition.display_name, definition.source_text], choose_talent.bind(id))
			talent_button.disabled = id == "firmament_blessing"
			if talent_button.disabled: talent_button.text += "（商品内容暂缓）"
	elif run.step == RunState.Step.CHOOSING:
		show_panel = true
		_event_table = EventTable.new()
		_event_table.main = _main
		_body.add_child(_event_table)
		_event_table.path_chosen.connect(_on_event_path_chosen)
		var tarot_deal_key := "%d:%d:%d" % [run.rng.seed, run.day, run.round_index]
		_event_table.show_choices(run.paths, choice_key != _last_dealt_key, tarot_deal_key, _nyx_designated_road())
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
		var ending_summary := "到达第%d天　胜利%d场／失败%d场\n剩余金币%d" % [run.day, wins, run.battle_results.size() - wins, _main.run_reward_state.gold]
		if not _main.is_smith_tutorial(): ending_summary += "　总经验%d　英雄等级%d" % [hero.experience, hero.level]
		_label(ending_summary)
		_button("新一局", _restart_run)
	_panel.visible = show_panel and not _main._viewing_result_battlefield and not _main.ordinary_shop_open
	_status.visible = not _panel.visible and not _main.ordinary_shop_open
	# 父节点隐藏会连带隐藏全部敌方卡面；每次阶段变化都重新设置，不能只在准备阶段隐藏。
	_main.get_node("WorldContent/EnemyBoardSection").visible = _main.current_phase in [_main.GamePhase.BATTLE, _main.GamePhase.RESULT] and not choosing_talent and not _main.ordinary_shop_open
	_refresh_sentry_views(preparing)


func _nudge_initial_pack() -> void:
	if is_instance_valid(_initial_pack_drop) and _initial_pack_drop.is_running(): return
	var button := _initial_pack_button
	var origin := Arrival.point(ArrivalSettings.get_values(), "end") - button.size * 0.5
	var footprint := button.size * button.scale * INITIAL_PACK_SHADOW_RATIO
	var shadow_center := Arrival.point(ArrivalSettings.get_values(), "end") + Vector2(0, button.size.y * button.scale.y * INITIAL_PACK_SHADOW_Y_RATIO)
	_initial_pack_shadow.visible = true
	_initial_pack_shadow.modulate.a = 0.0
	_initial_pack_drop = button.create_tween()
	_initial_pack_drop.tween_method(func(t: float):
		var lift := sin(PI * t)
		button.position = origin - Vector2(0, lift * INITIAL_PACK_NUDGE_HEIGHT)
		button.rotation_degrees = -sin(TAU * t) * sin(PI * t) * INITIAL_PACK_NUDGE_ANGLE, 0.0, 1.0, INITIAL_PACK_NUDGE_SECONDS)
	_initial_pack_drop.parallel().tween_method(func(t: float):
		var lift := sin(PI * t)
		_initial_pack_shadow.size = footprint * Vector2(1.0 + lift * INITIAL_PACK_SHADOW_SPREAD, 1.0)
		_initial_pack_shadow.position = shadow_center - _initial_pack_shadow.size * 0.5
		_initial_pack_shadow.modulate.a = lift * INITIAL_PACK_SHADOW_ALPHA, 0.0, 1.0, INITIAL_PACK_NUDGE_SECONDS)
	_initial_pack_drop.tween_callback(func():
		button.position = origin
		button.rotation = 0.0
		_initial_pack_shadow.hide())


func _drop_initial_pack() -> void:
	if is_instance_valid(_initial_pack_drop): _initial_pack_drop.kill()
	_initial_pack_shadow.hide()
	_initial_pack_drop = Arrival.play(_initial_pack_button, _initial_pack_prompt, ArrivalSettings.get_values())
	var display := get_tree().get_first_node_in_group(&"game_display_shell")
	if display != null and display.screen_transition.busy:
		# 停在左侧第一帧，黑幕完全退出后才播放；刷新界面也不能把暂停误判为落稳。
		_initial_pack_drop.pause()
		var entrance := _initial_pack_drop
		display.screen_transition.finished.connect(func():
			if entrance.is_valid(): entrance.play(), CONNECT_ONE_SHOT)


func _refresh_sentry_views(preparing: bool) -> void:
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
	var committed := select_path(id, _event_table.chosen_index)
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
	var dice: Dictionary = event.get("story_result", {})
	if event.has("mining_progress"):
		dice = {"roll": event.mining_progress.roll, "option_index": int(event.mining_progress.stage) - 1}
	if dice.has("roll") and not dice.get("guaranteed", false):
		var option := story_events.runtime_option(event, int(dice.option_index))
		if option.has("roll_sides"): _event_table.show_story_result(int(option.roll_sides), int(dice.roll))
	if run.is_event_battle():
		var result: Dictionary = event.story_result
		var text := String(event.options[int(result.option_index)].outcomes[int(result.outcome_index)].text)
		_label(text)
		_label("额外战斗 · 敌方先完成突击" if run.battle_path().enemy_first else "额外战斗")
		_label("调整阵容后，点击右下方开始战斗。")
		return
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
				var reward_text: String = {"gold": "获得3金币", "emblem": "获得1枚随机I级纹章", "minion": "获得1张随机灰烬证册I级随从", "pack": "获得1个灰烬证册小卡包（立即打开）", "wound": "随机拥有且有空槽的随从新增1处I级伤势；无目标不执行", "tutorial_smith": "玛格丽特已加入出战队伍，本局可无限使用刮刀。"}[event.reward]
				_label(reward_text)
				_show_event_reward_previews(event)
				var cost := int(event.cost)
				var claim_label := "领取奖励" if event.reward in ["emblem", "pack", "minion"] else "领取并继续"
				var take := _exit_button("继续旅程" if bool(event.get("reward_claimed", false)) else ("花费%d金币" % cost if cost > 0 else claim_label), complete_event.bind(true))
				take.disabled = not bool(event.get("reward_claimed", false)) and _main.run_reward_state.gold < cost
				if cost > 0 and not bool(event.get("reward_claimed", false)):
					_exit_button("放弃，不花金币", complete_event.bind(false))


func _build_story_choices(event: Dictionary) -> void:
	_story_material_pickers.clear()
	_camp_donation_picker = null
	_label(String(event.name))
	if event.has("story_result"):
		var result: Dictionary = event.story_result
		var outcome: Dictionary = event.options[int(result.option_index)].outcomes[int(result.outcome_index)]
		_label(String(result.get("text", outcome.text)))
		var reward_text := String(result.get("effect_text", outcome.effect_text))
		if result.has("skipped_packs"):
			reward_text += "\n未发放：%s（当前没有可抽取的卡包）" % "、".join(result.skipped_packs)
		_label(reward_text)
		_show_event_reward_previews(event)
		_exit_button("继续旅程", complete_event.bind(true))
		return
	if event.has("mining_progress"):
		var progress: Dictionary = event.mining_progress
		var previous: Dictionary = event.options[int(progress.stage) - 1].outcomes[0]
		_label("%s\n已暂存 %d 张矿物卡" % [previous.text, progress.cards.size()])
	else:
		_label(String(event.description))
	if event.path_id == "strange_alchemist": _build_story_material_pickers()
	if event.path_id == "bounty_hunter":
		var wanted := _story_locked_target(0)
		_label("悬赏目标：%s" % (wanted.card_data.display_name if wanted != null else "已离开收藏"))
	if event.path_id == "spoils_dispute":
		for index: int in 2:
			var participant := _story_locked_target(index)
			_label("随从%s：%s" % ["A" if index == 0 else "B", participant.card_data.display_name if participant != null else "已离开收藏"])
	var has_target: bool = event.options.any(func(option: Dictionary) -> bool: return option.has("target") and not option.has("unavailable_reason"))
	if has_target:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24) # 事件选项和随从槽之间的间隔
		_detail_body.add_child(row)
		_enhancement_options = VBoxContainer.new()
		_enhancement_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_enhancement_options)
		_build_event_service_slot(row, false)
	var owned: OwnedCard = _main.owned_card_collection.get_by_instance_id(_enhancement_card_id)
	var can_leave := false
	for index: int in event.options.size():
		var option := story_events.runtime_option(event, index)
		if not story_events.option_is_visible(event, option) or not MiningEvents.option_is_visible(event, option): continue
		if event.path_id == "strange_casino" and index in [2, 3] and not _story_blocked_reason(option, owned, true).is_empty(): continue
		if option.has("food_choices"): _build_story_food_picker(option)
		if option.get("camp_donation", false):
			_camp_donation_picker = OptionButton.new()
			_camp_donation_picker.add_item("选择要捐赠的纹章")
			for item: Dictionary in MiningEvents.donations(self):
				_camp_donation_picker.add_item(String(item.emblem_id))
				_camp_donation_picker.set_item_metadata(_camp_donation_picker.item_count - 1, String(item.instance_id))
			_detail_body.add_child(_camp_donation_picker)
		var blocked := _story_blocked_reason(option, owned)
		var button := _button(String(option.label), choose_story_option.bind(index), _enhancement_options if has_target else null)
		if option.get("camp_donation", false):
			_camp_donation_picker.item_selected.connect(func(_item: int): button.disabled = not _story_blocked_reason(option, null).is_empty())
		if option.has("food_choices"):
			_story_food_picker.multi_selected.connect(func(_item: int, _selected: bool):
				button.disabled = not _story_blocked_reason(option, null).is_empty())
		if event.path_id == "strange_alchemist" and index in [1, 2]:
			for picker: OptionButton in _story_material_pickers.values():
				picker.item_selected.connect(func(_item: int): button.disabled = not _story_blocked_reason(option, null).is_empty())
		if has_target: button.set_meta("story_option", index)
		can_leave = can_leave or (int(option.cost) == 0 and not option.has("target") and blocked.is_empty())
		button.text = String(option.label)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not blocked.is_empty()
		var explanation := "条件：%s" % String(option.condition)
		for outcome: Dictionary in option.outcomes:
			explanation += "\n%s：%s" % [str(outcome.source_probability), String(outcome.effect_text)]
		button.tooltip_text = explanation + ("\n" + blocked if not blocked.is_empty() else "")
		if not blocked.is_empty() and not option.has("target"):
			_label(blocked)
	if not can_leave:
		_exit_button("直接离开", complete_event.bind(false), _enhancement_options if has_target else null)


func _build_story_food_picker(option: Dictionary) -> void:
	_story_food_picker = ItemList.new()
	_story_food_picker.select_mode = ItemList.SELECT_MULTI
	_story_food_picker.custom_minimum_size.y = 84 # 食物选择区显示约三行，更多项目在区内滚动
	_story_food_picker.tooltip_text = "选择三枚未装备的食物纹章"
	for item: Dictionary in _main.emblem_library.get_inventory_state():
		if String(item.get("emblem_id", "")) in option.food_choices:
			var index := _story_food_picker.add_item(String(item.emblem_id))
			_story_food_picker.set_item_metadata(index, String(item.instance_id))
	_detail_body.add_child(_story_food_picker)


func _build_story_material_pickers() -> void:
	_label("中型禁药选择 I 至 III 级材料，大型另需一张 IV 级随从。确认后材料永久移除。")
	var owned := _story_minions()
	for rarity: int in 4:
		var picker := OptionButton.new()
		picker.add_item("选择 %s 级随从" % ["I", "II", "III", "IV"][rarity])
		for card: OwnedCard in owned:
			if int(card.card_data.rarity) != rarity: continue
			picker.add_item("%s（%s）" % [card.card_data.display_name, card.instance_id])
			picker.set_item_metadata(picker.item_count - 1, String(card.instance_id))
		_detail_body.add_child(picker)
		_story_material_pickers[rarity] = picker


func _event_presentation_busy() -> bool:
	return is_instance_valid(_story_roll) or is_instance_valid(_event_reward_flight) or is_instance_valid(_battle_board_exit)


func _cancel_event_presentations() -> void:
	_clear_battle_board_exit()
	_story_roll = null
	if is_instance_valid(_event_reward_flight): _event_reward_flight.free()
	_event_reward_flight = null
	_event_reward_in_flight.clear()


func event_reward_ids(kind: String) -> Array[StringName]:
	var ids: Array[StringName] = []
	for item: Dictionary in run.selected_path.get("reward_items", []) + _event_reward_in_flight:
		if item.kind == kind: ids.append(StringName(item.id))
	return ids


func _sync_event_reward_visibility() -> void:
	_main.emblem_library.set_event_reward_ids(event_reward_ids("sticker"))
	_main.celestial_indicators.set_event_reward_ids(event_reward_ids("indicator"))


func _show_event_reward_previews(event: Dictionary) -> void:
	var rewards_to_show: Array = event.get("reward_items", [])
	if rewards_to_show.is_empty(): return
	_event_table.show_detail_immediately()
	var tiles := HFlowContainer.new()
	tiles.name = "EventRewardPreviews"
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cards: Array[Control] = []
	for item: Dictionary in rewards_to_show:
		var tile := EventRewards.make_tile(_main, item)
		if tile == null: continue
		if item.kind == "card": cards.append(tile)
		else: tiles.add_child(tile)
		_event_reward_previews[String(item.id)] = tile
	if tiles.get_child_count() > 0: _detail_body.add_child(tiles)
	else: tiles.free()
	_event_table.show_reward_cards(cards)


func _event_reward_origins(awards: Array[Dictionary], button: BaseButton) -> Dictionary:
	var origins := {}
	for item: Dictionary in awards:
		var tile := _event_reward_previews.get(String(item.id)) as Control
		var center := EventRewards.preview_rect(tile).get_center() if is_instance_valid(tile) else Vector2.INF
		var area: Rect2 = _event_table.get_global_rect() if item.kind == "card" else _event_table._paper.get_global_rect()
		origins[String(item.id)] = center if area.has_point(center) else button.get_global_rect().get_center()
	return origins


func _play_event_reward_flight(origins: Dictionary, show_overflow: bool) -> void:
	var flight := EventRewards.new()
	flight.name = "EventRewardFlight"
	flight.main = _main
	_event_reward_flight = flight
	_main.add_child(flight)
	var previous_view: int = _main.current_world_view
	_main._cancel_click_carry()
	_panel.hide()
	_main.set_world_view(_main.WorldView.COLLECTION)
	flight.landed.connect(func(item: Dictionary):
		_event_reward_in_flight.erase(item)
		_sync_event_reward_visibility()
		if item.kind == "card": _reveal_event_reward_card(StringName(item.id)))
	flight.finished.connect(func():
		for id: StringName in event_reward_ids("card"): _reveal_event_reward_card(id)
		_event_reward_in_flight.clear()
		_event_reward_flight = null
		flight.queue_free()
		if not show_overflow: _main.set_world_view(previous_view)
		refresh()
		if show_overflow: _main._open_toolbox_inspection()
		show_task_hint.call_deferred())
	flight.play(_event_reward_in_flight.duplicate(), origins)


func _reveal_event_reward_card(id: StringName) -> void:
	var slot: Control = _main._find_collection_slot_for_owned_card(_main.owned_card_collection.get_by_instance_id(id))
	if is_instance_valid(slot): slot.show()


func _play_story_roll(sides: int, result: int, after_roll: Callable = Callable()) -> void:
	var roll := DiceRoll.new()
	_story_roll = roll
	if run.is_event_battle(): _main.start_battle_button.hide()
	roll.finished.connect(func():
		_story_roll = null
		refresh()
		if after_roll.is_valid(): after_roll.call()
		show_task_hint.call_deferred(), CONNECT_ONE_SHOT)
	_event_table.play_story_roll(roll, sides, result)


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
	if _main.current_phase != _main.GamePhase.PREPARE or run.step in [RunState.Step.BATTLE_RESULT, RunState.Step.ENDED] or not hero.pending_talent_levels.is_empty():
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
	if run.step != RunState.Step.EVENT or _main.current_phase != _main.GamePhase.PREPARE:
		return false
	var owned := data.get("owned_card") as OwnedCard
	if data.get("kind") != &"card" or owned == null or owned.card_data.card_type != CardData.CardType.MINION or _main.owned_card_collection.get_by_instance_id(owned.instance_id) != owned:
		return false
	if run.selected_path.get("reward") == "enhance_card": return not run.selected_path.has("enhancement_result")
	return run.selected_path.get("reward") == "story" and not run.selected_path.has("story_result") and run.selected_path.options.any(
		func(option: Dictionary) -> bool: return option.has("target") and not option.has("unavailable_reason") and _matches_story_target(option, owned))


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
			elif button is Button and button.has_meta("story_option"):
				button.disabled = not _story_blocked_reason(run.selected_path.options[int(button.get_meta("story_option"))], owned).is_empty()
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
		_exit_button("继续旅程", complete_event.bind(true), _enhancement_options)
	else:
		for index: int in run.selected_path.options.size():
			var option: Dictionary = run.selected_path.options[index]
			var button := _exit_button(_enhancement_option_text(option), apply_card_enhancement.bind(index), _enhancement_options)
			button.set_meta("enhancement_option", index)
		_exit_button("放弃强化并继续", complete_event.bind(false), _enhancement_options)
	_build_event_service_slot(row, finished)


func _build_event_service_slot(row: HBoxContainer, finished: bool) -> void:
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


func apply_card_enhancement(option_index: int, discard_confirmed: bool = false, source_button: BaseButton = null) -> bool:
	if run.step != RunState.Step.EVENT or run.selected_path.get("reward") != "enhance_card" or run.selected_path.has("enhancement_result") or option_index < 0 or option_index >= run.selected_path.options.size():
		return false
	var owned: OwnedCard = _main.owned_card_collection.get_by_instance_id(_enhancement_card_id)
	var option: Dictionary = run.selected_path.options[option_index]
	if owned == null or owned.card_data.card_type != CardData.CardType.MINION or _main.run_reward_state.gold < int(option.cost):
		return false
	if not is_instance_valid(source_button): source_button = _find_exit_button(apply_card_enhancement.bind(option_index))
	if not discard_confirmed and not _main.confirm_temporary_sticker_discard(source_button): return false
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
