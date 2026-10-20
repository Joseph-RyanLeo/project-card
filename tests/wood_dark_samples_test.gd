extends "res://tests/d2_7_shop_presentation_test.gd"

## 真实图集、原生Tween和Main战斗；验证每次一刺／一斩及随机外观不影响规则。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Timing = preload("res://scripts/battle/battle_projectile_timing.gd")
const SampleVisual = preload("res://scripts/battle/battle_element_sample_visual.gd")

var hits := 0
var launched: Array[BattleEffectEvent] = []
var sample_nodes: Array[SampleVisual] = []


func _run() -> void:
	create_timer(55).timeout.connect(func(): push_error("木暗样板验收超时"); quit(1))
	Profiles.reload_profiles(false)
	var atlas := SampleVisual.WOOD_ATLAS.get_image()
	for row: int in 3:
		var head := atlas.get_region(Rect2i(4 * 160, row * 450, 160, 150))
		check(not head.is_invisible(), "木原画角度%d的完整突刺头部未被裁掉" % row)
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("--2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(0.5).timeout
	main = shell.main_screen
	main.run_save_path = "/private/tmp/project-card-wood-dark-state.json"
	shell.open_attack_effect_lab()
	await process_frame
	var lab := shell._attack_effect_lab as AttackEffectLab
	lab._toggle_auto_play()
	for id: StringName in [&"wood_pierce", &"dark_repeat"]:
		lab._on_profile_selected(Profiles.PROFILE_IDS.find(id))
		var before: Dictionary = lab._drafts[id].duplicate(true)
		before.merge({"duration": 0.91, "trail_length": 0.63, "trail_softness": 0.04, "speed_variation_strength": 0.46}, true)
		lab._drafts[id] = before
		await click((lab.find_child("ElementSamplePresetButton", true, false) as Button).get_global_rect().get_center())
		var profile: Dictionary = lab._drafts[id]
		check(profile.mask_kind == (&"wood_thorns" if id == &"wood_pierce" else &"dark_slash"), "真实按钮为%s选中朋友原画样板" % id)
		check(lab.head_color_option.disabled and not (lab._numeric_controls[&"warp_strength"].row as Control).visible, "手绘样板保留配色，只展示实际生效参数")
		for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
			check(is_equal_approx(Timing.calculate_impact_delay(profile, variant), Timing.calculate_impact_delay(before, variant)), "样板%s保留变速%d的命中时间" % [id, variant])
		await _check_timing(lab, profile)
		lab._reset_current_profile()
		if id == &"wood_pierce":
			check(is_equal_approx(lab._preview_start.distance_to(lab._preview_end), lab.WOOD_PREVIEW_GAP), "木预览从承载目标跨向另一排")
		else:
			check(lab._preview_card.visible and not lab.source_marker.visible and lab.effect_layer.z_index > lab._preview_card.z_index, "暗斩在目标卡面上显示，不从攻击方飞出")
		if OS.get_cmdline_user_args().has("--record-samples"):
			await _record_lab(lab, String(id))
	# 固定测试用视觉随机种子，避免概率断言；正式战斗仍使用独立的控制器随机源。
	seed(73015)
	var wood_rows: Dictionary = {}
	var angles: Dictionary = {}
	for index: int in 24:
		var wood := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(100, 240), Vector2(100, 60)]), Profiles.get_profile(&"wood_pierce"), Color.WHITE, Color.WHITE) as SampleVisual
		Renderer.set_flight_paused(wood, true)
		wood_rows[wood.sprite.frame / 16] = true
		check(wood.get_child_count() == 1 and wood.sprite.hframes == 16 and wood.sprite.vframes == 3, "每次木穿刺仅有一张单角度原画，未同时画三刺")
		wood.queue_free()
		var dark := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(100, 240), Vector2(360, 60)]), Profiles.get_profile(&"dark_repeat"), Color.WHITE, Color.WHITE) as SampleVisual
		Renderer.set_flight_paused(dark, true)
		angles[snappedf(dark.rotation, 0.01)] = true
		check(dark.position == Vector2(360, 60) and dark.sprite.hframes == 4 and dark.get_child_count() == 1, "每次暗连击只含一次白闪和一道斩痕，并固定在真实目标")
		dark.queue_free()
	check(wood_rows.size() == 3 and angles.size() > 12, "木随机覆盖三个角度原画，暗斩每击具有独立随机角度")
	check(Profiles.export_profiles("/private/tmp/project-card-wood-dark.json", lab._drafts) == OK, "新样式可导出全部配置")
	var imported := Profiles.read_profile_file("/private/tmp/project-card-wood-dark.json")
	check(imported.success and imported.profiles[&"wood_pierce"].mask_kind == &"wood_thorns" and imported.profiles[&"dark_repeat"].mask_kind == &"dark_slash", "新样式JSON读回后保留原画选择")
	check(Profiles.save_profiles(lab._drafts, "/private/tmp/project-card-wood-dark.cfg") == OK, "保存到临时配置后共用入口可读取新样式")
	shell.close_attack_effect_lab()
	await process_frame
	await _check_real_battle(CardData.ElementType.WOOD, 3, 1)
	await _check_real_battle(CardData.ElementType.DARK, 3, 1)
	await _check_real_battle(CardData.ElementType.DARK, 5, 3)
	var scratch: String = main.run_save_path
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(scratch)
	print("Wood/dark sample failures: ", failures)
	quit(1 if failures else 0)


