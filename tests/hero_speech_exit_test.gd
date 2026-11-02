extends "res://tests/hero_speech_shop_leave_test.gd"

## 复用真实商店专项，再验证事件、战后结算、文字演出与气泡九宫格。
func _check_maze_leave() -> void:
	await super._check_maze_leave()
	check(main.maze_controller.hero.choose_talent("sentry_guard"), "测试英雄完成真实首级天赋选择，保持快照可验证")
	await _check_speech_animation()
	await _check_event_exit()
	await _check_result_exit()


func _check_speech_animation() -> void:
	var speech = main._hero_speech
	main.hero_say("好。")
	var one_line_height: float = speech.size.y
	main.hero_say("临时区域仍有纹章，是否真的要离开")
	var full_size: Vector2 = speech.size
	check(full_size.x == 178 and full_size.y > one_line_height and full_size.y < 142, "固定178px宽，长台词按完整换行数加高，短台词收紧")
	check(speech._background is NinePatchRect and speech._background.size == full_size and speech._background.patch_margin_bottom == 16, "九宫格只伸缩纯色中段，保留底边与尾尖")
	await create_timer(0.20).timeout
	check(speech.text_label.visible_characters > 0 and speech.text_label.visible_characters < speech.text_label.get_total_character_count() and speech.size == full_size, "逐字出现期间高度稳定，不随已显示字数抖动")
	await capture("hero-speech-typing")
	await create_timer(1.2).timeout
	check(speech.text_label.visible_characters == speech.text_label.get_total_character_count(), "台词演出最终完整显示")
	check(speech.text_label.get_line_count() == 2 and speech.text_label.get_minimum_size().y <= speech.text_label.size.y, "两行台词完整落在紧凑气泡内部")
	await capture("hero-speech-adaptive")
	main.hero_say("甲乙，丙丁。")
	var reveal: Tween = speech._text_reveal
	reveal.pause()
	reveal.custom_step(speech.EventText.CHARACTER_SECONDS * 3.0 + 0.01)
	check(speech.text_label.visible_characters == 3, "首句依事件逐字速度显示到逗号")
	reveal.custom_step(speech.EventText.TEXT_LINE_PAUSE * 0.5)
	check(speech.text_label.visible_characters == 3, "句段之间沿用事件的短暂停顿")
	reveal.custom_step(1.0)
	check(speech.text_label.visible_characters == 6, "停顿后继续显示下一句")
	speech.dismiss()
	var fade: Tween = speech._fade
	fade.pause()
	check(speech.visible and speech.confirmation_button == null and is_equal_approx(speech.modulate.a, 1.0), "渐隐开始立即清除确认资格，画面仍从不透明开始")
	fade.custom_step(speech.FADE_SECONDS * 0.5)
	check(speech.visible and speech.modulate.a > 0.0 and speech.modulate.a < 1.0, "渐隐中途底板与文字整体半透明")
	await capture("hero-speech-fading")
	main.hero_say("新的台词。")
	await create_timer(speech.FADE_SECONDS + 0.04).timeout
	check(speech.visible and is_equal_approx(speech.modulate.a, 1.0) and speech.text_label.text == "新的台词。", "渐隐中出现新台词会停止旧动画，不会被旧回调隐藏")
	speech.dismiss()
	await create_timer(speech.FADE_SECONDS + 0.05).timeout
	check(not speech.visible, "渐隐结束完全隐藏气泡")


func _finish_event_text() -> void:
	await process_frame
	await process_frame
	var table = main.maze_controller._event_table
	if is_instance_valid(table) and is_instance_valid(table._text_reveal): table._text_reveal.custom_step(30.0)
	await process_frame
	await process_frame


