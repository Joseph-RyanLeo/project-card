extends SceneTree

const Catalog = preload("res://scripts/flow/enemy_lineup_catalog.gd")
const Metrics = preload("res://scripts/tools/enemy_lineup_metrics.gd")
const LineupEditor = preload("res://scripts/tools/enemy_lineup_editor.gd")
const LabScene = preload("res://scenes/tools/BattleLab.tscn")
const MainScene = preload("res://scenes/Main.tscn")
const Builder = preload("res://scripts/flow/enemy_encounter_builder.gd")
const DRAFT := "/private/tmp/project-card-lineup-editor-drafts.json"
const EXPORT := "/private/tmp/project-card-lineup-editor-export.json"
const SAVE := "/private/tmp/project-card-lineup-editor-run.json"

var failures := 0
var assertions := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(28).timeout.connect(func(): push_error("阵容调试专项超时"); quit(1))
	for path: String in [DRAFT, EXPORT, SAVE, SAVE + ".bak"]: DirAccess.remove_absolute(path)
	root.size = Vector2i(1280, 720)
	var levels := await _editor_workflow()
	await _real_encounter(levels)
	for path: String in [DRAFT, EXPORT, SAVE, SAVE + ".bak"]: DirAccess.remove_absolute(path)
	print("阵容调试专项：%d 项，%d 失败" % [assertions, failures])
	quit(1 if failures else 0)


