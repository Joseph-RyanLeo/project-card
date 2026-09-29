extends SceneTree

const MainScript = preload("res://scripts/main.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := load("res://scenes/Main.tscn").instantiate() as MainScript
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.emblem_library != null, "主界面建立单一开发纹章库节点")
	_expect(main.emblem_library.get_inventory_state().is_empty(), "新局不自动把开发目录中的定义注入贴纸库存")
	var console_layer := main.get_node("DeveloperConsoleLayer") as CanvasLayer
	var console_ready: bool = (
		is_instance_valid(main._developer_console)
		and not main._developer_console.visible
		and console_layer.layer == 1
		and main._developer_console.z_index == 0
		and main._developer_console.mouse_filter == Control.MOUSE_FILTER_STOP
	)
	var console_open := InputEventKey.new()
	console_open.keycode = KEY_F2
	console_open.pressed = true
	root.push_input(console_open, true)
	await process_frame
	console_ready = console_ready and main._developer_console.visible
	main._on_developer_console_command_submitted("sticker add 火把")
	var console_added_items: Array[Dictionary] = main.emblem_library.get_inventory_state()
	console_ready = console_ready and console_added_items.size() == 1 and StringName(String(console_added_items[0].get("emblem_id", ""))) == &"火把"
	main._on_developer_console_command_submitted("wound add 中毒Ⅰ")
	console_added_items = main.emblem_library.get_inventory_state()
	console_ready = console_ready and console_added_items.size() == 2 and console_added_items[1].get("kind") == "wound"
	main.emblem_library.restore_inventory_state([])
	var console_close := InputEventKey.new()
	console_close.keycode = KEY_F2
	console_close.pressed = true
	root.push_input(console_close, true)
	await process_frame
	_expect(console_ready and not main._developer_console.visible, "F2 控制台可分别按贴纸ID与伤势名称加入独立实例")
	for entry_data: Array in [
		[&"火把", &"test_torch"],
		[&"光贴纸", &"test_light"],
		[&"长剑", &"test_sword"],
	]:
		var accepted: bool = main.emblem_library.return_sticker({
			"instance_id": entry_data[1],
			"emblem_id": entry_data[0],
			"temporary": false,
		})
		_expect(accepted, "真实库存接口接收已获得的%s实例" % String(entry_data[0]))
	var library_grid: Control = main.emblem_library.get_node("Scroll/Grid")
	var library_board: TextureRect = main.emblem_library.get_node("Board") as TextureRect
	var library_entries: Array = main.emblem_library._entries
	var normal_positions: Array[Vector2] = []
	for entry: Control in library_entries:
		normal_positions.append(entry.position)
	var layout_valid := library_entries.size() == 3
	layout_valid = layout_valid and library_board.size == Vector2(195, 148)
	layout_valid = layout_valid and library_board.get_parent() == main.emblem_library
	layout_valid = layout_valid and library_board.get_index() < main.emblem_library._scroll.get_index()
	for index: int in library_entries.size():
		var entry: Control = library_entries[index]
		var span := 2 if entry.is_element_sticker() else 1
		var expected_size := Vector2(14.0, 14.0) * span + Vector2.ONE * 3.0 * (span - 1)
		layout_valid = layout_valid and entry.size == expected_size
		layout_valid = layout_valid and entry.position.x >= 114 and entry.position.x + entry.size.x <= 179
		layout_valid = layout_valid and entry.position.y >= 16 and entry.position.y + entry.size.y <= 132
		for previous_index: int in index:
			var previous: Control = library_entries[previous_index]
			layout_valid = layout_valid and not Rect2(entry.position, entry.size).intersects(
				Rect2(previous.position, previous.size)
			)
	_expect(layout_valid, "横放工具箱右侧固定4×7格网，普通贴纸占14×14、元素贴纸占31×31")
	var ordinary_entries: Array[Control] = []
	for entry: Control in library_entries:
		if not entry.is_element_sticker():
			ordinary_entries.append(entry)
	_expect(ordinary_entries.size() == 2 and ordinary_entries[0].position.y == ordinary_entries[1].position.y, "普通纹章各自占一个格位")
	var scroll: ScrollContainer = main.emblem_library._scroll
	_expect(
		library_grid.size == Vector2(195, 148)
		and scroll.size == Vector2(195, 148)
		and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER
		and not scroll.get_v_scroll_bar().visible,
		"网格视口完整贴合横放底图，格网不滚动扩容"
	)
	var icons_centered := true
	for entry: Control in library_entries:
		var icon: TextureRect = entry.get_node("Icon")
		var expected_icon_size := Vector2(31, 31) if entry.is_element_sticker() else Vector2(14, 14)
		icons_centered = icons_centered and icon.size == expected_icon_size
		icons_centered = icons_centered and icon.position == (entry.size - icon.size) * 0.5
	_expect(icons_centered, "纹章与元素图标分别按14×14、31×31显示并居中")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-emblem-library-normal.png")
	main._on_developer_console_command_submitted("wound add 中毒Ⅰ")
	var wound_state: Dictionary = main.emblem_library.get_inventory_state().back()
	var wound_catalog_valid: bool = wound_state.get("kind") == "wound" and wound_state.get("wound_id") == &"中毒Ⅰ"
	_expect(
		EmblemLibraryData.get_tooltip(&"火把").contains("耀眼") and wound_catalog_valid
		and main.emblem_library._entries.back().size == Vector2(14, 14),
		"F2命令新增伤势后只出现一个14×14独立库存实例"
	)

	var source_slot: Control
	var owned: OwnedCard
	for candidate: Control in main._get_collection_card_slots():
		var candidate_owned := candidate.get_meta("owned_card", null) as OwnedCard
		if candidate_owned != null and not candidate_owned.emblem_slots.is_empty():
			source_slot = candidate
			owned = candidate_owned
			break
	var definition := owned.card_data if owned != null else null
	_expect(owned != null and owned is OwnedCard, "检视目标使用收藏中的OwnedCard实例")
	var source_card := source_slot.get_child(0) as CardView
	_expect(
		source_card.get_node("StatusSlotLayer").get_child_count() == 0,
		"普通卡面通过统一绘制层显示空槽提示点，不在状态图层堆叠占位节点"
	)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = source_card.get_global_rect().get_center()
	root.push_input(right_click, true)
	await create_timer(0.3).timeout
	var overlay := main._inspection_overlay as Control
	var inspect_card := main._inspection_card_view as CardView
	var inspection_library_bounds: Rect2 = main.emblem_library.get_display_bounds()
	var inspection_library_left: float = (
		main.emblem_library.position.x + inspection_library_bounds.position.x * main.emblem_library.scale.x
	)
	var inspection_library_right: float = (
		inspection_library_left + inspection_library_bounds.size.x * main.emblem_library.scale.x
	)
	var inspected_card_rect: Rect2 = main._inspection_surface.get_global_rect()
	var inspected_effect_box := overlay.get_node_or_null("InspectionEffectSideBox") as PanelContainer
	_expect(
		is_instance_valid(overlay)
		and is_instance_valid(inspect_card)
		and main._inspection_surface.scale == Vector2(4, 4)
		and overlay.get_node("InspectionDim").z_index == 0
		and main.emblem_library.get_parent() == overlay
		and main.emblem_library.scale.x <= 4.0
		and main.emblem_library.scale.x > 0.0
		and inspection_library_left < 0.0
		and inspection_library_right == 28.0
		and main.emblem_library.get_global_rect().size.is_equal_approx(Vector2(780, 592))
		and main._inspection_surface.position.is_equal_approx((overlay.size - main._inspection_surface.size * Vector2(4, 4)) * 0.5)
		and main._inspection_library_toggle != null
		and main._inspection_library_toggle.get_global_rect().position.x == 0.0
		and (inspected_effect_box == null or inspected_effect_box.get_global_rect().end.x <= overlay.size.x),
		"默认检视中工具箱4×收在左侧只露28像素边缘，卡牌仍居中且工具箱可见尺寸780×592"
	)
	await _click(main._inspection_library_toggle.get_global_rect().get_center())
	await create_timer(0.3).timeout
	var expanded_visible_left: float = 32.0 + 780.0 + 24.0
	var expanded_visible_right: float = expanded_visible_left + inspect_card.card_size.x * 4.0
	_expect(
		main._inspection_library_expanded
		and main.emblem_library.position.is_equal_approx(Vector2(32, 64))
		and is_equal_approx(expanded_visible_left, 836.0)
		and expanded_visible_right <= overlay.size.x
		and main._inspection_surface.position.x + main._inspection_surface.PADDING.x * 4.0 == expanded_visible_left,
		"点击露边展开工具箱时按卡面实际边界让位，4×卡框和工具箱都完整留在720p画布内"
	)
	await _click(main._inspection_library_toggle.get_global_rect().get_center())
	await create_timer(0.3).timeout
	_expect(
		not main._inspection_library_expanded
		and main._inspection_surface.position.is_equal_approx((overlay.size - main._inspection_surface.size * Vector2(4, 4)) * 0.5),
		"再次点击同侧边缘收回工具箱并让卡牌回到居中"
	)
	var inspection_entries: Array = main.emblem_library._entries
	var inspect_layout_valid := inspection_entries.size() >= normal_positions.size()
	for index: int in mini(inspection_entries.size(), normal_positions.size()):
		var entry := inspection_entries[index] as Control
		inspect_layout_valid = inspect_layout_valid and entry.position == normal_positions[index]
	_expect(
		inspect_layout_valid
		and is_equal_approx(library_grid.size.x, 195.0)
		and main.emblem_library._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER
		and not main.emblem_library._scroll.get_v_scroll_bar().visible,
		"常规与检视共用相同占格坐标和固定板面，不重排或分页"
	)
	if "--capture" in OS.get_cmdline_user_args():
		main.emblem_library._scroll.scroll_vertical = 0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-emblem-library-inspection.png")
	_expect(
		inspect_card.get_node_or_null("EmptyEmblemSlotMarkers") == null
		and CardSlotLayout.get_slot_definitions(definition, owned).size() == owned.wound_slots.size() + owned.emblem_slots.size(),
		"检视卡沿用OwnedCard布局并仅由卡面统一绘制2×2提示点"
	)
	var emblem_definition := _inventory_definition(main, &"火把")
	var emblem_drag := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": emblem_definition["id"],
		"definition": emblem_definition,
	} as Dictionary
	var first_emblem_position := _first_empty_emblem_position(owned)
	_expect(
		not main._drop_emblem_on_inspection_card(inspect_card, Vector2(-20, -20), emblem_drag)
		and main.emblem_library.get_inventory_item(&"test_torch").get("emblem_id", &"") == &"火把",
		"非法槽位拒绝粘贴且原贴纸实例仍保留在工作包"
	)
	_expect(
		inspect_card._can_drop_data(first_emblem_position, emblem_drag),
		"准备阶段真实纹章条目可以命中第一个合法空纹章槽"
	)
	inspect_card._drop_data(first_emblem_position, emblem_drag)
	await process_frame
	_expect(
		owned.emblem_slots[0].get("emblem_id", &"") == &"火把"
		and owned.emblem_slots[0].get("instance_id", &"") != &""
		and inspect_card.get_node("StatusSlotLayer").get_child_count() == 1,
		"粘贴会写入真实OwnedCard槽位并刷新检视卡面"
	)
	var rune_definition := _inventory_definition(main, &"光贴纸")
	var rune_drag := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": rune_definition["id"],
		"definition": rune_definition,
	} as Dictionary
	_expect(
		not inspect_card._can_drop_data(first_emblem_position, rune_drag),
		"元素贴纸不会误贴到普通纹章槽"
	)
	var save_path := "/private/tmp/project-card-d2-7-emblem-inspection-save.json"
	_expect(main.save_run_to_path(save_path) == OK, "纹章槽位进入现有JSON存档链路")
	var saved_text := FileAccess.get_file_as_string(save_path)
	_expect(saved_text.contains("test_torch"), "存档包含刚粘贴的纹章实例身份")
	main._close_card_inspection()
	await create_timer(0.25).timeout
	_expect(
		main._inspection_overlay == null
		and main.emblem_library.get_parent() == main._emblem_library_parent
		and main.emblem_library.scale == Vector2.ONE
		and not main.get_tree().paused,
		"关闭检视恢复纹章库布局与暂停状态"
	)
	main.set_phase_for_test(MainScript.GamePhase.BATTLE)
	main.battle_effect_layer.visible = true
	main._open_card_inspection(definition, owned)
	await process_frame
	var battle_inspect_card := main._inspection_card_view as CardView
	var battle_definition := _inventory_definition(main, &"长剑")
	var battle_drag := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": battle_definition["id"],
		"definition": battle_definition,
	} as Dictionary
	_expect(
		main.get_tree().paused
		and main._inspection_overlay.process_mode == Node.PROCESS_MODE_ALWAYS
		and not main.battle_effect_layer.visible
		and not battle_inspect_card._can_drop_data(first_emblem_position, battle_drag)
		and not main.emblem_library.get_node("Scroll/Grid").get_child(0).get("drag_enabled"),
		"战斗检视层始终可处理输入、隐藏全局浮字并保持只读"
	)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await create_timer(0.25, true).timeout
	_expect(
		main._inspection_overlay == null
		and not main.get_tree().paused
		and main.battle_effect_layer.visible,
		"Esc 关闭检视并恢复原暂停状态与浮动战斗特效"
	)
	main._open_card_inspection(definition, owned)
	await process_frame
	var dim_click := InputEventMouseButton.new()
	dim_click.button_index = MOUSE_BUTTON_LEFT
	dim_click.pressed = true
	dim_click.position = _find_exposed_dim_point(main._inspection_dim)
	root.push_input(dim_click, true)
	var dim_release := dim_click.duplicate() as InputEventMouseButton
	dim_release.pressed = false
	root.push_input(dim_release, true)
	await create_timer(0.25, true).timeout
	_expect(
		main._inspection_overlay == null and not main.get_tree().paused,
		"点击暗幕可在战斗暂停状态下关闭检视"
	)
	main._open_card_inspection(definition, owned)
	var battle_right_click := InputEventMouseButton.new()
	battle_right_click.button_index = MOUSE_BUTTON_RIGHT
	battle_right_click.pressed = true
	battle_right_click.position = Vector2(640, 360)
	root.push_input(battle_right_click, true)
	var battle_right_release := battle_right_click.duplicate() as InputEventMouseButton
	battle_right_release.pressed = false
	root.push_input(battle_right_release, true)
	await create_timer(0.25, true).timeout
	_expect(
		main._inspection_overlay == null and not main.get_tree().paused,
		"右键可在战斗暂停状态下关闭检视"
	)
	main._open_card_inspection(definition, owned)
	_expect(
		main._inspection_overlay.get_node_or_null("CloseInspectionButton") == null,
		"检视不再创建冗余关闭按钮"
	)
	var escape_close := InputEventKey.new()
	escape_close.keycode = KEY_ESCAPE
	escape_close.pressed = true
	root.push_input(escape_close, true)
	await create_timer(0.25, true).timeout
	_expect(main._inspection_overlay == null and not main.get_tree().paused, "Esc 仍可关闭检视")
	main.get_tree().paused = true
	main._open_card_inspection(definition, owned)
	main._close_card_inspection(true)
	_expect(
		main.get_tree().paused,
		"关闭检视保留打开前已经存在的暂停状态"
	)
	main.get_tree().paused = false
	main.set_phase_for_test(MainScript.GamePhase.PREPARE)
	main.queue_free()
	await process_frame
	print("D2-7 emblem inspection checks: %d failures" % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = position
	down.global_position = position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = position
	up.global_position = position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	await process_frame


func _first_empty_emblem_position(owned: OwnedCard) -> Vector2:
	for slot: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if int(slot.get("kind", -1)) != CardSlotLayout.Kind.EMBLEM:
			continue
		var slot_index := int(slot.get("storage_index", -1))
		if slot_index >= 0 and slot_index < owned.emblem_slots.size() and owned.emblem_slots[slot_index].is_empty():
			return (slot.get("position", Vector2.ZERO) as Vector2) + Vector2(7, 7)
	return Vector2.INF


func _inventory_definition(main: MainScript, emblem_id: StringName) -> Dictionary:
	var definition: Dictionary = {}
	for candidate: Dictionary in main.emblem_library.get_definitions():
		if StringName(String(candidate.get("id", ""))) == emblem_id:
			definition = candidate.duplicate(true)
			break
	if definition.is_empty():
		return {}
	for state: Dictionary in main.emblem_library.get_inventory_state():
		if StringName(String(state.get("emblem_id", ""))) == emblem_id:
			definition["returned_state"] = state
			return definition
	return {}


func _find_exposed_dim_point(dim: Control) -> Vector2:
	var overlay := dim.get_parent() as Control
	for y in range(710, 0, -10):
		for x in range(1270, 0, -10):
			var point := Vector2(x, y)
			if dim.get_global_rect().has_point(point) and not _covered_by_interactive_control(overlay, dim, point):
				return point
	return Vector2(640, 700)


func _covered_by_interactive_control(parent: Control, dim: Control, point: Vector2) -> bool:
	for child: Node in parent.get_children():
		if child == dim:
			continue
		if child is Control:
			var control := child as Control
			if (
				control.is_visible_in_tree()
				and control.mouse_filter == Control.MOUSE_FILTER_STOP
				and control.get_global_rect().has_point(point)
			):
				return true
			if _covered_by_interactive_control(control, dim, point):
				return true
	return false
