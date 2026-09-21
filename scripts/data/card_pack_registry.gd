class_name CardPackRegistry
extends RefCounted

## 卡包的权威归属表。卡牌可显式指定阵营；未指定时继承所属卡包。

const CardFactionScript = preload("res://scripts/data/card_faction.gd")

const PACKS := {
	&"ash_ledger": {"name": "灰烬征册", "faction": CardFactionScript.Id.RADIANT_ALLIANCE},
	&"ironwall_inscription": {"name": "铁壁铭刻", "faction": CardFactionScript.Id.RADIANT_ALLIANCE},
	&"silvermoon_chapter": {"name": "银月之章", "faction": CardFactionScript.Id.RADIANT_ALLIANCE},
	&"arcane_codex": {"name": "秘枢典籍", "faction": CardFactionScript.Id.HANSA_FEDERATION},
	&"gilded_formulae": {"name": "锻金配方", "faction": CardFactionScript.Id.HANSA_FEDERATION},
	&"thousand_sails_ledger": {"name": "千帆征册", "faction": CardFactionScript.Id.HANSA_FEDERATION},
	&"briar_oath": {"name": "荆林誓约", "faction": CardFactionScript.Id.WILD_BEAST_NEST},
	&"insect_eaten_bestiary": {"name": "虫蚀图志", "faction": CardFactionScript.Id.WILD_BEAST_NEST},
	&"beastblood_hide": {"name": "兽血之皮", "faction": CardFactionScript.Id.WILD_BEAST_NEST},
	&"labyrinth": {"name": "迷宫", "faction": CardFactionScript.Id.LABYRINTH},
}


static func get_faction(pack_id: StringName) -> CardFaction.Id:
	var pack_data := PACKS.get(pack_id, {}) as Dictionary
	return int(pack_data.get("faction", CardFactionScript.Id.UNALIGNED)) as CardFaction.Id


static func get_display_name(pack_id: StringName) -> String:
	var pack_data := PACKS.get(pack_id, {}) as Dictionary
	return str(pack_data.get("name", String(pack_id)))
