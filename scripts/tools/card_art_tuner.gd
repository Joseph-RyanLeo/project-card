@tool
class_name CardArtTuner
extends Control

## 自动发现卡牌、筛选卡包与类型、编辑基础资料及立绘的辅助工具。
## 所有交互先修改预览副本；只有显式点击保存才会写回 .tres 资源。

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const CARD_PREVIEW_SHADER: Shader = preload(
	"res://shaders/card_preview_3d.gdshader"
)
const PREVIEW_EFFECT_PADDING_BOTTOM_RIGHT := Vector2(4.0, 4.0) # 在卡面真实越界范围外为 3D 投影额外保留的右下透明边
const PREVIEW_POINTER_RESPONSE: float = 12.0 # 鼠标进入、离开时 3D 倾斜追随与回正速度
const PREVIEW_MAX_TILT_DEGREES: float = 10.0 # 4× 预览跟随鼠标时的最大倾斜角度
const PREVIEW_PROJECTION_INSET: float = 0.0 # 透视补偿内缩量；0 保持开关 3D 前后的卡面尺寸一致
const PREVIEW_FLASH_SPACING: float = 7.0 # 扫光条纹密度；越大，同屏出现的光带越多
const PREVIEW_FLASH_WIDTH: float = 2.4 # 扫光指数；越大光带越窄，越小光带越宽
const PREVIEW_FLASH_INTENSITY: float = 0.32 # 扫光叠加亮度；建议在 0.2～0.6 之间微调
const CARD_RESOURCE_DIRECTORY := "res://resources/cards"
const ALL_PACK_ID: StringName = &"__all_packs__"
const ALL_CARD_TYPES: int = -2 # 全部种类的选项ID；避开OptionButton把-1解释为自动编号
const SELECTABLE_CARD_TYPES := [
	CardData.CardType.MINION, CardData.CardType.EQUIPMENT,
	CardData.CardType.SPELL, CardData.CardType.RESOURCE,
]

signal card_resource_saved(resource: CardData)

# 原资源与每张卡的预览草稿分开，切换筛选时不丢失尚未保存的编辑。
var _catalog: Array[CardData] = []
var _drafts: Dictionary = {}
var _preview_data: CardData
var _active_pack_id: StringName = ALL_PACK_ID

@export_group("Card Art Preview")
@export var card_data: CardData:
	# 检查器切换卡牌时，同时重置预览偏移并刷新运行时控件。
	set(value):
		_card_data = value
		if value != null:
			var key := _draft_key(value)
			if not _drafts.has(key): _drafts[key] = value.duplicate() as CardData
			_preview_data = _drafts[key]
		else: _preview_data = null
		_preview_art_offset = _preview_data.art_offset if _preview_data != null else Vector2i.ZERO
		_sync_runtime_controls()
		_queue_preview_refresh()
		notify_property_list_changed()
	get:
		return _card_data

@export var preview_art_offset: Vector2i = Vector2i.ZERO:
	# 临时预览值与 card_data.art_offset 分离，保存前不会修改真实资源。
	set(value):
		_preview_art_offset = value
		if _preview_data != null: _preview_data.art_offset = value
		_sync_offset_controls()
		_queue_preview_refresh()
	get:
		return _preview_art_offset

@export_tool_button("保存卡牌修改", "Save")
var save_card_button: Callable = _save_card_to_resource

@export_tool_button("从卡牌资源重新载入", "Reload")
var reload_card_button: Callable = _reload_card_from_resource

@export_tool_button("预览偏移归零", "Clear")
var reset_offset_button: Callable = _reset_preview_offset

var _card_data: CardData
var _preview_art_offset: Vector2i = Vector2i.ZERO
var _refresh_queued: bool = false
var _preview_effect_material: ShaderMaterial
var _preview_pointer_force := Vector2.ZERO
var _active_selector_card_type: int = -1

