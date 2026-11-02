extends "res://tests/card_pack_opening_test.gd"

## 沿用正式输入与断言；每次只陈列选中的真实生成卡包，避免旧叠包坐标命中其他包。
const Appearance = preload("res://scripts/data/card_appearance.gd")

func _find_generated_pack(pack_size: String, rare: bool) -> int:
	var index := super._find_generated_pack(pack_size, rare)
	if index < 0: return index
	var offer: Dictionary = main.ordinary_shop_service.offers[index]
	main.ordinary_shop_service.offers.assign([offer])
	main._refresh_ordinary_shop_panel()
	return 0


func _finish_cards(sequence: CardPackOpening) -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main.run_save_path))
	for owned: OwnedCard in sequence.cards:
		var matched := false
		for state: Dictionary in saved.collection.cards:
			if state.instance_id == String(owned.instance_id): matched = state.surface_finish == Appearance.SURFACE_KEYS[owned.surface_finish] and state.art_finish == Appearance.ART_KEYS[owned.art_finish]
		check(matched, "实际撕包展示读取已落盘的卡面与卡图组合")
	var before_rng: int = main.ordinary_shop_service.rng.state
	await super._finish_cards(sequence)
	check(main.ordinary_shop_service.rng.state == before_rng, "逐张揭晓不重抽外观或推进玩法随机流")
