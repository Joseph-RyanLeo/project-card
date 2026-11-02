class_name BattleElementSampleVisual
extends Node2D

## 手绘序列只负责画面；外部共用弹道 Tween 负责命中、暂停、倍速与释放。
const WOOD_ATLAS: Texture2D = preload("res://assets/effects/hand_drawn/wood_pierce.png")
const DARK_ATLAS: Texture2D = preload("res://assets/effects/hand_drawn/dark_slash.png")
const WATER_ATLAS: Texture2D = preload("res://assets/effects/hand_drawn/water_shockwave.png")
const WATER_SHADER: Shader = preload("res://shaders/battle_water_shockwave.gdshader")
const WOOD_SHADER: Shader = preload("res://shaders/battle_wood_card_spacing.gdshader")
const WOOD_CELL_SIZE := Vector2(160, 450) # 每个角度保留完整纵向轨迹、两段卡牌留白及所有残影
const WOOD_ORIGINS: Array[Vector2] = [Vector2(78, 342), Vector2(53, 342), Vector2(71, 342)] # 原图下方卡牌中心在三个角度列内的位置
const WOOD_CARD_HEIGHT := 136.0 # 原图每段卡牌占用的纵向长度，不能按两排中心距整体压缩
const WOOD_REFERENCE_WIDTH := 70.0 # 调整器默认尺寸的参考值，默认保留原图像素比例
const WOOD_ROW_DISTANCE := 160.0 # 原图上下两张卡牌的中心距：136卡高＋24排间空隙
const WOOD_IMPACT_FRAME := 2.0 # 主刺穿过上方卡牌、首次在其上缘露出的原画帧号
const WOOD_FRAME_SECONDS := 0.05 # 命中后每张原帧保持50毫秒，避免完整长刺帧被压缩跳过
const DARK_CELL_SIZE := Vector2(224, 200) # 每击暗斩使用四张原画帧
const DARK_ORIGINS: Array[Vector2] = [Vector2(104, 100), Vector2(105, 75), Vector2(104, 125)] # 每击白闪的原画中心，随机转动时仍围绕目标
const WATER_CELL_SIZE := Vector2(128, 128) # 保留GIF每帧的完整透明画布和原画像素
const WATER_FRAME_COUNT := 24 # 冲击波完整帧数，含尾部水滴消散
const WATER_IMPACT_FRAME := 4 # 原画从此帧开始展开水花，对齐实际命中时刻
const WATER_FRAME_SECONDS := 0.04 # 命中后沿用原GIF的40毫秒帧时长
const WATER_BALL_RECT := Rect2(35, 58, 12, 12) # 第一帧右端的小水球，保留原球蓝白像素

var sprite: Sprite2D
var _kind: StringName
var _strike_index: int = 0
var _water_points := PackedVector2Array()
var water_ball: Sprite2D
var _water_profile := {}


