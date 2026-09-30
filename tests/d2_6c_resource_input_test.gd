extends SceneTree

const DISPLAY_SCENE: PackedScene = preload("res://scenes/GameDisplay.tscn")
const GameDisplayScript = preload("res://scripts/ui/game_display.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const ResourceHexLayout = preload("res://scripts/data/resource_hex_layout.gd")
const CardDragPreview = preload("res://scripts/ui/card_drag_preview.gd")
const ResourcePreparationTray = preload("res://scripts/ui/resource_preparation_tray.gd")
const BattleResourceState = preload("res://scripts/battle/battle_resource_state.gd")

var failures := 0
var viewport: SubViewport
var pointer := Vector2.ZERO
var transform := Transform2D.IDENTITY

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func mouse_move(point: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = transform * point
	event.global_position = event.position
	event.relative = (point - pointer) * transform.get_scale()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = point
	Input.warp_mouse(event.position)
	root.push_input(event, true)
	await process_frame

func mouse_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = transform * pointer
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func escape_key() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	root.push_input(release, true)
	await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var is_2k := args.has("2k")
	root.size = Vector2i(2560, 1440) if is_2k else Vector2i(1280, 720)
	var shell := DISPLAY_SCENE.instantiate()
	root.add_child(shell)
	shell.apply_display_mode(GameDisplayScript.DisplayMode.WINDOW_2K if is_2k else GameDisplayScript.DisplayMode.WINDOW_720P)
	for _frame: int in 90:
		await process_frame
		var expected_window := Vector2i(2560, 1440) if is_2k else Vector2i(1280, 720)
		if shell.get_window().size == expected_window: break
	var main = shell.main_screen
	viewport = shell.internal_viewport
	viewport.notify_mouse_entered()
	transform = shell.render_container.get_global_transform_with_canvas()
	check(
		transform.get_scale().is_equal_approx(Vector2(2, 2) if is_2k else Vector2.ONE),
		"%s运行真实显示壳且内部720p画布缩放倍率正确" % ("2K" if is_2k else "720p")
	)
	var resource_data := load("res://resources/cards/rainbow_gold_ore.tres") as CardData
	var resource: OwnedCard = main.owned_card_collection.create_card(resource_data)
	var blocker_data := load("res://resources/cards/fire_element_shard.tres") as CardData
	var blocker: OwnedCard = main.owned_card_collection.create_card(blocker_data)
	var enemy_resource: OwnedCard = OwnedCard.new()
	enemy_resource.initialize(load("res://resources/cards/wood_element_shard.tres") as CardData, &"ui_enemy_resource", 99)

	var player_disabled := _disabled_cells(main.resource_board_state.disabled_by_side.player)
	if main.resource_board_state.get_level_resource_cards("player").is_empty():
		var auto_resource := OwnedCard.new()
		auto_resource.initialize(load("res://resources/cards/wood_element_shard.tres") as CardData, &"ui_auto_resource_fixture", 999)
		var auto_anchor := _find_anchor(auto_resource.resource_shape, _occupied_cells(main.resource_board_state, "player"), Vector2i(-99, -99), player_disabled)
		check(main.resource_board_state.deploy_level_resource("player", auto_resource, auto_anchor), "为真实输入验收补一个固定的关卡资源夹具")
	main._refresh_resource_preparation_trays()
	var blocker_anchor := _find_anchor(blocker.resource_shape, _occupied_cells(main.resource_board_state, "player"), Vector2i(-99, -99), player_disabled)
	check(
		main.resource_board_state.try_deploy("player", String(blocker.instance_id), blocker.resource_shape, blocker_anchor, blocker.resource_shape[0]),
		"测试先在资源板建立占格阻挡与敌方资源"
	)
	var rarity_one_resource: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/stone_of_greed.tres") as CardData)
	var rarity_one_anchor := _find_anchor(
		rarity_one_resource.resource_shape,
		_occupied_cells(main.resource_board_state, "player"),
		Vector2i(-99, -99),
		player_disabled
	)
	check(
		main.resource_board_state.try_deploy("player", String(rarity_one_resource.instance_id), rarity_one_resource.resource_shape, rarity_one_anchor, rarity_one_resource.resource_shape[0]),
		"真实资源板同时放置I级深灰素材和II级铜色素材供截图核对"
	)
	main._refresh_resource_preparation_trays()
	main._sync_legacy_collection_cards()
	var display_cards: Array[CardData] = main.get_displayed_collection_cards()
	var filtered_index := display_cards.find(resource_data)
	if filtered_index >= 0:
		main.current_collection_page = filtered_index / main.COLLECTION_SLOTS_PER_PAGE
	main._build_collection_cards()
	main._refresh_resource_preparation_trays()
	var player_tray: ResourcePreparationTray = main.player_resource_tray
	check(
		player_tray._icon_nodes_by_id[String(rarity_one_resource.instance_id)].size() == rarity_one_resource.resource_shape.size()
		and player_tray._icon_nodes_by_id[String(blocker.instance_id)].size() == blocker.resource_shape.size()
		and player_tray.find_children("ResourceHealth*", "Label", true, false).is_empty(),
		"资源板每格各画一个图标，且没有剩余生命数字节点"
	)
	await process_frame
	await process_frame
	var source_slot: Control = main._find_collection_slot_for_owned_card(resource)
	check(is_instance_valid(source_slot), "收藏页显示彩金矿实例")
	if not is_instance_valid(source_slot):
		main.queue_free()
		quit(1)
		return
	var source_view := source_slot.get_child(0) as CardView
	var tray := player_tray
	var mapping_shape_cases: Array = [
		[Vector2i.ZERO],
		[Vector2i.ZERO, Vector2i(1, 0)],
		[Vector2i.ZERO, Vector2i(0, 1)],
	]
	for shape_value: Variant in mapping_shape_cases:
		var test_shape: Array[Vector2i] = []
		for cell_value: Variant in shape_value as Array:
			test_shape.append(cell_value as Vector2i)
		var mapped_corner: Dictionary = tray._map_card_grab_to_shape(test_shape, Vector2(91, 9))
		check(
			test_shape.has(mapped_corner.get("cell", Vector2i(-1, -1)))
			and mapped_corner.get("pixel_offset", Vector2.INF) == Vector2.ZERO,
			"单格/横向/纵向测试形状均映射到合法抓取格且不继承卡面偏移"
		)
	var actual_drop_resolutions: Array[Dictionary] = []
	tray.drop_requested.connect(func(_data: Dictionary, resolution: Dictionary) -> void: actual_drop_resolutions.append(resolution))
	var target_anchor := _find_anchor(resource.resource_shape, _occupied_cells(main.resource_board_state, "player"), Vector2i(-99, -99), player_disabled)
	var source_rect := source_view.get_global_rect()
	var source_point := source_rect.position + Vector2(source_rect.size.x - 8.0, 8.0)
	await mouse_move(source_point)
	await mouse_button(true)
	await mouse_move(source_point + Vector2(24, 4), true)
	check(viewport.gui_is_dragging(), "收藏卡片按住并移动触发原生拖拽")
	if viewport.gui_is_dragging():
		var drag_data := viewport.gui_get_drag_data() as Dictionary
		var mapped_grab: Dictionary = tray._map_card_grab_to_shape(resource.resource_shape, drag_data.get("grab_local_position", Vector2(49.5, 68.0)))
		var grab: Vector2i = mapped_grab.cell
		var drop_point: Vector2 = tray.get_global_transform_with_canvas() * (
			tray.LAYOUT_ORIGIN + ResourceHexLayout.center(target_anchor + grab) + mapped_grab.pixel_offset
		)
		await mouse_move(drop_point, true)
		var preview := (viewport.gui_get_drag_data() as Dictionary).get("drag_visual") as CardDragPreview
		await create_timer(0.15).timeout
		check(
			is_instance_valid(preview)
			and preview._resource_puzzle_mode
			and preview._resource_puzzle_tiles.size() == resource.resource_shape.size()
			and preview._resource_puzzle_icons.size() == resource.resource_shape.size()
			and preview.find_child("ResourcePuzzleHealth", true, false) == null,
			"原生拖影每格显示种类图标且不创建资源剩余生命数字"
		)
		var grab_index := resource.resource_shape.find(grab)
		var icon_center := preview._resource_puzzle_icons[grab_index].get_global_rect().get_center() if is_instance_valid(preview) and grab_index >= 0 else Vector2.INF
		check(
			icon_center.distance_to(pointer) <= 1.0,
			"收藏卡拖影按抓取格保持鼠标锚点，其他图标分布于各格中心"
		)
		if args.has("capture"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/project-card-resource-drag-%s.png" % ("2k" if is_2k else "720p"))
		await mouse_button(false)
	check(
		main.resource_board_state.deployments.player.has(String(resource.instance_id)),
		"收藏到资源板的真实鼠标拖放完成部署"
	)
	if not main.resource_board_state.deployments.player.has(String(resource.instance_id)):
		shell.queue_free()
		quit(maxi(failures, 1))
		return
	var placement: Dictionary = main.resource_board_state.deployments.player.get(String(resource.instance_id), {})
	if not placement.is_empty() and resource.resource_shape.size() > 1:
		var moved: Dictionary = {}
		var old_anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
		var relative_grab: Vector2i = resource.resource_shape.back()
		var source_cell := old_anchor + relative_grab
		var source_pixel: Vector2 = tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(source_cell) + Vector2(4, 3))
		await mouse_move(source_pixel)
		await mouse_button(true)
		await mouse_move(source_pixel + Vector2(24, 3), true)
		check(viewport.gui_is_dragging(), "板内从资源拼图第二格按住触发原生拖拽")
		if viewport.gui_is_dragging():
			var board_drag := viewport.gui_get_drag_data() as Dictionary
			var saved_offset: Vector2 = board_drag.get("resource_grab_pixel_offset", Vector2.ZERO)
			var new_anchor := _find_anchor(resource.resource_shape, _occupied_cells(main.resource_board_state, "player", [String(resource.instance_id)]), old_anchor, player_disabled)
			var second_target: Vector2 = tray.get_global_transform_with_canvas() * (
				tray.LAYOUT_ORIGIN + ResourceHexLayout.center(new_anchor + relative_grab) + saved_offset
			)
			await mouse_move(second_target, true)
			await mouse_button(false)
			moved = main.resource_board_state.deployments.player.get(String(resource.instance_id), {})
			check(
				Vector2i(int(moved.get("anchor", [-1, -1])[0]), int(moved.get("anchor", [-1, -1])[1])) == new_anchor
				and (moved.get("grab_pixel_offset", []) as Array).size() == 2
				and Vector2(float(moved.grab_pixel_offset[0]), float(moved.grab_pixel_offset[1])).distance_to(saved_offset) < 1.1,
				"板內從第二格移动后部署锚点变化且抓取像素偏移保留"
			)
		var before_invalid: Dictionary = moved.duplicate(true)
		var moved_anchor := Vector2i(int(moved.anchor[0]), int(moved.anchor[1]))
		var moved_grab: Vector2i = Vector2i(int(moved.grab_anchor[0]), int(moved.grab_anchor[1]))
		var invalid_point: Vector2 = tray.get_global_transform_with_canvas() * (
			tray.LAYOUT_ORIGIN + ResourceHexLayout.center(blocker_anchor + blocker.resource_shape[0])
		)
		var moved_source_cell := moved_anchor + moved_grab
		var moved_source_point: Vector2 = tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(moved_source_cell))
		await mouse_move(moved_source_point)
		await mouse_button(true)
		await mouse_move(moved_source_point + Vector2(22, 3), true)
		if viewport.gui_is_dragging():
			await mouse_move(invalid_point, true)
			await mouse_button(false)
		var after_invalid: Dictionary = main.resource_board_state.deployments.player.get(String(resource.instance_id), {})
		check(after_invalid.get("anchor", []) == before_invalid.get("anchor", []), "真实鼠标拖到占用格被拒绝并保留原部署")
		var clicked_cell := after_invalid.get("anchor", []) as Array
		var click_anchor := Vector2i(int(clicked_cell[0]), int(clicked_cell[1]))
		var click_point: Vector2 = tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(click_anchor + moved_grab))
		await mouse_move(click_point)
		await mouse_button(true)
		await mouse_button(false)
		check(not main._click_carry_data.is_empty(), "鼠标轻点资源拼图拾起后进入点击携带状态")
		await mouse_move(click_point + Vector2(25, 9))
		var click_grab: Vector2i = main._click_carry_data.get("resource_grab_cell", Vector2i.ZERO)
		var click_icon_index := resource.resource_shape.find(click_grab)
		var click_icon_center: Vector2 = main._click_carry_preview._resource_puzzle_icons[click_icon_index].get_global_rect().get_center()
		check(
			click_icon_center.distance_to(pointer) <= 1.0,
			"点击携带模式下抓取格种类图标随鼠标锚定"
		)
		await escape_key()
		check(main._click_carry_data.is_empty() and main.resource_board_state.deployments.player.has(String(resource.instance_id)), "ESC取消拾起并恢复原位")
		# 通过原生拖拽把资源退回收藏格。
		var return_source_point: Vector2 = click_point
		await mouse_move(return_source_point)
		await mouse_button(true)
		await mouse_move(return_source_point + Vector2(24, 4), true)
		if viewport.gui_is_dragging():
			var return_target: Vector2 = main.collection_drop_zone.get_global_rect().get_center()
			await mouse_move(return_target, true)
			await mouse_button(false)
		check(
			not main.resource_board_state.deployments.player.has(String(resource.instance_id))
			and main.owned_card_collection.get_by_instance_id(resource.instance_id) == resource,
			"资源板拖回收藏的真实鼠标操作收回部署且保留卡牌"
		)
		var lower_left_display_cards: Array[CardData] = main.get_displayed_collection_cards()
		var lower_left_card_index := lower_left_display_cards.find(resource.card_data)
		if lower_left_card_index >= 0:
			main.current_collection_page = lower_left_card_index / main.COLLECTION_SLOTS_PER_PAGE
			main._build_collection_cards()
			await process_frame
			source_slot = main._find_collection_slot_for_owned_card(resource)
		check(is_instance_valid(source_slot), "真实鼠标左下角抓取前卡牌位于当前收藏页")
		if is_instance_valid(source_slot):
			source_view = source_slot.get_child(0) as CardView
			var lower_left_rect := source_view.get_global_rect()
			var lower_left_point := lower_left_rect.position + Vector2(8.0, lower_left_rect.size.y - 8.0)
			await mouse_move(lower_left_point)
			await mouse_button(true)
			await mouse_move(lower_left_point + Vector2(24, 4), true)
			if viewport.gui_is_dragging():
				var lower_left_data := viewport.gui_get_drag_data() as Dictionary
				var lower_left_preview := lower_left_data.get("drag_visual") as CardDragPreview
				var lower_left_grab: Dictionary = tray._map_card_grab_to_shape(resource.resource_shape, lower_left_data.get("grab_local_position", Vector2(2, 134)))
				var lower_left_anchor := _find_anchor(resource.resource_shape, _occupied_cells(main.resource_board_state, "player"), Vector2i(-99, -99), player_disabled)
				var lower_left_drop: Vector2 = tray.get_global_transform_with_canvas() * (
					tray.LAYOUT_ORIGIN + ResourceHexLayout.center(lower_left_anchor + lower_left_grab.cell) + lower_left_grab.pixel_offset
				)
				await mouse_move(lower_left_drop, true)
				await create_timer(0.12).timeout
				check(
					is_instance_valid(lower_left_preview)
					and lower_left_preview._resource_puzzle_icons[lower_left_preview._resource_puzzle_shape.find(lower_left_grab.cell)].get_global_rect().get_center().distance_to(pointer) <= 1.0,
					"收藏卡左下角抓取切换拼图后对应格图标仍锚定鼠标"
				)
				await mouse_button(false)
				check(main.resource_board_state.deployments.player.has(String(resource.instance_id)), "左下角真实鼠标拖放仍按同一映射完成资源部署")
	# 真实移动事件触发双方资源悬停卡；悬停卡忽略鼠标，输入仍落在托盘。
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	main.resource_board_state.try_deploy("player", String(resource.instance_id), resource.resource_shape, target_anchor, resource.resource_shape[0])
	main._refresh_resource_preparation_trays()
	var automatic_card: OwnedCard = main.resource_board_state.get_level_resource_cards("player")[0]
	var automatic_id := String(automatic_card.instance_id)
	var automatic_before: Dictionary = main.resource_board_state.deployments.player[automatic_id].duplicate(true)
	var automatic_tile := player_tray._tile_nodes_by_id[automatic_id][0] as Control
	var automatic_point := automatic_tile.get_global_rect().get_center()
	await mouse_move(automatic_point)
	await mouse_button(true)
	await mouse_move(automatic_point + Vector2(28, 4), true)
	check(not viewport.gui_is_dragging(), "关卡自动资源按住移动不会触发原生拖拽")
	await mouse_button(false)
	await mouse_move(automatic_point)
	await mouse_button(true)
	await mouse_button(false)
	check(main._click_carry_data.is_empty() and main.resource_board_state.deployments.player[automatic_id] == automatic_before, "自动资源不能点按拾取或移动且部署原位保留")
	await mouse_move(automatic_point)
	check(is_instance_valid(player_tray._hover_card) and player_tray._hover_card.card_data == automatic_card.card_data, "不可移动的自动资源仍可悬停检视")
	var player_tile := player_tray._tile_nodes_by_id[String(resource.instance_id)][0] as Control
	await mouse_move(player_tile.get_global_rect().get_center())
	var player_hover = player_tray._hover_card
	check(is_instance_valid(player_hover) and player_hover.card_data == resource.card_data and player_hover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "玩家资源悬停显示完整卡面且不截获输入")
	var enemy_tray: ResourcePreparationTray = main.enemy_resource_tray
	var enemy_placement_anchor := _find_anchor(enemy_resource.resource_shape, _occupied_cells(main.resource_board_state, "enemy"), Vector2i(-99, -99), _disabled_cells(main.resource_board_state.disabled_by_side.enemy))
	check(main.resource_board_state.deploy_level_resource("enemy", enemy_resource, enemy_placement_anchor), "添加一个敌方关卡资源用于悬停输入验收")
	main._refresh_resource_preparation_trays()
	var tray_rect := enemy_tray.get_global_rect()
	var hover_rect := Rect2()
	var enemy_tile: Control
	for enemy_card: OwnedCard in main.resource_board_state.get_level_resource_cards("enemy"):
		enemy_tile = enemy_tray._tile_nodes_by_id[String(enemy_card.instance_id)][0] as Control
		await mouse_move(enemy_tile.get_global_rect().get_center())
		var enemy_hover := enemy_tray._hover_card
		var card_rect: Rect2 = enemy_hover.get_global_rect() if is_instance_valid(enemy_hover) else Rect2()

		check(is_instance_valid(enemy_hover) and enemy_hover.card_data == enemy_card.card_data and enemy_hover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "敌方资源%s悬停显示对应完整卡面" % enemy_card.card_data.display_name)
		check(card_rect.position.x >= 0.0 and card_rect.end.x <= 1280.0 and card_rect.position.y >= 0.0 and card_rect.end.y <= 720.0, "敌方资源卡面在%s画布内完整可见" % ("2K" if is_2k else "720p"))
		hover_rect = card_rect
	await create_timer(0.2).timeout
	check(is_instance_valid(enemy_tray._hover_card) and enemy_tray._hover_card.is_visible_in_tree(), "敌方资源完整详情卡绘制在现有全局悬停层")
	check(not tray_rect.intersects(hover_rect), "敌方资源托盘与完整悬停卡面不重叠")
	await mouse_move(Vector2(600, 350))
	check(not is_instance_valid(enemy_tray._hover_card), "鼠标离开敌方资源板后关闭详情卡")
	await mouse_move(enemy_tile.get_global_rect().get_center())
	check(is_instance_valid(enemy_tray._hover_card) and enemy_tray._hover_card.card_data == enemy_resource.card_data, "重新悬停另一张敌方资源时切换到对应卡面")
	var overlap_with_controls := false
	for control: Control in [main.start_battle_button, main.phase_label, main.battle_seed_panel, main.ground_reward_panel]:
		if is_instance_valid(control) and control.visible and hover_rect.intersects(control.get_global_rect()): overlap_with_controls = true
	check(not overlap_with_controls, "悬停卡面不覆盖开战、阶段、种子或奖励控制条")
	var escape_rect: Rect2 = main._escape_pause_menu.get_node("EscapeMenuButton").get_global_rect()
	var mode_rect: Rect2 = shell.display_mode_option.get_parent().get_global_rect()
	var physical_hover := Rect2(transform * hover_rect.position, hover_rect.size * transform.get_scale())
	check(
		not escape_rect.intersects(tray_rect) and not escape_rect.intersects(hover_rect)
		and not mode_rect.intersects(physical_hover),
		"Esc与显示模式入口在真实窗口中避开资源板和悬停卡"
	)
	if args.has("capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-resource-hover-%s.png" % ("2k" if is_2k else "720p"))
	check(
		root.get_texture().get_size() == (Vector2(2560, 1440) if is_2k else Vector2(1280, 720)),
		"真实窗口视口截图尺寸匹配%s" % ("2K" if is_2k else "720p")
	)
	var fighter: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres") as CardData)
	main.front_row.add_squad(SquadData.from_owned_card(fighter), 0)
	check(main.start_battle(20260930, false), "真实显示壳启动包含双方资源的战斗")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await mouse_move(Vector2(500, 350))
	enemy_tile = enemy_tray._tile_nodes_by_id[String(enemy_resource.instance_id)][0] as Control
	await mouse_move(enemy_tile.get_global_rect().get_center())
	check(
		main.current_phase == main.GamePhase.BATTLE and not enemy_tray._enabled
		and is_instance_valid(enemy_tray._hover_card)
		and enemy_tray._hover_card.card_data == enemy_resource.card_data,
		"战斗中关闭资源部署后，真实鼠标仍可查看敌方完整资源卡"
	)
	if args.has("capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-resource-combat-%s.png" % ("2k" if is_2k else "720p"))
	for state: BattleResourceState in main.battle_controller.enemy_resource_states:
		if state.owned_card != enemy_resource: continue
		state.apply_damage(state.current_health)
		main.enemy_resource_tray.set_battle_health(main.battle_controller.enemy_resource_states)
		break
	check(not is_instance_valid(enemy_tray._hover_card) and not enemy_tray._tile_nodes_by_id.has(String(enemy_resource.instance_id)), "敌方资源被击碎后刷新托盘并关闭已失效详情卡")
	shell.queue_free()
	await process_frame
	if failures == 0: print("D2-6C native resource input checks passed.")
	quit(failures)

func _find_anchor(shape: Array[Vector2i], occupied: Dictionary, skip := Vector2i(-99, -99), disabled: Dictionary = {}) -> Vector2i:
	for cell: Vector2i in ResourceHexLayout.valid_cells():
		for grab: Vector2i in shape:
			var anchor := cell - grab
			if anchor == skip: continue
			if ResourceHexLayout.can_place(shape, anchor, occupied, disabled): return anchor
	return Vector2i(-99, -99)

func _disabled_cells(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in cells: result[cell] = true
	return result

func _occupied_cells(board, side: String, excluded: Array = []) -> Dictionary:
	var result: Dictionary = {}
	for instance_id: Variant in board.deployments[side]:
		if String(instance_id) in excluded: continue
		var placement: Dictionary = board.deployments[side][instance_id]
		var anchor := Vector2i(int(placement.anchor[0]), int(placement.anchor[1]))
		for pair: Array in placement.shape:
			result[anchor + Vector2i(int(pair[0]), int(pair[1]))] = true
	return result