func _editor_workflow() -> Dictionary:
	var lab := LabScene.instantiate() as BattleLab
	root.add_child(lab)
	(lab.find_child("EncounterLineupsButton", true, false) as Button).pressed.emit()
	var editor := lab.find_child("EnemyLineupEditor", true, false) as LineupEditor
	check(editor != null and editor.visible and editor.lineup_picker.item_count >= 3, "战斗实验室入口加载本关正式阵容")
	if editor == null: return {}
	editor._drafts.clear()
	editor._sessions.clear()
	editor.draft_path = DRAFT
	editor.export_path = EXPORT
	editor._select_level(0)
	await create_timer(0.2).timeout
	check(editor._references.size() >= 3 and editor._metrics.text.contains("理论 DPS") and editor._metrics.text.contains("法术稀有度"), "实时面板展示正式关卡参考与各项指标")
	var before := Metrics.measure(editor._prepare(editor._working))
	editor._duplicate_lineup()
	editor.name_edit.text = "夹击编队"
	editor.name_edit.text_changed.emit("夹击编队")
	var workspace: Control = editor.workspace
	var table: Control = workspace.table
	check(not editor._management.visible and table.recent_bookmark_button.is_visible_in_tree(), "正常桌面仅显示蓝色书签，管理独立于收藏")
	table.recent_bookmark_button.pressed.emit()
	await create_timer(0.7).timeout
	check(editor._management.visible and table.get_displayed_collection_cards().is_empty(), "蓝签翻到阵容管理而非最近使用")
	await _capture_screen("blue")
	table.recent_bookmark_button.pressed.emit()
	await create_timer(0.7).timeout
	var right_click := InputEventMouseButton.new()
	right_click.position = editor._summary.get_global_rect().get_center()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	root.push_input(right_click)
	right_click.pressed = false
	root.push_input(right_click)
	check(editor._detail.visible, "右键右下角指标板打开明细")
	editor._detail.hide()
	var variants: Array = workspace._palette.filter(func(owned: OwnedCard) -> bool: return owned.card_data.id == &"crystal_shell_beetle")
	check(variants.size() == 2 and variants[0].resolved_action_type != variants[1].resolved_action_type and variants.all(func(owned: OwnedCard) -> bool: return not owned.rune_revealed.has(true)), "每种合法行动有一张未刮开的收藏模板")
	var pack: StringName = variants[0].card_data.pack_id
	var picker: OptionButton = workspace.pack_picker
	for index: int in range(1, picker.item_count):
		if picker.get_item_metadata(index) != pack: continue
		picker.item_selected.emit(index)
		break
	check(not pack.is_empty() and workspace._pack == pack and table.get_filtered_collection_cards().all(func(card: CardData) -> bool: return card.pack_id == pack), "按所属卡包筛选收藏")
	picker.item_selected.emit(0)
	var sticker_pages: Array = workspace._sticker_pages
	check(sticker_pages.map(func(page: Dictionary) -> String: return page.title) == ["基础纹章", "合成纹章", "符文贴纸", "伤势"], "工具箱合并为四页，按用途排序")
	var fusion_ids := {}
	for recipe: Dictionary in EmblemFusionRecipes.RECIPES: fusion_ids[recipe.result] = true
	check(sticker_pages[1].definitions.size() == fusion_ids.size() and sticker_pages[1].definitions.all(func(definition: Dictionary) -> bool: return fusion_ids.has(definition.id)), "合成产物全部集中在第二页")
	var shown_ids := {}
	for page_index: int in sticker_pages.size():
		workspace._set_sticker_page(page_index)
		var page_items: Array = table.emblem_library.get_inventory_state()
		check(page_items.size() == sticker_pages[page_index].definitions.size() and not page_items.any(EmblemStickerInventory.is_dropped), "第 %d 页所有贴纸均在格位内" % (page_index + 1))
		for item: Dictionary in page_items:
			var id := String(item.get("emblem_id", item.get("wound_id", "")))
			shown_ids[id] = page_index
	check(shown_ids.size() == table.emblem_library.get_definitions().size() - 1 and Builder.RUNE_MARKERS.keys().all(func(id: String) -> bool: return shown_ids.get(id) == 2), "保留所有已开放项目，五种元素与混沌贴纸集中在第三页")
	workspace._set_sticker_page(2)
	var fire: Callable = func(item: Dictionary) -> bool: return item.get("emblem_id") == "火贴纸"
	var stock: Array = table.emblem_library.get_inventory_state().filter(fire)
	check(stock.size() == 1 and table.emblem_library.consume_returned(stock[0]), "使用工具箱中的元素贴纸")
	await process_frame
	var restock: Array = table.emblem_library.get_inventory_state().filter(fire)
	check(restock.size() == 1 and not stock.is_empty() and restock[0].instance_id != stock[0].instance_id, "消耗后自动补充同类贴纸")
	workspace._set_sticker_page(0)
	table._open_toolbox_inspection()
	await create_timer(table.TOOLBOX_OPEN_SECONDS + 0.05).timeout
	check(workspace._sticker_page_button.is_visible_in_tree() and workspace._sticker_page_button.text == "基础纹章 1/4", "展开工具箱显示分类页名")
	workspace._sticker_next.pressed.emit()
	check(workspace._sticker_page_button.text == "合成纹章 2/4", "工具箱翻页按钮切换到合成纹章")
	await _capture_screen("sticker-pages")
	table._close_toolbox_inspection(false)
	var member: OwnedCard = variants.front()
	var drops := {"kind": &"card", "source_type": &"collection", "card_data": member.card_data, "owned_card": member}
	check(table._transfer_card(drops, &"board", table.front_row, 0), "用正式收藏到前排的摆放入口布置新小队")
	check(workspace._palette.any(func(owned: OwnedCard) -> bool: return owned != member and owned.card_data == member.card_data and owned.resolved_action_type == member.resolved_action_type), "用掉模板后补发同行动的无限副本")
	var spell := _first_template(workspace, &"side_by_side")
	check(table._on_spell_preparation_drop_requested({"owned_card": spell}, 0), "用正式法术栏入口加入法术")
	var spell_template := _first_template(workspace, &"side_by_side")
	check(spell_template != spell, "部署法术后收藏立即补发副本")
	var collection_point: Vector2 = table.collection_drop_zone.get_global_rect().get_center()
	table.collection_drop_zone.commit_card_drop(collection_point, {"kind": &"card", "source_type": &"spell_preparation", "owned_card": spell, "card_data": spell.card_data})
	check(_removed_from_editor(workspace, spell) and not table._is_spell_prepared(spell) and _first_template(workspace, &"side_by_side") == spell_template, "法术拖回收藏直接移除，原模板留在原位")
	check(table._on_spell_preparation_drop_requested({"owned_card": spell_template}, 0), "移除法术后仍可重新从模板取用")
	await _check_resources(workspace, table)
	var emblem := {"instance_id": "test_authored_fire", "emblem_id": "火贴纸", "element": 0, "temporary": false, "element_sticker": true}
	member.set_rune_sticker(0, emblem)
	var slot: BoardSlot = table.front_row.get_squads().front()
	var returned := {"kind": &"card", "source_type": &"board", "source_row": table.front_row, "source_slot": slot, "card_data": slot.get_squad_data().get_action_source()}
	table.collection_drop_zone.commit_card_drop(collection_point, returned)
	check(_removed_from_editor(workspace, member) and not table.recently_returned_owned_cards.has(member), "随从拖回收藏后移除实例，蓝签不记录回收")
	var replacement: Array = workspace._palette.filter(func(owned: OwnedCard) -> bool: return owned.card_data == member.card_data and owned.resolved_action_type == member.resolved_action_type)
	check(replacement.size() == 1 and replacement[0].rune_stickers[0].is_empty(), "同行动模板只保留一张，卡面保持空白")
	member = replacement[0]
	drops["owned_card"] = member
	check(table._transfer_card(drops, &"board", table.front_row, 0), "移除随从后仍可重新从模板取用")
	member.set_rune_sticker(0, emblem)
	member.set_rune_sticker(1, emblem.merged({"instance_id": "test_authored_chaos", "emblem_id": "混沌贴纸"}, true))
	await create_timer(0.2).timeout
	var after := Metrics.measure(editor._prepare(editor._working))
	check(after.durability > before.durability and after.spell_count == before.spell_count + 1 and editor._metrics.text != "", "增添小队和法术即时重算耐久和法术分档")
	var inspected: Dictionary = editor._prepare(editor._working)
	var authored_member: OwnedCard = inspected.formation[0].squad_data.get_action_source_instance()
	check(authored_member.rune_revealed[0] and authored_member.resolved_runes[0] == 0 and authored_member.rune_revealed[1] and not authored_member.rune_revealed[2], "指定元素和混沌显现，空槽保持未刮开")
	var undo_steps := editor._undo.size()
	editor.seed_edit.value += 1
	await create_timer(0.2).timeout
	authored_member = editor._prepare(editor._working).formation[0].squad_data.get_action_source_instance()
	check(member.rune_stickers[1].element == authored_member.resolved_runes[1] and editor._undo.size() == undo_steps, "改种子更新混沌卡面和试打，且不产生布置撤销步骤")
	var authored := editor._working.visual.duplicate(true) as Dictionary
	slot = table.front_row.get_squads().front()
	var squad_drag := {"kind": &"squad", "source_type": &"board", "source_row": table.front_row, "source_slot": slot, "squad_data": slot.get_squad_data()}
	table.collection_drop_zone.commit_card_drop(collection_point, squad_drag)
	check(_removed_from_editor(workspace, member), "整个小队拖回收藏也直接移除")
	editor._undo_table()
	check(editor._working.visual == authored, "撤销移除可恢复原小队及贴纸")
	check(editor._save_draft(), "命名阵容保存草稿")
	editor._duplicate_lineup()
	editor.name_edit.text = "掩护编队"
	editor.name_edit.text_changed.emit("掩护编队")
	check(editor._save_draft(), "同关卡保存第五套独立阵容")
	editor._export_level()
	var saved := Catalog.read_document(DRAFT)
	var exported := Catalog.read_document(EXPORT)
	var level: Array = saved.get("levels", {}).get("maze_1", [])
	check(level.size() == 5 and level[3].name == "夹击编队" and level[4].name == "掩护编队", "独立名称和阵容按同一关卡保存")
	check(exported.get("version") == 1 and exported.get("levels", {}).get("maze_1", []) == level, "导出正式可读取的版本与配置结构")
	editor._sessions.clear()
	editor._select_level(0)
	check(editor.lineup_picker.item_count == 5, "从已保存的草稿恢复五套阵容")
	editor.lineup_picker.select(3)
	editor.lineup_picker.item_selected.emit(3)
	editor._request_trial()
	var original := lab.battle_controller.enemy_states[0].get_action_source().id if not lab.battle_controller.enemy_states.is_empty() else &""
	check(not editor.visible and original != &"" and lab.battle_controller._enemy_prepared_spell_instances.size() == 1 and lab.battle_controller.enemy_resource_states.size() == 2, "试打将正式随从、法术和手摆资源交给同一战斗控制器")
	lab._start_battle()
	check(not lab.battle_controller.enemy_states.is_empty() and lab.battle_controller.enemy_states[0].get_action_source().id == original, "重置同种子复用所选命名阵容")
	editor.show()
	await _capture_screen("desk")
	lab.free()
	await process_frame
	return exported.get("levels", {})


