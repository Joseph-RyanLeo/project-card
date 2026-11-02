extends Control

## 本次收藏的只读卡位。原卡负责静态显示，单份共享检视画布负责悬停透视。
signal chosen
signal inspected
const CARD = preload("res://scenes/ui/CardView.tscn")
const CARD_ORIGIN := Vector2(28, 16) # 卡面在网格格子内的位置，留出角标与环绕高光
const CELL_SIZE := Vector2(160, 184) # 一张1倍卡和收藏数量说明的格子尺寸
var view: CardView
var halo: Control
var selected: bool:
	get: return is_instance_valid(halo) and halo.selected
var _press_position := Vector2.ZERO
var _pressed := false
var _caption: Label

func setup(owned: OwnedCard) -> void:
	custom_minimum_size = CELL_SIZE
	size = CELL_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	view = CARD.instantiate() as CardView
	view.set_snapshot_mode(true)
	view.configure_drag_source(false)
	view.set_card_data(owned.card_data)
	view.set_owned_card(owned)
	add_child(view)
	view.position = CARD_ORIGIN
	view.scale = Vector2.ONE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	halo = preload("res://scripts/ui/card_selection_halo.gd").new()
	halo.name = "SelectionHalo"
	halo.size = view.card_size
	view.add_child(halo)
	_caption = Label.new()
	_caption.position = Vector2(2, 160) # 收藏数量与已选位置的说明位置
	_caption.add_theme_font_size_override("font_size", 14) # 小卡说明字号
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	preload("res://scripts/ui/collection_card_hover.gd").bind_read_only(view)

func sync_choice(choice: Dictionary, count: int) -> void:
	halo.set_selected(not choice.is_empty())
	_caption.text = "已有 %d / 3%s" % [count, " · 已选位%d" % (int(choice.slot) + 1) if selected else ""]
	_caption.modulate = Color("ffe4a5") if selected else Color.WHITE

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = Rect2(CARD_ORIGIN, view.card_size).has_point(event.position)
			_press_position = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_position) < 6.0 and Rect2(CARD_ORIGIN, view.card_size).has_point(event.position):
				chosen.emit()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if Rect2(CARD_ORIGIN, view.card_size).has_point(event.position):
			inspected.emit()
		accept_event()
	# 滚轮不消费，沿父节点传到ScrollContainer。
