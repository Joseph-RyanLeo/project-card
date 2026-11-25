extends Node

## 手柄焦点负责选择对象。携带与刮擦使用逻辑坐标，并沿用主场景的提交入口。
const CrtProjection = preload("res://scripts/ui/crt_projection.gd")
const StickerEntry = preload("res://scripts/ui/emblem_library_entry.gd")
const FOCUS_GLOW = preload("res://shaders/gamepad_focus_glow.gdshader")
const FocusOutline = preload("res://scripts/ui/focus_outline.gd")
const EffectPopup = preload("res://scripts/ui/card_effect_popup.gd")
const STICK_DEADZONE := 0.20 # 自由移动时忽略的摇杆偏移
const NAV_THRESHOLD := 0.60 # 摇杆推过此行程才移动一次焦点
const NAV_REPEAT_MS := 190 # 持续推动时的焦点重复间隔
const NAV_FIRST_REPEAT_MS := 350 # 首次移动至开始连跳的间隔
const CARRY_SPEED := 680.0 # 手持卡牌、贴纸或刀头时每秒移动的逻辑像素数
const INSPECTION_FOLLOW := 24.0 # 摇杆高光跟随和回到中心的响应速度
const EVENT_SCROLL_SPEED := 350.0 # 右摇杆推满时每秒滚动的逻辑像素数
const STICKER_PEEL_END := 0.85 # 摇杆上拨至此位置时完全揭开封皮
const FOCUS_SPREAD := 17.0 # 焦点柔光在逻辑画布中的最远扩散范围
const FOCUS_FADE_SECONDS := 0.16 # 切换目标时淡入与淡出的时长
const FOCUS_ROW_BAND := 35.0 # 左右导航时将相邻高度归入同一视觉行的范围
const FOCUS_RETRY_MS := 150 # 等待入场布局或可选对象出现的间隔
const RT_PRESS_THRESHOLD := 0.55 # 扳机超过该行程才按下
const RT_RELEASE_THRESHOLD := 0.35 # 扳机回到该行程以下才松开
const RT_HOLD_MS := 2000 # RT 长按开战的真实毫秒数
const RT_VIBRATION_UPDATE_MS := 50 # 蓄力时刷新马达的间隔
const RT_VIBRATION_DURATION := 0.1 # 每段震动秒数
const RT_VIBRATION_START := Vector2(0.15, 0.0) # 弱／强马达起始强度
const RT_VIBRATION_PEAK := Vector2(0.9, 0.85) # 弱／强马达结束强度
const DIRECTION_BUTTONS := {
	JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT,
	JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN,
}

var _window: Window
var _game_viewport: SubViewport
var _get_gameplay_screen: Callable
var _get_menu: Callable
var _device := -1
var _active := false
var _injecting := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _marker: ColorRect
var _previous_marker: ColorRect
var _pack_marker: ColorRect
var _visual_target: Control
var _focus_fade: Tween
var _focus_started := 0
var _previous_event_card: EventCardView
var _focused_stack: ShopPackStackView
var _indicator_card: CardView
var _focus_item: Control
var _focus_area: StringName
var _focus_context: Control
var _world_view := -1
var _remembered_screen_id := 0
var _world_focus := {}
var _next_focus_retry := 0
var _stick_nav := Vector2.ZERO
var _next_repeat := 0
var _pointer := Vector2.ZERO
var _action_screen: Control
var _inspection: InspectionCardSurface
var _inspection_point := Vector2.ZERO
var _toolbox_screen: Control
var _lt_down := false
var _scrape_pressed := false
var _rt_down := false
var _rt_screen: Control
var _rt_pressed_at := 0
var _rt_can_charge := false
var _rt_last_vibration := -RT_VIBRATION_UPDATE_MS


func setup(game_viewport: SubViewport, get_gameplay_screen: Callable, get_menu: Callable) -> void:
	_game_viewport = game_viewport
	_get_gameplay_screen = get_gameplay_screen
	_get_menu = get_menu


func _ready() -> void:
	_window = get_window()
	_window.focus_exited.connect(_cancel_gamepad_actions)
	Input.joy_connection_changed.connect(_on_connection_changed)
	_bind_popup_button(&"ui_accept", JOY_BUTTON_A)
	_bind_popup_button(&"ui_cancel", JOY_BUTTON_B)
	_bind_popup_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_bind_popup_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_previous_marker = _make_focus_glow("PreviousGamepadFocus", 4094)
	_marker = _make_focus_glow("GamepadFocus", 4095)
	get_parent().add_child.call_deferred(_previous_marker)
	get_parent().add_child.call_deferred(_marker)


func _make_focus_glow(node_name: String, layer: int) -> ColorRect:
	var glow := ColorRect.new()
	glow.name = node_name
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = layer
	var shader := ShaderMaterial.new()
	shader.shader = FOCUS_GLOW
	glow.material = shader
	glow.hide()
	return glow


func _bind_popup_button(action: StringName, button: JoyButton) -> void:
	# 已展开的 PopupMenu 先收到手柄事件，由它直接确认、取消或上下移动。
	var binding := InputEventJoypadButton.new()
	binding.device = -1
	binding.button_index = button
	if not InputMap.action_has_event(action, binding): InputMap.action_add_event(action, binding)


func _input(event: InputEvent) -> void:
	if _injecting or not _window.has_focus() or not (get_parent() as Control).is_visible_in_tree(): return
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length_squared() > 0.0):
		if _active: _cancel_gamepad_actions()
		return
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]: return
		var threshold := RT_PRESS_THRESHOLD if motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] else NAV_THRESHOLD
		if absf(motion.axis_value) >= threshold: _activate(motion.device)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.button_index not in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER] and not DIRECTION_BUTTONS.has(button.button_index): return
		if button.pressed: _activate(button.device)
		get_viewport().set_input_as_handled()
		if button.device == _device:
			_dispatch_button.call_deferred(button.button_index, button.pressed)


