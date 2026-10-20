extends "res://tests/board_ui_fixes_20261019_test.gd"

const TOKEN_SAVE := "/private/tmp/project-card-token-ui-save.json"


func capture_ui(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = shell.internal_viewport.get_texture().get_image()
	image.save_png("/private/tmp/project-card-token-ui-%s.png" % label)
	return image


func verify_filters_and_search() -> void:
	var book: Control = main.get_node("%BookPanel")
	check(main.rarity_buttons.get_parent() == book and main.rarity_buttons.z_index < main.get_node("%PageStackArt").z_index, "稀有度标签在纸叠下方")
	var before := await capture_ui("collection")
	var stack: TextureRect = main.get_node("%PageStackArt")
	var source: Image = stack.texture.get_image()
	var errors := 0
	for x: int in range(400, 510):
		var point := Vector2i(x, 2)
		if not before.get_pixelv(Vector2i(stack.global_position) + point).is_equal_approx(source.get_pixelv(point)):
			errors += 1
	check(errors == 0, "稀有度下端与书页重叠处真实像素由书页遮挡")
	var bookmark: Control = main.recent_bookmark_button
	check(bookmark.global_position.y == 374, "书签常规状态下移20像素到世界Y742")
	await _click(bookmark)
	await create_timer(0.3).timeout
	check(main.collection_bookmark_active and bookmark.global_position.y == 354, "选中书签停在此前常规位置世界Y722")
	await _click(bookmark)
	await create_timer(0.3).timeout
	check(not main.collection_bookmark_active and bookmark.global_position.y == 374, "书签恢复新常规位置")
	var edit: LineEdit = main.search_edit
	check(edit.scale == Vector2.ONE and edit.size == Vector2(50, 14), "搜索输入区按原生尺寸绘制和命中，不缩放")
	var font := edit.get_theme_font("font") as FontFile
	check(font != null and font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and font.get_height(8) <= 14, "点阵字体完整放入14像素框高且无抗锯齿")
	await _click(edit)
	for character: String in "法术":
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = character.unicode_at(0)
		root.push_input(event, true)
		await process_frame
	check(edit.text == "法术" and main.search_query == "法术", "真实中文键盘输入仍执行收藏搜索")
	edit.release_focus()
	await capture_ui("search")
	await _click(main.clear_search_button)
	check(edit.text.is_empty() and main.search_query.is_empty(), "真实清空按钮命中正常")
	await _click(main.rarity_buttons.get_child(0))
	check(main.active_rarity_filters.has(0), "书页下方的稀有度标签露出部分仍可点击")
	await _click(main.rarity_buttons.get_child(0))


func pick_native(control: Control, grab: Vector2) -> void:
	await move_pointer(control.global_position + grab)
	await press_pointer(true)
	await move_pointer(pointer + Vector2(24, 0), true)
	await create_timer(0.13).timeout
	check(shell.internal_viewport.gui_is_dragging(), "真实原生拖动成功拿起")


func verify_spell_token() -> void:
	var spell: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	await process_frame
	var card: Control = main._find_collection_slot_for_owned_card(spell).get_child(0)
	await pick_native(card, Vector2(1, 30))
	var data: Dictionary = shell.internal_viewport.gui_get_drag_data()
	var preview: CardDragPreview = data.drag_visual
	var tray: Control = main.spell_preparation_tray
	var center := tray.global_position + Vector2(17, 100)
	var offset := preview.get_spell_preparation_global_center() - preview.global_position
	await move_pointer(center - offset, true)
	await create_timer(0.1).timeout
	check(pointer.x < tray.global_position.x and tray._preview_instance_id == spell.instance_id, "鼠标在法术板左侧之外，令牌中心进入后仍显示合法预览")
	check(preview.get_spell_preparation_visual().size == Vector2(42, 42) and preview.get_spell_preparation_visual().scale == Vector2.ONE, "手持令牌始终为原生42像素")
	await press_pointer(false)
	check(main.prepared_spell_instance_ids.has(spell.instance_id), "鼠标在板外也能按令牌中心实际放置")
	var transition: Control = tray._drop_transitions.get(StringName("visual_%s" % spell.instance_id))
	check(is_instance_valid(transition) and transition is TextureRect and transition.size == Vector2(42, 42), "落位使用令牌本身而非整卡快照")
	await create_timer(0.06).timeout
	check(is_instance_valid(transition) and transition.scale.is_equal_approx(Vector2.ONE), "落位中途保持尺寸，不二次缩小")
	await capture_ui("spell_drop")
	await create_timer(0.2).timeout
	var icon: Control = tray._icons_by_instance_id.get(spell.instance_id)
	check(is_instance_valid(icon) and icon.modulate.a == 1, "落位后恢复实际法术图标")
	# 反向边界：鼠标进板但令牌中心在板外，不得部署第二张。
	var second: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/damage_fireball.tres"))
	main._sync_legacy_collection_cards()
	main._build_collection_cards()
	await process_frame
	card = main._find_collection_slot_for_owned_card(second).get_child(0)
	await pick_native(card, Vector2(95, 130))
	await move_pointer(tray.global_position + Vector2(17, 110), true)
	await create_timer(0.08).timeout
	await press_pointer(false)
	check(not main.prepared_spell_instance_ids.has(second.instance_id), "鼠标在板内但令牌中心在外时拒绝放置")
	icon = tray._icons_by_instance_id.get(spell.instance_id)
	await pick_native(icon, Vector2(1, 1))
	data = shell.internal_viewport.gui_get_drag_data()
	preview = data.drag_visual
	offset = preview.get_spell_preparation_global_center() - preview.global_position
	var collection_rect: Rect2 = main.collection_drop_zone.get_global_rect()
	center = collection_rect.position + Vector2(5, 5)
	await move_pointer(center - offset, true)
	await create_timer(0.1).timeout
	check(not collection_rect.has_point(pointer), "回收时鼠标仍在收藏区外，以令牌进入区域判定")
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(not main.prepared_spell_instance_ids.has(spell.instance_id), "原生拖动按令牌中心真实回收收藏")
	# 点击携带使用同一落点，不经原生GUI鼠标接收节点。
	card = main._find_collection_slot_for_owned_card(spell).get_child(0)
	await _click(card)
	check(not main._click_carry_data.is_empty(), "真实点击拿起收藏法术")
	preview = main._click_carry_data.drag_visual
	center = tray.global_position + Vector2(80, 120)
	offset = preview.get_spell_preparation_global_center() - preview.global_position
	await move_pointer(center - offset)
	await press_pointer(true)
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(main.prepared_spell_instance_ids.has(spell.instance_id), "点击携带也按令牌中心放置")
	card = main._find_collection_slot_for_owned_card(second).get_child(0)
	await _click(card)
	preview = main._click_carry_data.drag_visual
	offset = preview.get_spell_preparation_global_center() - preview.global_position
	await move_pointer(tray.global_position + Vector2(41, 180) - offset)
	await press_pointer(true)
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(main.prepared_spell_instance_ids.find(second.instance_id) > main.prepared_spell_instance_ids.find(spell.instance_id), "第二枚令牌实际追加到同列队尾")
	icon = tray._icons_by_instance_id.get(second.instance_id)
	await pick_native(icon, Vector2(1, 1))
	data = shell.internal_viewport.gui_get_drag_data()
	preview = data.drag_visual
	offset = preview.get_spell_preparation_global_center() - preview.global_position
	await move_pointer(tray.global_position + Vector2(41, 70) - offset, true)
	await create_timer(0.1).timeout
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(main.prepared_spell_instance_ids.find(second.instance_id) < main.prepared_spell_instance_ids.find(spell.instance_id), "偏抓令牌按图像中心真实重排同列顺序")


func verify_indicators() -> void:
	var controller: CelestialIndicatorController = main.celestial_indicators
	for kind: int in CelestialIndicator.Kind.values():
		var item := CelestialIndicator.new()
		item.kind = kind as CelestialIndicator.Kind
		item.instance_id = StringName("ui_indicator_%d" % kind)
		controller.items.append(item)
	controller._sync_tray()
	await process_frame
	var moon: CelestialIndicator = controller.items[0]
	var sun: CelestialIndicator = controller.items[2]
	var moon_view: Control = controller._tray_views[moon.instance_id]
	var sun_view: Control = controller._tray_views[sun.instance_id]
	await pick_native(moon_view, Vector2(1, moon_view.size.y * 0.5))
	var preview: CelestialDragPreview = controller._preview
	var offset := preview.get_visual_center() - preview.global_position
	await move_pointer(sun_view.get_global_rect().get_center() - offset, true)
	await press_pointer(false)
	await create_timer(0.2).timeout
	moon_view = controller._tray_views[moon.instance_id]
	check(not Rect2(moon_view.position, moon_view.size).grow(1).intersects(Rect2(sun_view.position, sun_view.size)), "指示物丢到另一枚上方时自动避让，不能重叠")
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var slot: BoardSlot = main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	await process_frame
	var card: CardView = slot.get_primary_card_view()
	await pick_native(moon_view, Vector2(1, moon_view.size.y * 0.5))
	preview = controller._preview
	offset = preview.get_visual_center() - preview.global_position
	var intended := card.global_position + Vector2(3, 50)
	await move_pointer(intended - offset, true)
	await create_timer(0.1).timeout
	check(pointer.x < card.global_position.x and not controller._resolve_drop_target(pointer).is_empty(), "鼠标在卡外但指示物中心进入卡内时找到附着目标")
	await press_pointer(false)
	await create_timer(0.2).timeout
	check(slot.get_squad_data().has_indicator(moon.kind), "按指示物中心真实附着到小队")
	# 点击携带也按同一图像中心，回收时与太阳和哨位共用避让。
	var view: Control = slot.get_celestial_indicator(moon.instance_id)
	await _click(view)
	await create_timer(0.13).timeout
	check(not controller._data.is_empty(), "实际点击拿起同一枚指示物")
	preview = controller._preview
	offset = preview.get_visual_center() - preview.global_position
	await move_pointer(sun_view.get_global_rect().get_center() - offset)
	await press_pointer(true)
	await press_pointer(false)
	await create_timer(0.2).timeout
	moon_view = controller._tray_views[moon.instance_id]
	check(not slot.get_squad_data().has_indicator(moon.kind) and not Rect2(moon_view.position, moon_view.size).intersects(Rect2(sun_view.position, sun_view.size)), "点击回收也避开库存已有图标")
	var sentry: Control
	for child: Node in maze._sentry_bar.get_children():
		if child is EquipmentIndicator:
			sentry = child
			break
	check(is_instance_valid(sentry), "真实天赋提供的哨位在共用库存内")
	if is_instance_valid(sentry):
		var id: String = sentry.sentry_data.instance_id
		await pick_native(sentry, Vector2(1, 20))
		preview = controller._preview
		offset = preview.get_visual_center() - preview.global_position
		await move_pointer(sun_view.get_global_rect().get_center() - offset, true)
		await press_pointer(false)
		await create_timer(0.2).timeout
		var encoded: Array = []
		for item: Dictionary in maze.stock:
			if item.instance_id == id: encoded = item.get("stock_position", [])
		check(encoded.size() == 2, "哨位按拖动图像中心保存库存新位置")
		if encoded.size() == 2:
			var bounds := Rect2(Vector2(encoded[0], encoded[1]), Vector2(44, 49))
			var overlap := false
			for item_view: Control in controller._tray_views.values():
				overlap = overlap or bounds.intersects(Rect2(item_view.position, item_view.size))
			check(not overlap, "哨位也避让日月星，不挤占已有指示物")
	await capture_ui("indicators")
	var inventory_before := controller.capture_state()
	var stock_before: Array = maze.stock.duplicate(true)
	check(main.save_run_to_path(TOKEN_SAVE) == OK and main.load_run_from_path(TOKEN_SAVE), "避让后的实际位置和准备法术正常存读档")
	check(controller.capture_state() == inventory_before and maze.stock == stock_before, "读档保留避让后的日月星和哨位精确坐标")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = TOKEN_SAVE
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.4).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	await verify_filters_and_search()
	await verify_spell_token()
	await verify_resource_drag()
	await verify_indicators()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(TOKEN_SAVE)
	print("令牌判定与收藏UI：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
