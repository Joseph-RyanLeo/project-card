extends SceneTree

const MAIN = preload("res://scenes/Main.tscn")
const MainScript = preload("res://scripts/main.gd")
const CARD = preload("res://scenes/ui/CardView.tscn")
const Candidate = preload("res://scripts/ui/collection_candidate_card.gd")
const FocusOutline = preload("res://scripts/ui/focus_outline.gd")
const Damage = preload("res://scripts/battle/battle_damage_number.gd")
var main: MainScript
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/project-card-batch-six-" + label + ".png")


func _run() -> void:
	create_timer(18.0).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280, 720)
	main = MAIN.instantiate()
	main.run_save_path = "/private/tmp/project-card-batch-six-save.json"
	root.add_child(main)
	await process_frame
	await _test_damage()
	main.hide()
	await _test_inspection_layers()
	await _test_collection()
	main.queue_free()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args(): await RenderingServer.frame_post_draw
	print("第六批视觉反馈：%d项断言，%d失败" % [checks, failures])
	quit(1 if failures else 0)


func _test_damage() -> void:
	for row: BattlefieldRow in [main.front_row, main.back_row, main.enemy_front_row, main.enemy_back_row]:
		row.clear_squads()
	var definition := preload("res://resources/cards/militia.tres")
	for row: BattlefieldRow in [main.front_row, main.enemy_front_row, main.enemy_back_row]:
		var owned := main.owned_card_collection.create_card(definition)
		row.add_squad(SquadData.from_owned_card(owned), row.get_squad_count())
	await process_frame
	_check(main.start_battle(457, false), "真实主场景开战，伤害信号已接入")
	await process_frame
	await process_frame
	Input.warp_mouse(Vector2(35, 170))
	var controller := main.battle_controller
	var armor_target := controller.enemy_states[0]
	var health_target := controller.enemy_states[1]
	var player := controller.player_states[0]
	player.current_health = 5.0
	player.current_armor = 0.0
	player.apply_damage_exact(99.0, null, null, true)
	armor_target.current_armor = 30.0
	armor_target.apply_damage_exact(10.0)
	armor_target.apply_damage_exact(17.0)
	health_target.current_health = 30.0
	health_target.current_armor = 7.0
	var hit := BattleEffectEvent.new()
	hit.is_base_action = true
	hit.hellfire_adjusted = true
	hit.group_id = 67
	health_target.apply_damage_exact(7.0, player, hit)
	var extra := BattleEffectEvent.new()
	extra.hellfire_adjusted = true
	extra.group_id = hit.group_id
	extra.visual_kind = &"wound_poison_action"
	health_target.apply_damage_exact(6.0, player, extra, true)
	await process_frame
	var popups: Array[Node] = main.battle_effect_layer.get_children().filter(func(node: Node): return node.get_script() == Damage)
	_check(popups.size() == 2, "恰好10点与溢出伤害不显示，同次附伤合并，独立命中各自显示")
	if popups.size() != 2: return
	_check(popups[0]._parts == PackedStringArray(["17"]) and popups[0]._ink == Damage.ARMOR_COLOR and popups[1]._parts == PackedStringArray(["13"]) and popups[1]._ink == Damage.HEALTH_COLOR, "纯护甲灰色，混合伤害合并为红色，整点伤害省略小数")
	_check(popups[0].position.y - popups[1].position.y > 75.0, "镜头切换期间伤害字仍分别锚定前后排")
	var start: Vector2 = popups[0].position
	var initial_scale: float = popups[0].scale.x
	popups[0]._animate_size(Damage.GROW_TIME)
	_check(initial_scale < 4.0 and popups[0].scale.x > 4.0, "从小放大到略超4倍")
	var settle_deadline := Time.get_ticks_msec() + 400
	while is_instance_valid(popups[0]) and not is_equal_approx(popups[0].scale.x, 4.0) and Time.get_ticks_msec() < settle_deadline:
		await process_frame
	_check(is_instance_valid(popups[0]) and is_equal_approx(popups[0].scale.x, 4.0) and popups[0].position.y < start.y, "回弹到4倍，期间持续上移")
	await _capture("damage")
	await create_timer(Damage.FADE_TIME + Damage.HOLD_TIME + 0.02).timeout
	_check(not is_instance_valid(popups[0]) and not is_instance_valid(popups[1]), "伤害字上移淡出并释放")


