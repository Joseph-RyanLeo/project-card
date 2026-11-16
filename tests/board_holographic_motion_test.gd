extends SceneTree

## 真实GPU验证撤回全息战场视差，保留自动反光与法线加速。
const CARD = preload("res://scenes/ui/CardView.tscn")
const Settings = preload("res://scripts/ui/card_finish_settings.gd")
const OUTPUT := "/private/tmp/project-card-board-holo-motion"
var viewport: SubViewport
var card: CardView
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error(message)

func shot(force: Vector2) -> Image:
	card.set_process(false)
	card.update_finish_pointer(force)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func centroid(sample: Image, red_only: bool = false) -> Vector2:
	var total := Vector2.ZERO
	var count := 0.0
	for y: int in sample.get_height():
		for x: int in sample.get_width():
			var color := sample.get_pixel(x, y)
			if color.a < 0.99 or (red_only and not (color.r > 0.7 and color.g < 0.3)): continue
			total += Vector2(x, y)
			count += 1.0
	return total / maxf(1.0, count)

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var bytes := FileAccess.get_file_as_bytes(Settings.PATH)
	viewport = SubViewport.new()
	viewport.size = Vector2i(420, 550)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(3, 3))
	var data: CardData = load("res://resources/cards/militia.tres").duplicate()
	# 显眼的背景标记让GPU像素能直接测出位移，修改的是独立定义副本。
	var marker := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	marker.fill(Color(0.15, 0.2, 0.3))
	marker.fill_rect(Rect2i(34, 34, 12, 12), Color.RED)
	data.background_texture = ImageTexture.create_from_image(marker)
	var owned := OwnedCard.new()
	owned.initialize(data, &"board_holographic_probe", 0)
	owned.art_finish = CardAppearance.Art.HOLOGRAPHIC
	card = CARD.instantiate()
	card.set_card_data(data)
	card.set_owned_card(owned)
	viewport.add_child(card)
	card.position = Vector2(18, 18)
	card.configure_drag_source(false, &"board")
	var renderer = card._finish_controller
	var draft := Settings.new()
	draft.holographic_strength = 0.0
	draft.foil_shade_strength = 0.0
	renderer.settings_source = draft
	renderer.refresh()
	check(card._has_board_finish_motion() and not card._finish_surface_composited, "使用真实非合成战场卡自动光效入口")
	check(not card._finish_surface.get_shader_parameter("use_3d") and not renderer._art_material.get_shader_parameter("use_3d") and not renderer._background_material.get_shader_parameter("use_3d"), "撤回战场全息内层景深，角色和背景保持平面")
	check(renderer._art_material.get_shader_parameter("card_origin") == card.position, "恢复原有检视坐标接线")
	var shown: Dictionary = {}
	for child: Node in card.get_children():
		if child is CanvasItem and child != card.art_panel:
			shown[child] = child.visible
			child.hide()
	card.art_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.art_background.hide()
	var a := await shot(Vector2(-0.8, 0))
	var b := await shot(Vector2(0.8, 0))
	var character_shift := absf(centroid(a).x - centroid(b).x)
	check(is_zero_approx(character_shift) and a.get_data() == b.get_data(), "关闭反光后角色位置和画面保持不变")
	a.save_png(OUTPUT.path_join("character_left.png"))
	b.save_png(OUTPUT.path_join("character_right.png"))
	card.art_texture.hide()
	card.art_background.show()
	a = await shot(Vector2(-0.8, 0))
	b = await shot(Vector2(0.8, 0))
	var background_shift := absf(centroid(a, true).x - centroid(b, true).x)
	check(is_zero_approx(background_shift) and a.get_data() == b.get_data(), "关闭反光后背景位置和画面保持不变")
	a.save_png(OUTPUT.path_join("background_left.png"))
	b.save_png(OUTPUT.path_join("background_right.png"))
	for child: CanvasItem in shown: child.visible = shown[child]
	card.art_texture.show()
	draft.holographic_strength = 0.75
	draft.foil_shade_strength = 0.45
	renderer.refresh()
	card._mouse_hovered = false
	card._finish_orbit_seconds = 0.0
	card.update_finish_pointer(Vector2.ZERO)
	card._process(1.0)
	var holo_angle := card._finish_pointer_force.angle()
	check(is_equal_approx(holo_angle, TAU / 14.5), "全息与原闪卡继续按14.5秒一圈自动移动")
	owned.art_finish = CardAppearance.Art.PLAIN
	owned.surface_finish = CardAppearance.Surface.EMBOSSED
	card.set_owned_card(owned)
	card._finish_orbit_seconds = 0.0
	card.update_finish_pointer(Vector2.ZERO)
	card._process(1.0)
	var normal_angle := card._finish_pointer_force.angle()
	check(is_equal_approx(normal_angle, TAU / 12.0) and normal_angle > holo_angle, "法线闪按12秒一圈，比原速度略快")
	card.set_process(false)
	a = await shot(Vector2(-0.8, 0))
	b = await shot(Vector2(0.8, 0))
	check(a.get_data() != b.get_data(), "法线材质真实GPU光照随模拟指针变化")
	check(renderer._frame_material.get_shader_parameter("foil_enabled") and renderer._background_material.get_shader_parameter("foil_enabled") and not renderer._art_material.get_shader_parameter("foil_enabled"), "战场法线闪的白色闪纹仅在背景和外框启用")
	data.background_texture = load("res://resources/cards/militia.tres").background_texture
	owned.surface_finish = CardAppearance.Surface.PLAIN
	owned.art_finish = CardAppearance.Art.HOLOGRAPHIC
	card.set_owned_card(owned)
	a = await shot(Vector2(-0.8, 0.2))
	b = await shot(Vector2(0.8, -0.2))
	a.save_png(OUTPUT.path_join("holographic_left.png"))
	b.save_png(OUTPUT.path_join("holographic_right.png"))
	check(FileAccess.get_file_as_bytes(Settings.PATH) == bytes, "没有改写用户全局纹理配置")
	viewport.free()
	print("Board holographic motion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
