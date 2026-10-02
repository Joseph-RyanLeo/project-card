extends SceneTree

## 在干净目录通过 --main-pack 加载真实导出包，验证素材读取和符文覆盖命中。
## 此文件用绝对路径传给 --script，不需要放入被检验的旧导出包。

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var style = load("res://scripts/ui/rune_reveal_cover_style.gd")
	if style == null:
		push_error("找不到导出包内的符文覆盖样式脚本")
		quit(1)
		return
	var texture: Texture2D = style.get_cover_texture(0)
	var image: Image = texture.get_image() if texture != null else null
	print("PACKED_TEXTURE_RESOURCE exists=", texture != null)
	if image == null:
		push_error("导入纹理资源无法提供像素数据")
		quit(1)
		return
	if image.is_compressed():
		image.decompress()
	print("PACKED_TEXTURE_IMAGE size=", image.get_size())
	var opaque_count := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0:
				opaque_count += 1
	print("PACKED_IMAGE_OPAQUE_PIXELS ", opaque_count)
	var center := Vector2i(floori(image.get_width() * 0.5), floori(image.get_height() * 0.5))
	var expected: bool = image.get_pixelv(center).a > 0
	print("PACKED_RAW_GLOBAL_PATH ", ProjectSettings.globalize_path(style.COVER_TEXTURE_PATHS[0]))
	var first: bool = style.is_cover_pixel(center)
	var second: bool = style.is_cover_pixel(center)
	print("PACKED_COVER_HIT expected=", expected, " first=", first, " second=", second)
	print("PACKED_ALPHA_CACHE_SIZE ", style._cover_alpha.size())
	# 这是公开行为回归：不透明的素材中心必须是可刮区域，连续查询结果应保持正确。
	if first != expected or second != expected:
		push_error("导出包符文覆盖命中与实际素材像素不一致")
		quit(1)
		return
	print("PACKED_RUNE_RESOURCE_PASS")
	quit()
