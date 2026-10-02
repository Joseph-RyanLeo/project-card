extends SceneTree

## 真实窗口诊断：正式卡牌/商店/战斗路径；仅测试夹具增加计时，不接入正常游戏。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const DisplayScript = preload("res://scripts/ui/game_display.gd")
const COLLECTION_TARGET: int = 72 # 本轮伙伴反馈的收藏卡数量
const FRAME_SETTLE_WAIT: float = 0.4 # 等待布局和抬起动画稳定后的采样间隔
const PAGE_SETTLE_WAIT: float = 0.55 # 两次翻页之间等待动画完成的间隔
const DRAG_STEPS: int = 70 # 每次横穿战场提交的鼠标移动次数
const DRAG_REPEATS: int = 3 # 对同种卡牌横穿战场的次数
const TEST_TIMEOUT: float = 150.0 # 整个真实窗口测试的最长等待秒数
var shell: Control
var main: Control
var frames: Array[Dictionary] = []
var stage := "startup"
var previous_usec := 0
var operations: Array[Dictionary] = []
var rows: Array[Node] = []
var failures := 0

func _initialize() -> void:
	process_frame.connect(record_frame)
	run.call_deferred()

func record_frame() -> void:
	var now := Time.get_ticks_usec()
	if previous_usec > 0:
		frames.append({"stage": stage, "wall_ms": (now - previous_usec) / 1000.0, "frame": Engine.get_process_frames(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
	previous_usec = now

func mark(value: String) -> void:
	stage = value
	main.diagnostic_stage = value
	for row: Node in rows: row.diagnostic_stage = value
	print("PERF_STAGE ", stage)

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	var began := Time.get_ticks_usec()
	root.push_input(event, true)
	operations.append({"stage": stage, "tag": "mouse_motion", "cpu_ms": (Time.get_ticks_usec() - began) / 1000.0})
	await process_frame

func first_draw(tag: String, began: int) -> void:
	await RenderingServer.frame_post_draw
	operations.append({"stage": stage, "tag": tag, "to_draw_ms": (Time.get_ticks_usec() - began) / 1000.0})

func run() -> void:
	create_timer(TEST_TIMEOUT).timeout.connect(func(): push_error("性能测试超时"); export_data(); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.set_script(load("res://tests/performance/profiled_main.gd"))
	root.add_child(shell)
	rows = main.diagnostic_rows
	if rows.size() != 4:
		push_error("计时夹具必须包含完整四排战场")
		quit(1)
		return
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_1080P)
	main.run_save_path = "/private/tmp/project-card-performance-save.json"
	main._battle_performance_trace_enabled = true
	main.battle_controller.performance_trace_enabled = true
	await create_timer(1.0).timeout
	var definitions: Array[CardData] = main._get_shop_card_definitions()
	var index := 0
	while main.owned_card_collection.get_cards().size() < COLLECTION_TARGET:
		main.owned_card_collection.create_card(definitions[index % definitions.size()])
		index += 1
	main._sync_legacy_collection_cards()
	var deployed := 0
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type != CardData.CardType.MINION: continue
		var row: BattlefieldRow = main.front_row if deployed < 3 else main.back_row
		row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())
		deployed += 1
		if deployed == 6: break
	var enemy_count := 0
	for owned: OwnedCard in main.owned_card_collection.get_cards():
		if owned.card_data.card_type != CardData.CardType.MINION: continue
		var row: BattlefieldRow = main.enemy_front_row if enemy_count < 3 else main.enemy_back_row
		row.add_squad(SquadData.from_card(owned.card_data), row.get_squad_count())
		enemy_count += 1
		if enemy_count == 6: break
	main._build_collection_cards()
	print("PERF_SETUP cards=", main.owned_card_collection.get_cards().size(), " squads=", main.front_row.get_squad_count(), "/", main.back_row.get_squad_count(), " rows=", rows.size())
	await create_timer(0.5).timeout
	mark("idle72")
	await create_timer(1.0).timeout
	for target: int in [1, 2, 3, 4, 5, 0, 1, 0]:
		mark("page72")
		var began := Time.get_ticks_usec()
		main.turn_collection_page(target)
		await first_draw("page_input", began)
		await create_timer(PAGE_SETTLE_WAIT).timeout
	mark("shop_default")
	main.ordinary_shop_service.rng.seed = 12
	main._generate_ordinary_shop(false)
	var began := Time.get_ticks_usec()
	main._toggle_ordinary_shop()
	await first_draw("shop_open", began)
	await create_timer(FRAME_SETTLE_WAIT).timeout
	await hover_packs()
	mark("shop_default_close")
	main._toggle_ordinary_shop()
	await create_timer(0.3).timeout
	mark("shop32")
	main.ordinary_shop_service.config.temporary_offer_weights.card_pack_count = {"32": 1}
	main.ordinary_shop_service.config.temporary_offer_weights.card_pack_size = {"small": 1, "large": 1}
	main.ordinary_shop_service.rng.seed = 12
	for seed_value: int in range(1, 200):
		main.ordinary_shop_service.rng.seed = seed_value
		var generated: bool = main.ordinary_shop_service.refresh(main._get_shop_card_definitions(), main.owned_card_collection.get_cards(), main._get_shop_sticker_definitions(), main._get_all_held_stickers())
		var small_count := 0
		for offer: Dictionary in main.ordinary_shop_service.offers:
			if offer.get("kind") == "card_pack" and offer.get("size") == "small": small_count += 1
		if generated and small_count == 16: break
	main._refresh_ordinary_shop_panel()
	began = Time.get_ticks_usec()
	main._toggle_ordinary_shop()
	await first_draw("shop_open", began)
	await create_timer(FRAME_SETTLE_WAIT).timeout
	await hover_packs()
	mark("shop32_close")
	main._toggle_ordinary_shop()
	await create_timer(FRAME_SETTLE_WAIT).timeout
	await drag_cards(CardData.CardType.MINION, "drag_minion")
	await drag_cards(CardData.CardType.EQUIPMENT, "drag_equipment")
	await card_refresh_probe()
	mark("battle_start")
	main.set_battle_speed(1)
	began = Time.get_ticks_usec()
	var started: bool = main.start_battle(1331915, true)
	print("PERF_BATTLE_STARTED ", started)
	await first_draw("battle_start", began)
	mark("battle_running")
	var timeout := Time.get_ticks_msec() + 90000
	while main.current_phase == main.GamePhase.BATTLE and Time.get_ticks_msec() < timeout:
		await process_frame
	print("PERF_BATTLE_RESULT phase=", main.current_phase, " result=", main.battle_controller.current_result)
	await create_timer(0.6).timeout
	mark("result_idle")
	await create_timer(0.7).timeout
	export_data()
	shell.queue_free()
	await process_frame
	quit(failures)

func hover_packs() -> void:
	mark(stage + "_hover")
	var stacks: Array[Node] = main.ordinary_shop_offer_list.find_children("ShopPackStack_*", "Control", true, false)
	for stack: ShopPackStackView in stacks:
		print("PERF_PACK_COUNT ", stack._offers.size())
		for repeat: int in DRAG_REPEATS:
			for offer: ShopOfferView in stack._offers:
				await move(offer.get_global_rect().position + Vector2(5, 60))
				await create_timer(0.035).timeout
	await move(Vector2(30, 650))
	await create_timer(0.3).timeout

func drag_cards(kind: int, label: String) -> void:
	main.active_card_type_filters.assign([kind])
	main.current_collection_page = 0
	main._build_collection_cards()
	await create_timer(FRAME_SETTLE_WAIT).timeout
	var source: Control
	var owned: OwnedCard
	for slot: Control in main._get_collection_card_slots():
		var candidate: OwnedCard = slot.get_meta("owned_card", null)
		if candidate != null and not bool(slot.get_meta("is_deployed_ghost", false)):
			source = slot
			owned = candidate
			break
	if owned == null:
		push_error("没有可拖动实卡 " + label)
		failures += 1
		return
	mark(label + "_pickup")
	var data := {"kind": &"equipment_card" if kind == CardData.CardType.EQUIPMENT else &"card", "card_data": owned.card_data, "owned_card": owned, "source_type": &"collection", "source_slot": source, "grab_offset": Vector2(40, 40)}
	var began := Time.get_ticks_usec()
	main._on_click_carry_requested(data, source.get_global_rect().get_center())
	await first_draw("pickup", began)
	mark(label)
	var rect: Rect2 = main.front_row.get_global_rect()
	for repeat: int in DRAG_REPEATS:
		for step: int in DRAG_STEPS:
			var t := float(step) / float(DRAG_STEPS - 1)
			if repeat % 2: t = 1.0 - t
			var point := Vector2(lerpf(rect.position.x + 5, rect.end.x - 5, t), rect.get_center().y)
			await move(point)
	main._cancel_click_carry()
	main.active_card_type_filters.clear()
	main._build_collection_cards()
	await create_timer(FRAME_SETTLE_WAIT).timeout

func export_data() -> void:
	var data: Array[Dictionary] = main.diagnostic_samples.duplicate()
	for row: Node in rows:
		for sample: Dictionary in row.diagnostic_samples:
			var item := sample.duplicate()
			item.tag = "row." + String(item.tag)
			data.append(item)
	var payload := {"os": OS.get_name(), "processor": OS.get_processor_name(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "collection_cards": main.owned_card_collection.get_cards().size(), "battle_seed": 1331915, "operations": operations, "frames": frames, "modules": data, "existing_trace": main._battle_trace_frame_samples}
	var file := FileAccess.open("/private/tmp/project-card-performance-local.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	print("PERF_EXPORTED /private/tmp/project-card-performance-local.json")

func card_refresh_probe() -> void:
	mark("card_refresh")
	var owned: OwnedCard
	for candidate: OwnedCard in main.owned_card_collection.get_cards():
		if candidate.card_data.card_type == CardData.CardType.MINION and candidate.card_data.runes.size() == 3:
			owned = candidate
			break
	var view := preload("res://scenes/ui/CardView.tscn").instantiate() as CardView
	var probe := OwnedCard.new()
	probe.initialize(owned.card_data, &"diagnostic_probe", -1, RandomNumberGenerator.new())
	view.set_card_data(probe.card_data)
	view.set_owned_card(probe)
	main.add_child(view)
	view.position = Vector2(20, 20)
	await process_frame
	for repeat: int in 20:
		var began := Time.get_ticks_usec()
		RuneRevealCoverStyle.create_mask_image(probe.get_rune_scrape_mask_bytes(0))
		operations.append({"stage": stage, "tag": "mask_image", "cpu_ms": (Time.get_ticks_usec() - began) / 1000.0})
	for revealed: bool in [false, true]:
		probe.rune_revealed.assign([revealed, revealed, revealed])
		for repeat: int in 20:
			var began := Time.get_ticks_usec()
			view._refresh_runes()
			operations.append({"stage":stage,"tag":"runes_revealed" if revealed else "runes_hidden", "cpu_ms":(Time.get_ticks_usec() - began) / 1000.0})
			await process_frame
	view.queue_free()
	await process_frame
