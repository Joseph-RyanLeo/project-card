# D2-6C 七项问题：原因与 Luna 操作流程

本文件依据用户 2026-09-30 提供的五张截图及七项修复要求制定。用户已授权全部修复、九张资源牌默认加入收藏，并明确要求新建 gpt-6-luna 聊天执行。沿用“整批完成后集中审查”，不逐步停工索要确认。

## 已核对的原因

1. 下一场敌方还显示统计、准备阶段玩家还显示统计：Main._on_continue_next_level_pressed() 清空战斗控制器、隐藏右侧结算框，却没有清理四排 SquadView 的 _battle_result_active 和战斗卡面临时显示。start_battle() 同样没清理旧统计。SquadView.clear_battle_status() 与 clear_battle_result_statistics() 是两个已有接口，应复用，不能只隐藏右侧结算框。
2. 已消耗资源仍在收藏：BattleSettlementService 已按战前资源部署删除 OwnedCard，但 Main.settle_current_battle() 成功后直接 _build_collection_cards()，未 _sync_legacy_collection_cards()。UI 的 CardData 数组仍含已删除资源，_get_owned_card_for_collection_index() 找不到其 OwnedCard，所以产生可拿起但无法合法部署的幽灵卡。修复数据同步，不以禁用拖拽或每关补发资源掩盖。
3. Esc 菜单被统计穿透：SquadView._ensure_battle_result_overlay() 的统计层 z_index=4093，而 Main._build_escape_pause_menu() 设菜单4090；这些同属一个画布，统计层高于模态菜单。需要整理已有层级，菜单遮罩和按钮都高于统计，且不超过 Godot 的合法范围。不默认新建额外 CanvasLayer；如需改画布，必须同时验证进入调试器时 Main 隐藏不会遗留模态层。
4. 从资源卡右上角拿起时图标离鼠标远：ResourcePreparationTray._map_card_grab_to_shape() 在 shape 某轴只有一个坐标时，直接使用99×136卡面的 grab_local 减中心，偏移可达49.5/68像素，远大于35×32单格。CardDragPreview 又把种类图标放在拼图质心减抓取格/偏移处。需区别卡面抓取和板内抓取，保证转换后指示物跟随当前鼠标。
5. 九张资源未默认加入：Main.tscn 的 collection_cards 静态初始列表没有资源；卡面调试器 CARD_RESOURCE_PATHS 也没有九张资源。调试器已有“资源”类型筛选，复用即可。

## 必须遵守的边界

- 开始核对 cwd 与 main；只在主目录顺序修改，不建 worktree/分支，不提交、不上传、不新建更多聊天或子代理。
- 保留所有本轮开始时已有变更，特别是 Main.BATTLE_VOLUME_POSITION=Vector2(864,320)、stage8中54/36/+6三个用户既有断言。
- 已确认规则不变：胜负只看随从；普通资源攻击1点、开采秒杀且不耗强化；按小队计算次数；NPC奖励入口无效；部署资源正常结算全部消耗，未部署和新奖励保留；中断回滚。
- 默认加入仅为新运行/初始收藏提供九张实例，每张一张；不可在刷新、下一关或读旧档时自动补齐，否则会重新生成应消耗的资源。不改变旧存档所有权和已有实例形状。
- 不为了通过测试删除/放松既有断言，不运行全量套件；新增针对真实缺陷的单项回归，不用mock。
- 所有 Godot 启动均显式 --log-file /private/tmp/project-card-用途.log，所有测试实例串行。可执行文件用完整单引号路径：
  '/Users/Zhuanz/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'
- 图形 CLI 在普通沙箱会退出134；用 exec_command 的 sandbox_permissions=require_escalated 并说明真实鼠标/截图验收用途，已验证可运行。不要错误转义路径、重复搜索安装或要求用户重新安装。不要使用无法访问的 Codex CUA。
- 不引入依赖、不升级引擎。人工可调参数同排中文注释。

## 操作顺序

### A. 先补复现与生命周期修复（问题1、2、3）

1. 阅读 Main.start_battle、_show_battle_result、settle_current_battle、_on_continue_next_level_pressed、restart_battle、_restore_battle_snapshot，以及 BoardSlot/SquadView 的清理接口与 OwnedCardCollection/结算服务。
2. 在主场景回归中通过真正结算和继续按钮重现：结算后双方有统计与死亡标记；进入下一准备阶段四排恢复正常卡面；再启动第二场没有旧统计/骷髅/压暗效果。包含上一场阵亡随从，不能只测全部存活。
3. 复用已有四排清理入口；若现有函数不覆盖两类状态，补一个清晰的共享准备清理函数，内部调用现有接口。正确调用在下一关与下一场启动的阶段边界；重设卡面和准备属性时使用当前结算后的实例，不能恢复战前值而丢失永久成长或伤势。清理不应抹掉结算阶段应保留的统计。
4. 在结算成功后先同步收藏派生数组，再重建UI；同步应覆盖金币-only但消耗了资源、成长、资源奖励和重复提交路径的正确显示。检查收藏书签/recently_returned_owned_cards 是否残留已删除实例，若实际涉及则按权威收藏过滤，不新造所有权。
5. 验证已部署的采完/未采资源均离开 OwnedCardCollection、collection_cards、实际收藏页（测试筛选资源类别，检查真实CardView的OwnedCard引用）；未部署及奖励资源可真正拖入新关卡。旧存档恢复与中断重开保留其语义。

