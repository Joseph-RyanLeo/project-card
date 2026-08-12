class_name SquadView
extends PanelContainer

signal squad_clicked(squad_view: SquadView, card_data: CardData)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const CARD_SNAPSHOT_VISUAL_SCRIPT: Script = preload(
	"res://scripts/ui/card_snapshot_visual.gd"
)
const CARD_SIZE := Vector2(99, 136) # 每张随从卡始终保持的完整裸卡尺寸
const PREVIEW_ALPHA: float = 0.4 # 放置预览中待加入卡牌的不透明度
const INACTIVE_ATTRIBUTE_ALPHA: float = 0.4 # 非属性来源卡牌对应图标与数字的不透明度
const MODE_SWITCH_HOVER_SECONDS: float = 0.65 # 悬停多久后在“随从/小队”操作对象之间切换
const CARD_LIFT_OFFSET: float = 7.0 # 随从优先反馈时，鼠标下卡牌向上抽出的距离
const SQUAD_LIFT_OFFSET: float = 7.0 # 小队整体反馈时，全部成员一起向上提起的距离
const SQUAD_SHAKE_ANGLE: float = 2.5 # 小队优先反馈触发时左右短促震动的角度
const SQUAD_SHAKE_DURATION: float = 0.13 # 小队优先反馈单次震动的总时长（秒）
const STACK_TARGET_MAX_ROTATION_ANGLE: float = 2.0 # 拖动卡贴近合法目标时，目标小队持续旋转颤动的最大角度
const STACK_TARGET_ROTATION_CYCLES_PER_SECOND: float = 4.0 # 合法叠卡目标每秒完成左右旋转颤动的次数
const SQUAD_SHADOW_OFFSET := Vector2(5.0, 7.0) # 小队整体阴影相对小队的偏移
const SQUAD_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.34) # 小队整体反馈阴影的颜色与透明度
const LAYOUT_TWEEN_DURATION: float = 0.15 # 小队随行布局让位、恢复和飞入的动画时长（秒）
const PATTERN_LABEL_SIZE := Vector2(64.0, 14.0) # 小队牌型名称标签的固定显示尺寸
const PATTERN_LABEL_TOP: float = 132.0 # 牌型标签顶边相对卡牌顶边的像素位置
const REAL_PATTERN_COLOR := Color(1.0, 0.91, 0.58, 1.0) # 真实牌型名称使用的文字颜色
const PREVIEW_PATTERN_COLOR := Color(0.58, 0.9, 1.0, 0.9) # 假设牌型名称使用的文字颜色与透明度

var squad_data: SquadData
var _preview_squad_data: SquadData
var _preview_ghost_card: CardData # 预览中唯一半透明的卡；为空时整队都是虚影
var _card_views: Dictionary = {}
var _drag_enabled: bool = false
var _source_row: Node
var _prefer_minion: bool = true
var _hovered_card: CardData
var _active_drag_kind: StringName = &"card"
var _locked_drag_kind: StringName = &""
var _locked_drag_card: CardData
var _drag_hidden_card: CardData
var _last_clicked_card: CardData
var _mode_timer: Timer
var _squad_shadow: Panel
var _shake_tween: Tween
var _layout_tween: Tween
var _stack_target_feedback_strength: float = 0.0
var _stack_target_rotation_phase: float = 0.0
var _stack_target_snapshot_layer: Control
var _squad_feedback_active: bool = false
var _displayed_pattern_result: RunePatternResult

@onready var stack_feedback_layer: Control = %StackFeedbackLayer
@onready var squad_lift_layer: Control = %SquadLiftLayer
@onready var card_visual_layer: Control = %CardVisualLayer
@onready var pattern_label: Label = %PatternLabel


func _ready() -> void:
	_create_mode_timer()
	_create_squad_shadow()
	_refresh()
	set_process(false)


func _process(delta: float) -> void:
	if _stack_target_feedback_strength <= 0.0:
		set_process(false)
		return
	_stack_target_rotation_phase += (
		delta * STACK_TARGET_ROTATION_CYCLES_PER_SECOND * TAU
	)
	stack_feedback_layer.rotation_degrees = (
		sin(_stack_target_rotation_phase)
		* STACK_TARGET_MAX_ROTATION_ANGLE
		* _stack_target_feedback_strength
	)


