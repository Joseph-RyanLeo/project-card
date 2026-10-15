class_name EmblemFusionRecipes
extends RefCounted

## 配方使用稳定编号保存发现；同结果的不同配方互不揭晓。
const RECIPES: Array[Dictionary] = [
	{"id": "clover_2", "a": &"四叶草Ⅰ", "b": &"四叶草Ⅰ", "result": &"四叶草Ⅱ", "rank": 2},
	{"id": "clover_3", "a": &"四叶草Ⅱ", "b": &"四叶草Ⅰ", "result": &"四叶草Ⅲ", "rank": 3},
	{"id": "shield_2", "a": &"盾牌Ⅰ", "b": &"盾牌Ⅰ", "result": &"盾牌Ⅱ", "rank": 2},
	{"id": "shield_3", "a": &"盾牌Ⅱ", "b": &"盾牌Ⅰ", "result": &"盾牌Ⅲ", "rank": 3},
	{"id": "ham_bread", "a": &"面包", "b": &"火腿", "result": &"火腿面包"},
	{"id": "apple_pie", "a": &"面包", "b": &"苹果", "result": &"苹果派"},
	{"id": "toast", "a": &"火把", "b": &"面包", "result": &"烤面包"},
	{"id": "roast_ham", "a": &"火把", "b": &"火腿", "result": &"烤火腿"},
	{"id": "roast_apple", "a": &"火把", "b": &"苹果", "result": &"烤苹果"},
	{"id": "spiked_shield", "a": &"长剑", "b": &"盾牌Ⅰ", "result": &"刺盾"},
	{"id": "flame_sword", "a": &"长剑", "b": &"火把", "result": &"火焰剑"},
	{"id": "coin_bag", "a": &"金币", "b": &"金币", "result": &"金币袋"},
	{"id": "treasure", "a": &"金币袋", "b": &"宝石", "result": &"宝藏"},
	{"id": "famous_sword", "a": &"长剑", "b": &"宝石", "result": &"名剑"},
	{"id": "feather_2", "a": &"羽毛Ⅰ", "b": &"羽毛Ⅰ", "result": &"羽毛Ⅱ", "rank": 2},
	{"id": "cheese_bread", "a": &"奶酪", "b": &"面包", "result": &"奶酪面包"},
	{"id": "sandwich_cheese", "a": &"奶酪面包", "b": &"火腿", "result": &"三明治"},
	{"id": "sandwich_ham", "a": &"火腿面包", "b": &"奶酪", "result": &"三明治"},
	{"id": "gold_apple", "a": &"金币", "b": &"苹果", "result": &"金苹果"},
]
const SERIES: Array[Array] = [
	[&"四叶草Ⅰ", &"四叶草Ⅱ", &"四叶草Ⅲ"],
	[&"盾牌Ⅰ", &"盾牌Ⅱ", &"盾牌Ⅲ"],
	[&"羽毛Ⅰ", &"羽毛Ⅱ"],
]

static func resolve(first: StringName, second: StringName) -> Dictionary:
	var best: Dictionary = {}
	for recipe: Dictionary in RECIPES:
		if (_matches(first, recipe.a) and _matches(second, recipe.b)) or (_matches(first, recipe.b) and _matches(second, recipe.a)):
			if best.is_empty() or int(recipe.get("rank", 1)) > int(best.get("rank", 1)):
				best = recipe
	return best.duplicate(true)

static func _matches(actual: StringName, required: StringName) -> bool:
	if actual == required:
		return true
	for series: Array in SERIES:
		var required_index := series.find(required)
		if required_index >= 0:
			return series.find(actual) >= required_index
	return false
