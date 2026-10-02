extends SceneTree

const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const DisplayScript = preload("res://scripts/ui/game_display.gd")
const SHOP_CARD = preload("res://scenes/ui/ShopCardView.tscn")
const ShopCard = preload("res://scripts/ui/shop_card_view.gd")
const CARD = preload("res://scenes/ui/CardView.tscn")

var failures := 0
var shell: Control
var main: Control


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	# 同一帧提交移动与按键，避免原生窗口的真实鼠标位置在测试按下前覆盖悬停目标。
	var motion := InputEventMouseMotion.new()
	motion.position = shell.render_container.get_global_transform_with_canvas() * point
	motion.global_position = motion.position
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = shell.render_container.get_global_transform_with_canvas() * point
		event.global_position = event.position
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * point
	event.global_position = event.position
	root.push_input(event, true)
	await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-shop-presentation-%s.png" % name)


func _tile(index: int) -> Control:
	return main.ordinary_shop_offer_list.find_child("ShopOffer_%d" % index, true, false) as Control


func _run() -> void:
	create_timer(75.0).timeout.connect(func(): push_error("展示验收超时"); quit(1))
	shell = DISPLAY.instantiate()
	root.add_child(shell)
	var is_2k := OS.get_cmdline_user_args().has("2k")
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if is_2k else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-shop-presentation-state.json"
	var backdrop := main.ordinary_shop_layer.get_node("ShopMotionRoot/ShopTableBackdrop") as Control
	check(not backdrop.is_visible_in_tree() and not main.ordinary_shop_open, "启动准备阶段不显示商店背景")
	await capture("normal-2k" if is_2k else "normal-720p")
	await process_frame
	check(shell.render_container.scale.is_equal_approx(Vector2(2, 2) if is_2k else Vector2.ONE), "窗口稳定后按实际画布缩放发送输入")
	main.run_reward_state.gold = 100
	main.ordinary_shop_service.rng.seed = 12
	await click(main.ordinary_shop_entry_button.get_global_rect().get_center())
	await create_timer(0.4).timeout
	check(backdrop.is_visible_in_tree(), "进入商店才显示背景")
	if not main.ordinary_shop_open:
		shell.queue_free()
		quit(1)
		return
	check(not (main.get_node("%EnemyBoardSection") as Control).visible, "商店收起敌方中央战场及高层牌型标签")
	check(not main.ordinary_shop_panel is CanvasLayer and main.ordinary_shop_layer is Control, "商店复用主画布，不跨过资源详情与检视层")
	var definitions := main._get_shop_card_definitions() as Array[CardData]
	var minion: CardData
	for card: CardData in definitions:
		if card.card_type == CardData.CardType.MINION:
			minion = card
			break
	var fixture := {"kind": "single_card", "card_id": String(minion.id), "hidden": false, "hint": "", "price": 4, "instance_seed": "13", "offer_id": "presentation_fixture"}
	main.ordinary_shop_service.offers.clear()
	main.ordinary_shop_service.offers.append(fixture)
	main._refresh_ordinary_shop_panel()
	await create_timer(0.2).timeout
	var tile := _tile(0)
	check(tile != null and tile.find_children("*", "Button", true, false).is_empty(), "商品没有独立购买或查看按钮")
	await move(tile.get_global_rect().get_center())
	await create_timer(0.2).timeout
	check(tile._visual.position.y < -4.0, "真实悬停使商品抬起")
	await click(tile.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	check(is_instance_valid(main._inspection_overlay) and main._inspection_read_only and not main._inspection_has_library_toolbox, "右键明单进入位于商店上方的只读检视，不重挂工具箱")
	check(main._inspection_overlay.get_canvas() == main.ordinary_shop_layer.get_canvas() and main._inspection_overlay.z_index > main.ordinary_shop_layer.z_index, "卡牌检视与商店共享画布并正确排序")
	await capture("inspect-2k" if is_2k else "inspect-720p")
	await click(Vector2(50, 300))
	await create_timer(0.35).timeout
	check(not is_instance_valid(main._inspection_overlay) and main.ordinary_shop_open, "点击暗幕关闭商店卡牌检视并保留商店")
	fixture.hidden = true
	fixture.hint = "race"
	fixture.hint_value = minion.get_race_name()
	fixture.price = 8
	main._refresh_ordinary_shop_panel()
	await create_timer(0.15).timeout
	await click(_tile(0).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(0.35).timeout
	check(is_instance_valid(main._inspection_card_view) and main._inspection_card_view.card_data.display_name == "？" and main._inspection_card_view.card_data.art_texture == null and main._inspection_card_view.card_data.effect_text.is_empty(), "暗单右键检视只持有脱敏定义，不显示真实插画、名称或效果")
	await capture("hidden-inspect-2k" if is_2k else "hidden-inspect-720p")
	await key(KEY_ESCAPE)
	await create_timer(0.35).timeout
	check(not is_instance_valid(main._inspection_overlay), "Esc可以关闭暗单检视")
	await key(KEY_F2)
	check(main._developer_console.visible, "商店中F2控制台可打开")
	await key(KEY_F2)
	await key(KEY_ESCAPE)
	check(main._escape_pause_menu.is_menu_open(), "商店中Esc暂停菜单可打开")
	await capture("pause-2k" if is_2k else "pause-720p")
	await key(KEY_ESCAPE)
	main._generate_ordinary_shop(false)
	main._refresh_ordinary_shop_panel()
	await create_timer(0.15).timeout
	var tray := main.player_resource_tray as ResourcePreparationTray
	if tray._piece_by_cell.is_empty():
		var resource := main.owned_card_collection.create_card(main._get_resource_definitions()[0]) as OwnedCard
		for cell: Vector2i in ResourceHexLayout.valid_cells():
			if main.resource_board_state.try_deploy("player", String(resource.instance_id), resource.resource_shape, cell, Vector2i.ZERO):
				break
		main._refresh_resource_preparation_trays()
	check(not tray._piece_by_cell.is_empty(), "资源详情验收有真实部署目标")
	if not tray._piece_by_cell.is_empty():
		var resource_cell: Vector2i = tray._piece_by_cell.keys()[0]
		await move(tray.get_global_transform_with_canvas() * (tray.LAYOUT_ORIGIN + ResourceHexLayout.center(resource_cell)))
		check(is_instance_valid(tray._hover_card) and tray._hover_card.get_parent().z_index + tray._hover_card.z_index > main.ordinary_shop_layer.z_index, "真实资源悬停详情位于商店之上")
		await capture("resource-2k" if is_2k else "resource-720p")
	await move(Vector2(600, 300))
	await capture("table-2k" if is_2k else "table-720p")
	await click(main.ordinary_shop_panel.find_child("OrdinaryShopCloseButton", true, false).get_global_rect().get_center())
	await create_timer(0.35).timeout
	check(not backdrop.is_visible_in_tree(), "离店后背景消失并恢复原准备视图")
	check((main.get_node("%EnemyBoardSection") as Control).visible, "离店恢复敌方中央战场及牌型标签")
	await _check_public_cards()
	await _check_drag_and_alpha(minion)
	DirAccess.remove_absolute(main.run_save_path)
	print("D2-7 shop presentation failures: ", failures)
	shell.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _check_public_cards() -> void:
	for kind: int in CardData.CardType.size():
		var source := CardData.new()
		source.id = &"secret_identity"
		source.display_name = "秘密名称"
		source.effect_text = "秘密效果"
		source.card_type = kind as CardData.CardType
		source.rarity = CardData.Rarity.IV
		source.spell_trigger_kind = CardData.SpellTriggerKind.PREPARED
		source.spell_type = CardData.SpellType.DAMAGE
		source.equipment_type = CardData.EquipmentType.ARMOR
		source.resource_type = CardData.ResourceType.RELIC
		for hint: String in ["rarity", "race", "action_type", "spell_trigger_kind", "spell_type", "equipment_type", "resource_type"]:
			var offer := {"hidden": true, "hint": hint, "resolved_action_type": CardData.ActionType.DEFENSE}
			var safe := true
			var fixed_or_cycling := true
			for frame: int in 9:
				var card := ShopCard.public_definition(source, offer, frame)
				safe = safe and card.id.is_empty() and card.display_name == "？" and card.effect_text.is_empty() and card.runes.is_empty()
				fixed_or_cycling = fixed_or_cycling and (card.rarity == source.rarity if hint == "rarity" else int(card.rarity) == frame % 5)
				fixed_or_cycling = fixed_or_cycling and (card.race_type == source.race_type if hint == "race" else int(card.race_type) == frame % CardData.RaceType.size())
				fixed_or_cycling = fixed_or_cycling and (card.action_type == CardData.ActionType.DEFENSE if hint == "action_type" else int(card.action_type) == frame % CardData.ActionType.size())
				fixed_or_cycling = fixed_or_cycling and (card.spell_trigger_kind == source.spell_trigger_kind if hint == "spell_trigger_kind" else int(card.spell_trigger_kind) == 1 + frame % 3)
				fixed_or_cycling = fixed_or_cycling and (card.spell_type == source.spell_type if hint == "spell_type" else int(card.spell_type) == frame % CardData.SpellType.size())
				fixed_or_cycling = fixed_or_cycling and (card.equipment_type == source.equipment_type if hint == "equipment_type" else int(card.equipment_type) == frame % CardData.EquipmentType.size())
				fixed_or_cycling = fixed_or_cycling and (card.resource_type == source.resource_type if hint == "resource_type" else int(card.resource_type) == frame % CardData.ResourceType.size())
			check(safe and fixed_or_cycling, "暗单多帧脱敏、固定提示和公开轮播：%d/%s" % [kind, hint])
		var view := SHOP_CARD.instantiate() as ShopCardView
		view.configure_hidden(ShopCard.public_definition(source, {"hint": "rarity"}), {"hint": "rarity"})
		root.add_child(view)
		check(view.art_label.visible and view.art_label.text == "？" and not view.health_label.visible and not view.value_label.visible and not view.cooldown_label.visible and not view.armor_label.visible, "四类暗单保留问号和组合图标，隐藏所有数值：%d" % kind)
		var valid_textures := true
		for frame: int in 9:
			view.configure_hidden(ShopCard.public_definition(source, {}, frame), {})
			valid_textures = valid_textures and view.card_frame.texture != null and view.action_icon.texture != null and view.race_icon.texture != null
		check(valid_textures, "全部轮播组合可加载品级、角标与种类素材：%d" % kind)
		view.configure_hidden(ShopCard.public_definition(source, {"hint": "rarity"}), {"hint": "rarity"})
		var before := view.card_data
		await create_timer(ShopCard.CAROUSEL_HOLD + ShopCard.CAROUSEL_FADE + 0.05).timeout
		check(view.card_data != before and view.card_data.rarity == CardData.Rarity.IV, "真实计时器轮播未知字段且固定提示稀有度：%d" % kind)
		view.queue_free()
		await process_frame
	if DisplayServer.get_name() != "headless":
		var gallery := SubViewport.new()
		gallery.size = Vector2i(480, 156)
		gallery.transparent_bg = true
		gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(gallery)
		for kind: int in CardData.CardType.size():
			var definition := CardData.new()
			definition.card_type = kind as CardData.CardType
			var card := SHOP_CARD.instantiate() as ShopCardView
			card.configure_hidden(ShopCard.public_definition(definition, {}, 2), {})
			card.position = Vector2(8 + kind * 118, 8)
			gallery.add_child(card)
		await RenderingServer.frame_post_draw
		gallery.get_texture().get_image().save_png("/private/tmp/project-card-hidden-shop-gallery.png")
		gallery.queue_free()
		await process_frame


func _check_drag_and_alpha(definition: CardData) -> void:
	var owned := OwnedCard.new()
	owned.initialize(definition, &"alpha_fixture", 1)
	var other := OwnedCard.new()
	other.initialize(definition, &"alpha_other", 2)
	other.resolved_runes.assign([CardData.ElementType.LIGHT, CardData.ElementType.WATER, CardData.ElementType.FIRE])
	owned.resolved_runes.assign([CardData.ElementType.DARK, CardData.ElementType.WOOD, CardData.ElementType.WATER])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(300, 160)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var views: Array[CardView] = []
	for index: int in 2:
		var view := CARD.instantiate() as CardView
		view.set_card_data(definition)
		view.set_owned_card(owned if index == 0 else other)
		view.position = Vector2(10 + index * 140, 8)
		view.modulate.a = 0.35
		view.showing_effect = true
		viewport.add_child(view)
		views.append(view)
	var data := views[0]._build_drag_data(Vector2(40, 40))
	var preview := CardView.create_drag_visual(data)
	root.add_child(preview)
	check(preview.get_source_card_view().get_owned_card() == owned, "单卡携带预览绑定真实OwnedCard，而不是定义快照")
	preview.queue_free()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var left := image.get_region(Rect2i(18, 116, 83, 23))
		var right := image.get_region(Rect2i(158, 116, 83, 23))
		check(left.get_data() == right.get_data(), "真实渲染：不同隐藏元素在虚影与描述淡出状态下画面完全相同")
		image.save_png("/private/tmp/project-card-hidden-alpha-proof.png")
		var scraped: Array[Vector2i] = []
		for y: int in range(7, 16):
			for x: int in range(7, 16):
				scraped.append(Vector2i(x, y))
		owned.record_rune_scrape_pixels(0, scraped)
		views[0].refresh_rune_scrape_cover(0)
		await RenderingServer.frame_post_draw
		var partial := viewport.get_texture().get_image().get_region(Rect2i(18, 116, 23, 23))
		check(partial.get_data() != left.get_region(Rect2i(0, 0, 23, 23)).get_data() and not owned.rune_revealed[0], "实际刮擦更新共享遮罩后局部元素可见，未达到阈值仍保持未揭晓")
		owned.rune_revealed[0] = true
		views[0].set_owned_card(owned)
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().get_region(Rect2i(18, 116, 23, 23)).get_data() != partial.get_data(), "揭晓后移除覆盖并完整绘制实例元素")
	else:
		print("SKIP: headless不验证像素画面；真实窗口测试另行执行")
	viewport.queue_free()
	await process_frame