func set_squad_data(value: SquadData) -> void:
	squad_data = value
	_preview_squad_data = null
	_preview_ghost_card = null
	if is_node_ready():
		_refresh()


func get_squad_data() -> SquadData:
	return squad_data


func set_preview_squad(value: SquadData, ghost_card: CardData = null) -> void:
	squad_data = null
	_preview_squad_data = value
	_preview_ghost_card = ghost_card
	if is_node_ready():
		_refresh()


func is_preview() -> bool:
	return _preview_squad_data != null


func _get_card_preview_alpha(card_data: CardData) -> float:
	return (
		PREVIEW_ALPHA
		if is_preview()
		and (_preview_ghost_card == null or card_data == _preview_ghost_card)
		else 1.0
	)


func get_display_data() -> SquadData:
	return _preview_squad_data if is_preview() else squad_data


func get_displayed_pattern_result() -> RunePatternResult:
	return _displayed_pattern_result


func _get_current_visual_squad_data() -> SquadData:
	var data := get_display_data()
	if data == null or _drag_hidden_card == null or is_preview():
		return data
	# 从小队抽出单卡时，真实数据要等成功 drop 后才修改；拖动期间的
	# 实时卡牌与颤动快照都必须使用同一份“临时移除该卡”的显示副本。
	var visible_data := data.duplicate_squad()
	visible_data.remove_card(_drag_hidden_card)
	return visible_data


func get_card_data() -> CardData:
	var data := get_display_data()
	return data.horizontal_cards[0] if data != null and not data.horizontal_cards.is_empty() else null


func get_last_clicked_card() -> CardData:
	return _last_clicked_card if _last_clicked_card != null else get_card_data()


func get_card_view(card_data: CardData) -> CardView:
	return _card_views.get(card_data) as CardView


func fade_card_preview_glow(
	card_data: CardData,
	glow_state: Dictionary
) -> void:
	var live_card := get_card_view(card_data)
	if live_card != null:
		live_card.fade_preview_glow_state(glow_state)
	if not has_stack_target_snapshots():
		return
	var data := _get_current_visual_squad_data()
	var horizontal_index := (
		data.horizontal_cards.find(card_data) if data != null else -1
	)
	var snapshot := _stack_target_snapshot_layer.get_node_or_null(
		"CardSnapshot_%d" % horizontal_index
	) as CardSnapshotVisual
	if snapshot != null:
		var snapshot_card := snapshot.get_source_card_view() as CardView
		if snapshot_card != null:
			snapshot_card.fade_preview_glow_state(glow_state)


func get_primary_card_view() -> CardView:
	return get_card_view(get_card_data())


func set_stack_target_feedback(strength: float) -> void:
	var next_strength := clampf(strength, 0.0, 1.0)
	if next_strength <= 0.0:
		_stack_target_feedback_strength = 0.0
		_stack_target_rotation_phase = 0.0
		if is_instance_valid(stack_feedback_layer):
			stack_feedback_layer.rotation_degrees = 0.0
		_remove_stack_target_snapshots()
		set_process(false)
		return
	if _stack_target_feedback_strength <= 0.0:
		_stack_target_rotation_phase = 0.0
	_stack_target_feedback_strength = next_strength
	_ensure_stack_target_snapshots()
	set_process(true)


func get_stack_target_feedback_strength() -> float:
	return _stack_target_feedback_strength


func is_stack_target_rotation_active() -> bool:
	return _stack_target_feedback_strength > 0.0 and is_processing()


func has_stack_target_snapshots() -> bool:
	return (
		is_instance_valid(_stack_target_snapshot_layer)
		and _stack_target_snapshot_layer.get_child_count() > 0
	)


func get_stack_target_snapshot_count() -> int:
	return (
		_stack_target_snapshot_layer.get_child_count()
		if is_instance_valid(_stack_target_snapshot_layer)
		else 0
	)


