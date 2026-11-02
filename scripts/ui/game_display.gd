class_name GameDisplay
extends Control

## 静态游戏使用1280×720逻辑画布；收藏悬停动态层直接按窗口实际像素绘制。
## Main、DesignCanvas与输入继续使用1×逻辑尺寸。

enum DisplayMode {
	WINDOW_720P,
	WINDOW_1080P,
	WINDOW_2K,
	ADAPTIVE_FULLSCREEN,
}

const DESIGN_SIZE := Vector2i(1280, 720)
const INTERNAL_RENDER_SIZE := Vector2i(1280, 720) # 1×内部渲染画幅
const DISPLAY_MODE_POSITION := Vector2(1080, 8) # 显示模式入口放在右上，避开顶栏金币和生命槽
const DISPLAY_FEEDBACK_POSITION := Vector2(650, 46) # 窗口切换提示的逻辑坐标，避开右侧资源板
const INTEGER_SCALE_EPSILON: float = 0.0001 # 判断客户区是否为等比整数倍率时允许的浮点误差
const CARD_ART_TUNER_SCENE: PackedScene = preload("res://scenes/tools/CardArtTuner.tscn")
const BATTLE_LAB_SCENE: PackedScene = preload("res://scenes/tools/BattleLab.tscn")
const ATTACK_EFFECT_LAB_SCENE: PackedScene = preload("res://scenes/tools/AttackEffectLab.tscn")
const PACK_EFFECT_TUNER_SCENE: PackedScene = preload("res://scenes/tools/PackEffectTuner.tscn")
const PACK_RELIEF_PREVIEW_SCENE: PackedScene = preload("res://scenes/tools/PackReliefPreview.tscn")
const CARD_FONT_LAB_SCENE: PackedScene = preload("res://scenes/tools/CardFontLab.tscn")
const RARE_SHOP_LAB_SCENE: PackedScene = preload("res://scenes/tools/RareShopLab.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const PROFILE_DATA = preload("res://scripts/data/profile_progress.gd")
const SLOT_HUB_SCRIPT = preload("res://scripts/ui/slot_hub.gd")
const SETTINGS_SCRIPT = preload("res://scripts/ui/game_settings_panel.gd")
const PREFERENCES_SCRIPT = preload("res://scripts/data/game_preferences.gd")
const SAVE_SERVICE = preload("res://scripts/data/run_save_service.gd")
const START_MENU_SCRIPT = preload("res://scripts/ui/start_menu.gd")
const SLOT_SERVICE = preload("res://scripts/data/run_slot_service.gd")
const TRANSITION_SCRIPT = preload("res://scripts/ui/screen_transition.gd")
const WINDOW_MODE_TRANSITION_MAX_FRAMES: int = 60 # 等待 macOS 退出全屏的最长帧数
const WINDOW_SIZE_BY_MODE := {
	DisplayMode.WINDOW_720P: Vector2i(1280, 720),
	DisplayMode.WINDOW_1080P: Vector2i(1920, 1080),
	DisplayMode.WINDOW_2K: Vector2i(2560, 1440),
}
const DISPLAY_MODE_LABELS := {
	DisplayMode.WINDOW_720P: "720p 窗口",
	DisplayMode.WINDOW_1080P: "1080p 窗口",
	DisplayMode.WINDOW_2K: "2K 窗口",
	DisplayMode.ADAPTIVE_FULLSCREEN: "自适应全屏",
}

@onready var internal_viewport: SubViewport = %InternalViewport
@onready var design_canvas: Control = %DesignCanvas
@onready var render_container: SubViewportContainer = $RenderContainer
@onready var main_screen: Control = get_node_or_null("RenderContainer/InternalViewport/DesignCanvas/Main")
@onready var display_mode_option: OptionButton = %DisplayModeOption
@onready var display_mode_feedback: Label = %DisplayModeFeedback

var current_display_mode: DisplayMode = DisplayMode.WINDOW_1080P
var _window_resize_request_serial: int = 0
var _window_transition_in_progress: bool = false
var _card_art_tuner: CardArtTuner
var _battle_lab: BattleLab
var _attack_effect_lab: AttackEffectLab
var _pack_effect_tuner: Control
var _card_font_lab: Control
var _tuner_source: Control
var _tuner_previous_process_mode: Node.ProcessMode
var _tuner_previous_escape_input: bool
var _rare_shop: Variant
var _rare_shop_previous_main_process_mode: Node.ProcessMode
var _rare_shop_previous_escape_input: bool
var run_slots := SLOT_SERVICE.new()
var start_menu: Control
var _persistence_dialog: AcceptDialog
var screen_transition: CanvasLayer
var _collection_hover_surface: Control
var last_startup_timings: Dictionary = {}
var _slot_progress_panel: Control
var slot_progress: RefCounted
var _slot_checkpoint: Dictionary = {}
var _entering_slot := false
var _preferences := PREFERENCES_SCRIPT.new()
var _settings_panel: Control


func _enter_tree() -> void:
	# 外层仅转发暂停中的卡面检视输入；战斗 Main 仍由场景显式设置为 PAUSABLE。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Main 通过这个分组找到固定虚拟画布的显示壳。
	add_to_group(&"game_display_shell")


func _ready() -> void:
	screen_transition = TRANSITION_SCRIPT.new()
	screen_transition.name = "ScreenTransition"
	add_child(screen_transition)
	design_canvas.size = Vector2(DESIGN_SIZE)
	design_canvas.scale = Vector2.ONE
	_layout_render_container()
	if not resized.is_connected(_on_root_control_resized):
		resized.connect(_on_root_control_resized)
	_preferences.path = run_slots.directory.path_join("game_preferences.cfg")
	_preferences.load_settings()
	if is_instance_valid(main_screen) and is_instance_valid(main_screen.battle_volume_slider):
		main_screen.battle_volume_slider.set_value_no_signal(_preferences.volume)
	preload("res://scripts/battle/battle_audio_service.gd").set_master_volume_percent(_preferences.volume)
	_setup_display_mode_option()
	if main_screen == null:
		preload("res://scripts/ui/card_text_display_settings.gd").load_settings(text_settings_path())
		run_slots.load_selection()
		start_menu = START_MENU_SCRIPT.new()
		start_menu.name = "StartMenu"
		start_menu.slots = run_slots
		start_menu.start_requested.connect(_request_start_slot, CONNECT_DEFERRED)
		start_menu.settings_requested.connect(open_settings)
		start_menu.quit_requested.connect(_request_quit, CONNECT_DEFERRED)
		design_canvas.add_child(start_menu)
	else:
		_connect_main_screen()
	var window := get_window()
	get_tree().auto_accept_quit = false
	window.close_requested.connect(_request_quit)
	if not window.size_changed.is_connected(_on_root_window_size_changed):
		window.size_changed.connect(_on_root_window_size_changed)
	apply_display_mode(_preferences.display_mode as DisplayMode)
	display_mode_option.get_parent().visible = is_instance_valid(main_screen)


func _connect_main_screen() -> void:
	main_screen.profile_stage_changed.connect(_refresh_slot_progress_panel, CONNECT_DEFERRED)
	main_screen.card_pack_presentation_changed.connect(_on_card_pack_presentation_changed)
	main_screen._escape_pause_menu.main_menu_requested.connect(change_screen.bind(return_to_start_menu), CONNECT_DEFERRED)
	main_screen._escape_pause_menu.abandon_requested.connect(_abandon_slot_run, CONNECT_DEFERRED)
	main_screen._escape_pause_menu.find_child("ReturnToMainMenuButton", true, false).visible = start_menu != null
	_prepare_collection_hover.call_deferred()


func get_collection_hover_surface() -> Control:
	if not is_instance_valid(_collection_hover_surface):
		_collection_hover_surface = load("res://scripts/ui/collection_card_hover.gd").new()
		_collection_hover_surface.name = "CollectionHoverSurface"
		# 位于1倍游戏纹理之后，直接按窗口像素绘制；显示模式菜单和转场仍在上层。
		add_child(_collection_hover_surface)
	return _collection_hover_surface


func _prepare_collection_hover() -> void:
	if is_instance_valid(_collection_hover_surface) and is_instance_valid(_collection_hover_surface.get("card")): return
	if not is_instance_valid(main_screen): return
	if not main_screen.startup_complete: await main_screen.startup_completed
	if not is_instance_valid(main_screen): return
	for slot: Control in main_screen._get_collection_card_slots():
		var view := slot.get_child(0) as CardView if slot.get_child_count() > 0 else null
		if view != null and view.get_owned_card() != null:
			get_collection_hover_surface().call("prewarm_collection", view)
			break


func change_screen(action: Callable, show_loading: bool = false) -> void:
	await screen_transition.change(action, show_loading)


func _request_start_slot(index: int) -> void:
	await change_screen(start_slot.bind(index, true), true)


func start_slot(index: int, staged: bool = false) -> bool:
	if slot_progress != null or is_instance_valid(main_screen) or _entering_slot or run_slots.get_slot_path(index).is_empty(): return false
	_entering_slot = true
	var path := run_slots.get_slot_path(index)
	var selected_error := run_slots.select_slot(index)
	if selected_error != OK: return _slot_entry_failed("无法保存存档选择（%d）" % selected_error)
	var service := SAVE_SERVICE.new()
	slot_progress = PROFILE_DATA.new()
	if run_slots.has_slot(index):
		var loaded := service.load_checkpoint(path)
		if not loaded.get("success", false): return _slot_entry_failed("存档无法读取，原文件已保留。")
		_slot_checkpoint = loaded.checkpoint
		if _slot_checkpoint.has("profile_progress"):
			if not _slot_checkpoint.profile_progress is Dictionary or not slot_progress.restore_state(_slot_checkpoint.profile_progress):
				return _slot_entry_failed("存档局外数据无法读取，原文件已保留。")
		else:
			# Demo2旧档始终交给Main的既有迁移流程，不把它误当成新大厅。
			slot_progress.start_run()
	else:
		slot_progress.profile.tutorial.skip_eligible_at_creation = run_slots.can_skip_tutorial()
		_slot_checkpoint = {"schema_version": SAVE_SERVICE.SCHEMA_VERSION, "profile_progress": slot_progress.capture_state()}
		if service.save_checkpoint(path, _slot_checkpoint) != OK: return _slot_entry_failed("新存档无法保存，请检查存储空间或权限。")
	if slot_progress.run.stage == "active":
		if not await _create_run_screen(path, true, staged): return _slot_entry_failed("本局无法读取，原文件已保留。")
	var used_error := run_slots.mark_slot_used(index)
	if used_error != OK: return _slot_entry_failed("无法记住当前存档（%d），请重试。" % used_error)
	_entering_slot = false
	start_menu.hide()
	_refresh_slot_progress_panel()
	return true


func _create_run_screen(path: String, restore: bool, staged: bool) -> bool:
	var began := Time.get_ticks_usec()
	main_screen = MAIN_SCENE.instantiate()
	last_startup_timings = {"instantiate_ms": (Time.get_ticks_usec() - began) / 1000.0}
	main_screen.name = "Main"
	main_screen.short_maze_enabled = true
	main_screen.initialize_maze_run_on_ready = not restore
	main_screen.frame_budgeted_startup = staged
	main_screen.run_save_path = path
	main_screen.profile_progress.restore_state(slot_progress.capture_state())
	began = Time.get_ticks_usec()
	design_canvas.add_child(main_screen)
	if not main_screen.startup_complete:
		await main_screen.startup_completed
		await get_tree().process_frame
	last_startup_timings["initialize_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	began = Time.get_ticks_usec()
	var success: bool = main_screen.load_run_from_path(path) if restore else main_screen.save_run_to_path(path) == OK
	last_startup_timings["restore_or_save_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	if not success:
		main_screen.free()
		main_screen = null
		return false
	slot_progress = main_screen.profile_progress
	_connect_main_screen()
	if staged: main_screen._capture_startup_runtime_snapshot()
	return true


func _slot_entry_failed(message: String) -> bool:
	if is_instance_valid(main_screen): main_screen.free()
	main_screen = null
	slot_progress = null
	_slot_checkpoint.clear()
	_entering_slot = false
	start_menu.show_error(message)
	return false


func start_new_slot_run(staged: bool = false) -> bool:
	if slot_progress == null or slot_progress.run.stage != "hub" or _entering_slot: return false
	_entering_slot = true
	var before: Dictionary = slot_progress.capture_state()
	if is_instance_valid(main_screen):
		main_screen.free()
		main_screen = null
	var success := await _create_run_screen(run_slots.get_slot_path(run_slots.selected_slot), false, staged)
	_entering_slot = false
	if not success:
		slot_progress.restore_state(before)
		_show_persistence_error("新一局保存失败，原局外进度已保留，请重试。")
	_refresh_slot_progress_panel()
	return success


func _request_new_slot_run() -> void:
	await change_screen(start_new_slot_run.bind(true), true)


func return_to_start_menu() -> void:
	if start_menu == null or slot_progress == null or _entering_slot: return
	if not _save_active_run(): return
	if is_instance_valid(main_screen):
		main_screen._escape_pause_menu.close_menu()
		main_screen.free()
		main_screen = null
	get_tree().paused = false
	if is_instance_valid(_slot_progress_panel):
		_slot_progress_panel.hide()
		_slot_progress_panel.queue_free()
		_slot_progress_panel = null
	if is_instance_valid(_settings_panel): _settings_panel.hide()
	slot_progress = null
	_slot_checkpoint.clear()
	_on_card_pack_presentation_changed(false)
	start_menu.reset()


func _save_active_run() -> bool:
	if slot_progress == null and not is_instance_valid(main_screen): return true
	var error: int
	if is_instance_valid(main_screen):
		error = main_screen.save_run_to_path(main_screen.run_save_path)
	else:
		var next := _slot_checkpoint.duplicate(true)
		next.profile_progress = slot_progress.capture_state()
		error = SAVE_SERVICE.new().save_checkpoint(run_slots.get_slot_path(run_slots.selected_slot), next)
		if error == OK: _slot_checkpoint = next
	if error == OK: return true
	_show_persistence_error("保存失败（错误码 %d），请检查存储空间或文件权限后重试。" % error)
	return false


func _show_persistence_error(message: String) -> void:
	if not is_instance_valid(_persistence_dialog):
		_persistence_dialog = AcceptDialog.new()
		_persistence_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_persistence_dialog)
	_persistence_dialog.dialog_text = message
	_persistence_dialog.popup_centered()


func _request_quit() -> void:
	if screen_transition.busy:
		await screen_transition.finished
	if _save_active_run():
		get_tree().quit()


func _on_card_pack_presentation_changed(active: bool) -> void:
	# 完整4倍包装的封口靠近窗口顶部，外层倍率菜单不能挡住撕包输入。
	display_mode_option.get_parent().visible = not active and is_instance_valid(main_screen) and main_screen.visible


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_settings_panel) and _settings_panel.visible:
			_settings_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(_slot_progress_panel) and _slot_progress_panel.visible:
			if _slot_progress_panel.close_inspection():
				get_viewport().set_input_as_handled()
				return
			return_to_start_menu()
			get_viewport().set_input_as_handled()
			return
	if not is_instance_valid(main_screen) or not get_tree().paused or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var internal_position := (
		render_container.get_global_transform_with_canvas().affine_inverse()
		* mouse_event.position
	)
	if main_screen.open_paused_card_inspection_at(internal_position):
		get_viewport().set_input_as_handled()


func apply_display_mode(mode: DisplayMode) -> void:
	if Engine.is_embedded_in_editor():
		display_mode_option.disabled = true
		display_mode_feedback.text = "编辑器嵌入模式：关闭“下次运行游戏时嵌入”后重新运行"
		display_mode_feedback.visible = true
		return
	current_display_mode = mode
	_window_resize_request_serial += 1
	_window_transition_in_progress = true
	_select_option_without_signal(mode)
	if DisplayServer.get_name() == "headless":
		_window_transition_in_progress = false
		return
	var window := get_window()
	window.unresizable = true
	if mode == DisplayMode.ADAPTIVE_FULLSCREEN:
		display_mode_feedback.visible = false
		window.mode = Window.MODE_FULLSCREEN
		call_deferred("_verify_fullscreen_mode", _window_resize_request_serial, 0)
		return
	display_mode_feedback.visible = false
	window.mode = Window.MODE_WINDOWED
	# macOS 退出全屏是异步过程；下一帧再写窗口客户区尺寸，避免系统过渡覆盖它。
	call_deferred("_apply_windowed_size", mode, _window_resize_request_serial, 0)


func get_window_size_for_mode(mode: DisplayMode) -> Vector2i:
	return WINDOW_SIZE_BY_MODE.get(mode, Vector2i.ZERO) as Vector2i


func _setup_display_mode_option() -> void:
	display_mode_option.clear()
	for mode: DisplayMode in [
		DisplayMode.WINDOW_720P,
		DisplayMode.WINDOW_1080P,
		DisplayMode.WINDOW_2K,
		DisplayMode.ADAPTIVE_FULLSCREEN,
	]:
		display_mode_option.add_item(DISPLAY_MODE_LABELS[mode], mode)
	display_mode_option.tooltip_text = "固定窗口尺寸；窗口边缘不可拖动调整"
	display_mode_option.item_selected.connect(_on_display_mode_selected)


func _select_option_without_signal(mode: DisplayMode) -> void:
	if not is_instance_valid(display_mode_option):
		return
	for item_index: int in display_mode_option.item_count:
		if display_mode_option.get_item_id(item_index) == mode:
			display_mode_option.select(item_index)
			return


func _on_display_mode_selected(item_index: int) -> void:
	change_display_preference(display_mode_option.get_item_id(item_index))


func _apply_windowed_size(mode: DisplayMode, request_serial: int, attempt: int) -> void:
	if current_display_mode != mode or request_serial != _window_resize_request_serial:
		return
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		if attempt < WINDOW_MODE_TRANSITION_MAX_FRAMES:
			await get_tree().process_frame
			_apply_windowed_size(mode, request_serial, attempt + 1)
		else:
			_window_transition_in_progress = false
			display_mode_feedback.text = "退出全屏未完成，请稍后重试"
			display_mode_feedback.visible = true
		return
	window.size = WINDOW_SIZE_BY_MODE[mode]
	_window_transition_in_progress = false
	_select_option_without_signal(mode)
	call_deferred("_center_window")


func _verify_fullscreen_mode(request_serial: int, attempt: int) -> void:
	if request_serial != _window_resize_request_serial:
		return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		_window_transition_in_progress = false
		current_display_mode = DisplayMode.ADAPTIVE_FULLSCREEN
		_select_option_without_signal(current_display_mode)
		display_mode_feedback.visible = false
		return
	if attempt < WINDOW_MODE_TRANSITION_MAX_FRAMES:
		await get_tree().process_frame
		_verify_fullscreen_mode(request_serial, attempt + 1)
		return
	# 原生窗口请求未被系统接受时，恢复真实档位，不把请求当作成功。
	_window_transition_in_progress = false
	current_display_mode = _get_windowed_mode_for_size(window.size)
	_select_option_without_signal(current_display_mode)
	display_mode_feedback.text = "系统尚未进入全屏，请稍后重试"
	display_mode_feedback.visible = true


func _on_root_window_size_changed() -> void:
	_layout_render_container()
	if _window_transition_in_progress or DisplayServer.get_name() == "headless":
		return
	call_deferred("_sync_display_mode_from_actual_window")


func _on_root_control_resized() -> void:
	_layout_render_container()


func _layout_render_container() -> void:
	if not is_instance_valid(render_container):
		return
	# 根窗口使用 disabled stretch，因此这里的 size 就是真实客户区像素尺寸；
	# 只把固定 1×内部纹理一次性缩放到客户区。等比整数倍率保留硬像素，
	# 1080p 等非整数倍率改用线性过滤，避免同一逻辑像素宽度忽大忽小。
	render_container.size = Vector2(INTERNAL_RENDER_SIZE)
	var render_scale := Vector2(
		size.x / float(INTERNAL_RENDER_SIZE.x),
		size.y / float(INTERNAL_RENDER_SIZE.y)
	)
	render_container.scale = render_scale
	# 外层窗口控件与逻辑画布保持相同位置和倍率，2K 时也不会压住资源板。
	display_mode_option.get_parent().position = DISPLAY_MODE_POSITION * render_scale
	display_mode_option.get_parent().scale = render_scale
	display_mode_feedback.position = DISPLAY_FEEDBACK_POSITION * render_scale
	display_mode_feedback.scale = render_scale
	render_container.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if _is_uniform_integer_scale(render_scale)
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


static func _is_uniform_integer_scale(render_scale: Vector2) -> bool:
	if render_scale.x <= 0.0 or render_scale.y <= 0.0:
		return false
	return (
		absf(render_scale.x - render_scale.y) <= INTEGER_SCALE_EPSILON
		and absf(render_scale.x - roundf(render_scale.x))
		<= INTEGER_SCALE_EPSILON
		and absf(render_scale.y - roundf(render_scale.y))
		<= INTEGER_SCALE_EPSILON
	)


func _sync_display_mode_from_actual_window() -> void:
	if _window_transition_in_progress:
		return
	var window := get_window()
	current_display_mode = (
		DisplayMode.ADAPTIVE_FULLSCREEN
		if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
		else _get_windowed_mode_for_size(window.size)
	)
	_select_option_without_signal(current_display_mode)


func open_card_art_tuner() -> void:
	if is_instance_valid(_card_art_tuner):
		return
	_card_art_tuner = CARD_ART_TUNER_SCENE.instantiate() as CardArtTuner
	_card_art_tuner.name = "CardArtTuner"
	_card_art_tuner.card_resource_saved.connect(_on_card_resource_saved)
	design_canvas.add_child(_card_art_tuner)
	_card_art_tuner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_screen.visible = false


func _on_card_resource_saved(card: CardData) -> void:
	# 保存后更新现有卡面；准备态重算预览，不重建正在进行的战斗。
	for view: CardView in get_tree().get_nodes_in_group(&"card_views"):
		if not main_screen.is_ancestor_of(view) or view.card_data == null or view.card_data.id != card.id: continue
		if view.card_data != card:
			view.card_data.display_name = card.display_name
		view.set_card_data(view.card_data)
	if main_screen.current_phase == main_screen.GamePhase.PREPARE:
		main_screen._refresh_preparation_effect_preview()


func close_card_art_tuner() -> void:
	if is_instance_valid(_card_art_tuner):
		_card_art_tuner.queue_free()
	_card_art_tuner = null
	main_screen.visible = true


func is_card_art_tuner_open() -> bool:
	return is_instance_valid(_card_art_tuner)


func open_battle_lab() -> void:
	if is_instance_valid(_battle_lab):
		return
	_battle_lab = BATTLE_LAB_SCENE.instantiate() as BattleLab
	_battle_lab.name = "BattleLab"
	design_canvas.add_child(_battle_lab)
	_battle_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_lab.close_requested.connect(change_screen.bind(close_battle_lab))
	main_screen.visible = false


func close_battle_lab() -> void:
	if is_instance_valid(_battle_lab):
		_battle_lab.queue_free()
	_battle_lab = null
	main_screen.visible = true


func is_battle_lab_open() -> bool:
	return is_instance_valid(_battle_lab)


func open_attack_effect_lab() -> void:
	if is_instance_valid(_attack_effect_lab):
		return
	_attack_effect_lab = ATTACK_EFFECT_LAB_SCENE.instantiate() as AttackEffectLab
	_attack_effect_lab.name = "AttackEffectLab"
	design_canvas.add_child(_attack_effect_lab)
	_attack_effect_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_attack_effect_lab.close_requested.connect(change_screen.bind(close_attack_effect_lab))
	main_screen.visible = false


func close_attack_effect_lab() -> void:
	if is_instance_valid(_attack_effect_lab):
		_attack_effect_lab.queue_free()
	_attack_effect_lab = null
	main_screen.visible = true


func is_attack_effect_lab_open() -> bool:
	return is_instance_valid(_attack_effect_lab)


func open_pack_effect_tuner(source: Control = null, relief_preview: bool = false) -> void:
	if is_pack_effect_tuner_open() or is_card_font_lab_open() or is_card_art_tuner_open() or is_battle_lab_open() or is_attack_effect_lab_open(): return
	_suspend_tuner_source(source)
	_pack_effect_tuner = (PACK_RELIEF_PREVIEW_SCENE if relief_preview else PACK_EFFECT_TUNER_SCENE).instantiate()
	_pack_effect_tuner.close_requested.connect(change_screen.bind(close_pack_effect_tuner), CONNECT_DEFERRED)
	design_canvas.add_child(_pack_effect_tuner)
	if relief_preview:
		_pack_effect_tuner.fit_to_host(Vector2(DESIGN_SIZE))
	else:
		_pack_effect_tuner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_on_card_pack_presentation_changed(true)


func _suspend_tuner_source(source: Control) -> void:
	_tuner_source = source if is_instance_valid(source) else main_screen
	_tuner_previous_process_mode = _tuner_source.process_mode
	_tuner_previous_escape_input = _tuner_source._escape_pause_menu.is_processing_input()
	_tuner_source._escape_pause_menu.set_process_input(false)
	_tuner_source.process_mode = Node.PROCESS_MODE_DISABLED
	_tuner_source.hide()


func close_pack_effect_tuner() -> void:
	if not is_pack_effect_tuner_open(): return
	_pack_effect_tuner.prepare_close()
	design_canvas.remove_child(_pack_effect_tuner)
	_pack_effect_tuner.queue_free()
	_pack_effect_tuner = null
	_restore_tuner_source()


func _restore_tuner_source() -> void:
	_tuner_source.process_mode = _tuner_previous_process_mode
	_tuner_source._escape_pause_menu.set_process_input(_tuner_previous_escape_input)
	_tuner_source.show()
	_tuner_source = null
	_on_card_pack_presentation_changed(false)


func is_pack_effect_tuner_open() -> bool:
	return is_instance_valid(_pack_effect_tuner)


func open_card_font_lab(source: Control = null) -> void:
	if is_card_font_lab_open() or is_pack_effect_tuner_open() or is_card_art_tuner_open() or is_battle_lab_open() or is_attack_effect_lab_open(): return
	_suspend_tuner_source(source)
	_card_font_lab = CARD_FONT_LAB_SCENE.instantiate()
	_card_font_lab.close_requested.connect(change_screen.bind(close_card_font_lab), CONNECT_DEFERRED)
	design_canvas.add_child(_card_font_lab)
	_card_font_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func close_card_font_lab() -> void:
	if not is_card_font_lab_open(): return
	_card_font_lab.prepare_close()
	design_canvas.remove_child(_card_font_lab)
	_card_font_lab.queue_free()
	_card_font_lab = null
	_restore_tuner_source()


func is_card_font_lab_open() -> bool:
	return is_instance_valid(_card_font_lab)


func open_rare_shop() -> bool:
	if is_instance_valid(_rare_shop): return true
	if is_card_art_tuner_open() or is_battle_lab_open() or is_attack_effect_lab_open() or is_pack_effect_tuner_open() or is_card_font_lab_open(): return false
	_rare_shop_previous_main_process_mode = main_screen.process_mode
	_rare_shop_previous_escape_input = main_screen._escape_pause_menu.is_processing_input()
	main_screen._developer_console.set_open(false)
	main_screen._escape_pause_menu.set_process_input(false)
	main_screen.process_mode = Node.PROCESS_MODE_DISABLED
	main_screen.hide()
	_rare_shop = RARE_SHOP_LAB_SCENE.instantiate()
	_rare_shop.close_requested.connect(change_screen.bind(close_rare_shop), CONNECT_DEFERRED)
	_rare_shop.card_pack_presentation_changed.connect(_on_card_pack_presentation_changed)
	design_canvas.add_child(_rare_shop)
	_rare_shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return true


func close_rare_shop() -> void:
	if not is_instance_valid(_rare_shop): return
	_rare_shop._close_card_inspection(true)
	design_canvas.remove_child(_rare_shop)
	_rare_shop.queue_free()
	_rare_shop = null
	_on_card_pack_presentation_changed(false)
	main_screen.process_mode = _rare_shop_previous_main_process_mode
	main_screen._escape_pause_menu.set_process_input(_rare_shop_previous_escape_input)
	main_screen.show()


func _get_windowed_mode_for_size(window_size: Vector2i) -> DisplayMode:
	var closest_mode := DisplayMode.WINDOW_1080P
	var closest_distance := INF
	for mode: DisplayMode in [
		DisplayMode.WINDOW_720P,
		DisplayMode.WINDOW_1080P,
		DisplayMode.WINDOW_2K,
	]:
		var distance := Vector2(window_size).distance_squared_to(
			Vector2(WINDOW_SIZE_BY_MODE[mode])
		)
		if distance < closest_distance:
			closest_distance = distance
			closest_mode = mode
	return closest_mode


func _center_window() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED:
		return
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	var centered_offset := (usable_rect.size - window.size) / 2
	window.position = usable_rect.position + Vector2i(
		maxi(centered_offset.x, 0),
		maxi(centered_offset.y, 0)
	)


func _refresh_slot_progress_panel() -> void:
	if start_menu == null or slot_progress == null: return
	if is_instance_valid(main_screen): slot_progress = main_screen.profile_progress
	if is_instance_valid(_slot_progress_panel):
		_slot_progress_panel.hide()
		_slot_progress_panel.queue_free()
	_slot_progress_panel = null
	var active: bool = slot_progress.run.stage == "active"
	if is_instance_valid(main_screen):
		main_screen.visible = active
		main_screen.process_mode = Node.PROCESS_MODE_PAUSABLE if active else Node.PROCESS_MODE_DISABLED
		main_screen._escape_pause_menu.set_process_input(active)
	_on_card_pack_presentation_changed(false)
	if active: return
	_slot_progress_panel = SLOT_HUB_SCRIPT.new()
	_slot_progress_panel.name = "SlotProgressPanel"
	_slot_progress_panel.progress = slot_progress
	_slot_progress_panel.slot_index = run_slots.selected_slot
	_slot_progress_panel.new_run_requested.connect(_request_new_slot_run, CONNECT_DEFERRED)
	_slot_progress_panel.return_requested.connect(change_screen.bind(return_to_start_menu), CONNECT_DEFERRED)
	_slot_progress_panel.settings_requested.connect(open_settings)
	_slot_progress_panel.collection_action_requested.connect(_apply_collection_action)
	_slot_progress_panel.selection_requested.connect(_apply_collection_selection)
	design_canvas.add_child(_slot_progress_panel)


func _apply_collection_action(action: StringName) -> void:
	var before: Dictionary = slot_progress.capture_state()
	if not slot_progress.call(action) or not _save_active_run():
		slot_progress.restore_state(before)
		return
	_refresh_slot_progress_panel()


func _abandon_slot_run() -> void:
	if not is_instance_valid(main_screen): return
	if not main_screen.finish_maze_run("abandoned"):
		_show_persistence_error("放弃结算保存失败，当前本局已保留，请重试。")
	else:
		_refresh_slot_progress_panel()


func _apply_collection_selection(choices: Array) -> void:
	var before: Dictionary = slot_progress.capture_state()
	if not slot_progress.set_selection(choices):
		_show_persistence_error("选择不合法：最多8张，同种最多3个固定收藏位，请先取消其他选择。")
		return
	if not _save_active_run():
		slot_progress.restore_state(before)
		return
	_slot_progress_panel._draw_cards()


func text_settings_path() -> String:
	return run_slots.directory.path_join("card_text_display.cfg")


func open_settings() -> void:
	if not is_instance_valid(_settings_panel):
		_settings_panel = SETTINGS_SCRIPT.new()
		_settings_panel.name = "GameSettings"
		_settings_panel.text_settings_path = text_settings_path()
		_settings_panel.closed.connect(func(): _settings_panel.hide())
		_settings_panel.volume_changed.connect(func(value: float): _settings_panel.show_save_result(set_volume_preference(value)))
		_settings_panel.display_changed.connect(func(mode: int): _settings_panel.show_save_result(change_display_preference(mode)))
		design_canvas.add_child(_settings_panel)
	_settings_panel.sync_values(_preferences.volume, current_display_mode)
	_settings_panel.show()
	_settings_panel.move_to_front()


func set_volume_preference(value: float) -> Error:
	_preferences.volume = clampf(value, 0, 100)
	preload("res://scripts/battle/battle_audio_service.gd").set_master_volume_percent(_preferences.volume)
	if is_instance_valid(main_screen): main_screen.battle_volume_slider.set_value_no_signal(_preferences.volume)
	return _preferences.save_settings()


func change_display_preference(mode: int) -> Error:
	if mode < 0 or mode > 3: return ERR_INVALID_PARAMETER
	apply_display_mode(mode as DisplayMode)
	if Engine.is_embedded_in_editor(): return ERR_UNAVAILABLE
	_preferences.display_mode = mode
	return _preferences.save_settings()