### B. 层级修复（问题4）

1. 比较统计、卡牌层、特效、检视与暂停菜单有效绘制层。优先把统计层调整至卡面之上、模态菜单之下，使用有意义的常量，避免4093贴近上限叠加父层后截断。
2. 保留暂停菜单遮罩盖住统计的正常暗化效果；结算画面按Esc后，任何统计数字、图标、死亡标记不能绘制到菜单文字或按钮之上。
3. 真实输入验证结算阶段Esc打开、点击调试器入口、返回菜单、Esc关闭仍显示原结算统计；准备与战斗阶段的暂停/检视行为也不退化。取得结算→Esc菜单PNG，不仅比较数值层级。

### C. 鼠标锚点修复（问题5）

1. 复查 CardView.create_drag_visual、CardDragPreview.set_resource_puzzle_mode、ResourcePreparationTray.resolve_drop/_map_card_grab_to_shape、Main._update_card_carry_target 的坐标链。
2. 用户最新要求：拖影转换成资源拼图时，资源种类指示图标中心始终位于当前鼠标上，生命数字紧邻；不以原卡牌中心或拼图质心作为鼠标位置。板上安放后的图标仍按原拼图中心显示。
3. 收藏→拼图的抓取映射避免把卡面几十像素偏移原样带到单格；合理映射至单格范围，落点解析和可视拖影共用同一结果。板内移动仍保留真实抓取格与格内偏移，不重抽形状、不旋转、不破坏原生拖放与点击携带的一致性。
4. 复用现有跨淡动画；转换开始及动画结束都不能让指示图标跳离鼠标。不要通过每帧重建整块拼图解决。
5. 在720p/2K真窗口使用root.push_input经过SubViewportContainer，测试资源卡右上角、左下角和中心拿起后进入资源区；断言图标全局中心距鼠标不超过1个逻辑像素。至少覆盖单格、横向相连、纵向相连形状；native drag与click carry均测。落点/非法拒绝与板内第二格抓取测试保留。保存角落抓取时的真实渲染截图。

### D. 默认收藏与卡面调试器（问题6）

1. 将九张资源按现有Main.tscn初始数组模式追加，保留旧列表顺序，以免索引式初始敌方阵容变化。九张：fire_element_shard、light_element_shard、dark_element_shard、water_element_shard、wood_element_shard、rainbow_gold_ore、crystallized_remains、stone_of_greed、abandoned_toolbox。
2. 同步卡面调试器已有 CARD_RESOURCE_PATHS，复用“资源”类别筛选、选择、立绘预览、art_offset调整、显示描述与显式保存流程。不要给刷新时自动注入九张的新分支。
3. 实例化新Main确认每种资源有一张OwnedCard、合法固定形状，并验证调试器资源列表九张可选且预览真实立绘。验证切换后偏移调整有效，保存只由用户点击触发；测试不得无理由改用户美术偏移。

### E. 验证、文档与面向用户的说明（问题7）

1. 增加或扩展资源生命周期和输入专项测试，运行相关单项：d2_6c_resource_settlement_test、d2_6c_resource_input_test、d2_6c_resource_layout_test、d2_6c_resource_battle_test、game_display_test、d2_7_inspection_display_shell_test，以及既有卡面调试器相关测试（按修改范围选择）。串行、独立日志，发现真实失败先修根因。
2. 注意历史stage8文本/Tween兼容问题与显示测试退出引用警告，不篡改旧断言，不把这些说成全部通过；不做无关修复。
3. 更新 docs/D2_6C_IMPLEMENTATION.md，记录这七项的修复和实测路径。针对默认收藏只作Demo范围说明，不擅改核心获取/消耗规则。
4. 最终一次性告诉用户修复结果、验证与截图，并按AGENTS三层解释本阶段流程、核心脚本/变量、陌生写法。
5. 用户特别要的可调位置必须给准确绝对文件链接、当前常量/函数名、实际行号、坐标系和修改例子：
   - 资源区目前 scripts/main.gd 的 _build_resource_preparation_trays：敌方(1080,0)，玩家(1080,WORLD_SECTION_HEIGHT)，WORLD_SECTION_HEIGHT目前360；世界视角准备时整体y=-360，战场视角y=0。建议将两侧位置提炼为带中文注释的常量，统一使用，方便初学者调整，不能偷偷改变位置。
   - Esc目前 scripts/ui/escape_pause_menu.gd 的 ESCAPE_BUTTON_POSITION=Vector2(926,50)，这是720p逻辑画布坐标；2K经GameDisplay整体放大2x，不能把物理屏幕坐标填进去。
6. 不跨聊天回消息。最终报告直接在本新Luna聊天交给用户；不在子步骤结束后停工，连续完成全部已授权工作。若真权限或引擎阻断，准确报告实际拒绝/错误、已尝试路径与仍未完成项。
