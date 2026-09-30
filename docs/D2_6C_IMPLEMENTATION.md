# D2-6C 资源板实施交接

## 范围与约束

本阶段完成设计资料、资源素材、六边形布局模型、资源板准备 UI、部署/收回交互、实例形状存档、资源战斗状态、开采、九种收获、战后结算、地面临时背包、存档恢复与下一关流程。阶段学习验收仍在交接时进行。

固定几何权威为图4 `460eb1c1c6d39214b57f492401231589.png`：170×160、六列错位；底板图3为182×184；图5仅核对样式，图6单格217×32，图7禁用格35×32。图1/2仅作为界面位置/玩法参考，不决定栏位坐标。使用现有 `ResourceIndicatorStyle` 的 `ICON_ATLAS` 资源种类图。资源立绘保持原尺寸，由 CardView 既有卡图裁切和每卡 `art_offset` 控制取景。

## 确认规则摘要

双方每关独立抽0—3禁用格；资源 OwnedCard 获得时确定1—5相连格形状，不可旋转。部署映射和抓取锚点属于关卡状态。存档读档和 UI 刷新保持；中断回滚；正常战后本场部署资源从收藏移除。战斗/开采/奖励完整规则见三份设计入口。NPC 奖励无效，潮汐射手自身击碎触发强化仍生效。

## 奖励随机规则交接

- 随机装备适用通常卡包 I—IV，品级权重 75/20/4/1；指定 n 级时从该级全部合法装备等概率抽取。
- 随机纹章 I/II/III 权重 85/13/2，排除元素贴纸；“普通/稀有/史诗纹章”分别指 I/II/III。各档候选等概率；空档在剩余非空档按原权重重新归一。指定等级无合法候选则无奖励，不造占位装备。
- 五元素碎晶等概率。唯一/解锁约束沿用现有规则。金币扣除最低为0。
- 玩家获得金币记入玩家金币；装备、碎晶入收藏；纹章入工具箱。工具箱满时战后奖励进入持久化地面临时背包，玩家选择保留、丢弃或装备后才能继续；不能丢失奖励，重复结算幂等。敌方NPC奖励无效，不接入敌方持久收藏。

## 五步状态

1. 资料/素材/实例与布局模型：完成。
2. 六边形 UI 与交互：完成；玩家可从收藏拖入资源板，也可在板内按住拖动或点击拾取后落位；非法落点不改变部署。敌方资源板只显示独立 NPC 资源实例。
3. 目标选择与开采：完成。普通攻击候选包含敌方随从和双方资源；资源按中立目标处理、权重1、普通攻击固定扣1，不触发元素派生。开采按运行时小队的效果来源卡与装备计算次数，覆盖下一次行动并从双方存活资源等概率选取；发射时消费次数，伤害类型固定为伤害并一次扣除资源当前全部生命。资源不存在时不消费。潮汐射手强化与 NPC 奖励早退彼此独立，胜负只看随从。
4. 收获奖励与地面临时背包：完成。五碎晶、彩金矿、贪欲之石、晶化残躯和废弃工具箱的奖励均记入独立账本；金币在结算时入账，卡牌进收藏，纹章进工具箱。工具箱溢出会持久保存到地面临时背包，入包/装备/丢弃后解除下一关阻塞。
5. 存档流程与关卡继续：完成实现。战前快照、启动快照和本局存档包含资源部署与地面奖励；未提交战斗恢复战前资源板，已提交战斗移除部署资源；已提交战斗不可重放。存档同时保留待继续的已结算关卡标记；读档后可从准备阶段继续。处理地面奖励后继续会建立下一关资源板。

## 本阶段实现入口

- `ResourcePreparationTray` 负责绘制底板、固定六边形布局、禁用格、资源拼图、每格种类图标，统一处理悬停详情、落点解析和预览；绘制层会跨刷新保留，清理预览不修改拖放来源数据。
- `ResourceBoardState` 保存双方禁用格、部署锚点和抓取偏移，`level_resource_cards` 保存双方本关自动资源；手动资源仍由玩家收藏持有。
- `Main` 把收藏拖放、板内拖放和点击拾取送入同一落点解析/提交流程，并在开发控制台提供 `resource list`、`resource add <ID或名称>` 与 `resource enemy add <ID或名称>`。
- `RunSaveService` 校验手动部署引用收藏、自动部署引用本关容器；schema 5保存双方自动资源及生成标记，迁移保留旧实例，资源板状态往返保存。
- `BattleResourceState` 保存每个部署资源的战斗生命，不进入随从胜负、存活阵容或阵型注册。`BattleEffectEvent.resource_target` 让普通行动固定扣1、开采按当前剩余生命造成伤害；资源命中不触发直线追击。`BattleRunRewardLedger`、`BattlePermanentGrowthLedger` 与 `BattleOwnedCardChangeLedger` 将战斗期奖励和伤势变化送入原子结算。`RunRewardState.pending_ground_items` 保存溢出的纹章，工具箱面板提供入包、装备和丢弃。成功结算提交后移除部署资源；未部署资源留在收藏。下一关按钮生成新关卡资源状态。

