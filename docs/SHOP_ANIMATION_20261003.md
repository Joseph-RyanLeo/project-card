# 商店轮播、检视往返及开包前半段

## 1. 从输入到结果

购买失败仅更新状态说明，保留陈列和暗卡轮播。购买成功后，只移除售出节点、刷新余额与资格；其他商品继续使用原节点并平滑补位。真正刷新商店、更换商品内容才替换对应卡面。

右键检视明卡、暗卡、卡包或贴纸包：读取商品图片当前的画布变换，隐藏原图，合成大图从原位置放大到基础4倍；取消时沿反向动画回到原图，再恢复原图。暗卡只复制已经脱敏的当前轮播卡面，检视不揭晓身份。

左键买包：既有购买函数验证余额、资格或工具箱容量，完成入库、扣款、售出标记和存档；只有成功后才从该包位置放大。放大0.25秒、停留0.12秒，然后套用战斗死亡材质溶解，主体0.5秒、边缘0.56秒。动画结束回到商店。此阶段奖励仍按照既有流程直接入收藏／工具箱，尚未制作逐张展示的后半段；溶解只是暂代效果。动画期间的重复点击和关闭不重复提交交易。

## 2. 脚本和数据职责

- `scripts/main.gd`：`_refresh_ordinary_shop_panel` 保留原容器及未变化的商品；比较商品快照，仅移除售出或改变内容的节点。`_on_ordinary_shop_offer_pressed` 只在成功交易后刷新陈列；`_open_shop_pack_inspection` 统一包装检视与开包起点，`_dissolve_purchased_shop_pack` 仅修改视觉材质。`_close_card_inspection` 同时支持卡面与包装回退。
- `scripts/ui/shop_offer_view.gd`：`_reflow_offset` 和 `animate_reflow_from` 让商品图与静态价格一起横向补位；悬停仍只改变图片的纵向抬起与旋转。
- `scripts/ui/shop_pack_stack_view.gd`：移除售出包、重新排列剩余包并保留原节点，堆叠价格独立补位。
- `scripts/ui/shop_card_view.gd`：原计时器继续轮播，`continue_carousel_from` 只复制公开卡面的轮播帧及渐变材质。
- `scripts/ui/inspection_card_surface.gd`：沿用原生小画布合成、倾斜与光栅；包装溶解复用其纹理，避免截取整个窗口。
- `ordinary_shop_service.offers`、`run_reward_state.gold`、`owned_card_collection` 和工具箱库存仍是实际商品、余额及奖励数据；动画不承担这些数据的结算。

可调参数（声明处均有中文注释）：

- `scripts/main.gd` 顶部：`SHOP_INSPECTION_OPEN_SECONDS=0.25`、`SHOP_PACK_OPEN_HOLD=0.12`、`SHOP_PACK_INSPECTION_SCALE=4`。
- `scripts/ui/shop_offer_view.gd` 顶部：`REFLOW_SECONDS=0.24`。
- 暗单轮播仍为 `scripts/ui/shop_card_view.gd` 的 `CAROUSEL_HOLD=0.7`、`CAROUSEL_FADE=0.35`。
- 溶解直接沿用 `scripts/ui/squad_view.gd` 的 `DEATH_DISSOLVE_*` 常量；更改这些共用常量也会改变战斗死亡效果。

## 3. 不易理解的写法

容器会自行管理商品的逻辑位置。如果直接对商品节点的 `position` 做 Tween，下一次容器排版会覆盖它。因此先同步容器最终排版，用排版前后的位置差补偿商品的可视子节点，再把补偿量插值到0；固定的命中区域和悬停动画保持各自职责。同步 `NOTIFICATION_SORT_CHILDREN` 是让容器在当前帧立即排版，避免先跳到终点再回到起点的闪跳。

`get_global_transform_with_canvas` 包含父节点和显示画布的变换；乘以检视层变换的逆矩阵，将商品位置、比例和旋转转换到检视层。`basis_xform(PADDING)` 让透明留白也随同旋转，保证起点对齐。

`set_parallel(true)` 让移动、缩放和暗幕同时播放；`chain()` 在这些变化结束之后才开始停留和溶解。材质的参数先用 `set_shader_parameter` 初始化，再用 Tween 插值，避免参数尚未注册导致动画无法启动。

卡面的 `@onready` 引用要等节点入树后才能访问，所以暗单形态同步安排在 `add_child` 之后。轮播拷贝的定义已脱敏，不访问真实隐藏属性或交易随机流。

## 验证

专项脚本 `tests/d2_7_shop_animation_test.gd` 使用真实窗口输入、真实商品、真实存档，以及无法写入的路径验证回滚。覆盖轮播不重建、服务购买、四类商品放大回退、存档失败不播放、两类包装溶解、重复点击及奖励仅发一次。既有包装关闭验收仅调整等待新增动画完成的时间，保留原验证条件。此专项已加入串行工具 `tools/validate_d2_7.py`。

本轮串行运行六组原生窗口专项：新动画45项、紧凑布局23项、包装表面26项、层级与隐藏信息62项、商店润色24项、叠包12项，最终合计192项通过，最终日志无Godot脚本错误。没有运行全量套件；尚未在伙伴的Windows硬件上验证本轮新动画。叠包测试同步系统鼠标与模拟输入，避免真实指针在等待动画期间覆盖测试位置，未修改原有验收条件。