func _activate(device: int) -> void:
	if _active: return
	_active = true
	_device = device
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_pointer = CrtProjection.viewport_mouse(_game_viewport).clamp(Vector2.ZERO, Vector2(_game_viewport.size) - Vector2.ONE)
	_game_viewport.gui_release_focus()
	_window.gui_release_focus()
	_next_focus_retry = 0


func _process(delta: float) -> void:
	if not _active: return
	if not _window.has_focus() or not (get_parent() as Control).is_visible_in_tree():
		_cancel_gamepad_actions()
		return
	_update_right_trigger(true)
	var screen := _get_gameplay_screen.call() as Control
	var menu := _get_menu.call() as Control
	var direction := _axis_vector(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	var right := _filtered_stick(_axis_vector(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y))
	var popup_open := not _window.get_embedded_subwindows().is_empty()
	if menu == null: _update_toolbox(screen if not popup_open else null)
	if popup_open:
		_clear_inspection_point()
		if _stick_step(direction) and not is_zero_approx(_stick_nav.y):
			_send_key(KEY_DOWN if _stick_nav.y > 0.0 else KEY_UP)
	elif menu == null and _update_gameplay_motion(screen, direction, right, minf(delta, 0.05)):
		_stick_nav = Vector2.ZERO
	else:
		if menu != null: _clear_inspection_point()
		_sync_focus(screen, menu)
		if _stick_step(direction): _move_focus(screen, menu, _stick_nav)
	_update_focus_visual(popup_open or (menu == null and _has_free_movement(screen)), screen, right)


func _axis_vector(horizontal: JoyAxis, vertical: JoyAxis) -> Vector2:
	return Vector2(Input.get_joy_axis(_device, horizontal), Input.get_joy_axis(_device, vertical))


func _filtered_stick(raw: Vector2) -> Vector2:
	var length := raw.length()
	if length <= STICK_DEADZONE: return Vector2.ZERO
	return raw.normalized() * inverse_lerp(STICK_DEADZONE, 1.0, minf(length, 1.0))


func _stick_step(direction: Vector2) -> bool:
	var step := Vector2.ZERO
	if absf(direction.x) >= NAV_THRESHOLD and absf(direction.x) >= absf(direction.y):
		step.x = signf(direction.x)
	elif absf(direction.y) >= NAV_THRESHOLD:
		step.y = signf(direction.y)
	var changed := step != _stick_nav
	_stick_nav = step
	if step == Vector2.ZERO: return false
	var now := Time.get_ticks_msec()
	if not changed and now < _next_repeat: return false
	_next_repeat = now + (NAV_FIRST_REPEAT_MS if changed else NAV_REPEAT_MS)
	return true


func _update_gameplay_motion(screen: Control, stick: Vector2, right: Vector2, delta: float) -> bool:
	if not is_instance_valid(screen):
		_clear_inspection_point()
		return false
	var surface := screen._inspection_surface as InspectionCardSurface
	var pack: CardPackOpening = screen._card_pack_opening
	var looking_at_wrapper := is_instance_valid(pack) and pack.phase in [pack.Phase.SEALED, pack.Phase.TEARING]
	var looking_at_card := is_instance_valid(surface) and is_instance_valid(surface.card) and not _has_free_movement(screen)
	if is_instance_valid(surface) and not screen._inspection_closing and not screen._inspection_library_expanded and not is_instance_valid(screen._emblem_fusion_overlay) and (looking_at_card or looking_at_wrapper):
		var visible_size := surface.gamepad_look_size()
		var center := visible_size * 0.5
		if _inspection != surface:
			_clear_inspection_point()
			_inspection = surface
			_inspection_point = center
		var target := center + right * (center - Vector2.ONE)
		_inspection_point = _inspection_point.lerp(target, 1.0 - exp(-INSPECTION_FOLLOW * delta))
		if _inspection_point.distance_squared_to(target) < 0.01: _inspection_point = target
		surface.set_gamepad_point(_inspection_point)
	else:
		_clear_inspection_point()
		if not is_instance_valid(screen._inspection_overlay) and not is_instance_valid(screen._toolbox_overlay) and screen.maze_controller != null and is_instance_valid(screen.maze_controller._event_table):
			screen.maze_controller._event_table.scroll_gamepad_description(right.y * EVENT_SCROLL_SPEED * delta)
	if _has_pack_gesture(screen):
		var card_pack: Node = screen._card_pack_opening
		if is_instance_valid(card_pack): card_pack.sweep_gamepad_seal(stick.x)
		if is_instance_valid(screen._sticker_pack_opening):
			screen._sticker_pack_opening.peel_with_gamepad(clampf(-stick.y / STICKER_PEEL_END, 0.0, 1.0))
		return true
	if not _has_free_movement(screen): return false
	var direction := _filtered_stick(stick)
	if direction == Vector2.ZERO: return true
	_pointer = (_pointer + direction * CARRY_SPEED * delta).clamp(Vector2.ZERO, Vector2(_game_viewport.size) - Vector2.ONE)
	if screen._rune_scraper_mode: screen.move_gamepad_scraper(_pointer)
	elif _is_indicator_carrying(screen): screen.celestial_indicators.move_click_carry(_pointer)
	else:
		screen.gamepad_carry_position = _pointer
		screen._update_click_carry(_pointer)
	return true


func _has_pack_gesture(screen: Control) -> bool:
	if not is_instance_valid(screen): return false
	var pack: Node = screen._card_pack_opening
	if is_instance_valid(pack) and not pack.cards.is_empty() and pack.phase != pack.Phase.INSPECTING:
		return true
	var stickers: Node = screen._sticker_pack_opening
	return is_instance_valid(stickers) and stickers.phase in [stickers.Phase.ENLARGING, stickers.Phase.SEALED, stickers.Phase.PEELING, stickers.Phase.EXTRACTING]


func _has_free_movement(screen: Control) -> bool:
	return is_instance_valid(screen) and (screen._rune_scraper_mode or not screen._click_carry_data.is_empty() or _is_indicator_carrying(screen) or _has_pack_gesture(screen))


func _is_indicator_carrying(screen: Control) -> bool:
	return is_instance_valid(screen.celestial_indicators) and screen.celestial_indicators.is_click_carrying()


func _clear_inspection_point() -> void:
	if is_instance_valid(_inspection): _inspection.set_gamepad_point(Vector2.INF)
	_inspection = null


func _update_toolbox(screen: Control) -> void:
	var travel := Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_LEFT)
	var held := travel > RT_RELEASE_THRESHOLD if _lt_down else travel >= RT_PRESS_THRESHOLD
	if is_instance_valid(_toolbox_screen) and (not held or screen != _toolbox_screen or not is_instance_valid(screen._inspection_overlay)):
		_close_toolbox()
	if held and not is_instance_valid(_toolbox_screen) and is_instance_valid(screen) and screen._inspection_tools_enabled() and not screen.inspection_is_entering():
		_toolbox_screen = screen
		screen.set_inspection_library_expanded(true)
		_focus_item = null
	elif not held and is_instance_valid(screen) and screen._inspection_library_expanded and screen._inspection_tools_enabled():
		screen.set_inspection_library_expanded(false)
	_lt_down = held


