extends Node2D

## 已结算的事件金币共用一个绘制节点和一个多音轨播放器。
signal coin_landed(remaining: int)
signal finished
const COIN: Texture2D = preload("res://assets/ui/board_revision_20261019/gold_icon.png")
const COIN_EDGE: Texture2D = preload("res://assets/ui/currency/gold_coin_edge.jpg")
const CLINK: AudioStream = preload("res://assets/audio/ui/event_coin.mp3")
const REST_OFFSET := Vector2(89, 35) # 散布增大后把中心略往右放，给金额文字留出原有空间
const SPREAD := Vector2(45, 19) # 金币围绕金额散开的横纵范围
const REWARD_PAUSE := 0.7 # 金额文案出现后到第一枚金币飞出的停顿
const EMISSION_INTERVAL := 0.15 # 每多一枚金币，出场窗口延长的秒数
const MAX_EMISSION_WINDOW := 3.0 # 从第一枚到最后一枚离开金额文字的最长时长
const SCATTER_TIME := 0.21 # 金币从奖励位置散到桌面的时长
const HOVER_END := 0.34 # 单枚金币从文字出现，到离开桌面飞向余额栏的间隔
const FLIGHT_TIME := 0.46 # 单枚金币飞向余额栏的时长
const HOVER_HEIGHT := 24.0 # 金币展开后离桌面的浮空高度
const HOVER_BOB := 4.0 # 悬浮期间金币上下漂动的像素幅度
const HOVER_RATE := 1.75 # 悬浮期间每秒上下漂动的次数
const FLIGHT_CONTROL_POSITION := 0.45 # 弧线控制点位于起点到终点的水平比例
const FLIGHT_CONTROL_RISE := 32.0 # 弧线控制点比余额图标高出的像素数
const TURN_SPEEDS := Vector2(2.3, 3.1) # 从金额处飞出后绕竖轴翻转的每秒圈数范围
const SHADOW_RADIUS := 9.0 # 金币正面朝向镜头时的投影半宽
const SHADOW_DEPTH := 0.31 # 投影纵向为半径的比例
const SHADOW_COLOR := Color(0.15, 0.07, 0.04, 0.33) # 悬浮金币在纸面上的阴影色
const TRAIL_SAMPLE_TIME := 0.042 # 从当前时刻回看轨迹的秒数
const TRAIL_LENGTH := 34.0 # 飞得最快时拖尾也只延伸的像素数
const TRAIL_COLOR := Color("ffcf66") # 短拖尾的暖金色
const SPARK_INTERVAL := 0.064 # 飞行中每枚金币留下碎光的间隔
const SPARK_LIFETIME := 0.19 # 碎光离开飞行轨迹后继续漂移的时长
const SPARK_DRIFT := 54.0 # 飞行碎光向轨迹两侧漂散的速度
const BURST_TIME := 0.28 # 奖励从金额文字处爆开后消散的秒数
const BURST_RADIUS := 30.0 # 扩散金环的最大半径
const BURST_SPARKS := 12 # 每次爆开的碎光数，与实际奖励枚数独立
const PITCH_STEP := 0.08 # 每枚连续抵达后提高的音调倍率
const PITCH_MAX := 1.52 # 连续金币声的音调上限
const COIN_VOLUME_DB := -10.0 # 单次钱币声响度，给连续叠音留出余量

var _origin := Vector2.ZERO
var _target: Callable
var _positions := PackedVector2Array()
var _launches := PackedFloat32Array()
var _landed := 0
var _elapsed := 0.0
var _completed := false
var _audio: AudioStreamPlayer


func _ready() -> void:
	set_process(false)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func play(amount: int, origin: Vector2, target: Callable) -> void:
	_origin = origin
	_target = target
	_elapsed = -REWARD_PAUSE # 以第一枚飞出时为零点，停顿期间只显示奖励文字。
	var emission_window := minf((amount - 1) * EMISSION_INTERVAL, MAX_EMISSION_WINDOW)
	for index: int in amount:
		# 等角递进避免金币只落成一条线；表现不消耗迷宫随机数。
		var angle := index * 2.399963
		var spread := sqrt((index + 0.5) / amount)
		_positions.append(origin + REST_OFFSET + Vector2(cos(angle), sin(angle)) * SPREAD * spread)
		var fraction := float(index) / maxi(1, amount - 1)
		_launches.append(HOVER_END + emission_window * (1.0 - pow(1.0 - fraction, 1.85)))
	_audio = AudioStreamPlayer.new()
	var tracks := AudioStreamPolyphonic.new()
	tracks.polyphony = clampi(amount, 1, 64) # 短促金币音可彼此重叠
	_audio.stream = tracks
	add_child(_audio)
	_audio.play()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	while _landed < _positions.size() and _elapsed >= _launches[_landed] + FLIGHT_TIME:
		var pitch := minf(1.0 + _landed * PITCH_STEP, PITCH_MAX)
		var playback := _audio.get_stream_playback() as AudioStreamPlaybackPolyphonic
		if playback != null: playback.play_stream(CLINK, 0.0, COIN_VOLUME_DB - (pitch - 1.0) * 2.0, pitch)
		_landed += 1
		coin_landed.emit(_positions.size() - _landed)
	queue_redraw()
	if not _completed and _landed == _positions.size():
		_completed = true
		# 余额已到位，让最后的碎光和音符自然结束，再释放演出节点。
		get_tree().create_timer(maxf(SPARK_LIFETIME, CLINK.get_length())).timeout.connect(queue_free, CONNECT_ONE_SHOT)
		finished.emit()


