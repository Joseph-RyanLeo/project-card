# 卡牌与贴纸归位期间保留原位虚影

## 第一层：输入到结果

贴纸或卡牌在非法位置松手、取消携带，或从服务槽归还来源后，原位置持续显示32%透明度的不可交互虚影，正常亮度的实体执行归位动画。贴纸沿用0.28秒、卡牌沿用0.15秒；到位后才清理飞行图案或虚影，恢复正常显示。

收藏卡、服务卡返回收藏／战场及战场整队回位共用该行为。虚影跟随原布局与镜头，移动中的卡面不会带走虚影。服务槽拿起后仍为空白；普通排版让位不额外出现虚影。全部变化只涉及显示，不新增OwnedCard、不修改库存、小队成员或永久状态。

## 第二层：主要脚本和数据

- `EmblemLibraryEntry.play_return_feedback()`保留原图标并将`self_modulate.a`设为统一虚影透明度，同时创建正常亮度的前景`_return_visual`。`_finish_return_feedback()`负责到位或关闭／中断时恢复显示与清理。
- `CardView.begin_return_ghost()`从当前卡面复制一份只显示的`OriginReturnGhost`，共享同一OwnedCard引用，并复制当前数值、符文及状态显示。`_return_ghost`只记录该临时节点，`clear_return_ghost()`隐藏并删除它。重新拿起、排版被替换或源卡退出场景树时都会清理。
- `Main._animate_collection_card_entry()`覆盖收藏以及服务归还的单卡动画：开始保留来源虚影，实体继续执行原补间，原补间结束后清除虚影。
- `BattlefieldRow._animate_restored_slot_return()`明确请求整队归位留影。`SquadView.animate_from_global_position()`的`keep_origin_ghost`参数只在归位路径打开，为每张成员卡保留一份显示副本；原整队补间完成后统一清理。

## 第三层：需要理解的Godot写法

纹理颜色中的`self_modulate`只影响当前图标，因此可让工具箱原图变淡，而前景飞行图案保持正常亮度。原图在动画中保持可见，结束时恢复透明度，不需要修改任何库存数据。

卡牌虚影使用快照模式的CardView，关闭拖拽和鼠标接收，只复制显示状态。它挂在来源的布局层，而不是移动中的卡面内部：收藏使用原卡槽，整队使用CardVisualLayer上一级。这样既保留原位，也能随世界／镜头平移。源卡的`_exit_tree()`负责清理这个临时兄弟节点，避免源卡先被移走或销毁后留下虚影。

`Tween.finished`用于整队补间结束后的清理；Main中的单卡归位流程等待`is_layout_animating()`结束，再删除来源虚影。普通布局动画沿用原路径，防止一次邻卡让位就生成多份无关虚影。

## 验证

- 贴纸专项217项通过：包含原生拖动、点击携带、归位每帧留影、到位恢复、前景遮挡、出售／撤销及存档。
- 新增卡牌专项`tests/return_origin_ghost_20261025_test.gd`50项通过：收藏非法落点、服务卡归还、双卡整队回位的两种输入方式；验证虚影身份、透明度、禁用输入、布局位置稳定、实体最终与虚影重合，以及永久状态不变。
- 原有服务来源专项`tests/service_origin_revision_20261021_test.gd`40项通过，覆盖真实装备／独立指示物保留、服务属性隔离、原生非法放置及归还来源。三份最终图形日志合计307项通过、0失败，无脚本错误；仍有项目原有的场景UID回退警告。
- 已保存三类归位中途的真实窗口图像到`/private/tmp/project-card-return-ghost-0.png`至`-2.png`，并人工查看收藏及整队画面。
- Godot严格串行运行，均显式指定`--log-file /private/tmp/project-card-return-origin-*.log`；未运行全量套件。
