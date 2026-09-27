class_name StatusSlotLayer
extends Control

## 卡牌边缘状态槽的绘制层；由CardView创建，空槽提示与已贴状态共享同一布局。

const MARKER_SIZE: Vector2 = Vector2(2, 2) # 空槽提示点的2×2逻辑像素尺寸
const MARKER_CENTER_OFFSET := Vector2(6, 6) # 14×14状态图标中心点的左上角偏移
const EMBLEM_MARKER_COLOR := Color("e7bd55") # 纹章槽提示点的金色
const WOUND_MARKER_COLOR := Color("ef82a7") # 伤势槽提示点的粉红色

var card_data: CardData
var owned_card: OwnedCard
var slot_definitions: Array[Dictionary] = []


func set_slot_source(
	definition: CardData,
	instance: OwnedCard,
	resolved_slots: Array[Dictionary]
) -> void:
	if card_data == definition and owned_card == instance and slot_definitions == resolved_slots:
		return
	card_data = definition
	owned_card = instance
	slot_definitions.assign(resolved_slots)


func _draw() -> void:
	if card_data == null or card_data.card_type != CardData.CardType.MINION:
		return
	for definition: Dictionary in slot_definitions:
		var kind := int(definition["kind"])
		var states: Array[Dictionary] = []
		if owned_card != null:
			states = owned_card.emblem_slots if kind == CardSlotLayout.Kind.EMBLEM else owned_card.wound_slots
		var storage_index := int(definition["storage_index"])
		if storage_index < states.size() and not states[storage_index].is_empty():
			continue
		var point := (definition["position"] as Vector2) + MARKER_CENTER_OFFSET
		draw_rect(Rect2(point, MARKER_SIZE), EMBLEM_MARKER_COLOR if kind == CardSlotLayout.Kind.EMBLEM else WOUND_MARKER_COLOR)