func _close_toolbox() -> void:
	if not is_instance_valid(_toolbox_screen): return
	_toolbox_screen._cancel_inspection_carry_from_overlay()
	_toolbox_screen.set_inspection_library_expanded(false)
	_toolbox_screen = null
	_scrape_pressed = false
	_focus_item = null


func _dispatch_button(button: JoyButton, pressed: bool) -> void:
	if not _active or not _window.has_focus(): return
	var screen := _get_gameplay_screen.call() as Control
	var menu := _get_menu.call() as Control
	if button == JOY_BUTTON_A and not pressed and _scrape_pressed:
		_scrape_pressed = false
		if is_instance_valid(screen): screen.set_rune_scrape_pressed(false, _pointer)
		return
	if not pressed or not _window.get_embedded_subwindows().is_empty(): return
	if button == JOY_BUTTON_START:
		_send_key(KEY_ESCAPE)
		return
	if menu == null and _dispatch_gameplay_button(screen, button): return
	_sync_focus(screen, menu)
	if DIRECTION_BUTTONS.has(button):
		_move_focus(screen, menu, DIRECTION_BUTTONS[button])
	elif button == JOY_BUTTON_A and _usable(_focus_item):
		_activate_focus(screen)
	elif button == JOY_BUTTON_B:
		if _usable(_focus_item) and (_focus_item is CardView or _focus_item is EquipmentIndicator or (_focus_item is ShopOfferView and _focus_item.inspectable)):
			if is_instance_valid(screen) and screen.can_hover_paused_battle() and not _focus_item is EquipmentIndicator:
				screen.open_paused_card_inspection_at(_focus_rect(_focus_item).get_center())
			else:
				_click_control(_focus_item, MOUSE_BUTTON_RIGHT)
		else:
			_send_key(KEY_ESCAPE)


func _dispatch_gameplay_button(screen: Control, button: JoyButton) -> bool:
	if not is_instance_valid(screen): return false
	if _initial_pack_prompt(screen) != null:
		return button != JOY_BUTTON_A and not DIRECTION_BUTTONS.has(button)
	var stickers: Node = screen._sticker_pack_opening
	if is_instance_valid(stickers):
		if button == JOY_BUTTON_A and stickers.phase in [stickers.Phase.REVEALED, stickers.Phase.EMPTY_REVEALED]: stickers.collect()
		return true
	if _has_pack_gesture(screen):
		if button == JOY_BUTTON_A and is_instance_valid(screen._card_pack_opening):
			screen._card_pack_opening.auto_tear()
		return true
	if _is_indicator_carrying(screen):
		if button == JOY_BUTTON_A: screen.celestial_indicators.finish_drop(_pointer)
		elif button == JOY_BUTTON_B: screen.celestial_indicators.cancel_carry()
		return true
	if button == JOY_BUTTON_B and (is_instance_valid(screen._inspection_overlay) or not screen._click_carry_data.is_empty()):
		_scrape_pressed = false
		if not screen._cancel_inspection_carry_from_overlay():
			screen._close_card_inspection()
			if screen == _toolbox_screen and screen._inspection_closing:
				screen._last_minion_inspection_library_expanded = false
				_toolbox_screen = null
		return true
	if screen._rune_scraper_mode:
		if button == JOY_BUTTON_A:
			screen.set_rune_scrape_pressed(true, _pointer)
			_scrape_pressed = true
		return true
	if not screen._click_carry_data.is_empty():
		if button == JOY_BUTTON_A: screen._commit_click_carry(_pointer)
		return true
	if button == JOY_BUTTON_Y:
		if screen == _toolbox_screen and not is_instance_valid(screen._emblem_fusion_overlay):
			screen._toggle_rune_scraper_mode()
			if screen._rune_scraper_mode:
				_action_screen = screen
				_pointer = screen._inspection_surface.card_canvas_point(screen._inspection_card_view.card_size * Vector2(0.5, 0.75))
				screen.move_gamepad_scraper(_pointer)
		elif not is_instance_valid(screen._inspection_overlay):
			_sync_focus(screen, null)
			if not _cycle_card_indicator(screen): _send_key(KEY_SPACE)
		return true
	if button in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER] and not is_instance_valid(screen._inspection_overlay):
		var direction := -1 if button == JOY_BUTTON_LEFT_SHOULDER else 1
		if screen.current_phase == screen.GamePhase.BATTLE:
			screen._on_battle_speed_slot_selected(clampi(screen.battle_speed_index + direction, 0, screen.BATTLE_SPEED_MULTIPLIERS.size() - 1) + 1)
			return true
		if _focus_area == &"collection":
			screen.turn_collection_page(screen.current_collection_page + direction, &"gamepad")
			return true
	if button == JOY_BUTTON_A and is_instance_valid(screen._card_pack_opening) and is_instance_valid(screen._inspection_card_view) and not screen._inspection_library_expanded and not is_instance_valid(screen._emblem_fusion_overlay):
		_click_at(screen._inspection_surface.card_canvas_point(screen._inspection_card_view.card_size * 0.5), MOUSE_BUTTON_LEFT)
		return true
	return false


