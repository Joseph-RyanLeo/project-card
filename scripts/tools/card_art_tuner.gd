@tool
class_name CardArtTuner
extends Control

## 卡面立绘取景的编辑器/运行时辅助工具。
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
const CARD_RESOURCE_PATHS := [
	"res://resources/cards/ember_squire.tres",
	"res://resources/cards/tide_archer.tres",
	"res://resources/cards/spark_mage.tres",
	"res://resources/cards/old_wolf_kaspar.tres",
	"res://resources/cards/anvil_margaret.tres",
	"res://resources/cards/town_priest.tres",
	"res://resources/cards/diplomat.tres",
	"res://resources/cards/recruiter.tres",
	"res://resources/cards/elegy_poet.tres",
	"res://resources/cards/war_drum_musician.tres",
	"res://resources/cards/javelin_skirmisher.tres",
	"res://resources/cards/militia.tres",
	"res://resources/cards/militia_commander.tres",
	"res://resources/cards/mudleg_brothers.tres",
	"res://resources/cards/fireman.tres",
	"res://resources/cards/musketeer.tres",
	"res://resources/cards/berserker_vanguard.tres",
	"res://resources/cards/shieldwall_private.tres",
	"res://resources/cards/rune_engraver.tres",
	"res://resources/cards/timid_infantry.tres",
	"res://resources/cards/baggage_muleteer.tres",
	"res://resources/cards/heavy_knight.tres",
	"res://resources/cards/armorsmith.tres",
	"res://resources/cards/field_medic.tres",
	"res://resources/cards/frostfang_blade.tres",
	"res://resources/cards/azure_hunt_bow.tres",
	"res://resources/cards/mana_tonic.tres",
	"res://resources/cards/glacial_crossbow.tres",
	"res://resources/cards/emberbrand_sword.tres",
	"res://resources/cards/sapphire_plate.tres",
	"res://resources/cards/seastone_ring.tres",
	"res://resources/cards/tidecaller_scepter.tres",
	"res://resources/cards/restoration_flask.tres",
	"res://resources/cards/stormstring_bow.tres",
	"res://resources/cards/inferno_edge.tres",
	"res://resources/cards/royal_aegis.tres",
	"res://resources/cards/starsea_ring.tres",
	"res://resources/cards/void_orb_scepter.tres",
	"res://resources/cards/bloodrage_elixir.tres",
	"res://resources/cards/blessing_sacred_shield.tres",
	"res://resources/cards/blessing_strength.tres",
	"res://resources/cards/blessing_vitality.tres",
	"res://resources/cards/summon_undead_army.tres",
	"res://resources/cards/summon_resurrection.tres",
	"res://resources/cards/summon_scarab_swarm.tres",
	"res://resources/cards/damage_fireball.tres",
	"res://resources/cards/damage_sandstorm.tres",
	"res://resources/cards/damage_ice_cone.tres",
	"res://resources/cards/support_healing_aura.tres",
	"res://resources/cards/support_repulsion_aura.tres",
	"res://resources/cards/disruption_counterspell.tres",
	"res://resources/cards/disruption_rust_blade.tres",
	"res://resources/cards/disruption_discordant_wave.tres",
]
const SELECTABLE_CARD_TYPES := [
	CardData.CardType.MINION,
	CardData.CardType.SPELL,
	CardData.CardType.EQUIPMENT,
] # 调整器按随从、法术、装备分组，避免 53 张卡挤进同一个超长菜单

# 资源列表是工具可选择的卡牌白名单，避免误写其他 Resource。

@export_group("Card Art Preview")
@export var card_data: CardData:
	# 检查器切换卡牌时，同时重置预览偏移并刷新运行时控件。
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
	# 临时预览值与 card_data.art_offset 分离，保存前不会修改真实资源。
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
var _preview_effect_material: ShaderMaterial
var _preview_pointer_force := Vector2.ZERO
var _active_selector_card_type: CardData.CardType = CardData.CardType.MINION

@onready var preview_card: CardView = %PreviewCard
@onready var preview_viewport: SubViewport = %PreviewViewport
@onready var preview_display: TextureRect = %PreviewDisplay
@onready var status_label: Label = %StatusLabel
@onready var card_type_selector: OptionButton = %CardTypeSelector
@onready var card_selector: ItemList = %CardSelector
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
	_active_selector_card_type = (
		card_data.card_type
		if card_data != null
		else CardData.CardType.MINION
	)
	_populate_card_type_selector()
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


func _populate_card_type_selector() -> void:
	card_type_selector.clear()
	for selectable_type: CardData.CardType in SELECTABLE_CARD_TYPES:
		card_type_selector.add_item(
			["随从", "装备", "法术", "资源"][selectable_type],
			selectable_type
		)
	_sync_card_type_selector()


func _populate_card_selector() -> void:
	# 固定高度 ItemList 自带滚动条；metadata 继续保存真实资源路径。
	card_selector.clear()
	for resource_path: String in CARD_RESOURCE_PATHS:
		var available_card := load(resource_path) as CardData
		if (
			available_card == null
			or available_card.card_type != _active_selector_card_type
		):
			continue
		card_selector.add_item(available_card.display_name)
		var item_index := card_selector.item_count - 1
		card_selector.set_item_metadata(item_index, resource_path)


func _connect_runtime_controls() -> void:
	# bind() 把方向参数预先绑定到四个按钮，共用一个微调函数。
	card_type_selector.item_selected.connect(_on_card_type_selected)
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
	use_3d_check.toggled.connect(_on_use_3d_toggled)
	use_flash_check.toggled.connect(_on_use_flash_toggled)
	flash_type_selector.item_selected.connect(_on_flash_type_selected)


func _sync_runtime_controls() -> void:
	if not is_node_ready():
		return
	_sync_card_selector()
	_sync_offset_controls()


func _sync_card_selector() -> void:
	if not is_instance_valid(card_selector) or card_data == null:
		return
	if card_data.card_type != _active_selector_card_type:
		_active_selector_card_type = card_data.card_type
		_sync_card_type_selector()
		_populate_card_selector()
	for item_index: int in card_selector.item_count:
		if card_selector.get_item_metadata(item_index) == card_data.resource_path:
			card_selector.select(item_index)
			card_selector.ensure_current_is_visible()
			return


func _sync_card_type_selector() -> void:
	if not is_instance_valid(card_type_selector):
		return
	for item_index: int in card_type_selector.item_count:
		if card_type_selector.get_item_id(item_index) == _active_selector_card_type:
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
	_populate_card_selector()
	if card_selector.item_count > 0:
		_on_card_selected(0)


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
		status_label.text = "请在检查器中选择一张 CardData 资源。"
		return

	# 预览只操作副本。拖动数值时不会提前修改真正的 .tres 文件。
	var preview_data := card_data.duplicate(true) as CardData
	preview_data.art_offset = preview_art_offset
	preview_card.set_card_data(preview_data)
	preview_card.configure_drag_source(false)
	_refresh_effect_textures(preview_data)
	var normal_status := (
		"法线增强：已启用"
		if preview_data.art_normal_texture != null
		else "法线增强：未提供（不影响 3D / 扫光）"
	)
	status_label.text = "%s  |  当前预览偏移：%s  |  %s" % [
		card_data.display_name,
		preview_art_offset,
		normal_status,
	]


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


func _save_offset_to_resource() -> void:
	# 这是本工具唯一允许写入真实卡牌资源的入口。
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
