extends Control

## 主场景的流程协调器。
##
## 这里把收藏、两条战场行、阶段切换和两种拖拽入口连接起来；
## 小队布局与牌型显示分别下放给 BattlefieldRow / SquadView。
## 拖动期间只维护预览，只有 _transfer_* 系列函数会提交真实数据变更。

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const BATTLEFIELD_ROW_SCENE: PackedScene = preload("res://scenes/ui/BattlefieldRow.tscn")
const COLLECTION_DROP_ZONE_SCRIPT: Script = preload("res://scripts/ui/collection_drop_zone.gd")
const PAGE_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_large.fnt")
const WOOD_WORLD_TEXTURE: Texture2D = preload("res://assets/stage_6_5/wood_world.png")
const BATTLEFIELD_BACKGROUND_TEXTURE: Texture2D = preload("res://assets/stage_6_5/battlefield_background.png")
const TABLECLOTH_DECOR_TEXTURE: Texture2D = preload("res://assets/stage_6_5/tablecloth_decor.png")
const BATTLEFIELD_WOOD_PAD_TEXTURE: Texture2D = preload("res://assets/stage_6_5/battlefield_wood_pad.png")
const BATTLEFIELD_BROCADE_TEXTURE: Texture2D = preload("res://assets/stage_6_5/battlefield_brocade.png")
const COLLECTION_BOOK_BASE_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_book_cover.png")
const COLLECTION_LEFT_PAGE_FRONT_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_left_page_front.png")
const COLLECTION_RIGHT_PAGE_FRONT_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_right_page_front.png")
const RECENT_CARDS_BOOKMARK_TEXTURE: Texture2D = preload("res://assets/stage_6_5/recent_cards_bookmark.png")
const RECENT_CARDS_LEFT_PAGE_TEXTURE: Texture2D = preload("res://assets/stage_6_5/recent_cards_left_page.png")
const RECENT_CARDS_RIGHT_PAGE_TEXTURE: Texture2D = preload("res://assets/stage_6_5/recent_cards_right_page.png")
const COLLECTION_LEFT_PAGE_BACK_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_left_page_back.png")
const COLLECTION_RIGHT_PAGE_BACK_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_right_page_back.png")
const CHARACTER_SHEET_TEXTURE: Texture2D = preload("res://assets/stage_6_5/character_front_back.png")
const ACTION_TABS_TEXTURE: Texture2D = preload("res://assets/stage_6_5/page_tabs.png")
const CARD_TYPE_TABS_TEXTURE: Texture2D = preload("res://assets/stage_6_5/card_type_tabs.png")
const ACTION_FILTER_TEXTURES: Array[Texture2D] = [
	preload("res://assets/actions/action_melee.png"),
	preload("res://assets/actions/action_ranged.png"),
	preload("res://assets/actions/action_magic.png"),
	preload("res://assets/actions/action_heal.png"),
	preload("res://assets/actions/action_defense.png"),
] # 五个顶部标签依次代表近战、远程、法术、治疗、防御
const ACTION_FILTER_NAMES: Array[String] = ["近战", "远程", "法术", "治疗", "防御"] # 行动标签提示文字
const COLLECTION_FILTER_ICONS_TEXTURE: Texture2D = preload("res://assets/stage_6_5/collection_filter_icons.png")
const CHARACTER_FRONT_REGION := Rect2(449, 256, 161, 187) # 人物正面在原始透明图中的像素区域
const CHARACTER_BACK_REGION := Rect2(642, 256, 165, 187) # 人物背面在原始透明图中的像素区域
const ACTION_TAB_REGION := Rect2(34, 22, 34, 66) # 高清标签图中第一个完整未选中标签的像素区域
const CARD_TYPE_FILTER_REGIONS: Array[Rect2] = [
	Rect2(0, 0, 30, 40),
	Rect2(39, 0, 30, 40),
	Rect2(79, 0, 30, 40),
	Rect2(119, 0, 30, 40),
] # 四个独立书签在新素材中的裁切区域
const CARD_TYPE_FILTER_TYPES: Array[int] = [
	CardData.CardType.MINION,
	CardData.CardType.SPELL,
	CardData.CardType.EQUIPMENT,
	CardData.CardType.RESOURCE,
] # 书签视觉顺序：随从、法术、装备、资源
const CARD_TYPE_FILTER_NAMES: Array[String] = ["随从", "法术", "装备", "资源"] # 卡牌种类书签提示文字
const RARITY_FILTER_REGIONS: Array[Rect2] = [
	Rect2(192, 9, 16, 16),
	Rect2(216, 9, 16, 16),
	Rect2(240, 9, 16, 16),
	Rect2(263, 9, 16, 16),
	Rect2(287, 9, 16, 16),
] # I～V 五个当前可用的稀有度筛选图标
const ELEMENT_FILTER_REGIONS: Array[Rect2] = [
	Rect2(330, 9, 16, 16),
	Rect2(354, 9, 16, 16),
	Rect2(378, 9, 16, 16),
	Rect2(401, 9, 16, 16),
	Rect2(425, 9, 16, 16),
] # 水、木、火、光、暗五个元素筛选图标
const ELEMENT_FILTER_TYPES: Array[int] = [
	CardData.ElementType.WATER,
	CardData.ElementType.WOOD,
	CardData.ElementType.FIRE,
	CardData.ElementType.LIGHT,
	CardData.ElementType.DARK,
] # 元素图标的视觉顺序与 CardData 枚举顺序不同，在这里集中映射
const ELEMENT_FILTER_NAMES: Array[String] = ["水", "木", "火", "光", "暗"] # 与元素筛选图标顺序一致的提示文字
const SEARCH_FILTER_ART_REGION := Rect2(457, 0, 112, 40) # 从筛选图集单独裁出的完整搜索栏
const SEARCH_ICON_HOTSPOT_REGION := Rect2(0, 10, 17, 14) # 相对搜索栏图片的放大镜点击范围
const SEARCH_TEXT_HOTSPOT_REGION := Rect2(17, 10, 80, 14) # 相对搜索栏图片的文字输入范围
const SEARCH_CLEAR_HOTSPOT_REGION := Rect2(96, 10, 16, 14) # 相对搜索栏图片的 X 点击范围
# 收藏放大到最大交互比例时，也要容纳左侧 8px、顶部 4px、
# 右侧 5px 的越界图标，避免 ScrollContainer 把它们裁掉。
const COLLECTION_CARD_SAFE_PADDING := Vector2(14, 11) # 收藏槽四周预留空间，避免放大和越界图标被裁切
const WORLD_SECTION_HEIGHT: float = 360.0 # 敌方、我方和收藏三段纵向世界各自的高度
const VIEW_TWEEN_DURATION: float = 0.32 # 人物按钮与阶段默认视角的平滑切换时长
const COLLECTION_MAX_PHYSICAL_PAGES: int = 100 # 收藏最多显示 100 个物理单页
const COLLECTION_MAX_SPREADS: int = COLLECTION_MAX_PHYSICAL_PAGES / 2 # 两个物理页组成一组展开页
const COLLECTION_SLOTS_PER_PAGE: int = 12 # 每组左右书页合计固定卡位数
const COLLECTION_MAX_CARDS: int = COLLECTION_MAX_PHYSICAL_PAGES * 6 # 每个物理页 6 张，100 页合计 600 张
const RECENT_CARDS_LIMIT: int = 12 # 最近使用书签固定保留一组左右页，共 12 张
const COLLECTION_SLOT_STEP := Vector2(137.0, 153.0) # 高清收藏底图中相邻卡位的横向与纵向步长
const ENEMY_BACK_CARD_TOP_Y: float = 48.0 # 敌方后排卡牌顶边在 1280×1080 世界中的固定 Y 坐标
const ENEMY_FRONT_CARD_TOP_Y: float = 202.0 # 敌方前排卡牌顶边在 1280×1080 世界中的固定 Y 坐标
const PLAYER_FRONT_CARD_TOP_Y: float = 382.0 # 我方前排卡牌顶边在 1280×1080 世界中的固定 Y 坐标
const PLAYER_BACK_CARD_TOP_Y: float = 536.0 # 我方后排卡牌顶边在 1280×1080 世界中的固定 Y 坐标
const BATTLEFIELD_ROW_CONTENT_INSET_Y: float = 24.0 # BattlefieldRow 会把卡牌内容在 184px 行高中居中产生的内部顶边距离
const ACTION_TABS_POSITION := Vector2(42, -6) # 行动方式书签组相对书本的位置
const ACTION_TAB_STEP_X: float = 42.0 # 相邻行动标签左边缘的固定水平间距
const ACTION_TAB_REST_Y: float = 8.0 # 未选中行动标签的静止 Y 位置
const ACTION_TAB_SELECTED_Y: float = 0.0 # 选中行动标签向上抬起后的 Y 位置
const ACTION_TAB_ICON_POSITION := Vector2(5, 5) # 行动方式图标相对单个行动书签的位置
const CARD_TYPE_TABS_POSITION := Vector2(266, 7) # 卡牌种类书签组相对书本的位置
const CARD_TYPE_TAB_REST_Y: float = -2.0 # 未选中卡牌种类书签的静止 Y 位置
const CARD_TYPE_TAB_SELECTED_Y: float = -10.0 # 选中卡牌种类书签向上抽出的 Y 位置
const TAB_OVERSHOOT_PIXELS: float = 2.0 # 书签抽出或缩回时越过目标位置的像素数
const TAB_OVERSHOOT_DURATION: float = 0.14 # 书签先越过目标位置所用时间（秒）
const TAB_SETTLE_DURATION: float = 0.08 # 书签从越位处回弹到目标位置所用时间（秒）
const ACTION_TAB_TWEEN_DURATION: float = TAB_OVERSHOOT_DURATION + TAB_SETTLE_DURATION # 行动书签完整动画时长
const CARD_TYPE_TAB_TWEEN_DURATION: float = ACTION_TAB_TWEEN_DURATION # 卡牌种类书签沿用同一回弹节奏
const RARITY_FILTER_POSITION := Vector2(662, -1) # 稀有度五按钮组相对收藏区的位置
const ELEMENT_FILTER_POSITION := Vector2(800, -1) # 元素符文五按钮组相对收藏区的位置
const SEARCH_FILTER_POSITION := Vector2(927, -10) # 搜索栏图片及其交互层相对收藏区的位置
const COLLECTION_VIEWPORT_POSITION := Vector2(31, 33) # 收藏卡位层相对书本底座的位置
const COLLECTION_PAGE_SIZE := Vector2(413, 309) # 单张活动书页与书签页素材的原始尺寸
const COLLECTION_LEFT_PAGE_POSITION := Vector2(23, 25) # 左活动书页相对书皮的位置
const COLLECTION_RIGHT_PAGE_POSITION := Vector2(436, 25) # 右活动书页相对书皮的位置
const LEFT_PAGE_NUMBER_POSITION := Vector2(30, 310) # 左下物理页码相对书本的位置
const RIGHT_PAGE_NUMBER_POSITION := Vector2(794, 310) # 右下物理页码相对书本的位置
const PAGE_NUMBER_SIZE := Vector2(48, 24) # 左右物理页码各自的显示区域
const PAGE_NUMBER_FONT_SIZE: int = 12 # 页码复用卡牌基础数值的原生数字字号
const RECENT_BOOKMARK_POSITION := Vector2(-35, 82) # 最近使用书签从书本左侧露出的固定位置
const RECENT_BOOKMARK_SELECTED_OFFSET := Vector2(-8, 0) # 最近页启用时书签向左抽出的距离
const RECENT_BOOKMARK_SHAKE_ANGLE: float = 2.5 # 新卡收录时最近使用书签左右抖动的最大角度
const RECENT_BOOKMARK_SHAKE_STEP_DURATION: float = 0.045 # 最近使用书签每次小幅摆动的时间（秒）
const PAGE_TURN_HALF_DURATION: float = 0.18 # 翻页前半程或后半程各自的动画时长（秒）
const PAGE_TURN_SHADOW_WIDTH: float = 42.0 # 活动页靠近书脊时动态阴影的最大宽度
const PAGE_TURN_MID_SCALE_Y: float = 1.0 # 活动页压到书脊时的轻微纵向拉伸，模拟纸页抬起则增加数值
const PAGE_TURN_EDGE_WIDTH: float = 4.0 # 活动页自由边缘的像素宽度
const PAGE_TURN_EDGE_DARK_COLOR := Color("76563b") # 活动页最外侧暗边颜色
const PAGE_TURN_EDGE_LIGHT_COLOR := Color("f0d1a2") # 活动页内侧高光颜色
const PAGE_TURN_SHADOW_Z_INDEX: int = 50 # 高于固定页卡牌内部节点、低于活动页的投影层级
const PAGE_TURN_MOVING_Z_INDEX: int = 100 # 活动页纸张必须压住固定页卡牌内部最高绘制层