func _initial_pack_prompt(screen: Control) -> Control:
	var maze: ShortMazeController = screen.maze_controller
	if maze != null and is_instance_valid(maze._initial_pack_prompt) and maze._initial_pack_prompt.is_visible_in_tree():
		return maze._initial_pack_prompt
	return null


func _update_right_trigger(input_active: bool) -> void:
	var travel := Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_RIGHT)
	if not _rt_down:
		if travel < RT_PRESS_THRESHOLD:
			return
		_rt_down = true
		if input_active:
			_rt_screen = _get_gameplay_screen.call()
			_rt_pressed_at = Time.get_ticks_msec()
			_rt_can_charge = is_instance_valid(_rt_screen) and _rt_screen.can_gamepad_start_battle()
			if _rt_can_charge: _rt_screen.start_battle_button.set_gamepad_charging(true)
	_rt_down = travel > RT_RELEASE_THRESHOLD
	if not is_instance_valid(_rt_screen) or _initial_pack_prompt(_rt_screen) != null:
		_cancel_right_trigger()
		return
	if not input_active or _get_gameplay_screen.call() != _rt_screen or (_rt_can_charge and not _rt_screen.can_gamepad_start_battle()):
		_cancel_right_trigger()
		return
	var now := Time.get_ticks_msec()
	var elapsed := now - _rt_pressed_at
	if elapsed >= RT_HOLD_MS:
		var screen := _rt_screen
		var start := _rt_can_charge
		_cancel_right_trigger()
		if start:
			screen.start_battle_button.activate_with_press()
	elif not _rt_down:
		_rt_screen.try_switch_world_view()
		_cancel_right_trigger()
	elif _rt_can_charge and now - _rt_last_vibration >= RT_VIBRATION_UPDATE_MS:
		_rt_last_vibration = now
		var progress := float(elapsed) / RT_HOLD_MS
		var strength := RT_VIBRATION_START.lerp(RT_VIBRATION_PEAK, progress)
		Input.start_joy_vibration(_device, strength.x, strength.y, RT_VIBRATION_DURATION)


func _cancel_right_trigger() -> void:
	if _rt_can_charge:
		Input.stop_joy_vibration(_device)
		if is_instance_valid(_rt_screen): _rt_screen.start_battle_button.set_gamepad_charging(false)
	_rt_can_charge = false
	_rt_screen = null
	_rt_last_vibration = -RT_VIBRATION_UPDATE_MS


func _sync_focus(screen: Control, menu: Control) -> void:
	var context := _current_context(screen, menu)
	var world: int = screen.current_world_view if context == screen and is_instance_valid(screen) else -1
	if context != _focus_context or world != _world_view:
		_focus_context = context
		_world_view = world
		_focus_item = null
		_next_focus_retry = 0
	if not is_instance_valid(context) or _is_world_moving(screen): return
	if _usable(_focus_item):
		if world < 0 or not _focus_item is CardView or not _world_cover_bounds(screen).has_point(_focus_rect(_focus_item).get_center()):
			return
		_focus_item = null
	var now := Time.get_ticks_msec()
	if now < _next_focus_retry: return
	_next_focus_retry = now + FOCUS_RETRY_MS
	var targets := _targets(screen, menu)
	if targets.is_empty(): return
	var saved: Dictionary = _world_focus.get(_world_view, {}) if world >= 0 and _remembered_screen_id == screen.get_instance_id() else {}
	var match_entry := _restore_world_focus(targets, saved)
	_set_focus(screen, match_entry)


func _current_context(screen: Control, menu: Control) -> Control:
	if is_instance_valid(menu): return menu
	if not is_instance_valid(screen): return null
	for overlay: Control in [screen._emblem_fusion_overlay, screen._toolbox_overlay, screen._inspection_overlay]:
		if is_instance_valid(overlay): return overlay
	var arrival := _initial_pack_prompt(screen)
	if arrival != null: return arrival
	if screen.maze_controller != null:
		var maze: ShortMazeController = screen.maze_controller
		var table: Control = maze._event_table
		if is_instance_valid(table):
			if is_instance_valid(table._modal): return table._modal
			if _usable(maze._panel) and not table.gamepad_options_ready(): return maze._panel
	if screen.current_phase == screen.GamePhase.RESULT and not screen._viewing_result_battlefield:
		if screen.battle_result_panel.is_visible_in_tree(): return screen.battle_result_panel
		if screen.maze_controller != null and is_instance_valid(screen.maze_controller._panel) and screen.maze_controller._panel.is_visible_in_tree():
			return screen.maze_controller._panel
		return null
	return screen