func _check_timing(lab: AttackEffectLab, profile: Dictionary) -> void:
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		hits = 0
		var delay := Timing.calculate_impact_delay(profile, variant)
		var visual := Renderer.play(lab.effect_layer, PackedVector2Array([Vector2(100, 240), Vector2(100, 60)]), profile, Color.WHITE, Color.WHITE, func(): hits += 1, 1.0, variant, delay) as SampleVisual
		Renderer.set_flight_paused(visual, true)
		var tween := visual.get_meta("flight_tween") as Tween
		var frame := visual.sprite.frame
		await create_timer(0.02).timeout
		check(visual.sprite.frame == frame and hits == 0, "暂停时手绘帧与命中同时停止")
		tween.custom_step(delay - 0.001)
		check(hits == 0 and (profile.mask_kind != &"dark_slash" or not visual.sprite.visible), "逻辑命中前暗斩不提前闪击，木不提前结算")
		tween.custom_step(0.002)
		check(hits == 1 and visual.sprite.visible, "样板%s在变速%d的真实命中时刻显现且只回调一次" % [profile.mask_kind, variant])
		var elapsed := tween.get_total_elapsed_time()
		Renderer.set_flight_speed(visual, 3.0)
		tween.custom_step(0.01)
		check(is_equal_approx(tween.get_total_elapsed_time() - elapsed, 0.03), "原画动画随三倍速推进")
		tween.custom_step(2.0)
		check(hits == 1, "原画残影消散不追加命中")
		await process_frame
		check(not is_instance_valid(visual), "原画节点结束自动释放")


