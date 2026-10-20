extends SceneTree

## 真正读写跨机器 JSON，并通过调试器导入入口验证草稿、正式配置和错误边界。
const Profiles = preload("res://scripts/battle/battle_attack_effect_profiles.gd")
const LAB = preload("res://scenes/tools/AttackEffectLab.tscn")
const JSON_PATH := "/private/tmp/project-card-attack-transfer.json"
const CFG_PATH := "/private/tmp/project-card-attack-transfer.cfg"
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func write_document(document: Variant) -> void:
	var file := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Profiles.reload_profiles(false)
	var original := Profiles.get_profiles()
	var drafts := original.duplicate(true)
	for i: int in Profiles.PROFILE_IDS.size():
		var id: StringName = Profiles.PROFILE_IDS[i]
		drafts[id].duration = 0.3 + i * 0.1
		drafts[id].arc_height = -80 + i * 20
		drafts[id].mask_kind = Profiles.MASK_IDS[i % Profiles.MASK_IDS.size()]
	check(Profiles.export_profiles(JSON_PATH, drafts) == OK, "全部类型草稿导出JSON")
	check(Profiles.get_profiles() == original, "导出不提前应用草稿")
	var result := Profiles.read_profile_file(JSON_PATH)
	check(result.success, "导出文件可读回")
	for id: StringName in Profiles.PROFILE_IDS:
		check(result.profiles[id].mask_kind == drafts[id].mask_kind, "样式往返：" + String(id))
		for field: Dictionary in Profiles.NUMERIC_FIELDS:
			check(is_equal_approx(float(result.profiles[id][field.key]), float(drafts[id][field.key])), "参数往返：%s/%s" % [id, field.key])
	var lab := LAB.instantiate() as AttackEffectLab
	root.add_child(lab)
	await process_frame
	check(lab.find_child("ImportProfilesButton", true, false) != null and lab.find_child("ExportProfilesButton", true, false) != null, "界面提供导入导出按钮")
	lab._import_profile_file(JSON_PATH)
	check(lab._drafts == result.profiles and Profiles.get_profiles() == original, "导入仅更新全部类型草稿，保存前正式战斗保持原配置")
	check(is_equal_approx((lab._numeric_controls[&"duration"].slider as HSlider).value, drafts[lab._current_profile_id].duration), "导入后当前类型控件同步")
	lab._export_profile_file(JSON_PATH)
	check(Profiles.read_profile_file(JSON_PATH).profiles == lab._drafts, "界面导出当前草稿而非旧保存值")
	check(Profiles.save_profiles(lab._drafts, CFG_PATH) == OK and Profiles.get_profiles() == result.profiles, "保存成功才应用正式配置")
	var cfg := ConfigFile.new()
	check(cfg.load(CFG_PATH) == OK and cfg.get_sections().size() == Profiles.PROFILE_IDS.size() and is_equal_approx(float(cfg.get_value("ranged_attack", "duration")), drafts[&"ranged_attack"].duration), "正式保存文件包含全部类型")
	check(Profiles.save_profiles(original, "/private/tmp/project-card-missing-parent/config.cfg") != OK and Profiles.get_profiles() == result.profiles, "保存失败不改变运行配置")
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var invalid: Array[Dictionary] = []
	var broken := good.duplicate(true)
	broken.version = 999
	invalid.append(broken)
	broken = good.duplicate(true)
	broken.profiles.erase("water_spread")
	invalid.append(broken)
	broken = good.duplicate(true)
	broken.profiles.melee_attack.duration = "快"
	invalid.append(broken)
	broken = good.duplicate(true)
	broken.profiles.melee_attack.duration = 99
	invalid.append(broken)
	broken = good.duplicate(true)
	broken.profiles.melee_attack.mask_kind = "unknown"
	invalid.append(broken)
	broken = good.duplicate(true)
	broken.profiles.melee_attack.curve_segments = 20.5
	invalid.append(broken)
	for document: Dictionary in invalid:
		write_document(document)
		check(not Profiles.read_profile_file(JSON_PATH).success, "拒绝不完整、越界或不兼容配置")
		var before := lab._drafts.duplicate(true)
		lab._import_profile_file(JSON_PATH)
		check(lab._drafts == before and Profiles.get_profiles() == result.profiles, "导入失败保留草稿和正式配置")
	write_document([1, 2])
	check(not Profiles.read_profile_file(JSON_PATH).success, "拒绝数组代替配置对象")
	check(not Profiles.read_profile_file("/private/tmp/project-card-no-such-file.json").success, "文件不存在时提供错误")
	# 为人工复验保留一份合法文件；不触碰用户正式配置。
	Profiles.export_profiles(JSON_PATH, drafts)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		lab._import_profile_file(JSON_PATH)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-attack-transfer-preview.png") == OK, "导入导出界面截图")
		lab._open_export_dialog()
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/project-card-attack-transfer-dialog.png") == OK, "导出文件选择窗口截图")
		lab._export_dialog.hide()
	lab.queue_free()
	await process_frame
	print("攻击特效导入导出：%d条检查，%d失败" % [checks, failures])
	quit(1 if failures else 0)
