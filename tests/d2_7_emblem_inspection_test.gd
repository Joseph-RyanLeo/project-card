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
	_expect(
		main.emblem_library.get_definitions().size() == 41
		and main.emblem_library.get_node("Scroll/Grid").get_child_count() == 41,
		"纹章库包含CSV中的41条纹章定义，不混入伤势"
	)
	var library_grid: Control = main.emblem_library.get_node("Scroll/Grid")
	var library_entries: Array = main.emblem_library._entries
	var layout_valid := is_equal_approx(library_grid.size.x, 60.0)
	for index: int in library_entries.size():
		var entry: Control = library_entries[index]
		var span := 2 if entry.is_element_sticker() else 1
		var expected_size := Vector2(15.0, 15.0) * span
		layout_valid = layout_valid and entry.size == expected_size
		layout_valid = layout_valid and entry.position.x >= 0 and entry.position.x + entry.size.x <= 60
		for previous_index: int in index:
			var previous: Control = library_entries[previous_index]
			layout_valid = layout_valid and not Rect2(entry.position, entry.size).intersects(
				Rect2(previous.position, previous.size)
			)
	_expect(layout_valid, "普通项占15×15、每枚元素项占30×30且全体无重叠裁切")
	var ordinary_entries: Array[Control] = []
	for entry: Control in library_entries:
		if not entry.is_element_sticker():
			ordinary_entries.append(entry)
	_expect(
		ordinary_entries[0].position.y == ordinary_entries[1].position.y
		and ordinary_entries[1].position.y == ordinary_entries[2].position.y
		and ordinary_entries[2].position.y == ordinary_entries[3].position.y,
		"左到右空位扫描允许后续普通纹章补入首排第四格"
	)
	var scroll: ScrollContainer = main.emblem_library._scroll
	_expect(
		library_grid.size.y > scroll.size.y
		and scroll.get_v_scroll_bar().max_value > 0.0,
		"41项占格内容超过视口并可纵向滚动"
	)
	var icons_centered := true
	for entry: Control in library_entries:
		var icon: TextureRect = entry.get_node("Icon")
		var expected_icon_size := Vector2(27, 27) if entry.is_element_sticker() else Vector2(14, 14)
		icons_centered = icons_centered and icon.size == expected_icon_size
		icons_centered = icons_centered and icon.position == (entry.size - icon.size) * 0.5
	_expect(icons_centered, "普通图标维持14×14、元素维持27×27且均居中于占格范围")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await process_frame
	var final_entry: Control = library_entries.back()
	_expect(
		final_entry.get_global_rect().intersects(scroll.get_global_rect())
		and scroll.scroll_vertical > 0,
		"滚动到底仍能实际访问最后一项纹章"
	)
	scroll.scroll_vertical = 0
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/project-card-emblem-library-normal.png")
	_expect(
		EmblemLibraryData.get_tooltip(&"火把").contains("耀眼")
		and EmblemLibraryData.get_wound_definitions().size() == 27,
		"卡牌提示可读取41条纹章与27条伤势的本地审阅资料"
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
	_expect(
		is_instance_valid(overlay)
		and is_instance_valid(inspect_card)
		and main._inspection_surface.scale == Vector2(4, 4)
		and overlay.get_node("InspectionDim").z_index == 0
		and main.emblem_library.get_parent() == overlay
		and main.emblem_library.scale == Vector2(4, 4)
		and main.wound_library.get_parent() == overlay
		and main.wound_library.scale == Vector2(4, 4),
		"检视层使用4×逻辑放大，两侧工作区与暗幕按层级显示"
	)
	var normal_positions: Array[Vector2] = []
	for entry: Control in library_entries:
		normal_positions.append(entry.position)
	var inspect_layout_valid := true
	for index: int in library_entries.size():
		inspect_layout_valid = inspect_layout_valid and library_entries[index].position == normal_positions[index]
	_expect(
		inspect_layout_valid
		and is_equal_approx(library_grid.size.x, 60.0)
		and main.emblem_library._scroll.get_v_scroll_bar().max_value > 0.0,
		"常规与检视共用相同占格坐标，检视按4×显示且可滚动访问全部条目"
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
	var emblem_definition := main.emblem_library.get_definitions()[0] as Dictionary
	var emblem_drag := {
		"kind": &"emblem_library",
		"source_type": &"emblem_library",
		"emblem_id": emblem_definition["id"],
		"definition": emblem_definition,
	} as Dictionary
	var first_emblem_position := _first_empty_emblem_position(owned)
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
	var rune_definition := main.emblem_library.get_definitions()[3] as Dictionary
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
	_expect(saved_text.contains("dev_emblem_火把"), "存档包含刚粘贴的纹章实例身份")
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
	var battle_definition := main.emblem_library.get_definitions()[1] as Dictionary
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
		and not bool(main.emblem_library.get_node("Scroll/Grid").get_child(0).drag_enabled),
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
	var close_button := main._inspection_overlay.get_node("CloseInspectionButton") as Button
	var close_click := InputEventMouseButton.new()
	close_click.button_index = MOUSE_BUTTON_LEFT
	close_click.pressed = true
	close_click.position = close_button.get_global_rect().get_center()
	root.push_input(close_click, true)
	var close_release := close_click.duplicate() as InputEventMouseButton
	close_release.pressed = false
	root.push_input(close_release, true)
	await create_timer(0.25, true).timeout
	_expect(
		main._inspection_overlay == null and not main.get_tree().paused,
		"关闭按钮可在战斗暂停状态下关闭检视"
	)
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


func _first_empty_emblem_position(owned: OwnedCard) -> Vector2:
	for slot: Dictionary in CardSlotLayout.get_slot_definitions(owned.card_data, owned):
		if int(slot.get("kind", -1)) != CardSlotLayout.Kind.EMBLEM:
			continue
		var slot_index := int(slot.get("storage_index", -1))
		if slot_index >= 0 and slot_index < owned.emblem_slots.size() and owned.emblem_slots[slot_index].is_empty():
			return (slot.get("position", Vector2.ZERO) as Vector2) + Vector2(7, 7)
	return Vector2.INF


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
