extends "res://tests/card_foil_pointer_light_test.gd"

## GPU上逐层切换描边，检查法线闪范围、同一光带与其他闪卡的隔离。
func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("法线闪专项超时"); quit(2))
	var bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	var draft := Settings.new()
	draft.copy_values(load(Settings.PATH))
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"embossed_white_flash", 0)
	owned.surface_finish = CardAppearance.Surface.EMBOSSED
	owned.rune_revealed.fill(true)
	owned.emblem_slots[0] = {"emblem_id": &"面包"}
	var card: CardView = CARD.instantiate()
	card.set_card_data(owned.card_data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.set_process(false)
	surface.effect.set_shader_parameter("use_3d", false)
	var renderer: CardFinishPreview = card._finish_controller
	renderer.settings_source = draft
	renderer.refresh()
	var layers: Array[Control] = [card.art_texture, card.card_frame, card.card_name_frame,
		card.action_icon, card.health_icon, card.armor_icon, card.race_icon, card.cooldown_icon,
		card.value_label, card.health_label, card.armor_label, card.cooldown_label,
		card.rune_row.get_child(0).get_child(0), card._status_slot_layer.get_child(0)]
	var poses: Array[Vector2] = [Vector2(0.60, -0.30), Vector2(-0.65, 0.35), Vector2(0.20, 0.80)]
	surface.set_pointer_force(poses[0])
	var lit_card := await shot(surface)
	for layer: Control in layers:
		layer.material.set_shader_parameter("outline_highlight_enabled", false)
	renderer._background_material.set_shader_parameter("outline_highlight_enabled", false)
	var baseline_card := await shot(surface)
	for layer: Control in layers:
		layer.material.set_shader_parameter("outline_highlight_enabled", true)
	renderer._background_material.set_shader_parameter("outline_highlight_enabled", true)
	var comparison := Image.create_empty(lit_card.get_width() * 2, lit_card.get_height(), false, Image.FORMAT_RGBA8)
	var bounds := Rect2i(Vector2i.ZERO, lit_card.get_size())
	comparison.blit_rect(baseline_card, bounds, Vector2i.ZERO)
	comparison.blit_rect(lit_card, bounds, Vector2i(lit_card.get_width(), 0))
	check(_has_outline_change(baseline_card, lit_card), "原白色光带之外，边缘有额外白光")
	check(_off_band_count(baseline_card, lit_card, card, surface, draft, poses[0]) == 0, "所有新增白光共用卡面空间的闪纹")
	for layer: Control in layers:
		var changed := false
		for force: Vector2 in poses:
			surface.set_pointer_force(force)
			var lit := await shot(surface)
			layer.material.set_shader_parameter("outline_highlight_enabled", false)
			var baseline := await shot(surface)
			layer.material.set_shader_parameter("outline_highlight_enabled", true)
			if _has_outline_change(baseline, lit):
				changed = true
				break
		check(changed, "%s 有可见描边反光" % layer.name)
	check(comparison.save_png("/private/tmp/project-card-embossed-outlines.png") == OK, "导出描边前后同角度截图")
	var old_action: Texture2D = card.action_icon.material.get_shader_parameter("badge_texture")
	card.set_battle_action_type(CardData.ActionType.RANGED)
	check(card.action_icon.material.get_shader_parameter("badge_texture") != old_action, "战斗中切换行动方式会更新高光纹理")
	card.clear_battle_action_type()
	check(card.action_icon.material.get_shader_parameter("badge_texture") == old_action, "恢复行动方式时复用原图标")
	card.set_battle_vitals(17, 19)
	var health_origin: Vector2 = card.health_label.material.get_shader_parameter("layer_origin")
	check(health_origin.is_equal_approx(card.get_global_transform().affine_inverse() * card.health_label.get_global_transform().origin), "战斗读数移位后仍与整卡光带对齐")
	for face: int in CardAppearance.Surface.size():
		owned.surface_finish = face as CardAppearance.Surface
		card.set_owned_card(owned)
		var embossed := face == CardAppearance.Surface.EMBOSSED
		check(bool(renderer._art_material.get_shader_parameter("outline_highlight_enabled")) == embossed, "卡面 %d 的立绘描边开关正确" % face)
		check(bool(renderer._background_material.get_shader_parameter("outline_highlight_enabled")) == embossed, "卡面 %d 的背景描边开关正确" % face)
		check(bool(renderer._frame_material.get_shader_parameter("outline_highlight_enabled")) == embossed, "卡面 %d 的外框描边开关正确" % face)
		check(bool(card.health_icon.material.get_shader_parameter("outline_highlight_enabled")) == embossed, "卡面 %d 的图标描边开关正确" % face)
		check((card.health_label.material != null) == embossed, "卡面 %d 的数字材质正确" % face)
		if face in [CardAppearance.Surface.SILVER, CardAppearance.Surface.GOLD, CardAppearance.Surface.RAINBOW]:
			check(int(renderer._frame_material.get_shader_parameter("flash_type")) == face - CardAppearance.Surface.SILVER, "银金彩各用原来的闪纹颜色")
	owned.surface_finish = CardAppearance.Surface.EMBOSSED
	owned.art_finish = CardAppearance.Art.OVERFRAME
	card.set_owned_card(owned)
	check(card.card_frame.material == null and card._overframe_outline.material != null, "法线超框保留原框并高亮独立外边缘")
	var overframe_lit := await shot(surface)
	card._overframe_outline.material.set_shader_parameter("outline_highlight_enabled", false)
	var overframe_baseline := await shot(surface)
	check(_has_outline_change(overframe_baseline, overframe_lit), "法线超框的外边缘确实反光")
	owned.art_finish = CardAppearance.Art.HOLOGRAPHIC
	card.set_owned_card(owned)
	check(bool(renderer._art_material.get_shader_parameter("outline_highlight_enabled")), "法线闪配全息卡图时仍有描边")
	owned.surface_finish = CardAppearance.Surface.PLAIN
	card.set_owned_card(owned)
	check(not renderer._art_material.get_shader_parameter("outline_highlight_enabled"), "单独全息卡图无描边")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == bytes, "未改写用户纹理配置")
	renderer = null
	surface.queue_free()
	await process_frame
	print("Embossed white flash: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)


func _has_outline_change(base: Image, lit: Image) -> bool:
	var changed := 0
	for y: int in range(0, base.get_height(), 2):
		for x: int in range(0, base.get_width(), 2):
			var delta := lit.get_pixel(x, y) - base.get_pixel(x, y)
			if maxf(delta.r, maxf(delta.g, delta.b)) > 0.025:
				changed += 1
				if changed >= 5: return true
	return false


func _off_band_count(base: Image, lit: Image, card: CardView, surface: InspectionCardSurface, settings: Settings, force: Vector2) -> int:
	var padding := InspectionCardSurface.PADDING
	var plane_size := card.card_size + padding * 2.0
	var direction := Vector2.from_angle(deg_to_rad(settings.flash_angle_degrees))
	var gradient := (force * plane_size).normalized() * (direction / plane_size).length()
	var off_band := 0
	for y: int in range(0, base.get_height(), 2):
		for x: int in range(0, base.get_width(), 2):
			var delta := lit.get_pixel(x, y) - base.get_pixel(x, y)
			if maxf(delta.r, maxf(delta.g, delta.b)) < 0.07: continue
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / surface.render_scale - card.position
			var centered := point + padding - plane_size * 0.5
			var phase := (centered.dot(gradient) + Vector2(0.5, 0.5).dot(direction)) * settings.stripe_spacing
			phase += (force.x * 1.35 + force.y * 0.35) * PI + settings.flash_offset * TAU
			var stripe := pow(sin(phase) * 0.5 + 0.5, settings.stripe_width)
			if stripe < 0.04: off_band += 1
	return off_band