func _test_inspection_layers() -> void:
	var artboard := Control.new()
	root.add_child(artboard)
	var surfaces: Array[InspectionCardSurface] = []
	for index: int in 4:
		var id: String = ["side_by_side", "battle_fury", "return_to_battlefield", "volley_order"][index]
		var definition := load("res://resources/cards/%s.tres" % id) as CardData
		var owned := main.owned_card_collection.create_card(definition)
		owned.art_finish = CardAppearance.Art.HOLOGRAPHIC
		var card := CARD.instantiate() as CardView
		card.set_card_data(definition)
		card.set_owned_card(owned)
		artboard.add_child(card)
		_check(card.art_texture.texture == definition.art_texture and card._finish_controller._art_planes.is_empty(), id + " 非透视表面保留原图")
		var surface := InspectionCardSurface.new()
		artboard.add_child(surface)
		surface.setup(card, Callable(), Callable())
		surfaces.append(surface)
		surface.set_process(false)
		surface.position = Vector2(30 + index * 306, 148)
		surface.scale = Vector2(2.0, 2.0)
		surface.set_pointer_force(Vector2(0.88, -0.48))
		var renderer = card._finish_controller
		var planes: Array[TextureRect] = renderer._art_planes
		var depth := float(renderer._background_material.get_shader_parameter("layer_depth"))
		var ordered := planes.size() == definition.inspection_art_layers.size()
		for plane_index: int in planes.size():
			var plane := planes[plane_index]
			var shader := plane.material as ShaderMaterial
			var next_depth := float(shader.get_shader_parameter("layer_depth"))
			ordered = ordered and next_depth > depth and next_depth < 0.0 and plane.texture == definition.inspection_art_layers[plane_index]
			ordered = ordered and plane.position == Vector2.ZERO and shader.get_shader_parameter("pointer_force") == surface.force
			depth = next_depth
		_check(ordered and surface.render_scale >= 4.0 and card.art_texture.self_modulate.a == 0.0, id + " 全息检视按素材顺序分别设置深度，原画不在低分辨率下移动")
	await _capture("spells-holographic")
	if DisplayServer.get_name() != "headless": await _test_subpixel_planes(surfaces[1])
	var example := surfaces[1].card
	var finish_card := example.get_owned_card()
	finish_card.surface_finish = CardAppearance.Surface.GOLD
	for art: int in [CardAppearance.Art.PLAIN, CardAppearance.Art.OVERFRAME]:
		finish_card.art_finish = art
		example.set_owned_card(finish_card)
		_check(example._finish_controller._art_planes.is_empty() and example.art_texture.self_modulate.a == 1.0 and example.art_texture.texture == example.card_data.art_texture, "同一检视切回普通／超框卡图时复原平面原画")
	artboard.queue_free()
	await process_frame


func _test_subpixel_planes(surface: InspectionCardSurface) -> void:
	var card := surface.card
	var planes: Array[TextureRect] = card._finish_controller._art_planes
	if planes.size() < 2: return
	var probe := TextureRect.new()
	var image := Image.create_empty(108, 144, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(50, 68, 8, 8), Color.WHITE)
	probe.texture = ImageTexture.create_from_image(image)
	probe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	probe.position = card.position + card.art_panel.position + card.art_texture.position
	card.hide()
	surface.viewport.add_child(probe)
	var travels: Array[float] = []
	for plane: TextureRect in [planes.front(), planes.back()]:
		var material := plane.material.duplicate() as ShaderMaterial
		material.set_shader_parameter("card_finish", -1)
		material.set_shader_parameter("pointer_light_enabled", false)
		probe.material = material
		material.set_shader_parameter("pointer_force", Vector2.ZERO)
		await RenderingServer.frame_post_draw
		var before := surface.viewport.get_texture().get_image().get_used_rect().get_center().x
		material.set_shader_parameter("pointer_force", Vector2(0.075, 0.0))
		await RenderingServer.frame_post_draw
		var after := surface.viewport.get_texture().get_image().get_used_rect().get_center().x
		travels.append(absf(after - before))
	_check(travels[0] > travels[1] and travels[0] < surface.render_scale, "GPU捕获到小于一个原生像素的位移，深层和前层位移不同")
	probe.queue_free()
	card.show()
	await process_frame


func _test_collection() -> void:
	var owned := main.owned_card_collection.create_card(preload("res://resources/cards/anvil_margaret.tres"))
	var candidate := Candidate.new()
	root.add_child(candidate)
	candidate.setup(owned)
	candidate.position = Vector2(360, 114)
	candidate.scale = Vector2(2.0, 2.0)
	candidate.sync_choice({"slot": 0}, 0)
	await process_frame
	var card: CardView = candidate.view
	var mask := FocusOutline.card_mask(card)
	_check((mask.bounds as Rect2).position.x < 0.0 and (mask.bounds as Rect2).end.x > card.card_size.x, "轮廓覆盖实际突出卡框的左右角标")
	_check(not candidate.halo._curves.is_empty(), "已选卡沿实体轮廓生成流光路径")
	await _capture("collection")
	var marked := CARD.instantiate() as CardView
	marked.set_card_data(owned.card_data)
	marked.set_owned_card(owned)
	marked.show_new_card_marker = true
	root.add_child(marked)
	await create_timer(0.43).timeout
	_check(marked._new_card_dot.visible and marked._new_card_dot.modulate.a < 0.85 and marked._new_card_dot.modulate.a > 0.41, "原收藏绿点柔和呼吸")
	owned.is_new = false
	marked._refresh_new_card_dot()
	_check(not marked._new_card_dot.visible and (not is_instance_valid(marked._new_card_dot_breath) or not marked._new_card_dot_breath.is_valid()), "已阅时绿点和呼吸一并停止")
	candidate.queue_free()
	marked.queue_free()
