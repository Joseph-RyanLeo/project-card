class_name BattlefieldRow
extends PanelContainer

signal board_slot_clicked(row: BattlefieldRow, slot: BoardSlot)
signal card_dropped(
	row: BattlefieldRow,
	insert_index: int,
	data: Dictionary,
	card_global_position: Vector2
)
signal card_click_carry_requested(data: Dictionary, pointer_global_position: Vector2)

const BOARD_SLOT_SCENE: PackedScene = preload("res://scenes/ui/BoardSlot.tscn")
const BATTLEFIELD_UNIT_COUNT: int = 21 # 单排可使用的战场单元总容量
const BATTLEFIELD_UNIT_WIDTH: int = 33 # 一个战场单元对应的像素宽度
const SINGLE_CARD_UNIT_COUNT: int = 3 # 单卡小队占用的战场单元数
const SINGLE_CARD_WIDTH: int = 99 # 单张裸卡保持的固定显示宽度
const SQUAD_GAP: int = 18 # 同一排相邻小队之间的固定间距
const FULL_ROW_DISPLAY_WIDTH: int = 801 # 七个单卡小队含六段间距的真实显示宽度
const DROP_PREVIEW_Z_INDEX: int = 1000 # 目标虚影高于所有真实小队、低于鼠标携带卡牌的全局层级
const STACK_TARGET_FEEDBACK_RADIUS: float = 400.0 # 拖动单卡时，附近合法叠卡目标开始持续旋转颤动的中心距离
const STACK_OVERLAP_MIN: float = 10.0 # 两张卡相向边界至少覆盖该距离才进入叠卡吸附带
const STACK_SINGLE_RUNE_OVERLAP_MAX: float = 40.0 # 覆盖 10～40px 时按盖住一个符文处理
const STACK_OVERLAP_MAX: float = 70.0 # 覆盖 41～70px 时按盖住两个符文处理，超过后退出吸附带
const NEW_SQUAD_INSERT_RADIUS: float = 16.0 # 有容量时，拖动卡中心距相邻小队间隙中心多近会优先新建小队
const STACKED_RUNE_STEP_WIDTH: float = 30.0 # 预留位中一个可堆叠符文对应的横向像素宽度
const STACKED_CARD_BORDER_WIDTH: float = 1.0 # 剩余不足三单元时额外保留的卡牌边框宽度

@export var row_title: String = "前排" # 显示在该战场行左上角的名称

@onready var row_title_label: Label = %RowTitleLabel
@onready var row_display_area: Control = %RowDisplayArea
@onready var squad_row: HBoxContainer = %SquadRow
@onready var placement_overlay: Control = %PlacementOverlay

var _drag_enabled: bool = false
var _prefer_minion: bool = true
var _preview_slot: BoardSlot
var _preview_insert_index: int = -1
var _preview_intent: Dictionary = {}
var _preview_pointer_x: float = INF
var _preview_replaced_slot: BoardSlot
var _reservation_slot: Control
var _reservation_insert_index: int = -1
var _reservation_width: float = 0.0
var _hidden_source_slot: BoardSlot
var _active_drag_preview_offset: Vector2 = Vector2.ZERO
var _active_drag_visual: CardDragPreview
var _active_stack_feedback_drag_data: Dictionary = {}


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
	var local_position := (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* get_viewport().get_mouse_position()
	)
	_update_stack_target_feedback(
		local_position.x,
		_active_stack_feedback_drag_data
	)


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
	return slot


func remove_squad_slot(slot: BoardSlot) -> SquadData:
	if slot == null or slot.get_parent() != squad_row or slot.is_preview():
		return null
	var previous_positions := _capture_visible_slot_positions()
	var squad_data := slot.get_squad_data()
	squad_row.remove_child(slot)
	slot.queue_free()
	_animate_layout_next_frame(previous_positions)
	return squad_data


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


func can_receive_card_drag(data: Variant) -> bool:
	return _drag_enabled and _is_drag_data(data)