func get_card_views() -> Array[CardView]:
	var views: Array[CardView] = []
	var data := get_display_data()
	if data == null:
		return views
	for card_data: CardData in data.horizontal_cards:
		var view := get_card_view(card_data)
		if view != null:
			views.append(view)
	return views


func configure_drag_source(enabled: bool, source_row: Node = null) -> void:
	_drag_enabled = enabled and not is_preview()
	_source_row = source_row
	for card_data: CardData in _card_views:
		var card_view := _card_views[card_data] as CardView
		card_view.configure_drag_source(_drag_enabled, &"board", source_row, self)
	if not _drag_enabled:
		reset_hover_feedback()


func set_prefer_minion(value: bool) -> void:
	_prefer_minion = value
	if _hovered_card != null:
		_apply_immediate_hover_subject()
		if _is_single_card_squad():
			_mode_timer.stop()
		else:
			_mode_timer.start(MODE_SWITCH_HOVER_SECONDS)


func get_active_drag_kind() -> StringName:
	return _locked_drag_kind if not _locked_drag_kind.is_empty() else _active_drag_kind


func enrich_drag_data(data: Dictionary, card_data: CardData) -> Dictionary:
	var enriched := data.duplicate()
	if _locked_drag_kind.is_empty():
		_locked_drag_kind = _get_lockable_drag_kind()
		_locked_drag_card = card_data
	enriched["kind"] = _locked_drag_kind
	enriched["card_data"] = _locked_drag_card
	enriched["squad_data"] = squad_data
	enriched["source_squad"] = self
	enriched["source_card_index"] = (
		squad_data.horizontal_cards.find(_locked_drag_card)
		if squad_data != null
		else -1
	)
	if _locked_drag_kind == &"squad" and squad_data != null:
		var horizontal_index := squad_data.horizontal_cards.find(_locked_drag_card)
		var squad_grab_position: Vector2 = enriched.get("grab_local_position", Vector2.ZERO)
		if horizontal_index >= 0:
			squad_grab_position.x += squad_data.get_card_x_positions()[horizontal_index]
		enriched["grab_local_position"] = squad_grab_position
		enriched["preview_offset"] = squad_grab_position * (enriched.get("preview_scale", Vector2.ONE) as Vector2)
		enriched["card_data"] = squad_data.get_effect_source()
		enriched["squad_cards"] = squad_data.horizontal_cards.duplicate()
		enriched["squad_x_positions"] = squad_data.get_card_x_positions()
		enriched["squad_layer_cards"] = squad_data.layer_cards.duplicate()
		enriched["squad_size"] = Vector2(squad_data.get_display_width(), CARD_SIZE.y)
	return enriched


func lock_drag_subject(card_data: CardData) -> void:
	if not _locked_drag_kind.is_empty():
		return
	_locked_drag_kind = _get_lockable_drag_kind()
	_locked_drag_card = card_data


func unlock_drag_subject() -> void:
	_locked_drag_kind = &""
	_locked_drag_card = null


func set_drag_hidden_card(card_data: CardData) -> void:
	_drag_hidden_card = card_data
	_refresh()


func clear_drag_hidden_card() -> void:
	if _drag_hidden_card == null:
		return
	_drag_hidden_card = null
	_refresh()


func animate_from_global_position(previous_global_position: Vector2) -> void:
	if not visible or is_preview():
		return
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	var current_global_position := global_position
	card_visual_layer.position += previous_global_position - current_global_position
	_layout_tween = create_tween()
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	_layout_tween.set_ease(Tween.EASE_OUT)
	_layout_tween.tween_property(
		card_visual_layer,
		"position",
		Vector2.ZERO,
		LAYOUT_TWEEN_DURATION
	)


func is_layout_animating() -> bool:
	return _layout_tween != null and _layout_tween.is_valid() and _layout_tween.is_running()


func reset_hover_feedback() -> void:
	if is_instance_valid(_mode_timer):
		_mode_timer.stop()
	_hovered_card = null
	_active_drag_kind = _get_immediate_drag_kind()
	_locked_drag_kind = &""
	_locked_drag_card = null
	_set_squad_feedback(false)
	for card_view: CardView in get_card_views():
		card_view.clear_pointer_hover_feedback()


