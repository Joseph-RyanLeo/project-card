# Chat Summary 2026-07-05

本文提炼自 2026-07-05 与 Codex 的项目讨论，用于保留 Project Card 的早期语境、设计来源和协作约定。它不是逐字聊天记录，而是便于后续阅读和继续开发的整理版。

## 项目基本信息

- 项目暂定名为 Project Card。
- 项目目前位于 `/Users/Zhuanz/Documents/Codex/Project Card`。
- 项目还没有正式建立 Godot 工程，处于准备开始编写代码的阶段。
- 游戏类型是像素风格的卡牌自走棋游戏。
- 游戏视角参考《Balatro / 小丑牌》式的 2D 卡牌桌面视角。
- 计划使用 Godot 制作，当前倾向版本为 Godot 4.7。
- 主要脚本语言预计为 GDScript。

## 开发者状态与协作方式

- 开发者目前是 GDScript 初学者。
- 已对 Godot 的类、节点、信号等概念有初步了解。
- 后续希望 Codex 在开发时边教边做，不只给代码，也解释关键设计思路。
- 功能应拆成小步实现，避免一次生成过大的系统。
- 当规则存在多种理解或描述不明确时，Codex 应主动提问。

## 目标用户与体验方向

- 目标用户是喜欢像素风格的玩家。
- 游戏玩法强调轻量操作，不需要即时反应。
- 核心乐趣来自卡牌、阵容、堆叠、元素符文、牌型和自动战斗的策略组合。

## 文档结构约定

当前项目资料拆分为：

- `AGENTS.md`：给 Codex 和其他 agent 读取的项目协作入口。
- `GAMEPLAY_DESIGN.md`：记录玩法、卡牌、堆叠、战斗和数值草案。
- `docs/VISUAL_REFERENCES.md`：记录视觉参考图和对应说明。
- `docs/images/`：保存从 QQ 讨论记录中转移出来的图片素材。
- `notes/chat-summary-2026-07-05.md`：保存本次聊天的关键信息整理。
- `notes/open-questions.md`：集中保存待确认问题。

## 已保存的视觉资料

QQ 聊天中的 8 张截图已复制到项目内，不再依赖 QQ 缓存路径。

图片路径位于：

- `docs/images/card-minion-full.png`
- `docs/images/card-effect-toggle.png`
- `docs/images/action-icons.png`
- `docs/images/race-icons.png`
- `docs/images/rune-icons.png`
- `docs/images/card-stack-2.png`
- `docs/images/card-stack-3.png`
- `docs/images/combo-config-table.png`

视觉索引见：

- `docs/VISUAL_REFERENCES.md`

当前图片引用保持相对路径，以便项目迁移和版本管理。Codex 右侧预览器可能无法显示相对路径图片，但这不代表文件丢失或引用无效。

## 玩法资料来源

当前玩法来自用户手动输入和 QQ 截图内容，已整理进：

- `GAMEPLAY_DESIGN.md`

其中包括：

- 卡牌类型：随从卡、物品卡、法术卡、资源卡。
- 随从卡卡面结构。
- 行动方式：近战、远程、法术、治疗、防御。
- 元素符文：火、光、暗、水、木。
- 卡牌摆放与两排棋盘。
- 水平堆叠与小队规则。
- 牌型：混乱、对子、三条、两对、葫芦、顺子、同花。
- 元素方向：火灼烧、水扩散、暗连击、木穿刺、光折射。
- 迷宫、探索、普通战斗、Boss 战的暂定流程。
- 准备阶段、战斗阶段、法术释放、失败次数、加时疲劳等规则。

## 飞书表格计划

部分卡牌设计、玩法数值和配置可能存放在飞书表格中。

短期建议优先使用导出方式：

- 导出为 `.xlsx` 或 `.csv` 后放入项目目录。
- 或复制关键表格内容给 Codex。

长期如果需要自动同步，再考虑飞书 API。接入 API 前需要明确权限范围，并避免将 app secret、token 等密钥写入项目仓库。

## Godot 版本备注

用户提到 Godot 是否会给项目更新版本。

当前理解：

- Godot 项目通常不会无感自动升级。
- 使用更高版本 Godot 打开项目时，可能迁移、重导入或改写部分项目配置和资源。
- 正式创建项目前应尽量锁定 Godot 版本。
- 升级 Godot 版本前，应先说明风险并确认。

## 后续建议

- 先确认 Godot 4.7 的具体版本状态和安装情况。
- 建立 Godot 项目骨架前，先决定目录结构和 Git 管理方式。
- 先实现最小卡牌数据结构和卡牌展示原型。
- 再逐步实现符文、堆叠、小队、牌型和战斗结算。