## 实际验收结果（2026-09-30）

- 资源布局、素材接入、资源战斗、主场景资源结算、D2-5存档、D2-4战斗效果、显示壳与暂停检视相关单项测试通过；未运行全量测试套件。
- 资源战斗测试通过正常发射及到达时序验证7HP彩金矿开采秒杀、普通攻击固定1、治疗/防御替换、每小队次数、没有资源不消耗次数、保留原强化、潮汐击碎强化与迟到弹道落空。奖励测试验证指定纹章品级、排除元素贴纸、迷宫装备入池、IV唯一性、暗晶伤势范围、即时成长不重复及NPC奖励无效。
- `d2_6c_resource_settlement_test.gd` 实际实例化主场景，验证部署资源消耗、未部署和新奖励保留、重复结算幂等、纹章溢出、JSON往返、清理地面奖励和继续按钮信号确实进入下一关。
- `d2_6c_resource_input_test.gd` 上一轮在真实720p与2K窗口验收整块单图标和生命数字。2026-09-30新增需求取代该呈现：板面、ghost、落点拼图和拖影每格各有种类图标，移除剩余生命数字，但保留真实战斗生命。Luna已完成本版本720p/2K窗口验收；主线程复验出现间歇输入失败，最终状态见阶段总结，不能宣称窗口专项稳定通过。720p另验证战斗阶段禁用部署后仍可悬停详情；显示入口随画布倍率缩放，Esc入口移开资源区域。
- 图形启动在受限沙箱下退出134；使用获准的相同Steam Godot可执行文件运行正常，无需更换引擎或安装依赖。所有测试实例串行运行并显式指定日志。
- 截图：`/private/tmp/project-card-resource-drag-720p.png`、`/private/tmp/project-card-resource-hover-720p.png`、`/private/tmp/project-card-resource-drag-2k.png`、`/private/tmp/project-card-resource-hover-2k.png`、`/private/tmp/project-card-resource-combat-720p.png`。
- 阶段8旧测试未通过：它仍要求“本次进入小数累计”，而本轮未改动的基线 `BattleFormulaPresenter` 使用“小数结转”；另调用了当前运行引擎不存在的 `Tween.get_speed_scale()`。保留原断言与用户已修改的54、36及+6强化公式。显示壳测试退出仍报告2个ObjectDB引用与1个资源未释放，与先前主场景测试记录一致；功能断言通过，未宣称所有历史测试无错误。

## 学习交接：从输入到结果

准备阶段拖入资源卡时，`ResourcePreparationTray.resolve_drop()` 把鼠标位置转为六边形坐标并统一校验；提交后 `ResourceBoardState` 保存部署，UI按部署绘制整块拼图。战斗开始时 `BattleController` 创建独立的资源战斗状态。普通攻击或开采发射后，到达事件扣生命；击碎触发潮汐强化并将玩家奖励写入账本。结算服务从战前快照应用账本、消耗本场资源，再让Main处理工具箱溢出与下一关；中断则恢复战前状态。

核心数据分工：`OwnedCard.resource_shape` 属于卡牌实例，获得后不再重抽；`ResourceBoardState` 管关卡ID、禁用格和部署锚点；`BattleResourceState.current_health` 只管本场生命；`mining_actions_remaining_by_runtime_id` 为每个小队保存自己的次数。`RunRewardState.pending_ground_items` 保存地面奖励，`pending_next_level_from_id` 防止读档后绕过已结算关卡。`GameDisplay.tscn` 负责固定720p内部画布，Main串起输入、战斗和结算。

较陌生的写法：资源战斗状态继承 `RefCounted`，是独立数据对象而非随从节点，因此不会意外进入随从存活与胜负逻辑。`drop_requested` 等信号把UI交互交给Main，UI不用直接控制整个游戏。`affine_inverse()` 把窗口/画布鼠标坐标反算为托盘局部坐标，使2K缩放后仍抓住同一格。账本先记录、结算统一提交，配合战斗ID去重，避免重开或重复结算再次发奖。测试中的 `await process_frame` 和 `frame_post_draw` 分别等待输入处理与真实画面绘制完成，不能把直接调用提交函数当作鼠标操作验收。

## 敌方资源卡面悬停修复（2026-09-30）

