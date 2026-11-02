extends RefCounted

## 一般界面使用精细加粗黑体；卡面点阵字和像素数字素材各自保留。
const WEIGHT := 650.0 # 界面黑体字重，介于半粗与粗体之间
static var _font: FontVariation

static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = preload("res://assets/fonts/NotoSansSC-VF.ttf")
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): WEIGHT}
	return _font
