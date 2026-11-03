extends Control

## 未发现卡只创建允许的暗示节点，隐藏信息不会进入文字、提示或可检视卡面。
const CARD = preload("res://scenes/ui/CardView.tscn")
const SIZE := Vector2(99, 136) # 未发现卡与真实卡保持原生相同尺寸
const HINT_ALPHA := 0.42 # 暗示整体压暗程度
const ACTION_SECONDS := 1.6 # 多行动方式图标轮换间隔，首版可调整
var _actions: Array[CardData.ActionType] = []
var _action_index := 0
var _action: TextureRect
var _textures: Array[Texture2D] = []

func setup(card: CardData) -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	modulate = Color(HINT_ALPHA, HINT_ALPHA, HINT_ALPHA)
	var background := TextureRect.new()
	background.name = "HintBackground"
	background.texture = card.background_texture if card.background_texture != null else CardView.DEFAULT_ART_BACKGROUND_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.size = SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var frame := TextureRect.new()
	frame.name = "HintRarityFrame"
	frame.texture = load("res://assets/card_frames/card_frame_%s.png" % card.get_rarity_asset_key())
	frame.size = SIZE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	# 借用现有纹理查询，不把隐藏定义绑定到CardView，也不创建拥有实例。
	var helper := CARD.instantiate() as CardView
	var identity := helper._get_identity_texture(card)
	if identity != null:
		var icon := TextureRect.new()
		icon.name = "HintIdentity"
		icon.texture = identity
		icon.position = Vector2(49, 100) - (identity.get_size() * 0.5).floor() # 沿用卡面种族／类别图标中心
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
	if card.card_type == CardData.CardType.MINION:
		_actions.assign(card.acquisition_action_types if not card.acquisition_action_types.is_empty() else [card.action_type])
		for action: CardData.ActionType in _actions: _textures.append(helper._get_action_texture(action))
		_action = TextureRect.new()
		_action.name = "HintAction"
		_action.texture = _textures[0]
		_action.position = Vector2(-4, -4) # 行动暗示放在左上角，避开背景中心
		_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_action)
		if _actions.size() > 1:
			var timer := Timer.new()
			timer.wait_time = ACTION_SECONDS
			timer.timeout.connect(func():
				_action_index = (_action_index + 1) % _textures.size()
				_action.texture = _textures[_action_index])
			add_child(timer)
			timer.start()
	helper.free()