enum WorldView { BATTLEFIELDS, COLLECTION }

enum GamePhase {
	PREPARE,
	BATTLE,
	RESULT,
}

var current_phase: GamePhase = GamePhase.PREPARE
var selected_card: CardData
var selected_board_row: BattlefieldRow
var selected_board_slot: BoardSlot
# 点击携带与 Godot 原生拖拽共用同一种拖拽数据字典，避免两套规则分叉。
var _click_carry_data: Dictionary = {}
var _click_carry_preview: Control
var _active_collection_entry_animations: int = 0
var _battlefield_clock_check_queued: bool = false
var current_world_view: WorldView = WorldView.COLLECTION
var current_collection_page: int = 0
var active_rarity_filters: Array[int] = []
var active_element_filters: Array[int] = []
var active_action_filters: Array[int] = []
var active_card_type_filters: Array[int] = []
var search_query: String = ""
var recently_returned_cards: Array[CardData] = []
var collection_bookmark_active: bool = false
var _regular_collection_page_before_bookmark: int = 0
var last_page_turn_method: StringName = &""
var _view_tween: Tween
var _page_tween: Tween
var _action_tab_tween: Tween
var _card_type_tab_tween: Tween
var _recent_bookmark_tween: Tween
var _recent_bookmark_shake_tween: Tween
var _page_turn_overlay: Control

@export var collection_cards: Array[CardData] = [] # 真实收藏成员；显示顺序固定按稀有度 V→I 派生
@export var collection_card_scale: float = 1.0 # 收藏区域中卡牌的基础缩放倍率

var phase_label: Label
var play_area_label: Label
var world_content: Control
var front_row: BattlefieldRow
var back_row: BattlefieldRow
var enemy_back_row: BattlefieldRow
var enemy_front_row: BattlefieldRow
var collection_viewport: Control
var collection_card_row: Control
var collection_drop_zone: Control
var card_art_tuner_button: Button
var drag_mode_button: Button
var enemy_avatar: TextureRect
var player_avatar_button: TextureButton
var search_edit: LineEdit
var search_button: Button
var clear_search_button: Button
var search_filter_art: TextureRect
var rarity_buttons: Control
var card_type_filter_tabs: Control
var element_buttons: Control
var action_filter_tabs: Control
var left_edge_button: Button
var right_edge_button: Button
var left_page_number_label: Label
var right_page_number_label: Label
var recent_bookmark_button: TextureButton
var regular_pages_art: Control
var regular_left_page_art: TextureRect
var regular_right_page_art: TextureRect
var recent_left_page_art: TextureRect
var recent_right_page_art: TextureRect
var card_text_debug_panel: Panel
var effect_line_spacing_spin_box: SpinBox
var effect_color_button: ColorPickerButton
var effect_text_toggle: Button
var text_debug_reset_button: Button


func _build_scene_structure() -> void:
	# 三段世界使用同一坐标系；切视角只移动 WorldContent，不分别搬动卡牌。
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("18252a")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -1000
	add_child(background)
	var world := Control.new()
	world.name = "WorldContent"
	world.unique_name_in_owner = true
	world.size = Vector2(1280, WORLD_SECTION_HEIGHT * 3.0)
	add_child(world)
	_add_texture_layer(world, "WoodWorld", WOOD_WORLD_TEXTURE, Vector2.ZERO, Vector2(1280, 1240), -100)
	_add_texture_layer(world, "BattlefieldBackground", BATTLEFIELD_BACKGROUND_TEXTURE, Vector2.ZERO, Vector2(1280, 720), -90)
	_add_texture_layer(world, "TableclothDecor", TABLECLOTH_DECOR_TEXTURE, Vector2.ZERO, Vector2(1280, 720), -80)
	_add_texture_layer(world, "BattlefieldWoodPad", BATTLEFIELD_WOOD_PAD_TEXTURE, Vector2.ZERO, Vector2(1280, 720), -70)
	_add_texture_layer(world, "BattlefieldBrocade", BATTLEFIELD_BROCADE_TEXTURE, Vector2.ZERO, Vector2(1280, 720), -60)
	_build_board_section(world, "EnemyBoardSection", 0.0, true)
	_build_board_section(world, "PlayerBoardSection", WORLD_SECTION_HEIGHT, false)
	_build_collection_section(world)
	_build_enemy_avatar(world)
	_build_card_text_debug_controls()
	_assign_runtime_owner(world)
	_assign_runtime_owner(card_text_debug_panel)


func _add_texture_layer(
	parent: Control,
	node_name: String,
	texture: Texture2D,
	pos: Vector2,
	node_size: Vector2,
	depth: int
) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = node_name
	layer.texture = texture
	layer.position = pos
	layer.size = node_size
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = depth
	parent.add_child(layer)
	return layer


func _make_character_texture(region: Rect2) -> AtlasTexture:
	return _make_atlas_texture(CHARACTER_SHEET_TEXTURE, region)