敌方托盘靠近画布左边，原详情卡却固定向左弹出，导致卡面跑到可视区域外。现在敌方详情向托盘右侧展开，并把同一个 `CardView` 实例交给 Main 已有的 `ClickCarryLayer` 绘制；卡面在常规战场层之上、Esc暂停模态层之下，鼠标过滤保持忽略，所以不会截断托盘输入。悬停仍从托盘统一按 instance ID 查找OwnedCard，包含本关自动资源及迁移后的旧敌方资源。指针离开会关闭，实例切换会换成对应卡面，战斗生命归零触发托盘刷新时会移除卡面。真实720p/2K窗口已核对卡面和位置，并验证战斗阶段可悬停、击碎后关闭。

## 关卡自动资源生成（2026-09-30 后续确认）

`ResourceBoardState.initialize_level()` 只抽取双方各自的禁用格并清空旧关状态；`generate_level_resources()` 在新关创建时再独立抽取双方数量与卡牌，并用回溯放置算法一次排好资源。若资源池缺失或合法位置不足，候选关生成失败，不替换当前资源板。玩家收藏资源与本关自动资源共用部署表，但分别由 OwnedCardCollection 和 `level_resource_cards` 持有；自动资源不出现在收藏，不响应点击/拖动，只响应悬停与战斗伤害。

数量由 `randi_range(0, 3)` 均匀抽取；品级掷点0—98中，0—74对应I级，75—94对应II级，95—98对应III级。同级定义按卡牌ID排序后均匀抽取，顺序稳定但每次允许重复。每个实例获得时固定 `resource_shape`，抽出的卡、shape、部署和 `resources_generated` 标志一起写入关卡存档及战前快照。恢复和UI刷新只读状态。成功战后清空本关双方资源；玩家手动部署资源按收藏实例正常消耗。正常继续时创建新的关卡状态，再执行一次生成。

定向验证包含精确稀有度掷点计数、固定seed的形状/禁用格/重叠检查、关卡资源存档往返及禁止重复生成；真实窗口输入另在720p和2K验证自动资源无法拖动/点取、但仍可悬停。

## D2-6C 结算与拖拽回归修复（2026-09-30）

- 战斗进入准备阶段时，`Main._clear_battle_presentation_for_preparation()` 逐一调用四排 `BoardSlot.clear_battle_status()` 与 `clear_battle_result_statistics()`。它用于继续下一关和新战斗启动；结算页仍保留统计，清理也发生在结算提交之后，不会覆盖成长或伤势。
- 结算提交后先从 `OwnedCardCollection` 重建 `collection_cards`，同时将最近使用书签的实例列表与定义列表按仍持有的 `OwnedCard` 同步过滤。部署资源被服务删除时，收藏页不再保留无法部署的幽灵卡；奖励和未部署资源仍显示。
- `SquadView.BATTLE_RESULT_OVERLAY_Z_INDEX` 为 3500，`Main.ESCAPE_PAUSE_MENU_Z_INDEX` 为 4000，统计落在模态菜单下方，沿用原来的全屏遮罩与暂停流程。
- 收藏卡片映射到资源形状时只决定抓取格，卡面余量不再成为六边格像素偏移。拖拽拼图保留鼠标对应抓取格中心锚点，并在每个资源格中心显示图标。
- `Main.tscn` 初始收藏列表末尾追加九种资源各一张及已有 `mining_pick`，只影响新建运行。卡面调整器列出同一个 `mining_pick` 定义，不会刷新或读档时补发装备。
- 可调界面入口：`scripts/main.gd` 的 `ENEMY_RESOURCE_TRAY_POSITION` / `PLAYER_RESOURCE_TRAY_POSITION` 是敌方/玩家资源区在 1280×720 逻辑画布世界中的位置，当前分别为 `(6, 171)` 与 `(1094, 364)`；集合视角的世界内容整体 y=`-360`，所以玩家资源区显示在 y=4；战场视角世界内容 y=0，玩家资源区显示在 y=364。`scripts/ui/escape_pause_menu.gd` 的 `ESCAPE_BUTTON_POSITION` 当前为 `(0, 0)`，同样是逻辑画布坐标；2K 显示由画布整体放大，不要把物理像素写入。

