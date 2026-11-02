# 正式卡牌字体

Esc“卡名字体调试”额外提供缝合像素8px／10px黑体风格候选，资源位于 `font_lab/`。来源为 [作者官方2026.10.25发行版](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.10.25)，只提取简体中文等宽TTF和原始许可证，字体未修改。可在固定61×9px区域内对比，再点击“应用到卡牌”保存并用于实际卡名；正文保留原字体。说明见 `docs/CARD_FONT_LAB.md`。

未应用自选卡名参数时，“卡牌显示”模式的卡名与效果文字使用 `chill_7.ttf`（寒蝉点阵 7px），Godot 首选字号为 8。

“弹窗显示”模式默认使用项目内的 `NotoSansSC-VF.ttf`（思源黑体同源的 Noto Sans SC），采用500字重。卡名默认首选9号，区域61×9px；仅名字超宽时缩小。应用调试参数后，两种模式的卡名都使用自选设置。弹窗标题18号、正文16号，直接按实际窗口倍率排版。9px是原生逻辑尺寸，1080p窗口整体放大1.5倍，2K整体放大2倍。

字体来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md)，原文件地址为 `Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf`；下载于2026-10-29，未修改字体文件。授权原文保存在同目录 `NotoSansSC-LICENSE.txt`。工程直接打包字体，避免依赖玩家电脑安装的中文字体。
项目内将这套设计数字统一称为“卢恩数字”：上排是 `pixel_numbers_large.fnt` 大字形，下排是 `pixel_numbers_small.fnt` 小字形。行动值与生命值使用卢恩数字大字形；护甲与冷却秒数使用卢恩数字小字形。

寒蝉点阵原始文件仍保存在用户提供的美术素材目录中；项目内已删除字体选型阶段的其余候选副本。
