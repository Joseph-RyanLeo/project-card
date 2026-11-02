extends SceneTree

## 攻击特效调试器：配置完整性、实时预览、Shader 参数与持久化检查。

const BattleAttackEffectProfiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const BattleAttackTrailRenderer = preload("res://scripts/battle/battle_attack_trail_renderer.gd")
const LAB_SCENE: PackedScene = preload("res://scenes/tools/AttackEffectLab.tscn")
const SNAPSHOT_PATH := "/private/tmp/project-card-attack-effect-lab-test.cfg"

var _failure_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	BattleAttackEffectProfiles.reload_profiles(false)
	_expect(
		BattleAttackEffectProfiles.MASK_IDS == [&"soul_ribbon", &"water_flow", &"wood_thorns", &"dark_slash", &"water_shockwave"]
		and not FileAccess.file_exists("res://assets/effects/battle_trail_energy.png")
		and not FileAccess.file_exists("res://assets/effects/battle_trail_projectile.png"),
		"两种旧尾迹的样式入口和素材已删除"
	)
	for profile_id: StringName in BattleAttackEffectProfiles.PROFILE_IDS:
		var defaults := BattleAttackEffectProfiles.get_default_profile(profile_id)
		for removed_style: StringName in [&"energy", &"projectile"]:
			var old_profile := defaults.duplicate(true)
			old_profile["mask_kind"] = removed_style
			old_profile["duration"] = 0.91
			var normalized := BattleAttackEffectProfiles.normalize_profile(profile_id, old_profile)
			_expect(normalized["mask_kind"] == defaults["mask_kind"] and is_equal_approx(float(normalized["duration"]), 0.91), "旧本机样式恢复行动默认值并保留时长：%s/%s" % [profile_id, removed_style])
	var lab := LAB_SCENE.instantiate() as AttackEffectLab
	root.add_child(lab)
	await process_frame
	await process_frame
	_expect(
		lab.profile_option.item_count == BattleAttackEffectProfiles.PROFILE_IDS.size()
		and lab.mask_option.item_count == BattleAttackEffectProfiles.MASK_IDS.size()
		and lab._numeric_controls.size() == BattleAttackEffectProfiles.NUMERIC_FIELDS.size(),
		"页面展示全部攻击类型、特效样式和全部数值参数"
	)
	_expect(
		lab.effect_layer.get_child_count() > 0,
		"打开页面后无需点击即可播放实时预览"
	)
	var warp_controls := lab._numeric_controls[&"warp_strength"] as Dictionary
	var warp_slider := warp_controls["slider"] as HSlider
	warp_slider.value = 0.275
	await process_frame
	var current_profile := lab._drafts[lab._current_profile_id] as Dictionary
	var newest_effect := lab.effect_layer.get_child(lab.effect_layer.get_child_count() - 1) as Node2D
	var beam_mesh := newest_effect.get_node("BeamMesh") as MeshInstance2D
	var material := beam_mesh.material as ShaderMaterial
	_expect(
		is_equal_approx(float(current_profile["warp_strength"]), 0.275)
		and current_profile.has("speed_variation_strength")
		and is_equal_approx(float(material.get_shader_parameter("warp_strength")), 0.275)
		and is_equal_approx(float(material.get_shader_parameter("edge_threshold")), float(current_profile["edge_threshold"]))
		and is_equal_approx(float(material.get_shader_parameter("edge_softness")), float(current_profile["edge_softness"]))
		and not bool(material.get_shader_parameter("water_flow")),
		"拖动参数后草稿与屏幕上的 Shader 同帧更新"
	)
	lab._on_mask_selected(1)
	await process_frame
	newest_effect = lab.effect_layer.get_child(lab.effect_layer.get_child_count() - 1) as Node2D
	beam_mesh = newest_effect.get_node("BeamMesh") as MeshInstance2D
	material = beam_mesh.material as ShaderMaterial
	_expect(
		bool(material.get_shader_parameter("water_flow"))
		and lab.mask_option.get_item_text(1) == "像素水流",
		"切换现存样式立即使用程序水流预览"
	)
	var save_error := BattleAttackEffectProfiles.save_snapshot(SNAPSHOT_PATH)
	var saved_config := ConfigFile.new()
	var load_error := saved_config.load(SNAPSHOT_PATH)
	_expect(
		save_error == OK
		and load_error == OK
		and saved_config.has_section(String(BattleAttackEffectProfiles.PROFILE_IDS[0]))
		and saved_config.has_section_key(String(BattleAttackEffectProfiles.PROFILE_IDS[0]), "warp_strength")
		and saved_config.has_section_key(
			String(BattleAttackEffectProfiles.PROFILE_IDS[0]),
			"speed_variation_strength"
		),
		"统一配置可以写入并重新读取 ConfigFile"
	)
	lab.queue_free()
	await process_frame
	if _failure_count == 0:
		print("Attack effect lab checks passed.")
	else:
		push_error("Attack effect lab checks failed: %d" % _failure_count)
	quit(_failure_count)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
		return
	_failure_count += 1
	push_error("FAIL: %s" % description)
