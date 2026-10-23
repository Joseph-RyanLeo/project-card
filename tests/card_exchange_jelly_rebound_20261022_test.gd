extends "res://tests/card_exchange_jelly_shader_test.gd"

## 在原GPU和正式事务专项上增加本轮极限停顿、快回弹和整体超调检查。
func _check_gpu_shape() -> void:
	await super._check_gpu_shape()
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
	var baseline := await _render(viewport)
	effect.set_shader_parameter("jelly_amount", 1.0)
	effect.set_shader_parameter("jelly_progress", 0.20)
	var recoil := await _render(viewport)
	effect.set_shader_parameter("jelly_progress", 0.31)
	var held_recoil := await _render(viewport)
	check(recoil.get_data() == held_recoil.get_data(), "反向极限保持约3帧，GPU形状稳定")
	effect.set_shader_parameter("jelly_progress", 0.64)
	var enlarged := await _render(viewport)
	var rest := baseline.get_used_rect()
	var peak := enlarged.get_used_rect()
	check(peak.size.x > rest.size.x + 8 and peak.size.y > rest.size.y + 10, "整体超调时宽高均超过原卡，实际GPU约弹大5.5%")
	effect.set_shader_parameter("jelly_progress", 0.75)
	check((await _render(viewport)).get_data() == enlarged.get_data(), "整体弹大极限保持约3帧，不立即缩回")
	effect.set_shader_parameter("jelly_progress", 0.98)
	var near_end := (await _render(viewport)).get_used_rect()
	check(near_end.size.x <= rest.size.x + 2 and near_end.size.y <= rest.size.y + 2, "接近结束时缓慢缩回原尺寸附近")
	effect.set_shader_parameter("jelly_progress", 1.0)
	check((await _render(viewport)).get_data() == baseline.get_data(), "新增整体弹大之后仍精确恢复原始GPU像素")
	check(ANIMATION.FUSION_HOLD_SECONDS >= 0.08 and ANIMATION.FUSION_HOLD_SECONDS <= 0.084, "首次挤压极限较原来0.05秒增加约2帧")
	check(is_equal_approx(ANIMATION.JELLY_SECONDS * 0.20, 0.08) and ANIMATION.JELLY_SECONDS * (0.32 - 0.20) >= 0.045, "快速反弹0.08秒，极限停留约3帧")
	viewport.queue_free()
	await process_frame
