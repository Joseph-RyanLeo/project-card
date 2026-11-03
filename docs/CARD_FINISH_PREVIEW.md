# 五种卡面工艺预览

当前入口是 `scenes/tools/CardArtTuner.tscn`。在右下方工艺选项中切换普通卡、闪卡、全息闪卡、法线闪卡、碎闪和超框卡。关闭“材质”开关可临时对照完全关闭光影的原画。

2026-11-03起，工艺参数可通过顶部“保存工艺参数（全局）”持久化到`resources/ui/card_finish_settings.tres`，由真实卡面共用；各工艺取景仍独立保存到CardData。碎闪纹理密度现为15，详见[本轮光泽与保存修复](D3_3_FINISH_FEEDBACK_20261103.md)。工艺选择、3D和材质开关仍为预览状态。2026-10-27起开包已接入单卡实例、存档和两维独立随机获取，详见[开包罕贵度接入](PACK_CARD_APPEARANCE.md)。既有 I—V 品级仍按原规则工作。

## 2026-10-27：正式特殊卡放大模糊修复

特殊卡以4倍SubViewport合成动态光效。此前`InspectionCardSurface`只把外层TextureRect设为最近邻，新建内层SubViewport仍默认为线性过滤；原图先在内层被混色，外层再用最近邻无法恢复。普通卡1倍时不明显；数值字和部分图标显式指定最近邻，因此截图中这些区域清晰而人物、卡框和名字框模糊。

`scripts/ui/inspection_card_surface.gd`的`_setup_content()`现明确设置`viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST`。这是该离屏画布内未独立指定过滤方式的节点默认值，不是降低画布精度；源图保持硬像素，4倍光带、材质计算和独立线性阴影贴图继续保留。调整器自身场景此前已指定最近邻。

`tests/card_finish_sampling_test.gd`使用真实影步刺客、月华树人，关闭光效隔离采样，检查1:1立绘在4倍画布中每个原像素对应的4×4块同色；背景按窗口缩放，不将其误当成1:1像素块。随后将同一实例切为线性过滤作为GPU反例，最后恢复工艺并输出完整卡面。12项通过、0失败，日志`/private/tmp/project-card-card-sampling-final.log`；18种外观组合GPU回归187项通过，日志`/private/tmp/project-card-card-sampling-finishes.log`。对比图`/private/tmp/project-card-sampling-shadowstep_assassin.png`与`/private/tmp/project-card-sampling-moonlight_treant.png`均为左线性、右最近邻。未运行全量套件。

## 输入到画面

调整器将鼠标位置转换为 -1～1 的方向，再指数平滑。同一份方向交给整卡透视和内层材质，避免人物、背景与卡框倾斜不同步。

- 普通卡：保留原画与图标，不添加法线、投影或闪面材质。
- 闪卡：复用已有白光、金光、彩虹扫光。
- 全息闪卡：人物、卡框与背景共用同一相机、倾角和旋转方向；从前到后为卡框、人物、背景；人物与背景都在卡框后方，背景更远，转动时由真实的前后平面距离产生视差和远近缩放。细密交叉压纹与虹彩随方向反光。景深控制前后距离，不需要完整3D角色模型。
- 法线闪卡：优先读取现有 `art_normal_texture`。未提供时，从透明轮廓与亮度梯度生成自动浮雕，并叠加细纹。自动结果不是角色真实几何法线；精细压纹仍需要匹配的美术贴图。
- 碎闪：在合成后的整张卡上使用固定 Voronoi 晶片，覆盖人物、背景、卡框、卡名、符文及属性图标，保留原有透明轮廓。改变鼠标方向时各片分别亮暗，返回原方向得到相同图案。降低纹理密度可观察大块镜碎。
- 超框卡：按原尺寸和原取景位置绘制透明人物立绘，放到插画框上方、名字及属性下方。裁切限制在卡牌外轮廓内，允许延伸到完整符文板块；符文与说明层保持在人物上方。

