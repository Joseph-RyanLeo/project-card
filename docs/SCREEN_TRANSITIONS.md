# 加载动画与主页面转场

## 一、从点击到新画面

原先“开始游戏”在一次输入回调里同步实例化 Main、建立界面和收藏、初始化迷宫，再读取或创建存档。执行期间主线程不能绘制下一帧，因此会看到短暂停顿。大部分游戏资源已经预加载，不能把这段耗时全部当作磁盘读取。

现在先用0.18秒把旧画面压到全黑，显示行走人物和“正在加载……”，让加载画面真正绘制出来，再创建游戏。正式入口将 Main 初始化拆到多帧：场景结构、数据和战斗控制器、剩余界面及迷宫分别推进。迷宫新局本就会重建收藏和阵容，因此不再先渲染随后立即清空的开发用收藏／敌阵。存档恢复和新局保存仍复用原事务，完成后等待必要的显示刷新，隐藏加载人物，以0.24秒逐渐亮起游戏。加载人物最短展示0.35秒，避免轻微加载时一闪而过。

仅主菜单／游戏往返和独立工具进出使用同一黑场转场入口。黑场期间输入被拦截，不能重复新建或切换页面。游戏内的天赋和路径选择、事件继续、商店进出、开战、自动进入结算、下一天和上下移动视角均不添加全屏黑场，继续使用原演出；卡牌检视、开包、工具箱和暂停／存档弹窗也保留原行为。

## 二、各脚本与数据的职责

- `scripts/ui/screen_transition.gd` 是全屏 CanvasLayer，负责遮罩、动画和输入拦截。`busy` 表示正在转场；`is_covered` 表示已经全黑；`FADE_OUT_SECONDS`、`FADE_IN_SECONDS`、`MIN_LOADING_SECONDS`、`WALK_SCALE` 是带中文说明的可调参数。
- `resources/ui/loading_walk.tres` 保存 Godot 原生 SpriteFrames。用户的47×76 GIF被无损拆出六张透明PNG，原文件不修改；首帧50ms，其余各100ms，不引入GIF播放插件。
- `scripts/ui/game_display.gd` 创建全局黑场层。`change_screen()` 组织“先淡出、执行动作、再淡入”；开始按钮由 `_request_start_slot()` 调用分帧版本的 `start_slot()`；`last_startup_timings` 记录实例化、初始化和存取档耗时，供排查卡顿。
- 单独运行 Main 或卡面调整器时，更换整个场景使用 `ScreenTransition.change_scene()`；临时黑场挂在场景树根窗口下，等新场景就绪才淡入，不随旧场景一起销毁。
- `scripts/main.gd` 的 `frame_budgeted_startup` 由正式入口开启，`startup_complete`／`startup_completed` 告知显示壳何时可以恢复存档。独立开发场景保留同步初始化。正式入口等初始化回调结束后再读档，读档成功才捕获启动快照，避免将半成品或新局占位状态当作还原基准。
- Main 的 `change_screen()` 只将工具页面的切换交给显示壳；迷宫、事件、商店和战斗的原处理函数继续直接运行，不经过黑场层。

## 三、容易陌生的 Godot 写法

`await get_tree().process_frame` 会把后续代码留到下一帧；它不会创建工作线程。节点和场景树仍在 Godot 主线程中安全操作，动画则有机会在阶段之间更新。它也不保证某个很重的单步绝对不卡，继续优化时应看具体阶段耗时。

`await RenderingServer.frame_post_draw` 等待当前画面真正完成绘制，确保“先看见加载动画，再初始化”；无窗口测试没有实际画面，所以只在图形运行时等待此信号。

`Callable` 表示一个稍后执行的函数，`.bind(...)` 把参数一起带上。转场层用 `await action.call()` 执行传入函数：同步事务直接完成，分帧初始化则等待其全部完成，然后才淡入。

`CanvasLayer` 让遮罩绘制在分辨率菜单和内部游戏视口之上，覆盖整个窗口。`PROCESS_MODE_ALWAYS` 和 Tween 的 `TWEEN_PAUSE_PROCESS` 让暂停菜单返回主界面时，黑场依然能播放；`set_ignore_time_scale(true)` 保持转场使用真实时长。

`SpriteFrames` 保存每张纹理及相对持续时间，`AnimatedSprite2D` 负责循环。动画速度为每秒10帧，第一帧相对时长0.5，其余为1，所以对应50ms与100ms。

## 验证

`tests/screen_transition_test.gd` 使用真实开始界面、主场景、天赋／迷宫和战斗控制器，检查菜单／工具全黑后切换、加载帧更新、重复请求隔离、暂停中返回菜单和读档失败后的恢复，并确认游戏内的天赋、事件、开战、结算及下一天均不触发黑场。`tests/transition_scene_change_test.gd` 验证整个场景被替换时，临时遮罩依然能淡入并在结束后释放。

`tests/start_menu_test.gd`、`tests/game_display_test.gd` 分别检查三档存取／删除与各分辨率／工具入口；测试通过转场完成信号等待新画面，而非假设一次点击后一帧内完成。
