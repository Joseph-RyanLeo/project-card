extends Control

## 牌堆、模态三选一、落位演出共用真实事件牌；正式选择仍由协调器保存。
signal path_chosen(id: String)
signal choices_ready
const CardView = preload("res://scripts/ui/event_card_view.gd")
const TarotBacks = preload("res://scripts/data/event_tarot_backs.gd")
const Art = preload("res://scripts/ui/tabletop_art.gd")
const Header = preload("res://scripts/ui/tabletop_header.gd")
const Dust = preload("res://scripts/ui/event_landing_dust.gd")
const DiceRoll = preload("res://scripts/ui/event_dice_roll.gd")
const INK_SHADER = preload("res://shaders/card_death_dissolve.gdshader")
const DETAIL_POSITION := Vector2(368, 70) # 事件纸正文左上角，保留左侧纸签
const DETAIL_SIZE := Vector2(466, 207) # 正文滚动区原生尺寸
const REWARD_COLUMN_WIDTH := 176.0 # 右侧奖励叠牌区的最大宽度
const REWARD_TEXT_MIN_WIDTH := 176.0 # 左栏给正文保留的最低宽度
const REWARD_GAP := 12.0 # 奖励叠牌与左侧正文的间距
const REWARD_CARD_STEP := Vector2(24, 3) # 每张叠牌最大横移和下移量
const REWARD_HOVER_LIFT := 7.0 # 指向时把被盖住的奖励抬起
const REWARD_Z_STEP := 90 # 每张卡保留足够层级容纳自身图标和闪卡图层
const REWARD_STACK_Z_LIMIT := 12 # 限制叠牌累计层级，给上层窗口和提示保留绘制空间
const DICE_COLUMN_WIDTH := 143.0 # 骰子停靠在纸张右侧所占宽度
const DICE_GAP := 9.0 # 左侧结果与骰子列的间距
const DICE_THROW_BOX := Vector2(164, 164) # 骰子演出控件的宽高
const INK_SECONDS := 0.65 # 旧事件文字与按钮溶解的时长
const DECK_CORNER_LIFT_SECONDS := 0.075 # 右上角先掀起的时长
const DECK_LEVEL_SECONDS := 0.085 # 整张牌抬平的时长
const DECK_LEVEL_HOLD_SECONDS := 0.02 # 略高于牌堆时保持平整的时长
const DECK_CORNER_LAND_SECONDS := 0.065 # 右上角先落向牌堆的时长
const DECK_SETTLE_SECONDS := 0.075 # 其余牌面跟着落稳的时长
const DECK_LIFT_POSE := Vector4(-0.4, 0.15, -1.1, 6.0) # 右上角先抬的姿态，依次为透视X、透视Y、旋转度数、整体抬升像素
const DECK_LEVEL_POSE := Vector4(0.0, 0.0, 0.0, 9) # 四角同高的悬空平面
const DECK_LAND_POSE := Vector4(0.2, -0.55, 0.7, 5.05) # 右上角先触堆时的姿态，剩余三角还在空中
const TABLE_SIZE := Vector2(902, 351) # 新事件棋盘原生大小
const SELECTED_POSITION := Vector2(116, 108) # 描述状态的事件牌左上角
const DECK_POSITION := Vector2(368, 88) # 中央牌堆的原稿位置
const CHOICE_SCALE: float = 2.0 # 模态三张牌固定按原图2倍展示
const CHOICE_GAP: float = 36.0 # 三张放大牌之间的水平空隙
const DEAL_SECONDS: float = 0.32 # 每张牌从牌堆飞至屏幕中央的时长
const DEAL_INTERVAL: float = 0.10 # 三张牌依次飞出的时间差
const FLIP_SECONDS: float = 0.14 # 翻牌收拢和展开各自的时长
const SHOP_FACE_HOLD_SECONDS: float = 1.0 # 商店牌翻到正面后停留的秒数
const BOARD_SECONDS: float = 0.30 # 旧棋盘退场和描述棋盘落下的时长
const MOVE_SECONDS: float = 0.34 # 选中牌缩回原生尺寸并落入左侧卡位的时长
const CHARACTER_SECONDS: float = 0.045 # 描述与选项每个字符跳出的间隔，约每秒22字
const TEXT_LINE_PAUSE: float = 0.16 # 描述段落结束后开始下一段的停顿
const OPTION_ENTER_SECONDS: float = 0.28 # 选项条整体上移并渐显的时长
const OPTION_ENTER_OFFSET: float = 12.0 # 选项条从目标下方飞入的距离
const REVEAL_CLICK_SPEED: float = 1.8 # 每次点击让正在进行的描述/选项演出加速的倍率
const REVEAL_MAX_SPEED: float = 8.0 # 连点加速的上限
const DIM_ALPHA: float = 0.70 # 三选一时除候选牌外的背景压暗程度
var main: Control
var cards: Array[Button] = []
var detail_body: VBoxContainer
var busy: bool = false
var chosen_index := -1
var _nyx_road_index := -1
var _paths: Array[Dictionary] = []
var _board: Control
var _modal: Control
var _dim: ColorRect
var _deck: Button
var _deck_top: EventCardView
var _deck_jump: Tween
var _paper: ScrollContainer
var _show_detail_immediately := false
var _choice_backs: Array[Dictionary] = []
var _text_reveal: Tween
var _reveal_speed := 1.0

