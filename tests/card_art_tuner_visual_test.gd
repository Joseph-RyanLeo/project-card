extends SceneTree

## 实际渲染1280×720调整器，验收筛选、字段和4倍像素预览的布局。
const SCENE := preload("res://scenes/tools/CardArtTuner.tscn")
var tuner: CardArtTuner
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 720)
	tuner = SCENE.instantiate()
	root.add_child(tuner)
	await process_frame
	for index: int in tuner.pack_selector.item_count:
		if tuner.pack_selector.get_item_metadata(index) == &"ironwall_inscription": tuner.pack_selector.select(index); tuner.pack_selector.item_selected.emit(index)
	tuner.card_data = load("res://resources/cards/field_beer_machine.tres")
	tuner.use_3d_check.button_pressed = false
	tuner.use_flash_check.button_pressed = false
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("/private/tmp/project-card-tuner-editor.png")
	print("卡面调整器布局截图：", error)
	tuner.card_data = load("res://resources/cards/sentry_pistol.tres")
	await process_frame
	await RenderingServer.frame_post_draw
	error = root.get_texture().get_image().save_png("/private/tmp/project-card-tuner-equipment.png")
	print("装备字段布局截图：", error)
	tuner.queue_free()
	await process_frame
	quit(error)
