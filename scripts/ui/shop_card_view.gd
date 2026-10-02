class_name ShopCardView
extends CardView

## 商店卡面沿用 CardView 的组合；暗单仅接收公开提示生成的定义，不持有真卡内容。
const CAROUSEL_HOLD: float = 0.7 # 暗单每种图标或品级停留的秒数
const CAROUSEL_FADE: float = 0.35 # 新旧图标交叉渐变的秒数
const QUESTION_FONT_SIZE: int = 36 # 暗单插画区域问号的字号
const CROSSFADE_SHADER = preload("res://shaders/shop_card_crossfade.gdshader")

var _hidden_offer := false
var _public_hint: Dictionary = {}
var _carousel_index := 0
var _carousel_timer: Timer


static func public_definition(source: CardData, offer: Dictionary, frame: int = 0) -> CardData:
	var result := CardData.new()
	result.display_name = "？"
	result.card_type = source.card_type
	var hint := String(offer.get("hint", ""))
	result.rarity = source.rarity if hint == "rarity" else (frame % CardData.Rarity.size()) as CardData.Rarity
	result.race_type = source.race_type if hint == "race" else (frame % CardData.RaceType.size()) as CardData.RaceType
	result.action_type = int(offer.get("resolved_action_type", source.action_type)) as CardData.ActionType if hint == "action_type" else (frame % CardData.ActionType.size()) as CardData.ActionType
	result.spell_trigger_kind = source.spell_trigger_kind if hint == "spell_trigger_kind" else (1 + frame % 3) as CardData.SpellTriggerKind
	result.spell_type = source.spell_type if hint == "spell_type" else (frame % CardData.SpellType.size()) as CardData.SpellType
	result.equipment_type = source.equipment_type if hint == "equipment_type" else (frame % CardData.EquipmentType.size()) as CardData.EquipmentType
	result.resource_type = source.resource_type if hint == "resource_type" else (frame % CardData.ResourceType.size()) as CardData.ResourceType
	result.equipment_action_delta = 1 if frame % 2 == 0 else -1
	# 不复制 id、插画、效果、符文、真实数值、成长、贴纸或槽位布局。
	return result


func configure_hidden(public_card: CardData, offer: Dictionary) -> void:
	_hidden_offer = true
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


func _start_carousel() -> void:
	if is_instance_valid(_carousel_timer):
		return
	_carousel_timer = Timer.new()
	_carousel_timer.wait_time = CAROUSEL_HOLD + CAROUSEL_FADE
	_carousel_timer.timeout.connect(_advance_carousel)
	add_child(_carousel_timer)
	_carousel_timer.start()


func _advance_carousel() -> void:
	if not is_visible_in_tree():
		return
	var old_icons: Array[Dictionary] = []
	for icon: TextureRect in [card_frame, race_icon, action_icon]:
		old_icons.append({"icon": icon, "texture": icon.texture})
	_carousel_index += 1
	# 此时 card_data 已是脱敏定义，后续轮播只在这份公开数据上运行。
	set_card_data(public_definition(card_data, _public_hint, _carousel_index))
	for old: Dictionary in old_icons:
		var icon := old.icon as TextureRect
		if icon.texture == old.texture:
			continue
		var material := ShaderMaterial.new()
		material.shader = CROSSFADE_SHADER
		material.set_shader_parameter("previous_texture", old.texture)
		icon.material = material
		var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fade.tween_method(func(amount: float): material.set_shader_parameter("blend_amount", amount), 0.0, 1.0, CAROUSEL_FADE)
		fade.tween_callback(func():
			if icon.material == material:
				icon.material = null
		)


func continue_carousel_from(source: ShopCardView) -> void:
	# 只复制已脱敏的轮播卡面，不取商品定义或隐藏字段；避免放大起点突然换品级。
	_carousel_index = source._carousel_index
	set_card_data(source.card_data.duplicate(true))
	for pair: Array in [[card_frame, source.card_frame], [race_icon, source.race_icon], [action_icon, source.action_icon]]:
		(pair[0] as TextureRect).material = (pair[1] as TextureRect).material
