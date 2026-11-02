extends InspectionCardSurface

## 一份可复用的收藏显示层，直接在窗口画布绘制；真实CardView始终负责逻辑输入。
var source: CardView
var returning := false
var readonly_pointer := Vector2.ZERO # 只读卡位转入的归一化鼠标位置，不依赖窗口轮询坐标
var read_only := false # 收藏候选与替换对比只借用倾斜显示，不启用局内拖拽与实例编辑
var _display: Control
var _main_host: Node
var _warming := false
var _selection_halo: Control
const REST_THRESHOLD := 0.01 # 倾斜接近正面后归还原图
const MIN_RENDER_SCALE := 4.0 # 只读卡面至少4倍采样，原画保持最近邻；高分辨率窗口按需提高
const DISPLAY_Z := 100 # 高于1倍游戏合成纹理，低于窗口菜单及转场
const WARM_Z := -1 # 在不透明主画布后方绘制预热，避免低透明度被渲染器裁掉而未编译GPU管线

static func bind_read_only(value: CardView) -> void:
	# 命中层跟随原卡倍率；显示层只保留一份，卡内坐标统一归一化为-1～1。
	var shell := value.get_tree().get_first_node_in_group(&"game_display_shell")
	if shell == null: return
	var hover: Control = shell.get_collection_hover_surface()
	var hit := Control.new()
	hit.name = "ReadOnlyHoverHit"
	hit.size = value.card_size
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	value.add_child(hit)
	hit.mouse_entered.connect(func():
		var ancestor := value.get_parent()
		while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
		if ancestor != null and not ancestor.get_global_rect().encloses(value.get_global_rect()): return
		value.show_pointer_hover_feedback()
		hover.setup_collection(value, true))
	hit.mouse_exited.connect(func():
		value.clear_pointer_hover_feedback()
		if hover.source == value: hover.return_to_rest())
	hit.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and hover.source == value:
			hover.readonly_pointer = ((event.position / value.card_size - Vector2(0.5, 0.5)) * 2.0).clamp(-Vector2.ONE, Vector2.ONE))
	hit.visibility_changed.connect(func():
		if not hit.is_visible_in_tree() and hover.source == value: hover.release_collection())
	hit.tree_exiting.connect(func():
		if is_instance_valid(hover) and hover.source == value: hover.release_collection())

func _init() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _initialize_visual(value: CardView) -> void:
	if is_instance_valid(card): return
	_display = get_tree().get_first_node_in_group(&"game_display_shell") as Control
	var visual := (load("res://scenes/ui/CardView.tscn") as PackedScene).instantiate() as CardView
	visual.copy_snapshot_from(value)
	visual.set_snapshot_mode(true)
	visual.configure_drag_source(false)
	add_child(visual)
	render_scale = MIN_RENDER_SCALE
	setup(visual, Callable(), Callable())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = DISPLAY_Z
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	card.set_process(false)

func prewarm_collection(value: CardView) -> void:
	_initialize_visual(value)
	if source != null or _warming: return
	_warming = true
	# 先把常用材质的GPU管线绘制一次，不把首次编译留到鼠标移入。
	z_index = WARM_Z
	visible = true
	position = Vector2.ZERO
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_warming = false
	if source == null: release_collection()

func setup_collection(value: CardView, readonly: bool = false) -> void:
	if read_only: release_collection()
	_initialize_visual(value)
	read_only = readonly
	readonly_pointer = Vector2.ZERO
	source = value
	if read_only: source.modulate.a = 0.0
	_main_host = source.get_parent()
	while _main_host != null and not _main_host.has_method("_get_collection_card_slots"):
		_main_host = _main_host.get_parent()
	card.copy_snapshot_from(source)
	_sync_selection_halo()
	returning = false
	modulate = Color.WHITE
	z_index = DISPLAY_Z
	set_pointer_force(Vector2.ZERO)
	_sync_placement()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true
	set_process(true)

func release_collection() -> void:
	if read_only and is_instance_valid(source): source.modulate.a = 1.0
	if is_instance_valid(_selection_halo): _selection_halo.set_selected(false)
	read_only = false
	source = null
	_main_host = null
	visible = false
	modulate = Color.WHITE
	z_index = DISPLAY_Z
	set_process(false)
	if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(card): card.set_process(false)

func _sync_placement() -> void:
	var physical := source.get_global_transform_with_canvas()
	if is_instance_valid(_display):
		physical = _display.render_container.get_global_transform_with_canvas() * physical
	if get_parent() is CanvasItem:
		physical = (get_parent() as CanvasItem).get_global_transform_with_canvas().affine_inverse() * physical
	position = physical * -content_padding
	scale = physical.get_scale()
	rotation = physical.get_rotation()
	var precision := maxf(MIN_RENDER_SCALE, ceilf(maxf(absf(scale.x), absf(scale.y))))
	if precision != render_scale:
		render_scale = precision
		viewport.size = Vector2i((size * render_scale).round())
		viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * render_scale)
		effect.set_shader_parameter("texture_render_scale", render_scale)

func _blocked() -> bool:
	if CardView.EffectPopup.interaction_blocked(get_tree()) or get_tree().paused or not source.can_process(): return true
	if is_instance_valid(_display) and _display.screen_transition.busy: return true
	if is_instance_valid(_main_host):
		return _main_host._escape_pause_menu.is_menu_open() or is_instance_valid(_main_host._inspection_overlay) or is_instance_valid(_main_host._toolbox_overlay)
	return false

func _process(delta: float) -> void:
	if not is_instance_valid(source): release_collection(); return
	if not source.is_visible_in_tree() or source._left_button_pressed or (not read_only and not source._drag_enabled) or source.is_layout_animating() or source.is_set_as_top_level() or _blocked():
		_finish_hover()
		return
	_sync_placement()
	_sync_selection_halo()
	if returning or not source._mouse_hovered:
		update_pointer_force(Vector2.ZERO, delta)
		if force.length() < REST_THRESHOLD: _finish_hover()
		return
	if card.showing_effect != source.showing_effect:
		card.showing_effect = source.showing_effect
		card._refresh()
	var target := readonly_pointer if read_only else ((source.get_local_mouse_position() / source.card_size - Vector2(0.5, 0.5)) * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
	update_pointer_force(target, delta)

func return_to_rest() -> void:
	returning = true

func resume_hover() -> void:
	returning = false

func _finish_hover() -> void:
	if read_only: release_collection()
	else: source._stop_collection_hover()


func _sync_selection_halo() -> void:
	var original := source.get_node_or_null("SelectionHalo") if read_only and is_instance_valid(source) else null
	if original != null and not is_instance_valid(_selection_halo):
		_selection_halo = preload("res://scripts/ui/card_selection_halo.gd").new()
		_selection_halo.name = "SelectionHalo"
		_selection_halo.size = card.card_size
		card.add_child(_selection_halo)
	if is_instance_valid(_selection_halo):
		var selected: bool = original != null and original.selected
		if _selection_halo.selected != selected: _selection_halo.set_selected(selected)