func _targets(screen: Control, menu: Control) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var context := _current_context(screen, menu)
	if not is_instance_valid(context): return entries
	if context != screen:
		if is_instance_valid(screen) and screen.maze_controller != null and context == screen.maze_controller._initial_pack_prompt:
			_add_target(entries, screen.maze_controller._initial_pack_button, &"menu")
		elif is_instance_valid(screen) and context == screen._emblem_fusion_overlay:
			# 合成表面的按钮由弹层统一命中，不直接接收 GUI 鼠标事件。
			_add_target(entries, context._confirm, &"menu")
			_add_target(entries, context._cancel, &"menu")
		elif is_instance_valid(screen) and (context == screen._toolbox_overlay or (context == screen._inspection_overlay and screen._inspection_library_expanded)):
			for node: Node in screen.emblem_library.find_children("*", "Control", true, false):
				if node is StickerEntry and node.drag_enabled:
					_add_target(entries, node, &"toolbox")
			var delivery: Control = screen.maze_controller._event_item_delivery if screen.maze_controller != null else null
			if is_instance_valid(delivery) and delivery.get_parent() == context:
				for node: Node in delivery.find_children("*", "Control", true, false):
					if node is StickerEntry and node.drag_enabled: _add_target(entries, node, &"toolbox")
		else:
			var table: Control = screen.maze_controller._event_table if is_instance_valid(screen) and screen.maze_controller != null else null
			var waiting_for_options: bool = is_instance_valid(table) and (context == table._modal or context == screen.maze_controller._panel) and not table.gamepad_options_ready()
			if not waiting_for_options:
				_add_buttons(entries, context, &"menu")
		return entries
	if not screen.startup_complete or screen.is_page_turning() or screen._inspection_closing: return entries
	var shop: Control = screen.ordinary_shop_panel if screen.ordinary_shop_open else null
	var maze_panel: Control = screen.maze_controller._panel if screen.maze_controller != null else null
	var cover: Control = shop if _usable(shop) else maze_panel
	if screen.battle_result_panel.visible: cover = screen.battle_result_panel
	var cover_bounds := _world_cover_bounds(screen)
	if not screen._viewing_result_battlefield:
		for slot: Control in screen._get_collection_card_slots():
			_add_world_card(entries, slot.get_child(0) as CardView, &"collection", cover_bounds)
	for pair: Array in [[screen.front_row, &"front_row"], [screen.back_row, &"back_row"], [screen.enemy_front_row, &"enemy_front"], [screen.enemy_back_row, &"enemy_back"]]:
		var row := pair[0] as BattlefieldRow
		if not _usable(row): continue
		for slot: BoardSlot in row.get_squads():
			for card: CardView in slot.get_card_views(): _add_world_card(entries, card, pair[1], cover_bounds)
	if screen._viewing_result_battlefield:
		_add_target(entries, screen._return_to_result_button, &"result_return")
		return entries
	if _usable(cover):
		var area := &"shop" if cover == shop else &"table"
		var table: Control = screen.maze_controller._event_table if screen.maze_controller != null else null
		if cover == shop or not is_instance_valid(table) or table.gamepad_options_ready():
			_add_buttons(entries, cover, area)
		if cover == shop:
			entries = entries.filter(func(entry: Dictionary): return entry.item != screen._shop_procurement_button)
			for node: Node in shop.find_children("*", "Control", true, false):
				if node is ShopOfferView:
					_add_target(entries, node, area)
	for button: Control in [screen.start_battle_button, screen.ordinary_shop_entry_button]:
		_add_target(entries, button, &"controls")
	_add_target(entries, get_parent().display_mode_option, &"controls")
	if _usable(screen.battle_speed_bar): _add_buttons(entries, screen.battle_speed_bar, &"controls")
	return entries


func _add_buttons(entries: Array[Dictionary], parent: Control, area: StringName) -> void:
	for node: Node in parent.find_children("*", "Control", true, false):
		if node.name == &"InspectionLibraryToggle" or node.get_parent().name in [&"CollectionFilterLayer", &"ProcurementActions"]: continue
		if (node is BaseButton or node is HSlider) and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_add_target(entries, node, area)


func _world_cover_bounds(screen: Control) -> Rect2:
	for panel: Control in [screen.battle_result_panel, screen.ordinary_shop_panel, screen.maze_controller._panel if screen.maze_controller != null else null]:
		if is_instance_valid(panel) and panel.is_visible_in_tree(): return _focus_rect(panel)
	return Rect2()


func _add_world_card(entries: Array[Dictionary], card: CardView, area: StringName, cover: Rect2) -> void:
	if is_instance_valid(card) and card.modulate.a > 0.0 and not cover.has_point(_focus_rect(card).get_center()):
		_add_target(entries, card, area)


func _add_target(entries: Array[Dictionary], item: Control, area: StringName) -> void:
	if _usable(item): entries.append({"item": item, "area": area, "point": _focus_rect(item).get_center()})


