extends "res://tests/sentry_carry_input_test.gd"

## 沿用原双输入断言；先收起遮住前排图标的事件板，再操作真正已部署的图标。
func pick_up(id: String, gesture: String) -> void:
	if not main._tabletop_panels_parked and main._can_park_tabletop_panels():
		main._park_tabletop_panels()
		await create_timer(0.4).timeout
	var view := view_for(id)
	var source := view.get_global_rect().position + view.size * Vector2(0.5, 0.75)
	await move(source)
	await button(source, true)
	if gesture == "长按":
		await create_timer(0.15).timeout
		await move(source + Vector2(-48, 0), true)
		check(shell.internal_viewport.gui_is_dragging(), "长按进入真实原生拖动")
	else:
		await button(source, false)
	check(main.celestial_indicators._data.get("instance_id") == id, gesture + "共用携带状态中的哨位实例")
