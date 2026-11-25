extends SceneTree

const DISPLAY := preload("res://scenes/GameDisplay.tscn")
const MILITIA := preload("res://resources/cards/militia.tres")
const MARGARET := preload("res://resources/cards/anvil_margaret.tres")
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shell := DISPLAY.instantiate() as GameDisplay
	var main = shell.get_node("RenderContainer/InternalViewport/DesignCanvas/Main")
	main.short_maze_enabled = false
	main.run_save_path = "/private/tmp/project-card-paused-battle-overlap-save.json"
	root.add_child(shell)
	await process_frame
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	var cards: Array[CardData] = [MARGARET, MILITIA]
	var squad := SquadData.from_cards(cards, SquadData.TwoCardLayout.COMPACT)
	var slot: BoardSlot = main.front_row.add_squad(squad, 0)
	main.enemy_front_row.add_squad(SquadData.from_card(MILITIA), 0)
	_check(main.start_battle(8676, false), "真实双卡堆叠开战")
	main._on_battle_pause_button_pressed()
	await process_frame
	var top := slot.get_card_view(squad.layer_cards[0])
	var lower := slot.get_card_view(squad.layer_cards[1])
	var overlap := top.get_global_rect().intersection(lower.get_global_rect())
	_check(paused and overlap.has_area(), "战斗暂停且两张实体卡有重合区域")
	var position := shell.render_container.get_global_transform_with_canvas() * overlap.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	if DisplayServer.get_name() != "headless": Input.warp_mouse(position)
	root.push_input(motion, true)
	await process_frame
	await process_frame
	_check(shell._paused_hover_card == top, "暂停悬停命中重叠区最上层卡牌")
	var click := InputEventMouseButton.new()
	click.position = position
	click.global_position = position
	click.pressed = true
	click.button_index = MOUSE_BUTTON_RIGHT
	root.push_input(click, true)
	await process_frame
	_check(is_instance_valid(main._inspection_overlay) and main._inspection_card_data == top.card_data, "暂停右键检视最上层卡牌")
	main._close_card_inspection(true)
	paused = false
	shell.queue_free()
	await process_frame
	print("Paused battle overlap failures: ", _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