func _make_atlas_texture(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	return texture


func _build_enemy_avatar(parent: Control) -> void:
	var avatar := TextureRect.new()
	avatar.name = "EnemyAvatar"
	avatar.unique_name_in_owner = true
	avatar.texture = _make_character_texture(CHARACTER_FRONT_REGION)
	avatar.position = Vector2(38, 0)
	avatar.size = CHARACTER_FRONT_REGION.size
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.z_index = 100
	parent.add_child(avatar)


func _assign_runtime_owner(node: Node) -> void:
	if node.owner == null:
		node.owner = self
	if node is BattlefieldRow:
		return
	for child: Node in node.get_children():
		_assign_runtime_owner(child)


func _build_board_section(parent: Control, section_name: String, top: float, enemy: bool) -> void:
	var section := Panel.new()
	section.name = section_name
	section.unique_name_in_owner = true
	section.position = Vector2(208, top)
	section.size = Vector2(864, WORLD_SECTION_HEIGHT)
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(section)
	var upper := BATTLEFIELD_ROW_SCENE.instantiate() as BattlefieldRow
	var upper_card_top_y := ENEMY_BACK_CARD_TOP_Y if enemy else PLAYER_FRONT_CARD_TOP_Y
	upper.name = "EnemyBackRow" if enemy else "FrontRow"
	upper.unique_name_in_owner = true
	upper.position = Vector2(
		16,
		upper_card_top_y - top - BATTLEFIELD_ROW_CONTENT_INSET_Y
	)
	upper.size = Vector2(832, 136)
	upper.custom_minimum_size = Vector2(832, 136)
	upper.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	(upper.get_node("RowLayout/RowTitleLabel") as Label).visible = false
	upper.row_title = "敌方后排" if enemy else "我方前排"
	section.add_child(upper)
	var lower := BATTLEFIELD_ROW_SCENE.instantiate() as BattlefieldRow
	var lower_card_top_y := ENEMY_FRONT_CARD_TOP_Y if enemy else PLAYER_BACK_CARD_TOP_Y
	lower.name = "EnemyFrontRow" if enemy else "BackRow"
	lower.unique_name_in_owner = true
	lower.position = Vector2(
		16,
		lower_card_top_y - top - BATTLEFIELD_ROW_CONTENT_INSET_Y
	)
	lower.size = Vector2(832, 136)
	lower.custom_minimum_size = Vector2(832, 136)
	lower.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	(lower.get_node("RowLayout/RowTitleLabel") as Label).visible = false
	lower.row_title = "敌方前排" if enemy else "我方后排"
	section.add_child(lower)
	if not enemy:
		var player_avatar := TextureButton.new()
		player_avatar.name = "PlayerAvatarButton"
		player_avatar.unique_name_in_owner = true
		player_avatar.texture_normal = _make_character_texture(CHARACTER_BACK_REGION)
		player_avatar.position = Vector2(897, 160)
		player_avatar.size = CHARACTER_BACK_REGION.size
		player_avatar.ignore_texture_size = true
		player_avatar.stretch_mode = TextureButton.STRETCH_KEEP
		player_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		player_avatar.tooltip_text = "切换敌我战场与收藏视角"
		player_avatar.z_index = 100
		section.add_child(player_avatar)
		var phase := _make_label("准备阶段", Vector2(742, 76), Vector2(116, 24))
		phase.name = "PhaseLabel"
		phase.unique_name_in_owner = true
		phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		phase.visible = false
		section.add_child(phase)
		var drag_button := _make_button("DragModeButton", "拖拽：优先随从", Vector2(704, 108), Vector2(150, 34), true)
		drag_button.toggle_mode = true
		drag_button.button_pressed = true
		drag_button.visible = false
		section.add_child(drag_button)


func _build_collection_section(parent: Control) -> void:
	var section := Panel.new()
	section.name = "CollectionSection"
	section.unique_name_in_owner = true
	section.position = Vector2(0, WORLD_SECTION_HEIGHT * 2.0)
	section.size = Vector2(1280, WORLD_SECTION_HEIGHT)
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(section)
	var filter := Control.new()
	filter.name = "CollectionFilterLayer"
	filter.position = Vector2.ZERO
	filter.size = Vector2(1280, 360)
	filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.z_index = 200
	section.add_child(filter)
	var search_art := _add_texture_layer(
		filter,
		"SearchFilterArt",
		_make_atlas_texture(COLLECTION_FILTER_ICONS_TEXTURE, SEARCH_FILTER_ART_REGION),
		SEARCH_FILTER_POSITION,
		SEARCH_FILTER_ART_REGION.size,
		0
	)
	search_art.unique_name_in_owner = true
	var edit := LineEdit.new()
	edit.name = "SearchEdit"
	edit.unique_name_in_owner = true
	edit.position = SEARCH_FILTER_POSITION + SEARCH_TEXT_HOTSPOT_REGION.position
	edit.size = SEARCH_TEXT_HOTSPOT_REGION.size
	edit.placeholder_text = "搜索"
	edit.add_theme_font_size_override("font_size", 8)
	edit.z_index = 10
	for style_name: StringName in [&"normal", &"focus", &"read_only"]:
		edit.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	# LineEdit 的主题最小高度比像素图搜索框高；纵向压缩后，绘制和命中范围都严格落在图集框内。
	edit.scale = Vector2(1.0, SEARCH_TEXT_HOTSPOT_REGION.size.y / edit.get_combined_minimum_size().y)
	filter.add_child(edit)
	var search := _make_button(
		"SearchButton",
		"",
		SEARCH_FILTER_POSITION + SEARCH_ICON_HOTSPOT_REGION.position,
		SEARCH_ICON_HOTSPOT_REGION.size,
		true
	)
	search.flat = true
	search.tooltip_text = "执行收藏搜索"
	search.z_index = 11
	filter.add_child(search)
	var clear := _make_button(
		"ClearSearchButton",
		"X",
		SEARCH_FILTER_POSITION + SEARCH_CLEAR_HOTSPOT_REGION.position,
		SEARCH_CLEAR_HOTSPOT_REGION.size,
		true
	)
	clear.flat = true
	clear.visible = false
	clear.z_index = 11
	# 有文字的 Button 同样会受主题最小高度影响，沿用搜索框的图集高度。
	clear.scale = Vector2(1.0, SEARCH_CLEAR_HOTSPOT_REGION.size.y / clear.get_combined_minimum_size().y)
	filter.add_child(clear)
	var rarities := Control.new()
	rarities.name = "RarityButtons"
	rarities.unique_name_in_owner = true
	rarities.position = RARITY_FILTER_POSITION
	rarities.size = Vector2(111, 16)
	rarities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.add_child(rarities)
	var elements := Control.new()
	elements.name = "ElementButtons"
	elements.unique_name_in_owner = true
	elements.position = ELEMENT_FILTER_POSITION
	elements.size = Vector2(111, 16)
	elements.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.add_child(elements)
	filter.add_child(_make_button("CardArtTunerButton", "卡面调整器", Vector2(1110, 284), Vector2(150, 32), true))
	var feedback := _make_label("收藏准备就绪", Vector2(35, 12), Vector2(170, 48))
	feedback.name = "FeedbackLabel"
	feedback.unique_name_in_owner = true
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filter.add_child(feedback)
	var book := Panel.new()
	book.name = "BookPanel"
	book.unique_name_in_owner = true
	book.position = Vector2(204, -8)
	book.size = Vector2(872, 367)
	book.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	book.gui_input.connect(_on_book_gui_input)
	section.add_child(book)
	_add_texture_layer(
		book,
		"BookBaseArt",
		COLLECTION_BOOK_BASE_TEXTURE,
		Vector2.ZERO,
		Vector2(872, 359),
		-50
	)
	var tabs := Control.new()
	tabs.name = "ActionFilterTabs"
	tabs.unique_name_in_owner = true
	tabs.position = ACTION_TABS_POSITION
	tabs.size = Vector2(202, 74)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.z_index = -48
	book.add_child(tabs)
	var type_tabs := Control.new()
	type_tabs.name = "CardTypeFilterTabs"
	type_tabs.unique_name_in_owner = true
	type_tabs.position = CARD_TYPE_TABS_POSITION
	type_tabs.size = CARD_TYPE_TABS_TEXTURE.get_size()
	type_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_tabs.z_index = -48
	book.add_child(type_tabs)
	var bookmark := TextureButton.new()
	bookmark.name = "RecentBookmarkButton"
	bookmark.unique_name_in_owner = true
	bookmark.texture_normal = RECENT_CARDS_BOOKMARK_TEXTURE
	bookmark.position = book.position + RECENT_BOOKMARK_POSITION
	bookmark.size = RECENT_CARDS_BOOKMARK_TEXTURE.get_size()
	bookmark.ignore_texture_size = true
	bookmark.stretch_mode = TextureButton.STRETCH_KEEP
	bookmark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bookmark.tooltip_text = "最近使用的卡牌"
	bookmark.pivot_offset = bookmark.size * 0.5
	bookmark.z_index = -48
	section.add_child(bookmark)
	var regular_pages := Control.new()
	regular_pages.name = "RegularPagesArt"
	regular_pages.unique_name_in_owner = true
	regular_pages.size = book.size
	regular_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	regular_pages.z_index = -47
	book.add_child(regular_pages)
	var regular_left := _add_texture_layer(
		regular_pages,
		"RegularLeftPageArt",
		COLLECTION_LEFT_PAGE_FRONT_TEXTURE,
		COLLECTION_LEFT_PAGE_POSITION,
		COLLECTION_PAGE_SIZE,
		0
	)
	regular_left.unique_name_in_owner = true
	var regular_right := _add_texture_layer(
		regular_pages,
		"RegularRightPageArt",
		COLLECTION_RIGHT_PAGE_FRONT_TEXTURE,
		COLLECTION_RIGHT_PAGE_POSITION,
		COLLECTION_PAGE_SIZE,
		0
	)
	regular_right.unique_name_in_owner = true
	var recent_left := _add_texture_layer(
		book,
		"RecentLeftPageArt",
		RECENT_CARDS_LEFT_PAGE_TEXTURE,
		COLLECTION_LEFT_PAGE_POSITION,
		COLLECTION_PAGE_SIZE,
		-47
	)
	recent_left.unique_name_in_owner = true
	recent_left.visible = false
	var recent_right := _add_texture_layer(
		book,
		"RecentRightPageArt",
		RECENT_CARDS_RIGHT_PAGE_TEXTURE,
		COLLECTION_RIGHT_PAGE_POSITION,
		COLLECTION_PAGE_SIZE,
		-47
	)
	recent_right.unique_name_in_owner = true
	recent_right.visible = false
	var left_number := _make_label("1", LEFT_PAGE_NUMBER_POSITION, PAGE_NUMBER_SIZE)
	left_number.name = "LeftPageNumberLabel"
	left_number.unique_name_in_owner = true
	left_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_page_number_font(left_number)
	left_number.z_index = 25
	book.add_child(left_number)
	var right_number := _make_label("2", RIGHT_PAGE_NUMBER_POSITION, PAGE_NUMBER_SIZE)
	right_number.name = "RightPageNumberLabel"
	right_number.unique_name_in_owner = true
	right_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_page_number_font(right_number)
	right_number.z_index = 25
	book.add_child(right_number)
	var left_edge := _make_button("LeftEdgeButton", "", Vector2(0, 25), Vector2(48, 318), true)
	left_edge.flat = true
	left_edge.tooltip_text = "上一页"
	left_edge.z_index = 30
	book.add_child(left_edge)
	var right_edge := _make_button("RightEdgeButton", "", Vector2(824, 25), Vector2(48, 318), true)
	right_edge.flat = true
	right_edge.tooltip_text = "下一页"
	right_edge.z_index = 30
	book.add_child(right_edge)
	var viewport := Control.new()
	viewport.name = "CollectionViewport"
	viewport.unique_name_in_owner = true
	viewport.position = COLLECTION_VIEWPORT_POSITION
	viewport.size = Vector2(822, 306)
	book.add_child(viewport)
	var card_row := Control.new()
	card_row.name = "CollectionCardRow"
	card_row.unique_name_in_owner = true
	card_row.size = viewport.size
	viewport.add_child(card_row)
	var drop_zone := Control.new()
	drop_zone.name = "CollectionDropZone"
	drop_zone.unique_name_in_owner = true
	drop_zone.position = viewport.position
	drop_zone.size = viewport.size
	drop_zone.z_index = 20
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.set_script(COLLECTION_DROP_ZONE_SCRIPT)
	book.add_child(drop_zone)
	var badge := Panel.new()
	badge.name = "BadgePanel"
	badge.unique_name_in_owner = true
	badge.position = Vector2(35, 67)
	badge.size = Vector2(176, 281)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = -49
	section.add_child(badge)
	var badge_text := _make_label("强化徽章（预留）", Vector2(12, 12), Vector2(152, 32))
	badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.add_child(badge_text)
	# Control 的命中顺序除了 z_index 也受同层子节点顺序影响；
	# 把筛选层移动到最后，确保搜索按钮始终在书页和卡牌之上。
	section.move_child(filter, section.get_child_count() - 1)


func _make_button(node_name: String, text_value: String, pos: Vector2, node_size: Vector2, unique: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = unique
	button.text = text_value
	button.position = pos
	button.size = node_size
	return button


func _make_label(text_value: String, pos: Vector2, node_size: Vector2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = node_size
	return label


func _build_card_text_debug_controls() -> void:
	card_text_debug_panel = Panel.new()
	card_text_debug_panel.name = "CardTextDebugPanel"
	card_text_debug_panel.unique_name_in_owner = true
	card_text_debug_panel.position = Vector2(8, 534)
	card_text_debug_panel.size = Vector2(210, 178)
	card_text_debug_panel.z_index = 4000
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.08, 0.92)
	panel_style.border_color = Color(0.48, 0.38, 0.24, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	card_text_debug_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(card_text_debug_panel)
	var title := _make_label("卡牌文字调试", Vector2(10, 5), Vector2(190, 20))
	title.add_theme_font_size_override("font_size", 13)
	card_text_debug_panel.add_child(title)
	card_text_debug_panel.add_child(_make_label("效果行距", Vector2(10, 37), Vector2(64, 20)))
	effect_line_spacing_spin_box = SpinBox.new()
	effect_line_spacing_spin_box.name = "EffectLineSpacingSpinBox"
	effect_line_spacing_spin_box.unique_name_in_owner = true
	effect_line_spacing_spin_box.position = Vector2(104, 32)
	effect_line_spacing_spin_box.size = Vector2(96, 28)
	effect_line_spacing_spin_box.min_value = -4
	effect_line_spacing_spin_box.max_value = 8
	effect_line_spacing_spin_box.step = 1
	card_text_debug_panel.add_child(effect_line_spacing_spin_box)
	card_text_debug_panel.add_child(_make_label("效果文字颜色", Vector2(10, 73), Vector2(88, 20)))
	effect_color_button = ColorPickerButton.new()
	effect_color_button.name = "EffectColorButton"
	effect_color_button.unique_name_in_owner = true
	effect_color_button.position = Vector2(104, 68)
	effect_color_button.size = Vector2(96, 28)
	effect_color_button.color = Color.WHITE
	effect_color_button.edit_alpha = true
	card_text_debug_panel.add_child(effect_color_button)
	effect_text_toggle = _make_button("EffectTextToggle", "显示效果文字", Vector2(10, 104), Vector2(92, 28), true)
	effect_text_toggle.toggle_mode = true
	card_text_debug_panel.add_child(effect_text_toggle)
	text_debug_reset_button = _make_button("TextDebugResetButton", "恢复默认", Vector2(108, 104), Vector2(92, 28), true)
	card_text_debug_panel.add_child(text_debug_reset_button)


func _connect_card_text_debug_controls() -> void:
	# Main 可能在同一测试进程内多次实例化；先清除上一实例留下的静态调试状态。
	CardView.debug_effect_line_spacing = int(effect_line_spacing_spin_box.value)
	CardView.debug_effect_text_color = effect_color_button.color
	CardView.debug_force_effect_text = effect_text_toggle.button_pressed
	effect_line_spacing_spin_box.value_changed.connect(_on_effect_line_spacing_changed)
	effect_color_button.color_changed.connect(_on_effect_color_changed)
	effect_text_toggle.toggled.connect(_on_effect_text_toggled)
	text_debug_reset_button.pressed.connect(_reset_card_text_debug)
	_refresh_existing_card_text_style()


func _on_effect_line_spacing_changed(value: float) -> void:
	CardView.debug_effect_line_spacing = int(value)
	_refresh_existing_card_text_style()


func _on_effect_color_changed(color: Color) -> void:
	CardView.debug_effect_text_color = color
	_refresh_existing_card_text_style()


func _on_effect_text_toggled(show_effect: bool) -> void:
	CardView.debug_force_effect_text = show_effect
	_refresh_existing_card_text_style()


func _reset_card_text_debug() -> void:
	CardView.debug_effect_line_spacing = 0
	CardView.debug_effect_text_color = Color.WHITE
	CardView.debug_force_effect_text = false
	effect_line_spacing_spin_box.set_value_no_signal(0)
	effect_color_button.color = Color.WHITE
	effect_text_toggle.set_pressed_no_signal(false)
	_refresh_existing_card_text_style()


func _refresh_existing_card_text_style() -> void:
	for node: Node in get_tree().get_nodes_in_group("card_views"):
		if node is CardView:
			(node as CardView).refresh_text_debug_style()


# --- 场景初始化、阶段与全局状态 ---
func _ready() -> void:
	if not has_node("WorldContent"):
		_build_scene_structure()
	_bind_scene_nodes()
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()
	card_art_tuner_button.pressed.connect(_on_card_art_tuner_button_pressed)
	_connect_card_text_debug_controls()
	drag_mode_button.toggled.connect(_on_drag_mode_toggled)
	player_avatar_button.pressed.connect(_on_player_avatar_button_pressed)
	search_edit.text_changed.connect(_on_search_text_changed)
	search_edit.text_submitted.connect(func(_text: String) -> void: apply_search())
	search_button.pressed.connect(apply_search)
	clear_search_button.pressed.connect(clear_search)
	left_edge_button.pressed.connect(func() -> void: turn_collection_page(current_collection_page - 1, &"edge"))
	right_edge_button.pressed.connect(func() -> void: turn_collection_page(current_collection_page + 1, &"edge"))
	recent_bookmark_button.pressed.connect(toggle_recent_bookmark)
	_build_filter_buttons()
	collection_drop_zone.connect("card_dropped", _on_collection_card_dropped)
	_connect_board_rows()
	_build_collection_cards()
	_select_first_collection_card()
	_build_enemy_test_squads()
	world_content.position.y = -WORLD_SECTION_HEIGHT
	current_world_view = WorldView.COLLECTION
	_update_phase_label()
	_on_drag_mode_toggled(drag_mode_button.button_pressed)


func _bind_scene_nodes() -> void:
	phase_label = get_node("%PhaseLabel") as Label
	play_area_label = get_node("%FeedbackLabel") as Label
	world_content = get_node("%WorldContent") as Control
	front_row = get_node("%FrontRow") as BattlefieldRow
	back_row = get_node("%BackRow") as BattlefieldRow
	enemy_back_row = get_node("%EnemyBackRow") as BattlefieldRow
	enemy_front_row = get_node("%EnemyFrontRow") as BattlefieldRow
	enemy_avatar = get_node("%EnemyAvatar") as TextureRect
	collection_viewport = get_node("%CollectionViewport") as Control
	collection_card_row = get_node("%CollectionCardRow") as Control
	collection_drop_zone = get_node("%CollectionDropZone") as Control
	card_art_tuner_button = get_node("%CardArtTunerButton") as Button
	drag_mode_button = get_node("%DragModeButton") as Button
	player_avatar_button = get_node("%PlayerAvatarButton") as TextureButton
	search_edit = get_node("%SearchEdit") as LineEdit
	search_button = get_node("%SearchButton") as Button
	clear_search_button = get_node("%ClearSearchButton") as Button
	search_filter_art = get_node("%SearchFilterArt") as TextureRect
	rarity_buttons = get_node("%RarityButtons") as Control
	card_type_filter_tabs = get_node("%CardTypeFilterTabs") as Control
	element_buttons = get_node("%ElementButtons") as Control
	action_filter_tabs = get_node("%ActionFilterTabs") as Control
	left_edge_button = get_node("%LeftEdgeButton") as Button
	right_edge_button = get_node("%RightEdgeButton") as Button
	left_page_number_label = get_node("%LeftPageNumberLabel") as Label
	right_page_number_label = get_node("%RightPageNumberLabel") as Label
	recent_bookmark_button = get_node("%RecentBookmarkButton") as TextureButton
	regular_pages_art = get_node("%RegularPagesArt") as Control
	regular_left_page_art = get_node("%RegularLeftPageArt") as TextureRect
	regular_right_page_art = get_node("%RegularRightPageArt") as TextureRect
	recent_left_page_art = get_node("%RecentLeftPageArt") as TextureRect
	recent_right_page_art = get_node("%RecentRightPageArt") as TextureRect
	card_text_debug_panel = get_node("%CardTextDebugPanel") as Panel
	effect_line_spacing_spin_box = get_node("%EffectLineSpacingSpinBox") as SpinBox
	effect_color_button = get_node("%EffectColorButton") as ColorPickerButton
	effect_text_toggle = get_node("%EffectTextToggle") as Button
	text_debug_reset_button = get_node("%TextDebugResetButton") as Button


func _on_drag_mode_toggled(prefer_minion: bool) -> void:
	drag_mode_button.text = (
		"拖拽：优先随从" if prefer_minion else "拖拽：优先小队"
	)
	for row: BattlefieldRow in [front_row, back_row]:
		row.set_prefer_minion(prefer_minion)


func _on_player_avatar_button_pressed() -> void:
	set_world_view(WorldView.BATTLEFIELDS if current_world_view == WorldView.COLLECTION else WorldView.COLLECTION)


func set_world_view(view: WorldView, animate: bool = true) -> void:
	current_world_view = view
	player_avatar_button.texture_normal = _make_character_texture(
		CHARACTER_FRONT_REGION if view == WorldView.COLLECTION else CHARACTER_BACK_REGION
	)
	var target_y := -WORLD_SECTION_HEIGHT if view == WorldView.COLLECTION else 0.0
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	if not animate or not is_inside_tree():
		world_content.position.y = target_y
		return
	_view_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_view_tween.tween_property(world_content, "position:y", target_y, VIEW_TWEEN_DURATION)


func is_view_transitioning() -> bool:
	return _view_tween != null and _view_tween.is_valid() and _view_tween.is_running()


func _build_enemy_test_squads() -> void:
	if collection_cards.size() < 6:
		return
	var back_cards: Array[CardData] = [collection_cards[1], collection_cards[2]]
	var front_cards: Array[CardData] = [collection_cards[4], collection_cards[5]]
	enemy_back_row.add_squad(SquadData.from_cards(back_cards, SquadData.TwoCardLayout.COMPACT), 0)
	enemy_front_row.add_squad(SquadData.from_cards(front_cards, SquadData.TwoCardLayout.EXPANDED), 0)
	enemy_back_row.set_drag_enabled(false)
	enemy_front_row.set_drag_enabled(false)


func _build_filter_buttons() -> void:
	for child: Node in rarity_buttons.get_children():
		child.queue_free()
	for child: Node in card_type_filter_tabs.get_children():
		child.queue_free()
	for child: Node in element_buttons.get_children():
		child.queue_free()
	for child: Node in action_filter_tabs.get_children():
		child.queue_free()
	for rarity: int in CardData.Rarity.size():
		var region := RARITY_FILTER_REGIONS[rarity]
		var button := _create_atlas_filter_button(
			COLLECTION_FILTER_ICONS_TEXTURE,
			region,
			"稀有度 %s" % ["I", "II", "III", "IV", "V"][rarity]
		)
		button.position = region.position - RARITY_FILTER_REGIONS[0].position
		button.toggle_mode = true
		button.button_pressed = active_rarity_filters.has(rarity)
		_add_filter_selected_mark(button)
		button.pressed.connect(_on_rarity_button_pressed.bind(rarity))
		rarity_buttons.add_child(button)
	for visual_index: int in ELEMENT_FILTER_REGIONS.size():
		var element_type: int = ELEMENT_FILTER_TYPES[visual_index]
		var region := ELEMENT_FILTER_REGIONS[visual_index]
		var button := _create_atlas_filter_button(
			COLLECTION_FILTER_ICONS_TEXTURE,
			region,
			"包含%s符文" % ELEMENT_FILTER_NAMES[visual_index]
		)
		button.position = region.position - ELEMENT_FILTER_REGIONS[0].position
		button.toggle_mode = true
		button.button_pressed = active_element_filters.has(element_type)
		_add_filter_selected_mark(button)
		button.pressed.connect(_on_element_button_pressed.bind(element_type))
		element_buttons.add_child(button)
	for visual_index: int in CARD_TYPE_FILTER_REGIONS.size():
		var card_type: int = CARD_TYPE_FILTER_TYPES[visual_index]
		var region := CARD_TYPE_FILTER_REGIONS[visual_index]
		var button := _create_atlas_filter_button(
			CARD_TYPE_TABS_TEXTURE,
			region,
			"卡牌种类：%s" % CARD_TYPE_FILTER_NAMES[visual_index]
		)
		button.name = "CardTypeTab%d" % visual_index
		button.position = Vector2(region.position.x, CARD_TYPE_TAB_REST_Y)
		button.toggle_mode = true
		button.button_pressed = active_card_type_filters.has(card_type)
		button.pressed.connect(_on_card_type_filter_pressed.bind(card_type))
		card_type_filter_tabs.add_child(button)
	for action_type: int in CardData.ActionType.size():
		var tab_root := Control.new()
		tab_root.name = "ActionTab%d" % action_type
		tab_root.position = Vector2(action_type * ACTION_TAB_STEP_X, ACTION_TAB_REST_Y)
		tab_root.size = ACTION_TAB_REGION.size
		tab_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_filter_tabs.add_child(tab_root)
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = _make_atlas_texture(ACTION_TABS_TEXTURE, ACTION_TAB_REGION)
		art.size = ACTION_TAB_REGION.size
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_root.add_child(art)
		var action_icon := TextureRect.new()
		action_icon.name = "ActionIcon"
		action_icon.texture = ACTION_FILTER_TEXTURES[action_type]
		action_icon.position = ACTION_TAB_ICON_POSITION
		action_icon.size = Vector2(16, 16)
		action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		action_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		action_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_root.add_child(action_icon)
		var hotspot := Button.new()
		hotspot.name = "Hotspot"
		hotspot.size = Vector2(ACTION_TAB_REGION.size.x, 28)
		hotspot.flat = true
		hotspot.toggle_mode = true
		hotspot.button_pressed = active_action_filters.has(action_type)
		hotspot.tooltip_text = "行动方式：%s" % ACTION_FILTER_NAMES[action_type]
		hotspot.pressed.connect(_on_action_filter_pressed.bind(action_type))
		tab_root.add_child(hotspot)
	_update_card_type_tab_positions(false)
	_update_action_tab_positions(false)
	_update_filter_selected_marks()


func _create_atlas_filter_button(
	atlas: Texture2D,
	region: Rect2,
	tooltip: String
) -> TextureButton:
	# 同一 TextureButton 既显示图集裁片又负责点击，视觉与命中范围天然一致。
	var button := TextureButton.new()
	button.texture_normal = _make_atlas_texture(atlas, region)
	button.size = region.size
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.tooltip_text = tooltip
	return button


func _add_filter_selected_mark(button: BaseButton) -> void:
	var mark := Label.new()
	mark.name = "SelectedMark"
	mark.position = Vector2(7, -5)
	mark.size = Vector2(12, 12)
	mark.text = "✓"
	mark.add_theme_color_override("font_color", Color("fff1a8"))
	mark.add_theme_color_override("font_shadow_color", Color("3b1b14"))
	mark.add_theme_constant_override("shadow_offset_x", 1)
	mark.add_theme_constant_override("shadow_offset_y", 1)
	mark.add_theme_font_size_override("font_size", 10)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.z_index = 5
	button.add_child(mark)


func _update_filter_selected_marks() -> void:
	for container: Control in [rarity_buttons, element_buttons]:
		for child: Node in container.get_children():
			var button := child as BaseButton
			if button == null or not button.has_node("SelectedMark"):
				continue
			(button.get_node("SelectedMark") as Label).visible = button.button_pressed


func _update_action_tab_positions(animate: bool = true) -> void:
	if _action_tab_tween != null and _action_tab_tween.is_valid():
		_action_tab_tween.kill()
	var selected_flags: Array[bool] = []
	for action_type: int in action_filter_tabs.get_child_count():
		var tab_root := action_filter_tabs.get_child(action_type) as Control
		var selected := active_action_filters.has(action_type)
		selected_flags.append(selected)
		tab_root.z_index = 0
		if not animate:
			tab_root.position.y = ACTION_TAB_SELECTED_Y if selected else ACTION_TAB_REST_Y
	if animate:
		_action_tab_tween = _create_tab_overshoot_tween(
			action_filter_tabs,
			selected_flags,
			ACTION_TAB_REST_Y,
			ACTION_TAB_SELECTED_Y
		)


func _update_card_type_tab_positions(animate: bool = true) -> void:
	if _card_type_tab_tween != null and _card_type_tab_tween.is_valid():
		_card_type_tab_tween.kill()
	var selected_flags: Array[bool] = []
	for visual_index: int in card_type_filter_tabs.get_child_count():
		var selected := active_card_type_filters.has(CARD_TYPE_FILTER_TYPES[visual_index])
		selected_flags.append(selected)
		if not animate:
			var tab := card_type_filter_tabs.get_child(visual_index) as Control
			tab.position.y = CARD_TYPE_TAB_SELECTED_Y if selected else CARD_TYPE_TAB_REST_Y
	if animate:
		_card_type_tab_tween = _create_tab_overshoot_tween(
			card_type_filter_tabs,
			selected_flags,
			CARD_TYPE_TAB_REST_Y,
			CARD_TYPE_TAB_SELECTED_Y
		)


func _create_tab_overshoot_tween(
	container: Control,
	selected_flags: Array[bool],
	rest_y: float,
	selected_y: float
) -> Tween:
	var moving_tabs: Array[Control] = []
	var starts: Array[float] = []
	var overshoots: Array[float] = []
	var targets: Array[float] = []
	for index: int in container.get_child_count():
		var tab := container.get_child(index) as Control
		var selected := selected_flags[index]
		var target_y := selected_y if selected else rest_y
		var overshoot_direction := -1.0 if selected else 1.0
		var overshoot_y := target_y + overshoot_direction * TAB_OVERSHOOT_PIXELS
		tab.set_meta("tab_overshoot_target_y", overshoot_y)
		# 只补间状态真正发生变化的标签。未选中的兄弟标签若也进入
		# overshoot，会先下沉再回原位，看起来就像整组无故抖动。
		if is_equal_approx(tab.position.y, target_y):
			continue
		moving_tabs.append(tab)
		starts.append(tab.position.y)
		targets.append(target_y)
		overshoots.append(overshoot_y)
	var tween := create_tween()
	tween.tween_method(
		_apply_tab_overshoot_progress.bind(moving_tabs, starts, overshoots, targets),
		0.0,
		1.0,
		ACTION_TAB_TWEEN_DURATION
	)
	return tween


func _apply_tab_overshoot_progress(
	progress: float,
	moving_tabs: Array[Control],
	starts: Array[float],
	overshoots: Array[float],
	targets: Array[float]
) -> void:
	var first_phase_ratio := TAB_OVERSHOOT_DURATION / ACTION_TAB_TWEEN_DURATION
	for index: int in moving_tabs.size():
		var tab := moving_tabs[index]
		if not is_instance_valid(tab):
			continue
		if progress <= first_phase_ratio:
			var outward_progress := smoothstep(0.0, first_phase_ratio, progress)
			tab.position.y = lerpf(starts[index], overshoots[index], outward_progress)
		else:
			var settle_progress := smoothstep(first_phase_ratio, 1.0, progress)
			tab.position.y = lerpf(overshoots[index], targets[index], settle_progress)


func is_action_tab_transitioning() -> bool:
	return (
		_action_tab_tween != null
		and _action_tab_tween.is_valid()
		and _action_tab_tween.is_running()
	)


func is_card_type_tab_transitioning() -> bool:
	return (
		_card_type_tab_tween != null
		and _card_type_tab_tween.is_valid()
		and _card_type_tab_tween.is_running()
	)


func _on_rarity_button_pressed(rarity: int) -> void:
	toggle_rarity_filter(rarity)


func _on_element_button_pressed(element_type: int) -> void:
	toggle_element_filter(element_type)


func _on_card_type_filter_pressed(card_type: int) -> void:
	toggle_card_type_filter(card_type)


func _on_action_filter_pressed(action_type: int) -> void:
	toggle_action_filter(action_type)


func _toggle_single_filter(active_filters: Array[int], value: int) -> void:
	if active_filters.size() == 1 and active_filters[0] == value:
		active_filters.clear()
	else:
		active_filters.assign([value])


func toggle_action_filter(action_type: int) -> void:
	_toggle_single_filter(active_action_filters, action_type)
	for tab_index: int in action_filter_tabs.get_child_count():
		var hotspot := action_filter_tabs.get_child(tab_index).get_node("Hotspot") as Button
		hotspot.button_pressed = active_action_filters.has(tab_index)
	current_collection_page = 0
	_update_action_tab_positions()
	_build_collection_cards()


func toggle_card_type_filter(card_type: int) -> void:
	_toggle_single_filter(active_card_type_filters, card_type)
	for visual_index: int in card_type_filter_tabs.get_child_count():
		var button := card_type_filter_tabs.get_child(visual_index) as BaseButton
		button.button_pressed = active_card_type_filters.has(
			CARD_TYPE_FILTER_TYPES[visual_index]
		)
	current_collection_page = 0
	_update_card_type_tab_positions()
	_build_collection_cards()


func toggle_rarity_filter(rarity: int) -> void:
	_toggle_single_filter(active_rarity_filters, rarity)
	for rarity_index: int in rarity_buttons.get_child_count():
		(rarity_buttons.get_child(rarity_index) as BaseButton).button_pressed = (
			active_rarity_filters.has(rarity_index)
		)
	current_collection_page = 0
	_update_filter_selected_marks()
	_build_collection_cards()


func toggle_element_filter(element_type: int) -> void:
	if active_element_filters.has(element_type):
		active_element_filters.erase(element_type)
	else:
		active_element_filters.append(element_type)
	var visual_index := ELEMENT_FILTER_TYPES.find(element_type)
	if visual_index >= 0 and visual_index < element_buttons.get_child_count():
		(element_buttons.get_child(visual_index) as BaseButton).button_pressed = active_element_filters.has(element_type)
	current_collection_page = 0
	_update_filter_selected_marks()
	_build_collection_cards()


func apply_search() -> void:
	_on_search_text_changed(search_edit.text)


func clear_search() -> void:
	search_edit.text = ""
	_on_search_text_changed("")


func _on_search_text_changed(value: String) -> void:
	clear_search_button.visible = not value.is_empty()
	search_query = value.strip_edges().to_lower()
	current_collection_page = 0
	_build_collection_cards()


func get_filtered_collection_cards() -> Array[CardData]:
	var filtered: Array[CardData] = []
	# 先按 V→I 分组再筛选，同稀有度保留进入收藏时的先后顺序。
	# 这样 collection_cards 只负责保存所有权，不再成为玩家可编辑的位置表。
	for rarity: int in range(CardData.Rarity.V, CardData.Rarity.I - 1, -1):
		for card_data: CardData in collection_cards:
			if card_data.rarity != rarity:
				continue
			if not active_card_type_filters.is_empty() and not active_card_type_filters.has(card_data.card_type):
				continue
			if not active_rarity_filters.is_empty() and not active_rarity_filters.has(card_data.rarity):
				continue
			if not active_action_filters.is_empty() and not active_action_filters.has(card_data.action_type):
				continue
			var contains_all_selected_elements := true
			for element_type: int in active_element_filters:
				if not card_data.runes.has(element_type):
					contains_all_selected_elements = false
					break
			if not contains_all_selected_elements:
				continue
			if not search_query.is_empty():
				var searchable := "%s %s %s" % [card_data.display_name, card_data.get_race_name(), card_data.effect_text]
				if not searchable.to_lower().contains(search_query):
					continue
			filtered.append(card_data)
	return filtered


func get_displayed_collection_cards() -> Array[CardData]:
	if collection_bookmark_active:
		return recently_returned_cards.duplicate()
	return get_filtered_collection_cards()


func get_collection_physical_page_count() -> int:
	var card_count := get_displayed_collection_cards().size()
	if card_count == 0:
		return 1
	return mini(ceili(float(card_count) / 6.0), COLLECTION_MAX_PHYSICAL_PAGES)


func get_collection_spread_count() -> int:
	return mini(
		COLLECTION_MAX_SPREADS,
		maxi(1, ceili(float(get_collection_physical_page_count()) / 2.0))
	)


func toggle_recent_bookmark() -> void:
	if _is_collection_drag_active():
		return
	_clear_page_turn_overlay()
	if collection_bookmark_active:
		collection_bookmark_active = false
		current_collection_page = mini(
			_regular_collection_page_before_bookmark,
			get_collection_spread_count() - 1
		)
	else:
		_regular_collection_page_before_bookmark = current_collection_page
		collection_bookmark_active = true
		current_collection_page = 0
	_build_collection_cards()
	_animate_recent_bookmark_to_mode()


func _update_collection_book_mode_visuals() -> void:
	regular_pages_art.visible = not collection_bookmark_active
	recent_left_page_art.visible = collection_bookmark_active
	recent_right_page_art.visible = collection_bookmark_active
	# 普通收藏：书皮 < 书签 < 普通书页；最近使用：书皮 < 最近书页 < 书签。
	recent_bookmark_button.z_index = 80 if collection_bookmark_active else -48
	_update_page_number_labels()


func _animate_recent_bookmark_to_mode() -> void:
	if _recent_bookmark_tween != null and _recent_bookmark_tween.is_valid():
		_recent_bookmark_tween.kill()
	var rest_position := (get_node("%BookPanel") as Control).position + RECENT_BOOKMARK_POSITION
	var target_position := (
		rest_position + RECENT_BOOKMARK_SELECTED_OFFSET
		if collection_bookmark_active
		else rest_position
	)
	var overshoot_direction := -1.0 if collection_bookmark_active else 1.0
	var overshoot_position := target_position + Vector2(overshoot_direction * TAB_OVERSHOOT_PIXELS, 0)
	_recent_bookmark_tween = create_tween()
	_recent_bookmark_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recent_bookmark_tween.tween_property(
		recent_bookmark_button,
		"position",
		overshoot_position,
		TAB_OVERSHOOT_DURATION
	)
	_recent_bookmark_tween.tween_property(
		recent_bookmark_button,
		"position",
		target_position,
		TAB_SETTLE_DURATION
	)


func is_recent_bookmark_transitioning() -> bool:
	return (
		_recent_bookmark_tween != null
		and _recent_bookmark_tween.is_valid()
		and _recent_bookmark_tween.is_running()
	)


func _update_page_number_labels() -> void:
	if collection_bookmark_active:
		# 基础数值字体只包含数字；“最近”页继续使用界面字体，避免中文缺字。
		left_page_number_label.remove_theme_font_override("font")
		right_page_number_label.remove_theme_font_override("font")
		left_page_number_label.remove_theme_font_size_override("font_size")
		right_page_number_label.remove_theme_font_size_override("font_size")
		left_page_number_label.text = "最近 1"
		right_page_number_label.text = "最近 2"
		left_page_number_label.visible = true
		right_page_number_label.visible = true
		return
	var physical_page_count := get_collection_physical_page_count()
	var left_page_number := current_collection_page * 2 + 1
	var right_page_number := left_page_number + 1
	_apply_page_number_font(left_page_number_label)
	_apply_page_number_font(right_page_number_label)
	left_page_number_label.text = str(left_page_number)
	right_page_number_label.text = str(right_page_number)
	left_page_number_label.visible = left_page_number <= physical_page_count
	right_page_number_label.visible = right_page_number <= physical_page_count


func _record_recently_returned_card(card_data: CardData) -> void:
	if card_data == null:
		return
	recently_returned_cards.erase(card_data)
	recently_returned_cards.push_front(card_data)
	if recently_returned_cards.size() > RECENT_CARDS_LIMIT:
		recently_returned_cards.resize(RECENT_CARDS_LIMIT)
	_play_recent_bookmark_shake()


func _play_recent_bookmark_shake() -> void:
	if not is_instance_valid(recent_bookmark_button):
		return
	if _recent_bookmark_shake_tween != null and _recent_bookmark_shake_tween.is_valid():
		_recent_bookmark_shake_tween.kill()
	recent_bookmark_button.rotation = 0.0
	var angle := deg_to_rad(RECENT_BOOKMARK_SHAKE_ANGLE)
	_recent_bookmark_shake_tween = create_tween()
	_recent_bookmark_shake_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_recent_bookmark_shake_tween.tween_property(
		recent_bookmark_button,
		"rotation",
		-angle,
		RECENT_BOOKMARK_SHAKE_STEP_DURATION
	)
	_recent_bookmark_shake_tween.tween_property(
		recent_bookmark_button,
		"rotation",
		angle,
		RECENT_BOOKMARK_SHAKE_STEP_DURATION * 2.0
	)
	_recent_bookmark_shake_tween.tween_property(
		recent_bookmark_button,
		"rotation",
		0.0,
		RECENT_BOOKMARK_SHAKE_STEP_DURATION
	)


func is_recent_bookmark_shaking() -> bool:
	return (
		_recent_bookmark_shake_tween != null
		and _recent_bookmark_shake_tween.is_valid()
		and _recent_bookmark_shake_tween.is_running()
	)


func turn_collection_page(page: int, method: StringName = &"direct") -> bool:
	if _is_collection_drag_active() or collection_bookmark_active or is_page_turning():
		return false
	var target := clampi(page, 0, get_collection_spread_count() - 1)
	if target == current_collection_page:
		return false
	var previous_page := current_collection_page
	var previous_filtered_cards := get_filtered_collection_cards()
	_clear_page_turn_overlay()
	current_collection_page = target
	last_page_turn_method = method
	_build_collection_cards()
	_play_collection_page_turn(
		previous_page,
		target,
		previous_filtered_cards
	)
	return true


func _play_collection_page_turn(
	previous_page: int,
	target_page: int,
	previous_filtered_cards: Array[CardData]
) -> void:
	var turns_forward := target_page > previous_page
	var moving_side := 1 if turns_forward else 0
	var static_side := 0 if turns_forward else 1
	var target_side := 0 if turns_forward else 1
	var target_fixed_side := moving_side
	var target_filtered_cards := get_filtered_collection_cards()
	var book := get_node("%BookPanel") as Control
	var overlay := Control.new()
	overlay.name = "PageTurnOverlay"
	overlay.size = book.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 60
	overlay.set_meta("direction", 1 if turns_forward else -1)
	book.add_child(overlay)
	_page_turn_overlay = overlay

	var static_page := _create_page_turn_snapshot(
		static_side,
		previous_page,
		previous_filtered_cards,
		_get_regular_page_texture(static_side),
		true
	)
	static_page.name = "StaticOldPage"
	static_page.z_index = 0
	overlay.add_child(static_page)
	var target_fixed_page := _create_page_turn_snapshot(
		target_fixed_side,
		target_page,
		target_filtered_cards,
		_get_regular_page_texture(target_fixed_side),
		true
	)
	target_fixed_page.name = "StaticTargetPage"
	target_fixed_page.z_index = 0
	overlay.add_child(target_fixed_page)
	var moving_page := _create_page_turn_snapshot(
		moving_side,
		previous_page,
		previous_filtered_cards,
		_get_regular_page_texture(moving_side),
		true
	)
	moving_page.name = "MovingPage"
	moving_page.z_index = PAGE_TURN_MOVING_Z_INDEX
	moving_page.pivot_offset = Vector2(
		0.0 if turns_forward else COLLECTION_PAGE_SIZE.x,
		COLLECTION_PAGE_SIZE.y * 0.5
	)
	_add_page_turn_free_edge(moving_page, moving_side)
	overlay.add_child(moving_page)
	# 覆盖层已经完整持有旧固定页、目标固定页和活动页之后，才能隐藏
	# 实时收藏卡层；否则向后翻页时目标右页会在整段动画中变空。
	collection_card_row.visible = false
	left_page_number_label.visible = false
	right_page_number_label.visible = false

	var shadow := ColorRect.new()
	shadow.name = "PageTurnShadow"
	shadow.position = Vector2(
		COLLECTION_RIGHT_PAGE_POSITION.x - PAGE_TURN_SHADOW_WIDTH * 0.5,
		COLLECTION_LEFT_PAGE_POSITION.y
	)
	shadow.size = Vector2(PAGE_TURN_SHADOW_WIDTH, COLLECTION_PAGE_SIZE.y)
	shadow.color = Color(0.08, 0.04, 0.02, 0.30)
	shadow.modulate.a = 0.0
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.z_index = PAGE_TURN_SHADOW_Z_INDEX
	overlay.add_child(shadow)

	_page_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_page_tween.tween_property(moving_page, "scale:x", 0.0, PAGE_TURN_HALF_DURATION)
	_page_tween.parallel().tween_property(
		moving_page,
		"scale:y",
		PAGE_TURN_MID_SCALE_Y,
		PAGE_TURN_HALF_DURATION
	)
	_page_tween.parallel().tween_property(shadow, "modulate:a", 1.0, PAGE_TURN_HALF_DURATION)
	_page_tween.tween_callback(
		_swap_page_turn_face.bind(
			moving_page,
			target_side,
			target_page,
			target_filtered_cards
		)
	)
	_page_tween.tween_property(moving_page, "scale:x", 1.0, PAGE_TURN_HALF_DURATION)
	_page_tween.parallel().tween_property(moving_page, "scale:y", 1.0, PAGE_TURN_HALF_DURATION)
	_page_tween.parallel().tween_property(shadow, "modulate:a", 0.0, PAGE_TURN_HALF_DURATION)
	_page_tween.tween_callback(_finish_page_turn_overlay)


func _get_regular_page_texture(page_side: int) -> Texture2D:
	return COLLECTION_LEFT_PAGE_FRONT_TEXTURE if page_side == 0 else COLLECTION_RIGHT_PAGE_FRONT_TEXTURE


func _create_page_turn_snapshot(
	page_side: int,
	page_index: int,
	filtered_cards: Array[CardData],
	page_texture: Texture2D,
	include_cards: bool
) -> Control:
	var page := Control.new()
	page.position = COLLECTION_LEFT_PAGE_POSITION if page_side == 0 else COLLECTION_RIGHT_PAGE_POSITION
	page.size = COLLECTION_PAGE_SIZE
	page.clip_contents = true
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var physical_page := page_index * 2 + page_side + 1
	page.set_meta("physical_page", physical_page)
	var art := TextureRect.new()
	art.name = "PageArt"
	art.texture = page_texture
	art.size = COLLECTION_PAGE_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(art)
	var card_layer := Control.new()
	card_layer.name = "CardLayer"
	card_layer.size = COLLECTION_PAGE_SIZE
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(card_layer)
	var page_number := _create_page_turn_number(page_side, physical_page, page.position)
	page_number.visible = physical_page <= get_collection_physical_page_count()
	page.add_child(page_number)
	if not include_cards:
		return page
	for side_index: int in 6:
		var filtered_index := page_index * COLLECTION_SLOTS_PER_PAGE + page_side * 6 + side_index
		if filtered_index >= filtered_cards.size():
			break
		var card_data := filtered_cards[filtered_index]
		var slot := _create_collection_card_slot(
			card_data,
			_is_card_deployed(card_data),
			false
		)
		slot.name = "TurnCard%d" % side_index
		slot.position = (
			COLLECTION_VIEWPORT_POSITION
			+ _collection_slot_position(page_side * 6 + side_index)
			- page.position
		)
		card_layer.add_child(slot)
	return page


func _create_page_turn_number(
	page_side: int,
	physical_page: int,
	page_position: Vector2
) -> Label:
	var number_position := (
		LEFT_PAGE_NUMBER_POSITION
		if page_side == 0
		else RIGHT_PAGE_NUMBER_POSITION
	)
	var label := _make_label(
		str(physical_page),
		number_position - page_position,
		PAGE_NUMBER_SIZE
	)
	label.name = "PageNumberLabel"
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT
		if page_side == 0
		else HORIZONTAL_ALIGNMENT_RIGHT
	)
	label.z_index = 30
	_apply_page_number_font(label)
	return label


func _apply_page_number_font(label: Label) -> void:
	label.add_theme_font_override("font", PAGE_NUMBER_FONT)
	label.add_theme_font_size_override("font_size", PAGE_NUMBER_FONT_SIZE)


func _swap_page_turn_face(
	moving_page: Control,
	target_side: int,
	target_page: int,
	target_filtered_cards: Array[CardData]
) -> void:
	if not is_instance_valid(moving_page):
		return
	for child: Node in moving_page.get_children():
		moving_page.remove_child(child)
		child.queue_free()
	var target_snapshot := _create_page_turn_snapshot(
		target_side,
		target_page,
		target_filtered_cards,
		_get_regular_page_texture(target_side),
		true
	)
	moving_page.set_meta("physical_page", target_snapshot.get_meta("physical_page"))
	for child: Node in target_snapshot.get_children():
		target_snapshot.remove_child(child)
		moving_page.add_child(child)
	target_snapshot.free()
	moving_page.position = (
		COLLECTION_LEFT_PAGE_POSITION
		if target_side == 0
		else COLLECTION_RIGHT_PAGE_POSITION
	)
	moving_page.pivot_offset = Vector2(
		COLLECTION_PAGE_SIZE.x if target_side == 0 else 0.0,
		COLLECTION_PAGE_SIZE.y * 0.5
	)
	moving_page.scale = Vector2(0.0, PAGE_TURN_MID_SCALE_Y)
	_add_page_turn_free_edge(moving_page, target_side)


func _add_page_turn_free_edge(page: Control, page_side: int) -> void:
	var previous_edge := page.get_node_or_null("PageFreeEdge")
	if previous_edge != null:
		page.remove_child(previous_edge)
		previous_edge.queue_free()
	var edge := Control.new()
	edge.name = "PageFreeEdge"
	edge.position = Vector2(
		0.0 if page_side == 0 else COLLECTION_PAGE_SIZE.x - PAGE_TURN_EDGE_WIDTH,
		0.0
	)
	edge.size = Vector2(PAGE_TURN_EDGE_WIDTH, COLLECTION_PAGE_SIZE.y)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.z_index = 20
	page.add_child(edge)
	var dark_edge := ColorRect.new()
	dark_edge.name = "DarkEdge"
	dark_edge.size = edge.size
	dark_edge.color = PAGE_TURN_EDGE_DARK_COLOR
	dark_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.add_child(dark_edge)
	var highlight := ColorRect.new()
	highlight.name = "EdgeHighlight"
	highlight.position.x = 1.0 if page_side == 0 else 0.0
	highlight.size = Vector2(PAGE_TURN_EDGE_WIDTH - 1.0, COLLECTION_PAGE_SIZE.y)
	highlight.color = PAGE_TURN_EDGE_LIGHT_COLOR
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.add_child(highlight)


func _clear_page_turn_overlay() -> void:
	if _page_tween != null and _page_tween.is_valid() and _page_tween.is_running():
		_page_tween.kill()
	_finish_page_turn_overlay()


func _finish_page_turn_overlay() -> void:
	if is_instance_valid(_page_turn_overlay):
		var overlay_parent := _page_turn_overlay.get_parent()
		if overlay_parent != null:
			overlay_parent.remove_child(_page_turn_overlay)
		_page_turn_overlay.queue_free()
	_page_turn_overlay = null
	_page_tween = null
	if is_instance_valid(collection_card_row):
		collection_card_row.visible = true
	if is_instance_valid(left_page_number_label) and is_instance_valid(right_page_number_label):
		_update_page_number_labels()


func is_page_turning() -> bool:
	return is_instance_valid(_page_turn_overlay)


func _on_book_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			turn_collection_page(current_collection_page - 1, &"wheel")
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			turn_collection_page(current_collection_page + 1, &"wheel")


func _is_collection_drag_active() -> bool:
	return not _click_carry_data.is_empty() or get_viewport().gui_is_dragging()


func _on_card_art_tuner_button_pressed() -> void:
	_cancel_click_carry()
	get_tree().change_scene_to_file("res://scenes/tools/CardArtTuner.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_node_ready():
		collection_drop_zone.clear_drop_preview()


func _input(event: InputEvent) -> void:
	if _click_carry_data.is_empty():
		return

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		_update_click_carry(motion_event.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_commit_click_carry(mouse_event.position)
			get_viewport().set_input_as_handled()
		elif (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_click_carry()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			_cancel_click_carry()
			get_viewport().set_input_as_handled()


func _on_start_battle_button_pressed() -> void:
	_cancel_click_carry()
	match current_phase:
		GamePhase.PREPARE:
			current_phase = GamePhase.BATTLE
		GamePhase.BATTLE:
			current_phase = GamePhase.RESULT
		GamePhase.RESULT:
			current_phase = GamePhase.PREPARE
	_update_phase_label()


func set_phase_for_test(phase: GamePhase) -> void:
	_cancel_click_carry()
	current_phase = phase
	_update_phase_label()


func _update_phase_label() -> void:
	match current_phase:
		GamePhase.PREPARE:
			phase_label.text = "准备阶段"
		GamePhase.BATTLE:
			phase_label.text = "战斗阶段"
		GamePhase.RESULT:
			phase_label.text = "结算阶段"
	set_world_view(WorldView.COLLECTION if current_phase == GamePhase.PREPARE else WorldView.BATTLEFIELDS)
	_refresh_drag_availability()


func _connect_board_rows() -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.board_slot_clicked.connect(_on_board_slot_clicked)
		row.card_dropped.connect(_on_board_card_dropped)
		row.squads_changed.connect(_on_battlefield_squads_changed)
		row.card_click_carry_requested.connect(
			_on_click_carry_requested
		)
	for enemy_row: BattlefieldRow in [enemy_back_row, enemy_front_row]:
		enemy_row.set_drag_enabled(false)


func _on_battlefield_squads_changed() -> void:
	if _battlefield_clock_check_queued:
		return
	_battlefield_clock_check_queued = true
	_reset_rune_flow_if_no_battlefield_effects.call_deferred()


func _reset_rune_flow_if_no_battlefield_effects() -> void:
	_battlefield_clock_check_queued = false
	# 跨排移动会先移除后加入；延迟到事务结束再检查，避免中途误重置。
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()


func _battlefield_has_active_rune_effects() -> bool:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			for card_view: CardView in slot.get_card_views():
				if not card_view.get_highlighted_rune_indices().is_empty():
					return true
	return false


# --- 收藏视图构建与选中状态 ---
func _build_collection_cards(
	entering_card: CardData = null,
	entry_global_position: Variant = null
) -> void:
	current_collection_page = clampi(
		current_collection_page,
		0,
		get_collection_spread_count() - 1
	)
	_update_collection_book_mode_visuals()
	for child: Node in collection_card_row.get_children():
		collection_card_row.remove_child(child)
		child.queue_free()

	var filtered_cards := get_displayed_collection_cards()
	var page_start := current_collection_page * COLLECTION_SLOTS_PER_PAGE
	var page_cards: Array[CardData] = []
	for filtered_index: int in range(page_start, mini(page_start + COLLECTION_SLOTS_PER_PAGE, filtered_cards.size())):
		page_cards.append(filtered_cards[filtered_index])
	for page_index: int in COLLECTION_SLOTS_PER_PAGE:
		var empty_slot := Control.new()
		empty_slot.custom_minimum_size = Vector2(127, 158)
		empty_slot.size = empty_slot.custom_minimum_size
		empty_slot.position = _collection_slot_position(page_index)
		empty_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_slot.set_meta("collection_index", -1)
		collection_card_row.add_child(empty_slot)
		if page_index >= page_cards.size():
			continue
		var collection_card: CardData = page_cards[page_index]
		var slot := _create_collection_card_slot(
			collection_card,
			_is_card_deployed(collection_card)
		)
		var card_view := slot.get_child(0) as CardView
		slot.position = _collection_slot_position(page_index)
		slot.set_meta("collection_index", collection_cards.find(collection_card))
		collection_card_row.remove_child(empty_slot)
		empty_slot.queue_free()
		collection_card_row.add_child(slot)
		if collection_card == entering_card and entry_global_position is Vector2:
			_animate_collection_card_entry.call_deferred(
				card_view,
				entry_global_position as Vector2
			)


func _create_collection_card_slot(
	card_data: CardData,
	is_deployed_ghost: bool = false,
	interactive: bool = true
) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = (
		Vector2(99, 136) * collection_card_scale
		+ COLLECTION_CARD_SAFE_PADDING * 2.0
	)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_meta("is_deployed_ghost", is_deployed_ghost)

	var card_view := CARD_VIEW_SCENE.instantiate() as CardView
	card_view.position = (
		COLLECTION_CARD_SAFE_PADDING
		+ Vector2(99, 136)
		* (collection_card_scale - 1.0)
		* 0.5
	)
	card_view.scale = Vector2(collection_card_scale, collection_card_scale)
	card_view.set_card_data(card_data)
	if is_deployed_ghost:
		card_view.modulate.a = CardView.COLLECTION_DRAG_GHOST_ALPHA
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_view.configure_drag_source(false)
	elif interactive:
		card_view.card_clicked.connect(_on_collection_card_clicked)
		card_view.click_carry_requested.connect(
			_on_click_carry_requested
		)
		card_view.configure_drag_source(
			current_phase == GamePhase.PREPARE,
			&"collection",
			null,
			slot
		)
	else:
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_view.configure_drag_source(false)

	slot.add_child(card_view)
	return slot


func _is_card_deployed(card_data: CardData) -> bool:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad_data := slot.get_squad_data()
			if squad_data != null and squad_data.contains(card_data):
				return true
	return false


func _collection_slot_position(index: int) -> Vector2:
	var page_side := index / 6
	var side_index := index % 6
	return Vector2(
		float(page_side * 3 + side_index % 3) * COLLECTION_SLOT_STEP.x,
		float(side_index / 3) * COLLECTION_SLOT_STEP.y
	)


func _select_first_collection_card() -> void:
	if collection_cards.is_empty():
		_select_card(null)
		return

	_select_card(collection_cards[0])


func _on_collection_card_clicked(card_data: CardData) -> void:
	selected_board_row = null
	selected_board_slot = null
	_select_card(card_data)
	_refresh_drag_availability()


func _on_board_slot_clicked(row: BattlefieldRow, slot: BoardSlot) -> void:
	selected_board_row = row
	selected_board_slot = slot
	_select_card(slot.get_last_clicked_card())
	play_area_label.text = "已选择场上卡牌：%s。准备阶段可拖动换序、换排或收回收藏" % selected_card.display_name
	_refresh_drag_availability()


# --- 点击携带状态机：创建、预览、提交或取消 ---
func _on_click_carry_requested(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> void:
	if (
		current_phase != GamePhase.PREPARE
		or not _click_carry_data.is_empty()
		or not _is_card_drag_data(drag_data)
	):
		return

	# 点击携带不会触发 Godot 的原生 DRAG_BEGIN；在这里主动完成与
	# 原生拖拽相同的战场悬停清理，避免上一张卡保持鼠标指向状态。
	for row: BattlefieldRow in [front_row, back_row]:
		row.reset_all_hover_feedback()
	_click_carry_data = drag_data.duplicate()
	_click_carry_preview = _create_click_carry_preview(
		_click_carry_data,
		pointer_global_position
	)
	_click_carry_data["drag_visual"] = _click_carry_preview
	_ghost_click_carry_source()
	_update_click_carry(pointer_global_position)


func _create_click_carry_preview(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> Control:
	var preview_root := CardView.create_drag_visual(drag_data)
	add_child(preview_root)
	preview_root.global_position = pointer_global_position
	return preview_root


func _ghost_click_carry_source() -> void:
	var source_type := _click_carry_data.get("source_type") as StringName
	if source_type == &"collection":
		var source_slot := _click_carry_data.get("source_slot") as Control
		if (
			is_instance_valid(source_slot)
			and source_slot.get_parent() == collection_card_row
		):
			source_slot.modulate.a = CardView.COLLECTION_DRAG_GHOST_ALPHA
	elif source_type == &"board":
		var source_row := (
			_click_carry_data.get("source_row") as BattlefieldRow
		)
		if is_instance_valid(source_row):
			source_row._begin_card_drag(_click_carry_data)


func _update_click_carry(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return

	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.global_position = pointer_global_position
	for row: BattlefieldRow in [front_row, back_row]:
		row.update_stack_target_feedback_global(
			pointer_global_position,
			_click_carry_data
		)

	var target_row := _find_board_row_at(pointer_global_position)
	if target_row != null:
		for row: BattlefieldRow in [front_row, back_row]:
			if row != target_row:
				row.clear_drop_preview(false)
		collection_drop_zone.clear_drop_preview()
		target_row.preview_card_drop(
			_to_row_drop_position(target_row, pointer_global_position),
			_click_carry_data
		)
	elif collection_drop_zone.get_global_rect().has_point(pointer_global_position):
		front_row.clear_drop_preview(false)
		back_row.clear_drop_preview(false)
		collection_drop_zone.preview_card_drop(
			pointer_global_position,
			_click_carry_data
		)
	else:
		_clear_click_drop_feedback(false)


func _commit_click_carry(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return

	_update_click_carry(pointer_global_position)
	var committed := false
	var target_row := _find_board_row_at(pointer_global_position)
	if target_row != null:
		var row_position := _to_row_drop_position(
			target_row,
			pointer_global_position
		)
		if (
			target_row.has_active_drop_preview()
			or target_row.preview_card_drop(row_position, _click_carry_data)
		):
			target_row.commit_card_drop(row_position, _click_carry_data)
			committed = true
	elif collection_drop_zone.get_global_rect().has_point(pointer_global_position):
		if collection_drop_zone.preview_card_drop(
			pointer_global_position,
			_click_carry_data
		):
			collection_drop_zone.commit_card_drop(
				pointer_global_position,
				_click_carry_data
			)
			committed = true

	_finish_click_carry(committed)


func _cancel_click_carry() -> void:
	if not _click_carry_data.is_empty():
		_finish_click_carry(false)


func _finish_click_carry(committed: bool) -> void:
	var drag_data := _click_carry_data
	_click_carry_data = {}
	var return_global_position: Variant = null
	if (
		not committed
		and is_instance_valid(_click_carry_preview)
	):
		var drag_visual := _click_carry_preview as CardDragPreview
		if drag_visual != null:
			return_global_position = drag_visual.get_card_global_position()
	_clear_click_drop_feedback()
	for row: BattlefieldRow in [front_row, back_row]:
		row.stop_stack_target_feedback()

	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.queue_free()
	_click_carry_preview = null

	var source_type := drag_data.get("source_type") as StringName
	if source_type == &"collection":
		var source_slot := drag_data.get("source_slot") as Control
		if (
			is_instance_valid(source_slot)
			and source_slot.get_parent() == collection_card_row
		):
			source_slot.modulate.a = 1.0
			if (
				not committed
				and return_global_position is Vector2
				and source_slot.get_child_count() > 0
			):
				_animate_collection_card_entry.call_deferred(
					source_slot.get_child(0) as CardView,
					return_global_position as Vector2
				)
	elif source_type == &"board":
		var source_row := drag_data.get("source_row") as BattlefieldRow
		if is_instance_valid(source_row):
			source_row._finish_card_drag(return_global_position)


func _clear_click_drop_feedback(clear_stack_feedback: bool = true) -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.clear_drop_preview(clear_stack_feedback)
	collection_drop_zone.clear_drop_preview()


func _find_board_row_at(
	pointer_global_position: Vector2
) -> BattlefieldRow:
	for row: BattlefieldRow in [front_row, back_row]:
		var local_position := _to_row_drop_position(
			row,
			pointer_global_position
		)
		if Rect2(Vector2.ZERO, row.placement_overlay.size).has_point(
			local_position
		):
			return row
	return null


func _to_row_drop_position(
	row: BattlefieldRow,
	pointer_global_position: Vector2
) -> Vector2:
	return (
		row.placement_overlay
		.get_global_transform_with_canvas()
		.affine_inverse()
		* pointer_global_position
	)


# --- 原生拖拽入口与收藏重排预览 ---
func _on_board_card_dropped(
	target_row: BattlefieldRow,
	insert_index: int,
	drag_data: Dictionary,
	card_global_position: Vector2
) -> void:
	if drag_data.has("drop_intent"):
		_transfer_drop_intent(
			drag_data,
			target_row,
			card_global_position
		)
		return
	_transfer_card(
		drag_data,
		&"board",
		target_row,
		insert_index,
		card_global_position
	)


func _on_collection_card_dropped(
	drag_data: Dictionary,
	card_global_position: Vector2
) -> void:
	if drag_data.get("kind") == &"squad":
		collection_drop_zone.clear_drop_preview()
		_transfer_squad_to_collection(drag_data, card_global_position)
		return
	if drag_data.get("source_type") == &"collection":
		# 收藏卡放回收藏等同取消拖拽，不允许借此改变收藏位置。
		collection_drop_zone.clear_drop_preview()
		return

	collection_drop_zone.clear_drop_preview()
	_transfer_card(
		drag_data,
		&"collection",
		null,
		0,
		card_global_position
	)


func _get_collection_card_slots() -> Array[Control]:
	var slots: Array[Control] = []
	for child: Node in collection_card_row.get_children():
		var slot := child as Control
		if (
			slot != null
			and slot.get_child_count() > 0
			and not slot.is_queued_for_deletion()
		):
			slots.append(slot)
	return slots


# --- 放置事务：从拖拽数据推导并提交唯一一次真实数据变更 ---
func _transfer_card(
	drag_data: Dictionary,
	target_type: StringName,
	target_row: BattlefieldRow = null,
	insert_index: int = 0,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE or not _is_card_drag_data(drag_data):
		return false

	var card_data := drag_data["card_data"] as CardData
	var source_type := drag_data["source_type"] as StringName
	if target_type == &"board" and target_row == null:
		return false

	if source_type == &"collection":
		if target_type != &"board" or not target_row.has_capacity_for_single_card():
			return false

		if not collection_cards.has(card_data) or _is_card_deployed(card_data):
			return false

		selected_board_slot = target_row.add_card(card_data, insert_index)
		selected_board_row = target_row
		_build_collection_cards()
		if entry_global_position is Vector2:
			_animate_board_card_entry.call_deferred(
				selected_board_slot,
				entry_global_position as Vector2
			)
	elif source_type == &"board":
		var source_row := drag_data.get("source_row") as BattlefieldRow
		var source_slot := drag_data.get("source_slot") as BoardSlot
		if (
			not is_instance_valid(source_row)
			or not is_instance_valid(source_slot)
			or source_row.get_slot_index(source_slot) < 0
			or not source_slot.get_squad_data().contains(card_data)
		):
			return false

		if target_type == &"collection":
			var returned_card := card_data
			var returns_new_owned_card := not collection_cards.has(returned_card)
			if returns_new_owned_card and collection_cards.size() >= COLLECTION_MAX_CARDS:
				return false
			if not source_row.remove_card_from_squad(source_slot, card_data):
				return false
			# 上场卡一直保留在 collection_cards 中；回收只解除部署状态。
			if returns_new_owned_card:
				collection_cards.append(returned_card)
			_record_recently_returned_card(returned_card)
			selected_board_row = null
			selected_board_slot = null
			_build_collection_cards(returned_card, entry_global_position)
		elif target_type == &"board":
			if source_row == target_row:
				if source_slot.get_squad_data().get_card_count() > 1:
					source_row.remove_card_from_squad(source_slot, card_data)
					selected_board_slot = target_row.add_card(card_data, insert_index)
				else:
					if target_row.get_slot_index(source_slot) != insert_index:
						target_row.move_card_slot(source_slot, insert_index)
					selected_board_slot = source_slot
				selected_board_row = target_row
				if entry_global_position is Vector2:
					_animate_board_card_entry.call_deferred(
						selected_board_slot,
						entry_global_position as Vector2
					)
			else:
				if not target_row.has_capacity_for_single_card():
					return false

				if not source_row.remove_card_from_squad(source_slot, card_data):
					return false

				selected_board_slot = target_row.add_card(card_data, insert_index)
				selected_board_row = target_row
				if entry_global_position is Vector2:
					_animate_board_card_entry.call_deferred(
						selected_board_slot,
						entry_global_position as Vector2
					)
		else:
			return false
	else:
		return false

	_select_card(card_data)
	if target_type == &"collection":
		play_area_label.text = "已放回收藏"
	else:
		play_area_label.text = "已将 %s 放入%s" % [card_data.display_name, target_row.row_title]
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_drop_intent(
	drag_data: Dictionary,
	target_row: BattlefieldRow,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE or target_row == null:
		return false
	var intent := drag_data.get("drop_intent") as Dictionary
	if intent == null or intent.is_empty():
		return false
	var kind := drag_data.get("kind") as StringName
	if kind == &"squad":
		return _transfer_whole_squad(
			drag_data,
			target_row,
			int(intent.get("squad_index", 0)),
			entry_global_position
		)
	if kind != &"card":
		return false

	var card_data := drag_data.get("card_data") as CardData
	var source_type := drag_data.get("source_type") as StringName
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var target_slot := intent.get("target_slot") as BoardSlot
	var result_squad := intent.get("result_squad") as SquadData
	if card_data == null or result_squad == null or not result_squad.is_valid():
		return false
	var operation := intent.get("operation") as StringName
	if operation not in [&"new_squad", &"merge_card"]:
		return false
	if operation == &"merge_card" and (
		not is_instance_valid(target_slot)
		or target_row.get_slot_index(target_slot) < 0
	):
		return false
	if (
		operation == &"merge_card"
		and target_slot != source_slot
		and not target_slot.get_squad_data().can_accept_external_card_at(
			int(intent.get("card_index", 0))
		)
	):
		return false

	if source_type == &"collection":
		if not collection_cards.has(card_data) or _is_card_deployed(card_data):
			return false
	elif source_type == &"board":
		if (
			not is_instance_valid(source_row)
			or not is_instance_valid(source_slot)
			or source_row.get_slot_index(source_slot) < 0
			or not source_slot.get_squad_data().contains(card_data)
		):
			return false
	else:
		return false

	if operation == &"new_squad":
		if (
			source_type == &"board"
			and source_row == target_row
			and source_slot.get_squad_data().get_card_count() == 1
		):
			source_slot.get_squad_data().bring_card_to_top(card_data)
			target_row.move_squad_slot(
				source_slot,
				int(intent.get("squad_index", 0)),
				is_instance_valid(drag_data.get("drag_visual"))
			)
			selected_board_slot = source_slot
		elif source_type == &"board":
			source_row.remove_card_from_squad(source_slot, card_data)
			selected_board_slot = target_row.add_squad(
				result_squad,
				int(intent.get("squad_index", 0))
			)
		else:
			selected_board_slot = target_row.add_squad(
				result_squad,
				int(intent.get("squad_index", 0))
			)
	elif operation == &"merge_card":
		if source_type == &"board" and source_slot != target_slot:
			source_row.remove_card_from_squad(source_slot, card_data)
		target_slot.set_squad_data(result_squad)
		target_slot.configure_drag_source(true, target_row)
		selected_board_slot = target_slot
	else:
		return false

	if source_type == &"collection":
		_build_collection_cards()
	selected_board_row = target_row
	_select_card(card_data)
	if entry_global_position is Vector2 and is_instance_valid(selected_board_slot):
		_animate_board_card_entry.call_deferred(
			selected_board_slot,
			entry_global_position as Vector2
		)
	play_area_label.text = "已将 %s 放入%s的小队" % [card_data.display_name, target_row.row_title]
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_whole_squad(
	drag_data: Dictionary,
	target_row: BattlefieldRow,
	insert_index: int,
	entry_global_position: Variant = null
) -> bool:
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var squad_data := drag_data.get("squad_data") as SquadData
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row.get_slot_index(source_slot) < 0
		or source_slot.get_squad_data() != squad_data
	):
		return false
	if source_row == target_row:
		target_row.move_squad_slot(source_slot, insert_index)
		selected_board_slot = source_slot
	else:
		if not target_row.has_capacity_for_squad(squad_data):
			return false
		source_row.remove_squad_slot(source_slot)
		selected_board_slot = target_row.add_squad(squad_data, insert_index)
	selected_board_row = target_row
	_select_card(squad_data.get_effect_source())
	if entry_global_position is Vector2 and is_instance_valid(selected_board_slot):
		_animate_board_card_entry.call_deferred(selected_board_slot, entry_global_position)
	play_area_label.text = "已整体移动小队到%s" % target_row.row_title
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _transfer_squad_to_collection(
	drag_data: Dictionary,
	entry_global_position: Variant = null
) -> bool:
	if current_phase != GamePhase.PREPARE:
		return false
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row.get_slot_index(source_slot) < 0
	):
		return false
	var source_squad := source_slot.get_squad_data()
	if source_squad == null:
		return false
	var missing_cards: Array[CardData] = []
	for card_data: CardData in source_squad.horizontal_cards:
		if not collection_cards.has(card_data):
			missing_cards.append(card_data)
	if collection_cards.size() + missing_cards.size() > COLLECTION_MAX_CARDS:
		return false
	var squad_data := source_row.remove_squad_slot(source_slot)
	if squad_data == null:
		return false
	for card_data: CardData in missing_cards:
		collection_cards.append(card_data)
	for index: int in range(source_squad.horizontal_cards.size() - 1, -1, -1):
		_record_recently_returned_card(source_squad.horizontal_cards[index])
	selected_board_row = null
	selected_board_slot = null
	var entering_card := squad_data.horizontal_cards[0]
	_build_collection_cards(entering_card, entry_global_position)
	_select_card(entering_card)
	play_area_label.text = "已按水平顺序拆开小队并放回收藏"
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


# --- 拖拽可用性与移动动画 ---
func _is_card_drag_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false

	var drag_data := data as Dictionary
	if drag_data.get("source_type") not in [&"collection", &"board"]:
		return false
	if drag_data.get("kind") == &"card":
		return drag_data.get("card_data") is CardData
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	return false


func _refresh_drag_availability() -> void:
	var drag_enabled := current_phase == GamePhase.PREPARE
	for row: BattlefieldRow in [front_row, back_row]:
		row.set_drag_enabled(drag_enabled)

	for collection_slot: Control in _get_collection_card_slots():
		var is_deployed_ghost := bool(
			collection_slot.get_meta("is_deployed_ghost", false)
		)
		for child: Node in collection_slot.get_children():
			var card_view := child as CardView
			if card_view != null:
				card_view.configure_drag_source(
					drag_enabled and not is_deployed_ghost,
					&"collection",
					null,
					collection_slot
				)

	collection_drop_zone.set("drop_enabled", drag_enabled)


func _animate_collection_card_entry(
	card_view_value: Variant,
	entry_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(card_view_value):
		return

	var card_view := card_view_value as CardView
	if card_view == null or card_view.is_queued_for_deletion():
		return

	# 飞回收藏的卡仍属于 CollectionViewport；动画期间临时解除滚动区裁切并
	# 提到拖拽层，既能在收藏区外完整显示，也不会从其他收藏中间穿过。
	var resting_z_index := card_view.z_index
	_active_collection_entry_animations += 1
	collection_viewport.clip_contents = false
	card_view.set_resting_z_index(CardDragPreview.DRAG_PREVIEW_Z_INDEX)
	card_view.animate_from_global_position(entry_global_position)
	await get_tree().create_timer(CardView.LAYOUT_TWEEN_DURATION).timeout

	if is_instance_valid(card_view) and not card_view.is_queued_for_deletion():
		card_view.set_resting_z_index(resting_z_index)
	_active_collection_entry_animations = maxi(_active_collection_entry_animations - 1, 0)
	if _active_collection_entry_animations == 0 and is_instance_valid(collection_viewport):
		collection_viewport.clip_contents = true


func _animate_board_card_entry(
	slot_value: Variant,
	entry_global_position: Vector2
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(slot_value):
		return

	var slot := slot_value as BoardSlot
	if (
		slot != null
		and not slot.is_queued_for_deletion()
		and slot.get_parent() != null
	):
		slot.animate_from_global_position(entry_global_position)


func _select_card(card_data: CardData) -> void:
	selected_card = card_data

	if selected_card == null:
		play_area_label.text = "收藏为空"
		return

	play_area_label.text = "当前选中：%s。准备阶段可按住卡牌拖动放置" % selected_card.display_name
