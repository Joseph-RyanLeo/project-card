class_name BattleResourceState
extends RefCounted

## 单张资源卡在当前战斗中的独立生命状态，不属于随从阵容。

const OwnedCard = preload("res://scripts/data/owned_card.gd")

var owned_card: OwnedCard
var side: int = BattleSquadState.Side.PLAYER
var current_health: int = 0
var destroyed: bool = false
var harvested: bool = false

func initialize(card: OwnedCard, card_side: int) -> void:
	owned_card = card
	side = card_side
	current_health = card.card_data.max_health if card != null and card.card_data != null else 0
	destroyed = current_health <= 0

func apply_damage(amount: int) -> int:
	if destroyed or amount <= 0:
		return 0
	var applied := mini(amount, current_health)
	current_health -= applied
	destroyed = current_health <= 0
	return applied

func get_display_name() -> String:
	return owned_card.card_data.display_name if owned_card != null and owned_card.card_data != null else "资源"
