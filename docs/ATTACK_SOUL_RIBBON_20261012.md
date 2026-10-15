# 灵魂光带攻击特效

## 使用方式

游戏中按 Esc → 攻击特效调试器 → 选择行动类型 → 应用灵魂光带预设 → 保存全部配置。

也可以直接把“攻击特效样式”切为“灵魂光带”，保留自己的其他外观参数。每种行动分别保存样式，不会把所有攻击一起替换。旧默认样式继续保留。

预设包含弯曲路径、细尾宽头、白色亮芯、3像素轮廓，以及命中后尾迹继续进入目标的吸收过程。预览头尾颜色只用于调试，正式战斗继续读取原有元素颜色。

本次参考：[《五星地牢》灵魂光带制作演示](https://www.bilibili.com/video/BV1x4hk6CE7S/)。借鉴的是曲线、带状轮廓、像素化与吸收思路，轮廓由项目自己的 Shader 生成。

## 1. 从输入到画面的流程

调试器中的控件修改当前行动的草稿 → 渲染器采样攻击方到目标的贝塞尔曲线 → 创建带状网格 → Shader 按飞行进度显示一段光带。

头部到达目标后，命中只触发一次；虚拟飞行进度继续推进，但目标后方的光带被裁掉，因此剩余尾迹逐步进入目标。总播放时间结束后释放特效节点。

“保存全部配置”把草稿写入 `user://battle_attack_effects.cfg`。正式战斗与调试器调用同一个渲染器、读取同一套配置，因此没有独立的预览版本。

预设保留播放时间、变速强度、拖尾长度和头尾柔化，这四项会参与既有命中时刻计算。手动改变它们仍会按照项目原有规则改变弹道命中时间。

## 2. 主要文件、变量和函数

- `scripts/battle/battle_attack_effect_profiles.gd`：保存样式清单、参数范围和默认值。`make_soul_ribbon_profile()` 在当前配置上应用光带外观预设；`mask_kind = soul_ribbon` 表示使用光带。
- `scripts/tools/attack_effect_lab.gd`：`_drafts` 保存每种行动的草稿；`_apply_soul_ribbon_preset()` 应用预设并刷新控件；`_play_preview()` 使用草稿重播。
- `scripts/battle/battle_attack_trail_renderer.gd`：`sample_curve()` 生成路径；光带的控制点靠近发射端，起点和终点固定在攻击方、目标中心。`play()` 创建网格与材质，并沿用暂停、倍速、一次命中和结束清理。
- `shaders/battle_energy_beam.gdshader`：`soul_ribbon` 选择程序轮廓；`soul_taper` 控制细尾过渡；`soul_core_width` 控制亮芯；`impact_progress` 表示吸收点；`travel_progress` 表示虚拟头部进度。

建议先调整“尾迹高度”“整体弧度”“像素块大小”，再调整收尾指数和亮芯宽度。光带会忽略“首尾延伸”，以免越过目标中心。

## 3. 需要理解的 Godot / GDScript 写法

- `Dictionary.duplicate(true)` 复制配置，避免编辑调试草稿时直接改到共享默认数据。`merge(..., true)` 用预设中的字段覆盖当前值，未列入预设的字段继续保留。
- `ArrayMesh` 是脚本生成的网格。这里沿曲线放置成对顶点形成细长带子；UV 的横向表示沿路径走了多远，纵向表示带子的左右边缘。
- Shader 的 `uniform` 是由脚本传入的参数。Tween 每帧改变 `travel_progress`，GPU 根据它绘制轮廓，不需要为光带创建大量粒子。
- 命中后的虚拟进度允许大于1；目标后方只是不显示，进度仍继续移动，这正是“头到达后，尾迹继续被吸收”的原因。
- 正式战斗的伤害由控制器按逻辑时间结算。渲染器使用控制器传入的命中延迟对齐画面，视觉回调不会决定正式战斗伤害。

## 验证

Godot 4.7.2 下通过原有 `tests/attack_effect_lab_test.gd` 和新增 `tests/soul_ribbon_effect_test.gd`。

新增检查覆盖：预设按钮、当前行动隔离、专用参数实时预览、ConfigFile保存读回、三种变速曲线的命中对齐、暂停、三倍速、命中后吸收、一次命中与节点释放。另以图形模式运行同一检查并输出五个飞行／吸收阶段的真实画布截图，无Shader编译错误。

图形检查命令（每次只运行一个Godot进程）：

```sh
'/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot' --path . --log-file /private/tmp/project-card-soul-ribbon-render.log --script tests/soul_ribbon_effect_test.gd --resolution 1280x720 --quit-after 300 -- --capture
```

截图输出到 `/private/tmp/project-card-soul-ribbon-*.png`。测试只写临时配置快照，不覆盖开发者已保存的特效配置。
