# D2-10 普通纹章与影蔽／休眠运行时审计

当前实现范围、未闭环接口和阶段交接见 [2026-09 阶段交接](PHASE_HANDOFF_2026-09.md)。

## 本批实现状态

| 项目 | 状态 | 运行时入口与复用的既有执行器 |
| --- | --- | --- |
| 火把·耀眼 | 已实现 | `_register_formation_emblems()` 读取显现纹章实例，注册 `dazzling`；攻击主目标沿用 `choose_base_target()` 的耀眼权重，治疗／防御目标池不改写。 |
| 斗篷·影蔽 | 已实现 | 同一注册链路写入 `emblem_shadow` 与 `shadow_until = 战斗时间 + 15`；按已确认的行动或实际伤害提前撤销；到期仍由确定性战斗时钟处理。副效果不调用主目标过滤。 |
| 火腿／烤火腿／火腿面包 | 已实现 | 开战 `RUSH` 窗口按实例添加强化 modifier；`_build_action()` 将旧强化写入公式，随后按 modifier_id 消费；不写 OwnedCard 永久成长。 |
| 奶酪／奶酪面包 | 已实现 | 复用 `_apply_emblem_rush_effects()` 和 `BattleSquadState.charge_action_cooldown()`，不建立第二套计时器。 |
| 三明治 | 已实现 | 复用 `_get_adjacent_allies()` 的同排相邻规则；每枚实例分别叠加邻军强化与充能。 |
| 苹果／苹果派／烤苹果 | 已实现 | 复用纹章周期事件与战斗时间轴；治疗进入现有治疗上限、禁疗与归属结算。 |
| 金苹果 | 已实现 | 周期护甲生成 `ARMOR` 事件，经过现有护甲增益事件（包含铁砧翻倍）；静态基础护甲不走该事件。 |
| 脑死亡 | 已实现 | 伤势目录与飞书 `贴纸/纹章和伤势!N11:P11` 已登记“突击：强化+8，回响：休眠15秒”；运行时按显现伤势槽的 `脑死亡`／`brain_death` 身份注册，开战／复活沿用 RUSH 调用，普通行动发射后沿用 ECHO 调用，休眠每次回响刷新为当前战斗时间+15秒。 |
| 贪婪 | 已登记，运行时待确认 | 已从飞书 `贴纸/纹章和伤势!N31:P31` 写入本地目录与目标审阅表；效果为“数值始终为1，战斗中获得金币时获得等同于原始数值+5的强化”，触发次数、原始数值取值与强化归属仍待规则确认，本批不擅自接入战斗执行器。 |

## 本批补齐的混合与触发纹章

| 项目 | 状态 | 运行时入口 |
| --- | --- | --- |
| 改造 | 已实现 | 显现实例注册运行时造物种族，保留原种族；种族判定统一走 `BattleSquadState.has_effective_race()`。 |
| 四叶草Ⅰ／Ⅱ／Ⅲ | 已实现 | 真实 ECHO 事件按实例投掷 1d4，成功添加强化；Ⅲ 的首次致命硬币免死在伤害事件结算前消费，失败也记录，复活不重置。 |
| 盾牌Ⅲ | 已实现 | 基础护甲仍走静态属性；每个显现实例保留一次近战免疫，经过伤害事件前置拦截，复活不重置，消耗后卡面变暗。 |
| 刺盾 | 已实现 | 基础近战实际命中后读取受击前护甲，返还 `2+护甲×0.1` 直接生命伤害；返还事件不会再次触发刺盾。 |
| 火焰剑 | 已实现 | 复用耀眼关键词；RUSH 时把本小队最右侧可见符文（含贴纸）写入战斗临时覆盖，不改 OwnedCard。 |
| 天选之子 | 已实现 | 结构化定义标记概率取优，预留统一骰子入口；未把它扩展成全局目标或金币重投。 |
| 金币／金币袋／宝藏 | 已实现 | 每次真实 LAST_WISH 生成奖励账本记录；复活后的再次阵亡可再次记录，结算服务按 `battle_instance_id` 防重复提交。宝藏额外生成稀有度 I 基础纹章独立实例。 |
| 宝石 | 已实现 | 纹章库提供 `get_score_contribution()`，战斗控制器按可见实例提供 `get_emblem_score_contribution()`；当前项目没有最终计分调用方。 |
| 名剑 | 已实现 | 静态基础数值仍由 `STATIC_MODIFIERS` 提供；基础攻击命中前额外摧毁主目标1点护甲。 |
| 种子／树 | 已实现 | 种子在战斗结束前写入 OwnedCard 进度账本，第三场原槽进化为树；树的相邻保护通过共享保护次数和伤害前置事件消费。 |

## 数据、实例与结算边界

纹章实例由 `BattleController._register_formation_emblems()` 从每张卡的显现槽建立，保留 `OwnedCard`、`instance_id`、槽位和所属小队；遮挡槽不注册，来源卡以外的可见纹章仍注册到该小队。定义只放在 `EmblemLibraryData.BATTLE_EFFECTS`，状态保存在 `BattleSquadState`，战斗变化通过 RUSH／ECHO／伤害／LAST_WISH 事件进入运行时，战后持久变化统一写入已有 owned-card 与奖励账本。

本批所有计数都按实例保存，刷新布局不会重新登记；临时强化、治疗、护甲、保护和符文覆盖都不写永久卡面。准备预览、结算恢复、存档和重试沿用快照与结算日志，避免重复累加。

## 本轮验证安排

