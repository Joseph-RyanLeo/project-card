class_name BattlefieldRow
extends PanelContainer

## 单条战场行的布局、容量和拖放规则中心。
##
## 真实顺序只来自 SquadRow 中的非预览 BoardSlot；预留位与目标虚影都是临时节点。
## 拖动期间先构建 intent，再用 SquadData 副本展示；commit_card_drop 只发送事务信号，
## Main 才会真正移动数据。所有堆叠边界必须来自玩家看到的实体卡/实体小队。

signal board_slot_clicked(row: BattlefieldRow, slot: BoardSlot)
signal card_dropped(
	row: BattlefieldRow,
	insert_index: int,
	data: Dictionary,
	card_global_position: Vector2
)
signal card_click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal squads_changed

const BOARD_SLOT_SCENE: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")
const BATTLEFIELD_UNIT_COUNT: int = 21 # 单排可使用的战场单元总容量
const SINGLE_CARD_UNIT_COUNT: int = 3 # 单卡小队占用的战场单元数
const SINGLE_CARD_WIDTH: int = 99 # 单张裸卡保持的固定显示宽度
const SQUAD_GAP: int = 18 # 同一排相邻小队之间的固定间距
const FULL_ROW_DISPLAY_WIDTH: int = 801 # 七个单卡小队含六段间距的真实显示宽度
const DROP_PREVIEW_Z_INDEX: int = 1000 # 目标虚影高于所有真实小队、低于鼠标携带卡牌的全局层级
const STACK_TARGET_FEEDBACK_RADIUS: float = 700.0 # 拖动单卡时，附近合法叠卡目标开始持续旋转颤动的中心距离
const STACK_TARGET_FEEDBACK_SILENT_THRESHOLD: float = 0.3 # 距离衰减低于该强度时不旋转，避免远处卡面产生亚像素闪动
const STACK_TARGET_FEEDBACK_MIN_VISIBLE_STRENGTH: float = 0.5 # 进入有效区后的最低可见振幅，确保卡框与卡面一起明显轻晃
const STACK_OVERLAP_MIN: float = 10.0 # 两张卡相向边界至少覆盖该距离才进入叠卡吸附带
const STACK_SINGLE_RUNE_OVERLAP_MAX: float = 40.0 # 覆盖 10～40px 时按盖住一个符文处理
const STACK_OVERLAP_MAX: float = 70.0 # 覆盖 41～70px 时按盖住两个符文处理，超过后退出吸附带
const SQUAD_MERGE_OVERLAP_MIN: float = 41.0 # 四符文双卡整队覆盖单卡两个符文后才允许合并
const NEW_SQUAD_CENTER_RADIUS: float = 2.0 # 卡牌中心距真实间隙中心多近时明确选择独立放置
const STACKED_RUNE_STEP_WIDTH: float = 30.0 # 预留位中一个可堆叠符文对应的横向像素宽度
const COMPACT_SQUAD_RESERVATION_WIDTH: float = SINGLE_CARD_WIDTH + STACKED_RUNE_STEP_WIDTH + SQUAD_GAP # 紧密双卡整队预留：99px 卡宽 + 30px 符文步长 + 18px 小队间距
const RESERVATION_SWAP_HYSTERESIS: float = 0.5 # 留空换边时过滤亚像素抖动；实体越过中线 1px 即会触发交换

@export var row_title: String = "前排" # 显示在该战场行左上角的名称

@onready var row_title_label: Label = %RowTitleLabel
@onready var row_display_area: Control = %RowDisplayArea
@onready var squad_row: HBoxContainer = %SquadRow
@onready var placement_overlay: Control = %PlacementOverlay

var _drag_enabled: bool = false
var _prefer_minion: bool = true
# 目标虚影描述放下结果；reservation 则是唯一一块随拖动位置换位的空间预算。
var _preview_slot: BoardSlot
var _preview_insert_index: int = -1
var _preview_intent: Dictionary = {}
var _preview_pointer_x: float = INF
var _preview_replaced_slot: BoardSlot
var _reservation_slot: Control
var _reservation_insert_index: int = -1
var _reservation_width: float = 0.0
var _reservation_empty_width: float = 0.0
var _reservation_move_in_progress: bool = false
# 来源槽仅在拖动视觉中隐藏，真实 SquadData 在成功 drop 前保持不变。
var _hidden_source_slot: BoardSlot
var _active_drag_preview_offset: Vector2 = Vector2.ZERO
var _active_drag_visual: CardDragPreview
var _active_stack_feedback_drag_data: Dictionary = {}
var _merge_preview_anchor_card: CardData
var _merge_preview_alignment_revision: int = 0
var _preview_drag_visual: CardDragPreview


# --- 生命周期、行内容查询与真实槽增删 ---
func _ready() -> void:
	row_title_label.text = row_title
	row_display_area.custom_minimum_size.x = FULL_ROW_DISPLAY_WIDTH
	squad_row.add_theme_constant_override("separation", SQUAD_GAP)
	placement_overlay.set("battlefield_row", self)
	set_process(false)


func _process(_delta: float) -> void:
	if _active_stack_feedback_drag_data.is_empty():
		set_process(false)
		return
	if (has_active_drop_preview() or has_drop_reservation()) and is_finite(_preview_pointer_x):
		# 鼠标停下后拖拽实体仍会继续追赶；每帧沿用最后一个逻辑坐标，
		# 重新读取实体卡边界，避免虚影停在反向移动前的旧堆叠方向。
		preview_card_drop(
			Vector2(_preview_pointer_x, SquadView.CARD_SIZE.y * 0.5),
			_active_stack_feedback_drag_data,
			true
		)
		return
	var local_position := (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* get_viewport().get_mouse_position()
	)
	_update_stack_target_feedback(local_position.x, _active_stack_feedback_drag_data)


func get_squad_container() -> HBoxContainer:
	return squad_row


func get_squads() -> Array[BoardSlot]:
	return _get_real_slots()


func get_card_count() -> int:
	var count: int = 0
	for slot: BoardSlot in _get_real_slots():
		count += slot.get_squad_data().get_card_count()
	return count


func get_squad_count() -> int:
	return _get_real_slots().size()


func reset_all_hover_feedback() -> void:
	for slot: BoardSlot in _get_real_slots():
		slot.reset_hover_feedback()


func get_used_unit_count() -> int:
	var units: int = 0
	for slot: BoardSlot in _get_real_slots():
		units += slot.get_squad_data().get_unit_count()
	return units


func get_content_width() -> int:
	var slots := _get_real_slots()
	if slots.is_empty():
		return 0
	var width: int = 0
	for slot: BoardSlot in slots:
		width += slot.get_squad_data().get_display_width()
	return width + (slots.size() - 1) * SQUAD_GAP


func has_capacity_for_single_card() -> bool:
	return get_used_unit_count() + SINGLE_CARD_UNIT_COUNT <= BATTLEFIELD_UNIT_COUNT


func has_capacity_for_squad(squad_data: SquadData) -> bool:
	return (
		squad_data != null
		and get_used_unit_count() + squad_data.get_unit_count()
		<= BATTLEFIELD_UNIT_COUNT
	)


func add_card(card_data: CardData, insert_index: int) -> BoardSlot:
	return add_squad(SquadData.from_card(card_data), insert_index)


func add_squad(squad_data: SquadData, insert_index: int) -> BoardSlot:
	if squad_data == null or not squad_data.is_valid():
		return null
	var slot := BOARD_SLOT_SCENE.instantiate() as BoardSlot
	squad_row.add_child(slot)
	slot.set_squad_data(squad_data)
	_connect_slot(slot)
	_place_card_slot(slot, insert_index)
	squads_changed.emit()
	return slot


func remove_squad_slot(slot: BoardSlot) -> SquadData:
	if slot == null or slot.get_parent() != squad_row or slot.is_preview():
		return null
	var slots: Array[BoardSlot] = [slot]
	var removed := remove_squad_slots(slots)
	return removed[0] if not removed.is_empty() else null


