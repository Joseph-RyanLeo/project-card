extends SceneTree

## 从占位立绘 manifest 生成法术与装备 CardData 资源。
## 该脚本只写入 resources/cards/ 中对应的 29 个新文件，不修改已有随从资源。

const MANIFEST_PATH := "res://assets/card_art/placeholder_card_art_manifest.tsv"
const OUTPUT_ROOT := "res://resources/cards"
const EQUIPMENT_ACTION_DELTAS: Array[int] = [1, -1, 2, -2]
const EQUIPMENT_COOLDOWN_DELTAS: Array[float] = [0.5, -0.5]
const EQUIPMENT_HEALTH_DELTAS: Array[int] = [1, 2, 0, 3]
const EQUIPMENT_ARMOR_DELTAS: Array[int] = [0, 1, 2, 1]


func _init() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var manifest := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if manifest == null:
		push_error("无法打开占位卡面 manifest")
		quit(1)
		return
	manifest.get_line()
	var generated_count := 0
	var spell_count := 0
	var equipment_count := 0
	while not manifest.eof_reached():
		var columns := manifest.get_line().split("\t")
		if columns.size() < 4 or columns[0].is_empty():
			continue
		var kind := columns[0]
		var art_path := columns[1]
		if not art_path.begins_with("res://"):
			art_path = "res://" + art_path
		var display_name := columns[2]
		var subtype := columns[3]
		var art_texture := load(art_path) as Texture2D
		if art_texture == null:
			push_error("无法载入占位立绘：%s" % art_path)
			continue
		var card := CardData.new()
		card.id = StringName(art_path.get_file().get_basename())
		card.display_name = display_name
		card.card_type = (
			CardData.CardType.SPELL
			if kind == "spell"
			else CardData.CardType.EQUIPMENT
		)
		card.art_texture = art_texture
		card.art_offset = Vector2i.ZERO
		card.runes = []
		card.base_value = 0
		card.cooldown_seconds = 3.0
		card.max_health = 0
		card.armor = 0
		if kind == "spell":
			card.rarity = spell_count % CardData.Rarity.size()
			card.spell_type = _spell_type_from_name(subtype)
			card.effect_text = "占位：%s类法术，后续补充释放条件与效果。" % subtype
			spell_count += 1
		else:
			var equipment_index := equipment_count
			card.rarity = equipment_index % CardData.Rarity.size()
			card.equipment_type = _equipment_type_from_name(subtype)
			card.equipment_action_delta = EQUIPMENT_ACTION_DELTAS[
				equipment_index % EQUIPMENT_ACTION_DELTAS.size()
			]
			card.equipment_cooldown_delta = EQUIPMENT_COOLDOWN_DELTAS[
				equipment_index % EQUIPMENT_COOLDOWN_DELTAS.size()
			]
			card.equipment_health_delta = EQUIPMENT_HEALTH_DELTAS[
				equipment_index % EQUIPMENT_HEALTH_DELTAS.size()
			]
			card.equipment_armor_delta = EQUIPMENT_ARMOR_DELTAS[
				equipment_index % EQUIPMENT_ARMOR_DELTAS.size()
			]
			card.effect_text = (
				"占位：%s；行动%s%d，冷却%s%.1f秒，生命+%d，护甲+%d。"
				% [
					subtype,
					"+" if card.equipment_action_delta >= 0 else "",
					card.equipment_action_delta,
					"+" if card.equipment_cooldown_delta >= 0.0 else "",
					card.equipment_cooldown_delta,
					card.equipment_health_delta,
					card.equipment_armor_delta,
				]
			)
			equipment_count += 1
		var output_path := "%s/%s.tres" % [OUTPUT_ROOT, card.id]
		var error := ResourceSaver.save(card, output_path)
		if error != OK:
			push_error("保存占位卡牌失败：%s (%s)" % [output_path, error])
			continue
		generated_count += 1
	print("已从 manifest 生成 %d 张占位卡牌（法术 %d，装备 %d）。" % [
		generated_count,
		spell_count,
		equipment_count,
	])
	quit(0 if generated_count == 29 else 1)


func _spell_type_from_name(value: String) -> CardData.SpellType:
	return {
		"强化": CardData.SpellType.ENHANCE,
		"召唤": CardData.SpellType.SUMMON,
		"伤害": CardData.SpellType.DAMAGE,
		"支援": CardData.SpellType.SUPPORT,
		"干扰": CardData.SpellType.DISRUPTION,
	}.get(value, CardData.SpellType.ENHANCE) as CardData.SpellType


func _equipment_type_from_name(value: String) -> CardData.EquipmentType:
	return {
		"远程武器": CardData.EquipmentType.RANGED_WEAPON,
		"近战武器": CardData.EquipmentType.MELEE_WEAPON,
		"防具": CardData.EquipmentType.ARMOR,
		"饰品": CardData.EquipmentType.ACCESSORY,
		"法器": CardData.EquipmentType.FOCUS,
		"消耗品": CardData.EquipmentType.CONSUMABLE,
	}.get(value, CardData.EquipmentType.RANGED_WEAPON) as CardData.EquipmentType
