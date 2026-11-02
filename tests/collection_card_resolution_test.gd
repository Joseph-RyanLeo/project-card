extends "res://tests/collection_card_tilt_test.gd"

## 实际窗口像素A/B：相同卡面纹理，比较旧1倍主画布与新屏幕层投影。
const Finish = preload("res://scripts/ui/card_finish_preview.gd")

func shot() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()

func count_mixed_blocks(image: Image, rect: Rect2i) -> int:
	var result := 0
	for y: int in range((rect.position.y / 2) * 2, rect.end.y - 1, 2):
		for x: int in range((rect.position.x / 2) * 2, rect.end.x - 1, 2):
			var color := image.get_pixel(x, y)
			if color != image.get_pixel(x + 1, y) or color != image.get_pixel(x, y + 1) or color != image.get_pixel(x + 1, y + 1): result += 1
	return result

func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("收藏实际分辨率专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-collection-resolution.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.8).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	var pool = shell.get_collection_hover_surface()
	check(is_instance_valid(pool.card) and not pool.visible, "鼠标移入前已准备好可复用卡面与GPU材质")
	var identity := [pool.get_instance_id(), pool.card.get_instance_id(), pool.viewport.get_instance_id(), pool.effect.get_instance_id()]
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/shadowstep_assassin.tres"), main.ordinary_shop_service.rng)
	owned.art_finish = Appearance.Art.HOLOGRAPHIC
	var view := _show_owned(owned)
	await process_frame
	var entry_times: Array[float] = []
	for index: int in 8:
		await _motion(Vector2(1270, 700))
		await create_timer(0.42).timeout
		var began := Time.get_ticks_usec()
		await _motion(view.get_global_transform_with_canvas() * (view.card_size * Vector2(0.7, 0.4)))
		await RenderingServer.frame_post_draw
		entry_times.append((Time.get_ticks_usec() - began) / 1000.0)
		check(view._collection_hover_surface == pool and identity == [pool.get_instance_id(), pool.card.get_instance_id(), pool.viewport.get_instance_id(), pool.effect.get_instance_id()], "重复悬停复用同一节点、画布和材质")
	check(pool.get_viewport() == root and pool.get_viewport() != shell.internal_viewport and pool.scale == Vector2(2, 2), "最终透视在2K窗口像素层绘制，没有经过1倍主画布")
	print("复用后实际移入到首帧毫秒：", entry_times)
	pool.set_process(false)
	pool.set_pointer_force(Vector2(0.53, -0.22))
	var physical: Transform2D = pool.get_global_transform_with_canvas()
	var rect := Rect2i(Vector2i(physical.origin.floor()), Vector2i((pool.size * pool.scale).ceil())).intersection(Rect2i(Vector2i.ZERO, root.size))
	var current := await shot()
	var mixed_new := count_mixed_blocks(current, rect)
	# 同一份4倍卡面/同一投影材质临时送回旧1倍主画布，只改变最终绘制层。
	var legacy := TextureRect.new()
	legacy.texture = pool.texture
	legacy.material = pool.effect.duplicate()
	legacy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	legacy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	legacy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legacy.size = pool.size
	legacy.position = view.get_transform() * -pool.content_padding
	legacy.scale = view.scale
	legacy.z_index = view.z_index
	view.get_parent().add_child(legacy)
	pool.visible = false
	var previous := await shot()
	var mixed_old := count_mixed_blocks(previous, rect)
	check(mixed_old == 0 and mixed_new > 100, "GPU证实旧画面仅有2×2重复像素，新画面有实际屏幕单像素细节")
	print("相同投影2×2混色块：旧1倍输出=", mixed_old, "；实际分辨率=", mixed_new)
	var grid := Image.create(rect.size.x * 2, rect.size.y, false, Image.FORMAT_RGBA8)
	grid.blit_rect(previous, rect, Vector2i.ZERO)
	grid.blit_rect(current, rect, Vector2i(rect.size.x, 0))
	grid.save_png("/private/tmp/project-card-collection-resolution-compare.png")
	legacy.queue_free()
	pool.visible = true
	# 关闭光效和透视，仅检查1:1立绘原像素在2K中仍是清楚的2×2色块。
	pool.effect.set_shader_parameter("use_3d", false)
	pool.card._finish_controller.enabled = false
	pool.card._finish_controller.refresh()
	pool.card.art_background.visible = false
	var crisp := await shot()
	var art_origin: Vector2 = physical * Vector2(43, 53)
	var art_rect := Rect2i(Vector2i(art_origin.round()), Vector2i(100, 100))
	check(count_mixed_blocks(crisp, art_rect) == 0, "原画保持最近邻，没有用线性模糊来伪装平滑")
	pool.card.art_background.visible = true
	pool.card._finish_controller.enabled = true
	pool.effect.set_shader_parameter("use_3d", true)
	pool.card._finish_controller.refresh()
	pool.set_process(true)
	var cache_size := Finish._badge_asset_cache.size()
	await _motion(Vector2(1270, 700))
	await create_timer(0.42).timeout
	await hover(view, Vector2(0.5, 0.5))
	check(Finish._badge_asset_cache.size() == cache_size, "重复绑定图标和阴影使用缓存，不重复分配贴图")
	for mode: int in [shell.DisplayMode.WINDOW_720P, shell.DisplayMode.WINDOW_1080P, shell.DisplayMode.WINDOW_2K, shell.DisplayMode.ADAPTIVE_FULLSCREEN]:
		shell.apply_display_mode(mode)
		await create_timer(0.8 if mode != shell.DisplayMode.ADAPTIVE_FULLSCREEN else 1.5).timeout
		await hover(view, Vector2(0.6, 0.4))
		check(view._collection_hover_surface == pool and pool.scale.is_equal_approx(shell.render_container.scale), "切换窗口／实际全屏后复用画布并匹配真实输出倍率")
		var expected: Vector2 = shell.render_container.get_global_transform_with_canvas() * view.get_global_transform_with_canvas() * Vector2.ZERO
		check((pool.get_global_transform_with_canvas() * pool.content_padding).distance_to(expected) < 0.01, "不同窗口尺寸下卡面与原输入区域位置一致")
		print("显示模式 ", mode, " 实际窗口=", root.size, " 动态层倍率=", pool.scale)
	# 屏幕层不能盖过旧1倍画布内的暂停菜单与大检视。
	main._escape_pause_menu.open_menu()
	await process_frame
	await process_frame
	check(not pool.visible and view.modulate == Color.WHITE, "暂停菜单打开立即归还原卡，不残留屏幕层")
	main._escape_pause_menu.close_menu()
	shell.apply_display_mode(shell.DisplayMode.WINDOW_720P)
	await create_timer(0.7).timeout
	shell.queue_free()
	await process_frame
	await process_frame
	print("收藏复用与实际分辨率：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