func remove_squad_slots(slots: Array[BoardSlot]) -> Array[SquadData]:
	# 同批次阵亡必须一次捕获、一次删除、一次重排，避免连续 Tween
	# 互相覆盖，或幸存小队先瞬移到终点再退回旧位置开始补间。
	var valid_slots: Array[BoardSlot] = []
	for slot: BoardSlot in slots:
		if (
			is_instance_valid(slot)
			and slot.get_parent() == squad_row
			and not slot.is_preview()
			and not valid_slots.has(slot)
		):
			valid_slots.append(slot)
	if valid_slots.is_empty():
		return []
	var previous_positions := _capture_visible_slot_positions()
	var removed: Array[SquadData] = []
	for slot: BoardSlot in valid_slots:
		removed.append(slot.get_squad_data())
		squad_row.remove_child(slot)
		slot.queue_free()
	_animate_layout_immediately(previous_positions)
	squads_changed.emit()
	return removed


func clear_squads() -> void:
	# 战斗重开需要一次性恢复快照；批量清空避免把中间态当成多次事务。
	var removed_any := false
	for slot: BoardSlot in _get_real_slots():
		squad_row.remove_child(slot)
		slot.queue_free()
		removed_any = true
	if removed_any:
		squads_changed.emit()


func remove_card_from_squad(slot: BoardSlot, card_data: CardData) -> bool:
	if slot == null or slot.get_parent() != squad_row:
		return false
	var squad := slot.get_squad_data()
	if squad == null or not squad.contains(card_data):
		return false
	if squad.get_card_count() == 1:
		remove_squad_slot(slot)
	else:
		squad.remove_card(card_data)
		slot.set_squad_data(squad)
		slot.configure_drag_source(_drag_enabled, self)
		squads_changed.emit()
	return true


func get_slot_index(slot: BoardSlot) -> int:
	if slot == null or slot.get_parent() != squad_row or slot.is_preview():
		return -1
	return _get_real_slots().find(slot)


func move_card_slot(slot: BoardSlot, insert_index: int) -> void:
	move_squad_slot(slot, insert_index)


func move_squad_slot(
	slot: BoardSlot,
	insert_index: int,
	animate: bool = true
) -> void:
	if get_slot_index(slot) < 0:
		return
	var previous_positions := _capture_visible_slot_positions()
	_place_card_slot(slot, insert_index)
	if animate:
		_animate_layout_next_frame(previous_positions)