@onready var preview_card: CardView = %PreviewCard
@onready var preview_viewport: SubViewport = %PreviewViewport
@onready var preview_display: TextureRect = %PreviewDisplay
@onready var status_label: Label = %StatusLabel
@onready var card_type_selector: OptionButton = %CardTypeSelector
@onready var card_selector: ItemList = %CardSelector
@onready var pack_selector: OptionButton = %PackSelector
@onready var search_input: LineEdit = %SearchInput
@onready var refresh_catalog_button: Button = %RefreshCatalogButton
@onready var name_input: LineEdit = %NameInput
@onready var value_spin_box: SpinBox = %ValueSpinBox
@onready var health_spin_box: SpinBox = %HealthSpinBox
@onready var armor_spin_box: SpinBox = %ArmorSpinBox
@onready var value_title: Label = %ValueTitle
@onready var health_title: Label = %HealthTitle
@onready var armor_title: Label = %ArmorTitle
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
@onready var use_3d_check: CheckButton = %Use3DCheck
@onready var use_flash_check: CheckButton = %UseFlashCheck
@onready var flash_type_selector: OptionButton = %FlashTypeSelector


func _ready() -> void:
	# 场景节点就绪后再连接信号，避免 @tool 属性 setter 访问空节点。
	# 原始 CardView 在带透明安全边的 SubViewport 内以 1 倍渲染；显示节点再整体放大
	# 4 倍并应用 Shader，保证边框、立绘、文字不会分别产生不同透视。
	preview_card.pivot_offset = Vector2.ZERO
	_setup_effect_preview()
	_reload_catalog()
	_populate_card_type_selector()
	_populate_pack_selector()
	_populate_card_selector()
	_populate_effect_controls()
	_sync_effect_controls_to_material()
	_connect_runtime_controls()
	_sync_runtime_controls()
	_refresh_preview()
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_preview_effect_material):
		return
	var target_force := Vector2.ZERO
	var local_pointer := preview_display.get_local_mouse_position()
	if Rect2(Vector2.ZERO, preview_display.size).has_point(local_pointer):
		target_force = Vector2(
			(local_pointer.x / preview_display.size.x - 0.5) * 2.0,
			(local_pointer.y / preview_display.size.y - 0.5) * 2.0
		)
		target_force = target_force.clamp(Vector2(-1.0, -1.0), Vector2.ONE)
	var response := 1.0 - exp(-PREVIEW_POINTER_RESPONSE * delta)
	_preview_pointer_force = _preview_pointer_force.lerp(target_force, response)
	_preview_effect_material.set_shader_parameter(
		"pointer_force",
		_preview_pointer_force
	)


func _input(event: InputEvent) -> void:
	# 运行调整器时方向键与四个 1px 按钮共用同一事务入口；
	# @tool 编辑器预览不截获编辑器自身的方向键。
	if Engine.is_editor_hint() or not (event is InputEventKey):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox or focus is ItemList or focus is OptionButton:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	var direction := Vector2i.ZERO
	match key_event.keycode:
		KEY_LEFT:
			direction = Vector2i.LEFT
		KEY_RIGHT:
			direction = Vector2i.RIGHT
		KEY_UP:
			direction = Vector2i.UP
		KEY_DOWN:
			direction = Vector2i.DOWN
		_:
			return
	_nudge_preview(direction)
	get_viewport().set_input_as_handled()


func _setup_effect_preview() -> void:
	var card_padding := preview_card.get_max_visual_capture_padding_top_left()
	var render_size := (
		card_padding
		+ preview_card.card_size
		+ preview_card.get_visual_capture_padding_bottom_right()
		+ PREVIEW_EFFECT_PADDING_BOTTOM_RIGHT
	)
	preview_card.set_layout_position(card_padding)
	preview_viewport.size = Vector2i(render_size)
	preview_display.size = render_size
	preview_display.texture = preview_viewport.get_texture()
	_preview_effect_material = ShaderMaterial.new()
	_preview_effect_material.shader = CARD_PREVIEW_SHADER
	_preview_effect_material.set_shader_parameter(
		"card_texture_size_px",
		render_size
	)
	_preview_effect_material.set_shader_parameter(
		"max_tilt_degrees",
		PREVIEW_MAX_TILT_DEGREES
	)
	_preview_effect_material.set_shader_parameter(
		"inset",
		PREVIEW_PROJECTION_INSET
	)
	_preview_effect_material.set_shader_parameter(
		"stripe_spacing",
		PREVIEW_FLASH_SPACING
	)
	_preview_effect_material.set_shader_parameter(
		"stripe_width",
		PREVIEW_FLASH_WIDTH
	)
	_preview_effect_material.set_shader_parameter(
		"flash_intensity",
		PREVIEW_FLASH_INTENSITY
	)
	preview_display.material = _preview_effect_material


