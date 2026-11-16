extends Control

signal return_requested
signal purchase_requested(id: String)
signal selection_requested(main_id: String, side_id: String)
signal skip_requested

const Style = preload("res://scripts/ui/menu_style.gd")
var progress: ProfileProgress
var selecting := false
var _list: VBoxContainer
var _body: VBoxContainer
var _balance: Label
var _main_choice: OptionButton
var _side_choice: OptionButton
var _choices: Array[Array] = [[], []]
var _detail_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.make_theme()
	Style.add_background(self)
	var title := Label.new()
	title.text = "选择本局任务" if selecting else "迷宫商店"
	title.position = Vector2(60, 42) # 页面标题位置
	title.add_theme_font_size_override("font_size", 32) # 页面标题字号
	add_child(title)
	_balance = Label.new()
	_balance.position = Vector2(60, 98) # 余额位于标题下方
	add_child(_balance)
	var left := ScrollContainer.new()
	left.position = Vector2(60, 158) # 任务目录起点
	left.size = Vector2(340, 450) # 左侧目录滚动范围
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(left)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12) # 任务按钮间隔
	left.add_child(_list)
	var detail := ScrollContainer.new()
	detail.name = "TaskDetailScroll"
	detail.position = Vector2(440, 148) # 详情区域起点
	detail.size = Vector2(770, 455) # 长篇对白独立滚动范围
	detail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(detail)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16) # 详情段落间距
	detail.add_child(_body)
	var back := Style.button(self, "返回大厅", "TaskShopBackButton", return_requested.emit)
	back.position = Vector2(60, 640) # 底部返回按钮
	if selecting:
		_main_choice = OptionButton.new()
		_side_choice = OptionButton.new()
		for index: int in 2:
			var choice: OptionButton = [_main_choice, _side_choice][index]
			choice.position = Vector2(440 + index * 290, 620) # 主支线选择并排排列
			choice.custom_minimum_size = Vector2(270, 40) # 单个任务选择框尺寸
			choice.name = "MainTaskChoice" if index == 0 else "SideTaskChoice"
			add_child(choice)
		var start := Style.button(self, "开始本局", "BeginSelectedRunButton", func(): selection_requested.emit(_choices[0][_main_choice.selected], _choices[1][_side_choice.selected]))
		start.custom_minimum_size.x = 190 # 开始按钮宽度，避免越过720p逻辑画布右边界
		start.size = start.custom_minimum_size
		start.position = Vector2(1020, 620) # 开始按钮放在选择框右侧
	refresh()


func refresh() -> void:
	_balance.text = "积分余额 %d · 已购资格可免费重试" % int(progress.profile.points)
	for child: Node in _list.get_children(): child.free()
	for task: Dictionary in TaskCatalog.visible_tasks(progress):
		var state: Dictionary = progress.profile.tasks.get(task.id, {})
		var status := "已完成" if state.get("completed", false) else ("已购·免费重试" if state.get("purchased", false) else "%d积分" % int(task.price))
		var button := Style.button(_list, "%s %s\n%s" % [task.code, task.source["名称"], status], "Task_" + task.id, show_detail.bind(task.id))
		button.custom_minimum_size.x = 320 # 任务目录统一按钮宽度
	if selecting:
		for index: int in 2:
			var choice: OptionButton = [_main_choice, _side_choice][index]
			choice.clear()
			_choices[index] = [""]
			choice.add_item("不带主线" if index == 0 else "不带支线")
			for task: Dictionary in TaskCatalog.visible_tasks(progress):
				var state: Dictionary = progress.profile.tasks.get(task.id, {})
				if task.category != ["main", "side"][index] or not state.get("purchased", false) or state.get("completed", false): continue
				_choices[index].append(task.id)
				choice.add_item(task.source["名称"])
			var selected := TaskCatalog.selected(progress, ["main", "side"][index])
			if selected.is_empty() and index == 0 and not progress.profile.tasks.tutorial.completed: selected = "tutorial"
			choice.select(maxi(0, _choices[index].find(selected)))
	if not _detail_id.is_empty(): show_detail(_detail_id)
	elif not TaskCatalog.visible_tasks(progress).is_empty(): show_detail(TaskCatalog.visible_tasks(progress)[0].id)


func _text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(label)


func show_detail(id: String) -> void:
	if not TaskCatalog.available(progress, id): return
	_detail_id = id
	for child: Node in _body.get_children(): child.free()
	var task := TaskCatalog.get_task(id)
	var source: Dictionary = task.source
	_text("%s · %s\n%s" % [task.code, source["名称"], source["任务介绍"]])
	_text("目标：%s\n永久奖励：%s\n资格价格：%d积分\n试用物资与进程：\n%s" % [source["目标"], source["永久奖励"], int(task.price), TaskCatalog.progress_text(id)])
	var state: Dictionary = progress.profile.tasks.get(id, {})
	if not state.get("purchased", false):
		var buy := Style.button(_body, "购买资格 · %d积分" % int(task.price), "PurchaseTaskButton", _confirm_purchase.bind(id))
		buy.disabled = progress.profile.points < int(task.price) or selecting
		if progress.profile.points < int(task.price): _text("积分不足；完成迷宫可获得积分。")
	elif state.get("completed", false): _text("已完成，永久奖励将在后续新局启用。")
	else: _text("已拥有资格，失败后可免费重试；在开局前选择携带。")
	if id == "tutorial" and not state.get("completed", false) and progress.profile.tutorial.skip_eligible_at_creation and not selecting:
		Style.button(_body, "整项跳过教程…", "SkipTutorialButton", _confirm_skip)


func _confirm_purchase(id: String) -> void:
	var task := TaskCatalog.get_task(id)
	var dialog := ConfirmationDialog.new()
	dialog.name = "TaskPurchaseConfirmation"
	dialog.title = "确认购买任务资格"
	dialog.dialog_text = "%s\n花费%d积分购买一次挑战资格，失败可免费重试。\n购买后请返回大厅选择任务并手动开局。" % [task.source["名称"], int(task.price)]
	dialog.ok_button_text = "确认购买"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func(): purchase_requested.emit(id); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	Style.popup_for_display(dialog, Vector2i(680, 240)) # 购买确认弹窗尺寸


func _confirm_skip() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "跳过教程"
	dialog.ok_button_text = "确认跳过"
	dialog.cancel_button_text = "返回"
	dialog.dialog_text = "本档将开放第一层与刮刀，并获得一次1000引导积分。\n跳过不算实际通关，不发正常通关分，也不进入选卡。"
	add_child(dialog)
	dialog.confirmed.connect(func(): skip_requested.emit(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	Style.popup_for_display(dialog, Vector2i(680, 230)) # 教程跳过确认尺寸
