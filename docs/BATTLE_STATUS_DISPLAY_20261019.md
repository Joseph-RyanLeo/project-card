# 战斗状态显示一致性修复

## 整体流程与原因

动员机兵在突击时通过`IronwallRuntime.grant_temporary_emblem()`给相邻友军的`OwnedCard.emblem_slots`写入本场纹章，满槽时可升级。实际战斗随即读取这些槽位，因此效果生效。新建检视卡也会读取当前槽位。

战场小卡则复用原来的`CardView`节点。原`set_battle_status_slot_states()`只比较耗尽纹章索引与遮蔽伤势索引；两组索引未变就提前返回，漏掉了实例内部纹章新增、升级、移除，以及同类伤势内容变化。现在每次状态同步都进入已有的完整槽位签名比较；内容相同立即返回，内容改变才更新／复用／删除实际图标。没有增加第二份战斗状态。

同时核查了小卡、检视与动画快照的状态传递。检视原先遗漏已耗尽纹章、符文遮蔽和临时元素覆盖，流光也读取战前牌型；现直接取实际战斗状态。动画快照原先遗漏纹章耗尽、伤势遮蔽、受击权重及牌型高亮，现复制这些创建瞬间的显示值。

## 关键数据与入口

- `OwnedCard`：原单卡的纹章、伤势、符文与身份。动员的临时新增／升级通过现有`restore_temporary()`撤销，不改战后规则。
- `BattleSquadState`：本场实际符文元素、遮蔽和有效牌型；控制器另维护纹章耗尽登记。
- `scripts/ui/card_view.gd`：`set_battle_status_slot_states()`请求核对状态；`_refresh_status_slots()`以完整签名避免重复重建；`copy_runtime_display_state_from()`复制动画快照所需状态。
- `scripts/main.gd`：`_open_card_inspection()`从实际战斗状态设置检视；`_refresh_inspection_markers()`采用当前有效符文槽和牌型计算高亮。
- `tests/battle_status_display_consistency_test.gd`：用正式资源和真实主场景开战，检查动员给两个邻居新增／升级、魔像移除、临时纹章撤销与再次新增、余火转火、符文遮蔽、盾牌Ⅲ真实挡伤后耗尽、伤势遮蔽以及快照。

## Godot／GDScript写法

`OwnedCard`是引用对象：修改它内部的`emblem_slots`，对象本身仍是同一个引用。因此仅比较对象是否相同，或者只比较“变暗索引”，无法判断内容是否变化。槽位签名用`duplicate(true)`保存上一次内容的独立副本，下一次才能比较出原位修改；相同内容保持图标节点身份，不打断显示。

临时元素和遮蔽只在`BattleSquadState`生效，检视不能只读原始符文，也不能为显示去改共享`CardData`。这里通过现有读取函数传递显示覆盖，原符文保持不变。

## 验证结果

- 新专项：图形模式52项断言通过；包含实际图案显隐、透明度、纹理和节点复用检查。截图在`previews/battle_status_display_20261019/`。
- 现有`ironwall_battle_test.gd`：381项通过。
- 现有`ironwall_game_integration_test.gd`：23项通过；退出时仍有2个对象与1个资源未释放提示，不能将其视为完整无告警运行。
- 现有`d2_6a_status_slots_and_star_test.gd`：贴纸显示部分13项通过，后续星星传播在第267行访问空指示物数组时中断；不能按脚本打印的“0 failures”将整份测试记为通过，未改动旧断言。
- 无窗口Godot会输出本机证书读取错误；图形专项没有脚本错误。未运行全量测试。

日志分别为`/private/tmp/project-card-status-display-visual.log`、`/private/tmp/project-card-status-ironwall-regression.log`、`/private/tmp/project-card-status-ironwall-integration.log`与`/private/tmp/project-card-status-slot-regression.log`。
