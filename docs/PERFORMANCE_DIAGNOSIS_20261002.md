# 2026-10-02 卡顿诊断与 Windows 回传工具

已收到Windows实机回传，主要缺陷确认在导出符文资源读取，详见 [Windows实机分析](WINDOWS_PERFORMANCE_DIAGNOSIS_20261002.md)。下文保留正常工程资源加载时的本机测量，供后续减少重复刷新参考。

本轮只增加诊断工具、重复测量入口和报告，没有修改玩法或生产界面的实现，也没有重新导出游戏 EXE。分支为 main；已有未提交改动保留。

## 已测条件与范围

伙伴反馈：Windows、较旧显卡/内存、1080p窗口、最新导出包、约72张收藏卡。CPU/显卡型号由诊断包自动补齐。

本机：Apple M4、macOS、Godot 4.7.2、Compatibility/OpenGL，真实1920×1080窗口，内部1280×720画布。使用72张正式资源定义的实例卡，双方各3个前排、3个后排小队，战斗种子1331915，1倍速；没有模拟战斗结果。收藏组成、阵容与伙伴存档尚未对齐，因此这是代码负担定位，不是Windows帧率结论。

手机视频为720×1280、约29.97fps、25.77秒。可看到翻页、购买和约16小包/16大包的商店；视频不能给出游戏真实帧时间，也不能证明战斗切换与拖动的耗时。默认配置是3/4个卡包，故分别测默认商店与正式随机生成的32包商店。

最初没有完整敌阵、以及替换计时脚本后节点引用未绑定的试跑已排除。下表依据三次完整、有正常战斗过程且无脚本错误的原生测量，第三次使用保存到项目的重复测量入口。

## 结果与归因

| 项目 | 本机实测与结论 |
| --- | --- |
| 收藏翻页 | 同步脚本平均28–29ms，单次最大33–37ms；点击至第一帧绘制34–47ms。已复现短暂停顿。 |
| 战斗开始 | 脚本约50–56ms，至第一帧约60–69ms。其中清理四排卡面临时状态约29–33ms。 |
| 战斗结束 | 结果页同步脚本77–90ms；重建/恢复阵容约54–66ms，保存约3ms。主要负担在UI刷新。 |
| 随从拖动 | 建立新的放置虚影平均约4.2ms、最大7.6–8.6ms；携带目标更新峰值约9–16ms。比装备多出叠放意图、临时席位、虚影和邻近目标快照。 |
| 未刮符文重建 | 同一张三符文随从，未刮时约0.70–0.81ms，已揭晓约0.06–0.09ms；其中单张空白遮罩图像约0.18–0.21ms。新增遮罩是明确的重复成本。 |
| 默认商店 | 商品列表一次重建约10–14ms。 |
| 32包商店 | 一次列表重建约92–100ms；每个卡包可购检查约2.6–2.8ms。重复目录/卡池查询占了大部分。 |
| 纯卡包悬停 | 剔除开店/离店与列表重建后，32包悬停的帧间隔P95约12ms、最大27ms，没有超过33ms。此项没有在M4上复现伙伴的持续卡顿，需要Windows回传数据。 |

卡面重建、第一帧等待和帧间隔是三种不同量。父函数包含子函数耗时，不可相加；`RenderingServer.frame_post_draw` 表示引擎完成绘制，不是屏幕最终呈现的时间。三次原生窗口试验中自动鼠标输入的连续拖动耗时有波动，尤其邻近目标反馈依赖当前指针位置；不将它换算为伙伴设备的帧率。

### 对应代码

- `scripts/main.gd` 的 `turn_collection_page`：先重建12张实体卡，再创建3组六张的翻页快照；半程再创建6张。满页翻一次共创建36个CardView。`_create_page_turn_snapshot` 自身的计时不包括其后加入SceneTree的完整 `_ready` 成本，不能用它单独代表快照开销。
- `scripts/ui/card_view.gd` 的 `_refresh_runes` / `_create_rune_reveal_cover`：每次重建未揭晓槽都重新创建Image、ImageTexture和两份ShaderMaterial。`rune_reveal_cover_style.gd` 的 `create_mask_image` 每次扫描23×23像素；空白刮痕也走相同扫描。
- `scripts/main.gd` 的 `_clear_battle_presentation_for_preparation`：每槽调用 `clear_battle_status` 与 `clear_battle_result_statistics`。`squad_view.gd` 两者都触发刷新。状态清理的一些子方法还刷新符文与数值，因而切换时集中付费。
- `_show_battle_result` → `_restore_battle_result_layout` / `_restore_battle_snapshot`：四排清空并重新添加；新槽随后又清理状态和展示统计。`settle_current_battle` 内部重建收藏，返回后 `_show_battle_result` 再重建一次。结算的两次收藏重建合计约17–18ms，已包含在结算总时间内。
- `_create_shop_offer_tile` → `_can_buy_shop_card_pack`：每包先查询一次定义表，再通过 `_get_shop_card_definitions` 查询一次；`_build_card_definition_registry` 每次枚举资源目录和现有卡牌。资源的 `load` 会复用已加载资源，但目录与字典构造仍重复。悬停函数本身没有调用这些查询，因此不能把列表重建成本算成悬停成本。
- `battlefield_row.gd` 的 `_show_intent_preview` 与 `squad_view.gd` 的 `_ensure_stack_target_snapshots`：创建新的BoardSlot/CardView，未刮随从又带来遮罩成本。装备候选预览不经过同一套随从叠放路径。

