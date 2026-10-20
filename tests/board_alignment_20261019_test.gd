extends "res://tests/board_revision_20261019_test.gd"

const ALIGN_SAVE := "/private/tmp/project-card-board-alignment-save.json"


func capture_alignment(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var result: Image = shell.internal_viewport.get_texture().get_image()
	if "--capture-alignment" in OS.get_cmdline_user_args():
		result.save_png("/private/tmp/project-card-alignment-%s.png" % label)
	return result


func press_key(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func verify_talents() -> void:
	maze.new_run(20261019)
	var hud: Control = maze._status
	for slot: ColorRect in hud._talent_slots:
		check(slot.color == Color("8c8d8e"), "新局天赋位保持原稿灰色")
	check(maze.hero.grant_experience("alignment_real_progression", 12), "真实经验系统解锁本阶段1级和4级天赋")
	maze.refresh()
	await process_frame
	var chosen_names: Array[String] = []
	for index: int in 2:
		var id: String = maze.hero.get_pending_choices()[0]
		chosen_names.append(maze.rewards.config.talents[id].display_name)
		var button: Button
		for child: Node in maze._body.get_children():
			if child is Button:
				button = child
				break
		check(is_instance_valid(button), "真实升级流程显示对应天赋选择")
		await _click(button)
		check(maze.hero.selected_talents.get(str([1, 4, 7, 10][index])) == id, "真实点击提交当前档天赋")
		check(hud._talent_slots[index].color == hud.TALENT_COLORS[index] and chosen_names[index] in hud._talent_slots[index].tooltip_text, "对应色块点亮且显示已选效果")
	for talent_name: String in chosen_names:
		check(talent_name in main.player_avatar_button.tooltip_text, "英雄悬停包含全部已选天赋")
	main.set_world_view(main.WorldView.COLLECTION, false)
	for index: int in [2, 3]:
		check(hud._talent_slots[index].color == Color("8c8d8e") and "尚未选择" in hud._talent_slots[index].tooltip_text, "未开放的7／10级天赋保持灰色")
	await move_pointer(hud._talent_slots[1].get_global_rect().get_center())
	await create_timer(0.8).timeout
	check(shell.internal_viewport.gui_get_hovered_control() == hud._talent_slots[1], "新位置天赋色块实际可悬停")
	await capture_alignment("talent_hover")
	await move_pointer(main.player_avatar_button.get_global_rect().get_center())
	await create_timer(0.8).timeout
	await capture_alignment("hero_hover")
	check(main.save_run_to_path(ALIGN_SAVE) == OK and main.load_run_from_path(ALIGN_SAVE), "本阶段已选天赋可真实磁盘保存和恢复")
	for index: int in 2:
		check(hud._talent_slots[index].color == hud.TALENT_COLORS[index] and chosen_names[index] in hud._talent_slots[index].tooltip_text, "读档恢复天赋颜色和悬停说明")


func verify_search_and_pixels() -> void:
	main.set_world_view(main.WorldView.COLLECTION, false)
	await move_pointer(Vector2(700, 300))
	await create_timer(0.1).timeout
	var image := await capture_alignment("collection")
	var texture: Image = main.search_filter_art.texture.get_image()
	var checked := 0
	var exact := true
	# 用真实渲染结果和旧图左右边缘逐像素比较，避免缩窄时拉坏图标。
	for x: int in 33:
		var source_x := x if x < 17 else 96 + x - 17
		var target_x := x if x < 17 else 67 + x - 17
		for y: int in range(10, 24):
			var color := texture.get_pixel(source_x, y)
			if color.a < 1.0: continue
			checked += 1
			exact = exact and image.get_pixel(908 + target_x, 357 + y).is_equal_approx(color)
	check(checked > 200 and exact, "83像素搜索框两侧边框图标与旧素材原像素完全一致")
	await _click(main.search_edit)
	check(shell.internal_viewport.gui_get_focus_owner() == main.search_edit, "新位置输入区获得真实键盘焦点")
	for character: String in ["火", "枪"]:
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.pressed = true
		root.push_input(event, true)
	await process_frame
	await _click(main.search_button)
	check(main.search_query == "火枪" and not main._get_collection_card_slots().is_empty(), "缩窄搜索框仍可真实输入并搜索拥有卡牌")
	await _click(main.clear_search_button)
	check(main.search_query.is_empty() and main.search_edit.text.is_empty(), "右侧清空按钮移动后实际可点")
	var first_slot: Control = main._get_collection_card_slots()[0]
	check(first_slot.get_child(0).global_position.is_equal_approx(Vector2(246, 387)), "首张实际卡面含内部留白后对齐原稿(266,777)")
	await capture_alignment("collection_cards")


func verify_esc_volume() -> void:
	var slider: HSlider = main.battle_volume_slider
	check(not slider.is_visible_in_tree() and main.get_node("WorldContent/PlayerBoardSection").get_node_or_null("BattleVolumeSlider") == null, "音量仅位于Esc菜单内")
	await press_key(KEY_ESCAPE)
	check(paused and slider.is_visible_in_tree(), "Esc暂停后显示实际音量滑条")
	var old: float = slider.value
	await move_pointer(slider.get_global_rect().position + Vector2(slider.size.x * 0.8, slider.size.y * 0.5))
	await press_pointer(true)
	await press_pointer(false)
	check(slider.value > old and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")), slider.value / 100.0), "暂停时真实鼠标调整音量并写入音频总线")
	await capture_alignment("esc_volume")
	await press_key(KEY_ESCAPE)
	check(not paused and not slider.is_visible_in_tree(), "关闭Esc恢复游戏并隐藏音量")


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = ALIGN_SAVE
	root.add_child(shell)
	if "--2k" in OS.get_cmdline_user_args(): shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	await create_timer(0.55).timeout
	var frame: Control = main.world_content.get_node("BattlefieldWoodPad")
	check(frame.position == Vector2(189, -3) and frame.size == Vector2(902, 739), "主棋盘原生大小，顶部三像素位于世界外")
	await capture_alignment("battlefields")
	await verify_search_and_pixels()
	await verify_resource_drag()
	await verify_esc_volume()
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await verify_talents()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(ALIGN_SAVE)
	print("原稿位置与交互：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
