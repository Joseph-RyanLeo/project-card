extends Control

## 教学展示层：对白复用英雄气泡，操作说明靠近当前目标；不负责保存任务。
signal confirmed
signal teaching_completed
signal story_completed
signal target_activated(event: InputEventMouseButton)

const SpotlightShader = preload("res://shaders/hero_speech_spotlight.gdshader")
const FocusOutline = preload("res://scripts/ui/focus_outline.gd")
const SPOTLIGHT_PADDING := Vector2(22, 18) # 亮圈比英雄和气泡联合边界多出的柔和留白
const Portrait = preload("res://scripts/ui/character_portrait.gd")
const Speech = preload("res://scripts/ui/hero_speech_bubble.gd")
const Typography = preload("res://scripts/ui/ui_typography.gd")
const Style = preload("res://scripts/ui/menu_style.gd")
const CANVAS_SIZE := Vector2(1280, 720) # 教学与游戏共用的逻辑画布
const PANEL_WIDTH: float = 348.0 # 浅色操作提示框宽度
const PANEL_GAP: float = 14.0 # 提示框与被提示区域之间的间距
const SCREEN_MARGIN: float = 12.0 # 提示框距画布边缘的留白
const DIM_ALPHA: float = 0.28 # 教学时背景轻微压暗，目标区域保留亮度
const SOLO_GLOW_GAIN := 1.6 # 取消暗幕时增强目标轮廓对比
const PANEL_FILL := Color("f2e2c4") # 操作说明的浅色底板
const TEXT_COLOR := Color("49382a") # 浅色提示框内的深色文字
const BORDER_COLOR := Color("b68c56") # 文字提示框的边缘颜色
const FADE_SECONDS: float = 0.20 # 提示框与暗幕淡入淡出的时长
const FOCUS_BREATH_SECONDS := 1.8 # 被提示目标的呼吸光周期
const STORY_READ_SECONDS: float = 3.0 # 每句英雄对白全部显示后保留的阅读时间
const MAX_FOCUS_REGIONS := 12 # 一次可照亮的符文、纹章及属性区域数，须与shader一致

var title: String
var content: Dictionary
var focus_rect: Rect2
var speaker: Control
var speaker_resolver: Callable
var portrait_resolver: Callable
var portrait: Control
var inspection_dim: ColorRect
var instruction_label: Label
var speech: Control
var panel: PanelContainer
var _surface: Control
var _focus_material: ShaderMaterial
var _original_dim_material: Material
var _speech_spotlight_strength := 0.0
var _focus_time := 0.0
var _focus_texture: Texture2D
var action_rect := Rect2()
var speech_only := false
var _hero_lines: Array[Dictionary] = []
var _hero_line_index := 0
var _teaching_done := false
var _hero_done := true
var _hero_line_transitioning := false
var _narrative_done := true
var _closing := false
var _save_failed := false
var _transition: Tween
var _line_timing: Tween
var _narrative_timing: Tween
var _portrait_layer: CanvasLayer
var complete_on_click := false
var follow_target: Control
var activate_follow_target := false
var silhouette_target: Control
var resolve_silhouette: Callable
var resolve_focus: Callable
var _focus_regions: Array[Rect2] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface = Control.new()
	_surface.size = CANVAS_SIZE
	speech_only = String(content.get("instruction", "")).is_empty() and String(content.get("story_text", "")).is_empty() and not content.get("dialogue", []).is_empty()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if speech_only:
		z_index = 4001 # 纯对白的保存失败提示高于检视底板
		add_child(_surface)
	else:
		var layer := CanvasLayer.new()
		layer.layer = 3800 # 操作提示高于普通检视，低于Esc暂停菜单
		add_child(layer)
		layer.add_child(_surface)
	portrait = Portrait.new()
	portrait.name = "OffstagePortrait"
	_portrait_layer = CanvasLayer.new()
	_portrait_layer.layer = 3801 # 场外头像高于检视和教学暗幕，低于Esc菜单
	add_child(_portrait_layer)
	_portrait_layer.add_child(portrait)
	visibility_changed.connect(func(): _portrait_layer.visible = is_visible_in_tree())
	_build_focus()
	panel = PanelContainer.new()
	panel.name = "InstructionPanel"
	panel.custom_minimum_size.x = float(content.get("panel_width", PANEL_WIDTH))
	panel.add_theme_stylebox_override("panel", Style.panel(PANEL_FILL, BORDER_COLOR))
	_surface.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10) # 标题、对白与操作说明之间的间距
	panel.add_child(body)
	var heading := _label(title, 20)
	heading.name = "HintTitle"
	body.add_child(heading)
	var hero_lines: Array[Dictionary] = []
	for line: Dictionary in content.get("dialogue", []): hero_lines.append(line)
	if not String(content.get("story_text", "")).is_empty(): body.add_child(_label(content.story_text, 18))
	instruction_label = _label(String(content.get("instruction", "")), int(content.get("instruction_font_size", 18)))
	instruction_label.name = "InstructionText"
	instruction_label.visible = not instruction_label.text.is_empty()
	body.add_child(instruction_label)
	_teaching_done = instruction_label.text.is_empty()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = not speech_only and not content.get("highlight_only", false)
	if not hero_lines.is_empty():
		_hero_done = false
		_hero_lines = hero_lines
		speech = Speech.new()
		_surface.add_child(speech)
		_show_hero_line()
	var narrative := String(content.get("story_text", ""))
	if not narrative.is_empty():
		_narrative_done = false
		_narrative_timing = create_tween()
		_narrative_timing.tween_interval(maxf(STORY_READ_SECONDS, narrative.length() / 12.0))
		_narrative_timing.tween_callback(func(): _narrative_done = true; _finish_if_ready())
	_surface.modulate.a = 0.0
	_transition = create_tween()
	_transition.tween_property(_surface, "modulate:a", 1.0, FADE_SECONDS)
	_layout_hint.call_deferred()