func _populate_effect_controls() -> void:
	flash_type_selector.clear()
	flash_type_selector.add_item("白光", 0)
	flash_type_selector.add_item("金色", 1)
	flash_type_selector.add_item("彩虹", 2)
	flash_type_selector.select(1)


func _sync_effect_controls_to_material() -> void:
	_on_use_3d_toggled(use_3d_check.button_pressed)
	_on_use_flash_toggled(use_flash_check.button_pressed)
	_on_flash_type_selected(flash_type_selector.selected)


static func discover_card_resource_paths(directory: String = CARD_RESOURCE_DIRECTORY) -> Array[String]:
	# ResourceLoader保留导出前的资源名，导出后转换为remap也能扫描；子目录同样自动收录。
	var result: Array[String] = []
	var filenames := ResourceLoader.list_directory(directory)
	filenames.sort()
	for filename: String in filenames:
		var path := directory.path_join(filename)
		if filename.ends_with("/"): result.append_array(discover_card_resource_paths(path))
		elif filename.get_extension() == "tres" and ResourceLoader.load(path) is CardData: result.append(path)
	return result


func _reload_catalog() -> void:
	_catalog.clear()
	for path: String in discover_card_resource_paths(): _catalog.append(load(path) as CardData)
	_catalog.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.pack_id != b.pack_id: return String(a.pack_id) < String(b.pack_id)
		if a.card_type != b.card_type: return a.card_type < b.card_type
		if a.rarity != b.rarity: return a.rarity < b.rarity
		return String(a.id) < String(b.id))


func _populate_card_type_selector() -> void:
	card_type_selector.clear()
	card_type_selector.add_item("全部种类", ALL_CARD_TYPES)
	for selectable_type: int in SELECTABLE_CARD_TYPES:
		card_type_selector.add_item(["随从", "装备", "法术", "资源"][selectable_type], selectable_type)
	_sync_card_type_selector()


func _populate_pack_selector() -> void:
	pack_selector.clear()
	pack_selector.add_item("全部卡包")
	pack_selector.set_item_metadata(0, ALL_PACK_ID)
	var packs: Array[StringName] = []
	for card: CardData in _catalog:
		if not packs.has(card.pack_id): packs.append(card.pack_id)
	packs.sort()
	for pack_id: StringName in packs:
		pack_selector.add_item(CardPackRegistry.get_display_name(pack_id) if not pack_id.is_empty() else "未指定卡包")
		pack_selector.set_item_metadata(pack_selector.item_count - 1, pack_id)
	var selected := 0
	for index: int in pack_selector.item_count:
		if pack_selector.get_item_metadata(index) == _active_pack_id: selected = index
	pack_selector.select(selected)
	_active_pack_id = pack_selector.get_item_metadata(selected)


func _populate_card_selector() -> void:
	card_selector.clear()
	var query := search_input.text.strip_edges().to_lower()
	for available_card: CardData in _catalog:
		if _active_selector_card_type >= 0 and available_card.card_type != _active_selector_card_type: continue
		if _active_pack_id != ALL_PACK_ID and available_card.pack_id != _active_pack_id: continue
		var preview := _drafts.get(_draft_key(available_card), available_card) as CardData
		if not query.is_empty() and not query in (preview.display_name + " " + String(available_card.id)).to_lower(): continue
		var suffix := " · 衍生" if available_card.is_derived else (" · 停用" if not available_card.is_available else "")
		card_selector.add_item(preview.display_name + (" *" if _has_unsaved_changes(available_card) else "") + suffix)
		card_selector.set_item_metadata(card_selector.item_count - 1, available_card.resource_path)
	var current_index := -1
	for index: int in card_selector.item_count:
		if card_data != null and card_selector.get_item_metadata(index) == card_data.resource_path: current_index = index
	if current_index >= 0: card_selector.select(current_index)
	elif card_selector.item_count > 0: _on_card_selected(0)
	else: card_data = null


