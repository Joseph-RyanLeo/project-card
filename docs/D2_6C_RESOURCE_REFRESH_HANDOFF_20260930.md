# D2-6C 新增五项需求：Luna 高推理实施交接

用户要求由新的 Luna 高推理聊天执行本文件。前一聊天 01a0f164-9485-7df2-b2d2-81f650a65aa0 已完成七项修复；不要覆盖它的生命周期清理、幽灵收藏修复、暂停菜单层级、资源拖影鼠标锚点、初始九张资源和调试器资源支持。实现全部确定项后集中验证，不逐段停工回报。

## 需求与现状分析

1. 当前 ResourcePreparationTray._create_piece_badges 在整块质心创建一个图标和生命Label；CardDragPreview也只有一个资源图标。新要求是每一个六边格中心均有同类资源图标，实际仍是一张卡、一个HP状态、一次奖励。UI图标个数必须等于shape格数。
2. resource_hex_tile.png 与 indicator_icons.png 实际第一列为铜色，第二列为深灰色；现有I/II按列0/1取图，因此色彩要交换。不要交换CardData.rarity、OwnedCard形状尺寸、生命/奖励和随机池品级。
3. 删除资源板、原位ghost、落点拼图预览和拼图拖影中的剩余HP数字及其Label/字号/动画/入参（清理所有调用点）。保留真实BattleResourceState.current_health及攻击/开采逻辑；仍要按真实生命隐藏已击碎资源。完整卡面可保留定义里的原始生命上限，不把“取消显示”变成无生命/永不击碎。
4. 已有 resources/cards/mining_pick.tres：矿稿、迷宫卡包、I级近战武器、equipment_action_delta=1、关键词mining和uses_per_battle=1。无需创建同功能第二份装备。用户已纠正名称为“矿镐”，原“矿稿”和“矿搞”均为错字；沿用mining_pick定义、文件名与id，统一改为“矿镐”。应在初始收藏及卡面调试器开放已有mining_pick，让用户能装备并验证；实际效果只有装备到小队后行动值+1、每场开采1，不修改共享CardData造成多队串效果。
5. 每场新准备阶段自动在双方资源区刷新每方0—3张资源。这是一项新的关卡资源生成流程，目前initialize_level只生成禁用格、没有双方随机资源。需要保存自动资源的OwnedCard实例、固定shape、部署和刷新时机，不能在UI refresh里生成。

## 2026-09-30 用户确认（取代此前建议）

- 首次进入新局准备阶段、正常战斗结算进入下一准备阶段时生成一次；读档、中断重开、界面刷新不重抽。
- 双方独立生成0、1、2、3张，各数量25%。用户以每方0—3取代“双方合计最多5张”的早期想法，因此双方合计可为0—6张，不再加总数5的限制。
- 先按品级抽取，再在该品级资源种类中等概率选取，允许重复。用户要求品级概率沿用卡包等级稀有度。当前实现的通常抽卡权重I/II/III/IV=75/20/4/1，而九种资源仅I—III；用户已确认仅在现有品级按75∶20∶4归一化抽取，不保留IV的空抽。I/II/III概率分别75/99、20/99、4/99；同级种类等概率且可重复，每方抽定的0—3张必须完整生成。
- 自动资源仅属于本关：不能拖回收藏，也不能在资源板换位置。仍支持正常悬停检视和战斗受击/开采。手动部署资源保持原移动、取消、回收和战后消耗规则。
- 正确装备名称为“矿镐”，沿用mining_pick，不新增重复定义。补入默认装备收藏与卡面调试器；此前独立项已补入口，核查并保留。
- 上轮此Luna聊天已完成每格图标、I/II配色交换、删除生命数字、装备入口；本轮基于这些修改继续，不重复造另一套实现。

## 顺序实施方式

### 一、统一资源外观映射与每格图标

- 阅读 ResourceIndicatorStyle、ResourcePreparationTray、CardDragPreview及其全部调用点。共同外观映射放在已有ResourceIndicatorStyle中，逻辑品级I/II/III/IV/V→素材列1/0/2/3/4，各调用点复用；保留实际 atlas x 坐标0/45/92/137/182，不分别复制交换数组造成底座与图标脱节。
- ResourceIndicatorStyle.get_texture及get_icon_atlas_texture均按映射取底座/种类图；资源板和拖影的六边底座按同一映射。仅资源指示物配色交换，不更换普通随从/装备/纹章品级角标或数值规则。
- 板上每个tile中心创建独立TextureRect种类图标，使用原尺寸和透明内容边界（get_used_rect）正确居中，mouse_filter=IGNORE。整块移动、源ghost淡化和hover描边仍按instance_id统一处理，不为每格创建OwnedCard或战斗目标。
- 拖影按每格建立图标列表；删掉旧的单一图标/HP节点实现，复用现有跨淡动画。每格图标跟随对应tile；卡面→拼图时收藏抓取格中心继续锚定鼠标，板内抓取保持真实格内偏移。最新“每格中心”要求优先于旧的“只用一个质心图标”；鼠标抓取原点不能重新跳回原卡中心。若实际抓在格边缘，保留既有抓取偏移，不额外扭曲拼图让每个图标都同时到鼠标。
- 不每帧重建图标或tile；形状/品级/资源种类变更才更新。按实际贴图尺寸居中，遗物图高15、矿物图高22等不能全用固定21×22错位。

