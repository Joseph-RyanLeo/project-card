@tool
class_name CardView
extends Panel

## 单张卡牌的像素级显示与输入组件。
##
## CardData 是内容来源；本脚本负责把它渲染为固定 99×136 卡面，并生成统一拖拽数据。
## 小队内的水平位置、层级和牌型不在这里判断，而由 SquadView / SquadData 决定。
## `@tool` 让美术调节场景在编辑器中也能实时看到导出参数的效果。

signal card_clicked(card_data: CardData)
signal click_carry_requested(data: Dictionary, pointer_global_position: Vector2)
signal effect_display_changed(card_data: CardData, is_showing_effect: bool)
signal collection_return_requested(
	card_view: CardView,
	return_global_position: Vector2
)

const RUNE_FIRE_TEXTURE: Texture2D = preload("res://assets/runes/rune_fire.png")
const RUNE_WATER_TEXTURE: Texture2D = preload("res://assets/runes/rune_water.png")
const RUNE_WOOD_TEXTURE: Texture2D = preload("res://assets/runes/rune_wood.png")
const RUNE_LIGHT_TEXTURE: Texture2D = preload("res://assets/runes/rune_light.png")
const RUNE_DARK_TEXTURE: Texture2D = preload("res://assets/runes/rune_dark.png")
const RUNE_ACTIVE_FLOW_SHEET: Texture2D = preload(
	"res://assets/runes/rune_active_flow_sheet.png"
)
const ACTION_MELEE_TEXTURE: Texture2D = preload("res://assets/actions/action_melee.png")
const ACTION_RANGED_TEXTURE: Texture2D = preload("res://assets/actions/action_ranged.png")
const ACTION_MAGIC_TEXTURE: Texture2D = preload("res://assets/actions/action_magic.png")
const ACTION_HEAL_TEXTURE: Texture2D = preload("res://assets/actions/action_heal.png")
const ACTION_DEFENSE_TEXTURE: Texture2D = preload("res://assets/actions/action_defense.png")
const HEALTH_TEXTURE: Texture2D = preload("res://assets/stats/health.png")
const ARMOR_TEXTURE: Texture2D = preload("res://assets/stats/armor.png")
const COOLDOWN_HOURGLASS_TEXTURE: Texture2D = preload(
	"res://assets/stats/cooldown_hourglass.png"
)
const SPELL_RARITY_BADGE_TEXTURE: Texture2D = preload(
	"res://assets/card_ui/placeholders/spell_rarity_badges.png"
)
const SPELL_TYPE_ATLAS: Texture2D = preload(
	"res://assets/card_ui/placeholders/spell_type_atlas.png"
)
const EQUIPMENT_TYPE_ATLAS: Texture2D = preload(
	"res://assets/card_ui/placeholders/equipment_type_atlas.png"
)
const EQUIPMENT_ACTION_INCREASE_TEXTURE: Texture2D = preload(
	"res://assets/card_ui/placeholders/equipment_action_increase.png"
)
const EQUIPMENT_ACTION_DECREASE_TEXTURE: Texture2D = preload(
	"res://assets/card_ui/placeholders/equipment_action_decrease.png"
)
const SPELL_RARITY_BADGE_REGIONS := [
	Rect2(0, 0, 22, 22),
	Rect2(0, 106, 22, 22),
	Rect2(0, 80, 22, 22),
	Rect2(0, 52, 22, 22),
	Rect2(0, 26, 22, 22),
] # 法术稀有度图集视觉顺序为 I、V、IV、III、II，显式映射到 I～V
const SPELL_RARITY_BADGE_POSITION := Vector2(-6, -2) # 按法术参考图相对 99×136 卡框原点对齐
const SPELL_RARITY_BADGE_SIZE := Vector2(22, 22) # 法术稀有度角标保持原生 22×22px
const EQUIPMENT_ACTION_POSITION := Vector2(-9, -9) # 装备参考合图相对卡框原点的位置；完整箭头位于合图顶部
const EQUIPMENT_ACTION_SIZE := Vector2(28, 28) # 装备增减箭头保持原生 28×28px 画布
const SPELL_TYPE_ATLAS_X := [5, 26, 46, 67, 86] # 法术类型图集视觉列为 V、IV、III、II、I
const SPELL_TYPE_ATLAS_Y := [6, 23, 37, 52, 66] # 法术类型图集行依次为强化、召唤、伤害、支援、干扰
const SPELL_TYPE_ATLAS_W := [13, 13, 13, 13, 13] # 法术类型图标的原始裁切宽度
const SPELL_TYPE_ATLAS_H := [13, 12, 11, 10, 9] # 法术类型图标的原始裁切高度
const EQUIPMENT_TYPE_ATLAS_X := [2, 22, 40, 58, 76] # 装备类型图集视觉列为 II、III、IV、V、I
const EQUIPMENT_TYPE_ATLAS_Y := [4, 20, 36, 51, 66, 81] # 装备类型图集行依次为六种装备类型
const EQUIPMENT_TYPE_ATLAS_W := [13, 13, 13, 13, 13] # 装备类型图标的原始裁切宽度
const EQUIPMENT_TYPE_ATLAS_H := [13, 13, 10, 10, 12, 10] # 装备类型图标的原始裁切高度
const DEFAULT_ART_BACKGROUND_TEXTURE: Texture2D = preload(
	"res://assets/card_backgrounds/card_background_placeholder.png"
)
const CARD_NAME_FRAME_TEXTURE: Texture2D = preload(
	"res://assets/card_ui/card_name_frame.png"
)
const CARD_TEXT_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
const LAYOUT_TWEEN_DURATION: float = 0.15 # 卡牌让位、归位和飞入目标位置的动画时长（秒）
const INTERACTION_TWEEN_DURATION: float = 0.10 # 悬停、按压时阴影移动的动画时长（秒）
const HOVER_PUNCH_ANGLE: float = 5.0 # 鼠标进入实体卡左/右半边时，同方向轻晃的最大角度
const HOVER_PUNCH_DURATION: float = 0.16 # 悬停单方向轻晃并复位的总时长（秒）
const COLLECTION_HOVER_LIFT_OFFSET: float = 7.0 # 收藏悬停时向上抽出的像素距离
const HOVER_Z_OFFSET: int = 20 # 战场卡悬停时相对所在小队层级的提升量
const COLLECTION_DRAG_GHOST_ALPHA: float = 0.32 # 收藏卡拖起后原槽虚影的透明度
const RESTING_SHADOW_OFFSET := Vector2(6.0, 7.0) # 悬停状态下阴影相对卡牌的偏移
const PRESSED_SHADOW_OFFSET := Vector2(6.0, 8.0) # 按住状态下阴影相对卡牌的偏移
const INTERACTION_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.28) # 悬停和按压阴影的颜色及透明度
const CARD_LAYER_Z_STEP: int = 100 # 小队相邻整卡之间的层级间隔，必须大于卡牌内部所有子图层与悬停增量
const VISUAL_CAPTURE_LEFT_SAFETY: float = 1.0 # 快照在行动数字最左像素外额外保留的安全边
const ACTIVE_RUNE_FRAME_COUNT: int = 14 # 流光符文精灵表包含的动画帧数
const ACTIVE_RUNE_SHEET_COLUMN_STEP: int = 30 # 精灵表相邻元素符文起点的水平距离
const ACTIVE_RUNE_FRAME_SECONDS: Array[float] = [
	0.10, 0.08, 0.10, 0.10, 0.10, 0.10, 0.10,
	0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10,
] # 流光 GIF 原始 14 帧的逐帧停留时长（秒）
const PREVIEW_ACTIVE_RUNE_ALPHA: float = 0.62 # 假设牌型中流光符文相对真实结果的透明度
const ACTIVE_RUNE_CYCLE_SECONDS: float = 2.0 # 一轮完整流光动画的总时长（秒）
const ACTIVE_RUNE_START_PHASE_SECONDS: float = 1.4 # 新一轮真实流光首次出现时使用的精灵表时间相位（秒）
const ACTION_VALUE_POSITIONS := {
	&"single_other": Vector2(0, 7),
	&"single_one": Vector2(1, 7),
	&"double": Vector2(-5, 7),
} # 行动数值按位数和数字1使用的绝对卡面坐标
const HEALTH_VALUE_POSITIONS := {
	1: [Vector2(89, 88), Vector2(90, 88)],
	2: [Vector2(84, 88), Vector2(85, 88), Vector2(86, 88)],
	3: [Vector2(79, 88), Vector2(80, 88), Vector2(81, 88), Vector2(83, 88)],
} # 生命数值按“位数 -> 数字1数量”使用的绝对卡面坐标
const ARMOR_VALUE_POSITIONS := {
	1: [Vector2(90, 74), Vector2(90, 74)],
	2: [Vector2(86, 74), Vector2(87, 74), Vector2(88, 74)],
	3: [Vector2(82, 74), Vector2(82, 74), Vector2(84, 74), Vector2(84, 74)],
} # 护甲数值按“位数 -> 数字1数量”使用的绝对卡面坐标
const COOLDOWN_VALUE_POSITION := Vector2(-3, 24) # 冷却整数、小数点和小数位组合节点的绝对卡面坐标
const MAX_STATS_RIGHT_EDGE: float = 109.0 # 999生命在当前绝对坐标下到达的最右边界
@export_group("Card Pixel Layout")
@export var card_size: Vector2 = Vector2(99, 136) # 裸卡的基准像素尺寸
@export var title_area_position: Vector2 = Vector2(21, 5) # 卡牌名字文字区域整体下移 1px 后的左上角坐标
@export var title_area_size: Vector2 = Vector2(61, 10) # 卡牌名字文字可使用的最大区域
@export var name_frame_position: Vector2 = Vector2(0, 4) # 卡牌名字框的左上角坐标
@export var art_area_position: Vector2 = Vector2(10, 5) # 卡框内部立绘裁切窗口的左上角坐标
@export var art_area_size: Vector2 = Vector2(79, 95) # 背景和人物只允许显示在卡框内部的区域
@export var bottom_area_position: Vector2 = Vector2(1, 106) # 底部描述叠放层左上角；贴近卡框内沿并为描边保留空间
@export var bottom_area_size: Vector2 = Vector2(97, 28) # 底部描述叠放层尺寸；覆盖卡框底栏但不压住最外框
@export var rune_area_position: Vector2 = Vector2(8, 108) # 符文行继续使用原来的卡面绝对坐标，不随文字框扩宽而移动
@export var rune_area_size: Vector2 = Vector2(83, 23) # 三枚符文继续使用原来的布局尺寸
@export var effect_text_inset: Vector2 = Vector2(3, 2) # 效果文字相对描述叠放层四周预留的内边距
@export var health_icon_position: Vector2 = Vector2(84, 88) # 20×17生命图标在卡面上的绝对左上角坐标
@export var health_badge_size: Vector2 = Vector2(20, 17) # 新版生命图标的原生逻辑尺寸
@export var armor_icon_position: Vector2 = Vector2(87, 71) # 14×16护甲图标在卡面上的绝对左上角坐标
@export var armor_badge_size: Vector2 = Vector2(14, 16) # 新版护甲图标的原生逻辑尺寸
@export var cooldown_icon_position: Vector2 = Vector2(-1, 22) # 沙漏图标在卡面左上区域的绝对左上角坐标
@export var cooldown_icon_size: Vector2 = Vector2(12, 16) # 沙漏保持用户素材的 12×16px 原生尺寸
@export var action_top_overhang: float = 4.0 # 行动图标超出裸卡顶边缘的像素数
@export var race_center_pixel: Vector2i = Vector2i(49, 100) # 不同尺寸种族图标共用的中心像素坐标
@export var rune_slot_size: Vector2 = Vector2(23, 23) # 每个元素符文空腔的布局尺寸
@export var rune_icon_size: Vector2 = Vector2(23, 23) # 元素符文纹理的显示尺寸
@export var rune_spacing: int = 7 # 三个元素符文布局槽之间的水平间距

