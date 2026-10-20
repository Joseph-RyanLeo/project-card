extends "res://tests/board_ui_fixes_20261019_test.gd"

const CLEARANCE_SAVE := "/private/tmp/project-card-collection-clearance-save.json"


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = CLEARANCE_SAVE
	root.add_child(shell)
	if "--2k" in OS.get_cmdline_user_args(): shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	_deal("loose_coins")
	main.set_world_view(main.WorldView.COLLECTION, false)
	await create_timer(0.4).timeout
	var page: Control = main.get_node("%RegularLeftPageArt")
	var rest_positions: Dictionary = {}
	for slot: Control in main._get_collection_card_slots():
		var card: CardView = slot.get_child(0)
		var icon: Control = card.get_node("TopRow/ActionIcon")
		rest_positions[card] = card.global_position
		check(icon.get_global_rect().position.y >= page.global_position.y + 10, "普通状态下行动图标和装备箭头留在纸页内，避开筛选标签")
		check(card.get_global_rect().end.y <= page.get_global_rect().end.y, "第二排卡牌仍完整位于纸页内")
		await move_pointer(card.get_global_rect().get_center())
		await create_timer(0.25).timeout
		check(shell.internal_viewport.gui_get_hovered_control() == card, "新位置实际悬停卡面")
		check(is_equal_approx(card.global_position.y, rest_positions[card].y - 7), "保留原有7像素悬停上浮")
		check(icon.get_global_rect().position.y >= page.global_position.y + 3, "悬停后顶部图标仍与筛选标签分开")
	await move_pointer(Vector2(700, 300))
	await create_timer(0.25).timeout
	var tab: Control = main.card_type_filter_tabs.get_child(0)
	await _click(tab)
	await create_timer(0.3).timeout
	check(tab.global_position.y - main.world_content.position.y == 735, "筛选标签保持刚确认的抽出位置")
	await _click(tab)
	await create_timer(0.3).timeout
	check(tab.global_position.y - main.world_content.position.y == 743, "筛选标签保持刚确认的常规位置")
	check(main.get_node("%BookPanel").global_position.y - main.world_content.position.y == 748 and main.world_content.position.y == -387, "书本和视角位置保持不变")
	await capture_alignment("collection_clearance")
	await verify_resource_drag()
	paused = false
	shell.queue_free()
	await process_frame
	DirAccess.remove_absolute(CLEARANCE_SAVE)
	print("收藏顶部留白：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
