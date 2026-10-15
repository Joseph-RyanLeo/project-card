extends "res://tests/card_pack_opening_test.gd"

const Settings = preload("res://scripts/ui/pack_opening_effect_settings.gd")

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("开包调整器验收超时"); quit(1))
	Settings.save_path = "/private/tmp/project-card-pack-tuner-test-%d.cfg" % Time.get_ticks_usec()
	DirAccess.remove_absolute(Settings.save_path)
	Settings.reload()
	check(Settings.FIELDS.size() == 54 and _defaults_match(), "54个参数集中声明且无配置时使用默认值")
	Settings.set_value("pixel", 0)
	Settings.set_value("shake_seconds", NAN)
	check(Settings.get_values().pixel == 1 and Settings.get_values().shake_seconds == .38, "非法输入限制范围且拒绝非有限值")
	Settings.reset_defaults()
	shell = DISPLAY.instantiate()
	shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main").short_maze_enabled = false
	root.add_child(shell)
	shell.apply_display_mode(DisplayScript.DisplayMode.WINDOW_2K if OS.get_cmdline_user_args().has("2k") else DisplayScript.DisplayMode.WINDOW_720P)
	await create_timer(.7).timeout
	main = shell.main_screen
	var collection: Dictionary = main.owned_card_collection.capture_state()
	var reward: Dictionary = main.run_reward_state.capture_state()
	var old_mode: int = main.process_mode
	await key(KEY_ESCAPE)
	check(main._escape_pause_menu.is_menu_open(), "Esc真实输入打开菜单")
	var entry: Button
	for button: Button in main._escape_pause_menu.find_children("*", "Button", true, false):
		if button.text == "开包特效调整器": entry = button
	check(is_instance_valid(entry), "暂停菜单包含开包特效调整器入口")
	await click(entry.get_global_rect().get_center())
	await create_timer(.7).timeout
	var tuner: Control = shell._pack_effect_tuner
	check(is_instance_valid(tuner) and not main.visible and not main._escape_pause_menu.is_processing_input(), "真实菜单按钮打开调整器并隔离原场景Esc")
	if not is_instance_valid(tuner): quit(1); return
	check(tuner.controls.size() == 54 and tuner.preview_shop.ordinary_shop_open, "全部滑块与免费预览商店加载完成")
	await capture("pack-tuner-layout")
	var tabs: TabContainer = tuner.find_child("ParameterTabs", true, false)
	tabs.current_tab = 1
	await process_frame
	var slider: HSlider = tuner.controls.tear_shake_pixels.slider
	var rect := slider.get_global_rect()
	await click(Vector2(rect.position.x + rect.size.x * .3, rect.get_center().y))
	check(slider.value != 1 and is_equal_approx(tuner.controls.tear_shake_pixels.spin.value, slider.value) and is_equal_approx(Settings.get_values().tear_shake_pixels, slider.value), "真实点击滑块联动数值框及运行参数")
	var saved_amplitude: float = slider.value
	await click(tuner.find_child("SaveEffects", true, false).get_global_rect().get_center())
	check(FileAccess.file_exists(Settings.save_path), "保存按钮写独立特效配置")
	slider.value = 0
	await click(tuner.find_child("ReloadEffects", true, false).get_global_rect().get_center())
	check(slider.value == saved_amplitude, "重新载入恢复已保存值")
	await click(tuner.find_child("ResetEffects", true, false).get_global_rect().get_center())
	check(_defaults_match() and slider.value == 1, "恢复默认重置全部参数及控件")
	var config := ConfigFile.new()
	config.load(Settings.save_path)
	check(is_equal_approx(config.get_value("opening", "tear_shake_pixels"), saved_amplitude), "默认重置只影响草稿，保存前不覆盖磁盘配置")
	tuner.controls.inspect_seconds.slider.value = .6
	tuner.controls.return_seconds.slider.value = .6
	var tile: Control = tuner.preview_shop.ordinary_shop_offer_list.find_child("ShopOffer_0", true, false)
	await click(tuner.preview_container.get_global_transform_with_canvas() * tile.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await create_timer(.15).timeout
	check(is_instance_valid(tuner.preview_shop._card_pack_opening) and tuner.preview_shop._card_pack_opening.cards.is_empty() and tuner.preview_shop._card_pack_opening.phase == CardPackOpening.Phase.ENLARGING, "缩小预览内真实右键拿起商品，使用新的检视时长")
	await create_timer(.7).timeout
	check(tuner.preview_shop._card_pack_opening.phase == CardPackOpening.Phase.SEALED, "新的拿起时长结束后允许包装检视")
	await click(tuner.preview_container.get_global_transform_with_canvas() * Vector2(640, 340), MOUSE_BUTTON_RIGHT)
	await create_timer(.15).timeout
	check(tuner.preview_shop._inspection_closing and is_instance_valid(tuner.preview_shop._inspection_overlay), "预览内真实右键放回商品，使用新的回店时长")
	await create_timer(.7).timeout
	check(not is_instance_valid(tuner.preview_shop._inspection_overlay), "放回时长结束后真实商品恢复陈列")
	tuner.controls.inspect_seconds.slider.value = .25
	tuner.controls.return_seconds.slider.value = .2
	tuner.controls.auto_tear_seconds.slider.value = 2
	await click(tuner.find_child("PreviewNormal", true, false).get_global_rect().get_center())
	await create_timer(.5).timeout
	var sequence: CardPackOpening = tuner.preview_shop._card_pack_opening
	check(is_instance_valid(sequence) and sequence.phase == CardPackOpening.Phase.TEARING and not sequence.has_rare, "普通预览购买真实五张包，使用新的两秒自动撕包时长")
	check(sequence.effects == Settings.get_values() and sequence.tear_art.effects == sequence.effects and sequence.glow.effects == sequence.effects, "控制器、撕口与光效共享同一参数来源")
	slider.value = 0
	await process_frame
	await process_frame
	check(sequence.surface.effect.get_shader_parameter("visual_offset") == Vector2.ZERO, "撕包中滑块归零立即停止包装颤抖")
	slider.value = 2
	await create_timer(.08).timeout
	var offset: Vector2 = sequence.surface.effect.get_shader_parameter("visual_offset")
	check(not offset.is_zero_approx() and (offset * sequence.surface.scale).length() <= 2.83, "撕包中加大幅度实时作用于4倍显示后的着色器位移")
	await click(tuner.find_child("PreviewShop", true, false).get_global_rect().get_center())
	await process_frame
	check(not is_instance_valid(tuner.preview_shop._inspection_overlay) and tuner.preview_shop.position == Vector2.ZERO, "回商店可停止未完成动画并归位")
	tuner.controls.auto_tear_seconds.slider.value = .2
	tuner.controls.burst_seconds.slider.value = 1
	tuner.controls.rare_reveal_seconds.slider.value = 2
	tuner.controls.halo_radius.slider.value = 420
	tuner.controls.flash_intensity.slider.value = .75
	await click(tuner.find_child("PreviewRare", true, false).get_global_rect().get_center())
	await create_timer(.65).timeout
	sequence = tuner.preview_shop._card_pack_opening
	check(sequence.has_rare and sequence.phase == CardPackOpening.Phase.BURST and sequence.glow.strength > 0, "传奇预览包含IV卡并播放可调金光")
	await capture("pack-tuner-burst")
	await create_timer(1).timeout
	await click(tuner.find_child("PreviewHalo", true, false).get_global_rect().get_center())
	await process_frame
	check(sequence.current_index == 4 and sequence.glow.card_reveal and sequence.glow.rare and sequence.glow.strength > .8 and sequence.glow.effects.halo_radius == 420, "IV光环按钮跳至真实IV卡并使用新的半径与持续时间")
	check(sequence.surface.effect.get_shader_parameter("flash_intensity") == .75, "IV卡反光强度实时同步着色器")
	await capture("pack-tuner-halo")
	await create_timer(.7).timeout
	await click(tuner.find_child("PreviewHalo", true, false).get_global_rect().get_center())
	await process_frame
	check(sequence.glow.strength > .9, "重复IV光环可重新播放，不被上一段衰减覆盖")
	# 把绘制参数推到滑块两端，检查实际画布；0宽／0高不能提交退化多边形。
	for field: Dictionary in Settings.FIELDS:
		Settings.set_value(field.key, field.min)
	sequence.glow.card_reveal = false
	sequence.glow.strength = 1
	await RenderingServer.frame_post_draw
	check(sequence.glow.effects.beam_width == 0 and sequence.glow.effects.pixel == 1, "最小边界可渲染，光束宽度归零和粒子数量归零合法")
	for field: Dictionary in Settings.FIELDS:
		Settings.set_value(field.key, field.max)
	sequence.glow.card_reveal = true
	sequence.glow.strength = 1
	await RenderingServer.frame_post_draw
	check(sequence.glow.effects.halo_count == 100 and sequence.glow.effects.halo_radius == 650, "最大边界可渲染，100点大光环与颜色上限合法")
	var scratch: String = tuner.preview_shop.run_save_path
	await key(KEY_ESCAPE)
	await process_frame
	check(not shell.is_pack_effect_tuner_open() and main.visible and main.process_mode == old_mode and main._escape_pause_menu.is_processing_input(), "Esc在预览中退出，恢复原游戏处理和输入")
	check(is_equal_approx(Settings.get_values().tear_shake_pixels, saved_amplitude) and is_equal_approx(Settings.get_values().auto_tear_seconds, .35), "退出丢弃草稿，保留上次成功保存的参数")
	check(main.owned_card_collection.capture_state() == collection and main.run_reward_state.capture_state() == reward and not FileAccess.file_exists(scratch), "测试购买不影响本局收藏金币，临时交易存档清理")
	check(not main._escape_pause_menu.is_menu_open(), "退出Esc不穿透重新打开原菜单")
	# 测试商店也可通过自己的Esc菜单进入，返回时保留测试商店会话。
	check(shell.open_rare_shop(), "再次打开独立稀有商店")
	await create_timer(.5).timeout
	var rare_shop: Control = shell._rare_shop
	main = rare_shop
	await key(KEY_ESCAPE)
	check(rare_shop._escape_pause_menu.is_menu_open(), "稀有商店Esc同样提供暂停菜单")
	for button: Button in rare_shop._escape_pause_menu.find_children("*", "Button", true, false):
		if button.text == "开包特效调整器": entry = button
	await click(entry.get_global_rect().get_center())
	await create_timer(.6).timeout
	check(shell.is_pack_effect_tuner_open() and not rare_shop.visible, "从稀有商店进入调整器，来源场景隔离")
	await key(KEY_ESCAPE)
	await process_frame
	check(not shell.is_pack_effect_tuner_open() and shell._rare_shop == rare_shop and rare_shop.visible and rare_shop._escape_pause_menu.is_processing_input(), "退出调整器返回原稀有商店")
	shell.close_rare_shop()
	await process_frame
	Settings.reset_defaults()
	Settings.save()
	Settings.reload()
	check(_defaults_match(), "完整默认配置可保存并重新载入")
	DirAccess.remove_absolute(Settings.save_path)
	shell.queue_free()
	await process_frame
	print("Pack effect tuner failures: ", failures)
	quit(1 if failures else 0)

func _defaults_match() -> bool:
	for field: Dictionary in Settings.FIELDS:
		if not is_equal_approx(Settings.get_values()[field.key], field.default):
			print("默认值不符：", field.key, " actual=", Settings.get_values()[field.key], " expected=", field.default, " path=", Settings.save_path)
			return false
	return true
