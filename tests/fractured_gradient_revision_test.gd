extends SceneTree

## 独立GPU材质检查：片内连续渐变、鼠标响应及固定晶片图案。
var checks := 0
var failures := 0
var viewport: SubViewport
var material: ShaderMaterial

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else: failures += 1; push_error(message)

func shot(force: Vector2) -> Image:
	material.set_shader_parameter("force", force)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := ColorRect.new()
	canvas.size = Vector2(viewport.size)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item;\n#include "res://shaders/card_finish.gdshaderinc"\nuniform vec2 force = vec2(0.0);\nvoid fragment() { COLOR = vec4(fractured_finish(vec3(0.08), UV, force, 0.9, 7.0, 1.0, 0.55, 0.0), 1.0); }'
	material = ShaderMaterial.new()
	material.shader = shader
	canvas.material = material
	viewport.add_child(canvas)
	var a := await shot(Vector2(0.4, -0.2))
	var fixed := await shot(Vector2(0.4, -0.2))
	check(a.get_data() == fixed.get_data(), "同一鼠标方向下晶片图案与颜色保持稳定")
	var gradual := 0
	for y: int in range(4, 476, 2):
		for x: int in range(4, 636, 2):
			var left := a.get_pixel(x - 2, y)
			var center := a.get_pixel(x, y)
			var right := a.get_pixel(x + 2, y)
			var d1 := center.r - left.r
			var d2 := right.r - center.r
			if absf(d1) > 0.002 and absf(d1) < 0.025 and absf(d2) > 0.002 and absf(d2) < 0.025 and d1 * d2 > 0.0: gradual += 1
	check(gradual > 1500, "晶片内部存在连续的小幅明暗渐变：%d个连续梯度采样" % gradual)
	var moved := await shot(Vector2(-0.4, 0.2))
	check(moved.get_data() != a.get_data(), "移动鼠标改变晶片明暗")
	var directory := "/private/tmp/project-card-feedback-revision"
	DirAccess.make_dir_recursive_absolute(directory)
	a.save_png(directory.path_join("07_fractured_gradient.png"))
	moved.save_png(directory.path_join("08_fractured_pointer_moved.png"))
	viewport.free()
	print("Fractured gradient: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