@export_group("Card Font Sizes")
@export var title_font_size: int = 8 # 寒蝉点阵 7px 在卡牌名字上使用的固定字号
@export var title_font_min_size: int = 5 # 名字过长时允许缩小到的最小字号
@export var stats_font_size: int = 8 # 受击权重等尚未替换为图片数字的辅助字号
@export var effect_font_size: int = 8 # 寒蝉点阵 7px 在卡牌效果文字上使用的固定字号
@export var effect_line_spacing: int = 0 # 卡牌效果文字多行之间增加或减少的像素间距
@export var effect_text_color: Color = Color.WHITE # 卡牌效果文字的默认颜色
@export var effect_text_outline_size: int = 2 # 效果文字外扩的像素描边宽度；2px保证复杂插画上仍清晰可读
@export var effect_text_outline_color: Color = Color(0.03, 0.025, 0.02, 0.95) # 效果文字描边颜色；近黑但保留少量底色融合

@export_group("Card Effect Transition")
@export_range(0.0, 1.0, 0.05) var effect_rune_dim_alpha: float = 0.2 # 右键显示效果文字时符文保留的透明度
@export_range(0.01, 1.0, 0.01) var effect_transition_duration: float = 0.2 # 符文与效果文字交叉淡化的动画时长（秒）

@export var card_data: CardData:
	set(value):
		set_card_data(value)
	get:
		return _card_data

var _card_data: CardData
var showing_effect: bool = false
# 拖拽来源信息由收藏或 SquadView 注入，CardView 不直接修改来源容器。
var _drag_enabled: bool = false
var _drag_source_type: StringName
var _drag_source_row: Node
var _drag_source_slot: Control
var _collection_source_ghosted: bool = false
var _left_button_pressed: bool = false
var _active_drag_preview_offset: Vector2 = Vector2.ZERO
var _active_drag_visual: CardDragPreview
var _layout_tween: Tween
var _hover_punch_tween: Tween
var _shadow_tween: Tween
var _effect_transition_tween: Tween
var _layout_resting_position: Vector2 = Vector2.ZERO
var _mouse_hovered: bool = false
var _snapshot_mode: bool = false
var _interaction_shadow: Panel
var _external_lift: float = 0.0
var _resting_z_index: int = 0
# 高亮索引描述当前牌型参与的三个槽位；流光节点本身按需创建并等待全局周期。
var _highlighted_rune_indices: Array[int] = []
var _rune_highlight_is_preview: bool = false
var _dim_preview_active_runes: bool = true
var _active_rune_icons: Dictionary = {}
var _active_rune_join_cycles: Dictionary = {}
var _active_rune_frame: int = -1
var _battle_vitals_active: bool = false
var _battle_current_health: int = 0
var _battle_current_armor: int = 0
var _battle_cooldown_active: bool = false
var _battle_remaining_cooldown: float = 0.0

# 所有真实卡共享一条静态时间轴；新加入的符文等到下一轮再同步开始。
static var _active_rune_flow_epoch_msec: int = -1
static var _active_rune_flow_cached_process_frame: int = -1
static var _active_rune_flow_cached_elapsed_seconds: float = 0.0
static var _active_rune_flow_initial_process_frame: int = -1

@onready var name_clip: Control = %NameClip
@onready var name_label: Label = %NameLabel
@onready var action_icon: TextureRect = %ActionIcon
@onready var value_label: RuneNumberDisplay = %ValueLabel
@onready var top_row: Control = %TopRow
@onready var art_panel: Panel = %ArtPanel
@onready var art_content: Control = %ArtContent
@onready var art_background: TextureRect = %ArtBackground
@onready var art_texture: TextureRect = %ArtTexture
@onready var art_label: Label = %ArtLabel
@onready var card_frame: TextureRect = %CardFrame
@onready var card_name_frame: TextureRect = %CardNameFrame
@onready var race_icon: TextureRect = %RaceIcon
@onready var stats_row: Control = %StatsRow
@onready var health_icon: TextureRect = %HealthIcon
@onready var health_label: RuneNumberDisplay = %HealthLabel
@onready var armor_icon: TextureRect = %ArmorIcon
@onready var armor_label: RuneNumberDisplay = %ArmorLabel
@onready var cooldown_icon: TextureRect = %CooldownIcon
@onready var cooldown_label: RuneNumberDisplay = %CooldownLabel
@onready var priority_label: Label = %PriorityLabel
@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var rune_row: HBoxContainer = %RuneRow
@onready var effect_text_label: Label = %EffectTextLabel


# --- 生命周期、鼠标输入与拖拽数据 ---
func _ready() -> void:
	add_to_group("card_views")
	_layout_resting_position = position
	# 普通实体卡围绕中心轻晃；尚未入树就被配置成快照的卡必须保持
	# 左上角支点，避免稍后进入 SceneTree 时重新覆盖快照捕获变换。
	pivot_offset = Vector2.ZERO if _snapshot_mode else card_size * 0.5
	_create_interaction_shadow()
	_apply_pixel_layout()
	_ignore_mouse_on_children(self)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	set_process(false)
	_refresh()