func configure(kind: StringName, points: PackedVector2Array, profile: Dictionary, sequence_index: int, card_height: float = WOOD_CARD_HEIGHT) -> void:
	_kind = kind
	_strike_index = randi_range(0, 2) if kind == &"wood_thorns" else posmod(sequence_index, 3)
	sprite = Sprite2D.new()
	sprite.name = "SampleSprite"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.hframes = 4
	var width := float(profile["beam_height"])
	if kind == &"wood_thorns":
		sprite.texture = WOOD_ATLAS
		sprite.hframes = 16
		sprite.vframes = 3
		sprite.frame = _strike_index * 16
		position = points[0]
		var delta := points[-1] - points[0]
		rotation = delta.angle() + PI * 0.5
		var card_scale := card_height / WOOD_CARD_HEIGHT
		var row_distance := maxf(delta.length(), card_height)
		var extra_gap := row_distance - WOOD_ROW_DISTANCE * card_scale
		var canvas_height := WOOD_CELL_SIZE.y * card_scale + extra_gap
		sprite.scale = Vector2(width / WOOD_REFERENCE_WIDTH * card_scale, canvas_height / WOOD_CELL_SIZE.y)
		sprite.position = Vector2((WOOD_CELL_SIZE.x * 0.5 - WOOD_ORIGINS[_strike_index].x) * sprite.scale.x, canvas_height * 0.5 - WOOD_ORIGINS[_strike_index].y * card_scale - extra_gap)
		var material := ShaderMaterial.new()
		material.shader = WOOD_SHADER
		material.set_shader_parameter("card_scale", card_scale)
		material.set_shader_parameter("row_gap", row_distance - card_height)
		material.set_shader_parameter("canvas_height", canvas_height)
		sprite.material = material
	elif kind == &"water_shockwave":
		_water_profile = profile.duplicate()
		_water_points = PackedVector2Array([points[0], points[-1]])
		position = points[0]
		rotation = (points[-1] - points[0]).angle()
		sprite.texture = WATER_ATLAS
		sprite.hframes = WATER_FRAME_COUNT
		sprite.scale = Vector2.ONE * width / WATER_CELL_SIZE.x
		sprite.position = Vector2(64.0 - float(profile["water_wall_x"]), 0) * sprite.scale
		var material := ShaderMaterial.new()
		material.shader = WATER_SHADER
		material.set_shader_parameter("wall_x", float(profile["water_wall_x"]))
		material.set_shader_parameter("tail_length", float(profile["water_tail_length"]) / sprite.scale.x)
		sprite.material = material
		sprite.hide()
		water_ball = Sprite2D.new()
		water_ball.name = "WaterBall"
		water_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		water_ball.scale = Vector2.ONE * float(profile["water_ball_size"]) / WATER_BALL_RECT.size.y
		var tail := minf(WATER_BALL_RECT.position.x, float(profile["water_tail_length"]) / water_ball.scale.x)
		var ball_texture := AtlasTexture.new()
		ball_texture.atlas = WATER_ATLAS
		ball_texture.region = Rect2(WATER_BALL_RECT.position - Vector2(tail, 0), WATER_BALL_RECT.size + Vector2(tail, 0))
		water_ball.texture = ball_texture
		water_ball.position.x = -tail * water_ball.scale.x * 0.5
		add_child(water_ball)
	else:
		sprite.texture = DARK_ATLAS
		sprite.vframes = 3
		sprite.scale = Vector2.ONE * width / DARK_CELL_SIZE.x
		sprite.position = (DARK_CELL_SIZE * 0.5 - DARK_ORIGINS[_strike_index]) * sprite.scale
		position = points[-1]
		rotation = randf_range(-PI, PI)
		sprite.frame = _strike_index * 4
		sprite.hide()
	add_child(sprite)


func update_visual(progress: float, terminal_progress: float, elapsed: float, impact_delay: float) -> void:
	if _kind == &"wood_thorns":
		# 原帧自身表现跨越两张卡牌的穿刺，不再额外平移整张图或丢弃分段残影。
		var frame_progress := elapsed / maxf(impact_delay, 0.001) * WOOD_IMPACT_FRAME if elapsed < impact_delay else WOOD_IMPACT_FRAME + (elapsed - impact_delay) / WOOD_FRAME_SECONDS
		sprite.frame = _strike_index * 16 + clampi(floori(frame_progress), 0, 15)
	elif _kind == &"water_shockwave":
		var hit := elapsed >= impact_delay
		water_ball.visible = not hit
		sprite.visible = hit
		var frame_progress := float(_water_profile["water_impact_frame"]) + maxf(elapsed - impact_delay, 0.0) / WATER_FRAME_SECONDS * float(_water_profile["water_playback_speed"])
		sprite.frame = clampi(floori(frame_progress), 0, WATER_FRAME_COUNT - 1)
		var direction := (_water_points[-1] - _water_points[0]).normalized()
		var ball_end := _water_points[-1] - direction * float(_water_profile["water_ball_size"]) * 0.5
		position = _water_points[-1] if hit else _water_points[0].lerp(ball_end, clampf(progress, 0.0, 1.0))
	else:
		# 每个真实事件只展示一击：白闪→紫色斩痕→斩痕淡出。
		var phase := clampf((progress - 1.0) / maxf(terminal_progress - 1.0, 0.001), 0.0, 1.0)
		sprite.visible = progress >= 1.0 and phase < 1.0
		sprite.frame = _strike_index * 4 + mini(floori(phase * 8.0), 3)
		sprite.modulate.a = 1.0 - smoothstep(0.5, 1.0, phase)
