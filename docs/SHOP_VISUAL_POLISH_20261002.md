# 商店展示与刮刀接管说明（2026-10-02）

本文按最后一次确认更新，取代之前“金币图片进入全局字体和卡牌正文”的实现说明。主项目 main 中修改，合作伙伴需使用重新导出的 Windows 包。

## 1. 功能从输入到结果

- 点击商店：建立商品报价视图，桌布与内容整体下落、越过终点后回弹。点击离开：立即停止交易，商店整体向上收起，动画结束再恢复敌方战场和入店前的主视图。
- 商品放在首排；同类同大小卡包及贴纸包继续各自叠放。右上按钮下方为独立服务区，刮刀和撕卡均保持静止。价格与简短服务名称不放进悬停动画节点，只有卡图／包图抬起轻晃。页面不再有商品滚动容器。
- 商品主视图只显示图片和金币价格，取消包张数、包数、保底等底部描述；详细信息留在提示中。商店余额／刷新费／报价使用25×25金币图片与大号卢恩数字整数2倍显示（数字高度28）。服务名称字号20。出售／撕卡原生对话框继续使用普通金额文字，避免改变字体度量。
- 普通卡牌正文回到原像素字体，金额使用普通金币符号；战斗正文、工具箱提示和控制台不用金币图片。金额、报价、存档和随机抽取仍使用原始数据。
- 卡包与纹章包右键只读检视，显示名称，基础倍率统一为4×，继续复用卡牌的鼠标倾斜与光栅。检视不扣钱、不获得商品、不推进随机数。
- 随从检视展开工具箱后，点击刮刀进入行动模式。工具箱刮刀隐藏，原位只剩同轮廓凹槽；鼠标显示同尺寸手持刮刀。移动不刮，左键点击或按住移动才刮，首次有效擦除每槽付一把刀；70%提前揭晓、退出完整揭晓付费槽的规则不变。
- 取消刮刀行动时恢复普通鼠标，手持刮刀飞回凹槽，到达后工具箱刮刀重新出现。关闭检视／收起工具箱时也追踪正在移动的目标位置。

## 2. 关键脚本、状态和可调参数

- `scripts/main.gd`：商店建立与报价刷新、开关动画、包装检视、刮擦付款及手持／飞回流程。`ordinary_shop_open` 控制是否可交易；关闭动画期间面板仍可见，但交易入口拒绝执行。
- `scripts/ui/shop_offer_view.gd`：稳定命中框、可动图片 `_visual`、独立价格节点；服务商品通过 `hover_motion=false` 保持原位。
- `scripts/ui/shop_pack_stack_view.gd`：选择叠包前层、还原层级；价格节点独立于每个包的动画，不随包晃动。每个包仍是独立报价。
- `scripts/ui/shop_price_view.gd`：独立金币 TextureRect + 现有 RuneNumberDisplay；不修改全局主题或卡牌字体。金币 PNG 使用普通纹理导入，已删除旧 GoldText／BMFont。
- `scripts/ui/emblem_library_view.gd` 与 `shaders/scraper_groove.gdshader`：原生59×59刮刀及同纹理轮廓凹槽；`set_scraper_carried` 控制原位显隐。普通工具箱1×，检视4×。
- `scripts/ui/inspection_card_surface.gd`：把卡牌或包装合成到透明 SubViewport，再统一倾斜和扫光。包装无贴纸处理器，保持只读。
- `_rune_scraper_drag_data`：刀头相对鼠标的实际命中形状；`_rune_scraper_visual`：跟随鼠标的图片。判定和显示使用同一工具箱尺寸，不依赖系统自定义光标的大小限制。
- `run_reward_state.gold`、`ordinary_shop_service`、`OwnedCardCollection`：余额、报价和拥有实例；展示更改不改变经济规则。

人工调试位置：