func _refresh() -> void:
	if not is_node_ready():
		return
	_remove_stack_target_snapshots()

	var data := get_display_data()
	if data == null or not data.is_valid():
		_clear_card_views()
		_displayed_pattern_result = null
		pattern_label.visible = false
		custom_minimum_size = CARD_SIZE
		size = CARD_SIZE
		visible = false
		return
	_sync_card_views(data)

	var display_data := _get_current_visual_squad_data()
	if display_data.horizontal_cards.is_empty():
		for card_view: CardView in _card_views.values():
			card_view.visible = false
		visible = false
		return
	visible = true
	var display_width := float(display_data.get_display_width())
	_refresh_pattern_label(data, display_width)
	var highlighted_runes_by_card := _get_highlighted_runes_by_card(
		data,
		_displayed_pattern_result
	)
	custom_minimum_size = Vector2(display_width, CARD_SIZE.y)
	size = custom_minimum_size
	card_visual_layer.custom_minimum_size = custom_minimum_size
	card_visual_layer.pivot_offset = custom_minimum_size * 0.5
	stack_feedback_layer.custom_minimum_size = custom_minimum_size
	stack_feedback_layer.size = custom_minimum_size
	stack_feedback_layer.pivot_offset = custom_minimum_size * 0.5
	squad_lift_layer.custom_minimum_size = custom_minimum_size
	_apply_squad_lift_position()
	if is_instance_valid(_squad_shadow):
		_squad_shadow.size = custom_minimum_size
		_squad_shadow.custom_minimum_size = custom_minimum_size

	var x_positions := display_data.get_card_x_positions()
	for horizontal_index: int in display_data.horizontal_cards.size():
		var card_data := display_data.horizontal_cards[horizontal_index]
		var card_view := get_card_view(card_data)
		card_view.visible = true
		card_view.set_layout_position(
			Vector2(x_positions[horizontal_index], 0.0)
		)
		card_view.set_card_data(card_data)
		card_view.set_rune_pattern_highlights(
			_get_card_highlight_indices(highlighted_runes_by_card, card_data),
			is_preview()
		)
		card_view.set_attribute_source_state(
			card_data == display_data.get_action_source(),
			card_data == display_data.get_vitals_source(),
			card_data == display_data.get_effect_source(),
			INACTIVE_ATTRIBUTE_ALPHA
		)
		card_view.configure_drag_source(_drag_enabled, &"board", _source_row, self)
		card_view.modulate.a = _get_card_preview_alpha(card_data)
		card_view.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
			if is_preview()
			else Control.MOUSE_FILTER_STOP
		)

	for layer_index: int in display_data.layer_cards.size():
		var layer_card := display_data.layer_cards[layer_index]
		var layer_view := get_card_view(layer_card)
		if layer_view != null:
			# 每张卡内部还有卡框、名字、属性等 0～20 的相对层级。
			# 整卡之间拉开固定大间隔，才能保证下层卡的任何子节点都不会穿过上层卡。
			layer_view.set_resting_z_index(
				(display_data.layer_cards.size() - layer_index)
				* CardView.CARD_LAYER_Z_STEP
			)
	# Control 的鼠标命中在重叠时还会参考兄弟节点顺序。
	# 将下层到上层依次排列，保证玩家点到哪张可见卡，就选中视觉上的最上层卡。
	var draw_child_index: int = 0
	for layer_index: int in range(display_data.layer_cards.size() - 1, -1, -1):
		var ordered_view := get_card_view(display_data.layer_cards[layer_index])
		if ordered_view != null:
			card_visual_layer.move_child(ordered_view, draw_child_index)
			draw_child_index += 1
	if _stack_target_feedback_strength > 0.0:
		_ensure_stack_target_snapshots()


