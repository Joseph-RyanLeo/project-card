extends RefCounted

## 设置与Esc菜单共用工具清单；对局诊断和还原仍由对局菜单提供。
const ENTRIES := [
	["攻击特效调试器", "AttackEffectLabButton", &"attack_effect_lab"],
	["开包特效调整器", "PackEffectTunerButton", &"pack_effect_tuner"],
	["卡包凹凸调试", "PackReliefPreviewButton", &"pack_relief_preview"],
	["卡面调整器", "CardArtTunerButton", &"card_art_tuner"],
	["卡牌纹理调整器", "CardTextureTunerButton", &"card_texture_tuner"],
	["卡名字体调试", "CardFontLabButton", &"card_font_lab"],
	["战斗实验室", "BattleLabButton", &"battle_lab"],
	["骰子模型查看器", "DiceModelViewerButton", &"dice_model_viewer"],
]
