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
const CardEffectPopup = preload("res://scripts/ui/card_effect_popup.gd")
const PROFILE_DATA = preload("res://scripts/data/profile_progress.gd")
const GALLERY_SCRIPT = preload("res://scripts/ui/gallery_book.gd")
const SLOT_HUB_SCRIPT = preload("res://scripts/ui/slot_hub.gd")
const SETTINGS_SCRIPT = preload("res://scripts/ui/game_settings_panel.gd")
const PREFERENCES_SCRIPT = preload("res://scripts/data/game_preferences.gd")
const PIXEL_EDGE_AA_SHADER = preload("res://shaders/pixel_edge_aa.gdshader")
const CRT_SHADER = preload("res://shaders/crt_display.gdshader")
const CrtProjection = preload("res://scripts/ui/crt_projection.gd")
const CRT_LAYER := 1025 # Godot 内嵌窗口使用 1024，CRT 需要在整帧合成之后绘制
const SAVE_SERVICE = preload("res://scripts/data/run_save_service.gd")
const START_MENU_SCRIPT = preload("res://scripts/ui/start_menu.gd")
const GAMEPAD_POINTER_SCRIPT := preload("res://scripts/ui/gamepad_pointer.gd")
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
var _card_texture_tuner: Control
var _card_art_tuner: CardArtTuner
var _battle_lab: BattleLab
var _attack_effect_lab: AttackEffectLab
var _pack_effect_tuner: Control
var _card_font_lab: Control
var _dice_model_viewer: Control
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
var _gallery_panel: Control
var _slot_progress_panel: Control
var slot_progress: RefCounted
var _slot_checkpoint: Dictionary = {}
var _entering_slot := false
var _preferences := PREFERENCES_SCRIPT.new()
var _pixel_edge_aa_material := ShaderMaterial.new()
var _crt_layer: CanvasLayer
var _crt_material: ShaderMaterial
var _crt_curvature := Vector2.ZERO
var _settings_panel: Control
var _return_to_tool_settings := false
var _paused_hover_card: CardView
var _paused_spell_tray: Control
var _paused_hover_time := 0.0
var _paused_hover_popup: CanvasLayer
var _pointer_in_window := Vector2.INF
var _gamepad_pointer: Node


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
	preload("res://scripts/ui/event_landing_dust.gd").warm_shader(design_canvas)
	_preferences.path = run_slots.directory.path_join("game_preferences.cfg")
	_preferences.load_settings()
	_pixel_edge_aa_material.shader = PIXEL_EDGE_AA_SHADER
	_setup_crt_overlay()
	_layout_render_container()
	if not resized.is_connected(_on_root_control_resized):
		resized.connect(_on_root_control_resized)
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
	window.window_input.connect(_remap_crt_window_input)
	window.mouse_exited.connect(func(): _pointer_in_window = Vector2.INF)
	get_tree().auto_accept_quit = false
	window.close_requested.connect(_request_quit)
	if not window.size_changed.is_connected(_on_root_window_size_changed):
		window.size_changed.connect(_on_root_window_size_changed)
	_gamepad_pointer = GAMEPAD_POINTER_SCRIPT.new()
	_gamepad_pointer.name = "GamepadPointer"
	_gamepad_pointer.setup(internal_viewport, _get_gamepad_gameplay_screen, _get_gamepad_menu)
	add_child(_gamepad_pointer)
	apply_display_mode(_preferences.display_mode as DisplayMode)
	display_mode_option.get_parent().visible = is_instance_valid(main_screen)


func _get_gamepad_gameplay_screen() -> Control:
	if not is_instance_valid(main_screen) or not main_screen.is_visible_in_tree():
		return null
	if main_screen._escape_pause_menu.blocks_gameplay():
		return null
	if main_screen._task_dialogue_blocks_input():
		return null
	if is_instance_valid(main_screen._developer_console) and main_screen._developer_console.visible:
		return null
	if screen_transition.busy or is_developer_tool_open() or not get_window().get_embedded_subwindows().is_empty():
		return null
	if is_instance_valid(_settings_panel) and _settings_panel.visible:
		return null
	return main_screen


func _get_gamepad_menu() -> Control:
	if screen_transition.busy: return null
	if is_instance_valid(main_screen) and main_screen._escape_pause_menu.blocks_gameplay():
		return main_screen._escape_pause_menu.active_overlay()
	for menu: Control in [_card_art_tuner, _card_texture_tuner, _battle_lab, _attack_effect_lab, _pack_effect_tuner, _card_font_lab, _dice_model_viewer, _rare_shop, _settings_panel, _task_panel, _gallery_panel, _slot_progress_panel]:
		if is_instance_valid(menu) and menu.is_visible_in_tree(): return menu
	if is_instance_valid(start_menu) and start_menu.is_visible_in_tree():
		return start_menu._slot_overlay if start_menu._slot_overlay.visible else start_menu
	return null


