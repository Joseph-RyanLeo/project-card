extends Control

## 复用事件已保存的实例。这里只生成预览与飞行动画，入库仍由原事件事务负责。
signal landed(item: Dictionary)
signal finished

const TILE_SIZE := Vector2(53, 57) # 纹章和指示物的预览格尺寸
const START_PAUSE := 0.13 # 切换收藏视角后稍等，再开始发出奖励
const FLIGHT_SECONDS := 0.46 # 单件奖励从结算页飞到目的地的时长
const FLIGHT_INTERVAL := 0.045 # 多件奖励相继出发的间隔
const FLIGHT_ARC := 30.0 # 飞行路径向上的弧度高度
const KINDS := ["card", "sticker", "indicator"]
var main: Control
var _toolbox_rest := INF


static func collect(main_view: Control, before: Dictionary, presented_cards: Array[OwnedCard] = []) -> Array[Dictionary]:
	var awards: Array[Dictionary] = []
	var existing_cards := _ids(before.cards.cards)
	for card: OwnedCard in main_view.owned_card_collection.get_cards():
		if not existing_cards.has(String(card.instance_id)) and not presented_cards.has(card):
			awards.append({"kind": "card", "id": String(card.instance_id)})
	var existing_stickers := _ids(before.inventory)
	for sticker: Dictionary in main_view.emblem_library.get_inventory_state():
		if not existing_stickers.has(String(sticker.instance_id)):
			awards.append({"kind": "sticker", "id": String(sticker.instance_id)})
	var existing_indicators := _ids(before.celestial.items)
	for indicator: CelestialIndicator in main_view.celestial_indicators.items:
		if not existing_indicators.has(String(indicator.instance_id)):
			awards.append({"kind": "indicator", "id": String(indicator.instance_id)})
	return awards


static func _ids(items: Array) -> Dictionary:
	var ids := {}
	for item: Dictionary in items: ids[String(item.instance_id)] = true
	return ids


static func valid_items(value: Variant) -> bool:
	if not value is Array or value.is_empty(): return false
	var seen := {}
	for item: Variant in value:
		if not item is Dictionary or item.get("kind") not in KINDS or not item.get("id") is String or item.id.is_empty(): return false
		var key := "%s:%s" % [item.kind, item.id]
		if seen.has(key): return false
		seen[key] = true
	return true


static func make_tile(main_view: Control, item: Dictionary) -> Control:
	var tile := Control.new()
	tile.name = "EventReward"
	tile.custom_minimum_size = TILE_SIZE
	tile.size = TILE_SIZE
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var id := StringName(item.id)
	if item.kind == "card":
		var owned: OwnedCard = main_view.owned_card_collection.get_by_instance_id(id)
		if owned == null:
			tile.free()
			return null
		var card: CardView = main_view.CARD_VIEW_SCENE.instantiate()
		card.set_snapshot_mode(true)
		card.set_card_data(owned.card_data)
		card.set_owned_card(owned)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(card)
		card.position = card.get_visual_capture_padding_top_left()
		tile.custom_minimum_size = card.position + card.card_size + card.get_visual_capture_padding_bottom_right()
		tile.size = tile.custom_minimum_size
		tile.tooltip_text = owned.card_data.display_name
		return tile
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.kind == "sticker":
		var sticker: Dictionary = main_view.emblem_library.get_inventory_item(id)
		if sticker.is_empty():
			icon.free()
			tile.free()
			return null
		var is_wound: bool = sticker.get("kind") == "wound"
		var name := StringName(sticker.get("wound_id" if is_wound else "emblem_id", ""))
		icon.texture = RuneStickerStyle.get_texture_by_id(name) if sticker.get("element_sticker", false) else StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.WOUND if is_wound else CardSlotLayout.Kind.EMBLEM, name)
		tile.tooltip_text = String(name)
	else:
		for indicator: CelestialIndicator in main_view.celestial_indicators.items:
			if indicator.instance_id != id: continue
			icon.texture = CelestialIndicatorStyle.get_texture(indicator.kind)
			tile.tooltip_text = CelestialIndicator.NAMES[indicator.kind]
			break
	if icon.texture == null:
		icon.free()
		tile.free()
		return null
	tile.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tile


static func preview_rect(tile: Control) -> Rect2:
	var visual := tile.get_child(0) as CardView
	return visual.get_global_rect() if visual != null else tile.get_global_rect()


func play(items: Array[Dictionary], origins: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 3950 # 奖励覆盖桌面和收藏，暂停菜单仍能正常打开
	var animation := create_tween().set_parallel(true)
	var shakes := false
	var total := START_PAUSE + FLIGHT_SECONDS
	for index: int in items.size():
		var item := items[index]
		var tile := make_tile(main, item)
		if tile == null: continue
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tile)
		var card := tile.get_child(0) as CardView
		tile.pivot_offset = card.position + card.card_size * 0.5 if card != null else tile.size * 0.5
		var source: Vector2 = origins.get(String(item.id), get_viewport_rect().get_center())
		tile.position = source - tile.pivot_offset
		var start := START_PAUSE + index * FLIGHT_INTERVAL
		total = start + FLIGHT_SECONDS
		animation.tween_method(_move_tile.bind(tile, item, source), 0.0, 1.0, FLIGHT_SECONDS).set_delay(start)
		animation.tween_callback(func():
			tile.hide()
			landed.emit(item)
		).set_delay(total)
		shakes = shakes or item.kind == "sticker"
	animation.tween_interval(total)
	if shakes:
		var library: EmblemLibraryView = main.emblem_library
		_toolbox_rest = library.position.x
		library.tween_receipt_shake(animation.chain(), _toolbox_rest)
	animation.chain().tween_callback(func():
		_toolbox_rest = INF
		finished.emit())


func _exit_tree() -> void:
	if is_finite(_toolbox_rest) and is_instance_valid(main) and is_instance_valid(main.emblem_library):
		main.emblem_library.position.x = _toolbox_rest


func _move_tile(progress: float, tile: Control, item: Dictionary, source: Vector2) -> void:
	var destination := _target(item)
	var easing := smoothstep(0.0, 1.0, progress)
	var card := tile.get_child(0) as CardView
	var source_size := card.card_size if card != null else tile.size
	var target_size := minf(destination.size.x / source_size.x, destination.size.y / source_size.y)
	tile.position = source.lerp(destination.get_center(), easing) - tile.pivot_offset - Vector2(0, sin(PI * progress) * FLIGHT_ARC)
	tile.scale = Vector2.ONE * lerpf(1.0, clampf(target_size, 0.25, 2.0), easing)


func _target(item: Dictionary) -> Rect2:
	var id := StringName(item.id)
	var rect := Rect2()
	match item.kind:
		"sticker":
			rect = main.emblem_library.get_item_canvas_rect(id)
		"indicator":
			rect = main.celestial_indicators.get_item_canvas_rect(id)
		"card":
			var owned: OwnedCard = main.owned_card_collection.get_by_instance_id(id)
			var slot: Control = main._find_collection_slot_for_owned_card(owned)
			if is_instance_valid(slot) and slot.get_child_count() > 0:
				var card := slot.get_child(0) as CardView
				rect = card.get_global_rect()
			else:
				var book := main.get_node("%BookPanel") as Control
				rect = Rect2(book.get_global_rect().get_center() - TILE_SIZE * 0.5, TILE_SIZE)
	return rect if rect.has_area() else Rect2(get_viewport_rect().get_center() - TILE_SIZE * 0.5, TILE_SIZE)