func preview_card_drop(at_position: Vector2, data: Variant) -> bool:
	if not can_receive_card_drag(data):
		clear_drop_preview()
		return false
	# 合并预览会暂时隐藏真实目标。每次移动时先让它参与命中测试，
	# 才能在同一张目标卡上持续切换 30px / 60px 两个双卡吸附点。
	if is_instance_valid(_preview_replaced_slot):
		_preview_replaced_slot.visible = true
	var drag_data := data as Dictionary
	# 第一次进入本行时必须先按玩家当前看见的卡牌位置锁定意图，再创建
	# 会推动整排的预留位；否则预留位先移动目标，刚命中的卡边吸附带会
	# 被系统自己的布局变化立刻破坏。
	if not has_drop_reservation():
		_update_stack_target_feedback(at_position.x, drag_data)
		var initial_intent := _build_drop_intent(at_position, drag_data)
		var initial_intent_valid := (
			not initial_intent.is_empty()
			and _intent_fits_capacity(initial_intent, drag_data)
		)
		_ensure_drop_reservation(at_position.x, drag_data)
		if initial_intent_valid:
			_show_intent_preview(initial_intent)
			_preview_pointer_x = at_position.x
			return true
	_ensure_drop_reservation(at_position.x, drag_data)
	_update_stack_target_feedback(at_position.x, drag_data)
	# Godot 会在鼠标松开时用同一个坐标再次询问 _can_drop_data。
	# 此时拖拽快照可能仍在追赶鼠标；不能因为快照位置变化，就把玩家
	# 已经看到的叠卡虚影临时改判为新建小队。
	if (
		not _preview_intent.is_empty()
		and is_instance_valid(_preview_slot)
		and is_equal_approx(at_position.x, _preview_pointer_x)
	):
		if is_instance_valid(_preview_replaced_slot):
			_preview_replaced_slot.visible = false
		return true
	# 新建小队虚影出现后，完整虚影区域是稳定的释放区；但玩家继续
	# 移到相邻卡边的 10～70px 覆盖带时，必须允许切换为叠卡。
	if (
		_preview_intent.get("operation") == &"new_squad"
		and is_instance_valid(_preview_slot)
		and _reservation_contains_row_x(
			_get_drag_card_center_x(at_position.x, drag_data)
		)
		and _find_card_stack_target(at_position.x, drag_data) == null
	):
		_preview_pointer_x = at_position.x
		return true
	var intent := _build_drop_intent(at_position, drag_data)
	if intent.is_empty() or not _intent_fits_capacity(intent, data as Dictionary):
		_clear_intent_preview()
		return false
	if _same_intent(intent, _preview_intent):
		_preview_pointer_x = at_position.x
		if is_instance_valid(_preview_replaced_slot):
			_preview_replaced_slot.visible = false
		return true
	_show_intent_preview(intent)
	_preview_pointer_x = at_position.x
	return true


func commit_card_drop(at_position: Vector2, data: Variant) -> void:
	if not can_receive_card_drag(data):
		clear_drop_preview()
		return
	# 鼠标移动阶段已经持续重算吸附点；松手时直接提交最后一次预览，
	# 避免目标因虚影临时隐藏而被再次误判为空位。
	if _preview_intent.is_empty() and not preview_card_drop(at_position, data):
		return
	var intent := _preview_intent.duplicate()
	var insert_index := int(intent.get("squad_index", 0))
	var drag_data := (data as Dictionary).duplicate()
	drag_data["drop_intent"] = intent
	var preview_offset: Vector2 = drag_data.get("preview_offset", Vector2.ZERO)
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
	return _reservation_slot.size.x if has_drop_reservation() else 0.0


func get_drop_reservation_index() -> int:
	return _reservation_insert_index


func clear_drop_preview(clear_stack_feedback: bool = true) -> void:
	_clear_intent_preview()
	_clear_drop_reservation()
	if clear_stack_feedback:
		_clear_stack_target_feedback()


func _clear_intent_preview() -> void:
	if _preview_slot != null:
		var preview_parent := _preview_slot.get_parent()
		if preview_parent != null:
			preview_parent.remove_child(_preview_slot)
		_preview_slot.queue_free()
		_preview_slot = null
	if is_instance_valid(_preview_replaced_slot):
		_preview_replaced_slot.visible = true
	_preview_replaced_slot = null
	_preview_insert_index = -1
	_preview_intent = {}
	_preview_pointer_x = INF
	if has_drop_reservation():
		_set_drop_reservation_empty_width(_reservation_width)


func _ensure_drop_reservation(pointer_x: float, data: Dictionary) -> void:
	if data.get("kind") != &"card" or has_drop_reservation():
		return
	var new_squad_intent := {
		"operation": &"new_squad",
		"squad_index": _find_insert_index(
			_get_drag_card_center_x(pointer_x, data)
		),
		"card_index": 0,
		"result_squad": SquadData.from_card(data.get("card_data") as CardData),
	}
	if (
		not _intent_fits_capacity(new_squad_intent, data)
		and _get_legal_stack_candidates(pointer_x, data).is_empty()
	):
		return

	var previous_positions := _capture_visible_slot_positions()
	var remaining_units := _get_units_available_after_source_lift(data)
	if remaining_units <= 0:
		return
	var reserved_card_width := (
		float(SINGLE_CARD_WIDTH)
		if remaining_units >= SINGLE_CARD_UNIT_COUNT
		else (
			remaining_units * STACKED_RUNE_STEP_WIDTH
			+ STACKED_CARD_BORDER_WIDTH
		)
	)
	# 固定预算包含卡牌/最大叠卡宽度以及新增预留节点带来的一段小队间距。
	_reservation_width = reserved_card_width + SQUAD_GAP
	_reservation_insert_index = _find_insert_index(
		_get_drag_card_center_x(pointer_x, data)
	)
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


