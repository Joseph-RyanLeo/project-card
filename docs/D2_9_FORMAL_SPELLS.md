# D2-9 灰烬征册正式法术

当前运行时仍缺正式准备栏与施法调用链，阶段状态及后续候选见 [2026-09 阶段交接](PHASE_HANDOFF_2026-09.md)。

## 来源与范围

2026-09-23 通过项目既有 Feishu 桥接以只读方式读取指定卡牌审阅表：

- Base：`IcuQbyEQtaPWPgsOOOrcu5shnKh`
- Table：`tbl6qIMmgLoYgMpX`（卡牌审阅）
- 原始链接：`https://my.feishu.cn/base/IcuQbyEQtaPWPgsOOOrcu5shnKh?table=tbl6qIMmgLoYgMpX&view=vewSOt9OTH`
- 目标记录：战斗怒火、并肩作战、重返战场、齐射令；四条记录的审阅状态均为“已确认”。

只读字段和效果组快照保存在 `data/demo2/formal_spells_source_snapshot.json`，没有导出表内其他卡牌或字段。

## 已写入的正式资源

| 卡牌 | 稳定 ID | 品级 | 触发类别 | 效果组 |
|---|---|---:|---|---|
| 战斗怒火 | `battle_fury` | IV | 条件 | `battle_fury.effect.01` |
| 并肩作战 | `side_by_side` | III | 即时 | `side_by_side.effect.01`、`side_by_side.effect.02` |
| 重返战场 | `return_to_battlefield` | II | 准备 | `return_to_battlefield.effect.01` |
| 齐射令 | `volley_order` | I | 准备 | `volley_order.effect.01` |

四张资源位于 `resources/cards/`，`pack_id` 均为 `ash_ledger`，并已加入 `scenes/Main.tscn` 的收藏卡列表。效果定义继续由 `data/demo2/ash_ledger_effect_samples.json` 和 `BattleEffectCatalog` 作为运行时目录来源；资源只绑定确认过的效果 ID，不在资源里重复实现规则。

## 美术状态

四张透明背景像素 PNG 已放入 `assets/card_art/spells/`，并绑定到对应资源的 `CardData.art_texture`：`battle_fury.png`、`side_by_side.png`、`return_to_battlefield.png`、`volley_order.png`。像素尺寸、透明通道和原始比例保持不变。

四张正式法术也已加入 `scripts/tools/card_art_tuner.gd` 的 `CARD_RESOURCE_PATHS` 白名单，因此会按“法术”分类出现在卡面调整器中，可单独调整 `art_offset`。

## 验证

- `tests/d2_9_formal_spell_resource_test.gd`：四张来源快照、字段和效果绑定通过。
- `tests/d2_6b_asset_and_cards_test.gd`：原有 14 张占位法术、素材图集和正式装备回归通过。
- `scenes/Main.tscn`：无窗口加载通过。