func _draw() -> void:
	if _elapsed < 0.0 or not _target.is_valid(): return
	var destination: Vector2 = _target.call()
	for index: int in range(_landed, _positions.size()):
		var coin_age := _elapsed - _emission_time(index)
		if coin_age >= 0.0 and _elapsed < _launches[index]:
			_draw_coin_shadow(index, coin_age)
	if _elapsed < BURST_TIME: _draw_reward_burst(_elapsed / BURST_TIME)
	for index: int in _launches.size():
		var age := _elapsed - _launches[index]
		if age > 0.0 and age < FLIGHT_TIME + SPARK_LIFETIME:
			_draw_flight_sparks(index, age, destination)
	for index: int in range(_landed, _positions.size()):
		var coin_age := _elapsed - _emission_time(index)
		if coin_age < 0.0: continue
		var age := _elapsed - _launches[index]
		# 起飞后固定使用该枚金币上一阶段最后的悬浮位置，避免飞行时起点继续摆动。
		var start := _hover_position(index, minf(coin_age, HOVER_END))
		var flight := _flight_progress(age)
		var point := _flight_position(start, destination, flight)
		if age > 0.0:
			var previous := _flight_position(start, destination, _flight_progress(age - TRAIL_SAMPLE_TIME))
			_draw_trail(point, previous)
		_draw_turning_coin(point, _coin_face_width(index, coin_age))


func _emission_time(index: int) -> float:
	return _launches[index] - HOVER_END


func _shadow_width_scale(face_width: float) -> float:
	return maxf(face_width, COIN_EDGE.get_width()) / COIN.get_width()


func _draw_coin_shadow(index: int, coin_age: float) -> void:
	var scatter := _scatter_progress(coin_age)
	var ground := _origin.lerp(_positions[index], scatter)
	var width := _shadow_width_scale(_coin_face_width(index, coin_age))
	draw_set_transform(ground.round(), 0.0, Vector2(width, SHADOW_DEPTH))
	draw_circle(Vector2.ZERO, SHADOW_RADIUS, Color(SHADOW_COLOR, SHADOW_COLOR.a * scatter))
	draw_set_transform(Vector2.ZERO)


func _coin_face_width(index: int, elapsed: float) -> float:
	var turns := lerpf(TURN_SPEEDS.x, TURN_SPEEDS.y, float(index % 5) / 4.0)
	# 同一相位贯穿爆开、悬浮和收集，切换飞行阶段时不会突然回到正面。
	return roundf(COIN.get_width() * absf(cos(elapsed * TAU * turns + index * 0.3)))


func _draw_turning_coin(center: Vector2, face_width: float) -> void:
	var edge_size := COIN_EDGE.get_size()
	if face_width > edge_size.x:
		var face_size := Vector2(face_width, COIN.get_height())
		draw_texture_rect(COIN, Rect2((center - face_size * 0.5).round(), face_size), false)
		return
	# 侧图原稿是 JPG，顶底两行各跳过左右的白色背景角，保留其余原始像素。
	var at := (center - edge_size * 0.5).round()
	var body := Rect2(Vector2(0, 1), edge_size - Vector2(0, 2))
	draw_texture_rect_region(COIN_EDGE, Rect2(at + body.position, body.size), body)
	for row: float in [0.0, edge_size.y - 1.0]:
		var cap := Rect2(1.0, row, edge_size.x - 2.0, 1.0)
		draw_texture_rect_region(COIN_EDGE, Rect2(at + cap.position, cap.size), cap)


func _scatter_progress(seconds: float) -> float:
	return smoothstep(0.0, SCATTER_TIME, seconds)