func _refresh_pattern_label(data: SquadData, display_width: float) -> void:
	_displayed_pattern_result = data.get_rune_pattern_result()
	pattern_label.text = (
		"预览·%s" % _displayed_pattern_result.get_pattern_name()
		if is_preview()
		else _displayed_pattern_result.get_pattern_name()
	)
	pattern_label.modulate = (
		PREVIEW_PATTERN_COLOR if is_preview() else REAL_PATTERN_COLOR
	)
	pattern_label.custom_minimum_size = PATTERN_LABEL_SIZE
	pattern_label.size = PATTERN_LABEL_SIZE
	pattern_label.position = Vector2(
		floorf((display_width - PATTERN_LABEL_SIZE.x) * 0.5),
		PATTERN_LABEL_TOP
	)
	pattern_label.visible = true


func _get_highlighted_runes_by_card(
	data: SquadData, result: RunePatternResult
) -> Dictionary:
	var highlighted_by_card: Dictionary = {}
	if data == null or result == null:
		return highlighted_by_card
	var visible_slots := data.get_visible_rune_slots()
	for visible_index: int in result.participating_indices:
		if visible_index < 0 or visible_index >= visible_slots.size():
			continue
		var slot := visible_slots[visible_index]
		var card := slot["card"] as CardData
		if not highlighted_by_card.has(card):
			highlighted_by_card[card] = []
		var card_indices := highlighted_by_card[card] as Array
		card_indices.append(int(slot["rune_index"]))
	return highlighted_by_card


func _get_card_highlight_indices(
	highlighted_by_card: Dictionary, card_data: CardData
) -> Array[int]:
	var indices: Array[int] = []
	indices.assign(highlighted_by_card.get(card_data, []))
	return indices


func _sync_card_views(data: SquadData) -> void:
	# 与阶段 4 的固定 CardView 一样：已有卡牌复用原节点，只对真正
	# 加入/离开小队的卡做创建和释放，避免刷新中断鼠标与拖拽状态。
	for stored_card: CardData in _card_views.keys():
		if data.horizontal_cards.has(stored_card):
			continue
		var departing_view := get_card_view(stored_card)
		_card_views.erase(stored_card)
		if departing_view != null:
			card_visual_layer.remove_child(departing_view)
			departing_view.queue_free()

	for card_data: CardData in data.horizontal_cards:
		if get_card_view(card_data) != null:
			continue
		var card_view := CARD_VIEW_SCENE.instantiate() as CardView
		var horizontal_index := data.horizontal_cards.find(card_data)
		var x_positions := data.get_card_x_positions()
		card_view.position = Vector2(x_positions[horizontal_index], 0.0)
		card_view.set_card_data(card_data)
		card_view.card_clicked.connect(_on_card_clicked.bind(card_data))
		card_view.click_carry_requested.connect(_on_card_click_carry_requested)
		card_view.mouse_entered.connect(_on_card_mouse_entered.bind(card_data))
		card_view.mouse_exited.connect(_on_card_mouse_exited.bind(card_data))
		card_view.configure_drag_source(
			_drag_enabled,
			&"board",
			_source_row,
			self
		)
		card_view.modulate.a = _get_card_preview_alpha(card_data)
		card_view.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
			if is_preview()
			else Control.MOUSE_FILTER_STOP
		)
		card_visual_layer.add_child(card_view)
		_card_views[card_data] = card_view

	for stored_view: CardView in _card_views.values():
		stored_view.visible = false


func _clear_card_views() -> void:
	for card_view: CardView in _card_views.values():
		card_visual_layer.remove_child(card_view)
		card_view.queue_free()
	_card_views.clear()