func _first_template(workspace: Control, id: StringName) -> OwnedCard:
	for owned: OwnedCard in workspace._palette:
		if owned.card_data.id == id: return owned
	return null


func _removed_from_editor(workspace: Control, owned: OwnedCard) -> bool:
	return workspace.table.owned_card_collection.get_by_instance_id(owned.instance_id) == null and not workspace._filtered.has(owned)


func _check_resources(workspace: Control, table: Control) -> void:
	var resource: OwnedCard = null
	for owned: OwnedCard in workspace._palette:
		if owned.card_data.card_type == CardData.CardType.RESOURCE and owned.card_data.rarity == CardData.Rarity.II:
			resource = owned
			break
	var cells: Array[Vector2i] = ResourceHexLayout.valid_cells().filter(func(cell: Vector2i) -> bool: return workspace._cell_available(cell))
	var start := Vector2i.ZERO
	var next := Vector2i.ZERO
	for cell: Vector2i in cells:
		var neighbors := ResourceHexLayout.neighbors(cell)
		var valid := neighbors.filter(func(neighbor: Vector2i) -> bool: return neighbor in cells)
		if not valid.is_empty():
			start = cell
			next = valid.front()
			break
	var tray: Control = table.player_resource_tray
	var drop_point: Vector2 = tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(start))
	table._on_search_text_changed(resource.card_data.display_name)
	await process_frame
	var source: Control = table._find_collection_slot_for_owned_card(resource).get_child(0)
	var start_point := source.get_global_rect().get_center()
	_pointer_motion(start_point, start_point, false)
	_pointer_button(start_point, true)
	_pointer_motion(start_point, start_point + Vector2(20, 0), true)
	check(root.gui_is_dragging(), "在可视化桌面使用原生鼠标拖起资源卡")
	_pointer_motion(start_point + Vector2(20, 0), drop_point, true)
	await process_frame
	var drop_ready: Dictionary = tray.resolve_drop(drop_point, root.gui_get_drag_data()) if root.gui_is_dragging() else {}
	var hovered := root.gui_get_hovered_control()
	_pointer_button(drop_point, false)
	check(workspace.shape_is_open() and workspace._shape_confirm.disabled, "首次放下资源进入拼图编辑，格数不足时不可确认（%s，%s）" % [drop_ready, hovered])
	table.clear_search()
	if not workspace.shape_is_open(): return
	await _capture_screen("shape")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(next))
	click.pressed = true
	root.push_input(click)
	click.pressed = false
	root.push_input(click)
	check(not workspace._shape_confirm.disabled, "实际点击选够相连六边格后允许确认")
	workspace.confirm_shape()
	check(table.resource_board_state.deployments.player.has(String(resource.instance_id)) and resource.resource_shape.size() == 2, "保存资源形状和格位")
	if not table.resource_board_state.deployments.player.has(String(resource.instance_id)):
		workspace.cancel_shape()
		return
	var placed: Dictionary = table.resource_board_state.deployments.player[String(resource.instance_id)].duplicate(true)
	check(workspace._resource_context_click(start) and workspace.shape_is_open(), "右键手摆资源重新编辑形状")
	workspace.cancel_shape()
	check(table.resource_board_state.deployments.player[String(resource.instance_id)] == placed, "取消形状编辑保留原拼图")
	var resource_template := _first_template(workspace, resource.card_data.id)
	var resource_drag: Dictionary = tray._build_piece_drag_data(resource, start, tray.LAYOUT_ORIGIN + ResourceHexLayout.center(start))
	table.collection_drop_zone.commit_card_drop(table.collection_drop_zone.get_global_rect().get_center(), resource_drag)
	check(_removed_from_editor(workspace, resource) and workspace._cell_available(start) and _first_template(workspace, resource.card_data.id) == resource_template, "资源拖回收藏后清空原格，原模板留在原位")
	check(workspace.begin_resource_drop(resource_template, start) and workspace.select_shape_cell(next), "重新取用资源模板时可重新选择拼图")
	workspace.confirm_shape()
	var blocker := _first_template(workspace, workspace.BLOCK_ID)
	for cell: Vector2i in cells:
		if workspace._cell_available(cell): workspace.begin_resource_drop(blocker, cell)
		if table.resource_board_state.disabled_by_side.player.size() == 4: break
	check(table.resource_board_state.disabled_by_side.player.size() == 4, "资源占位卡可标记超过自动禁用格上限的手摆格")


