extends SceneTree

## 使用运行时同一合成函数生成静态图鉴，便于逐格核对裁切与居中。

const SpellPreparationStyle = preload("res://scripts/ui/spell_preparation_icon_style.gd")
const ResourceStyle = preload("res://scripts/ui/resource_indicator_style.gd")
const SPELL_OUTPUT := "res://assets/card_ui/spells/preparation_icon_catalog.png"
const RESOURCE_OUTPUT := "res://assets/card_ui/resources/indicator_catalog.png"


func _initialize() -> void:
	var spell_catalog := Image.create_empty(3 * 42, 5 * 42, false, Image.FORMAT_RGBA8)
	spell_catalog.fill(Color.TRANSPARENT)
	for source_column: int in 3:
		for rarity_index: int in 5:
			var texture := SpellPreparationStyle.get_texture(
				source_column,
				rarity_index as CardData.Rarity
			)
			spell_catalog.blit_rect(
				texture.get_image(),
				Rect2i(0, 0, 42, 42),
				Vector2i(source_column * 42, rarity_index * 42)
			)
	var spell_result := spell_catalog.save_png(SPELL_OUTPUT)
	if spell_result != OK:
		push_error("无法保存法术准备图鉴：%s" % error_string(spell_result))
		quit(1)
		return
	var resource_catalog := Image.create_empty(5 * 35, 4 * 33, false, Image.FORMAT_RGBA8)
	resource_catalog.fill(Color.TRANSPARENT)
	for rarity_index: int in 5:
		for source_row: int in 4:
			var texture := ResourceStyle.get_texture(rarity_index as CardData.Rarity, source_row)
			resource_catalog.blit_rect(
				texture.get_image(),
				Rect2i(0, 0, 35, 33),
				Vector2i(rarity_index * 35, source_row * 33)
			)
	var resource_result := resource_catalog.save_png(RESOURCE_OUTPUT)
	if resource_result != OK:
		push_error("无法保存资源指示物图鉴：%s" % error_string(resource_result))
		quit(1)
		return
	print("法术图鉴126×210、资源图鉴175×132，均按用户原生像素裁切合成。")
	quit()