func _process(_delta: float) -> void:
	if _active_rune_icons.is_empty():
		set_process(false)
		return
	_update_active_rune_frames()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_left_button_pressed = true
				if (
					_drag_enabled
					and is_instance_valid(_drag_source_slot)
					and _drag_source_slot.has_method("lock_drag_subject")
				):
					_drag_source_slot.lock_drag_subject(card_data)
					if _drag_enabled:
						_set_interaction_shadow_visible(true)
						_animate_shadow_offset(PRESSED_SHADOW_OFFSET)
				card_clicked.emit(card_data)
			elif _left_button_pressed:
				_left_button_pressed = false
				if _drag_enabled and card_data != null:
					var pointer_global_position := (
						get_global_transform_with_canvas()
						* mouse_event.position
					)
					var drag_data := _build_drag_data(
						mouse_event.position
					)
					_reset_interaction_visual()
					_mouse_hovered = false
					click_carry_requested.emit(
						drag_data,
						pointer_global_position
					)
			accept_event()
		elif (
			mouse_event.button_index == MOUSE_BUTTON_RIGHT
			and mouse_event.pressed
		):
			toggle_effect_display()
			accept_event()


func _has_point(point: Vector2) -> bool:
	# 卡牌向上抽出后，命中区域仍覆盖抽出前的完整卡面；否则鼠标从
	# 下边缘进入时，卡牌上移会把鼠标瞬间甩出自身并打断 mouse_entered。
	return Rect2(
		Vector2.ZERO,
		Vector2(size.x, size.y + _external_lift)
	).has_point(point)


func _get_drag_data(at_position: Vector2) -> Variant:
	if not _drag_enabled or card_data == null:
		return null

	var drag_data := _build_drag_data(at_position)
	# Godot 把原生拖拽预览挂在当前 SubViewport 的拖拽层，而不是
	# DesignCanvas 下。预览需要继承显示链路的实际视觉缩放；
	# 玩法判定仍继续使用逻辑 preview_scale。
	_apply_native_drag_visual_metrics(drag_data)
	_active_drag_preview_offset = (
		drag_data.get("drag_visual_offset", drag_data["preview_offset"])
		as Vector2
	)
	var preview_root := create_drag_visual(drag_data)
	drag_data["drag_visual"] = preview_root
	_active_drag_visual = preview_root
	set_drag_preview(preview_root)
	return drag_data


func _apply_native_drag_visual_metrics(drag_data: Dictionary) -> void:
	var visual_scale := get_global_transform_with_canvas().get_scale()
	drag_data["drag_visual_scale"] = visual_scale
	drag_data["drag_visual_offset"] = (
		(drag_data.get("grab_local_position", Vector2.ZERO) as Vector2)
		* visual_scale
	)


func _build_drag_data(at_position: Vector2) -> Dictionary:
	var drag_source_scale := scale
	var drag_data := {
		"kind": &"card",
		"card_data": card_data,
		"source_type": _drag_source_type,
		"source_row": _drag_source_row,
		"source_slot": _drag_source_slot,
		"grab_local_position": at_position,
		"preview_offset": at_position * drag_source_scale,
		"preview_scale": drag_source_scale,
		"showing_effect": showing_effect,
	}
	if (
		is_instance_valid(_drag_source_slot)
		and _drag_source_slot.has_method("enrich_drag_data")
	):
		return _drag_source_slot.enrich_drag_data(drag_data, card_data)
	return drag_data


static func create_drag_visual(drag_data: Dictionary) -> CardDragPreview:
	var preview_root := CardDragPreview.new()
	var card_view_scene := load("res://scenes/ui/CardView.tscn") as PackedScene
	var visual_scale: Vector2 = drag_data.get(
		"drag_visual_scale",
		drag_data.get("preview_scale", Vector2.ONE)
	)
	if drag_data.get("kind") == &"squad":
		var squad_visual := Control.new()
		var squad_size: Vector2 = drag_data.get("squad_size", Vector2(99, 136))
		squad_visual.size = squad_size
		squad_visual.custom_minimum_size = squad_size
		var cards: Array = drag_data.get("squad_cards", [])
		var x_positions: Array = drag_data.get("squad_x_positions", [])
		var layers: Array = drag_data.get("squad_layer_cards", [])
		for index: int in cards.size():
			var squad_card := card_view_scene.instantiate() as CardView
			squad_card.position = Vector2(float(x_positions[index]), 0.0)
			# CardView 会在 _ready() 记录静止位置，因此整队快照也要先放好 X 再入树。
			squad_visual.add_child(squad_card)
			squad_card.set_card_data(cards[index] as CardData)
			squad_card.configure_drag_source(false)
			squad_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			squad_card.set_resting_z_index(
				(cards.size() - layers.find(cards[index]))
				* CARD_LAYER_Z_STEP
			)
		preview_root.configure(
			squad_visual,
			drag_data.get("grab_local_position", Vector2.ZERO),
			visual_scale,
			squad_size
		)
		return preview_root
	var preview_card := card_view_scene.instantiate() as CardView
	preview_card.modulate.a = 0.9
	preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_card.showing_effect = bool(drag_data.get("showing_effect", false))
	preview_card.set_card_data(drag_data["card_data"] as CardData)
	preview_card.configure_drag_source(false)
	var grab_local_position: Vector2 = drag_data.get(
		"grab_local_position",
		Vector2.ZERO
	)
	preview_root.configure(
		preview_card,
		grab_local_position,
		visual_scale,
		preview_card.card_size
	)
	return preview_root


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		if (
			_drag_enabled
			and drag_data is Dictionary
			and (drag_data as Dictionary).get("source_slot") == _drag_source_slot
		):
			_left_button_pressed = false
			_mouse_hovered = false
			_reset_interaction_visual()
		if (
			_drag_enabled
			and _drag_source_type == &"collection"
			and is_instance_valid(_drag_source_slot)
			and drag_data is Dictionary
			and (drag_data as Dictionary).get("source_slot") == _drag_source_slot
		):
			_drag_source_slot.modulate.a = COLLECTION_DRAG_GHOST_ALPHA
			_collection_source_ghosted = true
	elif what == NOTIFICATION_DRAG_END and _collection_source_ghosted:
		var should_animate_back := (
			not get_viewport().gui_is_drag_successful()
		)
		var return_global_position := (
			_active_drag_visual.get_card_global_position()
			if is_instance_valid(_active_drag_visual)
			else (
				get_viewport().get_mouse_position()
				- _active_drag_preview_offset
			)
		)
		if is_instance_valid(_drag_source_slot):
			_drag_source_slot.modulate.a = 1.0
		_collection_source_ghosted = false
		if should_animate_back:
			collection_return_requested.emit(
				self,
				return_global_position
			)
		_active_drag_preview_offset = Vector2.ZERO
		_active_drag_visual = null


# --- 拖拽来源配置、悬停反馈与卡牌布局动画 ---
func configure_drag_source(
	enabled: bool,
	source_type: StringName = &"",
	source_row: Node = null,
	source_slot: Control = null
) -> void:
	_drag_enabled = enabled
	_drag_source_type = source_type
	_drag_source_row = source_row
	_drag_source_slot = source_slot
	if not _drag_enabled:
		_reset_interaction_visual()
	mouse_default_cursor_shape = (
		Control.CURSOR_DRAG if _drag_enabled else Control.CURSOR_ARROW
	)


func set_snapshot_mode(value: bool) -> void:
	_snapshot_mode = value
	pivot_offset = Vector2.ZERO if _snapshot_mode else card_size * 0.5
	if _snapshot_mode:
		_reset_interaction_visual()
		mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_mouse_entered() -> void:
	show_pointer_hover_feedback(true)


func show_pointer_hover_feedback(play_rotation_punch: bool = false) -> void:
	_mouse_hovered = true
	if _drag_enabled and not _left_button_pressed and not _snapshot_mode:
		# 收藏中的卡牌必须作为一个整体高于相邻卡牌的全部子图层；
		# 战场小队已经用 100 为整卡分层，只需要原有的小幅提升。
		var hover_z_offset := (
			CARD_LAYER_Z_STEP
			if _drag_source_type == &"collection"
			else HOVER_Z_OFFSET
		)
		z_index = _resting_z_index + hover_z_offset
		_set_interaction_shadow_visible(true)
		_animate_shadow_offset(RESTING_SHADOW_OFFSET)
		_set_collection_hover_lift(true)
		if play_rotation_punch:
			_play_hover_rotation_punch()


