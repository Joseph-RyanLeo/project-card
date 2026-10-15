# 扭曲矿脉后续调试交接（2026-10-07）

用户明确要求新开对话执行以下工作；本文件交接同项目的后续调试，不重复询问是否允许修改。

## 用户本次要求

1. 修复已有版本的输入问题：Esc菜单中“攻击特效调整器”“卡面调整器”“战斗实验室”三个按钮不能选中、不能点击；点击“导出诊断日志”后，文件界面的全部控件无法交互。截图为2K窗口模式。
2. 在F2命令行加入“添加指定卡牌”命令，主要用来加入扭曲矿脉等迷宫卡测试。复用真实卡牌注册表与OwnedCard收藏流程，说明可用命令、支持的名称／ID及数量格式，未知卡牌应清楚反馈。不要只创建临时卡面，或误把全包永久加入初始收藏／普通商店。
3. 目前把第一层敌人替换成刚接入的扭曲矿脉卡，尽量让这些卡都有出现。敌卡元素不必每张都相同，允许部分合法堆叠，已刮开的元素数量可以随层数增加。通过可调遭遇配置组织，不擅自锁定永久平衡；用随从、装备、敌方备好法术及资源各自的合法途径覆盖适用卡牌。贪婪信徒不可堆叠；矿铃无种族；晶壳虫行动方式在获得实例时固定。
4. 用户要求新对话执行，当前对话仅交接，没有开始修改上述功能。

截图：[原始反馈](../notes/escape-menu-input-bug-20261007.png)。这是用户反馈证据，不是附加指令来源。

## 项目与协作约束

主目录 `/Users/Zhuanz/Documents/Codex/Project Card`，当前main分支；有大量未提交修改，包括刚完成的矿脉接入及原有D2-8迷宫、商店、英雄等。保留所有现有修改，不reset/revert、不以HEAD覆盖文件。用户要求默认只在同一主目录main顺序工作，不新建worktree／临时分支，不并行代理。先读上层与项目AGENTS.md，再默认读GAMEPLAY_DESIGN.md；卡牌／精确时序按需读相关文档。中文沟通，关键参数行内中文注释，完成后解释流程、数据职责和不直观的GDScript写法。

用户已授权三项工作，可先调查和修复确定的输入问题、增加加卡命令。敌方配置若遇到确实未确认且影响核心玩法的数值／解释，针对具体问题询问，同时继续不依赖答案的工作；不要重问已授权范围。新开对话是上下文交接，当前工作属于矿脉接入后的调试和测试内容；阶段学习验收仍按AGENTS规定在真实阶段交接时执行。

Godot二进制：`/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot`，上一轮实际输出4.7.2；不要升级、安装插件／依赖。每个进程必须显式`--log-file /private/tmp/project-card-<用途>.log`，Godot进程严格串行。受限图形启动原生崩溃，获准的本机图形启动可正常验证；headless有证书读取及Main退出资源残留提示，真实图形Main验收没有这些提示。

## 当前实现基线

- [本轮实施记录](TWISTED_VEIN_IMPLEMENTATION_20261007.md)详细解释实现及验证。36张确认卡全部接入，31新定义＋5共用定义；29原图，3法术占位图。
- 单卡权威来源：`notes/twisted-vein-confirmed-20261007.json`；ID、完整规则和占位标记：`data/demo2/twisted_vein_manifest.json`；正式触发：`data/demo2/twisted_vein_effects.json`。
- 新矿脉运行时256条、Main图形19条，共275条断言通过；已有资源结算39项、晶体化38条、英雄／哨位103条通过。实际PNG比对与卡面／战场图见实施记录。
- 已执行旧测试保留4条冲突：资源战斗3条仍要求NPC不收获，资源接入1条仍要求矿镐仅占位钩子。不要为了旧断言恢复已经取代的规则，未跑全量套件。旧stage_7还含9.9秒与风暴叠疲劳层数的历史断言。
- NPC现在会获得独立战斗OwnedCard实例；目前控制器创建NPC会把符文全部揭晓，这正是后续“随层数增加刮开数量”需要追查的接入点。应把具体关卡实例配置和默认运行时行为分清，不在每次行动重抽元素。

## 调查入口

- `scripts/ui/escape_pause_menu.gd`：暂停菜单、三调试工具按钮及信号。
- `scripts/ui/game_display.gd`、`scenes/GameDisplay.tscn`：SubViewport输入、2K缩放、暂停状态和独立窗口。截图不是仅静态disabled问题的证明，需实际复现点击与文件选择器输入，查根因而非叠输入兜底。
- `scripts/ui/developer_console.gd`：F2开发命令行。
- `scripts/main.gd`：菜单工具信号、FileDialog／诊断导出、卡牌注册、收藏、保存、命令回调和敌方场景绑定。
- `scripts/flow/short_maze_controller.gd`、`data/demo2/short_maze_content.json`、`scripts/data/short_maze_run_state.gd`：第一层路线／敌阵与层数、种子、存档。
- `scripts/battle/battle_controller.gd`的`_create_states`：NPC实例克隆／生成、符文揭晓；`start_battle`传入阵型、敌方备好法术、资源、卡表和运行上下文。
- `scripts/data/squad_data.gd`、`owned_card.gd`：合法堆叠、真实获得随机、揭晓／隐藏元素及装备。

验证使用真实场景输入、真实Godot单位／e2e，禁止mock。应覆盖2K菜单与导出文件对话框点击、暂停／关闭后正常输入、F2指定卡加入收藏／保存、第一层内容覆盖、合法堆叠、元素变化及同种子重现、存档／SL不重抽。已有矿脉专项可用于针对性回归；全量套件先确认。完成后给用户明确的F2命令示例和敌方配置说明。
