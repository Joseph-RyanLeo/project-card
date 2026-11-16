extends "res://tests/deployment_tutorial_steps_test.gd"

## 新初始包、真实右键检视、备战乡邻加成与柔和亮圈的集中验收。
const MILITIA_DIR := "/private/tmp/project-card-militia-keywords-test"
const TextSettings = preload("res://scripts/ui/card_text_display_settings.gd")


func right_click(control: Control) -> void:
	var at: Vector2 = shell.render_container.get_global_transform_with_canvas() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = at
		root.push_input(event, true)
		await process_frame
	await create_timer(0.5).timeout


func verify_soft_spotlight(hint: Control) -> void:
	var original: ShaderMaterial = main._inspection_dim.material as ShaderMaterial
	check(original != null and original.shader.resource_path == "res://shaders/hero_speech_spotlight.gdshader", "真实英雄对白改用软边亮圈，没有矩形挖洞")
	var spotlight: Vector4 = original.get_shader_parameter("spotlight")
	var halo_area := Rect2(Vector2(spotlight.x - spotlight.z, spotlight.y - spotlight.w), Vector2(spotlight.z, spotlight.w) * 2)
	check(halo_area.encloses(hint.speech.get_rect()) and halo_area.intersects(main.maze_controller._hint_control_rect(main.player_avatar_button)), "亮圈根据当前英雄和气泡共同布局")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var dim := ColorRect.new()
	dim.size = Vector2(1280, 720)
	dim.material = original.duplicate() as ShaderMaterial
	dim.material.set_shader_parameter("dim_opacity", 0.78)
	dim.material.set_shader_parameter("use_backdrop_color", false)
	dim.material.set_shader_parameter("spotlight", Vector4(640, 360, 100, 120))
	dim.material.set_shader_parameter("canvas_region", Vector4(0, 0, 1280, 720))
	viewport.add_child(dim)
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := viewport.get_texture().get_image()
	var center := frame.get_pixel(640, 360).a
	var inner := frame.get_pixel(715, 360).a
	var middle := frame.get_pixel(730, 360).a
	var outer := frame.get_pixel(745, 360).a
	var background := frame.get_pixel(800, 360).a
	check(center < 0.01 and background > 0.75, "亮圈中心保持原亮度，远处维持原暗幕")
	check(inner > center and middle > inner and outer > middle and background > outer, "实际GPU像素在亮圈边缘连续渐变，而非硬切矩形")
	viewport.queue_free()


func verify_steady_backdrop(hint: Control) -> void:
	var dim: ColorRect = main._inspection_dim
	while is_instance_valid(hint) and (hint._hero_line_index < 1 or hint._speech_spotlight_strength < 0.99):
		await process_frame
	await RenderingServer.frame_post_draw
	var background_pixel := Vector2i(185, 400)
	var background_color: Color = shell.internal_viewport.get_texture().get_image().get_pixelv(background_pixel)
	var baseline_alpha := dim.modulate.a
	var changed_opacity := false
	var changed_background := false
	var fading_spot := false
	while is_instance_valid(hint):
		await RenderingServer.frame_post_draw
		changed_opacity = changed_opacity or not dim.visible or not is_equal_approx(dim.modulate.a, baseline_alpha)
		if is_instance_valid(hint):
			fading_spot = fading_spot or (hint._speech_spotlight_strength > 0.0 and hint._speech_spotlight_strength < 0.99)
			if not fading_spot and not hint._closing and hint.speech.visible: continue
		var pixel: Color = shell.internal_viewport.get_texture().get_image().get_pixelv(background_pixel)
		changed_background = changed_background or absf(pixel.get_luminance() - background_color.get_luminance()) > 0.012
	check(not changed_opacity and not changed_background and fading_spot and dim.material == null, "逐帧确认对白收尾仅淡出英雄亮区，远处背景亮度无闪动")