func _on_mouse_exited() -> void:
	_mouse_hovered = false
	if _drag_enabled and not _left_button_pressed:
		z_index = _resting_z_index
		_set_interaction_shadow_visible(false)
		_set_collection_hover_lift(false)


func clear_pointer_hover_feedback() -> void:
	# Godot 开始另一次拖拽或点击携带时不一定会补发旧卡的 mouse_exited。
	# 这里只清理持续反馈；已经开始的单次轻晃会自然回正，避免小队模式
	# 在同一帧切换反馈对象时把战场卡的入场轻晃截断。
	_mouse_hovered = false
	if not _left_button_pressed:
		z_index = _resting_z_index
		_set_interaction_shadow_visible(false)
		_set_collection_hover_lift(false)


func _reset_interaction_visual() -> void:
	z_index = _resting_z_index
	if _hover_punch_tween != null and _hover_punch_tween.is_valid():
		_hover_punch_tween.kill()
	rotation_degrees = 0.0
	_set_interaction_shadow_visible(false)
	set_external_lift(0.0)


func _set_collection_hover_lift(value: bool) -> void:
	# 战场卡的抽出距离由 SquadView 决定；CardView 只直接控制收藏。
	if _drag_source_type == &"collection":
		set_external_lift(COLLECTION_HOVER_LIFT_OFFSET if value else 0.0)


func _create_interaction_shadow() -> void:
	_interaction_shadow = Panel.new()
	_interaction_shadow.name = "InteractionShadow"
	_interaction_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_shadow.z_index = -10
	_interaction_shadow.show_behind_parent = true
	_interaction_shadow.position = RESTING_SHADOW_OFFSET
	_interaction_shadow.size = card_size
	_interaction_shadow.custom_minimum_size = card_size
	_interaction_shadow.visible = false
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = INTERACTION_SHADOW_COLOR
	shadow_style.corner_radius_top_left = 3
	shadow_style.corner_radius_top_right = 3
	shadow_style.corner_radius_bottom_left = 3
	shadow_style.corner_radius_bottom_right = 3
	_interaction_shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(_interaction_shadow)
	move_child(_interaction_shadow, 0)


func _set_interaction_shadow_visible(value: bool) -> void:
	if not is_instance_valid(_interaction_shadow):
		return
	_interaction_shadow.visible = value and not _snapshot_mode


func _animate_shadow_offset(target_offset: Vector2) -> void:
	if not is_instance_valid(_interaction_shadow):
		return
	if _shadow_tween != null and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = create_tween()
	_shadow_tween.set_trans(Tween.TRANS_QUAD)
	_shadow_tween.set_ease(Tween.EASE_OUT)
	_shadow_tween.tween_property(
		_interaction_shadow,
		"position",
		target_offset,
		INTERACTION_TWEEN_DURATION
	)


func _play_hover_rotation_punch() -> void:
	if _snapshot_mode:
		return
	if _hover_punch_tween != null and _hover_punch_tween.is_valid():
		_hover_punch_tween.kill()
	rotation_degrees = 0.0
	var punch_direction := _get_hover_punch_direction(
		get_local_mouse_position().x
	)
	_hover_punch_tween = create_tween()
	_hover_punch_tween.set_trans(Tween.TRANS_SINE)
	_hover_punch_tween.set_ease(Tween.EASE_OUT)
	_hover_punch_tween.tween_property(
		self,
		"rotation_degrees",
		HOVER_PUNCH_ANGLE * punch_direction,
		HOVER_PUNCH_DURATION * 0.45
	)
	_hover_punch_tween.tween_property(
		self,
		"rotation_degrees",
		0.0,
		HOVER_PUNCH_DURATION * 0.55
	)


func _get_hover_punch_direction(pointer_local_x: float) -> float:
	return -1.0 if pointer_local_x < card_size.x * 0.5 else 1.0


func animate_from_global_position(previous_global_position: Vector2) -> void:
	if not visible:
		return

	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()

	# 新动画可能在旧动画尚未完成时开始。必须先回到固定静止坐标，
	# 不能把 Tween 中途的临时 position 当成下一轮目标，否则偏移会累加。
	position = _layout_resting_position
	var visual_parent := get_parent() as CanvasItem
	if visual_parent == null:
		return
	# 拖拽起点是画布坐标，position 是父节点本地坐标；显式反变换后，
	# 720p、1080p、2K 和全屏都得到同一逻辑位移。
	position = (
		visual_parent
		.get_global_transform_with_canvas()
		.affine_inverse()
		* previous_global_position
	)
	_layout_tween = create_tween()
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	_layout_tween.set_ease(Tween.EASE_OUT)
	_layout_tween.tween_property(
		self,
		"position",
		_layout_resting_position + Vector2(0.0, -_external_lift),
		LAYOUT_TWEEN_DURATION
	)


func set_external_lift(pixels: float) -> void:
	_external_lift = maxf(pixels, 0.0)
	# 入树前尚未记录真实静止坐标，此时只保存状态；否则 configure_drag_source(false)
	# 会把收藏虚影预先设置好的安全边距位置误写成 (0, 0)。
	if not is_node_ready():
		return
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	position = _layout_resting_position + Vector2(0.0, -_external_lift)


func set_layout_position(value: Vector2) -> void:
	# 小队水平顺序变化时只更新长期存在的 CardView 静止坐标，
	# 不销毁节点；这样原生 mouse_entered / mouse_exited 状态不会中断。
	_layout_resting_position = value
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	position = _layout_resting_position + Vector2(0.0, -_external_lift)


func set_resting_z_index(value: int) -> void:
	_resting_z_index = value
	z_index = _resting_z_index


func set_attribute_source_state(
	action_active: bool,
	vitals_active: bool,
	effect_active: bool,
	inactive_alpha: float
) -> void:
	var action_alpha := 1.0 if action_active else inactive_alpha
	var vitals_alpha := 1.0 if vitals_active else inactive_alpha
	action_icon.modulate.a = action_alpha
	value_label.modulate.a = action_alpha
	cooldown_icon.modulate.a = action_alpha
	cooldown_label.modulate.a = action_alpha
	health_icon.modulate.a = vitals_alpha
	health_label.modulate.a = vitals_alpha
	armor_icon.modulate.a = vitals_alpha
	armor_label.modulate.a = vitals_alpha
	effect_text_label.modulate.a = 1.0 if effect_active else inactive_alpha


func toggle_effect_display() -> bool:
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		return false
	showing_effect = not showing_effect
	_animate_effect_transition()
	effect_display_changed.emit(card_data, showing_effect)
	return true


func is_effect_transition_animating() -> bool:
	return (
		_effect_transition_tween != null
		and _effect_transition_tween.is_valid()
		and _effect_transition_tween.is_running()
	)


func is_layout_animating() -> bool:
	return (
		_layout_tween != null
		and _layout_tween.is_valid()
		and _layout_tween.is_running()
	)


# --- 卡牌数据与牌型流光公开接口 ---
func set_card_data(value: CardData) -> void:
	_card_data = value

	if is_node_ready():
		_refresh()


func set_battle_vitals(current_health: int, current_armor: int) -> void:
	_battle_vitals_active = true
	_battle_current_health = clampi(current_health, 0, CardData.MAXIMUM_HEALTH)
	_battle_current_armor = clampi(current_armor, 0, CardData.MAXIMUM_ARMOR)
	if is_node_ready():
		_refresh_vitals_text()


func clear_battle_vitals() -> void:
	_battle_vitals_active = false
	if is_node_ready():
		_refresh_vitals_text()


func has_battle_vitals() -> bool:
	return _battle_vitals_active


func set_battle_remaining_cooldown(remaining_cooldown: float) -> void:
	_battle_cooldown_active = true
	_battle_remaining_cooldown = clampf(
		remaining_cooldown,
		0.0,
		CardData.MAXIMUM_COOLDOWN_SECONDS
	)
	if is_node_ready():
		_refresh_cooldown_text()


func clear_battle_remaining_cooldown() -> void:
	_battle_cooldown_active = false
	if is_node_ready():
		_refresh_cooldown_text()


func has_battle_remaining_cooldown() -> bool:
	return _battle_cooldown_active


func set_rune_pattern_highlights(
	rune_indices: Array[int],
	is_preview_highlight: bool = false,
	dim_preview_active_runes: bool = true
) -> void:
	if not is_preview_highlight and not rune_indices.is_empty():
		_start_active_rune_flow_if_needed()
	if (
		_highlighted_rune_indices == rune_indices
		and _rune_highlight_is_preview == is_preview_highlight
		and _dim_preview_active_runes == dim_preview_active_runes
	):
		return
	_highlighted_rune_indices.assign(rune_indices)
	_rune_highlight_is_preview = is_preview_highlight
	_dim_preview_active_runes = dim_preview_active_runes
	if is_node_ready():
		_refresh_runes()


