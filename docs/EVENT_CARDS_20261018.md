# 事件牌系统（2026-10-18）

## 本次行为

每天沿用当前的随机事件→强化事件→商店→战斗四轮。每轮从对应内容池抽三个不同候选，背面朝上，从左下角牌堆依次发出。背面下方只显示原有暗示，不显示名称、奖励或精确敌方阵容。点击后锁住其他候选，翻开所选牌、移动到左侧，右侧显示描述及操作。

事件选项仍由玩家确认；商店牌右侧提供进入商店，战斗牌右侧提供开始战斗，强化牌右侧复用原有真实卡牌槽。选中牌与奖励沿用原有本局存档，不依赖动画保存状态。动画完成前关闭游戏不会提交选择；奖励提交后读档会保留原结果。

保留全部旧测试事件，以已有金币、纹章、护甲等图标代替卡图。三个新事件的素材来自本轮用户附件；原文来自[飞书事件汇总](https://my.feishu.cn/wiki/StamwnVppibRoZknZftcQCXJnQf?sheet=lAwIUd)，只读取，未写回飞书。

## 内容与边界

- `data/demo2/story_events.json` 保存描述、原始出现层数／条件、选项、概率、结果原文及已接入奖励。
- 用户确认的 `test_ignore_appearance_limits: true` 暂时放开祈愿和白骨塔的层数／英雄限制，供当前第一层伊奥恩试玩。关闭开关后恢复原始限制；赌坊始终要求抽取时至少有5金币。
- 伊奥恩的祈愿：日、月、星进入已有共用指示物库存。混沌贴纸选项保留，但局外解锁系统尚未接入，暂时禁用。
- 奇怪的赌坊：猜硬币花5金币，50%获得10金币；普通骰子花10金币，1d6为6时获得60金币，否则获得1金币；花3金币随机获得苹果／面包／火腿／奶酪之一。以上获得量都是扣除费用后另行入账。骰子作弊、普通老虎机、预见老虎机因缺少装备／卡包／英雄系统而禁用，不重新分配其结果概率。
- 白骨塔：“拿走石头”的概率分支引用尚未实现的业石碎片和业火伤势，整项禁用；离开正常执行。不把未知奖励改成金币。
- 未实现选项显示禁用原因，悬停保留条件、原始概率及奖励说明。

## 代码如何运作

1. `ShortMazeController._generate_paths()` 用本局随机源抽取候选，继续遵守同轮去重与优先未见事件规则；未选事件仍可再次出现。
2. `event_card_table.gd` 创建真实按钮节点，负责发牌、翻牌、移位；完成后发出 `path_chosen` 信号。
3. `ShortMazeController.select_path()` 提交选择和存档，再由 `_build_selected_event()` 在右侧复用旧事件、强化、商店和战斗入口。
4. `maze_story_event_service.gd` 只判断条件、抽结果；`choose_story_option()` 在原有事务内扣费、发金币／贴纸／指示物，再保存。保存失败还原完整事务，包括随机源。
5. `selected_path.story_result` 保存选项、结果索引及实际骰子点数；`reward_claimed` 阻止重复领取。结果页面点击继续后才推进下一轮。

## GDScript学习要点

- `preload()` 在加载脚本时准备资源，牌面直接引用用户图片；`TEXTURE_FILTER_NEAREST` 用最近邻采样保留像素边缘。
- `signal` 将界面与规则分开：牌桌只发出选中ID，不直接写金币或收藏。
- `await tween.finished` 等待当前翻牌动作结束再开始下一步；`set_parallel(true)` 让移动、淡出等动画同时发生。动画不代替正式奖励事务。
- JSON读取的数值通常是浮点数。骰子点数与配置逐项转为 `int` 比较，避免数组成员判断把整数6与浮点6.0区分。
- `duplicate(true)` 深复制路径与事务快照，避免随后新增结果时同时改坏用于回退的旧数据。

## 验证入口

`tests/event_cards_test.gd` 使用正式GameDisplay、真实鼠标输入、真实单卡与磁盘存档，验证背面信息隐藏、翻牌与左右布局、强化卡槽、事件条件、扣费／概率、结果恢复、拒绝重复奖励及保存失败回退。加用户参数 `--capture-events` 可输出预览到 `/private/tmp/project-card-event-*.png`，须使用图形模式。

所有Godot命令须串行执行，显式带 `--log-file /private/tmp/project-card-用途.log`。无窗口渲染打开旧商店贴纸包时会出现现有着色器编译诊断；图形模式未复现该诊断。

本次结果：图形模式事件牌测试41项断言全部通过；`git diff --check`通过。额外运行既有 `d2_8_rewards_sentry_test.gd`，459项中455项通过，4项哨位图集尺寸断言失败：旧测试要求46／47×54，现有 `sentry_indicator_style.gd` 定义为44×49；该测试与相关服务／素材脚本本轮均无修改。

界面截图：[三张背面牌](previews/event_cards_20261018/backs.png)、[祈愿正面与选项](previews/event_cards_20261018/prayer.png)、[赌坊结果](previews/event_cards_20261018/casino-result.png)、[强化卡槽](previews/event_cards_20261018/enhancement.png)。


## 同日修正：战斗中的敌方卡面被隐藏

事件牌准备页会隐藏 `EnemyBoardSection`，此前只在准备阶段写入其 `visible`，进入战斗后沿用了隐藏状态。战斗数据与命中仍在正常结算，但所有敌方子节点一起不可见。

现在由 `ShortMazeController.refresh()` 根据当前阶段每次重算父节点显示：准备阶段隐藏精确阵容，战斗和结算阶段恢复显示；天赋选择及商店打开时按对应面板状态隐藏。Godot中父节点的 `visible = false` 会隐藏整棵子树，即使子卡面自身的 `visible` 是true。

新增 `tests/event_battle_visibility_test.gd`，使用正式GameDisplay、实际遭遇与真实伤害结算，覆盖开战敌方小队可见、战后查看、战斗存档返回准备及读档重试。修复前21项断言中5项失败，修复后图形模式21项全部通过；截图见[战斗中的真实敌方阵容](previews/event_cards_20261018/battle-visible.png)。
