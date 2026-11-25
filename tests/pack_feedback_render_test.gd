extends "res://tests/d3_4_ui_test.gd"

## 真实GPU核对单次左右摇摆、延迟银线往返扫光及事件卡背。
const OUTPUT := "/private/tmp/project-card-pack-feedback-render"
const Effects = preload("res://scripts/ui/pack_opening_effect_settings.gd")

func texture_shot(surface: InspectionCardSurface) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return surface.viewport.get_texture().get_image()

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	Effects.load_saved(OUTPUT.path_join("effects.cfg"))
	Effects.reset_defaults()
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = OUTPUT
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await frames()
	check(await shell.start_slot(0) and shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "真实新档打开教程")
	var main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if maze._initial_pack_drop.is_running(): await maze._initial_pack_drop.finished
	var pack: TextureButton = maze._initial_pack_button
	var gamepad := InputEventJoypadButton.new()
	gamepad.button_index = JOY_BUTTON_DPAD_RIGHT
	gamepad.pressed = true
	root.push_input(gamepad, true)
	await create_timer(0.2).timeout
	var glow := pack.get_node_or_null("InitialPackGamepadFocus") as ColorRect
	check(is_instance_valid(glow) and glow.is_visible_in_tree(), "手柄选中开场卡包，柔光挂在包装下")
	var origin := pack.position
	maze._initial_pack_idle_seconds = 0.0
	maze._nudge_initial_pack()
	var directions: Array[int] = []
	var glow_follows_pack := true
	var shadow_visible := false
	var shadow_widest := 0.0
	var shadow_center := Vector2.INF
	var shadow_drift := 0.0
	var captured_shadow := false
	while maze._initial_pack_drop.is_running():
		var shadow: Panel = maze._initial_pack_shadow
		if shadow.visible and shadow.modulate.a > 0.05:
			shadow_visible = true
			shadow_widest = maxf(shadow_widest, shadow.size.x)
			var center := shadow.position + shadow.size * 0.5
			if not shadow_center.is_finite(): shadow_center = center
			shadow_drift = maxf(shadow_drift, center.distance_to(shadow_center))
			if not captured_shadow and shadow.modulate.a > 0.17:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT.path_join("pack_jump_shadow.png"))
				captured_shadow = true
		var angle: float = maze._initial_pack_button.rotation_degrees
		if absf(angle) > 0.1:
			var direction := int(signf(angle))
			if directions.is_empty() or directions.back() != direction: directions.append(direction)
			if glow != null:
				var pack_transform := pack.get_global_transform_with_canvas()
				var glow_transform := glow.get_global_transform_with_canvas()
				var glow_center := glow_transform * (glow.size * 0.5)
				glow_follows_pack = glow_follows_pack and glow_transform.x.is_equal_approx(pack_transform.x) \
					and glow_transform.y.is_equal_approx(pack_transform.y) and glow_center.is_equal_approx(pack_transform * (pack.size * 0.5))
		await process_frame
	check(directions == [-1, 1] and maze._initial_pack_button.position.is_equal_approx(origin) and is_zero_approx(maze._initial_pack_button.rotation), "每次提醒只向左、向右各摆一次，并回到原位")
	check(glow != null and glow_follows_pack and not directions.is_empty(), "左右两次倾斜期间，柔光和卡包中心、旋转与缩放逐帧一致")
	check(shadow_visible and shadow_drift < 0.1, "跳动投影固定在地面，不随卡包上移")
	check(shadow_visible and shadow_widest > maze._initial_pack_button.size.x * maze._initial_pack_button.scale.x * maze.INITIAL_PACK_SHADOW_RATIO.x, "跳起时淡入柔和影子，并随高度略微变宽")
	check(not maze._initial_pack_shadow.visible and maze._initial_pack_shadow.mouse_filter == Control.MOUSE_FILTER_IGNORE, "落地后收起影子，且影子不拦截点击")
	await frames()
	await click_control(maze._initial_pack_button)
	await create_timer(0.8).timeout
	var opening: CardPackOpening = main._card_pack_opening
	check(is_instance_valid(opening), "真实点击卡包进入开包界面")
	check(glow != null and not glow.is_visible_in_tree(), "进入开包后桌面柔光收起")
	if not is_instance_valid(opening):
		print("CLICK_DIAGNOSTIC: ", maze._initial_pack_button.get_global_rect(), " disabled=", maze._initial_pack_button.disabled, " idle=", maze._initial_pack_idle_seconds, " hint=", main.get_node_or_null("TaskHint"), " message=", main.play_area_label.text)
		shell.free()
		quit(1)
		return
	var surface := opening.surface
	surface.set_process(false)
	surface.set_pointer_force(Vector2.ZERO)
	check(opening._seal_wait_seconds < 3.0 and opening.tear_art.seal_hint_seconds < 0.0, "点击进入后未满三秒不显示银线提示")
	var before := await texture_shot(surface)
	await create_timer(0.2).timeout
	check((await texture_shot(surface)).get_data() == before.get_data(), "等待期间封口保持原图，不提前闪烁")
	while opening._seal_wait_seconds < 3.1: await process_frame
	check(opening.tear_art.seal_hint_seconds >= 0.0, "三秒仍未撕开才开启扫光")
	# 固定实际材质相位，读GPU像素核对往返方向与局部对比，不依赖截图帧率。
	opening.set_process(false)
	opening.tear_art.set_process(false)
	var light := opening.tear_art.material as ShaderMaterial
	var samples: Array[Image] = []
	for seconds: float in [0.25, 0.75, 1.25, 1.75]:
		light.set_shader_parameter("seal_hint_seconds", seconds)
		samples.append(await texture_shot(surface))
	var a := samples[0]
	var b := samples[1]
	var c := samples[3]
	var centers: Array[float] = []
	for sample: Image in samples:
		var weighted_x := 0.0
		var brightness := 0.0
		var maximum := 0.0
		var minimum := 1.0
		for y: int in sample.get_height():
			for x: int in sample.get_width():
				var point := Vector2(x, y) / surface.render_scale - opening.tear_art.position
				if point.y < 8.0 or point.y >= 13.0 or point.x < 4.0 or point.x > opening.tear_art.size.x - 4.0: continue
				var color := sample.get_pixel(x, y)
				if color.a < 0.99: continue
				var value := (color.r + color.g + color.b) / 3.0
				maximum = maxf(maximum, value)
				minimum = minf(minimum, value)
				var gain := maxf(0.0, value - 0.65)
				weighted_x += point.x * gain
				brightness += gain
		centers.append(weighted_x / maxf(brightness, 0.001) / opening.tear_art.size.x)
		check(maximum - minimum > 0.45, "同一时刻银线具有明显的局部亮暗对比")
	check(centers[0] < 0.35 and centers[1] > 0.65 and centers[2] > 0.65 and centers[3] < 0.35, "亮光先左至右、再右至左：" + str(centers))
	var changed_seal := 0
	var changed_elsewhere := 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			var third := c.get_pixel(x, y)
			var delta := absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) + absf(second.r - third.r) + absf(second.g - third.g) + absf(second.b - third.b)
			if delta < 0.01: continue
			var point := Vector2(x, y) / surface.render_scale - opening.tear_art.position
			if point.y >= 8.0 and point.y < 13.0: changed_seal += 1
			else: changed_elsewhere += 1
	check(changed_seal > 150 and changed_elsewhere == 0, "实际扫光仅改变银色封口横线：线内%d像素、线外%d像素" % [changed_seal, changed_elsewhere])
	a.save_png(OUTPUT.path_join("seal_a.png"))
	b.save_png(OUTPUT.path_join("seal_b.png"))
	opening.auto_tear()
	await process_frame
	check(opening.tear_art.seal_hint_seconds < 0.0, "开始撕包后立即停止扫光")
	main._close_card_inspection(true)
	await frames()
	var owned: OwnedCard = main.owned_card_collection.get_cards().filter(func(card: OwnedCard) -> bool: return card.card_data.card_type == CardData.CardType.MINION).front()
	check(owned != null, "开场包提供真实随从供工具箱检视")
	if owned != null: await _check_toolbox_effect_popup(main, owned)
	var table = preload("res://scripts/ui/event_card_table.gd").new()
	table.main = main
	main.add_child(table)
	var paths: Array[Dictionary] = [
		{"path_id": "first", "kind": "free_event", "hint": "第一种卡背", "back_art": "res://assets/ui/shop_event_20261020/event_front.png"},
		{"path_id": "second", "kind": "free_event", "hint": "第二种卡背", "back_art": "res://assets/ui/shop_event_20261020/event_back.png"},
		{"path_id": "third", "kind": "free_event", "hint": "默认卡背"},
	]
	table.show_choices(paths, false)
	var top: EventCardView = table._deck.get_node("DeckTopCard")
	check(top.back_artwork == load(paths[0].back_art), "牌堆顶部读取第一张牌的专属卡背")
	table._deal()
	await create_timer(0.6).timeout
	check(table.cards[0].back_artwork == top.back_artwork and table.cards[1].back_artwork != top.back_artwork and table.cards[2].back_artwork == EventCardView.BACK, "抽出后各牌保留独立卡背，缺省牌沿用原卡背")
	table.free()
	shell.free()
	print("Pack feedback render: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check_toolbox_effect_popup(main: Control, owned: OwnedCard) -> void:
	var previous: Array[Dictionary] = main.emblem_library.get_inventory_state()
	check(main.emblem_library.restore_inventory_state([
		{"instance_id": &"hover_torch", "emblem_id": &"火把"},
		{"instance_id": &"hover_sword", "emblem_id": &"长剑"},
	]), "工具箱载入两枚真实纹章实例")
	main._open_card_inspection(owned.card_data, owned)
	await create_timer(0.35).timeout
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 0.95
	Input.parse_input_event(lt)
	await create_timer(0.4).timeout
	var torch: Control = main.emblem_library._entries[0]
	var sword: Control = main.emblem_library._entries[1]
	var popup := get_first_node_in_group(&"card_effect_popup")
	check(main._inspection_library_expanded and popup != null and popup.source == torch and popup.panel.visible and popup.title.text.contains("火把") and popup.body.get_parsed_text().contains("耀眼"), "按住 LT 展开工具箱后，手柄高亮显示火把的真实效果")
	var right := InputEventJoypadButton.new()
	right.button_index = JOY_BUTTON_DPAD_RIGHT
	right.pressed = true
	root.push_input(right, true)
	await create_timer(0.1).timeout
	check(popup != null and popup.source == sword and popup.title.text.contains("长剑"), "手柄移动焦点时效果框切换到新纹章")
	lt = lt.duplicate() as InputEventJoypadMotion
	lt.axis_value = 0.0
	Input.parse_input_event(lt)
	await create_timer(0.1).timeout
	check(not main._inspection_library_expanded and popup != null and not popup.panel.visible, "松开 LT 收起工具箱并关闭效果框")
	await click_control(main._inspection_library_toggle)
	await create_timer(0.35).timeout
	await _move_hover_mouse(torch.get_global_rect().get_center())
	check(popup != null and popup.source == torch and popup.panel.visible and popup.body.get_parsed_text().contains("耀眼"), "鼠标指向工具箱纹章也显示相同效果框")
	await _move_hover_mouse(Vector2(20, 700))
	check(popup != null and not popup.panel.visible, "鼠标移出纹章后效果框关闭")
	main._close_card_inspection(true)
	main.emblem_library.restore_inventory_state(previous)


func _move_hover_mouse(internal_position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = shell.render_container.get_global_transform_with_canvas() * internal_position
	event.global_position = event.position
	event.relative = event.position - root.get_mouse_position()
	root.push_input(event, true)
	await process_frame
