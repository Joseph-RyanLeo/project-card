extends "res://tests/event_cards_test.gd"


func check_position(expected: Vector2, message: String) -> void:
	check(main.world_content.position.is_equal_approx(expected), message)


func _run() -> void:
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.run_save_path = "/private/tmp/project-card-view-rebound-save.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await process_frame
	maze = main.maze_controller
	maze.new_run(20261019)
	check(maze.choose_talent("sentry_guard"), "真实迷宫初始天赋选择")
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check_position(Vector2(0, -3), "上半视角起点保持")
	var hero_position: Vector2 = maze._status._hero_panel.position
	main.set_world_view(main.WorldView.COLLECTION)
	var down: Tween = main._view_tween
	down.pause()
	down.custom_step(0.32)
	check_position(Vector2(1, -373), "向下移动时世界越过目标6像素")
	down.custom_step(0.12)
	check_position(Vector2(1, -367), "下半视角回弹到准确终点")
	check(is_equal_approx(absf(main.world_content.position.y - (-3.0)), 364.0), "上下视角实际垂直距离364像素")
	check(maze._status._hero_panel.position == hero_position and hero_position == Vector2(1084, 749), "英雄世界位置不随新视角参数改动")
	check(maze._status._hero_panel.global_position == Vector2(1085, 382), "英雄与其余素材一起随摄像机向上1像素观察")
	main.set_world_view(main.WorldView.BATTLEFIELDS)
	var up: Tween = main._view_tween
	up.pause()
	up.custom_step(0.32)
	check_position(Vector2(0, 3), "向上移动时世界越过目标6像素")
	up.custom_step(0.12)
	check_position(Vector2(0, -3), "上半视角回弹到准确终点")
	main.set_world_view(main.WorldView.BATTLEFIELDS)
	check(main._view_tween == null, "重复设置当前视角不原地弹动")
	main.set_world_view(main.WorldView.COLLECTION)
	var interrupted: Tween = main._view_tween
	interrupted.pause()
	interrupted.custom_step(0.16)
	var midpoint: Vector2 = main.world_content.position
	main.set_world_view(main.WorldView.BATTLEFIELDS)
	check(not interrupted.is_valid() and main.world_content.position == midpoint, "中途反向取消旧动画并从当前位置连续开始")
	main._view_tween.pause()
	main._view_tween.custom_step(0.32)
	check_position(Vector2(0, 3), "反向切换仍正常越过目标")
	main._view_tween.custom_step(0.12)
	check_position(Vector2(0, -3), "反向切换最终没有残余偏移")
	main.set_world_view(main.WorldView.COLLECTION)
	main._view_tween.pause()
	main._view_tween.custom_step(0.32)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	check_position(Vector2(0, -3), "立即定位取消回弹并精确归位")
	await process_frame
	await process_frame
	check_position(Vector2(0, -3), "旧动画不会在后续帧拉回世界")
	await _click(main.player_avatar_button)
	check(main.current_world_view == main.WorldView.COLLECTION, "2K窗口原生点击人物进入下半视角")
	await create_timer(0.5).timeout
	check_position(Vector2(1, -367), "实际播放完整向下动画后终点正确")
	await _click(main.player_avatar_button)
	check(main.current_world_view == main.WorldView.BATTLEFIELDS, "2K窗口原生点击人物返回上半视角")
	await create_timer(0.5).timeout
	check_position(Vector2(0, -3), "实际播放完整向上动画后终点正确")
	shell.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute("/private/tmp/project-card-view-rebound-save.json")
	print("视角364像素与回弹：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