func _clear_drop_reservation() -> void:
	if is_instance_valid(_reservation_slot):
		var reservation_parent := _reservation_slot.get_parent()
		if reservation_parent != null:
			reservation_parent.remove_child(_reservation_slot)
		_reservation_slot.queue_free()
	_reservation_slot = null
	_reservation_insert_index = -1
	_reservation_width = 0.0


func _set_drop_reservation_empty_width(value: float) -> void:
	if not has_drop_reservation():
		return
	# 固定总预算只会因新增预留节点多出一段 HBox 间距；叠卡虚影
	# 增长由调用方先扣除，剩余部分全部作为纯空白节点宽度。
	var empty_width := maxf(0.0, value - SQUAD_GAP)
	_reservation_slot.custom_minimum_size.x = empty_width
	_reservation_slot.size.x = empty_width


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


func _reservation_contains_row_x(row_x: float) -> bool:
	return (
		has_drop_reservation()
		and row_x >= _reservation_slot.position.x
		and row_x < _reservation_slot.position.x + _reservation_slot.size.x
	)


func _move_drop_reservation(insert_index: int) -> void:
	if not has_drop_reservation():
		return
	var visible_slots := _get_visible_real_slots()
	if insert_index >= visible_slots.size():
		squad_row.move_child(_reservation_slot, squad_row.get_child_count() - 1)
	else:
		_move_child_before(_reservation_slot, visible_slots[insert_index])


func update_stack_target_feedback_global(
	pointer_global_position: Vector2,
	data: Dictionary
) -> void:
	if not can_receive_card_drag(data) or data.get("kind") != &"card":
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


func _build_drop_intent(at_position: Vector2, data: Dictionary) -> Dictionary:
	var kind := data.get("kind") as StringName
	if kind == &"squad":
		var occupied_slot := _find_slot_at_x(at_position.x)
		if occupied_slot != null:
			return {}
		return {
			"operation": &"move_squad",
			"squad_index": _find_insert_index(at_position.x),
			"result_squad": data.get("squad_data"),
		}
	if kind != &"card":
		return {}
	var card_data := data.get("card_data") as CardData
	var target_slot := _find_card_stack_target(at_position.x, data)
	if target_slot == null:
		return {
			"operation": &"new_squad",
			"squad_index": _find_insert_index(
				_get_drag_card_center_x(at_position.x, data)
			),
			"card_index": 0,
			"result_squad": SquadData.from_card(card_data),
		}
	return _build_capacity_fitting_merge_intent(
		target_slot,
		at_position.x,
		data
	)


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
	if not result.insert_card(card_data, card_index, layout):
		return {}
	return {
		"operation": &"merge_card",
		"squad_index": get_slot_index(target_slot),
		"card_index": card_index,
		"two_card_layout": layout,
		"target_slot": target_slot,
		"result_squad": result,
	}


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