func complete_teaching() -> void:
	if _teaching_done or _closing: return
	_teaching_done = true
	if is_instance_valid(_transition): _transition.kill()
	_transition = create_tween()
	_transition.tween_property(_surface, "modulate:a", 0.0, FADE_SECONDS)
	teaching_completed.emit()
	_finish_if_ready()


func _finish_if_ready() -> void:
	if _hero_done and _narrative_done and not _closing and not _save_failed: story_completed.emit()
	if _teaching_done and _hero_done and _narrative_done and not _closing and not _save_failed: confirmed.emit()


func show_save_failure() -> void:
	_save_failed = true
	instruction_label.text = "保存失败，请再次点击以重试。"
	instruction_label.show()
	panel.show()
	if is_instance_valid(_transition): _transition.kill()
	_surface.modulate.a = 1.0
	panel.modulate.a = 1.0
	_layout_hint.call_deferred()


func save_recovered() -> void:
	if not _save_failed: return
	_save_failed = false
	instruction_label.text = String(content.get("instruction", ""))
	instruction_label.visible = not instruction_label.text.is_empty()
	panel.visible = not speech_only and not content.get("highlight_only", false)
	if _teaching_done:
		_transition = create_tween()
		_transition.tween_property(_surface, "modulate:a", 0.0, FADE_SECONDS)


func dismiss() -> void:
	if _closing: return
	_closing = true
	set_process_input(false)
	if is_instance_valid(speech): speech.dismiss()
	if is_instance_valid(portrait) and portrait.visible: portrait.dismiss()
	if is_instance_valid(_transition): _transition.kill()
	_transition = create_tween()
	_transition.tween_property(_surface, "modulate:a", 0.0, maxf(FADE_SECONDS, Portrait.DISAPPEAR_SECONDS))
	_transition.tween_callback(queue_free)


func _resolve_scene_speaker(name_text: String) -> Control:
	var target: Control
	if speaker_resolver.is_valid(): target = speaker_resolver.call(name_text)
	elif name_text.begins_with("伊奥恩") or name_text == "主角": target = speaker
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return null
	var area := target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
	return target if area.intersects(Rect2(Vector2.ZERO, CANVAS_SIZE)) else null