func get_highlighted_rune_indices() -> Array[int]:
	return _highlighted_rune_indices.duplicate()


func is_rune_highlight_preview() -> bool:
	return _rune_highlight_is_preview


func get_active_rune_animation_count() -> int:
	return _active_rune_icons.size()


func get_active_rune_animation_frame() -> int:
	return _active_rune_frame


static func has_active_rune_flow_started() -> bool:
	return _active_rune_flow_epoch_msec >= 0


static func reset_active_rune_flow() -> void:
	_active_rune_flow_epoch_msec = -1
	_active_rune_flow_cached_process_frame = -1
	_active_rune_flow_cached_elapsed_seconds = 0.0
	_active_rune_flow_initial_process_frame = -1


func is_rune_using_active_animation(slot_index: int) -> bool:
	if not _active_rune_icons.has(slot_index):
		return false
	var rune_icon := _active_rune_icons[slot_index] as TextureRect
	return rune_icon != null and rune_icon.texture is AtlasTexture


func is_rune_scheduled_for_active_animation(slot_index: int) -> bool:
	return _active_rune_icons.has(slot_index)


func is_rune_waiting_for_next_flow(slot_index: int) -> bool:
	if not _active_rune_join_cycles.has(slot_index):
		return false
	return (
		_get_global_flow_cycle()
		< int(_active_rune_join_cycles[slot_index])
	)


# --- 卡面内容刷新 ---
func _refresh() -> void:
	if card_data == null:
		_show_empty_card()
		return

	_set_card_name(card_data.display_name)
	action_icon.texture = _get_action_texture(card_data.action_type)
	value_label.text = str(card_data.base_value)
	_apply_action_layout(card_data.action_type)
	_refresh_card_type_visuals()
	_refresh_vitals_text()
	_refresh_cooldown_text()
	priority_label.text = str(card_data.get_base_target_priority())
	card_name_frame.visible = true
	_refresh_card_frame()
	_refresh_art()
	_refresh_race_icon()
	_refresh_bottom_text()


func _refresh_vitals_text() -> void:
	if card_data == null:
		health_label.text = ""
		armor_label.text = ""
		return
	if card_data.card_type == CardData.CardType.SPELL:
		health_label.text = ""
		armor_label.text = ""
		return
	if card_data.card_type == CardData.CardType.EQUIPMENT:
		health_label.text = str(card_data.equipment_health_delta)
		armor_label.text = str(card_data.equipment_armor_delta)
		_layout_vitals_numbers()
		return
	health_label.text = str(
		_battle_current_health if _battle_vitals_active else card_data.max_health
	)
	armor_label.text = str(
		_battle_current_armor if _battle_vitals_active else card_data.armor
	)
	_layout_vitals_numbers()


func _refresh_cooldown_text() -> void:
	if card_data == null:
		cooldown_label.text = ""
		return
	if card_data.card_type == CardData.CardType.SPELL:
		cooldown_label.text = ""
		return
	var seconds := card_data.cooldown_seconds
	if card_data.card_type == CardData.CardType.EQUIPMENT:
		seconds = absf(card_data.equipment_cooldown_delta)
	elif _battle_cooldown_active:
		seconds = _battle_remaining_cooldown
	cooldown_label.text = format_cooldown_seconds(seconds)
	_set_control_rect(
		cooldown_label,
		COOLDOWN_VALUE_POSITION,
		cooldown_label.get_rendered_size()
	)


static func format_cooldown_seconds(seconds: float) -> String:
	# 显示层向上保留一位小数；减去极小误差，避免精确 3.0 因浮点误差显示 3.1。
	var tenths := clampi(
		ceili(maxf(seconds, 0.0) * 10.0 - 0.0001),
		0,
		int(CardData.MAXIMUM_COOLDOWN_SECONDS * 10.0)
	)
	return "%d.%d" % [tenths / 10, tenths % 10]


func _refresh_bottom_text() -> void:
	if card_data == null:
		return
	_stop_effect_transition()
	effect_text_label.text = card_data.effect_text
	if card_data.card_type != CardData.CardType.MINION:
		showing_effect = false
		rune_row.visible = false
		rune_row.modulate.a = 1.0
		set_process(false)
		effect_text_label.visible = true
		effect_text_label.self_modulate.a = 1.0
	else:
		rune_row.visible = true
		_refresh_runes()
		rune_row.modulate.a = effect_rune_dim_alpha if showing_effect else 1.0
		effect_text_label.visible = showing_effect
		effect_text_label.self_modulate.a = 1.0 if showing_effect else 0.0


func _animate_effect_transition() -> void:
	_stop_effect_transition()
	rune_row.visible = true
	effect_text_label.visible = true
	effect_text_label.text = card_data.effect_text
	var target_rune_alpha := effect_rune_dim_alpha if showing_effect else 1.0
	var target_text_alpha := 1.0 if showing_effect else 0.0
	_effect_transition_tween = create_tween()
	_effect_transition_tween.set_trans(Tween.TRANS_QUAD)
	_effect_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_effect_transition_tween.set_parallel(true)
	_effect_transition_tween.tween_property(
		rune_row,
		"modulate:a",
		target_rune_alpha,
		effect_transition_duration
	)
	_effect_transition_tween.tween_property(
		effect_text_label,
		"self_modulate:a",
		target_text_alpha,
		effect_transition_duration
	)
	_effect_transition_tween.chain().tween_callback(
		_finish_effect_transition.bind(showing_effect)
	)


func _finish_effect_transition(expected_showing_effect: bool) -> void:
	if showing_effect != expected_showing_effect:
		return
	rune_row.modulate.a = effect_rune_dim_alpha if showing_effect else 1.0
	effect_text_label.self_modulate.a = 1.0 if showing_effect else 0.0
	effect_text_label.visible = showing_effect
	_effect_transition_tween = null


func _stop_effect_transition() -> void:
	if _effect_transition_tween != null and _effect_transition_tween.is_valid():
		_effect_transition_tween.kill()
	_effect_transition_tween = null


func _show_empty_card() -> void:
	_stop_effect_transition()
	_active_rune_icons.clear()
	_active_rune_join_cycles.clear()
	set_process(false)
	_set_card_name("空卡牌")
	action_icon.texture = null
	card_name_frame.visible = false
	card_frame.texture = null
	card_frame.visible = false
	art_background.texture = null
	art_background.visible = false
	art_texture.texture = null
	art_texture.visible = false
	art_label.visible = true
	race_icon.texture = null
	race_icon.visible = false
	value_label.text = ""
	health_label.text = ""
	armor_label.text = ""
	cooldown_label.text = ""
	priority_label.text = "-"
	action_icon.visible = false
	value_label.visible = false
	health_icon.visible = false
	health_label.visible = false
	armor_icon.visible = false
	armor_label.visible = false
	cooldown_icon.visible = false
	cooldown_label.visible = false
	priority_label.visible = false
	effect_text_label.visible = true
	effect_text_label.self_modulate.a = 1.0
	effect_text_label.text = "没有绑定 CardData"
	rune_row.visible = false
	rune_row.modulate.a = 1.0


func _refresh_art() -> void:
	var base_background := (
		card_data.background_texture
		if card_data.background_texture != null
		else DEFAULT_ART_BACKGROUND_TEXTURE
	)
	art_background.texture = base_background
	art_background.visible = art_background.texture != null
	art_texture.texture = card_data.art_texture
	art_texture.visible = card_data.art_texture != null
	_apply_art_offset()
	art_label.visible = (
		card_data.art_texture == null
		and art_background.texture == null
	)


func _set_card_name(display_name: String) -> void:
	name_label.text = display_name
	var name_font := name_label.get_theme_font("font")
	var fitted_size := title_font_size
	while fitted_size > title_font_min_size:
		var text_size := name_font.get_string_size(
			display_name,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1.0,
			fitted_size
		)
		if (
			text_size.x <= title_area_size.x
			and name_font.get_height(fitted_size) <= title_area_size.y
		):
			break
		fitted_size -= 1
	name_label.add_theme_font_size_override("font_size", fitted_size)
	_layout_name_label()


