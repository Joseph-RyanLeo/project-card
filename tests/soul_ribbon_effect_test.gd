extends SceneTree

## 灵魂光带：调试器配置、保存读回、命中对齐、暂停倍速与真实画布检查。
## 加 -- --capture 可在图形模式下输出预览和飞行／吸收截图到 /private/tmp。

const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const Renderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const Timing = preload("res://scripts/battle/battle_projectile_timing.gd")
const LAB = preload("res://scenes/tools/AttackEffectLab.tscn")
const SNAPSHOT := "/private/tmp/project-card-soul-ribbon-test.cfg"

var failures: int = 0
var hits: int = 0


func _init() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	root.size = Vector2i(1280, 720)
	Profiles.reload_profiles(false)
	var lab := LAB.instantiate() as AttackEffectLab
	root.add_child(lab)
	await process_frame
	await process_frame
	lab._auto_play = false
	lab._on_profile_selected(Profiles.PROFILE_IDS.find(&"magic_attack"))
	var old_profile := (lab._drafts[&"magic_attack"] as Dictionary).duplicate(true)
	# 使用非默认时长与拖尾，确认预设没有改动参与结算的参数。
	old_profile.merge({"duration": 0.91, "trail_length": 0.63, "trail_softness": 0.04, "speed_variation_strength": 0.46}, true)
	lab._drafts[&"magic_attack"] = old_profile
	var preset_button: Button
	for button: Button in lab.find_children("*", "Button", true, false):
		if button.text == "应用灵魂光带预设":
			preset_button = button
	check(preset_button != null, "调试器提供可点击的光带预设入口")
	if preset_button == null:
		quit(1)
		return
	preset_button.pressed.emit()
	await process_frame
	var profile := lab._drafts[&"magic_attack"] as Dictionary
	check(profile["mask_kind"] == &"soul_ribbon" and lab.mask_option.get_item_text(lab.mask_option.selected) == "灵魂光带", "预设选中灵魂光带样式")
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		check(is_equal_approx(Timing.calculate_impact_delay(old_profile, variant), Timing.calculate_impact_delay(profile, variant)), "变速%d的命中时刻保持一致" % variant)
	check((lab._drafts[&"melee_attack"] as Dictionary)["mask_kind"] == &"energy" and (lab._drafts[&"ranged_attack"] as Dictionary)["mask_kind"] == &"projectile", "预设只作用于当前行动，旧默认样式保留")
	var controls := lab._numeric_controls[&"soul_taper"] as Dictionary
	(controls["slider"] as HSlider).value = 1.25
	await process_frame
	var preview := lab.effect_layer.get_child(-1) as Node2D
	var material := (preview.get_node("BeamMesh") as MeshInstance2D).material as ShaderMaterial
	check(bool(material.get_shader_parameter("soul_ribbon")) and is_equal_approx(float(material.get_shader_parameter("soul_taper")), 1.25), "亮芯和收尾参数接入实际预览材质")
	# 保存到临时路径并从真实 ConfigFile 读回，不覆盖开发者的 user:// 配置。
	Profiles._profiles[&"magic_attack"] = profile.duplicate(true)
	check(Profiles.save_snapshot(SNAPSHOT) == OK, "光带配置写入临时快照")
	var config := ConfigFile.new()
	check(config.load(SNAPSHOT) == OK and config.get_value("magic_attack", "mask_kind") == "soul_ribbon" and is_equal_approx(float(config.get_value("magic_attack", "soul_taper")), 1.25), "光带样式与专用参数可以保存读回")
	var loaded := Profiles.get_default_profile(&"magic_attack")
	for key: String in config.get_section_keys("magic_attack"):
		loaded[key] = config.get_value("magic_attack", key)
	profile = Profiles.normalize_profile(&"magic_attack", loaded)
	check(Profiles.get_profile(&"magic_attack") == profile, "正式战斗的共用入口读取相同光带配置")
	var points := PackedVector2Array([Vector2(60, 170), Vector2(360, 80)])
	profile["end_padding"] = 64.0
	var sampled := Renderer.sample_curve(points, profile)
	check(sampled[0] == points[0] and sampled[-1] == points[-1], "光带始终从攻击方到目标中心，不越过吸收点")
	for child: Node in lab.effect_layer.get_children():
		child.queue_free()
	await process_frame
	for variant: int in Timing.TRAVEL_SPEED_VARIANT_COUNT:
		hits = 0
		var delay := Timing.calculate_impact_delay(profile, variant)
		var effect := Renderer.play(lab.effect_layer, points, profile, Color.WHITE, Color.CYAN, func() -> void: hits += 1, 1.0, variant, delay)
		var tween := effect.get_meta("flight_tween") as Tween
		Renderer.set_flight_paused(effect, true)
		await process_frame
		material = (effect.get_node("BeamMesh") as MeshInstance2D).material as ShaderMaterial
		check(is_zero_approx(float(material.get_shader_parameter("travel_progress"))) and hits == 0, "暂停不推进光带或提前触发命中")
		Renderer.set_flight_speed(effect, 3.0)
		tween.custom_step(0.01)
		var expected_progress := Timing.remap_travel_progress(0.03 / float(profile["duration"]), variant, float(profile["speed_variation_strength"])) * (1.0 + float(profile["trail_length"]) + float(profile["trail_softness"]))
		check(is_equal_approx(float(material.get_shader_parameter("travel_progress")), expected_progress), "光带三倍速实际推进三倍距离时间")
		Renderer.set_flight_speed(effect, 1.0)
		tween.custom_step(delay - 0.03 - 0.001)
		check(hits == 0, "逻辑命中前不触发光带回调")
		tween.custom_step(0.002)
		check(hits == 1 and absf(float(material.get_shader_parameter("travel_progress")) - 1.0) < 0.02, "变速%d在逻辑命中时刻抵达目标且仅命中一次" % variant)
		tween.custom_step((float(profile["duration"]) - delay) * 0.5)
		check(hits == 1 and float(material.get_shader_parameter("travel_progress")) > 1.0 and not effect.is_queued_for_deletion(), "命中后继续吸收尾迹，不重复结算")
		tween.custom_step(float(profile["duration"]))
		await process_frame
		check(not is_instance_valid(effect) and hits == 1, "播放结束完整清理光带节点")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await capture_preview(lab)
	lab.queue_free()
	await process_frame
	Profiles.reload_profiles(false)
	print("Soul ribbon failures: %d" % failures)
	quit(1 if failures else 0)


func capture_preview(lab: AttackEffectLab) -> void:
	lab._drafts[&"magic_attack"] = Profiles.make_soul_ribbon_profile(&"magic_attack", Profiles.get_default_profile(&"magic_attack"))
	lab._load_profile_into_controls(&"magic_attack")
	lab.head_color_option.select(0)
	lab.tail_color_option.select(4)
	lab._play_preview(true)
	await process_frame
	var effect := lab.effect_layer.get_child(-1) as Node2D
	var tween := effect.get_meta("flight_tween") as Tween
	tween.pause()
	var material := (effect.get_node("BeamMesh") as MeshInstance2D).material as ShaderMaterial
	for progress: float in [0.45, 0.85, 1.15, 1.40, 1.535]:
		material.set_shader_parameter("travel_progress", progress)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "/private/tmp/project-card-soul-ribbon-%.2f.png" % progress
		check(root.get_texture().get_image().save_png(path) == OK, "输出真实画布：%s" % path)


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