func _show_hero_line() -> void:
	var line := _hero_lines[_hero_line_index]
	var target := _resolve_scene_speaker(String(line.speaker))
	if target == null:
		var art: Texture2D = line.get("portrait") as Texture2D
		if art == null and portrait_resolver.is_valid(): art = portrait_resolver.call(String(line.speaker))
		if not portrait.visible:
			await portrait.present(String(line.speaker), art).finished
			if _closing: return
		target = portrait
	speech.speaker_head_inset = 0.0 if target == portrait else Speech.HEAD_INSET
	speech.say(String(line.text), target, 0.0, null, true)
	_hero_line_transitioning = false
	speech._text_reveal.finished.connect(_advance_hero_line_after_pause, CONNECT_ONE_SHOT)
	_layout_hint.call_deferred()


func _advance_hero_line_after_pause() -> void:
	_line_timing = create_tween()
	_line_timing.tween_interval(STORY_READ_SECONDS)
	_line_timing.tween_callback(_finish_hero_line)


func _finish_hero_line() -> void:
	if _closing or _hero_line_transitioning: return
	_hero_line_transitioning = true
	if is_instance_valid(_line_timing): _line_timing.kill()
	speech.dismiss()
	var next := _hero_line_index + 1
	var keep_portrait: bool = next < _hero_lines.size() and _hero_lines[next].speaker == _hero_lines[_hero_line_index].speaker and _resolve_scene_speaker(String(_hero_lines[next].speaker)) == null
	if portrait.visible and not keep_portrait:
		await portrait.dismiss().finished
	else:
		_line_timing = create_tween()
		_line_timing.tween_interval(Speech.FADE_SECONDS)
		await _line_timing.finished
	if _closing: return
	_hero_line_index = next
	if _hero_line_index < _hero_lines.size(): _show_hero_line()
	else:
		_hero_done = true
		_finish_if_ready()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.custom_minimum_size.x = float(content.get("panel_width", PANEL_WIDTH)) - 32.0 # 扣除底板左右留白后的正文宽度
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Typography.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


func _build_focus() -> void:
	if not content.get("dim", true): return
	var teaching := not String(content.get("instruction", "")).is_empty()
	var use_inspection_dim: bool = is_instance_valid(inspection_dim) and inspection_dim.is_visible_in_tree() and not content.get("dialogue", []).is_empty()
	if not teaching and not use_inspection_dim: return
	_focus_material = ShaderMaterial.new()
	_focus_material.shader = SpotlightShader
	_focus_material.set_shader_parameter("speech_enabled", false)
	if use_inspection_dim:
		# 保留原暗幕的节点、颜色和透明度，只在其上打开局部亮区。
		_original_dim_material = inspection_dim.material
		_focus_material.set_shader_parameter("dim_opacity", 1.0)
		_focus_material.set_shader_parameter("use_backdrop_color", true)
		inspection_dim.material = _focus_material
	else:
		var dim := ColorRect.new()
		dim.name = "HintSpotlight"
		dim.size = CANVAS_SIZE
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_focus_material.set_shader_parameter("dim_opacity", 0.0 if content.get("highlight_only", false) else DIM_ALPHA)
		if content.get("highlight_only", false):
			_focus_material.set_shader_parameter("focus_glow_gain", SOLO_GLOW_GAIN)
		dim.material = _focus_material
		_surface.add_child(dim)
	_update_target_focus()


func _exit_tree() -> void:
	if _uses_inspection_dim(): inspection_dim.material = _original_dim_material


func _uses_inspection_dim() -> bool:
	return _focus_material != null and is_instance_valid(inspection_dim) and inspection_dim.material == _focus_material


func set_live_instruction(text: String, regions: Array[Rect2]) -> void:
	if text != instruction_label.text:
		instruction_label.text = text
		_layout_hint.call_deferred()
	_set_focus_regions(regions)


