class_name BattleFireVisual
extends Node2D

## 显示火的持续伤害／治疗／护甲；状态、每跳和结束时间由战斗控制器提供。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const FIRE_SHADER: Shader = preload("res://shaders/battle_pixel_fire.gdshader")
const SIDE_MARGIN := 16.0 # 火焰伸出卡面左右边缘的逻辑像素
const CANVAS_WIDTH_SCALE := 2.0 # 横向绘制留白，容纳摆动与每跳膨胀后的完整火焰
const FOREGROUND_DEPTH := 14.0 # 外侧火团向卡面内延伸的最大逻辑像素，只在卡外确实有火时显示
const FOREGROUND_TIP_DEPTH := 14.0 # 内侧焰尖额外伸入卡面的最大逻辑像素，让三层尖形更明显
const FOREGROUND_OPACITY := 0.60 # 卡面前景相对外侧火团的透明度，允许透出卡图和符文等元素
const CARD_HEIGHT := 136.0 # 基准卡面高度，预览放大时火焰也按同一比例放大
const BELOW_FRACTION := 0.04 # 火焰绘制区域位于卡面底边以下的比例
const FIRE_OPACITY := 0.82 # 卡牌背后火团的整体透明度
const APPEAR_SECONDS := 0.12 # 火焰出现所需战斗秒数
const PULSE_SECONDS := 0.28 # 每跳或终结增强的战斗秒数
const WHITE_FLASH_SECONDS := 0.12 # 每跳结算时卡面瞬白并恢复的战斗秒数
const FLASH_CORNER_PIXELS := 2.0 # 瞬白轮廓沿裸卡四角保留的像素切角

var effect: ShaderMaterial
var flame: ColorRect
var foreground: ColorRect
var white_flash: Node2D
var _profile := {}
var _started_at := -1.0
var _pulse_at := -1000.0
var _finisher := false


func configure(profile: Dictionary, foreground_z_index: int = 30) -> void:
	_profile = profile.duplicate(true)
	if flame == null:
		name = "FireBurnVisual"
		process_mode = Node.PROCESS_MODE_PAUSABLE
		flame = ColorRect.new()
		flame.name = "Flame"
		flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect = ShaderMaterial.new()
		effect.shader = FIRE_SHADER
		flame.material = effect
		add_child(flame)
		foreground = ColorRect.new()
		foreground.name = "EdgeFlames"
		foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foreground.material = ShaderMaterial.new()
		(foreground.material as ShaderMaterial).shader = FIRE_SHADER
		(foreground.material as ShaderMaterial).set_shader_parameter("foreground", true)
		foreground.z_as_relative = false
		add_child(foreground)
	foreground.z_index = foreground_z_index
	if white_flash == null:
		white_flash = Node2D.new()
		white_flash.name = "CardWhiteFlash"
		white_flash.z_as_relative = false
		white_flash.visible = false
		add_child(white_flash)
	white_flash.z_index = foreground_z_index
	for material: ShaderMaterial in [effect, foreground.material]:
		material.set_shader_parameter("canvas_width_scale", CANVAS_WIDTH_SCALE)
	for key: String in ["pixel_size", "flow_speed", "flow_frequency", "warp_strength"]:
		effect.set_shader_parameter(key, float(_profile[key]))
		(foreground.material as ShaderMaterial).set_shader_parameter(key, float(_profile[key]))


func pulse(time: float, finisher: bool = false) -> void:
	_pulse_at = time
	_finisher = finisher


func has_pulse(time: float) -> bool:
	return time - _pulse_at < PULSE_SECONDS


func update_visual(bounds: Rect2, time: float, strength: float = 1.0, opacity: float = 1.0, card_bounds: Array[Rect2] = []) -> void:
	if _started_at < 0.0: _started_at = time
	var card_scale := bounds.size.y / CARD_HEIGHT
	var height := float(_profile["beam_height"]) * card_scale
	var margin := SIDE_MARGIN * card_scale
	flame.size = Vector2((bounds.size.x + margin * 2.0) * CANVAS_WIDTH_SCALE, height)
	flame.position = Vector2(bounds.get_center().x - flame.size.x * 0.5, bounds.end.y - height * (1.0 - BELOW_FRACTION))
	effect.set_shader_parameter("effect_size", flame.size)
	effect.set_shader_parameter("effect_time", time)
	effect.set_shader_parameter("pixel_size", float(_profile["pixel_size"]) * card_scale)
	effect.set_shader_parameter("intensity", strength)
	var pulse_value := maxf(0.0, 1.0 - (time - _pulse_at) / PULSE_SECONDS)
	effect.set_shader_parameter("pulse_strength", pulse_value * (2.0 if _finisher else 1.0))
	effect.set_shader_parameter("opacity", clampf((time - _started_at) / APPEAR_SECONDS, 0.0, 1.0) * opacity * FIRE_OPACITY)
	# 两层使用完全相同的画布与像素网格，前景只是同一团火被卡面挡住的一小部分。
	foreground.position = flame.position
	foreground.size = flame.size
	var front_effect := foreground.material as ShaderMaterial
	for key: String in ["effect_size", "effect_time", "pixel_size", "intensity", "pulse_strength", "opacity"]:
		front_effect.set_shader_parameter(key, effect.get_shader_parameter(key))
	var card_origin := bounds.position - flame.position
	front_effect.set_shader_parameter("card_rect", Vector4(card_origin.x, card_origin.y, bounds.size.x, bounds.size.y))
	front_effect.set_shader_parameter("foreground_depth", FOREGROUND_DEPTH * card_scale)
	front_effect.set_shader_parameter("foreground_tip_depth", FOREGROUND_TIP_DEPTH * card_scale)
	front_effect.set_shader_parameter("opacity", float(effect.get_shader_parameter("opacity")) * FOREGROUND_OPACITY)
	var flash_cards: Array[Rect2] = []
	flash_cards.assign(card_bounds)
	if flash_cards.is_empty(): flash_cards.append(bounds)
	_update_white_flash(flash_cards, time)