func _board_surface() -> Control:
	var board := Control.new()
	board.size = TABLE_SIZE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	Art.art(board, "event_board.png", Vector2.ZERO)
	var header := Header.new()
	header.main = main
	board.add_child(header)
	return board

func show_choices(paths: Array[Dictionary], _animate: bool, deal_key: String = "", nyx_road_index: int = -1) -> void:
	custom_minimum_size = TABLE_SIZE
	size = TABLE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paths = paths.duplicate(true)
	_nyx_road_index = nyx_road_index
	for path: Dictionary in _paths:
		_choice_backs.append(TarotBacks.pick(path, deal_key))
	_board = _board_surface()
	_deck = Button.new()
	_deck.name = "EventDeck"
	_deck.position = DECK_POSITION
	_deck.size = Vector2(166, 153) # 整个牌堆含下方叠牌厚度均可点击
	_deck.tooltip_text = "点击牌堆，抽取三张事件牌"
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_deck.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_board.add_child(_deck)
	var deck_art := Art.art(_deck, "event_deck.png", Vector2.ZERO)
	if not _paths.is_empty():
		# 下层直接画第二张待抽的牌，抬起顶牌时露出的牌背与发牌一致。
		var depth_origin := Vector2(0, CardView.CARD_SIZE.y)
		deck_art.texture = Art.atlas("event_deck.png", Rect2(depth_origin, _deck.size - depth_origin))
		deck_art.position = depth_origin
		deck_art.size = deck_art.texture.get_size()
		_add_deck_card(mini(1, _paths.size() - 1), "DeckNextCard")
		_deck_top = _add_deck_card(0, "DeckTopCard")
		_deck_top.prepare_back_projection()
	_deck.mouse_entered.connect(_jump_deck_top)
	_deck.pressed.connect(_deal)


func _add_deck_card(index: int, card_name: String) -> EventCardView:
	var card := CardView.new()
	card.name = card_name
	card.definition = _paths[index]
	card.tarot_back = _choice_backs[index].get("texture")
	card.tarot_reversed = _choice_backs[index].get("reversed", false)
	card.disabled = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck.add_child(card)
	return card


