# 资源、视角、预言与哨位修订（2026-10-26）

## 整体流程

1. **衍生资源隔离**：齿轮废料本来已经标记 `is_derived = true`，问题是自动资源生成没有检查。现在自然资源目录及资源板生成入口都排除衍生、停用定义。显式效果生成、卡面调整器和完整卡牌目录仍保留它们；不删除旧存档已存在的资源，也不重抽当前关资源。
2. **携带卡牌切视角**：点击携带和原生拖动都检测设计视口底部32像素区域，连续停留1秒切换到下半我方战场／收藏。离开底边、结束携带或切视角会清零计时；沿用原上下移动与回弹，不增加黑场。普通Tab双向切换，忽略重复按键、组合键；加载未完成、搜索输入和检视／暂停等弹层不触发。
3. **两种预言互斥**：放入胜利预言时收回失败预言，反向相同。先计算替换后的完整队列，再验证容量，因此满栏也允许一换一。被收回的法术保留原收藏实例与耐久，不因准备操作消费。读入历史双预言队列时保留顺序靠后的一种。
4. **哨位准备操作**：准备阶段及商店内均可部署、回收与移动库存坐标，战斗仍不能调整。库存位置变动后立即更新真实图标；路径牌没有变化时仍复用原路径桌面，但不再跳过哨位刷新。原生指示物拖动开始时把共用接收层移至兄弟节点末尾，避免事件面板截住GUI投放。不会让玩家点击穿透真实覆盖图标的事件／商店棋盘或顶栏，需要时仍应先收板或切换视角。

## 数据与脚本分工

- `scripts/data/resource_board_state.gd`：在自动生成池入口过滤；生成数量、品级权重、格形与存档恢复规则不变。
- `scripts/main.gd`：自然资源目录过滤；底边停留计时；Tab快捷键和输入保护；两种预言候选队列与历史顺序归一化。没有新增长期缓存或另一套卡牌归属数据。
- `scripts/ui/spell_preparation_tray.gd`：有正式落点解析器时，由Main按替换后的队列验证容量；独立托盘没有解析器时仍执行本地容量检查。
- `scripts/ui/celestial_indicator_controller.gd`：复用日月星／哨位的共同原生拖放入口，只调整携带期间接收层的兄弟顺序，落点仍按可见图标中心计算。
- `scripts/flow/short_maze_controller.gd`：从已有刷新尾部提取 `_refresh_sentry_views()`，正常刷新和路径面板快速返回分支都调用；取消商店开关对准备期哨位投放的额外禁止。库存坐标仍保存于原 `stock_position` 字段。

## 容易陌生的写法

`_drag_view_hold_seconds += delta` 是逐帧累计停留时间，不是等待1秒后无条件执行的异步任务；移开即可清零，不会在已经取消拖动后突然切屏。屏幕坐标取自内部Viewport，所以720p和2K窗口使用相同设计坐标判断。

`candidate_order` 是准备ID数组的局部副本。先移除冲突预言、再插入新法术并检查最终长度，只有确认落点才写回原准备列表；预检不改变收藏或耐久。

`move_child()` 调整GUI节点的兄弟顺序，不是把哨位部署到另一个战场区域。原问题中，绘制层级虽然较高，真实GUI投放仍先命中事件面板；临时计时／输入探针确认合法落点已解析成功，但原投放回调未收到事件。

## 验证

新增测试均使用真实对象或真实鼠标键盘输入，没有替代业务函数：

- `tests/resource_prophecy_revision_20261026_test.gd`：439项通过。覆盖80个种子的双方自然资源生成、衍生目录保留、停用过滤、满栏预言互换、普通法术容量、耐久与实例不变、历史队列归一化及真实保存读取；另检查加载前不响应快捷键。
- `tests/drag_camera_switch_20261026_test.gd`：720p和2K真实窗口各27项通过。覆盖点击携带、原生拖动、持续一秒、离开重计、空手不切换、Tab携带不中断、取消归属、既有动画终点及输入／检视保护。
- `tests/sentry_inventory_revision_20261026_test.gd`：44项通过。覆盖实际库存图标移动、边界及实例外观、正常事件路径进入商店、收板后真实双输入部署换排与回收、位置保存读取及战斗禁止操作。
- `tests/sentry_visible_board_input_20261026_test.gd`：2K真实窗口61项通过。继承原哨位双输入用例，不修改其业务断言；先收起遮挡战场的棋盘，并从图标未被顶栏覆盖的下部拿起，覆盖前／后／法术区域、占位拒绝、非法投放、右键／Esc取消和读档。

