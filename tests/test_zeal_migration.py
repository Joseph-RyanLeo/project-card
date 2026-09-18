"""热诚文本迁移的纯单元测试，不模拟远程接口。"""
import copy
import runpy
import unittest
from pathlib import Path

M = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/migrate_zeal_tables.py"))


class ZealMigrationTest(unittest.TestCase):
    def test_percentage_keeps_other_effects(self):
        self.assertEqual(M["convert_text"]("行动冷却增加20%，数值-1，受到所有治疗行动+2。"), "热诚-4，数值-1，受到所有治疗行动+2。")
        self.assertEqual(M["convert_text"]("均衡。前排时，行动冷却缩短5%。后排数值+2。"), "均衡。前排时，热诚+1。后排数值+2。")

    def test_special_confirmed_values(self):
        self.assertEqual(M["convert_text"]("法术行动倍率翻倍，行动冷却翻倍。", "黑铁法杖"), "法术行动倍率翻倍，热诚-12。")
        self.assertEqual(M["convert_text"]("伤害降低60%，行动冷却翻倍。", "钢化术"), "伤害降低60%，热诚-10。")
        self.assertEqual(M["convert_text"]("+3数值，行动冷却×0.6，行动效果×0.6。"), "+3数值，热诚+8，行动效果×0.6。")

    def test_seconds_and_non_cooldown_percentages_untouched(self):
        text = "充能1秒，冷却6秒，伤害增加20%，恢复40%生命。"
        self.assertEqual(M["convert_text"](text), text)

    def test_rich_text_style_preserved(self):
        value = [{"type": "text", "text": "突击：", "segmentStyle": {"bold": True}}, {"type": "text", "text": "相邻友军冷却缩短20%。", "segmentStyle": {"bold": False}}]
        old = copy.deepcopy(value)
        new = M["replace_rich"](value, M["convert_text"])
        self.assertEqual(value, old)
        self.assertEqual(new[0], old[0])
        self.assertEqual(new[1]["segmentStyle"], old[1]["segmentStyle"])
        self.assertEqual(new[1]["text"], "相邻友军热诚+4。")

    def test_reject_unconfirmed_fraction(self):
        with self.assertRaises(ValueError):
            M["convert_text"]("行动冷却缩短2%。")


if __name__ == "__main__":
    unittest.main()
