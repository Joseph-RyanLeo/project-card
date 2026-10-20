extends "res://tests/d2_7_shop_presentation_test.gd"

## 真实2K画布、原生Tween与正式战斗状态；不代替控制器生成假灼烧。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Timing = preload("res://scripts/battle/battle_projectile_timing.gd")
const FireVisual = preload("res://scripts/battle/battle_fire_visual.gd")
var hits := 0

func _run() -> void:
	create_timer(50.0).timeout.connect(func(): push_error("水火样板验收超时"); quit(1))
	Profiles.reload_profiles(false)
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-water-fire-test-save.json"
	shell.open_attack_effect_lab()
	await process_frame
	var lab := shell._attack_effect_lab as AttackEffectLab
	lab._toggle_auto_play()
	lab._on_profile_selected(Profiles.PROFILE_IDS.find(&"water_spread"))
	(lab._numeric_controls[&"duration"].slider as HSlider).value = 0.93
	(lab._numeric_controls[&"trail_length"].slider as HSlider).value = 0.61
	var before: Dictionary = lab._drafts[&"water_spread"].duplicate(true)
	(lab.find_child("WaterFlowPresetButton", true, false) as Button).pressed.emit()
	var water: Dictionary = lab._drafts[&"water_spread"]
	check(water.mask_kind == &"water_flow" and lab.mask_option.get_item_text(lab.mask_option.selected) == "像素水流", "调整器真实按钮应用水流样板")
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		check(is_equal_approx(Timing.calculate_impact_delay(water, variant), Timing.calculate_impact_delay(before, variant)), "水流预设保留变速%d的命中时间" % variant)
	var effect := lab.effect_layer.get_child(-1) as Node2D
	var material := (effect.get_node("BeamMesh") as MeshInstance2D).material as ShaderMaterial
	check(bool(material.get_shader_parameter("water_flow")), "正式共用渲染器开启实际水流shader分支")
	var wave_mesh := (effect.get_node("BeamMesh") as MeshInstance2D).mesh
	var vertices: PackedVector2Array = wave_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices[0].distance_to(vertices[1]) > absf(vertices[2].x - vertices[0].x) * 1.9, "水波横向厚度小于波面宽度的一半")
	check(is_equal_approx(lab._preview_start.distance_to(lab._preview_end), lab.WATER_PREVIEW_GAP), "调整器水扩散采用相邻卡位短距离")
	var distant := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(60, 140), Vector2(900, 140)]), water, Color.DODGER_BLUE, Color.DODGER_BLUE)
	Renderer.set_flight_paused(distant, true)
	check((distant.get_node("BeamMesh") as MeshInstance2D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices, "传播距离增加不会把水波拉成长条")
	distant.queue_free()
	Renderer.set_flight_paused(effect, true)
	var tween := effect.get_meta("flight_tween") as Tween
	tween.custom_step(0.32)
	var time_before := float(material.get_shader_parameter("effect_time"))
	await create_timer(0.08).timeout
	check(is_equal_approx(float(material.get_shader_parameter("effect_time")), time_before), "暂停弹道时液体噪声同时停止")
	Renderer.set_flight_speed(effect, 3.0)
	tween.custom_step(0.05)
	check(is_equal_approx(float(material.get_shader_parameter("effect_time")) - time_before, 0.15), "三倍速同时推进水流形变时钟")
	await capture("water-sample-2k")
	# 原生Tween在各随机速度变体下仍按真实命中延迟回调，且仅回调一次。
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		hits = 0
		var delay := Timing.calculate_impact_delay(water, variant)
		var flight := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(60, 140), Vector2(400, 210)]), water, Color.DODGER_BLUE, Color.DODGER_BLUE, func(): hits += 1, 1.0, variant, delay)
		var animation := flight.get_meta("flight_tween") as Tween
		animation.pause()
		animation.custom_step(delay - 0.001)
		check(hits == 0, "水弹道变体%d到逻辑命中前不触发回调" % variant)
		animation.custom_step(0.002)
		check(hits == 1, "水弹道变体%d在真实命中时间抵达" % variant)
		check(flight.position.is_equal_approx(Vector2(400, 210)), "水波变体%d的可见前缘在命中时抵达邻位" % variant)
		animation.custom_step(2.0)
		check(hits == 1, "水弹道变体%d收尾不重复命中" % variant)
	var left_wave := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(400, 210), Vector2(270, 210)]), water, Color.DODGER_BLUE, Color.DODGER_BLUE)
	Renderer.set_flight_paused(left_wave, true)
	check(is_equal_approx(absf(left_wave.rotation), PI), "向左扩散时水波圆弧前缘随传播方向翻转")
	left_wave.queue_free()
	lab._on_profile_selected(Profiles.PROFILE_IDS.find(&"fire_burn"))
	await process_frame
	var fire := lab.effect_layer.get_child(-1) as FireVisual
	check(is_instance_valid(fire) and lab._preview_card.visible and lab.mask_option.disabled and not (lab._numeric_controls[&"arc_height"].row as Control).visible, "火样板显示真实卡面，只展示生效的火焰参数")
	var fire_tween := fire.get_meta("preview_tween") as Tween
	# 预览回调直接消费相同火焰节点，固定在中段留存供人工对照。
	fire_tween.pause()
	lab._update_fire_preview(0.2, fire, lab._fire_preview_bounds(), 1.8)
	lab._update_fire_preview(0.9, fire, lab._fire_preview_bounds(), 1.8)
	check(float(fire.effect.get_shader_parameter("pulse_strength")) > 0.0 and is_equal_approx(float(fire.effect.get_shader_parameter("opacity")), FireVisual.FIRE_OPACITY), "火样板每跳增强并保留卡面辨识度")
	var card_bounds := lab._fire_preview_bounds()
	check(fire.flame.position.y < card_bounds.position.y and fire.flame.size.y > card_bounds.size.y and fire.get_parent().z_index < lab._preview_card.z_index, "宽底火焰尺寸包住整卡并绘制在卡面后方")
	check(float(fire.effect.get_shader_parameter("pixel_size")) == 4.0, "两倍预览时火焰像素和卡牌同比例放大")
	await _check_fire_behind_card(lab.get_viewport(), card_bounds.get_center(), fire, "调试器")
	await capture("fire-sample-2k")
	lab._preview_card.hide()
	await capture("fire-shape-only-2k")
	for time: float in [0.35, 0.65, 1.15, 1.40]:
		fire.update_visual(card_bounds, time)
		await capture("fire-shape-%.2f-2k" % time)
	lab._preview_card.show()
	if OS.get_cmdline_user_args().has("--record-fire"):
		await _capture_fire_motion(lab, fire, card_bounds)
	(lab._numeric_controls[&"beam_height"].slider as HSlider).value = 110
	await process_frame
	fire = lab.effect_layer.get_child(-1) as FireVisual
	lab._update_fire_preview(0.5, fire, lab._fire_preview_bounds(), 1.8)
	check(is_equal_approx(fire.flame.size.y, 220), "调整火焰高度按卡牌倍率传入共用显示节点")
	var legacy := Profiles.get_profiles()
	legacy.erase(&"fire_burn")
	var file := FileAccess.open("/private/tmp/project-card-water-fire-legacy.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": Profiles.FILE_FORMAT, "version": 1, "profiles": legacy}))
	file.close()
	var imported := Profiles.read_profile_file("/private/tmp/project-card-water-fire-legacy.json")
	check(imported.success and imported.profiles.size() == 10 and imported.profiles.has(&"fire_burn"), "旧九类JSON保留已有配置并补充火样板默认值")
	shell.close_attack_effect_lab()
	await process_frame
	await _test_real_burn()
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("Water/fire sample failures: ", failures)
	quit(1 if failures else 0)


