extends "res://tests/collection_card_tilt_test.gd"

## 实际收藏GPU：未悬停亮纹、普通卡隔离、悬停接管与缓存复用。
func screen() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	return root.get_texture().get_image()

func changed(a: Image, b: Image) -> int:
	var count := 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) > 0.025: count += 1
	return count

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("收藏静止亮纹专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-rest-flash.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.8).timeout
	main.set_world_view(main.WorldView.COLLECTION, false)
	await _motion(Vector2(1270, 700))
	var definition := load("res://resources/cards/militia.tres") as CardData
	var owned: OwnedCard = main.owned_card_collection.create_card(definition, main.ordinary_shop_service.rng)
	owned.is_new = false
	var view := _show_owned(owned)
	var physical: Transform2D = shell.render_container.get_global_transform_with_canvas() * view.get_global_transform_with_canvas()
	var area := Rect2i(Vector2i((physical * -InspectionCardSurface.PADDING).round()), Vector2i((view.card_size + InspectionCardSurface.PADDING * 2) * 2))
	var grid := Image.create(area.size.x * 6, area.size.y * 3, false, Image.FORMAT_RGBA8)
	var random_state: int = main.ordinary_shop_service.rng.state
	for art: int in Appearance.Art.size():
		owned.art_finish = art as Appearance.Art
		for face: int in Appearance.Surface.size():
			owned.surface_finish = face as Appearance.Surface
			view.set_owned_card(owned)
			var renderer = view._finish_controller
			var foil := face in [Appearance.Surface.SILVER, Appearance.Surface.GOLD, Appearance.Surface.RAINBOW, Appearance.Surface.FRACTURED]
			check((renderer != null and is_instance_valid(renderer._rest_flash) and renderer._rest_flash.visible) == foil, "银／金／彩／碎闪显示静止亮纹")
			check(not is_instance_valid(view._collection_hover_surface) and view.find_children("*", "SubViewport", true, false).is_empty(), "未悬停不启用检视或逐卡离屏画布")
			var visible := (await screen()).get_region(area)
			grid.blit_rect(visible, Rect2i(Vector2i.ZERO, area.size), Vector2i(face * area.size.x, art * area.size.y))
			if not foil: continue
			var light: TextureRect = renderer._rest_flash
			var mask := light.texture
			light.visible = false
			var unlit := (await screen()).get_region(area)
			check(changed(visible, unlit) > 500, "GPU实际显示未悬停亮面纹路")
			light.visible = true
			view._refresh()
			check(renderer._rest_flash == light and light.texture == mask, "重复刷新复用节点及轮廓遮罩")
			await hover(view, Vector2(0.7, 0.35))
			var pool = view._collection_hover_surface
			check(is_instance_valid(pool) and (not is_instance_valid(pool.card._finish_controller._rest_flash) or not pool.card._finish_controller._rest_flash.visible), "悬停显示层只绘制一次动态亮纹，不叠加静态亮纹")
			await _motion(Vector2(1270, 700))
			await create_timer(0.42).timeout
			var returned := (await screen()).get_region(area)
			check(not is_instance_valid(view._collection_hover_surface) and changed(visible, returned) == 0, "移开回正后恢复原静止亮纹")
	check(main.ordinary_shop_service.rng.state == random_state, "显示亮纹不消耗玩法随机流")
	grid.save_png("/private/tmp/project-card-collection-rest-finishes.png")
	shell.queue_free()
	await process_frame
	await process_frame
	print("收藏静止亮纹GPU：%d项，%d失败" % [assertions, failures])
	quit(1 if failures else 0)