专项验收：`d2_6c_resource_settlement_test.gd` 覆盖默认资源实例、收藏/最近书签同步、结算、继续按钮和四排状态清理；`d2_6c_resource_layout_test.gd`、`d2_6c_resource_battle_test.gd`、`d2_5_run_save_test.gd`、`game_display_test.gd` 与 `d2_7_inspection_display_shell_test.gd` 通过。卡面调整器真实界面测试确认资源筛选列出九张卡、可见真实立绘、偏移编辑只改预览副本，重新载入不写 `.tres`。`d2_6c_resource_input_test.gd` 在真实 720p/2K 窗口使用根窗口输入经 SubViewportContainer 验证收藏卡右上及左下抓取、图标中心距鼠标不超过 1 个逻辑像素、点击携带跟随、板内第二格移动、非法落点、退回收藏和资源悬停；单格、横向相连、纵向相连形状另有抓取映射专项断言。结算 Esc 覆盖截图为 `/private/tmp/project-card-escape-result-overlay.png`，拖影截图为 `/private/tmp/project-card-resource-drag-720p.png` 与 `/private/tmp/project-card-resource-drag-2k.png`。结算主场景测试仍报告既有 2 个 ObjectDB 与 1 个资源释放告警；未运行全量测试。

## D2-6C 资源显示刷新与矿镐入口（2026-09-30）

- `ResourceIndicatorStyle.SOURCE_COLUMN_BY_RARITY` 是逻辑品级到贴图素材列的共用映射：I取深灰列、II取铜色列，III—V保持原列。底座、格子和种类图标取同一素材列。
- `ResourcePreparationTray._create_piece_icons()` 按 OwnedCard 的 shape 为每格创建一个只显示的图标节点；底板原位 ghost 会同步淡化整块的格子和图标。落点预览在每格中心画相同资源图标。`CardDragPreview` 对每个拼图格分别创建图标，抓取格仍锚定鼠标。可见内容边界用于居中不同高度素材。
- 托盘 `_battle_health_by_id` 仍缓存真实战斗生命，归零时隐藏整张资源；`BattleResourceState.current_health`、受击与开采逻辑未变。托盘和拼图拖影删除显示生命数字节点。
- 既有 `mining_pick.tres` 显式设置 `base_value=1`。`Main.tscn` 新局初始收藏与 `CardArtTuner.CARD_RESOURCE_PATHS` 都引用该同一资源一次，不新建同效果装备；保存的数据定义仅在装备实际装到小队后由既有行动加值与开采逻辑使用。
- 本轮单项验收通过：`d2_6c_resource_card_intake_test.gd`（含初始收藏与调试器入口）、`d2_6c_resource_layout_test.gd`、`d2_6c_resource_battle_test.gd`、`d2_6c_resource_settlement_test.gd`；原生 `d2_6c_resource_input_test.gd` 真实鼠标窗口在720p与2K均通过，验证每格图标数量、生命数字移除、抓取锚点、非法放置、取消、回收与资源悬停。未运行全量测试。截图：`/private/tmp/project-card-resource-drag-720p.png`、`/private/tmp/project-card-resource-drag-2k.png`。
- 以上旧记录已由 2026-09-30 后续确认取代：每方每关独立抽0—3张，数量各25%；品级I/II/III权重为75/99、20/99、4/99，现有同级资源池内等概率且允许重复。自动资源在初始化新准备阶段时生成，归本关所有，不能拖回收藏或在板内移动；悬停、受击和开采保留。读档、战斗重启/回滚与UI刷新不重抽。正常结算继续后生成新关资源。本轮将既有 `mining_pick` 显示名统一为“矿镐”，不增加第二张卡。

### 学习交接

刷新流程由数据驱动：`ResourceBoardState` 仍保存一个资源实例的部署 shape，`ResourcePreparationTray.refresh()` 读部署并让每个 shape 格创建 tile/icon；拖拽时 `resolve_drop()` 决定抓取格，`CardDragPreview` 用同一 shape 排列 tile/icon。图标数随 shape 变化，但战斗状态只有一份 `BattleResourceState.current_health`，因此不会把每格图标误当成独立卡或生命池。素材列由 `ResourceIndicatorStyle` 映射，避免三个界面各自交换颜色造成底座和图标不一致。

新接触的实现方式：`AtlasTexture.region` 用来从共用大图集裁出每级/种类小图；`Image.get_used_rect()` 找到透明边界内真正有颜色的范围，代码据此对齐内容中心，避免遗物小图因画布高15像素、矿物画布高22像素而偏位。`TextureRect.mouse_filter = IGNORE` 让图标只负责画面，不截获托盘输入；OwnedCard 仍是唯一实体，多个图标节点只是它的显示子元素。

## 主线程阶段归档复验（2026-09-30）

代码、规则、学习说明、下一阶段目标及最终测试边界见 [阶段总结](D2_6C_STAGE_SUMMARY_20260930.md)。无窗口五项复验通过；原窗口脚本在720p与2K最终复验失败，临时诊断多次通过不能覆盖此记录。统一验收命令 `python3 tools/validate_d2_6c.py` 只调度本阶段专项、串行执行、不自动重跑。本次只检查该入口语法，未再次运行整批。
