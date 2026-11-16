extends RefCounted

## 卡牌悬停与教学共用的关键词说明；仅识别正文中出现的完整词。
const DEFINITIONS := {
	"乡邻": "自身与同排左右两侧友军同种族时触发。",
	"突击": "战斗开场时触发；无特殊说明，战中入场不补触发。",
	"遗愿": "本单位被消灭时触发。",
	"耀眼": "敌方普通攻击优先选择拥有耀眼的目标。",
	"均衡": "部署在前排或后排时，使用对应的行动与效果。",
	"回响": "每次实际行动发射后触发；跳过行动不触发。",
	"热诚": "每层改变5%的行动冷却速度；正数加快、负数减慢。",
	"开采": "将指定次数的行动改为开采资源；没有资源时不消耗次数。",
}


static func in_text(text: String) -> Array[String]:
	var result: Array[String] = []
	for word: String in DEFINITIONS:
		if text.contains(word): result.append(word)
	return result
