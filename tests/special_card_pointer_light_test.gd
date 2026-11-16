extends "res://tests/card_foil_pointer_light_test.gd"


func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("特殊卡柔光专项超时"); quit(1))
	root.size = Vector2i(1280, 720)
	var bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	var draft := Settings.new()
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"all_special_light", 0)
	var card: CardView = CARD.instantiate()
	card.set_card_data(owned.card_data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.set_process(false)
	surface.effect.set_shader_parameter("use_3d", false)
	var renderer = card._finish_controller
	renderer.settings_source = draft
	var grid := Image.create(540 * CardAppearance.Surface.size(), 688 * CardAppearance.Art.size(), false, Image.FORMAT_RGBA8)
	for art: int in CardAppearance.Art.size():
		for face: int in CardAppearance.Surface.size():
			owned.art_finish = art as CardAppearance.Art
			owned.surface_finish = face as CardAppearance.Surface
			card.set_owned_card(owned)
			surface.set_pointer_force(Vector2(0.85, 0))
			var special := face != CardAppearance.Surface.PLAIN or art != CardAppearance.Art.PLAIN
			check(bool(renderer._art_material.get_shader_parameter("pointer_light_enabled")) == special and bool(renderer._background_material.get_shader_parameter("pointer_light_enabled")) == special and bool(renderer._frame_material.get_shader_parameter("pointer_light_enabled")) == special, "全部外观组合的立绘、背景和外框柔光资格正确")
			draft.foil_shade_strength = 0
			renderer.refresh()
			var unit := await shot(surface)
			draft.foil_shade_strength = 1
			renderer.refresh()
			var bright := await shot(surface)
			check((bright.get_data() != unit.get_data()) == special, "真实GPU确认所有特殊组合均有明暗变化，普通组合保持原画")
			grid.blit_rect(bright, Rect2i(Vector2i.ZERO, bright.get_size()), Vector2i(face * 540, art * 688))
			if face != CardAppearance.Surface.FRACTURED: continue
			check(bool(surface.effect.get_shader_parameter("use_fractured")) and bool(surface.effect.get_shader_parameter("use_flash")) and int(renderer._frame_material.get_shader_parameter("flash_type")) == 0 and int(renderer._background_material.get_shader_parameter("flash_type")) == 0, "碎闪保留晶片并默认启用背景与外框白色闪纹")
			draft.foil_shade_strength = 0
			draft.flash_intensity = 0
			surface.set_pointer_force(Vector2(0.6, -0.3))
			renderer.refresh()
			var unlit := await shot(surface)
			draft.flash_intensity = 0.08
			renderer.refresh()
			var white := await shot(surface)
			var measured := 0
			for y: int in range(30, 80):
				for x: int in [1, 2]:
					var at := Vector2i((Vector2(x, y) + card.position) * surface.render_scale)
					var delta := white.get_pixelv(at) - unlit.get_pixelv(at)
					if delta.r + delta.g + delta.b < 0.03: continue
					measured += 1
					check(absf(delta.r - delta.g) < 0.009 and absf(delta.g - delta.b) < 0.009, "GPU测得碎闪新增闪纹为白色")
			check(measured > 10, "碎闪白色闪纹实际可见")
			draft.flash_intensity = 0.2
	grid.save_png("/private/tmp/project-card-special-light-grid.png")
	check(FileAccess.get_file_as_bytes(Settings.PATH) == bytes, "专项未改写用户纹理配置")
	surface.free()
	print("Special card pointer light: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