func _on_pack_selected(index: int) -> void:
	_active_pack_id = pack_selector.get_item_metadata(index)
	_populate_card_selector()
	_queue_preview_refresh()


func _on_search_changed(_query: String) -> void:
	_populate_card_selector()
	_queue_preview_refresh()


func _on_refresh_catalog_pressed() -> void:
	_reload_catalog()
	_populate_pack_selector()
	_populate_card_selector()
	_queue_preview_refresh()


func _draft_key(card: CardData) -> String:
	return card.resource_path if not card.resource_path.is_empty() else "instance:%d" % card.get_instance_id()


func _editable_fields(card: CardData) -> Array[StringName]:
	var fields: Array[StringName] = [&"display_name", &"art_offset"]
	match card.card_type:
		CardData.CardType.MINION: fields.append_array([&"base_value", &"max_health", &"armor"])
		CardData.CardType.EQUIPMENT: fields.append_array([&"equipment_action_delta", &"equipment_health_delta", &"equipment_armor_delta"])
		CardData.CardType.RESOURCE: fields.append_array([&"max_health", &"armor"])
	return fields


func _has_unsaved_changes(source: CardData) -> bool:
	var draft := _drafts.get(_draft_key(source)) as CardData
	if draft == null: return false
	for field: StringName in _editable_fields(source):
		if draft.get(field) != source.get(field): return true
	return false


func _on_name_changed(value: String) -> void:
	if _preview_data == null: return
	_preview_data.display_name = value
	_queue_preview_refresh()


func _on_stat_changed(value: float, stat: StringName) -> void:
	if _preview_data == null: return
	var field := stat
	if _preview_data.card_type == CardData.CardType.EQUIPMENT:
		field = {&"base_value": &"equipment_action_delta", &"max_health": &"equipment_health_delta", &"armor": &"equipment_armor_delta"}[stat]
	if not _editable_fields(_preview_data).has(field): return
	_preview_data.set(field, roundi(value))
	_queue_preview_refresh()


func _connect_runtime_controls() -> void:
	# bind() 把方向参数预先绑定到四个按钮，共用一个微调函数。
	card_type_selector.item_selected.connect(_on_card_type_selected)
	pack_selector.item_selected.connect(_on_pack_selected)
	search_input.text_changed.connect(_on_search_changed)
	refresh_catalog_button.pressed.connect(_on_refresh_catalog_pressed)
	name_input.text_changed.connect(_on_name_changed)
	value_spin_box.value_changed.connect(_on_stat_changed.bind(&"base_value"))
	health_spin_box.value_changed.connect(_on_stat_changed.bind(&"max_health"))
	armor_spin_box.value_changed.connect(_on_stat_changed.bind(&"armor"))
	card_selector.item_selected.connect(_on_card_selected)
	offset_x_spin_box.value_changed.connect(_on_offset_x_changed)
	offset_y_spin_box.value_changed.connect(_on_offset_y_changed)
	back_button.pressed.connect(_on_back_button_pressed)
	nudge_left_button.pressed.connect(_nudge_preview.bind(Vector2i.LEFT))
	nudge_right_button.pressed.connect(_nudge_preview.bind(Vector2i.RIGHT))
	nudge_up_button.pressed.connect(_nudge_preview.bind(Vector2i.UP))
	nudge_down_button.pressed.connect(_nudge_preview.bind(Vector2i.DOWN))
	save_button.pressed.connect(_save_card_to_resource)
	reload_button.pressed.connect(_reload_card_from_resource)
	reset_button.pressed.connect(_reset_preview_offset)
	use_3d_check.toggled.connect(_on_use_3d_toggled)
	use_flash_check.toggled.connect(_on_use_flash_toggled)
	flash_type_selector.item_selected.connect(_on_flash_type_selected)


