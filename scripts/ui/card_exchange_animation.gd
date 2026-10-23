extends Control

## 置换提交后的纯展示：三卡居中并排、白色剪影撞合、新卡揭晓、飞入收藏并抖动。
## 拥有权与随机结果由Main提交，此节点只保管临时视觉与Tween。
signal finished
signal landed
const CARD_SCENE := preload("res://scenes/ui/CardView.tscn")
const SNAPSHOT_SCRIPT := preload("res://scripts/ui/card_snapshot_visual.gd")
const WHITE_SHADER := preload("res://shaders/emblem_fusion_white.gdshader")
const SPARKS_SCRIPT := preload("res://scripts/ui/emblem_fusion_sparks.gd")
const CLICK_SPEED_SCRIPT := preload("res://scripts/ui/animation_click_speed.gd")
const CARD_SIZE := Vector2(99, 136) # 合成展示所用裸卡逻辑尺寸
const MATERIAL_SCALE := 2.0 # 三张材料居中并排时相对原生卡面的倍率
const MATERIAL_GAP := 80.0 # 并排材料的裸卡边缘之间的逻辑像素间距
const ARRANGE_SECONDS := 0.34 # 三张材料从槽位放大并移到屏幕中间的时长
const ARRANGE_HOLD_SECONDS := 0.12 # 三张材料并排到位后短暂停留的时长
const PULLBACK_SECONDS := 0.12 # 两侧卡保持原色向外回撤蓄力的时长
const PULLBACK_PIXELS := 12.0 # 两侧卡撞击前向外回撤的距离，以原图1倍像素计，2倍演出时为24逻辑像素
const COLLIDE_SECONDS := 0.35 # 两侧材料加速撞向中间卡的时长，参照GIF约7帧×50毫秒
const WHITE_START_PROGRESS := 0.55 # 前冲时间经过此比例才开始变白，前半程保持原色
const WHITE_SECONDS := 0.06 # 接近碰撞时迅速变白的时长，参照GIF的临近撞击闪白
const FUSION_HOLD_SECONDS := 0.083 # 三张白色剪影在挤压极限停留，较原来增加约2帧（按60帧/秒）
const JELLY_START_PROGRESS := 0.82 # 前冲进入最后18%时开始纵向拉长、横向挤压，在重合时达到峰值
const JELLY_SECONDS := 0.40 # 新卡快速反弹、极限缓停、整体弹大并恢复的总时长；可超过2倍至4倍的放大时长
const REVEAL_SECONDS := 0.10 # 新卡从白色迅速恢复原色的时长，参照GIF约2帧
const EXPAND_SECONDS := 0.24 # 新卡由2倍扩大至4倍的时长，独立于恢复颜色
const SPARK_SECONDS := 0.20 # 重合揭晓时十字闪点出现、向外飘散并消失的时长
const SPARK_SCALE := 3.0 # 复用纹章十字闪点时的显示倍率，使闪点分布在新卡两侧
const DISPLAY_SCALE := 4.0 # 新卡展示的最终倍率
const DISPLAY_SECONDS := 0.65 # 新卡在中央停留供玩家查看的时长
const FLY_SECONDS := 0.50 # 新卡缩小并飞入收藏的时长
const FLY_END_SCALE := 0.22 # 新卡飞入收藏时收缩至裸卡的倍率
const BOOK_SHAKE_OFFSET := 5.0 # 收藏书本整体抖动的最大水平位移
const BOOK_SHAKE_STEP := 0.045 # 收藏书本抖动的单步时长
const BACKDROP_ALPHA := 0.40 # 演出期间背景压暗的透明度

var _tween: Tween
var _click_speed := CLICK_SPEED_SCRIPT.new()
var _book: Control
var _book_rest := Vector2.ZERO
var _materials: Array[Control] = []
var _reward: Control
var _sparks: Control
var stage := &"arrange"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 4000

func _input(event: InputEvent) -> void:
	# 先完成已保存结果的展示，防止鼠标穿透后再次采购或抓取卡牌。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click_speed.register_click(_tween)
	if event is InputEventMouse or event is InputEventKey or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()