func _place_card_slot(slot: BoardSlot, insert_index: int) -> void:
	var remaining_slots := _get_real_slots()
	remaining_slots.erase(slot)
	var clamped_index := clampi(insert_index, 0, remaining_slots.size())
	if clamped_index == remaining_slots.size():
		squad_row.move_child(slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(slot, remaining_slots[clamped_index])


func set_drag_enabled(value: bool) -> void:
	_drag_enabled = value
	for slot: BoardSlot in _get_real_slots():
		slot.configure_drag_source(_drag_enabled, self)
	if not _drag_enabled:
		_finish_card_drag()


func set_prefer_minion(value: bool) -> void:
	_prefer_minion = value
	for slot: BoardSlot in _get_real_slots():
		slot.set_prefer_minion(value)


# --- 放置预览与提交入口 ---
func can_receive_card_drag(data: Variant) -> bool:
	return _drag_enabled and _is_drag_data(data)


func preview_card_drop(
	at_position: Vector2,
	data: Variant,
	force_recalculate: bool = false
) -> bool:
	if not can_receive_card_drag(data):
		clear_drop_preview()
		return false
	reset_all_hover_feedback()
	var drag_data := data as Dictionary
	_update_stack_target_feedback(at_position.x, drag_data)
	# Godot 松手前会用同一坐标再查询一次。鼠标没有移动时必须沿用玩家
	# 已看到的席位和虚影；拖拽快照的追赶只由 force_recalculate 帧更新处理。
	if (
		not force_recalculate
		and not _preview_intent.is_empty()
		and is_instance_valid(_preview_slot)
		and is_equal_approx(at_position.x, _preview_pointer_x)
	):
		return true
	# 唯一席位是拖动卡的临时位置，必须先于堆叠/独立意图建立和换位。
	# 意图随后只读取已经让位后的实体边界，不再反向决定席位放在哪边。
	var had_reservation := has_drop_reservation()
	var reservation_moved := _ensure_drop_reservation(
		at_position.x,
		drag_data
	)
	var reservation_created := not had_reservation and has_drop_reservation()
	if reservation_moved:
		_reservation_move_in_progress = true
	elif _reservation_move_in_progress and not _has_layout_animation():
		_reservation_move_in_progress = false
	var reservation_transitioning := _reservation_move_in_progress
	var intent := _build_drop_intent(
		at_position,
		drag_data,
		reservation_created,
		reservation_transitioning
	)
	if intent.is_empty() or not _intent_fits_capacity(intent, data as Dictionary):
		_clear_intent_preview()
		_update_drop_reservation_width({})
		if has_drop_reservation():
			_preview_pointer_x = at_position.x
		return false
	if _same_intent(intent, _preview_intent) and not reservation_moved:
		_update_drop_reservation_width(intent)
		if (
			is_instance_valid(_preview_slot)
			and is_instance_valid(_preview_replaced_slot)
		):
			_preview_slot.set_stack_target_feedback(
				_preview_replaced_slot.get_stack_target_feedback_strength()
			)
		_preview_pointer_x = at_position.x
		return true
	_show_intent_preview(
		intent,
		drag_data,
		reservation_moved or (
			reservation_created
			and drag_data.get("kind") == &"squad"
		)
	)
	_update_drop_reservation_width(intent)
	_preview_pointer_x = at_position.x
	return true


func commit_card_drop(at_position: Vector2, data: Variant) -> void:
	if not can_receive_card_drag(data):
		clear_drop_preview()
		return
	# 鼠标移动阶段已经持续重算吸附点；松手时直接提交最后一次预览，
	# 避免覆盖层与拖动快照的帧间变化改写玩家已经看到的意图。
	if _preview_intent.is_empty() and not preview_card_drop(at_position, data):
		return
	var intent := _preview_intent.duplicate()
	var insert_index := int(intent.get("squad_index", 0))
	var drag_data := (data as Dictionary).duplicate()
	drag_data["drop_intent"] = intent
	var preview_offset: Vector2 = drag_data.get(
		"drag_visual_offset",
		drag_data.get("preview_offset", Vector2.ZERO)
	)
	var drag_visual := drag_data.get("drag_visual") as CardDragPreview
	# 拖动反馈继续使用带追赶延迟的快照；成功松手后的飞入起点改用
	# 即时跟随鼠标的预览根节点，避免真实卡从尚未追上的内部纹理处补飞。
	var card_global_position := (
		drag_visual.global_position - preview_offset
		if is_instance_valid(drag_visual)
		else placement_overlay.get_global_transform_with_canvas() * at_position - preview_offset
	)
	clear_drop_preview()
	_restore_hidden_source_slot()
	card_dropped.emit(self, insert_index, drag_data, card_global_position)


func has_active_drop_preview() -> bool:
	return not _preview_intent.is_empty() and is_instance_valid(_preview_slot)


func has_drop_reservation() -> bool:
	return is_instance_valid(_reservation_slot)


func get_drop_reservation_width() -> float:
	return _reservation_width if has_drop_reservation() else 0.0


func get_drop_reservation_empty_width() -> float:
	return _reservation_empty_width if has_drop_reservation() else 0.0


func get_drop_reservation_index() -> int:
	return _reservation_insert_index


func clear_drop_preview(clear_stack_feedback: bool = true) -> void:
	_clear_intent_preview()
	_clear_drop_reservation()
	if clear_stack_feedback:
		_clear_stack_target_feedback()


# --- 唯一预留位：宽度由来源离场后的可用容量决定，位置随实体越过中线换位 ---
func _clear_intent_preview() -> void:
	if is_instance_valid(_preview_drag_visual):
		_preview_drag_visual.set_preview_rune_highlights([])
	_preview_drag_visual = null
	if is_instance_valid(_preview_replaced_slot):
		# 合并期间真实目标仍留在 HBox 中负责占位和实体边界；这里只恢复绘制。
		_preview_replaced_slot.modulate.a = 1.0
	_merge_preview_alignment_revision += 1
	_merge_preview_anchor_card = null
	if _preview_slot != null:
		# 预览节点留在场景树中等待安全释放，避免鼠标切换帧对已经
		# remove_child 的 Control 发送 get_local_mouse_position 通知。
		_preview_slot.visible = false
		_preview_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_slot.queue_free()
		_preview_slot = null
	_preview_replaced_slot = null
	_preview_insert_index = -1
	_preview_intent = {}
	_preview_pointer_x = INF
	if has_drop_reservation():
		_set_drop_reservation_empty_width(_reservation_width)


func _ensure_drop_reservation(
	pointer_x: float,
	data: Dictionary
) -> bool:
	var is_card_drag: bool = data.get("kind") == &"card"
	var is_compact_squad_drag: bool = (
		data.get("kind") == &"squad"
		and _can_build_stack_intent(data)
	)
	if not is_card_drag and not is_compact_squad_drag:
		return false
	var drag_center_x := _get_drag_card_center_x(pointer_x, data)
	var next_insert_index := _find_reservation_insert_index(drag_center_x)
	var source_row := data.get("source_row") as BattlefieldRow
	var source_slot := data.get("source_slot") as BoardSlot
	if (
		is_card_drag
		and not has_drop_reservation()
		and source_row == self
		and is_instance_valid(source_slot)
		and not source_slot.get_current_visual_squad_data().horizontal_cards.is_empty()
	):
		var source_rect := _get_slot_visual_rect(source_slot)
		if drag_center_x >= source_rect.position.x and drag_center_x <= source_rect.end.x:
			# 从多卡小队原位抬起时，中心相等不能统一归到右侧；初始
			# 唯一席位沿用该卡原本的水平侧，左卡在来源前、其余卡在来源后。
			var source_card_index := (
				source_slot.get_squad_data().horizontal_cards.find(
					data.get("card_data") as CardData
				)
			)
			var source_visible_index := _get_visible_real_slots().find(source_slot)
			next_insert_index = (
				source_visible_index
				+ (0 if source_card_index == 0 else 1)
			)
	if has_drop_reservation():
		# HBox 换边后真实卡仍在 0.15 秒补间；期间继续读取移动边界会让
		# 同一个鼠标位置反向触发下一次换边，形成左右循环。
		if _reservation_move_in_progress and _has_layout_animation():
			return false
		if next_insert_index != _reservation_insert_index:
			# 预留位换边会让 HBox 直接重排所有真实小队。先记住旧位置，
			# 让单卡越过单卡或多卡小队时都复用同一套平滑让位动画。
			var previous_positions := _capture_visible_slot_positions()
			_reservation_insert_index = next_insert_index
			_move_drop_reservation(_reservation_insert_index)
			_animate_layout_next_frame(previous_positions)
			return true
		return false
	var previous_positions := _capture_visible_slot_positions()
	var remaining_units := _get_units_available_after_source_lift(data)
	if remaining_units <= 0:
		return false
	_reservation_width = (
		COMPACT_SQUAD_RESERVATION_WIDTH
		if is_compact_squad_drag
		else (
			float(SINGLE_CARD_WIDTH + SQUAD_GAP)
			if remaining_units >= SINGLE_CARD_UNIT_COUNT
			else remaining_units * STACKED_RUNE_STEP_WIDTH
		)
	)
	_reservation_insert_index = next_insert_index
	_reservation_slot = Control.new()
	_reservation_slot.name = "CardDropReservation"
	_reservation_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reservation_slot.custom_minimum_size = Vector2(
		0.0,
		SquadView.CARD_SIZE.y
	)
	_reservation_slot.size = _reservation_slot.custom_minimum_size
	squad_row.add_child(_reservation_slot)
	_move_drop_reservation(_reservation_insert_index)
	_set_drop_reservation_empty_width(_reservation_width)
	_animate_layout_next_frame(previous_positions)
	return false


func _find_reservation_insert_index(drag_center_x: float) -> int:
	var visible_slots := _get_visible_real_slots()
	var next_index := _find_insert_index(drag_center_x)
	if not has_drop_reservation() or next_index == _reservation_insert_index:
		return next_index
	# 过滤恰好停在实体中线附近的亚像素来回跳动，但判断对象始终是
	# 玩家当前看到的实体小队；预览虚影和席位自身都不参与边界。
	if next_index == _reservation_insert_index - 1:
		var crossed_left := visible_slots[next_index]
		if (
			drag_center_x
			>= _get_slot_visual_rect(crossed_left).get_center().x
			- RESERVATION_SWAP_HYSTERESIS
		):
			return _reservation_insert_index
	elif (
		next_index == _reservation_insert_index + 1
		and _reservation_insert_index < visible_slots.size()
	):
		var crossed_right := visible_slots[_reservation_insert_index]
		if (
			drag_center_x
			<= _get_slot_visual_rect(crossed_right).get_center().x
			+ RESERVATION_SWAP_HYSTERESIS
		):
			return _reservation_insert_index
	return next_index


func _update_drop_reservation_width(intent: Dictionary) -> void:
	if not has_drop_reservation():
		return
	if intent.get("operation") != &"merge_card":
		_set_drop_reservation_empty_width(_reservation_width)
		return
	var consumed_width := 0.0
	var target_slot := intent.get("target_slot") as BoardSlot
	var result_squad := intent.get("result_squad") as SquadData
	if is_instance_valid(target_slot) and result_squad != null:
		consumed_width = maxf(
			0.0,
			result_squad.get_display_width()
			- target_slot.get_current_visual_squad_data().get_display_width()
		)
	# 预留节点始终保持固定布局宽度；虚影覆盖其中 consumed_width，
	# 这里只记录玩家实际还能看到的空白，不能再次压缩 HBox 触发整排位移。
	var stack_budget := minf(_reservation_width, float(SINGLE_CARD_WIDTH))
	_set_drop_reservation_empty_width(stack_budget - consumed_width)


func _clear_drop_reservation() -> void:
	if is_instance_valid(_reservation_slot):
		var reservation_parent := _reservation_slot.get_parent()
		if reservation_parent != null:
			reservation_parent.remove_child(_reservation_slot)
		_reservation_slot.queue_free()
	_reservation_slot = null
	_reservation_insert_index = -1
	_reservation_width = 0.0
	_reservation_empty_width = 0.0
	_reservation_move_in_progress = false


func _set_drop_reservation_empty_width(value: float) -> void:
	if not has_drop_reservation():
		return
	_reservation_empty_width = maxf(0.0, value)
	# HBox 中的节点宽度只由固定席位预算决定。预览虚影会覆盖席位的
	# 一部分，但不能通过修改节点宽度反过来推动实体卡牌。
	var node_width := maxf(0.0, _reservation_width - SQUAD_GAP)
	_reservation_slot.visible = _reservation_width > 0.0
	_reservation_slot.custom_minimum_size.x = node_width
	_reservation_slot.size.x = node_width


func _get_units_available_after_source_lift(data: Dictionary) -> int:
	var used_units := get_used_unit_count()
	var source_row := data.get("source_row") as BattlefieldRow
	var source_slot := data.get("source_slot") as BoardSlot
	if source_row == self and is_instance_valid(source_slot):
		var source_squad := source_slot.get_squad_data()
		used_units -= source_squad.get_unit_count()
		if data.get("kind") == &"card":
			var source_after := source_squad.duplicate_squad()
			source_after.remove_card(data.get("card_data") as CardData)
			used_units += source_after.get_unit_count()
	return maxi(0, BATTLEFIELD_UNIT_COUNT - used_units)


func _move_drop_reservation(insert_index: int) -> void:
	if not has_drop_reservation():
		return
	var visible_slots := _get_visible_real_slots()
	if insert_index >= visible_slots.size():
		squad_row.move_child(_reservation_slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(_reservation_slot, visible_slots[insert_index])


# --- 合法目标反馈与放置意图推导 ---
func update_stack_target_feedback_global(
	pointer_global_position: Vector2,
	data: Dictionary
) -> void:
	if not can_receive_card_drag(data) or not _can_build_stack_intent(data):
		stop_stack_target_feedback()
		return
	_active_stack_feedback_drag_data = data.duplicate()
	set_process(true)
	var local_position := (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* pointer_global_position
	)
	_update_stack_target_feedback(local_position.x, data)


func stop_stack_target_feedback() -> void:
	_active_stack_feedback_drag_data = {}
	set_process(false)
	_clear_stack_target_feedback()


func _build_drop_intent(
	at_position: Vector2,
	data: Dictionary,
	reservation_created: bool = false,
	reservation_transitioning: bool = false
) -> Dictionary:
	var kind := data.get("kind") as StringName
	if kind == &"squad":
		var merge_target := _find_compact_squad_merge_target(at_position.x, data)
		if merge_target != null:
			return _build_compact_squad_merge_intent(
				merge_target,
				at_position.x,
				data
			)
		return {
			"operation": &"move_squad",
			"squad_index": (
				_reservation_insert_index
				if has_drop_reservation()
				else _find_insert_index(
					_get_drag_card_center_x(at_position.x, data)
				)
			),
			"result_squad": data.get("squad_data"),
		}
	if kind != &"card":
		return {}
	var card_data := data.get("card_data") as CardData
	var target_slot := _find_card_stack_target(at_position.x, data)
	var new_squad_intent := {
		"operation": &"new_squad",
		"squad_index": (
			_reservation_insert_index
			if has_drop_reservation()
			else _find_insert_index(
				_get_drag_card_center_x(at_position.x, data)
			)
		),
		"card_index": 0,
		"result_squad": SquadData.from_card(card_data),
	}
	if (
		is_instance_valid(target_slot)
		and target_slot == data.get("source_slot")
		and reservation_created
	):
		if (
			is_instance_valid(data.get("drag_visual"))
			and _intent_fits_capacity(new_squad_intent, data)
		):
			# 从多卡小队原位抬起且能独立落位时，先让拖动卡占用
			# 刚建立的席位，不把原布局重叠误判成重新堆叠。
			return new_squad_intent
		# 容量不足以独立放置时只能显示回到来源的合法预览；首帧沿用
		# 原双卡形态，但它不能再反向改变已经确定的席位侧别。
		var source_squad := target_slot.get_squad_data()
		var source_merge := _build_merge_intent(
			target_slot,
			at_position.x,
			data,
			source_squad.two_card_layout
		)
		return (
			source_merge
			if _intent_fits_capacity(source_merge, data)
			else {}
		)
	if reservation_transitioning:
		# 预留位刚换边或实体仍在补间时，先让卡牌完成独立让位。
		# 容量不够独立落位就暂不显示虚影，补间结束后由 _process
		# 沿用最后指针位置重算，避免交换途中提前闪出完整合并预览。
		return (
			new_squad_intent
			if _intent_fits_capacity(new_squad_intent, data)
			else {}
		)
	if (
		target_slot != null
		and target_slot != data.get("source_slot")
		and _is_drag_center_at_real_gap(at_position.x, data)
		and _intent_fits_capacity(new_squad_intent, data)
	):
		return new_squad_intent
	if target_slot == null:
		return new_squad_intent
	return _build_capacity_fitting_merge_intent(
		target_slot,
		at_position.x,
		data
	)


func _can_build_stack_intent(data: Dictionary) -> bool:
	if data.get("kind") == &"card":
		return true
	var squad := data.get("squad_data") as SquadData
	return (
		data.get("kind") == &"squad"
		and squad != null
		and squad.get_card_count() == 2
		and squad.two_card_layout == SquadData.TwoCardLayout.COMPACT
		and squad.get_visible_runes().size() == 4
	)


func _build_compact_squad_merge_intent(
	target_slot: BoardSlot,
	pointer_x: float,
	data: Dictionary
) -> Dictionary:
	var source_squad := data.get("squad_data") as SquadData
	if (
		not _can_build_stack_intent(data)
		or not is_instance_valid(target_slot)
		or target_slot == data.get("source_slot")
	):
		return {}
	var target_squad := target_slot.get_squad_data()
	if target_squad == null or target_squad.get_card_count() != 1:
		return {}
	var single_on_left := (
		_get_drag_card_center_x(pointer_x, data)
		> _get_slot_visual_rect(target_slot).get_center().x
	)
	var result := source_squad.merge_compact_double_with_single(
		target_squad,
		single_on_left
	)
	if result == null:
		return {}
	var intent := {
		"operation": &"merge_squad",
		"squad_index": get_slot_index(target_slot),
		"card_index": 0 if single_on_left else 2,
		"single_on_left": single_on_left,
		"target_slot": target_slot,
		"result_squad": result,
	}
	return intent if _intent_fits_capacity(intent, data) else {}


func _build_merge_intent(
	target_slot: BoardSlot,
	pointer_x: float,
	data: Dictionary,
	forced_two_card_layout: Variant = null
) -> Dictionary:
	var card_data := data.get("card_data") as CardData
	var target_squad := target_slot.get_squad_data()
	var source_slot := data.get("source_slot") as BoardSlot
	var result := target_squad.duplicate_squad()
	if target_slot == source_slot:
		result.remove_card(card_data)
	if result.get_card_count() >= SquadData.MAX_CARD_COUNT:
		return {}
	var card_index := _find_card_insert_index(
		target_slot,
		pointer_x,
		result.get_card_count(),
		data
	)
	if target_slot == source_slot:
		var original_index := target_squad.horizontal_cards.find(card_data)
		if original_index >= 0 and original_index <= result.get_card_count():
			# 拖动卡仍覆盖来源小队的实体整体时，默认保持其原水平槽位；
			# 双卡抽出后只在两个实体中心完全重合时沿用原槽位；一旦
			# 拖动实体越过剩余卡中心，就必须允许 2+3 与 1+3 换边。
			var drag_center_x := _get_drag_card_center_x(pointer_x, data)
			var target_rect := _get_slot_visual_rect(target_slot)
			if (
				result.get_card_count() == 1
				and is_equal_approx(drag_center_x, target_rect.get_center().x)
			):
				card_index = original_index
			elif (
				result.get_card_count() > 1
				and drag_center_x >= target_rect.position.x
				and drag_center_x <= target_rect.end.x
			):
				card_index = original_index
	if (
		target_slot != source_slot
		and not target_squad.can_accept_external_card_at(card_index)
	):
		return {}
	var layout: SquadData.TwoCardLayout = (
		forced_two_card_layout as SquadData.TwoCardLayout
		if forced_two_card_layout is SquadData.TwoCardLayout
		else _find_two_card_layout(
			target_slot,
			pointer_x,
			card_index,
			data
		)
	)
	if (
		target_slot == source_slot
		and result.get_card_count() == 1
		and not has_drop_reservation()
	):
		# 当该排没有独立放置容量时，按下首帧只能回到来源小队，先保持
		# 原双卡形态；鼠标继续移动后仍按实体边界切换展开/紧密布局。
		layout = target_squad.two_card_layout
	if not result.insert_card(card_data, card_index, layout):
		return {}
	var intent := {
		"operation": &"merge_card",
		"squad_index": get_slot_index(target_slot),
		"card_index": card_index,
		"two_card_layout": layout,
		"target_slot": target_slot,
		"result_squad": result,
	}
	if (
		target_slot == source_slot
		and _is_drag_card_at_source_resting_position(target_slot, pointer_x, data)
	):
		intent["suppress_redundant_source_preview"] = true
	return intent


func _is_drag_card_at_source_resting_position(
	source_slot: BoardSlot,
	pointer_x: float,
	data: Dictionary
) -> bool:
	var card_data := data.get("card_data") as CardData
	var source_squad := source_slot.get_squad_data()
	var horizontal_index := source_squad.horizontal_cards.find(card_data)
	if horizontal_index < 0:
		return false
	var source_card_left := (
		source_slot.position.x
		+ source_squad.get_card_x_positions()[horizontal_index]
	)
	return is_equal_approx(
		_get_drag_card_left_x(pointer_x, data),
		source_card_left
	)


func _build_capacity_fitting_merge_intent(
	target_slot: BoardSlot,
	pointer_x: float,
	data: Dictionary
) -> Dictionary:
	var preferred := _build_merge_intent(target_slot, pointer_x, data)
	if not preferred.is_empty() and _intent_fits_capacity(preferred, data):
		return preferred
	var preferred_result := preferred.get("result_squad") as SquadData
	if (
		preferred_result == null
		or preferred_result.get_card_count() != 2
		or preferred_result.two_card_layout
		!= SquadData.TwoCardLayout.EXPANDED
	):
		return {}
	# 20 单元时，卡牌边缘可能更接近 60px 展开点（+2，超容量），
	# 但同一张附近单卡的 30px 紧密点只增加 1 单元。优先降级到
	# 这个近处合法布局，不能越过数张卡去吸附远方的 +0 目标。
	var compact := _build_merge_intent(
		target_slot,
		pointer_x,
		data,
		SquadData.TwoCardLayout.COMPACT
	)
	return compact if _intent_fits_capacity(compact, data) else {}


func _intent_fits_capacity(intent: Dictionary, data: Dictionary) -> bool:
	var used_units := get_used_unit_count()
	var source_row := data.get("source_row") as BattlefieldRow
	var source_slot := data.get("source_slot") as BoardSlot
	var kind := data.get("kind") as StringName
	var card_data := data.get("card_data") as CardData
	var target_slot := intent.get("target_slot") as BoardSlot
	if (
		is_instance_valid(target_slot)
		and target_slot != source_slot
		and not target_slot.get_squad_data().can_accept_external_card_at(
			int(intent.get("card_index", 0))
		)
	):
		return false
	if source_row == self and is_instance_valid(source_slot):
		var source_squad := source_slot.get_squad_data()
		used_units -= source_squad.get_unit_count()
		if kind == &"card" and target_slot != source_slot:
			var source_after := source_squad.duplicate_squad()
			source_after.remove_card(card_data)
			used_units += source_after.get_unit_count()
	if is_instance_valid(target_slot) and target_slot != source_slot:
		used_units -= target_slot.get_squad_data().get_unit_count()
	var result_squad := intent.get("result_squad") as SquadData
	if result_squad != null:
		used_units += result_squad.get_unit_count()
	return used_units <= BATTLEFIELD_UNIT_COUNT


func _show_intent_preview(
	intent: Dictionary,
	drag_data: Dictionary = {},
	reservation_moved: bool = false
) -> void:
	var previous_positions := _capture_visible_slot_positions()
	var preview_squad := intent.get("result_squad") as SquadData
	var next_target := intent.get("target_slot") as BoardSlot
	var carried_anchor_canvas_position := Vector2.ZERO
	var has_carried_anchor := false
	if (
		is_instance_valid(_preview_slot)
		and next_target == _preview_replaced_slot
		and _merge_preview_anchor_card != null
	):
		var previous_preview_data := (
			_preview_slot.get_current_visual_squad_data()
		)
		if (
			previous_preview_data != null
			and previous_preview_data.contains(_merge_preview_anchor_card)
		):
			carried_anchor_canvas_position = _get_card_logical_canvas_position(
				_preview_slot,
				_merge_preview_anchor_card
			)
			has_carried_anchor = true
	_clear_intent_preview()
	_preview_intent = intent
	_preview_insert_index = int(intent.get("squad_index", 0))
	var operation := intent.get("operation") as StringName
	_preview_replaced_slot = next_target
	var merge_anchor_canvas_position := Vector2.ZERO
	var has_merge_anchor := false
	if (
		operation in [&"merge_card", &"merge_squad"]
		and is_instance_valid(_preview_replaced_slot)
	):
		var target_squad := _preview_replaced_slot.get_current_visual_squad_data()
		if target_squad != null and not target_squad.horizontal_cards.is_empty():
			_merge_preview_anchor_card = target_squad.horizontal_cards[0]
			if has_carried_anchor and not reservation_moved:
				merge_anchor_canvas_position = carried_anchor_canvas_position
				has_merge_anchor = true
			else:
				merge_anchor_canvas_position = _get_card_logical_canvas_position(
					_preview_replaced_slot,
					_merge_preview_anchor_card
				)
				has_merge_anchor = true
	# 卡牌刚从原小队原位抬起时，鼠标携带实体已经补在它原来的位置。
	# 再画一份“放回来源”的完整半透明结果，会把同一张卡重复显示两次；
	# 保留合法 intent 供下一次点击提交，但这个无变化结果无需额外虚影。
	if bool(intent.get("suppress_redundant_source_preview", false)):
		_preview_replaced_slot = null
		return
	_preview_slot = BOARD_SLOT_SCENE.instantiate() as BoardSlot
	var preview_uses_reservation := (
		has_drop_reservation()
		and operation in [&"new_squad", &"move_squad"]
	)
	if preview_uses_reservation:
		_reservation_slot.add_child(_preview_slot)
	elif operation in [&"merge_card", &"merge_squad"] and is_instance_valid(_preview_replaced_slot):
		# 合并虚影放入独立覆盖层，不再替换 HBox 中的目标节点。
		# 因此实体边界、目标位置和唯一预留位都不会被虚影宽度二次改写。
		placement_overlay.add_child(_preview_slot)
	else:
		squad_row.add_child(_preview_slot)
	_preview_slot.z_index = DROP_PREVIEW_Z_INDEX
	_preview_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 单卡预览只让待加入卡半透明；整队移动则保持整队虚影。
	var preview_ghost_cards: Array[CardData] = []
	if operation in [&"new_squad", &"merge_card"]:
		preview_ghost_cards.append(preview_squad.get_effect_source())
	elif operation == &"merge_squad":
		var carried_squad := drag_data.get("squad_data") as SquadData
		if carried_squad != null:
			preview_ghost_cards.assign(carried_squad.horizontal_cards)
	_preview_slot.set_preview_squad(preview_squad, preview_ghost_cards)
	_sync_dragged_card_preview_highlights(drag_data)
	if is_instance_valid(_preview_replaced_slot):
		_preview_slot.set_stack_target_feedback(
			_preview_replaced_slot.get_stack_target_feedback_strength()
		)
		# 晃动由包含完整合并结果的预览节点绘制。真实目标只保留布局与边界，
		# 避免目标快照和结果快照同时显示成两张重叠卡牌。
		_preview_replaced_slot.modulate.a = 0.0
	if (
		not preview_uses_reservation
		and operation not in [&"merge_card", &"merge_squad"]
	):
		# 先把虚影放到最终兄弟顺序，再按预留位真实左右邻居扣除 HBox 间距。
		_move_preview_slot(_preview_insert_index)
	if preview_uses_reservation:
		_preview_slot.position = Vector2(
			(_reservation_slot.size.x - _preview_slot.size.x) * 0.5,
			0.0
		)
	if has_merge_anchor:
		var alignment_revision := _merge_preview_alignment_revision
		_align_merge_preview_to_target_anchor(merge_anchor_canvas_position)
		_align_merge_preview_to_target_anchor.call_deferred(
			merge_anchor_canvas_position
		)
		_align_merge_preview_after_layout(
			alignment_revision,
			merge_anchor_canvas_position,
			reservation_moved
		)
	if (
		not preview_uses_reservation
		and operation not in [&"merge_card", &"merge_squad"]
	):
		_animate_layout_next_frame(previous_positions)


func _sync_dragged_card_preview_highlights(drag_data: Dictionary) -> void:
	var drag_visual := drag_data.get("drag_visual") as CardDragPreview
	var dragged_card := drag_data.get("card_data") as CardData
	if (
		not is_instance_valid(drag_visual)
		or dragged_card == null
		or not is_instance_valid(_preview_slot)
	):
		return
	var preview_card_view := _preview_slot.get_card_view(dragged_card)
	var highlighted_indices: Array[int] = []
	if preview_card_view != null:
		highlighted_indices.assign(
			preview_card_view.get_highlighted_rune_indices()
		)
	_preview_drag_visual = drag_visual
	_preview_drag_visual.set_preview_rune_highlights(highlighted_indices)


func _align_merge_preview_after_layout(
	revision: int,
	anchor_canvas_position: Vector2,
	follow_replaced_slot: bool
) -> void:
	await get_tree().process_frame
	if revision == _merge_preview_alignment_revision:
		if (
			follow_replaced_slot
			and is_instance_valid(_preview_replaced_slot)
			and _merge_preview_anchor_card != null
		):
			# 真实目标在 HBox 中补间，但合并虚影位于独立覆盖层。先把虚影
			# 对齐到目标当前可见位置，再把它与目标用相同时长送到最终位置，
			# 否则越过多卡小队时只会看到隐藏槽在动、完整合并虚影仍停在原处。
			anchor_canvas_position = _get_card_logical_canvas_position(
				_preview_replaced_slot,
				_merge_preview_anchor_card
			)
			_align_merge_preview_to_target_anchor(anchor_canvas_position)
			var previous_preview_global_position := (
				_preview_slot.card_visual_layer
				.get_global_transform_with_canvas()
				.origin
			)
			var final_anchor_canvas_position := _get_card_logical_canvas_position(
				_preview_replaced_slot,
				_merge_preview_anchor_card,
				false
			)
			_align_merge_preview_to_target_anchor(final_anchor_canvas_position)
			_preview_slot.animate_from_global_position(
				previous_preview_global_position,
				true
			)
			return
		_align_merge_preview_to_target_anchor(anchor_canvas_position)


func _align_merge_preview_to_target_anchor(
	anchor_canvas_position: Vector2
) -> void:
	if (
		_merge_preview_anchor_card == null
		or not is_instance_valid(_preview_slot)
	):
		return
	var preview_data := _preview_slot.get_current_visual_squad_data()
	if (
		preview_data == null
		or not preview_data.contains(_merge_preview_anchor_card)
	):
		return
	var preview_canvas_position := _get_card_logical_canvas_position(
		_preview_slot,
		_merge_preview_anchor_card
	)
	var canvas_delta := (
		anchor_canvas_position - preview_canvas_position
	)
	var preview_parent := _preview_slot.get_parent() as Control
	var parent_inverse := (
		preview_parent.get_global_transform_with_canvas().affine_inverse()
	)
	_preview_slot.position += (
		parent_inverse * (preview_canvas_position + canvas_delta)
		- parent_inverse * preview_canvas_position
	)


func _same_intent(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return false
	return (
		left.get("operation") == right.get("operation")
		and left.get("squad_index") == right.get("squad_index")
		and left.get("card_index") == right.get("card_index")
		and left.get("two_card_layout") == right.get("two_card_layout")
		and left.get("target_slot") == right.get("target_slot")
	)


# --- Godot 原生拖拽生命周期；只隐藏/恢复来源视觉，不提前改真实数据 ---
func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		_begin_card_drag(drag_data)
		if drag_data is Dictionary:
			update_stack_target_feedback_global(
				get_viewport().get_mouse_position(),
				drag_data as Dictionary
			)
	elif what == NOTIFICATION_DRAG_END:
		var return_global_position: Variant = null
		if is_instance_valid(_hidden_source_slot) and not get_viewport().gui_is_drag_successful():
			return_global_position = (
				_active_drag_visual.get_card_global_position()
				if is_instance_valid(_active_drag_visual)
				else get_viewport().get_mouse_position() - _active_drag_preview_offset
			)
		_finish_card_drag(return_global_position)


func _begin_card_drag(data: Variant) -> void:
	_finish_card_drag()
	# 原生拖拽开始后，旧鼠标目标可能收不到 mouse_exited。
	# 无论来源位于收藏还是战场，都先清掉本行遗留的悬停视觉。
	reset_all_hover_feedback()
	if not can_receive_card_drag(data):
		return
	var drag_data := data as Dictionary
	if drag_data.get("source_type") != &"board" or drag_data.get("source_row") != self:
		return
	var source_slot := drag_data.get("source_slot") as BoardSlot
	if source_slot == null or source_slot.get_parent() != squad_row:
		return
	_hidden_source_slot = source_slot
	_active_drag_preview_offset = drag_data.get(
		"drag_visual_offset",
		drag_data.get("preview_offset", Vector2.ZERO)
	)
	_active_drag_visual = drag_data.get("drag_visual") as CardDragPreview
	if drag_data.get("kind") == &"squad":
		_hidden_source_slot.visible = false
	else:
		_hidden_source_slot.set_drag_hidden_card(drag_data.get("card_data") as CardData)


func _finish_card_drag(return_global_position: Variant = null) -> void:
	clear_drop_preview()
	stop_stack_target_feedback()
	_restore_hidden_source_slot(return_global_position)
	_active_drag_preview_offset = Vector2.ZERO
	_active_drag_visual = null


func _restore_hidden_source_slot(return_global_position: Variant = null) -> void:
	if is_instance_valid(_hidden_source_slot) and _hidden_source_slot.get_parent() == squad_row:
		var restored_slot := _hidden_source_slot
		restored_slot.visible = true
		restored_slot.clear_drag_hidden_card()
		restored_slot.unlock_drag_subject()
		if return_global_position is Vector2:
			_animate_restored_slot_return.call_deferred(restored_slot, return_global_position)
	_hidden_source_slot = null


func _animate_restored_slot_return(slot_value: Variant, return_global_position: Vector2) -> void:
	await get_tree().process_frame
	if is_instance_valid(slot_value):
		(slot_value as BoardSlot).animate_from_global_position(return_global_position)


func _connect_slot(slot: BoardSlot) -> void:
	slot.slot_clicked.connect(_on_occupied_slot_clicked)
	slot.click_carry_requested.connect(_on_click_carry_requested)
	slot.set_prefer_minion(_prefer_minion)
	slot.configure_drag_source(_drag_enabled, self)


func _on_occupied_slot_clicked(slot: BoardSlot) -> void:
	board_slot_clicked.emit(self, slot)


func _on_click_carry_requested(data: Dictionary, pointer_global_position: Vector2) -> void:
	card_click_carry_requested.emit(data, pointer_global_position)


# --- 以实体边界寻找堆叠目标或独立插入位置 ---
func _find_slot_at_x(pointer_x: float) -> BoardSlot:
	for slot: BoardSlot in _get_visible_real_slots():
		var visual_data := slot.get_current_visual_squad_data()
		var rect := Rect2(
			slot.position,
			Vector2(visual_data.get_display_width(), SquadView.CARD_SIZE.y)
		)
		if pointer_x >= rect.position.x and pointer_x < rect.end.x:
			return slot
	return null


func _find_card_stack_target(pointer_x: float, data: Dictionary) -> BoardSlot:
	# 真实拖拽和点击携带都会提供抓取点；缺少该字段的是旧测试或兼容调用，
	# 继续沿用阶段 4 的鼠标矩形命中，避免把“卡牌左上角=鼠标”误当真实几何。
	if not data.has("grab_local_position"):
		var pointer_target := _find_slot_at_x(pointer_x)
		if pointer_target == null:
			return null
		var pointer_intent := _build_capacity_fitting_merge_intent(
			pointer_target,
			pointer_x,
			data
		)
		return pointer_target if not pointer_intent.is_empty() else null
	# 已经吸附同一目标后，允许拖动卡穿过卡面中央的深度重叠区。
	# 否则从目标一侧横穿到另一侧时会短暂退回“独立上场”。
	var sticky_target := _get_sticky_stack_target(pointer_x, data)
	if sticky_target != null:
		return sticky_target
	var candidates := _get_legal_stack_candidates(pointer_x, data)
	var source_slot := data.get("source_slot") as BoardSlot
	if (
		data.get("source_row") == self
		and is_instance_valid(source_slot)
		and get_slot_index(source_slot) >= 0
		and not source_slot.get_current_visual_squad_data().horizontal_cards.is_empty()
	):
		var source_rect := _get_slot_visual_rect(source_slot)
		var drag_left_x := _get_drag_card_left_x(pointer_x, data)
		var drag_right_x := drag_left_x + _get_drag_card_width(data)
		var source_overlap := maxf(
			0.0,
			minf(drag_right_x, source_rect.end.x)
			- maxf(drag_left_x, source_rect.position.x)
		)
		var strongest_external_overlap := 0.0
		for candidate: Dictionary in candidates:
			var external_slot := candidate.get("slot") as BoardSlot
			if external_slot == source_slot:
				continue
			var external_rect := _get_slot_visual_rect(external_slot)
			strongest_external_overlap = maxf(
				strongest_external_overlap,
				maxf(
					0.0,
					minf(drag_right_x, external_rect.end.x)
					- maxf(drag_left_x, external_rect.position.x)
				)
			)
		if (
			source_overlap > 0.0
			and (
				source_slot.get_squad_data().get_card_count() > 1
				or strongest_external_overlap <= source_overlap
			)
		):
			var source_intent := _build_capacity_fitting_merge_intent(
				source_slot,
				pointer_x,
				data
			)
			# 从小队中抬起卡牌时，拖动实体仍覆盖剩余实体小队就视为
			# 原位重叠；无需先退到 10～70px 边缘带才能显示来源预览。
			if not source_intent.is_empty():
				return source_slot
	var nearest_overlapping: BoardSlot
	var nearest_overlapping_distance := INF
	for candidate: Dictionary in candidates:
		var slot := candidate.get("slot") as BoardSlot
		var distance := float(candidate.get("distance", INF))
		if not _is_in_stack_overlap_band(slot, pointer_x, data):
			continue
		if distance < nearest_overlapping_distance:
			nearest_overlapping = slot
			nearest_overlapping_distance = distance
	return nearest_overlapping


func _is_drag_center_at_real_gap(pointer_x: float, data: Dictionary) -> bool:
	var drag_center_x := _get_drag_card_center_x(pointer_x, data)
	var visible_slots := _get_visible_real_slots()
	for index: int in visible_slots.size() - 1:
		var left_rect := _get_slot_visual_rect(visible_slots[index])
		var right_rect := _get_slot_visual_rect(visible_slots[index + 1])
		var gap_center_x := (left_rect.end.x + right_rect.position.x) * 0.5
		if absf(drag_center_x - gap_center_x) <= NEW_SQUAD_CENTER_RADIUS:
			return true
	return false


func _get_sticky_stack_target(
	pointer_x: float,
	data: Dictionary
) -> BoardSlot:
	if _preview_intent.get("operation") != &"merge_card":
		return null
	var previous_target := _preview_intent.get("target_slot") as BoardSlot
	if (
		not is_instance_valid(previous_target)
		or get_slot_index(previous_target) < 0
		or _get_stack_overlap(previous_target, pointer_x, data)
		<= STACK_OVERLAP_MAX
	):
		return null
	# 深度重叠只负责帮助玩家横穿同一张目标卡，不能盖过另一张卡已经
	# 精确进入 10～70px 覆盖带的事实，否则场上卡会被来源小队粘住。
	for slot: BoardSlot in _get_visible_real_slots():
		if (
			slot != previous_target
			and _is_in_stack_overlap_band(slot, pointer_x, data)
			and not _build_capacity_fitting_merge_intent(
				slot,
				pointer_x,
				data
			).is_empty()
		):
			return null
	var continued_intent := _build_capacity_fitting_merge_intent(
		previous_target,
		pointer_x,
		data
	)
	return previous_target if not continued_intent.is_empty() else null


func _get_legal_stack_candidates(pointer_x: float, data: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var drag_center_x := _get_drag_card_center_x(pointer_x, data)
	for slot: BoardSlot in _get_visible_real_slots():
		var intent := _build_capacity_fitting_merge_intent(
			slot,
			pointer_x,
			data
		)
		if intent.is_empty():
			continue
		var slot_center_x := _get_slot_visual_rect(slot).get_center().x
		candidates.append({
			"slot": slot,
			"intent": intent,
			"distance": absf(drag_center_x - slot_center_x),
		})
	return candidates


func _find_compact_squad_merge_target(
	pointer_x: float,
	data: Dictionary
) -> BoardSlot:
	var nearest_target: BoardSlot
	var nearest_distance := INF
	var drag_center_x := _get_drag_card_center_x(pointer_x, data)
	for slot: BoardSlot in _get_visible_real_slots():
		if slot == data.get("source_slot"):
			continue
		var target_squad := slot.get_squad_data()
		if target_squad == null or target_squad.get_card_count() != 1:
			continue
		var overlap := _get_stack_overlap(slot, pointer_x, data)
		if overlap < SQUAD_MERGE_OVERLAP_MIN or overlap > STACK_OVERLAP_MAX:
			continue
		if _build_compact_squad_merge_intent(slot, pointer_x, data).is_empty():
			continue
		var distance := absf(
			drag_center_x - _get_slot_visual_rect(slot).get_center().x
		)
		if distance < nearest_distance:
			nearest_target = slot
			nearest_distance = distance
	return nearest_target


func _update_stack_target_feedback(pointer_x: float, data: Dictionary) -> void:
	if not _can_build_stack_intent(data):
		_clear_stack_target_feedback()
		return
	if _has_layout_animation():
		_clear_stack_target_feedback()
		return
	var updated_slots := {}
	var source_slot := data.get("source_slot") as BoardSlot
	var candidates: Array[Dictionary] = []
	if data.get("kind") == &"card":
		candidates = _get_legal_stack_candidates(pointer_x, data)
	else:
		var squad_target := _find_compact_squad_merge_target(pointer_x, data)
		if squad_target != null:
			candidates.append({
				"slot": squad_target,
				"distance": absf(
					_get_drag_card_center_x(pointer_x, data)
					- _get_slot_visual_rect(squad_target).get_center().x
				),
			})
	for candidate: Dictionary in candidates:
		var distance := float(candidate.get("distance", INF))
		if distance > STACK_TARGET_FEEDBACK_RADIUS:
			continue
		var strength := 1.0 - distance / STACK_TARGET_FEEDBACK_RADIUS
		# 平方曲线让远处快速变弱，只保留最近一两个目标的清晰提示。
		strength *= strength
		if strength < STACK_TARGET_FEEDBACK_SILENT_THRESHOLD:
			continue
		strength = remap(
			strength,
			STACK_TARGET_FEEDBACK_SILENT_THRESHOLD,
			1.0,
			STACK_TARGET_FEEDBACK_MIN_VISIBLE_STRENGTH,
			1.0
		)
		var slot := candidate.get("slot") as BoardSlot
		if (
			slot == source_slot
			and _is_in_stack_overlap_band(slot, pointer_x, data)
		):
			strength = 1.0
		slot.set_stack_target_feedback(strength)
		updated_slots[slot] = true
	for slot: BoardSlot in _get_real_slots():
		if not updated_slots.has(slot):
			slot.set_stack_target_feedback(0.0)


func _has_layout_animation() -> bool:
	for slot: BoardSlot in _get_visible_real_slots():
		if slot.is_layout_animating():
			return true
	return false


func _clear_stack_target_feedback() -> void:
	for slot: BoardSlot in _get_real_slots():
		slot.set_stack_target_feedback(0.0)


func _find_insert_index(pointer_x: float) -> int:
	var visible_slots := _get_visible_real_slots()
	for index: int in visible_slots.size():
		var slot := visible_slots[index]
		if pointer_x < _get_slot_visual_rect(slot).get_center().x:
			return index
	return visible_slots.size()


func _find_card_insert_index(
	slot: BoardSlot,
	pointer_x: float,
	remaining_count: int,
	drag_data: Dictionary
) -> int:
	var visible_data := slot.get_current_visual_squad_data()
	if (
		remaining_count == 2
		and visible_data != null
		and visible_data.two_card_layout == SquadData.TwoCardLayout.EXPANDED
		and _intent_fits_capacity({
			"operation": &"merge_card",
			"target_slot": slot,
			"card_index": 1,
			"result_squad": _build_expanded_middle_result(slot, drag_data),
		}, drag_data)
	):
		# 展开双卡从任一实体外边缘接近时先形成 1+3+1 中插预览；
		# 拖动卡中心越过整个小队中心后，唯一席位才与小队换位。
		return 1
	var drag_center_x := _get_drag_card_center_x(pointer_x, drag_data)
	var slot_rect := _get_slot_visual_rect(slot)
	var local_x := drag_center_x - slot_rect.position.x
	if remaining_count <= 1:
		return 0 if local_x < slot_rect.size.x * 0.5 else 1
	if local_x < slot_rect.size.x / 3.0:
		return 0
	if local_x < slot_rect.size.x * 2.0 / 3.0:
		return 1
	return 2


func _build_expanded_middle_result(
	slot: BoardSlot,
	drag_data: Dictionary
) -> SquadData:
	var result := slot.get_current_visual_squad_data().duplicate_squad()
	var card_data := drag_data.get("card_data") as CardData
	if result.contains(card_data):
		result.remove_card(card_data)
	result.insert_card(card_data, 1, SquadData.TwoCardLayout.EXPANDED)
	return result


func _find_two_card_layout(
	slot: BoardSlot,
	pointer_x: float,
	_card_index: int,
	drag_data: Dictionary
) -> SquadData.TwoCardLayout:
	var overlap := _get_stack_overlap(slot, pointer_x, drag_data)
	return (
		SquadData.TwoCardLayout.EXPANDED
		if overlap <= STACK_SINGLE_RUNE_OVERLAP_MAX
		else SquadData.TwoCardLayout.COMPACT
	)


func _get_stack_overlap(
	slot: BoardSlot,
	pointer_x: float,
	drag_data: Dictionary
) -> float:
	var drag_left := _get_drag_card_left_x(pointer_x, drag_data)
	var drag_right := drag_left + _get_drag_card_width(drag_data)
	var target_rect := _get_slot_visual_rect(slot)
	var target_left := target_rect.position.x
	var target_right := target_rect.end.x
	var drag_center := (drag_left + drag_right) * 0.5
	var target_center := (target_left + target_right) * 0.5
	return maxf(
		0.0,
		target_right - drag_left
		if drag_center >= target_center
		else drag_right - target_left
	)


func _get_slot_visual_left_x(slot: BoardSlot) -> float:
	return _get_slot_visual_rect(slot).position.x


func _get_slot_visual_rect(slot: BoardSlot) -> Rect2:
	# 真实 BoardSlot 是边界权威。目标虚影即使视觉上与它重叠，也不能反向改变判定。
	var visual_data := slot.get_current_visual_squad_data()
	if visual_data == null or visual_data.horizontal_cards.is_empty():
		return Rect2(slot.position, slot.size)
	var left_card := visual_data.horizontal_cards[0]
	var global_left := _get_card_logical_canvas_position(
		slot,
		left_card
	)
	var row_left := (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* global_left
	)
	return Rect2(
		row_left,
		Vector2(visual_data.get_display_width(), SquadView.CARD_SIZE.y)
	)


func _get_card_logical_canvas_position(
	slot: BoardSlot,
	card: CardData,
	include_layout_animation: bool = true
) -> Vector2:
	var card_x := 0.0
	var visual_data := slot.get_current_visual_squad_data()
	if visual_data != null:
		var card_index := visual_data.horizontal_cards.find(card)
		var card_positions := visual_data.get_card_x_positions()
		if card_index >= 0 and card_index < card_positions.size():
			card_x = card_positions[card_index]
	# HBox 换位时 Slot 根节点会先到终点，CardVisualLayer 再从旧位置平滑追上。
	# 边界必须加上这段玩家实际看见的让位偏移；悬停抬起与颤动位于它的
	# 父层，仍不会反过来改变水平堆叠判定。
	var layout_visual_offset := Vector2.ZERO
	if include_layout_animation and is_instance_valid(slot.card_visual_layer):
		layout_visual_offset = slot.card_visual_layer.position
	return (
		slot.get_global_transform_with_canvas()
		* (Vector2(card_x, 0.0) + layout_visual_offset)
	)


func _is_in_stack_overlap_band(
	slot: BoardSlot,
	pointer_x: float,
	drag_data: Dictionary
) -> bool:
	var overlap := _get_stack_overlap(slot, pointer_x, drag_data)
	if (
		overlap >= STACK_OVERLAP_MIN
		and overlap <= STACK_OVERLAP_MAX
	):
		return true
	# 展开双卡的可见整体宽 159px。第三张卡从外侧深入时，先在整体
	# 中心两侧建立中插预览；实体中心越过小队中心后，席位才交换。
	var visual_data := slot.get_current_visual_squad_data()
	if (
		visual_data == null
		or visual_data.get_card_count() != 2
		or visual_data.two_card_layout != SquadData.TwoCardLayout.EXPANDED
	):
		return false
	var target_rect := _get_slot_visual_rect(slot)
	var middle_radius := (
		target_rect.size.x * 0.5
		- _get_drag_card_width(drag_data) * 0.5
		+ STACK_OVERLAP_MAX
	)
	return absf(
		_get_drag_card_center_x(pointer_x, drag_data)
		- target_rect.get_center().x
	) <= middle_radius


func _get_drag_card_left_x(pointer_x: float, drag_data: Dictionary) -> float:
	# 拖尾、旋转只属于表现。堆叠与唯一预留位必须由稳定的鼠标抓取点
	# 推导，否则鼠标停住后拖尾继续追赶会让预留位先反向、再换回来。
	if not drag_data.has("grab_local_position"):
		return pointer_x
	var grab_local_position: Vector2 = drag_data.get("grab_local_position", Vector2.ZERO)
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	return pointer_x - grab_local_position.x * preview_scale.x


func _get_drag_card_width(drag_data: Dictionary) -> float:
	# 旋转后的 AABB 会每帧改变宽度；规则只使用未旋转卡牌的逻辑宽度。
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	var dragged_squad := drag_data.get("squad_data") as SquadData
	if drag_data.get("kind") == &"squad" and dragged_squad != null:
		return dragged_squad.get_display_width() * preview_scale.x
	return SquadView.CARD_SIZE.x * preview_scale.x


func _get_drag_card_center_x(pointer_x: float, drag_data: Dictionary) -> float:
	if not drag_data.has("grab_local_position"):
		return pointer_x
	return _get_drag_card_left_x(pointer_x, drag_data) + _get_drag_card_width(drag_data) * 0.5


func _get_drag_visual_rect(drag_data: Dictionary) -> Rect2:
	var drag_visual := drag_data.get("drag_visual") as CardDragPreview
	if not is_instance_valid(drag_visual):
		return Rect2()
	var global_corners := drag_visual.get_card_global_corners()
	if global_corners.size() != 4:
		return Rect2()
	var inverse_transform := (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
	)
	var minimum := inverse_transform * global_corners[0]
	var maximum := minimum
	for global_corner: Vector2 in global_corners:
		var local_corner := inverse_transform * global_corner
		minimum.x = minf(minimum.x, local_corner.x)
		minimum.y = minf(minimum.y, local_corner.y)
		maximum.x = maxf(maximum.x, local_corner.x)
		maximum.y = maxf(maximum.y, local_corner.y)
	return Rect2(minimum, maximum - minimum)


# --- 临时节点排序、真实槽过滤与让位动画 ---
func _move_preview_slot(insert_index: int) -> void:
	var visible_slots := _get_visible_real_slots()
	if is_instance_valid(_preview_replaced_slot):
		var target_child_index := _preview_replaced_slot.get_index()
		squad_row.move_child(_preview_slot, target_child_index)
	elif insert_index >= visible_slots.size():
		squad_row.move_child(_preview_slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(_preview_slot, visible_slots[insert_index])


func _move_child_before(child: Node, target: Node) -> void:
	var target_index := target.get_index()
	if child.get_index() < target_index:
		target_index -= 1
	squad_row.move_child(child, target_index)


func _get_real_slots() -> Array[BoardSlot]:
	var slots: Array[BoardSlot] = []
	for child: Node in squad_row.get_children():
		var slot := child as BoardSlot
		if slot != null and not slot.is_preview():
			slots.append(slot)
	return slots


func _get_visible_real_slots() -> Array[BoardSlot]:
	var slots: Array[BoardSlot] = []
	for slot: BoardSlot in _get_real_slots():
		if slot.visible:
			slots.append(slot)
	return slots


func _capture_visible_slot_positions() -> Dictionary:
	var positions := {}
	for slot: BoardSlot in _get_visible_real_slots():
		# 保存玩家实际看见的卡面画布位置，而不是已提前跳到终点的
		# Container 根节点位置；也避免把显示链路位移当作本地逻辑像素。
		positions[slot] = (
			slot.card_visual_layer
			.get_global_transform_with_canvas()
			.origin
		)
	return positions


func _animate_layout_next_frame(previous_positions: Dictionary) -> void:
	if previous_positions.is_empty():
		return
	# 换位期间不叠加合法堆叠的旋转颤动；补间结束后下一帧会自然重算。
	_clear_stack_target_feedback()
	await get_tree().process_frame
	_start_layout_animation(previous_positions)


func _animate_layout_immediately(previous_positions: Dictionary) -> void:
	if previous_positions.is_empty():
		return
	_clear_stack_target_feedback()
	# 阵亡退场不能等待一帧：容器先算终点，再立即给视觉补回旧坐标偏移。
	# 普通拖放仍保留下一帧路径，因为其预留位需要等待新节点完成尺寸刷新。
	squad_row.queue_sort()
	squad_row.notification(Container.NOTIFICATION_SORT_CHILDREN)
	_start_layout_animation(previous_positions)


func _start_layout_animation(previous_positions: Dictionary) -> void:
	for slot_value: Variant in previous_positions:
		if is_instance_valid(slot_value):
			var slot := slot_value as BoardSlot
			if slot.visible and slot.get_parent() == squad_row:
				slot.animate_from_global_position(previous_positions[slot_value])


func _is_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var drag_data := data as Dictionary
	if drag_data.get("source_type") not in [&"collection", &"board"]:
		return false
	if drag_data.get("kind") == &"card":
		var card_data := drag_data.get("card_data") as CardData
		return card_data != null and card_data.card_type == CardData.CardType.MINION
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	return false