func _connect_main_screen() -> void:
	main_screen.profile_stage_changed.connect(_refresh_slot_progress_panel, CONNECT_DEFERRED)
	main_screen.card_pack_presentation_changed.connect(_on_card_pack_presentation_changed)
	main_screen._escape_pause_menu.modal_visibility_changed.connect(_on_card_pack_presentation_changed.bind(false))
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
	main_screen.maze_controller.show_task_hint.call_deferred()
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
	await change_screen(_open_task_shop.bind(true))


func return_to_start_menu() -> void:
	if start_menu == null or slot_progress == null or _entering_slot: return
	if not _save_active_run(): return
	if is_instance_valid(main_screen):
		main_screen._escape_pause_menu.close_menu()
		main_screen.free()
		main_screen = null
	get_tree().paused = false
	_close_task_shop()
	_clear_gallery()
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
		if main_screen._developer_event_test.is_active():
			var restore_error: String = main_screen._developer_event_test.stop()
			if not restore_error.is_empty():
				_show_persistence_error(restore_error)
				return false
			slot_progress = main_screen.profile_progress
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
	display_mode_option.get_parent().visible = (
		not active and is_instance_valid(main_screen) and main_screen.visible
		and not main_screen._escape_pause_menu.blocks_gameplay()
		and not is_instance_valid(main_screen._card_pack_opening)
		and not is_instance_valid(main_screen._sticker_pack_opening)
	)


func _process(delta: float) -> void:
	var card: CardView
	var spell_tray: Control
	if _pointer_in_window.is_finite() and not _gamepad_pointer._active and is_instance_valid(main_screen) and main_screen.can_hover_paused_battle() and not screen_transition.busy and not is_developer_tool_open():
		var pointer := render_container.get_global_transform_with_canvas().affine_inverse() * _pointer_in_window
		var display_controls := display_mode_option.get_parent() as Control
		if Rect2(Vector2.ZERO, render_container.size).has_point(pointer) and not (display_controls.visible and display_controls.get_global_rect().has_point(_pointer_in_window)):
			spell_tray = main_screen.find_paused_spell_tray_at(pointer)
			card = spell_tray.hover_at(pointer) if spell_tray != null else main_screen.find_battle_card_at(pointer)
	if spell_tray != _paused_spell_tray:
		if is_instance_valid(_paused_spell_tray): _paused_spell_tray.clear_hover_card()
		_paused_spell_tray = spell_tray
	if card != _paused_hover_card or card == null:
		if is_instance_valid(_paused_hover_popup): _paused_hover_popup.hide_card(null, &"paused_battle")
		_paused_hover_card = card
		_paused_hover_time = 0.0
	if card == null: return
	_paused_hover_time += delta
	if _paused_hover_time < card.hover_effect_delay_seconds: return
	if not is_instance_valid(_paused_hover_popup): _paused_hover_popup = CardEffectPopup.shared(get_tree())
	_paused_hover_popup.show_card(card, null, true)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_in_window = event.position
	if event is InputEventMouseButton and event.pressed:
		_paused_hover_time = 0.0
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_settings_panel) and _settings_panel.visible:
			if not _settings_panel.close_subpage(): _settings_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if is_developer_tool_open():
			if is_battle_lab_open() and _battle_lab.close_lineup_layer():
				get_viewport().set_input_as_handled()
				return
			if is_card_art_tuner_open(): change_screen(close_card_art_tuner)
			elif is_battle_lab_open(): change_screen(close_battle_lab)
			elif is_attack_effect_lab_open(): change_screen(close_attack_effect_lab)
			return
		if is_instance_valid(_task_panel):
			_close_task_shop()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(_gallery_panel):
			if not _gallery_panel.close_inspection(): change_screen(_close_gallery)
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


