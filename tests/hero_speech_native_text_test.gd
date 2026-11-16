extends SceneTree

## 实际窗口绘制：分辨率、头像跟随、暂停、淡出、释放及字形像素检查。
const DISPLAY = preload("res://scenes/GameDisplay.tscn")
const MODES = preload("res://scripts/ui/game_display.gd")
const DIR := "/private/tmp/project-card-speech-native-test"
const PREVIEWS := "res://docs/previews/d3_4_20261105"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error("FAIL: " + message)


func check_reveal_pixels(partial: Image, full: Image, text_rect: Rect2i) -> void:
	var visible_ink := 0
	var shifted_ink := 0
	for y: int in range(text_rect.position.y, text_rect.end.y):
		for x: int in range(text_rect.position.x, text_rect.end.x):
			if partial.get_pixel(x, y).r >= 0.4: continue
			visible_ink += 1
			if full.get_pixel(x, y).r >= 0.4: shifted_ink += 1
	check(visible_ink > 0 and shifted_ink == 0, "逐字阶段已显示的字形与完整台词像素对齐")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("本专项需要真实窗口，验证实际字体绘制分辨率与像素。")
		quit(1)
		return
	create_timer(60).timeout.connect(func(): push_error("气泡原生文字专项超时"); quit(1))
	DirAccess.make_dir_recursive_absolute(DIR)
	var shell = DISPLAY.instantiate()
	shell.run_slots.directory = DIR
	var main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = DIR.path_join("run.json")
	root.add_child(shell)
	await process_frame
	var speech = main._hero_speech
	for mode: int in [MODES.DisplayMode.WINDOW_720P, MODES.DisplayMode.WINDOW_1080P, MODES.DisplayMode.WINDOW_2K]:
		shell.apply_display_mode(mode)
		await create_timer(0.2).timeout
		main.set_world_view(main.WorldView.BATTLEFIELDS, false)
		speech.say("运气不错，这迷宫虽然危险，还是藏着不少好东西。", main.player_avatar_button, 0, null, true)
		await process_frame
		var scale_value: float = shell.render_container.scale.x
		print("SPEECH_METRICS: ", scale_value, " logical=", speech.size, " window=", speech._visual.get_rect(), " label=", speech.text_label.size)
		check(speech.text_label.get_parent() == speech._visual and speech._visual.get_parent().custom_viewport == root, "文字的CanvasLayer直接提交给根窗口绘制")
		check(speech.text_label.get_theme_font_size("font_size") == roundi(14 * scale_value) and speech.text_label.scale == Vector2.ONE, "按真实窗口像素选字号，不拉伸文字控件")
		check(is_equal_approx(speech.size.x, 178.0) and is_equal_approx(speech._background.scale.x, scale_value), "底图保持178逻辑像素并独立像素缩放")
		check(speech._visual.get_rect().encloses(speech.text_label.get_global_rect()), "完整文字位于气泡内")
		check(speech.text_label.get_minimum_size().y <= speech.text_label.size.y + 1, "多行文字没有底部裁切")
		var before: Vector2 = speech._visual.position
		main.player_avatar_button.position -= Vector2(17, 9)
		await process_frame
		await process_frame
		check(not speech._visual.position.is_equal_approx(before), "根窗口气泡实际跟随头像移动")
		main.player_avatar_button.position += Vector2(17, 9)
		await process_frame
		await speech._text_reveal.finished
		check(speech.text_label.visible_characters == speech.text_label.get_total_character_count(), "原逐字显示完整结束")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			var rect: Rect2i = Rect2i(speech.text_label.get_global_rect())
			speech.text_label.visible_characters = 5
			await RenderingServer.frame_post_draw
			check_reveal_pixels(root.get_texture().get_image(), frame, rect)
			speech.text_label.visible_characters = speech.text_label.get_total_character_count()
			frame.save_png(PREVIEWS.path_join("10_speech_native_%d.png" % root.size.x))
			if mode == MODES.DisplayMode.WINDOW_2K:
				var best_repeat := 0.0
				for phase: int in 2:
					var equal := 0
					var total := 0
					for y: int in range(rect.position.y, rect.end.y):
						for x: int in range(rect.position.x + phase, rect.end.x - 1, 2):
							var a := frame.get_pixel(x, y)
							var b := frame.get_pixel(x + 1, y)
							if minf(a.r, b.r) < 0.6:
								total += 1
								if a == b: equal += 1
					best_repeat = maxf(best_repeat, float(equal) / maxi(total, 1))
				print("TEXT_TWO_PIXEL_REPEAT: ", best_repeat)
				check(best_repeat < 0.9, "2K字形不再呈整齐的两像素重复块")
		paused = true
		await create_timer(0.1).timeout
		check(speech._visual.is_visible_in_tree(), "教学暂停期间根窗口文字仍可见")
		paused = false
		speech.dismiss()
		await create_timer(speech.FADE_SECONDS * 0.5).timeout
		check(speech._visual.modulate.a < 1 and speech._visual.modulate.a > 0, "底图与文字共用平滑淡出")
		await create_timer(speech.FADE_SECONDS).timeout
		check(not speech._visual.visible, "收起后根窗口不残留文字")
	speech.say("准备出发。", main.player_avatar_button, 0, null, true)
	main.hide()
	await process_frame
	check(not speech._visual.visible, "离开主界面立即隐藏独立绘制层")
	var visual: WeakRef = weakref(speech._visual)
	shell.free()
	await process_frame
	check(visual.get_ref() == null, "释放原场景时一并释放根窗口气泡")
	print("Hero speech native text: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