### 二、移除剩余生命显示并补装备入口

- 从资源板和拖影删除生命Label、字号常量、渐变动画及废弃health参数；保留战斗健康缓存的存在/消失判断。原位ghost和native/click carry视觉要同步移除。
- 修改本次创建的资源专项测试中针对已取消显示的断言，改验收“无资源生命数字节点、种类图标数与格数一致、真实伤害仍有效”。这是需求明确改变后的测试更新；不得降低其他既有断言。
- mining_pick沿用同一id与tres（兼容持有实例），显式确认近战武器、I级、基础数值1、equipment_action_delta=1、开采1。必要时补base_value=1而不是重复叠加到2。关键词和已有BattleController次数计算复用，不新增平行开采系统。
- 将mining_pick补入新运行初始收藏、卡面调试器路径列表；避免对读档或下一关自动补装备。所有当前权威资料与显示名纠正为“矿镐”，保持卡包归属和奖励池约束。

### 三、随机资源（确认后执行）

已确认采用“本关资源不可收回且不可换位”：
- 将ResourceBoardState已有enemy_resource_cards泛化为双方的关卡资源容器，例如level_resource_cards={player:{},enemy:{}}，复用OwnedCard保存shape；不要新增一套与原部署表重复的独立棋盘。玩家手动资源仍引用OwnedCardCollection，自动资源引用本关容器，两类instance_id不会冲突。同步替换旧enemy容器调用，清理已失效代码。
- 首次新局及Main.start_new_resource_level的关卡创建入口一次性生成资源，UI仅读取。生成先按原0—3规则独立抽禁用格，再为双方各抽0—3张（每个数量25%）；先按确认后的品级权重，再在同级合法资源池均匀抽，可重复，每张仅初始化一次shape。
- placement从合法锚点中随机选，必要时对已固定的shape回溯换位置，不能通过反复重抽卡牌/形状/数量悄悄改概率。不得占禁用格、重叠、越界，目标数量必须完整落板；0张合法。需要处理放置失败并给出可验证原因，不留下半初始化关卡。
- Main._get_deployed_resource_cards、托盘的实例注册及悬停同时识别本关自动资源和手动资源。自动资源没有回收或拖动换位入口；手动资源继续允许板内移动、取消、拖回收藏，且不能占自动资源格位。
- 结算快照和消耗校验区分来源：自动资源击碎/剩余都在本场结束被清理；手动部署资源正常结算仍从收藏消耗；未部署、新奖励保留。不能因为自动玩家资源不在收藏导致missing_deployed_resource或save_resource_board_reference_invalid。NPC奖励仍全早退。
- 存档保存双方本关实例、shape、布局与生成标记；战前快照和中断恢复完全保留。不读档后凭空重抽0张的空关卡。更新RunSaveService相关引用校验及schema/迁移，兼容此前schema4 enemy_resource_cards与玩家手动资源，不把旧玩家收藏数据丢失或变自动资源。
- 正常RESULT仍展示刚结束的统计，直到进入新准备阶段再生成下一批资源；不会把新准备资源加入刚结束的战斗或奖励账本。

### 四、验证与交接

- 更新GAMEPLAY_DESIGN及相关docs的资源显示/自动生成规则，仅把已确认内容记为当前权威；记录本次需求取代“整块单图标/显示生命数字”的关系。默认九张资源的前次实现继续保留。
- 相关单项测试：resource布局/战斗/结算/输入，run_save、显示壳/暂停检视与卡面调试器。针对随机资源补真实数据unit和主场景e2e：双方独立0..3及数量25%、品级权重与同级抽取、重复类型合法、所有形状及禁用格校验、两关ID改变且每关只生成一次、UI刷新/read-save/restart无重抽、自动及手动资源来源差别、NPC奖励、正常结算与读档之后继续。
- 真窗口720p/2K截图确认I深灰、II铜、III及以上未变；1/2/3格形状每格中心图标；无生命数字；抓角落native/click carry、非法落点、取消/回收不退化。
- 不写mock，不为让旧测试绿而修改旧断言；只更新本次明确被需求取代的资源显示断言。不跑全量套件、不commit、不worktree、不新建更多线程或代理。
- 所有Godot实例串行，每次显式--log-file /private/tmp/project-card-用途.log；可执行文件：
  '/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'
  图形CLI需sandbox_permissions=require_escalated并说明鼠标/截图验证目的，已验证能启动；路径整体单引号，不双重反斜杠。不要使用Codex CUA。
- 保留用户音量位置(864,320)、stage8 54/36/+6旧改动与前一Luna刚完成的修改，所有人工可调参数同排中文注释。
- 最终一次性报告完整实测结果、截图、仍未确认/未验证项，按AGENTS三层说明。位置入口继续给绝对链接与最新行号：Main.ENEMY_RESOURCE_TRAY_POSITION、PLAYER_RESOURCE_TRAY_POSITION，EscapePauseMenu.ESCAPE_BUTTON_POSITION；名称统一为“矿镐”，明确同id沿用现有资源。
