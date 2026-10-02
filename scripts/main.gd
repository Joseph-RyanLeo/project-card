extends Control

## 主场景的流程协调器。
##
## 这里把收藏、两条战场行、阶段切换和两种拖拽入口连接起来；
## 小队布局与牌型显示分别下放给 BattlefieldRow / SquadView。
## 拖动期间只维护预览，只有 _transfer_* 系列函数会提交真实数据变更。

const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/CardView.tscn")
const SHOP_CARD_VIEW_SCENE: PackedScene = preload("res://scenes/ui/ShopCardView.tscn")
const ShopCardViewScript = preload("res://scripts/ui/shop_card_view.gd")
const ShopOfferViewScript = preload("res://scripts/ui/shop_offer_view.gd")
const ShopPackStackViewScript = preload("res://scripts/ui/shop_pack_stack_view.gd")
const ShopPriceViewScript = preload("res://scripts/ui/shop_price_view.gd")
const SHOP_OPEN_OFFSET: float = -380.0 # 商店从屏幕上方落下时的初始纵向位移
const SHOP_OPEN_OVERSHOOT: float = 12.0 # 下落越过终点后回弹的距离
const SHOP_OPEN_DURATION: float = 0.24 # 商店下降到越过点的秒数
const SHOP_REBOUND_DURATION: float = 0.13 # 越过后回弹到原位的秒数
const SHOP_CLOSE_DURATION: float = 0.22 # 商店回收至屏幕上方的秒数
const SHOP_INSPECTION_OPEN_SECONDS: float = 0.25 # 商品从陈列位置放大到检视位置的秒数
const SHOP_PACK_OPEN_HOLD: float = 0.12 # 包装放大后停留再开始溶解的秒数
const SHOP_PACK_INSPECTION_SCALE: float = 4.0 # 包装检视相对原生商品画布的整数放大倍率
const SHOP_BACKGROUND_POSITION := Vector2(224, 40) # 商店桌布左上角，使用1280×720逻辑画布坐标
const SHOP_BACKGROUND_SIZE := Vector2(832, 306) # 商店桌布覆盖的宽高
const BATTLEFIELD_ROW_SCENE: PackedScene = preload("res://scenes/ui/BattlefieldRow.tscn")
const COLLECTION_DROP_ZONE_SCRIPT: Script = preload("res://scripts/ui/collection_drop_zone.gd")
const SPELL_PREPARATION_TRAY_SCRIPT: Script = preload("res://scripts/ui/spell_preparation_tray.gd")
const DEVELOPER_CONSOLE_SCRIPT: Script = preload("res://scripts/ui/developer_console.gd")
const ESCAPE_PAUSE_MENU_SCRIPT: Script = preload("res://scripts/ui/escape_pause_menu.gd")
const BattleSquadState = preload("res://scripts/battle/battle_squad_state.gd")
const BattleController = preload("res://scripts/battle/battle_controller.gd")
const BattleRules = preload("res://scripts/battle/battle_rules.gd")
const BattleElementResolver = preload("res://scripts/battle/battle_element_resolver.gd")
const BattleLogEntry = preload("res://scripts/battle/battle_log_entry.gd")
const BattleFormulaPresenter = preload("res://scripts/battle/battle_formula_presenter.gd")
const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleAttackTrailRenderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const BattlePermanentGrowthLedger = preload("res://scripts/battle/battle_permanent_growth_ledger.gd")
const BattleRunRewardLedger = preload("res://scripts/battle/battle_run_reward_ledger.gd")
const BattlePreparationSnapshot = preload("res://scripts/data/battle_preparation_snapshot.gd")
const OwnedCard = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollection = preload("res://scripts/data/owned_card_collection.gd")
const CardSlotLayout = preload("res://scripts/data/card_slot_layout.gd")
const EmblemLibraryData = preload("res://scripts/data/emblem_library_data.gd")
const StatusIndicatorStyle = preload("res://scripts/ui/status_indicator_style.gd")
const RuneRevealCoverStyleScript = preload("res://scripts/ui/rune_reveal_cover_style.gd")
const EmblemLibraryViewScript = preload("res://scripts/ui/emblem_library_view.gd")
const CardInspectionOverlayScript = preload("res://scripts/ui/card_inspection_overlay.gd")
const RunSettlementJournal = preload("res://scripts/data/run_settlement_journal.gd")
const RunRewardState = preload("res://scripts/data/run_reward_state.gd")
const BattleSettlementService = preload("res://scripts/data/battle_settlement_service.gd")
const BattleDiagnosticRecorderScript = preload("res://scripts/battle/battle_diagnostic_recorder.gd")
const BattleDiagnosticSerializerScript = preload("res://scripts/battle/battle_diagnostic_serializer.gd")
const BattleAudioServiceScript = preload("res://scripts/battle/battle_audio_service.gd")
const RunSaveService = preload("res://scripts/data/run_save_service.gd")
const OrdinaryShopServiceScript = preload("res://scripts/data/ordinary_shop_service.gd")
const ResourceBoardState = preload("res://scripts/data/resource_board_state.gd")
const RESOURCE_PREPARATION_TRAY_SCRIPT = preload("res://scripts/ui/resource_preparation_tray.gd")
const PAGE_NUMBER_FONT: Font = preload("res://assets/fonts/pixel_numbers_large.fnt")
const BATTLE_LOG_FONT: Font = preload("res://assets/fonts/chill_7.ttf")
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
const CHARACTER_SHEET_TEXTURE: Texture2D = preload("res://assets/stage_6_5/character_front_back.png")
const PLAYER_AVATAR_TURN_TEXTURE: Texture2D = preload("res://assets/stage_6_5/player_avatar_turn.png")
const ACTION_TABS_TEXTURE: Texture2D = preload("res://assets/stage_6_5/page_tabs.png")
const CARD_TYPE_TABS_TEXTURE: Texture2D = preload("res://assets/stage_6_5/card_type_tabs.png")
const RARITY_FILTER_TEXTURE: Texture2D = preload("res://assets/stage_6_5/rarity_filter_icons.png")
const ELEMENT_FILTER_TEXTURE: Texture2D = preload("res://assets/stage_6_5/element_filter_icons.png")
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
const PLAYER_AVATAR_FRAME_SIZE := Vector2(180.0, 180.0) # 我方人物转身图集中单帧的原始像素尺寸
const PLAYER_AVATAR_FRAME_COUNT: int = 8 # 用户动图前八帧为正面转背面的有效动作帧
const PLAYER_AVATAR_POSITION := Vector2(890.0, 164.0) # 新人物画布与旧按钮中心大致对齐的位置
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
	Rect2(0, 23, 13, 18),
	Rect2(21, 23, 13, 18),
	Rect2(42, 23, 13, 18),
	Rect2(63, 23, 15, 18),
	Rect2(86, 23, 15, 18),
] # I～V 五个未选中暗版稀有度图标
const RARITY_FILTER_SELECTED_REGIONS: Array[Rect2] = [
	Rect2(0, 0, 13, 18),
	Rect2(21, 0, 13, 18),
	Rect2(42, 0, 13, 18),
	Rect2(63, 0, 15, 18),
	Rect2(86, 0, 15, 18),
] # I～V 五个选中亮版稀有度图标
const ELEMENT_FILTER_REGIONS: Array[Rect2] = [
	Rect2(0, 21, 16, 16),
	Rect2(24, 21, 16, 16),
	Rect2(48, 21, 16, 16),
	Rect2(71, 21, 16, 16),
	Rect2(95, 21, 16, 16),
] # 水、木、火、光、暗五个未选中暗版元素筛选图标
const ELEMENT_FILTER_SELECTED_REGIONS: Array[Rect2] = [
	Rect2(0, 0, 16, 16),
	Rect2(24, 0, 16, 16),
	Rect2(48, 0, 16, 16),
	Rect2(71, 0, 16, 16),
	Rect2(95, 0, 16, 16),
] # 水、木、火、光、暗五个选中亮版元素筛选图标
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
const ENEMY_RESOURCE_TRAY_POSITION := Vector2(6.0, 171.0) # 敌方资源区在敌方世界段内的位置；x向右、y向下
const PLAYER_RESOURCE_TRAY_POSITION := Vector2(1094.0, WORLD_SECTION_HEIGHT+4) # 玩家资源区在玩家世界段内的位置；整体视角会随我方世界段平移
const SPELL_PREPARATION_TRAY_POSITION := Vector2(13.0, 380.0) # 法术板位于我方战场左侧、战斗种子下方
const TOOLBOX_POSITION := Vector2(6.0, 167.0) # 普通工具箱在收藏区域内的1×位置；x向右、y向下，检视收展位置独立计算
const DEVELOPER_CONSOLE_CANVAS_LAYER: int = 1 # 控制台绘制在主界面普通 CanvasLayer 上方
const ESCAPE_PAUSE_MENU_Z_INDEX: int = 4000 # 暂停菜单高于结算统计与常规卡牌层
const BATTLE_VOLUME_POSITION := Vector2(864.0, 320.0) # 音量控制位于准备栏下方、头像上方的面板局部坐标
const VIEW_TWEEN_DURATION: float = 0.32 # 人物按钮与阶段默认视角的平滑切换时长
const PLAYER_AVATAR_TURN_DURATION: float = 0.32 # 完整转身动作的时长，与战场视角切换同步
const COLLECTION_MAX_PHYSICAL_PAGES: int = 100 # 收藏最多显示 100 个物理单页
const COLLECTION_MAX_SPREADS: int = COLLECTION_MAX_PHYSICAL_PAGES / 2 # 两个物理页组成一组展开页
const COLLECTION_SLOTS_PER_PAGE: int = 12 # 每组左右书页合计固定卡位数
const COLLECTION_MAX_CARDS: int = COLLECTION_MAX_PHYSICAL_PAGES * 6 # 每个物理页 6 张，100 页合计 600 张
const SPELL_CAST_PRESENTATION_MAX_SCALE: float = 2.2 # 战斗法术卡面放大后的最大视觉倍率
const SPELL_CAST_PRESENTATION_REST_SCALE: float = 1.8 # 卡面收束阶段的视觉倍率
const SPELL_CAST_PRESENTATION_FADE_RATIO: float = 0.18 # 法术卡淡入时长占整段演出的比例
const SPELL_CAST_PRESENTATION_GROW_RATIO: float = 0.52 # 法术卡放大时长占整段演出的比例
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
const ACTION_TAB_ICON_FRAME_SIZE := Vector2(25, 28) # 五种行动图标共同对齐的逻辑框，不直接作为纹理拉伸尺寸
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
const START_BATTLE_BUTTON_POSITION := Vector2(704, 294) # 正式开始战斗按钮在我方战场区的位置
const START_BATTLE_BUTTON_SIZE := Vector2(150, 38) # 正式开始战斗按钮的可点击尺寸
const BATTLE_PAUSE_BUTTON_POSITION := Vector2(42, 190) # 暂停按钮紧邻四段速度条左侧
const BATTLE_PAUSE_BUTTON_SIZE := Vector2(32, 30) # 暂停按钮的可点击尺寸
const BATTLE_SPEED_BUTTON_POSITION := Vector2(78, 190) # 四段战斗速度条位于左上敌方画像正下方
const BATTLE_SPEED_BUTTON_SIZE := Vector2(164, 30) # 四段战斗速度条的总可点击尺寸
const BATTLE_SPEED_MULTIPLIERS: Array[float] = [0.5, 1.0, 2.0, 3.0] # 四段战斗速度由左向右递增
const BATTLE_TRACE_MAX_FRAMES: int = 36000 # 性能采样最多保留10分钟@60fps，达到上限后停止记录
const BATTLE_TIMER_POSITION := Vector2(54, 343) # 战斗逻辑计时位于战场中线靠左位置
const BATTLE_TIMER_SIZE := Vector2(130, 32) # 战斗计时文字的固定显示区域
const BATTLE_SEED_PANEL_POSITION := Vector2(12, 820) # 种子器位于战斗计时下方，方便按阵容截图复现同一场战斗
const BATTLE_SEED_PANEL_SIZE := Vector2(202, 62) # 一行标题与一行可编辑种子、随机按钮的固定区域
const BATTLE_SEED_MAX: int = 999999999 # 与战斗实验室统一使用九位非负种子，便于手工抄录
const BATTLE_LOG_POSITION := Vector2(12, 448) # 战斗日志位于战场页面左下角的固定位置
const BATTLE_LOG_SIZE := Vector2(202, 246) # 战斗日志容器的固定显示尺寸
const BATTLE_LOG_MAX_ENTRIES: int = 100 # 日志最多保留的行动条数，避免长战斗无限增长
const FORMULA_POPUP_MIN_WIDTH: float = 210.0 # 短公式弹窗的最小阅读宽度
const FORMULA_POPUP_MAX_WIDTH: float = 340.0 # 长公式弹窗在换行前允许使用的最大宽度
const FORMULA_POPUP_MAX_HEIGHT: float = 300.0 # 长公式弹窗无需占满画面的最大高度
const FORMULA_POPUP_CONTENT_PADDING := Vector2(18.0, 18.0) # 弹窗两侧各 9 像素内边距合计占用的横纵空间
const FORMULA_POPUP_MOUSE_GAP: float = 10.0 # 弹窗底边与鼠标之间的垂直间距
const EFFECT_LAYER_Z_INDEX: int = 1200 # 高于三卡堆最高卡面、低于公式弹窗与结算框的元素特效层级
const EFFECT_FLASH_SECONDS: float = 0.62 # 火灼烧与终结闪烁持续时间（秒）
const EFFECT_IMPACT_RADIUS := Vector2(24.0, 32.0) # 元素命中目标时菱形脉冲的横纵半径
const EFFECT_COLOR_NONE := Color("ffffff") # 无有效元素组合时的纯白攻击颜色
const EFFECT_COLOR_LIGHT := Color("ffd70f") # 光元素的纯黄色攻击颜色
const EFFECT_COLOR_DARK := Color("b05dff") # 暗元素的纯紫色攻击颜色
const EFFECT_COLOR_FIRE := Color("e51414") # 火元素的纯红色攻击颜色
const EFFECT_COLOR_WATER := Color("0095ff") # 水元素的纯蓝色攻击颜色
const EFFECT_COLOR_WOOD := Color("3ac330") # 木元素的纯绿色攻击颜色
const BATTLE_RESULT_PANEL_POSITION := Vector2(1096, 184) # 战后入口放在战场右侧空白区，不遮挡四排卡牌
const BATTLE_RESULT_PANEL_SIZE := Vector2(170, 278) # 右侧结算框高度，同时容纳战斗数据导出与重开入口
signal battle_departure_requested(state: BattleSquadState)

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
var _native_carry_data: Dictionary = {} # 统一跟踪原生卡牌/装备拖拽的当前目标
var _rune_scrape_last_pointer: Vector2 = Vector2.INF # 连续刮擦的上一画布坐标；脱离检视卡后会清空
var _rune_scrape_last_inside_surface: bool = false # 只有连续留在检视面内才插值，避免从工具箱跨屏连线
var _rune_scraper_mode: bool = false # 只有主动进入刮刀模式后才接收刮擦输入
var _rune_scrape_button_held: bool = false # 左键按住时才沿鼠标路径连续刮擦
var _rune_scrape_sticker_consumed_this_stroke: bool = false # 移除贴纸后要求下一次独立按键再刮底层
var _rune_scraper_paid_slots: Dictionary = {} # 当前刮刀模式内已付费槽；退出时统一完整揭晓
var _rune_scraper_drag_data: Dictionary = {} # 刀头相对鼠标的固定命中形状
var _rune_scraper_visual: TextureRect
var _rune_scraper_return_tween: Tween
var _rune_scraper_previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
const SCRAPER_RETURN_DURATION: float = 0.22 # 手持刮刀取消后飞回凹槽的秒数
var _native_carry_update_frame := -1
var _native_carry_update_pointer := Vector2.INF
var _native_carry_last_target: Dictionary = {}
var _native_carry_pointer := Vector2.ZERO
var _battlefield_clock_check_queued: bool = false
var _equipment_drop_profile_started_usec := 0
var _equipment_drop_profile_last_usec := 0
var _equipment_drop_profile_sections: Dictionary = {}
var _equipment_drop_profile_active := false
var _battle_performance_trace_enabled: bool = false
var _battle_trace_frame_samples: Array[Dictionary] = []
var _battle_trace_drag_preview_usec: int = 0
var _battle_trace_state_sync_usec: int = 0
var _battle_trace_effect_dispatch_usec: int = 0
var _battle_trace_last_advance_total_usec: int = 0
var _battle_trace_last_exact_snap_total_usec: int = 0
var _battle_trace_previous_frame_usec: int = 0
var _battle_trace_page_turn_usec: int = 0
var _battle_trace_start_usec: int = 0
var _battle_trace_result_usec: int = 0
var current_world_view: WorldView = WorldView.COLLECTION
var current_collection_page: int = 0
var active_rarity_filters: Array[int] = []
var active_element_filters: Array[int] = []
var active_action_filters: Array[int] = []
var active_card_type_filters: Array[int] = []
var search_query: String = ""
var recently_returned_cards: Array[CardData] = []
var recently_returned_owned_cards: Array[OwnedCard] = [] # 最近页与卡面定义并行保存，避免同名卡错绑实例
var collection_bookmark_active: bool = false
var _regular_collection_page_before_bookmark: int = 0
var _collection_effect_display_states: Dictionary = {} # 按卡牌稳定id保存收藏中的效果面状态，翻页重建节点后仍可恢复
var last_page_turn_method: StringName = &""
var _view_tween: Tween
var _player_avatar_turn_tween: Tween
var _player_avatar_frame_index: int = 0
var _page_tween: Tween
var _action_tab_tween: Tween
var _card_type_tab_tween: Tween
var _recent_bookmark_tween: Tween
var _recent_bookmark_shake_tween: Tween
var _page_turn_overlay: Control
var _battle_snapshot: BattlePreparationSnapshot
var _battle_state_slots: Dictionary = {}
var battle_departure_count: int = 0
var battle_speed_index: int = 1
var _active_battle_departures: int = 0
var _pending_battle_result: BattleController.Result = BattleController.Result.NONE
var _battle_log_entries: Array[BattleLogEntry] = []
var _next_direct_effect_log_id: int = 1
var _battle_log_by_group: Dictionary = {}
var _battle_generation: int = 0
var _completed_battle_departures: Array[Dictionary] = []
var _battle_departure_flush_queued: bool = false
var _next_battle_instance_sequence: int = 1
var _resume_battle_instance_id: StringName = &"" # 战斗中退出读档后，下一次开战复用原战斗身份

var owned_card_collection := OwnedCardCollection.new()
@export_range(0, 20, 1) var spell_preparation_capacity: int = 10 # 当前英雄可准备的法术实例上限；英雄容量系统接入前由此处配置
var prepared_spell_instance_ids: Array[StringName] = []
var settlement_journal := RunSettlementJournal.new()
var run_reward_state := RunRewardState.new()
var battle_settlement_service := BattleSettlementService.new()
var run_save_service := RunSaveService.new()
var resource_board_state := ResourceBoardState.new()
var player_resource_tray: Control
var enemy_resource_tray: Control
var _last_battle_settlement_result: Dictionary = {}
var _last_run_persistence_result: Dictionary = {}
var _startup_runtime_snapshot: Dictionary = {}

@export var collection_cards: Array[CardData] = [] # 场景初始定义及旧UI派生数组；可变所有权以OwnedCardCollection为准
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
var spell_preparation_tray: Control
var spell_cast_presentation: CardView
var spell_cast_presentation_tween: Tween
var drag_mode_button: Button
var enemy_avatar: TextureRect
var battle_pause_button: Button
var battle_speed_bar: Control
var battle_speed_buttons: Array[Button] = []
var battle_timer_label: Label
var battle_seed_panel: PanelContainer
var battle_seed_spin: SpinBox
var battle_seed_random_button: Button
var battle_log_panel: PanelContainer
var battle_log_text: RichTextLabel
var formula_popup: PanelContainer
var formula_popup_text: RichTextLabel
var _formula_popup_hide_generation: int = 0
var battle_effect_layer: Control
var player_avatar_button: TextureButton
var battle_volume_slider: HSlider
var battle_audio_service: Variant
var celestial_indicators: CelestialIndicatorController
var start_battle_button: Button
var battle_result_panel: Panel
var battle_result_label: Label
var battle_result_summary_label: RichTextLabel
var export_battle_data_button: Button
var battle_export_status_label: Label
var restart_battle_button: Button
var continue_next_level_button: Button
var ground_reward_panel: Panel
var ground_reward_list: VBoxContainer
var battle_diagnostic_file_dialog: FileDialog
var battle_diagnostic_message_dialog: AcceptDialog
var battle_controller: BattleController
var _battle_diagnostic_recorder: BattleDiagnosticRecorder
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
var emblem_library: Variant
var _emblem_library_parent: Control
var _inspection_overlay: Variant
var _inspection_carry_layer: Control
var _inspection_card_view: CardView
var _inspection_owned_card: OwnedCard
var _inspection_card_data: CardData
var _inspection_previous_tree_paused := false
var _manual_pause_requested: bool = false
var _inspection_pause_requested: bool = false
var _special_spell_pause_requested: bool = false
var _inspection_effect_layer_was_visible := true
var _inspection_surface: InspectionCardSurface
var _inspection_source_view: Control
var _shop_pack_opening := false
var _click_carry_layer: Control
var _inspection_statistics_suppression_snapshot: Array[Dictionary] = []
var _inspection_dim: ColorRect
var _inspection_display_mode_button: Button
var _inspection_library_toggle: Button
var _inspection_library_expanded := false
var _last_minion_inspection_library_expanded: bool = false
var _inspection_has_library_toolbox: bool = false
var _inspection_read_only: bool = false
var _show_battle_target_priority: bool = false
var _inspection_tween: Tween
var _inspection_library_original_parent: Control
var _inspection_library_original_canvas_transform := Transform2D.IDENTITY
var _inspection_library_original_layout: Dictionary = {}
var _inspection_library_original_z_index := -48
var _inspection_library_original_scroll := 0
var _inspection_library_transform_saved := false
var _inspection_placement_tween: Tween
var _inspection_placement_visual: Polygon2D
var _inspection_placement_in_progress := false
var _inspection_closing := false
var _next_developer_emblem_instance: int = 1
var _developer_console: Variant
var _escape_pause_menu: EscapePauseMenu
var _escape_menu_pause_requested := false
const INSPECTION_STICKER_FLIGHT_DURATION: float = 0.18 # 纹章与元素贴纸从抓取位置飞入槽位的动画时长
const INSPECTION_LIBRARY_SCALE: float = 4.0 # 检视工具箱与卡牌同为局部4倍显示
const INSPECTION_LIBRARY_REVEAL: float = 28.0 # 收起时工具箱露出可点击的边缘宽度
const INSPECTION_LIBRARY_GAP: float = 24.0 # 展开工具箱与卡牌实体可见边界之间的间隔
const INSPECTION_LIBRARY_TOGGLE_DURATION: float = 0.24 # 工具箱收展和卡牌让位的动画时长
const INSPECTION_EFFECT_BOX_SIZE := Vector2(260.0, 150.0) # 长文本说明框的逻辑尺寸
const INSPECTION_EFFECT_BOX_TOP: float = 4.0 # 长效果说明框从逻辑画布顶部开始显示
const INSPECTION_DISPLAY_BUTTON_POSITION := Vector2(1030.0, 50.0) # 避开显示模式栏并覆盖卡面区域
var _last_chaos_reroll_day_token: StringName = &""
var ordinary_shop_service: Variant
var ordinary_shop_layer: Control
var ordinary_shop_panel: PanelContainer
var ordinary_shop_offer_list: VBoxContainer
var _shop_open_tween: Tween
var _shop_motion_root: Control
var ordinary_shop_status: Label
var ordinary_shop_entry_button: Button
var continue_run_button: Button
var claim_random_cards_button: Button
var debug_new_shop_button: Button
var _shop_tear_dialog: ConfirmationDialog
var _shop_sell_dialog: AcceptDialog
var ordinary_shop_open := false
var _ordinary_shop_previous_world_view: WorldView = WorldView.COLLECTION
var scraper_count: int = 0
const DEFAULT_RUN_SAVE_PATH := "user://project_card_run.json"
var run_save_path: String = DEFAULT_RUN_SAVE_PATH


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
	_build_resource_preparation_trays(world)
	_build_spell_preparation_tray(world)
	_build_collection_section(world)
	_build_enemy_avatar(world)
	_build_battle_hud(world)
	_build_battle_result_panel()
	_assign_runtime_owner(world)
	_build_ordinary_shop_interface()
	_build_developer_console()
	_build_escape_pause_menu()
	_build_click_carry_layer()


func _build_developer_console() -> void:
	var console_layer := CanvasLayer.new()
	console_layer.name = "DeveloperConsoleLayer"
	console_layer.layer = DEVELOPER_CONSOLE_CANVAS_LAYER
	add_child(console_layer)
	_developer_console = DEVELOPER_CONSOLE_SCRIPT.new()
	_developer_console.name = "DeveloperConsole"
	_developer_console.visible = false
	_developer_console.command_submitted.connect(_on_developer_console_command_submitted)
	console_layer.add_child(_developer_console)


func _build_ordinary_shop_interface() -> void:
	ordinary_shop_layer = Control.new()
	ordinary_shop_layer.name = "OrdinaryShopLayer"
	ordinary_shop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ordinary_shop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ordinary_shop_layer.z_index = 250 # 商店位于普通战场上方，资源详情、检视和暂停菜单下方
	add_child(ordinary_shop_layer)
	var shop_backdrop := TextureRect.new()
	shop_backdrop.name = "ShopTableBackdrop"
	shop_backdrop.visible = false
	shop_backdrop.position = SHOP_BACKGROUND_POSITION
	shop_backdrop.size = SHOP_BACKGROUND_SIZE
	shop_backdrop.texture = preload("res://assets/card_ui/shop/background.png")
	shop_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shop_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	shop_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shop_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_motion_root = Control.new()
	_shop_motion_root.name = "ShopMotionRoot"
	_shop_motion_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop_motion_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ordinary_shop_layer.add_child(_shop_motion_root)
	_shop_motion_root.add_child(shop_backdrop)
	ordinary_shop_entry_button = Button.new()
	ordinary_shop_entry_button.name = "OrdinaryShopEntryButton"
	ordinary_shop_entry_button.text = "商店"
	ordinary_shop_entry_button.position = Vector2(1160, 74) # 入口按钮避开右上角战斗种子栏
	ordinary_shop_entry_button.size = Vector2(92, 32) # 入口按钮的可点击尺寸
	ordinary_shop_entry_button.pressed.connect(_toggle_ordinary_shop)
	ordinary_shop_layer.add_child(ordinary_shop_entry_button)
	ordinary_shop_panel = PanelContainer.new()
	ordinary_shop_panel.name = "OrdinaryShopPanel"
	ordinary_shop_panel.position = Vector2(208, 0) # 商店面板与敌方战场区域对齐
	ordinary_shop_panel.size = Vector2(864, 360) # 收纳在敌方中央两排桌面内
	ordinary_shop_panel.custom_minimum_size = ordinary_shop_panel.size
	ordinary_shop_panel.visible = false
	ordinary_shop_panel.visibility_changed.connect(func():
		if not ordinary_shop_panel.visible:
			if is_instance_valid(_shop_open_tween):
				_shop_open_tween.kill()
			_shop_motion_root.position.y = 0.0
		shop_backdrop.visible = ordinary_shop_panel.visible
		# 敌方牌型标签使用独立高层反馈；商店打开时连同敌方中央战场一起收起。
		(get_node("%EnemyBoardSection") as Control).visible = not ordinary_shop_panel.visible
	)
	ordinary_shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("211d19", 0.30)
	panel_style.content_margin_left = 14 # 商品陈列与面板左边框的间距
	panel_style.content_margin_top = 44 # 标题避开显示壳顶端的分辨率下拉框，防止刷新按钮被挡住
	panel_style.content_margin_right = 14 # 商品陈列与面板右边框的间距
	panel_style.content_margin_bottom = 8 # 滚动区域与面板下边框的间距
	ordinary_shop_panel.add_theme_stylebox_override("panel", panel_style)
	_shop_motion_root.add_child(ordinary_shop_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4) # 标题、状态和桌面商品区之间的纵向间距
	ordinary_shop_panel.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := Label.new()
	title.text = "普通商店 · 灰烬证册"
	title.add_theme_font_size_override("font_size", 24) # 商店标题字号
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var sell_button := Button.new()
	sell_button.name = "SellCardsButton"
	sell_button.text = "出售"
	sell_button.pressed.connect(_open_shop_sell_dialog)
	heading.add_child(sell_button)
	var refresh_button := Button.new()
	refresh_button.name = "OrdinaryShopRefreshButton"
	refresh_button.text = "刷新"
	refresh_button.custom_minimum_size = Vector2(72, 32) # 刷新按钮保留明确的鼠标点击命中区域
	refresh_button.pressed.connect(_refresh_ordinary_shop)
	heading.add_child(refresh_button)
	continue_run_button = Button.new()
	continue_run_button.name = "ContinueRunButton"
	continue_run_button.text = "继续游戏"
	continue_run_button.position = Vector2(1060, 112) # 继续入口位于商店打开按钮下方
	continue_run_button.size = Vector2(92, 32) # 继续入口的可点击尺寸
	continue_run_button.tooltip_text = "从唯一的本局存档槽恢复"
	continue_run_button.visible = FileAccess.file_exists(run_save_path)
	continue_run_button.pressed.connect(_continue_saved_run)
	ordinary_shop_layer.add_child(continue_run_button)
	claim_random_cards_button = Button.new()
	claim_random_cards_button.name = "ClaimRandomCardRequestsButton"
	claim_random_cards_button.text = "领取随机随从"
	claim_random_cards_button.position = Vector2(1060, 150) # 待领取奖励入口放在继续游戏入口下方
	claim_random_cards_button.size = Vector2(92, 32) # 奖励入口保持与继续按钮相同的点击尺寸
	claim_random_cards_button.visible = false
	claim_random_cards_button.pressed.connect(_claim_pending_random_cards)
	ordinary_shop_layer.add_child(claim_random_cards_button)
	debug_new_shop_button = Button.new()
	debug_new_shop_button.name = "DebugNewShopButton"
	debug_new_shop_button.text = "新商店"
	debug_new_shop_button.tooltip_text = "仅调试构建可见；正式新店仍由事件流程创建"
	debug_new_shop_button.visible = OS.is_debug_build()
	debug_new_shop_button.pressed.connect(_start_new_ordinary_shop)
	heading.add_child(debug_new_shop_button)
	var close_button := Button.new()
	close_button.name = "OrdinaryShopCloseButton"
	close_button.text = "离开"
	close_button.pressed.connect(_toggle_ordinary_shop)
	heading.add_child(close_button)
	ordinary_shop_status = Label.new()
	ordinary_shop_status.name = "OrdinaryShopStatus"
	ordinary_shop_status.custom_minimum_size = Vector2(0, 26) # 状态提示预留高度
	ordinary_shop_status.clip_text = true
	ordinary_shop_status.add_theme_font_size_override("font_size", 18) # 单行状态文字的字号
	content.add_child(ordinary_shop_status)
	ordinary_shop_offer_list = VBoxContainer.new()
	ordinary_shop_offer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ordinary_shop_offer_list.add_theme_constant_override("separation", 4) # 金币信息与商品陈列之间的间距
	content.add_child(ordinary_shop_offer_list)


func _toggle_ordinary_shop() -> void:
	if current_phase != GamePhase.PREPARE or ordinary_shop_service == null:
		return
	ordinary_shop_open = not ordinary_shop_open
	if ordinary_shop_open:
		if not ordinary_shop_panel.visible:
			_ordinary_shop_previous_world_view = current_world_view
		set_world_view(WorldView.BATTLEFIELDS)
	else:
		_play_shop_close_animation()
	if ordinary_shop_open:
		ordinary_shop_panel.visible = true
	if ordinary_shop_open and ordinary_shop_service.offers.is_empty():
		_generate_ordinary_shop(false)
	elif not ordinary_shop_open:
		var save_error := save_run_to_path(run_save_path)
		ordinary_shop_status.text = "已保存本局" if save_error == OK else "离店存档失败（错误码 %d）" % save_error
		play_area_label.text = ordinary_shop_status.text
	if ordinary_shop_open:
		_refresh_ordinary_shop_panel()
		_play_shop_open_animation()
	if is_instance_valid(continue_run_button):
		continue_run_button.visible = FileAccess.file_exists(run_save_path)


func _play_shop_open_animation() -> void:
	if is_instance_valid(_shop_open_tween):
		_shop_open_tween.kill()
	_shop_motion_root.position.y = SHOP_OPEN_OFFSET
	_shop_open_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shop_open_tween.tween_property(_shop_motion_root, "position:y", SHOP_OPEN_OVERSHOOT, SHOP_OPEN_DURATION)
	_shop_open_tween.tween_property(_shop_motion_root, "position:y", 0.0, SHOP_REBOUND_DURATION)


func _play_shop_close_animation() -> void:
	if is_instance_valid(_shop_open_tween):
		_shop_open_tween.kill()
	_shop_open_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_shop_open_tween.tween_property(_shop_motion_root, "position:y", SHOP_OPEN_OFFSET, SHOP_CLOSE_DURATION)
	_shop_open_tween.tween_callback(func():
		ordinary_shop_panel.visible = false
		set_world_view(_ordinary_shop_previous_world_view)
	)


func _continue_saved_run() -> void:
	if load_run_from_path(run_save_path):
		ordinary_shop_open = false
		ordinary_shop_panel.visible = false
		ordinary_shop_status.text = "已继续本局"
	else:
		ordinary_shop_status.text = "继续游戏失败：本局存档无法读取或校验"


func _get_shop_card_definitions() -> Array[CardData]:
	var result: Array[CardData] = []
	for value: Variant in _build_card_definition_registry().values():
		if value is CardData:
			result.append(value as CardData)
	return result


func _get_shop_sticker_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in EmblemLibraryData.get_definitions():
		if String(definition.get("target", "emblem")) != "rune" and int(definition.get("rarity", -1)) < 0:
			continue
		result.append(definition)
	return result


func _get_all_held_stickers() -> Array[Dictionary]:
	var result := emblem_library.get_inventory_state() as Array[Dictionary]
	for owned: OwnedCard in owned_card_collection.get_cards():
		for states: Array[Dictionary] in [owned.emblem_slots, owned.wound_slots, owned.rune_stickers]:
			for state: Dictionary in states:
				if not state.is_empty():
					result.append(state.duplicate(true))
	return result


func _generate_ordinary_shop(is_refresh: bool) -> bool:
	var success: bool = ordinary_shop_service.refresh(
		_get_shop_card_definitions(),
		owned_card_collection.get_cards(),
		_get_shop_sticker_definitions(),
		_get_all_held_stickers()
	)
	if success and is_refresh:
		ordinary_shop_service.refresh_count += 1
	_refresh_ordinary_shop_panel()
	if not success:
		ordinary_shop_status.text = "当前卡池无法生成完整商品，商店状态没有改变"
	return success


func _refresh_ordinary_shop() -> void:
	if not ordinary_shop_open or ordinary_shop_service == null:
		return
	var price: int = ordinary_shop_service.refresh_price()
	if run_reward_state.gold < price:
		ordinary_shop_status.text = "金币不足：刷新需要%d金币" % price
		return
	if not _generate_ordinary_shop(true):
		return
	run_reward_state.gold -= price
	ordinary_shop_status.text = "商店已刷新，花费%d金币" % price
	_refresh_ordinary_shop_panel()


func _start_new_ordinary_shop() -> void:
	if not ordinary_shop_open:
		return
	var old_refresh_count: int = ordinary_shop_service.refresh_count
	ordinary_shop_service.refresh_count = 0
	if not _generate_ordinary_shop(false):
		ordinary_shop_service.refresh_count = old_refresh_count
		return
	ordinary_shop_status.text = "已生成新商店报价"
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		ordinary_shop_status.text = "新商店已生成；保存失败（错误码 %d）" % save_error
	_refresh_ordinary_shop_panel()


func _claim_pending_random_cards() -> void:
	if ordinary_shop_service == null or run_reward_state.pending_random_card_requests.is_empty():
		return
	var all_definitions: Array[CardData] = []
	for value: Variant in _build_card_definition_registry().values():
		if value is CardData:
			all_definitions.append(value as CardData)
	var next_rng := RandomNumberGenerator.new()
	next_rng.seed = ordinary_shop_service.rng.seed
	next_rng.state = ordinary_shop_service.rng.state
	var current_owned := owned_card_collection.get_cards()
	var pending_cards: Array[CardData] = []
	for request: Dictionary in run_reward_state.pending_random_card_requests:
		var parameters: Dictionary = request.get("parameters", {}) as Dictionary
		var requested_type := _random_reward_card_type(parameters)
		var requested_pack := String(parameters.get("pack_id", parameters.get("theme_id", "")))
		var minimum_rarity := _random_reward_rarity(parameters.get("minimum_rarity", "I"))
		var exact_rarity := _random_reward_rarity(parameters.get("rarity", "")) if parameters.has("rarity") else -1
		if requested_type < 0 or minimum_rarity < 0 or (parameters.has("rarity") and exact_rarity < 0):
			ordinary_shop_status.text = "随机卡牌请求含有无效筛选条件，原请求已保留"
			return
		var held_iv: Dictionary = {}
		for owned: OwnedCard in current_owned:
			if owned.card_data.rarity == CardData.Rarity.IV:
				held_iv[owned.card_data.id] = true
		for chosen_card: CardData in pending_cards:
			if chosen_card.rarity == CardData.Rarity.IV:
				held_iv[chosen_card.id] = true
		for _draw: int in int(request.get("amount", 0)):
			var candidates: Array[CardData] = []
			for definition: CardData in all_definitions:
				if not definition.is_available or definition.is_derived or definition.card_type != requested_type:
					continue
				if not requested_pack.is_empty() and String(definition.pack_id) != requested_pack:
					continue
				if int(definition.rarity) < minimum_rarity or (exact_rarity >= 0 and int(definition.rarity) != exact_rarity) or (definition.rarity == CardData.Rarity.IV and held_iv.has(definition.id)):
					continue
				candidates.append(definition)
			var selected: CardData = ordinary_shop_service._draw_by_rarity_weights(candidates, next_rng, minimum_rarity)
			if selected == null:
				ordinary_shop_status.text = "当前没有满足该随机随从请求的候选；请求与随机状态均保留"
				return
			pending_cards.append(selected)
			if selected.rarity == CardData.Rarity.IV:
				held_iv[selected.id] = true
	var previous_collection := owned_card_collection.capture_state()
	var previous_reward := run_reward_state.capture_state()
	var previous_rng_state: int = ordinary_shop_service.rng.state
	for card: CardData in pending_cards:
		if owned_card_collection.create_card(card, next_rng) == null:
			owned_card_collection.restore_state(previous_collection)
			ordinary_shop_service.rng.state = previous_rng_state
			ordinary_shop_status.text = "创建随机卡牌实例失败；原请求已保留"
			return
	run_reward_state.pending_random_card_requests.clear()
	ordinary_shop_service.rng.state = next_rng.state
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		owned_card_collection.restore_state(previous_collection)
		run_reward_state.restore_state(previous_reward)
		ordinary_shop_service.rng.state = previous_rng_state
		ordinary_shop_status.text = "保存失败；随机随从请求已回滚并保留"
		return
	_sync_legacy_collection_cards()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	ordinary_shop_status.text = "已领取随机随从：%s" % "、".join(_shop_card_names(pending_cards))
	_refresh_ordinary_shop_panel()


func _random_reward_card_type(parameters: Dictionary) -> int:
	var value: Variant = parameters.get("card_type", parameters.get("type", "minion"))
	if value is int and int(value) >= 0 and int(value) < CardData.CardType.size():
		return int(value)
	var names := {"minion": CardData.CardType.MINION, "随从": CardData.CardType.MINION, "equipment": CardData.CardType.EQUIPMENT, "装备": CardData.CardType.EQUIPMENT, "spell": CardData.CardType.SPELL, "法术": CardData.CardType.SPELL, "resource": CardData.CardType.RESOURCE, "资源": CardData.CardType.RESOURCE}
	return int(names[String(value)]) if names.has(String(value)) else -1


func _random_reward_rarity(value: Variant) -> int:
	if value is int:
		return int(value) if int(value) >= 0 and int(value) < CardData.Rarity.size() else -1
	return ["I", "II", "III", "IV", "V"].find(String(value))


func _refresh_ordinary_shop_panel() -> void:
	if not is_instance_valid(ordinary_shop_offer_list) or ordinary_shop_service == null:
		return
	if is_instance_valid(claim_random_cards_button):
		var has_pending_requests := run_reward_state.get_pending_random_card_count() > 0
		claim_random_cards_button.visible = has_pending_requests
		claim_random_cards_button.disabled = not has_pending_requests
	if is_instance_valid(debug_new_shop_button):
		debug_new_shop_button.visible = OS.is_debug_build()
	# 只更新成交/替换的商品，原卡面和轮播计时器一直留在树中。
	var wallet := ordinary_shop_offer_list.get_node_or_null("ShopWallet") as HBoxContainer
	var display_row := ordinary_shop_offer_list.get_node_or_null("ShopDisplayRow") as HBoxContainer
	if wallet == null:
		wallet = HBoxContainer.new()
		wallet.name = "ShopWallet"
		wallet.add_theme_constant_override("separation", 20) # 余额与刷新费用之间的间距
		ordinary_shop_offer_list.add_child(wallet)
		display_row = HBoxContainer.new()
		display_row.name = "ShopDisplayRow"
		display_row.add_theme_constant_override("separation", 8) # 主商品与服务区的间距
		ordinary_shop_offer_list.add_child(display_row)
		var grid := HBoxContainer.new()
		grid.name = "OrdinaryShopOfferGrid"
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("separation", 8) # 同排主商品之间的间距
		display_row.add_child(grid)
		var service_column := VBoxContainer.new()
		service_column.name = "ShopServices"
		service_column.add_theme_constant_override("separation", 8) # 两项服务之间的间距
		display_row.add_child(service_column)
	var wallet_values := [run_reward_state.gold, ordinary_shop_service.refresh_price()]
	if wallet.get_meta("values", []) != wallet_values:
		for child: Node in wallet.get_children():
			wallet.remove_child(child)
			child.queue_free()
		wallet.add_child(_shop_price([wallet_values[0]]))
		wallet.add_child(_shop_price([wallet_values[1]], "刷新"))
		wallet.set_meta("values", wallet_values)
	var offer_grid := display_row.get_node("OrdinaryShopOfferGrid") as HBoxContainer
	var services := display_row.get_node("ShopServices") as VBoxContainer
	var retained: Dictionary = {}
	var old_positions: Dictionary = {}
	for existing: ShopOfferView in ordinary_shop_offer_list.find_children("ShopOffer_*", "Control", true, false):
		retained[int(existing.get_meta("shop_offer_index"))] = existing
		old_positions[existing] = existing._visual.get_global_transform_with_canvas().origin
	var existing_stacks: Dictionary = {}
	var old_prices: Dictionary = {}
	for stack: ShopPackStackView in offer_grid.get_children().filter(func(node: Node): return node is ShopPackStackView):
		existing_stacks[String(stack.name)] = stack
		old_prices[stack] = stack._description.get_global_transform_with_canvas().origin
	# 本次刷新共用定义和合法候选；不把持有资格长期缓存，购买时仍重新验证。
	var definitions := _build_card_definition_registry()
	var catalog: Array[CardData] = []
	for definition: CardData in definitions.values():
		catalog.append(definition)
	var candidates: Array[CardData] = ordinary_shop_service._eligible_cards(catalog, owned_card_collection.get_cards())
	var pack_stacks: Dictionary = {}
	var desired_grid: Array[Control] = []
	for index: int in ordinary_shop_service.offers.size():
		var offer: Dictionary = ordinary_shop_service.offers[index]
		if bool(offer.get("sold", false)):
			continue
		var is_pack: bool = offer.get("kind") in ["card_pack", "sticker_pack"]
		var tile := retained.get(index) as ShopOfferView
		if tile != null and tile.get_meta("offer") != offer:
			_remove_shop_offer_tile(tile)
			tile = null
		if tile == null:
			tile = _create_shop_offer_tile(index, offer, is_pack, definitions, candidates)
		else:
			tile.set_purchase_enabled((offer.get("kind") != "sticker_pack" or _can_accept_shop_sticker_offer(offer)) and (offer.get("kind") != "card_pack" or _can_buy_shop_card_pack(offer, definitions, candidates)))
			tile.tooltip_text = _ordinary_shop_offer_text(offer)
		retained.erase(index)
		if is_pack:
			var key := "%s:%s" % [String(offer.get("pack_id", "ash_ledger")), String(offer.get("size", "small"))] if offer.get("kind") == "card_pack" else "sticker_pack"
			if not pack_stacks.has(key):
				var stack_name := "ShopPackStack_" + key.replace(":", "_")
				var stack := existing_stacks.get(stack_name) as ShopPackStackView
				if stack == null:
					stack = ShopPackStackViewScript.new()
					stack.name = stack_name
					stack.configure(_shop_price([int(offer.get("price", 0))]))
					stack.set_meta("price", int(offer.get("price", 0)))
					offer_grid.add_child(stack)
				if stack.get_meta("price", -1) != int(offer.get("price", 0)):
					stack.set_price(_shop_price([int(offer.get("price", 0))]))
					stack.set_meta("price", int(offer.get("price", 0)))
				pack_stacks[key] = stack
				desired_grid.append(stack)
			if tile.get_parent() == null:
				pack_stacks[key].add_offer(tile)
		elif offer.get("kind") in ["scraper", "tear_service"]:
			if tile.get_parent() == null:
				services.add_child(tile)
		else:
			if tile.get_parent() == null:
				offer_grid.add_child(tile)
			desired_grid.append(tile)
	for tile: ShopOfferView in retained.values():
		_remove_shop_offer_tile(tile)
	for stack: ShopPackStackView in existing_stacks.values():
		if stack._offers.is_empty():
			offer_grid.remove_child(stack)
			stack.queue_free()
	for stack: ShopPackStackView in pack_stacks.values():
		stack.reorder_offers()
	for index: int in desired_grid.size():
		offer_grid.move_child(desired_grid[index], index)
	# 先同步容器的目标布局，再补偿图片位置；不等待下一帧，避免补位先闪跳一帧。
	for container: Container in [ordinary_shop_offer_list, wallet, display_row, offer_grid, services]:
		container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for tile: ShopOfferView in old_positions:
		if tile.is_inside_tree():
			tile.animate_reflow_from(old_positions[tile])
	for stack: ShopPackStackView in old_prices:
		if stack.is_inside_tree():
			stack.animate_price_reflow_from(old_prices[stack])


func _remove_shop_offer_tile(tile: ShopOfferView) -> void:
	var parent := tile.get_parent()
	if parent is ShopPackStackView:
		parent.remove_offer(tile)
	elif parent != null:
		parent.remove_child(tile)
	tile.queue_free()


func _create_shop_offer_tile(index: int, offer: Dictionary, stacked: bool, definitions: Dictionary, candidates: Array[CardData]) -> ShopOfferView:
	var tile := ShopOfferViewScript.new()
	tile.name = "ShopOffer_%d" % index
	tile.set_meta("shop_offer_index", index)
	tile.set_meta("offer", offer.duplicate(true))
	var art: Control
	if offer.get("kind") == "single_card":
		art = _create_shop_single_card_view(offer, definitions)
	elif offer.get("kind") == "sticker_pack":
		art = _create_shop_sticker_pack_art()
	else:
		var image := TextureRect.new()
		image.size = Vector2(99, 136) # 卡包商品保持单卡大小的画布
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.texture = _ordinary_shop_offer_icon(offer)
		if offer.get("kind") == "scraper":
			image.size = image.texture.get_size() # 刮刀按59×59原像素展示，服务区不旋转、不缩放
		elif offer.get("kind") == "tear_service":
			image.size = Vector2(44, 60) # 撕卡服务图标的紧凑显示尺寸
		art = image
	var enabled: bool = (
		(offer.get("kind") != "sticker_pack" or _can_accept_shop_sticker_offer(offer))
		and (offer.get("kind") != "card_pack" or _can_buy_shop_card_pack(offer, definitions, candidates))
	)
	var service_name := "刮刀" if offer.get("kind") == "scraper" else ("撕卡" if offer.get("kind") == "tear_service" else "")
	tile.hover_motion = service_name.is_empty()
	tile.tooltip_text = _ordinary_shop_offer_text(offer)
	var prices: Array[int] = [int(offer.get("price", 0))]
	if offer.get("kind") == "tear_service":
		var config_prices: Dictionary = ordinary_shop_service.config.get("tear_service", {}).get("prices_by_return_count", {})
		prices = [int(config_prices.get("1", 0)), int(config_prices.get("2", 0)), int(config_prices.get("3", 0))]
	tile.configure(art, _shop_price(prices), offer.get("kind") in ["single_card", "card_pack", "sticker_pack"], enabled, stacked, service_name)
	tile.purchase_requested.connect(_on_ordinary_shop_offer_pressed.bind(index))
	tile.inspection_requested.connect(_preview_shop_offer.bind(index))
	return tile


func _create_shop_sticker_pack_art() -> Control:
	var pack := Control.new()
	pack.name = "SealedStickerPack"
	pack.size = Vector2(99, 136) # 纹章包在商品图片区域占用的尺寸
	pack.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var layers := Control.new()
	layers.size = Vector2(126, 125) # 正式底壳素材的原始画布尺寸
	layers.scale = Vector2.ONE * (99.0 / 126.0) # 底壳与封皮一起等比缩放到商品宽度
	layers.position.y = (136.0 - 125.0 * layers.scale.y) * 0.5 # 包装在商品区域内纵向居中
	pack.add_child(layers)
	var base := TextureRect.new()
	base.name = "PackBase"
	base.texture = preload("res://assets/card_ui/shop/sticker_pack_base.png")
	base.size = Vector2(126, 125) # 底壳按原始像素画布显示
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layers.add_child(base)
	var seal := TextureRect.new()
	seal.name = "PackSeal"
	seal.texture = preload("res://assets/card_ui/shop/sticker_pack_seal.png")
	seal.position = Vector2(17, 6) # 封皮对齐原图底壳内口的位置
	seal.size = Vector2(91, 92) # 封皮按原始像素尺寸显示
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layers.add_child(seal)
	return pack


func _preview_shop_offer(index: int) -> void:
	if not ordinary_shop_open or is_instance_valid(_inspection_overlay) or _escape_pause_menu.is_menu_open() or (_developer_console != null and _developer_console.visible) or index < 0 or index >= ordinary_shop_service.offers.size():
		return
	var offer: Dictionary = ordinary_shop_service.offers[index]
	if offer.get("kind") == "single_card":
		_preview_shop_single_card(index)
	elif offer.get("kind") in ["card_pack", "sticker_pack"] and not bool(offer.get("sold", false)):
		_open_shop_pack_inspection(offer, _shop_offer_art(index))


func _shop_offer_art(index: int) -> Control:
	var tile := ordinary_shop_offer_list.find_child("ShopOffer_%d" % index, true, false) as ShopOfferView
	return tile._visual.get_child(0) as Control if tile != null else null


func _open_shop_pack_inspection(offer: Dictionary, source: Control = null, opening: bool = false) -> void:
	_finish_rune_scraper_mode()
	_cancel_click_carry()
	_inspection_closing = false
	_inspection_previous_tree_paused = get_tree().paused
	_inspection_pause_requested = false
	_inspection_effect_layer_was_visible = battle_effect_layer.visible
	_inspection_has_library_toolbox = false
	_inspection_read_only = true
	_shop_pack_opening = opening
	_build_inspection_overlay("开包" if opening else "卡包检视", "正在打开包装…" if opening else "只读检视；点击暗幕、右键或按 Esc 关闭")
	var art: Control
	if offer.get("kind") == "sticker_pack":
		art = _create_shop_sticker_pack_art()
	else:
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.texture = _ordinary_shop_offer_icon(offer)
		image.size = Vector2(99, 136) # 包装以原生商品尺寸合成，检视表面统一放大
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art = image
	art.name = "InspectionPackArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection_overlay.add_child(art)
	_inspection_surface = preload("res://scripts/ui/inspection_card_surface.gd").new() as InspectionCardSurface
	_inspection_surface.name = "InspectionSurface"
	_inspection_overlay.add_child(_inspection_surface)
	var preview_scale := SHOP_PACK_INSPECTION_SCALE
	_inspection_surface.setup_art(art)
	var target_scale := Vector2.ONE * preview_scale
	var target_position: Vector2 = ((_inspection_overlay.size - _inspection_surface.size * preview_scale) * 0.5 - Vector2(0, 25)).round() # 居中并给名称留位
	_inspection_surface.scale = Vector2.ONE
	_inspection_surface.position = target_position + _inspection_surface.size * (preview_scale - 1.0) * 0.5
	if is_instance_valid(source):
		var origin: Transform2D = _inspection_overlay.get_global_transform_with_canvas().affine_inverse() * source.get_global_transform_with_canvas()
		_inspection_source_view = source
		_inspection_surface.scale = origin.get_scale()
		_inspection_surface.position = origin.origin - origin.basis_xform(_inspection_surface.PADDING)
		_inspection_surface.rotation = origin.get_rotation()
		source.visible = false
	_inspection_dim.modulate.a = 0.0
	_inspection_tween = _inspection_overlay.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_inspection_tween.tween_property(_inspection_surface, "position", target_position, SHOP_INSPECTION_OPEN_SECONDS)
	_inspection_tween.tween_property(_inspection_surface, "scale", target_scale, SHOP_INSPECTION_OPEN_SECONDS)
	_inspection_tween.tween_property(_inspection_surface, "rotation", 0.0, SHOP_INSPECTION_OPEN_SECONDS)
	_inspection_tween.tween_property(_inspection_dim, "modulate:a", 1.0, SHOP_INSPECTION_OPEN_SECONDS)
	var pack_name := "纹章贴纸包" if offer.get("kind") == "sticker_pack" else "灰烬证册 · %s卡包" % ("大" if offer.get("size") == "large" else "小")
	var name_label := _make_label(pack_name, Vector2(260, 645), Vector2(760, 34)) # 名称位于4倍包装大图下方并水平居中
	name_label.name = "InspectionPackName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24) # 检视卡包名称的字号
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection_overlay.add_child(name_label)
	name_label.modulate.a = 0.0
	_inspection_tween.tween_property(name_label, "modulate:a", 1.0, SHOP_INSPECTION_OPEN_SECONDS)
	if opening:
		_inspection_surface.set_process(false)
		_inspection_tween.chain().tween_interval(SHOP_PACK_OPEN_HOLD)
		_inspection_tween.tween_callback(_dissolve_purchased_shop_pack)


func _dissolve_purchased_shop_pack() -> void:
	if not is_instance_valid(_inspection_surface):
		return
	# 包装已合成在原生小画布中；复用战斗死亡着色器与时长，不读取屏幕或操作随机流。
	var dissolve := ShaderMaterial.new()
	dissolve.shader = SquadView.DEATH_DISSOLVE_SHADER
	dissolve.set_shader_parameter("dissolve_progress", 0.0)
	dissolve.set_shader_parameter("edge_progress", 0.0)
	dissolve.set_shader_parameter("dissolve_fill_color", SquadView.DEATH_DISSOLVE_FILL_COLOR)
	dissolve.set_shader_parameter("dissolve_outline_color", SquadView.DEATH_DISSOLVE_OUTLINE_COLOR)
	dissolve.set_shader_parameter("outline_pixels", SquadView.DEATH_DISSOLVE_OUTLINE_PIXELS)
	_inspection_surface.material = dissolve
	_inspection_tween = _inspection_overlay.create_tween().set_parallel(true)
	_inspection_tween.tween_property(dissolve, "shader_parameter/dissolve_progress", 1.0, SquadView.DEATH_DISSOLVE_BODY_SECONDS).from(0.0)
	_inspection_tween.tween_property(dissolve, "shader_parameter/edge_progress", 1.0, SquadView.DEATH_DISSOLVE_EDGE_SECONDS).from(0.0)
	_inspection_tween.tween_property(_inspection_dim, "modulate:a", 0.0, SquadView.DEATH_DISSOLVE_EDGE_SECONDS)
	var name_label := _inspection_overlay.get_node("InspectionPackName") as Label
	_inspection_tween.tween_property(name_label, "modulate:a", 0.0, SquadView.DEATH_DISSOLVE_EDGE_SECONDS)
	_inspection_tween.finished.connect(_finish_card_inspection_close)


func _ordinary_shop_offer_icon(offer: Dictionary) -> Texture2D:
	match String(offer.get("kind", "")):
		"card_pack":
			return preload("res://assets/card_ui/shop/ash_ledger_large.png") if offer.get("size") == "large" else preload("res://assets/card_ui/shop/ash_ledger_small.png")
		"sticker_pack": return preload("res://assets/card_ui/shop/sticker_pack_base.png")
		"tear_service":
			return preload("res://assets/card_backgrounds/card_background_placeholder.png")
		"scraper": return RuneStickerStyle.get_scraper_texture()
	return null


func _create_shop_single_card_view(offer: Dictionary, definitions: Dictionary = {}) -> CardView:
	if definitions.is_empty():
		definitions = _build_card_definition_registry()
	var definition := definitions.get(StringName(String(offer.get("card_id", "")))) as CardData
	var view := SHOP_CARD_VIEW_SCENE.instantiate() as CardView
	if definition == null:
		return view
	if bool(offer.get("hidden", false)):
		view.configure_hidden(ShopCardViewScript.public_definition(definition, offer), offer)
	else:
		view.set_card_data(definition)
		view.set_owned_card(_create_shop_preview_owned(definition, offer))
	view.configure_drag_source(false)
	return view


func _create_shop_preview_owned(definition: CardData, offer: Dictionary) -> OwnedCard:
	var seed_text := String(offer.get("instance_seed", ""))
	if not seed_text.is_valid_int():
		return null
	var preview_owned := OwnedCard.new()
	var preview_rng := RandomNumberGenerator.new()
	preview_rng.seed = int(seed_text)
	preview_owned.initialize(definition, &"ordinary_shop_preview", -1, preview_rng)
	return preview_owned


func _preview_shop_single_card(index: int) -> void:
	if not ordinary_shop_open or is_instance_valid(_inspection_overlay) or index < 0 or index >= ordinary_shop_service.offers.size():
		return
	var offer: Dictionary = ordinary_shop_service.offers[index]
	if offer.get("kind") != "single_card" or bool(offer.get("sold", false)):
		return
	var definition := _build_card_definition_registry().get(StringName(String(offer.get("card_id", "")))) as CardData
	if definition == null:
		return
	if bool(offer.get("hidden", false)):
		var public_card := ShopCardViewScript.public_definition(definition, offer)
		_open_card_inspection(public_card, null, _shop_offer_art(index) as CardView, true, offer)
	else:
		var preview_owned := _create_shop_preview_owned(definition, offer)
		if preview_owned != null:
			_open_card_inspection(definition, preview_owned, _shop_offer_art(index) as CardView, true)


func _shop_price(values: Array[int], caption: String = "") -> Control:
	var price := ShopPriceViewScript.new()
	price.configure(values, caption)
	return price


func _ordinary_shop_offer_text(offer: Dictionary) -> String:
	var kind := String(offer.get("kind", ""))
	match kind:
		"card_pack":
			return "%s卡包：%d张 · %d金币%s" % ["大" if offer.get("size") == "large" else "小", int((ordinary_shop_service.config.get("card_pack_sizes", {}) as Dictionary).get(offer.get("size", "small"), 0)), int(offer.get("price", 0)), "（至少一张II级）" if offer.get("size") == "large" else ""]
		"sticker_pack": return "贴纸包：5枚 · %d金币" % int(offer.get("price", 0))
		"single_card":
			if bool(offer.get("sold", false)) and ordinary_shop_service.reveal_by_offer.has(String(offer.get("offer_id", ""))):
				var revealed_card := _build_card_definition_registry().get(StringName(String(ordinary_shop_service.reveal_by_offer[String(offer.get("offer_id", ""))]))) as CardData
				return "已揭晓：%s" % (revealed_card.display_name if revealed_card != null else "卡牌")
			if bool(offer.get("hidden", false)):
				var hint_names := {"rarity": "稀有度", "action_type": "行动方式", "race": "种族", "card_type": "卡牌类型", "spell_trigger_kind": "准备方式", "spell_type": "法术种类", "equipment_type": "装备种类", "resource_type": "资源种类"}
				return "暗牌（%s：%s）· %d金币" % [hint_names.get(String(offer.get("hint", "")), "提示"), String(offer.get("hint_value", "")), int(offer.get("price", 0))]
			var card := _build_card_definition_registry().get(StringName(String(offer.get("card_id", "")))) as CardData
			return "%s · %d金币" % [card.display_name if card != null else "明牌", int(offer.get("price", 0))]
		"scraper": return "刮刀 ×1 · %d金币（现有%d把）" % [int(offer.get("price", 0)), scraper_count]
		"tear_service":
			var prices: Dictionary = (ordinary_shop_service.config.get("tear_service", {}) as Dictionary).get("prices_by_return_count", {})
			return "撕卡：返还1/2/3枚 · %d/%d/%d金币" % [int(prices.get("1", 0)), int(prices.get("2", 0)), int(prices.get("3", 0))]
	return "商品"


func _on_ordinary_shop_offer_pressed(index: int) -> void:
	if not ordinary_shop_open or is_instance_valid(_inspection_overlay) or (_developer_console != null and _developer_console.visible) or _escape_pause_menu.is_menu_open() or index < 0 or index >= ordinary_shop_service.offers.size():
		return
	var offer: Dictionary = ordinary_shop_service.offers[index]
	if bool(offer.get("sold", false)):
		return
	var pack_source := _shop_offer_art(index)
	var before_gold := run_reward_state.gold
	match String(offer.get("kind", "")):
		"card_pack": _buy_shop_card_pack(index, offer)
		"sticker_pack": _buy_shop_sticker_pack(index, offer)
		"single_card": _buy_shop_single_card(index, offer)
		"scraper": _buy_shop_scraper(offer)
		"tear_service": _open_shop_tear_selection()
	if bool(offer.get("sold", false)) and offer.get("kind") in ["card_pack", "sticker_pack"]:
		_open_shop_pack_inspection(offer, pack_source, true)
	if bool(offer.get("sold", false)) or run_reward_state.gold != before_gold:
		_refresh_ordinary_shop_panel()


func _buy_shop_card_pack(index: int, offer: Dictionary) -> void:
	var price := int(offer.get("price", 0))
	if run_reward_state.gold < price:
		ordinary_shop_status.text = "金币不足"
		return
	if not _can_buy_shop_card_pack(offer):
		ordinary_shop_status.text = "卡包候选或保底资格已变化；未执行交易"
		return
	var candidates: Array[CardData] = ordinary_shop_service._eligible_cards(_get_shop_card_definitions(), owned_card_collection.get_cards())
	var chosen: Array[CardData] = []
	var used_iv: Dictionary = {}
	for id_value: Variant in offer.get("cards", []) as Array:
		var chosen_card: CardData
		for card: CardData in candidates:
			if String(card.id) == String(id_value) and not (card.rarity == CardData.Rarity.IV and used_iv.has(card.id)):
				chosen_card = card
				break
		if chosen_card == null:
			ordinary_shop_status.text = "卡包候选已失效；未扣金币、抽取或改变卡牌实例序号"
			return
		chosen.append(chosen_card)
		if chosen_card.rarity == CardData.Rarity.IV:
			used_iv[chosen_card.id] = true
	if chosen.size() != int((ordinary_shop_service.config.get("card_pack_sizes", {}) as Dictionary).get(offer.get("size", "small"), 0)):
		ordinary_shop_status.text = "卡包内容不完整，未执行交易"
		return
	var before_collection := owned_card_collection.capture_state()
	var before_rng: int = ordinary_shop_service.rng.state
	var before_gold := run_reward_state.gold
	for card: CardData in chosen:
		if owned_card_collection.create_card(card, ordinary_shop_service.rng) == null:
			owned_card_collection.restore_state(before_collection)
			ordinary_shop_service.rng.state = before_rng
			ordinary_shop_status.text = "卡牌实例创建失败，交易已回滚"
			return
	run_reward_state.gold -= price
	ordinary_shop_service.offers[index]["sold"] = true
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		owned_card_collection.restore_state(before_collection)
		run_reward_state.gold = before_gold
		ordinary_shop_service.rng.state = before_rng
		ordinary_shop_service.offers[index].erase("sold")
		ordinary_shop_status.text = "存档失败，卡包交易已回滚（错误码 %d）" % save_error
		return
	_sync_legacy_collection_cards()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	ordinary_shop_status.text = "已开包并获得：%s" % "、".join(_shop_card_names(chosen))


func _buy_shop_single_card(index: int, offer: Dictionary) -> void:
	var price := int(offer.get("price", 0))
	var definition := _build_card_definition_registry().get(StringName(String(offer.get("card_id", "")))) as CardData
	var eligible_now: Array[CardData] = ordinary_shop_service._eligible_cards(_get_shop_card_definitions(), owned_card_collection.get_cards())
	if run_reward_state.gold < price or definition == null or not eligible_now.has(definition):
		ordinary_shop_status.text = "金币不足或卡牌定义已失效"
		return
	var before_collection := owned_card_collection.capture_state()
	var before_rng: int = ordinary_shop_service.rng.state
	var before_gold := run_reward_state.gold
	var instance_rng := RandomNumberGenerator.new()
	instance_rng.seed = int(String(offer.get("instance_seed", "0")))
	var purchased_card := owned_card_collection.create_card(definition, instance_rng)
	if purchased_card == null:
		ordinary_shop_status.text = "卡牌实例创建失败，未扣款"
		return
	if offer.has("resolved_action_type"):
		purchased_card.resolved_action_type = int(offer["resolved_action_type"])
	run_reward_state.gold -= price
	var hidden := bool(offer.get("hidden", false))
	ordinary_shop_service.offers[index]["sold"] = true
	if hidden:
		ordinary_shop_service.reveal_by_offer[String(offer.get("offer_id", ""))] = String(definition.id)
	var save_error := save_run_to_path(run_save_path) if hidden else OK
	if save_error != OK:
		owned_card_collection.restore_state(before_collection)
		run_reward_state.gold = before_gold
		ordinary_shop_service.rng.state = before_rng
		ordinary_shop_service.offers[index].erase("sold")
		ordinary_shop_service.reveal_by_offer.erase(String(offer.get("offer_id", "")))
		ordinary_shop_status.text = "存档失败，暗牌交易已回滚"
		return
	_sync_legacy_collection_cards()
	_build_collection_cards()
	ordinary_shop_status.text = "暗牌揭晓：%s" % definition.display_name if hidden else "已购入：%s" % definition.display_name


func _buy_shop_sticker_pack(index: int, offer: Dictionary) -> void:
	var raw_stickers := offer.get("stickers", []) as Array
	if raw_stickers.size() != int((ordinary_shop_service.config.get("sticker_pack", {}) as Dictionary).get("sticker_count", 5)):
		ordinary_shop_status.text = "贴纸包候选不完整"
		return
	var price := int(offer.get("price", 0))
	if run_reward_state.gold < price:
		ordinary_shop_status.text = "金币不足"
		return
	var before_inventory: Array[Dictionary] = emblem_library.get_inventory_state()
	var before_next_id := _next_developer_emblem_instance
	var before_rng: int = ordinary_shop_service.rng.state
	var before_gold := run_reward_state.gold
	var states: Array[Dictionary] = []
	for sticker: Dictionary in raw_stickers:
		var id := StringName(String(sticker.get("id", "")))
		if id == &"万能贴纸" and _has_universal_sticker_in_collection_or_bag():
			ordinary_shop_status.text = "万能贴纸唯一性已变化，未执行交易"
			return
		var state := {"instance_id": "shop_sticker_%06d" % _next_developer_emblem_instance, "emblem_id": id, "temporary": false, "source": "ordinary_shop", "element_sticker": sticker.get("target", "emblem") == "rune"}
		_next_developer_emblem_instance += 1
		if id == &"混沌贴纸":
			state["element"] = ordinary_shop_service.rng.randi_range(0, 4)
		states.append(state)
	if not emblem_library.can_add_stickers(states):
		_next_developer_emblem_instance = before_next_id
		ordinary_shop_service.rng.state = before_rng
		ordinary_shop_status.text = "工具箱空间不足，贴纸包未扣款且未揭晓"
		return
	for state: Dictionary in states:
		if not emblem_library.return_sticker(state):
			emblem_library.restore_inventory_state(before_inventory)
			_next_developer_emblem_instance = before_next_id
			ordinary_shop_service.rng.state = before_rng
			ordinary_shop_status.text = "工具箱接收失败，交易已回滚"
			return
	run_reward_state.gold -= price
	ordinary_shop_service.offers[index]["sold"] = true
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		emblem_library.restore_inventory_state(before_inventory)
		_next_developer_emblem_instance = before_next_id
		ordinary_shop_service.rng.state = before_rng
		run_reward_state.gold = before_gold
		ordinary_shop_service.offers[index].erase("sold")
		ordinary_shop_status.text = "存档失败，贴纸包交易已回滚"
		return
	ordinary_shop_status.text = "贴纸包已揭晓并收入工具箱：%s" % "、".join(_shop_sticker_names(states))
	emblem_library.set_scraper_count(scraper_count)


func _buy_shop_scraper(offer: Dictionary) -> void:
	var price := int(offer.get("price", 0))
	if run_reward_state.gold < price:
		ordinary_shop_status.text = "金币不足"
		return
	run_reward_state.gold -= price
	scraper_count += 1
	emblem_library.set_scraper_count(scraper_count)
	ordinary_shop_status.text = "已购买刮刀；现有%d把" % scraper_count


func _can_buy_shop_card_pack(offer: Dictionary, definitions: Dictionary = {}, candidates: Array[CardData] = []) -> bool:
	var cards_value: Variant = offer.get("cards", null)
	if not cards_value is Array:
		return false
	if definitions.is_empty():
		definitions = _build_card_definition_registry()
		var catalog: Array[CardData] = []
		for definition: CardData in definitions.values():
			catalog.append(definition)
		candidates = ordinary_shop_service._eligible_cards(catalog, owned_card_collection.get_cards())
	var selected: Array[CardData] = []
	var used_iv: Dictionary = {}
	for card_id_value: Variant in cards_value:
		var card := definitions.get(StringName(String(card_id_value))) as CardData
		if card == null or not candidates.has(card) or (card.rarity == CardData.Rarity.IV and used_iv.has(card.id)):
			return false
		selected.append(card)
		if card.rarity == CardData.Rarity.IV:
			used_iv[card.id] = true
	var size_key := String(offer.get("size", ""))
	var card_count := int((ordinary_shop_service.config.get("card_pack_sizes", {}) as Dictionary).get(size_key, 0))
	if card_count <= 0 or selected.size() != card_count:
		return false
	var minimum_rarity: int = ordinary_shop_service._configured_minimum_pack_rarity()
	if size_key == "large" and not ordinary_shop_service._contains_rarity_at_least(selected, minimum_rarity):
		return false
	return true


func _open_shop_tear_selection() -> void:
	var eligible_cards: Array[OwnedCard] = []
	for owned: OwnedCard in owned_card_collection.get_cards():
		if _card_has_tearable_stickers(owned):
			eligible_cards.append(owned)
	if eligible_cards.is_empty():
		ordinary_shop_status.text = "没有带有可返还贴纸的卡牌"
		return
	_shop_tear_dialog = ConfirmationDialog.new()
	_shop_tear_dialog.title = "撕卡：选择返还贴纸"
	_shop_tear_dialog.dialog_text = "选择一张卡，再选择1至3枚贴纸。卡牌将被永久销毁，未选中的贴纸也会销毁。"
	_shop_tear_dialog.get_ok_button().text = "核对费用与销毁内容"
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8) # 撕卡选择器之间的纵向间距
	_shop_tear_dialog.add_child(layout)
	var card_picker := OptionButton.new()
	card_picker.name = "TearCardPicker"
	for owned: OwnedCard in eligible_cards:
		card_picker.add_item("%s（%d枚贴纸）" % [owned.card_data.display_name, _tearable_stickers(owned).size()])
		card_picker.set_item_metadata(card_picker.item_count - 1, String(owned.instance_id))
	layout.add_child(card_picker)
	var sticker_pickers: Array[OptionButton] = []
	var first_card_stickers := _tearable_stickers(eligible_cards[0])
	for slot: int in 3:
		var picker := OptionButton.new()
		picker.add_item("不返还")
		picker.set_item_metadata(0, "")
		for state: Dictionary in first_card_stickers:
			var item_id := String(state.get("emblem_id", ""))
			picker.add_item(item_id)
			picker.set_item_metadata(picker.item_count - 1, String(state.get("instance_id", "")))
		sticker_pickers.append(picker)
		layout.add_child(picker)
	card_picker.item_selected.connect(_refresh_shop_tear_sticker_options.bind(card_picker, sticker_pickers, eligible_cards))
	_shop_tear_dialog.confirmed.connect(_confirm_shop_tear_selection.bind(card_picker, sticker_pickers, eligible_cards))
	_shop_tear_dialog.confirmed.connect(_shop_tear_dialog.queue_free)
	_shop_tear_dialog.canceled.connect(_shop_tear_dialog.queue_free)
	_shop_tear_dialog.close_requested.connect(_shop_tear_dialog.queue_free)
	ordinary_shop_layer.add_child(_shop_tear_dialog)
	if DisplayServer.get_name() != "headless":
		_shop_tear_dialog.popup_centered(Vector2i(520, 300)) # 撕卡选择窗口的初始宽高


func _refresh_shop_tear_sticker_options(_selected_index: int, card_picker: OptionButton, pickers: Array[OptionButton], cards: Array[OwnedCard]) -> void:
	var selected_id := String(card_picker.get_item_metadata(card_picker.selected))
	var owned: OwnedCard
	for candidate: OwnedCard in cards:
		if String(candidate.instance_id) == selected_id:
			owned = candidate
			break
	var stickers := _tearable_stickers(owned)
	for picker: OptionButton in pickers:
		picker.clear()
		picker.add_item("不返还")
		picker.set_item_metadata(0, "")
		for state: Dictionary in stickers:
			picker.add_item(String(state.get("emblem_id", "")))
			picker.set_item_metadata(picker.item_count - 1, String(state.get("instance_id", "")))


func _confirm_shop_tear_selection(card_picker: OptionButton, pickers: Array[OptionButton], cards: Array[OwnedCard]) -> void:
	var selected_cards_id := String(card_picker.get_item_metadata(card_picker.selected))
	var owned: OwnedCard
	for candidate: OwnedCard in cards:
		if String(candidate.instance_id) == selected_cards_id:
			owned = owned_card_collection.get_by_instance_id(candidate.instance_id)
			break
	if owned == null:
		ordinary_shop_status.text = "所选卡牌已不存在"
		_shop_tear_dialog.queue_free()
		return
	var chosen_ids: Array[StringName] = []
	for picker: OptionButton in pickers:
		if picker.selected <= 0:
			continue
		var sticker_id := StringName(String(picker.get_item_metadata(picker.selected)))
		if chosen_ids.has(sticker_id):
			ordinary_shop_status.text = "同一枚贴纸不能重复选择"
			return
		chosen_ids.append(sticker_id)
	if chosen_ids.is_empty():
		ordinary_shop_status.text = "至少选择一枚贴纸"
		return
	var attached := _tearable_stickers(owned)
	var selected_states: Array[Dictionary] = []
	var returned_names := PackedStringArray()
	var destroyed_names := PackedStringArray()
	for state: Dictionary in attached:
		var id := StringName(String(state.get("instance_id", "")))
		if chosen_ids.has(id):
			var returned_state := state.duplicate(true)
			returned_state.erase("grid_x")
			returned_state.erase("grid_y")
			returned_state.erase("grid_span")
			selected_states.append(returned_state)
			returned_names.append(String(state.get("emblem_id", "")))
		else:
			destroyed_names.append(String(state.get("emblem_id", "")))
	if selected_states.size() != chosen_ids.size():
		ordinary_shop_status.text = "所选贴纸已变化"
		return
	if not emblem_library.can_add_stickers(selected_states):
		ordinary_shop_status.text = "工具箱空间不足，撕卡没有执行"
		return
	var prices := (ordinary_shop_service.config.get("tear_service", {}) as Dictionary).get("prices_by_return_count", {}) as Dictionary
	var price := int(prices.get(str(selected_states.size()), 0))
	if run_reward_state.gold < price:
		ordinary_shop_status.text = "金币不足：返还%d枚贴纸需要%d金币" % [selected_states.size(), price]
		return
	var returned_equipment: PackedStringArray = _equipment_returned_by_host(owned.instance_id)
	var confirm := ConfirmationDialog.new()
	confirm.title = "确认撕卡"
	confirm.dialog_text = "永久销毁卡牌：%s\n返还贴纸：%s\n随卡销毁的贴纸：%s\n返回收藏的装备：%s\n总费用：%d金币" % [owned.card_data.display_name, "、".join(returned_names), "、".join(destroyed_names) if not destroyed_names.is_empty() else "无", "、".join(returned_equipment) if not returned_equipment.is_empty() else "无", price]
	confirm.get_ok_button().text = "确认销毁并返还"
	confirm.get_cancel_button().text = "取消"
	confirm.confirmed.connect(_execute_shop_tear.bind(owned.instance_id, selected_states, price))
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	confirm.close_requested.connect(confirm.queue_free)
	ordinary_shop_layer.add_child(confirm)
	if DisplayServer.get_name() != "headless":
		confirm.popup_centered(Vector2i(540, 240)) # 撕卡确认窗口的初始宽高
	_shop_tear_dialog.queue_free()


func _execute_shop_tear(instance_id: StringName, selected_states: Array[Dictionary], price: int) -> void:
	var owned := owned_card_collection.get_by_instance_id(instance_id)
	if owned == null or run_reward_state.gold < price or not emblem_library.can_add_stickers(selected_states):
		ordinary_shop_status.text = "撕卡条件已变化；没有扣费或销毁卡牌"
		return
	var saved_collection := owned_card_collection.capture_state()
	var saved_inventory: Array[Dictionary] = emblem_library.get_inventory_state()
	for state: Dictionary in selected_states:
		var sticker_id := StringName(String(state.get("instance_id", "")))
		var found := _remove_owned_sticker_instance(owned, sticker_id)
		if found.is_empty():
			owned_card_collection.restore_state(saved_collection)
			emblem_library.restore_inventory_state(saved_inventory)
			ordinary_shop_status.text = "贴纸实例已变化，交易回滚"
			return
	for state: Dictionary in selected_states:
		if not emblem_library.return_sticker(state):
			owned_card_collection.restore_state(saved_collection)
			emblem_library.restore_inventory_state(saved_inventory)
			ordinary_shop_status.text = "工具箱接收失败，交易回滚"
			return
	_remove_owned_instance_from_rows(instance_id)
	prepared_spell_instance_ids.erase(instance_id)
	resource_board_state.deployments.get("player", {}).erase(String(instance_id))
	owned_card_collection.remove_by_instance_id(instance_id)
	run_reward_state.gold -= price
	_remove_missing_equipment_from_board()
	_sync_legacy_collection_cards()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	ordinary_shop_status.text = "已销毁卡牌并返还贴纸：%s" % "、".join(_shop_sticker_names(selected_states))


func _card_has_tearable_stickers(owned: OwnedCard) -> bool:
	return owned != null and not _tearable_stickers(owned).is_empty()


func _tearable_stickers(owned: OwnedCard) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if owned == null:
		return result
	for state: Dictionary in owned.emblem_slots + owned.rune_stickers:
		if not state.is_empty() and not String(state.get("emblem_id", "")).is_empty():
			result.append(state.duplicate(true))
	return result


func _remove_owned_sticker_instance(owned: OwnedCard, instance_id: StringName) -> Dictionary:
	for index: int in owned.emblem_slots.size():
		if StringName(String(owned.emblem_slots[index].get("instance_id", ""))) == instance_id:
			var removed := owned.emblem_slots[index].duplicate(true)
			owned.set_emblem_slot(index, {})
			return removed
	for index: int in owned.rune_stickers.size():
		if StringName(String(owned.rune_stickers[index].get("instance_id", ""))) == instance_id:
			var removed := owned.rune_stickers[index].duplicate(true)
			owned.set_rune_sticker(index, {})
			return removed
	return {}


func _shop_card_names(cards: Array[CardData]) -> PackedStringArray:
	var names := PackedStringArray()
	for card: CardData in cards:
		names.append(card.display_name)
	return names


func _shop_sticker_names(states: Array[Dictionary]) -> PackedStringArray:
	var names := PackedStringArray()
	for state: Dictionary in states:
		names.append(String(state.get("emblem_id", "")))
	return names


func _open_shop_sell_dialog() -> void:
	if not ordinary_shop_open:
		return
	_shop_sell_dialog = AcceptDialog.new()
	_shop_sell_dialog.title = "出售收藏卡牌"
	_shop_sell_dialog.dialog_text = "选择要出售的卡牌。卡牌附着贴纸随卡销毁；所装备的装备返回收藏。"
	_shop_sell_dialog.get_ok_button().text = "关闭"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4) # 出售卡牌按钮之间的纵向间距
	_shop_sell_dialog.add_child(list)
	for owned: OwnedCard in owned_card_collection.get_cards():
		var button := Button.new()
		var hosted_squad := _get_squad_for_owned_instance(owned.instance_id)
		var must_split := hosted_squad != null and hosted_squad.get_card_count() > 1
		button.text = "%s · %d金币%s" % [owned.card_data.display_name, _shop_card_sale_price(owned), "（请先拆队）" if must_split else ""]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = must_split
		button.tooltip_text = "小队成员必须先拆为单卡" if must_split else ""
		button.pressed.connect(_confirm_shop_sale.bind(owned.instance_id))
		list.add_child(button)
	ordinary_shop_layer.add_child(_shop_sell_dialog)
	_shop_sell_dialog.confirmed.connect(_shop_sell_dialog.queue_free)
	_shop_sell_dialog.close_requested.connect(_shop_sell_dialog.queue_free)
	if DisplayServer.get_name() != "headless":
		_shop_sell_dialog.popup_centered(Vector2i(520, 520)) # 出售清单窗口的初始宽高


func _shop_card_sale_price(owned: OwnedCard) -> int:
	if owned == null or owned.card_data == null:
		return 0
	var sale_config := ordinary_shop_service.config.get("card_sale", {}) as Dictionary
	var base_prices := sale_config.get("base_prices", {}) as Dictionary
	var price := int(base_prices.get(["I", "II", "III", "IV", "V"][int(owned.card_data.rarity)], 1))
	if owned.card_data.card_type == CardData.CardType.SPELL:
		var maximum_durability := maxi(int(owned.card_data.rarity) + 1, 1)
		price = ceili(float(price * maxi(owned.spell_durability, 0)) / float(maximum_durability))
	for state: Dictionary in owned.emblem_slots + owned.rune_stickers:
		if not state.is_empty():
			price += int(sale_config.get("sticker_bonus", 1))
	for revealed: bool in owned.rune_revealed:
		if revealed:
			price += int(sale_config.get("revealed_rune_bonus", 1))
	for state: Dictionary in owned.wound_slots:
		if not state.is_empty():
			price -= int(sale_config.get("wound_penalty", 1))
	return maxi(price, int(sale_config.get("minimum_price", 1)))


func _confirm_shop_sale(instance_id: StringName) -> void:
	var owned := owned_card_collection.get_by_instance_id(instance_id)
	if owned == null:
		return
	var hosted_squad := _get_squad_for_owned_instance(instance_id)
	if hosted_squad != null and hosted_squad.get_card_count() > 1:
		ordinary_shop_status.text = "小队成员必须先拆成单卡，不能直接出售整队或队员"
		return
	var value := _shop_card_sale_price(owned)
	var returned_equipment := PackedStringArray()
	var sold_equipment := PackedStringArray()
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			if squad.get_card_data_for_owned_instance(instance_id) != null and squad.get_equipped_item() != null:
				returned_equipment.append(squad.get_equipped_item().card_data.display_name)
			elif squad.get_equipped_item() != null and squad.get_equipped_item().instance_id == instance_id:
				sold_equipment.append(squad.get_equipped_item().card_data.display_name)
	var confirm := ConfirmationDialog.new()
	confirm.title = "确认出售卡牌"
	confirm.dialog_text = "出售：%s\n获得：%d金币\n随卡出售的贴纸：%s\n返还收藏的装备：%s\n从战场解除的售出装备：%s" % [owned.card_data.display_name, value, "、".join(_shop_sticker_names(_tearable_stickers(owned))) if not _tearable_stickers(owned).is_empty() else "无", "、".join(returned_equipment) if not returned_equipment.is_empty() else "无", "、".join(sold_equipment) if not sold_equipment.is_empty() else "无"]
	confirm.get_ok_button().text = "确认出售"
	confirm.confirmed.connect(_execute_shop_sale.bind(instance_id, value))
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	confirm.close_requested.connect(confirm.queue_free)
	ordinary_shop_layer.add_child(confirm)
	if is_instance_valid(_shop_sell_dialog):
		_shop_sell_dialog.hide()
		_shop_sell_dialog.queue_free()
	if DisplayServer.get_name() != "headless":
		confirm.popup_centered(Vector2i(460, 210)) # 出售确认窗口的初始宽高


func _execute_shop_sale(instance_id: StringName, expected_value: int) -> void:
	var owned := owned_card_collection.get_by_instance_id(instance_id)
	var hosted_squad := _get_squad_for_owned_instance(instance_id)
	if owned == null or _shop_card_sale_price(owned) != expected_value or (hosted_squad != null and hosted_squad.get_card_count() > 1):
		ordinary_shop_status.text = "出售条件已变化，没有销毁卡牌"
		return
	var sold_value := expected_value
	_remove_owned_instance_from_rows(instance_id)
	prepared_spell_instance_ids.erase(instance_id)
	resource_board_state.deployments.get("player", {}).erase(String(instance_id))
	owned_card_collection.remove_by_instance_id(instance_id)
	run_reward_state.add_gold(sold_value)
	_remove_missing_equipment_from_board()
	_sync_legacy_collection_cards()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	ordinary_shop_status.text = "已出售%s，获得%d金币" % [owned.card_data.display_name, sold_value]
	_refresh_ordinary_shop_panel()
	_refresh_resource_preparation_trays()


func _get_squad_for_owned_instance(instance_id: StringName) -> SquadData:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad != null and squad.get_card_data_for_owned_instance(instance_id) != null:
				return squad
	return null


func _equipment_returned_by_host(instance_id: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad != null and squad.get_card_data_for_owned_instance(instance_id) != null and squad.get_equipped_item() != null:
				result.append(squad.get_equipped_item().card_data.display_name)
	return result


func _remove_owned_instance_from_rows(instance_id: StringName) -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads().duplicate():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			var member_data := squad.get_card_data_for_owned_instance(instance_id)
			var equipped := squad.get_equipped_item()
			if equipped != null and equipped.instance_id == instance_id:
				squad.unequip_item()
				slot.set_squad_data(squad)
			if member_data != null:
				if squad.get_equipped_item() != null:
					squad.unequip_item()
					slot.set_squad_data(squad)
				row.remove_card_from_squad(slot, member_data)


func _can_accept_shop_sticker_offer(offer: Dictionary) -> bool:
	var raw_stickers := offer.get("stickers", []) as Array
	if raw_stickers.size() != int((ordinary_shop_service.config.get("sticker_pack", {}) as Dictionary).get("sticker_count", 5)):
		return false
	var states: Array[Dictionary] = []
	var next_id := _next_developer_emblem_instance
	for sticker: Dictionary in raw_stickers:
		var id := StringName(String(sticker.get("id", "")))
		if id == &"万能贴纸" and _has_universal_sticker_in_collection_or_bag():
			return false
		states.append({
			"instance_id": "shop_preview_%06d" % next_id,
			"emblem_id": id,
			"temporary": false,
			"source": "ordinary_shop",
			"element_sticker": sticker.get("target", "emblem") == "rune",
		})
		next_id += 1
	return emblem_library.can_add_stickers(states)


func _build_escape_pause_menu() -> void:
	_escape_pause_menu = ESCAPE_PAUSE_MENU_SCRIPT.new() as EscapePauseMenu
	_escape_pause_menu.name = "EscapePauseMenu"
	_escape_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_escape_pause_menu.z_index = ESCAPE_PAUSE_MENU_Z_INDEX
	_escape_pause_menu.escape_pressed.connect(_on_escape_pause_menu_requested)
	_escape_pause_menu.tool_requested.connect(_on_escape_menu_tool_requested)
	_escape_pause_menu.return_requested.connect(_close_escape_pause_menu)
	_escape_pause_menu.restore_requested.connect(_on_escape_menu_restore_requested)
	_escape_pause_menu.target_priority_display_changed.connect(
		_set_battle_target_priority_display_enabled
	)
	add_child(_escape_pause_menu)


func _build_click_carry_layer() -> void:
	_click_carry_layer = Control.new()
	_click_carry_layer.name = "ClickCarryLayer"
	_click_carry_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_click_carry_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_carry_layer.z_index = 4096
	add_child(_click_carry_layer)


func _build_resource_preparation_trays(parent: Control) -> void:
	player_resource_tray = RESOURCE_PREPARATION_TRAY_SCRIPT.new()
	player_resource_tray.configure(resource_board_state, "player")
	player_resource_tray.position = PLAYER_RESOURCE_TRAY_POSITION
	player_resource_tray.z_index = 150
	player_resource_tray.drop_requested.connect(_on_resource_tray_drop_requested.bind("player"))
	player_resource_tray.click_carry_requested.connect(_on_click_carry_requested)
	parent.add_child(player_resource_tray)
	enemy_resource_tray = RESOURCE_PREPARATION_TRAY_SCRIPT.new()
	enemy_resource_tray.configure(resource_board_state, "enemy")
	enemy_resource_tray.position = ENEMY_RESOURCE_TRAY_POSITION
	enemy_resource_tray.z_index = 150
	enemy_resource_tray.set_drop_enabled(false)
	parent.add_child(enemy_resource_tray)


func _initialize_resource_level_if_needed() -> void:
	if resource_board_state.level_id.is_empty():
		var level_rng := RandomNumberGenerator.new()
		level_rng.randomize()
		var initial_board := ResourceBoardState.new()
		if not initial_board.initialize_level(&"level_000001", level_rng):
			push_error("无法初始化首关资源区")
			return
		var generation := initial_board.generate_level_resources(_get_resource_definitions(), level_rng)
		if not bool(generation.get("success", false)):
			push_error("首关资源生成失败：%s" % generation.get("reason", "unknown"))
			return
		resource_board_state = initial_board


func _refresh_resource_preparation_trays() -> void:
	var cards := owned_card_collection.get_cards()
	if current_phase == GamePhase.PREPARE:
		if is_instance_valid(player_resource_tray): player_resource_tray.clear_battle_health()
		if is_instance_valid(enemy_resource_tray): enemy_resource_tray.clear_battle_health()
	if is_instance_valid(player_resource_tray):
		player_resource_tray.configure(resource_board_state, "player")
		var player_resource_cards := cards.duplicate()
		player_resource_cards.append_array(resource_board_state.get_level_resource_cards("player"))
		player_resource_tray.set_owned_cards(player_resource_cards)
		player_resource_tray.set_drop_enabled(current_phase == GamePhase.PREPARE)
	if is_instance_valid(enemy_resource_tray):
		enemy_resource_tray.configure(resource_board_state, "enemy")
		enemy_resource_tray.set_owned_cards(resource_board_state.get_level_resource_cards("enemy"))


func _set_resource_trays_carry_active(active: bool) -> void:
	for tray_value in [player_resource_tray, enemy_resource_tray]:
		var tray := tray_value as ResourcePreparationTray
		if is_instance_valid(tray): tray.set_carry_active(active)


func start_new_resource_level(level_id: StringName, rng: RandomNumberGenerator) -> bool:
	var advancing_settled_run := (
		current_phase == GamePhase.RESULT and bool(_last_battle_settlement_result.get("success", false))
	) or (current_phase == GamePhase.PREPARE and not run_reward_state.pending_next_level_from_id.is_empty())
	if (current_phase != GamePhase.PREPARE and not advancing_settled_run) or level_id.is_empty() or rng == null:
		return false
	# 先在候选状态中生成完整新关；失败时保留当前关卡，不留下半生成数据。
	var candidate := ResourceBoardState.new()
	if not candidate.initialize_level(level_id, rng):
		return false
	var generation := candidate.generate_level_resources(_get_resource_definitions(), rng)
	if not bool(generation.get("success", false)):
		push_error("新关资源生成失败：%s" % generation.get("reason", "unknown"))
		return false
	resource_board_state = candidate
	if is_instance_valid(player_resource_tray): player_resource_tray.clear_battle_health()
	if is_instance_valid(enemy_resource_tray): enemy_resource_tray.clear_battle_health()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	return true


func _get_resource_definitions() -> Array[CardData]:
	var result: Array[CardData] = []
	for definition: CardData in _build_card_definition_registry().values():
		if definition.card_type == CardData.CardType.RESOURCE:
			result.append(definition)
	return result


func _on_resource_tray_drop_requested(data: Dictionary, resolution: Dictionary, owner_side: String) -> void:
	_commit_resource_preparation_drop(data, resolution, owner_side)


func _commit_resource_preparation_drop(data: Dictionary, resolution: Dictionary, owner_side: String = "player") -> bool:
	if current_phase != GamePhase.PREPARE or owner_side != "player":
		return false
	var owned := data.get("owned_card") as OwnedCard
	if owned == null or owned.card_data == null or owned.card_data.card_type != CardData.CardType.RESOURCE or owned_card_collection.get_by_instance_id(owned.instance_id) != owned:
		return false
	if data.get("source_type") == &"collection" and _is_owned_card_deployed(owned):
		return false
	var tray := player_resource_tray as ResourcePreparationTray
	if not tray.commit_drop(data, resolution):
		return false
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	return true


func _find_resource_tray_at(pointer_global_position: Vector2) -> ResourcePreparationTray:
	for tray_value in [player_resource_tray, enemy_resource_tray]:
		var tray := tray_value as ResourcePreparationTray
		if is_instance_valid(tray) and tray.is_drop_position_global(pointer_global_position):
			return tray
	return null


func _build_spell_preparation_tray(parent: Control) -> void:
	spell_preparation_tray = SPELL_PREPARATION_TRAY_SCRIPT.new() as Control
	spell_preparation_tray.name = "SpellPreparationTray"
	spell_preparation_tray.position = SPELL_PREPARATION_TRAY_POSITION
	spell_preparation_tray.z_index = 150
	parent.add_child(spell_preparation_tray)
	spell_preparation_tray.call(
		"set_drop_index_resolver", Callable(self, "_resolve_prepared_spell_drop_index")
	)
	spell_preparation_tray.drop_requested.connect(_on_spell_preparation_drop_requested)
	spell_preparation_tray.click_carry_requested.connect(_on_click_carry_requested)
	spell_preparation_tray.inspection_requested.connect(_on_card_inspection_requested)


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
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.z_index = depth
	parent.add_child(layer)
	# TextureRect 入树时可能按纹理最小尺寸重算 Rect，因此入树后写回设计坐标。
	layer.position = pos
	layer.size = node_size
	return layer


func _make_character_texture(region: Rect2) -> AtlasTexture:
	return _make_atlas_texture(CHARACTER_SHEET_TEXTURE, region)


func _make_player_avatar_frame_texture(frame_index: int) -> AtlasTexture:
	return _make_atlas_texture(
		PLAYER_AVATAR_TURN_TEXTURE,
		Rect2(PLAYER_AVATAR_FRAME_SIZE.x * frame_index, 0.0, PLAYER_AVATAR_FRAME_SIZE.x, PLAYER_AVATAR_FRAME_SIZE.y)
	)


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
	avatar.stretch_mode = TextureRect.STRETCH_SCALE
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.z_index = 100
	parent.add_child(avatar)
	avatar.position = Vector2(38, 0)
	avatar.size = CHARACTER_FRONT_REGION.size


func _build_battle_hud(parent: Control) -> void:
	battle_pause_button = _make_button(
		"BattlePauseButton",
		"⏸️",
		BATTLE_PAUSE_BUTTON_POSITION,
		BATTLE_PAUSE_BUTTON_SIZE,
		true
	)
	battle_pause_button.z_index = 200
	battle_pause_button.visible = false
	battle_pause_button.process_mode = Node.PROCESS_MODE_ALWAYS
	battle_pause_button.tooltip_text = "暂停战斗"
	parent.add_child(battle_pause_button)
	battle_pause_button.pressed.connect(_on_battle_pause_button_pressed)

	var speed_bar := HBoxContainer.new()
	speed_bar.name = "BattleSpeedBar"
	speed_bar.unique_name_in_owner = true
	speed_bar.position = BATTLE_SPEED_BUTTON_POSITION
	speed_bar.size = BATTLE_SPEED_BUTTON_SIZE
	speed_bar.z_index = 200
	speed_bar.visible = false
	speed_bar.add_theme_constant_override("separation", 1)
	parent.add_child(speed_bar)
	for speed_index: int in BATTLE_SPEED_MULTIPLIERS.size():
		var multiplier := BATTLE_SPEED_MULTIPLIERS[speed_index]
		var speed_button := _make_button(
			"Speed%d" % speed_index,
			"%.1f×" % multiplier if multiplier < 1.0 else "%d×" % int(multiplier),
			BATTLE_SPEED_BUTTON_POSITION,
			Vector2(BATTLE_SPEED_BUTTON_SIZE.x / 4.0 - 1.0, BATTLE_SPEED_BUTTON_SIZE.y),
			true
		)
		speed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed_button.toggle_mode = true
		speed_button.tooltip_text = "直接切换到 %.1f× 战斗播放速度" % multiplier
		speed_bar.add_child(speed_button)
		speed_button.pressed.connect(set_battle_speed.bind(speed_index))
	var timer := _make_label("战斗 00:00.0", BATTLE_TIMER_POSITION, BATTLE_TIMER_SIZE)
	timer.name = "BattleTimerLabel"
	timer.unique_name_in_owner = true
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer.add_theme_font_size_override("font_size", 16)
	timer.add_theme_color_override("font_color", Color("f5df9b"))
	timer.add_theme_color_override("font_outline_color", Color("231d18"))
	timer.add_theme_constant_override("outline_size", 2)
	timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer.z_index = 200
	timer.visible = false
	parent.add_child(timer)

	var seed_panel := PanelContainer.new()
	seed_panel.name = "BattleSeedPanel"
	seed_panel.unique_name_in_owner = true
	seed_panel.position = BATTLE_SEED_PANEL_POSITION
	seed_panel.size = BATTLE_SEED_PANEL_SIZE
	seed_panel.custom_minimum_size = BATTLE_SEED_PANEL_SIZE
	seed_panel.z_index = 200
	seed_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var seed_style := StyleBoxFlat.new()
	seed_style.bg_color = Color(0.025, 0.035, 0.043, 0.9)
	seed_style.border_color = Color(0.31, 0.55, 0.58, 0.9)
	seed_style.set_border_width_all(1)
	seed_style.set_corner_radius_all(4)
	seed_style.content_margin_left = 6.0
	seed_style.content_margin_top = 4.0
	seed_style.content_margin_right = 6.0
	seed_style.content_margin_bottom = 4.0
	seed_panel.add_theme_stylebox_override("panel", seed_style)
	parent.add_child(seed_panel)

	var seed_layout := VBoxContainer.new()
	seed_layout.add_theme_constant_override("separation", 2)
	seed_panel.add_child(seed_layout)
	var seed_title := Label.new()
	seed_title.text = "战斗种子"
	seed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_title.add_theme_font_override("font", BATTLE_LOG_FONT)
	seed_title.add_theme_font_size_override("font_size", 10)
	seed_title.add_theme_color_override("font_color", Color("f5df9b"))
	seed_layout.add_child(seed_title)
	var seed_controls := HBoxContainer.new()
	seed_controls.add_theme_constant_override("separation", 4)
	seed_layout.add_child(seed_controls)
	var seed_spin := SpinBox.new()
	seed_spin.name = "BattleSeedSpin"
	seed_spin.unique_name_in_owner = true
	seed_spin.min_value = 0.0
	seed_spin.max_value = float(BATTLE_SEED_MAX)
	seed_spin.step = 1.0
	seed_spin.allow_greater = false
	seed_spin.allow_lesser = false
	seed_spin.update_on_text_changed = true
	seed_spin.custom_minimum_size = Vector2(126, 26)
	seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_spin.tooltip_text = "修改后用于下一场战斗；相同阵容和种子可复现相同随机结果"
	seed_controls.add_child(seed_spin)
	var seed_random := Button.new()
	seed_random.name = "BattleSeedRandomButton"
	seed_random.unique_name_in_owner = true
	seed_random.text = "随机"
	seed_random.custom_minimum_size = Vector2(54, 26)
	seed_random.tooltip_text = "生成一个新的战斗种子"
	seed_controls.add_child(seed_random)

	var log_panel := PanelContainer.new()
	log_panel.name = "BattleLogPanel"
	log_panel.unique_name_in_owner = true
	log_panel.position = BATTLE_LOG_POSITION
	log_panel.size = BATTLE_LOG_SIZE
	log_panel.custom_minimum_size = BATTLE_LOG_SIZE
	log_panel.z_index = 200
	log_panel.visible = false
	log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.043, 0.9)
	panel_style.border_color = Color(0.31, 0.55, 0.58, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 7.0
	panel_style.content_margin_top = 5.0
	panel_style.content_margin_right = 7.0
	panel_style.content_margin_bottom = 5.0
	log_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(log_panel)

	var log_layout := VBoxContainer.new()
	log_layout.add_theme_constant_override("separation", 3)
	log_panel.add_child(log_layout)
	var log_title := Label.new()
	log_title.name = "BattleLogTitle"
	log_title.unique_name_in_owner = true
	log_title.text = "战斗日志"
	log_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_title.add_theme_font_override("font", BATTLE_LOG_FONT)
	log_title.add_theme_font_size_override("font_size", 16)
	log_title.add_theme_color_override("font_color", Color("f5df9b"))
	log_layout.add_child(log_title)
	var log_text := RichTextLabel.new()
	log_text.name = "BattleLogText"
	log_text.unique_name_in_owner = true
	log_text.bbcode_enabled = true
	log_text.meta_underlined = true
	log_text.fit_content = false
	log_text.scroll_active = true
	log_text.scroll_following = true
	log_text.selection_enabled = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_override("normal_font", BATTLE_LOG_FONT)
	log_text.add_theme_font_size_override("normal_font_size", 8)
	log_text.add_theme_color_override("default_color", Color("d9e5df"))
	log_layout.add_child(log_text)

	var effect_layer := Control.new()
	effect_layer.name = "BattleEffectLayer"
	effect_layer.unique_name_in_owner = true
	effect_layer.position = Vector2.ZERO
	effect_layer.size = Vector2(1280, 720)
	effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_layer.z_index = EFFECT_LAYER_Z_INDEX
	parent.add_child(effect_layer)


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
		player_avatar.texture_normal = _make_player_avatar_frame_texture(0)
		player_avatar.position = PLAYER_AVATAR_POSITION
		player_avatar.size = PLAYER_AVATAR_FRAME_SIZE
		player_avatar.ignore_texture_size = true
		player_avatar.stretch_mode = TextureButton.STRETCH_SCALE
		player_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		player_avatar.tooltip_text = "切换敌我战场与收藏视角"
		player_avatar.z_index = 100
		section.add_child(player_avatar)
		player_avatar.position = PLAYER_AVATAR_POSITION
		player_avatar.size = PLAYER_AVATAR_FRAME_SIZE
		var volume_label := _make_label("音量", BATTLE_VOLUME_POSITION, Vector2(34, 18))
		volume_label.name = "BattleVolumeLabel"
		volume_label.unique_name_in_owner = true
		volume_label.add_theme_font_size_override("font_size", 9)
		volume_label.add_theme_color_override("font_color", Color("f5df9b"))
		volume_label.z_index = 101
		section.add_child(volume_label)
		var volume_slider := HSlider.new()
		volume_slider.name = "BattleVolumeSlider"
		volume_slider.unique_name_in_owner = true
		volume_slider.position = BATTLE_VOLUME_POSITION + Vector2(36, 0)
		volume_slider.size = Vector2(162, 18)
		volume_slider.min_value = 0.0
		volume_slider.max_value = 100.0
		volume_slider.step = 1.0
		volume_slider.value = 25.0 # 音量滑条默认百分比，0 为静音
		volume_slider.tooltip_text = "全局音量：0 为静音，100 为最大音量"
		volume_slider.z_index = 101
		section.add_child(volume_slider)
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
		var start_button := _make_button(
			"StartBattleButton",
			"开始战斗",
			START_BATTLE_BUTTON_POSITION,
			START_BATTLE_BUTTON_SIZE,
			true
		)
		start_button.tooltip_text = "锁定准备阵容并开始基础自动战斗"
		start_button.z_index = 200
		section.add_child(start_button)


func _build_battle_result_panel() -> void:
	# 详细战绩直接覆盖在恢复后的卡牌上，这里只保留不遮挡战场的总结果入口。
	var panel := Panel.new()
	panel.name = "BattleResultPanel"
	panel.unique_name_in_owner = true
	panel.position = BATTLE_RESULT_PANEL_POSITION
	panel.size = BATTLE_RESULT_PANEL_SIZE
	panel.z_index = 4000
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.047, 0.055, 0.96)
	style.border_color = Color(0.82, 0.68, 0.31, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var title := _make_label("战斗结算", Vector2(10, 5), Vector2(150, 30))
	title.name = "BattleResultLabel"
	title.unique_name_in_owner = true
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	panel.add_child(title)
	var placeholder := RichTextLabel.new()
	placeholder.name = "BattleResultPlaceholder"
	placeholder.unique_name_in_owner = true
	placeholder.position = Vector2(10, 36)
	placeholder.size = Vector2(150, 140)
	placeholder.text = "卡面：本局统计\n永久成长：无\n本场奖励：无"
	placeholder.fit_content = false
	placeholder.scroll_active = true
	placeholder.add_theme_font_override("normal_font", BATTLE_LOG_FONT)
	placeholder.add_theme_font_size_override("normal_font_size", 11)
	placeholder.add_theme_color_override("default_color", Color("e8eee5"))
	panel.add_child(placeholder)
	var export_button := _make_button(
		"ExportBattleDataButton",
		"导出战斗数据",
		Vector2(10, 182),
		Vector2(150, 27),
		true
	)
	panel.add_child(export_button)
	var export_status := _make_label("", Vector2(9, 212), Vector2(152, 30))
	export_status.name = "BattleExportStatusLabel"
	export_status.unique_name_in_owner = true
	export_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	export_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	export_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_status.add_theme_font_size_override("font_size", 9)
	panel.add_child(export_status)
	var restart := _make_button(
		"RestartBattleButton",
		"重新开始",
		Vector2(25, 245),
		Vector2(120, 27),
		true
	)
	panel.add_child(restart)
	var continue_button := _make_button("ContinueNextLevelButton", "继续下一关", Vector2(25, 245), Vector2(120, 27), true)
	continue_button.visible = false
	panel.add_child(continue_button)
	_assign_runtime_owner(panel)
	_build_ground_reward_panel()


func _build_ground_reward_panel() -> void:
	ground_reward_panel = Panel.new()
	ground_reward_panel.name = "GroundRewardPanel"
	ground_reward_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ground_reward_panel.position = Vector2(-230, -180)
	ground_reward_panel.size = Vector2(460, 360)
	ground_reward_panel.z_index = 4000
	ground_reward_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ground_reward_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.047, 0.055, 0.98)
	style.border_color = Color(0.82, 0.68, 0.31, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	ground_reward_panel.add_theme_stylebox_override("panel", style)
	add_child(ground_reward_panel)
	var title := _make_label("地面临时背包", Vector2(18, 8), Vector2(424, 30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	ground_reward_panel.add_child(title)
	var description := _make_label("工作包满出的纹章保存在这里。领取、装备或丢弃后才能继续。", Vector2(18, 40), Vector2(424, 32))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 11)
	ground_reward_panel.add_child(description)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(18, 78)
	scroll.size = Vector2(424, 264)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	ground_reward_panel.add_child(scroll)
	ground_reward_list = VBoxContainer.new()
	ground_reward_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_reward_list.add_theme_constant_override("separation", 6)
	scroll.add_child(ground_reward_list)
	_assign_runtime_owner(ground_reward_panel)


func _build_battle_diagnostic_file_dialog() -> void:
	if is_instance_valid(battle_diagnostic_file_dialog):
		return
	battle_diagnostic_file_dialog = FileDialog.new()
	battle_diagnostic_file_dialog.name = "BattleDiagnosticSaveDialog"
	battle_diagnostic_file_dialog.title = "导出战斗数据"
	battle_diagnostic_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	battle_diagnostic_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	battle_diagnostic_file_dialog.filters = PackedStringArray(["*.json ; JSON 战斗数据"])
	battle_diagnostic_file_dialog.overwrite_warning_enabled = true
	battle_diagnostic_file_dialog.file_selected.connect(_save_battle_diagnostic_file)
	add_child(battle_diagnostic_file_dialog)
	var documents_path := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not DirAccess.dir_exists_absolute(documents_path):
		documents_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if DirAccess.dir_exists_absolute(documents_path):
		battle_diagnostic_file_dialog.current_dir = documents_path


func _on_export_battle_data_button_pressed() -> void:
	if (
		_battle_diagnostic_recorder == null
		or not _battle_diagnostic_recorder.is_complete
		or not is_instance_valid(battle_diagnostic_file_dialog)
	):
		_refresh_battle_diagnostic_export_button()
		return
	battle_diagnostic_file_dialog.current_file = _default_battle_diagnostic_filename()
	battle_diagnostic_file_dialog.popup_centered_ratio(0.72)


func _default_battle_diagnostic_filename() -> String:
	var project_version := String(ProjectSettings.get_setting("application/config/version", "unknown"))
	if project_version.is_empty():
		project_version = "unknown"
	project_version = project_version.replace("/", "_").replace("\\", "_").replace(" ", "_")
	var date_part := Time.get_datetime_string_from_system(false)
	date_part = date_part.replace("-", "").replace(":", "").replace("T", "_")
	return "project-card-battle-%s-godot%s.json" % [date_part, project_version]


func _save_battle_diagnostic_file(path: String) -> void:
	if _battle_diagnostic_recorder == null or not _battle_diagnostic_recorder.is_complete:
		_show_battle_diagnostic_message("没有可导出的完整战斗记录。")
		return
	var result := BattleDiagnosticSerializerScript.save_to_path(
		_battle_diagnostic_recorder.get_record_copy(),
		path
	)
	if not bool(result.get("success", false)):
		var failure_path := String(result.get("path", path))
		var failure_reason := String(result.get("reason", "unknown"))
		battle_export_status_label.text = "导出失败：%s" % failure_reason
		battle_export_status_label.tooltip_text = failure_path
		_show_battle_diagnostic_message(
			"写入战斗数据失败。\n路径：%s\n错误：%s" % [failure_path, result.get("error", "未知错误")]
		)
		return
	var saved_path := String(result.get("path", path))
	battle_export_status_label.text = "已保存：%s" % saved_path.get_file()
	battle_export_status_label.tooltip_text = saved_path
	play_area_label.text = "战斗数据已导出到：%s" % saved_path


func _show_battle_diagnostic_message(message: String) -> void:
	if not is_instance_valid(battle_diagnostic_message_dialog):
		battle_diagnostic_message_dialog = AcceptDialog.new()
		battle_diagnostic_message_dialog.name = "BattleDiagnosticMessageDialog"
		add_child(battle_diagnostic_message_dialog)
	battle_diagnostic_message_dialog.dialog_text = message
	battle_diagnostic_message_dialog.popup_centered()


func _refresh_battle_diagnostic_export_button() -> void:
	if not is_instance_valid(export_battle_data_button):
		return
	export_battle_data_button.disabled = (
		_battle_diagnostic_recorder == null
		or not _battle_diagnostic_recorder.is_complete
	)


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
	rarities.size = RARITY_FILTER_TEXTURE.get_size()
	rarities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.add_child(rarities)
	var elements := Control.new()
	elements.name = "ElementButtons"
	elements.unique_name_in_owner = true
	elements.position = ELEMENT_FILTER_POSITION
	elements.size = ELEMENT_FILTER_TEXTURE.get_size()
	elements.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter.add_child(elements)
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
	bookmark.stretch_mode = TextureButton.STRETCH_SCALE
	bookmark.tooltip_text = "最近使用的卡牌"
	bookmark.pivot_offset = bookmark.size * 0.5
	bookmark.z_index = -48
	section.add_child(bookmark)
	bookmark.position = book.position + RECENT_BOOKMARK_POSITION
	bookmark.size = RECENT_CARDS_BOOKMARK_TEXTURE.get_size()
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
	# 卡牌左上角图标和悬停抽出会越过卡位区域；收藏视口只负责定位，不负责裁切。
	viewport.clip_contents = false
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
	var badge: Variant = EmblemLibraryViewScript.new()
	badge.name = "BadgePanel"
	badge.unique_name_in_owner = true
	badge.position = TOOLBOX_POSITION
	badge.size = Vector2(195, 148)
	var sticker_definitions := EmblemLibraryData.get_definitions()
	for wound_definition: Dictionary in EmblemLibraryData.get_wound_definitions():
		wound_definition["status_kind"] = "wound"
		sticker_definitions.append(wound_definition)
	badge.set_definitions(sticker_definitions)
	badge.z_index = -48
	section.add_child(badge)
	emblem_library = badge
	_emblem_library_parent = section
	emblem_library.click_carry_requested.connect(_on_click_carry_requested)
	emblem_library.scraper_action_mode_requested.connect(_toggle_rune_scraper_mode)
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


# --- 场景初始化、阶段与全局状态 ---
func _ready() -> void:
	_battle_performance_trace_enabled = (
		"--trace-battle-performance" in OS.get_cmdline_user_args()
		or OS.get_environment("PROJECT_CARD_TRACE_BATTLE_PERFORMANCE") == "1"
	)
	set_process(true)
	if not has_node("WorldContent"):
		_build_scene_structure()
	battle_audio_service = BattleAudioServiceScript.new()
	battle_audio_service.name = "BattleAudioService"
	add_child(battle_audio_service)
	_bind_scene_nodes()
	_initialize_owned_card_collection()
	ordinary_shop_service = OrdinaryShopServiceScript.new()
	if ordinary_shop_service.load_config():
		var shop_seed := Time.get_ticks_usec()
		ordinary_shop_service.initialize(shop_seed)
		scraper_count = int((ordinary_shop_service.config.get("scraper", {}) as Dictionary).get("starting_count", 0))
		if is_instance_valid(emblem_library):
			emblem_library.set_scraper_count(scraper_count)
	_initialize_resource_level_if_needed()
	_refresh_resource_preparation_trays()
	_build_formula_popup()
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()
	drag_mode_button.toggled.connect(_on_drag_mode_toggled)
	player_avatar_button.pressed.connect(_on_player_avatar_button_pressed)
	search_edit.text_changed.connect(_on_search_text_changed)
	search_edit.text_submitted.connect(func(_text: String) -> void: apply_search())
	search_button.pressed.connect(apply_search)
	clear_search_button.pressed.connect(clear_search)
	left_edge_button.pressed.connect(func() -> void: turn_collection_page(current_collection_page - 1, &"edge"))
	right_edge_button.pressed.connect(func() -> void: turn_collection_page(current_collection_page + 1, &"edge"))
	recent_bookmark_button.pressed.connect(toggle_recent_bookmark)
	start_battle_button.pressed.connect(_on_start_battle_button_pressed)
	export_battle_data_button.pressed.connect(_on_export_battle_data_button_pressed)
	restart_battle_button.pressed.connect(_on_restart_battle_button_pressed)
	continue_next_level_button.pressed.connect(_on_continue_next_level_pressed)
	battle_seed_random_button.pressed.connect(_use_new_battle_seed)
	_use_new_battle_seed()
	battle_controller = BattleController.new() as BattleController
	battle_controller.name = "BattleController"
	battle_controller.use_projectile_timing = true
	battle_controller.performance_trace_enabled = _battle_performance_trace_enabled
	add_child(battle_controller)
	battle_controller.states_changed.connect(_on_battle_states_changed)
	battle_controller.projectile_launched.connect(_on_battle_projectile_launched)
	battle_controller.action_resolved.connect(_on_battle_action_resolved)
	battle_controller.effect_resolved.connect(_on_battle_effect_resolved)
	battle_controller.special_effect_resolved.connect(_on_battle_special_effect_resolved)
	battle_controller.direct_damage_resolved.connect(_on_battle_direct_damage_resolved)
	battle_controller.squad_defeated.connect(_request_battle_squad_departure)
	battle_controller.squad_revived.connect(_cancel_battle_squad_departure)
	battle_controller.battle_finished.connect(_on_battle_finished)
	battle_controller.spell_cast_started.connect(_on_spell_cast_started)
	battle_controller.spell_cast_finished.connect(_on_spell_cast_finished)
	_build_battle_diagnostic_file_dialog()
	_apply_battle_speed()
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
	celestial_indicators = CelestialIndicatorController.new()
	add_child(celestial_indicators)
	celestial_indicators.initialize(self)
	battle_controller.indicator_transferred.connect(celestial_indicators.animate_star_transfer)
	_refresh_preparation_effect_preview.call_deferred()
	_capture_startup_runtime_snapshot.call_deferred()
	_refresh_spell_preparation_tray()


func _capture_startup_runtime_snapshot() -> void:
	if not _startup_runtime_snapshot.is_empty():
		return
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	var display_mode: Variant = display_shell.get("current_display_mode") if is_instance_valid(display_shell) else null
	_startup_runtime_snapshot = {
		"collection": owned_card_collection.capture_state(),
		"resource_board_state": resource_board_state.capture_state(),
		"rows": {
			&"player_front": _duplicate_row_squads(front_row),
			&"player_back": _duplicate_row_squads(back_row),
			&"enemy_front": _duplicate_row_squads(enemy_front_row),
			&"enemy_back": _duplicate_row_squads(enemy_back_row),
		},
		"prepared_spell_instance_ids": prepared_spell_instance_ids.duplicate(),
		"sticker_inventory": emblem_library.get_inventory_state().duplicate(true),
		"next_developer_emblem_instance": _next_developer_emblem_instance,
		"scraper_count": scraper_count,
		"ordinary_shop_state": ordinary_shop_service.capture_state() if ordinary_shop_service != null else {},
		"indicator_inventory": celestial_indicators.capture_state(),
		"reward_state": run_reward_state.capture_state(),
		"settlement_journal": settlement_journal.capture_state(),
		"battle_snapshot": _battle_snapshot,
		"battle_seed": clampi(roundi(battle_seed_spin.value), 0, BATTLE_SEED_MAX),
		"battle_speed_index": battle_speed_index,
		"volume_percent": battle_volume_slider.value,
		"next_battle_instance_sequence": _next_battle_instance_sequence,
		"resume_battle_instance_id": _resume_battle_instance_id,
		"phase": current_phase,
		"world_view": current_world_view,
		"collection_page": current_collection_page,
		"bookmark_active": collection_bookmark_active,
		"regular_collection_page": _regular_collection_page_before_bookmark,
		"recent_cards": recently_returned_cards.duplicate(),
		"recent_owned_cards": recently_returned_owned_cards.duplicate(),
		"rarity_filters": active_rarity_filters.duplicate(),
		"element_filters": active_element_filters.duplicate(),
		"action_filters": active_action_filters.duplicate(),
		"card_type_filters": active_card_type_filters.duplicate(),
		"search_query": search_query,
		"selected_card": selected_card,
		"collection_effect_display_states": _collection_effect_display_states.duplicate(true),
		"toolbox_scroll": emblem_library.get_scroll_position(),
		"show_battle_target_priority": _show_battle_target_priority,
		"spell_preparation_capacity": spell_preparation_capacity,
		"manual_pause_requested": _manual_pause_requested,
		"special_spell_pause_requested": _special_spell_pause_requested,
		"tree_paused": get_tree().paused,
		"battle_effect_layer_visible": battle_effect_layer.visible,
		"chaos_reroll_day_token": _last_chaos_reroll_day_token,
		"display_mode": display_mode,
	}
	if is_instance_valid(_escape_pause_menu):
		_escape_pause_menu.set_restore_available(true)


func _restore_startup_runtime_snapshot() -> bool:
	if _startup_runtime_snapshot.is_empty():
		return false
	var snapshot := _startup_runtime_snapshot
	if not emblem_library.can_restore_inventory_state(snapshot["sticker_inventory"] as Array):
		return false
	var snapshot_shop: Dictionary = snapshot.get("ordinary_shop_state", {}) as Dictionary
	if ordinary_shop_service != null and not ordinary_shop_service.validate_saved_state(snapshot_shop):
		return false
	_cancel_click_carry()
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_native_carry_data = {}
	_native_carry_last_target = {}
	_clear_click_drop_feedback(false)
	_clear_page_turn_overlay()
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	if _player_avatar_turn_tween != null and _player_avatar_turn_tween.is_valid():
		_player_avatar_turn_tween.kill()
	if _recent_bookmark_tween != null and _recent_bookmark_tween.is_valid():
		_recent_bookmark_tween.kill()
	if _recent_bookmark_shake_tween != null and _recent_bookmark_shake_tween.is_valid():
		_recent_bookmark_shake_tween.kill()
	_clear_spell_cast_presentation()
	_close_card_inspection(true)
	if battle_controller != null:
		battle_controller.clear_battle()
	for child: Node in battle_effect_layer.get_children():
		child.queue_free()
	_clear_battle_log()
	_battle_generation += 1
	_completed_battle_departures.clear()
	_battle_departure_flush_queued = false
	_active_battle_departures = 0
	_pending_battle_result = BattleController.Result.NONE
	battle_departure_count = 0
	_next_direct_effect_log_id = 1
	_battle_state_slots.clear()
	_last_battle_settlement_result.clear()
	_last_run_persistence_result.clear()
	if not owned_card_collection.restore_state(snapshot["collection"] as Dictionary):
		push_error("本次启动快照中的OwnedCard集合无法恢复")
		return false
	_sync_legacy_collection_cards()
	if not emblem_library.restore_inventory_state(snapshot["sticker_inventory"] as Array):
		push_error("本次启动快照中的纹章与伤势库存无法恢复")
		return false
	emblem_library.set_scroll_position(int(snapshot.get("toolbox_scroll", 0)))
	emblem_library._refresh_entries()
	_last_minion_inspection_library_expanded = false
	_set_battle_target_priority_display_enabled(
		bool(snapshot.get("show_battle_target_priority", false))
	)
	_next_developer_emblem_instance = int(snapshot["next_developer_emblem_instance"])
	scraper_count = maxi(int(snapshot.get("scraper_count", 0)), 0)
	emblem_library.set_scraper_count(scraper_count)
	if ordinary_shop_service != null:
		var shop_snapshot := snapshot.get("ordinary_shop_state", {}) as Dictionary
		ordinary_shop_service.initialize(int(shop_snapshot.get("rng_state", Time.get_ticks_usec())), shop_snapshot)
	_refresh_ordinary_shop_panel()
	_last_chaos_reroll_day_token = snapshot["chaos_reroll_day_token"] as StringName
	_restore_row_from_snapshot(front_row, (snapshot["rows"] as Dictionary)[&"player_front"])
	_restore_row_from_snapshot(back_row, (snapshot["rows"] as Dictionary)[&"player_back"])
	_restore_row_from_snapshot(enemy_front_row, (snapshot["rows"] as Dictionary)[&"enemy_front"])
	_restore_row_from_snapshot(enemy_back_row, (snapshot["rows"] as Dictionary)[&"enemy_back"])
	celestial_indicators.restore_state(snapshot["indicator_inventory"] as Dictionary)
	if not resource_board_state.restore_state(snapshot.get("resource_board_state", {}) as Dictionary, _build_card_definition_registry()):
		push_error("本次启动快照中的资源板无法恢复")
		return false
	prepared_spell_instance_ids.assign(snapshot["prepared_spell_instance_ids"] as Array)
	spell_preparation_capacity = int(snapshot["spell_preparation_capacity"])
	run_reward_state.restore_state(snapshot["reward_state"] as Dictionary)
	settlement_journal.restore_state(snapshot["settlement_journal"] as Dictionary)
	_battle_snapshot = snapshot["battle_snapshot"] as BattlePreparationSnapshot
	_next_battle_instance_sequence = int(snapshot["next_battle_instance_sequence"])
	_resume_battle_instance_id = snapshot["resume_battle_instance_id"] as StringName
	battle_seed_spin.value = int(snapshot["battle_seed"])
	battle_speed_index = int(snapshot["battle_speed_index"])
	battle_volume_slider.set_value_no_signal(float(snapshot["volume_percent"]))
	battle_audio_service.set_master_volume_percent(battle_volume_slider.value)
	_apply_battle_speed()
	_manual_pause_requested = bool(snapshot["manual_pause_requested"])
	_inspection_pause_requested = false
	_special_spell_pause_requested = bool(snapshot["special_spell_pause_requested"])
	current_phase = int(snapshot["phase"]) as GamePhase
	selected_board_row = null
	selected_board_slot = null
	current_collection_page = int(snapshot["collection_page"])
	collection_bookmark_active = bool(snapshot["bookmark_active"])
	_regular_collection_page_before_bookmark = int(snapshot["regular_collection_page"])
	recently_returned_cards.assign(snapshot["recent_cards"] as Array)
	recently_returned_owned_cards.assign(snapshot["recent_owned_cards"] as Array)
	active_rarity_filters.assign(snapshot["rarity_filters"] as Array)
	active_element_filters.assign(snapshot["element_filters"] as Array)
	active_action_filters.assign(snapshot["action_filters"] as Array)
	active_card_type_filters.assign(snapshot["card_type_filters"] as Array)
	search_query = String(snapshot["search_query"])
	search_edit.text = search_query
	clear_search_button.visible = not search_query.is_empty()
	_collection_effect_display_states = (snapshot["collection_effect_display_states"] as Dictionary).duplicate(true)
	_build_filter_buttons()
	for rarity_index: int in rarity_buttons.get_child_count():
		(rarity_buttons.get_child(rarity_index) as BaseButton).button_pressed = active_rarity_filters.has(rarity_index)
	_sync_minion_filter_controls()
	current_collection_page = int(snapshot["collection_page"])
	_update_collection_book_mode_visuals()
	var book := get_node("%BookPanel") as Control
	recent_bookmark_button.position = book.position + RECENT_BOOKMARK_POSITION
	if collection_bookmark_active:
		recent_bookmark_button.position += RECENT_BOOKMARK_SELECTED_OFFSET
	_build_collection_cards()
	if snapshot["selected_card"] is CardData:
		_select_card(snapshot["selected_card"] as CardData)
	current_world_view = int(snapshot["world_view"]) as WorldView
	_update_phase_label()
	set_world_view(current_world_view, false)
	recent_bookmark_button.rotation = 0.0
	_update_battle_timer()
	_refresh_spell_preparation_tray()
	_refresh_preparation_effect_preview()
	_escape_menu_pause_requested = _escape_pause_menu.is_menu_open()
	get_tree().paused = (
		bool(snapshot["tree_paused"])
		or _manual_pause_requested
		or _special_spell_pause_requested
		or _escape_menu_pause_requested
	)
	battle_effect_layer.visible = bool(snapshot["battle_effect_layer_visible"])
	_update_battle_pause_button()
	var display_mode: Variant = snapshot.get("display_mode")
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if is_instance_valid(display_shell) and display_mode != null:
		display_shell.call("apply_display_mode", display_mode)
	return true


func _initialize_owned_card_collection() -> void:
	# Main.tscn 目前仍以 CardData 数组提供初始内容；入树时只转换一次，
	# 此后 OwnedCardCollection 才是可变归属的权威容器。
	if owned_card_collection.size() > 0:
		return
	for card_data: CardData in collection_cards:
		owned_card_collection.create_card(card_data)


func _sync_legacy_collection_cards() -> void:
	# 收藏 UI 的实例化与筛选仍读取 CardData。本小步只保留这层派生数组，
	# 不允许它拥有永久状态；后续 UI 迁移到 OwnedCard 时可删除此兼容入口。
	collection_cards.clear()
	for owned_card: OwnedCard in owned_card_collection.get_cards():
		collection_cards.append(owned_card.card_data)
	var retained_recent_cards: Array[CardData] = []
	var retained_recent_owned_cards: Array[OwnedCard] = []
	for index: int in mini(recently_returned_cards.size(), recently_returned_owned_cards.size()):
		var recent_owned := recently_returned_owned_cards[index]
		if recent_owned == null or owned_card_collection.get_by_instance_id(recent_owned.instance_id) != recent_owned:
			continue
		retained_recent_cards.append(recent_owned.card_data)
		retained_recent_owned_cards.append(recent_owned)
	recently_returned_cards = retained_recent_cards
	recently_returned_owned_cards = retained_recent_owned_cards


func _bind_owned_cards_to_player_squads() -> void:
	# 同一实例即使换排、换位或拆队，SquadData 中的绑定仍随卡保留。
	# 对尚未绑定的旧场景数据按收藏获得顺序补齐；已被其他小队占用的实例不会复用。
	var claimed_instance_ids: Dictionary = {}
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			for card_data: CardData in squad.horizontal_cards:
				var owned_card := squad.get_owned_card(card_data)
				if owned_card == null:
					owned_card = owned_card_collection.find_first_by_definition(
						card_data,
						claimed_instance_ids
					)
					if owned_card != null:
						squad.bind_owned_card(card_data, owned_card)
				if owned_card != null:
					claimed_instance_ids[owned_card.instance_id] = true


func _take_next_battle_instance_id() -> StringName:
	if not _resume_battle_instance_id.is_empty():
		var resumed_id := _resume_battle_instance_id
		_resume_battle_instance_id = &""
		return resumed_id
	var result := StringName("run_battle_%06d" % _next_battle_instance_sequence)
	_next_battle_instance_sequence += 1
	return result


func _bind_scene_nodes() -> void:
	phase_label = get_node("%PhaseLabel") as Label
	play_area_label = get_node("%FeedbackLabel") as Label
	world_content = get_node("%WorldContent") as Control
	front_row = get_node("%FrontRow") as BattlefieldRow
	back_row = get_node("%BackRow") as BattlefieldRow
	enemy_back_row = get_node("%EnemyBackRow") as BattlefieldRow
	enemy_front_row = get_node("%EnemyFrontRow") as BattlefieldRow
	enemy_avatar = get_node("%EnemyAvatar") as TextureRect
	battle_pause_button = get_node("%BattlePauseButton") as Button
	battle_speed_bar = get_node("%BattleSpeedBar") as Control
	for child: Node in battle_speed_bar.get_children():
		if child is Button:
			battle_speed_buttons.append(child as Button)
	battle_timer_label = get_node("%BattleTimerLabel") as Label
	battle_seed_panel = get_node("%BattleSeedPanel") as PanelContainer
	battle_seed_spin = get_node("%BattleSeedSpin") as SpinBox
	battle_seed_random_button = get_node("%BattleSeedRandomButton") as Button
	battle_log_panel = get_node("%BattleLogPanel") as PanelContainer
	battle_log_text = get_node("%BattleLogText") as RichTextLabel
	battle_effect_layer = get_node("%BattleEffectLayer") as Control
	collection_viewport = get_node("%CollectionViewport") as Control
	collection_card_row = get_node("%CollectionCardRow") as Control
	collection_drop_zone = get_node("%CollectionDropZone") as Control
	drag_mode_button = get_node("%DragModeButton") as Button
	player_avatar_button = get_node("%PlayerAvatarButton") as TextureButton
	battle_volume_slider = get_node("%BattleVolumeSlider") as HSlider
	battle_volume_slider.value_changed.connect(_on_battle_volume_changed)
	battle_audio_service.set_master_volume_percent(battle_volume_slider.value)
	start_battle_button = get_node("%StartBattleButton") as Button


func _build_formula_popup() -> void:
	if is_instance_valid(formula_popup):
		return
	formula_popup = PanelContainer.new()
	formula_popup.name = "BattleFormulaPopup"
	formula_popup.size = Vector2(FORMULA_POPUP_MIN_WIDTH, 1.0)
	formula_popup.custom_minimum_size = Vector2.ZERO
	formula_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	formula_popup.z_index = 2000
	formula_popup.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.043, 0.97)
	style.border_color = Color(0.86, 0.73, 0.39, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(9.0)
	formula_popup.add_theme_stylebox_override("panel", style)
	add_child(formula_popup)
	formula_popup_text = RichTextLabel.new()
	formula_popup_text.name = "FormulaText"
	formula_popup_text.fit_content = false
	formula_popup_text.scroll_active = true
	formula_popup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	formula_popup_text.add_theme_font_override("normal_font", BATTLE_LOG_FONT)
	formula_popup_text.add_theme_font_size_override("normal_font_size", 12)
	formula_popup_text.add_theme_color_override("default_color", Color("e8eee5"))
	formula_popup.add_child(formula_popup_text)
	formula_popup.mouse_entered.connect(_on_formula_popup_mouse_entered)
	formula_popup.mouse_exited.connect(_schedule_formula_popup_hide)
	if not battle_log_text.meta_hover_started.is_connected(_on_battle_log_meta_hover_started):
		battle_log_text.meta_hover_started.connect(_on_battle_log_meta_hover_started)
		battle_log_text.meta_hover_ended.connect(_on_battle_log_meta_hover_ended)
	battle_result_panel = get_node("%BattleResultPanel") as Panel
	battle_result_label = get_node("%BattleResultLabel") as Label
	battle_result_summary_label = get_node("%BattleResultPlaceholder") as RichTextLabel
	restart_battle_button = get_node("%RestartBattleButton") as Button
	continue_next_level_button = get_node("%ContinueNextLevelButton") as Button
	export_battle_data_button = get_node("%ExportBattleDataButton") as Button
	battle_export_status_label = get_node("%BattleExportStatusLabel") as Label
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


func _on_drag_mode_toggled(prefer_minion: bool) -> void:
	drag_mode_button.text = (
		"拖拽：优先随从" if prefer_minion else "拖拽：优先小队"
	)
	for row: BattlefieldRow in [front_row, back_row]:
		row.set_prefer_minion(prefer_minion)


func _on_player_avatar_button_pressed() -> void:
	set_world_view(WorldView.BATTLEFIELDS if current_world_view == WorldView.COLLECTION else WorldView.COLLECTION)


func _on_battle_volume_changed(value: float) -> void:
	if is_instance_valid(battle_audio_service):
		battle_audio_service.set_master_volume_percent(value)


func set_battle_speed(index: int) -> void:
	battle_speed_index = clampi(index, 0, BATTLE_SPEED_MULTIPLIERS.size() - 1)
	_apply_battle_speed()


func _on_battle_pause_button_pressed() -> void:
	if current_phase != GamePhase.BATTLE or is_instance_valid(_inspection_overlay):
		return
	_manual_pause_requested = not _manual_pause_requested
	_sync_battle_pause_owners()


func set_special_spell_pause_requested(paused: bool) -> void:
	## 特殊法术可通过此入口提出暂停；普通法术默认不提出暂停请求。
	_special_spell_pause_requested = paused
	_sync_battle_pause_owners()


func _sync_battle_pause_owners() -> void:
	get_tree().paused = (
		_manual_pause_requested
		or _inspection_pause_requested
		or _special_spell_pause_requested
		or _escape_menu_pause_requested
	)
	_update_battle_pause_button()


func _on_escape_pause_menu_requested() -> void:
	if _rune_scraper_mode:
		_finish_rune_scraper_mode()
		return
	_finish_rune_scraper_mode()
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if is_instance_valid(display_shell):
		if bool(display_shell.call("is_card_art_tuner_open")):
			display_shell.call("close_card_art_tuner")
			return
		if bool(display_shell.call("is_battle_lab_open")):
			display_shell.call("close_battle_lab")
			return
		if bool(display_shell.call("is_attack_effect_lab_open")):
			display_shell.call("close_attack_effect_lab")
			return
	if _escape_pause_menu.is_menu_open():
		_close_escape_pause_menu()
		return
	if is_instance_valid(_developer_console) and _developer_console.visible:
		_developer_console.set_open(false)
		return
	if is_instance_valid(_inspection_overlay):
		if not _cancel_inspection_carry_from_overlay():
			_close_card_inspection()
		return
	if not _click_carry_data.is_empty() or get_viewport().gui_is_dragging():
		_cancel_click_carry()
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		_native_carry_data = {}
		_native_carry_last_target = {}
		_clear_click_drop_feedback(false)
		return
	_escape_menu_pause_requested = true
	_escape_pause_menu.open_menu()
	_sync_battle_pause_owners()


func _close_escape_pause_menu() -> void:
	if not _escape_menu_pause_requested:
		return
	_escape_menu_pause_requested = false
	_escape_pause_menu.close_menu()
	_sync_battle_pause_owners()


func _on_escape_menu_tool_requested(tool: StringName) -> void:
	match tool:
		&"attack_effect_lab":
			_on_attack_effect_lab_button_pressed()
		&"card_art_tuner":
			_on_card_art_tuner_button_pressed()
		&"battle_lab":
			_on_battle_lab_button_pressed()


func _on_escape_menu_restore_requested() -> void:
	if _restore_startup_runtime_snapshot():
		play_area_label.text = "已恢复本次启动时的界面、阵容与运行状态"
	else:
		play_area_label.text = "无法恢复启动状态：快照数据校验失败"


func _set_battle_target_priority_display_enabled(enabled: bool) -> void:
	_show_battle_target_priority = enabled
	if is_instance_valid(_escape_pause_menu):
		_escape_pause_menu.set_target_priority_display_enabled(enabled)
	for row: BattlefieldRow in [front_row, back_row, enemy_front_row, enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			slot.set_target_priority_display_enabled(enabled)


func _update_battle_pause_button() -> void:
	if not is_instance_valid(battle_pause_button):
		return
	var paused := get_tree().paused
	battle_pause_button.text = "▶️" if paused else "⏸️"
	battle_pause_button.tooltip_text = "继续战斗" if paused else "暂停战斗"


func _use_new_battle_seed() -> void:
	if battle_seed_spin == null:
		return
	# 用微秒时钟生成便于抄录的九位非负整数；真正的随机序列仍由
	# BattleController 自己的 RandomNumberGenerator 独立维护。
	battle_seed_spin.value = int(Time.get_ticks_usec() % (BATTLE_SEED_MAX + 1))


func _apply_battle_speed() -> void:
	var multiplier := BATTLE_SPEED_MULTIPLIERS[battle_speed_index]
	for index: int in battle_speed_buttons.size():
		battle_speed_buttons[index].button_pressed = index == battle_speed_index
		battle_speed_buttons[index].modulate = Color("fff0b4") if index == battle_speed_index else Color("b9a982")
	if battle_controller != null:
		battle_controller.set_battle_speed_multiplier(multiplier)
	if is_instance_valid(battle_effect_layer):
		for child: Node in battle_effect_layer.get_children():
			if BattleAttackTrailRenderer.is_flight_root(child):
				BattleAttackTrailRenderer.set_flight_speed(child, multiplier)


func set_world_view(view: WorldView, animate: bool = true) -> void:
	current_world_view = view
	_turn_player_avatar(0 if view == WorldView.COLLECTION else PLAYER_AVATAR_FRAME_COUNT - 1, animate)
	var target_y := -WORLD_SECTION_HEIGHT if view == WorldView.COLLECTION else 0.0
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	if not animate or not is_inside_tree():
		world_content.position.y = target_y
		return
	_view_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_view_tween.tween_property(world_content, "position:y", target_y, VIEW_TWEEN_DURATION)


func _turn_player_avatar(target_frame: int, animate: bool) -> void:
	if _player_avatar_turn_tween != null and _player_avatar_turn_tween.is_valid():
		_player_avatar_turn_tween.kill()
	if not animate or not is_inside_tree() or target_frame == _player_avatar_frame_index:
		_set_player_avatar_frame(float(target_frame))
		return
	var remaining_frame_count := absi(target_frame - _player_avatar_frame_index)
	var duration := PLAYER_AVATAR_TURN_DURATION * float(remaining_frame_count) / float(PLAYER_AVATAR_FRAME_COUNT - 1)
	_player_avatar_turn_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	_player_avatar_turn_tween.tween_method(_set_player_avatar_frame, float(_player_avatar_frame_index), float(target_frame), duration)


func _set_player_avatar_frame(frame_value: float) -> void:
	var next_frame := clampi(roundi(frame_value), 0, PLAYER_AVATAR_FRAME_COUNT - 1)
	if next_frame == _player_avatar_frame_index:
		return
	_player_avatar_frame_index = next_frame
	player_avatar_button.texture_normal = _make_player_avatar_frame_texture(next_frame)


func _build_enemy_test_squads() -> void:
	if collection_cards.size() < 17:
		return
	var back_cards: Array[CardData] = [collection_cards[1], collection_cards[2]]
	var front_cards: Array[CardData] = [collection_cards[4], collection_cards[5]]
	enemy_back_row.add_squad(SquadData.from_cards(back_cards, SquadData.TwoCardLayout.COMPACT), 0)
	enemy_front_row.add_squad(SquadData.from_cards(front_cards, SquadData.TwoCardLayout.EXPANDED), 0)
	# 每排再加入两个独立伤害小队，让固定敌阵拥有更接近实战的测试压力。
	enemy_back_row.add_squad(SquadData.from_card(collection_cards[10]), 1)
	enemy_front_row.add_squad(SquadData.from_card(collection_cards[11]), 1)
	enemy_back_row.add_squad(SquadData.from_card(collection_cards[15]), 2)
	enemy_front_row.add_squad(SquadData.from_card(collection_cards[16]), 2)
	enemy_back_row.set_drag_enabled(false)
	enemy_front_row.set_drag_enabled(false)


func _build_filter_buttons() -> void:
	for child: Node in rarity_buttons.get_children():
		rarity_buttons.remove_child(child)
		child.queue_free()
	for child: Node in card_type_filter_tabs.get_children():
		card_type_filter_tabs.remove_child(child)
		child.queue_free()
	for child: Node in element_buttons.get_children():
		element_buttons.remove_child(child)
		child.queue_free()
	for child: Node in action_filter_tabs.get_children():
		action_filter_tabs.remove_child(child)
		child.queue_free()
	for rarity: int in CardData.Rarity.size():
		var region := RARITY_FILTER_REGIONS[rarity]
		var button := _create_atlas_filter_button(
			RARITY_FILTER_TEXTURE,
			region,
			"稀有度 %s" % ["I", "II", "III", "IV", "V"][rarity]
		)
		button.texture_pressed = _make_atlas_texture(
			RARITY_FILTER_TEXTURE,
			RARITY_FILTER_SELECTED_REGIONS[rarity]
		)
		button.position = region.position - RARITY_FILTER_REGIONS[0].position
		button.toggle_mode = true
		button.button_pressed = active_rarity_filters.has(rarity)
		button.pressed.connect(_on_rarity_button_pressed.bind(rarity))
		rarity_buttons.add_child(button)
		button.size = region.size
	for visual_index: int in ELEMENT_FILTER_REGIONS.size():
		var element_type: int = ELEMENT_FILTER_TYPES[visual_index]
		var region := ELEMENT_FILTER_REGIONS[visual_index]
		var button := _create_atlas_filter_button(
			ELEMENT_FILTER_TEXTURE,
			region,
			"包含%s符文" % ELEMENT_FILTER_NAMES[visual_index]
		)
		button.texture_pressed = _make_atlas_texture(
			ELEMENT_FILTER_TEXTURE,
			ELEMENT_FILTER_SELECTED_REGIONS[visual_index]
		)
		button.position = region.position - ELEMENT_FILTER_REGIONS[0].position
		button.toggle_mode = true
		button.button_pressed = active_element_filters.has(element_type)
		button.pressed.connect(_on_element_button_pressed.bind(element_type))
		element_buttons.add_child(button)
		button.size = region.size
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
		button.size = region.size
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
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_root.add_child(art)
		art.size = ACTION_TAB_REGION.size
		var action_icon := TextureRect.new()
		action_icon.name = "ActionIcon"
		# GameDisplay 固定在 1×内部画布绘制；筛选图标直接使用各自的 1×原图，
		# 避免 24×25 防御图标被统一拉到 25px 宽，也避免 25×25 图标产生半像素居中。
		action_icon.texture = ACTION_FILTER_TEXTURES[action_type]
		var icon_rect := get_action_tab_icon_rect(action_type)
		action_icon.position = icon_rect.position
		action_icon.size = icon_rect.size
		action_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		action_icon.stretch_mode = TextureRect.STRETCH_KEEP
		action_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		action_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_root.add_child(action_icon)
		action_icon.position = icon_rect.position
		action_icon.size = icon_rect.size
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


func get_action_tab_icon_rect(action_type: int) -> Rect2:
	var icon_size := ACTION_FILTER_TEXTURES[action_type].get_size()
	# 奇数差值无法真正居中时固定向左、向上取整，保证最终坐标始终落在整数像素。
	var centered_offset := ((ACTION_TAB_ICON_FRAME_SIZE - icon_size) * 0.5).floor()
	return Rect2(ACTION_TAB_ICON_POSITION + centered_offset, icon_size)


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
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.tooltip_text = tooltip
	return button


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
	if not active_action_filters.is_empty():
		active_card_type_filters.assign([CardData.CardType.MINION])
	elif (
		active_element_filters.is_empty()
		and active_card_type_filters == [CardData.CardType.MINION]
	):
		# 随从标签由行动筛选自动带起；最后一个行动条件弹回时一起恢复无类型筛选。
		active_card_type_filters.clear()
	_sync_minion_filter_controls()


func toggle_card_type_filter(card_type: int) -> void:
	_toggle_single_filter(active_card_type_filters, card_type)
	if card_type != CardData.CardType.MINION:
		if active_card_type_filters.has(card_type):
			active_action_filters.clear()
			active_element_filters.clear()
	elif active_card_type_filters.is_empty():
		# 行动方式和元素只属于随从；主动弹回随从标签时也同时清空它们。
		active_action_filters.clear()
		active_element_filters.clear()
	_sync_minion_filter_controls()


func _sync_minion_filter_controls() -> void:
	# 类型、行动与元素共同描述“随从筛选”，必须在一次状态提交中同步。
	for tab_index: int in action_filter_tabs.get_child_count():
		var hotspot := action_filter_tabs.get_child(tab_index).get_node("Hotspot") as Button
		hotspot.button_pressed = active_action_filters.has(tab_index)
	for visual_index: int in card_type_filter_tabs.get_child_count():
		var button := card_type_filter_tabs.get_child(visual_index) as BaseButton
		button.button_pressed = active_card_type_filters.has(
			CARD_TYPE_FILTER_TYPES[visual_index]
		)
	for visual_index: int in element_buttons.get_child_count():
		var element_button := element_buttons.get_child(visual_index) as BaseButton
		element_button.button_pressed = active_element_filters.has(
			ELEMENT_FILTER_TYPES[visual_index]
		)
	current_collection_page = 0
	_update_action_tab_positions()
	_update_card_type_tab_positions()
	_build_collection_cards()


func toggle_rarity_filter(rarity: int) -> void:
	_toggle_single_filter(active_rarity_filters, rarity)
	for rarity_index: int in rarity_buttons.get_child_count():
		(rarity_buttons.get_child(rarity_index) as BaseButton).button_pressed = (
			active_rarity_filters.has(rarity_index)
		)
	current_collection_page = 0
	_build_collection_cards()


func toggle_element_filter(element_type: int) -> void:
	if active_element_filters.has(element_type):
		active_element_filters.erase(element_type)
	else:
		active_element_filters.append(element_type)
	if not active_element_filters.is_empty():
		active_card_type_filters.assign([CardData.CardType.MINION])
	_sync_minion_filter_controls()


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
			if (
				not active_action_filters.is_empty()
				and (
					card_data.card_type != CardData.CardType.MINION
					or not active_action_filters.has(card_data.action_type)
				)
			):
				continue
			var contains_all_selected_elements := true
			if not active_element_filters.is_empty() and card_data.card_type != CardData.CardType.MINION:
				continue
			for element_type: int in active_element_filters:
				if not card_data.runes.has(element_type):
					contains_all_selected_elements = false
					break
			if not contains_all_selected_elements:
				continue
			if not search_query.is_empty():
				var subtype_name := card_data.get_race_name()
				if card_data.card_type == CardData.CardType.SPELL:
					subtype_name = card_data.get_spell_type_name()
				elif card_data.card_type == CardData.CardType.EQUIPMENT:
					subtype_name = card_data.get_equipment_type_name()
				var searchable := "%s %s %s %s" % [
					card_data.display_name,
					card_data.get_card_type_name(),
					subtype_name,
					card_data.effect_text,
				]
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


func _record_recently_returned_card(card_data: CardData, owned_card: OwnedCard = null) -> void:
	if card_data == null:
		return
	if owned_card == null:
		for candidate: OwnedCard in owned_card_collection.get_cards():
			if candidate.card_data == card_data:
				owned_card = candidate
				break
	var old_index := recently_returned_cards.find(card_data)
	if old_index >= 0:
		recently_returned_cards.remove_at(old_index)
		if old_index < recently_returned_owned_cards.size():
			recently_returned_owned_cards.remove_at(old_index)
	recently_returned_cards.push_front(card_data)
	recently_returned_owned_cards.push_front(owned_card)
	if recently_returned_cards.size() > RECENT_CARDS_LIMIT:
		recently_returned_cards.resize(RECENT_CARDS_LIMIT)
		recently_returned_owned_cards.resize(mini(recently_returned_owned_cards.size(), RECENT_CARDS_LIMIT))
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
	var profile_started_usec := Time.get_ticks_usec() if _battle_performance_trace_enabled else 0
	var previous_page := current_collection_page
	var previous_filtered_cards := get_filtered_collection_cards()
	_clear_page_turn_overlay()
	# 旧卡面直接随纸张移动；先从实时层取出，避免重建时被释放。
	var previous_slots := collection_card_row.get_children()
	for slot: Node in previous_slots:
		collection_card_row.remove_child(slot)
	current_collection_page = target
	last_page_turn_method = method
	_build_collection_cards()
	_play_collection_page_turn(
		previous_page,
		target,
		previous_filtered_cards,
		previous_slots
	)
	if profile_started_usec > 0:
		_battle_trace_page_turn_usec += Time.get_ticks_usec() - profile_started_usec
	return true


func _play_collection_page_turn(
	previous_page: int,
	target_page: int,
	previous_filtered_cards: Array[CardData],
	previous_slots: Array[Node]
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
	var target_slots := collection_card_row.get_children()
	overlay.set_meta("target_slots", target_slots)

	var static_page := _create_page_turn_snapshot(
		static_side,
		previous_page,
		previous_filtered_cards,
		_get_regular_page_texture(static_side),
		false
	)
	static_page.name = "StaticOldPage"
	static_page.z_index = 0
	overlay.add_child(static_page)
	_move_collection_slots_to_turn_page(previous_slots, static_side, static_page)
	var target_fixed_page := _create_page_turn_snapshot(
		target_fixed_side,
		target_page,
		target_filtered_cards,
		_get_regular_page_texture(target_fixed_side),
		false
	)
	target_fixed_page.name = "StaticTargetPage"
	target_fixed_page.z_index = 0
	overlay.add_child(target_fixed_page)
	_move_collection_slots_to_turn_page(target_slots, target_fixed_side, target_fixed_page)
	var target_face := _create_page_turn_snapshot(
		target_side, target_page, target_filtered_cards,
		_get_regular_page_texture(target_side), false
	)
	target_face.name = "TargetFace"
	target_face.visible = false
	overlay.add_child(target_face)
	_move_collection_slots_to_turn_page(target_slots, target_side, target_face)
	var moving_page := _create_page_turn_snapshot(
		moving_side,
		previous_page,
		previous_filtered_cards,
		_get_regular_page_texture(moving_side),
		false
	)
	moving_page.name = "MovingPage"
	moving_page.z_index = PAGE_TURN_MOVING_Z_INDEX
	moving_page.pivot_offset = Vector2(
		0.0 if turns_forward else COLLECTION_PAGE_SIZE.x,
		COLLECTION_PAGE_SIZE.y * 0.5
	)
	_add_page_turn_free_edge(moving_page, moving_side)
	overlay.add_child(moving_page)
	_move_collection_slots_to_turn_page(previous_slots, moving_side, moving_page)
	# 四个纸面共用旧页和目标页的实卡；动画结束后目标卡面归还实时层。
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
		_swap_page_turn_face.bind(moving_page, target_side)
	)
	_page_tween.tween_property(moving_page, "scale:x", 1.0, PAGE_TURN_HALF_DURATION)
	_page_tween.parallel().tween_property(moving_page, "scale:y", 1.0, PAGE_TURN_HALF_DURATION)
	_page_tween.parallel().tween_property(shadow, "modulate:a", 0.0, PAGE_TURN_HALF_DURATION)
	_page_tween.tween_callback(_finish_page_turn_overlay)


func _move_collection_slots_to_turn_page(
	slots: Array[Node], page_side: int, page: Control
) -> void:
	var layer := page.get_node("CardLayer") as Control
	for index: int in range(page_side * 6, mini(page_side * 6 + 6, slots.size())):
		var slot := slots[index] as Control
		slot.set_meta("page_turn_position", slot.position)
		if slot.get_parent() != null:
			slot.get_parent().remove_child(slot)
		layer.add_child(slot)
		slot.position = COLLECTION_VIEWPORT_POSITION + _collection_slot_position(index) - page.position
		if slot.get_child_count() > 0:
			var view := slot.get_child(0) as CardView
			view.configure_drag_source(false)
			view.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_regular_page_texture(page_side: int) -> Texture2D:
	return (
		COLLECTION_LEFT_PAGE_FRONT_TEXTURE
		if page_side == 0
		else COLLECTION_RIGHT_PAGE_FRONT_TEXTURE
	)


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
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(art)
	art.size = COLLECTION_PAGE_SIZE
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
		var owned_card := _get_owned_card_for_collection_index(filtered_cards, filtered_index)
		var is_ghost := (
			_is_owned_card_deployed(owned_card) or _is_spell_prepared(owned_card)
			if owned_card != null
			else _is_card_deployed(card_data)
		)
		var slot := _create_collection_card_slot(
			card_data,
			is_ghost,
			false,
			owned_card
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


func _swap_page_turn_face(moving_page: Control, target_side: int) -> void:
	if not is_instance_valid(moving_page):
		return
	for child: Node in moving_page.get_children():
		moving_page.remove_child(child)
		child.queue_free()
	var target_snapshot := _page_turn_overlay.get_node("TargetFace") as Control

	moving_page.set_meta("physical_page", target_snapshot.get_meta("physical_page"))
	for child: Node in target_snapshot.get_children():
		target_snapshot.remove_child(child)
		moving_page.add_child(child)
	target_snapshot.get_parent().remove_child(target_snapshot)
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
		# 包括被中途取消的翻页；先收回目标卡面，再销毁旧纸面。
		for slot: Control in _page_turn_overlay.get_meta("target_slots", []):
			slot.get_parent().remove_child(slot)
			collection_card_row.add_child(slot)
			slot.position = slot.get_meta("page_turn_position")
			slot.remove_meta("page_turn_position")
			if slot.get_child_count() > 0:
				var view := slot.get_child(0) as CardView
				var ghost := bool(slot.get_meta("is_deployed_ghost", false))
				view.mouse_filter = Control.MOUSE_FILTER_IGNORE if ghost else Control.MOUSE_FILTER_STOP
				view.configure_drag_source(current_phase == GamePhase.PREPARE and not ghost, &"collection", null, slot)
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
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if (
		is_instance_valid(display_shell)
		and display_shell.is_ancestor_of(self)
		and display_shell.has_method("open_card_art_tuner")
	):
		display_shell.call("open_card_art_tuner")
		return
	get_tree().change_scene_to_file("res://scenes/tools/CardArtTuner.tscn")


func _on_battle_lab_button_pressed() -> void:
	_cancel_click_carry()
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if (
		is_instance_valid(display_shell)
		and display_shell.is_ancestor_of(self)
		and display_shell.has_method("open_battle_lab")
	):
		display_shell.call("open_battle_lab")
		return
	get_tree().change_scene_to_file("res://scenes/tools/BattleLab.tscn")


func _on_attack_effect_lab_button_pressed() -> void:
	_cancel_click_carry()
	var display_shell := get_tree().get_first_node_in_group(&"game_display_shell")
	if (
		is_instance_valid(display_shell)
		and display_shell.is_ancestor_of(self)
		and display_shell.has_method("open_attack_effect_lab")
	):
		display_shell.call("open_attack_effect_lab")
		return
	get_tree().change_scene_to_file("res://scenes/tools/AttackEffectLab.tscn")


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var drag_data: Variant = get_viewport().gui_get_drag_data()
		if (
			drag_data is Dictionary
			and _is_card_carry_drag(drag_data as Dictionary)
		):
			_native_carry_data = (drag_data as Dictionary).duplicate()
			_set_resource_trays_carry_active(true)
			_native_carry_update_frame = -1
			_native_carry_update_pointer = Vector2.INF
			_native_carry_pointer = get_viewport().get_mouse_position()
			_update_card_carry_target.call_deferred(
				get_viewport().get_mouse_position(),
				_native_carry_data
			)
	elif what == NOTIFICATION_DRAG_END:
		var failed_indicator_drag := _native_carry_data
		_native_carry_data = {}
		_set_resource_trays_carry_active(false)
		_native_carry_update_frame = -1
		_native_carry_update_pointer = Vector2.INF
		_native_carry_last_target = {}
		_clear_click_drop_feedback(false)
		if (
			not failed_indicator_drag.is_empty()
			and failed_indicator_drag.get("kind") == &"equipment_indicator"
			and not get_viewport().gui_is_drag_successful()
		):
			var drag_visual_value: Variant = failed_indicator_drag.get("drag_visual")
			var drag_visual: CardDragPreview
			if is_instance_valid(drag_visual_value) and drag_visual_value is CardDragPreview:
				drag_visual = drag_visual_value as CardDragPreview
				drag_visual.set_equipment_indicator_mode(false)
			var preview_offset: Vector2 = failed_indicator_drag.get(
				"drag_visual_offset",
				failed_indicator_drag.get("preview_offset", Vector2.ZERO)
			)
			var return_global_position := (
				drag_visual.get_card_global_position()
				if is_instance_valid(drag_visual)
				else get_viewport().get_mouse_position() - preview_offset
			)
			_return_failed_equipment_indicator_drag.call_deferred(
				failed_indicator_drag,
				return_global_position
			)


func _process(delta: float) -> void:
	if _rune_scraper_mode and is_instance_valid(_rune_scraper_visual):
		_rune_scraper_visual.global_position = get_global_mouse_position() - RuneStickerStyle.get_scraper_hit_point() * _rune_scraper_visual.scale
	# 接收层偶尔漏发 mouse_exited；以最近收到的鼠标坐标逐帧统一确定拖拽目标。
	if (
		not _native_carry_data.is_empty()
		and _is_card_carry_drag(_native_carry_data)
		and get_viewport().gui_is_dragging()
	):
		var live_drag_data: Variant = get_viewport().gui_get_drag_data()
		if live_drag_data is Dictionary:
			_native_carry_data["drag_visual"] = (live_drag_data as Dictionary).get("drag_visual")
		_update_card_carry_target(
			_native_carry_pointer,
			_native_carry_data
		)
	_record_battle_performance_frame(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _rune_scraper_mode and _is_rune_scraper_input_blocked():
		_rune_scrape_button_held = false
		_end_rune_scrape_stroke()


func _input(event: InputEvent) -> void:
	if (
		_rune_scraper_mode
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).keycode == KEY_ESCAPE
	):
		_finish_rune_scraper_mode()
		get_viewport().set_input_as_handled()
		return
	if _rune_scraper_mode:
		if _is_rune_scraper_input_blocked():
			_rune_scrape_button_held = false
			_end_rune_scrape_stroke()
		elif event is InputEventMouseButton:
			var scrape_button := event as InputEventMouseButton
			if scrape_button.button_index == MOUSE_BUTTON_RIGHT and scrape_button.pressed:
				_finish_rune_scraper_mode()
				get_viewport().set_input_as_handled()
				return
			if scrape_button.button_index == MOUSE_BUTTON_LEFT:
				_rune_scrape_button_held = scrape_button.pressed
				if scrape_button.pressed:
					_begin_rune_scrape_stroke(scrape_button.position)
					_update_rune_scrape_stroke(scrape_button.position, _rune_scraper_drag_data)
				else:
					_end_rune_scrape_stroke()
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventMouseMotion and _rune_scrape_button_held:
			_update_rune_scrape_stroke((event as InputEventMouseMotion).position, _rune_scraper_drag_data)
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).keycode == KEY_F2
		and is_instance_valid(_developer_console)
	):
		_developer_console.set_open(not _developer_console.visible)
		get_viewport().set_input_as_handled()
		return
	if (
		_battle_performance_trace_enabled
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).keycode == KEY_F10
	):
		_write_battle_performance_trace()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and not _native_carry_data.is_empty():
		_native_carry_pointer = (event as InputEventMouseMotion).position
		_update_card_carry_target(
			_native_carry_pointer,
			_native_carry_data
		)
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


func _set_equipment_drag_visual_mode(
	drag_data: Dictionary,
	enabled: bool
) -> void:
	if drag_data.get("kind") not in [&"equipment_card", &"equipment_indicator"]:
		return
	var drag_visual_value: Variant = drag_data.get("drag_visual")
	if is_instance_valid(drag_visual_value) and drag_visual_value is CardDragPreview:
		(drag_visual_value as CardDragPreview).set_equipment_indicator_mode(enabled)


func _set_spell_preparation_drag_visual_mode(
	drag_data: Dictionary,
	enabled: bool
) -> void:
	var drag_visual_value: Variant = drag_data.get("drag_visual")
	if is_instance_valid(drag_visual_value) and drag_visual_value is CardDragPreview:
		(drag_visual_value as CardDragPreview).set_spell_preparation_icon_mode(enabled)


func _is_card_carry_drag(drag_data: Dictionary) -> bool:
	return (
		drag_data.get("source_type") in [&"board", &"collection", &"spell_preparation", &"resource_preparation"]
		and drag_data.get("kind") in [
		&"card",
		&"squad",
		&"equipment_card",
		&"equipment_indicator",
		]
	)


func _update_card_carry_target(
	pointer_global_position: Vector2,
	drag_data: Dictionary
) -> Dictionary:
	# 点击携带在外层计时；原生长按拖动此前漏采，这里补齐同一落点路径。
	if not _battle_performance_trace_enabled or _native_carry_data.is_empty():
		return _update_card_carry_target_impl(pointer_global_position, drag_data)
	var began := Time.get_ticks_usec()
	var target := _update_card_carry_target_impl(pointer_global_position, drag_data)
	_battle_trace_drag_preview_usec += Time.get_ticks_usec() - began
	return target


func _update_card_carry_target_impl(
	pointer_global_position: Vector2,
	drag_data: Dictionary
) -> Dictionary:
	var is_native_drag := (
		not _native_carry_data.is_empty()
		and _is_card_carry_drag(drag_data)
	)
	if is_native_drag:
		var frame := Engine.get_process_frames()
		if (
			frame == _native_carry_update_frame
			and pointer_global_position.is_equal_approx(_native_carry_update_pointer)
		):
			return _native_carry_last_target
		_native_carry_update_frame = frame
		_native_carry_update_pointer = pointer_global_position
	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.global_position = pointer_global_position
	for row: BattlefieldRow in [front_row, back_row]:
		row.update_stack_target_feedback_global(pointer_global_position, drag_data)

	var target := {"row": null, "collection": false, "spell_preparation": false, "resource_tray": null, "resource_resolution": {}, "accepted": false}
	var resource_tray := _find_resource_tray_at(pointer_global_position)
	if resource_tray != null:
		for row: BattlefieldRow in [front_row, back_row]: row.clear_drop_preview(false)
		collection_drop_zone.clear_drop_preview()
		if is_instance_valid(spell_preparation_tray): spell_preparation_tray.call("_clear_insertion_preview")
		target["resource_tray"] = resource_tray
		var resolution: Dictionary = resource_tray.update_preview(pointer_global_position, drag_data)
		var puzzle_preview := drag_data.get("drag_visual") as CardDragPreview
		var puzzle_card := drag_data.get("owned_card") as OwnedCard
		if puzzle_preview != null and puzzle_card != null and resolution.has("grab_cell"):
			puzzle_preview.set_resource_puzzle_mode(true, puzzle_card.resource_shape, int(puzzle_card.card_data.rarity), resolution.grab_cell, resolution.grab_pixel_offset, int(puzzle_card.card_data.resource_type))
		target["resource_resolution"] = resolution
		target["accepted"] = bool(resolution.get("valid", false))
		if is_native_drag: _native_carry_last_target = target
		return target
	if is_instance_valid(player_resource_tray): player_resource_tray.clear_preview()
	var departing_preview := drag_data.get("drag_visual") as CardDragPreview
	if departing_preview != null and departing_preview.has_method("set_resource_puzzle_mode"):
		departing_preview.set_resource_puzzle_mode(false)
	if (
		is_instance_valid(spell_preparation_tray)
		and spell_preparation_tray.is_drop_position_global(pointer_global_position)
	):
		for row: BattlefieldRow in [front_row, back_row]:
			row.clear_drop_preview(false)
		collection_drop_zone.clear_drop_preview()
		target["spell_preparation"] = true
		var tray_local := spell_preparation_tray.get_global_transform_with_canvas().affine_inverse() * pointer_global_position
		target["accepted"] = spell_preparation_tray.call("_can_drop_data", tray_local, drag_data)
		_set_spell_preparation_drag_visual_mode(drag_data, bool(target["accepted"]))
		if is_native_drag:
			_native_carry_last_target = target
		return target
	if is_instance_valid(spell_preparation_tray):
		spell_preparation_tray.call("_clear_insertion_preview")
	var target_row := _find_board_row_at(pointer_global_position)
	if target_row != null:
		for row: BattlefieldRow in [front_row, back_row]:
			if row != target_row:
				row.clear_drop_preview(false)
		collection_drop_zone.clear_drop_preview()
		target["row"] = target_row
		target["accepted"] = target_row.preview_card_drop(
			_to_row_drop_position(target_row, pointer_global_position),
			drag_data
		)
	elif collection_drop_zone.get_global_rect().has_point(pointer_global_position):
		front_row.clear_drop_preview(false)
		back_row.clear_drop_preview(false)
		target["collection"] = true
		target["accepted"] = collection_drop_zone.preview_card_drop(
			pointer_global_position,
			drag_data
		)
	else:
		_clear_click_drop_feedback(false)
	if drag_data.get("kind") in [&"equipment_card", &"equipment_indicator"]:
		_set_equipment_drag_visual_mode(
			drag_data,
			target.get("row") != null and bool(target.get("accepted", false))
		)
	_set_spell_preparation_drag_visual_mode(
		drag_data,
		bool(target.get("spell_preparation", false)) and bool(target.get("accepted", false))
	)
	if is_native_drag:
		_native_carry_last_target = target
	return target


func _on_start_battle_button_pressed() -> void:
	start_battle()


func start_battle(random_seed: int = -1, auto_run: bool = true) -> bool:
	if not run_reward_state.pending_next_level_from_id.is_empty():
		play_area_label.text = "本关已经结算；请先处理奖励并进入下一关。"
		return false
	if not run_reward_state.pending_ground_items.is_empty():
		play_area_label.text = "先处理地面临时背包中的奖励，再开始下一场战斗。"
		_refresh_ground_reward_panel()
		return false
	if current_phase != GamePhase.PREPARE or battle_controller == null:
		return false
	var profile_started_usec := Time.get_ticks_usec() if _battle_performance_trace_enabled else 0
	_cancel_click_carry()
	_clear_battle_presentation_for_preparation()
	_bind_owned_cards_to_player_squads()
	var resolved_seed := (
		random_seed
		if random_seed >= 0
		else clampi(roundi(battle_seed_spin.value), 0, BATTLE_SEED_MAX)
	)
	var battle_instance_id := _take_next_battle_instance_id()
	_battle_snapshot = _capture_battle_snapshot(battle_instance_id, resolved_seed)
	_last_battle_settlement_result.clear()
	_battle_state_slots.clear()
	_clear_battle_log()
	if _battle_diagnostic_recorder != null:
		_battle_diagnostic_recorder.detach()
	_battle_diagnostic_recorder = BattleDiagnosticRecorderScript.new()
	_battle_diagnostic_recorder.recording_completed.connect(
		_refresh_battle_diagnostic_export_button
	)
	_battle_diagnostic_recorder.attach(battle_controller)
	battle_export_status_label.text = ""
	battle_export_status_label.tooltip_text = ""
	_refresh_battle_diagnostic_export_button()
	_battle_generation += 1
	_completed_battle_departures.clear()
	_battle_departure_flush_queued = false
	battle_departure_count = 0
	_active_battle_departures = 0
	_pending_battle_result = BattleController.Result.NONE
	var player_formation := _build_battle_formation(front_row, &"player_front")
	player_formation.append_array(_build_battle_formation(back_row, &"player_back"))
	var enemy_formation := _build_battle_formation(enemy_front_row, &"enemy_front")
	enemy_formation.append_array(_build_battle_formation(enemy_back_row, &"enemy_back"))
	current_phase = GamePhase.BATTLE
	battle_result_panel.visible = false
	_update_phase_label()
	battle_seed_spin.value = resolved_seed
	battle_controller.start_battle(
		player_formation,
		enemy_formation,
		resolved_seed,
		auto_run,
		battle_instance_id,
		_get_prepared_spell_instances(),
		[],
		_get_deployed_resource_cards("player"),
		_get_deployed_resource_cards("enemy"),
		_build_reward_card_catalog(),
		owned_card_collection.get_cards()
	)
	_map_battle_states_to_slots(battle_controller.player_states, player_formation)
	_map_battle_states_to_slots(battle_controller.enemy_states, enemy_formation)
	_update_battle_timer()
	_on_battle_states_changed()
	if battle_controller.current_result == BattleController.Result.NONE:
		play_area_label.text = "自动战斗开始：同冷却同时发射，弹道命中时结算"
	if profile_started_usec > 0:
		_battle_trace_start_usec += Time.get_ticks_usec() - profile_started_usec
	return true


func _get_deployed_resource_cards(side: String) -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	var deployments: Dictionary = resource_board_state.deployments.get(side, {})
	for instance_id_value: Variant in deployments.keys():
		var instance_id := String(instance_id_value)
		var card := resource_board_state.get_level_resource(side, instance_id)
		if card == null and side == "player":
			card = owned_card_collection.get_by_instance_id(StringName(instance_id))
		if card != null and card.card_data != null and card.card_data.card_type == CardData.CardType.RESOURCE:
			result.append(card)
	return result


func _clear_battle_presentation_for_preparation() -> void:
	# 结算统计保留到离开结算页；跨入准备或新战斗时，四排一起清除战斗临时卡面状态。
	for row: BattlefieldRow in [enemy_back_row, enemy_front_row, front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			slot.clear_battle_status(true)


func _build_reward_card_catalog() -> Array[CardData]:
	var result: Array[CardData] = []
	for card: CardData in _build_card_definition_registry().values(): result.append(card)
	result.sort_custom(func(left: CardData, right: CardData) -> bool: return String(left.id) < String(right.id))
	return result


func _on_restart_battle_button_pressed() -> void:
	restart_battle()


func restart_battle() -> bool:
	if _battle_snapshot == null or _battle_snapshot.is_empty() or battle_controller == null:
		return false
	if settlement_journal.is_committed(_battle_snapshot.battle_instance_id):
		# 已提交场次统一走下一关入口，避免留在旧关卡重新开战。
		var previous_level := resource_board_state.level_id
		current_phase = GamePhase.PREPARE
		_on_continue_next_level_pressed()
		return resource_board_state.level_id != previous_level
	_close_card_inspection(true)
	_clear_spell_cast_presentation()
	_manual_pause_requested = false
	_special_spell_pause_requested = false
	_inspection_pause_requested = false
	_sync_battle_pause_owners()
	battle_controller.clear_battle()
	_clear_battle_log()
	_battle_generation += 1
	_completed_battle_departures.clear()
	_battle_departure_flush_queued = false
	_active_battle_departures = 0
	_pending_battle_result = BattleController.Result.NONE
	_last_battle_settlement_result.clear()
	_restore_battle_snapshot(
		not settlement_journal.is_committed(_battle_snapshot.battle_instance_id)
	)
	_battle_state_slots.clear()
	current_phase = GamePhase.PREPARE
	battle_result_panel.visible = false
	battle_result_label.text = "战斗结算"
	battle_result_summary_label.text = "卡面：本局统计\n永久成长：无\n本场奖励：无"
	_update_battle_timer()
	_update_phase_label()
	_build_collection_cards()
	_refresh_ground_reward_panel()
	_refresh_preparation_effect_preview.call_deferred()
	play_area_label.text = "已精确恢复本次战斗开始前的阵容与准备状态"
	return true


func set_phase_for_test(phase: GamePhase) -> void:
	if phase != GamePhase.BATTLE:
		_close_card_inspection(true)
		_manual_pause_requested = false
		_special_spell_pause_requested = false
		_inspection_pause_requested = false
		_sync_battle_pause_owners()
	_cancel_click_carry()
	if battle_controller != null and phase != GamePhase.BATTLE:
		battle_controller.stop_battle()
	current_phase = phase
	_update_phase_label()
	if current_phase == GamePhase.PREPARE:
		_refresh_preparation_effect_preview.call_deferred()


func _exit_tree() -> void:
	if _rune_scraper_mode:
		Input.mouse_mode = _rune_scraper_previous_mouse_mode
	_clear_spell_cast_presentation()
	if is_instance_valid(battle_controller):
		battle_controller.clear_battle()
	_manual_pause_requested = false
	_inspection_pause_requested = false
	_special_spell_pause_requested = false
	if get_tree() != null:
		get_tree().paused = false


func _update_phase_label() -> void:
	match current_phase:
		GamePhase.PREPARE:
			phase_label.text = "准备阶段"
		GamePhase.BATTLE:
			phase_label.text = "战斗阶段"
		GamePhase.RESULT:
			phase_label.text = "结算阶段"
	set_world_view(WorldView.COLLECTION if current_phase == GamePhase.PREPARE else WorldView.BATTLEFIELDS)
	start_battle_button.visible = current_phase == GamePhase.PREPARE
	ordinary_shop_entry_button.visible = current_phase == GamePhase.PREPARE
	ordinary_shop_entry_button.disabled = ordinary_shop_service == null
	if is_instance_valid(continue_run_button):
		continue_run_button.visible = current_phase == GamePhase.PREPARE and FileAccess.file_exists(run_save_path)
	if current_phase != GamePhase.PREPARE and ordinary_shop_open:
		ordinary_shop_open = false
		ordinary_shop_panel.visible = false
	battle_pause_button.visible = current_phase == GamePhase.BATTLE
	_update_battle_pause_button()
	battle_speed_bar.visible = current_phase == GamePhase.BATTLE
	battle_timer_label.visible = current_phase == GamePhase.BATTLE
	battle_seed_panel.visible = true
	battle_seed_spin.get_line_edit().editable = current_phase == GamePhase.PREPARE
	battle_seed_random_button.disabled = current_phase != GamePhase.PREPARE
	# 结算页继续复用本场同一份结构化日志，直到玩家点击重新开始。
	battle_log_panel.visible = current_phase in [GamePhase.BATTLE, GamePhase.RESULT]
	var preparing_for_next_level := current_phase == GamePhase.PREPARE and not run_reward_state.pending_next_level_from_id.is_empty()
	battle_result_panel.visible = current_phase == GamePhase.RESULT or preparing_for_next_level
	if is_instance_valid(continue_next_level_button):
		continue_next_level_button.visible = (
			(current_phase == GamePhase.RESULT and bool(_last_battle_settlement_result.get("success", false)))
			or preparing_for_next_level
		)
	if is_instance_valid(restart_battle_button):
		restart_battle_button.visible = current_phase == GamePhase.RESULT and not bool(_last_battle_settlement_result.get("success", false))
	_refresh_battle_diagnostic_export_button()
	_refresh_drag_availability()
	_refresh_spell_preparation_tray()


func _capture_battle_snapshot(
	battle_instance_id: StringName,
	battle_seed: int
) -> BattlePreparationSnapshot:
	var snapshot := BattlePreparationSnapshot.new()
	if not snapshot.initialize(
		battle_instance_id,
		battle_seed,
		owned_card_collection,
		{
			&"player_front": _duplicate_row_squads(front_row),
			&"player_back": _duplicate_row_squads(back_row),
			&"enemy_front": _duplicate_row_squads(enemy_front_row),
			&"enemy_back": _duplicate_row_squads(enemy_back_row),
		},
		prepared_spell_instance_ids,
		resource_board_state.capture_state()
	):
		return null
	return snapshot


func _get_prepared_spell_instances() -> Array[OwnedCard]:
	var result: Array[OwnedCard] = []
	for instance_id: StringName in prepared_spell_instance_ids:
		var owned := owned_card_collection.get_by_instance_id(instance_id)
		if owned != null:
			result.append(owned)
	return result


func _refresh_spell_preparation_tray() -> void:
	if not is_instance_valid(spell_preparation_tray):
		return
	var cards := _get_prepared_spell_instances()
	spell_preparation_tray.set_capacity(spell_preparation_capacity)
	spell_preparation_tray.set_prepared_cards(cards)
	spell_preparation_tray.set_drop_enabled(current_phase == GamePhase.PREPARE)
	spell_preparation_tray.visible = current_phase != GamePhase.RESULT


func _is_spell_prepared(owned_card: OwnedCard) -> bool:
	return owned_card != null and prepared_spell_instance_ids.has(owned_card.instance_id)


func _prepared_spell_candidate_order(owned: OwnedCard, insertion_index: int) -> Array[StringName]:
	var candidate_order: Array[StringName] = prepared_spell_instance_ids.duplicate()
	var previous_index := candidate_order.find(owned.instance_id)
	if previous_index >= 0:
		candidate_order.remove_at(previous_index)
	candidate_order.insert(clampi(insertion_index, 0, candidate_order.size()), owned.instance_id)
	return candidate_order


func _is_prepared_spell_drop_valid(owned: OwnedCard, insertion_index: int) -> bool:
	if (
		current_phase != GamePhase.PREPARE
		or owned == null
		or owned.card_data == null
		or owned.card_data.card_type != CardData.CardType.SPELL
		or owned.card_data.get_spell_preparation_column() < 0
		or owned.spell_durability <= 0
		or owned_card_collection.get_by_instance_id(owned.instance_id) != owned
	):
		return false
	if (
		not prepared_spell_instance_ids.has(owned.instance_id)
		and prepared_spell_instance_ids.size() >= spell_preparation_capacity
	):
		return false
	return _prepared_spell_time_order_is_valid(
		_prepared_spell_candidate_order(owned, insertion_index)
	)


func _resolve_prepared_spell_drop_index(owned: OwnedCard, requested_index: int) -> int:
	if (
		current_phase != GamePhase.PREPARE
		or owned == null
		or owned.card_data == null
		or owned.card_data.card_type != CardData.CardType.SPELL
		or owned.card_data.get_spell_preparation_column() < 0
		or owned.spell_durability <= 0
		or owned_card_collection.get_by_instance_id(owned.instance_id) != owned
	):
		return -1
	var already_prepared := prepared_spell_instance_ids.has(owned.instance_id)
	if not already_prepared and prepared_spell_instance_ids.size() >= spell_preparation_capacity:
		return -1
	var resolved_index := requested_index
	if not already_prepared and owned.card_data.get_spell_preparation_column() == 2:
		var trigger_time := _prepared_spell_time(owned)
		resolved_index = prepared_spell_instance_ids.size()
		for index: int in prepared_spell_instance_ids.size():
			var existing := owned_card_collection.get_by_instance_id(prepared_spell_instance_ids[index])
			if existing != null and existing.card_data.get_spell_preparation_column() == 2:
				if _prepared_spell_time(existing) > trigger_time:
					resolved_index = index
					break
	if not _is_prepared_spell_drop_valid(owned, resolved_index):
		return -1
	return resolved_index


func _on_spell_preparation_drop_requested(data: Dictionary, insertion_index: int) -> bool:
	if current_phase != GamePhase.PREPARE:
		return false
	var owned := data.get("owned_card") as OwnedCard
	if owned == null:
		return false
	if (
		not prepared_spell_instance_ids.has(owned.instance_id)
		and prepared_spell_instance_ids.size() >= spell_preparation_capacity
	):
		play_area_label.text = "法术准备栏已达到%d张上限" % spell_preparation_capacity
		return false
	var resolved_index := _resolve_prepared_spell_drop_index(owned, insertion_index)
	if resolved_index < 0:
		play_area_label.text = "准备类法术按准备秒数升序排列；只能调整相同秒数内的先后"
		return false
	var candidate_order := _prepared_spell_candidate_order(owned, resolved_index)
	if is_instance_valid(spell_preparation_tray):
		spell_preparation_tray.clear_hover_card()
	prepared_spell_instance_ids.assign(candidate_order)
	_normalize_prepared_spell_order()
	_refresh_spell_preparation_tray()
	_build_collection_cards()
	spell_preparation_tray.animate_drop_transition(data, owned.instance_id)
	play_area_label.text = "已按触发类别调整法术准备顺序（%d/%d）" % [
		prepared_spell_instance_ids.size(), spell_preparation_capacity
	]
	return true


func _normalize_prepared_spell_order() -> void:
	var ordered: Array[StringName] = []
	for column_index: int in 3:
		for instance_id: StringName in prepared_spell_instance_ids:
			var owned := owned_card_collection.get_by_instance_id(instance_id)
			if (
				owned != null
				and owned.card_data != null
				and owned.card_data.get_spell_preparation_column() == column_index
			):
				ordered.append(instance_id)
	if battle_controller != null:
		var prepared_start := ordered.size()
		for index: int in ordered.size():
			var owned := owned_card_collection.get_by_instance_id(ordered[index])
			if owned != null and owned.card_data.get_spell_preparation_column() == 2:
				prepared_start = index
				break
		for index: int in range(prepared_start + 1, ordered.size()):
			var moving_id := ordered[index]
			var moving := owned_card_collection.get_by_instance_id(moving_id)
			var moving_time := _prepared_spell_time(moving)
			var insert_at := index
			while insert_at > prepared_start:
				var previous := owned_card_collection.get_by_instance_id(ordered[insert_at - 1])
				if _prepared_spell_time(previous) <= moving_time:
					break
				ordered[insert_at] = ordered[insert_at - 1]
				insert_at -= 1
			ordered[insert_at] = moving_id
	prepared_spell_instance_ids.assign(ordered)


func _prepared_spell_time(owned: OwnedCard) -> float:
	if owned == null or owned.card_data == null or battle_controller == null:
		return INF
	return battle_controller.get_elapsed_spell_trigger_seconds(owned.card_data)


func _prepared_spell_time_order_is_valid(instance_ids: Array) -> bool:
	var previous_time := -INF
	for instance_id_value: Variant in instance_ids:
		var owned := owned_card_collection.get_by_instance_id(instance_id_value as StringName)
		if owned == null or owned.card_data.get_spell_preparation_column() != 2:
			continue
		var trigger_time := _prepared_spell_time(owned)
		if trigger_time < previous_time:
			return false
		previous_time = trigger_time
	return true


func _duplicate_row_squads(row: BattlefieldRow) -> Array[SquadData]:
	var squads: Array[SquadData] = []
	for slot: BoardSlot in row.get_squads():
		squads.append(slot.get_squad_data().duplicate_squad())
	return squads


func _restore_battle_snapshot(restore_collection_state: bool = true) -> void:
	if _battle_snapshot == null:
		return
	if restore_collection_state and not _battle_snapshot.restore_collection(owned_card_collection):
		return
	battle_seed_spin.value = _battle_snapshot.battle_seed
	if restore_collection_state:
		prepared_spell_instance_ids = _battle_snapshot.get_prepared_spell_instance_ids()
		_refresh_spell_preparation_tray()
	if not resource_board_state.restore_state(_battle_snapshot.get_resource_board_state(), _build_card_definition_registry()):
		push_error("战斗快照中的资源板无法恢复")
		return
	if is_instance_valid(player_resource_tray): player_resource_tray.clear_battle_health()
	if is_instance_valid(enemy_resource_tray): enemy_resource_tray.clear_battle_health()
	_refresh_resource_preparation_trays()
	_sync_legacy_collection_cards()
	_restore_row_from_snapshot(front_row, _battle_snapshot.get_row_squads(&"player_front"))
	_restore_row_from_snapshot(back_row, _battle_snapshot.get_row_squads(&"player_back"))
	_restore_row_from_snapshot(enemy_front_row, _battle_snapshot.get_row_squads(&"enemy_front"))
	_restore_row_from_snapshot(enemy_back_row, _battle_snapshot.get_row_squads(&"enemy_back"))


func _restore_row_from_snapshot(row: BattlefieldRow, snapshot_value: Variant) -> void:
	row.clear_squads()
	var squads := snapshot_value as Array
	for squad_value: Variant in squads:
		var squad := squad_value as SquadData
		if squad != null:
			var restored_squad := squad.duplicate_squad()
			var equipped_item := restored_squad.get_equipped_item()
			if (
				equipped_item != null
				and owned_card_collection.get_by_instance_id(equipped_item.instance_id) == null
			):
				restored_squad.unequip_item()
			row.add_squad(restored_squad, row.get_squad_count())


func save_run_to_path(path: String) -> Error:
	# 合法存档点前先结算模式内已付费槽，存档不携带半完成付款状态。
	_finish_rune_scraper_mode()
	var use_battle_snapshot := (
		_battle_snapshot != null
		and not _battle_snapshot.is_empty()
		and current_phase != GamePhase.PREPARE
		and not settlement_journal.is_committed(_battle_snapshot.battle_instance_id)
	)
	var collection_state := (
		_battle_snapshot.get_collection_state_for_save()
		if use_battle_snapshot
		else owned_card_collection.capture_state()
	)
	var rows := _snapshot_rows_for_save() if use_battle_snapshot else _current_rows_for_save()
	var saved_seed := (
		_battle_snapshot.battle_seed
		if use_battle_snapshot
		else clampi(roundi(battle_seed_spin.value), 0, BATTLE_SEED_MAX)
	)
	var pending_battle_id := (
		_battle_snapshot.battle_instance_id
		if use_battle_snapshot
		else &""
	)
	var checkpoint := run_save_service.create_checkpoint(
		collection_state,
		rows,
		saved_seed,
		pending_battle_id,
		_next_battle_instance_sequence,
		run_reward_state,
		settlement_journal,
		current_phase,
		celestial_indicators.capture_state(),
		(
			_battle_snapshot.get_prepared_spell_instance_ids()
			if use_battle_snapshot
			else prepared_spell_instance_ids
		),
		_resource_board_for_save(use_battle_snapshot)
	)
	checkpoint["developer_sticker_bag"] = {
		"inventory_version": 2,
		"items": emblem_library.get_inventory_state(),
		"next_instance": _next_developer_emblem_instance,
	}
	checkpoint["ordinary_shop_state"] = ordinary_shop_service.capture_state() if ordinary_shop_service != null else {}
	checkpoint["scraper_count"] = scraper_count
	checkpoint["chaos_reroll_day_token"] = _last_chaos_reroll_day_token
	var error := run_save_service.save_checkpoint(path, checkpoint)
	_last_run_persistence_result = {
		"success": error == OK,
		"error": error,
		"path": path,
		"pending_battle_instance_id": pending_battle_id,
	}
	return error


func _resource_board_for_save(use_battle_snapshot: bool) -> ResourceBoardState:
	if not use_battle_snapshot or _battle_snapshot == null:
		return resource_board_state
	var snapshot_board := ResourceBoardState.new()
	if snapshot_board.restore_state(_battle_snapshot.get_resource_board_state(), _build_card_definition_registry()):
		return snapshot_board
	return resource_board_state


func reroll_chaos_stickers_for_new_day(day_token: StringName) -> int:
	if day_token.is_empty() or day_token == _last_chaos_reroll_day_token:
		return 0
	_last_chaos_reroll_day_token = day_token
	var rerolled := 0
	for owned_card: OwnedCard in owned_card_collection.get_cards():
		var changed := false
		for rune_index: int in owned_card.rune_stickers.size():
			var sticker: Dictionary = owned_card.rune_stickers[rune_index]
			if sticker.get("emblem_id", &"") != &"混沌贴纸":
				continue
			var next_state := sticker.duplicate(true)
			next_state["element"] = randi_range(0, 4)
			owned_card.set_rune_sticker(rune_index, next_state)
			rerolled += 1
			changed = true
		if changed:
			_refresh_owned_card_status_visuals(owned_card)
	return rerolled


func load_run_from_path(path: String) -> bool:
	var load_result := run_save_service.load_checkpoint(path)
	if not bool(load_result.get("success", false)):
		_last_run_persistence_result = load_result
		return false
	var loaded_checkpoint := load_result.get("checkpoint", {}) as Dictionary
	var migration_save_pending := (
		int(loaded_checkpoint.get("schema_version", 0)) < RunSaveService.SCHEMA_VERSION
		or int(loaded_checkpoint.get("status_slot_migration_version", 0)) < RunSaveService.STATUS_SLOT_MIGRATION_VERSION
		or int(loaded_checkpoint.get("rune_scrape_migration_version", 0)) < RunSaveService.RUNE_SCRAPE_MIGRATION_VERSION
		or loaded_checkpoint.has("developer_wound_workspace")
		or not loaded_checkpoint.has("ordinary_shop_state")
		or not loaded_checkpoint.has("scraper_count")
	)
	var sticker_bag_value: Variant = loaded_checkpoint.get("developer_sticker_bag", {})
	if not sticker_bag_value is Dictionary:
		return false
	var sticker_bag := sticker_bag_value as Dictionary
	var saved_shop_value: Variant = loaded_checkpoint.get("ordinary_shop_state", {})
	if not saved_shop_value is Dictionary:
		return false
	var saved_shop_state := saved_shop_value as Dictionary
	var known_card_ids: Array[String] = []
	for card_id: Variant in _build_card_definition_registry():
		known_card_ids.append(String(card_id))
	var known_sticker_ids: Array[String] = []
	for definition: Dictionary in _get_shop_sticker_definitions():
		known_sticker_ids.append(String(definition.get("id", "")))
	if ordinary_shop_service != null and not ordinary_shop_service.validate_saved_state(saved_shop_state, known_card_ids, known_sticker_ids, _get_shop_card_definitions()):
		return false
	if int(sticker_bag.get("inventory_version", 0)) < 2:
		migration_save_pending = true
	var returned_stickers: Variant = sticker_bag.get("items", sticker_bag.get("returned", []))
	if not returned_stickers is Array:
		return false
	var saved_wounds_value: Variant = loaded_checkpoint.get("developer_wound_workspace", [])
	if not saved_wounds_value is Array:
		return false
	var candidate_stickers: Array[Dictionary] = []
	for sticker_value: Variant in returned_stickers:
		if not sticker_value is Dictionary:
			return false
		var sticker := (sticker_value as Dictionary).duplicate(true)
		if String(sticker.get("instance_id", "")).is_empty():
			return false
		candidate_stickers.append(sticker)
	var legacy_wound_index := 0
	for wound_value: Variant in saved_wounds_value:
		if not wound_value is Dictionary:
			return false
		var wound_state := (wound_value as Dictionary).duplicate(true)
		wound_state["kind"] = "wound"
		if String(wound_state.get("instance_id", "")).is_empty():
			wound_state["instance_id"] = "legacy_wound_%04d" % legacy_wound_index
		legacy_wound_index += 1
		candidate_stickers.append(wound_state)
	var previous_collection_state := owned_card_collection.capture_state()
	var previous_reward_state := run_reward_state.capture_state()
	var previous_journal_state := settlement_journal.capture_state()
	var previous_resource_board_state := resource_board_state.capture_state()
	var restore_result := run_save_service.restore_checkpoint(
		loaded_checkpoint,
		owned_card_collection,
		run_reward_state,
		settlement_journal,
		_build_card_definition_registry(),
		# 当前主场景是开发测试模式，旧卡牌状态布局按兼容规则迁移。
		true
	)
	if not bool(restore_result.get("success", false)):
		_last_run_persistence_result = restore_result
		return false
	var migration_returns: Array = restore_result.get("slot_migration_returns", [])
	for returned_value: Variant in migration_returns:
		if not returned_value is Dictionary:
			continue
		var returned_item := returned_value as Dictionary
		var returned_state := (returned_item.get("state", {}) as Dictionary).duplicate(true)
		if returned_state.is_empty():
			continue
		var returned_kind := String(returned_item.get("kind", "emblem"))
		returned_state["kind"] = "wound" if returned_kind == "wound" else "emblem"
		var duplicate_instance := false
		for existing: Dictionary in candidate_stickers:
			if String(existing.get("instance_id", "")) == String(returned_state.get("instance_id", "")):
				duplicate_instance = true
				break
		if not duplicate_instance:
			candidate_stickers.append(returned_state)
	# 旧布局坐标不对应新4×7格网；按存档顺序稳定重新排位，并保留所有实例字段。
	for state: Dictionary in candidate_stickers:
		state.erase("grid_x")
		state.erase("grid_y")
		state.erase("grid_span")
	if not emblem_library.can_restore_inventory_state(candidate_stickers):
		owned_card_collection.restore_state(previous_collection_state)
		run_reward_state.restore_state(previous_reward_state)
		settlement_journal.restore_state(previous_journal_state)
		resource_board_state.restore_state(previous_resource_board_state, _build_card_definition_registry())
		play_area_label.text = "存档贴纸与伤势超过28格容量或含无效实例；原存档数据未载入"
		return false
	if not emblem_library.restore_inventory_state(candidate_stickers):
		owned_card_collection.restore_state(previous_collection_state)
		run_reward_state.restore_state(previous_reward_state)
		settlement_journal.restore_state(previous_journal_state)
		resource_board_state.restore_state(previous_resource_board_state, _build_card_definition_registry())
		return false

	var loaded_resource_board: Variant = restore_result.get("resource_board_state", null)
	resource_board_state = (
		loaded_resource_board as ResourceBoardState
		if loaded_resource_board != null
		else ResourceBoardState.new()
	)
	_initialize_resource_level_if_needed()
	_cancel_click_carry()
	_clear_spell_cast_presentation()
	_close_card_inspection(true)
	emblem_library._refresh_entries()
	_next_developer_emblem_instance = maxi(1, int(sticker_bag.get("next_instance", 1)))
	if ordinary_shop_service != null:
		var shop_seed := int(saved_shop_state.get("rng_state", Time.get_ticks_usec()))
		ordinary_shop_service.initialize(shop_seed, saved_shop_state)
	scraper_count = maxi(int(loaded_checkpoint.get("scraper_count", 0)), 0)
	emblem_library.set_scraper_count(scraper_count)
	_last_chaos_reroll_day_token = StringName(
		String((load_result.get("checkpoint", {}) as Dictionary).get("chaos_reroll_day_token", ""))
	)
	if battle_controller != null:
		battle_controller.clear_battle()
	_clear_battle_log()
	_battle_generation += 1
	_completed_battle_departures.clear()
	_battle_departure_flush_queued = false
	_active_battle_departures = 0
	_pending_battle_result = BattleController.Result.NONE
	_last_battle_settlement_result.clear()
	_battle_snapshot = null
	_battle_state_slots.clear()
	_next_battle_instance_sequence = int(restore_result.get("next_battle_instance_sequence", 1))
	_resume_battle_instance_id = restore_result.get("pending_battle_instance_id", &"") as StringName
	prepared_spell_instance_ids.assign(
		restore_result.get("prepared_spell_instance_ids", []) as Array
	)
	_normalize_prepared_spell_order()
	battle_seed_spin.value = int(restore_result.get("battle_seed", 0))
	_sync_legacy_collection_cards()
	var restored_rows := restore_result.get("rows", {}) as Dictionary
	celestial_indicators.restore_state(restore_result.get("indicator_inventory", {}))
	_restore_row_from_snapshot(front_row, restored_rows.get(&"player_front", []))
	_restore_row_from_snapshot(back_row, restored_rows.get(&"player_back", []))
	_restore_row_from_snapshot(enemy_front_row, restored_rows.get(&"enemy_front", []))
	_restore_row_from_snapshot(enemy_back_row, restored_rows.get(&"enemy_back", []))
	current_phase = GamePhase.PREPARE
	battle_result_panel.visible = false
	battle_result_label.text = "战斗结算"
	battle_result_summary_label.text = "卡面：本局统计\n永久成长：无\n本场奖励：无"
	_update_battle_timer()
	_update_phase_label()
	_build_collection_cards()
	_refresh_resource_preparation_trays()
	_refresh_ground_reward_panel()
	_refresh_preparation_effect_preview.call_deferred()
	ordinary_shop_open = false
	ordinary_shop_panel.visible = false
	_refresh_ordinary_shop_panel()
	var migration_save_error: Error = OK
	if migration_save_pending:
		migration_save_error = save_run_to_path(path)
	play_area_label.text = (
		"已恢复存档到战前准备；槽位迁移返还%d件状态" % migration_returns.size()
		if not migration_returns.is_empty()
		else "已从本局存档恢复到安全的战前准备状态"
	)
	if migration_save_error != OK:
		play_area_label.text += "；迁移标记自动保存失败，请手动保存"
	_last_run_persistence_result = {
		"success": true,
		"path": path,
		"pending_battle_instance_id": _resume_battle_instance_id,
		"migration_saved": migration_save_error == OK,
		"migration_save_error": migration_save_error,
	}
	return true


func _current_rows_for_save() -> Dictionary:
	return {
		&"player_front": _duplicate_row_squads(front_row),
		&"player_back": _duplicate_row_squads(back_row),
		&"enemy_front": _duplicate_row_squads(enemy_front_row),
		&"enemy_back": _duplicate_row_squads(enemy_back_row),
	}


func _snapshot_rows_for_save() -> Dictionary:
	return {
		&"player_front": _battle_snapshot.get_row_squads(&"player_front"),
		&"player_back": _battle_snapshot.get_row_squads(&"player_back"),
		&"enemy_front": _battle_snapshot.get_row_squads(&"enemy_front"),
		&"enemy_back": _battle_snapshot.get_row_squads(&"enemy_back"),
	}


func _build_card_definition_registry() -> Dictionary:
	var registry: Dictionary = {}
	var directory := DirAccess.open("res://resources/cards")
	if directory != null:
		for filename: String in directory.get_files():
			if filename.get_extension() != "tres": continue
			var card := load("res://resources/cards/%s" % filename) as CardData
			if card != null and not card.id.is_empty(): registry[card.id] = card
	for owned_card: OwnedCard in owned_card_collection.get_cards():
		if owned_card.card_data != null:
			registry[owned_card.card_data.id] = owned_card.card_data
	for row: BattlefieldRow in [front_row, back_row, enemy_front_row, enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			for card_data: CardData in squad.horizontal_cards:
				if card_data != null:
					registry[card_data.id] = card_data
	return registry


func _build_battle_formation(
	row: BattlefieldRow,
	row_key: StringName
) -> Array[Dictionary]:
	var formation: Array[Dictionary] = []
	for index: int in row.get_squad_count():
		var slot := row.get_squads()[index]
		formation.append({
			"squad_data": slot.get_squad_data(),
			"row_key": row_key,
			"formation_index": index,
			"slot": slot,
		})
	return formation


func _map_battle_states_to_slots(
	states: Array[BattleSquadState],
	formation: Array[Dictionary]
) -> void:
	for index: int in mini(states.size(), formation.size()):
		_battle_state_slots[states[index]] = formation[index].get("slot")


func _on_battle_states_changed() -> void:
	if battle_controller == null:
		return
	var profile_started_usec := Time.get_ticks_usec() if _battle_performance_trace_enabled else 0
	_update_battle_timer()
	for state: BattleSquadState in battle_controller.get_all_states():
		var slot := _battle_state_slots.get(state) as BoardSlot
		if is_instance_valid(slot):
			slot.set_target_priority_display_enabled(_show_battle_target_priority)
			if current_phase == GamePhase.BATTLE:
				slot.refresh_celestial_indicators(state.squad_data)
			slot.set_battle_status(
				state.displayed_health,
				state.displayed_armor,
				state.remaining_cooldown,
				state.get_buff_stacks(BattleRules.FATIGUE_BUFF_ID),
				state.get_display_action_value(),
				state.runtime_action_type_override,
				state.get_rune_pattern_result(),
				state.get_active_rune_slots(),
				state.get_masked_rune_indices_by_card(),
				battle_controller.get_spent_emblem_slots_by_card(state),
				state.get_runtime_rune_overrides_by_card(),
				battle_controller.get_effective_target_weight(state),
				state.get_masked_wound_indices_by_card()
			)
	if is_instance_valid(player_resource_tray):
		player_resource_tray.set_battle_health(battle_controller.player_resource_states)
	if is_instance_valid(enemy_resource_tray):
		enemy_resource_tray.set_battle_health(battle_controller.enemy_resource_states)
	if profile_started_usec > 0:
		_battle_trace_state_sync_usec += Time.get_ticks_usec() - profile_started_usec


func _on_spell_cast_started(
	spell: OwnedCard,
	battle_generation: int,
	presentation_seconds: float
) -> void:
	if spell == null or spell.card_data == null:
		return
	_clear_spell_cast_presentation()
	spell_cast_presentation = CARD_VIEW_SCENE.instantiate() as CardView
	spell_cast_presentation.name = "SpellCastPresentation"
	spell_cast_presentation.set_card_data(spell.card_data)
	spell_cast_presentation.set_owned_card(spell)
	spell_cast_presentation.configure_drag_source(false)
	spell_cast_presentation.process_mode = Node.PROCESS_MODE_ALWAYS
	spell_cast_presentation.pivot_offset = Vector2(49.5, 68.0)
	spell_cast_presentation.position = Vector2(590.5, 250.0)
	spell_cast_presentation.scale = Vector2.ONE * 0.55
	spell_cast_presentation.modulate.a = 0.0
	spell_cast_presentation.z_index = 3000
	add_child(spell_cast_presentation)
	spell_cast_presentation.set_meta("battle_generation", battle_generation)
	spell_cast_presentation_tween = create_tween()
	spell_cast_presentation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	spell_cast_presentation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	spell_cast_presentation_tween.tween_property(
		spell_cast_presentation,
		"modulate:a",
		1.0,
		presentation_seconds * SPELL_CAST_PRESENTATION_FADE_RATIO
	)
	spell_cast_presentation_tween.tween_property(
		spell_cast_presentation,
		"scale",
		Vector2.ONE * SPELL_CAST_PRESENTATION_MAX_SCALE,
		presentation_seconds * SPELL_CAST_PRESENTATION_GROW_RATIO
	)
	spell_cast_presentation_tween.tween_property(
		spell_cast_presentation,
		"scale",
		Vector2.ONE * SPELL_CAST_PRESENTATION_REST_SCALE,
		presentation_seconds * (1.0 - SPELL_CAST_PRESENTATION_FADE_RATIO - SPELL_CAST_PRESENTATION_GROW_RATIO)
	)
	spell_cast_presentation_tween.finished.connect(func() -> void:
		if not is_instance_valid(spell_cast_presentation) or battle_controller == null:
			return
		var opening_finished := battle_controller.notify_spell_presentation_finished(
			spell.instance_id,
			battle_generation
		)
		if not opening_finished:
			_on_spell_cast_finished(spell.instance_id, battle_generation)
	)


func _on_spell_cast_finished(spell_instance_id: StringName, battle_generation: int) -> void:
	if (
		is_instance_valid(spell_cast_presentation)
		and spell_cast_presentation.get_meta("battle_generation", -1) == battle_generation
		and spell_cast_presentation.get_owned_card() != null
		and spell_cast_presentation.get_owned_card().instance_id == spell_instance_id
	):
		_clear_spell_cast_presentation()


func _clear_spell_cast_presentation() -> void:
	if is_instance_valid(spell_cast_presentation_tween) and spell_cast_presentation_tween.is_running():
		spell_cast_presentation_tween.kill()
	spell_cast_presentation_tween = null
	if is_instance_valid(spell_cast_presentation):
		spell_cast_presentation.queue_free()
	spell_cast_presentation = null


func _refresh_preparation_effect_preview() -> void:
	if current_phase != GamePhase.PREPARE or battle_controller == null:
		return
	var profile_started_usec := Time.get_ticks_usec() if _equipment_drop_profile_active else 0
	# 备战态复用正式战斗的状态初始化与持续效果系统，但不会触发突击、推进时间或写入奖励账本。
	var player_formation := _build_battle_formation(front_row, &"player_front")
	player_formation.append_array(_build_battle_formation(back_row, &"player_back"))
	var enemy_formation := _build_battle_formation(enemy_front_row, &"enemy_front")
	enemy_formation.append_array(_build_battle_formation(enemy_back_row, &"enemy_back"))
	_battle_state_slots.clear()
	battle_controller.prepare_battle_preview(player_formation, enemy_formation, 0)
	_map_battle_states_to_slots(battle_controller.player_states, player_formation)
	_map_battle_states_to_slots(battle_controller.enemy_states, enemy_formation)
	_on_battle_states_changed()
	if profile_started_usec > 0:
		_record_equipment_drop_profile_duration(
			&"preparation_preview_refresh",
			Time.get_ticks_usec() - profile_started_usec
		)


func _update_battle_timer() -> void:
	if battle_timer_label == null:
		return
	var elapsed := battle_controller.elapsed_seconds if battle_controller != null else 0.0
	var total_tenths := maxi(floori(elapsed * 10.0 + 0.0001), 0)
	var minutes := total_tenths / 600
	var seconds := (total_tenths / 10) % 60
	var tenths := total_tenths % 10
	battle_timer_label.text = "战斗 %02d:%02d.%d" % [minutes, seconds, tenths]


func _on_battle_action_resolved(
	actor: BattleSquadState,
	target: BattleSquadState,
	action_type: CardData.ActionType,
	amount: int
) -> void:
	var actor_slot := _battle_state_slots.get(actor) as BoardSlot
	var target_slot := _battle_state_slots.get(target) as BoardSlot
	var action_name := CardData.get_action_type_name_for(action_type)
	var target_name := target.get_effect_source().display_name if target != null else "资源"
	if is_instance_valid(actor_slot):
		actor_slot.show_battle_action("%s → %s  %d" % [action_name, target_name, amount])
	if is_instance_valid(target_slot):
		var target_text := (
			"受到 %d" % amount
			if action_type in [CardData.ActionType.MELEE, CardData.ActionType.RANGED, CardData.ActionType.MAGIC]
			else "%s +%d" % [action_name, amount]
		)
		target_slot.show_battle_action(target_text, true)


func _on_battle_effect_resolved(event: BattleEffectEvent) -> void:
	var profile_started_usec := Time.get_ticks_usec() if _battle_performance_trace_enabled else 0
	if (
		event != null
		and event.is_base_action
		and event.effect_kind == BattleEffectEvent.EffectKind.DAMAGE
		and not event.missed
		and is_instance_valid(battle_audio_service)
	):
		battle_audio_service.play_action_hit(event.action_type)
	_append_battle_effect(event)
	if event.visual_kind in [&"fire_burn", &"fire_tick", &"fire_finish"]:
		_play_battle_effect_visual(event)
	if profile_started_usec > 0:
		_battle_trace_effect_dispatch_usec += Time.get_ticks_usec() - profile_started_usec


func _on_battle_projectile_launched(event: BattleEffectEvent) -> void:
	if not _battle_performance_trace_enabled:
		_handle_battle_projectile_launched(event)
		return
	var profile_started_usec := Time.get_ticks_usec()
	_handle_battle_projectile_launched(event)
	_battle_trace_effect_dispatch_usec += Time.get_ticks_usec() - profile_started_usec


func _handle_battle_projectile_launched(event: BattleEffectEvent) -> void:
	if event == null or battle_controller == null:
		return
	if event.is_base_action and is_instance_valid(battle_audio_service):
		battle_audio_service.play_action_launch(event.action_type)
	var source_slot := _battle_state_slots.get(event.source) as BoardSlot
	if event.resource_target != null:
		var target_tray := player_resource_tray if int(event.resource_target.get("side")) == BattleSquadState.Side.PLAYER else enemy_resource_tray
		if not is_instance_valid(source_slot) or not is_instance_valid(target_tray) or not is_instance_valid(battle_effect_layer):
			return
		var inverse := battle_effect_layer.get_global_transform_with_canvas().affine_inverse()
		var from_local := inverse * source_slot.get_global_rect().get_center()
		var to_local: Vector2 = inverse * target_tray.get_instance_center_global((event.resource_target.get("owned_card") as OwnedCard).instance_id)
		var visual_kind := _action_visual_kind(event.action_type)
		var color := _element_attack_color(-1)
		_play_element_line(
			PackedVector2Array([from_local, to_local]), visual_kind, color, color,
			func() -> void: _play_element_impact(to_local, visual_kind, color),
			event.projectile_speed_variant, event.projectile_impact_delay
		)
		return
	var target_slot := _battle_state_slots.get(event.target) as BoardSlot
	if not is_instance_valid(target_slot) or not is_instance_valid(battle_effect_layer):
		return
	var visual_source_slot := source_slot
	if not event.is_base_action and event.visual_kind != &"dark_repeat":
		var anchor_slot := _battle_state_slots.get(event.anchor) as BoardSlot
		if is_instance_valid(anchor_slot):
			visual_source_slot = anchor_slot
	if not is_instance_valid(visual_source_slot):
		return
	if event.is_base_action:
		visual_source_slot.play_battle_action_lift(battle_controller.battle_speed_multiplier)
	var inverse := battle_effect_layer.get_global_transform_with_canvas().affine_inverse()
	var from_local := inverse * visual_source_slot.get_global_rect().get_center()
	var to_local := inverse * target_slot.get_global_rect().get_center()
	var points := PackedVector2Array([from_local, to_local])
	if visual_source_slot == target_slot:
		# 自疗与自我防御也沿一条短弧线回到自身，不能因起终点重合而跳过弹道。
		points = PackedVector2Array([
			from_local + Vector2(-18.0, 4.0),
			from_local + Vector2(0.0, -54.0),
			to_local,
		])
	if event.visual_kind == &"dark_repeat":
		var delta := to_local - from_local
		var normal := Vector2(-delta.y, delta.x).normalized() if not delta.is_zero_approx() else Vector2.UP
		var curve_offset := 28.0 + float(event.sequence_index) * 9.0
		var curve_direction := -1.0 if event.sequence_index % 2 == 1 else 1.0
		points = PackedVector2Array([from_local, (from_local + to_local) * 0.5 + normal * curve_offset * curve_direction, to_local])
	var visual_kind := event.visual_kind if event.visual_kind != &"" else _action_visual_kind(event.action_type)
	var colors := _attack_element_colors(event.source) if event.is_base_action else {
		"head": _element_attack_color(event.element_type),
		"tail": _element_attack_color(event.element_type),
	}
	_play_element_line(
		points,
		visual_kind,
		colors["head"],
		colors["tail"],
		func() -> void:
			_play_element_impact(to_local, visual_kind, colors["head"]),
		event.projectile_speed_variant,
		event.projectile_impact_delay
	)


func _on_battle_direct_damage_resolved(
	state: BattleSquadState,
	source_id: StringName,
	amount: int
) -> void:
	var slot := _battle_state_slots.get(state) as BoardSlot
	if not is_instance_valid(slot):
		return
	var source_name := "疲劳" if source_id == BattleRules.FATIGUE_BUFF_ID else String(source_id)
	slot.show_battle_action("%s -%d" % [source_name, amount], true)


func _format_battle_squad_name(state: BattleSquadState) -> String:
	if state == null or state.get_effect_source() == null:
		return "未知目标"
	var side_name := (
		"我方"
		if state.side == BattleSquadState.Side.PLAYER
		else "敌方"
	)
	var result := "%s%s" % [side_name, state.get_effect_source().display_name]
	if state.squad_data != null and state.squad_data.get_card_count() > 1:
		result += "的小队"
	return result


func _append_battle_effect(event: BattleEffectEvent) -> void:
	if event == null or battle_log_text == null:
		return
	var entry := _battle_log_by_group.get(event.group_id) as BattleLogEntry
	var is_new := entry == null
	if entry == null:
		entry = BattleLogEntry.new()
		entry.group_id = event.group_id
		entry.timestamp = event.timestamp
		entry.source = event.source
	entry.add_event(event)
	if is_new:
		_append_battle_log_entry(entry)
	else:
		_refresh_battle_log_text()


func _on_battle_special_effect_resolved(record: Dictionary) -> void:
	if record.is_empty() or battle_log_text == null:
		return
	var entry := BattleLogEntry.new()
	entry.group_id = -_next_direct_effect_log_id
	_next_direct_effect_log_id += 1
	entry.timestamp = float(record.get("logical_time_seconds", 0.0))
	if String(record.get("kind", "")) == "roll":
		var roll_source_name := String(record.get("source_card_name", "未知来源"))
		entry.add_direct_effect_line(
			"%.1f秒 · %s：%s" % [entry.timestamp, roll_source_name, String(record.get("effect_reading", "掷骰结果未知"))]
		)
		_append_battle_log_entry(entry)
		return
	var source_name := String(record.get("source_card_name", "未知来源"))
	var target_name := String(record.get("target_card_name", "未知目标"))
	var kind := String(record.get("kind", "effect"))
	var amount := float(record.get("effective_amount", 0.0))
	var calculated := float(record.get("calculated_amount", amount))
	var verb := "获得护甲" if kind == "armor" else "受到伤害"
	var reading := String(record.get("effect_reading", ""))
	var tags: Array = record.get("tags", []) as Array
	var tag_text := "、".join(_string_array_to_strings(tags))
	var details: Array[String] = ["%.1f秒" % entry.timestamp, "%s触发" % source_name]
	var trigger_name := String(record.get("trigger_name", ""))
	if not trigger_name.is_empty():
		details.append(trigger_name)
	if not tag_text.is_empty():
		details.append(tag_text)
	var source_status := String(record.get("source_status", "unknown"))
	if source_status == "unknown":
		details.append("未知来源")
	var amount_text := BattleLogEntry.format_number(amount)
	if kind == "armor":
		amount_text = "+%s" % amount_text
	else:
		amount_text = "-%s" % amount_text
	var line := "%s 对 %s：%s %s" % [" · ".join(details), target_name, verb, amount_text]
	if not is_equal_approx(calculated, amount):
		line += "（计算 %s，实际 %s）" % [BattleLogEntry.format_number(calculated), BattleLogEntry.format_number(amount)]
	if not reading.is_empty():
		line += "；来源条目：%s" % reading
	entry.add_direct_effect_line(line)
	_append_battle_log_entry(entry)


func _append_battle_log_entry(entry: BattleLogEntry) -> void:
	_battle_log_entries.append(entry)
	_battle_log_by_group[entry.group_id] = entry
	while _battle_log_entries.size() > BATTLE_LOG_MAX_ENTRIES:
		var removed: BattleLogEntry = _battle_log_entries.pop_front()
		_battle_log_by_group.erase(removed.group_id)
	_refresh_battle_log_text()


func _refresh_battle_log_text() -> void:
	var lines: Array[String] = []
	for log_entry: BattleLogEntry in _battle_log_entries:
		lines.append(log_entry.to_bbcode())
	battle_log_text.text = "\n".join(lines)


func _string_array_to_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _clear_battle_log() -> void:
	_battle_log_entries.clear()
	_battle_log_by_group.clear()
	if is_instance_valid(formula_popup):
		formula_popup.visible = false
	if battle_log_text != null:
		battle_log_text.text = ""


func _on_battle_log_meta_hover_started(meta: Variant) -> void:
	var parts := String(meta).split(":")
	if parts.size() != 3 or parts[0] != "formula":
		return
	var entry := _battle_log_by_group.get(int(parts[1])) as BattleLogEntry
	var event := entry.events[int(parts[2])] if entry != null and int(parts[2]) >= 0 and int(parts[2]) < entry.events.size() else null
	var formula := event.formula if event != null else null
	if formula == null:
		return
	var popup_content := _format_formula_popup(formula, event)
	formula_popup_text.text = popup_content
	formula_popup.visible = true
	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	var desired_size := _measure_formula_popup_size(popup_content, viewport_size)
	var safe_size := Vector2(minf(desired_size.x, viewport_size.x), minf(desired_size.y, viewport_size.y))
	formula_popup.size = safe_size
	formula_popup_text.scroll_active = true
	formula_popup.position = BattleFormulaPresenter.place_popup(
		mouse, viewport_size, safe_size, FORMULA_POPUP_MOUSE_GAP
	)
	_formula_popup_hide_generation += 1


func _measure_formula_popup_size(popup_content: String, viewport_size: Vector2) -> Vector2:
	return BattleFormulaPresenter.measure_popup_size(
		popup_content,
		formula_popup_text.get_theme_font("normal_font"),
		formula_popup_text.get_theme_font_size("normal_font_size"),
		FORMULA_POPUP_MIN_WIDTH,
		FORMULA_POPUP_MAX_WIDTH,
		FORMULA_POPUP_MAX_HEIGHT,
		FORMULA_POPUP_CONTENT_PADDING,
		viewport_size
	)


func _on_battle_log_meta_hover_ended(_meta: Variant) -> void:
	_schedule_formula_popup_hide()


func _schedule_formula_popup_hide() -> void:
	if not is_instance_valid(formula_popup) or not formula_popup.visible:
		return
	_formula_popup_hide_generation += 1
	_hide_formula_popup_after_pointer_transition(_formula_popup_hide_generation)


func _on_formula_popup_mouse_entered() -> void:
	_formula_popup_hide_generation += 1


func _hide_formula_popup_after_pointer_transition(generation: int) -> void:
	await get_tree().create_timer(0.2).timeout
	if generation != _formula_popup_hide_generation or not is_instance_valid(formula_popup):
		return
	if formula_popup.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	formula_popup.visible = false


func _format_formula_popup(formula: BattleFormulaData, event: BattleEffectEvent = null) -> String:
	return BattleFormulaPresenter.format_popup(formula, event)


func _play_battle_effect_visual(event: BattleEffectEvent) -> void:
	if event == null or event.visual_kind == &"" or not is_instance_valid(battle_effect_layer):
		return
	var target_slot := _battle_state_slots.get(event.target) as BoardSlot
	if event.visual_kind in [&"fire_burn", &"fire_tick", &"fire_finish"] and is_instance_valid(target_slot):
		var inverse := battle_effect_layer.get_global_transform_with_canvas().affine_inverse()
		var global_rect := target_slot.get_global_rect()
		var flash := ColorRect.new()
		flash.name = "ElementFlash"
		flash.position = inverse * global_rect.position
		flash.size = global_rect.size
		flash.pivot_offset = flash.size * 0.5
		flash.scale = Vector2(0.88, 0.88)
		flash.color = _effect_visual_color(event.visual_kind)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle_effect_layer.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.set_parallel(true)
		flash_tween.tween_property(flash, "scale", Vector2(1.04, 1.04), EFFECT_FLASH_SECONDS)
		flash_tween.tween_property(flash, "modulate:a", 0.0, EFFECT_FLASH_SECONDS)
		flash_tween.set_parallel(false)
		flash_tween.tween_callback(flash.queue_free)
		_play_element_impact(inverse * global_rect.get_center(), event.visual_kind)


func _play_element_line(
	points: PackedVector2Array,
	kind: StringName,
	head_color: Color = EFFECT_COLOR_NONE,
	tail_color: Color = EFFECT_COLOR_NONE,
	impact_callback: Callable = Callable(),
	speed_variant: int = -1,
	logical_impact_delay: float = -1.0
) -> Node2D:
	if not is_instance_valid(battle_effect_layer) or points.size() < 2:
		return null
	return BattleAttackTrailRenderer.play(
		battle_effect_layer,
		points,
		BattleAttackEffectProfiles.get_profile(kind),
		head_color,
		tail_color,
		impact_callback,
		battle_controller.battle_speed_multiplier if battle_controller != null else 1.0,
		speed_variant,
		logical_impact_delay
	)


func _action_visual_kind(action_type: CardData.ActionType) -> StringName:
	match action_type:
		CardData.ActionType.RANGED: return &"ranged_attack"
		CardData.ActionType.MAGIC: return &"magic_attack"
		CardData.ActionType.HEAL: return &"heal_action"
		CardData.ActionType.DEFENSE: return &"defense_action"
		_: return &"melee_attack"


func _attack_element_colors(actor: BattleSquadState) -> Dictionary:
	var result := {"head": EFFECT_COLOR_NONE, "tail": EFFECT_COLOR_NONE}
	if actor == null or actor.squad_data == null:
		return result
	var groups := BattleElementResolver.get_element_groups(
		actor.get_rune_pattern_result()
	)
	if groups.is_empty():
		return result
	result["head"] = _element_attack_color(int(groups[0]["element"]))
	result["tail"] = (
		_element_attack_color(int(groups[1]["element"]))
		if groups.size() >= 2
		else result["head"]
	)
	return result


func _element_attack_color(element_type: int) -> Color:
	match element_type:
		CardData.ElementType.LIGHT: return EFFECT_COLOR_LIGHT
		CardData.ElementType.DARK: return EFFECT_COLOR_DARK
		CardData.ElementType.FIRE: return EFFECT_COLOR_FIRE
		CardData.ElementType.WATER: return EFFECT_COLOR_WATER
		CardData.ElementType.WOOD: return EFFECT_COLOR_WOOD
		_: return EFFECT_COLOR_NONE


func _play_element_impact(
	center: Vector2,
	kind: StringName,
	color_override: Color = Color.TRANSPARENT
) -> void:
	var pulse := Node2D.new()
	pulse.name = "ElementImpact"
	pulse.position = center
	pulse.scale = Vector2(0.55, 0.55)
	var diamond := Line2D.new()
	diamond.width = 3.0
	diamond.default_color = color_override if color_override.a > 0.0 else _effect_visual_color(kind)
	diamond.closed = true
	diamond.antialiased = false
	diamond.points = PackedVector2Array([
		Vector2(0.0, -EFFECT_IMPACT_RADIUS.y),
		Vector2(EFFECT_IMPACT_RADIUS.x, 0.0),
		Vector2(0.0, EFFECT_IMPACT_RADIUS.y),
		Vector2(-EFFECT_IMPACT_RADIUS.x, 0.0),
	])
	pulse.add_child(diamond)
	battle_effect_layer.add_child(pulse)
	var tween := pulse.create_tween()
	tween.set_parallel(true)
	var effect_duration := float(BattleAttackEffectProfiles.get_profile(kind)["duration"])
	tween.tween_property(pulse, "scale", Vector2(1.2, 1.2), effect_duration)
	tween.tween_property(pulse, "modulate:a", 0.0, effect_duration)
	tween.set_parallel(false)
	tween.tween_callback(pulse.queue_free)


func _effect_visual_color(kind: StringName) -> Color:
	match kind:
		&"melee_attack": return Color(1.0, 0.30, 0.12, 0.96)
		&"ranged_attack": return Color(1.0, 0.72, 0.18, 0.96)
		&"magic_attack": return Color(0.36, 0.52, 1.0, 0.96)
		&"water_spread": return Color(0.20, 0.72, 1.0, 0.96)
		&"dark_repeat": return Color(0.72, 0.30, 1.0, 0.96)
		&"wood_pierce": return Color(0.32, 1.0, 0.40, 0.96)
		&"light_reflect": return Color(1.0, 0.96, 0.52, 1.0)
		&"fire_finish": return Color(1.0, 0.88, 0.42, 0.68)
		_: return Color(1.0, 0.32, 0.12, 0.48)


func _request_battle_squad_departure(state: BattleSquadState) -> void:
	# 战斗规则只发出阵亡事实；所有卡牌退场表现仍集中在这个单一入口。
	battle_departure_count += 1
	battle_departure_requested.emit(state)
	var slot := _battle_state_slots.get(state) as BoardSlot
	var row := _row_for_battle_key(state.row_key)
	_active_battle_departures += 1
	_animate_battle_squad_departure(
		state,
		slot,
		row,
		_battle_generation,
		state.life_generation
	)


func _cancel_battle_squad_departure(state: BattleSquadState) -> void:
	if state == null or not state.alive:
		return
	var slot := _battle_state_slots.get(state) as BoardSlot
	if not is_instance_valid(slot):
		var row := _row_for_battle_key(state.row_key)
		if row == null:
			return
		var insert_index := 0
		for existing_state: BattleSquadState in battle_controller.get_all_states():
			if (
				existing_state == state
				or not existing_state.alive
				or existing_state.row_key != state.row_key
				or existing_state.formation_index >= state.formation_index
			):
				continue
			var existing_slot := _battle_state_slots.get(existing_state) as BoardSlot
			if is_instance_valid(existing_slot) and existing_slot.get_parent() == row.squad_row:
				insert_index = maxi(insert_index, row.get_slot_index(existing_slot) + 1)
		slot = row.add_squad(state.squad_data, insert_index)
		if not is_instance_valid(slot):
			return
		_battle_state_slots[state] = slot
	if is_instance_valid(slot):
		slot.cancel_death_dissolve()
	_on_battle_states_changed()


func _animate_battle_squad_departure(
	state: BattleSquadState,
	slot: BoardSlot,
	row: BattlefieldRow,
	battle_generation: int,
	departure_life_generation: int
) -> void:
	if is_instance_valid(slot):
		var noise_seed := float(state.side * 101 + state.formation_index * 17 + battle_departure_count)
		await slot.play_death_dissolve(noise_seed)
	if battle_generation != _battle_generation:
		return
	if state.alive or state.life_generation != departure_life_generation:
		_active_battle_departures = maxi(_active_battle_departures - 1, 0)
		if (
			_active_battle_departures == 0
			and _pending_battle_result != BattleController.Result.NONE
		):
			_show_battle_result(_pending_battle_result)
		return
	_completed_battle_departures.append({
		"state": state,
		"slot": slot,
		"row": row,
		"life_generation": departure_life_generation,
	})
	_active_battle_departures = maxi(_active_battle_departures - 1, 0)
	if not _battle_departure_flush_queued:
		_battle_departure_flush_queued = true
		_flush_completed_battle_departures.call_deferred()


func _flush_completed_battle_departures() -> void:
	_battle_departure_flush_queued = false
	var row_slots := {}
	for entry: Dictionary in _completed_battle_departures:
		var state := entry.get("state") as BattleSquadState
		var row := entry.get("row") as BattlefieldRow
		var slot := entry.get("slot") as BoardSlot
		if (
			state != null
			and (state.alive or state.life_generation != int(entry.get("life_generation", -1)))
		):
			if is_instance_valid(slot):
				slot.cancel_death_dissolve()
				_battle_state_slots[state] = slot
			continue
		if is_instance_valid(row) and is_instance_valid(slot):
			if not row_slots.has(row):
				row_slots[row] = []
			(row_slots[row] as Array).append(slot)
		_battle_state_slots.erase(state)
	_completed_battle_departures.clear()
	for row_value: Variant in row_slots:
		var slots: Array[BoardSlot] = []
		for slot_value: Variant in row_slots[row_value]:
			var slot := slot_value as BoardSlot
			if is_instance_valid(slot):
				slots.append(slot)
		(row_value as BattlefieldRow).remove_squad_slots(slots)
	if (
		_active_battle_departures == 0
		and _pending_battle_result != BattleController.Result.NONE
	):
		_show_battle_result(_pending_battle_result)


func _row_for_battle_key(row_key: StringName) -> BattlefieldRow:
	match row_key:
		&"player_front":
			return front_row
		&"player_back":
			return back_row
		&"enemy_front":
			return enemy_front_row
		&"enemy_back":
			return enemy_back_row
		_:
			return null


func _on_battle_finished(result: BattleController.Result) -> void:
	# Controller 信号连接早于采集器；先在结算改写 OwnedCard 前冻结战斗最终状态。
	if _battle_diagnostic_recorder != null:
		_battle_diagnostic_recorder.finish(result)
	_pending_battle_result = result
	if _active_battle_departures == 0:
		_show_battle_result(result)


func _show_battle_result(result: BattleController.Result) -> void:
	var profile_started_usec := Time.get_ticks_usec() if _battle_performance_trace_enabled else 0
	_pending_battle_result = BattleController.Result.NONE
	current_phase = GamePhase.RESULT
	_manual_pause_requested = false
	_inspection_pause_requested = false
	_special_spell_pause_requested = false
	_clear_spell_cast_presentation()
	_sync_battle_pause_owners()
	_restore_battle_result_layout()
	_last_battle_settlement_result = settle_current_battle()
	if bool(_last_battle_settlement_result.get("success", false)):
		run_reward_state.pending_next_level_from_id = resource_board_state.level_id
		_add_settled_emblem_rewards_to_library()
	if int(_last_battle_settlement_result.get("equipment_consumed", 0)) > 0:
		_remove_missing_equipment_from_board()
	# 首次提交已经在 settle_current_battle 更新收藏；重复／失败结算才在此刷新。
	if _last_battle_settlement_result.get("status") != BattleSettlementService.STATUS_COMMITTED:
		_sync_legacy_collection_cards()
		_build_collection_cards()
	match result:
		BattleController.Result.PLAYER_VICTORY:
			battle_result_label.text = "胜利"
		BattleController.Result.PLAYER_DEFEAT:
			battle_result_label.text = "失败"
		BattleController.Result.DRAW:
			battle_result_label.text = "平局"
		_:
			battle_result_label.text = "战斗结算"
	_refresh_battle_result_summary()
	_update_phase_label()
	play_area_label.text = "战斗结束：%s" % battle_result_label.text
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		play_area_label.text += "；结算存档失败（错误码 %d）" % save_error
	if profile_started_usec > 0:
		_battle_trace_result_usec += Time.get_ticks_usec() - profile_started_usec


func _refresh_battle_result_summary() -> void:
	if battle_result_summary_label == null or battle_controller == null:
		return
	battle_result_summary_label.text = _format_battle_result_summary(
		battle_controller.permanent_growth_ledger.get_entries(),
		battle_controller.run_reward_ledger.get_entries(),
		_last_battle_settlement_result.get("status") in [
			BattleSettlementService.STATUS_COMMITTED,
			BattleSettlementService.STATUS_ALREADY_COMMITTED,
		]
	)

	battle_result_summary_label.scroll_to_line(0)


func _remove_missing_equipment_from_board() -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			var item := squad.get_equipped_item() if squad != null else null
			if item != null and owned_card_collection.get_by_instance_id(item.instance_id) == null:
				squad.unequip_item()
				slot.set_squad_data(squad)


func _format_battle_result_summary(
	growth_entries: Array[Dictionary],
	reward_entries: Array[Dictionary],
	settled: bool = false
) -> String:
	var lines: Array[String] = ["卡面：本局统计"]
	var growth_totals: Dictionary = {}
	var growth_order: Array[String] = []
	for entry: Dictionary in growth_entries:
		if int(entry.get("side", BattleSquadState.Side.PLAYER)) != BattleSquadState.Side.PLAYER:
			continue
		var stat := entry.get("stat", &"") as StringName
		if stat not in [
			BattlePermanentGrowthLedger.STAT_BASE_VALUE,
			BattlePermanentGrowthLedger.STAT_BASE_ARMOR,
		]:
			continue
		var key := "%d:%d:%s" % [
			int(entry.get("owner_runtime_id", -1)),
			int(entry.get("card_index", -1)),
			String(stat),
		]
		if not growth_totals.has(key):
			var card := entry.get("card_data") as CardData
			growth_totals[key] = {
				"card_name": card.display_name if card != null else String(entry.get("card_id", "未知卡牌")),
				"stat": stat,
				"amount": 0.0,
			}
			growth_order.append(key)
		var total := growth_totals[key] as Dictionary
		total["amount"] = float(total.get("amount", 0.0)) + float(entry.get("amount", 0.0))
	if growth_order.is_empty():
		lines.append("永久成长：无")
	else:
		lines.append("永久成长" if settled else "永久成长（待写回）")
		for key: String in growth_order:
			var total := growth_totals[key] as Dictionary
			var stat_name := (
				"行动"
				if total.get("stat") == BattlePermanentGrowthLedger.STAT_BASE_VALUE
				else "基础护甲"
			)
			lines.append("• %s：%s %s" % [
				String(total.get("card_name", "未知卡牌")),
				stat_name,
				_format_positive_result_amount(float(total.get("amount", 0.0))),
			])

	var gold_total := 0
	var random_card_total := 0
	var awarded_card_names: Array[String] = []
	var random_emblem_names: Array[String] = []
	for entry: Dictionary in reward_entries:
		if int(entry.get("side", -1)) != BattleSquadState.Side.PLAYER:
			continue
		match entry.get("kind", &"") as StringName:
			BattleRunRewardLedger.KIND_GOLD:
				gold_total += int(entry.get("amount", 0))
			BattleRunRewardLedger.KIND_RANDOM_CARD_REQUEST:
				random_card_total += int(entry.get("amount", 0))
			BattleRunRewardLedger.KIND_GOLD_DELTA:
				gold_total += int((entry.get("parameters", {}) as Dictionary).get("gold_delta", 0))
			BattleRunRewardLedger.KIND_OWNED_CARD_AWARD:
				awarded_card_names.append(String((entry.get("parameters", {}) as Dictionary).get("card_name", "资源卡")))
			BattleRunRewardLedger.KIND_RANDOM_EMBLEM_INSTANCE:
				random_emblem_names.append(String((entry.get("parameters", {}) as Dictionary).get("emblem_id", "基础纹章")))
	if gold_total == 0 and random_card_total <= 0 and awarded_card_names.is_empty() and random_emblem_names.is_empty():
		lines.append("本场奖励：无")
	else:
		lines.append("本场奖励" if settled else "本场奖励（待写回）")
		if gold_total != 0:
			lines.append("• 金币 %s%d" % ["+" if gold_total > 0 else "", gold_total])
		if random_card_total > 0:
			lines.append(
				"• 随机随从请求已进入待解析队列 +%d" % random_card_total
				if settled
				else "• 待抽取随从 +%d" % random_card_total
			)
		for card_name: String in awarded_card_names:
			lines.append("• 获得资源卡：%s" % card_name)
		for emblem_name: String in random_emblem_names:
			lines.append("• 基础纹章：%s" % emblem_name)
	return "\n".join(lines)


func settle_current_battle() -> Dictionary:
	if _battle_snapshot == null or battle_controller == null:
		return {
			"success": false,
			"status": BattleSettlementService.STATUS_FAILED,
			"reason": "missing_main_battle_context",
		}
	var result := battle_settlement_service.settle(
		_battle_snapshot,
		battle_controller.permanent_growth_ledger.get_entries(),
		battle_controller.run_reward_ledger.get_entries(),
		owned_card_collection,
		run_reward_state,
		settlement_journal,
		battle_controller.get_owned_card_change_entries_for_settlement(),
		_build_card_definition_registry(),
		resource_board_state
	)
	if result.get("status") == BattleSettlementService.STATUS_COMMITTED:
		run_reward_state.pending_next_level_from_id = resource_board_state.level_id
		prepared_spell_instance_ids.clear()
		_refresh_spell_preparation_tray()
		_sync_legacy_collection_cards()
		_build_collection_cards()
	return result


func _add_settled_emblem_rewards_to_library() -> void:
	if _battle_snapshot == null:
		return
	var entries := run_reward_state.drain_emblem_instances_for_battle(_battle_snapshot.battle_instance_id)
	for entry: Dictionary in entries:
		var sticker_state := {
			"instance_id": entry.get("emblem_instance_id", ""),
			"emblem_id": entry.get("emblem_id", ""),
			"temporary": false,
			"source": entry.get("source", "battle_reward"),
		}
		if emblem_library.can_add_sticker(sticker_state):
			var accepted: bool = emblem_library.return_sticker(sticker_state)
			assert(accepted, "奖励纹章入包前已验证合法性")
		else:
			run_reward_state.add_ground_item({
				"ground_id": String(entry.get("emblem_instance_id", "")),
				"item_kind": "emblem",
				"item_id": String(entry.get("emblem_id", "")),
				"instance_id": String(entry.get("emblem_instance_id", "")),
				"battle_instance_id": String(entry.get("battle_instance_id", "")),
				"source": entry.get("source", "battle_reward"),
			})
	_refresh_ground_reward_panel()


func _refresh_ground_reward_panel() -> void:
	if not is_instance_valid(ground_reward_panel) or not is_instance_valid(ground_reward_list): return
	for child: Node in ground_reward_list.get_children(): child.queue_free()
	var items := run_reward_state.pending_ground_items
	ground_reward_panel.visible = not items.is_empty()
	for item: Dictionary in items:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 40
		row.add_theme_constant_override("separation", 5)
		var label := Label.new()
		label.text = String(item.get("item_id", "未知奖励"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var item_id := StringName(String(item.get("ground_id", "")))
		var keep := Button.new()
		keep.text = "入包"
		keep.custom_minimum_size.x = 58
		keep.tooltip_text = "放入工具箱；需要有可用空格"
		keep.disabled = not _ground_item_can_enter_toolbox(item)
		keep.pressed.connect(_keep_ground_item.bind(item_id))
		row.add_child(keep)
		var equip := Button.new()
		equip.text = "装备"
		equip.custom_minimum_size.x = 58
		equip.tooltip_text = "装备到第一处可用友军纹章槽"
		equip.disabled = not _find_ground_emblem_slot().get("success", false)
		equip.pressed.connect(_equip_ground_item.bind(item_id))
		row.add_child(equip)
		var discard := Button.new()
		discard.text = "丢弃"
		discard.custom_minimum_size.x = 58
		discard.pressed.connect(_discard_ground_item.bind(item_id))
		row.add_child(discard)
		ground_reward_list.add_child(row)
	if is_instance_valid(continue_next_level_button):
		continue_next_level_button.disabled = not items.is_empty()
	if is_instance_valid(start_battle_button):
		start_battle_button.disabled = not items.is_empty() or current_phase != GamePhase.PREPARE or not run_reward_state.pending_next_level_from_id.is_empty()


func _ground_item_can_enter_toolbox(item: Dictionary) -> bool:
	if String(item.get("item_kind", "")) != "emblem": return false
	return emblem_library.can_add_sticker({
		"instance_id": item.get("instance_id", ""),
		"emblem_id": item.get("item_id", ""),
		"temporary": false,
		"source": item.get("source", "ground_reward"),
	})


func _keep_ground_item(item_id: StringName) -> void:
	for item: Dictionary in run_reward_state.pending_ground_items:
		if StringName(String(item.get("ground_id", ""))) != item_id: continue
		if not _ground_item_can_enter_toolbox(item): return
		if emblem_library.return_sticker({
			"instance_id": item.get("instance_id", ""),
			"emblem_id": item.get("item_id", ""),
			"temporary": false,
			"source": item.get("source", "ground_reward"),
		}):
			run_reward_state.remove_ground_item(item_id)
			_refresh_ground_reward_panel()
			return


func _find_ground_emblem_slot() -> Dictionary:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null: continue
			for card: CardData in squad.horizontal_cards:
				var owned := squad.get_owned_card(card)
				if owned == null: continue
				for slot_index: int in squad.get_visible_emblem_slot_indices(card):
					if slot_index >= 0 and slot_index < owned.emblem_slots.size() and owned.emblem_slots[slot_index].is_empty():
						return {"success": true, "owned": owned, "slot_index": slot_index, "squad_slot": slot}
	return {"success": false}


func _equip_ground_item(item_id: StringName) -> void:
	var item: Dictionary
	for candidate: Dictionary in run_reward_state.pending_ground_items:
		if StringName(String(candidate.get("ground_id", ""))) == item_id:
			item = candidate
			break
	if item.is_empty() or String(item.get("item_kind", "")) != "emblem": return
	var target := _find_ground_emblem_slot()
	if not bool(target.get("success", false)): return
	var owned := target.get("owned") as OwnedCard
	var instance_id := StringName(String(item.get("instance_id", "")))
	if not owned.set_emblem_slot(int(target.get("slot_index", -1)), {"emblem_id": StringName(String(item.get("item_id", ""))), "instance_id": instance_id, "temporary": false}): return
	(target.get("squad_slot") as BoardSlot).set_squad_data((target.get("squad_slot") as BoardSlot).get_squad_data())
	run_reward_state.remove_ground_item(item_id)
	_refresh_ground_reward_panel()
	_build_collection_cards()


func _discard_ground_item(item_id: StringName) -> void:
	run_reward_state.remove_ground_item(item_id)
	_refresh_ground_reward_panel()


func _on_continue_next_level_pressed() -> void:
	var completed_level := run_reward_state.pending_next_level_from_id
	var from_result := current_phase == GamePhase.RESULT and bool(_last_battle_settlement_result.get("success", false))
	if (not from_result and (current_phase != GamePhase.PREPARE or completed_level.is_empty())) or not run_reward_state.pending_ground_items.is_empty():
		return
	if completed_level.is_empty():
		completed_level = resource_board_state.level_id
	var level_number := int(String(completed_level).get_slice("_", 1)) + 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not start_new_resource_level(StringName("level_%06d" % level_number), rng):
		return
	_clear_battle_presentation_for_preparation()
	run_reward_state.pending_next_level_from_id = &""
	if battle_controller != null: battle_controller.clear_battle()
	_battle_snapshot = null
	_last_battle_settlement_result.clear()
	current_phase = GamePhase.PREPARE
	battle_result_panel.visible = false
	_clear_battle_log()
	_update_phase_label()
	_build_collection_cards()
	_refresh_ground_reward_panel()
	play_area_label.text = "已进入%s；资源板已按新关卡规则重新生成" % resource_board_state.level_id


func _on_developer_console_command_submitted(command: String) -> void:
	if not is_instance_valid(_developer_console):
		return
	var tokens := command.strip_edges().split(" ", false)
	if tokens.is_empty():
		return
	if tokens[0].to_lower() == "help":
		_developer_console.append_output("命令：gold set <非负整数> / 设置金币数 <非负整数>（仅准备阶段）；sticker list/add <贴纸ID>；wound list/add <伤势ID或名称>；resource list/add <资源ID或名称>；resource enemy add <资源ID或名称>")
		return
	if (tokens[0].to_lower() == "gold" and tokens.size() >= 2 and tokens[1].to_lower() == "set") or tokens[0] == "设置金币数":
		var amount_token := tokens[2] if tokens[0].to_lower() == "gold" and tokens.size() == 3 else (tokens[1] if tokens[0] == "设置金币数" and tokens.size() == 2 else "")
		_handle_developer_gold_command(amount_token)
		return
	if tokens[0].to_lower() == "resource":
		_handle_developer_resource_command(tokens)
		return
	if tokens.size() == 2 and tokens[0].to_lower() == "wound" and tokens[1].to_lower() == "list":
		var wound_ids := PackedStringArray()
		for definition: Dictionary in emblem_library.get_definitions():
			if String(definition.get("status_kind", "emblem")) == "wound":
				wound_ids.append(String(definition.get("id", "")))
		_developer_console.append_output("可用伤势：" + "、".join(wound_ids))
		return
	if tokens.size() >= 3 and tokens[0].to_lower() == "wound" and tokens[1].to_lower() == "add":
		var requested_wound := " ".join(tokens.slice(2))
		for definition: Dictionary in emblem_library.get_definitions():
			if (
				String(definition.get("status_kind", "emblem")) == "wound"
				and requested_wound in [String(definition.get("id", "")), String(definition.get("name", ""))]
			):
				_developer_console.append_output(_add_developer_wound(definition))
				return
		_developer_console.append_output("找不到伤势 ID 或名称：" + requested_wound + "；可输入 wound list 查看。")
		return
	if tokens.size() == 2 and tokens[0].to_lower() == "sticker" and tokens[1].to_lower() == "list":
		var ids := PackedStringArray()
		for definition: Dictionary in emblem_library.get_definitions():
			if String(definition.get("status_kind", "emblem")) != "wound":
				ids.append(String(definition.get("id", "")))
		_developer_console.append_output("可用贴纸：" + "、".join(ids))
		return
	if tokens.size() != 3 or tokens[0].to_lower() != "sticker" or tokens[1].to_lower() != "add":
		_developer_console.append_output("命令格式无效。输入 help 查看用法。")
		return
	var requested_id := StringName(tokens[2])
	for definition: Dictionary in emblem_library.get_definitions():
		if StringName(String(definition.get("id", ""))) == requested_id:
			_developer_console.append_output(_add_developer_sticker(definition))
			return
	_developer_console.append_output("找不到贴纸 ID：" + String(requested_id) + "；可输入 sticker list 查看。")


func _handle_developer_gold_command(amount_text: String) -> void:
	if current_phase != GamePhase.PREPARE:
		_developer_console.append_output("设置金币数只允许在准备阶段执行。")
		return
	if amount_text.is_empty() or amount_text.length() > 16:
		_developer_console.append_output("金币数须为0至9007199254740991之间的非负整数（可精确保存范围）；格式：gold set 100。")
		return
	for index: int in amount_text.length():
		var codepoint := amount_text.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			_developer_console.append_output("金币数须为非负整数，不接受负数、小数或非数字。")
			return
	if amount_text.length() == 16 and amount_text > "9007199254740991":
		_developer_console.append_output("金币数超出可精确保存范围，未更改金币。")
		return
	var requested_gold := int(amount_text)
	var previous_gold := run_reward_state.gold
	run_reward_state.gold = requested_gold
	_refresh_ordinary_shop_panel()
	var save_error := save_run_to_path(run_save_path)
	if save_error != OK:
		run_reward_state.gold = previous_gold
		_refresh_ordinary_shop_panel()
		_developer_console.append_output("保存失败（%s），余额已恢复为%s。" % [error_string(save_error), str(previous_gold) + "金币"])
		return
	_developer_console.append_output("余额已设置为%d金币并保存。" % requested_gold)


func _handle_developer_resource_command(tokens: PackedStringArray) -> void:
	if tokens.size() == 2 and tokens[1].to_lower() == "list":
		var names: PackedStringArray = []
		for card: CardData in _build_card_definition_registry().values():
			if card.card_type == CardData.CardType.RESOURCE: names.append("%s (%s)" % [card.display_name, card.id])
		_developer_console.append_output("可用资源：" + "、".join(names))
		return
	var is_enemy := tokens.size() == 4 and tokens[1].to_lower() == "enemy" and tokens[2].to_lower() == "add"
	var is_player := tokens.size() == 3 and tokens[1].to_lower() == "add"
	if not is_enemy and not is_player:
		_developer_console.append_output("命令格式：resource list；resource add <资源ID或名称>；resource enemy add <资源ID或名称>")
		return
	var requested := tokens[3] if is_enemy else tokens[2]
	for card: CardData in _build_card_definition_registry().values():
		if card.card_type != CardData.CardType.RESOURCE or (String(card.id) != requested and card.display_name != requested): continue
		if is_enemy:
			_developer_console.append_output(_add_enemy_test_resource(card))
		else:
			if current_phase != GamePhase.PREPARE:
				_developer_console.append_output("只能在准备阶段加入测试资源。")
				return
			var owned := owned_card_collection.create_card(card)
			collection_cards.append(card)
			_build_collection_cards()
			_refresh_resource_preparation_trays()
			_developer_console.append_output("已加入收藏：%s。可切换收藏的资源类型筛选后拖入资源板。" % card.display_name)
		return
	_developer_console.append_output("找不到资源：%s；输入 resource list 查看。" % requested)


func _add_enemy_test_resource(definition: CardData) -> String:
	if current_phase != GamePhase.PREPARE:
		return "只能在准备阶段部署敌方测试资源。"
	var sequence: int = resource_board_state.level_resource_cards.enemy.size() + 1
	var owned := OwnedCard.new()
	owned.initialize(definition, StringName("enemy_resource_%04d" % sequence), sequence)
	var occupied: Dictionary = {}
	var disabled: Dictionary = {}
	for cell in resource_board_state.disabled_by_side["enemy"]: disabled[cell] = true
	for placement: Dictionary in resource_board_state.deployments["enemy"].values():
		var origin := Vector2i(placement.anchor[0], placement.anchor[1])
		for pair in placement.shape: occupied[origin + Vector2i(pair[0], pair[1])] = true
	var layout := preload("res://scripts/data/resource_hex_layout.gd")
	for anchor in layout.valid_cells():
		if not layout.can_place(owned.resource_shape, anchor, occupied, disabled): continue
		if resource_board_state.deploy_level_resource("enemy", owned, anchor):
			_refresh_resource_preparation_trays()
			return "已部署敌方测试资源：%s（%d格），不加入玩家收藏。" % [definition.display_name, owned.resource_shape.size()]
	return "敌方资源板没有可用位置，未改变状态。"


func _add_developer_sticker(definition: Dictionary) -> String:
	if current_phase != GamePhase.PREPARE:
		return "只能在准备阶段新增测试贴纸。"
	var emblem_id := StringName(String(definition.get("id", "")))
	if emblem_id.is_empty() or not is_instance_valid(emblem_library):
		return "贴纸定义无效。"
	if emblem_id == &"万能贴纸":
		if _has_universal_sticker_in_collection_or_bag():
			return "万能贴纸已持有，不能重复加入。"
	var instance_id := StringName(
		"dev_sticker_%s_%04d" % [String(emblem_id), _next_developer_emblem_instance]
	)
	var state := {
		"instance_id": instance_id,
		"emblem_id": emblem_id,
		"temporary": false,
		"source": "developer_console",
		"element_sticker": definition.get("target", "emblem") == "rune",
	}
	if not emblem_library.return_sticker(state):
		return "工具箱已满（28/28）或实例已存在；没有新增实例。"
	_next_developer_emblem_instance += 1
	return "已加入 %s（%d/28）" % [String(emblem_id), emblem_library.get_inventory_state().size()]


func _add_developer_wound(definition: Dictionary) -> String:
	if current_phase != GamePhase.PREPARE:
		return "只能在准备阶段新增测试伤势。"
	var wound_id := StringName(String(definition.get("id", "")))
	if wound_id.is_empty() or not is_instance_valid(emblem_library):
		return "伤势定义无效。"
	var instance_id := StringName("dev_wound_%s_%04d" % [String(wound_id), _next_developer_emblem_instance])
	var state := {
		"kind": "wound",
		"instance_id": instance_id,
		"wound_id": wound_id,
		"level": int(definition.get("level", 1)),
		"temporary": false,
		"source": "developer_console",
	}
	if not emblem_library.return_sticker(state):
		return "工具箱已满（28/28）或实例无效；没有新增伤势。"
	_next_developer_emblem_instance += 1
	return "已将伤势 %s 加入工具箱（%d/28）" % [String(wound_id), emblem_library.get_inventory_state().size()]


func _has_universal_sticker_in_collection_or_bag() -> bool:
	for item: Dictionary in emblem_library.get_inventory_state():
		if StringName(String(item.get("emblem_id", ""))) == &"万能贴纸":
			return true
	for owned: OwnedCard in owned_card_collection.get_cards():
		for state: Dictionary in owned.rune_stickers:
			if StringName(String(state.get("emblem_id", ""))) == &"万能贴纸":
				return true
	return false


func _has_universal_sticker_on_owned_cards() -> bool:
	for owned: OwnedCard in owned_card_collection.get_cards():
		for state: Dictionary in owned.rune_stickers:
			if StringName(String(state.get("emblem_id", ""))) == &"万能贴纸":
				return true
	return false


func _sticker_instance_is_attached(instance_id: StringName) -> bool:
	if instance_id.is_empty():
		return false
	for owned: OwnedCard in owned_card_collection.get_cards():
		for state: Dictionary in owned.emblem_slots:
			if StringName(String(state.get("instance_id", ""))) == instance_id:
				return true
		for state: Dictionary in owned.rune_stickers:
			if StringName(String(state.get("instance_id", ""))) == instance_id:
				return true
		for state: Dictionary in owned.wound_slots:
			if StringName(String(state.get("instance_id", ""))) == instance_id:
				return true
	return false


func _format_positive_result_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "+%d" % roundi(amount)
	return "+%s" % BattleLogEntry.format_number(amount)


func _restore_battle_result_layout() -> void:
	# 阵亡动画会把槽从行中移除；结算页按战前快照重建，再按稳定排位映射战绩。
	_restore_battle_snapshot()
	_battle_state_slots.clear()
	for state: BattleSquadState in battle_controller.get_all_states():
		var row := _row_for_battle_key(state.row_key)
		if row == null:
			continue
		var row_slots := row.get_squads()
		if state.formation_index < 0 or state.formation_index >= row_slots.size():
			continue
		var slot := row_slots[state.formation_index] as BoardSlot
		_battle_state_slots[state] = slot
		slot.show_battle_result_statistics(
			state.get_battle_statistics(),
			not state.alive,
			state.get_effective_action_type()
		)


func _connect_board_rows() -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.board_slot_clicked.connect(_on_board_slot_clicked)
		row.card_dropped.connect(_on_board_card_dropped)
		row.squads_changed.connect(_on_battlefield_squads_changed)
		row.card_inspection_requested.connect(_on_card_inspection_requested)
		row.card_click_carry_requested.connect(
			_on_click_carry_requested
		)
	for enemy_row: BattlefieldRow in [enemy_back_row, enemy_front_row]:
		enemy_row.set_drag_enabled(false)
		enemy_row.squads_changed.connect(_on_battlefield_squads_changed)
		enemy_row.card_inspection_requested.connect(_on_card_inspection_requested)


func _on_battlefield_squads_changed() -> void:
	if _battlefield_clock_check_queued:
		return
	_battlefield_clock_check_queued = true
	_reset_rune_flow_if_no_battlefield_effects.call_deferred()


func _reset_rune_flow_if_no_battlefield_effects() -> void:
	_battlefield_clock_check_queued = false
	var profile_started_usec := Time.get_ticks_usec() if _equipment_drop_profile_active else 0
	# 跨排移动会先移除后加入；延迟到事务结束再检查，避免中途误重置。
	if not _battlefield_has_active_rune_effects():
		CardView.reset_active_rune_flow()
	_refresh_preparation_effect_preview()
	if profile_started_usec > 0:
		_record_equipment_drop_profile_duration(
			&"deferred_board_refresh",
			Time.get_ticks_usec() - profile_started_usec
		)


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
	var profile_started_usec := Time.get_ticks_usec() if _equipment_drop_profile_active else 0
	_clear_page_turn_overlay()
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
		var owned_card := _get_owned_card_for_collection_index(
			filtered_cards,
			page_start + page_index
		)
		var slot := _create_collection_card_slot(
			collection_card,
			(
				_is_owned_card_deployed(owned_card)
				or _is_spell_prepared(owned_card)
				if owned_card != null
				else _is_card_deployed(collection_card)
			),
			true,
			owned_card
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
	if profile_started_usec > 0:
		_record_equipment_drop_profile_duration(
			&"collection_rebuild_total",
			Time.get_ticks_usec() - profile_started_usec
		)
	_refresh_resource_preparation_trays()


func _find_collection_slot_for_owned_card(owned_card: OwnedCard) -> Control:
	if owned_card == null:
		return null
	for slot: Control in _get_collection_card_slots():
		if slot.get_meta("owned_card", null) == owned_card:
			return slot
	return null


func _animate_returned_equipment_entries(entries: Array[Dictionary]) -> void:
	for entry: Dictionary in entries:
		var owned_item := entry.get("owned_card") as OwnedCard
		var slot := _find_collection_slot_for_owned_card(owned_item)
		if slot == null or slot.get_child_count() == 0:
			continue
		_animate_collection_card_entry.call_deferred(
			slot.get_child(0) as CardView,
			entry.get("global_position", Vector2.ZERO) as Vector2
		)


func _capture_returned_equipment_entry(
	slot: BoardSlot,
	result_squad: SquadData,
	release_binding: bool = false
) -> Dictionary:
	if not is_instance_valid(slot):
		return {}
	var squad := slot.get_squad_data()
	var owned_item := squad.get_equipped_item() if squad != null else null
	if owned_item == null or result_squad.get_equipped_item() == owned_item:
		return {}
	var indicator := slot.get_equipment_indicator()
	var entry := {
		"owned_card": owned_item,
		"global_position": (
			indicator.global_position
			if is_instance_valid(indicator)
			else slot.global_position
		),
	}
	if release_binding:
		squad.unequip_item()
		slot.set_squad_data(squad)
	return entry


func _create_collection_card_slot(
	card_data: CardData,
	is_deployed_ghost: bool = false,
	interactive: bool = true,
	owned_card: OwnedCard = null
) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = (
		Vector2(99, 136) * collection_card_scale
		+ COLLECTION_CARD_SAFE_PADDING * 2.0
	)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_meta("is_deployed_ghost", is_deployed_ghost)
	if owned_card != null:
		slot.set_meta("owned_card", owned_card)

	var card_view := CARD_VIEW_SCENE.instantiate() as CardView
	card_view.position = (
		COLLECTION_CARD_SAFE_PADDING
		+ Vector2(99, 136)
		* (collection_card_scale - 1.0)
		* 0.5
	)
	card_view.scale = Vector2(collection_card_scale, collection_card_scale)
	card_view.set_card_data(card_data)
	card_view.set_owned_card(owned_card)
	card_view.showing_effect = bool(
		_collection_effect_display_states.get(
			_get_collection_effect_state_key(card_data, owned_card),
			false
		)
	)
	card_view.collection_return_requested.connect(
		_animate_collection_card_entry
	)
	if is_deployed_ghost:
		card_view.modulate.a = CardView.COLLECTION_DRAG_GHOST_ALPHA
		card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_view.configure_drag_source(false)
	elif interactive:
		card_view.card_clicked.connect(_on_collection_card_clicked)
		card_view.inspection_requested.connect(_on_card_inspection_requested)
		card_view.effect_display_changed.connect(
			_on_collection_effect_display_changed.bind(owned_card)
		)
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


func _on_collection_effect_display_changed(
	card_data: CardData,
	is_showing_effect: bool,
	owned_card: OwnedCard = null
) -> void:
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		return
	var state_key: Variant = _get_collection_effect_state_key(card_data, owned_card)
	if is_showing_effect:
		_collection_effect_display_states[state_key] = true
	else:
		_collection_effect_display_states.erase(state_key)


func _get_collection_effect_state_key(card_data: CardData, owned_card: OwnedCard = null) -> Variant:
	# 已拥有卡优先使用实例ID，避免相同定义的多张卡共享翻页／描述状态。
	if owned_card != null and not owned_card.instance_id.is_empty():
		return owned_card.instance_id
	# 正式卡使用稳定id；测试或临时卡没有id时退回资源对象本身，避免空id互相串状态。
	if card_data != null and not card_data.id.is_empty():
		return card_data.id
	return card_data


func _get_owned_card_for_collection_index(
	filtered_cards: Array[CardData],
	filtered_index: int
) -> OwnedCard:
	if filtered_index < 0 or filtered_index >= filtered_cards.size():
		return null
	if collection_bookmark_active and filtered_index < recently_returned_owned_cards.size():
		var recent_owned := recently_returned_owned_cards[filtered_index]
		if recent_owned != null and recent_owned.card_data == filtered_cards[filtered_index]:
			return recent_owned
	var target := filtered_cards[filtered_index]
	var occurrence := 0
	for index: int in filtered_index:
		if filtered_cards[index] == target:
			occurrence += 1
	var seen := 0
	for owned_card: OwnedCard in owned_card_collection.get_cards():
		if owned_card.card_data != target:
			continue
		if seen == occurrence:
			return owned_card
		seen += 1
	return null


func _is_card_deployed(card_data: CardData) -> bool:
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad_data := slot.get_squad_data()
			if squad_data != null and squad_data.contains(card_data):
				return true
			if (
				squad_data != null
				and squad_data.get_equipped_item() != null
				and squad_data.get_equipped_item().card_data == card_data
			):
				return true
	return false


func _is_owned_card_deployed(owned_card: OwnedCard) -> bool:
	if owned_card == null:
		return false
	for side in ["player", "enemy"]:
		if resource_board_state.deployments.get(side, {}).has(String(owned_card.instance_id)):
			return true
	for row: BattlefieldRow in [front_row, back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			if squad.get_equipped_item() == owned_card:
				return true
			for member_data: CardData in squad.horizontal_cards:
				if squad.get_owned_card(member_data) == owned_card:
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


func _on_card_inspection_requested(
	card_view: CardView,
	card_data: CardData,
	owned_card: OwnedCard
) -> void:
	if card_data == null or is_instance_valid(_inspection_overlay):
		return
	_open_card_inspection(card_data, owned_card, card_view)


func open_paused_card_inspection_at(canvas_position: Vector2) -> bool:
	if (
		not get_tree().paused
		or current_phase != GamePhase.BATTLE
		or is_instance_valid(_inspection_overlay)
	):
		return false
	var target_view: CardView
	for node: Node in get_tree().get_nodes_in_group("card_views"):
		if not node is CardView:
			continue
		var candidate := node as CardView
		if (
			not candidate.is_visible_in_tree()
			or candidate.mouse_filter == Control.MOUSE_FILTER_IGNORE
			or candidate.card_data == null
		):
			continue
		var local_position := (
			candidate.get_global_transform_with_canvas().affine_inverse()
			* canvas_position
		)
		if candidate._has_point(local_position):
			if target_view == null or candidate.global_z_index >= target_view.global_z_index:
				target_view = candidate
	if target_view == null:
		return false
	_on_card_inspection_requested(
		target_view,
		target_view.card_data,
		target_view.get_owned_card()
	)
	return is_instance_valid(_inspection_overlay)


func _build_inspection_overlay(title_text: String, help_text: String) -> void:
	_inspection_overlay = CardInspectionOverlayScript.new()
	_inspection_overlay.name = "CardInspectionOverlay"
	_inspection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspection_overlay.z_index = 4000
	_inspection_overlay.cancel_carry_if_active = _cancel_inspection_carry_from_overlay
	_inspection_overlay.close_requested.connect(_close_card_inspection)
	add_child(_inspection_overlay)

	var dim := ColorRect.new()
	dim.name = "InspectionDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.02, 0.025, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_inspection_dim_gui_input)
	_inspection_overlay.add_child(dim)
	_inspection_dim = dim

	var title := _make_label(
		title_text,
		Vector2(24, 14),
		Vector2(480, 28)
	)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("f5df9b"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.z_index = 20
	_inspection_overlay.add_child(title)

	var help := _make_label(
		help_text,
		Vector2(24, 42),
		Vector2(680, 22)
	)
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color("d9e5df"))
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.z_index = 20
	_inspection_overlay.add_child(help)



func _open_card_inspection(card_data: CardData, owned_card: OwnedCard, source_view: CardView = null, read_only: bool = false, hidden_offer: Dictionary = {}) -> void:
	_finish_rune_scraper_mode()
	_cancel_click_carry()
	_inspection_closing = false
	_inspection_previous_tree_paused = get_tree().paused
	if (
		current_phase == GamePhase.BATTLE
		and _inspection_previous_tree_paused
		and not _manual_pause_requested
		and not _special_spell_pause_requested
	):
		_manual_pause_requested = true
	_inspection_pause_requested = current_phase == GamePhase.BATTLE
	_inspection_effect_layer_was_visible = (
		battle_effect_layer.visible if is_instance_valid(battle_effect_layer) else true
	)
	_inspection_card_data = card_data
	_inspection_owned_card = owned_card
	_inspection_has_library_toolbox = (
		not read_only
		and card_data != null
		and card_data.card_type == CardData.CardType.MINION
		and is_instance_valid(emblem_library)
		and _emblem_library_parent != null
	)
	_inspection_read_only = read_only
	if _inspection_has_library_toolbox:
		_inspection_library_expanded = _last_minion_inspection_library_expanded
	_build_inspection_overlay(
		"卡牌检视" + ("（战斗中只读）" if current_phase == GamePhase.BATTLE else ""),
		("商店卡牌只读；" if read_only else ("准备阶段：拖动纹章到卡牌上的金色2×2点；" if current_phase == GamePhase.PREPARE else "战斗检视为只读；")) + "点击暗幕、右键或按 Esc 关闭"
	)

	_inspection_card_view = (SHOP_CARD_VIEW_SCENE if not hidden_offer.is_empty() else CARD_VIEW_SCENE).instantiate() as CardView
	_inspection_card_view.name = "InspectionCard"
	_inspection_card_view.position = Vector2.ZERO
	_inspection_card_view.pivot_offset = Vector2.ZERO
	_inspection_card_view.scale = Vector2.ONE
	_inspection_card_view.z_index = 25
	_inspection_card_view.set_card_data(card_data)
	_inspection_card_view.set_owned_card(owned_card)
	if not hidden_offer.is_empty():
		_inspection_card_view.configure_hidden(card_data, hidden_offer)
	var inspection_squad := _find_squad_for_owned_card(owned_card)
	if inspection_squad != null:
		_inspection_card_view.set_squad_attribute_preview_from_squad(inspection_squad)
	var inspection_battle_state := _find_battle_state_for_squad(inspection_squad)
	if inspection_battle_state != null:
		_inspection_card_view.set_battle_action_type(
			inspection_battle_state.runtime_action_type_override as CardData.ActionType
			if inspection_battle_state.runtime_action_type_override >= 0
			else inspection_battle_state.get_effective_action_type()
		)
		_inspection_card_view.set_battle_target_weight(
			battle_controller.get_effective_target_weight(inspection_battle_state)
		)
		_inspection_card_view.set_battle_action_value(
			inspection_battle_state.get_display_action_value()
		)
		_inspection_card_view.set_battle_vitals(
			inspection_battle_state.displayed_health,
			inspection_battle_state.displayed_armor
		)
		_inspection_card_view.set_battle_remaining_cooldown(
			inspection_battle_state.remaining_cooldown
		)
		var masked_wound_indices: Array[int] = []
		masked_wound_indices.assign(
			inspection_battle_state.get_masked_wound_indices_by_card().get(card_data, [])
		)
		_inspection_card_view.set_battle_status_slot_states([], masked_wound_indices)
	_inspection_card_view.configure_drag_source(false)
	_inspection_card_view.set_emblem_drop_handler(
		Callable(self, "_handle_inspection_emblem_drop")
	)
	_inspection_overlay.add_child(_inspection_card_view)
	if not hidden_offer.is_empty() and source_view is ShopCardView:
		_inspection_card_view.continue_carousel_from(source_view)
	_refresh_inspection_markers()
	_inspection_surface = preload("res://scripts/ui/inspection_card_surface.gd").new() as InspectionCardSurface
	_inspection_surface.name = "InspectionSurface"
	_inspection_overlay.add_child(_inspection_surface)
	_inspection_surface.setup(_inspection_card_view, _handle_inspection_emblem_drop, _inspection_sticker_tooltip)
	if _inspection_has_library_toolbox:
		_inspection_library_original_parent = emblem_library.get_parent() as Control
		# Control 没有 Node2D 的 global_scale/global_rotation；保存画布变换后，
		# 在新父节点下用 position/scale/rotation 分解回合法的 Control 属性。
		_inspection_library_original_canvas_transform = emblem_library.get_global_transform_with_canvas()
		_inspection_library_original_layout = {
			"position": emblem_library.position,
			"size": emblem_library.size,
			"scale": emblem_library.scale,
			"rotation": emblem_library.rotation,
			"pivot_offset": emblem_library.pivot_offset,
			"custom_minimum_size": emblem_library.custom_minimum_size,
		}
		_inspection_library_original_z_index = emblem_library.z_index
		_inspection_library_original_scroll = emblem_library.get_scroll_position()
		_inspection_library_transform_saved = true
	var target_scale := Vector2(4, 4) # 卡牌检视相对原生卡面的局部4倍；窗口整体倍率仍只由显示壳执行
	var target_position: Vector2 = (_inspection_overlay.size - _inspection_surface.size * target_scale) * 0.5
	_inspection_surface.scale = target_scale
	_inspection_surface.position = target_position
	if is_instance_valid(source_view):
		var source_transform: Transform2D = _inspection_overlay.get_global_transform_with_canvas().affine_inverse() * source_view.get_global_transform_with_canvas()
		_inspection_surface.scale = source_transform.get_scale()
		_inspection_surface.position = source_transform.origin - source_transform.basis_xform(_inspection_surface.PADDING)
		_inspection_surface.rotation = source_transform.get_rotation()
		_inspection_source_view = source_view
		source_view.visible = false
		_set_inspection_source_statistics_suppressed(true)
	if _inspection_has_library_toolbox:
		target_position = _inspection_card_position(_inspection_library_expanded, target_scale)
	var effect_box: PanelContainer = null
	if card_data != null and card_data.effect_text.length() > 36:
		effect_box = PanelContainer.new()
		effect_box.name = "InspectionEffectSideBox"
		effect_box.size = INSPECTION_EFFECT_BOX_SIZE
		effect_box.position = Vector2(
			target_position.x + _inspection_surface.size.x * target_scale.x + 24.0,
			INSPECTION_EFFECT_BOX_TOP
		)
		var effect_style := StyleBoxFlat.new()
		effect_style.bg_color = Color(0.055, 0.07, 0.075, 0.96)
		effect_style.border_color = Color("d1aa58")
		effect_style.set_border_width_all(1)
		effect_box.add_theme_stylebox_override("panel", effect_style)
		var effect_label := Label.new()
		effect_label.text = CardView.format_gold_symbols(card_data.effect_text)
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.add_theme_font_override("font", preload("res://assets/fonts/chill_7.ttf"))
		effect_label.add_theme_font_size_override("font_size", 12)
		effect_label.add_theme_color_override("font_color", Color.WHITE)
		effect_label.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02, 0.95))
		effect_label.add_theme_constant_override("outline_size", 2)
		effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect_box.add_child(effect_label)
		effect_box.z_index = 24
		_inspection_overlay.add_child(effect_box)
	_inspection_dim.modulate.a = 0.0
	_inspection_tween = _inspection_overlay.create_tween().set_parallel(true)
	_inspection_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_inspection_tween.tween_property(_inspection_surface, "position", target_position, 0.25)
	_inspection_tween.tween_property(_inspection_surface, "scale", target_scale, 0.25)
	_inspection_tween.tween_property(_inspection_surface, "rotation", 0.0, 0.25)
	_inspection_tween.tween_property(_inspection_dim, "modulate:a", 1.0, 0.25)
	if is_instance_valid(effect_box):
		effect_box.modulate.a = 0.0
		_inspection_tween.tween_property(effect_box, "modulate:a", 1.0, 0.25)

	if _inspection_has_library_toolbox:
		if emblem_library.get_parent() != null:
			emblem_library.get_parent().remove_child(emblem_library)
		_inspection_overlay.add_child(emblem_library)
		emblem_library.z_index = 15
		emblem_library.set_inspect_mode(true)
		emblem_library.set_drag_enabled(false)
		_set_control_transform_from_canvas(
			emblem_library as Control,
			_inspection_overlay as Control,
			_inspection_library_original_canvas_transform
		)
		var library_target_position := _inspection_library_position(_inspection_library_expanded)
		_inspection_tween.tween_property(emblem_library, "position", library_target_position, 0.25)
		_inspection_tween.tween_property(emblem_library, "scale", Vector2.ONE * INSPECTION_LIBRARY_SCALE, 0.25)
		_inspection_tween.tween_property(emblem_library, "rotation", 0.0, 0.25)
		_inspection_tween.tween_callback(_finish_inspection_library_open).set_delay(0.25)
		_inspection_library_toggle = _make_button(
			"InspectionLibraryToggle",
			"‹" if _inspection_library_expanded else "›",
			Vector2(0.0, (_inspection_overlay.size.y - 64.0) * 0.5),
			Vector2(28.0, 64.0),
			false
		)
		_inspection_library_toggle.z_index = 60
		_inspection_library_toggle.tooltip_text = "展开纹章与伤势工具箱" if not _inspection_library_expanded else "收起纹章与伤势工具箱"
		_inspection_library_toggle.pressed.connect(_toggle_inspection_library)
		_inspection_overlay.add_child(_inspection_library_toggle)

	_inspection_carry_layer = Control.new()
	_inspection_carry_layer.name = "InspectionCarryLayer"
	_inspection_carry_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspection_carry_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspection_carry_layer.z_index = 40
	_inspection_overlay.add_child(_inspection_carry_layer)
	_inspection_display_mode_button = _make_button(
		"InspectionDisplayModeButton",
		"显示描述",
		INSPECTION_DISPLAY_BUTTON_POSITION,
		Vector2(140, 28),
		false
	)
	_inspection_display_mode_button.z_index = 80
	_inspection_display_mode_button.pressed.connect(_toggle_inspection_display_mode)
	_inspection_overlay.add_child(_inspection_display_mode_button)
	_inspection_overlay.move_child(
		_inspection_display_mode_button,
		_inspection_overlay.get_child_count() - 1
	)
	_set_inspection_pattern_labels_suppressed(true)
	if current_phase == GamePhase.BATTLE and is_instance_valid(battle_effect_layer):
		battle_effect_layer.visible = false

	if current_phase == GamePhase.BATTLE:
		_sync_battle_pause_owners()
	else:
		get_tree().paused = _inspection_previous_tree_paused
		_update_battle_pause_button()
	_refresh_drag_availability()


func _toggle_inspection_display_mode() -> void:
	if not is_instance_valid(_inspection_card_view):
		return
	_inspection_card_view.toggle_effect_display()
	if is_instance_valid(_inspection_display_mode_button):
		_inspection_display_mode_button.text = (
			"显示符文" if _inspection_card_view.showing_effect else "显示描述"
		)


func _finish_inspection_library_open() -> void:
	if _inspection_closing or not is_instance_valid(emblem_library):
		return
	emblem_library.set_drag_enabled(current_phase == GamePhase.PREPARE)


func _inspection_library_position(expanded: bool) -> Vector2:
	if not is_instance_valid(emblem_library) or not is_instance_valid(_inspection_overlay):
		return Vector2.ZERO
	var toolbox_x: float = 32.0 if expanded else INSPECTION_LIBRARY_REVEAL - emblem_library.size.x * INSPECTION_LIBRARY_SCALE
	var toolbox_y: float = (_inspection_overlay.size.y - emblem_library.size.y * INSPECTION_LIBRARY_SCALE) * 0.5
	return Vector2(toolbox_x, toolbox_y)


func _inspection_card_position(expanded: bool, card_scale: Vector2 = Vector2.ZERO) -> Vector2:
	if not is_instance_valid(_inspection_surface) or not is_instance_valid(_inspection_overlay):
		return Vector2.ZERO
	var layout_scale := _inspection_surface.scale if card_scale == Vector2.ZERO else card_scale
	var centered: Vector2 = (_inspection_overlay.size - _inspection_surface.size * layout_scale) * 0.5
	if not expanded or not is_instance_valid(emblem_library):
		return centered
	# 只按卡面真实可见框留位；合成表面的透明内边距可以压到工具箱上方。
	var visible_card_left: float = 32.0 + emblem_library.size.x * INSPECTION_LIBRARY_SCALE + INSPECTION_LIBRARY_GAP
	return Vector2(visible_card_left - _inspection_surface.PADDING.x * layout_scale.x, centered.y)


func _toggle_inspection_library() -> void:
	if _inspection_closing or not _inspection_has_library_toolbox or not is_instance_valid(emblem_library) or not is_instance_valid(_inspection_surface):
		return
	_finish_rune_scraper_mode()
	_inspection_library_expanded = not _inspection_library_expanded
	if is_instance_valid(_inspection_tween) and _inspection_tween.is_running():
		_inspection_tween.kill()
	_inspection_tween = _inspection_overlay.create_tween().set_parallel(true)
	_inspection_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_inspection_tween.tween_property(emblem_library, "position", _inspection_library_position(_inspection_library_expanded), INSPECTION_LIBRARY_TOGGLE_DURATION)
	_inspection_tween.tween_property(_inspection_surface, "position", _inspection_card_position(_inspection_library_expanded), INSPECTION_LIBRARY_TOGGLE_DURATION)
	_inspection_tween.chain().tween_callback(_finish_inspection_library_open)
	if is_instance_valid(_inspection_library_toggle):
		_inspection_library_toggle.text = "‹" if _inspection_library_expanded else "›"
		_inspection_library_toggle.tooltip_text = "收起纹章与伤势工具箱" if _inspection_library_expanded else "展开纹章与伤势工具箱"


func _set_control_transform_from_canvas(
	control: Control,
	parent: Control,
	canvas_transform: Transform2D
) -> void:
	var local_transform: Transform2D = (
		parent.get_global_transform_with_canvas().affine_inverse()
		* canvas_transform
	)
	control.position = local_transform.origin
	control.rotation = local_transform.get_rotation()
	control.scale = local_transform.get_scale()


func _on_inspection_dim_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_close_card_inspection()
		get_viewport().set_input_as_handled()


func _close_card_inspection(immediate: bool = false) -> void:
	if not is_instance_valid(_inspection_overlay) or _inspection_closing or (_shop_pack_opening and not immediate):
		return
	_finish_rune_scraper_mode()
	_inspection_closing = true
	if _inspection_source_view is ShopCardView and _inspection_card_view is ShopCardView:
		_inspection_card_view._carousel_timer.paused = true
		_inspection_source_view.continue_carousel_from(_inspection_card_view)
	if _inspection_has_library_toolbox:
		_last_minion_inspection_library_expanded = _inspection_library_expanded
	_finish_inspection_placement_animation()
	if not _click_carry_data.is_empty():
		_cancel_click_carry()
	if is_instance_valid(_inspection_tween) and _inspection_tween.is_running():
		_inspection_tween.kill()
	if is_instance_valid(_inspection_surface):
		_inspection_surface.clear_drop_preview()
		_inspection_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_inspection_dim):
		_inspection_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if _inspection_has_library_toolbox and is_instance_valid(emblem_library):
		emblem_library.set_drag_enabled(false)
	if immediate:
		_finish_card_inspection_close()
		return
	if not is_instance_valid(_inspection_surface):
		_finish_card_inspection_close()
		return
	var target_position := _inspection_surface.position
	var target_scale := Vector2.ONE
	var target_rotation := 0.0
	if is_instance_valid(_inspection_source_view):
		var source_transform: Transform2D = (
			_inspection_overlay.get_global_transform_with_canvas().affine_inverse()
			* _inspection_source_view.get_global_transform_with_canvas()
		)
		target_scale = source_transform.get_scale()
		target_rotation = source_transform.get_rotation()
		target_position = source_transform.origin - source_transform.basis_xform(_inspection_surface.PADDING)
	else:
		var current_center := _inspection_surface.position + _inspection_surface.size * _inspection_surface.scale * 0.5
		target_position = current_center - _inspection_surface.size * target_scale * 0.5
	_inspection_tween = _inspection_overlay.create_tween().set_parallel(true)
	_inspection_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_inspection_tween.tween_property(_inspection_surface, "position", target_position, 0.2)
	_inspection_tween.tween_property(_inspection_surface, "scale", target_scale, 0.2)
	_inspection_tween.tween_property(_inspection_surface, "rotation", target_rotation, 0.2)
	var pack_name := _inspection_overlay.get_node_or_null("InspectionPackName") as Label
	if pack_name != null:
		_inspection_tween.tween_property(pack_name, "modulate:a", 0.0, 0.2)
	var original_local_transform := Transform2D.IDENTITY
	if is_instance_valid(emblem_library) and emblem_library.get_parent() == _inspection_overlay and _inspection_library_transform_saved:
		original_local_transform = (
			(_inspection_overlay as Control).get_global_transform_with_canvas().affine_inverse()
			* _inspection_library_original_canvas_transform
		)
		_inspection_tween.tween_property(
			emblem_library,
			"position",
			original_local_transform.origin,
			0.2
		)
	if is_instance_valid(emblem_library) and emblem_library.get_parent() == _inspection_overlay:
		_inspection_tween.tween_property(
			emblem_library,
			"scale",
			original_local_transform.get_scale(),
			0.2
		)
		_inspection_tween.tween_property(
			emblem_library,
			"rotation",
			original_local_transform.get_rotation(),
			0.2
		)
	if is_instance_valid(_inspection_dim):
		_inspection_tween.tween_property(_inspection_dim, "modulate:a", 0.0, 0.2)
	_inspection_tween.finished.connect(_finish_card_inspection_close)


func _finish_card_inspection_close() -> void:
	if not is_instance_valid(_inspection_overlay):
		return
	if is_instance_valid(_inspection_source_view):
		_set_inspection_source_statistics_suppressed(false)
		_inspection_source_view.visible = true
	_inspection_source_view = null
	_shop_pack_opening = false
	if is_instance_valid(_inspection_card_view):
		_inspection_card_view.set_emblem_drop_handler(Callable())
	if emblem_library != null and emblem_library.get_parent() == _inspection_overlay:
		_inspection_overlay.remove_child(emblem_library)
		var restore_parent := _inspection_library_original_parent if _inspection_library_original_parent != null else _emblem_library_parent
		if restore_parent != null:
			restore_parent.add_child(emblem_library)
		emblem_library.set_inspect_mode(false)
		if _inspection_library_transform_saved:
			emblem_library.position = _inspection_library_original_layout.get("position", TOOLBOX_POSITION)
			emblem_library.size = _inspection_library_original_layout.get("size", Vector2(124, 280))
			emblem_library.scale = _inspection_library_original_layout.get("scale", Vector2.ONE)
			emblem_library.rotation = _inspection_library_original_layout.get("rotation", 0.0)
			emblem_library.pivot_offset = _inspection_library_original_layout.get("pivot_offset", Vector2.ZERO)
			emblem_library.custom_minimum_size = _inspection_library_original_layout.get(
				"custom_minimum_size",
				Vector2(124, 280)
			)
			emblem_library.set_scroll_position(_inspection_library_original_scroll)
			emblem_library.z_index = _inspection_library_original_z_index
		else:
			emblem_library.position = TOOLBOX_POSITION
			emblem_library.z_index = -48
		emblem_library.set_drag_enabled(false)
	_inspection_pause_requested = false
	if current_phase == GamePhase.BATTLE:
		_sync_battle_pause_owners()
	else:
		get_tree().paused = _inspection_previous_tree_paused
		_update_battle_pause_button()
	if is_instance_valid(battle_effect_layer):
		battle_effect_layer.visible = _inspection_effect_layer_was_visible
	_inspection_overlay.queue_free()
	_inspection_overlay = null
	_inspection_carry_layer = null
	_set_inspection_pattern_labels_suppressed(false)
	_inspection_card_view = null
	_inspection_surface = null
	_inspection_owned_card = null
	_inspection_card_data = null
	_inspection_dim = null
	_inspection_display_mode_button = null
	_inspection_library_toggle = null
	_inspection_library_expanded = false
	_inspection_has_library_toolbox = false
	_inspection_read_only = false
	_inspection_library_original_parent = null
	_inspection_library_original_layout.clear()
	_inspection_library_transform_saved = false
	_inspection_tween = null
	_inspection_closing = false
	_refresh_drag_availability()


func _cancel_inspection_carry_from_overlay() -> bool:
	if _rune_scraper_mode:
		_finish_rune_scraper_mode()
		return true
	if _click_carry_data.is_empty():
		return false
	_cancel_click_carry()
	return true


func _handle_inspection_emblem_drop(
	action: StringName,
	card_view: CardView,
	at_position: Vector2,
	data: Variant
) -> Variant:
	if action == &"can_drop":
		return _can_drop_emblem_on_inspection_card(card_view, at_position, data)
	if action == &"drop":
		return _drop_emblem_on_inspection_card(card_view, at_position, data)
	if action == &"animate_drop":
		return _animate_inspection_item_drop(card_view, at_position, data)
	if action == &"get_preview":
		return _get_inspection_drop_preview(card_view, at_position, data)
	return false


func _can_drop_emblem_on_inspection_card(
	card_view: CardView,
	at_position: Vector2,
	data: Variant
) -> bool:
	return not _resolve_inspection_drop_target(card_view, at_position, data).is_empty()


func _resolve_inspection_drop_target(
	card_view: CardView,
	at_position: Vector2,
	data: Variant
) -> Dictionary:
	if (
		_inspection_read_only
		or
		_inspection_placement_in_progress
		or current_phase != GamePhase.PREPARE
		or card_view != _inspection_card_view
		or _inspection_owned_card == null
		or not _inspection_owned_card.is_valid()
		or _inspection_card_data == null
		or not data is Dictionary
	):
		return {}
	var drag_data := data as Dictionary
	if _inspection_card_data.card_type != CardData.CardType.MINION:
		return {}
	if drag_data.get("kind") != &"emblem_library":
		return {}
	var definition := drag_data.get("definition", {}) as Dictionary
	if not definition.has("returned_state"):
		return {}
	var returned_state := definition.get("returned_state", {}) as Dictionary
	var instance_id := StringName(String(returned_state.get("instance_id", "")))
	var inventory_state: Dictionary = emblem_library.get_inventory_item(instance_id)
	if instance_id.is_empty() or inventory_state.is_empty():
		return {}
	var is_wound := String(inventory_state.get("kind", "emblem")) == "wound"
	var item_id := StringName(String(inventory_state.get("wound_id", "") if is_wound else inventory_state.get("emblem_id", "")))
	if (
		item_id.is_empty()
		or String(definition.get("status_kind", "emblem")) != ("wound" if is_wound else "emblem")
		or StringName(String(definition.get("id", ""))) != item_id
		or StringName(String(drag_data.get("wound_id", "") if is_wound else drag_data.get("emblem_id", ""))) != item_id
	):
		return {}
	if _sticker_instance_is_attached(instance_id):
		return {}
	if is_wound:
		var wound_slot := _find_empty_wound_slot_at(at_position)
		return {"kind": "wound", "slot_index": wound_slot, "id": item_id, "definition": definition, "inventory_state": inventory_state} if wound_slot >= 0 else {}
	var emblem_id := item_id
	if StringName(String(inventory_state.get("emblem_id", ""))) != emblem_id:
		return {}
	if emblem_id == &"万能贴纸" and _has_universal_sticker_on_owned_cards():
		return {}
	if definition.get("target", "emblem") == "rune":
		var rune_index := _inspection_rune_at(at_position)
		if rune_index < 0 or (
			rune_index < _inspection_owned_card.rune_stickers.size()
			and not _inspection_owned_card.rune_stickers[rune_index].is_empty()
		):
			return {}
		return {"kind": "rune", "rune_index": rune_index, "id": emblem_id, "definition": definition, "inventory_state": inventory_state}
	var emblem_slot := _find_empty_emblem_slot_at(at_position)
	return {"kind": "emblem", "slot_index": emblem_slot, "id": emblem_id, "definition": definition, "inventory_state": inventory_state} if emblem_slot >= 0 else {}


func _drop_emblem_on_inspection_card(
	card_view: CardView,
	at_position: Vector2,
	data: Variant,
	defer_visual_handoff: bool = false,
	resolved_target: Dictionary = {}
) -> bool:
	var target := resolved_target
	if target.is_empty():
		target = _resolve_inspection_drop_target(card_view, at_position, data)
	if target.is_empty() or not data is Dictionary:
		return false
	var drag_data := data as Dictionary
	var is_wound: bool = target.kind == "wound"
	var emblem_id := target.id as StringName
	var definition := target.definition as Dictionary
	var state := (target.inventory_state as Dictionary).duplicate(true)
	var instance_id := StringName(String(state.get("instance_id", "")))
	if instance_id.is_empty():
		return false
	var placed := false
	if is_wound:
		state["wound_id"] = StringName(String(state.get("wound_id", emblem_id)))
		placed = _inspection_owned_card.set_wound_slot(target.slot_index, state)
	elif target.kind == "rune":
		state["emblem_id"] = StringName(String(state.get("emblem_id", emblem_id)))
		var elements := {"火贴纸": 0, "水贴纸": 1, "木贴纸": 2, "光贴纸": 3, "暗贴纸": 4}
		if emblem_id == &"混沌贴纸":
			state["element"] = randi_range(0, 4)
		elif not state.has("element"):
			state["element"] = elements.get(String(emblem_id), 0)
		placed = _inspection_owned_card.set_rune_sticker(target.rune_index, state)
	else:
		state["emblem_id"] = StringName(String(state.get("emblem_id", emblem_id)))
		placed = _inspection_owned_card.set_emblem_slot(target.slot_index, state)
		if state.has("saved_progress"):
			_inspection_owned_card.progress_by_source[state.instance_id] = state.saved_progress
	if not placed:
		return false
	if not emblem_library.consume_returned(state):
		if is_wound:
			_inspection_owned_card.set_wound_slot(target.slot_index, {})
		elif target.kind == "rune":
			_inspection_owned_card.set_rune_sticker(target.rune_index, {})
		else:
			_inspection_owned_card.set_emblem_slot(target.slot_index, {})
		if state.has("saved_progress"):
			_inspection_owned_card.progress_by_source.erase(instance_id)
		return false
	if not defer_visual_handoff:
		_refresh_owned_card_status_visuals(_inspection_owned_card)
		_refresh_inspection_markers()
		play_area_label.text = "已将%s贴到%s的%s" % [String(emblem_id), _inspection_card_data.display_name, "伤势槽" if is_wound else ("符文槽" if target.kind == "rune" else "纹章槽")]
	return true


func _animate_inspection_item_drop(
	card_view: CardView,
	at_position: Vector2,
	data: Variant
) -> bool:
	if _inspection_placement_in_progress or not data is Dictionary:
		return false
	var drag_data := data as Dictionary
	var target := _resolve_inspection_drop_target(card_view, at_position, drag_data)
	if target.is_empty():
		return false
	var landing := _get_inspection_drop_preview(card_view, at_position, drag_data, target)
	var texture := landing.get("texture") as Texture2D
	if texture == null or not is_instance_valid(_inspection_carry_layer):
		return false
	var start_corners := _get_inspection_carry_corners(drag_data)
	if start_corners.size() != 4:
		return false
	var target_position := landing.get("position", Vector2.ZERO) as Vector2
	var target_size := landing.get("size", Vector2.ZERO) as Vector2
	var target_corners := PackedVector2Array([
		target_position,
		target_position + Vector2(target_size.x, 0.0),
		target_position + target_size,
		target_position + Vector2(0.0, target_size.y),
	])
	var animated_visual := Polygon2D.new()
	animated_visual.name = "InspectionStickerFlight"
	animated_visual.polygon = PackedVector2Array(start_corners)
	animated_visual.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(texture.get_width(), 0.0),
		Vector2(texture.get_size()),
		Vector2(0.0, texture.get_height()),
	])
	animated_visual.texture = texture
	animated_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated_visual.z_index = 200
	_inspection_card_view.add_child(animated_visual)
	var definition := target.get("definition", {}) as Dictionary
	if not _drop_emblem_on_inspection_card(card_view, at_position, drag_data, true, target):
		animated_visual.queue_free()
		return false
	_inspection_placement_visual = animated_visual
	_inspection_placement_in_progress = true
	_inspection_placement_tween = create_tween()
	_inspection_placement_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_inspection_placement_tween.tween_property(
		animated_visual,
		"polygon",
		target_corners,
		INSPECTION_STICKER_FLIGHT_DURATION
	)
	_inspection_placement_tween.finished.connect(_finish_inspection_placement_animation)
	return true


func _get_inspection_carry_corners(data: Dictionary) -> PackedVector2Array:
	var screen_corners := PackedVector2Array()
	var drag_visual := data.get("drag_visual") as Control
	if is_instance_valid(drag_visual) and not drag_visual.is_queued_for_deletion():
		var transform := drag_visual.get_global_transform_with_canvas()
		var visual_size := drag_visual.size
		screen_corners = PackedVector2Array([
			transform * Vector2.ZERO,
			transform * Vector2(visual_size.x, 0.0),
			transform * visual_size,
			transform * Vector2(0.0, visual_size.y),
		])
	else:
		var pointer := get_viewport().get_mouse_position()
		var preview_size := data.get("preview_size", Vector2(14, 14)) as Vector2
		var preview_scale := data.get("preview_scale", Vector2.ONE) as Vector2
		var preview_offset := data.get("preview_offset", Vector2.ZERO) as Vector2
		var top_left := pointer + preview_offset
		preview_size *= preview_scale
		screen_corners = PackedVector2Array([
			top_left,
			top_left + Vector2(preview_size.x, 0.0),
			top_left + preview_size,
			top_left + Vector2(0.0, preview_size.y),
		])
	var result := PackedVector2Array()
	var surface_inverse := _inspection_surface.get_global_transform_with_canvas().affine_inverse()
	for screen_point: Vector2 in screen_corners:
		result.append(_inspection_surface.card_point(surface_inverse * screen_point))
	return result


func _finish_inspection_placement_animation() -> void:
	if is_instance_valid(_inspection_placement_tween) and _inspection_placement_tween.is_running():
		_inspection_placement_tween.kill()
	_inspection_placement_tween = null
	if is_instance_valid(_inspection_placement_visual):
		_inspection_placement_visual.queue_free()
	_inspection_placement_visual = null
	if _inspection_placement_in_progress:
		if is_instance_valid(_inspection_owned_card):
			_refresh_owned_card_status_visuals(_inspection_owned_card)
			_refresh_inspection_markers()
			if is_instance_valid(_inspection_card_data):
				play_area_label.text = "状态已贴到%s" % _inspection_card_data.display_name
		_inspection_placement_in_progress = false


func _inspection_rune_at(point: Vector2) -> int:
	if not is_instance_valid(_inspection_card_view):
		return -1
	for index: int in _inspection_card_data.runes.size():
		var origin := _inspection_card_view.rune_area_position + Vector2(index * (_inspection_card_view.rune_slot_size.x + _inspection_card_view.rune_spacing), 0)
		if Rect2(origin, _inspection_card_view.rune_slot_size).has_point(point):
			return index
	return -1


func _begin_rune_scrape_stroke(pointer: Vector2) -> void:
	_rune_scrape_last_pointer = pointer
	_rune_scrape_sticker_consumed_this_stroke = false
	# 拾起刮刀时不连线；必须先在检视卡面内收到一次移动事件才开始路径。
	_rune_scrape_last_inside_surface = false


func _end_rune_scrape_stroke() -> void:
	_rune_scrape_last_pointer = Vector2.INF
	_rune_scrape_last_inside_surface = false


func _update_rune_scrape_stroke(pointer: Vector2, drag_data: Dictionary) -> void:
	if (
		not _rune_scraper_mode
		or current_phase != GamePhase.PREPARE
		or _inspection_read_only
		or not is_instance_valid(_inspection_surface)
		or _inspection_card_view == null
		or _inspection_owned_card == null
		or _inspection_owned_card.card_data == null
		or _inspection_owned_card.card_data.card_type != CardData.CardType.MINION
	):
		_end_rune_scrape_stroke()
		return
	if not _inspection_surface.get_global_rect().has_point(pointer):
		_rune_scrape_last_pointer = Vector2.INF
		_rune_scrape_last_inside_surface = false
		return
	var start_pointer := pointer
	if _rune_scrape_last_inside_surface and _rune_scrape_last_pointer.is_finite():
		start_pointer = _rune_scrape_last_pointer
	var distance := start_pointer.distance_to(pointer)
	var steps := maxi(ceili(distance / RuneRevealCoverStyleScript.SCRAPE_SAMPLE_SPACING), 1)
	var dirty_rune_slots: Dictionary = {}
	for step: int in range(1, steps + 1):
		var sample := start_pointer.lerp(pointer, float(step) / float(steps))
		if _inspection_surface.get_global_rect().has_point(sample):
			_apply_rune_scrape_sample(sample, drag_data, dirty_rune_slots)
	for rune_index_value: Variant in dirty_rune_slots.keys():
		var rune_index := int(rune_index_value)
		if rune_index < _inspection_owned_card.rune_revealed.size() and not _inspection_owned_card.rune_revealed[rune_index]:
			_inspection_card_view.refresh_rune_scrape_cover(rune_index)
	_rune_scrape_last_pointer = pointer
	_rune_scrape_last_inside_surface = true


func _apply_rune_scrape_sample(
	pointer: Vector2,
	drag_data: Dictionary,
	dirty_rune_slots: Dictionary
) -> void:
	if _rune_scrape_sticker_consumed_this_stroke:
		return
	var blade_polygon := _get_rune_scrape_blade_polygon(pointer, drag_data)
	if blade_polygon.size() < 3:
		return
	var bounds_min := blade_polygon[0]
	var bounds_max := bounds_min
	for vertex: Vector2 in blade_polygon:
		bounds_min = bounds_min.min(vertex)
		bounds_max = bounds_max.max(vertex)
	var blade_bounds := Rect2(bounds_min, bounds_max - bounds_min)
	var card_view := _inspection_card_view
	var owned := _inspection_owned_card
	var removable := _find_removable_sticker(blade_bounds.get_center(), blade_bounds)
	if not removable.is_empty() and scraper_count > 0:
		var removed := false
		match String(removable.get("kind", "")):
			"rune": removed = owned.set_rune_sticker(int(removable.index), {})
			"wound": removed = owned.set_wound_slot(int(removable.index), {})
			"emblem": removed = owned.set_emblem_slot(int(removable.index), {})
		if removed:
			scraper_count -= 1
			emblem_library.set_scraper_count(scraper_count)
			_refresh_owned_card_status_visuals(owned)
			_refresh_inspection_markers()
			play_area_label.text = "已移除一枚贴纸或伤势；底层符文需要下一次独立点击"
			_rune_scrape_sticker_consumed_this_stroke = true
		return
	for rune_index: int in owned.card_data.runes.size():
		if (
			rune_index >= owned.rune_revealed.size()
			or owned.rune_revealed[rune_index]
			or rune_index >= owned.rune_stickers.size()
			or not owned.rune_stickers[rune_index].is_empty()
		):
			continue
		var origin := card_view.rune_area_position + Vector2(
			rune_index * (card_view.rune_slot_size.x + card_view.rune_spacing),
			0
		)
		var slot_rect := Rect2(origin, card_view.rune_slot_size)
		if not blade_bounds.intersects(slot_rect, true):
			continue
		var scraped_pixels: Array[Vector2i] = []
		for y: int in RuneRevealCoverStyleScript.SIZE:
			for x: int in RuneRevealCoverStyleScript.SIZE:
				var pixel := Vector2i(x, y)
				if not RuneRevealCoverStyleScript.is_cover_pixel(pixel):
					continue
				var pixel_center := origin + Vector2(
					(float(x) + 0.5) * card_view.rune_slot_size.x / RuneRevealCoverStyleScript.SIZE,
					(float(y) + 0.5) * card_view.rune_slot_size.y / RuneRevealCoverStyleScript.SIZE
				)
				if (
					Geometry2D.is_point_in_polygon(pixel_center, blade_polygon)
					and not owned.has_rune_scraped_pixel(rune_index, pixel)
				):
					scraped_pixels.append(pixel)
		if scraped_pixels.is_empty():
			continue
		var paid_key := _rune_scraper_paid_key(owned, rune_index)
		var newly_paid := not _rune_scraper_paid_slots.has(paid_key)
		if newly_paid:
			if scraper_count <= 0:
				continue
			# 刀数扣减与首批有效像素在同一次同步调用中提交；若掩码拒收则回滚刀数。
			scraper_count -= 1
			emblem_library.set_scraper_count(scraper_count)
			_rune_scraper_paid_slots[paid_key] = {"owned": owned, "index": rune_index}
		if owned.record_rune_scrape_pixels(rune_index, scraped_pixels) <= 0:
			if newly_paid:
				_rune_scraper_paid_slots.erase(paid_key)
				scraper_count += 1
				emblem_library.set_scraper_count(scraper_count)
			continue
		if RuneRevealCoverStyleScript.is_complete(owned.get_rune_scraped_pixel_count(rune_index)):
			owned.rune_revealed[rune_index] = true
			owned.rune_scrape_masks[rune_index] = ""
			_rune_scraper_paid_slots.erase(paid_key)
			_refresh_owned_card_status_visuals(owned)
			_refresh_inspection_markers()
			play_area_label.text = "已刮开%s的第%d枚符文" % [owned.card_data.display_name, rune_index + 1]
		else:
			dirty_rune_slots[rune_index] = true


func _rune_scraper_paid_key(owned: OwnedCard, rune_index: int) -> String:
	return "%s:%d" % [String(owned.instance_id), rune_index]


func _toggle_rune_scraper_mode() -> void:
	if _rune_scraper_mode:
		_finish_rune_scraper_mode()
		return
	if (
		current_phase != GamePhase.PREPARE
		or _inspection_read_only
		or not is_instance_valid(_inspection_surface)
		or not is_instance_valid(_inspection_card_view)
		or _inspection_owned_card == null
		or not _inspection_owned_card.is_valid()
		or _inspection_card_data == null
		or _inspection_card_data.card_type != CardData.CardType.MINION
		or scraper_count <= 0
		or not _inspection_library_expanded
		or _inspection_closing
		or _is_rune_scraper_input_blocked()
	):
		return
	var scraper: TextureRect = emblem_library._scraper
	if not is_instance_valid(scraper) or scraper.texture == null:
		return
	_rune_scraper_mode = true
	if is_instance_valid(_rune_scraper_return_tween):
		_rune_scraper_return_tween.kill()
	if is_instance_valid(_rune_scraper_visual):
		_rune_scraper_visual.queue_free()
	_rune_scraper_paid_slots.clear()
	_rune_scraper_drag_data = scraper._build_drag_data(scraper.blade_point, false)
	var unused_preview := _rune_scraper_drag_data.get("drag_visual") as Control
	if is_instance_valid(unused_preview):
		unused_preview.free()
	_rune_scraper_drag_data.erase("drag_visual")
	_rune_scrape_button_held = false
	_rune_scraper_visual = TextureRect.new()
	_rune_scraper_visual.name = "HeldRuneScraper"
	_rune_scraper_visual.texture = scraper.texture
	_rune_scraper_visual.size = scraper.size
	_rune_scraper_visual.scale = scraper.get_global_transform_with_canvas().get_scale()
	_rune_scraper_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rune_scraper_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rune_scraper_visual.z_index = 4096
	_rune_scraper_visual.z_as_relative = false
	add_child(_rune_scraper_visual)
	_rune_scraper_visual.global_position = get_global_mouse_position() - scraper.blade_point * _rune_scraper_visual.scale
	emblem_library.set_scraper_carried(true)
	_rune_scraper_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	play_area_label.text = "刮刀已就绪：左键点击或按住移动；右键或 Esc 退出"


func _finish_rune_scraper_mode() -> void:
	if not _rune_scraper_mode and _rune_scraper_paid_slots.is_empty():
		return
	_rune_scraper_mode = false
	_rune_scrape_button_held = false
	_end_rune_scrape_stroke()
	Input.mouse_mode = _rune_scraper_previous_mouse_mode
	_return_rune_scraper_visual()
	for value: Variant in _rune_scraper_paid_slots.values():
		if not value is Dictionary:
			continue
		var payment := value as Dictionary
		var owned := payment.get("owned") as OwnedCard
		var rune_index := int(payment.get("index", -1))
		if (
			owned == null
			or rune_index < 0
			or rune_index >= owned.rune_revealed.size()
			or owned.rune_revealed[rune_index]
		):
			continue
		owned.rune_revealed[rune_index] = true
		owned.rune_scrape_masks[rune_index] = ""
		if owned == _inspection_owned_card and is_instance_valid(_inspection_card_view):
			_refresh_owned_card_status_visuals(owned)
			_refresh_inspection_markers()
			play_area_label.text = "已完成本次付费刮擦；符文已完整揭晓"
	_rune_scraper_paid_slots.clear()
	_rune_scraper_drag_data.clear()


func _return_rune_scraper_visual() -> void:
	if not is_instance_valid(_rune_scraper_visual):
		emblem_library.set_scraper_carried(false)
		return
	var visual := _rune_scraper_visual
	var start := visual.global_position
	var start_scale := visual.scale
	_rune_scraper_return_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_rune_scraper_return_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_rune_scraper_return_tween.tween_method(func(progress: float):
		if is_instance_valid(visual) and is_instance_valid(emblem_library._scraper):
			# 关闭检视时工具箱也在移动，飞回目标实时读取凹槽位置与缩放。
			visual.global_position = start.lerp(emblem_library._scraper.get_global_transform_with_canvas().origin, progress)
			visual.scale = start_scale.lerp(emblem_library._scraper.get_global_transform_with_canvas().get_scale(), progress)
	, 0.0, 1.0, SCRAPER_RETURN_DURATION)
	_rune_scraper_return_tween.tween_callback(func():
		if is_instance_valid(visual):
			visual.queue_free()
		if _rune_scraper_visual == visual:
			_rune_scraper_visual = null
			emblem_library.set_scraper_carried(false)
	)


func _is_rune_scraper_input_blocked() -> bool:
	return (
		(_developer_console != null and _developer_console.visible)
		or _escape_menu_pause_requested
		or (_escape_pause_menu != null and _escape_pause_menu.is_menu_open())
		or get_tree().paused
		or _inspection_read_only
		or _inspection_closing
		or not is_instance_valid(_inspection_overlay)
	)


func _get_rune_scrape_blade_polygon(
	pointer_global: Vector2,
	drag_data: Dictionary
) -> PackedVector2Array:
	var surface := _inspection_surface
	var surface_scale := surface.get_global_transform_with_canvas().get_scale()
	if is_zero_approx(surface_scale.x) or is_zero_approx(surface_scale.y):
		return PackedVector2Array()
	var surface_pointer := surface.get_global_transform_with_canvas().affine_inverse() * pointer_global
	var offset := (drag_data.get("hit_rect_offset", Vector2.ZERO) as Vector2) / surface_scale
	var hit_size := (drag_data.get("hit_rect_size", Vector2.ZERO) as Vector2) / surface_scale
	var corners := PackedVector2Array([
		surface.card_point(surface_pointer + offset),
		surface.card_point(surface_pointer + offset + Vector2(hit_size.x, 0.0)),
		surface.card_point(surface_pointer + offset + hit_size),
		surface.card_point(surface_pointer + offset + Vector2(0.0, hit_size.y)),
	])
	return corners


func _find_removable_sticker(point: Vector2, hit_rect: Rect2 = Rect2()) -> Dictionary:
	if hit_rect.has_area():
		for rune_index: int in _inspection_owned_card.rune_stickers.size():
			var rune_origin := _inspection_card_view.rune_area_position + Vector2(rune_index * (_inspection_card_view.rune_slot_size.x + _inspection_card_view.rune_spacing), 0)
			if not _inspection_owned_card.rune_stickers[rune_index].is_empty() and Rect2(rune_origin - Vector2(2, 2), Vector2(27, 27)).intersects(hit_rect, true):
				return {"kind": "rune", "index": rune_index}
		for slot: Dictionary in CardSlotLayout.get_slot_definitions(_inspection_card_data, _inspection_owned_card):
			var index := int(slot.storage_index)
			var wound := int(slot.kind) == CardSlotLayout.Kind.WOUND
			var states: Array[Dictionary] = _inspection_owned_card.wound_slots if wound else _inspection_owned_card.emblem_slots
			if index >= states.size() or states[index].is_empty():
				continue
			if Rect2(slot.position as Vector2, Vector2(14, 14)).intersects(hit_rect, true):
				return {"kind": "wound" if wound else "emblem", "index": index}
		return {}
	var rune_index := _inspection_rune_at(point)
	if rune_index >= 0 and rune_index < _inspection_owned_card.rune_stickers.size():
		var rune_origin := _inspection_card_view.rune_area_position + Vector2(rune_index * (_inspection_card_view.rune_slot_size.x + _inspection_card_view.rune_spacing), 0)
		var rune_rect := Rect2(rune_origin - Vector2(2, 2), Vector2(27, 27))
		if _hit_rect_matches(rune_rect, point, hit_rect):
			if not _inspection_owned_card.rune_stickers[rune_index].is_empty():
				return {"kind": "rune", "index": rune_index}
	for slot: Dictionary in CardSlotLayout.get_slot_definitions(_inspection_card_data, _inspection_owned_card):
		var index := int(slot.storage_index)
		var slot_rect := Rect2(slot.position as Vector2, Vector2(14, 14))
		var wound := int(slot.kind) == CardSlotLayout.Kind.WOUND
		var states: Array[Dictionary] = _inspection_owned_card.wound_slots if wound else _inspection_owned_card.emblem_slots
		if index < states.size() and not states[index].is_empty() and _hit_rect_matches(slot_rect, point, hit_rect):
			return {"kind": "wound" if wound else "emblem", "index": index}
	return {}


func _hit_rect_matches(target_rect: Rect2, point: Vector2, hit_rect: Rect2) -> bool:
	if hit_rect.has_area():
		return target_rect.intersects(hit_rect, true)
	return target_rect.has_point(point)


func _get_inspection_drop_preview(
	card_view: CardView,
	point: Vector2,
	data: Variant,
	resolved_target: Dictionary = {}
) -> Dictionary:
	var target := resolved_target
	if target.is_empty():
		target = _resolve_inspection_drop_target(card_view, point, data)
	if target.is_empty() or not data is Dictionary:
		return {}
	var emblem_id := target.id as StringName
	if target.kind == "wound":
		var wound_rect := _get_status_slot_rect(target.slot_index, CardSlotLayout.Kind.WOUND)
		return {"texture": StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.WOUND, emblem_id), "position": wound_rect.position, "size": wound_rect.size}
	if target.kind == "rune":
		var rune_index: int = target.rune_index
		var rune_origin := _inspection_card_view.rune_area_position + Vector2(rune_index * (_inspection_card_view.rune_slot_size.x + _inspection_card_view.rune_spacing), 0)
		return {"texture": RuneStickerStyle.get_texture_by_id(emblem_id), "position": rune_origin + (_inspection_card_view.rune_slot_size - Vector2(27, 27)) * 0.5, "size": Vector2(27, 27)}
	var slot_rect := _get_emblem_slot_rect(target.slot_index)
	return {"texture": StatusIndicatorStyle.get_texture(CardSlotLayout.Kind.EMBLEM, emblem_id), "position": slot_rect.position, "size": slot_rect.size}


func _get_emblem_slot_rect(storage_index: int) -> Rect2:
	return _get_status_slot_rect(storage_index, CardSlotLayout.Kind.EMBLEM)


func _get_status_slot_rect(storage_index: int, kind: int) -> Rect2:
	for slot: Dictionary in CardSlotLayout.get_slot_definitions(_inspection_card_data, _inspection_owned_card):
		if int(slot.kind) == kind and int(slot.storage_index) == storage_index:
			return Rect2(slot.position as Vector2, Vector2(14, 14))
	return Rect2()


func _inspection_sticker_tooltip(point: Vector2) -> String:
	return _inspection_card_view.get_sticker_tooltip(point) if is_instance_valid(_inspection_card_view) else ""


func _find_empty_emblem_slot_at(at_position: Vector2) -> int:
	if _inspection_card_data == null or _inspection_owned_card == null:
		return -1
	for definition: Dictionary in CardSlotLayout.get_slot_definitions(_inspection_card_data, _inspection_owned_card):
		if int(definition["kind"]) != CardSlotLayout.Kind.EMBLEM:
			continue
		var storage_index := int(definition["storage_index"])
		if storage_index < 0 or storage_index >= _inspection_owned_card.emblem_slots.size():
			continue
		if not (_inspection_owned_card.emblem_slots[storage_index] as Dictionary).is_empty():
			continue
		var slot_rect := Rect2(definition["position"] as Vector2, Vector2(14, 14))
		if slot_rect.has_point(at_position):
			return storage_index
	return -1


func _find_empty_wound_slot_at(at_position: Vector2) -> int:
	if _inspection_card_data == null or _inspection_owned_card == null:
		return -1
	for definition: Dictionary in CardSlotLayout.get_slot_definitions(_inspection_card_data, _inspection_owned_card):
		if int(definition["kind"]) != CardSlotLayout.Kind.WOUND:
			continue
		var storage_index := int(definition["storage_index"])
		if storage_index >= _inspection_owned_card.wound_slots.size() or not _inspection_owned_card.wound_slots[storage_index].is_empty():
			continue
		if Rect2(definition["position"] as Vector2, Vector2(14, 14)).has_point(at_position):
			return storage_index
	return -1


func _refresh_inspection_markers() -> void:
	if not is_instance_valid(_inspection_card_view) or _inspection_card_data == null or _inspection_owned_card == null:
		return
	var inspection_squad := SquadData.from_owned_card(_inspection_owned_card)
	for row: BattlefieldRow in [front_row, back_row, enemy_front_row, enemy_back_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad != null and squad.get_owned_card(_inspection_card_data) == _inspection_owned_card:
				inspection_squad = squad
	var pattern := inspection_squad.get_rune_pattern_result()
	var visible_slots := inspection_squad.get_visible_rune_slots()
	var highlighted: Array[int] = []
	for index: int in pattern.participating_indices:
		if visible_slots[index].card == _inspection_card_data:
			highlighted.append(int(visible_slots[index].rune_index))
	_inspection_card_view.set_rune_pattern_highlights(highlighted)


func _refresh_owned_card_status_visuals(owned_card: OwnedCard) -> void:
	if owned_card == null:
		return
	var attached_squad := _find_squad_for_owned_card(owned_card)
	if is_instance_valid(_inspection_card_view) and _inspection_owned_card == owned_card:
		_inspection_card_view.set_owned_card(owned_card)
		if attached_squad != null:
			_inspection_card_view.set_squad_attribute_preview_from_squad(attached_squad)
	for slot: Control in _get_collection_card_slots():
		if slot.get_meta("owned_card", null) != owned_card:
			continue
		if slot.get_child_count() > 0:
			(slot.get_child(0) as CardView).set_owned_card(owned_card)
	for row: BattlefieldRow in [front_row, back_row, enemy_back_row, enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			for card_data: CardData in squad.horizontal_cards:
				if squad.get_owned_card(card_data) == owned_card:
					var view := slot.get_card_view(card_data)
					if view != null:
						view.set_owned_card(owned_card)
						view.set_squad_attribute_preview_from_squad(squad)
	_refresh_preparation_effect_preview()


func _find_squad_for_owned_card(owned_card: OwnedCard) -> SquadData:
	if owned_card == null:
		return null
	for row: BattlefieldRow in [front_row, back_row, enemy_back_row, enemy_front_row]:
		for slot: BoardSlot in row.get_squads():
			var squad := slot.get_squad_data()
			if squad == null:
				continue
			for card_data: CardData in squad.horizontal_cards:
				if squad.get_owned_card(card_data) == owned_card:
					return squad
	return null


func _find_battle_state_for_squad(squad: SquadData) -> BattleSquadState:
	if squad == null or current_phase != GamePhase.BATTLE or battle_controller == null:
		return null
	for state: BattleSquadState in battle_controller.get_all_states():
		if state.squad_data == squad:
			return state
	return null


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
	if drag_data.get("kind") == &"celestial_indicator":
		celestial_indicators.begin_click_carry(drag_data, pointer_global_position)
		return
	if (
		current_phase != GamePhase.PREPARE
		or not _click_carry_data.is_empty()
		or (not _is_card_drag_data(drag_data) and not _is_inspection_item_drag(drag_data))
	):
		return
	if _is_inspection_item_drag(drag_data):
		_click_carry_data = drag_data.duplicate()
		_click_carry_preview = _create_click_carry_preview(
			_click_carry_data,
			pointer_global_position
		)
		_click_carry_data["drag_visual"] = _click_carry_preview
		_update_click_carry(pointer_global_position)
		return

	# 点击携带不会触发 Godot 的原生 DRAG_BEGIN；在这里主动完成与
	# 原生拖拽相同的战场悬停清理，避免上一张卡保持鼠标指向状态。
	for row: BattlefieldRow in [front_row, back_row]:
		row.reset_all_hover_feedback()
	_click_carry_data = drag_data.duplicate()
	_set_resource_trays_carry_active(true)
	_click_carry_preview = _create_click_carry_preview(
		_click_carry_data,
		pointer_global_position
	)
	_click_carry_data["drag_visual"] = _click_carry_preview
	if _click_carry_data.get("source_type") == &"resource_preparation":
		var resource_owned := _click_carry_data.get("owned_card") as OwnedCard
		if resource_owned != null:
			_click_carry_preview.set_resource_puzzle_mode(true, resource_owned.resource_shape, int(resource_owned.card_data.rarity), _click_carry_data.get("resource_grab_cell", Vector2i.ZERO), _click_carry_data.get("resource_grab_pixel_offset", Vector2.ZERO), int(resource_owned.card_data.resource_type))
	_ghost_click_carry_source()
	_update_click_carry(pointer_global_position)


func _create_click_carry_preview(
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> Control:
	if _is_inspection_item_drag(drag_data):
		var preview := drag_data.get("drag_visual") as Control
		assert(is_instance_valid(preview), "纹章库物件与刮刀必须提供统一携带预览")
		preview.name = "InspectionItemCarryPreview"
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.modulate.a = 0.9
		var preview_layer: Control = (
			_inspection_carry_layer
			if is_instance_valid(_inspection_carry_layer)
			else _click_carry_layer
		)
		if preview.get_parent() != null:
			preview.get_parent().remove_child(preview)
		preview_layer.add_child(preview)
		_position_inspection_item_preview(preview, drag_data, pointer_global_position)
		return preview
	var preview_root := CardView.create_drag_visual(drag_data)
	add_child(preview_root)
	preview_root.global_position = pointer_global_position
	if drag_data.get("kind") == &"equipment_indicator":
		preview_root.set_equipment_indicator_mode(true, false)
		preview_root.continue_equipment_pickup(
			drag_data.get("indicator_lifted_grab_local_position", drag_data.get("indicator_grab_local_position", EquipmentIndicatorStyle.DISPLAY_SIZE * 0.5))
		)
	return preview_root


func _ghost_click_carry_source() -> void:
	assert(_is_card_drag_data(_click_carry_data), "只有卡牌来源能进入卡牌虚化与来源恢复")
	var source_type := _click_carry_data.get("source_type") as StringName
	if source_type == &"collection":
		var source_slot := _click_carry_data.get("source_slot") as Control
		if (
			is_instance_valid(source_slot)
			and source_slot.get_parent() == collection_card_row
		):
			source_slot.modulate.a = CardView.COLLECTION_DRAG_GHOST_ALPHA
	elif source_type == &"spell_preparation":
		var source_slot := _click_carry_data.get("source_slot") as Control
		if is_instance_valid(source_slot):
			source_slot.modulate.a = 0.0
	elif source_type == &"resource_preparation":
		var tray := _click_carry_data.get("source_tray") as ResourcePreparationTray
		if is_instance_valid(tray): tray.begin_carry(StringName(String(_click_carry_data.get("owned_card").instance_id)))
	elif source_type == &"board":
		var source_row := (
			_click_carry_data.get("source_row") as BattlefieldRow
		)
		if is_instance_valid(source_row):
			source_row._begin_card_drag(_click_carry_data)
		if _click_carry_data.get("kind") == &"equipment_indicator":
			var source_slot := _click_carry_data.get("source_slot") as BoardSlot
			if is_instance_valid(source_slot):
				var indicator := source_slot.get_equipment_indicator()
				if is_instance_valid(indicator):
					indicator.visible = false


func _update_click_carry(pointer_global_position: Vector2) -> void:
	if not _battle_performance_trace_enabled:
		_update_click_carry_impl(pointer_global_position)
		return
	var profile_started_usec := Time.get_ticks_usec()
	_update_click_carry_impl(pointer_global_position)
	_battle_trace_drag_preview_usec += Time.get_ticks_usec() - profile_started_usec


func _update_click_carry_impl(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return

	if _is_inspection_item_drag(_click_carry_data):
		if is_instance_valid(_click_carry_preview):
			_position_inspection_item_preview(
				_click_carry_preview,
				_click_carry_data,
				pointer_global_position
			)
		if is_instance_valid(_inspection_surface):
			var surface_rect := _inspection_surface.get_global_rect()
			if surface_rect.has_point(pointer_global_position):
				_inspection_surface.can_drop_global(pointer_global_position, _click_carry_data)
			else:
				_inspection_surface.clear_drop_preview()
				var definition := _click_carry_data.get("definition", {}) as Dictionary
				var state := definition.get("returned_state", {}) as Dictionary
				if not state.is_empty() and emblem_library.get_global_rect().has_point(pointer_global_position):
					emblem_library.preview_sticker_move_global(
						StringName(String(state.get("instance_id", ""))),
						pointer_global_position,
						_click_carry_data
					)
				else:
					emblem_library.clear_sticker_move_preview()
		else:
			var definition := _click_carry_data.get("definition", {}) as Dictionary
			var state := definition.get("returned_state", {}) as Dictionary
			if not state.is_empty() and emblem_library.get_global_rect().has_point(pointer_global_position):
				emblem_library.preview_sticker_move_global(
					StringName(String(state.get("instance_id", ""))),
					pointer_global_position,
					_click_carry_data
				)
			else:
				emblem_library.clear_sticker_move_preview()
		return

	_update_card_carry_target(pointer_global_position, _click_carry_data)


func _position_inspection_item_preview(
	preview: Control,
	drag_data: Dictionary,
	pointer_global_position: Vector2
) -> void:
	if not is_instance_valid(preview) or not preview.get_parent() is Control:
		return
	var preview_offset := drag_data.get("preview_offset", Vector2.ZERO) as Vector2
	var layer_transform := (preview.get_parent() as Control).get_global_transform_with_canvas()
	preview.position = layer_transform.affine_inverse() * (pointer_global_position + preview_offset)


func _set_inspection_pattern_labels_suppressed(suppressed: bool) -> void:
	for row: BattlefieldRow in [front_row, back_row, enemy_back_row, enemy_front_row]:
		if not is_instance_valid(row):
			continue
		for slot: BoardSlot in row.get_squads():
			slot.set_inspection_pattern_suppressed(suppressed)


func _set_inspection_source_statistics_suppressed(suppressed: bool) -> void:
	if suppressed:
		if not _inspection_statistics_suppression_snapshot.is_empty():
			return
		for row: BattlefieldRow in [front_row, back_row, enemy_back_row, enemy_front_row]:
			if not is_instance_valid(row):
				continue
			for slot: BoardSlot in row.get_squads():
				var node: Node = slot
				while is_instance_valid(node) and not (node is SquadView):
					node = node.get_parent()
				if not is_instance_valid(node):
					continue
				var squad_view := node as SquadView
				if _has_inspection_statistics_snapshot(squad_view):
					continue
				_inspection_statistics_suppression_snapshot.append({
					"view": squad_view,
					"was_suppressed": squad_view.is_battle_result_statistics_suppressed(),
				})
				squad_view.set_battle_result_statistics_suppressed(true)
		return
	for entry: Dictionary in _inspection_statistics_suppression_snapshot:
		var squad_view := entry.get("view") as SquadView
		if is_instance_valid(squad_view):
			squad_view.set_battle_result_statistics_suppressed(bool(entry.get("was_suppressed", false)))
	_inspection_statistics_suppression_snapshot.clear()


func _has_inspection_statistics_snapshot(squad_view: SquadView) -> bool:
	for entry: Dictionary in _inspection_statistics_suppression_snapshot:
		if entry.get("view") == squad_view:
			return true
	return false


func _commit_click_carry(pointer_global_position: Vector2) -> void:
	if _click_carry_data.is_empty():
		return
	if _is_inspection_item_drag(_click_carry_data):
		_update_click_carry(pointer_global_position)
		var committed := false
		if (
			is_instance_valid(_inspection_surface)
			and _inspection_surface.get_global_rect().has_point(pointer_global_position)
		):
			committed = _inspection_surface.drop_global(pointer_global_position, _click_carry_data)
		else:
			var definition := _click_carry_data.get("definition", {}) as Dictionary
			var state := definition.get("returned_state", {}) as Dictionary
			if not state.is_empty():
				committed = emblem_library.try_move_sticker_global(
					StringName(String(state.get("instance_id", ""))),
					pointer_global_position,
					_click_carry_data
				)
		_finish_click_carry(committed)
		get_viewport().set_input_as_handled()
		return

	var target := _update_card_carry_target(
		pointer_global_position,
		_click_carry_data
	)
	var committed := false
	var target_row := target.get("row") as BattlefieldRow
	var resource_tray := target.get("resource_tray") as ResourcePreparationTray
	if resource_tray != null and bool(target.get("accepted", false)):
		committed = _commit_resource_preparation_drop(_click_carry_data, target.get("resource_resolution", {}) as Dictionary)
	elif bool(target.get("spell_preparation", false)):
		if bool(target.get("accepted", false)):
			committed = _on_spell_preparation_drop_requested(
				_click_carry_data,
				int(spell_preparation_tray.call(
					"insertion_index_for_global_position",
					pointer_global_position,
					_click_carry_data
				))
			)
	elif target_row != null:
		var row_position := _to_row_drop_position(
			target_row,
			pointer_global_position
		)
		if bool(target.get("accepted", false)):
			target_row.commit_card_drop(row_position, _click_carry_data)
			committed = true
	elif bool(target.get("collection", false)):
		if bool(target.get("accepted", false)):
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
	_end_rune_scrape_stroke()
	_click_carry_data = {}
	_set_resource_trays_carry_active(false)
	if drag_data.get("source_type") == &"spell_preparation" and is_instance_valid(spell_preparation_tray):
		spell_preparation_tray.end_card_carry()
	var is_inspection_item := _is_inspection_item_drag(drag_data)
	var should_return_failed_indicator: bool = (
		not committed
		and drag_data.get("kind") == &"equipment_indicator"
	)
	if drag_data.get("kind") in [&"equipment_card", &"equipment_indicator"]:
		_set_equipment_drag_visual_mode(drag_data, false)
	var return_global_position: Variant = null
	if (
		not committed
		and is_instance_valid(_click_carry_preview)
	):
		var drag_visual := _click_carry_preview as CardDragPreview
		if drag_visual != null:
			return_global_position = drag_visual.get_card_global_position()
	_clear_click_drop_feedback()
	if is_instance_valid(emblem_library):
		emblem_library.clear_sticker_move_preview()
	if is_instance_valid(_inspection_surface):
		_inspection_surface.clear_drop_preview()
	for row: BattlefieldRow in [front_row, back_row]:
		row.stop_stack_target_feedback()

	if is_instance_valid(_click_carry_preview):
		_click_carry_preview.queue_free()
	_click_carry_preview = null

	if is_inspection_item:
		_refresh_drag_availability()
		return
	if not _is_card_drag_data(drag_data):
		push_error("点击携带结束时收到不符合卡牌拖拽契约的数据")
		return
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
	elif source_type == &"resource_preparation":
		var source_tray := drag_data.get("source_tray") as ResourcePreparationTray
		if is_instance_valid(source_tray): source_tray.refresh()
	elif source_type == &"board":
		var source_row := drag_data.get("source_row") as BattlefieldRow
		if is_instance_valid(source_row):
			source_row._finish_card_drag(
				null if should_return_failed_indicator else return_global_position
			)
		var source_slot := drag_data.get("source_slot") as BoardSlot
		if is_instance_valid(source_slot):
			var indicator := source_slot.get_equipment_indicator()
			if is_instance_valid(indicator):
				indicator.visible = true
		if should_return_failed_indicator:
			_return_failed_equipment_indicator_drag(
				drag_data,
				return_global_position as Vector2
				if return_global_position is Vector2
				else get_viewport().get_mouse_position()
			)
	elif source_type == &"spell_preparation":
		var source_slot := drag_data.get("source_slot") as Control
		if is_instance_valid(source_slot):
			source_slot.modulate.a = 1.0


func _clear_click_drop_feedback(clear_stack_feedback: bool = true) -> void:
	for row: BattlefieldRow in [front_row, back_row]:
		row.clear_drop_preview(clear_stack_feedback)
	collection_drop_zone.clear_drop_preview()
	if is_instance_valid(spell_preparation_tray):
		spell_preparation_tray.call("_clear_insertion_preview")


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
	if drag_data.get("kind") in [&"equipment_card", &"equipment_indicator"]:
		_begin_equipment_drop_profile()
		_equip_item_on_squad(target_row, drag_data)
		return
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
	if drag_data.get("source_type") == &"resource_preparation":
		var owned_resource := drag_data.get("owned_card") as OwnedCard
		if owned_resource != null and not resource_board_state.is_level_resource("player", String(owned_resource.instance_id)):
			resource_board_state.deployments["player"].erase(String(owned_resource.instance_id))
			_build_collection_cards()
			_refresh_resource_preparation_trays()
			play_area_label.text = "资源已从资源板收回收藏"
		return
	if drag_data.get("source_type") == &"spell_preparation":
		var prepared_spell := drag_data.get("owned_card") as OwnedCard
		if prepared_spell != null:
			spell_preparation_tray.clear_hover_card()
			prepared_spell_instance_ids.erase(prepared_spell.instance_id)
			_refresh_spell_preparation_tray()
			_build_collection_cards()
			play_area_label.text = "法术已从准备栏取回收藏"
		return
	if drag_data.get("kind") == &"equipment_indicator":
		collection_drop_zone.clear_drop_preview()
		_unequip_indicator_to_collection(drag_data, card_global_position)
		return
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


func _equip_item_on_squad(
	target_row: BattlefieldRow,
	drag_data: Dictionary
) -> bool:
	if current_phase != GamePhase.PREPARE or target_row == null:
		return false
	var intent := drag_data.get("drop_intent") as Dictionary
	var target_slot := intent.get("target_slot") as BoardSlot if intent != null else null
	var owned_item := drag_data.get("owned_card") as OwnedCard
	var indicator_local_position: Vector2 = intent.get(
		"indicator_local_position",
		SquadData.DEFAULT_EQUIPMENT_INDICATOR_POSITION
	) if intent != null else SquadData.DEFAULT_EQUIPMENT_INDICATOR_POSITION
	if (
		intent == null
		or intent.get("operation") != &"equip_item"
		or not is_instance_valid(target_slot)
		or target_row.get_slot_index(target_slot) < 0
		or owned_item == null
		or owned_item.card_data == null
		or owned_item.card_data.card_type != CardData.CardType.EQUIPMENT
		or owned_card_collection.get_by_instance_id(owned_item.instance_id) != owned_item
		or not indicator_local_position.is_finite()
	):
		return false
	var target_squad := target_slot.get_squad_data()
	if target_squad == null:
		return false
	var source_type := drag_data.get("source_type") as StringName
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var source_squad: SquadData
	if source_type == &"collection":
		if _is_owned_card_deployed(owned_item) or not target_squad.can_equip_item(owned_item):
			return false
	elif source_type == &"board":
		if (
			not is_instance_valid(source_row)
			or not is_instance_valid(source_slot)
			or source_row.get_slot_index(source_slot) < 0
		):
			return false
		source_squad = source_slot.get_squad_data()
		if source_squad == null or source_squad.get_equipped_item() != owned_item:
			return false
		if target_slot != source_slot and not target_squad.can_equip_item(owned_item):
			return false
	else:
		return false

	if target_slot == source_slot:
		if not target_squad.set_equipment_indicator_position(indicator_local_position):
			return false
	else:
		var source_indicator_position := (
			source_squad.get_equipment_indicator_position()
			if source_squad != null
			else SquadData.DEFAULT_EQUIPMENT_INDICATOR_POSITION
		)
		if source_squad != null and source_squad.unequip_item() != owned_item:
			return false
		if not target_squad.equip_item(owned_item, indicator_local_position):
			if source_squad != null:
				source_squad.equip_item(owned_item, source_indicator_position)
			return false
		if source_squad != null:
			source_slot.set_squad_data(source_squad)
			source_slot.configure_drag_source(true, source_row)
	target_slot.set_squad_data(target_squad)
	target_slot.configure_drag_source(true, target_row)
	_record_equipment_drop_profile_section(&"slot_refresh")
	var placed_indicator := target_slot.get_equipment_indicator()
	if is_instance_valid(placed_indicator):
		placed_indicator.call(
			"play_drop_feedback",
			intent.get("indicator_release_global_center", Vector2.INF)
		)
	selected_board_row = target_row
	selected_board_slot = target_slot
	_select_card(owned_item.card_data)
	_record_equipment_drop_profile_section(&"select_card")
	_build_collection_cards()
	_record_equipment_drop_profile_section(&"build_collection_cards")
	play_area_label.text = "%s 已以指示物形态绑定到鼠标落点" % owned_item.card_data.display_name
	_refresh_drag_availability()
	_record_equipment_drop_profile_section(&"refresh_drag_availability")
	_on_battlefield_squads_changed()
	_record_equipment_drop_profile_section(&"battlefield_changed_callback")
	return true


func _begin_equipment_drop_profile() -> void:
	if OS.get_environment("PROJECT_CARD_TRACE_EQUIP_DROP") != "1":
		return
	_equipment_drop_profile_sections.clear()
	_equipment_drop_profile_started_usec = Time.get_ticks_usec()
	_equipment_drop_profile_last_usec = _equipment_drop_profile_started_usec
	_equipment_drop_profile_active = true


func _record_equipment_drop_profile_section(section: StringName) -> void:
	if not _equipment_drop_profile_active:
		return
	var now := Time.get_ticks_usec()
	_equipment_drop_profile_sections[section] = now - _equipment_drop_profile_last_usec
	_equipment_drop_profile_last_usec = now
	if section == &"battlefield_changed_callback":
		_report_equipment_drop_first_frame.call_deferred()


func _record_equipment_drop_profile_duration(section: StringName, duration_usec: int) -> void:
	if _equipment_drop_profile_active:
		_equipment_drop_profile_sections[section] = duration_usec


func _report_equipment_drop_first_frame() -> void:
	if not _equipment_drop_profile_active:
		return
	await RenderingServer.frame_post_draw
	if not _equipment_drop_profile_active:
		return
	var elapsed_usec := Time.get_ticks_usec() - _equipment_drop_profile_started_usec
	_equipment_drop_profile_active = false
	print(
		"EQUIPMENT_DROP_PROFILE release_signal_to_first_draw_ms=%.3f sections_us=%s"
		% [float(elapsed_usec) / 1000.0, str(_equipment_drop_profile_sections)]
	)


func _record_battle_performance_frame(delta: float) -> void:
	if not _battle_performance_trace_enabled or _battle_trace_frame_samples.size() >= BATTLE_TRACE_MAX_FRAMES:
		return
	var advance_total_usec := (
		battle_controller.performance_trace_advance_total_usec
		if is_instance_valid(battle_controller)
		else _battle_trace_last_advance_total_usec
	)
	var advance_delta_usec := maxi(advance_total_usec - _battle_trace_last_advance_total_usec, 0)
	_battle_trace_last_advance_total_usec = advance_total_usec
	var exact_snap_total_usec := 0
	for row: BattlefieldRow in [front_row, back_row]:
		if is_instance_valid(row):
			exact_snap_total_usec += row.equipment_exact_snap_total_usec
	var exact_snap_delta_usec := maxi(
		exact_snap_total_usec - _battle_trace_last_exact_snap_total_usec,
		0
	)
	_battle_trace_last_exact_snap_total_usec = exact_snap_total_usec
	var now := Time.get_ticks_usec()
	var wall_frame_ms := float(now - _battle_trace_previous_frame_usec) / 1000.0 if _battle_trace_previous_frame_usec > 0 else 0.0
	_battle_trace_previous_frame_usec = now
	_battle_trace_frame_samples.append({
		"frame_ms": delta * 1000.0,
		"wall_frame_ms": wall_frame_ms,
		"phase": int(current_phase),
		"shop_open": ordinary_shop_open,
		"collection_page": current_collection_page,
		"native_drag_active": not _native_carry_data.is_empty(),
		"click_carry_active": not _click_carry_data.is_empty(),
		"collection_page_turn_ms": float(_battle_trace_page_turn_usec) / 1000.0,
		"battle_start_ms": float(_battle_trace_start_usec) / 1000.0,
		"battle_result_ms": float(_battle_trace_result_usec) / 1000.0,
		"drag_preview_ms": float(_battle_trace_drag_preview_usec) / 1000.0,
		"release_exact_snap_ms": float(exact_snap_delta_usec) / 1000.0,
		"battle_advance_ms": float(advance_delta_usec) / 1000.0,
		"state_sync_ms": float(_battle_trace_state_sync_usec) / 1000.0,
		"effect_dispatch_ms": float(_battle_trace_effect_dispatch_usec) / 1000.0,
		"battle_effect_children": (
			battle_effect_layer.get_child_count()
			if is_instance_valid(battle_effect_layer)
			else 0
		),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	})
	_battle_trace_page_turn_usec = 0
	_battle_trace_start_usec = 0
	_battle_trace_result_usec = 0
	_battle_trace_drag_preview_usec = 0
	_battle_trace_state_sync_usec = 0
	_battle_trace_effect_dispatch_usec = 0


func _write_battle_performance_trace() -> void:
	if not _battle_performance_trace_enabled:
		return
	var metric_names: Array[String] = [
		"frame_ms",
		"wall_frame_ms",
		"collection_page_turn_ms",
		"battle_start_ms",
		"battle_result_ms",
		"drag_preview_ms",
		"release_exact_snap_ms",
		"battle_advance_ms",
		"state_sync_ms",
		"effect_dispatch_ms",
		"battle_effect_children",
		"draw_calls",
	]
	var summary: Dictionary = {}
	for metric: String in metric_names:
		var values: Array[float] = []
		for sample: Dictionary in _battle_trace_frame_samples:
			values.append(float(sample[metric]))
		values.sort()
		if values.is_empty():
			summary[metric] = {"p50": 0.0, "p95": 0.0, "max": 0.0}
			continue
		var p50_index := clampi(ceili(float(values.size()) * 0.50) - 1, 0, values.size() - 1)
		var p95_index := clampi(ceili(float(values.size()) * 0.95) - 1, 0, values.size() - 1)
		summary[metric] = {
			"p50": values[p50_index],
			"p95": values[p95_index],
			"max": values.back(),
		}
	var slow_frame_count := 0
	for sample: Dictionary in _battle_trace_frame_samples:
		if float(sample.frame_ms) > 33.0:
			slow_frame_count += 1
	var payload := {
		"sampling_version": 2,
		"os": OS.get_name(),
		"window_size": [int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)],
		"sample_count": _battle_trace_frame_samples.size(),
		"frames_over_33ms": slow_frame_count,
		"summary": summary,
		"samples": _battle_trace_frame_samples,
	}
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var relative_path := "user://logs/battle-performance-%s.json" % stamp
	var absolute_directory := ProjectSettings.globalize_path("user://logs")
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var file := FileAccess.open(relative_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入战斗性能日志：%s" % relative_path)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var absolute_path := ProjectSettings.globalize_path(relative_path)
	print("BATTLE_PERFORMANCE_TRACE %s" % absolute_path)
	if is_instance_valid(play_area_label):
		play_area_label.text = "性能日志已写入 logs 文件夹（F10 可再次导出）"
		play_area_label.tooltip_text = absolute_path


func _return_failed_equipment_indicator_drag(
	drag_data: Dictionary,
	entry_global_position: Vector2
) -> bool:
	# 指示物一旦离开合法卡面就已经显示为完整装备牌；松在任何无效区域，
	# 都按“卸下”处理，而不是把它弹回原随从。
	return _unequip_indicator_to_collection(drag_data, entry_global_position)


func _unequip_indicator_to_collection(
	drag_data: Dictionary,
	entry_global_position: Vector2
) -> bool:
	if current_phase != GamePhase.PREPARE:
		return false
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var owned_item := drag_data.get("owned_card") as OwnedCard
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row not in [front_row, back_row]
		or source_row.get_slot_index(source_slot) < 0
		or owned_item == null
	):
		return false
	var squad := source_slot.get_squad_data()
	if squad == null or squad.get_equipped_item() != owned_item:
		return false
	if squad.unequip_item() != owned_item:
		return false
	source_slot.set_squad_data(squad)
	source_slot.configure_drag_source(true, source_row)
	selected_board_row = null
	selected_board_slot = null
	_select_card(owned_item.card_data)
	_build_collection_cards(owned_item.card_data, entry_global_position)
	play_area_label.text = "%s 已从指示物恢复为装备牌" % owned_item.card_data.display_name
	_refresh_drag_availability()
	_on_battlefield_squads_changed()
	return true


func _get_collection_card_slots() -> Array[Control]:
	var slots: Array[Control] = []
	var children: Array = (
		_page_turn_overlay.get_meta("target_slots", [])
		if is_instance_valid(_page_turn_overlay)
		else collection_card_row.get_children()
	)
	for child: Node in children:
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
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		# 法术/装备当前只有占位卡面；统一走失败返回路径，不能进入战场规则。
		return false
	var source_type := drag_data["source_type"] as StringName
	if target_type == &"board" and target_row == null:
		return false

	if source_type == &"collection":
		if target_type != &"board" or not target_row.has_capacity_for_single_card():
			return false

		var owned_card := drag_data.get("owned_card") as OwnedCard
		if owned_card == null:
			# 旧测试/旧调用点没有实例字段时，从权威收藏补齐；真实CardView会直接携带实例。
			owned_card = owned_card_collection.find_first_by_definition(card_data)
		if (
			not collection_cards.has(card_data)
			or owned_card == null
			or owned_card_collection.get_by_instance_id(owned_card.instance_id) != owned_card
			or _is_owned_card_deployed(owned_card)
		):
			return false

		selected_board_slot = target_row.add_card(card_data, insert_index, owned_card)
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

		var source_squad := source_slot.get_squad_data()
		var returned_equipment_entries: Array[Dictionary] = []
		var moving_whole_single := source_squad.get_card_count() == 1
		if target_type == &"collection":
			var returns_new_owned_card := not collection_cards.has(card_data)
			if returns_new_owned_card and collection_cards.size() >= COLLECTION_MAX_CARDS:
				return false
		elif (
			target_type == &"board"
			and source_row != target_row
			and not target_row.has_capacity_for_single_card()
		):
			return false
		if target_type == &"collection" or not moving_whole_single:
			var returned_entry := _capture_returned_equipment_entry(
				source_slot,
				SquadData.new(),
				true
			)
			if not returned_entry.is_empty():
				returned_equipment_entries.append(returned_entry)
		if target_type == &"collection":
			var returned_card := card_data
			var returned_owned_card := source_squad.get_owned_card(card_data)
			var returns_new_owned_card := not collection_cards.has(returned_card)
			if not source_row.remove_card_from_squad(source_slot, card_data):
				return false
			# 上场卡一直保留在 collection_cards 中；回收只解除部署状态。
			if returns_new_owned_card:
				collection_cards.append(returned_card)
			_record_recently_returned_card(returned_card, returned_owned_card)
			selected_board_row = null
			selected_board_slot = null
			_build_collection_cards(returned_card, entry_global_position)
		elif target_type == &"board":
			var moving_owned_card := source_squad.get_owned_card(card_data)
			if source_row == target_row:
				if not moving_whole_single:
					source_row.remove_card_from_squad(source_slot, card_data)
					selected_board_slot = target_row.add_card(
						card_data,
						insert_index,
						moving_owned_card
					)
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

				if moving_whole_single:
					var moved_squad := source_row.remove_squad_slot(source_slot)
					if moved_squad == null:
						return false
					selected_board_slot = target_row.add_squad(moved_squad, insert_index)
				else:
					if not source_row.remove_card_from_squad(source_slot, card_data):
						return false
					selected_board_slot = target_row.add_card(
						card_data,
						insert_index,
						moving_owned_card
					)
				selected_board_row = target_row
				if entry_global_position is Vector2:
					_animate_board_card_entry.call_deferred(
						selected_board_slot,
						entry_global_position as Vector2
					)
		else:
			return false
		if not returned_equipment_entries.is_empty():
			if target_type == &"board":
				_build_collection_cards()
			for returned_entry: Dictionary in returned_equipment_entries:
				var returned_item := returned_entry.get("owned_card") as OwnedCard
				if returned_item != null:
					_record_recently_returned_card(returned_item.card_data, returned_item)
			_animate_returned_equipment_entries(returned_equipment_entries)
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
		if intent.get("operation") == &"merge_squad":
			return _transfer_compact_squad_into_single(
				drag_data,
				target_row,
				intent,
				entry_global_position
			)
		return _transfer_whole_squad(
			drag_data,
			target_row,
			int(intent.get("squad_index", 0)),
			entry_global_position
		)
	if kind != &"card":
		return false

	var card_data := drag_data.get("card_data") as CardData
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		# 非随从不能生成新小队或合并到小队，原生拖拽结束后由来源恢复。
		return false
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
		and not target_slot.get_squad_data().can_accept_card_at(
			card_data,
			int(intent.get("card_index", 0))
		)
	):
		return false

	if source_type == &"collection":
		var owned_card := drag_data.get("owned_card") as OwnedCard
		if owned_card == null:
			# 兼容旧拖拽字典，同时保证进入小队后仍绑定到唯一OwnedCard。
			owned_card = owned_card_collection.find_first_by_definition(card_data)
		if (
			not collection_cards.has(card_data)
			or owned_card == null
			or owned_card_collection.get_by_instance_id(owned_card.instance_id) != owned_card
			or _is_owned_card_deployed(owned_card)
		):
			return false
		result_squad.bind_owned_card(card_data, owned_card)
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
	if source_type == &"board" and operation == &"new_squad":
		var live_source_squad := source_slot.get_squad_data()
		if live_source_squad.get_card_count() == 1:
			result_squad.merge_indicators_from(live_source_squad)
		if (
			live_source_squad.get_card_count() == 1
			and live_source_squad.get_equipped_item() != null
			and result_squad.get_equipped_item() == null
		):
			result_squad.equip_item(
				live_source_squad.get_equipped_item(),
				live_source_squad.get_equipment_indicator_position()
			)

	var returned_equipment_entries: Array[Dictionary] = []
	if (
		operation == &"new_squad"
		and source_type == &"board"
		and source_slot.get_squad_data().get_card_count() > 1
	):
		var returned_entry := _capture_returned_equipment_entry(
			source_slot,
			result_squad,
			true
		)
		if not returned_entry.is_empty():
			returned_equipment_entries.append(returned_entry)
	if operation == &"merge_card" and source_type == &"board" and source_slot != target_slot:
		for equipment_slot: BoardSlot in [target_slot, source_slot]:
			var returned_entry := _capture_returned_equipment_entry(
				equipment_slot,
				result_squad,
				true
			)
			if not returned_entry.is_empty():
				returned_equipment_entries.append(returned_entry)

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

	if source_type == &"collection" or not returned_equipment_entries.is_empty():
		_build_collection_cards()
	if not returned_equipment_entries.is_empty():
		for returned_entry: Dictionary in returned_equipment_entries:
			var returned_item := returned_entry.get("owned_card") as OwnedCard
			if returned_item != null:
				_record_recently_returned_card(returned_item.card_data, returned_item)
		_animate_returned_equipment_entries(returned_equipment_entries)
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


func _transfer_compact_squad_into_single(
	drag_data: Dictionary,
	target_row: BattlefieldRow,
	intent: Dictionary,
	entry_global_position: Variant = null
) -> bool:
	var source_row := drag_data.get("source_row") as BattlefieldRow
	var source_slot := drag_data.get("source_slot") as BoardSlot
	var source_squad := drag_data.get("squad_data") as SquadData
	var target_slot := intent.get("target_slot") as BoardSlot
	if (
		not is_instance_valid(source_row)
		or not is_instance_valid(source_slot)
		or source_row.get_slot_index(source_slot) < 0
		or source_slot.get_squad_data() != source_squad
		or not is_instance_valid(target_slot)
		or target_row.get_slot_index(target_slot) < 0
		or target_slot == source_slot
	):
		return false
	var target_squad := target_slot.get_squad_data()
	var result := source_squad.merge_compact_double_with_single(
		target_squad,
		bool(intent.get("single_on_left", false))
	)
	if result == null:
		return false
	var used_units := target_row.get_used_unit_count()
	if source_row == target_row:
		used_units -= source_squad.get_unit_count()
	used_units -= target_squad.get_unit_count()
	used_units += result.get_unit_count()
	if used_units > BattlefieldRow.BATTLEFIELD_UNIT_COUNT:
		return false
	var returned_equipment_entries: Array[Dictionary] = []
	for equipment_slot: BoardSlot in [source_slot, target_slot]:
		var returned_entry := _capture_returned_equipment_entry(
			equipment_slot,
			result,
			true
		)
		if not returned_entry.is_empty():
			returned_equipment_entries.append(returned_entry)

	source_row.remove_squad_slot(source_slot)
	target_slot.set_squad_data(result)
	target_slot.configure_drag_source(true, target_row)
	if not returned_equipment_entries.is_empty():
		_build_collection_cards()
		for returned_entry: Dictionary in returned_equipment_entries:
			var returned_item := returned_entry.get("owned_card") as OwnedCard
			if returned_item != null:
				_record_recently_returned_card(returned_item.card_data, returned_item)
		_animate_returned_equipment_entries(returned_equipment_entries)
	selected_board_row = target_row
	selected_board_slot = target_slot
	_select_card(result.get_effect_source())
	if entry_global_position is Vector2:
		_animate_board_card_entry.call_deferred(target_slot, entry_global_position)
	play_area_label.text = "已将四符文双卡小队与%s的单卡合并" % target_row.row_title
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
		_record_recently_returned_card(
			source_squad.horizontal_cards[index],
			source_squad.get_owned_card(source_squad.horizontal_cards[index])
		)
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
	if drag_data.get("source_type") not in [&"collection", &"board", &"spell_preparation", &"resource_preparation"]:
		return false
	if drag_data.get("kind") == &"card":
		return drag_data.get("card_data") is CardData
	if drag_data.get("kind") == &"squad":
		return drag_data.get("squad_data") is SquadData
	if drag_data.get("kind") in [&"equipment_card", &"equipment_indicator"]:
		return (
			drag_data.get("card_data") is CardData
			and drag_data.get("owned_card") is OwnedCard
		)
	return false


func _is_inspection_item_drag(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get("kind") in [
		&"emblem_library",
		&"sticker_scraper",
	]


func _refresh_drag_availability() -> void:
	var drag_enabled := current_phase == GamePhase.PREPARE
	if is_instance_valid(spell_preparation_tray):
		spell_preparation_tray.set_drop_enabled(drag_enabled)
	if is_instance_valid(player_resource_tray):
		player_resource_tray.set_drop_enabled(drag_enabled)
	if emblem_library != null:
		emblem_library.set_drag_enabled(
			drag_enabled and is_instance_valid(_inspection_overlay)
		)
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

	# 点击携带和原生长按拖拽都进入这里；回位期间只临时提升真实卡牌，
	# 收藏视口本身始终不裁切，避免一次失败回位永久改变后续悬停表现。
	var resting_z_index := card_view.z_index
	card_view.set_resting_z_index(CardDragPreview.DRAG_PREVIEW_Z_INDEX)
	card_view.animate_from_global_position(entry_global_position)
	# 层级跟随真实动画状态，不能用独立计时器猜测 Tween 的结束帧。
	while is_instance_valid(card_view) and card_view.is_layout_animating():
		await get_tree().process_frame

	if is_instance_valid(card_view) and not card_view.is_queued_for_deletion():
		card_view.set_resting_z_index(resting_z_index)


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