func _show_intent_preview(intent: Dictionary) -> void:
	var previous_positions := _capture_visible_slot_positions()
	_clear_intent_preview()
	_preview_intent = intent
	_preview_insert_index = int(intent.get("squad_index", 0))
	var operation := intent.get("operation") as StringName
	if (
		operation == &"new_squad"
		and has_drop_reservation()
		and _reservation_insert_index != _preview_insert_index
	):
		# 稳定的是总让位宽度，不是首次进入战场时的位置。独立部署的
		# 插入边界变化后，预留位与它的单卡虚影必须一起移动到新索引。
		_reservation_insert_index = _preview_insert_index
		_move_drop_reservation(_reservation_insert_index)
	_preview_replaced_slot = intent.get("target_slot") as BoardSlot
	if is_instance_valid(_preview_replaced_slot):
		_preview_replaced_slot.visible = false
	_preview_slot = BOARD_SLOT_SCENE.instantiate() as BoardSlot
	if operation == &"new_squad" and has_drop_reservation():
		_reservation_slot.add_child(_preview_slot)
	else:
		squad_row.add_child(_preview_slot)
	_preview_slot.z_index = DROP_PREVIEW_Z_INDEX
	var preview_squad := intent.get("result_squad") as SquadData
	# 单卡预览只让待加入卡半透明；整队移动则保持整队虚影。
	_preview_slot.set_preview_squad(
		preview_squad,
		preview_squad.get_effect_source()
		if operation in [&"new_squad", &"merge_card"]
		else null
	)
	if is_instance_valid(_preview_replaced_slot):
		_preview_slot.set_stack_target_feedback(
			_preview_replaced_slot.get_stack_target_feedback_strength()
		)
	if operation != &"new_squad":
		# 先把虚影放到最终兄弟顺序，再按预留位真实左右邻居扣除 HBox 间距。
		_move_preview_slot(_preview_insert_index)
	if (
		operation == &"merge_card"
		and has_drop_reservation()
		and is_instance_valid(_preview_replaced_slot)
	):
		var preview_growth := maxf(
			0.0,
			_preview_slot.size.x - _preview_replaced_slot.size.x
		)
		# 虚影横向增加的 30/60px 属于总预留预算的一部分，不能再额外
		# 撑宽整排；纯空白宽度只保留“总预算 - 虚影增量”。
		_set_drop_reservation_empty_width(
			_reservation_width - preview_growth
		)
	elif has_drop_reservation():
		_set_drop_reservation_empty_width(_reservation_width)
	if operation == &"new_squad" and has_drop_reservation():
		_preview_slot.position = Vector2(
			(_reservation_slot.size.x - _preview_slot.size.x) * 0.5,
			0.0
		)
	_animate_layout_next_frame(previous_positions)


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
	# 无论来源位于手牌还是战场，都先清掉本行遗留的悬停视觉。
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
	_active_drag_preview_offset = drag_data.get("preview_offset", Vector2.ZERO)
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


func _find_slot_at_x(pointer_x: float) -> BoardSlot:
	for slot: BoardSlot in _get_visible_real_slots():
		if pointer_x >= slot.position.x and pointer_x < slot.position.x + slot.size.x:
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
	if candidates.is_empty():
		return null
	var source_slot := data.get("source_slot") as BoardSlot
	var nearest_new_overlapping: BoardSlot
	var nearest_new_overlapping_distance := INF
	var overlapping_source: BoardSlot
	var overlapping_source_distance := INF
	for candidate: Dictionary in candidates:
		var slot := candidate.get("slot") as BoardSlot
		var distance := float(candidate.get("distance", INF))
		if not _is_in_stack_overlap_band(slot, pointer_x, data):
			continue
		if slot == source_slot:
			if distance < overlapping_source_distance:
				overlapping_source = slot
				overlapping_source_distance = distance
		elif distance < nearest_new_overlapping_distance:
			nearest_new_overlapping = slot
			nearest_new_overlapping_distance = distance
	# 从小队抽出的卡仍覆盖来源小队时，玩家最可能是在调整水平位置或
	# 把下层卡提到最上。来源小队必须先于旁边目标和新建小队判定。
	if overlapping_source != null:
		return overlapping_source
	# 手牌卡或已经完全离开来源小队的场上卡，仍可使用两个小队之间的
	# 独立部署区；这项判断要放在其他重叠目标之前。
	if _can_use_new_squad_insert_zone(pointer_x, data):
		return null
	if nearest_new_overlapping != null:
		return nearest_new_overlapping

	# 即使当前容量无法新建小队，也不能越过 10～70px 卡边覆盖带，
	# 自动跳去远处目标；没有精确命中时保持无效放置。
	return null


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


func _can_use_new_squad_insert_zone(
	pointer_x: float,
	data: Dictionary
) -> bool:
	var new_squad_intent := {
		"operation": &"new_squad",
		"squad_index": _find_insert_index(
			_get_drag_card_center_x(pointer_x, data)
		),
		"card_index": 0,
		"result_squad": SquadData.from_card(data.get("card_data") as CardData),
	}
	if not _intent_fits_capacity(new_squad_intent, data):
		return false
	var drag_center_x := _get_drag_card_center_x(pointer_x, data)
	var visible_slots := _get_visible_real_slots()
	for index: int in visible_slots.size() - 1:
		var left_slot := visible_slots[index]
		var right_slot := visible_slots[index + 1]
		var gap_center_x := (
			left_slot.position.x + left_slot.size.x + right_slot.position.x
		) * 0.5
		if absf(drag_center_x - gap_center_x) <= NEW_SQUAD_INSERT_RADIUS:
			return true
	return false


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
		var slot_center_x := slot.position.x + slot.size.x * 0.5
		candidates.append({
			"slot": slot,
			"intent": intent,
			"distance": absf(drag_center_x - slot_center_x),
		})
	return candidates


