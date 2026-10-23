class_name ShopCardView
extends CardView

## 商店卡面沿用 CardView 的组合；暗单仅接收公开提示生成的定义，不持有真卡内容。
const CAROUSEL_HOLD: float = 0.7 # 暗单每种图标或品级停留的秒数
const CAROUSEL_FADE: float = 0.35 # 新旧图标交叉渐变的秒数
const IDENTITY_CAROUSEL_SECONDS: float = 1.29 # 中央种族／种类图标独立轮播间隔，避开左上行动图标的1.05秒节奏
const ACTION_CAROUSEL_RECT := Rect2(-9, -9, 32, 36) # 左上图标固定透明画布，容纳全部行动、法术角标及装备箭头
const IDENTITY_CAROUSEL_SIZE := Vector2i(16, 16) # 中央种族／种类图标固定透明画布，保持原像素居中且不拉伸
const QUESTION_FONT_SIZE: int = 36 # 暗单插画区域问号的字号
const CROSSFADE_SHADER = preload("res://shaders/shop_card_crossfade.gdshader")

var _hidden_offer := false
var _public_hint: Dictionary = {}
var _carousel_index := 0
var _carousel_timer: Timer
var _identity_index := 0
var _identity_timer: Timer
var _previous_rarity: int
var _identity_from: CardData
var _rarity_progress := 1.0
var _identity_progress := 1.0
var _rarity_tween: Tween
var _identity_tween: Tween
var _identity_effect: ShaderMaterial
static var _icon_canvases: Dictionary = {}


static func public_definition(source: CardData, offer: Dictionary, frame: int = 0, identity_frame: int = -1) -> CardData:
	var result := CardData.new()
	var identity := frame if identity_frame < 0 else identity_frame
	result.display_name = "？"
	result.card_type = source.card_type
	var hint := String(offer.get("hint", ""))
	result.rarity = source.rarity if hint == "rarity" else (frame % CardData.Rarity.size()) as CardData.Rarity
	result.race_type = source.race_type if hint == "race" else (identity % int(CardData.RaceType.NONE)) as CardData.RaceType
	result.action_type = int(offer.get("resolved_action_type", source.action_type)) as CardData.ActionType if hint == "action_type" else (frame % CardData.ActionType.size()) as CardData.ActionType
	result.spell_trigger_kind = source.spell_trigger_kind if hint == "spell_trigger_kind" else (1 + frame % 3) as CardData.SpellTriggerKind
	result.spell_type = source.spell_type if hint == "spell_type" else (identity % CardData.SpellType.size()) as CardData.SpellType
	result.equipment_type = source.equipment_type if hint == "equipment_type" else (identity % CardData.EquipmentType.size()) as CardData.EquipmentType
	result.resource_type = source.resource_type if hint == "resource_type" else (identity % CardData.ResourceType.size()) as CardData.ResourceType
	result.equipment_action_delta = 1 if frame % 2 == 0 else -1
	# 不复制 id、插画、效果、符文、真实数值、成长、贴纸或槽位布局。
	return result


func configure_hidden(public_card: CardData, offer: Dictionary) -> void:
	_hidden_offer = true
	_previous_rarity = int(public_card.rarity)
	_identity_from = public_card.duplicate(true)
	_rarity_progress = 1.0
	_identity_progress = 1.0
	if is_instance_valid(_rarity_tween): _rarity_tween.kill()
	if is_instance_valid(_identity_tween): _identity_tween.kill()
	# 只保留提示种类和公开行动方式；不会保留带真实 card_id 的商品字典。
	_public_hint = {"hint": offer.get("hint", ""), "resolved_action_type": int(public_card.action_type)}
	set_card_data(public_card)
	set_owned_card(null)
	if is_node_ready():
		_start_carousel()


func _ready() -> void:
	super._ready()
	configure_drag_source(false)
	if _hidden_offer:
		_start_carousel()


func _refresh() -> void:
	super._refresh()
	if not _hidden_offer:
		return
	for number: Control in [value_label, health_label, armor_label, cooldown_label, priority_label]:
		number.visible = false
		number.tooltip_text = ""
	effect_text_label.text = ""
	effect_text_label.visible = false
	if is_instance_valid(_status_slot_layer):
		_status_slot_layer.visible = false
	art_texture.visible = false
	art_label.text = "？"
	art_label.visible = true
	art_label.add_theme_font_size_override("font_size", QUESTION_FONT_SIZE)
	art_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for icon: Control in [race_icon, action_icon, cooldown_icon, health_icon, armor_icon]:
		icon.tooltip_text = ""
	rune_row.visible = false
	_normalize_carousel_icon(action_icon, ACTION_CAROUSEL_RECT)
	_normalize_carousel_icon(race_icon, Rect2(Vector2(race_center_pixel) - Vector2(IDENTITY_CAROUSEL_SIZE) * 0.5, Vector2(IDENTITY_CAROUSEL_SIZE)))
	_update_identity_material()


func _normalize_carousel_icon(icon: TextureRect, bounds: Rect2) -> void:
	if icon.texture == null: return
	icon.texture = _icon_canvas(icon.texture, Vector2i(bounds.size))
	_set_control_rect(icon, bounds.position, bounds.size)
	icon.stretch_mode = TextureRect.STRETCH_SCALE


func _icon_canvas(source: Texture2D, canvas_size: Vector2i) -> Texture2D:
	var key := source.resource_path
	if source is AtlasTexture:
		key = source.atlas.resource_path + str(source.region)
	elif key.is_empty():
		key = str(source.get_rid())
	key += str(canvas_size)
	if not _icon_canvases.has(key):
		var image := source.get_image()
		image.convert(Image.FORMAT_RGBA8)
		var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), (canvas_size - image.get_size()) / 2)
		_icon_canvases[key] = ImageTexture.create_from_image(canvas)
	return _icon_canvases[key]