func _usable(item: Variant) -> bool:
	# 放牌和贴纸结算会立即重建显示节点，旧焦点可能已释放。
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not item.is_visible_in_tree() or item.size.x <= 0.0 or item.size.y <= 0.0: return false
	if item is BaseButton and (item.disabled or item.modulate.a < 0.99): return false
	var point := _focus_rect(item).get_center()
	var ancestor: Node = item.get_parent()
	while ancestor is Control:
		if ancestor is ScrollContainer and not _focus_rect(ancestor).has_point(point): return false
		ancestor = ancestor.get_parent()
	return Rect2(Vector2.ZERO, Vector2(_game_viewport.size)).has_point(point)


func _focus_rect(item: Control) -> Rect2:
	var bounds := item.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, item.size)
	if item.get_viewport() == _window:
		var render_transform: Transform2D = get_parent().render_container.get_global_transform_with_canvas()
		return render_transform.affine_inverse() * bounds
	return bounds


func _focus_identity(item: Control) -> StringName:
	if item is CardView and item.get_owned_card() != null: return item.get_owned_card().instance_id
	return item.name


func _restore_world_focus(targets: Array[Dictionary], saved: Dictionary) -> Dictionary:
	if saved.is_empty(): return targets.front()
	var best: Dictionary = targets.front()
	var distance := INF
	for entry: Dictionary in targets:
		if entry.area != saved.area: continue
		if _focus_identity(entry.item) == saved.id: return entry
		var offset: float = entry.point.distance_squared_to(saved.point)
		if offset < distance:
			best = entry
			distance = offset
	return best


func _set_focus(screen: Control, entry: Dictionary) -> void:
	_focus_item = entry.item
	_focus_area = entry.area
	if not _focus_item is EquipmentIndicator: _indicator_card = null
	if _world_view < 0 or not is_instance_valid(screen): return
	if _remembered_screen_id != screen.get_instance_id():
		_remembered_screen_id = screen.get_instance_id()
		_world_focus.clear()
	_world_focus[_world_view] = {"id": _focus_identity(_focus_item), "area": _focus_area, "point": entry.point}


func _cycle_card_indicator(screen: Control) -> bool:
	var card := _focus_item as CardView if _usable(_focus_item) else null
	if _usable(_focus_item) and _focus_item is EquipmentIndicator:
		card = _indicator_card if is_instance_valid(_indicator_card) else null
	if not is_instance_valid(card): return false
	var slot := card._drag_source_slot as BoardSlot
	if not is_instance_valid(slot): return false
	var choices: Array[Control] = [card]
	var squad := slot.get_display_data()
	if squad == null: return false
	for item: OwnedCard in squad.get_equipped_items():
		var view := slot.get_equipment_indicator(item)
		if _usable(view): choices.append(view)
	for attachment: Dictionary in squad.indicator_attachments:
		var view := slot.get_celestial_indicator(attachment.indicator.instance_id)
		if _usable(view): choices.append(view)
	if choices.size() == 1: return false
	var next := choices[(choices.find(_focus_item) + 1) % choices.size()]
	_indicator_card = card
	if next == card:
		_set_focus(screen, {"item": card, "area": _focus_area, "point": _focus_rect(card).get_center()})
	else:
		_focus_item = next
	return true


func _move_focus(screen: Control, menu: Control, direction: Vector2) -> void:
	if menu == null and (_has_free_movement(screen) or _is_world_moving(screen)): return
	if _usable(_focus_item) and _focus_item is HSlider and direction.x != 0.0:
		_focus_item.value += _focus_item.step * direction.x
		return
	var targets := _targets(screen, menu)
	if targets.is_empty(): return
	if not _usable(_focus_item):
		_set_focus(screen, targets.front())
		return
	if menu == null and is_instance_valid(screen) and screen._viewing_result_battlefield:
		if (_focus_area == &"enemy_front" and direction == Vector2.DOWN) or (_focus_area == &"front_row" and direction == Vector2.UP):
			if _usable(screen._return_to_result_button):
				_set_focus(screen, {"item": screen._return_to_result_button, "area": &"result_return", "point": _focus_rect(screen._return_to_result_button).get_center()})
			return
	var current := _indicator_card if _focus_item is EquipmentIndicator and _usable(_indicator_card) else _focus_item
	var origin := _focus_rect(current).get_center()
	var world := _world_view >= 0
	if world and direction.x != 0.0:
		var row := targets.filter(func(entry: Dictionary):
			return entry.area == _focus_area and (_focus_area != &"collection" or absf(entry.point.y - origin.y) < FOCUS_ROW_BAND))
		row.sort_custom(func(a: Dictionary, b: Dictionary):
			var a_line := roundi(a.point.y / FOCUS_ROW_BAND)
			var b_line := roundi(b.point.y / FOCUS_ROW_BAND)
			return a.point.x < b.point.x if a_line == b_line else a_line < b_line)
		var index := row.find_custom(func(entry: Dictionary): return entry.item == current)
		if index >= 0: _set_focus(screen, row[clampi(index + int(direction.x), 0, row.size() - 1)])
		return
	var best: Dictionary = {}
	var best_score := INF
	for entry: Dictionary in targets:
		var offset: Vector2 = entry.point - origin
		if world and entry.area == _focus_area and (_focus_area != &"collection" or absf(offset.y) < FOCUS_ROW_BAND): continue
		var forward := offset.dot(direction)
		if forward <= 3.0: continue
		var score := forward + absf(offset.cross(direction)) * (0.45 if world else 1.9)
		if world and _focus_area == &"collection" and entry.area == &"collection":
			score = -10000.0 + forward + absf(offset.x) * 2.0 # 收藏内先找相邻排的最近同列
		if score < best_score:
			best_score = score
			best = entry
	if not best.is_empty(): _set_focus(screen, best)