func _update_stack_target_feedback(pointer_x: float, data: Dictionary) -> void:
	if data.get("kind") != &"card":
		_clear_stack_target_feedback()
		return
	var updated_slots := {}
	var source_slot := data.get("source_slot") as BoardSlot
	for candidate: Dictionary in _get_legal_stack_candidates(pointer_x, data):
		var distance := float(candidate.get("distance", INF))
		if distance > STACK_TARGET_FEEDBACK_RADIUS:
			continue
		var strength := 1.0 - distance / STACK_TARGET_FEEDBACK_RADIUS
		# 平方曲线让远处快速变弱，只保留最近一两个目标的清晰提示。
		strength *= strength
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


func _clear_stack_target_feedback() -> void:
	for slot: BoardSlot in _get_real_slots():
		slot.set_stack_target_feedback(0.0)


func _find_insert_index(pointer_x: float) -> int:
	var visible_slots := _get_visible_real_slots()
	for index: int in visible_slots.size():
		var slot := visible_slots[index]
		if pointer_x < slot.position.x + slot.size.x * 0.5:
			return index
	return visible_slots.size()


func _find_card_insert_index(
	slot: BoardSlot,
	pointer_x: float,
	remaining_count: int,
	drag_data: Dictionary
) -> int:
	var drag_center_x := _get_drag_card_center_x(pointer_x, drag_data)
	var local_x := drag_center_x - slot.position.x
	if remaining_count <= 1:
		return 0 if local_x < slot.size.x * 0.5 else 1
	if local_x < slot.size.x / 3.0:
		return 0
	if local_x < slot.size.x * 2.0 / 3.0:
		return 1
	return 2


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
	var target_left := _get_slot_visual_left_x(slot)
	var target_right := target_left + SquadView.CARD_SIZE.x
	var drag_center := (drag_left + drag_right) * 0.5
	var target_center := (target_left + target_right) * 0.5
	return maxf(
		0.0,
		target_right - drag_left
		if drag_center >= target_center
		else drag_right - target_left
	)


func _get_slot_visual_left_x(slot: BoardSlot) -> float:
	var primary_view := slot.get_primary_card_view()
	if primary_view == null or not primary_view.is_inside_tree():
		return slot.position.x
	var global_left := (
		primary_view.get_global_transform_with_canvas() * Vector2.ZERO
	)
	return (
		placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* global_left
	).x


func _is_in_stack_overlap_band(
	slot: BoardSlot,
	pointer_x: float,
	drag_data: Dictionary
) -> bool:
	var overlap := _get_stack_overlap(slot, pointer_x, drag_data)
	return (
		overlap >= STACK_OVERLAP_MIN
		and overlap <= STACK_OVERLAP_MAX
	)


func _get_drag_card_left_x(pointer_x: float, drag_data: Dictionary) -> float:
	var visual_rect := _get_drag_visual_rect(drag_data)
	if visual_rect.size.x > 0.0:
		return visual_rect.position.x
	if not drag_data.has("grab_local_position"):
		return pointer_x
	var grab_local_position: Vector2 = drag_data.get("grab_local_position", Vector2.ZERO)
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	var visual_scale_x := preview_scale.x * CardDragPreview.DRAG_SCALE_MULTIPLIER
	return pointer_x - grab_local_position.x * visual_scale_x


func _get_drag_card_width(drag_data: Dictionary) -> float:
	var visual_rect := _get_drag_visual_rect(drag_data)
	if visual_rect.size.x > 0.0:
		return visual_rect.size.x
	var preview_scale: Vector2 = drag_data.get("preview_scale", Vector2.ONE)
	return SquadView.CARD_SIZE.x * preview_scale.x * CardDragPreview.DRAG_SCALE_MULTIPLIER


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
		positions[slot] = slot.global_position
	return positions


func _animate_layout_next_frame(previous_positions: Dictionary) -> void:
	if previous_positions.is_empty():
		return
	await get_tree().process_frame
	for slot_value: Variant in previous_positions:
		if is_instance_valid(slot_value):
			var slot := slot_value as BoardSlot
			if slot.visible and slot.get_parent() == squad_row:
				slot.animate_from_global_position(previous_positions[slot_value])


func _is_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var drag_data := data as Dictionary
	if drag_data.get("source_type") not in [&"hand", &"board"]:
		return false
	if drag_data.get("kind") == &"card":
		return drag_data.get("card_data") is CardData
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	return false