func _layout_name_label() -> void:
	var label_height := maxf(
		title_area_size.y,
		name_label.get_combined_minimum_size().y
	)
	_set_control_rect(
		name_label,
		Vector2(0, floorf((title_area_size.y - label_height) * 0.5)),
		Vector2(title_area_size.x, label_height)
	)


func _apply_art_offset() -> void:
	if art_texture.texture == null:
		return

	var texture_size := art_texture.texture.get_size()
	var centered_position := Vector2(
		floori((art_area_size.x - texture_size.x) * 0.5),
		floori((art_area_size.y - texture_size.y) * 0.5)
	)
	_set_control_rect(
		art_texture,
		centered_position + Vector2(card_data.art_offset),
		texture_size
	)


func _refresh_card_frame() -> void:
	var rarity_key := card_data.get_rarity_asset_key()
	var texture_path := (
		"res://assets/card_frames/card_frame_%s.png" % rarity_key
	)
	card_frame.texture = load(texture_path) as Texture2D
	card_frame.visible = card_frame.texture != null


func _refresh_race_icon() -> void:
	if card_data.card_type == CardData.CardType.SPELL:
		race_icon.texture = _make_raw_atlas_texture(
			SPELL_TYPE_ATLAS,
			_get_spell_type_region(card_data.spell_type, card_data.rarity)
		)
		race_icon.visible = true
		var spell_icon_size := (_get_spell_type_region(card_data.spell_type, card_data.rarity)).size
		_set_centered_identity_icon(spell_icon_size)
		race_icon.tooltip_text = "%s · 稀有度 %s" % [
			card_data.get_spell_type_name(),
			card_data.get_rarity_name(),
		]
		return
	if card_data.card_type == CardData.CardType.EQUIPMENT:
		race_icon.texture = _make_raw_atlas_texture(
			EQUIPMENT_TYPE_ATLAS,
			_get_equipment_type_region(card_data.equipment_type, card_data.rarity)
		)
		race_icon.visible = true
		var equipment_icon_size := (_get_equipment_type_region(card_data.equipment_type, card_data.rarity)).size
		_set_centered_identity_icon(equipment_icon_size)
		race_icon.tooltip_text = "%s · 稀有度 %s" % [
			card_data.get_equipment_type_name(),
			card_data.get_rarity_name(),
		]
		return
	if card_data.card_type != CardData.CardType.MINION:
		race_icon.texture = null
		race_icon.visible = false
		return

	var race_key := card_data.get_race_asset_key()
	var rarity_key := card_data.get_rarity_asset_key()
	var texture_path := (
		"res://assets/races/%s/race_%s_%s.png"
		% [race_key, race_key, rarity_key]
	)
	var texture := load(texture_path) as Texture2D
	race_icon.texture = texture
	race_icon.visible = texture != null
	if texture == null:
		return

	var icon_size := texture.get_size()
	var icon_position := Vector2(
		race_center_pixel.x - floori(icon_size.x * 0.5),
		race_center_pixel.y - floori(icon_size.y * 0.5)
	)
	_set_control_rect(race_icon, icon_position, icon_size)
	race_icon.tooltip_text = "%s · 稀有度 %s" % [
		card_data.get_race_name(),
		card_data.get_rarity_name(),
	]


func _refresh_card_type_visuals() -> void:
	# 共用随从节点：非随从只替换左上/中央身份图标，不复制第二套 CardView。
	action_icon.visible = true
	value_label.visible = true
	health_icon.visible = true
	health_label.visible = true
	armor_icon.visible = true
	armor_label.visible = true
	cooldown_icon.visible = true
	cooldown_label.visible = true
	priority_label.visible = false
	if card_data.card_type == CardData.CardType.SPELL:
		action_icon.texture = _make_raw_atlas_texture(
			SPELL_RARITY_BADGE_TEXTURE,
			SPELL_RARITY_BADGE_REGIONS[card_data.rarity]
		)
		_set_control_rect(
			action_icon,
			SPELL_RARITY_BADGE_POSITION,
			SPELL_RARITY_BADGE_SIZE
		)
		value_label.text = ""
		value_label.visible = false
		health_icon.visible = false
		health_label.visible = false
		armor_icon.visible = false
		armor_label.visible = false
		cooldown_icon.visible = false
		cooldown_label.visible = false
	elif card_data.card_type == CardData.CardType.EQUIPMENT:
		action_icon.texture = (
			EQUIPMENT_ACTION_INCREASE_TEXTURE
			if card_data.equipment_action_delta >= 0
			else EQUIPMENT_ACTION_DECREASE_TEXTURE
		)
		_set_control_rect(
			action_icon,
			EQUIPMENT_ACTION_POSITION,
			EQUIPMENT_ACTION_SIZE
		)
		value_label.text = str(absi(card_data.equipment_action_delta))
		_set_control_rect(
			value_label,
			_get_action_value_position(value_label.text),
			value_label.get_rendered_size()
		)
	else:
		_apply_action_layout(card_data.action_type)
		priority_label.visible = false


func _make_raw_atlas_texture(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = region
	return atlas_texture


func _get_spell_type_region(
	spell_type: CardData.SpellType,
	rarity: CardData.Rarity,
) -> Rect2:
	var visual_column_by_rarity := [4, 3, 2, 1, 0] # I、II、III、IV、V 对应图集 I、II、III、IV、V 的反向视觉列
	var visual_column: int = visual_column_by_rarity[rarity]
	return Rect2(
		SPELL_TYPE_ATLAS_X[visual_column],
		SPELL_TYPE_ATLAS_Y[spell_type],
		SPELL_TYPE_ATLAS_W[visual_column],
		SPELL_TYPE_ATLAS_H[spell_type],
	)


func _get_equipment_type_region(
	equipment_type: CardData.EquipmentType,
	rarity: CardData.Rarity,
) -> Rect2:
	var visual_column_by_rarity := [4, 0, 1, 2, 3] # I、II、III、IV、V 对应图集 I、II、III、IV、V 的非顺序列
	var visual_column: int = visual_column_by_rarity[rarity]
	return Rect2(
		EQUIPMENT_TYPE_ATLAS_X[visual_column],
		EQUIPMENT_TYPE_ATLAS_Y[equipment_type],
		EQUIPMENT_TYPE_ATLAS_W[visual_column],
		EQUIPMENT_TYPE_ATLAS_H[equipment_type],
	)


func _set_centered_identity_icon(icon_size: Vector2) -> void:
	_set_control_rect(
		race_icon,
		Vector2(
			race_center_pixel.x - floori(icon_size.x * 0.5),
			race_center_pixel.y - floori(icon_size.y * 0.5)
		),
		icon_size
	)


func _refresh_runes() -> void:
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		_active_rune_icons.clear()
		_active_rune_join_cycles.clear()
		set_process(false)
		rune_row.visible = false
		return
	var previous_join_cycles := _active_rune_join_cycles.duplicate()
	_active_rune_icons.clear()
	_active_rune_join_cycles.clear()
	_active_rune_frame = -1
	for child: Node in rune_row.get_children():
		rune_row.remove_child(child)
		child.queue_free()
	var current_cycle := _get_global_flow_cycle()
	var joins_initial_cycle := (
		has_active_rune_flow_started()
		and Engine.get_process_frames() == _active_rune_flow_initial_process_frame
	)
	for slot_index: int in 3:
		var rune_slot := _create_rune_slot()
		rune_row.add_child(rune_slot)
		if slot_index < card_data.runes.size():
			var rune := card_data.runes[slot_index]
			var is_active := _highlighted_rune_indices.has(slot_index)
			var join_cycle: int = -1
			if is_active:
				join_cycle = (
					current_cycle
					if _rune_highlight_is_preview or joins_initial_cycle
					else int(previous_join_cycles.get(
						slot_index,
						current_cycle + 1
					))
				)
				_active_rune_join_cycles[slot_index] = join_cycle
			var show_active_frame := is_active and current_cycle >= join_cycle
			var rune_icon := _create_rune_icon(rune, show_active_frame)
			rune_slot.add_child(rune_icon)
			if is_active:
				_active_rune_icons[slot_index] = rune_icon
	_update_active_rune_frames()
	set_process(not _active_rune_icons.is_empty())


# --- 符文纹理与全局流光时间轴 ---
func _create_rune_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = rune_slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _create_rune_icon(
	rune: CardData.ElementType, use_active_animation: bool = false
) -> TextureRect:
	var icon := TextureRect.new()
	icon.position = (rune_slot_size - rune_icon_size) * 0.5
	icon.custom_minimum_size = rune_icon_size
	icon.size = rune_icon_size
	icon.texture = (
		_create_active_rune_atlas(rune)
		if use_active_animation
		else _get_rune_texture(rune)
	)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate.a = (
		PREVIEW_ACTIVE_RUNE_ALPHA
		if (
			use_active_animation
			and _rune_highlight_is_preview
			and _dim_preview_active_runes
		)
		else 1.0
	)
	icon.tooltip_text = card_data.get_element_type_name(rune)
	return icon


func _create_active_rune_atlas(
	rune: CardData.ElementType
) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = RUNE_ACTIVE_FLOW_SHEET
	atlas_texture.region = Rect2(
		_get_active_rune_sheet_x(rune),
		0.0,
		rune_icon_size.x,
		rune_icon_size.y
	)
	return atlas_texture


func _get_active_rune_sheet_x(rune: CardData.ElementType) -> float:
	match rune:
		CardData.ElementType.DARK:
			return 0.0
		CardData.ElementType.FIRE:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP)
		CardData.ElementType.WATER:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 2)
		CardData.ElementType.LIGHT:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 3)
		CardData.ElementType.WOOD:
			return float(ACTIVE_RUNE_SHEET_COLUMN_STEP * 4)
		_:
			return 0.0