func _record_lab(lab: AttackEffectLab, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var directory := "/private/tmp/project-card-wood-dark-motion"
	DirAccess.make_dir_recursive_absolute(directory)
	lab._play_preview(true)
	for index: int in 30:
		await create_timer(0.04).timeout
		await RenderingServer.frame_post_draw
		var frame := lab.get_viewport().get_texture().get_image()
		frame.get_region(Rect2i(lab.preview_canvas.get_global_rect())).save_png("%s/%s-%02d.png" % [directory, label, index])
		if index == 10: frame.save_png("%s/%s-lab.png" % [directory, label])


func _make_owned(element: int, health: int = 2000, cooldown: float = 8.0) -> OwnedCard:
	var definition: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
	definition.effect_ids.clear()
	definition.keywords.clear()
	definition.cooldown_seconds = cooldown
	definition.max_health = health
	definition.base_value = 5
	var owned: OwnedCard = main.owned_card_collection.create_card(definition)
	owned.resolved_runes.assign([element, element, element])
	owned.rune_revealed.assign([true, true, true])
	return owned


func _check_real_battle(element: int, rune_count: int, expected: int) -> void:
	main.current_phase = main.GamePhase.PREPARE
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]: row.clear_squads()
	main.resource_board_state = ResourceBoardState.new()
	main.resource_board_state.initialize_level(&"wood_dark_test", RandomNumberGenerator.new())
	var left := _make_owned(element)
	var squad := SquadData.from_owned_card(left)
	if rune_count == 5:
		var right := _make_owned(element)
		squad = SquadData.from_cards([left.get_battlefield_card(), right.get_battlefield_card()], SquadData.TwoCardLayout.EXPANDED)
		squad.bind_owned_card(left.get_battlefield_card(), left)
		squad.bind_owned_card(right.get_battlefield_card(), right)
	main.front_row.add_squad(squad, 0)
	var dummy: CardData = preload("res://resources/cards/ember_squire.tres").duplicate(true)
	dummy.effect_ids.clear()
	dummy.keywords.clear()
	dummy.runes.clear()
	dummy.max_health = 2000
	dummy.base_value = 0
	dummy.cooldown_seconds = 99
	main.enemy_front_row.add_squad(SquadData.from_card(dummy), 0)
	if element == CardData.ElementType.WOOD:
		main.enemy_back_row.add_squad(SquadData.from_card(dummy.duplicate(true)), 0)
	# 等真实行容器完成居中和入场位移，再读取卡位坐标并开始战斗。
	await create_timer(0.30).timeout
	launched.clear()
	sample_nodes.clear()
	var controller: BattleController = main.battle_controller
	if not controller.projectile_launched.is_connected(_collect_projectile): controller.projectile_launched.connect(_collect_projectile)
	check(main.start_battle(73015, false), "真实Main开始%d枚元素样板战斗" % rune_count)
	for step: int in 260:
		controller.advance_time(0.05)
		if launched.size() >= expected: break
	check(launched.size() == expected and sample_nodes.size() == expected, "真实控制器产生%d次副效果，画面恰好对应%d个原画节点" % [expected, expected])
	var impacts_before: int = main.battle_effect_layer.find_children("ElementImpact*", "Node2D", false, false).size()
	var targets: Dictionary = {}
	for index: int in sample_nodes.size():
		var visual := sample_nodes[index]
		var event := launched[index]
		targets[event.target] = true
		var slot: BoardSlot = main._battle_state_slots[event.target]
		var inverse: Transform2D = main.battle_effect_layer.get_global_transform_with_canvas().affine_inverse()
		var to: Vector2 = inverse * slot.get_global_rect().get_center()
		var tween := visual.get_meta("flight_tween") as Tween
		tween.pause()
		tween.custom_step(event.projectile_impact_delay + 0.03)
		if element == CardData.ElementType.DARK:
			check(visual.position.is_equal_approx(to), "正式暗连击固定在原目标，未沿旧弹道飞行")
		else:
			var anchor: BoardSlot = main._battle_state_slots[event.anchor]
			check(visual.position.is_equal_approx(inverse * anchor.get_global_rect().get_center()), "正式木刺从承载目标出发，沿跨排方向播放")
	if element == CardData.ElementType.DARK: check(targets.size() == 1, "多次真实暗连击仍锁定同一个原目标")
	check(main.battle_effect_layer.find_children("ElementImpact*", "Node2D", false, false).size() == impacts_before, "手绘副效果命中不额外叠加旧菱形冲击，普通主攻击保持原表现")
	await capture("wood-dark-real-%d-%d" % [element, rune_count])
	main._clear_battle_presentation_for_preparation()
	controller.clear_battle()
	main.current_phase = main.GamePhase.PREPARE
	await process_frame


func _collect_projectile(event: BattleEffectEvent) -> void:
	if event.is_base_action or event.visual_kind not in [&"wood_pierce", &"dark_repeat"]: return
	launched.append(event)
	var visual := main.battle_effect_layer.get_child(-1) as SampleVisual
	if visual != null:
		Renderer.set_flight_paused(visual, true)
		sample_nodes.append(visual)