用户已确认本轮暂不启动 Godot 测试。后续定向验证命令沿用单进程、显式 `--log-file /private/tmp/project-card-<用途>.log` 约束，需覆盖每种新增效果的真实注册触发、遮挡、非来源卡、多实例、退场／复活、战后重开和无 `SCRIPT ERROR` 检查。
文档上方的 29 项 PASS 是前一批既有实现的历史结果，不代表本轮新增效果已经执行测试。

## 注册、遮挡与实例身份

`BattleController._register_formation_emblems()` 和 `_register_formation_wounds()` 在战斗快照建立后扫描每个小队的显现槽。遮挡槽不注册；行动来源卡以外的可见纹章仍注册到所属小队。每条注册都保留 `OwnedCard`、纹章 `instance_id` 或伤势槽实例身份。布局重算只更新逻辑位置，不重新注册。

强化消费使用 `BattleModifierContainer.get_active_modifier_ids()` 快照并按 modifier_id 移除，因此同名纹章按实例叠加，重算不会重复消费或重复添加。回响、友军行动后等后置事件产生的新强化不在本次行动快照中。

## 影蔽与休眠来源审计

| 来源类别 | 本地找到的来源 | 持续／解除实现 | 资料状态 |
| --- | --- | --- | --- |
| 纹章 | 斗篷 | 15秒确定性战斗时钟；按确认条件提前撤销 `emblem_shadow`；副效果仍可命中 | 持续时间与提前解除已确认；不套用月亮3秒恢复 |
| 指示物 | 月亮 | 现有 `moon_restore_time` 固定3秒，行动后启动且再次行动不刷新 | 已在 `GAMEPLAY_DESIGN.md` 与 `celestial_indicator.gd` 确认；不套给斗篷 |
| 伤势 | 飞书源表 `贴纸/纹章和伤势!N11:P11` 已确认脑死亡；稳定标识符单元格为空 | 运行时兼容 `脑死亡`／`brain_death` 显现槽；RUSH 强化+8，ECHO 每次刷新15秒休眠 | 规则已确认；保留兼容别名避免旧存档或显现槽身份失配 |
| 卡牌、英雄、装备、法术、其他指示物 | 当前代码与本地目录未找到可确认的影蔽或休眠来源 | 不新增猜测性注册 | 待后续资料 |

休眠状态保存在 `BattleSquadState.sleep_source_until`。休眠单位保留数值与冷却，但战斗时间轴不推进其冷却，也不会进入普通行动选择；到期由同一确定性时钟清除。暂停、倍速和分帧只改变推进调用，不改变触发次数。

## 结算检视遮挡修复

结算统计节点位于 `SquadView.stack_feedback_layer`，卡面检视覆盖层位于 `Main`。检视打开时沿 `source_view` 父链找到 `SquadView`，显式调用 `set_battle_result_statistics_suppressed(true)` 隐藏底层统计；关闭、重开战斗、准备阶段切换时恢复。卡面 pattern label 继续复用原有 suppression 入口，没有调整 z-index。

## 定向验证

命令（串行，显式日志文件）：

```text
'/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot' --headless --path . --log-file /private/tmp/project-card-d2-10-refresh2.log --script res://tests/d2_10_emblem_battle_effects_test.gd
```

真实 `BattleController` 场景结果：29 项 PASS，包含可见／遮挡注册、非来源卡、真实选敌、耀眼与影蔽重叠、副效果命中、斗篷行动/受伤提前解除与15秒到期、强化行动消费、脑死亡突击／回响休眠刷新、奶酪充能、三明治邻接、多实例、周期治疗、死亡退场、复活与金苹果经铁砧护甲翻倍；无 `SCRIPT ERROR`。

项目导入解析命令：

```text
'/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot' --headless --path . --log-file /private/tmp/project-card-import-final.log --import --quit
```

脚本解析通过。日志仍有环境级 macOS 证书／编辑器设置写入提示，不是项目 `SCRIPT ERROR`。

同批回归：`d2_8_emblem_static_modifier_test.gd` 0 failures；`d2_7_inspection_interaction_test.gd` 0 failures；`stage_7_basic_auto_battle_test.gd` 通过，包含结算统计、重开、死亡退场与复活入口。

## 待确认问题

1. 目标多维表已新增并在线读回确认“脑死亡”（`recvw3fof2M2Vx`，已整理）与“贪婪”（`recvw3fof2trqs`，初版待确认）两条记录；源表的稳定标识符列目前为空，因此运行时继续兼容 `脑死亡` 与 `brain_death` 两种身份。源表名称共70条，目标表原有68条，本次缺口为这两条，接口读回时新增候选为0。
2. “贪婪”的触发次数、原始数值取值与强化归属仍待确认，未纳入本批战斗运行时实现。

## 本轮交互与显示补充

- 战斗卡面从 `BattleSquadState.get_runtime_rune_overrides_by_card()` 注入本场符文覆盖；`CardView` 的符文图标、元素贴纸和活动帧共用同一临时元素，不写回 `OwnedCard`。
- 收藏翻页快照按同一顺序的 `OwnedCard.instance_id` 重新绑定，保留纹章、状态和效果面显示；刷新只重建显示，不重复注册或修改实例。
- 收藏卡悬停 `0.25s` 后切换描述，描述模式把符文行透明度降到 `0.20`；拖拽、叠卡预览和离开命中区会取消延迟并恢复原模式。参数在 `scripts/ui/card_view.gd` 的 `effect_rune_dim_alpha`（`0.0～1.0`）和 `hover_effect_delay_seconds`（`0.05～1.0`）脚本导出项中，修改后重启场景即可读取。
- 卡牌检视新增显式“显示符文/显示描述”按钮；长描述放入侧栏说明框。纹章库进入检视时保存全局位置、缩放、旋转、层级和滚动位置，沿现有 Tween 放大并在关闭时反向恢复，动画期间禁用拖拽。