func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("民兵关键词教学专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(MILITIA_DIR)
	Effects.load_saved(MILITIA_DIR.path_join("effects.cfg"))
	Effects.reset_defaults()
	TextSettings.load_settings(MILITIA_DIR.path_join("card-text.cfg"))
	TextSettings.set_mode(self, TextSettings.Mode.CARD, false)
	root.gui_embed_subwindows = true
	shell = SHELL.instantiate()
	shell.run_slots.directory = MILITIA_DIR
	for index: int in 3: shell.run_slots.delete_slot(index)
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await frames()
	check(await shell.start_slot(0), "创建隔离民兵教学档")
	check(shell.slot_progress.select_catalog_tasks("tutorial", "") and await shell.start_new_slot_run(), "正式开始新教程")
	main = shell.main_screen
	var maze = main.maze_controller
	while shell.screen_transition.busy: await process_frame
	if is_instance_valid(maze._initial_pack_drop): await maze._initial_pack_drop.finished
	check(main.save_profile_action(func():
		for id: String in ["supplies", "event_reward", "shop_route", "shop_entered"]:
			main.profile_progress.record_hint_read("tutorial:step:" + id, TaskCatalog.tutorial_hint(id), {"story": id != "supplies", "teaching": true})
		return true), "隔离夹具只略过已测的操作教学，保留开包对白")
	check(maze.open_task_supply(), "正式打开初始卡包")
	var ids: Array = main.owned_card_collection.get_cards().map(func(card: OwnedCard): return String(card.card_data.id))
	check(ids.size() == 5 and ids.has("militia") and not ids.has("elegy_poet"), "初始5张仅以民兵替换悲歌诗人，不额外发卡")
	await create_timer(0.7).timeout
	main._card_pack_opening.auto_tear()
	var hint := await expected_hint("supplies")
	await create_timer(0.5).timeout
	await verify_soft_spotlight(hint)
	await capture_pack("16_hero_soft_spotlight")
	await verify_steady_backdrop(hint)
	if "--backdrop-only" in OS.get_cmdline_user_args():
		shell.free()
		print("开包暗幕专项：%d 项，%d 失败" % [checks, failures])
		quit(1 if failures else 0)
		return
	main._close_card_inspection(true)
	await create_timer(0.4).timeout
	while not maze.hero.pending_talent_levels.is_empty(): maze.choose_talent(String(maze.hero.get_pending_choices()[0]))
	while maze.run.get_round_kind() != "battle":
		check(maze.select_path(String(maze.run.paths[0].path_id)), "正式走过首战前事件")
		if maze.run.get_round_kind() == "shop":
			if is_instance_valid(main._shop_open_tween) and main._shop_open_tween.is_running(): await main._shop_open_tween.finished
			await click_control(main._shop_leave_button)
		else: check(maze.complete_event(false, true), "正式完成前置事件")
	check(maze.select_path(String(maze.run.paths[0].path_id)), "正式进入战斗准备")
	hint = await expected_hint("deploy_view")
	await click_control(main.player_avatar_button)
	hint = await expected_hint("deploy")
	var militia: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/militia.tres"))
	var gun: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": gun.card_data, "owned_card": gun}, &"board", main.front_row), "正式部署第一个随从")
	hint = await expected_hint("militia_inspect")
	check(hint.instruction_label.text.contains("右键") and hint.instruction_label.text.contains("民兵"), "首次部署后先引导右键民兵，而非直接催促开战")
	await right_click(main.front_row.get_squads()[0].card_view)
	check(is_instance_valid(main._inspection_overlay) and not hint._teaching_done and not main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:militia_inspect"), "右键其他随从不会误完成民兵教学")
	await key_escape()
	var militia_view: CardView = main._find_collection_slot_for_owned_card(militia).get_child(0)
	await right_click(militia_view)
	hint = await expected_hint("militia_keywords")
	check(main._inspection_owned_card == militia and main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:militia_inspect"), "真实右键民兵后才保存检视步骤并介绍关键词")
	var effect_box: PanelContainer = main._inspection_overlay.get_node("InspectionEffectSideBox")
	var labels := (effect_box.get("_visual") as Control).find_children("*", "RichTextLabel", true, false)
	var text := labels[0] as RichTextLabel
	check(text.text.contains("[b][keyword") and (labels[1] as RichTextLabel).get_parsed_text().contains("左右两侧"), "默认卡面模式的检视同样显示粗体动态关键词及规则说明")
	check(effect_box.position.y >= main.INSPECTION_DISPLAY_BUTTON_POSITION.y + 28 and Rect2(0, 0, 1280, 720).encloses(effect_box.get_rect()), "检视关键词说明避开右上角控件并完整落在画布内")
	check(hint.instruction_label.text.contains("同排左右两侧") and hint.instruction_label.text.contains("数值各+1"), "教学说明关键词系统与民兵乡邻的实际效果")
	await capture_pack("17_militia_keyword_inspection")
	await key_escape()
	hint = await expected_hint("militia_neighbor")
	check(not maze._militia_neighbor_active(), "只有单个随从时乡邻尚未触发")
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": militia.card_data, "owned_card": militia}, &"board", main.front_row, 1), "正式把民兵放到同排第二位")
	await create_timer(0.4).timeout
	check(not maze._militia_neighbor_active() and main.get_node_or_null("TaskHint") == hint, "只有一侧人类时保留引导，不误判乡邻成立")
	var shield: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/shieldwall_private.tres"))
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": shield.card_data, "owned_card": shield}, &"board", main.front_row, 2), "正式在民兵另一侧部署人类随从")
	await create_timer(0.4).timeout
	check(not maze._militia_neighbor_active() and main.get_node_or_null("TaskHint") == hint, "火枪手是矮人，站位正确但种族不符仍不能完成乡邻教学")
	var checkpoint := MILITIA_DIR.path_join("before-practice-battle.json")
	check(main.save_run_to_path(checkpoint) == OK, "保存尚未完成乡邻练习的真实准备状态")
	await click_control(main.start_battle_button)
	var combat_hint := await expected_hint("battle_intro")
	check(not main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:militia_neighbor"), "提前开战不会把未触发的乡邻练习误记为已完成")
	await click_control(main.front_row)
	check(main.load_run_from_path(checkpoint), "恢复练习前的真实存档继续调整站位")
	hint = await expected_hint("militia_neighbor")
	main.set_world_view(main.WorldView.COLLECTION, false)
	# 读档恢复的是新的OwnedCard实例，继续使用恢复后的权威实例。
	militia = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/militia.tres"))
	gun = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var gun_slot: BoardSlot = main.front_row.get_squads()[0]
	check(main._transfer_card({"kind": &"card", "source_type": &"board", "source_row": main.front_row, "source_slot": gun_slot, "card_data": gun_slot.get_squad_data().horizontal_cards[0], "owned_card": gun}, &"board", main.back_row, 0), "通过正式转移把矮人移到后排")
	var priest: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/town_priest.tres"))
	check(main._transfer_card({"kind": &"card", "source_type": &"collection", "card_data": priest.card_data, "owned_card": priest}, &"board", main.front_row, 0), "将人类城镇牧师放到民兵另一侧，与盾墙列兵一起满足乡邻")
	hint = await expected_hint("battle_ready")
	check(maze._militia_neighbor_active() and main.profile_progress.profile.tutorial.read_hints.has("tutorial:step:militia_neighbor"), "真实备战效果生效后才完成乡邻教学并进入继续布阵提示")
	var militia_state: BattleSquadState
	for state: BattleSquadState in main.battle_controller.player_states:
		if state.get_effect_source().id == &"militia": militia_state = state
	check(militia_state.modifiers.get_additive(BattleModifier.Stat.ACTION_VALUE) == 1, "民兵数值实际获得乡邻+1，不仅更改提示状态")
	await capture_pack("18_militia_neighbor_active")
	shell.free()
	print("Militia keyword tutorial: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
