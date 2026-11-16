extends "res://tests/card_foil_pointer_light_test.gd"

const OUTPUT := "res://docs/previews/card_film_continuity_20261107"


func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("背景外框纹路连续性专项超时"); quit(1))
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var data: CardData = load("res://resources/cards/anvil_margaret.tres")
	var owned := OwnedCard.new()
	owned.initialize(data, &"film_continuity", 0)
	owned.surface_finish = CardAppearance.Surface.FINGERPRINT
	var card: CardView = CARD.instantiate()
	card.set_card_data(data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	surface.set_process(false)
	surface.effect.set_shader_parameter("use_3d", false)
	var draft := Settings.new()
	var renderer = card._finish_controller
	renderer.settings_source = draft
	renderer.refresh()
	surface.set_pointer_force(Vector2(0.65, -0.3))
	(await shot(surface)).save_png(OUTPUT.path_join("fingerprint_margaret.png"))
	# 用相同中灰底纸分别渲染真实背景／外框shader，比较同一整卡位置的光纹。
	# 消除原素材颜色差异，保留正式节点的尺寸、起点和全息深度运算。
	var flat := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.35, 0.35, 0.35))
	var paper := ImageTexture.create_from_image(flat)
	card.art_texture.hide()
	for art: int in [CardAppearance.Art.PLAIN, CardAppearance.Art.HOLOGRAPHIC]:
		surface.effect.set_shader_parameter("use_3d", art == CardAppearance.Art.HOLOGRAPHIC)
		owned.art_finish = art as CardAppearance.Art
		card.set_owned_card(owned)
		card.art_texture.hide()
		card.card_frame.texture = paper
		card.art_background.texture = paper
		# 全息色膜是另一个独立工艺；这里只测其深度变换下的指纹连续性。
		renderer._background_material.set_shader_parameter("card_finish", -1)
		for pose: Vector2 in [Vector2.ZERO, Vector2(-0.8, 0.25), Vector2(0.65, -0.3)]:
			surface.set_pointer_force(pose)
			card.card_frame.hide()
			var background := await shot(surface)
			card.card_frame.show()
			var frame := await shot(surface)
			var max_delta := 0.0
			var samples := 0
			for y: int in range(35, 95):
				for x: int in range(14, 85):
					var at := Vector2i((Vector2(x, y) + card.position) * surface.render_scale + Vector2(0.5, 0.5))
					var delta := frame.get_pixelv(at) - background.get_pixelv(at)
					max_delta = maxf(max_delta, maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))))
					samples += 1
			check(samples > 4000 and max_delta < 0.012, "真实背景与外框在同一整卡坐标显示同一纹路，全息深度也不使纹路错开")
	surface.free()
	print("Film background/frame continuity GPU: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