func _remap_crt_window_input(event: InputEvent) -> void:
	if _crt_curvature == Vector2.ZERO or not is_visible_in_tree(): return
	if not (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventGesture): return
	# window_input 在 Godot 的悬停、控件命中和 SubViewport 转发之前发出。
	var window := get_window()
	var to_window := window.get_final_transform()
	var to_viewport := to_window.affine_inverse()
	var frame_size := window.get_visible_rect().size
	if frame_size.x <= 0.0 or frame_size.y <= 0.0: return
	var point: Vector2 = event.position
	var source := to_window * CrtProjection.to_source(to_viewport * point, frame_size, _crt_curvature)
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		var previous: Vector2 = to_viewport * (point - event.relative)
		event.relative = source - to_window * CrtProjection.to_source(previous, frame_size, _crt_curvature)
	event.position = source
	if event is InputEventMouse: event.global_position = source


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
	# 固定 1×内部纹理一次性缩放到客户区。分数倍率默认平滑，也可只在边缘混色。
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
	var use_edge_aa := _preferences.pixel_edge_aa and not render_scale.is_equal_approx(render_scale.round())
	render_container.material = _pixel_edge_aa_material if use_edge_aa else null
	_crt_material.set_shader_parameter("output_scale", render_scale.y)


func _setup_crt_overlay() -> void:
	_crt_layer = CanvasLayer.new()
	_crt_layer.name = "CRTOverlay"
	_crt_layer.layer = CRT_LAYER
	add_child(_crt_layer)
	var surface := ColorRect.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = CRT_SHADER
	surface.material = _crt_material
	_crt_layer.add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_crt_preference()


func _apply_crt_preference() -> void:
	var strength: float = _preferences.crt_strength * 0.01 if _preferences.crt_enabled else 0.0
	_crt_curvature = CrtProjection.MAX_CURVATURE * strength
	_crt_layer.visible = strength > 0.0
	_crt_material.set_shader_parameter("scanline_strength", strength)
	_crt_material.set_shader_parameter("curvature", _crt_curvature)


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


func is_developer_tool_open() -> bool:
	return is_card_texture_tuner_open() or is_card_art_tuner_open() or is_battle_lab_open() or is_attack_effect_lab_open() or is_pack_effect_tuner_open() or is_card_font_lab_open() or is_instance_valid(_dice_model_viewer)


func open_developer_tool(tool: StringName, source: Control = null) -> void:
	match tool:
		&"card_texture_tuner": open_card_texture_tuner(source)
		&"card_art_tuner": open_card_art_tuner(source)
		&"battle_lab": open_battle_lab(source)
		&"attack_effect_lab": open_attack_effect_lab(source)
		&"pack_effect_tuner", &"pack_relief_preview": open_pack_effect_tuner(source, tool == &"pack_relief_preview")
		&"card_font_lab": open_card_font_lab(source)
		&"dice_model_viewer": open_dice_model_viewer(source)


func _on_settings_tool_requested(tool: StringName) -> void:
	if screen_transition.busy or is_developer_tool_open(): return
	_settings_panel.hide()
	_return_to_tool_settings = true
	change_screen(open_developer_tool.bind(tool), true)


func open_card_texture_tuner(source: Control = null) -> void:
	if is_developer_tool_open(): return
	_suspend_tuner_source(source)
	_card_texture_tuner = preload("res://scenes/tools/CardTextureTuner.tscn").instantiate()
	_card_texture_tuner.close_requested.connect(func(): change_screen(close_card_texture_tuner))
	design_canvas.add_child(_card_texture_tuner)


func close_card_texture_tuner() -> void:
	if is_instance_valid(_card_texture_tuner): _card_texture_tuner.queue_free()
	_card_texture_tuner = null
	_restore_tuner_source()


func is_card_texture_tuner_open() -> bool:
	return is_instance_valid(_card_texture_tuner)


func open_card_art_tuner(source: Control = null) -> void:
	if is_developer_tool_open(): return
	_suspend_tuner_source(source)
	_card_art_tuner = CARD_ART_TUNER_SCENE.instantiate() as CardArtTuner
	_card_art_tuner.name = "CardArtTuner"
	_card_art_tuner.card_resource_saved.connect(_on_card_resource_saved)
	design_canvas.add_child(_card_art_tuner)
	_card_art_tuner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_card_resource_saved(card: CardData) -> void:
	if not is_instance_valid(main_screen): return
	# 保存后更新现有卡面；准备态重算预览，不重建正在进行的战斗。
	for view: CardView in get_tree().get_nodes_in_group(&"card_views"):
		if not main_screen.is_ancestor_of(view) or view.card_data == null or view.card_data.id != card.id: continue
		if view.card_data != card:
			view.card_data.display_name = card.display_name
			view.card_data.background_style = card.background_style
			view.card_data.background_offsets = card.background_offsets.duplicate()
		view.set_card_data(view.card_data)
	if main_screen.current_phase == main_screen.GamePhase.PREPARE:
		main_screen._refresh_preparation_effect_preview()