func _capture_screen(page: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-lineup-editor-%s.png" % page)


func _pointer_motion(previous: Vector2, current: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = current
	event.global_position = current
	event.relative = current - previous
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)


func _pointer_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func _real_encounter(levels: Dictionary) -> void:
	var main: Control = MainScene.instantiate()
	main.short_maze_enabled = true
	main.run_save_path = SAVE
	root.add_child(main)
	await process_frame
	var maze: ShortMazeController = main.maze_controller
	check(maze != null, "正式迷宫控制器已初始化")
	if maze == null:
		main.free()
		return
	maze.new_run(47007)
	maze.choose_talent("sentry_guard")
	maze._named_lineup_levels = levels
	maze.run.round_index = 3
	maze.run.step = ShortMazeRunState.Step.CHOOSING
	maze.run.paths.clear()
	var state_before: int = maze.run.rng.state
	maze._generate_paths()
	check(maze.run.paths.size() == 3 and maze.run.paths.all(func(path: Dictionary) -> bool: return path.has("lineup_id") and path.has("battle_seed")), "正式跑图从五套抽出三个已锁定的不同遭遇")
	if maze.run.paths.size() != 3 or not maze.run.paths.front().has("lineup_id"):
		main.free()
		return
	var picked: Array[Dictionary] = maze.run.paths.duplicate(true)
	var authored: Array[Dictionary] = picked.filter(func(path: Dictionary) -> bool: return path.has("visual"))
	check(not authored.is_empty(), "正式抽选池包含可视化发布的阵容")
	if authored.is_empty():
		main.free()
		return
	var chosen: Dictionary = authored.front()
	var automatic_board := ResourceBoardState.new()
	var automatic := OwnedCard.new()
	automatic.initialize(load("res://resources/cards/stone_of_greed.tres") as CardData, &"automatic_overlap", 0)
	var blocked: Array = chosen.visual.blocked
	if not blocked.is_empty():
		var overlap := Vector2i(blocked[0][0], blocked[0][1])
		check(automatic_board.deploy_level_resource("enemy", automatic, overlap), "自动资源先占据待禁用的格子")
		var built_board := Builder.place_level_resources(chosen, main._build_card_definition_registry(), automatic_board)
		var automatic_tile: Dictionary = automatic_board.deployments.enemy.get("automatic_overlap", {})
		check(built_board and not automatic_tile.is_empty() and automatic_tile.anchor != [overlap.x, overlap.y] and overlap in automatic_board.disabled_by_side.enemy, "手摆占位优先，自动资源重新落到可用格")
	maze.run.paths.clear()
	maze.run.rng.state = state_before
	maze._generate_paths()
	check(maze.run.paths == picked, "同随机状态生成相同阵容和战斗种子")
	check(main.save_run_to_path(SAVE) == OK, "三条未选择的命名遭遇可以先保存")
	maze._named_lineup_levels.clear()
	check(main.load_run_from_path(SAVE) and maze.run.paths.size() == 3 and maze.run.paths.front().lineup_id == picked.front().lineup_id, "调整正式配置后仍保留旧档已生成的备选阵容")
	check(maze.select_path(String(chosen.path_id)), "用正式地图入口选择已锁定的可视化阵容")
	var original: Dictionary = maze.run.selected_path
	check(original.has("encounter_state") and original.lineup_name == chosen.lineup_name, "正式战前保存阵容身份、名字与已生成实例")
	var resource_state: Dictionary = main.resource_board_state.capture_state()
	var placed: Dictionary = resource_state.deployments.enemy.get("authored_resource_0001", {})
	var shapes: Array = chosen.visual.resources
	var shape: Dictionary = shapes[1] if shapes.size() > 1 else {}
	var exact_layout: bool = JSON.parse_string(JSON.stringify(placed.get("shape"))) == shape.get("shape") and JSON.parse_string(JSON.stringify(placed.get("anchor"))) == shape.get("anchor")
	check(exact_layout and resource_state.disabled_by_side.enemy.size() >= 4, "正式遭遇保留手摆形状、格位和四个占位格（手摆 %s，正式 %s，禁用格 %d）" % [shape, placed, resource_state.disabled_by_side.enemy.size()])
	var loaded: bool = main.load_run_from_path(SAVE)
	var recovered := maze.run.selected_path
	var same_encounter: bool = JSON.parse_string(JSON.stringify(recovered.get("encounter_state"))) == JSON.parse_string(JSON.stringify(original.encounter_state))
	check(loaded and recovered.get("lineup_id") == original.lineup_id and recovered.get("battle_seed") == original.battle_seed and same_encounter, "重读已选择遭遇复用实例快照和种子（读档 %s，实例一致 %s）" % [loaded, same_encounter])
	check(main.resource_board_state.capture_state() == resource_state, "读档完整恢复手摆资源、禁用格和自动资源")
	var invalid := picked.front().duplicate(true) as Dictionary
	invalid["lineup_day"] = 2
	check(not maze._valid_saved_named_battle(invalid, 1, 3, false), "拒绝归属日期不一致的命名阵容快照")
	main.free()


func check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
