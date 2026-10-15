extends SceneTree

## 同一测试可加载编辑器工程或exe内的真实PCK，覆盖完整卡池和三个商店入口。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const EXPECTED_CARD_COUNT := 72
var assertions := 0
var failures := 0
var shell: Control
var main: Control


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)


func click(point: Vector2) -> void:
	var outer: Vector2 = shell.render_container.get_global_transform_with_canvas() * point
	var motion := InputEventMouseMotion.new()
	motion.position = outer
	motion.global_position = outer
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = outer
		event.global_position = outer
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func flow_button(index: int) -> Button:
	var buttons: Array[Button] = []
	for child: Node in main.maze_controller._body.get_children():
		if child is Button:
			buttons.append(child)
	return buttons[index] if index < buttons.size() else null


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var resources := ResourceLoader.list_directory("res://resources/cards")
	var raw_files := DirAccess.get_files_at("res://resources/cards")
	var raw_tres := 0
	var remaps := 0
	for filename: String in raw_files:
		if filename.ends_with(".tres"): raw_tres += 1
		if filename.ends_with(".tres.remap"): remaps += 1
	print("卡牌资源目录：原始tres=", raw_tres, " remap=", remaps, " ResourceLoader=", resources.size())
	check(resources.size() == EXPECTED_CARD_COUNT, "资源加载器识别全部72张卡牌定义")
	if "packed" in OS.get_cmdline_user_args():
		check(raw_tres == 0 and remaps == EXPECTED_CARD_COUNT, "实际导出资源包仅包含72个remap，不借用工程原始tres")
	for seed_value: int in [1707, 1708]:
		for shop_index: int in range(3):
			shell = DISPLAY.instantiate()
			main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
			main.run_save_path = "/private/tmp/project-card-export-shop-test.json"
			root.add_child(shell)
			await process_frame
			await process_frame
			var maze = main.maze_controller
			check(maze != null, "导出配置能初始化迷宫")
			if maze == null: break
			var registry: Dictionary = main._build_card_definition_registry()
			check(registry.size() == EXPECTED_CARD_COUNT, "Main注册表包含未持有的全部72张卡牌")
			var pool: Array = main.ordinary_shop_service._eligible_cards(main._get_shop_card_definitions(), main.owned_card_collection.get_cards())
			var counts := [0, 0, 0, 0, 0]
			for card: Resource in pool: counts[int(card.rarity)] += 1
			check(counts == [11, 10, 6, 3, 0], "商店I至V级完整候选数为11/10/6/3/0")
			maze.run.rng.seed = seed_value # 固定真实随机源的测试输入，不替代路径或商店生成。
			var talent := flow_button(0)
			check(talent != null, "第一个天赋入口存在")
			if talent != null: await click(talent.get_global_rect().get_center())
			check(maze.hero.has_talent("sentry_guard") and maze.run.paths.size() == 3, "真实点击第一个天赋后生成三条商店路径")
			var target := flow_button(shop_index)
			check(target != null, "商店路径入口存在：%d" % shop_index)
			if target != null: await click(target.get_global_rect().get_center())
			check(main.ordinary_shop_open and main.ordinary_shop_panel.is_visible_in_tree() and not maze._panel.is_visible_in_tree(), "真实鼠标进入商店：种子%d／入口%d" % [seed_value, shop_index])
			check(not main.ordinary_shop_service.offers.is_empty(), "商店成功生成实际商品")
			if main.ordinary_shop_open:
				var selected: Dictionary = maze.run.selected_path.duplicate(true)
				check(main.load_run_from_path(main.run_save_path), "新商店存档可完整读回")
				check(main.ordinary_shop_open and maze.run.selected_path == selected and not main.ordinary_shop_service.offers.is_empty(), "读档保留所选商店和商品")
			shell.queue_free()
			await process_frame
			await process_frame
	print("导出商店专项：", assertions, "项断言，失败", failures)
	quit(1 if failures else 0)
