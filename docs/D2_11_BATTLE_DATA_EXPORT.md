# D2.11 战斗诊断数据导出

## 导出入口

战斗结算面板上的“导出战斗数据”按钮打开系统保存对话框，默认保存为 UTF-8 JSON。记录只在当前进程中保留；开始下一场战斗时会替换为新记录。采集器直接订阅控制器事件，独立于最多显示 100 条的战斗日志缓存。

## JSON schema 1

- `schema_version`: 导出格式版本；当前为整数 `1`。
- `metadata`: 项目名与版本、Godot 版本、导出时间、SHA-256 内容指纹，以及无法从运行时确认的构建号、Git commit 和工作区状态。未知信息使用 `"unknown"` 和对应的状态/原因字段，不能把未知写成空字符串或猜测值。
- `battle`: 单局冻结记录。`initial_states` 和 `final.states` 用 `cross_run_alignment_key` 对齐同一编队位置与卡牌组合；`timeline` 按 `sequence` 保存效果结算、效果追踪和整数化/小数余量结算。来源对象含稳定卡牌/OwnedCard/纹章/伤势身份；无法映射的来源保留状态与原因。
- `capture_status`: 事件计数、是否完整、是否截断。当前采集不设 UI 日志的 100 条上限；若将来新增采集限制，必须把 `truncated` 置为 `true` 并给出 `truncation_reason`。

公式事件保留原始基值、加项、牌型/元素/其他乘数、最终平加和精确值。`action_value_modifier_sources` 与 `reinforcement_modifier_sources` 给出构成行动值的活动修正及其来源，`immediate_action_source` 记录即时行动入口。分数小数余量和实际提交的整数结算分别记录，避免把理论公式结果误认为已应用的整数变化。

初始和最终 RNG 状态覆盖 BattleController 与效果运行时各自的生成器；`random_sources_complete` 当前明确为 `false`，因为游戏外的全局随机入口没有纳入战斗 RNG 快照。内容指纹仅覆盖 metadata 中列出的实现文件，不代表整个资源目录、Godot 导入产物或 Git commit。

## 格式兼容约定

读取端应按 `schema_version` 选择解析规则，忽略未知的可选字段，并把显式 `unknown`/`available: false` 视为未知数据。新增可选字段保持 schema 1；删除字段、改变字段类型/单位/语义、改变时间线条目含义或稳定对齐键规则时必须递增 schema 主版本，并在本文件补充迁移说明。兼容旧数据时由读取端判断，不在导出时悄悄改写旧 schema。

要把实现回移到旧版游戏，必须取得那个版本真实且指定的源目录或 commit/ref，并单独比较其控制器事件、公式与序列化接口。不能只凭“旧版”名称推测其目录或 API。