func _capture_fire_motion(lab: AttackEffectLab, fire: FireVisual, bounds: Rect2) -> void:
	if DisplayServer.get_name() == "headless": return
	var directory := "/private/tmp/project-card-fire-motion-frames"
	DirAccess.make_dir_recursive_absolute(directory)
	var region := Rect2i(fire.flame.get_global_rect().grow(8.0))
	for mode: String in ["shape", "card"]:
		lab._preview_card.visible = mode == "card"
		for index: int in 24:
			var time := 0.20 + float(index) * 0.08
			if index % 8 == 0: fire.pulse(time)
			fire.update_visual(bounds, time)
			await RenderingServer.frame_post_draw
			lab.get_viewport().get_texture().get_image().get_region(region).save_png("%s/%s-%02d.png" % [directory, mode, index])
	lab._preview_card.show()
	print("火焰连续帧已保存：", directory)


func _check_fire_behind_card(viewport: Viewport, center: Vector2, visual: FireVisual, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# 侧缘取在中线下方，避开战斗伤害提示横条。
	var rim_x := 0.5 + (0.08 - 0.5) / FireVisual.CANVAS_WIDTH_SCALE
	var rim := Vector2i(visual.flame.get_global_transform_with_canvas() * (visual.flame.size * Vector2(rim_x, 0.65)))
	var art := Vector2i(center)
	await RenderingServer.frame_post_draw
	var with_fire := viewport.get_texture().get_image()
	# 正式同步会按放逐状态刷新根节点可见性；仅隐藏实际绘制子节点做像素对照。
	visual.flame.hide()
	await RenderingServer.frame_post_draw
	var without_fire := viewport.get_texture().get_image()
	check(with_fire.get_pixelv(art).is_equal_approx(without_fire.get_pixelv(art)), label + "实际画面中卡牌中央像素不被火团染色")
	check(not with_fire.get_pixelv(rim).is_equal_approx(without_fire.get_pixelv(rim)), label + "实际画面中火团侧缘可见，未被背景遮住")
	visual.flame.show()


func _test_real_burn() -> void:
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	main.resource_board_state = ResourceBoardState.new()
	main.resource_board_state.initialize_level(&"water_fire_test", RandomNumberGenerator.new())
	for i: int in 2:
		var definition: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
		definition.cooldown_seconds = 9.0 # 观察单轮灼烧到期，避免下一轮攻击在熄灭前续上
		var owned: OwnedCard = main.owned_card_collection.create_card(definition)
		owned.resolved_runes.assign([CardData.ElementType.FIRE, CardData.ElementType.FIRE, CardData.ElementType.FIRE])
		owned.rune_revealed.assign([true, true, true])
		main.front_row.add_squad(SquadData.from_owned_card(owned), i)
	var dummy: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
	dummy.max_health = 2000
	dummy.cooldown_seconds = 99
	dummy.base_value = 0
	main.enemy_front_row.add_squad(SquadData.from_card(dummy), 0)
	check(main.start_battle(4201, false), "真实Main和正式控制器开始火元素测试战斗")
	var controller: BattleController = main.battle_controller
	for i: int in 300:
		if controller.active_continuous_effects.size() >= 2: break
		controller.advance_time(0.05)
	main._sync_fire_burn_visuals()
	check(controller.active_continuous_effects.size() == 2 and main._fire_burn_visuals.size() == 1, "两份真实灼烧独立存在，同一目标只显示一层火焰")
	if main._fire_burn_visuals.is_empty(): return
	var target: BattleSquadState = main._fire_burn_visuals.keys()[0]
	var visual := main._fire_burn_visuals[target] as FireVisual
	check(not visual.z_as_relative and visual.z_index == main.FIRE_BACKGROUND_Z_INDEX, "正式火团层级独立于1200层的前景弹道")
	controller.advance_time(0.2)
	main._sync_fire_burn_visuals()
	var inventory_before: Array = controller.active_continuous_effects.duplicate(true)
	var health := target.current_health
	main._sync_fire_burn_visuals()
	check(controller.active_continuous_effects == inventory_before and target.current_health == health, "火焰刷新不改动持续状态、剩余次数或伤害")
	var clock := float(visual.effect.get_shader_parameter("effect_time"))
	main._on_battle_pause_button_pressed()
	await create_timer(0.08).timeout
	check(paused and float(visual.effect.get_shader_parameter("effect_time")) == clock, "正式暂停同时冻结火苗和每跳增强")
	main._on_battle_pause_button_pressed()
	main.set_battle_speed(main.BATTLE_SPEED_MULTIPLIERS.find(3.0))
	controller._process(0.1)
	main._sync_fire_burn_visuals()
	check(is_equal_approx(float(visual.effect.get_shader_parameter("effect_time")) - clock, 0.3), "正式三倍速使火焰使用同一战斗时钟")
	var slot: BoardSlot = main._battle_state_slots[target]
	var origin := visual.flame.position
	slot.position.x += 18
	main._sync_fire_burn_visuals()
	check(is_equal_approx(visual.flame.position.x - origin.x, 18), "火焰随真实目标卡位移动")
	await _check_fire_behind_card(main.get_viewport(), slot.get_global_rect().get_center(), visual, "正式战斗")
	await capture("fire-battle-2k")
	for i: int in 85: controller.advance_time(0.05)
	main._sync_fire_burn_visuals()
	check(controller.active_continuous_effects.is_empty() and main._fire_burn_visuals.is_empty(), "真实灼烧到期后自动熄灭并清理节点")
	# 新一轮真实行动再次施加后，死亡和重开都必须清理显示引用。
	for i: int in 300:
		if not controller.active_continuous_effects.is_empty(): break
		controller.advance_time(0.05)
	main._sync_fire_burn_visuals()
	check(not main._fire_burn_visuals.is_empty(), "后续真实行动可再次显示火焰")
	target.current_health = 0
	target.alive = false
	main._sync_fire_burn_visuals()
	check(main._fire_burn_visuals.is_empty(), "目标死亡立即清理附着火焰")
	main._clear_battle_presentation_for_preparation()
	check(main._fire_burn_visuals.is_empty(), "返回准备阶段不残留火焰引用")
	controller.clear_battle()
	main.current_phase = main.GamePhase.PREPARE
