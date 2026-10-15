extends SceneTree

## 放大绘制截图，供核对晨昏元素与矿石鉴定师的真实卡面槽位。
const CARD := preload("res://scenes/ui/CardView.tscn")
func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("171c28")
	background.size = Vector2(1280, 720)
	root.add_child(background)
	var index := 0
	for id: String in ["twilight_elemental", "ore_appraiser"]:
		var definition := load("res://resources/cards/%s.tres" % id) as CardData
		var owned := OwnedCard.new()
		owned.initialize(definition, StringName("visual_" + id), index)
		var view := CARD.instantiate() as CardView
		root.add_child(view)
		view.scale = Vector2(4, 4)
		view.set_card_data(definition)
		view.set_owned_card(owned)
		# 缩放围绕卡牌中心；逻辑位置加上中心偏移，使可见卡框完整留在画布内。
		view.set_layout_position(Vector2(290 + index * 560, 269))
		index += 1
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-minion-slots-fixed.png")
	quit()
