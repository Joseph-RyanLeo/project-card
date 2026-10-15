extends SceneTree

const CARD_VIEW := preload("res://scenes/ui/CardView.tscn")
const SHEET_SIZE := Vector2i(1620, 850) # 九列四排卡面验收图的输出尺寸
const CARD_SCALE := Vector2(1.5, 1.5) # 放大像素卡面便于检查取景和数字
const CELL_STEP := Vector2(178, 203) # 卡面验收图的列距与行距
var views: Array[CardView] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = SHEET_SIZE
	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.14)
	background.size = Vector2(SHEET_SIZE)
	root.add_child(background)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/demo2/twisted_vein_manifest.json"))
	for index: int in manifest.cards.size():
		var card := load("res://resources/cards/%s.tres" % manifest.cards[index].id) as CardData
		var owned := OwnedCard.new()
		owned.initialize(card, StringName("visual:%d" % index), index)
		var view := CARD_VIEW.instantiate() as CardView
		root.add_child(view)
		view.position = Vector2(50, 52) + Vector2(index % 9, index / 9) * CELL_STEP
		view.scale = CARD_SCALE
		view.set_owned_card(owned)
		view.set_card_data(card)
		views.append(view)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png("/private/tmp/project-card-twisted-vein-cards.png")
	print("矿脉36张卡面验收图保存：", error)
	for view: CardView in views: view.showing_effect = true; view._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	error = image.save_png("/private/tmp/project-card-twisted-vein-effects.png")
	print("矿脉效果卡面验收图保存：", error)
	quit(error)