func _set_shop_focus(target: Control) -> void:
	var offer := target as ShopOfferView
	var stack := offer.get_parent() as ShopPackStackView if offer != null else null
	if _focused_stack != stack and is_instance_valid(_focused_stack): _focused_stack.set_gamepad_offer(null)
	_focused_stack = stack
	if stack != null: stack.set_gamepad_offer(offer)


func _update_hover_target(target: Control, screen: Control) -> void:
	if is_instance_valid(_visual_target) and _visual_target.has_method("set_gamepad_hover"):
		_visual_target.set_gamepad_hover(false)
	_set_shop_focus(target)
	if target is EventCardView:
		# 接管三张候选，清掉鼠标切换前可能留下的上抬。
		for choice: Node in target.get_parent().get_children():
			if choice is EventCardView: choice.set_gamepad_hover(choice == target)
	elif is_instance_valid(target) and target.has_method("set_gamepad_hover"):
		target.set_gamepad_hover(true)
	var table: Control = screen.maze_controller._event_table if is_instance_valid(screen) and screen.maze_controller != null else null
	if is_instance_valid(table) and is_instance_valid(table._deck) and (target == table._deck or _visual_target == table._deck):
		table.set_deck_hover(target == table._deck)


func _hide_focus_popup() -> void:
	var popup := get_tree().get_first_node_in_group(&"card_effect_popup") as CanvasLayer
	if popup != null: popup.hide_gamepad()


func _update_focus_visual(hidden: bool, screen: Control = null, look: Vector2 = Vector2.ZERO) -> void:
	var target := _focus_item if not hidden and _usable(_focus_item) else null
	var pack: TextureButton
	if target is TextureButton and is_instance_valid(screen) and screen.maze_controller != null:
		if target == screen.maze_controller._initial_pack_button: pack = target
	if target != _visual_target:
		if is_instance_valid(_focus_fade): _focus_fade.kill()
		if is_instance_valid(_pack_marker): _pack_marker.hide()
		_hide_focus_popup()
		_update_hover_target(target, screen)
		_previous_event_card = _visual_target as EventCardView if is_instance_valid(_visual_target) else null
		_visual_target = target
		_focus_started = Time.get_ticks_msec()
		if target != null:
			_previous_marker.visible = _marker.visible
			_previous_marker.position = _marker.position
			_previous_marker.size = _marker.size
			_previous_marker.modulate = _marker.modulate
			_previous_marker.material = _marker.material.duplicate()
			var marker := _marker if pack == null else _attach_pack_glow(pack)
			marker.modulate.a = 0.0
			marker.show()
			_focus_fade = create_tween().set_parallel(true)
			_focus_fade.tween_property(marker, "modulate:a", 1.0, FOCUS_FADE_SECONDS)
			_focus_fade.tween_property(_previous_marker, "modulate:a", 0.0, FOCUS_FADE_SECONDS)
		else:
			_previous_marker.hide()
	_marker.visible = target != null and pack == null
	if not _marker.visible: return
	if target is ShopOfferView: target.set_gamepad_look(look)
	var render_transform: Transform2D = get_parent().render_container.get_global_transform_with_canvas()
	var spread := FOCUS_SPREAD * render_transform.get_scale().x
	if is_instance_valid(_previous_event_card) and _previous_marker.visible and _previous_marker.modulate.a > 0.0:
		_place_focus_glow(_previous_marker, _previous_event_card, render_transform, spread)
	_place_focus_glow(_marker, target, render_transform, spread)
	_marker.material.set_shader_parameter("pulse_weight", 1.0 if target is CardView or target is EventCardView or target is ShopOfferView else 0.0)
	_update_focus_popup(target)


func _place_focus_glow(marker: ColorRect, target: Control, render_transform: Transform2D, spread: float) -> void:
	var visual := target._visual as Control if target is ShopOfferView and is_instance_valid(target._visual) else target
	var bounds := _focus_rect(visual)
	var texture: Texture2D
	var projection: InspectionCardSurface
	if target is EventCardView:
		bounds = target.get_global_transform_with_canvas() * target.choice_visual_rect()
		texture = target.FRONT if target.face_up else target.BACK
	elif target is ShopOfferView and is_instance_valid(target._hover_surface):
		projection = target._hover_surface
		bounds = _focus_rect(projection)
		texture = projection.texture
	elif target is CardView:
		var mask := FocusOutline.card_mask(target)
		if not mask.is_empty():
			texture = mask.texture
			bounds = target.get_global_transform_with_canvas() * (mask.bounds as Rect2)
			if target.get_viewport() == _window: bounds = render_transform.affine_inverse() * bounds
	elif visual != target and visual.get_child_count() > 0 and visual.get_child(0) is TextureRect:
		var art := visual.get_child(0) as TextureRect
		bounds = _focus_rect(art)
		texture = art.texture
	var shape := render_transform * bounds
	var glow := shape.grow(spread)
	marker.position = glow.position
	marker.size = glow.size
	var shader := marker.material as ShaderMaterial
	shader.set_shader_parameter("panel_size", glow.size)
	shader.set_shader_parameter("spread", spread)
	shader.set_shader_parameter("inner_pixel", render_transform.get_scale().x)
	shader.set_shader_parameter("use_silhouette", texture != null)
	shader.set_shader_parameter("silhouette_texture", texture)
	shader.set_shader_parameter("silhouette_rect", Vector4(spread, spread, shape.size.x, shape.size.y))
	shader.set_shader_parameter("projected_shape", projection != null)
	shader.set_shader_parameter("projection_force", projection.force if projection != null else Vector2.ZERO)