func _update_active_rune_frames() -> void:
	if _active_rune_icons.is_empty():
		return
	var elapsed_seconds := _get_global_flow_elapsed_seconds()
	var current_cycle := floori(
		elapsed_seconds / ACTIVE_RUNE_CYCLE_SECONDS
	)
	var effect_elapsed_seconds := (
		elapsed_seconds + _get_active_rune_start_phase_seconds()
	)
	var cycle_time := fposmod(
		effect_elapsed_seconds,
		ACTIVE_RUNE_CYCLE_SECONDS
	)
	var current_frame := _get_flow_frame_at_time(cycle_time)
	_active_rune_frame = current_frame
	var frame_y := float(current_frame) * rune_icon_size.y
	for slot_value: Variant in _active_rune_icons.keys():
		var slot_index := int(slot_value)
		var rune_icon := _active_rune_icons[slot_index] as TextureRect
		var join_cycle := int(_active_rune_join_cycles[slot_index])
		if current_cycle < join_cycle:
			if rune_icon.texture is AtlasTexture:
				rune_icon.texture = _get_rune_texture(
					card_data.runes[slot_index]
				)
			continue
		if not rune_icon.texture is AtlasTexture:
			rune_icon.texture = _create_active_rune_atlas(
				card_data.runes[slot_index]
			)
		var atlas_texture := rune_icon.texture as AtlasTexture
		var region := atlas_texture.region
		region.position.y = frame_y
		atlas_texture.region = region


func _get_global_flow_elapsed_seconds() -> float:
	if _active_rune_flow_epoch_msec < 0:
		return 0.0
	var process_frame := Engine.get_process_frames()
	if process_frame != _active_rune_flow_cached_process_frame:
		_active_rune_flow_cached_process_frame = process_frame
		_active_rune_flow_cached_elapsed_seconds = float(
			Time.get_ticks_msec() - _active_rune_flow_epoch_msec
		) / 1000.0
	return _active_rune_flow_cached_elapsed_seconds


static func _start_active_rune_flow_if_needed() -> void:
	if _active_rune_flow_epoch_msec >= 0:
		return
	_active_rune_flow_epoch_msec = Time.get_ticks_msec()
	_active_rune_flow_cached_process_frame = -1
	_active_rune_flow_cached_elapsed_seconds = 0.0
	_active_rune_flow_initial_process_frame = Engine.get_process_frames()


func _get_global_flow_cycle() -> int:
	return floori(
		_get_global_flow_elapsed_seconds() / ACTIVE_RUNE_CYCLE_SECONDS
	)


func _get_active_rune_start_phase_seconds() -> float:
	return fposmod(
		ACTIVE_RUNE_START_PHASE_SECONDS,
		ACTIVE_RUNE_CYCLE_SECONDS
	)


func _get_flow_frame_at_time(cycle_time: float) -> int:
	var source_cycle_seconds: float = 0.0
	for frame_seconds: float in ACTIVE_RUNE_FRAME_SECONDS:
		source_cycle_seconds += frame_seconds
	var normalized_progress := (
		fposmod(cycle_time, ACTIVE_RUNE_CYCLE_SECONDS)
		/ ACTIVE_RUNE_CYCLE_SECONDS
	)
	var source_cycle_time := normalized_progress * source_cycle_seconds
	var accumulated_seconds: float = 0.0
	for frame_index: int in ACTIVE_RUNE_FRAME_COUNT:
		accumulated_seconds += ACTIVE_RUNE_FRAME_SECONDS[frame_index]
		if source_cycle_time < accumulated_seconds:
			return frame_index
	return ACTIVE_RUNE_FRAME_COUNT - 1


func _get_rune_texture(rune: CardData.ElementType) -> Texture2D:
	match rune:
		CardData.ElementType.FIRE:
			return RUNE_FIRE_TEXTURE
		CardData.ElementType.WATER:
			return RUNE_WATER_TEXTURE
		CardData.ElementType.WOOD:
			return RUNE_WOOD_TEXTURE
		CardData.ElementType.LIGHT:
			return RUNE_LIGHT_TEXTURE
		CardData.ElementType.DARK:
			return RUNE_DARK_TEXTURE
		_:
			return RUNE_FIRE_TEXTURE


func _get_action_texture(action_type: CardData.ActionType) -> Texture2D:
	match action_type:
		CardData.ActionType.MELEE:
			return ACTION_MELEE_TEXTURE
		CardData.ActionType.RANGED:
			return ACTION_RANGED_TEXTURE
		CardData.ActionType.MAGIC:
			return ACTION_MAGIC_TEXTURE
		CardData.ActionType.HEAL:
			return ACTION_HEAL_TEXTURE
		CardData.ActionType.DEFENSE:
			return ACTION_DEFENSE_TEXTURE
		_:
			return ACTION_MELEE_TEXTURE


# --- 固定像素布局；集中设置 Rect 可避免场景与脚本各维护一份坐标 ---
func _apply_pixel_layout() -> void:
	# 行动、生命和护甲图标会越过 99×136 裸卡边界，根节点不能裁切。
	# 效果文字自身负责三行布局，外层不裁切，让2px黑色描边可以画入预留边距。
	clip_contents = false
	custom_minimum_size = card_size
	size = card_size

	_set_control_rect(top_row, Vector2.ZERO, card_size)
	_set_control_rect(name_clip, title_area_position, title_area_size)
	name_clip.clip_contents = true
	_set_control_rect(art_panel, art_area_position, art_area_size)
	# 人物原图保持 1:1 像素；超出插画窗口的部分由 ArtPanel 裁切。
	art_panel.clip_contents = true
	_set_control_rect(art_content, Vector2.ZERO, art_area_size)
	_set_control_rect(art_background, Vector2.ZERO, art_area_size)
	_set_control_rect(art_label, Vector2.ZERO, art_area_size)
	art_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_background.stretch_mode = TextureRect.STRETCH_SCALE
	art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_texture.stretch_mode = TextureRect.STRETCH_KEEP
	_set_control_rect(card_frame, Vector2.ZERO, card_size)
	card_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_frame.stretch_mode = TextureRect.STRETCH_SCALE
	card_name_frame.texture = CARD_NAME_FRAME_TEXTURE
	_set_control_rect(
		card_name_frame,
		name_frame_position,
		CARD_NAME_FRAME_TEXTURE.get_size()
	)
	card_name_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_name_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_set_control_rect(stats_row, Vector2.ZERO, card_size)
	_set_control_rect(
		health_icon,
		health_icon_position,
		health_badge_size
	)
	_set_control_rect(
		armor_icon,
		armor_icon_position,
		armor_badge_size
	)
	_set_control_rect(cooldown_icon, cooldown_icon_position, cooldown_icon_size)
	_set_control_rect(cooldown_label, COOLDOWN_VALUE_POSITION, cooldown_label.get_rendered_size())
	_layout_vitals_numbers()
	priority_label.visible = false
	_set_control_rect(bottom_panel, bottom_area_position, bottom_area_size)
	bottom_panel.clip_contents = false
	_set_control_rect(
		rune_row,
		rune_area_position - bottom_area_position,
		rune_area_size
	)
	var effect_text_size := bottom_area_size - effect_text_inset * 2.0
	_set_control_rect(effect_text_label, effect_text_inset, effect_text_size)

	art_panel.z_index = 0
	card_frame.z_index = 5
	card_name_frame.z_index = 8
	top_row.z_index = 10
	bottom_panel.z_index = 10
	stats_row.z_index = 20
	action_icon.z_index = 10
	value_label.z_index = 11
	action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	action_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 三个状态图标直接使用正式 1×源图，由显示壳统一放大最终画面。
	health_icon.texture = HEALTH_TEXTURE
	health_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	health_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	armor_icon.texture = ARMOR_TEXTURE
	armor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	armor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cooldown_icon.texture = COOLDOWN_HOURGLASS_TEXTURE
	cooldown_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cooldown_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_apply_action_layout(CardData.ActionType.MELEE)
	_apply_card_typography()
	name_label.add_theme_color_override(
		"font_color",
		Color("35251c")
	)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_layout_name_label()
	priority_label.add_theme_font_size_override("font_size", stats_font_size)
	rune_row.add_theme_constant_override("separation", rune_spacing)


