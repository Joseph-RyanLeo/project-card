extends SceneTree

const CARD := preload("res://scenes/ui/CardView.tscn")
const RuneStyle := preload("res://scripts/ui/rune_reveal_cover_style.gd")
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 740)
	var definition := (load("res://resources/cards/elegy_poet.tres") as CardData).duplicate() as CardData
	definition.runes.assign([CardData.ElementType.DARK, CardData.ElementType.FIRE, CardData.ElementType.LIGHT])
	var owned := OwnedCard.new()
	owned.initialize(definition, &"overframe_rune_proof", 0)
	owned.resolved_runes.assign(definition.runes)
	owned.rune_revealed.assign([true, true, false])
	var card := CARD.instantiate() as CardView
	card.set_card_data(definition)
	card.set_owned_card(owned)
	root.add_child(card)
	var ordinary := _icon(card, 0)
	_check(not ordinary.texture is AtlasTexture and ordinary.material == null, "普通卡保留原纹理和混合方式")
	owned.art_finish = CardAppearance.Art.OVERFRAME
	card.set_owned_card(owned)
	if DisplayServer.get_name() != "headless": await _check_rotated_art_clip(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.position = Vector2(90, 20)
	surface.scale = Vector2(4, 4)
	surface.set_process(false)
	var dark := _icon(card, 0)
	var fire := _icon(card, 1)
	var light := _icon(card, 2)
	var cover := card.rune_row.get_child(2).get_child(1) as TextureRect
	var cover_material := cover.material as ShaderMaterial
	for icon: TextureRect in [dark, fire, light]:
		_check((icon.texture as AtlasTexture).atlas == CardView.OVERFRAME_RUNE_IDLE_SHEET, "未生效的超框底层符文使用独立静态图集")
	_check(dark.material == null and fire.material == null, "刮开的超框符文使用普通混合")
	_check((dark.texture as AtlasTexture).region.position.x == 0.0 and (fire.texture as AtlasTexture).region.position.x == 30.0 and (light.texture as AtlasTexture).region.position.x == 90.0, "图集深紫／火／光三列与元素对应")
	_check(cover.texture == RuneStyle.get_overframe_cover_texture() and cover_material.shader == RuneStyle.OVERFRAME_SHADER, "只有未刮覆盖使用灰色裁片和叠底材质")
	_check((light.material as ShaderMaterial).shader == RuneStyle.COVER_SHADER and (light.material as ShaderMaterial).get_shader_parameter("reveal_only") == true, "底层原色符文仍受刮除遮罩限制")
	if DisplayServer.get_name() != "headless":
		var rendered := await _shot(surface)
		card.rune_row.hide()
		var base := await _shot(surface)
		card.rune_row.show()
		_check(_matches_composite(cover, rendered, base, surface, true), "只有未刮的灰色覆盖层按 55% Multiply")
		_check(_matches_composite(dark, rendered, base, surface, false), "已刮的静态图标按原色和原 alpha 混合")
		var pose := Vector2(0.72, -0.34)
		surface.set_pointer_force(pose)
		_check(cover_material.get_shader_parameter("pointer_force") == pose, "检视角度传给覆盖层的浮雕法线")
		var with_normal := await _shot(surface)
		cover_material.set_shader_parameter("pointer_force", Vector2.ZERO)
		var without_normal := await _shot(surface)
		_check(_changed_rune_pixels(cover, with_normal, without_normal, surface).size() > 24 and _changed_rune_pixels(dark, with_normal, without_normal, surface).is_empty(), "法线反光只改变未刮覆盖层，不改变已刮符文")
		if "--capture" in OS.get_cmdline_user_args():
			surface.set_pointer_force(Vector2(0.40, -0.28))
			await _shot(surface)
			_check(root.get_texture().get_image().save_png("/private/tmp/project-card-overframe-runes.png") == OK, "保存超框卡实机预览")
		surface.set_pointer_force(Vector2.ZERO)
	var original_mask := (light.material as ShaderMaterial).get_shader_parameter("scrape_mask") as Texture2D
	var first_pixels: Array[Vector2i] = [Vector2i(11, 11)]
	owned.record_rune_scrape_pixels(2, first_pixels)
	card.refresh_rune_scrape_cover(2)
	var next_mask := (light.material as ShaderMaterial).get_shader_parameter("scrape_mask") as Texture2D
	_check(cover.material == cover_material and next_mask != original_mask and cover_material.get_shader_parameter("scrape_mask") == next_mask, "第一次刮开复用覆盖法线材质，两层共用新遮罩")
	if DisplayServer.get_name() != "headless":
		var partial := await _shot(surface)
		light.hide()
		var without_light := await _shot(surface)
		light.show()
		_check(_changed_rune_pixels(light, partial, without_light, surface) == first_pixels, "图集非首列只在刮开的一像素处显示原色")

	owned.surface_finish = CardAppearance.Surface.EMBOSSED
	owned.rune_revealed[2] = true
	card.set_owned_card(owned)
	_check(card.rune_row.get_child(2).get_child_count() == 1 and _icon(card, 2).material == null, "完全刮开后移除覆盖，即使是法线闪也不向超框底层符文加法线")
	owned.surface_finish = CardAppearance.Surface.PLAIN
	card.set_owned_card(owned)

	var highlights: Array[int] = [0]
	CardView._start_active_rune_flow_if_needed()
	await process_frame
	card.set_rune_pattern_highlights(highlights)
	_check((_icon(card, 0).texture as AtlasTexture).atlas == CardView.OVERFRAME_RUNE_IDLE_SHEET, "等待下一轮同步流光时继续显示静态图标")
	card.set_rune_pattern_highlights(highlights, true)
	card._update_active_rune_frames()
	_check((_icon(card, 0).texture as AtlasTexture).atlas == CardView.OVERFRAME_RUNE_FRAMES[card.get_active_rune_animation_frame()], "超框成型使用现有时间轴对应的序列帧")
	card.set_battle_masked_runes(highlights)
	_check(not _icon(card, 0).visible, "战斗遮蔽仍隐藏超框符文")
	card.clear_battle_masked_runes()
	owned.set_rune_sticker(1, {"emblem_id": &"木贴纸", "instance_id": &"preview_sticker", "element": int(CardData.ElementType.WOOD)})
	card.set_owned_card(owned)
	_check(_icon(card, 1).texture.get_size() == Vector2(27, 27) and _icon(card, 1).material == null, "独立元素贴纸保留原样，不使用叠底")
	owned.art_finish = CardAppearance.Art.PLAIN
	card.set_owned_card(owned)
	_check((_icon(card, 0).texture as AtlasTexture).atlas == CardView.RUNE_ACTIVE_FLOW_SHEET and _icon(card, 0).material == null, "切回普通卡恢复原流光图集和材质")
	surface.free()
	print("Overframe rune multiply: %d failures" % _failures)
	quit(_failures)


func _check_rotated_art_clip(card: CardView) -> void:
	card.scale = Vector2(4, 4)
	card.position = Vector2(154, 78) + card.pivot_offset * (card.scale - Vector2.ONE)
	card.rotation_degrees = CardView.HOVER_PUNCH_ANGLE
	await process_frame
	await RenderingServer.frame_post_draw
	var rotated := root.get_texture().get_image()
	card.art_content.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var reference := root.get_texture().get_image()
	card.art_content.show()
	var to_card := card.get_global_transform_with_canvas().affine_inverse()
	var window := card.art_panel.get_rect()
	var inside := 0
	var outside := 0
	for y: int in rotated.get_height():
		for x: int in rotated.get_width():
			if rotated.get_pixel(x, y) == reference.get_pixel(x, y): continue
			if window.grow(0.2).has_point(to_card * Vector2(x + 0.5, y + 0.5)):
				inside += 1
			else:
				outside += 1
	_check(inside > 10000 and outside == 0, "悬停晃动时立绘和背景只画在随卡旋转的插画窗口内（漏出 %d 像素）" % outside)
	if "--capture" in OS.get_cmdline_user_args():
		rotated.save_png("/private/tmp/project-card-overframe-hover.png")
	card.rotation_degrees = 0.0


func _icon(card: CardView, slot_index: int) -> TextureRect:
	return card.rune_row.get_child(slot_index).get_child(0) as TextureRect


func _shot(surface: InspectionCardSurface) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return surface.viewport.get_texture().get_image()


func _sample_at(icon: TextureRect, point: Vector2i, surface: InspectionCardSurface) -> Vector2i:
	return Vector2i((icon.get_global_rect().position + Vector2(point) + Vector2(0.5, 0.5)) * surface.render_scale)


func _matches_composite(icon: TextureRect, rendered: Image, base: Image, surface: InspectionCardSurface, multiply: bool) -> bool:
	var atlas := icon.texture as AtlasTexture
	var raw := atlas.atlas.get_image().get_region(Rect2i(atlas.region))
	var nonzero := 0
	var wrong := 0
	for row: int in raw.get_height():
		for column: int in raw.get_width():
			var point := Vector2i(column, row)
			var at := _sample_at(icon, point, surface)
			var ink := raw.get_pixelv(point)
			var paper := base.get_pixelv(at)
			var actual := rendered.get_pixelv(at)
			if paper.a < 0.99: continue
			if ink.a > 0.0: nonzero += 1
			var ink_color := Color(ink.r, ink.g, ink.b)
			var expected := paper * Color.WHITE.lerp(ink_color, ink.a * 0.55) if multiply else paper.lerp(ink_color, ink.a)
			if absf(expected.r - actual.r) > 2.0 / 255.0 or absf(expected.g - actual.g) > 2.0 / 255.0 or absf(expected.b - actual.b) > 2.0 / 255.0 or actual.a != paper.a:
				wrong += 1
	return nonzero > 300 and wrong == 0


func _changed_rune_pixels(icon: TextureRect, rendered: Image, reference: Image, surface: InspectionCardSurface) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for row: int in int(icon.size.y):
		for column: int in int(icon.size.x):
			var point := Vector2i(column, row)
			var at := _sample_at(icon, point, surface)
			if rendered.get_pixelv(at) != reference.get_pixelv(at): changed.append(point)
	return changed


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)
