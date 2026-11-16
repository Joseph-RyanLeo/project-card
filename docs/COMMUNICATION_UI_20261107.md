# 对白头像与玩法教学（2026-11-07）

## 功能与主要流程

场上可见角色继续从原英雄按钮或卡牌发出气泡；当前画面没有该角色时，左下角出现独立头像。头像先放大，随后复用既有气泡逐字显示台词。气泡先按完整台词确定换行和居中位置，每个字直接出现在最终位置。显示完整后保留3秒阅读时间，再随气泡收起并缩小消失。同一角色连续几句保留头像，换人时先收起上一位。打开Esc期间，头像与气泡隐藏，对白暂停；关闭Esc后接着播放。

现有任务对白已通过原TaskHintOverlay接入，不另建剧情存档或对白队列。角色图优先引用既有CardData.art_texture，使用AtlasTexture裁掉透明留白。圆环后缘和前缘分层绘制，立绘可以探出上缘，下半部由圆环遮住。带透明轮廓的卡图共用这套取景，构图特殊或背景与人物合在一起的素材可单独准备头像。尚无图的角色显示姓名首字，保留角色自己的姓名，不借用其他角色的图。埃德温·尘灰目前的CardData没有art_texture，仍需要后续提供角色图。

非必要教学调用`main.show_gameplay_teaching(key)`。入口先复用原有教学记录与存档事务保存，再把条目交给左上计时横条。横条包括正方形感叹号、小字“玩法教学”和教学标题，正方形边框按顺时针累计进度，入场时提示条放大并渐显，超过正常大小后短暂停顿，再回到正常尺寸并开始计时。默认8秒走满后先放大并停顿，再缩小并渐隐。计时期间鼠标移入提示条会轻微放大，移出回到正常尺寸。点击提示条任意位置可直接打开Esc玩法教学并选中该条目，使用现有暂停所有权；连续提醒排队，已提醒条目不再自动重复。

Esc首页的“玩法教学”提供左侧目录与右侧正文，可查看全部当前已编写的操作／知识教学，并保留旧存档中独有的教学快照。正文优先从现行目录读取，避免规则修改后回看旧版本。剧情台词仍不进入教学目录。

当前必做操作教学继续使用原提示框，按实际操作完成；没有擅自把它们转换成计时提醒。新计时提醒供后续事件明确调用。

## 脚本、数据与入口

- `scripts/ui/task_hint_overlay.gd`：沿用原逐句对白流程，解析当前说话者；找不到可见节点时选择场外头像。`_show_hero_line()`负责进入与开口，`_finish_hero_line()`负责句末停留之后的换人与退出。
- `scripts/ui/character_portrait.gd`：只负责头像、姓名牌和缩放动画。`present()`放大，`dismiss()`缩小。尺寸、位置、时长集中在文件头的中文注释参数中。
- `scripts/ui/hero_speech_bubble.gd`：沿用现有九宫格、原生窗口字体与逐字演出；增加Esc期间固定对白的隐藏与保留，防止头像暂时隐藏被误认为角色离场。
- `scripts/main.gd`：`character_definition()`／`character_portrait()`复用已有卡牌资源；`show_gameplay_teaching()`负责落盘与通知；`_open_gameplay_teaching()`沿用Esc暂停机制。
- `scripts/ui/gameplay_teaching_toast.gd`：只负责通知队列、倒计时、正方形进度和点击信号。`current_key`是当前条目，`progress`为0到1的完成比例，`_queue`存后续条目；它不负责游戏规则与存档。
- `scripts/ui/escape_pause_menu.gd`：`open_teaching(key)`打开目录并定位正文；从菜单主动打开时默认显示第一项。
- `scripts/data/task_catalog.gd`与`data/tasks/tutorial_hints.json`：复用教学标题和正文，新增`teaching_entries()`生成目录，不维护第二份教学文字。
- `ProfileProgress.profile.tutorial.read_hints`／`hint_texts`：继续存教学记录；`run.read_story_nodes`继续独立记录本局剧情。非必要教学在通知实际提交时记录，通知超时不删除条目；存盘失败回滚记录且不弹出通知。战中教学记录同步进入原战前存档，不提交本场未结算的战斗成长。

后续新增非必要教学时，在原JSON目录增加标题与instruction，再在合适事件调用，例如：

```gdscript
# 此示例只演示调用；不要把必要操作教学随意改为非必要教学。
show_gameplay_teaching("tutorial:step:新条目编号")
```

已有任务对白按现有数据填写`speaker`和`text`即可自动使用场外头像。其他脚本也可以直接使用同一展示层：

```gdscript
var dialog := preload("res://scripts/ui/task_hint_overlay.gd").new()
dialog.content = {
    "dialogue": [{"speaker": "后勤机器人", "text": "补给已送达。"}],
    "instruction": "",
    "dim": false,
}
dialog.portrait_resolver = character_portrait
dialog.confirmed.connect(dialog.dismiss)
add_child(dialog)
```

如果角色已有可见节点，可设置`speaker_resolver`回调返回该节点；如果没有CardData，可在对白的`portrait`字段直接提供Texture2D。这里只负责展示；事件自身仍负责原有的剧情时机与保存。

## Godot／GDScript 写法说明

`Tween`按时间修改节点的scale与透明度，因此动画不依赖帧数；头像用底部中心作为pivot_offset，让放大看起来从底部弹出。收起缩到0.01而非绝对零，避免气泡计算相对变换时出现不可逆矩阵。

`await tween.finished`表示等待头像放大完成后再说话，或等缩小完成再换人，不会阻塞游戏主线程。头像、逐字、句间停留分别管理；Esc只冻结对白自己的Tween，保留原有“教学暂停战斗但对白继续”的行为。

`CanvasLayer`提供独立的UI绘制层，让头像不随上下战场镜头移动，并保持在检视与暗幕上方、Esc菜单下方；文字仍沿用原气泡直接在根窗口绘制的方式，保持720p／1080p／2K清晰度。

`Signal`把“玩家点击条目”交给Main处理；通知组件不知道怎么暂停战斗，菜单也不负责改写教学存档。这让两种组件可复用，而不与具体任务绑定。

`AtlasTexture`仅引用原卡图的一块区域，不修改原图片或卡面取景数据。正方形进度使用`draw_line()`沿四条边绘制，`queue_redraw()`仅请求更新当前通知图案。

## 预览与验证

打开`scenes/tools/CommunicationPreview.tscn`，按F6可单独预览场外对白、计时提醒、点击定位和Esc回看；该预览不接触玩家存档。

`tests/communication_ui_test.gd`使用真实GameDisplay／Main、真实鼠标输入与隔离临时存档，检查通知队列、计时、暂停、对应条目、存档往返与失败回滚，以及头像放大／缩小、缺图占位、在场锚点复用与释放；实际窗口截图位于`docs/previews/communication_20261107/`。

执行Godot验证须串行，且每个进程显式传入`--log-file /private/tmp/project-card-用途.log`。

本次结果：新增真实窗口专项25项通过；既有英雄气泡专项33项在固定60帧时间步下通过；既有Esc启动还原专项无断言失败；独立预览场景无窗口加载通过。720p、1080p和2K头像截图已目视检查。普通可变时间步运行既有气泡专项时，截图后的淡出中间帧断言出现时序抖动（分别在1080p／2K出现一次）；未改动原测试断言，固定时间步下确认中间透明度与最终隐藏均正确。原场景仍会报告旧资源UID改用路径加载的警告，Esc既有测试退出时有资源未释放日志；本轮未扩展处理这些既有问题。
