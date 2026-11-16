extends SceneTree

## 真实GPU：停用磨砂，正面暗、边缘亮，宽柔光跟随鼠标；人物不叠加光带。
const CARD = preload("res://scenes/ui/CardView.tscn")
const Settings = preload("res://scripts/ui/card_finish_settings.gd")
var checks := 0
var failures := 0


func _initialize() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)


func shot(surface: InspectionCardSurface) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return surface.viewport.get_texture().get_image()


func compare(a: Image, b: Image, card: CardView, surface: InspectionCardSurface) -> Dictionary:
	var result := {"role": 0, "role_changed": 0, "background": 0, "frame": 0, "title": 0}
	var art: Image = card.art_texture.texture.get_image()
	var frame: Image = card.card_frame.texture.get_image()
	for y: int in range(2, a.get_height() - 2, 4):
		for x: int in range(2, a.get_width() - 2, 4):
			var point := Vector2(x, y) / surface.render_scale - card.position
			var color_delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			var changed := absf(color_delta.r) + absf(color_delta.g) + absf(color_delta.b) > 0.003
			if Rect2(card.art_area_position, card.art_area_size).has_point(point):
				var art_point := Vector2i(point - card.art_panel.position - card.art_texture.position)
				var alpha := art.get_pixelv(art_point).a if Rect2i(Vector2i.ZERO, art.get_size()).has_point(art_point) else 0.0
				var frame_alpha := frame.get_pixelv(Vector2i(point)).a
				if alpha > 0.99 and frame_alpha < 0.01:
					result.role += 1
					if changed: result.role_changed += 1
				elif alpha < 0.01 and frame_alpha < 0.01 and changed: result.background += 1
			if Rect2(1, 30, 2, 60).has_point(point) and changed: result.frame += 1
			if Rect2(card.title_area_position + Vector2(10, 2), card.title_area_size - Vector2(20, 4)).has_point(point) and changed: result.title += 1
	return result


func gain(reference: Image, sample: Image, card: CardView, surface: InspectionCardSurface, region: Rect2) -> float:
	var total := 0.0
	var count := 0
	for y: int in range(2, reference.get_height() - 2, 4):
		for x: int in range(2, reference.get_width() - 2, 4):
			var point := Vector2(x, y) / surface.render_scale - card.position
			if not Rect2(card.art_area_position, card.art_area_size).has_point(point) or not region.has_point(point / card.card_size): continue
			var base := reference.get_pixel(x, y)
			var value := (base.r + base.g + base.b) / 3.0
			if base.a < 0.99 or value < 0.08 or value > 0.45: continue
			var color := sample.get_pixel(x, y)
			total += (color.r + color.g + color.b) / (value * 3.0)
			count += 1
	return total / maxf(count, 1)


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("闪卡鼠标柔光专项超时"); quit(1))
	root.size = Vector2i(1280, 720)
	var data: CardData = load("res://resources/cards/militia.tres")
	var bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	var draft := Settings.new()
	var owned := OwnedCard.new()
	owned.initialize(data, &"foil_pointer_light_probe", 0)
	var card: CardView = CARD.instantiate()
	card.set_card_data(data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.set_process(false)
	var renderer = card._finish_controller
	renderer.settings_source = draft
	surface.effect.set_shader_parameter("use_3d", false)
	var grid := Image.create(540 * 5, 688 * 3, false, Image.FORMAT_RGBA8)
	for face: int in [CardAppearance.Surface.SILVER, CardAppearance.Surface.GOLD, CardAppearance.Surface.RAINBOW]:
		owned.surface_finish = face as CardAppearance.Surface
		card.set_owned_card(owned)
		surface.set_pointer_force(Vector2(0.6, -0.3))
		draft.flash_intensity = 0
		renderer.refresh()
		var unlit := await shot(surface)
		draft.flash_intensity = 0.8
		renderer.refresh()
		var lit := await shot(surface)
		var difference := compare(unlit, lit, card, surface)
		check(difference.role > 500 and difference.role_changed == 0 and difference.title == 0, "银金彩闪的角色与卡名不受光带影响")
		check(difference.background > 50 and difference.frame > 10, "背景与外框继续显示光带")
		draft.foil_matte_strength = 1
		draft.foil_matte_grain_size = 6
		draft.foil_matte_density = 1
		renderer.refresh()
		check((await shot(surface)).get_data() == lit.get_data(), "旧存档残留的最大磨砂参数不会重新启用颗粒")
		draft.flash_intensity = 0
		draft.foil_shade_strength = 1
		renderer.refresh()
		var poses: Array[Vector2] = [Vector2.ZERO, Vector2(0.85, 0), Vector2(-0.85, 0), Vector2(0, -0.85), Vector2(0, 0.85)]
		var images: Array[Image] = []
		for index: int in poses.size():
			surface.set_pointer_force(poses[index])
			images.append(await shot(surface))
			grid.blit_rect(images[index], Rect2i(Vector2i.ZERO, images[index].get_size()), Vector2i(index * 540, (face - 1) * 688))
			if index == 0: continue
			difference = compare(images[0], images[index], card, surface)
			check(gain(images[0], images[index], card, surface, Rect2(0, 0, 1, 1)) > 1.3 and difference.role_changed > 500 and difference.title == 0, "四个边缘均比居中更亮，人物参与柔光且卡名不变")
		var left := Rect2(0, 0, 0.4, 1)
		var right := Rect2(0.6, 0, 0.4, 1)
		var top := Rect2(0, 0, 1, 0.45)
		var bottom := Rect2(0, 0.55, 1, 0.45)
		check(gain(images[0], images[1], card, surface, right) > gain(images[0], images[1], card, surface, left) + 0.04, "指向右侧时右侧局部更亮")
		check(gain(images[0], images[2], card, surface, left) > gain(images[0], images[2], card, surface, right) + 0.04, "指向左侧时左侧局部更亮")
		check(gain(images[0], images[3], card, surface, top) > gain(images[0], images[3], card, surface, bottom) + 0.04, "指向上侧时上侧局部更亮")
		check(gain(images[0], images[4], card, surface, bottom) > gain(images[0], images[4], card, surface, top) + 0.04, "指向下侧时下侧局部更亮")
		renderer.bind_surface(surface.effect, false)
		check((await shot(surface)).get_data() == images[4].get_data(), "静置与合成检视使用相同的鼠标柔光")
		renderer.bind_surface(surface.effect, true)
		draft.foil_shade_strength = 0
		renderer.refresh()
		var no_shade := await shot(surface)
		surface.set_pointer_force(Vector2(-0.85, 0))
		check((await shot(surface)).get_data() == no_shade.get_data(), "明暗强度0完全关闭鼠标柔光，不改变原画")
	grid.save_png("/private/tmp/project-card-pointer-light-grid.png")
	owned.surface_finish = CardAppearance.Surface.PLAIN
	card.set_owned_card(owned)
	var plain := await shot(surface)
	draft.foil_shade_strength = 1
	draft.flash_intensity = 1
	renderer.refresh()
	check((await shot(surface)).get_data() == plain.get_data(), "普通卡不受闪卡参数影响")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == bytes, "专项不覆盖用户配置")
	surface.free()
	print("Foil pointer light GPU: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