全息与法线在人物和背景层处理，不会染色覆盖上方的名字、属性或符文；碎闪在整卡合成后处理，各区域共用连续的碎片图案。

前后层使用与外层相同的旋转矩阵、视野角和画布坐标。Shader将外层卡框平面的取样射线求交到不同深度的平行平面，再把结果合成后交给现有整卡投影；内层不额外旋转，不会叠加成双倍角度。正面姿态补偿远近缩放，保留原尺寸与取景。默认景深2.5对应人物在卡框后25px、背景在卡框后60px；这里是虚拟空间距离，不是人物直接平移25px。鼠标向右时人物相对卡框向左偏，背景向左偏更多；上下方向同理。背景与原图保持同倍率，不再使用放大裁切或预留取样余量。内层只保留深度偏移，整体透视由外层统一处理；移动后超出原素材的窄边沿用素材边缘像素，避免为了遮空而放大整幅背景。全息背景先生成同尺寸的显示副本：从不透明像素向透明角逐层延展颜色，避免把原素材的透明圆角拉成深色方块。副本按源纹理缓存，不在鼠标移动时重建；其他工艺使用原始纹理，原图片不改写。关闭“3D”时三层一起停止几何变换，材质反光仍可观察。

从闪卡开始，五种工艺的行动、生命、护甲、种族／类别和冷却／热诚图标统一使用法线明暗、高光与轮廓投影；普通卡不启用这些效果。法线按原图透明轮廓和亮度生成，阴影随同一光源反向移动；黑色描边保留。数值字形仍在图标上方绘制。

图标颜色继续最近邻取样，阴影单独使用带1px透明边的线性取样纹理。两者共用最近邻会使阴影随细微鼠标位移整像素跳动；透明边则避免线性取样到边界时被硬裁切。`tests/card_finish_shadow_motion_test.gd` 对正式图标和材质进行64步真实GPU扫光，限制相邻帧最大单像素透明度跳变。

图集图标先提取独立小图交给材质，避免法线或投影读到相邻图案；原节点纹理不替换。所有预览统一采用4倍合成采样，画布额外保留3px投影安全边；原画保持最近邻取样，逻辑坐标和4倍显示尺寸不变。

## 各工艺取景保存

普通卡继续使用 `CardData.art_offset`；其他五种卡面使用 `art_finish_offsets` 字典，保存键依次为 `foil`、`holographic`、`embossed`、`fractured`、`overframe`。旧资源没有这些键时沿用原取景，无须迁移卡牌文件。修改普通卡前会固定其他工艺继承的旧位置，因此六种卡面始终可独立调整。

调整器切换工艺时回填它自己的X/Y。所有修改先进入本卡草稿；“保存修改”保存已编辑字段与各工艺各自的取景，按工艺逐项合并磁盘新资料；“保存到所有罕贵度卡面”把当前X/Y统一写入本卡全部六种工艺，同时保存资料，不影响其他卡。批量保存后仍可分别调整。名称与基础属性继续是本卡共用数据。

卡面显示使用一次性的资源副本，将当前工艺坐标交给原有 `CardView.art_offset` 流程；草稿保留完整工艺位置字典。这样不需要把美术预览选择写入战斗实例。

## 代码职责

- `scripts/tools/card_art_tuner.gd`：控件、参数、按工艺独立编辑取景及普通／批量保存、现有鼠标平滑以及合成采样倍率。
- `scripts/data/card_data.gd`：工艺位置字典、旧取景默认值和独立／统一位置的读写方法。
- `scripts/ui/card_finish_preview.gd`：调整器、真实卡牌和开包检视共用的双维度材质控制器，管理内层材质及超框层级。每张卡使用独立材质实例；调整器原有六项入口映射到同一套配置。
- `shaders/card_art_finish.gdshader`：前后深度平面的投影补偿、专用／自动法线及图层材质。
- `shaders/card_projection.gdshaderinc`：整卡与内层共用的旋转矩阵，防止角度和方向不一致。
- `shaders/card_badge_relief.gdshader`：五种工艺共用的图标法线与投影；几何只扩展阴影绘制范围，不改变节点布局与命中。
- `shaders/card_finish.gdshaderinc`：全息压纹与碎片反光的共用数学函数。
- 既有 `shaders/card_preview_3d.gdshader`：合成后的整卡透视、扫光及覆盖所有区域的碎闪。

