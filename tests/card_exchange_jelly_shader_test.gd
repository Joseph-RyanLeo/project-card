extends "res://tests/d2_8_card_exchange_ui_test.gd"

## 用真实卡面GPU像素和正式置换事务验证形变，避免只核对Shader参数却漏掉未渲染的问题。
const ANIMATION = preload("res://scripts/ui/card_exchange_animation.gd")

func run() -> void:
	create_timer(70.0).timeout.connect(func(): push_error("融合果冻Shader专项超时"); quit(1))
	shell = DISPLAY.instantiate()
	main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-jelly-shader-save.json"
	root.add_child(shell)
	shell.apply_display_mode(shell.DisplayMode.WINDOW_2K)
	await create_timer(0.5).timeout
	await _check_gpu_shape()
	main.run_reward_state.gold = 200
	main._toggle_ordinary_shop()
	await create_timer(0.4).timeout
	main._open_shop_card_services()
	main.ordinary_shop_service.rng.seed = 20261022
	var materials := add_materials(CardData.Rarity.I)
	select_materials(materials)
	await create_timer(0.35).timeout
	var count_before: int = main.owned_card_collection.size()
	await click(main._shop_exchange_confirm.get_global_rect().get_center())
	var animation: Control = main._shop_exchange_animation
	check(is_instance_valid(animation), "真实点击融合按钮启动正式演出")
	if not is_instance_valid(animation): quit(1); return
	var count_committed: int = main.owned_card_collection.size()
	var rng_committed: int = main.ordinary_shop_service.rng.state
	check(count_committed == count_before - 2 and FileAccess.file_exists(main.run_save_path), "果冻演出之前已完成三换一及保存")
	await _wait_stage(animation, &"arranged")
	check(animation._materials.all(func(view: Control): return is_zero_approx(_parameter(animation._effect(view), &"jelly_amount"))), "并排与蓄力阶段卡牌不提前挤压")
	await _wait_stage(animation, &"fuse")
	check(animation._materials.all(func(view: Control): return is_equal_approx(float(animation._effect(view).get_shader_parameter("white_amount")), 1.0) and is_equal_approx(float(animation._effect(view).get_shader_parameter("jelly_amount")), 1.0)), "白色剪影重合时三张材料达到果冻挤压峰值")
	await capture("jelly-fuse")
	await _wait_stage(animation, &"reveal")
	check(is_equal_approx(float(animation._effect(animation._reward).get_shader_parameter("jelly_amount")), 1.0), "新卡接续材料的挤压幅度，替换瞬间不跳回正常形状")
	await create_timer(0.06).timeout
	var phase: float = float(animation._effect(animation._reward).get_shader_parameter("jelly_progress"))
	check(phase > 0.0 and phase < 1.0, "新卡揭晓时，现有Tween推进Shader回弹进度")
	await capture("jelly-rebound")
	await _wait_stage(animation, &"display")
	check(is_equal_approx(float(animation._effect(animation._reward).get_shader_parameter("jelly_progress")), 1.0) and is_zero_approx(float(animation._effect(animation._reward).get_shader_parameter("white_amount"))) and animation._reward.scale == Vector2(4, 4), "展示阶段完全复原，恢复原色4倍卡面")
	await animation.finished
	await process_frame
	check(main._shop_exchange_animation == null and main.owned_card_collection.size() == count_committed and main.ordinary_shop_service.rng.state == rng_committed and main.run_reward_state.gold == 200, "回弹及飞回不重复结算，也不消耗金币或业务随机数")
	# 重新播放，通过真实连续点击验证回弹沿用整场加速和取消清理。
	main._open_shop_card_services()
	select_materials(add_materials(CardData.Rarity.I))
	await create_timer(0.35).timeout
	main._execute_shop_exchange()
	animation = main._shop_exchange_animation
	var fast_count: int = main.owned_card_collection.size()
	var fast_rng: int = main.ordinary_shop_service.rng.state
	for index: int in 6: await click(Vector2(70, 680))
	check(animation._click_speed.speed == 8.0, "果冻演出仍可连续点击加速到8倍")
	await animation.finished
	await process_frame
	check(main._shop_exchange_animation == null and main.owned_card_collection.size() == fast_count and main.ordinary_shop_service.rng.state == fast_rng, "8倍演出正常完成且不重复置换")
	main._open_shop_card_services()
	select_materials(add_materials(CardData.Rarity.I))
	await create_timer(0.35).timeout
	main._execute_shop_exchange()
	animation = main._shop_exchange_animation
	await _wait_stage(animation, &"fuse")
	main._close_shop_card_services()
	await process_frame
	check(main._shop_exchange_animation == null and not is_instance_valid(animation), "果冻峰值期间关闭服务页释放Shader快照与演出")
	DirAccess.remove_absolute(main.run_save_path)
	shell.queue_free()
	await process_frame
	print("融合果冻Shader：%d项检查，%d失败" % [assertions, failures])
	quit(1 if failures else 0)