func _identity_texture(definition: CardData, rarity: int) -> Texture2D:
	var public_card: CardData = definition.duplicate(true)
	public_card.rarity = rarity as CardData.Rarity
	return _icon_canvas(_get_identity_texture(public_card), IDENTITY_CAROUSEL_SIZE)


func _update_identity_material() -> void:
	if not race_icon.visible or _identity_from == null: return
	if _identity_effect == null:
		_identity_effect = ShaderMaterial.new()
		_identity_effect.shader = CROSSFADE_SHADER
		_identity_effect.set_shader_parameter("use_rarity_blend", true)
	race_icon.material = _identity_effect
	_identity_effect.set_shader_parameter("previous_texture", _identity_texture(_identity_from, int(card_data.rarity)))
	_identity_effect.set_shader_parameter("previous_rarity_texture", _identity_texture(card_data, _previous_rarity))
	_identity_effect.set_shader_parameter("previous_rarity_previous_texture", _identity_texture(_identity_from, _previous_rarity))
	_identity_effect.set_shader_parameter("blend_amount", 0.5 - 0.5 * cos(PI * _identity_progress))
	_identity_effect.set_shader_parameter("rarity_blend_amount", 0.5 - 0.5 * cos(PI * _rarity_progress))


func _start_carousel() -> void:
	if is_instance_valid(_carousel_timer):
		return
	_carousel_timer = Timer.new()
	_carousel_timer.one_shot = true
	_carousel_timer.wait_time = CAROUSEL_HOLD + CAROUSEL_FADE
	_carousel_timer.timeout.connect(_advance_carousel)
	add_child(_carousel_timer)
	_carousel_timer.start()
	_identity_timer = Timer.new()
	_identity_timer.one_shot = true
	_identity_timer.wait_time = IDENTITY_CAROUSEL_SECONDS
	_identity_timer.timeout.connect(_advance_identity)
	add_child(_identity_timer)
	_identity_timer.start()


func _advance_carousel() -> void:
	_carousel_timer.start(CAROUSEL_HOLD + CAROUSEL_FADE)
	if not is_visible_in_tree():
		return
	_previous_rarity = int(card_data.rarity)
	_rarity_progress = 0.0
	_carousel_index += 1
	_update_carousel(false)


func _advance_identity() -> void:
	_identity_timer.start(IDENTITY_CAROUSEL_SECONDS)
	if not is_visible_in_tree(): return
	_identity_from = card_data.duplicate(true)
	_identity_progress = 0.0
	_identity_index += 1
	_update_carousel(true)


func _update_carousel(identity_changed: bool) -> void:
	var old_icons: Array[Dictionary] = []
	for icon: TextureRect in [card_frame, action_icon]:
		old_icons.append({"icon": icon, "texture": icon.texture})
	# 此时 card_data 已是脱敏定义，后续轮播只在这份公开数据上运行。
	set_card_data(public_definition(card_data, _public_hint, _carousel_index, _identity_index))
	for old: Dictionary in old_icons:
		var icon := old.icon as TextureRect
		if identity_changed:
			icon.texture = old.texture
			continue
		if icon.texture == old.texture or old.texture == null or icon.texture == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = CROSSFADE_SHADER
		material.set_shader_parameter("previous_texture", old.texture)
		icon.material = material
	_animate_channel(identity_changed)


func _set_rarity_progress(progress: float) -> void:
	_rarity_progress = progress
	var blend := 0.5 - 0.5 * cos(PI * progress)
	for icon: TextureRect in [card_frame, action_icon]:
		if icon.material == null: continue
		(icon.material as ShaderMaterial).set_shader_parameter("blend_amount", blend)
		if progress >= 1.0: icon.material = null
	if _identity_effect != null: _identity_effect.set_shader_parameter("rarity_blend_amount", blend)


func _set_identity_progress(progress: float) -> void:
	_identity_progress = progress
	if _identity_effect != null:
		_identity_effect.set_shader_parameter("blend_amount", 0.5 - 0.5 * cos(PI * progress))


func _animate_channel(identity: bool) -> void:
	var progress := _identity_progress if identity else _rarity_progress
	var old := _identity_tween if identity else _rarity_tween
	if is_instance_valid(old): old.kill()
	var fade := create_tween().set_trans(Tween.TRANS_LINEAR)
	fade.tween_method(_set_identity_progress if identity else _set_rarity_progress, progress, 1.0, CAROUSEL_FADE * (1.0 - progress))
	if identity: _identity_tween = fade
	else: _rarity_tween = fade


func continue_carousel_from(source: ShopCardView) -> void:
	# 只复制已脱敏的轮播卡面，不取商品定义或隐藏字段；避免放大起点突然换品级。
	_carousel_index = source._carousel_index
	_identity_index = source._identity_index
	_previous_rarity = source._previous_rarity
	_identity_from = source._identity_from.duplicate(true)
	_rarity_progress = source._rarity_progress
	_identity_progress = source._identity_progress
	set_card_data(source.card_data.duplicate(true))
	for pair: Array in [[card_frame, source.card_frame], [action_icon, source.action_icon]]:
		(pair[0] as TextureRect).texture = (pair[1] as TextureRect).texture
		var effect := (pair[1] as TextureRect).material
		(pair[0] as TextureRect).material = effect.duplicate() if effect != null else null
	_set_rarity_progress(_rarity_progress)
	_set_identity_progress(_identity_progress)
	_animate_channel(false)
	_animate_channel(true)
	_carousel_timer.start(maxf(source._carousel_timer.time_left, 0.001))
	_identity_timer.start(maxf(source._identity_timer.time_left, 0.001))