`RefCounted` 控制器不是新场景，由调整器持有；超框节点实际挂在卡牌下，随卡牌释放。Shader 的 `uniform` 是GDScript传给GPU的参数。Voronoi 给每个像素找到最近的晶片中心；固定哈希让晶片的形状与反光方向稳定，不会每帧重抽。

## 参考与适配范围

- [Pokémon Cards CSS](https://github.com/simeydotme/pokemon-cards-css)：参考多种反光、纹理和分层展示的视觉方向；本实现未复制其CSS或宝可梦素材。
- [Holo Card Studio 网页源码](https://github.com/EverettFish/holo-card-studio/blob/main/assets/web-holographic/app.js)：参考人物／背景按观看方向产生相对位移的组织方式，未引入其Blender、Three.js或生成流水线。
- [Godot 2D全息卡](https://godotshaders.com/shader/2d-holographic-card-shader/)：可选法线、渐变与噪声纹理的原生参考。
- [Animated Glitter](https://godotshaders.com/shader/animated-glitter/)：细碎闪光参考；本实现的晶片按鼠标角度驱动，不按时间随机变动。

五种工艺均已有实现路径，没有缺失教程的阻塞。需要继续美术打磨时，主要补充匹配角色的手绘法线、专用压纹／碎片图案，以及超框专用取景，而非更换引擎或安装插件。

## 验证

`tests/card_finish_visual_test.gd` 使用实际图形渲染，检查五种工艺、共用相机与倾角、前后深度、正面取景不变、3D开关同步、专用法线、缺图卡、切换恢复及源资源隔离，输出 `/private/tmp/project-card-five-finishes.png` 对照图和 `/private/tmp/project-card-holo-window-depth.png` 三姿态图。校准平面沿用正式背景颜色并去除素材四角自带的透明度，以便检查几何是否额外露空；另用余烬侍从与未去除透明度的正式背景，检查四角补齐、极限视差、普通卡恢复及源纹理不变。固定大小的紫红标记用于测量全息背景与原图是否同倍率、鼠标移动时图案尺寸是否稳定，允许最多1个显示像素的取整误差。须以图形模式运行，不能用空渲染器替代画面验收。

自动运行Godot时必须显式指定 `--log-file /private/tmp/project-card-<用途>.log`，并串行执行。既有调整器回归入口是 `tests/card_art_tuner_preview_regression_test.gd`，资料编辑与保存回归入口是 `tests/card_art_tuner_editor_test.gd`，使用真实临时资源验证六种取景独立保存、跨卡切换、磁盘合并与批量按钮。


## 2026-10-27：收藏悬停显示罕贵度

### 整体流程

收藏卡悬停改为与商店单卡一致的检视式透视，取消向上抽出7像素及平面旋转轻晃。鼠标在固定原卡范围中归一化为方向，经原`InspectionCardSurface`平滑后同时驱动整卡倾斜与罕贵度材质；普通、银／金／彩闪、法线、碎闪以及全息／超框组合均沿真实OwnedCard显示。移开平滑回正后归还原卡，快速移入另一张时立即归还旧卡，始终最多一张活动显示副本。2026-10-28起该副本常驻复用，休眠时隐藏并停止离屏更新。

真实收藏CardView保持在原槽第一子节点，位置、缩放及输入区域不变。悬停只重新绑定同一份只读CardView快照，引用同一OwnedCard，不新发卡、不重新抽工艺；源卡临时透明但继续接收输入。点击携带、原生拖动、右键检视、禁止拖拽、重建／翻页与离树均停用显示副本并恢复源卡。原悬停描述切换同步到倾斜显示。

### 关键数据与脚本

- `CardView._set_collection_hover()`／`_stop_collection_hover()`负责借用共享显示层、恢复透明度与归还；静态`_collection_hover_owner`限制只有一张活动卡，替换旧7像素悬停位移。战场和服务卡继续沿用其原有反馈。
- `scripts/ui/collection_card_hover.gd`继承`InspectionCardSurface`，只组织快照、固定原卡坐标和显示生命周期，复用透视、最近邻采样、鼠标平滑、法线与各工艺材质。
- 快照按原卡保存显示状态并设`set_snapshot_mode(true)`，禁用交互、新卡标记和再次悬停；`showing_effect`改变时才同步刷新，不每帧重建CardView。所有拥有实例、卡图取景、数据保存仍归原流程。
- `GameDisplay.get_collection_hover_surface()`持有唯一显示层，首批收藏准备好后预热一次。CardView、SubViewport及材质实例在切卡时复用，不给每张收藏卡创建画布。休眠时禁用SubViewport更新与卡面处理。
- 快照用`copy_snapshot_from()`一次绑定卡牌定义、OwnedCard及运行时显示数据，只刷新一次。图标小图、补边阴影与全息背景副本按源纹理缓存，切卡不反复读回、生成相同贴图。
- 显示层直接挂在GameDisplay窗口画布，由原卡的全局变换乘上RenderContainer变换对齐。整卡投影直接按窗口实际像素执行，内层卡面至少4倍采样，超过4倍输出时按需提高。1280×720逻辑界面和原卡命中保持原流程；原图、图标仍最近邻，独立阴影保持线性。

### 初学者需要理解的写法

显示副本不等于复制一张游戏卡：`set_owned_card()`传入的是同一OwnedCard引用，收藏容器不变；快照只隔离显示节点。原卡透明依然保留固定GUI命中，因此不会因透视边缘变化反复触发进入／离开。

`get_global_transform_with_canvas()`获得原卡所在逻辑画布的完整变换，再乘显示容器变换换算到窗口像素；最后乘`-content_padding`包含阴影安全边。`Transform2D * Vector2`是在变换位置，包含平移、缩放及旋转，不能只用`position - padding`代替。`call()`用于运行时加载显示脚本的方法调用，避免CardView与持有CardView的检视脚本相互预载。

`returning`表示鼠标离开后的回正阶段，沿用同一指数平滑，接近零时才恢复原图；拿起或打开大检视时直接停用共享层，保证虚影和拖拽预览仍只有原来的实例来源。


验证：`tests/collection_card_tilt_test.gd`在最终720p及2K各186项通过、0失败；覆盖18种外观、鼠标反向倾斜、原位命中、描述同步、回正清理、点击携带、原生长按拖拽、右键检视与重建释放。日志为`/private/tmp/project-card-collection-tilt-final-720.log`及`/private/tmp/project-card-collection-tilt-final-2k.log`。既有`return_origin_ghost_20261025_test.gd`50项通过、0失败，日志`/private/tmp/project-card-collection-tilt-return-regression.log`。旧stage_4中的悬停抬起断言已按新规则更新，本轮未运行该整个大脚本或全量套件。真实画面为`/private/tmp/project-card-collection-tilt.png`。Godot进程串行且各自显式指定日志，测试存档／诊断使用隔离临时路径；原场景UID回退提示保持记录。


### 2026-10-28：复用与实际分辨率验证

旧路径即使使用4倍卡面采样，整卡投影仍先落在1280×720主画布，2K窗口再最近邻放大，因此倾斜轮廓和动态光效也变成2×2重复像素；每次悬停新建节点和贴图又增加首帧停顿。新路径保留源图最近邻，只将悬停动态画面改为窗口像素输出，并复用同一个显示层。

预热使用主画布后方的完整不透明绘制，而不是极低透明度，避免渲染器直接跳过而没有准备GPU管线。`await RenderingServer.frame_post_draw`表示等真实一帧绘制完成，再隐藏预热层。菜单、转场或大检视开启时立即归还原卡，防止窗口层盖住逻辑画布内的弹窗。

`tests/collection_card_resolution_test.gd`实际GPU专项22项、0失败：连续8次悬停保留相同节点、画布和材质；使用完全相同的卡面纹理、投影材质对照新旧绘制目标，旧路径2×2混色块为0，新路径为8351；关闭透视和光效后1:1原画像素仍是同色2×2块。另覆盖720p、1080p、2560×1440窗口与当前显示器2940×1846自适应全屏的坐标、倍率及暂停遮挡。日志`/private/tmp/project-card-collection-resolution-warmed.log`，对比图`/private/tmp/project-card-collection-resolution-compare.png`左旧右新。

同次运行移入到首帧约33毫秒，随后7次约16–18毫秒；此前首次约66–70毫秒，重复约17–45毫秒。这是本机输入到绘制完成的观测，含等待下一帧，不能当作纯脚本耗时或所有机器的保证。共用材质GPU回归155项、归位虚影50项通过；最终2K悬停交互186项覆盖18种外观及原生操作，日志`/private/tmp/project-card-hover-pool-final-2k.log`。未运行全量套件。


### 2026-10-28：未悬停时保留闪卡亮纹

此前原生CardView只配置了整卡材质参数，没有承载整卡合成纹理的绘制节点；全息和图标自身材质能显示，银／金／彩闪的整卡光带只有悬停／检视时才实际绘制。现在未悬停使用一个轻量TextureRect叠加静止光带，沿用同一亮纹函数和检视默认参数；普通、法线及碎闪卡不额外添加这种光带。

流程：OwnedCard提供卡面工艺 → CardView刷新工艺控制器 → 未合成时显示静态亮纹；进入悬停后源卡整体隐藏，由已有共享显示层绘制动态光带；回正归还后显示原静态亮纹。没有为静止收藏卡增加SubViewport、逐帧更新或整卡截图。

关键职责：`CardView._finish_surface_composited`明确区分“只有材质参数”与“材质已挂到外层合成纹理”；`CardFinishPreview._refresh_rest_flash()`管理静态光层；`_get_rest_flash_mask()`按卡框填满插画窗口，并合并外伸属性图标的透明轮廓，按布局缓存。`shaders/card_rest_flash.gdshader`与`card_preview_3d.gdshader`共用`card_finish.gdshaderinc`里的`card_flash_light()`，避免两套光带算法偏移；合成表面停用内层静态光带，避免双重增亮。

初学者写法：`blend_add`表示只向原画加上反射光，纹理仅作透明度遮罩，不重新采样或模糊原画；光层继承卡牌调制透明度，虚影依旧半透明。`static Dictionary`由不同控制器共享缓存，布局相同的卡牌复用同一遮罩，不是在每张卡上存一份完整画面。

验证：`tests/collection_rest_flash_test.gd`在真实2K收藏检查18种组合、普通卡隔离、GPU静止亮纹差异、节点／遮罩复用、无逐卡Viewport、悬停接管及回正恢复，73项通过；日志`/private/tmp/project-card-rest-flash-gpu-2.log`。实拍`/private/tmp/project-card-collection-rest-finishes.png`每列依次为普通／银／金／彩／法线／碎闪，每行为普通／全息／超框卡图。18种正式检视GPU回归187项通过，日志`/private/tmp/project-card-rest-flash-combinations.log`；未运行全量套件。

## 2026-11-03：基础图鉴普通材质与全局工艺保存

无OwnedCard的基础图鉴在绑定检视表面后也必须刷新为普通卡面／卡图，不能因无实例提前返回并保留默认扫光。全局工艺配置独立于单张CardData，调整器顶部提供保存／重载入口；碎闪密度15，其他工艺独立保留。根因、操作、脚本职责、实际截图与5组408项GPU验证见[修复说明](D3_3_FINISH_FEEDBACK_20261103.md)。
