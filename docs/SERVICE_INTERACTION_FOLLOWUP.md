# 强化、服务槽与法术检视交互修正

## 一、整体流程

强化页仍属于准备阶段，现在允许其他随从正常换位与堆叠；借入事件槽的卡牌保持原位虚影，不能同时操作两份。商店服务页的三个置换槽与单卡出售槽之间可直接拖动，长按原生拖动和单击携带使用相同的目标判断。转移不成交、不重抽符文，也不复制卡牌实例；目标原有卡按已有替换规则归还来源。

服务卡的拖动数据现在使用与临时单卡小队一致的战场引用，使预览仍能找到原 OwnedCard。原先同名卡可能拥有独立战场引用，而服务卡却带着共享定义，创建预览时查找失败会丢失实例，进而把定义符文当作公开卡面显示。修正引用后，预览保持该实例的揭晓状态、固定元素和贴纸。

服务槽卡面直接复用 CardView 的战场轻晃和延迟效果展示，离开、拖起或转移时清理悬停。敌我法术右键则把悬停卡作为检视动画的来源：来源暂时隐藏，中央检视放大，关闭后飞回原处，再按鼠标位置刷新预览；战斗仍保持原来的暂停与只读边界。

## 二、脚本与数据职责

- `scripts/main.gd` 的 `_is_card_service_active()` 只保留商店服务板的布阵限制，不再将强化槽可见视为禁止布阵。`_update_card_carry_target()` 先判断服务槽目标，再处理归还原位；点击携带的提交顺序与之对应。
- `_is_service_card_transfer()` 确认拖动来源确实持有该实例；`_take_service_card_view()` 优先从旧服务槽取出正在使用的卡面。旧槽的 `card_returned` 信号同步清理其记录，目标槽使用原有选择函数登记新的实例编号。
- `scripts/ui/card_service_slot.gd` 的 `take_card_view()` 只移交卡面，`return_card()` 才负责销毁服务卡面并归还原位。前者保留 `service_origin`，所以跨槽之后取消仍能正确回到原收藏／战场位置。
- `scripts/ui/card_view.gd` 的 `_build_drag_data()` 对收藏和服务槽统一使用 `OwnedCard.get_battlefield_card()`；预览的临时 SquadData 与该引用一致，不能再因引用不同而丢失 OwnedCard。悬停沿用 `_play_hover_rotation_punch()` 和 `_schedule_hover_effect_display()`。
- `scripts/ui/spell_preparation_tray.gd` 传出 `_hover_card_popup` 作为检视来源，并用 `inspection_hover_owner` 接入 Main 已有的关闭回调。来源隐藏时暂停悬停更新，防止动画途中提前收回或重新显示卡面。

## 三、容易陌生的写法

Godot 的 Resource 可以内容相同但引用不同。`SquadData.get_owned_card(card_data)` 按资源引用查找，不能只看卡名；共享定义和某张同名卡的战场引用不是同一个键。OwnedCard 保存实际符文与揭晓状态，CardData 只提供共享定义。

`card_returned.emit()` 是通知旧槽已腾空，不表示销毁 OwnedCard。实际永久删除仍只发生在确认出售、提取或置换成交时。`call_deferred()` 让旧槽刷新等当前卡面移交完成后执行，避免刷新过程把正在转移的节点再重建一遍。

`inspection_hover_owner` 是来源卡面上的元数据，Main 在检视关闭后将鼠标位置交回所属托盘，复用现有资源预览的清理流程，而不是再写一套检视位移动画。

## 验证

- `tests/service_drag_followup_test.gd` 使用真实卡牌、服务板、原生拖动与点击携带，检查同名实例的符文覆盖、出售槽／置换槽互拖、槽间移交、悬停反馈、数据不变，以及强化页换排与堆叠；图形窗口验证36项通过。
- `tests/spell_inspection_motion_test.gd` 通过真实两天迷宫战斗产生敌方法术队列，使用图形窗口与鼠标检查敌我法术检视的来源、移动放大、返回、暂停与只读状态；29项通过。
- 两项交互测试均需图形窗口：托盘和布阵反馈会逐帧读取真实鼠标位置，无窗口模式的合成输入不足以验证这类命中与动画，不应以其结果代替图形验收。
- 已有 `tests/service_origin_revision_20261021_test.gd` 图形回归40／40项通过，覆盖借用、归还、装备关联、出售撤销、强化与重新部署；收板按钮断言已按现行规则更新为“关店后无板时禁用并显示暗图”，保留原坐标检查，不改按钮逻辑。