func close_card_art_tuner() -> void:
	if is_instance_valid(_card_art_tuner):
		_card_art_tuner.queue_free()
	_card_art_tuner = null
	_restore_tuner_source()


func is_card_art_tuner_open() -> bool:
	return is_instance_valid(_card_art_tuner)


func open_battle_lab(source: Control = null) -> void:
	if is_developer_tool_open(): return
	_suspend_tuner_source(source)
	_battle_lab = BATTLE_LAB_SCENE.instantiate() as BattleLab
	_battle_lab.name = "BattleLab"
	design_canvas.add_child(_battle_lab)
	_battle_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_lab.close_requested.connect(change_screen.bind(close_battle_lab))


func close_battle_lab() -> void:
	if is_instance_valid(_battle_lab):
		_battle_lab.queue_free()
	_battle_lab = null
	_restore_tuner_source()


func is_battle_lab_open() -> bool:
	return is_instance_valid(_battle_lab)


func open_attack_effect_lab(source: Control = null) -> void:
	if is_developer_tool_open(): return
	_suspend_tuner_source(source)
	_attack_effect_lab = ATTACK_EFFECT_LAB_SCENE.instantiate() as AttackEffectLab
	_attack_effect_lab.name = "AttackEffectLab"
	design_canvas.add_child(_attack_effect_lab)
	_attack_effect_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_attack_effect_lab.close_requested.connect(change_screen.bind(close_attack_effect_lab))


func close_attack_effect_lab() -> void:
	if is_instance_valid(_attack_effect_lab):
		_attack_effect_lab.queue_free()
	_attack_effect_lab = null
	_restore_tuner_source()


func is_attack_effect_lab_open() -> bool:
	return is_instance_valid(_attack_effect_lab)


func open_pack_effect_tuner(source: Control = null, relief_preview: bool = false) -> void:
	if is_developer_tool_open(): return
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
	_tuner_source = source
	if not is_instance_valid(_tuner_source):
		if is_instance_valid(main_screen) and main_screen.visible: _tuner_source = main_screen
		elif is_instance_valid(_slot_progress_panel) and _slot_progress_panel.visible: _tuner_source = _slot_progress_panel
		else: _tuner_source = start_menu
	_tuner_previous_process_mode = _tuner_source.process_mode
	if _tuner_source.has_method("_on_escape_pause_menu_requested"):
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
	if _tuner_source.has_method("_on_escape_pause_menu_requested"):
		_tuner_source._escape_pause_menu.set_process_input(_tuner_previous_escape_input)
	_tuner_source.show()
	_tuner_source = null
	_on_card_pack_presentation_changed(false)
	if _return_to_tool_settings:
		_return_to_tool_settings = false
		open_settings()


func is_pack_effect_tuner_open() -> bool:
	return is_instance_valid(_pack_effect_tuner)


func open_card_font_lab(source: Control = null) -> void:
	if is_developer_tool_open(): return
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


func open_dice_model_viewer(source: Control = null) -> void:
	if is_developer_tool_open(): return
	_suspend_tuner_source(source)
	_dice_model_viewer = preload("res://scenes/tools/DiceModelViewer.tscn").instantiate()
	_dice_model_viewer.close_requested.connect(change_screen.bind(close_dice_model_viewer), CONNECT_DEFERRED)
	design_canvas.add_child(_dice_model_viewer)


func close_dice_model_viewer() -> void:
	if not is_instance_valid(_dice_model_viewer): return
	design_canvas.remove_child(_dice_model_viewer)
	_dice_model_viewer.queue_free()
	_dice_model_viewer = null
	_restore_tuner_source()


func open_rare_shop() -> bool:
	if is_instance_valid(_rare_shop): return true
	if is_developer_tool_open(): return false
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
	_clear_gallery()
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
	_slot_progress_panel.shop_requested.connect(change_screen.bind(_open_task_shop), CONNECT_DEFERRED)
	_slot_progress_panel.gallery_requested.connect(change_screen.bind(_open_gallery), CONNECT_DEFERRED)
	_slot_progress_panel.settings_requested.connect(open_settings)
	_slot_progress_panel.collection_action_requested.connect(_apply_collection_action)
	_slot_progress_panel.selection_requested.connect(_apply_collection_selection)
	design_canvas.add_child(_slot_progress_panel)


var _task_panel: Control