func _set_focus_regions(regions: Array[Rect2]) -> void:
	regions = regions.filter(func(rect: Rect2) -> bool: return rect.has_area())
	if _focus_regions == regions: return
	_focus_regions = regions
	focus_rect = Rect2()
	for rect: Rect2 in regions:
		focus_rect = focus_rect.merge(rect) if focus_rect.has_area() else rect
	if _focus_material != null:
		var packed := PackedVector4Array()
		packed.resize(MAX_FOCUS_REGIONS)
		var count := mini(regions.size(), MAX_FOCUS_REGIONS)
		for index: int in count:
			var rect := regions[index]
			packed[index] = Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
		_focus_material.set_shader_parameter("focus_regions", packed)
		_focus_material.set_shader_parameter("focus_region_count", count)
	_layout_hint()


func _update_target_focus() -> void:
	if _focus_material == null: return
	var active := not String(content.get("instruction", "")).is_empty() and focus_rect.has_area()
	_focus_material.set_shader_parameter("focus_enabled", active)
	if not active: return
	_focus_material.set_shader_parameter("focus_rect", Vector4(focus_rect.position.x, focus_rect.position.y, focus_rect.size.x, focus_rect.size.y))
	_focus_material.set_shader_parameter("focus_breath", 0.5 - 0.5 * cos(_focus_time * TAU / FOCUS_BREATH_SECONDS))
	if not is_instance_valid(silhouette_target) or not silhouette_target.is_visible_in_tree() or silhouette_target.size.x <= 0.0 or silhouette_target.size.y <= 0.0:
		_focus_material.set_shader_parameter("use_silhouette", false)
		return
	var texture: Texture2D
	if silhouette_target is TextureButton:
		texture = silhouette_target.texture_normal
	elif silhouette_target is TextureRect:
		texture = FocusOutline.frame_mask(silhouette_target.texture)
	_focus_material.set_shader_parameter("use_silhouette", texture != null)
	if texture == null: return
	FocusOutline.set_transform(_focus_material, silhouette_target)
	if texture != _focus_texture:
		_focus_texture = texture
		FocusOutline.set_texture(_focus_material, texture)


func _layout_hint() -> void:
	panel.size = panel.get_combined_minimum_size()
	match String(content.get("placement", "")):
		"bottom_left":
			panel.position = Vector2(SCREEN_MARGIN, CANVAS_SIZE.y - SCREEN_MARGIN - panel.size.y).round()
			return
		"bottom_right":
			panel.position = (CANVAS_SIZE - Vector2.ONE * SCREEN_MARGIN - panel.size).round()
			return
		"top_left":
			panel.position = Vector2(SCREEN_MARGIN, 64.0) # 避开Esc按钮，提示留在工具箱左上方
			return
	if content.get("placement", "") == "right":
		panel.position = Vector2(focus_rect.end.x + PANEL_GAP, focus_rect.position.y).clamp(Vector2.ONE * SCREEN_MARGIN, CANVAS_SIZE - Vector2.ONE * SCREEN_MARGIN - panel.size).round()
		return
	var occupied := focus_rect.merge(speech.get_rect()) if is_instance_valid(speech) else focus_rect
	var candidates: Array[Vector2] = [Vector2(focus_rect.position.x, focus_rect.end.y + PANEL_GAP), Vector2(occupied.position.x - panel.size.x - PANEL_GAP, focus_rect.position.y), Vector2(occupied.end.x + PANEL_GAP, focus_rect.position.y), Vector2(focus_rect.position.x, occupied.position.y - panel.size.y - PANEL_GAP)]
	var bounds := Rect2(Vector2.ONE * SCREEN_MARGIN, CANVAS_SIZE - Vector2.ONE * SCREEN_MARGIN * 2.0)
	for point: Vector2 in candidates:
		var area := Rect2(point, panel.size)
		if bounds.encloses(area) and (not is_instance_valid(speech) or not area.intersects(speech.get_rect())):
			panel.position = point.round()
			return
	# 大目标可能横跨画布；在边界内选择与目标重叠面积最小的位置。
	var least_overlap := INF
	for point: Vector2 in candidates:
		point = point.clamp(bounds.position, (bounds.end - panel.size).max(bounds.position))
		var area := Rect2(point, panel.size)
		var overlap := area.intersection(focus_rect).get_area()
		if is_instance_valid(speech): overlap += area.intersection(speech.get_rect()).get_area()
		if overlap < least_overlap:
			least_overlap = overlap
			panel.position = point.round()