func _sync_runtime_controls() -> void:
	if not is_node_ready():
		return
	_sync_card_selector()
	_sync_offset_controls()
	_sync_card_fields()


func _sync_card_selector() -> void:
	if not is_instance_valid(card_selector) or card_data == null:
		return
	for item_index: int in card_selector.item_count:
		if card_selector.get_item_metadata(item_index) == card_data.resource_path:
			card_selector.select(item_index)
			card_selector.ensure_current_is_visible()
			return


func _sync_card_type_selector() -> void:
	if not is_instance_valid(card_type_selector):
		return
	for item_index: int in card_type_selector.item_count:
		if card_type_selector.get_item_id(item_index) == (ALL_CARD_TYPES if _active_selector_card_type < 0 else _active_selector_card_type):
			card_type_selector.select(item_index)
			return


func _sync_offset_controls() -> void:
	# 程序回填 SpinBox 时临时阻断信号，避免 setter 递归刷新。
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


func _on_card_type_selected(item_index: int) -> void:
	_active_selector_card_type = card_type_selector.get_item_id(item_index)
	if _active_selector_card_type == ALL_CARD_TYPES: _active_selector_card_type = -1
	_populate_card_selector()
	_queue_preview_refresh()


func _sync_card_fields() -> void:
	if not is_instance_valid(name_input): return
	name_input.set_block_signals(true)
	name_input.text = _preview_data.display_name if _preview_data != null else ""
	name_input.editable = _preview_data != null
	name_input.set_block_signals(false)
	var equipment := _preview_data != null and _preview_data.card_type == CardData.CardType.EQUIPMENT
	value_title.text = "数值修正" if equipment else "数值"
	health_title.text = "生命修正" if equipment else "生命值"
	armor_title.text = "护甲修正" if equipment else "护甲"
	for entry: Array in [[value_spin_box, &"base_value", &"equipment_action_delta", -99, CardData.MAXIMUM_BASE_VALUE], [health_spin_box, &"max_health", &"equipment_health_delta", -99, CardData.MAXIMUM_HEALTH], [armor_spin_box, &"armor", &"equipment_armor_delta", 0, CardData.MAXIMUM_ARMOR]]:
		var spin: SpinBox = entry[0]
		var field: StringName = entry[2] if equipment else entry[1]
		spin.set_block_signals(true)
		spin.min_value = entry[3] if equipment else 0
		spin.max_value = 99 if equipment else entry[4]
		spin.editable = _preview_data != null and _editable_fields(_preview_data).has(field)
		spin.value = _preview_data.get(field) if spin.editable else 0
		spin.tooltip_text = "法术数值由各自效果定义，不使用这组基础属性。" if _preview_data != null and _preview_data.card_type == CardData.CardType.SPELL else ""
		spin.set_block_signals(false)
	save_button.disabled = _preview_data == null


func _on_offset_x_changed(value: float) -> void:
	preview_art_offset = Vector2i(int(value), preview_art_offset.y)


func _on_offset_y_changed(value: float) -> void:
	preview_art_offset = Vector2i(preview_art_offset.x, int(value))


func _nudge_preview(direction: Vector2i) -> void:
	preview_art_offset += direction


func _on_use_3d_toggled(enabled: bool) -> void:
	_preview_effect_material.set_shader_parameter("use_3d", enabled)


func _on_use_flash_toggled(enabled: bool) -> void:
	_preview_effect_material.set_shader_parameter("use_flash", enabled)


func _on_flash_type_selected(item_index: int) -> void:
	_preview_effect_material.set_shader_parameter(
		"flash_type",
		flash_type_selector.get_item_id(item_index)
	)


