extends SceneTree

## 在反馈保存测试之后用独立进程读回临时工艺资源，不触碰项目正式配置。
const Settings = preload("res://scripts/ui/card_finish_settings.gd")
const TUNER = preload("res://scenes/tools/CardArtTuner.tscn")
const PATH := "/private/tmp/project-card-gallery-finish-feedback/card_finish_settings.tres"
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var saved := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved != null and saved.fractured_density == 15, "独立进程从磁盘读回碎闪15")
	check(is_equal_approx(saved.holographic_strength, 0.9) and saved.embossed_density == 47, "独立进程保留同次保存与外部合并的工艺参数")
	var tuner := TUNER.instantiate() as CardArtTuner
	tuner.finish_settings_path = PATH
	root.add_child(tuner)
	await process_frame
	tuner.finish_selector.select(CardFinishPreview.Finish.FRACTURED)
	tuner.finish_selector.item_selected.emit(CardFinishPreview.Finish.FRACTURED)
	await process_frame
	check(tuner.finish_density_spin.value == 15 and not tuner._has_finish_changes() and tuner.save_finish_button.disabled, "独立进程打开工具显示15，且没有伪造未保存状态")
	check(CardFinishPreview.SETTINGS.fractured_density == 15, "项目正式卡面仍读取15")
	var owned := OwnedCard.new()
	owned.initialize(load("res://resources/cards/militia.tres"), &"settings_restore_probe", 0)
	owned.surface_finish = CardAppearance.Surface.FRACTURED
	var card := (load("res://scenes/ui/CardView.tscn") as PackedScene).instantiate() as CardView
	card.set_card_data(owned.card_data)
	card.set_owned_card(owned)
	root.add_child(card)
	var surface := InspectionCardSurface.new()
	root.add_child(surface)
	surface.setup(card, Callable(), Callable())
	var shared: Resource = CardFinishPreview.SETTINGS
	var original: Vector3 = shared.parameters(&"fractured")
	shared.set_parameters(&"fractured", Vector3(original.x, original.y, 17))
	shared.emit_changed()
	check(surface.effect.get_shader_parameter("finish_density") == 17, "全局配置变更信号立即刷新已存在的真实卡面")
	shared.set_parameters(&"fractured", original)
	shared.emit_changed()
	check(surface.effect.get_shader_parameter("finish_density") == 15, "恢复全局15同样立即生效，未写项目资源")
	surface.free()
	tuner.free()
	await process_frame
	print("Finish settings restore checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