func _wait_stage(animation: Control, expected: StringName) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(animation) and animation.stage != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(animation) and animation.stage == expected, "演出到达阶段：" + String(expected))

func _parameter(effect: ShaderMaterial, key: StringName) -> float:
	var value: Variant = effect.get_shader_parameter(key)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(effect.shader.get_rid(), key)
	return float(value)

func _render(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _check_gpu_shape() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 480)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var animation := ANIMATION.new()
	viewport.add_child(animation)
	var owned: OwnedCard = main.owned_card_collection.find_first_by_definition(load("res://resources/cards/musketeer.tres"))
	var visual := animation._make_card(owned)
	visual.position = Vector2(210, 240)
	visual.scale = Vector2(2, 2)
	var effect: ShaderMaterial = animation._effect(visual)
	var snapshot := visual.get_child(0) as CardSnapshotVisual
	check(effect.get_shader_parameter("jelly_pivot") == snapshot.get_card_origin_in_texture() + animation.CARD_SIZE * 0.5, "支点使用裸卡中心，包含越界属性图标也不偏移")
	var baseline := await _render(viewport)
	var rest := baseline.get_used_rect()
	check(rest.size.x > 190 and rest.size.y >= 272, "真实GPU渲染完整2倍卡面与越界角标")
	effect.set_shader_parameter("white_amount", 1.0)
	effect.set_shader_parameter("jelly_amount", 1.0)
	var squeezed := await _render(viewport)
	var peak := squeezed.get_used_rect()
	check(peak.size.x < rest.size.x - 8 and peak.size.y > rest.size.y + 20, "GPU实际白卡在峰值上下拉长、左右压窄")
	var white := true
	for y: int in range(peak.position.y, peak.end.y):
		for x: int in range(peak.position.x, peak.end.x):
			var pixel := squeezed.get_pixel(x, y)
			if pixel.a > 0.8 and (pixel.r < 0.98 or pixel.g < 0.98 or pixel.b < 0.98): white = false
	check(white and squeezed.get_pixel(peak.position.x, 0).a == 0.0, "同一Shader在变形时保留纯白剪影与透明背景")
	squeezed.save_png("/private/tmp/project-card-jelly-shape-peak.png")
	effect.set_shader_parameter("jelly_progress", 1.0 / 3.0)
	var recoil := await _render(viewport)
	var recoil_rect := recoil.get_used_rect()
	check(recoil_rect.size.x > rest.size.x and recoil_rect.size.y < rest.size.y, "GPU实际回弹越过原形，形成横向略宽、纵向略扁的反向弹性")
	recoil.save_png("/private/tmp/project-card-jelly-shape-recoil.png")
	effect.set_shader_parameter("white_amount", 0.0)
	effect.set_shader_parameter("jelly_progress", 1.0)
	var settled := await _render(viewport)
	check(settled.get_data() == baseline.get_data(), "回弹结束的GPU像素与原卡完全一致，无裁切、残白或残余形变")
	effect.set_shader_parameter("jelly_progress", 0.0)
	effect.set_shader_parameter("jelly_amount", 0.0)
	var disabled := await _render(viewport)
	check(disabled.get_data() == baseline.get_data(), "默认关闭果冻时共用Shader保持原像素，纹章闪白不被附加形变")
	viewport.queue_free()
	await process_frame
