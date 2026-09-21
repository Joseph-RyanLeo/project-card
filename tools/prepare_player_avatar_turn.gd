extends SceneTree

## 将用户转身GIF的前八个不同画面做成透明图集；只清除与画布边缘连通的灰底。
## 原始不透明帧图集保存在 source/，以后可重复运行本脚本更新透明图集。

const SOURCE_PATH := "res://assets/stage_6_5/source/player_avatar_turn_raw.png"
const OUTPUT_PATH := "res://assets/stage_6_5/player_avatar_turn.png"
const FRAME_SIZE := Vector2i(180, 180) # 用户GIF每一帧的原生尺寸
const FRAME_COUNT: int = 8 # 前八帧完成转身；其余GIF帧重复停留在背面
const BACKGROUND_CHANNEL: int = 59 # GIF预览画布的#3b3b3b灰底，仅从每帧边缘连通区域清除


func _initialize() -> void:
	var sheet := Image.load_from_file(SOURCE_PATH)
	if sheet == null or sheet.get_size() != Vector2i(FRAME_SIZE.x * FRAME_COUNT, FRAME_SIZE.y):
		push_error("英雄转身原始图集必须是八帧180×180")
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	for frame_index: int in FRAME_COUNT:
		_remove_frame_background(sheet, frame_index)
	var result := sheet.save_png(OUTPUT_PATH)
	if result != OK:
		push_error("无法保存英雄转身透明图集：%s" % error_string(result))
		quit(1)
		return
	print("英雄转身透明图集已生成：8帧，每帧180×180")
	quit()


func _remove_frame_background(sheet: Image, frame_index: int) -> void:
	var visited := PackedByteArray()
	visited.resize(FRAME_SIZE.x * FRAME_SIZE.y)
	var pending: Array[Vector2i] = []
	for x: int in FRAME_SIZE.x:
		pending.append(Vector2i(x, 0))
		pending.append(Vector2i(x, FRAME_SIZE.y - 1))
	for y: int in FRAME_SIZE.y:
		pending.append(Vector2i(0, y))
		pending.append(Vector2i(FRAME_SIZE.x - 1, y))
	var cursor := 0
	while cursor < pending.size():
		var point := pending[cursor]
		cursor += 1
		if point.x < 0 or point.y < 0 or point.x >= FRAME_SIZE.x or point.y >= FRAME_SIZE.y:
			continue
		var index := point.y * FRAME_SIZE.x + point.x
		if visited[index] != 0:
			continue
		visited[index] = 1
		var sheet_point := point + Vector2i(frame_index * FRAME_SIZE.x, 0)
		var pixel := sheet.get_pixelv(sheet_point)
		if (
			pixel.r8 != BACKGROUND_CHANNEL
			or pixel.g8 != BACKGROUND_CHANNEL
			or pixel.b8 != BACKGROUND_CHANNEL
		):
			continue
		sheet.set_pixelv(sheet_point, Color.TRANSPARENT)
		pending.append(point + Vector2i.LEFT)
		pending.append(point + Vector2i.RIGHT)
		pending.append(point + Vector2i.UP)
		pending.append(point + Vector2i.DOWN)