func play(materials: Array[Dictionary], awarded: OwnedCard, book: Control, collection_card: CardView = null) -> void:
	_book = book
	_book_rest = book.position
	var center := size * 0.5
	var dim := ColorRect.new()
	dim.name = "ExchangeBackdrop"
	dim.color = Color(0, 0, 0, BACKDROP_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	for index: int in materials.size():
		var entry := materials[index]
		var visual := _make_card(entry.owned_card as OwnedCard)
		visual.name = "ExchangeMaterial_%d" % index
		visual.position = get_global_transform_with_canvas().affine_inverse() * (entry.center as Vector2)
		visual.scale = entry.scale
		visual.rotation = float(entry.rotation)
		visual.z_index = index + 1
		_materials.append(visual)
	_reward = _make_card(awarded)
	_reward.name = "ExchangeReward"
	_reward.position = center
	_reward.scale = Vector2.ONE * MATERIAL_SCALE
	_reward.modulate.a = 0.0
	_reward.z_index = 4
	_set_whiten(_reward, 1.0)
	_effect(_reward).set_shader_parameter("jelly_amount", 1.0)
	_sparks = SPARKS_SCRIPT.new()
	_sparks.position = center
	_sparks.scale = Vector2.ONE * SPARK_SCALE
	_sparks.z_index = 5
	add_child(_sparks)
	_tween = create_tween()
	_click_speed.apply_to(_tween)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for index: int in _materials.size():
		var visual := _materials[index]
		var arranged := center + Vector2((index - 1) * (CARD_SIZE.x * MATERIAL_SCALE + MATERIAL_GAP), 0)
		if index == 0: _tween.tween_property(visual, "position", arranged, ARRANGE_SECONDS)
		else: _tween.parallel().tween_property(visual, "position", arranged, ARRANGE_SECONDS)
		_tween.parallel().tween_property(visual, "scale", Vector2.ONE * MATERIAL_SCALE, ARRANGE_SECONDS)
		_tween.parallel().tween_property(visual, "rotation", 0.0, ARRANGE_SECONDS)
	_tween.tween_callback(func(): stage = &"arranged")
	_tween.tween_interval(ARRANGE_HOLD_SECONDS)
	_tween.tween_callback(func(): stage = &"pullback")
	for index: int in _materials.size():
		var pulled_back := center + Vector2((index - 1) * (CARD_SIZE.x * MATERIAL_SCALE + MATERIAL_GAP + PULLBACK_PIXELS * MATERIAL_SCALE), 0)
		if index == 0: _tween.tween_property(_materials[index], "position", pulled_back, PULLBACK_SECONDS)
		else: _tween.parallel().tween_property(_materials[index], "position", pulled_back, PULLBACK_SECONDS)
	_tween.tween_callback(func(): stage = &"collide")
	_tween.tween_method(_collide_materials, 0.0, 1.0, COLLIDE_SECONDS).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(func(): stage = &"fuse")
	_tween.tween_interval(FUSION_HOLD_SECONDS)
	_tween.tween_callback(_begin_reveal)
	_tween.tween_method(_reveal_reward, 0.0, 1.0, REVEAL_SECONDS)
	_tween.parallel().tween_property(_reward, "scale", Vector2.ONE * DISPLAY_SCALE, EXPAND_SECONDS)
	_tween.parallel().tween_method(_settle_reward, 0.0, 1.0, JELLY_SECONDS).set_trans(Tween.TRANS_LINEAR)
	_tween.parallel().tween_method(_sparks.set_progress, 0.0, 1.0, SPARK_SECONDS).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(func(): stage = &"display")
	_tween.tween_interval(DISPLAY_SECONDS)
	_tween.tween_callback(func(): stage = &"fly")
	var destination: Vector2 = get_global_transform_with_canvas().affine_inverse() * (book.get_global_transform_with_canvas() * (book.size * Vector2(0.5, 0.32)))
	var end_scale := Vector2.ONE * FLY_END_SCALE
	if is_instance_valid(collection_card):
		var card_transform := get_global_transform_with_canvas().affine_inverse() * collection_card.get_global_transform_with_canvas()
		destination = card_transform * (CARD_SIZE * 0.5)
		end_scale = card_transform.get_scale()
	_tween.tween_property(_reward, "position", destination, FLY_SECONDS)
	_tween.parallel().tween_property(_reward, "scale", end_scale, FLY_SECONDS)
	if not is_instance_valid(collection_card):
		_tween.parallel().tween_property(_reward, "modulate:a", 0.0, FLY_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(dim, "modulate:a", 0.0, FLY_SECONDS)
	_tween.tween_callback(func():
		stage = &"shake"
		_reward.modulate.a = 0.0
		landed.emit()
	)
	for offset: float in [-1.0, 1.0, -0.6, 0.6, -0.3, 0.3, 0.0]:
		_tween.tween_property(book, "position:x", _book_rest.x + BOOK_SHAKE_OFFSET * offset, BOOK_SHAKE_STEP).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_finish)

func _make_card(owned: OwnedCard) -> Control:
	# 复用现有卡面渲染，偏移保留越界图标；动画只变换一个整卡纹理。
	var center := Control.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := CARD_SCENE.instantiate() as CardView
	card.set_card_data(owned.card_data)
	card.set_owned_card(owned)
	card.set_snapshot_mode(true)
	var snapshot := SNAPSHOT_SCRIPT.new() as CardSnapshotVisual
	center.add_child(snapshot)
	snapshot.configure(card, CARD_SIZE, CanvasItem.TEXTURE_FILTER_NEAREST, 1)
	snapshot.position = -CARD_SIZE * 0.5 - snapshot.get_card_origin_in_texture()
	var white := ShaderMaterial.new()
	white.shader = WHITE_SHADER
	white.set_shader_parameter("jelly_pivot", snapshot.get_card_origin_in_texture() + CARD_SIZE * 0.5)
	snapshot.get_texture_control().material = white
	return center

func _effect(visual: Control) -> ShaderMaterial:
	var snapshot := visual.get_child(0) as CardSnapshotVisual
	return snapshot.get_texture_control().material as ShaderMaterial

func _set_whiten(visual: Control, amount: float) -> void:
	_effect(visual).set_shader_parameter("white_amount", amount)

func _collide_materials(progress: float) -> void:
	# 三次曲线让两侧卡缓慢起步、越接近中间卡越快；中间卡始终固定。
	var travel := progress * progress * progress
	# GIF前半程保持原色，接近重合时才在约一帧内变白。
	var whiten := clampf((progress - WHITE_START_PROGRESS) * COLLIDE_SECONDS / WHITE_SECONDS, 0.0, 1.0)
	var jelly := smoothstep(JELLY_START_PROGRESS, 1.0, progress)
	for index: int in _materials.size():
		_set_whiten(_materials[index], whiten)
		_effect(_materials[index]).set_shader_parameter("jelly_amount", jelly)
		var offset := (index - 1) * (CARD_SIZE.x * MATERIAL_SCALE + MATERIAL_GAP + PULLBACK_PIXELS * MATERIAL_SCALE)
		_materials[index].position = size * 0.5 + Vector2(offset * (1.0 - travel), 0)

func _begin_reveal() -> void:
	stage = &"reveal"
	for visual: Control in _materials: visual.visible = false
	_reward.modulate.a = 1.0
	_sparks.set_progress(0.0)

func _reveal_reward(progress: float) -> void:
	_set_whiten(_reward, 1.0 - progress)

func _settle_reward(progress: float) -> void:
	_effect(_reward).set_shader_parameter("jelly_progress", progress)

func _finish() -> void:
	stage = &"finished"
	finished.emit()
	queue_free()

func cancel() -> void:
	if is_instance_valid(_tween): _tween.kill()
	if is_instance_valid(_book): _book.position = _book_rest
	_finish()

func _exit_tree() -> void:
	if is_instance_valid(_tween): _tween.kill()
	if is_instance_valid(_book): _book.position = _book_rest
