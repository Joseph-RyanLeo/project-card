extends "res://tests/d2_7_shop_presentation_test.gd"

## 真实原画GPU、配置往返、原生Tween及Main水扩散事件；不写用户正式配置。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Timing = preload("res://scripts/battle/battle_projectile_timing.gd")
const Sample = preload("res://scripts/battle/battle_element_sample_visual.gd")
var assertions := 0
var hits := 0
var launched: Array[BattleEffectEvent] = []
var visuals: Array[Sample] = []

func check(ok: bool, label: String) -> void:
	assertions += 1
	super.check(ok, label)

func _run() -> void:
	create_timer(70).timeout.connect(func(): push_error("水流冲击波验收超时"); quit(1))
	Profiles.reload_profiles(false)
	check(Profiles.get_profile(&"water_spread").mask_kind == &"water_flow", "新增可选项保留像素水流默认值")
	await _check_original_frames()
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-water-shockwave-run.json"
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K)
	await create_timer(0.6).timeout
	shell.open_attack_effect_lab()
	await process_frame
	await process_frame
	var lab := shell._attack_effect_lab as AttackEffectLab
	lab._auto_play = false
	lab._on_profile_selected(Profiles.PROFILE_IDS.find(&"water_spread"))
	var before: Dictionary = lab._drafts[&"water_spread"].duplicate(true)
	lab.mask_option.item_selected.emit(Profiles.MASK_IDS.find(&"water_shockwave"))
	await process_frame
	var profile: Dictionary = lab._drafts[&"water_spread"]
	check(profile.mask_kind == &"water_shockwave" and lab.mask_option.get_item_text(lab.mask_option.selected) == "水流冲击波（原画）", "水扩散下拉框真实信号选择新样式并播放")
	check(lab.head_color_option.disabled and not (lab._numeric_controls[&"warp_strength"].row as Control).visible, "原画保留配色，隐藏不生效的程序噪声参数")
	check(is_equal_approx(lab._preview_start.distance_to(lab._preview_end), lab.WATER_PREVIEW_GAP), "冲击波沿用相邻卡位的水扩散预览")
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		var delay := Timing.calculate_impact_delay(profile, variant)
		check(is_equal_approx(delay, Timing.calculate_impact_delay(before, variant)), "切换样式保留变速%d原有命中时间" % variant)
		await _check_flight(lab.effect_layer, profile, variant, delay)
	await _check_parameters(lab)
	# 参数调试验收后恢复默认草稿，再检查正式战斗接触位置。
	lab._drafts[&"water_spread"] = profile
	lab._load_profile_into_controls(&"water_spread")
	lab._layout_preview()
	var preview := lab.effect_layer.get_child(-1) as Sample
	if preview != null and not preview.is_queued_for_deletion():
		Renderer.set_flight_paused(preview, true)
		(preview.get_meta("flight_tween") as Tween).custom_step(0.48)
	await capture("water-shockwave-lab-2k")
	check(Profiles.export_profiles("/private/tmp/project-card-water-shockwave.json", lab._drafts) == OK, "冲击波可导出JSON")
	var imported := Profiles.read_profile_file("/private/tmp/project-card-water-shockwave.json")
	check(imported.success and imported.profiles[&"water_spread"].mask_kind == &"water_shockwave", "冲击波配置往返保留选择")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/private/tmp/project-card-water-shockwave.json"))
	legacy.version = 2
	for data: Dictionary in legacy.profiles.values():
		for field: Dictionary in Profiles.NUMERIC_FIELDS:
			if field.get("introduced", 1) == 3: data.erase(field.key)
	var file := FileAccess.open("/private/tmp/project-card-water-contact-v2.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var restored := Profiles.read_profile_file("/private/tmp/project-card-water-contact-v2.json")
	check(restored.success and restored.profiles[&"water_spread"].water_ball_size == 12.0 and restored.profiles[&"water_spread"].water_wall_x == 68.0, "旧v2配置导入补齐水球和墙面参数")
	check(Profiles.save_profiles(imported.profiles, "/private/tmp/project-card-water-shockwave.cfg") == OK, "临时保存后正式入口读取冲击波")
	shell.close_attack_effect_lab()
	await process_frame
	await _check_real_battle()
	shell.queue_free()
	await process_frame
	await process_frame
	print("水流冲击波：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func _check_original_frames() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(640, 400)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var visual := Sample.new()
	view.add_child(visual)
	var profile := Profiles.get_default_profile(&"water_spread")
	profile.beam_height = 128.0
	visual.configure(&"water_shockwave", PackedVector2Array([Vector2(160, 160), Vector2(300, 160)]), profile, 0)
	var atlas := Sample.WATER_ATLAS.get_image()
	atlas.convert(Image.FORMAT_RGBA8)
	atlas.premultiply_alpha() # 清掉导入器扩散到完全透明像素的RGB，只比较真实可见原画。
	# 新飞行阶段只绘制原画右端的小球，不再带着整条水柱。
	visual.update_visual(0.0, 1.5, 0.0, 0.4)
	await process_frame
	await RenderingServer.frame_post_draw
	var ball_origin := Vector2i((visual.water_ball.get_global_transform() * visual.water_ball.get_rect().position).round())
	var ball_image := view.get_texture().get_image().get_region(Rect2i(ball_origin, Vector2i(12, 12)))
	ball_image.convert(Image.FORMAT_RGBA8)
	check(ball_image.get_data() == atlas.get_region(Rect2i(35, 58, 12, 12)).get_data() and not visual.sprite.visible, "飞行水球逐像素保留原球，整张水柱隐藏")
	# 隔离尾流裁切，确认命中后20张原画本身没有改色或重排。
	(visual.sprite.material as ShaderMaterial).set_shader_parameter("tail_length", 128.0)
	for frame: int in range(Sample.WATER_IMPACT_FRAME, Sample.WATER_FRAME_COUNT):
		var elapsed := 0.4 + (frame - Sample.WATER_IMPACT_FRAME) * Sample.WATER_FRAME_SECONDS
		visual.update_visual(1.0, 1.5, elapsed + 0.00001, 0.4)
		await process_frame
		await RenderingServer.frame_post_draw
		RenderingServer.force_sync()
		var origin := Vector2i((visual.sprite.get_global_transform() * visual.sprite.get_rect().position).round())
		var drawn := view.get_texture().get_image().get_region(Rect2i(origin, Vector2i(128, 128)))
		drawn.convert(Image.FORMAT_RGBA8)
		var expected := atlas.get_region(Rect2i(frame * 128, 0, 128, 128))
		check(visual.sprite.frame == frame and drawn.get_data() == expected.get_data(), "第%d帧原比例GPU逐像素保留颜色、透明度和水滴" % frame)
	(visual.sprite.material as ShaderMaterial).set_shader_parameter("tail_length", 0.0)
	visual.update_visual(1.0, 1.5, 0.56001, 0.4)
	await process_frame
	await RenderingServer.frame_post_draw
	var splash_origin := Vector2i((visual.sprite.get_global_transform() * visual.sprite.get_rect().position).round())
	var clipped := view.get_texture().get_image().get_region(Rect2i(splash_origin, Vector2i(128, 128)))
	var long_stream := 0
	for y: int in range(58, 70):
		for x: int in 68:
			if clipped.get_pixel(x, y).a > 0.0: long_stream += 1
	check(long_stream == 0, "GPU确认零尾流移除命中前的横向长水柱")
	view.queue_free()
	await process_frame

func _check_flight(parent: CanvasItem, profile: Dictionary, variant: int, delay: float) -> void:
	hits = 0
	var to := Vector2(380, 210)
	var visual := Renderer.play(parent, PackedVector2Array([Vector2(250, 210), to]), profile, Color.RED, Color.GREEN, func(): hits += 1, 1.0, variant, delay) as Sample
	var tween := visual.get_meta("flight_tween") as Tween
	Renderer.set_flight_paused(visual, true)
	tween.custom_step(delay - 0.0001)
	check(hits == 0 and visual.water_ball.visible and not visual.sprite.visible, "变速%d命中前仅有小水球且不回调" % variant)
	tween.custom_step(0.00011)
	check(hits == 1 and visual.position.is_equal_approx(to) and visual.sprite.frame == Sample.WATER_IMPACT_FRAME and visual.sprite.visible and not visual.water_ball.visible, "变速%d命中时水球切换为原画水花" % variant)
	var elapsed := tween.get_total_elapsed_time()
	var frame := visual.sprite.frame
	await create_timer(0.06).timeout
	check(visual.sprite.frame == frame and tween.get_total_elapsed_time() == elapsed, "暂停同时冻结水花和弹道")
	for index: int in 19:
		tween.custom_step(0.04)
		check(visual.sprite.frame == Sample.WATER_IMPACT_FRAME + index + 1, "命中后完整保留40毫秒原帧%d" % (index + 5))
	Renderer.set_flight_speed(visual, 3.0)
	elapsed = tween.get_total_elapsed_time()
	tween.custom_step(0.005)
	check(is_equal_approx(tween.get_total_elapsed_time() - elapsed, 0.015), "三倍速推进同一动画时钟")
	tween.custom_step(1.0)
	check(hits == 1, "水滴收尾不重复命中")
	await process_frame
	check(not is_instance_valid(visual), "播完完整水花后释放节点")
	var left := Renderer.play(parent, PackedVector2Array([to, Vector2(250, 210)]), profile, Color.WHITE, Color.WHITE) as Sample
	Renderer.set_flight_paused(left, true)
	check(is_equal_approx(absf(left.rotation), PI) and left.sprite.scale.x == left.sprite.scale.y, "向左扩散自动转向且不拉伸原画")
	left.queue_free()
	await process_frame

func _check_real_battle() -> void:
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	main.resource_board_state = ResourceBoardState.new()
	main.resource_board_state.initialize_level(&"water_shockwave_test", RandomNumberGenerator.new())
	var definition: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
	definition.effect_ids.clear()
	definition.keywords.clear()
	definition.base_value = 5
	definition.max_health = 2000
	definition.cooldown_seconds = 8.0
	var owned: OwnedCard = main.owned_card_collection.create_card(definition)
	owned.resolved_runes.assign([CardData.ElementType.WATER, CardData.ElementType.WATER, CardData.ElementType.WATER])
	owned.rune_revealed.assign([true, true, true])
	main.front_row.add_squad(SquadData.from_owned_card(owned), 0)
	var dummy: CardData = definition.duplicate(true)
	dummy.base_value = 0
	dummy.cooldown_seconds = 99
	dummy.runes.clear()
	for index: int in 3: main.enemy_front_row.add_squad(SquadData.from_card(dummy.duplicate(true)), index)
	await create_timer(0.3).timeout
	var controller: BattleController = main.battle_controller
	controller.projectile_launched.connect(_collect_water)
	check(main.start_battle(73028, false), "真实Main开始水元素扩散战斗")
	for step: int in 260:
		controller.advance_time(0.05)
		if not launched.is_empty(): break
	check(not launched.is_empty() and launched.size() == visuals.size(), "实际水扩散事件逐个创建新冲击波原画节点")
	for index: int in visuals.size():
		var visual := visuals[index]
		var event := launched[index]
		var slot: BoardSlot = main._battle_state_slots[event.target]
		var target: Vector2 = main.battle_effect_layer.get_global_transform_with_canvas().affine_inverse() * slot.get_global_rect().get_center()
		var tween := visual.get_meta("flight_tween") as Tween
		tween.pause()
		tween.custom_step(event.projectile_impact_delay + 0.001)
		var inverse: Transform2D = main.battle_effect_layer.get_global_transform_with_canvas().affine_inverse()
		var bounds := Rect2(inverse * slot.get_global_rect().position, inverse.basis_xform(slot.get_global_rect().size))
		var anchor_slot: BoardSlot = main._battle_state_slots[event.anchor]
		var from: Vector2 = inverse * anchor_slot.get_global_rect().get_center()
		var contact := Renderer.water_contact_point(from, target, bounds)
		check(visual.position.is_equal_approx(contact) and visual.sprite.frame == Sample.WATER_IMPACT_FRAME, "正式战斗按原命中时刻撞在真实邻位的迎面卡边")
	var count: int = main.battle_effect_layer.get_child_count()
	main._play_element_impact(Vector2(500, 180), &"water_spread")
	check(main.battle_effect_layer.get_child_count() == count, "原画自带命中水花，不叠加旧菱形冲击")
	main._clear_battle_presentation_for_preparation()
	controller.clear_battle()
	main.current_phase = main.GamePhase.PREPARE

func _collect_water(event: BattleEffectEvent) -> void:
	if event.visual_kind != &"water_spread": return
	launched.append(event)
	for child: Node in main.battle_effect_layer.get_children():
		if child is Sample and child not in visuals:
			visuals.append(child)


func _check_parameters(lab: AttackEffectLab) -> void:
	var original: Dictionary = lab._drafts[&"water_spread"].duplicate(true)
	lab._drafts[&"water_spread"] = original.duplicate(true)
	lab._water_freeze_button.button_pressed = true
	await process_frame
	var effect := lab.effect_layer.get_child(-1) as Sample
	var bounds := lab._water_target_bounds()
	var edge := Vector2(bounds.position.x, bounds.get_center().y)
	check(lab._preview_card.visible and lab._wood_target_card.visible and lab._water_boundary_guide.visible and not lab.target_marker.visible, "冲击波调试显示真实双卡与迎面卡边参考线")
	check(effect.position.is_equal_approx(edge) and effect.sprite.visible and not effect.water_ball.visible, "定格按钮停在迎面卡边的首张水花")
	await capture("water-contact-default-2k")
	var position := effect.position
	(lab._numeric_controls[&"water_contact_offset"].slider as HSlider).value = -10.0
	effect = lab.effect_layer.get_child(-1) as Sample
	check(effect.position.is_equal_approx(position - Vector2(10, 0)), "定格调节边界偏移立即把接触点移到卡外")
	var sprite_position := effect.sprite.position
	(lab._numeric_controls[&"water_wall_x"].slider as HSlider).value = 74.0
	effect = lab.effect_layer.get_child(-1) as Sample
	check(is_equal_approx(effect.sprite.position.x - sprite_position.x, -6.0 * effect.sprite.scale.x), "原画墙面X独立改变锚点而不移动卡边")
	(lab._numeric_controls[&"water_ball_size"].slider as HSlider).value = 24.0
	effect = lab.effect_layer.get_child(-1) as Sample
	check(is_equal_approx(effect.water_ball.get_rect().size.y * effect.water_ball.scale.y, 24.0) and is_equal_approx(effect.sprite.scale.x, 112.0 / 128.0), "水球大小独立于水花尺寸")
	(lab._numeric_controls[&"water_tail_length"].slider as HSlider).value = 20.0
	effect = lab.effect_layer.get_child(-1) as Sample
	check(effect.water_ball.texture.get_size().x > 12.0 and is_equal_approx(float((effect.sprite.material as ShaderMaterial).get_shader_parameter("tail_length")), 20.0 / effect.sprite.scale.x), "尾流参数同时控制飞行小球和命中水柱")
	(lab._numeric_controls[&"water_impact_frame"].slider as HSlider).value = 6.0
	(lab._numeric_controls[&"water_playback_speed"].slider as HSlider).value = 2.0
	effect = lab.effect_layer.get_child(-1) as Sample
	check(effect.sprite.frame == 6, "起始帧修改立即同步到命中定格")
	var tween := effect.get_meta("flight_tween") as Tween
	tween.custom_step(0.04)
	check(effect.sprite.frame == 8, "两倍水花速度每40毫秒推进两帧")
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		check(is_equal_approx(Timing.calculate_impact_delay(lab._drafts[&"water_spread"], variant), Timing.calculate_impact_delay(original, variant)), "外观调节不改变变速%d的实际命中时刻" % variant)
	check(Profiles.export_profiles("/private/tmp/project-card-water-contact-tuned.json", lab._drafts) == OK, "可导出实际调节后的水球和卡边参数")
	var roundtrip := Profiles.read_profile_file("/private/tmp/project-card-water-contact-tuned.json")
	check(roundtrip.success and roundtrip.profiles[&"water_spread"].water_ball_size == 24.0 and roundtrip.profiles[&"water_spread"].water_wall_x == 74.0 and roundtrip.profiles[&"water_spread"].water_contact_offset == -10.0 and roundtrip.profiles[&"water_spread"].water_impact_frame == 6.0 and roundtrip.profiles[&"water_spread"].water_playback_speed == 2.0, "非默认调节值导入后完整保留")
	await capture("water-contact-frozen-2k")
	lab._water_freeze_button.button_pressed = false
	# 接触点方向及几何尺寸完全由真实目标边界决定。
	check(Renderer.water_contact_point(Vector2(300, 100), Vector2(100, 100), Rect2(50, 32, 100, 136)).is_equal_approx(Vector2(150, 100)), "向左传播命中目标右边界")
	check(Renderer.water_contact_point(Vector2(100, 300), Vector2(100, 100), Rect2(50, 32, 100, 136)).is_equal_approx(Vector2(100, 168)), "从下方传播命中目标下边界")
