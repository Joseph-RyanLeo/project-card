extends SceneTree

const CoverStyle = preload("res://scripts/ui/rune_reveal_cover_style.gd")
const OwnedCardScript = preload("res://scripts/data/owned_card.gd")
const OwnedCardCollectionScript = preload("res://scripts/data/owned_card_collection.gd")
const SaveService = preload("res://scripts/data/run_save_service.gd")
const RunRewardStateScript = preload("res://scripts/data/run_reward_state.gd")
const SettlementJournalScript = preload("res://scripts/data/run_settlement_journal.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if value:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _run() -> void:
	for rarity: int in 5:
		var texture := CoverStyle.get_cover_texture(rarity)
		check(
			texture != null
			and texture.get_width() == 23
			and texture.get_height() == 23
			and texture.resource_path.ends_with("rarity_%s.png" % ["i", "ii", "iii", "iv", "v"][rarity]),
			"品级%d使用对应23×23覆盖素材" % (rarity + 1)
		)
	check(CoverStyle.is_cover_pixel(Vector2i(11, 11)), "覆盖圆心属于可刮除实际面积")
	check(not CoverStyle.is_cover_pixel(Vector2i(0, 0)), "PNG透明角落不计入擦除面积")
	check(CoverStyle.get_opaque_pixel_count() == 409, "CPU覆盖面积与23×23原图409个不透明像素一致")
	var owned := OwnedCardScript.new()
	var card_data := load("res://resources/cards/heavy_knight.tres") as CardData
	owned.initialize(card_data, &"cover_save_test", 0)
	var first := [Vector2i(11, 11), Vector2i(0, 0)] as Array[Vector2i]
	check(owned.record_rune_scrape_pixels(0, first) == 1, "擦除只记录原图不透明覆盖像素")
	check(owned.record_rune_scrape_pixels(0, [Vector2i(11, 11)]) == 0, "重复擦同一像素不会重复计数")
	var mask := CoverStyle.create_mask_image(owned.get_rune_scrape_mask_bytes(0))
	check(mask.get_pixel(11, 11).r > 0.5 and mask.get_pixel(0, 0).r < 0.5, "着色器遮罩只透明化真实擦除像素")
	var scraped: Array[Vector2i] = []
	for y: int in CoverStyle.SIZE:
		for x: int in CoverStyle.SIZE:
			if CoverStyle.is_cover_pixel(Vector2i(x, y)):
				scraped.append(Vector2i(x, y))
	var threshold := ceili(float(CoverStyle.get_opaque_pixel_count()) * CoverStyle.SCRAPE_COMPLETE_RATIO)
	check(CoverStyle.is_complete(threshold), "恰好达到70%原图覆盖像素即可通过揭晓阈值")
	check(not CoverStyle.is_complete(threshold - 1), "低于70%一个像素时不能揭晓")
	owned.rune_revealed[0] = true
	var snapshot := owned.capture_state()
	var restored := OwnedCardScript.new()
	check(restored.restore_state(snapshot), "实例快照接受有效擦除位图")
	check(
		restored.get_rune_scraped_pixel_count(0) == 1
		and restored.rune_revealed[0]
		and restored.resolved_runes == owned.resolved_runes,
		"快照保留擦除进度、揭晓状态和底层固定符文"
	)
	var encoded := SaveService.new()._encode_collection_state({"next_instance_sequence": 2, "cards": [snapshot]})
	var old_card: Dictionary = (encoded.get("cards", []) as Array)[0]
	old_card.erase("rune_scrape_masks")
	var old_decoded := SaveService.new()._decode_collection_state(
		{"next_instance_sequence": 2, "cards": [old_card]},
		{String(card_data.id): card_data},
		true,
		false,
		SaveService.SCHEMA_VERSION,
		true
	)
	var old_state: Dictionary = old_decoded.get("state", {})
	var migrated_card := OwnedCardScript.new()
	var migrated_card_state: Dictionary = (old_state.get("cards", []) as Array)[0] if not old_state.is_empty() else {}
	var migrated_card_restored := not migrated_card_state.is_empty() and migrated_card.restore_state(migrated_card_state)
	check(
		bool(old_decoded.get("success", false))
		and migrated_card_restored
		and migrated_card.rune_revealed == [true, false, false]
		and migrated_card.get_rune_scraped_pixel_count(0) == 0
		and migrated_card.resolved_runes == owned.resolved_runes,
		"旧版存档只清除免费擦痕：保留已经揭晓的槽和底层符文"
	)
	if migrated_card != null:
		migrated_card.record_rune_scrape_pixels(0, [Vector2i(11, 11)])
		migrated_card.rune_revealed[0] = true
		old_state["cards"] = [migrated_card.capture_state()]
		var checkpoint := SaveService.new().create_checkpoint(
			old_state,
			{},
			0,
			&"",
			1,
			RunRewardStateScript.new(),
			SettlementJournalScript.new(),
			0
		)
		var current_collection := OwnedCardCollectionScript.new()
		var current_reward_state := RunRewardStateScript.new()
		var current_journal := SettlementJournalScript.new()
		var current_decoded := SaveService.new().restore_checkpoint(
			checkpoint,
			current_collection,
			current_reward_state,
			current_journal,
			{String(card_data.id): card_data},
			true
		)
		var current_card: OwnedCard = current_collection.get_by_instance_id(&"cover_save_test")
		check(
			int(checkpoint.get("rune_scrape_migration_version", 0)) == SaveService.RUNE_SCRAPE_MIGRATION_VERSION
			and bool(current_decoded.get("success", false))
			and current_card != null
			and current_card.rune_revealed[0]
			and current_card.get_rune_scraped_pixel_count(0) == 1
			and current_card.resolved_runes == migrated_card.resolved_runes,
			"迁移后的新揭晓与擦痕在再次存档读取时完整保留"
		)
	print("Rune cover save failures: ", failures)
	quit(1 if failures else 0)
