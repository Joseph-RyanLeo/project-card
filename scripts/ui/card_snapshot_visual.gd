class_name CardSnapshotVisual
extends Control

## 把一张正在拖动的 CardView 放进 SubViewport，再显示为单张纹理。
## 这样卡牌及越界图标会作为整体移动，避免分别变换导致像素模糊或裁切。
## 原 CardView 会被移入 SubViewport，所以调用方不能同时再把它当普通场景子节点使用。

const SUPERSAMPLE_FACTOR: int = 2 # 快照内部整数倍渲染倍率；越高越清晰但显存与渲染开销越大

var _source_card_view: Control
var _viewport: SubViewport
var _texture_rect: TextureRect
var _capture_size: Vector2 = Vector2.ZERO
var _card_origin_in_texture: Vector2 = Vector2.ZERO


func configure(
	source_card_view: Control,
	card_size: Vector2,
	output_texture_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_LINEAR
) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_card_view = source_card_view
	var visual_bounds := _calculate_visual_bounds(source_card_view, card_size)
	_card_origin_in_texture = -visual_bounds.position
	_capture_size = visual_bounds.size
	custom_minimum_size = _capture_size
	size = _capture_size

	_viewport = SubViewport.new()
	_viewport.name = "CardSnapshotViewport"
	_viewport.size = Vector2i(_capture_size * SUPERSAMPLE_FACTOR)
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# 拖拽期间只有这一张活动卡使用独立渲染目标。保持实时更新，
	# 可以让右键切换后的效果面与真实卡牌显示保持一致。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	if _source_card_view.has_method("configure_drag_source"):
		_source_card_view.configure_drag_source(false)
	if _source_card_view.has_method("set_snapshot_mode"):
		_source_card_view.set_snapshot_mode(true)
	# 悬停轻晃使用卡牌中心作为旋转支点；快照的整数放大则必须以
	# 捕获区域左上角为支点，否则 2 倍缩放会把卡面推出 SubViewport 并裁切。
	_source_card_view.pivot_offset = Vector2.ZERO
	# set_snapshot_mode() 会先清理交互状态，因此整数放大必须在它之后设置。
	_source_card_view.position = (
		_card_origin_in_texture * SUPERSAMPLE_FACTOR
	)
	_source_card_view.scale = Vector2.ONE * SUPERSAMPLE_FACTOR
	_source_card_view.rotation = 0.0
	_viewport.add_child(_source_card_view)

	_texture_rect = TextureRect.new()
	_texture_rect.name = "FlattenedCardTexture"
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture_rect.texture_filter = output_texture_filter
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.size = _capture_size
	_texture_rect.custom_minimum_size = _capture_size
	add_child(_texture_rect)


# 外部只通过这些查询读取快照纹理、原卡和裸卡在带 padding 纹理中的原点。
func get_texture_control() -> TextureRect:
	return _texture_rect


func get_source_card_view() -> Control:
	return _source_card_view


func get_card_origin_in_texture() -> Vector2:
	return _card_origin_in_texture


func get_capture_size() -> Vector2:
	return _capture_size


func _calculate_visual_bounds(source: Control, card_size: Vector2) -> Rect2:
	var content_min := Vector2.ZERO
	var content_max := card_size
	var card_views: Array[CardView] = []
	if source is CardView:
		card_views.append(source as CardView)
	else:
		for child: Node in source.get_children():
			if child is CardView:
				card_views.append(child as CardView)
	for card_view: CardView in card_views:
		var card_position := (
			Vector2.ZERO
			if card_view == source
			else card_view.position
		)
		var card_min := (
			card_position
			- card_view.get_visual_capture_padding_top_left()
		)
		var card_max := (
			card_position
			+ card_view.card_size
			+ card_view.get_visual_capture_padding_bottom_right()
		)
		content_min.x = minf(content_min.x, card_min.x)
		content_min.y = minf(content_min.y, card_min.y)
		content_max.x = maxf(content_max.x, card_max.x)
		content_max.y = maxf(content_max.y, card_max.y)
	return Rect2(content_min, content_max - content_min)
