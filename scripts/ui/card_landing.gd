extends RefCounted

## 新登场卡牌只改变视图的抬升量，原来由棋盘负责的站位始终有效。
const Dust = preload("res://scripts/ui/event_landing_dust.gd")
const DROP_HEIGHT := 48.0 # 卡牌初次登场的下落距离
const DROP_SECONDS := 0.30 # 卡牌下落到桌面的时长
const DUST_EDGE_SCALE := 1.08 # 初始烟圈略宽于卡边，再继续向四周扩散
const DUST_COLOR := Color(0.69, 0.58, 0.44, 0.82) # 加亮桌面扬尘，深色战场上仍能分辨
const DUST_IMPACT_AGE := 0.05 # 接触桌面时直接进入烟尘亮起阶段
const LANDING_META := &"board_landing_tween"

static func play(card: CardView) -> Tween:
	var previous := card.get_meta(LANDING_META, null) as Tween if card.has_meta(LANDING_META) else null
	if is_instance_valid(previous): previous.kill()
	card.set_board_landing_lift(DROP_HEIGHT)
	# 首战教学会暂停战斗时间，卡面与烟尘仍要完成进场。
	var landing := card.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	card.set_meta(LANDING_META, landing)
	landing.tween_method(card.set_board_landing_lift, DROP_HEIGHT, 0.0, DROP_SECONDS)
	landing.tween_callback(dust.bind(card))
	landing.tween_callback(card.remove_meta.bind(LANDING_META))
	return landing


static func dust(card: CardView) -> void:
	if not is_instance_valid(card) or not card.is_visible_in_tree(): return
	var effect := Dust.new()
	effect.scale = card.card_size / (Dust.PUFF_RADIUS * 2.0) * DUST_EDGE_SCALE
	effect.dust_color = DUST_COLOR
	effect.elapsed = DUST_IMPACT_AGE
	effect.position = (card.card_size - Dust.EFFECT_SIZE * effect.scale) * 0.5
	effect.process_mode = Node.PROCESS_MODE_ALWAYS
	effect.show_behind_parent = true
	card.add_child(effect)