func _hover_position(index: int, seconds: float) -> Vector2:
	var scatter := _scatter_progress(seconds)
	var ground := _origin.lerp(_positions[index], scatter)
	var bob := sin(TAU * HOVER_RATE * seconds + index * 0.87) * HOVER_BOB
	bob *= smoothstep(SCATTER_TIME * 0.65, HOVER_END, seconds)
	return ground - Vector2(0.0, HOVER_HEIGHT * scatter + bob)


func _flight_progress(age: float) -> float:
	var progress := clampf(age / FLIGHT_TIME, 0.0, 1.0)
	return progress * progress


func _flight_position(start: Vector2, destination: Vector2, progress: float) -> Vector2:
	var control := Vector2(lerpf(start.x, destination.x, FLIGHT_CONTROL_POSITION), minf(start.y, destination.y) - FLIGHT_CONTROL_RISE)
	# 两段线性插值再插一次，得到一条从起点上扬、末端回到图标中心的二次贝塞尔曲线。
	return start.lerp(control, progress).lerp(control.lerp(destination, progress), progress)


func _draw_flight_sparks(index: int, age: float, destination: Vector2) -> void:
	# 回算仍存活的几颗粒子，掉帧时也按时间发射，不占用迷宫随机数。
	var phase := float(index % 5) * SPARK_INTERVAL / 5.0
	var birth_age := floorf((minf(age, FLIGHT_TIME) - phase) / SPARK_INTERVAL) * SPARK_INTERVAL + phase
	var start := _hover_position(index, HOVER_END)
	while birth_age > 0.0 and age - birth_age < SPARK_LIFETIME:
		var lifetime := age - birth_age
		var alpha := 1.0 - lifetime / SPARK_LIFETIME
		var point := _flight_position(start, destination, _flight_progress(birth_age))
		var angle := birth_age * 133.0 + index * 2.4
		point += Vector2(cos(angle), sin(angle)) * (3.0 + SPARK_DRIFT * lifetime)
		var core := Color(1.0, 0.93, 0.60, alpha)
		point = point.round()
		if alpha > 0.43:
			draw_rect(Rect2(point + Vector2(-2, 0), Vector2(5, 1)), Color(TRAIL_COLOR, alpha * 0.68))
			draw_rect(Rect2(point + Vector2(0, -2), Vector2(1, 5)), Color(TRAIL_COLOR, alpha * 0.68))
		draw_rect(Rect2(point, Vector2.ONE), core)
		birth_age -= SPARK_INTERVAL


func _draw_trail(point: Vector2, previous: Vector2) -> void:
	# 在原轨迹回采上一点即可画尾迹，无需维护逐帧历史，帧率变化也不会拉长尾巴。
	var tail := (previous - point).limit_length(TRAIL_LENGTH)
	if tail.length_squared() < 1.0: return
	var near := (point + tail * 0.36).round()
	var middle := (point + tail * 0.72).round()
	draw_line(point.round(), middle, Color(0.56, 0.30, 0.08, 0.40), 3.0)
	draw_line(middle, (point + tail).round(), Color(TRAIL_COLOR, 0.22), 1.0)
	draw_line(near, middle, Color(TRAIL_COLOR, 0.45), 1.0)
	draw_line(point.round(), near, Color(TRAIL_COLOR, 0.73), 2.0)


func _draw_reward_burst(progress: float) -> void:
	var remaining := 1.0 - progress
	var spread := 1.0 - remaining * remaining * remaining
	var center := _origin.round()
	draw_arc(center, lerpf(5.0, BURST_RADIUS, spread), 0.0, TAU, 18, Color(TRAIL_COLOR, remaining * 0.76), 1.0)
	var flash := maxf(0.0, 1.0 - progress * 2.9)
	if flash > 0.0:
		var tint := Color(1.0, 0.93, 0.71, flash)
		draw_circle(center, lerpf(9.0, 4.0, flash), Color(tint, flash * 0.55))
		var size := Vector2(3.0, 15.0) * flash + Vector2.ONE * 2.0
		draw_rect(Rect2((center - size * 0.5).round(), size.round()), tint)
		size = Vector2(size.y, size.x)
		draw_rect(Rect2((center - size * 0.5).round(), size.round()), tint)
	for index: int in BURST_SPARKS:
		var angle := index * TAU / BURST_SPARKS + sin(float(index) * 5.3) * 0.13
		var radius := (BURST_RADIUS + float(index % 4) * 5.0) * spread
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		var spark_size := Vector2(2, 2) if index % 3 == 0 else Vector2.ONE
		draw_rect(Rect2(point.round(), spark_size), Color(TRAIL_COLOR.lerp(Color.WHITE, flash), remaining))