func _check_event_exit() -> void:
	var maze: ShortMazeController = main.maze_controller
	var bag := main.emblem_library as EmblemLibraryView
	maze.run.initialize(43)
	maze.run.round_index = 0
	maze.run.step = ShortMazeRunState.Step.EVENT
	for event: Dictionary in maze.content.free_events:
		if event.reward == "emblem": maze.run.selected_path = event.duplicate(true); break
	bag.restore_inventory_state(_layout(false))
	check(maze.complete_event() and maze.run.selected_path.get("reward_claimed", false) and bag.has_dropped_stickers(), "事件满箱发奖先停留，奖励只提交一次")
	main._close_toolbox_inspection(false)
	main.set_world_view(main.WorldView.BATTLEFIELDS, false)
	await _finish_event_text()
	var button: BaseButton = maze._find_exit_button(maze.complete_event.bind(true))
	check(is_instance_valid(button) and button.is_visible_in_tree(), "找到事件原来的继续按钮")
	if not is_instance_valid(button): return
	var inventory := bag.get_inventory_state()
	await click(button.get_global_rect().get_center())
	check(maze.run.step == ShortMazeRunState.Step.EVENT and main._hero_speech.is_confirming(button) and bag.get_inventory_state() == inventory, "事件首次真实点击继续仅让英雄提示，不重复发奖或销毁")
	check(main._hero_speech.text_label.text == "临时区域仍有纹章，是否确认丢弃" and main.find_child("TemporaryStickerDiscardConfirmation", true, false) == null, "事件退出由英雄说话，旧原生确认框已删除")
	await create_timer(1.2).timeout
	await capture("hero-speech-event-exit")
	await click(Vector2(480, 360))
	check(not main._hero_speech.is_confirming(button) and bag.get_inventory_state() == inventory, "点别处取消事件退出确认，保留临时纹章")
	await click(button.get_global_rect().get_center())
	check(maze.run.step == ShortMazeRunState.Step.EVENT and main._hero_speech.is_confirming(button), "取消后第一次继续重新提示")
	await click(button.get_global_rect().get_center())
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and not bag.has_dropped_stickers() and bag.get_inventory_state().size() == 28, "事件原按钮第二次点击才丢弃并继续，不重领奖励")
	# 强化选项与放弃按钮分别确认，不能借用另一按钮的提示。
	maze.run.round_index = 1
	maze.run.paths.clear()
	maze.run.step = ShortMazeRunState.Step.EVENT
	maze.run.selected_path = maze.content.paid_events[0].duplicate(true)
	main.run_reward_state.gold = 100
	var owned: OwnedCard = main.owned_card_collection.create_card(load("res://resources/cards/militia.tres"), maze.run.rng)
	bag.receive_stickers([{"instance_id": "event_other_exit", "emblem_id": "火把"}])
	maze.refresh()
	check(maze.select_enhancement_card({"kind": &"card", "owned_card": owned}), "真实随从进入强化卡槽")
	await _finish_event_text()
	var take: BaseButton = maze._find_exit_button(maze.apply_card_enhancement.bind(0))
	var decline: BaseButton = maze._find_exit_button(maze.complete_event.bind(false))
	await click(take.get_global_rect().get_center())
	check(main._hero_speech.is_confirming(take) and not maze.run.selected_path.has("enhancement_result"), "首次点击强化仅提示，不提前支付或强化")
	await click(decline.get_global_rect().get_center())
	check(maze.run.step == ShortMazeRunState.Step.EVENT and main._hero_speech.is_confirming(decline) and not main._hero_speech.is_confirming(take) and bag.has_dropped_stickers(), "换点放弃按钮仅重新提示，不借用强化按钮确认")
	await click(decline.get_global_rect().get_center())
	check(maze.run.step == ShortMazeRunState.Step.CHOOSING and main.run_reward_state.gold == 100 and not bag.has_dropped_stickers(), "再次点同一放弃按钮才退出，不扣强化费用")


func _check_result_exit() -> void:
	var maze: ShortMazeController = main.maze_controller
	var bag := main.emblem_library as EmblemLibraryView
	bag.receive_stickers([{"instance_id": "result_speech_drop", "emblem_id": "火把"}])
	main._last_battle_settlement_result = {"success": true}
	main.current_phase = main.GamePhase.RESULT
	maze.run.round_index = 3
	maze.run.paths.clear()
	maze.run.selected_path = maze.content.enemies[0].duplicate(true)
	maze.run.selected_path["battle_seed"] = 123
	maze.run.step = ShortMazeRunState.Step.BATTLE_ACTIVE
	maze.run.settle_battle(true)
	check(maze.validate_state(maze.capture_state()), "结算回滚使用真实敌人定义和完整合法的战后快照")
	main._update_phase_label()
	maze.refresh()
	await create_timer(0.5).timeout
	var button: Button = main.continue_next_level_button
	await click(button.get_global_rect().get_center())
	check(main.current_phase == main.GamePhase.RESULT and maze.run.day == 1 and main._hero_speech.is_confirming(button) and bag.has_dropped_stickers(), "结算首次真实点击进入下一天只显示英雄气泡")
	await create_timer(1.2).timeout
	await capture("hero-speech-result-exit")
	await click(Vector2(480, 360))
	check(main.current_phase == main.GamePhase.RESULT and not main._hero_speech.is_confirming(button) and bag.has_dropped_stickers(), "点别处取消结算确认，不推进日期")
	await click(button.get_global_rect().get_center())
	var inventory := bag.get_inventory_state()
	main.run_save_path = "/private/tmp/project-card-hero-result-no-directory/run.json"
	await click(button.get_global_rect().get_center())
	check(main.current_phase == main.GamePhase.RESULT and maze.run.day == 1 and bag.get_inventory_state() == inventory and not main._hero_speech.is_confirming(button), "结算二次点击保存失败回滚日期与临时纹章，确认失效；phase=%s day=%s step=%s same_inventory=%s confirming=%s" % [main.current_phase, maze.run.day, maze.run.step, bag.get_inventory_state() == inventory, main._hero_speech.is_confirming(button)])
	main.run_save_path = "/private/tmp/project-card-hero-speech-run.json"
	await click(button.get_global_rect().get_center())
	check(main.current_phase == main.GamePhase.RESULT and main._hero_speech.is_confirming(button), "结算保存失败后再次操作重新提示")
	await click(button.get_global_rect().get_center())
	check(main.current_phase == main.GamePhase.PREPARE and maze.run.day == 2 and not bag.has_dropped_stickers(), "结算原按钮第二次点击才丢弃临时纹章并进入下一天")
