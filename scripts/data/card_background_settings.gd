@tool
class_name CardBackgroundSettings
extends Resource

## 卡牌共用背景取景；超框卡单独一组，卡牌资源可保存自己的覆盖位置。
@export var standard_offsets: Dictionary[int, Vector2i] = {} # 所有普通卡共用的各背景位置
@export var overframe_offsets: Dictionary[int, Vector2i] = {} # 所有超框卡共用的各背景位置


func get_offset(style: int, overframe: bool = false) -> Vector2i:
	if overframe and overframe_offsets.has(style):
		return overframe_offsets[style]
	return standard_offsets.get(style, Vector2i.ZERO)


func set_offset(style: int, value: Vector2i, overframe: bool = false) -> void:
	var offsets := overframe_offsets if overframe else standard_offsets
	offsets[style] = value
	emit_changed()