func _open_task_shop(selecting: bool = false) -> void:
	if slot_progress == null or slot_progress.run.stage != "hub" or is_instance_valid(_task_panel): return
	_slot_progress_panel.hide()
	_task_panel = preload("res://scripts/ui/task_shop.gd").new()
	_task_panel.name = "TaskSelection" if selecting else "TaskShop"
	_task_panel.progress = slot_progress
	_task_panel.selecting = selecting
	_task_panel.return_requested.connect(_close_task_shop, CONNECT_DEFERRED)
	_task_panel.purchase_requested.connect(_purchase_task)
	_task_panel.skip_requested.connect(_skip_tutorial)
	_task_panel.selection_requested.connect(_begin_selected_run, CONNECT_DEFERRED)
	design_canvas.add_child(_task_panel)


func _close_task_shop() -> void:
	if is_instance_valid(_task_panel):
		_task_panel.hide()
		_task_panel.queue_free()
	_task_panel = null
	if is_instance_valid(_slot_progress_panel):
		_slot_progress_panel.refresh_balance()
		_slot_progress_panel.show()


func _purchase_task(id: String) -> void:
	if slot_progress == null or slot_progress.run.stage != "hub": return
	var before: Dictionary = slot_progress.capture_state()
	if not slot_progress.purchase_catalog_task(id): return
	if not _save_active_run(): slot_progress.restore_state(before)
	if is_instance_valid(_task_panel): _task_panel.refresh()


func _skip_tutorial() -> void:
	var before: Dictionary = slot_progress.capture_state()
	if not slot_progress.complete_tutorial(true): return
	if not _save_active_run(): slot_progress.restore_state(before)
	_close_task_shop()
	_refresh_slot_progress_panel()


func _begin_selected_run(main_id: String, side_id: String) -> void:
	if slot_progress == null: return
	var before: Dictionary = slot_progress.capture_state()
	if not slot_progress.select_catalog_tasks(main_id, side_id): return
	if not _save_active_run():
		slot_progress.restore_state(before)
		return
	_close_task_shop()
	await change_screen(start_new_slot_run.bind(true), true)


func _open_gallery() -> void:
	if slot_progress == null or slot_progress.run.stage != "hub" or is_instance_valid(_gallery_panel): return
	get_collection_hover_surface().release_collection()
	_slot_progress_panel.hide()
	_gallery_panel = GALLERY_SCRIPT.new()
	_gallery_panel.name = "GalleryBook"
	_gallery_panel.progress = slot_progress
	_gallery_panel.slot_index = run_slots.selected_slot
	_gallery_panel.return_requested.connect(change_screen.bind(_close_gallery), CONNECT_DEFERRED)
	design_canvas.add_child(_gallery_panel)


func _clear_gallery() -> void:
	if not is_instance_valid(_gallery_panel): return
	get_collection_hover_surface().release_collection()
	_gallery_panel.close_inspection(false)
	_gallery_panel.hide()
	_gallery_panel.queue_free()
	_gallery_panel = null


func _close_gallery() -> void:
	_clear_gallery()
	if is_instance_valid(_slot_progress_panel): _slot_progress_panel.show()


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
		_settings_panel.developer_tools_enabled = true
		_settings_panel.tool_requested.connect(_on_settings_tool_requested)
		_settings_panel.text_settings_path = text_settings_path()
		_settings_panel.closed.connect(func(): _settings_panel.hide())
		_settings_panel.volume_changed.connect(func(value: float): _settings_panel.show_save_result(set_volume_preference(value)))
		_settings_panel.display_changed.connect(func(mode: int): _settings_panel.show_save_result(change_display_preference(mode)))
		_settings_panel.pixel_edge_aa_changed.connect(func(enabled: bool):
			_settings_panel.show_save_result(set_pixel_edge_aa_preference(enabled)))
		_settings_panel.crt_changed.connect(func(enabled: bool, strength: float):
			_settings_panel.show_save_result(set_crt_preference(enabled, strength)))
		design_canvas.add_child(_settings_panel)
	_settings_panel.sync_values(_preferences.volume, current_display_mode, _preferences.pixel_edge_aa)
	_settings_panel.sync_crt(_preferences.crt_enabled, _preferences.crt_strength)
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


func set_pixel_edge_aa_preference(enabled: bool) -> Error:
	_preferences.pixel_edge_aa = enabled
	_layout_render_container()
	return _preferences.save_settings()


func set_crt_preference(enabled: bool, strength: float) -> Error:
	_preferences.crt_enabled = enabled
	_preferences.crt_strength = clampf(strength, 0.0, 100.0)
	_apply_crt_preference()
	return _preferences.save_settings()
