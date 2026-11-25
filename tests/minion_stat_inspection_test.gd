extends SceneTree

const CARD_SCENE := preload("res://scenes/ui/CardView.tscn")
const MAIN_SCENE := preload("res://scenes/Main.tscn")
const MainScript := preload("res://scripts/main.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var definition := CardData.new()
	definition.id = &"stat_test"
	definition.card_type = CardData.CardType.MINION
	definition.base_value = 6
	definition.max_health = 10
	definition.armor = 4
	definition.cooldown_seconds = 3.0
	definition.runes.assign([CardData.ElementType.FIRE, CardData.ElementType.WATER, CardData.ElementType.WOOD])
	var owner := OwnedCard.new()
	owner.initialize(definition, &"stat_test:1", 0)
	owner.resolved_runes.assign(definition.runes)
	owner.rune_revealed.assign([true, false, false])
	owner.apply_permanent_growth(OwnedCard.STAT_BASE_VALUE, 1)
	var squad := SquadData.from_owned_card(owner)
	var equipment := CardData.new()
	equipment.id = &"stat_test_item"
	equipment.card_type = CardData.CardType.EQUIPMENT
	equipment.equipment_action_delta = -1
	equipment.equipment_health_delta = 3
	equipment.equipment_armor_delta = -2
	equipment.equipment_zeal_delta = 2
	var item := OwnedCard.new()
	item.initialize(equipment, &"stat_test:2", 1)
	_check(squad.equip_item(item), "测试装备成功上阵")
	var card := CARD_SCENE.instantiate() as CardView
	card.set_card_data(definition)
	card.set_owned_card(owner)
	card.set_squad_attribute_preview_from_squad(squad)
	root.add_child(card)
	var up := RuneNumberDisplay.STAT_GAIN_COLOR
	var down := RuneNumberDisplay.STAT_LOSS_COLOR
	card.set_inspection_stat_breakdown(true)
	owner.rune_revealed.assign([true, true, true])
	card.set_owned_card(owner)
	card.set_squad_attribute_preview_from_squad(squad, true)
	_check_split(card.health_label, "10", "3", true, up, Vector2(90, 90))
	_check_split(card.armor_label, "4", "2", false, down, Vector2(91, 77))
	var health_roll: Tween = card._battle_number_tweens[&"squad_preview_health"]
	var armor_roll: Tween = card._battle_number_tweens[&"squad_preview_armor"]
	for roll: Tween in [health_roll, armor_roll]:
		roll.pause()
		roll.custom_step(CardView.STAT_CHANGE_SECONDS * 0.48)
	_check_split(card.health_label, "11", "3", true, up, Vector2(90, 90))
	_check_split(card.armor_label, "5", "2", false, down, Vector2(91, 77))
	for roll: Tween in [health_roll, armor_roll]:
		roll.custom_step(CardView.STAT_CHANGE_SECONDS)
	card.set_inspection_stat_breakdown(false)
	_check_single(card.value_label, "8", up, "常态数值含火符文强化")
	_check_single(card.health_label, "15", up, "常态生命")
	_check_single(card.armor_label, "5", down, "常态护甲")
	_check_single(card.cooldown_label, "2.8", Color.WHITE, "常态冷却")
	card.set_inspection_stat_breakdown(true)
	_check_split(card.value_label, "7", "1", true, up, Vector2(1, 10))
	_check_split(card.health_label, "12", "3", true, up, Vector2(90, 90))
	_check_split(card.armor_label, "7", "2", false, down, Vector2(91, 77))
	_check_split(card.cooldown_label, "3", "0.2", false, up, Vector2(2, 27))
	_check(card.value_label._get_stat_delta_x() == card.value_label.get_stat_sign_offset().x + 6.0, "右侧首位为1时再左移一像素")
	_check_stat_animation(card)
	var digits := RuneNumberDisplay.LARGE_TEXTURE.get_image()
	var tinted := RuneNumberDisplay._get_stat_palette(RuneNumberDisplay.LARGE_TEXTURE, up).get_image()
	for row: int in digits.get_height():
		for column: int in digits.get_width():
			var original := digits.get_pixel(column, row)
			var expected := up if original == Color.WHITE else original
			_check(tinted.get_pixel(column, row).is_equal_approx(expected), "只重着色纯白像素")
	card.set_squad_attribute_preview(7, 12, 7, 3.0)
	await create_timer(0.32).timeout
	_check_single(card.value_label, "7", Color.WHITE, "检视零差额")
	_check(card.value_label.position == CardView.get_action_value_position(7), "零差额恢复原坐标")
	card.inspection_stat_progress = 0.0
	_check(card.animate_inspection_stats(true) == 0.0 and card._inspection_stat_tween == null, "四项零差额时不创建拆解动画")
	card.set_squad_attribute_preview(7, 12, 7, 3.4)
	await create_timer(0.32).timeout
	_check_split(card.cooldown_label, "3", "0.4", true, down, Vector2(2, 27))
	card.set_inspection_stat_breakdown(false)
	card.set_battle_stat_baselines(Vector3i(7, 10, 4))
	card.set_battle_vitals(13, 4)
	card.set_battle_action_value(6)
	card.set_battle_remaining_cooldown(1.8)
	_check_single(card.health_label, "13", up, "战斗生命高于基础")
	_check_single(card.armor_label, "4", Color.WHITE, "战斗护甲等于基础")
	_check_single(card.value_label, "6", down, "战斗数值低于基础")
	_check_single(card.cooldown_label, "1.8", Color.WHITE, "战斗剩余冷却")
	card.set_battle_vitals(8, 6)
	card.set_battle_action_value(9)
	await create_timer(0.32).timeout
	_check_single(card.health_label, "8", down, "战斗生命低于基础")
	_check_single(card.armor_label, "6", up, "战斗护甲高于基础")
	_check_single(card.value_label, "9", up, "战斗数值高于基础")
	definition.base_value = CardData.MAXIMUM_BASE_VALUE
	_check(SquadData.from_owned_card(owner).get_preview_action_value() == CardData.MAXIMUM_BASE_VALUE + 2, "强化不受基础行动数值上限限制")
	card.free()
	await _check_inspection_lifecycle(owner)
	print("Minion stat inspection checks: %d failure(s)." % _failures)
	quit(_failures)


func _check_stat_animation(card: CardView) -> void:
	card.inspection_stat_progress = 0.0
	_check(card.value_label.position + card.value_label._stat_single_offset == CardView.get_action_value_position(8), "合体数字与常态坐标完全重合")
	_check(card.health_label.position + card.health_label._stat_single_offset == CardView.get_health_value_position(15), "合体生命保持原来的基线高度")
	var labels: Array[RuneNumberDisplay] = [card.value_label, card.health_label, card.armor_label, card.cooldown_label]
	card.inspection_stat_progress = RuneNumberDisplay.STAT_WHITEN_END
	for label: RuneNumberDisplay in labels:
		var shader := label.material as ShaderMaterial
		_check(shader != null and shader.shader == RuneNumberDisplay.STAT_WHITE_SHADER and shader.get_shader_parameter("white_amount") == 1.0, "四组数字复用纯白剪影")
		_check(is_zero_approx(label._get_stat_separation()), "分离前当前值仍在原位")
	card.inspection_stat_progress = 0.52
	var separation := card.value_label._get_stat_separation()
	_check(separation > 0.0 and separation < 1.0, "中间帧尚未抵达两侧锚点")
	card.inspection_stat_progress = 0.9
	_check(card.value_label._get_stat_separation() == 1.0, "数字先到位再恢复颜色")
	card.inspection_stat_progress = 1.0
	for label: RuneNumberDisplay in labels:
		_check(label.material == null, "就位后恢复原色与描边")


func _check_inspection_lifecycle(owner: OwnedCard) -> void:
	var main := MAIN_SCENE.instantiate() as MainScript
	main.run_save_path = "/private/tmp/project-card-stat-animation-test-save.json"
	root.add_child(main)
	await process_frame
	await _check_preparation_neighbor(main)
	await _check_scrape_vitals(main, owner)
	main._open_card_inspection(owner.card_data, owner, null, true)
	var inspected := main._inspection_card_view
	_check(inspected.has_inspection_stat_breakdown() and inspected.inspection_stat_progress == 0.0, "主场景打开检视时，从当前值起播")
	var enter := inspected._inspection_stat_tween
	enter.pause()
	enter.custom_step(CardView.INSPECTION_STAT_SPLIT_SECONDS * 0.5)
	_check(is_equal_approx(inspected.inspection_stat_progress, 0.5), "真实检视进入剪影拆解中段")
	main._close_card_inspection()
	var leave := inspected._inspection_stat_tween
	_check(not enter.is_valid() and leave != enter and is_equal_approx(inspected.inspection_stat_progress, 0.5), "中途退出从当前帧反向融合，不跳到完全拆开")
	await create_timer(0.32).timeout
	_check(not is_instance_valid(main._inspection_overlay), "融合结束后正常关闭检视")
	main._open_card_inspection(owner.card_data, owner, null, true)
	await create_timer(CardView.INSPECTION_STAT_SPLIT_SECONDS + 0.05).timeout
	inspected = main._inspection_card_view
	_check(inspected.inspection_stat_progress == 1.0, "完整打开后数字保持拆解状态")
	main._close_card_inspection()
	leave = inspected._inspection_stat_tween
	leave.pause()
	leave.custom_step(CardView.INSPECTION_STAT_FUSE_SECONDS)
	_check(is_zero_approx(inspected.inspection_stat_progress) and inspected.value_label.material == null, "完整关闭时在原位置合回正常颜色的当前值")
	await create_timer(0.35).timeout
	_check(not is_instance_valid(main._inspection_overlay), "完整关卡后清理检视")
	main._open_card_inspection(owner.card_data, owner, null, true)
	inspected = main._inspection_card_view
	var pack := CardPackOpening.new()
	main.add_child(pack)
	pack.set_process(false)
	pack.cards.assign([owner])
	pack.surface = main._inspection_surface
	pack.overlay = main._inspection_overlay
	pack.glow = CardPackOpening.Glow.new()
	pack.overlay.add_child(pack.glow)
	pack._reveal_card(false)
	await create_timer(CardView.INSPECTION_STAT_SPLIT_SECONDS + 0.05).timeout
	_check(inspected.inspection_stat_progress == 1.0, "开包卡实际揭晓后完成拆解")
	pack.collect_current()
	await create_timer(float(pack.effects.collect_seconds) + 0.05).timeout
	_check(pack.phase == CardPackOpening.Phase.FINISHED and inspected.inspection_stat_progress == 0.0, "开包收卡在离场结束前合回单值")
	main.free()


func _check_preparation_neighbor(main: MainScript) -> void:
	var row := main.front_row
	row.clear_squads()
	var cards: Array[OwnedCard] = []
	for id: String in ["town_priest", "militia", "shieldwall_private"]:
		var owned := OwnedCard.new()
		owned.initialize(load("res://resources/cards/%s.tres" % id), StringName("inspection_neighbor:" + id), cards.size())
		owned.rune_revealed.fill(false)
		row.add_squad(SquadData.from_owned_card(owned), cards.size())
		cards.append(owned)
	await process_frame
	var militia := cards[1]
	var source := row.get_squads()[1].get_card_view(militia.get_battlefield_card())
	var up := RuneNumberDisplay.STAT_GAIN_COLOR
	_check_single(source.value_label, "2", up, "乡邻生效时备战卡面为绿色2")
	source.inspection_requested.emit(source, source.card_data, militia)
	var inspected := main._inspection_card_view
	_check_split(inspected.value_label, "1", "1", true, up, Vector2(1, 10))
	_check(inspected._inspection_stat_tween != null, "备战乡邻差额播放已有的拆解动画")
	militia.resolved_runes[0] = CardData.ElementType.FIRE
	militia.rune_revealed[0] = true
	main._refresh_owned_card_status_visuals(militia)
	await create_timer(CardView.STAT_CHANGE_SECONDS + 0.05).timeout
	_check_single(source.value_label, "4", up, "火符文强化加到乡邻后的备战总值")
	_check_split(inspected.value_label, "1", "3", true, up, Vector2(1, 10))
	main._close_card_inspection(true)
	row.remove_squad_slot(row.get_squads()[2])
	militia.rune_revealed[0] = false
	await process_frame
	source.inspection_requested.emit(source, source.card_data, militia)
	inspected = main._inspection_card_view
	_check_single(inspected.value_label, "1", Color.WHITE, "移走一侧人类后检视恢复白色1")
	main._close_card_inspection(true)
	row.clear_squads()
	await process_frame


func _check_scrape_vitals(main: MainScript, owner: OwnedCard) -> void:
	owner.rune_revealed[1] = false
	owner.rune_revealed[2] = false
	main._open_card_inspection(owner.card_data, owner)
	var inspected := main._inspection_card_view
	await create_timer(CardView.INSPECTION_STAT_SPLIT_SECONDS + 0.05).timeout
	for index: int in [1, 2]:
		main._rune_scraper_paid_slots[main._rune_scraper_paid_key(owner, index)] = {"owned": owner, "index": index}
	main._finish_rune_scraper_mode()
	_check_single(inspected.health_label, "10", Color.WHITE, "刮开水符文从原白字开始")
	_check_single(inspected.armor_label, "4", Color.WHITE, "刮开木符文从原白字开始")
	var health_roll: Tween = inspected._battle_number_tweens[&"squad_preview_health"]
	var armor_roll: Tween = inspected._battle_number_tweens[&"squad_preview_armor"]
	for roll: Tween in [health_roll, armor_roll]:
		roll.pause()
		roll.custom_step(CardView.STAT_CHANGE_SECONDS * 0.48)
	_check_single(inspected.health_label, "11", Color.WHITE, "白色生命数字滚动中段")
	_check_single(inspected.armor_label, "5", Color.WHITE, "白色护甲数字滚动中段")
	for roll: Tween in [health_roll, armor_roll]:
		roll.custom_step(CardView.STAT_CHANGE_SECONDS)
	_check_single(inspected.health_label, "12", Color.WHITE, "刮开水符文后白字到位")
	_check_single(inspected.armor_label, "7", Color.WHITE, "刮开木符文后白字到位")
	_check(inspected.health_label.scale.is_equal_approx(Vector2.ONE) and inspected.armor_label.scale.is_equal_approx(Vector2.ONE), "白色数字缩回原尺寸")
	main._close_card_inspection(true)


func _check_split(label: RuneNumberDisplay, base_text: String, delta_text: String, positive: bool, color: Color, anchor: Vector2) -> void:
	_check(label.has_stat_breakdown() and label._stat_base_text == base_text and label._stat_delta_text == delta_text, "基础与差额 %s / %s" % [base_text, delta_text])
	_check(label._stat_positive == positive and label._stat_color == color, "检视符号与颜色 %s / %s" % [base_text, delta_text])
	_check(label.position + label.get_stat_sign_offset() == anchor, "检视符号像素锚点 %s" % anchor)


func _check_single(label: RuneNumberDisplay, value: String, color: Color, context: String) -> void:
	_check(label.text == value and label._stat_color == color and not label.has_stat_breakdown(), "%s（实际 %s / %s）" % [context, label.text, label._stat_color])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
