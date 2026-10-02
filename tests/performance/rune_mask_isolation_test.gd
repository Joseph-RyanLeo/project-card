extends SceneTree

## 真实卡面回归：首次刮除必须脱离共享空遮罩，更新不能泄漏到其他卡或其他槽。
const CARD_SCENE = preload("res://scenes/ui/CardView.tscn")
const STYLE = preload("res://scripts/ui/rune_reveal_cover_style.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var definition := load("res://resources/cards/heavy_knight.tres") as CardData
	var cards: Array[OwnedCard] = []
	var views: Array[CardView] = []
	for index: int in 2:
		var owned := OwnedCard.new()
		owned.initialize(definition, StringName("mask_isolation_%d" % index), index)
		var view := CARD_SCENE.instantiate() as CardView
		view.set_card_data(definition)
		view.set_owned_card(owned)
		root.add_child(view)
		cards.append(owned)
		views.append(view)
	await process_frame
	var empty := STYLE.get_empty_mask_texture()
	check(views[0]._rune_scrape_mask_textures[0] == empty and views[1]._rune_scrape_mask_textures[0] == empty, "未刮卡面复用空遮罩")
	check(cards[0].record_rune_scrape_pixels(0, [Vector2i(11, 11)]) == 1, "第一张卡实际刮除圆心像素")
	views[0].refresh_rune_scrape_cover(0)
	var changed := views[0]._rune_scrape_mask_textures[0] as ImageTexture
	check(changed != empty, "首次刮除为该槽分配独立遮罩")
	check(views[0]._rune_scrape_mask_textures[1] == empty and views[1]._rune_scrape_mask_textures[0] == empty, "同卡其他槽和另一张卡仍使用空遮罩")
	var cover := views[0]._rune_scrape_cover_icons[0] as TextureRect
	var icon := cover.get_parent().get_child(0) as TextureRect
	check((cover.material as ShaderMaterial).get_shader_parameter("scrape_mask") == changed and (icon.material as ShaderMaterial).get_shader_parameter("scrape_mask") == changed, "覆盖与底层元素同步使用独立遮罩")
	cards[0].record_rune_scrape_pixels(0, [Vector2i(12, 11)])
	views[0].refresh_rune_scrape_cover(0)
	check(views[0]._rune_scrape_mask_textures[0] == changed, "继续刮除更新同一独立纹理")
	await RenderingServer.frame_post_draw
	var pixels := changed.get_image()
	var blank := empty.get_image()
	check(pixels != null and pixels.get_pixel(11, 11).r > 0.5 and pixels.get_pixel(12, 11).r > 0.5 and pixels.get_pixel(10, 11).r < 0.5, "独立纹理只显示实际刮除的两点")
	check(blank != null and blank.get_pixel(11, 11).r < 0.5 and cards[1].get_rune_scraped_pixel_count(0) == 0, "共享纹理与其他实例都没有被修改")
	for view: CardView in views:
		view.queue_free()
	await process_frame
	print("Rune mask isolation failures: ", failures)
	quit(1 if failures else 0)