func _update_speaker_spotlight(delta: float) -> void:
	if _focus_material == null: return
	var active := not _closing and is_instance_valid(speech) and speech.visible and is_instance_valid(speech._speaker)
	if _uses_inspection_dim():
		var next := _hero_line_index + 1
		var same_speaker_next: bool = (
			not _closing
			and _speech_spotlight_strength > 0.0
			and next < _hero_lines.size()
			and _hero_lines[next].speaker == _hero_lines[_hero_line_index].speaker
		)
		_speech_spotlight_strength = move_toward(_speech_spotlight_strength, 1.0 if active or same_speaker_next else 0.0, delta / FADE_SECONDS)
		_focus_material.set_shader_parameter("speech_strength", _speech_spotlight_strength)
		_focus_material.set_shader_parameter("speech_enabled", _speech_spotlight_strength > 0.0)
		var backdrop := inspection_dim.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, inspection_dim.size)
		_focus_material.set_shader_parameter("canvas_region", Vector4(backdrop.position.x, backdrop.position.y, backdrop.size.x, backdrop.size.y))
	else:
		_focus_material.set_shader_parameter("speech_enabled", active)
	if not active: return
	var active_speaker: Control = speech._speaker
	var area := active_speaker.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, active_speaker.size)
	area = area.merge(speech.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, speech.size))
	var radius := area.size * 0.5 + SPOTLIGHT_PADDING
	_focus_material.set_shader_parameter("spotlight", Vector4(area.get_center().x, area.get_center().y, radius.x, radius.y))


func _process(delta: float) -> void:
	var menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	var menu_open: bool = menu != null and menu.blocks_gameplay()
	_portrait_layer.visible = is_visible_in_tree() and not menu_open
	# 教学战斗暂停时对白仍播放；只有玩家打开Esc时冻结对白自己的时间。
	var timelines: Array = [_line_timing, _narrative_timing, portrait._motion]
	if is_instance_valid(speech): timelines.append(speech._text_reveal)
	for timeline: Tween in timelines:
		if is_instance_valid(timeline): timeline.set_speed_scale(0.0 if menu_open else 1.0)
	if menu_open: return
	# 收藏刷新会重建卡面；每帧重新找到同一实例的发言者，不重播台词。
	if is_instance_valid(speech) and speech.visible and not _hero_done:
		var active_speaker := portrait if portrait.visible else _resolve_scene_speaker(String(_hero_lines[_hero_line_index].speaker))
		if is_instance_valid(active_speaker): speech._speaker = active_speaker
	_update_speaker_spotlight(delta)
	if resolve_silhouette.is_valid(): silhouette_target = resolve_silhouette.call()
	var rect := focus_rect
	if resolve_focus.is_valid():
		_set_focus_regions(resolve_focus.call())
		rect = focus_rect
	elif is_instance_valid(follow_target): rect = follow_target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, follow_target.size)
	if activate_follow_target and follow_target is BaseButton:
		action_rect = rect if follow_target.is_visible_in_tree() and not follow_target.disabled and not _teaching_done else Rect2()
	if rect != focus_rect:
		focus_rect = rect
		_layout_hint()
	_focus_time = fmod(_focus_time + delta, FOCUS_BREATH_SECONDS)
	_update_target_focus()


func blocks_gameplay() -> bool:
	return not _closing and not _hero_done and content.get("lock_dialogue", false)


func _input(event: InputEvent) -> void:
	if _closing: return
	var pause_menu := get_tree().get_first_node_in_group(&"escape_pause_menus")
	if pause_menu != null and pause_menu.blocks_gameplay(): return
	if blocks_gameplay():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(speech) and speech.visible and not _hero_line_transitioning:
			if speech.finish_reveal(): _advance_hero_line_after_pause()
			else: _finish_hero_line()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if action_rect.has_area() and action_rect.has_point(event.position):
			target_activated.emit(event)
			get_viewport().set_input_as_handled()
		elif _save_failed:
			confirmed.emit()
			get_viewport().set_input_as_handled()
		elif complete_on_click:
			complete_teaching()
			get_viewport().set_input_as_handled()