func _jump_deck_top() -> void:
	if busy or not is_instance_valid(_deck_top) or (is_instance_valid(_deck_jump) and _deck_jump.is_running()): return
	_deck_jump = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_deck_jump.tween_method(_pose_deck_top, Vector4.ZERO, DECK_LIFT_POSE, DECK_CORNER_LIFT_SECONDS)
	_deck_jump.tween_method(_pose_deck_top, DECK_LIFT_POSE, DECK_LEVEL_POSE, DECK_LEVEL_SECONDS)
	_deck_jump.tween_interval(DECK_LEVEL_HOLD_SECONDS)
	_deck_jump.tween_method(_pose_deck_top, DECK_LEVEL_POSE, DECK_LAND_POSE, DECK_CORNER_LAND_SECONDS)
	_deck_jump.tween_method(_pose_deck_top, DECK_LAND_POSE, Vector4.ZERO, DECK_SETTLE_SECONDS)


func _pose_deck_top(pose: Vector4) -> void:
	_deck_top.back_tilt = Vector2(pose.x, pose.y)
	_deck_top.rotation_degrees = pose.z
	_deck_top.position.y = -pose.w


func _deal() -> void:
	if busy or is_instance_valid(_modal): return
	busy = true
	main._cancel_click_carry()
	main._close_toolbox_inspection(false)
	_deck.disabled = true
	var top_offset := Vector2.ZERO
	var top_angle := 0.0
	if is_instance_valid(_deck_jump): _deck_jump.kill()
	if is_instance_valid(_deck_top):
		top_offset = _deck_top.position
		top_angle = _deck_top.rotation
	_modal = Control.new()
	_modal.name = "EventChoiceOverlay"
	_modal.top_level = true
	_modal.position = Vector2.ZERO
	_modal.size = Vector2(1280, 720) # 模态层使用逻辑画布，不随世界视角移动
	_modal.z_as_relative = false
	_modal.z_index = 2800 # 三张牌高于背景暗幕，仍低于检视与Esc菜单
	add_child(_modal)
	_dim = ColorRect.new()
	_dim.size = _modal.size
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(_dim)
	var dim_tween := create_tween()
	dim_tween.tween_property(_dim, "color:a", DIM_ALPHA, DEAL_SECONDS + DEAL_INTERVAL * 2)
	var card_size := CardView.CARD_SIZE * CHOICE_SCALE
	var total_width := card_size.x * _paths.size() + CHOICE_GAP * (_paths.size() - 1)
	var start := Vector2((1280.0 - total_width) * 0.5, (720.0 - card_size.y) * 0.5)
	for index: int in _paths.size():
		var card := CardView.new()
		card.name = "EventChoice%d" % index
		card.definition = _paths[index]
		card.tarot_back = _choice_backs[index].get("texture")
		card.tarot_reversed = _choice_backs[index].get("reversed", false)
		card.z_index = _paths.size() - index # 先抽的牌在上，后抽的牌始终从下面飞出
		_modal.add_child(card)
		if index == _nyx_road_index:
			var marker := Label.new()
			marker.text = "奈克斯指定"
			marker.position = Vector2(3, -18) # 置于指定牌背上方，不遮盖牌图
			marker.add_theme_color_override("font_color", Color("ebc68f"))
			marker.add_theme_font_size_override("font_size", 10) # 按事件牌倍率放大
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(marker)
		card.pivot_offset = Vector2.ZERO
		card.position = _board.global_position + DECK_POSITION
		if index == 0:
			# 在跳起时点牌，第一张从当前姿态接着飞出。
			card.position += top_offset + CardView.CARD_SIZE.rotated(top_angle) * -0.5 + CardView.CARD_SIZE * 0.5
			card.rotation = top_angle
			_deck_top.transfer_back_projection_to(card)
			_pose_deck_top(Vector4.ZERO)
		card.scale = Vector2.ONE
		card.disabled = true
		card.pressed.connect(_choose.bind(index))
		cards.append(card)
		var destination := start + Vector2(index * (card_size.x + CHOICE_GAP), 0)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", destination, DEAL_SECONDS).set_delay(index * DEAL_INTERVAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE * CHOICE_SCALE, DEAL_SECONDS).set_delay(index * DEAL_INTERVAL)
		if index == 0:
			tween.tween_property(card, "rotation", 0.0, DEAL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if not card.back_tilt.is_zero_approx():
				tween.tween_property(card, "back_tilt", Vector2.ZERO, DEAL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var unlock := create_tween()
	unlock.tween_interval(DEAL_SECONDS + (_paths.size() - 1) * DEAL_INTERVAL)
	unlock.tween_callback(_unlock_cards)

func _unlock_cards() -> void:
	busy = false
	for card: Button in cards:
		card.disabled = false
		card.set_choice_hover_enabled(true)
	choices_ready.emit()

func _choose(index: int) -> void:
	if busy: return
	busy = true
	var selected: Button = cards[index]
	selected.position.y -= selected._choice_lift * selected.scale.y
	for card: Button in cards:
		card.set_choice_hover_enabled(false)
		card.disabled = true
	selected.z_index = cards.size() + 1 # 选中后独立置顶，翻牌不被飞走的候选遮住
	# 选中瞬间开始退场；候选牌仍位于独立屏幕层，不跟着旧棋盘飞走。
	var leave := create_tween().set_parallel(true)
	leave.tween_property(_board, "position:y", -TABLE_SIZE.y - 16, BOARD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	for other: int in cards.size():
		if other == index: continue
		leave.tween_property(cards[other], "position", cards[other].position + Vector2(-700 if other < index else 700, -420), BOARD_SECONDS)
		leave.tween_property(cards[other], "rotation", -0.45 if other < index else 0.45, BOARD_SECONDS)
		leave.tween_property(cards[other], "modulate:a", 0.0, BOARD_SECONDS)
	var pivot := CardView.CARD_SIZE * 0.5
	selected.position += pivot * selected.scale
	selected.pivot_offset = pivot
	selected.position -= pivot
	var flip := create_tween()
	flip.tween_property(selected, "scale:x", 0.0, FLIP_SECONDS)
	flip.tween_callback(func(): selected.face_up = true)
	flip.tween_property(selected, "scale:x", CHOICE_SCALE, FLIP_SECONDS)
	await flip.finished
	if selected.definition.get("kind") == "shop":
		await get_tree().create_timer(SHOP_FACE_HOLD_SECONDS).timeout
		# 提交路径会释放旧事件页；将同一模态层交给Main，完成离场和渐亮。
		var overlay := _modal
		overlay.reparent(main, true)
		chosen_index = index
		path_chosen.emit(String(selected.definition.path_id))
		if not main.ordinary_shop_open:
			overlay.queue_free()
			return
		var depart := main.create_tween().set_parallel(true)
		depart.tween_property(selected, "position:y", -CardView.CARD_SIZE.y * CHOICE_SCALE, BOARD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		depart.tween_property(_dim, "color:a", 0.0, main.SHOP_OPEN_DURATION + main.SHOP_REBOUND_DURATION)
		depart.chain().tween_callback(overlay.queue_free)
		return
	var description := _board_surface()
	description.name = "IncomingEventBoard"
	description.position.y = -TABLE_SIZE.y - 16
	Art.art(description, "event_description.png", Vector2(311, 57))
	var arrive := create_tween().set_parallel(true)
	arrive.tween_property(description, "position:y", 0.0, BOARD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	arrive.tween_property(_dim, "color:a", 0.0, BOARD_SECONDS)
	await arrive.finished
	var move := create_tween().set_parallel(true)
	move.tween_property(selected, "position", global_position + SELECTED_POSITION, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(selected, "scale", Vector2.ONE, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await move.finished
	# 提交后协调器会重建描述状态；烟尘交给描述页，避免旧页释放时中断。
	chosen_index = index
	path_chosen.emit(String(selected.definition.path_id))

func show_selected(path: Dictionary, reveal: bool = false) -> void:
	custom_minimum_size = TABLE_SIZE
	size = TABLE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board = _board_surface()
	Art.art(_board, "event_description.png", Vector2(311, 57))
	var card := CardView.new()
	card.name = "SelectedEventCard"
	card.definition = path
	card.face_up = true
	card.disabled = true
	add_child(card)
	card.position = SELECTED_POSITION
	_paper = ScrollContainer.new()
	_paper.name = "EventDescription"
	_paper.position = DETAIL_POSITION
	_paper.size = DETAIL_SIZE
	_paper.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_paper.add_theme_font_override("font", CardView.FONT)
	add_child(_paper)
	detail_body = VBoxContainer.new()
	var typography := Theme.new()
	typography.default_font = CardView.FONT
	detail_body.theme = typography
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_constant_override("separation", 8) # 描述和选项的垂直间隔
	_paper.add_child(detail_body)
	if reveal:
		var dust := Dust.new()
		dust.position = SELECTED_POSITION - Vector2(80, 70) # 粒子范围围绕牌边，避免烟团盖满卡图
		add_child(dust)
	# 协调器随后同步添加描述和选项；推迟到布局完成后统一启动逐字显示。
	_reveal_detail_text.call_deferred()

func play_story_roll(roll: Control, sides: int, result: int) -> void:
	if is_instance_valid(_text_reveal): _text_reveal.kill()
	var ink := ShaderMaterial.new()
	ink.shader = INK_SHADER
	ink.set_shader_parameter("noise_scale", 10.0)
	ink.set_shader_parameter("dissolve_fill_color", Color(0.25, 0.12, 0.08, 0.54))
	ink.set_shader_parameter("dissolve_outline_color", Color(0.25, 0.12, 0.08, 0.65))
	_paper.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	for control: Control in detail_body.find_children("*", "Control", true, false):
		control.material = ink
	roll.size = DICE_THROW_BOX
	roll.position = DETAIL_POSITION + (DETAIL_SIZE - DICE_THROW_BOX) * 0.5
	roll.hide()
	add_child(roll)
	roll.prepare(sides, result)
	var animation := create_tween()
	animation.tween_method(func(value: float):
		ink.set_shader_parameter("dissolve_progress", value)
		ink.set_shader_parameter("edge_progress", value - 0.12),
		0.0, 1.12, INK_SECONDS)
	animation.tween_callback(func():
		_paper.hide()
		roll.show()
		roll.play_prepared(_dice_rest_position().x))


func show_detail_immediately() -> void:
	_show_detail_immediately = true


func show_reward_cards(tiles: Array[Control]) -> void:
	if tiles.is_empty(): return
	var column := Control.new()
	column.name = "EventRewardCards"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var largest := Vector2.ZERO
	for tile: Control in tiles: largest = largest.max(tile.size)
	var gaps := maxi(1, tiles.size() - 1)
	var width := clampf(_paper.size.x - REWARD_TEXT_MIN_WIDTH - REWARD_GAP, largest.x, REWARD_COLUMN_WIDTH)
	var available := Vector2(width, _paper.size.y)
	var step := REWARD_CARD_STEP.min((available - largest).max(Vector2.ZERO) / gaps)
	var stack_size := largest + step * (tiles.size() - 1)
	column.size = Vector2(stack_size.x, _paper.size.y)
	column.position = Vector2(_paper.position.x + _paper.size.x - column.size.x, _paper.position.y)
	add_child(column)
	_paper.size.x -= column.size.x + REWARD_GAP
	var origin := Vector2(0, (column.size.y - stack_size.y) * 0.5)
	for index: int in tiles.size():
		var tile := tiles[index]
		column.add_child(tile)
		tile.position = (origin + step * index).round()
		var resting_z := mini(index, REWARD_STACK_Z_LIMIT) * REWARD_Z_STEP
		tile.z_index = resting_z
		var card := tile.get_child(0) as Control
		var rest := card.position
		tile.mouse_entered.connect(func():
			tile.z_index = mini(tiles.size(), REWARD_STACK_Z_LIMIT + 1) * REWARD_Z_STEP
			card.position.y = rest.y - REWARD_HOVER_LIFT)
		tile.mouse_exited.connect(func():
			tile.z_index = resting_z
			card.position = rest)


func show_story_result(sides: int, result: int) -> void:
	show_detail_immediately()
	_paper.size.x = DETAIL_SIZE.x - DICE_COLUMN_WIDTH - DICE_GAP
	var roll := DiceRoll.new()
	add_child(roll)
	roll.name = "SettledEventDice"
	roll.size = DICE_THROW_BOX
	roll.position = _dice_rest_position()
	roll.show_result(sides, result)


func _dice_rest_position() -> Vector2:
	return DETAIL_POSITION + Vector2(DETAIL_SIZE.x - (DICE_COLUMN_WIDTH + DICE_THROW_BOX.x) * 0.5, (DETAIL_SIZE.y - DICE_THROW_BOX.y) * 0.5)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_text_reveal) or not _text_reveal.is_running(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for slot: PanelContainer in main._card_service_slots():
			if slot.is_visible_in_tree() and slot.get_global_rect().has_point(event.position): return
		var paper := get_node_or_null("EventDescription") as Control
		if is_instance_valid(paper) and paper.get_global_rect().has_point(event.position):
			_reveal_speed = minf(_reveal_speed * REVEAL_CLICK_SPEED, REVEAL_MAX_SPEED)
			_text_reveal.set_speed_scale(_reveal_speed)
			get_viewport().set_input_as_handled()

func _reveal_detail_text() -> void:
	if not is_inside_tree() or not is_instance_valid(detail_body): return
	if _show_detail_immediately: return
	var nodes := detail_body.find_children("*", "Control", true, false)
	for node: Control in nodes:
		if _inside_service_slot(node): continue
		if node is Button:
			# VBoxContainer会在描述换行后重新排版。外层保留排版位置，
			# 仅移动内部按钮，避免Tween用旧坐标把选项拉回文字上方。
			var parent := node.get_parent()
			var index := node.get_index()
			var frame := Control.new()
			frame.name = "OptionMotionFrame"
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			frame.custom_minimum_size.y = node.get_combined_minimum_size().y
			parent.add_child(frame)
			parent.move_child(frame, index)
			node.reparent(frame, false)
			node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			node.minimum_size_changed.connect(func(): frame.custom_minimum_size.y = node.get_combined_minimum_size().y)
			node.modulate.a = 0.0
		elif node is Label: node.visible_characters = 0
	_text_reveal = create_tween()
	_text_reveal.tween_interval(0.10)
	for node: Control in nodes:
		if _inside_service_slot(node): continue
		if node is Button:
			_text_reveal.tween_callback(func(): node.position = Vector2(0, OPTION_ENTER_OFFSET))
			_text_reveal.tween_property(node, "position", Vector2.ZERO, OPTION_ENTER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_text_reveal.parallel().tween_property(node, "modulate:a", 1.0, OPTION_ENTER_SECONDS)
		elif node is Label and not node.text.is_empty():
			_text_reveal.tween_property(node, "visible_characters", node.get_total_character_count(), node.get_total_character_count() * CHARACTER_SECONDS)
			_text_reveal.tween_interval(TEXT_LINE_PAUSE)

func _inside_service_slot(node: Node) -> bool:
	var ancestor := node.get_parent()
	while ancestor != detail_body and ancestor != null:
		if ancestor.name == "EventRewardPreviews" or ancestor is CardView or ancestor.get_script() == preload("res://scripts/ui/card_service_slot.gd"): return true
		ancestor = ancestor.get_parent()
	return false