原哨位测试只检查了库存数据是否包含位置，没有检查图标是否实际移动；此前路径桌面快速返回让旧库存图标残留，后续操作实际上仍点击残留图标。修正刷新后真实部署图标位于前排角落和法术板顶部，原夹具始终点击图标中心会被棋盘／顶栏遮挡，故增加可见场景入口，不修改原测试的业务预期。库存移动专项补上了实际显示位置断言。

现有相关回归通过：哨位战斗103项、铁壁战斗381项、银月战斗467项、结算刷新49项。

未将以下旧用例记为通过，也未改其预期：

- `d2_6c_resource_layout_test.gd`：2项仍期待旧27格／六列布局，当前是19格／五列；本轮没有修改几何布局。其资源生成与状态往返部分未新增失败。
- `d2_6b_spell_preparation_and_release_test.gd`：19项失败并有1处后续空图标访问错误。旧夹具仍使用193×310尺寸、Y=42投放，而现有托盘为195×324、列表从Y=65开始，首次投放即无效并影响后续图标与虚影检查。保留场景导出数据的临时基线，把本轮准备／容量逻辑恢复为修改前版本，与修改后均得到完全相同的19条失败及1处脚本错误，未通过修改预期掩盖问题。

所有Godot进程串行执行，每个进程显式指定独立临时日志。未运行全量套件。日志仍含原有资源UID回退、系统证书及退出引用警告，不以退出码代替断言／脚本错误检查。

## 临时日志

- `/private/tmp/project-card-four-fixes-resource-prophecy-final-checked-output.log`
- `/private/tmp/project-card-four-fixes-camera-720-output.log`
- `/private/tmp/project-card-four-fixes-camera-2k-output.log`
- `/private/tmp/project-card-four-fixes-sentry-inventory-refresh-output.log`
- `/private/tmp/project-card-four-fixes-sentry-visible-final-output.log`
- `/private/tmp/project-card-four-fixes-spell-before-preserved-output.log`
- `/private/tmp/project-card-four-fixes-spell-after-preserved-output.log`

临时输入探针及旧逻辑对照放在 `/private/tmp/`，不接入正式游戏。基线通过替换脚本时保留场景导出属性，避免默认收藏丢失而产生不一致的测试前提。

## 后续修订：自动下移时棋盘留在原位

用户要求拖动触发下半视角时，商店与事件板留在原来的上半世界位置，不跟到下半视角。这里的“原位”是世界坐标不变，不是固定在屏幕上；镜头向下后，上半棋盘会随世界离开当前画面。

**流程**：底边连续停留1秒 → 启用原有收板状态 → 将原面板挂回上半世界并更新投放权限 → 执行原镜头移动与回弹。卡牌继续携带，路径桌面、商品与奖励随机状态都不重建。刷新不会把棋盘拉回下半视角；玩家仍可用原收板按钮把棋盘移回来。

**职责**：只在Main的 `_update_drag_world_view()` 自动触发分支复用 `_tabletop_panels_parked`、`_sync_tabletop_panel_anchors()` 和 `_refresh_drag_availability()`，没有新增面板副本或新的跟随状态。Tab、人物按钮和手动收板仍走原入口，返回上半后照常恢复跟随。

**写法**：Godot节点的位置受父节点变换影响。将已有面板重新挂到 `WorldContent`，它就会保持世界中的原位置，而不是继续依附屏幕层跟着镜头出现。测试用 `affine_inverse()` 把屏幕位置换算回世界位置，并在移动途中、移动结束及刷新后分别比较。

新增 `tests/drag_camera_tabletop_anchor_20261026_test.gd`，使用正式流程和真实输入。720p与2K窗口各52项通过，覆盖事件板／商店、点击携带／原生拖动、途中与终点世界坐标、取消、刷新、手动移回、Tab返回及商品／随机状态不变。原拖动视角专项另27项通过；未运行全量套件。

对应临时输出为 `/private/tmp/project-card-drag-tabletop-anchor-720-checked-output.log`、`/private/tmp/project-card-drag-tabletop-anchor-2k-checked-output.log` 和 `/private/tmp/project-card-drag-camera-anchor-regression-output.log`。
