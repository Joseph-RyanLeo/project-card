class_name CardFaction
extends RefCounted

## 阵营的稳定数据标识。这里只定义归属与显示名，不提前实现阵营战斗效果。

enum Id {
	UNALIGNED,
	RADIANT_ALLIANCE,
	HANSA_FEDERATION,
	WILD_BEAST_NEST,
	PATHFINDER_ASSOCIATION,
	LABYRINTH,
}

const DISPLAY_NAMES := [
	"未归属",
	"辉光同盟",
	"汉萨联邦",
	"野性兽巢",
	"寻路者协会",
	"迷宫",
]


static func get_display_name(faction: Id) -> String:
	return DISPLAY_NAMES[faction]