func _attach_pack_glow(pack: TextureButton) -> ColorRect:
	if not is_instance_valid(_pack_marker) or _pack_marker.get_parent() != pack:
		if is_instance_valid(_pack_marker): _pack_marker.queue_free()
		_pack_marker = _make_focus_glow("InitialPackGamepadFocus", 0)
		pack.add_child(_pack_marker)
	# 子节点和包装共用坐标系，Tween 更新时投影变换也在同一帧生效。
	var bounds := Rect2(Vector2.ZERO, pack.size).grow(FOCUS_SPREAD)
	_pack_marker.position = bounds.position
	_pack_marker.size = bounds.size
	_pack_marker.material.set_shader_parameter("panel_size", bounds.size)
	_pack_marker.material.set_shader_parameter("spread", FOCUS_SPREAD)
	_pack_marker.material.set_shader_parameter("inner_pixel", 1.0 / pack.get_global_transform_with_canvas().get_scale().x)
	_pack_marker.material.set_shader_parameter("pulse_weight", 1.0)
	_pack_marker.material.set_shader_parameter("silhouette_texture", pack.texture_normal)
	_pack_marker.material.set_shader_parameter("use_silhouette", true)
	_pack_marker.material.set_shader_parameter("silhouette_rect", Vector4(FOCUS_SPREAD, FOCUS_SPREAD, pack.size.x, pack.size.y))
	return _pack_marker


func _update_focus_popup(target: Control) -> void:
	if target is StickerEntry:
		if not target.get_hovered_sticker_help().is_empty(): EffectPopup.shared(get_tree()).show_sticker(target, true)
		return
	var source: Control = target
	if target is ShopOfferView:
		source = target._hover_surface.card if is_instance_valid(target._hover_surface) else null
	if not (source is CardView or source is CelestialIndicatorView): return
	var delay: float = source.hover_effect_delay_seconds if source is CardView else 0.25
	if (Time.get_ticks_msec() - _focus_started) * 0.001 >= delay:
		EffectPopup.shared(get_tree()).show_gamepad_card(source, target)


func _is_world_moving(screen: Control) -> bool:
	return _world_view >= 0 and is_instance_valid(screen) and is_instance_valid(screen._view_tween) and screen._view_tween.is_running()


func _activate_focus(screen: Control) -> void:
	if _focus_item is OptionButton:
		_focus_item.show_popup()
		var popup: PopupMenu = _focus_item.get_popup()
		if popup.get_focused_item() < 0:
			for index: int in popup.item_count:
				if not popup.is_item_disabled(index):
					popup.set_focused_item(index)
					break
		return
	var target := _focus_item
	if is_instance_valid(screen) and target == screen.start_battle_button:
		target.activate_with_press()
		return
	_pointer = _focus_rect(target).get_center()
	_click_control(target, MOUSE_BUTTON_LEFT)
	if is_instance_valid(screen) and (not screen._click_carry_data.is_empty() or _is_indicator_carrying(screen)):
		screen.gamepad_carry_position = _pointer
		_action_screen = screen


func _click_control(target: Control, button: MouseButton) -> void:
	var center := target.size * 0.5
	if target is CardView or target is EquipmentIndicator or target is StickerEntry or target is ShopOfferView:
		# 堆叠卡可以部分重合。直接把确认交给高亮的卡，点击携带信号仍走原入口。
		var input := _mouse_event(center, button, true)
		target._gui_input(input)
		if is_instance_valid(target) and button == MOUSE_BUTTON_LEFT:
			target._gui_input(_mouse_event(center, button, false))
		return
	_click_at(_focus_rect(target).get_center(), button)


func _mouse_event(point: Vector2, button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var input := InputEventMouseButton.new()
	input.position = point
	input.global_position = point
	input.button_index = button
	input.pressed = pressed
	input.button_mask = (1 << (button - 1)) if pressed else 0
	return input


func _click_at(point: Vector2, button: MouseButton) -> void:
	var transform: Transform2D = get_parent().render_container.get_global_transform_with_canvas()
	point = transform * point
	_injecting = true
	_window.push_input(_mouse_event(point, button, true), true)
	if _window.get_embedded_subwindows().is_empty():
		_window.push_input(_mouse_event(point, button, false), true)
	_injecting = false


func _send_key(code: Key) -> void:
	_injecting = true
	var input := InputEventKey.new()
	input.keycode = code
	input.pressed = true
	_window.push_input(input, true)
	input = input.duplicate()
	input.pressed = false
	_window.push_input(input, true)
	_injecting = false


func _on_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == _device: _cancel_gamepad_actions()


func _exit_tree() -> void:
	if _active:
		if _rt_can_charge: Input.stop_joy_vibration(_device)
		Input.mouse_mode = _previous_mouse_mode


func _cancel_gamepad_actions() -> void:
	if not _active: return
	_active = false
	_cancel_right_trigger()
	_rt_down = false
	_lt_down = false
	_stick_nav = Vector2.ZERO
	_clear_inspection_point()
	_close_toolbox()
	if is_instance_valid(_action_screen):
		_action_screen._cancel_click_carry()
		if _is_indicator_carrying(_action_screen): _action_screen.celestial_indicators.cancel_carry()
		if _action_screen._rune_scraper_mode: _action_screen._finish_rune_scraper_mode()
	_action_screen = null
	var screen := _get_gameplay_screen.call() as Control
	if is_instance_valid(screen) and is_instance_valid(screen._card_pack_opening): screen._card_pack_opening.release_gamepad_seal()
	if is_instance_valid(_marker): _update_focus_visual(true)
	Input.mouse_mode = _previous_mouse_mode
	_device = -1
