@tool
class_name CardArtTuner
extends Control

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const CARD_RESOURCE_PATHS := [
	"res://resources/cards/ember_squire.tres",
	"res://resources/cards/tide_archer.tres",
	"res://resources/cards/spark_mage.tres",
	"res://resources/cards/dusk_mender.tres",
	"res://resources/cards/thorn_guard.tres",
	"res://resources/cards/shadow_slinger.tres",
	"res://resources/cards/grove_lancer.tres",
	"res://resources/cards/sunlit_bastion.tres",
]

@export_group("Card Art Preview")
@export var card_data: CardData:
	set(value):
		_card_data = value
		_preview_art_offset = (
			value.art_offset if value != null else Vector2i.ZERO
		)
		_sync_runtime_controls()
		_queue_preview_refresh()
		notify_property_list_changed()
	get:
		return _card_data

@export var preview_art_offset: Vector2i = Vector2i.ZERO:
	set(value):
		_preview_art_offset = value
		_sync_offset_controls()
		_queue_preview_refresh()
	get:
		return _preview_art_offset

@export_tool_button("保存偏移到卡牌资源", "Save")
var save_offset_button: Callable = _save_offset_to_resource

@export_tool_button("从卡牌资源重新载入", "Reload")
var reload_offset_button: Callable = _reload_offset_from_resource

@export_tool_button("预览偏移归零", "Clear")
var reset_offset_button: Callable = _reset_preview_offset

var _card_data: CardData
var _preview_art_offset: Vector2i = Vector2i.ZERO
var _refresh_queued: bool = false

@onready var preview_card: CardView = %PreviewCard
@onready var status_label: Label = %StatusLabel
@onready var card_selector: OptionButton = %CardSelector
@onready var offset_x_spin_box: SpinBox = %OffsetXSpinBox
@onready var offset_y_spin_box: SpinBox = %OffsetYSpinBox
@onready var back_button: Button = %BackButton
@onready var nudge_left_button: Button = %NudgeLeftButton
@onready var nudge_right_button: Button = %NudgeRightButton
@onready var nudge_up_button: Button = %NudgeUpButton
@onready var nudge_down_button: Button = %NudgeDownButton
@onready var save_button: Button = %SaveButton
@onready var reload_button: Button = %ReloadButton
@onready var reset_button: Button = %ResetButton


func _ready() -> void:
	_populate_card_selector()
	_connect_runtime_controls()
	_sync_runtime_controls()
	_refresh_preview()


func _populate_card_selector() -> void:
	card_selector.clear()
	for resource_path: String in CARD_RESOURCE_PATHS:
		var available_card := load(resource_path) as CardData
		if available_card == null:
			continue
		card_selector.add_item(available_card.display_name)
		var item_index := card_selector.item_count - 1
		card_selector.set_item_metadata(item_index, resource_path)


func _connect_runtime_controls() -> void:
	card_selector.item_selected.connect(_on_card_selected)
	offset_x_spin_box.value_changed.connect(_on_offset_x_changed)
	offset_y_spin_box.value_changed.connect(_on_offset_y_changed)
	back_button.pressed.connect(_on_back_button_pressed)
	nudge_left_button.pressed.connect(_nudge_preview.bind(Vector2i.LEFT))
	nudge_right_button.pressed.connect(_nudge_preview.bind(Vector2i.RIGHT))
	nudge_up_button.pressed.connect(_nudge_preview.bind(Vector2i.UP))
	nudge_down_button.pressed.connect(_nudge_preview.bind(Vector2i.DOWN))
	save_button.pressed.connect(_save_offset_to_resource)
	reload_button.pressed.connect(_reload_offset_from_resource)
	reset_button.pressed.connect(_reset_preview_offset)


func _sync_runtime_controls() -> void:
	if not is_node_ready():
		return
	_sync_card_selector()
	_sync_offset_controls()


func _sync_card_selector() -> void:
	if not is_instance_valid(card_selector) or card_data == null:
		return
	for item_index: int in card_selector.item_count:
		if card_selector.get_item_metadata(item_index) == card_data.resource_path:
			card_selector.select(item_index)
			return


func _sync_offset_controls() -> void:
	if not is_instance_valid(offset_x_spin_box):
		return
	offset_x_spin_box.set_block_signals(true)
	offset_y_spin_box.set_block_signals(true)
	offset_x_spin_box.value = preview_art_offset.x
	offset_y_spin_box.value = preview_art_offset.y
	offset_x_spin_box.set_block_signals(false)
	offset_y_spin_box.set_block_signals(false)


func _on_card_selected(item_index: int) -> void:
	var resource_path := str(card_selector.get_item_metadata(item_index))
	var selected_resource := load(resource_path) as CardData
	if selected_resource == null:
		_set_status("无法载入卡牌资源：%s" % resource_path)
		return
	card_data = selected_resource


func _on_offset_x_changed(value: float) -> void:
	preview_art_offset = Vector2i(int(value), preview_art_offset.y)


func _on_offset_y_changed(value: float) -> void:
	preview_art_offset = Vector2i(preview_art_offset.x, int(value))


func _nudge_preview(direction: Vector2i) -> void:
	preview_art_offset += direction


func _on_back_button_pressed() -> void:
	if Engine.is_editor_hint():
		_set_status("请运行场景后使用“返回主界面”。")
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _queue_preview_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return

	_refresh_queued = true
	call_deferred("_refresh_preview")


func _refresh_preview() -> void:
	_refresh_queued = false
	if not is_instance_valid(preview_card):
		return

	if card_data == null:
		preview_card.set_card_data(null)
		status_label.text = "请在检查器中选择一张 CardData 资源。"
		return

	# 预览只操作副本。拖动数值时不会提前修改真正的 .tres 文件。
	var preview_data := card_data.duplicate(true) as CardData
	preview_data.art_offset = preview_art_offset
	preview_card.set_card_data(preview_data)
	preview_card.configure_drag_source(false)
	status_label.text = "%s  |  当前预览偏移：%s" % [
		card_data.display_name,
		preview_art_offset,
	]


func _save_offset_to_resource() -> void:
	if card_data == null:
		_set_status("没有可保存的 CardData。")
		return
	if card_data.resource_path.is_empty():
		_set_status("该 CardData 没有独立资源路径，无法保存。")
		return

	card_data.art_offset = preview_art_offset
	card_data.emit_changed()
	var error := ResourceSaver.save(card_data, card_data.resource_path)
	if error == OK:
		_refresh_preview()
		_set_status("已保存：%s  偏移 %s" % [
			card_data.display_name,
			preview_art_offset,
		])
	else:
		_set_status("保存失败，错误码：%d" % error)


func _reload_offset_from_resource() -> void:
	if card_data == null:
		_set_status("没有可重新载入的 CardData。")
		return

	preview_art_offset = card_data.art_offset
	_set_status("已恢复资源中的偏移：%s" % preview_art_offset)


func _reset_preview_offset() -> void:
	preview_art_offset = Vector2i.ZERO
	_set_status("预览偏移已归零；点击保存后才会写入资源。")


func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