- `scripts/main.gd` 顶部：`SHOP_OPEN_OFFSET=-380`，`SHOP_OPEN_OVERSHOOT=12`，`SHOP_OPEN_DURATION=0.24`，`SHOP_REBOUND_DURATION=0.13`，`SHOP_CLOSE_DURATION=0.22`。
- 同处：`SHOP_BACKGROUND_POSITION=(224,40)`、`SHOP_BACKGROUND_SIZE=(832,306)`；按1280×720逻辑画布填写。`SHOP_PACK_INSPECTION_SCALE=4` 控制包装检视倍率。
- Main 刮刀状态处：`SCRAPER_RETURN_DURATION=0.22` 控制飞回时间。
- `scripts/ui/shop_price_view.gd` 顶部：`NUMBER_SCALE=2`、`GAP=5`、`TEXT_SIZE=20`。
- `scripts/ui/shop_card_view.gd` 顶部：`CAROUSEL_HOLD=0.7`、`CAROUSEL_FADE=0.35` 控制暗单停留和渐变时间，本次没有修改。
- `scripts/ui/shop_pack_stack_view.gd`：`PACK_STEP=28` 控制包的露出宽度。
- `scripts/ui/emblem_library_view.gd`：刮刀位置(14,48)、数量位置(50,111)。

## 3. 不易理解的 Godot 写法

旧方案将金币 PNG 用作 BMFont 页面，导入器会把该 PNG 标记为 `importer="skip"`，使它不能再作为普通 Texture2D 预加载。撤掉 BMFont 后重新导入 PNG，避免整条脚本依赖链解析失败。独立图片节点也不会增加正文行高或改变中文字符度量。

HBoxContainer 把金币与数字排列成金额；卢恩数字内部按原生字形绘制，外围 Control 预留2倍实际宽高，避免 Godot 的容器只按缩放前尺寸挤压它。价格属于商品本身，图片属于可动 `_visual`，所以倾斜和抬起不会传递给文字。

Tween 默认顺序执行。开店先下落再回弹；离店先向上收起再隐藏。快速开关会停止前一个 Tween，避免旧回调把新打开的店隐藏。

工具箱位于检视层时有4倍缩放。`get_global_transform_with_canvas()` 读取这层真实比例，手持图片沿用该比例；刀头命中也读取相同变换。飞回通过 `tween_method` 每帧插值，同时读取凹槽当前位置，所以工具箱在关闭检视时移动也能对齐。透明轮廓凹槽直接使用刮刀自己的纹理，不需另一张易错位的素材。

720p／2K显示壳使用1／2倍整数缩放；1080p仍采用既有1.5倍输出，原图像素尺寸保证针对逻辑画布，非整数窗口输出不等于每个像素占相同整数屏幕像素。

## 验证范围

本轮串行运行专项，没有运行全量套件。原生窗口包装验证26项通过（原图颜色／有效像素、4倍倍率、倾斜光栅、只读关闭、独立购买）；新增紧凑商店验证720p18项、补充明暗单卡及普通金额符号后的2K23项通过，包含20组真实报价布局、静止价格／服务、关闭动画、拿刀及关闭检视飞回。

刮擦回归使用原生刀头的边角轨迹验证“不到70%的已付费槽”，避免更宽刀头在旧轨迹上提前揭晓后清空擦痕掩码，误把合法揭晓判为不能继续刮。最终11项通过；测试释放未安装的预览并等待关闭完成后，退出日志无CanvasItem／纹理泄漏。既有2K展示回归62项通过，包含资源弹窗、Esc／F2层级、四大类暗单轮播、卡牌检视与隐藏符文防泄漏。商店润色回归24项通过，包含叠包遮挡、包装名称、出售窗口字体及快速开关清理。本轮五个最终专项合计146项功能断言通过。

现成脚本：`tests/d2_7_shop_compact_test.gd`、`tests/d2_7_pack_surface_test.gd`、`tests/d2_7_rune_scrape_2k_test.gd`、`tests/d2_7_shop_presentation_test.gd`。每个Godot进程必须显式传 `--log-file /private/tmp/project-card-用途.log`，并串行运行。紧凑布局专项已加入 `tools/validate_d2_7.py`。

## 后续更新

2026-10-03增加轮播状态保留、商品补位、四类商品检视往返和购买开包溶解，详见 [商店动画说明](SHOP_ANIMATION_20261003.md)。包装检视现在有0.25秒放大及0.2秒回退，既有验证等待动画完成后再检查清理。
