extends SceneTree

const Transition = preload("res://scripts/ui/screen_transition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(15.0).timeout.connect(func(): push_error("独立场景转场超时"); quit(1))
	var initial := Control.new()
	root.add_child(initial)
	current_scene = initial
	await Transition.change_scene(self, "res://scenes/tools/CardArtTuner.tscn")
	await process_frame
	if not current_scene is CardArtTuner:
		push_error("独立场景未在黑场中切换到卡面调整器")
		quit(1)
		return
	for child: Node in root.get_children():
		if child is Transition:
			push_error("独立转场遮罩没有释放")
			quit(1)
			return
	print("PASS: 独立场景更换后新场景就绪，黑场层完整释放")
	quit()