func _on_back_button_pressed() -> void:
	if Engine.is_editor_hint():
		_set_status("请运行场景后使用“返回主界面”。")
		return
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if (
		is_instance_valid(display_shell)
		and display_shell.is_ancestor_of(self)
		and display_shell.has_method("close_card_art_tuner")
	):
		display_shell.call("close_card_art_tuner")
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _queue_preview_refresh() -> void:
	# 同一帧多个属性变化只排队一次刷新，减少 @tool 模式重复重建卡面。
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
		status_label.text = "当前筛选没有卡牌。可更换卡包、种类或搜索条件。"
		return

	# 每张卡保留独立草稿，刷新只重画草稿，不改写真实资源。
	var preview_data := _preview_data
	preview_card.set_card_data(preview_data)
	preview_card.configure_drag_source(false)
	_refresh_effect_textures(preview_data)
	var normal_status := (
		"法线增强：已启用"
		if preview_data.art_normal_texture != null
		else "法线增强：未提供（不影响 3D / 扫光）"
	)
	status_label.text = "%s · %s · %s | 偏移 %s | %s" % [
		preview_data.display_name, CardPackRegistry.get_display_name(card_data.pack_id) if not card_data.pack_id.is_empty() else "未指定卡包",
		card_data.get_card_type_name(), preview_art_offset,
		"有未保存修改" if _has_unsaved_changes(card_data) else normal_status,
	]
	_update_current_list_label()


func _refresh_effect_textures(preview_data: CardData) -> void:
	var has_art := preview_data.art_texture != null
	if has_art:
		_preview_effect_material.set_shader_parameter(
			"mask_origin_px",
			preview_card.position
			+ preview_card.art_panel.position
			+ preview_card.art_texture.position
		)
		_preview_effect_material.set_shader_parameter(
			"mask_size_px",
			preview_card.art_texture.size
		)
	var has_normal := preview_data.art_normal_texture != null
	_preview_effect_material.set_shader_parameter(
		"use_normal_texture",
		has_normal
	)
	if has_normal:
		_preview_effect_material.set_shader_parameter(
			"normal_texture",
			preview_data.art_normal_texture
		)


func _update_current_list_label() -> void:
	if card_data == null: return
	for index: int in card_selector.item_count:
		if card_selector.get_item_metadata(index) == card_data.resource_path:
			var suffix := " · 衍生" if card_data.is_derived else (" · 停用" if not card_data.is_available else "")
			card_selector.set_item_text(index, _preview_data.display_name + (" *" if _has_unsaved_changes(card_data) else "") + suffix)
			return


func _save_card_to_resource() -> void:
	if card_data == null or card_data.resource_path.is_empty():
		_set_status("请选择有独立资源文件的卡牌。")
		return
	if _preview_data.display_name.strip_edges().is_empty():
		_set_status("卡牌名称不能为空；尚未保存。")
		return
	# 先读磁盘最新定义，仅叠加本次真正改动的字段，保留效果ID、关键词与其他资料。
	var saved := ResourceLoader.load(card_data.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	if saved == null:
		_set_status("无法读取卡牌资源，尚未保存。")
		return
	for field: StringName in _editable_fields(card_data):
		if _preview_data.get(field) != card_data.get(field): saved.set(field, _preview_data.get(field))
	var error := ResourceSaver.save(saved, card_data.resource_path)
	if error != OK:
		_set_status("保存失败（错误码%d）；预览草稿仍保留。" % error)
		return
	for property: Dictionary in saved.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: card_data.set(property.name, saved.get(property.name))
	card_data.emit_changed()
	_drafts.erase(_draft_key(card_data))
	card_data = _card_data
	card_resource_saved.emit(card_data)
	_refresh_preview()
	_set_status("已保存：%s（名称、适用属性及取景；ID保持不变）" % card_data.display_name)


func _reload_card_from_resource() -> void:
	if card_data == null: return
	var loaded := ResourceLoader.load(card_data.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData if not card_data.resource_path.is_empty() else card_data
	if loaded == null:
		_set_status("无法重新读取资源，草稿仍保留。")
		return
	for property: Dictionary in loaded.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: card_data.set(property.name, loaded.get(property.name))
	_drafts.erase(_draft_key(card_data))
	card_data = _card_data
	_refresh_preview()
	_set_status("已从资源重新载入，放弃当前卡牌未保存修改。")


func _reset_preview_offset() -> void:
	preview_art_offset = Vector2i.ZERO
	_set_status("预览偏移已归零；点击保存后才会写入资源。")


func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