## 建议下一轮优化顺序

1. 复用符文节点、空白遮罩图像/纹理和只读材质；只有刮痕或显示状态实际改变时更新。部分刮痕必须按实例与符文槽维护，避免共享可变纹理串卡。
2. 合并战斗阶段切换的卡面刷新；无变化时早退。结算完成全部数据更新后只重建一次收藏；复用可保留的战场视图。
3. 同一次商店刷新共用定义表/候选集合，避免每包重复扫描。离店不必完整重建已经隐藏的商品列表。
4. 随从叠放虚影与颤动快照复用；仅意图或卡面数据改变时重建。
5. 用伙伴同一存档与硬件进行前后对照。对纯悬停，先核对帧间隔、脚本耗时与draw_calls；CPU耗时小但仍卡时再定位驱动/绘制负担，不能只凭“旧显卡”判断。

这些是基于实测的方案，本轮尚未把它们落实到生产代码。

## 发给伙伴的包

成品：`builds/diagnostics/ProjectCard-Windows-Diagnostics.zip`。

解压三个文件到游戏主EXE所在文件夹 → 双击 `Run-Diagnostics.cmd` → 按README顺序操作、每段按F10 → 退出游戏 → 把新生成的 `Diagnostic-*.zip` 发回。包含硬件信息、本次F10日志、游戏引擎输出、每秒游戏进程CPU/内存和本局测试前后存档。没有游戏EXE，配合现有带F10采样器的导出包使用。

采样操作依次为：空闲、翻页、商店进入与悬停、离店与随从拖动、装备拖动、战斗开始至结束。F10日志是累计数组，分析时去掉上一份已采集的前缀；步骤名称需要与伙伴实际操作核对。第一份空闲日志含启动/恢复，不能将其最大值当成纯空闲耗时。原采样器的 `window_size` 是内部画布，实际窗口由伙伴设定；硬件文件中的桌面分辨率也不是游戏窗口。

验证：ZIP结构/UTF8 BOM/文件完整性检查通过；现有Main通过启动环境变量与真实F10输入生成有效JSON。headless退出仍报告已有的2个ObjectDB实例、1个资源未释放，功能校验通过但退出清理并非完全干净。这里没有Windows运行环境，PowerShell的CIM查询、启动和Compress-Archive链路尚未在实机执行；伙伴本次运行用于确认。

## 复测入口与实现学习

输入到结果：`ui_performance_probe.gd` 建立正式显示壳与真实卡牌，按阶段翻页/悬停/携带，并启动自动战斗直至正常结算；每帧记录独立时钟间隔，同时由计时子类记录同步函数耗时。正常游戏不载入这些子类。

数据与脚本：`tests/performance/ui_performance_probe.gd` 负责场景与输入；`profiled_main.gd` / `profiled_battlefield_row.gd` 负责包裹原函数；原始日志写 `/private/tmp/project-card-performance-local.json`，本轮摘要保存在 `notes/performance/2026-10-02-local-summary.json`。Windows端CMD调用PowerShell，后者只在启动进程中设置采样环境变量，等退出后归档；`tools/analyze_windows_performance.py` 读取回传ZIP/目录/JSON并统计F10分段。

写法解释：`extends` 与 `super.函数()` 让测试子类执行原实现，计时不会替换业务结果；`await RenderingServer.frame_post_draw` 测的是操作到绘制完成的等待。Main动态建行时原行已进入树，测试替换脚本后必须重新绑定四个 `@onready` 节点引用，这只发生在新建空行的诊断夹具中。部分函数会同步调用其他被计时函数，故记录是包含关系。PowerShell对已有文件使用 `-LiteralPath`，保证中文/空格路径按完整文件名读取；UTF8 BOM保证Windows PowerShell 5.1正确解析中文。

本机复测（Godot进程串行，显式日志）：

```sh
"/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot" --path "/Users/Zhuanz/Documents/Codex/Project Card" --log-file /private/tmp/project-card-perf-reusable-check.log --script res://tests/performance/ui_performance_probe.gd
```

回传分析：

```sh
python3 tools/analyze_windows_performance.py "/收到的/Diagnostic-日期-编号.zip" --output /private/tmp/project-card-windows-analysis.json
```

原始两轮有效日志：`/private/tmp/project-card-perf-native-final.log`、`/private/tmp/project-card-perf-native-confirm.log`；保存入口验证日志：`/private/tmp/project-card-perf-reusable-check.log`。临时完整JSON会被下一次本机复测覆盖，项目摘要不会自动覆盖。