func _ensure_stack_target_snapshots() -> void:
	if has_stack_target_snapshots() or not is_node_ready():
		return
	var data := _get_current_visual_squad_data()
	if data == null or not data.is_valid():
		return
	var snapshot_result := data.get_rune_pattern_result()
	var highlighted_runes_by_card := _get_highlighted_runes_by_card(
		data,
		snapshot_result
	)

	_stack_target_snapshot_layer = Control.new()
	_stack_target_snapshot_layer.name = "StackTargetSnapshotLayer"
	_stack_target_snapshot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack_target_snapshot_layer.custom_minimum_size = custom_minimum_size
	_stack_target_snapshot_layer.size = custom_minimum_size
	squad_lift_layer.add_child(_stack_target_snapshot_layer)

	var x_positions := data.get_card_x_positions()
	for horizontal_index: int in data.horizontal_cards.size():
		var card_data := data.horizontal_cards[horizontal_index]
		var snapshot_card := CARD_VIEW_SCENE.instantiate() as CardView
		var live_card := get_card_view(card_data)
		if live_card != null:
			snapshot_card.showing_effect = live_card.showing_effect
			snapshot_card.set_card_data(card_data)
		snapshot_card.set_rune_pattern_highlights(
			_get_card_highlight_indices(highlighted_runes_by_card, card_data),
			is_preview()
		)

		var snapshot := CARD_SNAPSHOT_VISUAL_SCRIPT.new() as CardSnapshotVisual
		snapshot.name = "CardSnapshot_%d" % horizontal_index
		# 先让快照容器进入场景树，随后 configure() 加入的 SubViewport 与
		# CardView 才会立即完成 _ready()，可以安全设置属性来源透明度。
		_stack_target_snapshot_layer.add_child(snapshot)
		# 目标进入反馈范围时会从实时节点切换为快照。这里使用最近邻采样，
		# 让旋转尚未开始的第一帧与原卡像素完全对齐，避免小号数字先跳 1px。
		# 活动拖动卡仍沿用 CardSnapshotVisual 默认的线性采样，以保持移动平滑。
		snapshot.configure(
			snapshot_card,
			CARD_SIZE,
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
		# configure() 会把 CardView 加入快照 SubViewport，使它完成 _ready()；
		# 属性节点此时才存在，因此来源透明度必须在这一步之后设置。
		snapshot_card.set_attribute_source_state(
			card_data == data.get_action_source(),
			card_data == data.get_vitals_source(),
			card_data == data.get_effect_source(),
			INACTIVE_ATTRIBUTE_ALPHA
		)
		snapshot_card.modulate.a = _get_card_preview_alpha(card_data)
		# 快照纹理包含左上越界图标的留白；减去留白后，裸卡左上角仍然
		# 精确落在原卡牌的水平位置，不会改变 30px / 60px 堆叠布局。
		snapshot.position = Vector2(
			x_positions[horizontal_index],
			0.0
		) - CardSnapshotVisual.CAPTURE_PADDING_TOP_LEFT

	for layer_index: int in data.layer_cards.size():
		var horizontal_index := data.horizontal_cards.find(
			data.layer_cards[layer_index]
		)
		if horizontal_index < 0:
			continue
		var snapshot := _stack_target_snapshot_layer.get_node(
			"CardSnapshot_%d" % horizontal_index
		) as CardSnapshotVisual
		snapshot.z_index = (
			(data.layer_cards.size() - layer_index)
			* CardView.CARD_LAYER_Z_STEP
		)
	card_visual_layer.visible = false


func _remove_stack_target_snapshots() -> void:
	if is_instance_valid(_stack_target_snapshot_layer):
		_stack_target_snapshot_layer.visible = false
		_stack_target_snapshot_layer.queue_free()
	_stack_target_snapshot_layer = null
	if is_instance_valid(card_visual_layer):
		card_visual_layer.visible = true


func _create_mode_timer() -> void:
	_mode_timer = Timer.new()
	_mode_timer.name = "ModeSwitchTimer"
	_mode_timer.one_shot = true
	_mode_timer.wait_time = MODE_SWITCH_HOVER_SECONDS
	_mode_timer.timeout.connect(_on_mode_switch_timeout)
	add_child(_mode_timer)


func _create_squad_shadow() -> void:
	_squad_shadow = Panel.new()
	_squad_shadow.name = "SquadInteractionShadow"
	_squad_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_shadow.show_behind_parent = true
	_squad_shadow.z_index = -20
	_squad_shadow.position = SQUAD_SHADOW_OFFSET
	_squad_shadow.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = SQUAD_SHADOW_COLOR
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	_squad_shadow.add_theme_stylebox_override("panel", style)
	add_child(_squad_shadow)
	move_child(_squad_shadow, 0)


func _on_card_clicked(_ignored: CardData, clicked_card: CardData) -> void:
	_last_clicked_card = clicked_card
	squad_clicked.emit(self, clicked_card)


func _on_card_click_carry_requested(data: Dictionary, pointer_global_position: Vector2) -> void:
	click_carry_requested.emit(data, pointer_global_position)


func _on_card_mouse_entered(card_data: CardData) -> void:
	if not _drag_enabled or is_preview():
		return
	_hovered_card = card_data
	_apply_immediate_hover_subject()
	if _is_single_card_squad():
		_mode_timer.stop()
	else:
		_mode_timer.start(MODE_SWITCH_HOVER_SECONDS)


func _on_card_mouse_exited(card_data: CardData) -> void:
	if _hovered_card != card_data or not _locked_drag_kind.is_empty():
		return
	reset_hover_feedback()


func _apply_immediate_hover_subject() -> void:
	_set_squad_feedback(false)
	_active_drag_kind = _get_immediate_drag_kind()
	if _active_drag_kind == &"card":
		var hovered_view := get_card_view(_hovered_card)
		if hovered_view != null:
			hovered_view.set_external_lift(CARD_LIFT_OFFSET)
	else:
		_clear_member_pointer_hover_feedback()
		_set_squad_feedback(true)


func _on_mode_switch_timeout() -> void:
	if _hovered_card == null or not _locked_drag_kind.is_empty():
		return
	# 单卡小队没有“整体抽取多张卡”的含义，始终保持单卡操作。
	if _is_single_card_squad():
		_apply_immediate_hover_subject()
		return
	if _prefer_minion:
		_active_drag_kind = &"squad"
		_clear_member_pointer_hover_feedback()
		_set_squad_feedback(true)
	else:
		_set_squad_feedback(false)
		_active_drag_kind = &"card"
		var hovered_view := get_card_view(_hovered_card)
		if hovered_view != null:
			hovered_view.show_pointer_hover_feedback()
			hovered_view.set_external_lift(CARD_LIFT_OFFSET)


func _clear_member_pointer_hover_feedback() -> void:
	for card_view: CardView in get_card_views():
		card_view.clear_pointer_hover_feedback()


func _get_immediate_drag_kind() -> StringName:
	if _is_single_card_squad():
		return &"card"
	return &"card" if _prefer_minion else &"squad"


func _get_lockable_drag_kind() -> StringName:
	return &"card" if _is_single_card_squad() else _active_drag_kind


func _is_single_card_squad() -> bool:
	return squad_data != null and squad_data.get_card_count() == 1


func _set_squad_feedback(value: bool) -> void:
	_squad_feedback_active = value
	if is_instance_valid(_squad_shadow):
		_squad_shadow.visible = value
	_apply_squad_lift_position()
	if not value:
		if _shake_tween != null and _shake_tween.is_valid():
			_shake_tween.kill()
		rotation_degrees = 0.0
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	rotation_degrees = 0.0
	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_SINE)
	_shake_tween.tween_property(self, "rotation_degrees", -SQUAD_SHAKE_ANGLE, SQUAD_SHAKE_DURATION * 0.3)
	_shake_tween.tween_property(self, "rotation_degrees", SQUAD_SHAKE_ANGLE, SQUAD_SHAKE_DURATION * 0.35)
	_shake_tween.tween_property(self, "rotation_degrees", 0.0, SQUAD_SHAKE_DURATION * 0.35)


func _apply_squad_lift_position() -> void:
	if not is_instance_valid(squad_lift_layer):
		return
	# 命中节点本身记录抽出距离，整队反馈也复用同一套稳定命中逻辑。
	# 外层只负责快照容器，不再整体平移所有可交互 CardView。
	squad_lift_layer.position = Vector2.ZERO
	var lift := SQUAD_LIFT_OFFSET if _squad_feedback_active else 0.0
	for card_view: CardView in get_card_views():
		card_view.set_external_lift(lift)