func _update_white_flash(cards: Array[Rect2], time: float) -> void:
	var amount := clampf(1.0 - (time - _pulse_at) / WHITE_FLASH_SECONDS, 0.0, 1.0)
	white_flash.visible = amount > 0.0
	if not white_flash.visible: return
	white_flash.modulate.a = amount * amount
	while white_flash.get_child_count() < cards.size():
		white_flash.add_child(Polygon2D.new())
	for index: int in white_flash.get_child_count():
		var surface := white_flash.get_child(index) as Polygon2D
		surface.visible = index < cards.size()
		if not surface.visible: continue
		var rect := cards[index]
		var corner := FLASH_CORNER_PIXELS * rect.size.y / CARD_HEIGHT
		var w := rect.size.x
		var h := rect.size.y
		surface.position = rect.position
		# 每张实体卡单独覆盖，随真实卡面移动；不扩大卡框，也不修改卡面原材质。
		surface.polygon = PackedVector2Array([Vector2(corner, 0), Vector2(w - corner, 0), Vector2(w, corner), Vector2(w, h - corner), Vector2(w - corner, h), Vector2(corner, h), Vector2(0, h - corner), Vector2(0, corner)])


static func play_event(event: BattleEffectEvent, visuals: Dictionary, controller: BattleController, slots: Dictionary, layer: CanvasItem, background_z: int, foreground_z: int) -> void:
	if event == null or event.missed or event.visual_kind not in [&"fire_burn", &"fire_tick", &"fire_finish"] or not is_instance_valid(slots.get(event.target)):
		return
	var visual := _ensure_target(event.target, visuals, layer, background_z, foreground_z)
	if event.visual_kind != &"fire_burn":
		visual.pulse(controller.elapsed_seconds, event.visual_kind == &"fire_finish")
	sync_targets(visuals, controller, slots, layer, background_z, foreground_z)


static func _ensure_target(target: BattleSquadState, visuals: Dictionary, layer: CanvasItem, background_z: int, foreground_z: int) -> BattleFireVisual:
	var visual := visuals.get(target) as BattleFireVisual
	if not is_instance_valid(visual):
		visual = BattleFireVisual.new()
		visual.z_as_relative = false
		visual.z_index = background_z
		layer.add_child(visual)
		visual.configure(Profiles.get_profile(&"fire_burn"), foreground_z)
		visuals[target] = visual
	return visual


static func sync_targets(visuals: Dictionary, controller: BattleController, slots: Dictionary, layer: CanvasItem, background_z: int, foreground_z: int) -> void:
	var counts := {}
	for status: Dictionary in controller.active_continuous_effects:
		var target := status.get("target") as BattleSquadState
		if target == null or not target.alive or target.current_health <= 0.0: continue
		counts[target] = int(counts.get(target, 0)) + 1
		_ensure_target(target, visuals, layer, background_z, foreground_z)
	var time := controller.elapsed_seconds
	var inverse := layer.get_global_transform_with_canvas().affine_inverse()
	for target: BattleSquadState in visuals.keys():
		var visual := visuals[target] as BattleFireVisual
		var slot := slots.get(target) as BoardSlot
		if not is_instance_valid(visual) or not is_instance_valid(slot) or not target.alive or target.current_health <= 0.0 or (not counts.has(target) and not visual.has_pulse(time)):
			if is_instance_valid(visual): visual.queue_free()
			visuals.erase(target)
			continue
		visual.visible = not target.is_banished
		var rect := slot.get_global_rect()
		var cards: Array[Rect2] = []
		for card: CardData in slot.squad_data.horizontal_cards:
			var card_rect := slot.get_card_view(card).get_global_rect()
			cards.append(Rect2(inverse * card_rect.position, inverse.basis_xform(card_rect.size)))
		visual.update_visual(Rect2(inverse * rect.position, inverse.basis_xform(rect.size)), time, minf(1.0 + float(counts.get(target, 1) - 1) * 0.12, 1.5), 1.0, cards)


static func clear_targets(visuals: Dictionary) -> void:
	for visual: Node in visuals.values():
		if is_instance_valid(visual): visual.queue_free()
	visuals.clear()