func _apply_card_typography() -> void:
	name_label.add_theme_font_override("font", CARD_TEXT_FONT)
	effect_text_label.add_theme_font_override("font", CARD_TEXT_FONT)
	# WORD_SMART 在没有空格的中文长句中会退回逐字断行，避免 Windows
	# 把整句当成一个单词撑出卡框；最多显示三行。
	effect_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 文字外框不裁切，2px黑色描边可以进入四周预留的空隙；行数仍限制为3行，
	# 避免极长描述越过卡牌底边。
	effect_text_label.clip_text = false
	effect_text_label.max_lines_visible = 3
	effect_text_label.custom_minimum_size = bottom_area_size - effect_text_inset * 2.0
	name_label.add_theme_font_size_override("font_size", title_font_size)
	effect_text_label.add_theme_font_size_override("font_size", effect_font_size)
	effect_text_label.add_theme_color_override(
		"font_color",
		effect_text_color
	)
	effect_text_label.add_theme_color_override(
		"font_outline_color",
		effect_text_outline_color
	)
	effect_text_label.add_theme_constant_override(
		"outline_size",
		effect_text_outline_size
	)
	effect_text_label.add_theme_constant_override(
		"line_spacing",
		effect_line_spacing
	)


func _apply_action_layout(action_type: CardData.ActionType) -> void:
	var icon_rect := _get_action_icon_rect(action_type)
	_set_control_rect(action_icon, icon_rect.position, icon_rect.size)
	_set_control_rect(
		value_label,
		_get_action_value_position(value_label.text),
		value_label.get_rendered_size()
	)


func get_visual_capture_padding_top_left() -> Vector2:
	if card_data != null:
		if card_data.card_type == CardData.CardType.SPELL:
			return _get_rect_capture_padding(
				Rect2(SPELL_RARITY_BADGE_POSITION, SPELL_RARITY_BADGE_SIZE)
			)
		if card_data.card_type == CardData.CardType.EQUIPMENT:
			return _get_rect_capture_padding(
				Rect2(EQUIPMENT_ACTION_POSITION, EQUIPMENT_ACTION_SIZE)
			)
	var action_type := (
		card_data.action_type
		if card_data != null
		else CardData.ActionType.MELEE
	)
	return _get_visual_capture_padding_top_left(action_type)


func get_max_visual_capture_padding_top_left() -> Vector2:
	var padding := Vector2.ZERO
	for action_type: CardData.ActionType in [
		CardData.ActionType.MELEE,
		CardData.ActionType.RANGED,
		CardData.ActionType.MAGIC,
		CardData.ActionType.HEAL,
		CardData.ActionType.DEFENSE,
	]:
		var action_padding := _get_visual_capture_padding_top_left(action_type)
		padding.x = maxf(padding.x, action_padding.x)
		padding.y = maxf(padding.y, action_padding.y)
	for extra_rect: Rect2 in [
		Rect2(SPELL_RARITY_BADGE_POSITION, SPELL_RARITY_BADGE_SIZE),
		Rect2(EQUIPMENT_ACTION_POSITION, EQUIPMENT_ACTION_SIZE),
	]:
		var extra_padding := _get_rect_capture_padding(extra_rect)
		padding.x = maxf(padding.x, extra_padding.x)
		padding.y = maxf(padding.y, extra_padding.y)
	return padding


func get_visual_capture_padding_bottom_right() -> Vector2:
	return Vector2(maxf(MAX_STATS_RIGHT_EDGE - card_size.x, 0.0), 0.0)


func _get_visual_capture_padding_top_left(
	action_type: CardData.ActionType
) -> Vector2:
	var icon_rect := _get_action_icon_rect(action_type)
	var value_text := str(card_data.base_value) if card_data != null else "0"
	var value_rect := Rect2(
		_get_action_value_position(value_text),
		Vector2(20, RuneNumberDisplay.LARGE_HEIGHT)
	)
	var left_edge := minf(icon_rect.position.x, value_rect.position.x)
	var top_edge := minf(icon_rect.position.y, value_rect.position.y)
	return Vector2(
		maxf(-left_edge, 0.0) + VISUAL_CAPTURE_LEFT_SAFETY,
		maxf(-top_edge, 0.0)
	)


func _get_rect_capture_padding(rect: Rect2) -> Vector2:
	return Vector2(
		maxf(-rect.position.x, 0.0) + VISUAL_CAPTURE_LEFT_SAFETY,
		maxf(-rect.position.y, 0.0)
	)


func _get_action_icon_rect(action_type: CardData.ActionType) -> Rect2:
	var icon_size := Vector2(25, 25)
	var left_overhang: float = 4.0
	match action_type:
		CardData.ActionType.MAGIC:
			icon_size = Vector2(25, 25)
			left_overhang = 7.0
		CardData.ActionType.DEFENSE:
			icon_size = Vector2(24, 25)
			left_overhang = 6.0
		CardData.ActionType.RANGED, CardData.ActionType.MELEE:
			icon_size = Vector2(25, 25)
			left_overhang = 4.0
		CardData.ActionType.HEAL:
			icon_size = Vector2(25, 28)
			left_overhang = 8.0
	return Rect2(Vector2(-left_overhang, -action_top_overhang), icon_size)


static func get_action_value_position(value: int) -> Vector2:
	return _get_action_value_position(str(clampi(value, 0, CardData.MAXIMUM_BASE_VALUE)))


static func get_health_value_position(value: int) -> Vector2:
	return _get_position_by_digits_and_ones(
		clampi(value, 0, CardData.MAXIMUM_HEALTH),
		HEALTH_VALUE_POSITIONS
	)


static func get_armor_value_position(value: int) -> Vector2:
	return _get_position_by_digits_and_ones(
		clampi(value, 0, CardData.MAXIMUM_ARMOR),
		ARMOR_VALUE_POSITIONS
	)


static func _get_action_value_position(value_text: String) -> Vector2:
	if value_text.length() >= 2:
		return ACTION_VALUE_POSITIONS[&"double"] as Vector2
	if value_text == "1":
		return ACTION_VALUE_POSITIONS[&"single_one"] as Vector2
	return ACTION_VALUE_POSITIONS[&"single_other"] as Vector2


static func _get_position_by_digits_and_ones(value: int, positions: Dictionary) -> Vector2:
	var value_text := str(value)
	var digit_count := clampi(value_text.length(), 1, 3)
	var one_count := mini(value_text.count("1"), digit_count)
	var positions_for_digits := positions[digit_count] as Array
	return positions_for_digits[mini(one_count, positions_for_digits.size() - 1)] as Vector2


func _layout_vitals_numbers() -> void:
	if not is_instance_valid(health_label) or not is_instance_valid(armor_label):
		return
	var health_value := 0
	var armor_value := 0
	if card_data != null:
		if card_data.card_type == CardData.CardType.EQUIPMENT:
			health_value = card_data.equipment_health_delta
			armor_value = card_data.equipment_armor_delta
		else:
			health_value = _battle_current_health if _battle_vitals_active else card_data.max_health
			armor_value = _battle_current_armor if _battle_vitals_active else card_data.armor
	_set_control_rect(
		health_label,
		get_health_value_position(health_value),
		health_label.get_rendered_size()
	)
	_set_control_rect(
		armor_label,
		get_armor_value_position(armor_value),
		armor_label.get_rendered_size()
	)


func _set_control_rect(control: Control, position_value: Vector2, size_value: Vector2) -> void:
	control.position = position_value
	control.custom_minimum_size = Vector2.ZERO
	control.size = size_value
	control.custom_minimum_size = size_value


func _ignore_mouse_on_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_ignore_mouse_on_children(child)
