class_name CardSnapshotVisual
extends Control

# 卡牌内部有向左、向上和向右越出 99×136 裸卡范围的图标。
# 先把这些内容一并收入快照，旋转时才不会把行动、护甲或生命图标裁掉。
const CAPTURE_PADDING_TOP_LEFT := Vector2(8.0, 4.0) # 快照为左侧行动图标和顶部越界内容预留的像素
const CAPTURE_PADDING_BOTTOM_RIGHT := Vector2(5.0, 0.0) # 快照为右侧生命、护甲等越界内容预留的像素
const SUPERSAMPLE_FACTOR: int = 2 # 快照内部整数倍渲染倍率；越高越清晰但显存与渲染开销越大

var _source_card_view: Variant
var _viewport: SubViewport
var _texture_rect: TextureRect
var _capture_size: Vector2 = Vector2.ZERO


func configure(
	source_card_view: Variant,
	card_size: Vector2,
	output_texture_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_LINEAR
) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_card_view = source_card_view
	_capture_size = (
		CAPTURE_PADDING_TOP_LEFT
		+ card_size
		+ CAPTURE_PADDING_BOTTOM_RIGHT
	)
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
	# set_snapshot_mode() 会先清理交互缩放，因此整数放大必须在它之后设置。
	_source_card_view.position = (
		CAPTURE_PADDING_TOP_LEFT * SUPERSAMPLE_FACTOR
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


func get_texture_control() -> TextureRect:
	return _texture_rect


func get_source_card_view() -> Variant:
	return _source_card_view


func get_card_origin_in_texture() -> Vector2:
	return CAPTURE_PADDING_TOP_LEFT


func get_capture_size() -> Vector2:
	return _capture_size
